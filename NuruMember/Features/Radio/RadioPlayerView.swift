// Nuru Radio — the full station experience over the backend radio module.
//
// GET /radio/programs (listPublic) returns every visible non-draft program,
// live-first. The station screen groups them: ON AIR (live), UP NEXT (scheduled,
// soonest first) and RECORDED SHOWS (ended + audio_url — playable anytime).
//
// Tapping a row (or arriving while a program is live — we auto-open it) shows
// the LIVE STUDIO: playback through RadioCenter.shared (the app-wide engine that
// keeps audio going after this page closes and surfaces it in the Dynamic
// Island / Lock Screen), animated broadcast rings + equalizer, studio lamps,
// REAL reactions (POST /radio/programs/{id}/react — idempotent per
// client_event_id) with a floating-emoji burst, and a REAL live chat
// (GET/POST /radio/programs/{id}/comments, polled every 5s while open).
import SwiftUI

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

struct RadioReactionCounts: Decodable, Sendable {
    let heart: Int; let amen: Int; let fire: Int

    /// Optimistic +1 for a kind — reconciled by the POST /react response.
    func bumped(_ kind: String) -> RadioReactionCounts {
        RadioReactionCounts(heart: heart + (kind == "heart" ? 1 : 0),
                            amen: amen + (kind == "amen" ? 1 : 0),
                            fire: fire + (kind == "fire" ? 1 : 0))
    }
}

/// One comment row. The backend select (radio service listComments) returns
/// id/program_id/member_id/body/created_at only — NO author-name join yet, so
/// the UI renders comments anonymously ("Member"; own rows show "You").
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
    /// Everything else — aired shows with no recording (and any unknown status).
    /// Still listed so the station never looks empty while programs exist; members
    /// can open them to read/leave comments even though there's nothing to play.
    var pastShows: [RadioProgram] {
        programs.filter { !$0.live && $0.status != "scheduled" && !$0.recorded }
    }

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
                RadioStudioView(program: p)
            }
        }
        .task {
            // Reopened from the mini player while tuned → land back in that studio.
            if !autoOpened, let tuned = RadioCenter.shared.program {
                autoOpened = true
                path.append(tuned)
            }
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
                if !vm.pastShows.isEmpty {
                    RadioSectionHeader(title: "PAST SHOWS")
                    ForEach(vm.pastShows) { p in row(p) }
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
            } else if program.recorded {
                Icon(.play, size: 10, color: Nuru.gold)
                Text("RECORDED").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
            } else {
                Text("AIRED").font(.inter(10, .bold)).kerning(1.2)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 5)
        .background(pillBackground, in: Capsule())
    }
    private var pillBackground: Color {
        if program.live { return Color(hex: 0xDC2626) }
        if program.status == "scheduled" { return Color.white.opacity(0.14) }
        return program.recorded ? Nuru.gold.opacity(0.16) : Color.white.opacity(0.10)
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

// MARK: - Studio model — real reactions + real chat (polled)

@MainActor
final class RadioStudioModel: ObservableObject {
    /// Last-known REAL counts. nil until the first successful POST /react —
    /// the read endpoints don't return counts, and we never invent numbers.
    @Published var counts: RadioReactionCounts?
    /// Newest-first (server order). `chat` reverses for bottom-anchored display.
    @Published var comments: [RadioComment] = []
    @Published var commentsLoading = true
    @Published var draft = ""
    @Published var sending = false

    private var programId = ""

    /// Chat display order — oldest → newest, newest at the bottom.
    var chat: [RadioComment] { comments.reversed() }

    /// Loads comments, then keeps polling every ~5s. Run from a `.task` so the
    /// loop is cancelled automatically when the studio page disappears.
    func start(_ id: String) async {
        programId = id
        while !Task.isCancelled {
            await refreshComments()
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    private func refreshComments() async {
        guard let fresh = try? await MemberAPI.radioComments(programId) else {
            commentsLoading = false
            return
        }
        // Merge by id — keep optimistic local rows the server hasn't returned yet.
        let serverIds = Set(fresh.map(\.id))
        let pendingLocal = comments.filter { $0.id.hasPrefix("local-") && !serverIds.contains($0.id) }
        comments = pendingLocal + fresh
        commentsLoading = false
    }

    /// Optimistic bump of the last-known counts, then reconcile with the POST
    /// response (idempotent server-side — a fresh UUID client_event_id per tap).
    func react(_ kind: String) async {
        let previous = counts
        if let c = counts { counts = c.bumped(kind) }
        do { counts = try await MemberAPI.radioReact(programId, kind: kind) }
        catch { counts = previous }
    }

    /// Optimistic append: show the comment instantly, reconcile with the server
    /// row on success, roll back (restoring the draft) on failure.
    func sendComment() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        let optimistic = RadioComment(id: "local-\(UUID().uuidString)", memberId: "me", body: text,
                                      createdAt: ISO8601DateFormatter.nuru.string(from: Date()))
        comments.insert(optimistic, at: 0)   // storage is newest-first
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

// MARK: - The LIVE STUDIO (re-imagined player)

struct RadioStudioView: View {
    let program: RadioProgram
    @StateObject private var vm = RadioStudioModel()
    @ObservedObject private var center = RadioCenter.shared
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    private var tuned: Bool { center.program?.id == program.id }
    private var playingHere: Bool { tuned && center.playing }

    var body: some View {
        ZStack {
            StudioBackground()
            VStack(spacing: 0) {
                StudioHeader(live: program.live) { dismiss() }   // minimize — audio keeps playing
                ScrollView {
                    VStack(spacing: 0) {
                        StudioHero(program: program, playing: playingHere)
                        EqualizerStrip(playing: playingHere)
                            .padding(.top, 18).padding(.horizontal, 48)
                        StudioTransport(program: program)
                            .padding(.top, 20)
                        StudioReactionBar(vm: vm)
                            .padding(.top, 24)
                        LiveChatSection(vm: vm, myId: auth.profile?.userId)
                            .padding(.top, 26).padding(.horizontal, 16)
                    }
                    .padding(.bottom, 28)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // Auto-join a live broadcast when nothing else is tuned — the ON AIR
            // card says "Listen live", so land already listening.
            if program.live, center.program == nil, program.streamUrl != nil {
                center.tune(program)
            }
            await vm.start(program.id)   // comments load + 5s poll, cancelled on leave
        }
    }
}

/// Deep-navy studio dark with a faint gold booth glow up top.
private struct StudioBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x060F1C), Color(hex: 0x04090F)],
                           startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Nuru.gold.opacity(0.10), .clear],
                           center: UnitPoint(x: 0.5, y: 0.14), startRadius: 0, endRadius: 340)
        }
        .ignoresSafeArea()
    }
}

