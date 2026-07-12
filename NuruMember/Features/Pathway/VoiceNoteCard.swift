// Wave 2 — a discipler's voice on the lesson.
//   • VoiceNoteCard      — "A word from <leader>": avatar, play/pause, thin
//     progress line. Streams the m4a with AVPlayer; styled like the narration
//     card but warm (verse background, gold edge) because it's a person.
//   • VoiceNoteLeaderRow — Instructor+ affordance under the lesson: record
//     (or re-record) up to 5 minutes for the whole congregation.
//   • VoiceRecordSheet   — the recorder: one big button, live seconds,
//     preview, then "Share with your congregation".
import SwiftUI
import AVFoundation

// MARK: - Playback

@MainActor
final class VoiceNotePlayer: ObservableObject {
    @Published var playing = false
    @Published var progress: Double = 0

    private var player: AVPlayer?
    private var ticker: Timer?
    private var durationSec: Double = 1

    func toggle(url: String, durationSec: Int) {
        if playing { pause(); return }
        self.durationSec = Double(max(1, durationSec))
        if player == nil, let u = URL(string: url) {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = AVPlayer(url: u)
        }
        guard let player else { return }
        if progress >= 0.999 { player.seek(to: .zero); progress = 0 }
        player.play()
        playing = true
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    func pause() {
        player?.pause()
        playing = false
        ticker?.invalidate(); ticker = nil
    }

    private func tick() {
        guard let player else { return }
        let t = player.currentTime().seconds
        progress = min(1, max(0, t / durationSec))
        if progress >= 0.999 { pause() }
    }
}

struct VoiceNoteCard: View {
    let note: ModuleVoiceNote
    @StateObject private var player = VoiceNotePlayer()

    private var firstName: String {
        note.authorName.split(separator: " ").first.map(String.init) ?? note.authorName
    }

    var body: some View {
        Button {
            Haptics.tap()
            player.toggle(url: note.audioUrl, durationSec: note.durationSec)
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Avatar(url: note.avatarUrl, name: note.authorName, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("A WORD FROM \(firstName.uppercased())")
                            .font(.inter(10, .bold)).kerning(1.8)
                            .foregroundStyle(Nuru.goldChipText)
                        Text("Voice note · \(max(1, note.durationSec / 60))m \(note.durationSec % 60)s")
                            .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    }
                    Spacer(minLength: 0)
                    ZStack {
                        Circle().fill(Nuru.gold).frame(width: 40, height: 40)
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Nuru.navy)
                            .offset(x: player.playing ? 0 : 1)
                    }
                    .shadow(color: Nuru.gold.opacity(0.4), radius: 6, y: 3)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Nuru.gold.opacity(0.18))
                        Capsule().fill(Nuru.gold)
                            .frame(width: max(0, geo.size.width * player.progress))
                    }
                }
                .frame(height: 3)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Nuru.gold.opacity(player.playing ? 0.7 : 0.35), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
        .onDisappear { player.pause() }
        .accessibilityLabel("\(player.playing ? "Pause" : "Play") voice note from \(note.authorName)")
    }
}

// MARK: - Leader affordance

struct VoiceNoteLeaderRow: View {
    let moduleId: String
    let existing: ModuleVoiceNote?
    let onChanged: () -> Void
    @State private var showRecorder = false

    var body: some View {
        Button {
            Haptics.tap()
            showRecorder = true
        } label: {
            HStack(spacing: 8) {
                Icon(.mic, size: 13, color: Nuru.goldChipText)
                Text(existing == nil ? "Leave a word for your flock" : "Re-record your word")
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.goldChipText)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Nuru.verseBg, in: Capsule())
            .overlay(Capsule().stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .sheet(isPresented: $showRecorder) {
            VoiceRecordSheet(moduleId: moduleId, existing: existing) {
                showRecorder = false
                onChanged()
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Recorder sheet

@MainActor
final class VoiceRecorderModel: NSObject, ObservableObject {
    enum Phase { case idle, denied, recording, recorded, uploading }
    @Published var phase: Phase = .idle
    @Published var seconds = 0
    @Published var error: String?

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var preview: AVAudioPlayer?
    @Published var previewing = false

    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("nuru-voice-note.m4a")
    static let maxSeconds = 300

    func start() {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else { self.phase = .denied; return }
                self.beginRecording()
            }
        }
    }

    private func beginRecording() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true)
            try? FileManager.default.removeItem(at: fileURL)
            recorder = try AVAudioRecorder(url: fileURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            recorder?.record()
            seconds = 0
            phase = .recording
            ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.phase == .recording else { return }
                    self.seconds += 1
                    if self.seconds >= Self.maxSeconds { self.stop() }
                }
            }
        } catch {
            self.error = "Couldn't start recording."
            phase = .idle
        }
    }

    func stop() {
        recorder?.stop(); recorder = nil
        ticker?.invalidate(); ticker = nil
        phase = seconds >= 2 ? .recorded : .idle
        if phase == .idle { error = seconds < 2 ? "Hold it a little longer — say a full word to your flock." : nil }
    }

    func togglePreview() {
        if previewing { preview?.stop(); previewing = false; return }
        preview = try? AVAudioPlayer(contentsOf: fileURL)
        preview?.play()
        previewing = preview?.isPlaying == true
    }

    func share(moduleId: String) async -> Bool {
        phase = .uploading
        do {
            let data = try Data(contentsOf: fileURL)
            let url = try await MemberAPI.uploadVoiceAudio(m4a: data)
            try await MemberAPI.setVoiceNote(moduleId: moduleId, audioUrl: url, durationSec: max(1, seconds))
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't share the voice note."
            phase = .recorded
            return false
        }
    }
}

