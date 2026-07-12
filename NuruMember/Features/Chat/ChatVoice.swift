// Chat voice messages — Android parity (ChatThreadScreen.kt's VoiceRecorder/
// VoicePlayer/WaveformBars, ported).
//   • ChatVoiceRecorder — AVAudioRecorder (AAC m4a, mono) with a 10 Hz meter
//     sampler feeding `levels` (0–100) for the live wave; waveformFor() bucket-
//     averages down to the server cap (64 of max 80 ints). The 5-minute cap and
//     system interruptions FINALIZE the take (`finishedFile`) — they never
//     discard it.
//   • ChatVoicePlayer  — one-at-a-time remote playback with progress, so the
//     played fraction can highlight the shared waveform. Stops on the item's
//     real end, not a metadata estimate.
//   • LiveWaveView / WaveformBars — the composer's live wave and the bubble's
//     static-with-fill wave.
//   • VoiceMessageBubble — a real, playable voice message (replaces the old
//     inert "Voice note" pill).
import SwiftUI
import AVFoundation

// MARK: - Audio session bookkeeping

/// One hold per active voice recorder/player; the shared AVAudioSession is
/// released (with .notifyOthersOnDeactivation, so the member's Music/podcast
/// resumes) only when the LAST hold is gone — and never out from under the
/// radio, which manages its own lifecycle (RadioCenter.stop() deactivates).
@MainActor
enum VoiceAudioSession {
    private static var holds = 0

