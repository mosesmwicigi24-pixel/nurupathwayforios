// Nuru Live L4 — the broadcaster's "backstage" (docs/LIVE_STREAMING.md L4
// section). Once its own tab; since the Partners programme restructure
// (PARTNERS_PROGRAMME §0) it is the "My Broadcasts" page PUSHED from the
// Broadcast card at the top of Events (`pushed: true`) — Events shows that
// card only for a member whose /me permissions include `live:go`
// (LiveBroadcastEligibility.canGoLive); everyone else watches through Home's
// LIVE banner / the cell card, unchanged. The studio card itself lives in
// BroadcastStudioCard.swift so Events and this page render the one design.
// This is the exact L3 Go Live entry point Home already uses
// (GoLiveSetupSheet → GoLiveBroadcastView, offering whichever of church/cell
// the signed-in profile is eligible for — no forced scope).
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
    /// True when pushed onto the Events stack (the only way in now): no
    /// NavigationStack of its own, a back tile in the header, and the
    /// standard pushed-screen top padding.
    var pushed: Bool = false

    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var liveDiscovery = LiveDiscoveryCenter.shared

    // My Broadcasts
    @State private var rows: [LiveMyRecordingRow] = []
    @State private var resolvedURLs: [String: URL] = [:]   // recordingId → absolute, shareable URL
    @State private var loadingBroadcasts = true
    @State private var errorText: String?
    @State private var playingRow: LiveMyRecordingRow?
    @State private var confirmDeleteId: String?
    @State private var deletingId: String?

    var body: some View {
        Group {
            if pushed {
                page
                    .navigationBarBackButtonHidden(true)
                    .toolbar(.hidden, for: .navigationBar)
            } else {
                NavigationStack { page.toolbar(.hidden, for: .navigationBar) }
            }
        }
        .task { await load() }
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

    private var page: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: Nuru.S.lg) {
                    BroadcastStudioCard()
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
    }

    private func load() async {
        await liveDiscovery.refresh()
        await loadMyBroadcasts()
    }

    // MARK: Header — the same cream hero-band idiom every folded tab uses.

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            if pushed {
                Button { Haptics.tap(); dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("🔴 NURU LIVE").font(.inter(11, .bold)).kerning(2).foregroundStyle(Color(hex: 0x9A7A2A))
                Text("My Broadcasts").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.navy)
                Text("Broadcast to the church or your cell, and revisit past streams.")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
            }
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
