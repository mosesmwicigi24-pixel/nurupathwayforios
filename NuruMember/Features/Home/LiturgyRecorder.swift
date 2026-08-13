// Liturgy recorder (feat/liturgy-recorded-voice) — Admin/SuperAdmin only:
// lets the pastor record the daily liturgy in his OWN VOICE, one band at a
// time, instead of relying only on on-device speech synthesis.
//   • LiturgyRecorderModel  — AVAudioRecorder-backed, mirrors
//     VoiceRecorderModel (VoiceNoteCard.swift) almost exactly: same Phase
//     enum, same AAC/44.1kHz/mono settings, same record→preview→keep-or-
//     discard lifecycle, same interruption handling. Differs only in the
//     upload step: `share(band:)` calls the ONE-STEP admin endpoint
//     (MemberAPI.uploadLiturgyRecording) instead of the two-step
//     upload-then-attach module-voice-note flow — there is no separate
//     "attach" call here, the multipart POST does both at once.
//   • LiturgyRecordSheet    — the recorder for ONE band: big button, live
//     seconds, "Listen back" / "Redo", then save.
//   • LiturgyRecordingsSheet — the admin's home base: all 7 bands, clock
//     order, each showing "his voice" vs "synthesised" plus a record/
//     re-record control and (when recorded) a delete control. Deliberately
//     NOT a completion meter — no "5 of 7", no progress bar, no color-coded
//     urgency. Mixed coverage is the permanent normal state (see
//     LiturgyRecorderLogic.swift's header) — this list exists so he can see
//     and manage coverage, not so he feels behind on it.
import SwiftUI
import AVFoundation

// MARK: - Recorder model (mirrors VoiceRecorderModel; see file header)

@MainActor
final class LiturgyRecorderModel: NSObject, ObservableObject {
    enum Phase { case idle, denied, recording, recorded, uploading }
    @Published var phase: Phase = .idle
    @Published var seconds = 0
    @Published var error: String?
    @Published var previewing = false

    private var recorder: AVAudioRecorder?
    private var ticker: Timer?
    private var preview: AVAudioPlayer?
    private var interruptionObserver: NSObjectProtocol?
    private var holdsSession = false

    let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("nuru-liturgy-recording.m4a")
    /// The backend's own bound (`duration_sec` accepts 1–900) — recording
    /// auto-stops here rather than producing a take the server would reject.
    static let maxSeconds = 900

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
            try VoiceAudioSession.activate(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            holdsSession = true
            try? FileManager.default.removeItem(at: fileURL)
            let r = try AVAudioRecorder(url: fileURL, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            guard r.record() else {   // session refused (active call etc.)
                releaseSession()
                self.error = "Couldn't start recording."
                phase = .idle
                return
            }
            recorder = r
            seconds = 0
            phase = .recording
            observeInterruptions()
            let t = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.phase == .recording, let r = self.recorder else { return }
                    self.seconds = Int(r.currentTime)
                    if self.seconds >= Self.maxSeconds { self.stop() }
                }
            }
            RunLoop.main.add(t, forMode: .common)
            ticker = t
        } catch {
            releaseSession()
            self.error = "Couldn't start recording."
            phase = .idle
        }
    }

    /// A call/Siri stops the hardware mid-take: finalize what was captured
    /// (as if he tapped Stop) so the clock can't count silence.
    private func observeInterruptions() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began
            Task { @MainActor [weak self] in
                guard let self, began else { return }
                if self.phase == .recording { self.stop() }
                else if self.previewing { self.preview?.stop(); self.previewDidEnd() }
            }
        }
    }

    func stop() {
        if let r = recorder { seconds = Int(r.currentTime.rounded()) }
        recorder?.stop(); recorder = nil
        ticker?.invalidate(); ticker = nil
        releaseSession()
        phase = seconds >= 2 ? .recorded : .idle
        if phase == .idle { error = seconds < 2 ? "Hold it a little longer — read a full line before stopping." : nil }
    }

    func togglePreview() {
        if previewing { preview?.stop(); previewDidEnd(); return }
        do {
            try VoiceAudioSession.activate(.playback, mode: .spokenAudio)
            holdsSession = true
        } catch {}
        preview = try? AVAudioPlayer(contentsOf: fileURL)
        preview?.delegate = self
        preview?.play()
        previewing = preview?.isPlaying == true
        if !previewing { releaseSession() }
    }

    /// Back to a clean slate — a running preview must not play through the
    /// speaker into the retake.
    func redo() {
        if previewing { preview?.stop(); previewDidEnd() }
        preview = nil
        seconds = 0
        error = nil
        phase = .idle
    }

    /// Sheet teardown (swipe-dismiss or done): nothing may keep running —
    /// recorder, preview, the 1 Hz ticker, the interruption observer, or the
    /// audio-session hold.
    func cleanup() {
        recorder?.stop(); recorder = nil
        ticker?.invalidate(); ticker = nil
        preview?.stop(); preview = nil
        previewing = false
        if let o = interruptionObserver {
            NotificationCenter.default.removeObserver(o)
            interruptionObserver = nil
        }
        releaseSession()
    }

    private func previewDidEnd() {
        previewing = false
        releaseSession()
    }

    private func releaseSession() {
        guard holdsSession else { return }
        holdsSession = false
        VoiceAudioSession.release()
    }

    /// The ONE combined upload+attach call — see MemberAPI+LiturgyRecordings.swift.
    /// Calling this again for the same band is how a re-record REPLACES the
    /// existing recording; there's no separate "replace" step.
    func share(band: LiturgyBand) async -> Bool {
        guard LiturgyRecorderValidation.isValidDuration(seconds) else {
            self.error = "That take is too short to save."
            phase = .recorded
            return false
        }
        phase = .uploading
        do {
            // Off the main actor — even a long take is a few MB of disk read.
            let data = try await Task.detached { [fileURL] in try Data(contentsOf: fileURL) }.value
            _ = try await MemberAPI.uploadLiturgyRecording(band: band.rawValue, m4a: data, durationSec: seconds)
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't save the recording."
            phase = .recorded
            return false
        }
    }
}