/// Minimize chevron · centered NURU RADIO wordmark · studio-lamp cluster.
private struct StudioHeader: View {
    let live: Bool
    let minimize: () -> Void
    var body: some View {
        HStack {
            Button(action: minimize) {
                Icon(.chevronDown, size: 18, color: .white)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Minimize player — audio keeps playing")
            Spacer(minLength: 0)
            StudioLamps(live: live)
        }
        .overlay {
            VStack(spacing: 1) {
                Text("NURU RADIO").font(.inter(12, .bold)).kerning(3).foregroundStyle(.white)
                Text("THE GOODNESS MISSION").font(.inter(7, .semibold)).kerning(1.8)
                    .foregroundStyle(Nuru.gold.opacity(0.8))
            }
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
    }
}

/// The booth lamps: red (pulses while LIVE), amber (steady — connected),
/// green (steady — on-air signal), plus the micro-caps status word.
private struct StudioLamps: View {
    let live: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                lamp(Color(hex: 0xEF4444), on: live, pulsing: live)
                lamp(Color(hex: 0xF59E0B), on: true, pulsing: false)
                lamp(Color(hex: 0x22C55E), on: live, pulsing: false)
            }
            Text(live ? "ON AIR" : "STUDIO").font(.inter(9, .bold)).kerning(1.44)
                .foregroundStyle(live ? .white : .white.opacity(0.55))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
        .onAppear {
            guard live, !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private func lamp(_ color: Color, on: Bool, pulsing: Bool) -> some View {
        Circle().fill(on ? color : color.opacity(0.22))
            .frame(width: 8, height: 8)
            .shadow(color: on ? color.opacity(0.9) : .clear, radius: 4)
            .opacity(pulsing ? (pulse ? 0.3 : 1) : 1)
    }
}

/// Artwork inside expanding broadcast rings, then pill + serif title + meta.
private struct StudioHero: View {
    let program: RadioProgram
    let playing: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                BroadcastRings(playing: playing)
                StudioArtwork(program: program)
            }
            .frame(width: 300, height: 300)
            .padding(.top, 4)
            RadioStatusPill(program: program).padding(.top, 2)
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
}

/// 2–3 concentric rings expanding and fading out from the artwork while
/// playing; hidden when paused; disabled entirely under reduce-motion.
private struct BroadcastRings: View {
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let period = 2.6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing || reduceMotion)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let phase = ((t / period) + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .stroke(Nuru.gold.opacity((1 - phase) * 0.35), lineWidth: 1.5)
                        .frame(width: 206, height: 206)
                        .scaleEffect(1 + phase * 0.45)
                }
            }
        }
        .opacity(playing && !reduceMotion ? 1 : 0)
        .animation(.easeInOut(duration: 0.4), value: playing)
        .allowsHitTesting(false)
    }
}

