// Chat voice messages — Android parity (ChatThreadScreen.kt's VoiceRecorder/
// VoicePlayer/WaveformBars, ported).
//   • ChatVoiceRecorder — AVAudioRecorder (AAC m4a, mono) with a 10 Hz meter
//     sampler feeding `levels` (0–100) for the live wave; waveformFor() bucket-
//     averages down to the server cap (64 of max 80 ints).
//   • ChatVoicePlayer  — one-at-a-time remote playback with progress, so the
//     played fraction can highlight the shared waveform.
//   • LiveWaveView / WaveformBars — the composer's live wave and the bubble's
//     static-with-fill wave.
//   • VoiceMessageBubble — a real, playable voice message (replaces the old
//     inert "Voice note" pill).
import SwiftUI
import AVFoundation

// MARK: - Recorder

@MainActor
final class ChatVoiceRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var elapsedSec = 0
    @Published var levels: [Int] = []   // 0..100, one per 100 ms

    private var recorder: AVAudioRecorder?
    private var meter: Timer?
    private var fileURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("nuru-chat-voice.m4a")
    }

    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self, granted else { return }
                self.begin()
            }
        }
    }

    private func begin() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            try? FileManager.default.removeItem(at: fileURL)
            let r = try AVAudioRecorder(url: fileURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            r.isMeteringEnabled = true
            r.record()
            recorder = r
            levels = []
            elapsedSec = 0
            isRecording = true
            var ticks = 0
            meter?.invalidate()
            meter = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let r = self.recorder, self.isRecording else { return }
                    r.updateMeters()
                    // dBFS (−160…0) → 0..100, matching Android's normalisation.
                    let db = r.averagePower(forChannel: 0)
                    let level = Int((max(0, min(1, (db + 50) / 50)) * 100).rounded())
                    self.levels.append(level)
                    if self.levels.count > 600 { self.levels.removeFirst() }
                    ticks += 1
                    if ticks % 10 == 0 { self.elapsedSec += 1 }
                    if self.elapsedSec >= 300 { _ = self.stop() } // server caps 5 min
                }
            }
        } catch {
            isRecording = false
        }
    }

    /// Stop and return the recorded file (nil if too short to mean anything).
    func stop() -> URL? {
        meter?.invalidate(); meter = nil
        recorder?.stop(); recorder = nil
        isRecording = false
        return elapsedSec >= 1 ? fileURL : nil
    }

    func cancel() {
        meter?.invalidate(); meter = nil
        recorder?.stop(); recorder = nil
        isRecording = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Bucket-average the live samples down to `bars` ints 0..100 (server cap 80).
    func waveformFor(_ bars: Int = 64) -> [Int] {
        guard !levels.isEmpty else { return [] }
        let chunk = max(1, levels.count / bars)
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

    func toggle(id: String, url: String, durationSec: Int) {
        if playingId == id { stop(); return }
        stop()
        guard let u = URL(string: url) else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
        let p = AVPlayer(url: u)
        player = p
        playingId = id
        progress = 0
        p.play()
        let dur = Double(max(1, durationSec))
        ticker = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let p = self.player else { return }
                self.progress = min(1, max(0, p.currentTime().seconds / dur))
                if self.progress >= 0.999 { self.stop() }
            }
        }
    }

    func stop() {
        player?.pause(); player = nil
        ticker?.invalidate(); ticker = nil
        playingId = nil
        progress = 0
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
                player.toggle(id: message.messageId, url: url, durationSec: max(1, duration))
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
