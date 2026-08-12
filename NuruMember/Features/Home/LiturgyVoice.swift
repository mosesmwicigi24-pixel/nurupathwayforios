// Liturgy voice — give the daily liturgy a VOICE (owner ask, final piece of
// the four-part liturgy upgrade). On-device speech only: AVSpeechSynthesizer,
// never a cloud TTS service — zero cost for a 76-member church on a real
// budget, works offline, no API key to leak, no member audio ever leaves the
// device. There is no TTS anywhere else in this stack; this is the first.
//
// Pure logic (text shaping, the state machine, voice selection) lives in
// LiturgyVoiceLogic.swift and is unit-tested there without any AV dependency.
// This file is the thin AVFoundation-backed engine that drives it:
//   - Never auto-plays — every `toggle(_:)` call originates from a member's
//     tap on HomeLiturgyCard's listen control. A devotional app that starts
//     talking unbidden is an intrusion, worse at 5am than any other hour.
//   - Reuses ChatVoice.swift's `VoiceAudioSession` (the SAME hold-counted
//     session helper chat voice notes already use) instead of hand-rolling
//     AVAudioSession calls — it already knows never to deactivate the
//     session out from under a playing Radio station.
//   - DUCKS Nuru Radio (RadioCenter.duck()/unduck()) rather than silently
//     interrupting it — worship music playing through the app-wide station
//     drops to a whisper for the reading, then returns to full volume.
//   - DECLINES rather than speaks (with a reason the card surfaces) when:
//     the member is currently broadcasting on Nuru Live — WebRTC holds the
//     session's `.playAndRecord` category exclusively, and synthesizing
//     speech over that would either fail outright or bleed into the
//     outgoing stream; or VoiceOver is running — starting a SECOND spoken
//     voice on top of VoiceOver's own is exactly the "two voices at once"
//     problem accessibility review flags, so we defer to VoiceOver instead.
//   - Handles a phone-call interruption by pausing (not stopping) — iOS
//     hands back `.shouldResume` when the call ends and playback picks up
//     from the same word, mirroring RadioCenter/ChatVoicePlayer.
//   - PHASE 2 seam: `LiturgyAudioSource.recorded(URL)` already has a real
//     playback path here (`playRecorded`), sharing the exact same session/
//     duck/interruption/state-machine plumbing as synthesis. Nothing calls
//     it today — HomeLiturgy has no recorded-audio field yet — but the day
//     the backend adds one, only the call site in LiturgyCards.swift needs
//     to change (pass the URL instead of `nil`); this engine needs no
//     rewrite.
import AVFoundation
import Combine
import UIKit

@MainActor
final class LiturgyVoiceEngine: NSObject, ObservableObject {
    @Published private(set) var state: LiturgyVoiceState = .idle
    /// Set (briefly) when a listen request was DECLINED rather than silently
    /// dropped — the card surfaces this as a small message, never nothing.
    /// Public var (not private(set)): the card clears it once its toast
    /// auto-dismisses.
    @Published var declineReason: String?

    private let synthesizer = AVSpeechSynthesizer()
    private var pendingUtteranceCount = 0
    private var pendingSource: LiturgyAudioSource?

    private var recordedPlayer: AVPlayer?
    private var recordedEndObserver: NSObjectProtocol?

    private var interruptionObserver: NSObjectProtocol?
    private var broadcastObserver: AnyCancellable?
    private var holdsSession = false
    private var duckedRadio = false

    override init() {
        super.init()
        synthesizer.delegate = self
        observeInterruptions()
        // If the member starts broadcasting WHILE we're mid-reading (island-
        // minimized broadcast start from another tab is the realistic path —
        // Home stays mounted underneath, see RootView's tab ZStack), yield
        // immediately rather than let WebRTC and AVSpeechSynthesizer fight
        // over the session.
        broadcastObserver = BroadcastCenter.shared.$controller
            .dropFirst()
            .sink { [weak self] controller in
                guard let self, controller != nil, self.state != .idle else { return }
                self.stop()
            }
    }

    deinit {
        if let interruptionObserver {
            NotificationCenter.default.removeObserver(interruptionObserver)
        }
    }

    // MARK: - Transport

    /// Tap-to-toggle: idle → start speaking; playing → pause; paused → resume.
    /// Never called automatically — every call originates from the member's
    /// own tap on the listen control.
    func toggle(_ source: LiturgyAudioSource) {
        switch state {
        case .idle: start(source)
        case .playing: performPause()
        case .paused: performResume()
        }
    }

    /// Stop cleanly, from anywhere: navigating away, backgrounding, the
    /// screen disappearing, a fresh liturgy replacing the one being read, or
    /// this engine being torn down. Safe to call from `.idle` (no-op).
    func stop() {
        guard state != .idle else { return }
        synthesizer.stopSpeaking(at: .immediate)
        recordedPlayer?.pause()
        teardownRecorded()
        finish()
    }