    static func activate(_ category: AVAudioSession.Category,
                         mode: AVAudioSession.Mode,
                         options: AVAudioSession.CategoryOptions = []) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(category, mode: mode, options: options)
        try session.setActive(true)
        holds += 1
    }

    static func release() {
        holds = max(0, holds - 1)
        guard holds == 0, !RadioCenter.shared.playing else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - Recorder

@MainActor
final class ChatVoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var elapsedSec = 0
    @Published var levels: [Int] = []   // 0..100, one per 100 ms
    /// Set when the take ends WITHOUT the member tapping send — the 5-minute
    /// cap or a system interruption (call/Siri). The file is finished and
    /// ready to send, so the composer strip stays up instead of vanishing.
    @Published var finishedFile: URL?
    /// Pulsed true when the mic permission is refused, so the composer can
    /// show a brief "Allow microphone in Settings" hint instead of nothing.
    @Published var denied = false

    private var recorder: AVAudioRecorder?
    private var meter: Timer?
    private var interruptionObserver: NSObjectProtocol?
    private var holdsSession = false
    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nuru-chat-voice.m4a")
    }

    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.denied = true; return }
                self.begin()
            }
        }
    }

    private func begin() {
        // A playing voice note must never bleed into the mic — .playAndRecord
        // + defaultToSpeaker would record it straight into the new message.
        ChatVoicePlayer.threadShared.stop()
        do {
            try VoiceAudioSession.activate(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            holdsSession = true
            try? FileManager.default.removeItem(at: fileURL)
            let r = try AVAudioRecorder(url: fileURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            r.isMeteringEnabled = true
            guard r.record() else {   // session refused (active call etc.)
                releaseSession()
                return
            }
            recorder = r
            levels = []
            elapsedSec = 0
            finishedFile = nil
            isRecording = true
            observeInterruptions()
            meter?.invalidate()
            let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let r = self.recorder, self.isRecording else { return }
                    r.updateMeters()
                    // dBFS (−160…0) → 0..100, matching Android's normalisation.
                    let db = r.averagePower(forChannel: 0)
                    let level = Int((max(0, min(1, (db + 50) / 50)) * 100).rounded())
                    self.levels.append(level)
                    if self.levels.count > 600 { self.levels.removeFirst() }
                    // The recorder's own clock, never tick counts — timers
                    // starve in the tracking run-loop mode and through
                    // interruptions while the hardware keeps rolling.
                    self.elapsedSec = Int(r.currentTime)
                    if self.elapsedSec >= 300 { self.finish() } // server caps 5 min
                }
            }
            RunLoop.main.add(t, forMode: .common)   // keep ticking mid-scroll
            meter = t
        } catch {
            isRecording = false
            releaseSession()
        }
    }

    /// A call/Siri stops the hardware; finalize what we captured so the clock
    /// can't keep counting silence into the sent duration.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            Task { @MainActor [weak self] in
                guard let self, began, self.isRecording else { return }
                self.finish()
            }
        }
    }

    /// The take ended without a send tap (5-min cap / interruption): keep it.
    /// `finishedFile` keeps the composer strip alive in a ready-to-send state.
    private func finish() {
        guard isRecording else { return }
        finishedFile = endCapture()
    }

    /// Stop the hardware; the real duration comes from the recorder's clock.
    private func endCapture() -> URL? {
        meter?.invalidate(); meter = nil
        if let o = interruptionObserver {
            NotificationCenter.default.removeObserver(o)
            interruptionObserver = nil
        }
        if let r = recorder {
            elapsedSec = Int(r.currentTime.rounded())
            r.stop()
        }
        recorder = nil
        isRecording = false
        releaseSession()
        return elapsedSec >= 1 ? fileURL : nil
    }

    /// Stop and return the recorded file (nil if too short to mean anything).
    /// Also the hand-off after an autostop — the finished take returns as-is,
    /// and it stays on disk until discardFile() or cancel().
    func stop() -> URL? {
        if isRecording { _ = endCapture() }
        finishedFile = nil
        return elapsedSec >= 1 ? fileURL : nil
    }

    func cancel() {
        if isRecording { _ = endCapture() }
        meter?.invalidate(); meter = nil
        finishedFile = nil
        elapsedSec = 0
        levels = []
        try? FileManager.default.removeItem(at: fileURL)
        releaseSession()
    }

    /// The upload landed — the tmp copy is no longer the only copy.
    func discardFile() {
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func releaseSession() {
        guard holdsSession else { return }
        holdsSession = false
        VoiceAudioSession.release()
    }

    /// Bucket-average the live samples down to `bars` ints 0..100 (server cap 80).
    func waveformFor(_ bars: Int = 64) -> [Int] {
        guard !levels.isEmpty else { return [] }
        // ceil, so a 65–127 sample take averages its tail into the last bars
        // instead of dropping everything past the first 6.4 seconds.
        let chunk = max(1, Int((Double(levels.count) / Double(bars)).rounded(.up)))
        var out: [Int] = []
        var i = 0
        while i < levels.count && out.count < bars {
            let slice = levels[i..<min(i + chunk, levels.count)]
            out.append(slice.reduce(0, +) / slice.count)
            i += chunk
        }
        return out
    }
}

// MARK: - Player (one at a time)

@MainActor
final class ChatVoicePlayer: ObservableObject {
    /// One player for the whole thread — starting any bubble stops the last.
    static let threadShared = ChatVoicePlayer()

    @Published var playingId: String?
    @Published var progress: Double = 0

    private var player: AVPlayer?
    private var ticker: Timer?
    private var endObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var durationSec: Double = 1
    private var holdsSession = false

