// Nuru Live L4 — the Live tab (docs/LIVE_STREAMING.md L4 section). RootView
// only mounts this for a member whose /me permissions include `live:go`
// (LiveBroadcastEligibility.canGoLive) — everyone else keeps the four-tab bar
// and watches through Home's LIVE banner / the cell card, unchanged. This is
// the broadcaster's own "backstage": the exact L3 Go Live entry point Home
// already uses (GoLiveSetupSheet → GoLiveBroadcastView, offering whichever of
// church/cell the signed-in profile is eligible for — no forced scope, same
// as Home's header icon).
//
// TASTE PASS (2026-07-31, owner: "on Android it's bare; bring iOS's to the
// same elevated design"): the plain header-card-list layout became a proper
// hero "studio card" (navy, breathing Go Live pill, swaps to "LIVE now —
// watch" when someone else is already broadcasting church-wide), and the
// L2 Replays list embedded here became "My Broadcasts" — GET
// /live/recordings/mine, this broadcaster's own stewardship view (Play /
// Download-Share / Delete per row), distinct from the read-only Replays list
// Home and the cell card still use (`LiveReplaysView` itself is untouched).
import SwiftUI

struct NuruLiveTabView: View {
    @EnvironmentObject private var auth: AuthStore
    @ObservedObject private var broadcast = BroadcastCenter.shared
    @ObservedObject private var liveDiscovery = LiveDiscoveryCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showGoLiveSheet = false
    @State private var breathe = false

    // My Broadcasts
    @State private var rows: [LiveMyRecordingRow] = []
    @State private var resolvedURLs: [String: URL] = [:]   // recordingId → absolute, shareable URL
    @State private var loadingBroadcasts = true
    @State private var errorText: String?
    @State private var playingRow: LiveMyRecordingRow?
    @State private var confirmDeleteId: String?
    @State private var deletingId: String?

    /// The church-wide stream someone ELSE is broadcasting right now, if
    /// any — `LiveDiscoveryCenter.streams` already excludes this device's
    /// own active broadcast (see its `ingest` header comment), so this can
    /// never be "my own" stream.
    private var churchStreamLive: LiveStreamSummary? {
        liveDiscovery.streams.first { $0.isChurch }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    VStack(alignment: .leading, spacing: Nuru.S.lg) {
                        heroCard
                        myBroadcastsSection
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .refreshable { await load() }
            .ignoresSafeArea(edges: .top)
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
        }
        .task { await load() }
        .sheet(isPresented: $showGoLiveSheet) {
            GoLiveSetupSheet { BroadcastCenter.shared.start(session: $0) }
        }
        // `.id($0.recordingId)` — flicker guard, same reasoning as every
        // other `LiveViewerPlayerView` call site (see its own header note).
        .fullScreenCover(item: $playingRow) { row in
            LiveViewerPlayerView(item: .myRecording(row), replaysScope: row.scope, replaysCellId: row.cellId)
                .id(row.recordingId)
        }
        .confirmationDialog(
            "Delete this recording?",
            isPresented: Binding(get: { confirmDeleteId != nil }, set: { if !$0 { confirmDeleteId = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete forever", role: .destructive) {
                if let id = confirmDeleteId { Haptics.action(); Task { await deleteBroadcast(id) } }
            }
            Button("Cancel", role: .cancel) { confirmDeleteId = nil }
        } message: {
            let title = rows.first { $0.recordingId == confirmDeleteId }?.title ?? "this recording"
            Text("Delete '\(title)'? The recording will be gone forever.")
        }
    }

    private func load() async {
        await liveDiscovery.refresh()
        await loadMyBroadcasts()
    }

    // MARK: Header — the same cream hero-band idiom every folded tab uses.

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🔴 NURU LIVE").font(.inter(11, .bold)).kerning(2).foregroundStyle(Color(hex: 0x9A7A2A))
            Text("Go live").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.navy)
            Text("Broadcast to the church or your cell, and revisit past streams.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen).padding(.top, 60).padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // MARK: Hero studio card — navy, Fraunces wordmark, breathing Go Live
    // pill; swaps its CTA to "LIVE now — watch" when the church is already
    // on air (starting a second church stream would just 409 anyway, so
    // pointing at watching is strictly more useful).

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("NURU LIVE").font(.inter(10, .bold)).kerning(2.4).foregroundStyle(Nuru.gold.opacity(0.85))
                Text("Nuru Live").font(.fraunces(24, .semibold)).foregroundStyle(.white)
                Text("Bring the family together, wherever they are.")
                    .font(.inter(12)).foregroundStyle(.white.opacity(0.65))
            }
            if broadcast.controller == nil, let live = churchStreamLive {
                watchNowRow(live)
            } else {
                goLivePill
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }

    private var goLivePill: some View {
        let live = broadcast.controller != nil
        return Button {
            Haptics.tap()
            if live { broadcast.restore() } else { showGoLiveSheet = true }
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().stroke(Nuru.gold.opacity(0.45), lineWidth: 2)
                        .frame(width: 44, height: 44)
                        .scaleEffect(breathe ? 1.4 : 1)
                        .opacity(breathe ? 0 : 0.85)
                    Circle().fill(live ? Color.white.opacity(0.16) : Nuru.gold).frame(width: 40, height: 40)
                    Image(systemName: "video.fill").font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(live ? .white : Nuru.navy)
                }
                Text(live ? "You're live — tap to return" : "Go Live")
                    .font(.inter(15, .bold)).foregroundStyle(live ? .white : Nuru.navy)
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 15, color: live ? .white.opacity(0.7) : Nuru.navy.opacity(0.55))
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background(live ? Color.white.opacity(0.10) : Nuru.gold, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Color.white.opacity(live ? 0.16 : 0), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { breathe = true }
        }
    }

