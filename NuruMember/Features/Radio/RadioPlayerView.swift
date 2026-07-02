// Nuru Radio — the full station experience over the backend radio module.
//
// GET /radio/programs (listPublic) returns every visible non-draft program,
// live-first. The station screen groups them: ON AIR (live), UP NEXT (scheduled,
// soonest first) and RECORDED SHOWS (ended + audio_url — playable anytime, which
// is the "offline listening" story today: recorded shows stream from their hosted
// audio_url on demand. Future work: a real download manager (background
// URLSession + local file store) for true no-network playback).
//
// Tapping a row (or arriving while a program is live — we auto-open it) shows the
// program player: HLS via AVPlayer when live (hls_url), audio_url for recorded,
// reactions (POST /radio/programs/{id}/react — idempotent per client_event_id)
// and comments (GET/POST /radio/programs/{id}/comments) on EVERY program,
// scheduled included, so members can hype upcoming shows.
import SwiftUI
import AVFoundation

// MARK: - Wire models (snake_case → camelCase via APIClient's decoder)

struct RadioProgram: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let category: String
    let speaker: String?
    let artworkUrl: String?
    let scheduledAt: String?
    let status: String            // "scheduled" | "live" | "ended" (draft never served)
    let isLive: Bool
    let audioUrl: String?
    let hlsUrl: String?
    let peakListeners: Int?

    /// Live → HLS; otherwise the hosted recording (nil = nothing to play yet).
    var streamUrl: URL? {
        if isLive, let h = hlsUrl, let u = URL(string: h) { return u }
        if let a = audioUrl, let u = URL(string: a) { return u }
        return nil
    }

    var live: Bool { isLive || status == "live" }
    var recorded: Bool { status == "ended" && audioUrl != nil }
}

struct RadioReactionCounts: Decodable, Sendable { let heart: Int; let amen: Int; let fire: Int }

/// One comment row. The backend select (radio service listComments) returns
/// id/program_id/member_id/body/created_at only — NO author-name join yet, so
/// the UI renders comments anonymously ("Member").
struct RadioComment: Decodable, Sendable, Identifiable {
    let id: String
    let memberId: String
    let body: String
    let createdAt: String
}

// MARK: - Station model (the directory screen)

@MainActor
final class RadioStationModel: ObservableObject {
    @Published var programs: [RadioProgram] = []
    @Published var loading = true
    @Published var errorText: String?

    var onAir: [RadioProgram] { programs.filter { $0.live } }
    /// Scheduled shows, soonest first (server order is newest-first, so re-sort).
    var upNext: [RadioProgram] {
        programs.filter { $0.status == "scheduled" && !$0.live }
            .sorted { ($0.scheduledAt ?? "") < ($1.scheduledAt ?? "") }
    }
    /// Ended shows WITH a hosted recording — playable anytime (server order kept).
    var recordedShows: [RadioProgram] { programs.filter { $0.recorded } }

    func load() async {
        loading = programs.isEmpty
        errorText = nil
        do {
            programs = try await MemberAPI.radioPrograms()
        } catch {
            if programs.isEmpty { errorText = error.localizedDescription }
        }
        loading = false
    }
}

// MARK: - Entry (fullscreen from Home) — station list, auto-opens the live show

