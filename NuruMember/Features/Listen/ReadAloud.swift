// Read aloud. Plan readings can use server-authorized narration, with the
// device voice as an offline/service fallback; other readers remain on-device.
// Only plan and scripture text goes to the provider, never a member's reflection.
// Android's twin: ReadAloud.kt.
//
// The liturgy voice reads one short card. A plan reading, a devotional, a
// letter or a lesson is long, so this engine adds what listening to something
// long needs:
//   - paragraphs (ListenScript.swift) queued in order, the current one
//     tracked from the synthesizer's own didStart callbacks;
//   - pause and resume where the voice stopped — AVSpeechSynthesizer can
//     pause mid-sentence (`pauseSpeaking(at: .word)`) and carry on;
//   - a paragraph back or on, and a speed (ListenSpeed, kept on this phone):
//     both stop and queue again from the paragraph;
//   - it keeps reading with the screen locked or the app in the background
//     (UIBackgroundModes: audio, the `.playback` / `.spokenAudio` session).
//     It stops when the member LEAVES the reading (the reader's onDisappear),
//     not when the app goes to the background — listening with the phone in
//     a pocket is the point.
// The guards are the liturgy voice's: never over VoiceOver (two voices — the
// Listen control isn't offered while it runs, and a reading pauses if it
// starts), never while the church is broadcasting live (or the member is: a
// broadcast holds the session), and Nuru Radio is PAUSED for a reading, not
// ducked under it — minutes of music under someone reading is noise. Radio
// comes back when the reading pauses or ends, as on Android. A phone call
// pauses the reading; it carries on if iOS says it may.
import AVFoundation
import Combine
import UIKit

@MainActor
final class ReadAloud: NSObject, ObservableObject {
    static let shared = ReadAloud()

    @Published private(set) var status: ListenStatus = .idle
    /// The reading loaded (playing or paused) — nil when none is.
    @Published private(set) var key: String?
    /// The paragraph being read, of the loaded reading's.
    @Published private(set) var index = 0
    @Published private(set) var speed: Double
    @Published private(set) var voiceOverOn: Bool
    /// The church is live (or this member is broadcasting): Listen waits.
    @Published private(set) var liveNow = false
    @Published private(set) var deviceFallback = false

    private var paragraphs: [String] = []
    private var synthesizer: AVSpeechSynthesizer?
    private var narration: PlanNarration?
    private var audioPlayer: AVAudioPlayer?
    private var audioTask: Task<Void, Never>?
    private var audioGeneration = UUID()
    #if DEBUG
    // Injected only by simulator tests; production always uses the API client.
    var testAudioLoader: ((String) async throws -> Data)?
    #endif
    /// The queued utterances (held, so their identities stay unique) and the
    /// paragraph each one reads.
    private var queued: [AVSpeechUtterance] = []
    private var paragraphOf: [ObjectIdentifier: Int] = [:]
    /// A skip or a new speed while paused: resume starts that paragraph again.
    private var resumeFresh = false
    private var holdsSession = false
    private var pausedRadio = false
    private var interrupted = false
    private var observers: [NSObjectProtocol] = []
    private var liveObserver: AnyCancellable?
    private var radioObserver: AnyCancellable?

    private override init() {
        let stored = UserDefaults.standard.double(forKey: ListenSpeed.storageKey)
        speed = stored > 0 ? stored : 1.0
        voiceOverOn = UIAccessibility.isVoiceOverRunning
        super.init()
        observe()
    }

    /// Listen may be offered right now.
    var offered: Bool { !voiceOverOn && !liveNow }

    /// The controls for one reading on screen.
    func controls(for reading: ListenReading) -> ListenControls {
        ListenControls.resolve(reading, loadedKey: key, status: status, index: index,
                               offered: offered, speed: speed, deviceFallback: deviceFallback)
    }

    // MARK: - Transport (every call is a member's tap)

    /// The one button: start this reading from the top, pause it, or resume it.
    func toggle(_ reading: ListenReading) {
        if key == reading.key {
            switch status {
            case .playing: pause(); return
            case .paused: resume(); return
            case .idle: break
            }
        }
        play(reading, from: 0)
    }

    func play(_ reading: ListenReading, from start: Int = 0) {
        guard !reading.words.isEmpty, offered else { return }
        if status != .idle { halt(handBackRadio: false) }   // another reading was loaded
        guard activateSession() else { return }
        paragraphs = reading.words
        key = reading.key
        narration = reading.narration
        deviceFallback = reading.isPlan && reading.narration == nil
        speakFrom(min(max(start, 0), reading.words.count - 1))
    }

    func pause() { pause(handBackRadio: true) }

    func resume() {
        guard status == .paused, key != nil, !paragraphs.isEmpty else { return }
        guard !UIAccessibility.isVoiceOverRunning else { return }
        guard activateSession() else { return }
        if narration != nil, !resumeFresh, let player = audioPlayer, !player.isPlaying {
            pauseRadio()
            if player.play() { status = .playing } else { speakFrom(index) }
        } else if resumeFresh || synthesizer?.isPaused != true {
            speakFrom(index)
        } else {
            pauseRadio()
            synthesizer?.continueSpeaking()
            status = .playing
        }
    }

