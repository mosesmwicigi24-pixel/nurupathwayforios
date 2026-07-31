// Nuru Live L3 "Broadcast Studio" — the app-wide broadcast engine holder.
//
// Mirrors RadioCenter exactly: BEFORE this file, GoLiveBroadcastView owned
// its BroadcastController as a `@StateObject`, so the controller — and the
// live RTMP publish it drives — died the instant the view left the
// hierarchy (tab switch, `.fullScreenCover` dismiss, anything). That's the
// bug this arc exists to fix: leaving the broadcast screen must NOT end the
// stream, exactly like closing the radio player never stops the station.
//
// So the controller's lifetime is hoisted OUT of any view and into this
// singleton. The three "Go Live" entry points (NuruLiveTabView, HomeView,
// CellInfoView) no longer own a local `GoLiveSession?` + `.fullScreenCover`
// — they call `BroadcastCenter.shared.start(session:)` and RootView owns the
// ONE presentation (mirroring how RootView is already the one place that
// presents `RadioPlayerView` / `LiveViewerPlayerView`). GoLiveBroadcastView
// becomes a thin "remote control" over whatever's here, just like
// RadioPlayerView is a remote control over RadioCenter.shared.
import Foundation

@MainActor
final class BroadcastCenter: ObservableObject {
    static let shared = BroadcastCenter()

    /// Non-nil for the lifetime of an active broadcast — minted once by
    /// `start(session:)`, held onto through minimize/restore, and dropped
    /// only by `clear()`. RootView's floating island and fullScreenCover
    /// both key off this being non-nil.
    @Published private(set) var controller: BroadcastController?
    /// True while the full-screen broadcast surface is the thing on screen.
    /// False = minimized: the island takes over, but the controller keeps
    /// mixing/publishing regardless of this flag — this bool only controls
    /// which UI is showing, never the underlying RTMP connection.
    @Published var presented = false

    private var phaseTask: Task<Void, Never>?

    private init() {}

    /// Mints the controller for a freshly-created session (the setup
    /// sheet's `POST /live/streams` already succeeded server-side — this
    /// just starts publishing to it) and presents the full-screen surface.
    /// Guarded against stacking a second broadcast on top of a live one —
    /// every entry point checks `controller == nil` before offering the
    /// setup sheet in the first place (see NuruLiveTabView/HomeView/
    /// CellInfoView's `goLiveTapped`), but this is the belt-and-suspenders
    /// backstop against a race between two taps.
    func start(session: GoLiveSession) {
        guard controller == nil else { presented = true; return }
        let c = BroadcastController(session: session)
        controller = c
        presented = true
        Task { await c.start() }
        // Auto-clear once the broadcast is well and truly over — but ONLY
        // while minimized (`!presented`). While the full-screen surface is
        // up, the `.ended` phase drives the summary/permission-denied view
        // INSIDE GoLiveBroadcastView; clearing here first would yank the
        // fullScreenCover away before the broadcaster ever sees it. A
        // minimized broadcast that ends on its own (island's End tap, a
        // background drop that exhausts retries and is never manually
        // retried) has no summary screen to show, so clearing immediately
        // is correct there.
        phaseTask?.cancel()
        phaseTask = Task { [weak self, weak c] in
            guard let c else { return }
            for await phase in c.$phase.values {
                guard let self, !Task.isCancelled else { return }
                if phase == .ended, !self.presented { self.clear() }
            }
        }
    }

    /// The chevron "minimize" control on the broadcast screen — leaves the
    /// full-screen surface WITHOUT touching the controller. Mixer + RTMP
    /// keep running; the island takes over as the visible "you're live"
    /// surface on every other screen.
    func minimize() { presented = false }

    /// The island's tap target (or a re-tap of "Go live" while already
    /// broadcasting) — brings the full-screen surface back.
    func restore() { presented = true }

    /// The broadcast is genuinely over — explicit End, a permission-denied
    /// abort before anything started, or the summary/permission-denied
    /// view's own "Done"/"Close". Drops the controller so the island
    /// disappears and a fresh `start(session:)` is free to mint a new one.
    func clear() {
        phaseTask?.cancel()
        phaseTask = nil
        controller = nil
        presented = false
    }
}