struct RadioPlayerView: View {
    @StateObject private var vm = RadioStationModel()
    @Environment(\.dismiss) private var dismiss
    @State private var path: [RadioProgram] = []
    @State private var autoOpened = false

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                RadioBackground()
                content
            }
            .overlay(alignment: .topLeading) {
                Button { dismiss() } label: {
                    Icon(.x, size: 18, color: .white).frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain).padding(.leading, 16).padding(.top, 8)
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: RadioProgram.self) { p in
                RadioProgramDetailView(program: p)
            }
        }
        .task {
            await vm.load()
            // Land straight on the live broadcast the first time one is on.
            if !autoOpened, let live = vm.onAir.first {
                autoOpened = true
                path.append(live)
            }
        }
    }

    @ViewBuilder private var content: some View {
        if vm.loading {
            ProgressView().tint(Nuru.gold)
        } else if let err = vm.errorText {
            RadioErrorState(message: err) { Task { await vm.load() } }
        } else if vm.programs.isEmpty {
            RadioEmptyState()
        } else {
            stationList
        }
    }

    private var stationList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                stationHeader
                if !vm.onAir.isEmpty {
                    RadioSectionHeader(title: "ON AIR")
                    ForEach(vm.onAir) { p in row(p) }
                }
                if !vm.upNext.isEmpty {
                    RadioSectionHeader(title: "UP NEXT")
                    ForEach(vm.upNext) { p in row(p) }
                }
                if !vm.recordedShows.isEmpty {
                    RadioSectionHeader(title: "RECORDED SHOWS")
                    ForEach(vm.recordedShows) { p in row(p) }
                }
            }
            .padding(.bottom, 32)
        }
        .refreshable { await vm.load() }
    }

    private var stationHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nuru Radio").font(.fraunces(28, .semibold)).kerning(-0.5).foregroundStyle(.white)
            Text(vm.onAir.isEmpty ? "Off air right now — browse the schedule or replay a show."
                                  : "Broadcasting live now.")
                .font(.inter(12)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 60).padding(.bottom, 8)
    }

    private func row(_ p: RadioProgram) -> some View {
        NavigationLink(value: p) { RadioProgramRow(program: p) }.buttonStyle(.plain)
    }
}

// MARK: - Shared chrome

private struct RadioBackground: View {
    var body: some View {
        LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x060F1C)],
                       startPoint: .top, endPoint: .bottom).ignoresSafeArea()
    }
}

private struct RadioSectionHeader: View {
    let title: String
    var body: some View {
        Text(title).font(.inter(11, .bold)).kerning(1.4)
            .foregroundStyle(Nuru.gold.opacity(0.9))
            .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
    }
}

private struct RadioErrorState: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40)).foregroundStyle(Nuru.gold.opacity(0.7))
            Text("Couldn't tune in").font(.fraunces(20, .semibold)).foregroundStyle(.white)
            Text(message).font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center).padding(.horizontal, 48)
            Button(action: retry) {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(Nuru.gold, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct RadioEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 44)).foregroundStyle(Nuru.gold.opacity(0.7))
            Text("Off air right now").font(.fraunces(20, .semibold)).foregroundStyle(.white)
            Text("The Goodness Mission Radio will be back — check again soon.")
                .font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center).padding(.horizontal, 48)
        }
    }
}

