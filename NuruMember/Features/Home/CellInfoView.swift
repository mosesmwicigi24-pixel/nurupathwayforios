// Cell info — the destination behind every cell aspect surfaced on Home (the
// "This week at Nuru" featured-cell card and the "Your cohort" card). It merges
// the two cell payloads the member already sees — GET /home/featured-cell and
// GET /me/cell-summary — into one screen: the cell's leader/discipler, its
// meeting rhythm, the next gathering, and the members/attendance/level/focus
// stats. Navy rounded-bottom header (no hero image), matching MentorView.
import SwiftUI

@MainActor
final class CellInfoViewModel: ObservableObject {
    @Published var featured: FeaturedCell?
    @Published var cell: CellSummary.Cell?
    @Published var loading = true
    @Published var error: String?
    /// GET /live/now, filtered to the "cell" scope row (if any) — the server
    /// already scopes that row to the caller's OWN cell, so no cell id is sent
    /// up; this is this screen's own single fetch, not a second endpoint.
    @Published var liveStream: LiveStreamSummary?

    var name: String { featured?.name ?? cell?.name ?? "Your cell" }
    var isEmpty: Bool { featured == nil && cell == nil }

    func load() async {
        loading = true; error = nil
        async let fc = try? MemberAPI.featuredCell()
        async let cs = try? MemberAPI.cellSummary()
        async let live = try? MemberAPI.fetchLiveNow()
        featured = await fc ?? nil
        cell = (await cs)?.cell
        liveStream = (await live ?? []).first { $0.scope == "cell" }
        if isEmpty { error = "Couldn't load your cell." }
        loading = false
    }
}