    /// `durationSec` ≤ 0 means "metadata absent" — the real length is read
    /// from the asset once it loads, so old meta-less notes don't sprint to
    /// 100 % in a second.
    func toggle(id: String, url: String, durationSec: Int) {
        if playingId == id { stop(); return }
        stop()
        guard let u = URL(string: url) else { return }
        do {
            try VoiceAudioSession.activate(.playback, mode: .spokenAudio)
            holdsSession = true
        } catch {}
        let item = AVPlayerItem(url: u)
        let p = AVPlayer(playerItem: item)
        player = p
        playingId = id
        progress = 0
        self.durationSec = Double(max(1, durationSec))
        // The audio's real end — not a progress estimate — stops playback:
        // metadata durations lie (old notes have none, interrupted takes
        // overshoot), and estimating from them wedged or truncated bubbles.
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stop() }
        }
        observeInterruptions()
        p.play()
        if durationSec <= 0 {
            Task { [weak self, weak item] in
                guard let item, let t = try? await item.asset.load(.duration) else { return }
                let d = t.seconds
                guard let self, d.isFinite, d > 0,
                      self.player?.currentItem === item else { return }
                self.durationSec = d
            }
        }
        let t = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                // A load that dies (offline, bad URL) must not wedge the
                // bubble in a silent "playing" state.
                if p.currentItem?.status == .failed || p.error != nil { self.stop(); return }
                self.progress = min(1, max(0, p.currentTime().seconds / self.durationSec))
            }
        }
        RunLoop.main.add(t, forMode: .common)
        ticker = t
    }

    /// A call/Siri pause must not leave the bubble wedged on "playing".
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            Task { @MainActor [weak self] in
                if began { self?.stop() }
            }
        }
    }

    func stop() {
        player?.pause(); player = nil
        ticker?.invalidate(); ticker = nil
        if let o = endObserver { NotificationCenter.default.removeObserver(o); endObserver = nil }
        if let o = interruptionObserver { NotificationCenter.default.removeObserver(o); interruptionObserver = nil }
        playingId = nil
        progress = 0
        if holdsSession { holdsSession = false; VoiceAudioSession.release() }
    }
}

// MARK: - Waves

/// The composer's live wave — the newest ~40 levels as slim bars.
struct LiveWaveView: View {
    let levels: [Int]
    var tint: Color = .white

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.suffix(40).enumerated()), id: \.offset) { _, l in
                Capsule().fill(tint.opacity(0.9))
                    .frame(width: 2.5, height: max(3, CGFloat(l) / 100 * 22))
            }
        }
        .frame(height: 24)
        .animation(.linear(duration: 0.1), value: levels.count)
    }
}

/// A shared voice message's waveform — bars fill left→right as audio plays.
struct WaveformBars: View {
    let waveform: [Int]
    let progress: Double
    let playedTint: Color
    let restTint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            let bars = waveform.isEmpty ? Array(repeating: 45, count: 28) : waveform
            ForEach(Array(bars.enumerated()), id: \.offset) { i, l in
                Capsule()
                    .fill(Double(i) / Double(max(1, bars.count)) <= progress ? playedTint : restTint)
                    .frame(width: 2.5, height: max(3, CGFloat(min(100, max(0, l))) / 100 * 20))
            }
        }
        .frame(height: 22)
    }
}

// MARK: - The playable bubble

struct VoiceMessageBubble: View {
    let message: ChatMessage
    @ObservedObject var player: ChatVoicePlayer
    let onDark: Bool   // true inside my navy bubble, false on the light bubble

    private var duration: Int { message.attachmentMeta?.duration ?? 0 }
    private var playing: Bool { player.playingId == message.messageId }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Haptics.tap()
                guard let url = message.attachmentUrl else { return }
                // Raw duration on purpose: 0 tells the player the metadata is
                // absent, so it reads the real length from the asset.
                player.toggle(id: message.messageId, url: url, durationSec: duration)
            } label: {
                ZStack {
                    Circle().fill(onDark ? Color.white.opacity(0.22) : Nuru.gold)
                        .frame(width: 34, height: 34)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(onDark ? .white : Nuru.navy)
                        .offset(x: playing ? 0 : 1)
                }
            }
            .buttonStyle(.pressable)
            WaveformBars(
                waveform: message.attachmentMeta?.waveform ?? [],
                progress: playing ? player.progress : 0,
                playedTint: onDark ? .white : Nuru.gold,
                restTint: onDark ? Color.white.opacity(0.4) : Nuru.gold.opacity(0.35),
            )
            Text(String(format: "%d:%02d", duration / 60, duration % 60))
                .font(.inter(11, .semibold)).monospacedDigit()
                .foregroundStyle(onDark ? Color.white.opacity(0.85) : Nuru.ink600)
        }
        .accessibilityLabel("\(playing ? "Pause" : "Play") voice message, \(duration) seconds")
    }
}