/// Status pill: red LIVE / white "UP NEXT · Wed 7:30 PM" / gold RECORDED.
private struct RadioStatusPill: View {
    let program: RadioProgram
    var body: some View {
        HStack(spacing: 6) {
            if program.live {
                Circle().fill(.white).frame(width: 6, height: 6)
                Text("LIVE").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(.white)
            } else if program.status == "scheduled" {
                Icon(.clock, size: 10, color: .white)
                Text("UP NEXT\(program.scheduledAt.map { " · " + radioDate($0) } ?? "")")
                    .font(.inter(10, .bold)).kerning(1.2).foregroundStyle(.white)
            } else {
                Icon(.play, size: 10, color: Nuru.gold)
                Text("RECORDED").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(pillBackground, in: Capsule())
    }
    private var pillBackground: Color {
        if program.live { return Color(hex: 0xDC2626) }
        if program.status == "scheduled" { return Color.white.opacity(0.14) }
        return Nuru.gold.opacity(0.16)
    }
}

/// One station-directory row: artwork thumb, title, speaker · category, pill.
private struct RadioProgramRow: View {
    let program: RadioProgram
    var body: some View {
        HStack(spacing: 12) {
            thumb
            VStack(alignment: .leading, spacing: 3) {
                Text(program.title).font(.fraunces(15, .semibold)).foregroundStyle(.white)
                    .lineLimit(1)
                Text([program.speaker, program.category].compactMap { $0 }.joined(separator: " · "))
                    .font(.inter(11)).foregroundStyle(.white.opacity(0.55)).lineLimit(1)
            }
            Spacer(minLength: 8)
            RadioStatusPill(program: program)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private var thumb: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1628)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let a = program.artworkUrl, let u = URL(string: a) {
                CachedAsyncImage(url: u) { ph in
                    (ph.image ?? Image(systemName: "dot.radiowaves.left.and.right"))
                        .resizable().scaledToFill()
                }
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 20)).foregroundStyle(Nuru.gold.opacity(0.8))
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Program detail: the player + reactions + comments

@MainActor
final class RadioProgramModel: ObservableObject {
    @Published var playing = false
    @Published var counts: RadioReactionCounts?
    @Published var comments: [RadioComment] = []
    @Published var commentsLoading = true
    @Published var draft = ""
    @Published var sending = false
    private var player: AVPlayer?

    func loadComments(_ programId: String) async {
        comments = (try? await MemberAPI.radioComments(programId)) ?? comments
        commentsLoading = false
    }

    func togglePlay(_ program: RadioProgram) {
        guard let url = program.streamUrl else { return }
        if playing { player?.pause(); playing = false; return }
        if player == nil {
            // Radio must be heard even with the ring switch on silent.
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            try? AVAudioSession.sharedInstance().setActive(true)
            player = AVPlayer(url: url)
        }
        player?.play(); playing = true
    }

    func stop() { player?.pause(); player = nil; playing = false }

    func react(_ programId: String, _ kind: String) async {
        counts = (try? await MemberAPI.radioReact(programId, kind: kind)) ?? counts
    }

    /// Optimistic append: show the comment instantly, reconcile with the server
    /// row on success, roll back (restoring the draft) on failure.
    func sendComment(_ programId: String) async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        let optimistic = RadioComment(id: "local-\(UUID().uuidString)", memberId: "me", body: text,
                                      createdAt: ISO8601DateFormatter.nuru.string(from: Date()))
        comments.insert(optimistic, at: 0)   // server lists newest first
        draft = ""
        do {
            let saved = try await MemberAPI.addRadioComment(programId, body: text)
            if let i = comments.firstIndex(where: { $0.id == optimistic.id }) { comments[i] = saved }
        } catch {
            comments.removeAll { $0.id == optimistic.id }
            draft = text
        }
        sending = false
    }
}

struct RadioProgramDetailView: View {
    let program: RadioProgram
    @StateObject private var vm = RadioProgramModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            RadioBackground()
            ScrollView {
                VStack(spacing: 0) {
                    RadioDetailHeader(program: program)
                    RadioPlayControl(program: program, playing: vm.playing) { vm.togglePlay(program) }
                        .padding(.top, 24)
                    reactions.padding(.top, 22)
                    RadioCommentsSection(vm: vm, programId: program.id)
                        .padding(.top, 28)
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .overlay(alignment: .topLeading) {
            Button { vm.stop(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: .white).frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain).padding(.leading, 16).padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.loadComments(program.id) }
        .onDisappear { vm.stop() }
    }

    private var reactions: some View {
        HStack(spacing: 14) {
            RadioReactionChip(emoji: "❤️", count: vm.counts?.heart) { Task { await vm.react(program.id, "heart") } }
            RadioReactionChip(emoji: "🙏", count: vm.counts?.amen) { Task { await vm.react(program.id, "amen") } }
            RadioReactionChip(emoji: "🔥", count: vm.counts?.fire) { Task { await vm.react(program.id, "fire") } }
        }
    }
}

/// Artwork + pill + serif title + speaker · category + description.
private struct RadioDetailHeader: View {
    let program: RadioProgram
    var body: some View {
        VStack(spacing: 0) {
            artwork.padding(.top, 64)
            RadioStatusPill(program: program).padding(.top, 20)
            Text(program.title).font(.fraunces(26, .semibold)).kerning(-0.5).foregroundStyle(.white)
                .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 10)
            Text([program.speaker, program.category].compactMap { $0 }.joined(separator: " · "))
                .font(.inter(13)).foregroundStyle(.white.opacity(0.6)).padding(.top, 4)
            if let d = program.description, !d.isEmpty {
                Text(d).font(.inter(12)).foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center).lineLimit(3)
                    .padding(.horizontal, 40).padding(.top, 8)
            }
        }
    }

    private var artwork: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1628)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let a = program.artworkUrl, let u = URL(string: a) {
                CachedAsyncImage(url: u) { ph in
                    (ph.image ?? Image(systemName: "dot.radiowaves.left.and.right"))
                        .resizable().scaledToFill()
                }
            } else {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 64)).foregroundStyle(Nuru.gold.opacity(0.8))
            }
        }
        .frame(width: 220, height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 18)
    }
}