private struct StudioArtwork: View {
    let program: RadioProgram
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1628)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let a = program.artworkUrl, let u = URL(string: a) {
                CachedAsyncImage(url: u) { ph in
                    if let img = ph.image { img.resizable().scaledToFill() }
                    else { glyph }
                }
            } else {
                glyph
            }
        }
        .frame(width: 196, height: 196)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(Color.white.opacity(0.10), lineWidth: 1))
        .shadow(color: .black.opacity(0.55), radius: 26, y: 14)
    }
    private var glyph: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 56)).foregroundStyle(Nuru.gold.opacity(0.85))
    }
}

/// Slim gold equalizer — bars dance while playing, settle into a gentle static
/// arc when paused (and always under reduce-motion). Pure decoration.
private struct EqualizerStrip: View {
    let playing: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let barCount = 28

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: !playing || reduceMotion)) { ctx in
            let tick = Int(ctx.date.timeIntervalSinceReferenceDate / 0.16)
            HStack(alignment: .center, spacing: 3) {
                ForEach(0..<barCount, id: \.self) { i in
                    Capsule()
                        .fill(LinearGradient(colors: [Nuru.goldHi, Nuru.gold, Nuru.goldLo],
                                             startPoint: .top, endPoint: .bottom))
                        .frame(width: 3, height: barHeight(i, tick))
                        .animation(.easeInOut(duration: 0.15), value: tick)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .opacity(playing ? 1 : 0.35)
        }
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int, _ tick: Int) -> CGFloat {
        guard playing, !reduceMotion else { return frozenHeight(i) }
        // Cheap deterministic hash of (bar, tick) → stable pseudo-random dance.
        var h = UInt64(bitPattern: Int64(i &* 2654435761 &+ tick &* 40503))
        h = (h ^ (h >> 13)) &* 0x9E3779B97F4A7C15
        let unit = Double((h >> 32) & 0xFFFF) / 65535.0
        return CGFloat(6 + unit * 22)
    }

    private func frozenHeight(_ i: Int) -> CGFloat {
        let x = Double(i) / Double(barCount - 1)
        return CGFloat(8 + 8 * sin(x * .pi))
    }
}

/// Big gold play/pause disc + the live caption (or a scrubber for recordings).
private struct StudioTransport: View {
    let program: RadioProgram
    @ObservedObject private var center = RadioCenter.shared

    init(program: RadioProgram) { self.program = program }

    private var tuned: Bool { center.program?.id == program.id }
    private var playingHere: Bool { tuned && center.playing }

    var body: some View {
        VStack(spacing: 14) {
            Button {
                if tuned { center.togglePlay() } else { center.tune(program) }
            } label: {
                Image(systemName: playingHere ? "pause.fill" : "play.fill")
                    .font(.system(size: 30)).foregroundStyle(Nuru.navy)
                    .offset(x: playingHere ? 0 : 2)
                    .frame(width: 84, height: 84)
                    .background(LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.22), lineWidth: 4).padding(3))
                    .shadow(color: Nuru.gold.opacity(playingHere ? 0.55 : 0.35), radius: 22, y: 10)
            }
            .buttonStyle(.plain)
            .disabled(program.streamUrl == nil)
            .opacity(program.streamUrl == nil ? 0.4 : 1)

