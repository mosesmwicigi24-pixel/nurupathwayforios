// Nuru Live discovery — "invite loudly, never hijack" (owner's design). This is
// the ONE app-wide source of truth for "what's watchable right now" that feeds
// three surfaces:
//   1. A tapped `live_stream_started` push routes straight into the player (or
//      Home if the stream already ended by the time the tap lands) — see
//      RootView's `.onReceive(.nuruNotificationTap)`.
//   2. Home's mini-window pop-up for a stream this session hasn't seen yet.
//   3. The app-wide LIVE bar shown on every tab except Home while a stream is
//      live and the player isn't already open.
//
// Never originates content or gates anything — GET /live/now stays the single
// server-authoritative call; this only remembers, this session, which
// stream_ids have already been surfaced so they don't re-interrupt.
import Foundation

@MainActor
final class LiveDiscoveryCenter: ObservableObject {
    static let shared = LiveDiscoveryCenter()

    /// The latest GET /live/now rows this member may watch (server already
    /// scopes cell rows to their own cell) — ordered newest-first, matching
    /// the server's `ORDER BY started_at DESC`.
    @Published private(set) var streams: [LiveStreamSummary] = []
    /// Non-nil exactly while Home's mini-window should be showing — the
    /// stream_id it's for. One popup at a time; cleared by `dismissPopup` or
    /// `markSeen`, and never re-set for that same stream_id afterward.
    @Published private(set) var popupStreamId: String?
    /// Set by whoever presents a live player from a discovery surface (the
    /// app-wide bar tap, a routed notification tap). The bar hides while this
    /// is non-nil; `nil` again on dismiss.
    @Published var requestedItem: LivePlayableItem?

    /// stream_ids this session has already surfaced (popped up, tapped, or
    /// routed to) — never shown again as a fresh interruption this launch.
    private var seen: Set<String> = []

    private init() {}

    /// The newest stream the member may watch, if any — what the app-wide bar
    /// names and what a `live_stream_started` notification tap opens.
    var newestWatchable: LiveStreamSummary? { streams.first }

    /// Re-fetch GET /live/now and fold the result in. Best-effort: a failed
    /// fetch just leaves the previous rows in place rather than clearing them.
    func refresh() async {
        guard let rows = try? await MemberAPI.fetchLiveNow() else { return }
        ingest(rows)
    }

    /// Fold a fresh `/live/now` result (however it was fetched — Home's own
    /// poll piggybacks this too, so there is only ever one notion of "current
    /// streams") into shared state, and surface the mini-window for the
    /// first row this session hasn't already seen — a stream just noticed for
    /// the first time (whether it started seconds or minutes ago), never a
    /// second time for the same stream_id.
    func ingest(_ rows: [LiveStreamSummary]) {
        streams = rows
        guard popupStreamId == nil else { return }   // one mini-window at a time
        if let fresh = rows.first(where: { !seen.contains($0.streamId) }) {
            popupStreamId = fresh.streamId
        }
    }

    /// X dismiss on the mini-window — collapses to the ordinary LIVE banner
    /// card; this stream_id never pops up again this session.
    func dismissPopup(_ streamId: String) {
        seen.insert(streamId)
        if popupStreamId == streamId { popupStreamId = nil }
    }

    /// Any path that hands the member straight into the player (mini-window
    /// "Join live", the app-wide bar, a routed notification tap) also counts
    /// as "seen" — no popup left waiting when they come back to Home.
    func markSeen(_ streamId: String) {
        seen.insert(streamId)
        if popupStreamId == streamId { popupStreamId = nil }
    }
}