struct VoiceRecordSheet: View {
    let moduleId: String
    let existing: ModuleVoiceNote?
    let onDone: () -> Void
    @StateObject private var model = VoiceRecorderModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("A WORD FOR YOUR FLOCK")
                .font(.inter(11, .bold)).kerning(1.8)
                .foregroundStyle(Nuru.goldChipText)
                .padding(.top, 26)
            Text(existing == nil
                 ? "Everyone in your congregation will hear this at the top of the lesson. Up to five minutes."
                 : "This replaces your current word on this module.")
                .font(.inter(13.5)).foregroundStyle(Nuru.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            switch model.phase {
            case .idle, .denied:
                bigButton(icon: .mic, label: "Start recording", tint: Nuru.navy) { model.start() }
                if model.phase == .denied {
                    Text("Allow microphone access in Settings → Nuru Place to record.")
                        .font(.inter(12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                }
            case .recording:
                Text(timeString(model.seconds))
                    .font(.fraunces(40)).foregroundStyle(Nuru.navy)
                    .monospacedDigit()
                bigButton(icon: nil, sfSymbol: "stop.fill", label: "Stop", tint: .red) { model.stop() }
            case .recorded, .uploading:
                Text("\(timeString(model.seconds)) recorded")
                    .font(.inter(15, .semibold)).foregroundStyle(Nuru.navy)
                HStack(spacing: 12) {
                    Button {
                        Haptics.tap(); model.togglePreview()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: model.previewing ? "pause.fill" : "play.fill")
                                .font(.system(size: 12, weight: .bold))
                            Text("Listen back").font(.inter(13, .semibold))
                        }
                        .foregroundStyle(Nuru.navy)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    Button {
                        Haptics.tap(); model.phase = .idle; model.seconds = 0
                    } label: {
                        HStack(spacing: 6) {
                            Icon(.mic, size: 12, color: Nuru.ink)
                            Text("Redo").font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
                Button {
                    Haptics.action()
                    Task {
                        if await model.share(moduleId: moduleId) {
                            Haptics.success()
                            onDone()
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if model.phase == .uploading {
                            ProgressView().tint(Nuru.navy)
                        } else {
                            Icon(.users, size: 14, color: Nuru.navy)
                        }
                        Text(model.phase == .uploading ? "Sharing…" : "Share with your congregation")
                            .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(model.phase == .uploading)
                .padding(.horizontal, 24)
            }

            if let err = model.error {
                Text(err).font(.inter(12)).foregroundStyle(.red)
                    .multilineTextAlignment(.center).padding(.horizontal, 24)
            }
            Spacer(minLength: 0)
        }
        .presentationBackground(Color(red: 0.985, green: 0.975, blue: 0.95))
    }

    private func timeString(_ s: Int) -> String { String(format: "%d:%02d", s / 60, s % 60) }

    @ViewBuilder
    private func bigButton(icon: Lucide?, sfSymbol: String? = nil, label: String, tint: Color,
                           action: @escaping () -> Void) -> some View {
        Button {
            Haptics.action(); action()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(tint).frame(width: 74, height: 74)
                    if let icon {
                        Icon(icon, size: 28, color: .white)
                    } else if let sfSymbol {
                        Image(systemName: sfSymbol)
                            .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                    }
                }
                .shadow(color: tint.opacity(0.35), radius: 10, y: 4)
                Text(label).font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
            }
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Cell presence (Pathway hub)

/// "Leah, Sam and 1 other from your cell opened a lesson this week." Quiet,
/// factual togetherness — renders nothing when nobody has been reading.
struct CellPresenceLine: View {
    @State private var presence: CommunityPresence?

    private var line: String? {
        guard let p = presence, p.count > 0 else { return nil }
        let who = p.scope == "cell" ? "your cell" : "your congregation"
        let others = p.count - p.names.count
        var names = p.names.joined(separator: ", ")
        if p.names.count > 1, let last = p.names.last {
            names = p.names.dropLast().joined(separator: ", ") + " and " + last
        }
        if others > 0 {
            return "\(names) and \(others) other\(others == 1 ? "" : "s") from \(who) opened a lesson this week."
        }
        return p.count == 1
            ? "\(names) from \(who) opened a lesson this week. You're not walking alone."
            : "\(names) from \(who) opened a lesson this week."
    }

    var body: some View {
        Group {
            if let line {
                HStack(alignment: .top, spacing: 8) {
                    Icon(.flame, size: 13, color: Nuru.goldChipText)
                        .padding(.top, 1)
                    Text(line)
                        .font(.inter(12.5)).foregroundStyle(Nuru.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
            }
        }
        .task { presence = try? await MemberAPI.communityPresence() }
    }
}