            if program.streamUrl == nil {
                Text(program.status == "scheduled" ? "Playback opens when the show goes live."
                                                   : "No recording available for this show.")
                    .font(.inter(11)).foregroundStyle(.white.opacity(0.45))
            } else if program.live {
                HStack(spacing: 6) {
                    Circle().fill(Color(hex: 0xDC2626)).frame(width: 6, height: 6)
                    Text(playingHere ? "LIVE — you're listening with the church"
                                     : "LIVE — tap play to join the broadcast")
                        .font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.75))
                }
            } else if tuned {
                RecordedScrubber()
            } else {
                Text("Recorded show — tap play to listen")
                    .font(.inter(11)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(.horizontal, 36)
    }
}

/// Timeline scrubber for recorded shows (live streams get the caption instead).
private struct RecordedScrubber: View {
    @ObservedObject private var center = RadioCenter.shared
    @State private var scrubbing = false
    @State private var scrubValue: Double = 0

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubValue : min(center.currentTime, max(center.duration, 1)) },
                    set: { scrubValue = $0 }
                ),
                in: 0...max(center.duration, 1)
            ) { editing in
                if editing { scrubbing = true }
                else { center.seek(to: scrubValue); scrubbing = false }
            }
            .tint(Nuru.gold)
            .disabled(center.duration <= 0)
            HStack {
                Text(clock(scrubbing ? scrubValue : center.currentTime))
                Spacer()
                Text(clock(center.duration))
            }
            .font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.5))
        }
    }

    private func clock(_ s: Double) -> String {
        guard s.isFinite, s > 0 else { return "0:00" }
        let t = Int(s)
        if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
        return String(format: "%d:%02d", t / 60, t % 60)
    }
}

// MARK: - Reactions (real counts + floating-emoji delight)

private struct StudioReactionBar: View {
    @ObservedObject var vm: RadioStudioModel
    var body: some View {
        HStack(spacing: 14) {
            StudioReactionChip(emoji: "❤️", count: vm.counts?.heart) { Task { await vm.react("heart") } }
            StudioReactionChip(emoji: "🙏", count: vm.counts?.amen) { Task { await vm.react("amen") } }
            StudioReactionChip(emoji: "🔥", count: vm.counts?.fire) { Task { await vm.react("fire") } }
        }
    }
}

private struct EmojiParticle: Identifiable {
    let id = UUID()
    let xJitter: CGFloat
    let drift: CGFloat
    let delay: Double
    let scale: CGFloat
}

/// One reaction chip. Tapping fires the REAL react POST (via `action`) and
/// spawns 3–5 emoji copies that drift up and fade (skipped under reduce-motion).
private struct StudioReactionChip: View {
    let emoji: String
    let count: Int?
    let action: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var particles: [EmojiParticle] = []
    @State private var taps = 0

