// Nuru Live discovery — "invite loudly, never hijack" (owner's design). This is
// the ONE app-wide source of truth for "what's watchable right now" that feeds
// three surfaces:
//   1. A tapped Live notice — a banner or an inbox row, the same way
//      (NoticeRouter, EXPERIENCE.md §7.2 #3) — routes straight into the
//      player, or to a calm "This Live has ended" once the stream is over.
//   2. Home's mini-window pop-up for a stream this session hasn't seen yet.
//   3. The app-wide LIVE bar shown on every tab except Home while a stream is
//      live and the player isn't already open.
//
// Never originates content or gates anything — GET /live/now stays the single
// server-authoritative call; this only remembers, this session, which
// stream_ids have already been surfaced so they don't re-interrupt.
import Foundation

/// A Live notice tapped after its stream ended — RootView shows "This Live
/// has ended" with the stream's name, instead of an error, a blank player or
/// a silent jump to Home.
struct LiveEndedNotice: Identifiable, Equatable {
    let id = UUID()
    /// The notice's own title for the stream ("Ring check"); nil when it had none.
    let title: String?
    /// Set when /live/now didn't answer — whether it's still live isn't
    /// known, so the screen says why (§4) instead of "ended".
    var failure: NuruStateCopy? = nil
}

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
    /// A tapped Live notice whose stream is over — RootView presents "This
    /// Live has ended"; nil again on Close.
    @Published var endedNotice: LiveEndedNotice?

    /// stream_ids this session has already surfaced (popped up, tapped, or
    /// routed to) — never shown again as a fresh interruption this launch.
    private var seen: Set<String> = []

    private init() {}

    /// The newest stream the member may watch, if any — what the app-wide bar
    /// names and what a `live_stream_started` notification tap opens.
    var newestWatchable: LiveStreamSummary? { streams.first }

    /// Re-fetch GET /live/now and fold the result in. Best-effort: a failed
    /// fetch just leaves the previous rows in place rather than clearing them
    /// (and says why, for a caller that must not guess).
    @discardableResult
    func refresh() async -> Error? {
        do {
            ingest(try await MemberAPI.fetchLiveNow())
            return nil
        } catch {
            return error
        }
    }

    /// A tapped Live notice (`live_stream_started`, `live_guest_invite`) —
    /// from a banner or the inbox, one way (EXPERIENCE.md §7.2 #3): re-check
    /// /live/now (the stream may have ended by the time the tap lands), then
    /// the player for the stream it names — a guest invite's own card waits
    /// inside — or, once that stream is over, "This Live has ended". Never
    /// some other stream in its place. A notice from this phone's own
    /// broadcast brings the broadcast back.
    func openNotice(streamId: String?, title: String?) async {
        if let own = BroadcastCenter.shared.controller?.session.stream.streamId, own == streamId {
            BroadcastCenter.shared.restore()
            return
        }
        let failure = await refresh()
        if let stream = Self.noticeTarget(in: streams, named: streamId) {
            markSeen(stream.streamId)
            requestedItem = .live(stream)
        } else {
            // Not live — or, when /live/now didn't answer, not known: that
            // is said in the one state language, never guessed as "ended".
            endedNotice = LiveEndedNotice(title: title, failure: failure.map { NuruStateCopy.failure($0) })
        }
    }

    /// The stream a Live notice opens, from the watchable rows: exactly the
    /// one it names (nil once that one is over — never another in its
    /// place), or the newest when it names none (an older notice). Pure.
    nonisolated static func noticeTarget(in rows: [LiveStreamSummary], named streamId: String?) -> LiveStreamSummary? {
        guard let streamId, !streamId.isEmpty else { return rows.first }
        return rows.first { $0.streamId == streamId }
    }

    /// Fold a fresh `/live/now` result (however it was fetched — Home's own
    /// poll piggybacks this too, so there is only ever one notion of "current
    /// streams") into shared state, and surface the mini-window for the
    /// first row this session hasn't already seen — a stream just noticed for
    /// the first time (whether it started seconds or minutes ago), never a
    /// second time for the same stream_id.
    ///
    /// GUARD (owner bug report, 2026-07-31 taste pass): `/live/now` has no
    /// notion of "and don't tell ME about MY OWN stream" — the row for a
    /// broadcaster's own currently-live stream comes back exactly like
    /// anyone else's. Left unfiltered, that let a broadcaster who minimized
    /// their own broadcast tap the app-wide LIVE bar (or Home's mini-window,
    /// or a routed `live_stream_started` push for their own stream) straight
    /// into `LiveViewerPlayerView` for the stream THEY are publishing — the
    /// screenshot bug was that view's guest-invite/"on stage soon" chrome
    /// rendering on top of what should have been their own broadcast surface.
    /// The one and only currently-active `BroadcastCenter` session (if any)
    /// is always this device's own — dropping its stream_id here means none
    /// of the three discovery surfaces (bar/mini-window/notification) can
    /// EVER offer a broadcaster their own stream as something to "watch".
    func ingest(_ rows: [LiveStreamSummary]) {
        let ownStreamId = BroadcastCenter.shared.controller?.session.stream.streamId
        streams = ownStreamId == nil ? rows : rows.filter { $0.streamId != ownStreamId }
        guard popupStreamId == nil else { return }   // one mini-window at a time
        if let fresh = streams.first(where: { !seen.contains($0.streamId) }) {
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
