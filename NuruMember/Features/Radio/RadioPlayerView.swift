// Nuru Radio — the immersive LIVE RADIO screen (Figma "LiveRadioScreen" make).
//
// One screen, no pushes: an ambient artwork backdrop with breathing gold/indigo
// glows, the ON AIR centerpiece (red-ringed + shimmering while broadcasting,
// grayscale "OFF AIR" otherwise), transport (mute · 78pt gold play/pause ·
// sleep timer — or a "Remind me when we're live" CTA off-air), REAL stat chips,
// and glass segmented tabs: Live (reactions + chat) · Recordings · Schedule.
//
// Data is entirely real: GET /radio/programs (re-polled every 45s so going live
// flips the screen without reopening), POST /radio/programs/{id}/react
// (idempotent per client_event_id, optimistic counts), GET/POST comments
// (5s poll while open, optimistic insert with rollback). Playback routes
// through RadioCenter.shared so audio, the Dynamic Island and the lock screen
// all keep working when this page closes.
import SwiftUI
import UIKit
import UserNotifications

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

    var total: Int { heart + amen + fire }

    /// Optimistic +1 for a kind — reconciled by the POST /react response.
    func bumped(_ kind: String) -> RadioReactionCounts {
        RadioReactionCounts(heart: heart + (kind == "heart" ? 1 : 0),
                            amen: amen + (kind == "amen" ? 1 : 0),
                            fire: fire + (kind == "fire" ? 1 : 0))
    }
}

/// One comment row. The backend join now carries the author's name/avatar;
/// both stay optional so older payloads (and optimistic local rows) still
/// decode — the UI falls back to "Member" only when the name is absent.
struct RadioComment: Decodable, Sendable, Identifiable {
    let id: String
    let memberId: String
    let body: String
    let createdAt: String
    var authorName: String?
    var authorAvatarUrl: String?
}

// MARK: - Design tokens (the TSX's exact hexes; Nuru.* where they match)

private enum RadioUX {
    static let navyDeep  = Color(hex: 0x060F1C)                 // NAVY_DEEP
    static let gold      = Nuru.gold                            // #c89b3c
    static let goldLight = Nuru.goldLight                       // #e6c068
    static let goldDeep  = Color(hex: 0xB6862F)                 // gradient tail
    static let glass       = Color.white.opacity(0.06)          // GLASS
    static let glassBorder = Color.white.opacity(0.10)          // GLASS_BORDER
    static let red     = Color(hex: 0xEF4444)
    static let redDeep = Color(hex: 0xDC2626)
    static let redSoft = Color(hex: 0xFCA5A5)
    static let indigo     = Color(hex: 0x4338CA)
    static let indigoSoft = Color(hex: 0x818CF8)
    static let green = Color(hex: 0x16A34A)

    /// The design's ON AIR neon photograph — centerpiece fallback artwork.
    static let onAirNeon = URL(string:
        "https://images.unsplash.com/photo-1760895653496-b28ed02f3705?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080")