/// The gold play/pause. Disabled with a hint when there is nothing to stream yet
/// (scheduled shows before airtime, or ended shows with no recording).
private struct RadioPlayControl: View {
    let program: RadioProgram
    let playing: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: toggle) {
                Image(systemName: playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 30)).foregroundStyle(Nuru.navy)
                    .frame(width: 84, height: 84)
                    .background(LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .shadow(color: Nuru.gold.opacity(0.5), radius: 20, y: 10)
            }
            .buttonStyle(.plain)
            .disabled(program.streamUrl == nil)
            .opacity(program.streamUrl == nil ? 0.4 : 1)
            if program.streamUrl == nil {
                Text(program.status == "scheduled" ? "Playback opens when the show goes live."
                                                   : "No recording available for this show.")
                    .font(.inter(11)).foregroundStyle(.white.opacity(0.45))
            }
        }
    }
}

private struct RadioReactionChip: View {
    let emoji: String
    let count: Int?
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(emoji).font(.system(size: 16))
                if let c = count, c > 0 { Text("\(c)").font(.inter(12, .bold)).foregroundStyle(.white) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// Comments live on every visible program — scheduled shows included, so members
/// can hype what's coming. Composer posts with a client_event_id (idempotent).
private struct RadioCommentsSection: View {
    @ObservedObject var vm: RadioProgramModel
    let programId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("COMMENTS").font(.inter(11, .bold)).kerning(1.4)
                .foregroundStyle(Nuru.gold.opacity(0.9))
                .padding(.horizontal, 20).padding(.bottom, 10)
            composer.padding(.horizontal, 16).padding(.bottom, 12)
            if vm.commentsLoading {
                ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 16)
            } else if vm.comments.isEmpty {
                Text("No comments yet — be the first to say something.")
                    .font(.inter(12)).foregroundStyle(.white.opacity(0.45))
                    .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 14)
            } else {
                ForEach(vm.comments) { c in RadioCommentRow(comment: c) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("", text: $vm.draft, prompt: Text("Say something…")
                .foregroundColor(.white.opacity(0.35)))
                .font(.inter(13)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .submitLabel(.send)
                .onSubmit { Task { await vm.sendComment(programId) } }
            Button { Task { await vm.sendComment(programId) } } label: {
                Icon(.send, size: 16, color: Nuru.navy)
                    .frame(width: 38, height: 38)
                    .background(Nuru.gold, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.sending || vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
        }
    }
}

/// Compact comment row. Comments carry member_id only (no author-name join on
/// the backend select yet), so the byline is a generic "Member".
private struct RadioCommentRow: View {
    let comment: RadioComment
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Icon(.user, size: 13, color: Nuru.gold)
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Member").font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.7))
                    Text(timeAgo(comment.createdAt)).font(.inter(10)).foregroundStyle(.white.opacity(0.35))
                }
                Text(comment.body).font(.inter(13)).foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.vertical, 7)
    }
}

// MARK: - Helpers

private func radioDate(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let f = DateFormatter(); f.dateFormat = "EEE h:mm a"
    return f.string(from: d)
}