    private func watchNowRow(_ stream: LiveStreamSummary) -> some View {
        Button {
            Haptics.tap()
            liveDiscovery.markSeen(stream.streamId)
            liveDiscovery.requestedItem = .live(stream)
        } label: {
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Circle().fill(Color(hex: 0xDC2626)).frame(width: 6, height: 6)
                    Text("LIVE").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(.white)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color(hex: 0xDC2626), in: Capsule())
                Text(stream.title).font(.inter(13, .semibold)).foregroundStyle(.white).lineLimit(1)
                Spacer(minLength: 8)
                Text("Watch").font(.inter(12, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Nuru.gold, in: Capsule())
            }
            .padding(.horizontal, 14)
            .frame(height: 60)
            .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: My Broadcasts — GET /live/recordings/mine, owner-managed
    // keep/delete stewardship (this broadcaster's OWN streams only, or every
    // stream for a live:manage holder — server-decided, not client-filtered).

    private var myBroadcastsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("MY BROADCASTS").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xB08A1E))
                .padding(.horizontal, 4)
            if loadingBroadcasts && rows.isEmpty {
                ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 30)
            } else if let errorText, rows.isEmpty {
                broadcastsErrorState(errorText)
            } else if rows.isEmpty {
                broadcastsEmptyState
            } else {
                VStack(spacing: 10) {
                    ForEach(rows) { row in broadcastRow(row) }
                }
            }
        }
    }

    private func broadcastRow(_ row: LiveMyRecordingRow) -> some View {
        HStack(spacing: Nuru.S.md) {
            Button {
                Haptics.tap()
                playingRow = row
            } label: {
                HStack(spacing: Nuru.S.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.navy)
                        Icon(row.isAudio ? .audioLines : .camera, size: 18, color: Nuru.gold)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(2)
                        HStack(spacing: 6) {
                            Text(row.scope == "church" ? "CHURCH" : "CELL").font(.inter(10, .bold)).kerning(0.6)
                                .foregroundStyle(Nuru.goldChipText)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Nuru.goldChipBg, in: Capsule())
                            Text(LiveFormat.dateLabel(row.startedAt)).font(.nMicro).foregroundStyle(Nuru.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.pressableSubtle)

            Menu {
                Button { Haptics.tap(); playingRow = row } label: {
                    Label("Play", systemImage: "play.fill")
                }
                if let url = resolvedURLs[row.recordingId] {
                    ShareLink(item: url) {
                        Label("Download / Share", systemImage: "square.and.arrow.up")
                    }
                }
                Button(role: .destructive) {
                    Haptics.tap()
                    confirmDeleteId = row.recordingId
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                if deletingId == row.recordingId {
                    ProgressView().tint(Nuru.muted)
                        .frame(width: 30, height: 30)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Nuru.muted)
                        .frame(width: 30, height: 30)
                        .background(Nuru.surface, in: Circle())
                }
            }
            .disabled(deletingId == row.recordingId)
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .opacity(deletingId == row.recordingId ? 0.5 : 1)
    }

    private var broadcastsEmptyState: some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.calendarClock, size: 32, color: Nuru.gold.opacity(0.7))
            Text("No broadcasts yet").font(.inter(16, .bold)).foregroundStyle(Nuru.ink)
            Text("Once you go live and end a stream, it'll show up here to revisit, share, or clear away.")
                .font(.nCaption).foregroundStyle(Nuru.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Nuru.S.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func broadcastsErrorState(_ message: String) -> some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.circleHelp, size: 28, color: Nuru.muted)
            Text("Couldn't load your broadcasts").font(.inter(14, .bold)).foregroundStyle(Nuru.ink)
            Text(message).font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                .padding(.horizontal, Nuru.S.xl)
            Button { Task { await loadMyBroadcasts() } } label: {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func loadMyBroadcasts() async {
        loadingBroadcasts = rows.isEmpty
        errorText = nil
        do {
            let fetched = try await MemberAPI.fetchMyRecordings()
            rows = fetched
            for row in fetched where resolvedURLs[row.recordingId] == nil {
                if let u = await MemberAPI.resolveLiveMediaURL(row.url) { resolvedURLs[row.recordingId] = u }
            }
        } catch {
            if rows.isEmpty { errorText = error.localizedDescription }
        }
        loadingBroadcasts = false
    }

    private func deleteBroadcast(_ id: String) async {
        deletingId = id
        do {
            try await MemberAPI.deleteLiveRecording(streamId: id)
            Haptics.success()
            rows.removeAll { $0.recordingId == id }
            resolvedURLs.removeValue(forKey: id)
        } catch {
            Haptics.error()
        }
        deletingId = nil
        confirmDeleteId = nil
    }
}