extension LiturgyRecorderModel: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.previewDidEnd() }
    }
}

// MARK: - Per-band recorder sheet

struct LiturgyRecordSheet: View {
    let band: LiturgyBand
    let alreadyRecorded: Bool
    let onSaved: () -> Void
    @StateObject private var model = LiturgyRecorderModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Text("\(band.label.uppercased()) · YOUR VOICE")
                .font(.inter(11, .bold)).kerning(1.8)
                .foregroundStyle(Nuru.goldChipText)
                .padding(.top, 26)
            Text(alreadyRecorded
                 ? "This replaces your current \(band.label.lowercased()) recording. The congregation hears it instead of the on-device voice from now on."
                 : "The congregation hears this instead of the on-device voice for \(band.label.lowercased()).")
                .font(.inter(13.5)).foregroundStyle(Nuru.ink)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)

            switch model.phase {
            case .idle, .denied:
                bigButton(sfSymbol: "mic.fill", label: "Start recording", tint: Nuru.navy) { model.start() }
                if model.phase == .denied {
                    Text("Allow microphone access in Settings → Nuru Place to record.")
                        .font(.inter(12)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                }
            case .recording:
                Text(LiturgyRecorderFormat.timeString(model.seconds))
                    .font(.fraunces(40)).foregroundStyle(Nuru.navy)
                    .monospacedDigit()
                bigButton(sfSymbol: "stop.fill", label: "Stop", tint: .red) { model.stop() }
            case .recorded, .uploading:
                Text("\(LiturgyRecorderFormat.timeString(model.seconds)) recorded")
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
                        Haptics.tap(); model.redo()
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
                        if await model.share(band: band) {
                            Haptics.success()
                            onSaved()
                            dismiss()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if model.phase == .uploading {
                            ProgressView().tint(Nuru.navy)
                        } else {
                            Icon(.checkCircle2, size: 14, color: Nuru.navy)
                        }
                        Text(model.phase == .uploading ? "Saving…" : "Save this reading")
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
        // A half-hearted swipe must not leave a live mic (or upload) running
        // behind a closed sheet; deliberate dismissal still tears it all down.
        .interactiveDismissDisabled(model.phase == .recording || model.phase == .uploading)
        .onDisappear { model.cleanup() }
    }

    @ViewBuilder
    private func bigButton(sfSymbol: String, label: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.action(); action()
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle().fill(tint).frame(width: 74, height: 74)
                    Image(systemName: sfSymbol)
                        .font(.system(size: 24, weight: .bold)).foregroundStyle(.white)
                }
                .shadow(color: tint.opacity(0.35), radius: 10, y: 4)
                Text(label).font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
            }
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Admin recorder list (all 7 bands)

/// The pastor's own home base for this feature: see the list, tap a band to
/// (re-)record or remove it. No count, no progress bar, no "X left" — see
/// this file's header and LiturgyRecorderLogic.swift for why.
struct LiturgyRecordingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rows: [LiturgyRecordingRow] = LiturgyRecordingRows.build(from: [])
    @State private var loaded = false
    @State private var loadError: String?
    @State private var recordTarget: LiturgyBand?
    @State private var deleteTarget: LiturgyBand?
    @State private var deleting: LiturgyBand?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                } footer: {
                    // No completion language on purpose — mixed coverage is
                    // the permanent normal state, not a checklist to finish.
                    Text("Bands without a recording use the on-device voice — that's expected, not a gap.")
                        .font(.inter(11.5)).foregroundStyle(Nuru.muted)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Liturgy — Your Voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay {
                if !loaded {
                    ProgressView().tint(Nuru.navy)
                } else if let loadError {
                    VStack(spacing: 8) {
                        Text(loadError).font(.inter(13)).foregroundStyle(.secondary)
                        Button("Try again") { Task { await load() } }
                            .font(.inter(13, .semibold))
                    }
                    .padding(24)
                }
            }
        }
        .task { await load() }
        .sheet(item: $recordTarget) { band in
            LiturgyRecordSheet(band: band, alreadyRecorded: hasRecording(band)) {
                Task { await load() }
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            deleteTarget.map { "Remove your \($0.label.lowercased()) recording?" } ?? "",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let band = deleteTarget { Task { await delete(band) } }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("The on-device voice will read this band again until you record a new take.")
        }
    }

    private func hasRecording(_ band: LiturgyBand) -> Bool {
        rows.first { $0.band == band }?.hasRecording ?? false
    }

    @ViewBuilder
    private func rowView(_ row: LiturgyRecordingRow) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.band.label)
                    .font(.inter(14.5, .semibold)).foregroundStyle(Nuru.ink)
                statusChip(row)
            }
            Spacer(minLength: 8)
            if deleting == row.band {
                ProgressView().tint(Nuru.navy)
            } else {
                if row.hasRecording {
                    Button {
                        Haptics.tap(); deleteTarget = row.band
                    } label: {
                        Icon(.trash2, size: 15, color: .red.opacity(0.75))
                    }
                    .buttonStyle(.pressable)
                }
                Button {
                    Haptics.tap(); recordTarget = row.band
                } label: {
                    Icon(.mic, size: 15, color: Nuru.goldChipText)
                        .frame(width: 30, height: 30)
                        .background(Nuru.verseBg, in: Circle())
                        .overlay(Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(row.hasRecording ? "Re-record \(row.band.label)" : "Record \(row.band.label)")
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func statusChip(_ row: LiturgyRecordingRow) -> some View {
        if row.hasRecording {
            Text("His voice" + (row.durationSec.map { " · \(LiturgyRecorderFormat.timeString($0))" } ?? ""))
                .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Nuru.goldChipBg, in: Capsule())
        } else {
            Text("Synthesised")
                .font(.inter(11, .semibold)).foregroundStyle(Nuru.muted)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Nuru.mutedBg, in: Capsule())
        }
    }

    private func load() async {
        do {
            let statuses = try await MemberAPI.liturgyRecordings()
            rows = LiturgyRecordingRows.build(from: statuses)
            loadError = nil
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? "Couldn't load your recordings."
        }
        loaded = true
    }

    private func delete(_ band: LiturgyBand) async {
        deleting = band
        do {
            try await MemberAPI.deleteLiturgyRecording(band: band.rawValue)
            Haptics.success()
        } catch {
            // A 404 means it was already gone (e.g. another admin removed it
            // moments ago) — either way there's nothing left to show as
            // recorded, so a fresh load settles the list either way.
            Haptics.error()
        }
        deleting = nil
        await load()
    }
}

extension LiturgyBand: Identifiable { var id: String { rawValue } }