    /// One paragraph back or on. While paused it only moves the place; while
    /// playing it reads from there. Past the end is the end.
    func skip(_ delta: Int) {
        guard key != nil, !paragraphs.isEmpty else { return }
        let target = index + delta
        if target > paragraphs.count - 1 { stop(); return }
        let i = max(target, 0)
        switch status {
        case .playing: speakFrom(i)
        case .paused: index = i; resumeFresh = true
        case .idle: break
        }
    }

    /// The next speed, kept on this phone; a reading in progress picks it up
    /// from the paragraph it is on.
    func cycleSpeed() {
        speed = ListenSpeed.next(after: speed)
        UserDefaults.standard.set(speed, forKey: ListenSpeed.storageKey)
        switch status {
        case .playing: speakFrom(index)
        case .paused: resumeFresh = true
        case .idle: break
        }
    }

    /// Stop and unload. Safe when nothing is loaded.
    func stop() {
        guard status != .idle || key != nil else { return }
        halt(handBackRadio: true)
    }

    /// The reader showing `key` is leaving (or its words changed): stop it if
    /// it is the one loaded, so a voice never reads what is no longer there.
    func leave(_ key: String) {
        if self.key == key { stop() }
    }

    // MARK: - Speaking

    private func pause(handBackRadio: Bool) {
        guard status == .playing else { return }
        if narration != nil {
            audioTask?.cancel()
            audioTask = nil
            audioGeneration = UUID()
            if let player = audioPlayer { player.pause() } else { resumeFresh = true }
        } else {
            synthesizer?.pauseSpeaking(at: .word)
        }
        status = .paused
        if handBackRadio { resumeRadio() }
    }

    private func speakFrom(_ start: Int) {
        discardSynthesizer()
        discardAudio()
        guard start >= 0, start < paragraphs.count else { halt(handBackRadio: true); return }
        if let path = narration?.audioPath(index: start) {
            index = start
            resumeFresh = false
            status = .playing
            pauseRadio()
            let generation = audioGeneration
            audioTask = Task { [weak self] in
                do {
                    let bytes: Data
                    #if DEBUG
                    if let loader = self?.testAudioLoader { bytes = try await loader(path) }
                    else { bytes = try await APIClient.shared.download(serverPath: path, method: "POST") }
                    #else
                    bytes = try await APIClient.shared.download(serverPath: path, method: "POST")
                    #endif
                    guard let self, !Task.isCancelled, self.audioGeneration == generation, self.status == .playing else { return }
                    guard !bytes.isEmpty, bytes.count <= 10 * 1024 * 1024 else { throw NSError(domain: "PlanNarration", code: 2) }
                    let player = try AVAudioPlayer(data: bytes)
                    player.delegate = self
                    player.enableRate = true
                    player.rate = Float(self.speed)
                    self.audioPlayer = player
                    guard player.play() else { throw NSError(domain: "PlanNarration", code: 1) }
                } catch {
                    guard let self, !Task.isCancelled, self.audioGeneration == generation, self.status == .playing else { return }
                    // Keep reading available when the service or network is down.
                    self.narration = nil
                    self.deviceFallback = true
                    self.speakFrom(start)
                }
            }
            return
        }
        let synth = AVSpeechSynthesizer()
        synth.delegate = self
        synthesizer = synth
        let voice = Self.voice
        let rate = ListenSpeed.rate(for: speed, defaultRate: AVSpeechUtteranceDefaultSpeechRate,
                                    minimum: AVSpeechUtteranceMinimumSpeechRate,
                                    maximum: AVSpeechUtteranceMaximumSpeechRate)
        var list: [AVSpeechUtterance] = []
        var map: [ObjectIdentifier: Int] = [:]
        for j in start..<paragraphs.count {
            let u = AVSpeechUtterance(string: paragraphs[j])
            u.voice = voice
            u.rate = rate
            u.pitchMultiplier = 0.97
            // A breath between paragraphs.
            u.postUtteranceDelay = 0.3
            map[ObjectIdentifier(u)] = j
            list.append(u)
        }
        queued = list
        paragraphOf = map
        index = start
        resumeFresh = false
        status = .playing
        pauseRadio()
        for u in list { synth.speak(u) }
    }

    private func discardSynthesizer() {
        if let s = synthesizer {
            s.delegate = nil
            s.stopSpeaking(at: .immediate)
        }
        synthesizer = nil
        queued = []
        paragraphOf = [:]
    }

    private func discardAudio() {
        audioGeneration = UUID()
        audioTask?.cancel()
        audioTask = nil
        audioPlayer?.delegate = nil
        audioPlayer?.stop()
        audioPlayer = nil
    }