struct CellInfoView: View {
    @StateObject private var vm = CellInfoViewModel()
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    // Nuru Live (L2) — this cell's LIVE banner opens the same full-screen
    // player as Home's church banner; "Watch replays" opens the same list,
    // scoped to this cell.
    @State private var openLiveItem: LivePlayableItem?
    @State private var openReplays = false
    // Nuru Live (L3, broadcaster) — this screen's own Go Live button, forced
    // to scope=cell (no picker) since we're already inside one specific cell.
    // The controller itself lives in BroadcastCenter (app-wide) — see
    // RootView for the single fullScreenCover presentation + floating island.
    @ObservedObject private var broadcast = BroadcastCenter.shared
    @State private var showGoLiveSheet = false

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        if vm.loading && vm.isEmpty {
                            // Shimmer ghosts in the screen's own rhythm: leader
                            // card → rhythm card → stats row.
                            loadingGhost(height: 88)
                            loadingGhost(height: 132)
                            HStack(spacing: Nuru.S.sm) {
                                loadingGhost(height: 56)
                                loadingGhost(height: 56)
                            }
                        } else if vm.isEmpty {
                            emptyCard
                        } else {
                            if let live = vm.liveStream { cellLiveCard(live) }
                            if LiveBroadcastEligibility.showCellEntryPoint(auth.profile) { goLiveButton }
                            leaderCard
                            if hasRhythm { rhythmCard }
                            if let n = vm.cell?.next { nextGatheringCard(n) }
                            statsGrid
                            watchReplaysButton
                            openCommunityButton
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.isEmpty { await vm.load() } }
        .fullScreenCover(item: $openLiveItem) { item in
            // `.id(item.id)` — see LiveViewerPlayerView's flicker-guard note:
            // without it, a rebind of `openLiveItem` to a DIFFERENT stream
            // while the cover is still up reuses the same view identity (and
            // its @StateObject player) instead of tearing down and starting
            // fresh, so the old stream's frames would keep showing.
            LiveViewerPlayerView(item: item, replaysScope: "cell", replaysCellId: vm.cell?.cellGroupId, replaysCellName: vm.name)
                .id(item.id)
        }
        .sheet(isPresented: $openReplays) {
            LiveReplaysView(scope: "cell", cellId: vm.cell?.cellGroupId, cellName: vm.name)
        }
        .sheet(isPresented: $showGoLiveSheet) {
            GoLiveSetupSheet(forcedCell: (id: auth.profile?.cellGroupId ?? "", name: vm.name)) {
                BroadcastCenter.shared.start(session: $0)
            }
        }
    }

    // MARK: Nuru Live (L3) — this cell's own Go Live button, forced scope=cell

    private var goLiveButton: some View {
        Button {
            Haptics.tap()
            // Already broadcasting (minimized elsewhere) — reopen it rather
            // than minting a second stream on top.
            if broadcast.controller != nil { broadcast.restore() } else { showGoLiveSheet = true }
        } label: {
            HStack(spacing: Nuru.S.sm) {
                Icon(.megaphone, size: 15, color: Nuru.navy)
                    .frame(width: 32, height: 32)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(broadcast.controller != nil ? "You're live — tap to return" : "Go live to your cell")
                    .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 15, color: Nuru.navy.opacity(0.6))
            }
        }
        .buttonStyle(.pressable)
        .padding(Nuru.S.base)
        .background(Nuru.gold.opacity(0.14), in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
    }

    // MARK: Nuru Live — this cell's LIVE banner (same treatment as Home's church one)

    private func cellLiveCard(_ stream: LiveStreamSummary) -> some View {
        HomeLiveBannerCard(
            stream: stream,
            onWatch: { Haptics.action(); openLiveItem = .live(stream) },
            onReplays: { openReplays = true }
        )
    }

    private var watchReplaysButton: some View {
        Button { Haptics.tap(); openReplays = true } label: {
            HStack(spacing: Nuru.S.sm) {
                Icon(.calendarClock, size: 15, color: Nuru.goldChipText)
                    .frame(width: 32, height: 32)
                    .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text("Watch replays").font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 15, color: Nuru.faint)
            }
        }
        .buttonStyle(.pressable)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    /// One shimmering placeholder card (loading state only).
    private func loadingGhost(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
            .fill(Nuru.surface)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .nuruShimmer()
    }

    // Navy header with rounded bottom, circular back button, gold overline, serif title.
    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.onNavy)
                    .frame(width: 38, height: 38)
                    .background(Nuru.navyDeep, in: Circle())
            }
            .buttonStyle(.pressable)

            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("YOUR CELL")
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Nuru.gold)
                Text(vm.name)
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.white)
                    .fixedSize(horizontal: false, vertical: true)
                if let f = vm.featured?.focus {
                    Text(f).font(.nCaption).foregroundStyle(Nuru.onNavyFaint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.lg)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
                .fill(Nuru.navy)
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Leader / discipler

    private var leaderName: String? { vm.cell?.leader?.name ?? vm.featured?.disciplerName }
    private var leaderRole: String? { vm.cell?.leader?.role ?? vm.featured?.disciplerRole }

    private var leaderCard: some View {
        HStack(spacing: Nuru.S.base) {
            Avatar(url: vm.cell?.leader?.avatarUrl, name: leaderName ?? vm.name, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("CELL LEADER").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                Text(leaderName ?? "Not assigned yet").font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                if let r = leaderRole { Text(r).font(.nCaption).foregroundStyle(Nuru.muted) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: Meeting rhythm (from featured-cell)

    private var hasRhythm: Bool {
        (vm.featured?.meets != nil) || (vm.featured?.nextSession != nil) || (vm.featured?.room != nil)
    }

    private var rhythmCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Text("MEETING RHYTHM").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.muted)
            if let m = vm.featured?.meets { rhythmRow(.calendarClock, "Meets", m) }
            if let n = vm.featured?.nextSession { rhythmRow(.calendarDays, "Next session", n) }
            if let r = vm.featured?.room { rhythmRow(.mapPin, "Where", r) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func rhythmRow(_ icon: Lucide, _ label: String, _ value: String) -> some View {
        HStack(spacing: Nuru.S.md) {
            Icon(icon, size: 16, color: Nuru.goldChipText)
                .frame(width: 34, height: 34)
                .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.nMicro).foregroundStyle(Nuru.faint)
                Text(value).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Next gathering (from cell-summary)

    private func nextGatheringCard(_ n: CellSummary.Cell.Next) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).fill(Nuru.goldTint).frame(width: 44, height: 44)
                Icon(.calendarClock, size: 20, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT GATHERING").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                Text(Self.longDate(n.startAt)).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                if let loc = n.location { Text(loc).font(.nMicro).foregroundStyle(Nuru.muted) }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.priorityBg, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    // MARK: Stats (members · attendance · level · focus)

    private var statsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Nuru.S.sm), GridItem(.flexible(), spacing: Nuru.S.sm)], spacing: Nuru.S.sm) {
            statTile(.handHeart, "Members", membersText)
            statTile(.percent, "Attendance", attendanceText)
            if let l = vm.featured?.levelLabel { statTile(.award, "Level", l) }
            if let f = vm.featured?.focus { statTile(.target, "Focus", f) }
        }
    }

    private func statTile(_ icon: Lucide, _ label: String, _ value: String) -> some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(icon, size: 15, color: Nuru.goldChipText)
                .frame(width: 32, height: 32)
                .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.nMicro).foregroundStyle(Nuru.faint)
                Text(value).font(.inter(14, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.sm)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private var membersText: String {
        if let m = vm.cell?.members { return "\(m)" }
        if let m = vm.featured?.members { return "\(m)" }
        return "—"
    }
    private var attendanceText: String {
        guard let a = vm.cell?.attendance, a.expected > 0 else { return "—" }
        return "\(a.attended)/\(a.expected)"
    }

    // MARK: Open community

    private var openCommunityButton: some View {
        NavigationLink(value: CommunityRoute.prayerWall) {
            HStack {
                Spacer()
                Text("Open community ›").font(.nCardCTA).foregroundStyle(Nuru.white)
                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.pressable)
        .padding(.top, Nuru.S.xs)
    }

    // MARK: Empty state

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).fill(Nuru.goldTint).frame(width: 48, height: 48)
                Icon(.users, size: 22, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("No cell yet").font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                Text("When your leader adds you to a discipleship cell, you'll see your leader, meeting rhythm and gatherings here.")
                    .font(.nCaption).foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Also the recovery path when the fetch failed (both cell endpoints
            // swallow errors, so "empty" and "offline" look the same here).
            Button { Haptics.tap(); Task { await vm.load() } } label: {
                Text("Refresh").font(.nCardCTA).foregroundStyle(Nuru.gold)
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: date helpers

    private static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
    private static func longDate(_ iso: String) -> String {
        guard let d = parse(iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d · h:mm a"; return f.string(from: d)
    }
}
