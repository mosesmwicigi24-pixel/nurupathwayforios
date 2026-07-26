// Nuru Live — Replays list (L2). Reachable from the Home LIVE banner and
// from the cell card. Rows show title, date (from `started_at`) and a scope
// label (Church / the member's cell name when known, else "Cell") — no
// duration, since the backend doesn't return one. Tapping a row plays the
// recording through the SAME full-screen player used for live streams.
import SwiftUI

struct LiveReplaysView: View {
    /// Optional filters mirroring GET /live/recordings?scope=&cell_id=; both
    /// nil lists everything visible to the caller (church + the member's own
    /// cell). Passed a specific scope/cellId when opened from a scoped
    /// surface (e.g. the cell card) so the list lands on the relevant subset.
    var scope: String? = nil
    var cellId: String? = nil
    /// The member's own cell name, when the caller already knows it (e.g.
    /// CellInfoView) — lets a cell-scope row read "Your Cell" by name instead
    /// of the generic "Cell" fallback.
    var cellName: String? = nil
    /// L4: true when hosted directly inside the Live tab's own NavigationStack
    /// rather than presented as a `.sheet` (Home / CellInfoView still present
    /// this modally, unchanged) — skips the wrapping NavigationStack, nav
    /// title and "Done" button, which would otherwise duplicate/fight the
    /// host's own chrome and a dismiss() that has nothing to dismiss.
    var embedded: Bool = false

    @Environment(\.dismiss) private var dismiss
    @State private var rows: [LiveRecordingRow] = []
    @State private var loading = true
    @State private var errorText: String?
    @State private var playingItem: LivePlayableItem?

    var body: some View {
        Group {
            if embedded {
                content
            } else {
                NavigationStack {
                    content
                        .navigationTitle("Replays")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { dismiss() }
                            }
                        }
                }
            }
        }
        .task { await load() }
        .fullScreenCover(item: $playingItem) { LiveViewerPlayerView(item: $0, replaysScope: scope, replaysCellId: cellId, replaysCellName: cellName) }
    }

    @ViewBuilder private var content: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            if loading && rows.isEmpty {
                ProgressView().tint(Nuru.gold)
            } else if let errorText, rows.isEmpty {
                errorState(errorText)
            } else if rows.isEmpty {
                emptyState
            } else if embedded {
                // Hosted inside the Live tab's own ScrollView (below the Go
                // Live card) — a plain VStack, not a List, so there's no
                // nested-scroll-view fight with that outer ScrollView. The
                // Live tab's own `.refreshable` covers reloading.
                VStack(spacing: 10) {
                    ForEach(rows) { row in
                        Button {
                            Haptics.tap()
                            playingItem = .recording(row, cellName: cellName)
                        } label: {
                            rowView(row)
                        }
                        .buttonStyle(.pressableSubtle)
                    }
                }
            } else {
                List {
                    ForEach(rows) { row in
                        Button {
                            Haptics.tap()
                            playingItem = .recording(row, cellName: cellName)
                        } label: {
                            rowView(row)
                        }
                        .buttonStyle(.pressableSubtle)
                        .listRowInsets(EdgeInsets(top: 6, leading: Nuru.S.screen, bottom: 6, trailing: Nuru.S.screen))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .refreshable { await load() }
            }
        }
    }

    private func load() async {
        loading = rows.isEmpty
        errorText = nil
        do {
            rows = try await MemberAPI.fetchRecordings(scope: scope, cellId: cellId)
        } catch {
            if rows.isEmpty { errorText = error.localizedDescription }
        }
        loading = false
    }

    private func rowView(_ row: LiveRecordingRow) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.goldChipBg)
                Icon(row.isAudio ? .audioLines : .camera, size: 18, color: Nuru.goldChipText)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(2)
                HStack(spacing: 6) {
                    Text(scopeLabel(row)).font(.inter(10, .bold)).kerning(0.6)
                        .foregroundStyle(Nuru.goldChipText)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Nuru.goldChipBg, in: Capsule())
                    Text(LiveFormat.dateLabel(row.startedAt)).font(.nMicro).foregroundStyle(Nuru.muted)
                }
            }
            Spacer(minLength: 0)
            Icon(.play, size: 14, color: Nuru.gold)
                .frame(width: 30, height: 30)
                .background(Nuru.white, in: Circle())
                .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func scopeLabel(_ row: LiveRecordingRow) -> String {
        row.scope == "church" ? "CHURCH" : (cellName?.uppercased() ?? "CELL")
    }

    private var emptyState: some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.calendarClock, size: 32, color: Nuru.gold.opacity(0.7))
            Text("No replays yet").font(.inter(16, .bold)).foregroundStyle(Nuru.ink)
            Text("When a live stream ends, its replay will appear here.")
                .font(.nCaption).foregroundStyle(Nuru.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Nuru.S.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.circleHelp, size: 32, color: Nuru.muted)
            Text("Couldn't load replays").font(.inter(16, .bold)).foregroundStyle(Nuru.ink)
            Text(message).font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                .padding(.horizontal, Nuru.S.xl)
            Button { Task { await load() } } label: {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