    /// The one place a reading ends, for any reason.
    private func halt(handBackRadio: Bool) {
        discardSynthesizer()
        discardAudio()
        narration = nil
        deviceFallback = false
        paragraphs = []
        key = nil
        index = 0
        resumeFresh = false
        interrupted = false
        status = .idle
        releaseSession()
        if handBackRadio { resumeRadio() } else { pausedRadio = false }
    }

    fileprivate func started(synth: ObjectIdentifier, utterance: ObjectIdentifier) {
        guard isCurrent(synth), status == .playing, let i = paragraphOf[utterance] else { return }
        index = i
    }

    fileprivate func finished(synth: ObjectIdentifier, utterance: ObjectIdentifier) {
        guard isCurrent(synth), let i = paragraphOf[utterance] else { return }
        if i >= paragraphs.count - 1 { halt(handBackRadio: true) }
    }

    private func isCurrent(_ synth: ObjectIdentifier) -> Bool {
        guard let s = synthesizer else { return false }
        return ObjectIdentifier(s) == synth
    }

    /// Re-evaluate installed voices for each reading, including voices the
    /// member downloaded since the app was launched. Prefer premium, then
    /// enhanced, then the installed default-quality English voices.
    private static var voice: AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter {
            !$0.voiceTraits.contains(.isNoveltyVoice) && !$0.voiceTraits.contains(.isPersonalVoice)
        }.map {
            ListenVoiceCandidate(identifier: $0.identifier, language: $0.language,
                                 quality: $0.quality == .premium ? 2 : ($0.quality == .enhanced ? 1 : 0))
        }
        guard let chosen = ListenVoiceSelector.choose(from: candidates) else { return nil }
        return AVSpeechSynthesisVoice(identifier: chosen.identifier)
    }

    // MARK: - Session and Radio

    private func activateSession() -> Bool {
        if holdsSession {
            // After a call the system may have deactivated it.
            try? AVAudioSession.sharedInstance().setActive(true)
            return true
        }
        do {
            try VoiceAudioSession.activate(.playback, mode: .spokenAudio)
            holdsSession = true
            return true
        } catch {
            return false
        }
    }

    private func releaseSession() {
        guard holdsSession else { return }
        holdsSession = false
        VoiceAudioSession.release()
    }

    private func pauseRadio() {
        guard RadioCenter.shared.playing else { return }
        pausedRadio = true
        RadioCenter.shared.pause()
    }

    private func resumeRadio() {
        guard pausedRadio else { return }
        pausedRadio = false
        RadioCenter.shared.play()
    }

    // MARK: - Observers

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: UIAccessibility.voiceOverStatusDidChangeNotification,
                                            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.voiceOverChanged() }
        })
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
                                            object: AVAudioSession.sharedInstance(), queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            let began = raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == AVAudioSession.InterruptionType.began
            let optionsRaw = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let mayResume = AVAudioSession.InterruptionOptions(rawValue: optionsRaw).contains(.shouldResume)
            Task { @MainActor [weak self] in self?.interruption(began: began, mayResume: mayResume) }
        })
        // The church going live hides Listen (a reading already playing
        // carries on, as on Android); the member starting a broadcast stops
        // it — WebRTC holds the session's recording claim.
        liveObserver = LiveDiscoveryCenter.shared.$streams
            .map { rows in rows.contains { $0.isChurch } }
            .combineLatest(BroadcastCenter.shared.$controller.map { $0 != nil })
            .sink { [weak self] churchLive, broadcasting in
                guard let self else { return }
                self.liveNow = churchLive || broadcasting
                if broadcasting, self.status != .idle { self.stop() }
            }
        // The member starts Radio themselves while a reading plays: the
        // reading pauses (Radio asked for the speaker last).
        radioObserver = RadioCenter.shared.$playing
            .removeDuplicates()
            .sink { [weak self] on in
                guard let self, on, self.status == .playing else { return }
                self.pausedRadio = false
                self.pause(handBackRadio: false)
            }
    }

    private func voiceOverChanged() {
        voiceOverOn = UIAccessibility.isVoiceOverRunning
        // Never two voices: VoiceOver reads the screen now.
        if voiceOverOn, status == .playing { pause(handBackRadio: true) }
    }

    private func interruption(began: Bool, mayResume: Bool) {
        if began {
            guard status == .playing else { return }
            interrupted = true
            pause(handBackRadio: false)
        } else {
            guard interrupted else { return }
            interrupted = false
            if mayResume { resume() }
        }
    }
}

extension ReadAloud: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let identity = ObjectIdentifier(player)
        Task { @MainActor [weak self] in
            guard let self, let current = self.audioPlayer, ObjectIdentifier(current) == identity, self.status == .playing else { return }
            if flag, self.index < self.paragraphs.count - 1 {
                self.speakFrom(self.index + 1)
            } else {
                self.stop()
            }
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension ReadAloud: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let s = ObjectIdentifier(synthesizer)
        let u = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.started(synth: s, utterance: u) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let s = ObjectIdentifier(synthesizer)
        let u = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.finished(synth: s, utterance: u) }
    }
}