    private func start(_ source: LiturgyAudioSource) {
        let next = state.applying(.start)
        guard next != state else { return }
        declineReason = nil

        // Never produce two spoken voices at once — VoiceOver already reads
        // this screen when the member swipes to it.
        guard !UIAccessibility.isVoiceOverRunning else {
            declineReason = "VoiceOver is already reading this screen — turn it off to hear the liturgy voice instead."
            return
        }
        // A live broadcast owns the session's recording claim exclusively —
        // decline rather than risk bleeding synthesized speech into it.
        guard BroadcastCenter.shared.controller == nil else {
            declineReason = "You're live right now — the liturgy voice will wait until your broadcast ends."
            return
        }
        do {
            try VoiceAudioSession.activate(.playback, mode: .spokenAudio, options: [.duckOthers])
            holdsSession = true
        } catch {
            declineReason = "Couldn't start the liturgy voice just now — please try again in a moment."
            return
        }

        // Duck Nuru Radio rather than talk over worship music unannounced.
        RadioCenter.shared.duck()
        duckedRadio = true

        pendingSource = source
        switch source {
        case .synthesized(let segments): speakAll(segments)
        case .recorded(let url): playRecorded(url)
        }
        state = next
    }

    private func performPause() {
        let next = state.applying(.pause)
        guard next != state else { return }
        pauseUnderlying()
        state = next
        // Let worship breathe at full volume again while we're silent.
        if duckedRadio { RadioCenter.shared.unduck(); duckedRadio = false }
    }

    private func performResume() {
        let next = state.applying(.resume)
        guard next != state else { return }
        resumeUnderlying()
        RadioCenter.shared.duck()
        duckedRadio = true
        state = next
    }

    private func pauseUnderlying() {
        switch pendingSource {
        case .synthesized: if synthesizer.isSpeaking { synthesizer.pauseSpeaking(at: .word) }
        case .recorded: recordedPlayer?.pause()
        case nil: break
        }
    }

    private func resumeUnderlying() {
        switch pendingSource {
        case .synthesized: if synthesizer.isPaused { synthesizer.continueSpeaking() }
        case .recorded: recordedPlayer?.play()
        case nil: break
        }
    }

    /// The one place playback ends, for ANY reason (natural finish, explicit
    /// stop, a cancel from the delegate). Idempotent — safe to call more
    /// than once for the same session.
    private func finish() {
        state = .idle
        pendingSource = nil
        pendingUtteranceCount = 0
        if duckedRadio { RadioCenter.shared.unduck(); duckedRadio = false }
        if holdsSession { holdsSession = false; VoiceAudioSession.release() }
    }

    // MARK: - Synthesis

    private func speakAll(_ segments: [LiturgySpeechSegment]) {
        pendingUtteranceCount = segments.count
        guard pendingUtteranceCount > 0 else { finish(); return }
        let voice = Self.cachedVoice
        for segment in segments {
            let utterance = AVSpeechUtterance(string: segment.text)
            utterance.voice = voice
            // Unhurried, like a person praying — noticeably slower than the
            // default clip, with a touch less brightness than the default
            // pitch. Rate/pitch are the two knobs AVSpeechUtterance exposes;
            // this pairing is what keeps it from reading like a GPS voice.
            utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.86
            utterance.pitchMultiplier = 0.96
            utterance.postUtteranceDelay = segment.pauseAfter
            synthesizer.speak(utterance)
        }
    }

    /// Resolved once per app run — `AVSpeechSynthesisVoice.speechVoices()` is
    /// a real device query, so this lives here (not in LiturgyVoiceLogic.swift)
    /// while the actual RANKING rule (LiturgyVoiceSelector.choose) stays pure
    /// and unit-tested. `nil` (no English voice at all) leaves AVSpeechUtterance
    /// on the system default, which is still graceful.
    private static let cachedVoice: AVSpeechSynthesisVoice? = {
        let candidates = AVSpeechSynthesisVoice.speechVoices().map {
            LiturgyVoiceCandidate(identifier: $0.identifier, language: $0.language,
                                   isEnhancedOrPremium: $0.quality == .enhanced || $0.quality == .premium)
        }
        guard let chosen = LiturgyVoiceSelector.choose(from: candidates) else { return nil }
        return AVSpeechSynthesisVoice(identifier: chosen.identifier)
    }()

    // MARK: - Recorded (PHASE 2 seam — no caller today, see file header)

    private func playRecorded(_ url: URL) {
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        recordedPlayer = player
        recordedEndObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish() }
        }
        player.play()
    }

    private func teardownRecorded() {
        if let recordedEndObserver { NotificationCenter.default.removeObserver(recordedEndObserver) }
        recordedEndObserver = nil
        recordedPlayer = nil
    }

    // MARK: - Interruptions (a phone call) — pause, then resume only if iOS says we may.

    private func observeInterruptions() {
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            Task { @MainActor [weak self] in
                guard let self, self.state != .idle else { return }
                switch type {
                case .began: self.performPause()
                case .ended where options.contains(.shouldResume): self.performResume()
                default: break
                }
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension LiturgyVoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.pendingUtteranceCount -= 1
            if self.pendingUtteranceCount <= 0 { self.finish() }
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.finish() }
    }
}