    var body: some View {
        Button {
            taps += 1
            action()
            spawnBurst()
        } label: {
            HStack(spacing: 6) {
                Text(emoji).font(.system(size: 17))
                if let c = count, c > 0 {
                    Text("\(c)").font(.inter(12, .bold)).foregroundStyle(.white)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(Color.white.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.16), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            ZStack {
                ForEach(particles) { p in FloatingEmoji(emoji: emoji, particle: p) }
            }
            .allowsHitTesting(false)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    private func spawnBurst() {
        guard !reduceMotion else { return }
        let burst = (0..<Int.random(in: 3...5)).map { _ in
            EmojiParticle(xJitter: .random(in: -28...28), drift: .random(in: 64...112),
                          delay: .random(in: 0...0.15), scale: .random(in: 0.8...1.35))
        }
        particles.append(contentsOf: burst)
        let ids = Set(burst.map(\.id))
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            particles.removeAll { ids.contains($0.id) }
        }
    }
}

private struct FloatingEmoji: View {
    let emoji: String
    let particle: EmojiParticle
    @State private var up = false
    var body: some View {
        Text(emoji)
            .font(.system(size: 18))
            .scaleEffect(up ? particle.scale : 0.7)
            .offset(x: up ? particle.xJitter : 0, y: up ? -particle.drift : -6)
            .opacity(up ? 0 : 0.95)
            .onAppear {
                withAnimation(.easeOut(duration: 1.2).delay(particle.delay)) { up = true }
            }
    }
}

// MARK: - Live chat (real comments, newest at the bottom, 5s poll)

private struct LiveChatSection: View {
    @ObservedObject var vm: RadioStudioModel
    let myId: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(Color(hex: 0xDC2626)).frame(width: 6, height: 6)
                Text("LIVE CHAT").font(.inter(11, .bold)).kerning(1.4)
                    .foregroundStyle(Nuru.gold.opacity(0.9))
                Spacer(minLength: 0)
                if !vm.comments.isEmpty {
                    Text("\(vm.comments.count)").font(.inter(10, .bold)).foregroundStyle(.white.opacity(0.6))
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Color.white.opacity(0.08), in: Capsule())
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 8)

            chatScroll

            StudioComposer(vm: vm)
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 12)
        }
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    /// The chat panel scrolls internally (bottom-anchored like a chat thread),
    /// so polled inserts never yank the page itself around.
    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if vm.commentsLoading && vm.comments.isEmpty {
                        ProgressView().tint(Nuru.gold)
                            .frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else if vm.comments.isEmpty {
                        VStack(spacing: 6) {
                            Text("💬").font(.system(size: 22))
                            Text("No messages yet — say something to the studio.")
                                .font(.inter(12)).foregroundStyle(.white.opacity(0.45))
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                    } else {
                        ForEach(vm.chat) { c in
                            StudioChatRow(comment: c, mine: c.memberId == myId || c.id.hasPrefix("local-"))
                                .id(c.id)
                        }
                    }
                    Color.clear.frame(height: 1).id("chat-bottom")
                }
                .padding(.vertical, 4)
            }
            .frame(height: 300)
            .onChange(of: vm.comments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo("chat-bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("chat-bottom", anchor: .bottom) }
        }
    }
}

/// One chat line: monogram circle · name ("You" for own rows) · relative time · body.
private struct StudioChatRow: View {
    let comment: RadioComment
    let mine: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            monogram
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(mine ? "You" : "Member").font(.inter(11, .semibold))
                        .foregroundStyle(mine ? Nuru.gold : .white.opacity(0.7))
                    Text(timeAgo(comment.createdAt)).font(.inter(10)).foregroundStyle(.white.opacity(0.35))
                }
                Text(comment.body).font(.inter(13)).foregroundStyle(.white.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 7)
    }

    private var monogram: some View {
        Text(mine ? "Y" : "M")
            .font(.inter(11, .bold)).foregroundStyle(mine ? Nuru.navy : Nuru.gold)
            .frame(width: 28, height: 28)
            .background(mine ? AnyShapeStyle(Nuru.gold) : AnyShapeStyle(Color.white.opacity(0.10)), in: Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
    }
}

/// Rounded "Say something…" field + gold send disc (disabled while empty).
private struct StudioComposer: View {
    @ObservedObject var vm: RadioStudioModel

    private var empty: Bool { vm.draft.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        HStack(spacing: 10) {
            TextField("", text: $vm.draft, prompt: Text("Say something…")
                .foregroundColor(.white.opacity(0.35)))
                .font(.inter(13)).foregroundStyle(.white)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Color.white.opacity(0.08), in: Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                .submitLabel(.send)
                .onSubmit { Task { await vm.sendComment() } }
            Button { Task { await vm.sendComment() } } label: {
                Icon(.send, size: 16, color: Nuru.navy)
                    .frame(width: 38, height: 38)
                    .background(Nuru.gold, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.sending || empty)
            .opacity(empty ? 0.4 : 1)
        }
    }
}

// MARK: - Helpers

private func radioDate(_ iso: String) -> String {
    guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let f = DateFormatter(); f.dateFormat = "EEE h:mm a"
    return f.string(from: d)
}
