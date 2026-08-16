// Nuru Live L5 — the VIEWER-side pulse poller (5s, per docs/LIVE_INTERACTIVE.md
// "one poll for the whole overlay"). The broadcaster's own pulse poll lives
// directly on BroadcastController (folded in alongside its existing
// startViewerPolling, same 3s cadence) rather than a second instance of this
// type, since that controller already owns the RTMP lifecycle the poll must
// start/stop with. This one is for LiveViewerPlayerView, whose lifecycle is
// just "the player is on screen".
import Foundation

@MainActor
final class LivePulseController: ObservableObject {
    @Published private(set) var pulse: LivePulse?
    /// Reactions newly seen since the previous poll — consumed once by the
    /// view (spawn a particle per entry) then cleared via `clearFreshReactions()`.
    /// The very first poll seeds `seenReactionKeys` WITHOUT publishing anything
    /// here, so opening the player never floods the screen with a stream's
    /// entire reaction history at once.
    @Published private(set) var freshReactions: [LiveRecentReaction] = []

    private let streamId: String
    private let intervalNanos: UInt64
    private var task: Task<Void, Never>?
    private var seenReactionKeys: Set<String> = []
    private var isFirstPoll = true

    init(streamId: String, intervalSeconds: UInt64 = 5) {
        self.streamId = streamId
        self.intervalNanos = intervalSeconds * 1_000_000_000
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            await self.poll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: self.intervalNanos)
                guard !Task.isCancelled else { return }
                await self.poll()
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    /// Manual out-of-cadence refresh — called right after an action that
    /// should reflect immediately (e.g. responding to a guest invite) rather
    /// than waiting out the rest of the 5s window.
    func pollNow() async { await poll() }

    func clearFreshReactions() { freshReactions = [] }

    private func poll() async {
        guard let p = try? await MemberAPI.fetchLivePulse(streamId: streamId) else { return }
        var newOnes: [LiveRecentReaction] = []
        for r in p.recentReactions {
            let key = "\(r.emoji)|\(r.at)"
            guard !seenReactionKeys.contains(key) else { continue }
            seenReactionKeys.insert(key)
            if !isFirstPoll { newOnes.append(r) }
        }
        isFirstPoll = false
        // The server only ever sends a short recent window, so this never
        // grows unbounded across a real viewing session — trimmed defensively.
        if seenReactionKeys.count > 500 { seenReactionKeys.removeAll() }
        pulse = p
        if !newOnes.isEmpty { freshReactions = newOnes }
    }
}