    static var goldGradient: LinearGradient {
        LinearGradient(colors: [gold, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Stable 2-color monogram gradients (the design's palette pairs).
    static let monogramPairs: [(Color, Color)] = [
        (Color(hex: 0x6366F1), Color(hex: 0x4338CA)),   // indigo
        (Color(hex: 0x16A34A), Color(hex: 0x15803D)),   // green
        (Color(hex: 0xDC2626), Color(hex: 0x991B1B)),   // red
        (Color(hex: 0xC89B3C), Color(hex: 0x8A6711)),   // gold (also "mine")
    ]

    /// Deterministic palette pick per author name.
    static func monogram(for name: String) -> (Color, Color) {
        var h: UInt64 = 5381
        for b in name.utf8 { h = (h &* 33) &+ UInt64(b) }
        return monogramPairs[Int(h % UInt64(monogramPairs.count))]
    }
}

// MARK: - Station model — programs + 45s re-poll while the screen is open

@MainActor
final class LiveRadioModel: ObservableObject {
    @Published var programs: [RadioProgram] = []
    @Published var loading = true
    @Published var errorText: String?

    /// The broadcast on air right now (server sends live-first).
    var liveProgram: RadioProgram? { programs.first { $0.live } }
    /// Scheduled shows, soonest first (server order is newest-first, so re-sort).
    var scheduled: [RadioProgram] {
        programs.filter { $0.status == "scheduled" && !$0.live }
            .sorted { ($0.scheduledAt ?? "") < ($1.scheduledAt ?? "") }
    }
    var nextScheduled: RadioProgram? { scheduled.first }
    /// Ended shows WITH a hosted recording — playable anytime (server order kept).
    var recordedShows: [RadioProgram] { programs.filter { $0.recorded } }
    /// Everything already aired (recorded or not) — the schedule's history rows.
    var aired: [RadioProgram] {
        programs.filter { !$0.live && $0.status != "scheduled" }
    }

    /// Load, then keep re-polling every 45s. Run from `.task` so the loop is
    /// cancelled automatically when the screen closes — going live mid-visit
    /// flips the whole screen without reopening.
    func start() async {
        while !Task.isCancelled {
            await load()
            try? await Task.sleep(nanoseconds: 45_000_000_000)
        }
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

// MARK: - Live-tab model — real reactions + real chat (5s poll)

@MainActor
final class LiveChatModel: ObservableObject {
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

    /// Loads comments, then keeps polling every ~5s. Run from a `.task(id:)`
    /// keyed by the live program so the loop cancels/restarts on change.
    func start(_ id: String) async {
        if programId != id {
            programId = id
            counts = nil
            comments = []
            commentsLoading = true
        }
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
    /// response (idempotent server-side — a fresh client_event_id per tap).
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

// MARK: - Entry — the immersive LiveRadioScreen (fullScreenCover from Home)

private enum RadioTab { case live, recordings, schedule }

struct RadioPlayerView: View {
    @StateObject private var vm = LiveRadioModel()
    @StateObject private var chat = LiveChatModel()
    @ObservedObject private var center = RadioCenter.shared
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var tab: RadioTab = .live
    @State private var autoTabbed = false
    @State private var autoTuned = false

    // MARK: Derived state

    private var live: RadioProgram? { vm.liveProgram }
    private var isLive: Bool { live != nil }
    /// A non-live tune (a recording) — takes over the centerpiece context so
    /// reopening from the island lands back on what's actually playing.
    private var nowRec: RadioProgram? {
        guard let p = center.program, !p.live else { return nil }
        return p
    }
    /// Audio is actually flowing — drives the glow, shimmer and play rings.
    private var spinning: Bool { center.playing }

    var body: some View {
        // The backdrop ignores safe areas on its own; the header/content column
        // stays INSIDE them (standard layout — matching Android). No manual
        // UIKit inset math: reading the key window's insets mis-sized the
        // screen when presented over another surface, shoving the back button
        // off-screen and the whole column off-center.
        ZStack {
            LiveRadioBackdrop(artwork: backdropArtwork)
            VStack(spacing: 0) {
                header
                content
            }
        }
        .preferredColorScheme(.dark)
        .task { await vm.start() }                                // 45s program poll
        .task(id: live?.id) {                                     // chat follows the live show
            if let id = live?.id { await chat.start(id) }
        }
        .onChange(of: vm.loading) { _, isLoading in
            guard !isLoading, !autoTabbed else { return }
            autoTabbed = true
            // Land where the moment is: live tab on air (design default),
            // recordings when reopened mid-recording, else the schedule.
            if nowRec != nil { tab = .recordings }
            else { tab = isLive ? .live : .schedule }
            // Auto-join a live broadcast when nothing else is tuned.
            if !autoTuned, let l = live, center.program == nil, l.streamUrl != nil {
                autoTuned = true
                center.tune(l)
            }
        }
    }

    private var backdropArtwork: URL? {
        if let s = nowRec?.artworkUrl ?? live?.artworkUrl, let u = URL(string: s) { return u }
        return RadioUX.onAirNeon
    }

    // MARK: Header — glass back · live dot + wordmark · glass bell

    private var header: some View {
        HStack {
            GlassSquareButton(sfSymbol: nil, lucide: .chevronLeft) {
                Haptics.tap()
                dismiss()
            }
            .accessibilityLabel("Back")
            Spacer(minLength: 0)
            GlassSquareButton(sfSymbol: nil, lucide: .bell, iconSize: 18, dot: true) {
                Haptics.tap()
                dismiss()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .nuruOpenNotifications, object: nil)
                }
            }
            .accessibilityLabel("Notifications")
        }
        .overlay {
            HStack(spacing: 6) {
                if isLive { PulsingDot(color: RadioUX.red, size: 6) }
                Text("NURU RADIO").font(.inter(11, .bold)).kerning(3.1)
                    .foregroundStyle(RadioUX.gold)
            }
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 8)
    }

    // MARK: Scroll content

    @ViewBuilder private var content: some View {
        if vm.loading && vm.programs.isEmpty {
            Spacer()
            ProgressView().tint(RadioUX.gold)
            Spacer()
        } else if let err = vm.errorText, vm.programs.isEmpty {
            Spacer()
            offAirError(err)
            Spacer()
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    LiveCenterpiece(live: isLive, spinning: spinning, artwork: centerpieceArtwork)
                        .padding(.top, 12)
                    titles
                    progressLine.padding(.top, 20)
                    transport.padding(.top, 20)
                    if isLive { statChips.padding(.top, 20) }
                    segmentedTabs.padding(.top, 24)
                    tabContent.padding(.top, 16)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var centerpieceArtwork: URL? {
        if let s = live?.artworkUrl, let u = URL(string: s) { return u }
        return RadioUX.onAirNeon
    }

    private func offAirError(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 40)).foregroundStyle(RadioUX.gold.opacity(0.7))
            Text("Couldn't tune in").font(.fraunces(20, .semibold)).foregroundStyle(.white)
            Text(message).font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center).padding(.horizontal, 48)
            Button {
                Haptics.tap()
                Task { await vm.load() }
            } label: {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 22).padding(.vertical, 10)
                    .background(RadioUX.gold, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
    }

    // MARK: Titles — kicker · Fraunces title · host line

    private var titles: some View {
        VStack(spacing: 0) {
            Text(kickerText)
                .font(.inter(9, .bold)).kerning(2.0)
                .foregroundStyle(RadioUX.goldLight)
                .padding(.top, 24)
            Text(titleText)
                .font(.fraunces(24, .semibold)).kerning(-0.48)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            if let host = hostText, !host.isEmpty {
                Text(host)
                    .font(.inter(13, .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.top, 4)
            }
        }
    }

    private var kickerText: String {
        if nowRec != nil { return "RECORDING" }
        if let l = live, !l.category.trimmingCharacters(in: .whitespaces).isEmpty {
            return l.category.uppercased()
        }
        return "NURU PLACE RADIO"
    }

    private var titleText: String {
        if let r = nowRec { return r.title }
        if let l = live { return l.title }
        return "We're off air right now"
    }

    private var hostText: String? {
        if let r = nowRec { return r.speaker }
        if let l = live { return l.speaker }
        if let next = vm.nextScheduled, let when = radioBackAt(next.scheduledAt) {
            return "Back at \(when)"
        }
        return nil
    }

    // MARK: Progress / status line

    @ViewBuilder private var progressLine: some View {
        if nowRec != nil {
            RecordingProgressLine()
        } else if isLive {
            LiveSweepLine(tunedAt: center.tunedAt)
        } else if let next = vm.nextScheduled, let when = radioClockLabel(next.scheduledAt) {
            (Text("Next up · ")
             + Text(next.title).font(.inter(12, .bold)).foregroundStyle(RadioUX.goldLight)
             + Text(" at \(when)"))
                .font(.inter(12))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Transport — mute · 78pt gold play/pause · sleep (or remind CTA)

    @ViewBuilder private var transport: some View {
        if isLive || nowRec != nil {
            LiveTransportRow(live: live, nowRec: nowRec, spinning: spinning)
        } else if let next = vm.nextScheduled, next.scheduledAt != nil {
            RemindMeCTA(next: next)
        }
    }

    // MARK: Stat chips (live only — REAL data, chips omitted when unknown)

    private var statChips: some View {
        HStack(spacing: 8) {
            if let n = live?.peakListeners, n > 0 {
                StatChip(lucide: .users, value: n.formatted(), label: "LISTENING")
            }
            if let started = radioClockLabel(live?.scheduledAt) {
                StatChip(lucide: .clock, value: started, label: "STARTED")
            }
            StatChip(lucide: .globe, value: "Worldwide", label: "REACH")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Segmented tabs — glass pill, gold-gradient active

    private var segmentedTabs: some View {
        HStack(spacing: 4) {
            tabButton(.live, label: isLive ? "Live" : "Now")
            tabButton(.recordings, label: "Recordings")
            tabButton(.schedule, label: "Schedule")
        }
        .padding(4)
        .background(RadioUX.glass, in: Capsule())
        .overlay(Capsule().stroke(RadioUX.glassBorder, lineWidth: 1))
    }

    private func tabButton(_ t: RadioTab, label: String) -> some View {
        let on = tab == t
        return Button {
            Haptics.selection()
            withAnimation(.easeOut(duration: 0.25)) { tab = t }
        } label: {
            Text(label)
                .font(.inter(11, on ? .bold : .semibold))
                .foregroundStyle(on ? Nuru.navy : .white.opacity(0.6))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if on { Capsule().fill(RadioUX.goldGradient) }
                }
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private var tabContent: some View {
        Group {
            switch tab {
            case .live:
                LiveTabView(live: live, chat: chat, myId: auth.profile?.userId)
            case .recordings:
                RecordingsTabView(recordings: vm.recordedShows)
            case .schedule:
                ScheduleTabView(live: live, scheduled: vm.scheduled, aired: vm.aired)
            }
        }
        .id(tab)
        .transition(.opacity.combined(with: .offset(y: 8)))
    }
}

// MARK: - Ambient backdrop — blurred artwork + navy gradient + breathing glows

private struct LiveRadioBackdrop: View {
    let artwork: URL?

    var body: some View {
        ZStack {
            RadioUX.navyDeep
            CachedAsyncImage(url: artwork) { ph in
                if let img = ph.image {
                    img.resizable().scaledToFill()
                } else {
                    Color.clear
                }
            }
            .scaleEffect(1.25)
            .blur(radius: 44)
            .overlay(Color.black.opacity(0.35))   // brightness(0.4) darken
            LinearGradient(stops: [
                .init(color: RadioUX.navyDeep.opacity(0.55), location: 0),
                .init(color: RadioUX.navyDeep.opacity(0.82), location: 0.45),
                .init(color: RadioUX.navyDeep, location: 1),
            ], startPoint: .top, endPoint: .bottom)
            GeometryReader { geo in
                BreathingGlow(color: RadioUX.gold.opacity(0.27),
                              duration: 6, opacities: (0.4, 0.7), scales: (1, 1.15))
                    .position(x: 64, y: 168)                            // -left-16 top-10
                BreathingGlow(color: RadioUX.indigo.opacity(0.33),
                              duration: 7, opacities: (0.3, 0.6), scales: (1.1, 1))
                    .position(x: geo.size.width - 48, y: geo.size.height - 224) // -right-20 bottom-24
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One 256pt radial glow slowly breathing opacity + scale (static under
/// Reduce Motion — held at the midpoint of its range).
private struct BreathingGlow: View {
    let color: Color
    let duration: Double
    let opacities: (Double, Double)
    let scales: (CGFloat, CGFloat)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var on = false

    var body: some View {
        Circle()
            .fill(RadialGradient(colors: [color, .clear],
                                 center: .center, startRadius: 0, endRadius: 128))
            .frame(width: 256, height: 256)
            .blur(radius: 48)
            .opacity(reduceMotion ? (opacities.0 + opacities.1) / 2 : (on ? opacities.1 : opacities.0))
            .scaleEffect(reduceMotion ? 1 : (on ? scales.1 : scales.0))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

// MARK: - Small shared pieces

/// 40pt glass square (radius 16) header button — chevron/bell chrome.
private struct GlassSquareButton: View {
    var sfSymbol: String?
    var lucide: Lucide?
    var iconSize: CGFloat = 20
    var dot = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Group {
                    if let lucide {
                        Icon(lucide, size: iconSize, color: .white)
                    } else if let sfSymbol {
                        Image(systemName: sfSymbol)
                            .font(.system(size: iconSize - 2, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 40, height: 40)
                if dot {
                    Circle().fill(RadioUX.gold).frame(width: 8, height: 8)
                        .padding(10)
                }
            }
            .background(RadioUX.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(RadioUX.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

/// Small red dot pulsing 1→0.3→1 (design 1.2s loop); static under Reduce Motion.
private struct PulsingDot: View {
    let color: Color
    var size: CGFloat = 6
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle().fill(color)
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.9), radius: 4)
            .opacity(dim ? 0.3 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}

// MARK: - Centerpiece — ON AIR panel: glow, red ring, shimmer, off-air chip

private struct LiveCenterpiece: View {
    let live: Bool
    let spinning: Bool
    let artwork: URL?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glowHigh = false

    var body: some View {
        ZStack {
            // Breathing glow behind the panel — red while playing, gold idle.
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(spinning ? RadioUX.red.opacity(0.55) : RadioUX.gold.opacity(0.27))
                .blur(radius: 32)
                .opacity(spinning ? (reduceMotion ? 0.8 : (glowHigh ? 1 : 0.55)) : 0.4)

            panel
        }
        .frame(maxWidth: 300)
        .aspectRatio(5.0 / 3.0, contentMode: .fit)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: true)) {
                glowHigh = true
            }
        }
    }

    private var panel: some View {
        ZStack {
            CachedAsyncImage(url: artwork) { ph in
                if let img = ph.image {
                    img.resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1628)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay {
                            Image(systemName: "dot.radiowaves.left.and.right")
                                .font(.system(size: 44)).foregroundStyle(RadioUX.gold.opacity(0.8))
                        }
                }
            }
            .grayscale(live ? 0 : 0.7)
            .overlay(Color.black.opacity(live ? 0 : 0.5))   // brightness(0.4) off-air

            if spinning && !reduceMotion { ShimmerSweep() }

            if !live {
                Text("OFF AIR")
                    .font(.inter(10, .bold)).kerning(2.2)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 4)
                    .background(RadioUX.navyDeep.opacity(0.7), in: Capsule())
                    .overlay(Capsule().stroke(RadioUX.glassBorder, lineWidth: 1))
            }
        }
        .aspectRatio(5.0 / 3.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous)
            .stroke(live ? RadioUX.red.opacity(0.6) : Color.white.opacity(0.14), lineWidth: 2))
        .shadow(color: .black.opacity(0.85), radius: 30, y: 20)
    }
}

/// White shimmer band sweeping the panel while broadcasting: 3s travel across
/// (-120% → 220%), then a 1.5s rest — the design's exact cadence.
private struct ShimmerSweep: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
            GeometryReader { geo in
                let period = 4.5
                let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
                let phase = min(1, t / 3)
                let eased = phase * phase * (3 - 2 * phase)   // easeInOut
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, .white.opacity(0.14), .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: geo.size.width * 0.45, height: geo.size.height * 2)
                    .rotationEffect(.degrees(20))
                    .offset(x: -1.2 * geo.size.width + eased * 3.4 * geo.size.width,
                            y: -geo.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Progress lines

/// LIVE: "● LIVE" + a subtle gold wave + elapsed clock since tune-in.
private struct LiveSweepLine: View {
    let tunedAt: Date?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle().fill(RadioUX.redDeep).frame(width: 6, height: 6)
                Text("LIVE").font(.inter(10, .bold)).kerning(1.4)
                    .foregroundStyle(RadioUX.redSoft)
            }
            waveBar
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                Text(fmtElapsed(tunedAt.map { ctx.date.timeIntervalSince($0) } ?? 0))
                    .font(.inter(10)).monospacedDigit()
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
    }

    /// Subtle live wave — thin gold bars breathing on layered sines (a radio
    /// signal, not a loading bar); brightest mid-line, fading toward the
    /// edges. Frozen at a pleasant phase under Reduce Motion. Mirrors
    /// Android's LiveWaveBar exactly.
    private var waveBar: some View {
        Group {
            if reduceMotion {
                wave(phase: 1.1)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    let phase = ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.8) / 2.8 * 2 * .pi
                    wave(phase: phase)
                }
            }
        }
        .frame(height: 18)
        .accessibilityHidden(true)
    }

    private func wave(phase: Double) -> some View {
        Canvas { context, size in
            let n = 27
            let slot = size.width / CGFloat(n)
            let barW = min(slot * 0.42, 3)
            let mid = size.height / 2
            for i in 0..<n {
                let x = slot * CGFloat(i) + slot / 2
                let envelope = sin(.pi * Double(i) / Double(n - 1))
                let a = 0.34 + 0.26 * sin(phase + Double(i) * 0.9)
                      + 0.18 * sin(phase * 1.7 + Double(i) * 0.47 + 1.3)
                let h = max(2, size.height * min(0.85, max(0.12, a)) * (0.45 + 0.55 * envelope))
                let rect = CGRect(x: x - barW / 2, y: mid - CGFloat(h) / 2,
                                  width: barW, height: CGFloat(h))
                context.fill(Path(roundedRect: rect, cornerRadius: barW / 2),
                             with: .color(RadioUX.gold.opacity(0.35 + 0.55 * envelope)))
            }
        }
    }
}

/// RECORDING: real gold progress from RadioCenter, drag to seek, mm:ss labels.
private struct RecordingProgressLine: View {
    @ObservedObject private var center = RadioCenter.shared
    @State private var scrubbing = false
    @State private var scrubFraction: Double = 0

    private var fraction: Double {
        if scrubbing { return scrubFraction }
        guard center.duration > 0 else { return 0 }
        return min(1, max(0, center.currentTime / center.duration))
    }

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(LinearGradient(colors: [RadioUX.gold, RadioUX.goldLight],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(0, geo.size.width * fraction))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard center.duration > 0 else { return }
                            scrubbing = true
                            scrubFraction = min(1, max(0, v.location.x / geo.size.width))
                        }
                        .onEnded { _ in
                            guard center.duration > 0 else { return }
                            Haptics.selection()
                            center.seek(to: scrubFraction * center.duration)
                            scrubbing = false
                        }
                )
            }
            .frame(height: 6)
            HStack {
                Text(fmtClock(scrubbing ? scrubFraction * center.duration : center.currentTime))
                Spacer()
                Text(fmtClock(center.duration))
            }
            .font(.inter(10)).monospacedDigit()
            .foregroundStyle(.white.opacity(0.55))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording progress")
    }
}

// MARK: - Transport row (live / recording)

private struct LiveTransportRow: View {
    let live: RadioProgram?
    let nowRec: RadioProgram?
    let spinning: Bool
    @ObservedObject private var center = RadioCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showSleep = false

    var body: some View {
        HStack(spacing: 28) {
            // Mute — active (gold) while sound is ON, per the design's `volume`.
            GlassCircleButton(active: !center.muted) {
                Haptics.tap()
                center.toggleMute()
            } content: {
                Image(systemName: center.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 18, weight: .semibold))
            }
            .accessibilityLabel(center.muted ? "Unmute" : "Mute")

            playButton

            GlassCircleButton(active: center.sleepAt != nil) {
                Haptics.tap()
                showSleep = true
            } content: {
                Icon(.moon, size: 20, color: center.sleepAt != nil ? RadioUX.goldLight : .white)
            }
            .accessibilityLabel("Sleep timer")
            .confirmationDialog("Sleep timer", isPresented: $showSleep, titleVisibility: .visible) {
                Button("15 minutes") { RadioCenter.shared.setSleepTimer(minutes: 15); Haptics.selection() }
                Button("30 minutes") { RadioCenter.shared.setSleepTimer(minutes: 30); Haptics.selection() }
                Button("60 minutes") { RadioCenter.shared.setSleepTimer(minutes: 60); Haptics.selection() }
                if center.sleepAt != nil {
                    Button("Off", role: .destructive) { RadioCenter.shared.setSleepTimer(minutes: nil) }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Pause the radio after…")
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// 78pt gold-gradient play/pause with an expanding gold ring while playing.
    private var playButton: some View {
        Button {
            Haptics.action()
            toggle()
        } label: {
            ZStack {
                if spinning && !reduceMotion { ExpandingRing() }
                Circle()
                    .fill(RadioUX.goldGradient)
                    .frame(width: 78, height: 78)
                    .shadow(color: RadioUX.gold.opacity(0.8), radius: 22, y: 12)
                Image(systemName: spinning ? "pause.fill" : "play.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(Nuru.navy)
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: spinning ? 0 : 2)
            }
        }
        .buttonStyle(.pressable)
        .animation(.easeInOut(duration: 0.2), value: spinning)
        .disabled(target?.streamUrl == nil)
        .opacity(target?.streamUrl == nil ? 0.4 : 1)
        .accessibilityLabel(spinning ? "Pause" : "Play")
    }

    private var target: RadioProgram? { nowRec ?? live }

    private func toggle() {
        let center = RadioCenter.shared
        if let rec = nowRec {
            center.program?.id == rec.id ? center.togglePlay() : center.tune(rec)
        } else if let l = live {
            center.program?.id == l.id ? center.togglePlay() : center.tune(l)
        }
    }
}

/// Gold ring expanding 1→1.35 and fading 0.5→0, 1.8s loop (playing only).
private struct ExpandingRing: View {
    @State private var expand = false
    var body: some View {
        Circle()
            .stroke(RadioUX.gold, lineWidth: 2)
            .frame(width: 78, height: 78)
            .scaleEffect(expand ? 1.35 : 1)
            .opacity(expand ? 0 : 0.5)
            .onAppear {
                withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                    expand = true
                }
            }
            .accessibilityHidden(true)
    }
}

/// 48pt glass circle; active = gold-tinted fill/border (the design's GlassBtn).
private struct GlassCircleButton<Content: View>: View {
    let active: Bool
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        Button(action: action) {
            content()
                .foregroundStyle(active ? RadioUX.goldLight : .white)
                .frame(width: 48, height: 48)
                .background(active ? RadioUX.gold.opacity(0.165) : RadioUX.glass, in: Circle())
                .overlay(Circle().stroke(active ? RadioUX.gold.opacity(0.4) : RadioUX.glassBorder,
                                         lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Off-air CTA — local notification when the next show goes live

private struct RemindMeCTA: View {
    let next: RadioProgram
    @State private var notified = false

    private var key: String { "nuru.radio.remind.\(next.id)" }

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "bell.and.waves.left.and.right")
                    .font(.system(size: 15, weight: .semibold))
                Text(notified ? "We'll notify you 🔔" : "Remind me when we're live")
                    .font(.inter(14, notified ? .semibold : .bold))
            }
            .foregroundStyle(notified ? .white : Nuru.navy)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background {
                if notified {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RadioUX.glass)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(RadioUX.goldGradient)
                }
            }
            .overlay {
                if notified {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(RadioUX.glassBorder, lineWidth: 1)
                }
            }
            .shadow(color: notified ? .clear : RadioUX.gold.opacity(0.55), radius: 15, y: 10)
        }
        .buttonStyle(.pressable)
        .onAppear { notified = UserDefaults.standard.bool(forKey: key) }
        .onChange(of: next.id) { _, _ in
            notified = UserDefaults.standard.bool(forKey: key)
        }
    }

    private func toggle() async {
        if notified {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [key])
            UserDefaults.standard.removeObject(forKey: key)
            withAnimation(.easeOut(duration: 0.2)) { notified = false }
            Haptics.tap()
            return
        }
        guard let date = radioISODate(next.scheduledAt) else { return }
        let centre = UNUserNotificationCenter.current()
        let granted = (try? await centre.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { Haptics.error(); return }
        let content = UNMutableNotificationContent()
        content.title = "Nuru Radio is live"
        content.body = "\(next.title) is starting — tune in now."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        try? await centre.add(UNNotificationRequest(identifier: key, content: content, trigger: trigger))
        UserDefaults.standard.set(true, forKey: key)
        withAnimation(.easeOut(duration: 0.2)) { notified = true }
        Haptics.success()
    }
}

// MARK: - Stat chip (glass pill: icon · value · caps label)

private struct StatChip: View {
    let lucide: Lucide
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Icon(lucide, size: 12, color: RadioUX.goldLight)
            Text(value).font(.inter(11, .bold)).foregroundStyle(.white)
            Text(label).font(.inter(9, .semibold)).kerning(0.9)
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(RadioUX.glass, in: Capsule())
        .overlay(Capsule().stroke(RadioUX.glassBorder, lineWidth: 1))
    }
}

// MARK: - LIVE tab — reactions (real POST /react) + live chat (real comments)

private struct ReactionFloat: Identifiable {
    let id = UUID()
    let emoji: String
    let xJitter: CGFloat
}

private struct LiveTabView: View {
    let live: RadioProgram?
    @ObservedObject var chat: LiveChatModel
    let myId: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var floats: [ReactionFloat] = []

    var body: some View {
        if live != nil {
            VStack(spacing: 0) {
                reactionRow
                if let counts = chat.counts {
                    Text("\(counts.total.formatted()) reactions today")
                        .font(.inter(10, .semibold))
                        .foregroundStyle(.white.opacity(0.45))
                        .padding(.top, 8)
                }
                commentsList.padding(.top, 12)
                composer.padding(.top, 12)
            }
        } else {
            Text("Reactions open when we go live. Catch a recording below meanwhile.")
                .font(.inter(12))
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(RadioUX.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(RadioUX.glassBorder, lineWidth: 1))
        }
    }

    // Three 48pt reaction circles + the floating-emoji burst above them.
    private var reactionRow: some View {
        HStack(spacing: 12) {
            ReactionButton(tint: RadioUX.redDeep) {
                Icon(.heart, size: 20, color: .white)
            } action: { fire("heart", emoji: "❤️") }
            ReactionButton(tint: RadioUX.gold) {
                Icon(.handHeart, size: 20, color: .white)
            } action: { fire("amen", emoji: "🙏") }
            ReactionButton(tint: RadioUX.indigoSoft) {
                Text("🙌").font(.system(size: 19))
            } action: { fire("fire", emoji: "🙌") }
        }
        .frame(maxWidth: .infinity)
        .overlay {
            ZStack {
                ForEach(floats) { f in FloatingReaction(float: f) }
            }
            .allowsHitTesting(false)
        }
    }

    private func fire(_ kind: String, emoji: String) {
        Haptics.love()
        Task { await chat.react(kind) }
        guard !reduceMotion else { return }
        let f = ReactionFloat(emoji: emoji, xJitter: .random(in: -24...24))
        floats.append(f)
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            floats.removeAll { $0.id == f.id }
        }
    }

    // Glass chat rows — 28pt gradient monograms, bold name + white/70 body.
    @ViewBuilder private var commentsList: some View {
        if chat.commentsLoading && chat.comments.isEmpty {
            ProgressView().tint(RadioUX.gold)
                .frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if chat.comments.isEmpty {
            Text("No messages yet — say amen to the studio.")
                .font(.inter(12)).foregroundStyle(.white.opacity(0.45))
                .frame(maxWidth: .infinity).padding(.vertical, 20)
        } else {
            LazyVStack(spacing: 10) {
                ForEach(chat.chat) { c in
                    LiveChatRow(comment: c,
                                mine: c.memberId == myId || c.id.hasPrefix("local-"))
                }
            }
        }
    }

    // Glass pill composer: "Say amen…" + 32pt gold send circle.
    private var composer: some View {
        HStack(spacing: 8) {
            TextField("", text: $chat.draft,
                      prompt: Text("Say amen…").foregroundColor(.white.opacity(0.4)))
                .font(.inter(13)).foregroundStyle(.white)
                .padding(.vertical, 6)
                .submitLabel(.send)
                .onSubmit(send)
            Button(action: send) {
                Icon(.send, size: 14, color: canSend ? Nuru.navy : .white.opacity(0.4))
                    .frame(width: 32, height: 32)
                    .background {
                        if canSend { Circle().fill(RadioUX.goldGradient) }
                        else { Circle().fill(Color.white.opacity(0.12)) }
                    }
            }
            .buttonStyle(.pressable)
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.vertical, 6)
        .padding(.leading, 16)
        .padding(.trailing, 6)
        .background(RadioUX.glass, in: Capsule())
        .overlay(Capsule().stroke(RadioUX.glassBorder, lineWidth: 1))
    }

    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespaces).isEmpty && !chat.sending
    }

    private func send() {
        guard canSend else { return }
        Haptics.action()
        Task { await chat.sendComment() }
    }
}

/// A 48pt tinted reaction circle (bg tint 16%, border tint 40%).
private struct ReactionButton<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: () -> Content
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            content()
                .frame(width: 48, height: 48)
                .background(tint.opacity(0.165), in: Circle())
                .overlay(Circle().stroke(tint.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(PressableStyle(scale: 0.85))
    }
}

/// One emoji rising ~70pt while scaling 0.6→1.2 and fading — the tap burst.
private struct FloatingReaction: View {
    let float: ReactionFloat
    @State private var up = false

    var body: some View {
        Text(float.emoji)
            .font(.system(size: 26))
            .scaleEffect(up ? 1.2 : 0.6)
            .offset(x: float.xJitter, y: up ? -70 : 0)
            .opacity(up ? 0 : 0.95)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4)) { up = true }
            }
    }
}

/// One glass chat row: gradient monogram (or real avatar) + inline name/body.
private struct LiveChatRow: View {
    let comment: RadioComment
    let mine: Bool

    private var displayName: String {
        if mine { return "You" }
        if let n = comment.authorName?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return "Member"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            monogram
            (Text(displayName).font(.inter(12, .bold)).foregroundStyle(.white)
             + Text(" ")
             + Text(comment.body).font(.inter(12)).foregroundStyle(.white.opacity(0.7)))
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RadioUX.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(RadioUX.glassBorder, lineWidth: 1))
    }

    private var monogram: some View {
        let pair = mine
            ? (RadioUX.monogramPairs[3].0, RadioUX.monogramPairs[3].1)   // gold — "mine"
            : RadioUX.monogram(for: displayName)
        return ZStack {
            Circle().fill(LinearGradient(colors: [pair.0, pair.1],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
            if !mine, let s = comment.authorAvatarUrl, let u = URL(string: s) {
                CachedAsyncImage(url: u) { ph in
                    if let img = ph.image { img.resizable().scaledToFill() }
                    else { initialsText }
                }
            } else {
                initialsText
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
    }

    private var initialsText: some View {
        Text(radioInitials(mine ? "Me" : displayName))
            .font(.inter(9, .bold)).foregroundStyle(.white)
    }
}

// MARK: - RECORDINGS tab — real recorded shows, play via RadioCenter, download

private struct ShareFile: Identifiable {
    let id = UUID()
    let url: URL
}

private struct RecordingsTabView: View {
    let recordings: [RadioProgram]
    @ObservedObject private var center = RadioCenter.shared
    @State private var downloadingId: String?
    @State private var shareFile: ShareFile?

    var body: some View {
        if recordings.isEmpty {
            Text("No recordings yet — shows land here after they air.")
                .font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(RadioUX.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(RadioUX.glassBorder, lineWidth: 1))
        } else {
            VStack(spacing: 10) {
                ForEach(recordings) { r in
                    RecordingRow(program: r,
                                 downloading: downloadingId == r.id,
                                 onDownload: { Task { await download(r) } })
                }
            }
            .sheet(item: $shareFile) { file in
                ShareSheet(items: [file.url])
            }
        }
    }

    /// URLSession download → temp file → share sheet. Spinner in-button while
    /// fetching; error haptic if anything fails.
    private func download(_ p: RadioProgram) async {
        guard downloadingId == nil, let s = p.audioUrl, let url = URL(string: s) else { return }
        Haptics.tap()
        downloadingId = p.id
        defer { downloadingId = nil }
        do {
            let (tmp, response) = try await URLSession.shared.download(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw URLError(.badServerResponse)
            }
            let safeName = p.title.replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
            let ext = url.pathExtension.isEmpty ? "mp3" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(safeName).\(ext)")
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: tmp, to: dest)
            Haptics.success()
            shareFile = ShareFile(url: dest)
        } catch {
            Haptics.error()
        }
    }
}

private struct RecordingRow: View {
    let program: RadioProgram
    let downloading: Bool
    let onDownload: () -> Void
    @ObservedObject private var center = RadioCenter.shared

    private var tuned: Bool { center.program?.id == program.id }
    private var playing: Bool { tuned && center.playing }

    var body: some View {
        HStack(spacing: 12) {
            cover
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(program.category.uppercased())
                        .font(.inter(8, .bold)).kerning(0.8)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(RadioUX.gold.opacity(0.2), in: Capsule())
                    if let date = radioDayLabel(program.scheduledAt) {
                        Text(date).font(.inter(10)).foregroundStyle(.white.opacity(0.45))
                    }
                }
                Text(program.title)
                    .font(.inter(13, .bold)).foregroundStyle(.white)
                    .lineLimit(1)
                if tuned {
                    HStack(spacing: 8) {
                        RadioMiniWave(playing: playing, count: 12, height: 12,
                                      color: RadioUX.goldLight)
                        Text("\(fmtClock(center.currentTime)) / \(fmtClock(center.duration))")
                            .font(.inter(9)).monospacedDigit()
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    .padding(.top, 4)
                } else if let sub = subtitle {
                    Text(sub).font(.inter(10)).foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            downloadButton
        }
        .padding(10)
        .background(tuned ? Color(hex: 0xC9A227).opacity(0.12) : RadioUX.glass,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(tuned ? RadioUX.gold.opacity(0.4) : RadioUX.glassBorder, lineWidth: 1))
    }

    /// Speaker only — the wire has no duration, and we never invent one.
    private var subtitle: String? {
        if let s = program.speaker, !s.isEmpty { return s }
        return nil
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1628)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            if let a = program.artworkUrl, let u = URL(string: a) {
                CachedAsyncImage(url: u) { ph in
                    if let img = ph.image { img.resizable().scaledToFill() }
                    else { coverGlyph }
                }
            } else {
                coverGlyph
            }
            // Dark scrim + 32pt gold play/pause — the whole cover is the button.
            Button {
                Haptics.action()
                tuned ? center.togglePlay() : center.tune(program)
            } label: {
                ZStack {
                    RadioUX.navyDeep.opacity(0.4)
                    Image(systemName: playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Nuru.navy)
                        .contentTransition(.symbolEffect(.replace))
                        .offset(x: playing ? 0 : 1)
                        .frame(width: 32, height: 32)
                        .background(RadioUX.goldGradient, in: Circle())
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(playing ? "Pause recording" : "Play recording")
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var coverGlyph: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.system(size: 18)).foregroundStyle(RadioUX.gold.opacity(0.8))
    }

    private var downloadButton: some View {
        Button(action: onDownload) {
            Group {
                if downloading {
                    ProgressView().tint(.white).scaleEffect(0.7)
                } else {
                    Icon(.download, size: 15, color: .white)
                }
            }
            .frame(width: 36, height: 36)
            .background(RadioUX.glass, in: Circle())
            .overlay(Circle().stroke(RadioUX.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(downloading || program.audioUrl == nil)
        .accessibilityLabel("Download recording")
    }
}

/// UIActivityViewController wrapper — presents the downloaded audio for saving
/// to Files, AirDrop, sharing, etc.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - SCHEDULE tab — live first, then next/upcoming, then aired

private struct ScheduleTabView: View {
    let live: RadioProgram?
    let scheduled: [RadioProgram]
    let aired: [RadioProgram]

    private enum RowState { case live, next, upcoming, done }

    var body: some View {
        let rows = buildRows()
        if rows.isEmpty {
            Text("Nothing on the schedule yet — check back soon.")
                .font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 32)
                .background(RadioUX.glass, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(RadioUX.glassBorder, lineWidth: 1))
        } else {
            VStack(spacing: 8) {
                ForEach(rows, id: \.0.id) { program, state in
                    ScheduleRow(program: program, state: state)
                }
            }
        }
    }

    private func buildRows() -> [(RadioProgram, RowState)] {
        var rows: [(RadioProgram, RowState)] = []
        if let l = live { rows.append((l, .live)) }
        for (i, p) in scheduled.enumerated() {
            rows.append((p, i == 0 ? .next : .upcoming))
        }
        for p in aired { rows.append((p, .done)) }
        return rows
    }

    private struct ScheduleRow: View {
        let program: RadioProgram
        let state: RowState

        var body: some View {
            HStack(spacing: 12) {
                timeColumn
                Rectangle().fill(Color.white.opacity(0.12))
                    .frame(width: 1, height: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(program.title)
                        .font(.inter(13, .bold))
                        .foregroundStyle(state == .done ? Color.white.opacity(0.5) : .white)
                        .lineLimit(1)
                    Text([program.speaker, program.category].compactMap { $0 }
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.inter(10)).foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                stateChip
            }
            .padding(12)
            .background(RadioUX.glass, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(state == .live ? RadioUX.gold.opacity(0.53) : RadioUX.glassBorder,
                        lineWidth: 1))
        }

        private var timeColumn: some View {
            VStack(spacing: 0) {
                Text(radioTimeParts(program.scheduledAt)?.0 ?? "—")
                    .font(.inter(13, .bold)).kerning(-0.26)
                    .foregroundStyle(.white)
                Text(radioTimeParts(program.scheduledAt)?.1 ?? "")
                    .font(.inter(8, .bold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .frame(width: 48)
        }

        @ViewBuilder private var stateChip: some View {
            switch state {
            case .live:
                HStack(spacing: 4) {
                    Circle().fill(.white).frame(width: 4, height: 4)
                    Text("LIVE").font(.inter(8, .bold)).kerning(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RadioUX.redDeep, in: Capsule())
            case .next:
                Text("NEXT").font(.inter(8, .bold)).kerning(0.8)
                    .foregroundStyle(RadioUX.goldLight)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RadioUX.gold.opacity(0.2), in: Capsule())
            case .upcoming:
                Icon(.clock, size: 13, color: .white.opacity(0.35))
            case .done:
                Text("Aired").font(.inter(9, .bold))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
    }
}

// MARK: - Formatting helpers

private let radioTimeFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
}()
private let radioTimeShortFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "h:mm"; return f
}()
private let radioAmPmFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "a"; return f
}()
private let radioDayFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "MMM d"; return f
}()
private let radioDayTimeFormatter: DateFormatter = {
    let f = DateFormatter(); f.dateFormat = "EEE h:mm a"; return f
}()

private func radioISODate(_ iso: String?) -> Date? {
    guard let iso else { return nil }
    return ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
}

/// "8:00 AM" — clock label for stat chips / next-up lines.
private func radioClockLabel(_ iso: String?) -> String? {
    radioISODate(iso).map { radioTimeFormatter.string(from: $0) }
}

/// Off-air "Back at …": same-day → "8:00 AM", otherwise "Wed 8:00 AM".
private func radioBackAt(_ iso: String?) -> String? {
    guard let d = radioISODate(iso) else { return nil }
    return Calendar.current.isDateInToday(d)
        ? radioTimeFormatter.string(from: d)
        : radioDayTimeFormatter.string(from: d)
}

/// Schedule time column → ("8:00", "AM").
private func radioTimeParts(_ iso: String?) -> (String, String)? {
    guard let d = radioISODate(iso) else { return nil }
    return (radioTimeShortFormatter.string(from: d), radioAmPmFormatter.string(from: d))
}

/// Recording row date — "Jun 29".
private func radioDayLabel(_ iso: String?) -> String? {
    radioISODate(iso).map { radioDayFormatter.string(from: $0) }
}

/// m:ss (the design's fmtClock — minutes uncapped, e.g. "72:40").
private func fmtClock(_ s: Double) -> String {
    guard s.isFinite, s > 0 else { return "0:00" }
    let t = Int(s)
    return String(format: "%d:%02d", t / 60, t % 60)
}

/// Elapsed live clock — h:mm:ss past the hour, mm:ss before it.
private func fmtElapsed(_ s: TimeInterval) -> String {
    let t = max(0, Int(s))
    if t >= 3600 { return String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60) }
    return String(format: "%02d:%02d", t / 60, t % 60)
}

/// Two-letter initials for the chat monograms.
private func radioInitials(_ name: String) -> String {
    let parts = name.split(separator: " ").prefix(2)
    let chars = parts.compactMap { $0.first }.map(String.init)
    return chars.isEmpty ? "M" : chars.joined().uppercased()
}
