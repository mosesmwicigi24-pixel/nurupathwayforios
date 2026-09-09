// Nuru Live — the ONE full-screen viewer player, shared by a real live
// stream and a recorded replay (LivePlayableItem unifies both). Video plays
// through AVPlayerViewController (native scrubbing for replays, native
// fullscreen/AirPlay); audio plays through a bare AVPlayer behind a branded
// navy+gold waveform backdrop matching the Radio screen's aesthetic — there
// is no video track to show, so we never present a blank video surface.
//
// Heartbeat: POST /live/streams/{id}/heartbeat every 30s while the player is
// open, ONLY for a genuine live stream (LivePlayableItem.heartbeatStreamId).
// A recording never heartbeats. The timer is owned by LiveViewerPlayerController
// and is invalidated in `stop()`, called from `.onDisappear` — not merely
// paused when the view backgrounds.
//
// End-of-stream: there is no server push for "the stream just ended", so we
// infer it from AVPlayer's own signals — AVPlayerItem.status == .failed,
// .AVPlayerItemFailedToPlayToEndTime, a natural .AVPlayerItemDidPlayToEndTime
// (for a LIVE item this only fires when the source dropped, since HLS live
// playlists don't end on their own), or a stall that doesn't clear within 15s.
// Any of these retire playback into a terminal "ended" state with a "Replays"
// link — never a spinner that hangs forever.
//
// FLICKER GUARD (2026-07-31 viewer redesign): every call site that presents
// this view via `.fullScreenCover(item:)` now appends `.id(item.id)` to the
// returned view (CellInfoView, HomeView, RootView, LiveReplaysView). Reason:
// `fullScreenCover(item:)` does NOT dismiss/re-present when its bound item
// changes from one non-nil value straight to a DIFFERENT non-nil value (only
// a transition through `nil` does that) — it keeps the same presented view
// and just re-invokes the content closure. Without `.id`, this struct would
// keep its existing SwiftUI identity across that call, so its `@StateObject`
// controller/pulse controller would NOT reinitialize and `.task { controller
// .start(...) }` would NOT rerun (plain `.task` only fires on an identity
// change) — the viewer would silently go on showing the PREVIOUS stream's
// frames under the new stream's chrome. RootView is the one call site that
// can actually hit this (a second `live_stream_started` push, or the app-wide
// LIVE bar, rebinding `requestedItem` while a different stream is already
// open); the other three only ever go nil → item, but carry the guard too
// since nothing stops a future call site from doing the same.
import AVFoundation
import AVKit
import SwiftUI

@MainActor
final class LiveViewerPlayerController: ObservableObject {
    enum Phase: Equatable { case loading, playing, ended }

    @Published private(set) var phase: Phase = .loading
    @Published private(set) var endedMessage = "The stream has ended"
    @Published private(set) var player: AVPlayer?

    private let isLive: Bool
    private let heartbeatStreamId: String?

    private var statusObs: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var failObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var timeObserverToken: Any?
    private var stallTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var cdnWarmUpTask: Task<Void, Never>?
    private var lastProgressAt = Date()
    private var stopped = false

    init(isLive: Bool, heartbeatStreamId: String?) {
        self.isLive = isLive
        self.heartbeatStreamId = heartbeatStreamId
    }

    /// `fallbackPath` is the direct-origin playlist (`hls_fallback_url`). When
    /// one is present on a LIVE stream we open on it and swap to the CDN copy
    /// after a warm-up window — see `cdnWarmUpNanos` and `scheduleCDNSwap`.
    func start(mediaPath: String, fallbackPath: String? = nil) async {
        guard let url = await MemberAPI.resolveLiveMediaURL(mediaPath) else {
            markEnded("Couldn't load this \(isLive ? "stream" : "recording").")
            return
        }
        // Only a LIVE stream races a mirror, and only when the server actually
        // sent a DIFFERENT direct-origin path (no CDN configured ⇒ same path,
        // or none at all).
        var originURL: URL?
        if isLive, let raw = fallbackPath?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            originURL = await MemberAPI.resolveLiveMediaURL(raw)
        }
        let opensOnFallback = originURL != nil && originURL != url
        guard !stopped else { return }   // the view was dismissed while we awaited resolution
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = makeItem(opensOnFallback ? originURL! : url)
        let avPlayer = AVPlayer(playerItem: item)
        // Don't wait to build a buffer before starting playback — join the
        // stream as fast as the network allows rather than optimizing for a
        // stutter-free start. Applies to replays too (a faster non-live join
        // is still strictly better there, nothing live-edge-specific about
        // this one).
        avPlayer.automaticallyWaitsToMinimizeStalling = false
        player = avPlayer
        observe(item: item, player: avPlayer)
        avPlayer.play()
        phase = .playing
        lastProgressAt = Date()
        startHeartbeat()
        if opensOnFallback { scheduleCDNSwap(to: url) }
    }

    /// One configured item, so the first play and the CDN swap are identical
    /// but for the URL.
    private func makeItem(_ url: URL) -> AVPlayerItem {
        let item = AVPlayerItem(url: url)
        // LATENCY (owner ask, 2026-08-01) — configure the LIVE-edge distance
        // as tight as the client can request; server-side HLS target-latency/
        // part-duration tuning is a separate, already-scoped piece of work
        // (explicitly NOT touched here). Skipped for a replay (`!isLive`) —
        // there is no "live edge" for a finished recording, and these knobs
        // are meaningless (at best a no-op, at worst fighting normal VOD
        // scrub/buffer behavior) against one.
        if isLive {
            item.automaticallyPreservesTimeOffsetFromLive = true
            item.configuredTimeOffsetFromLive = CMTime(seconds: 3, preferredTimescale: 1)
            // Small forward buffer — the player starts playing sooner
            // (faster join) and stays closer to the live edge instead of
            // building a deep cushion, trading a little more rebuffer risk
            // for latency. The existing stall/ended handling (`noteStall`/
            // `markEnded`, 15s grace) is what makes that trade acceptable.
            item.preferredForwardBufferDuration = 2
        }
        return item
    }

    /// How long the viewer stays on the direct-origin playlist before moving
    /// to the CDN one — long enough that the edge's mirror has almost
    /// certainly caught up to a just-started stream.
    private static let cdnWarmUpNanos: UInt64 = 8_000_000_000

    /// Flicker fix, part 2 (Android parity — LivePlayerScreen's CDN_WARM_UP_MS):
    /// swap the origin playlist for the CDN one once the mirror has had time to
    /// catch up, so the viewer never sees the edge's stale copy of the PREVIOUS
    /// broadcast. Fires at most once per player; a stream that already ended (or
    /// a view that was dismissed) skips it.
    private func scheduleCDNSwap(to url: URL) {
        cdnWarmUpTask?.cancel()
        cdnWarmUpTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.cdnWarmUpNanos)
            guard !Task.isCancelled, let self, !self.stopped,
                  self.phase == .playing, let player = self.player else { return }
            let wasPlaying = player.rate > 0
            let next = self.makeItem(url)
            // The retired item's own notifications must not outlive it — a
            // discarded live item posts DidPlayToEndTime, which would retire a
            // stream that is playing perfectly well.
            self.detachItemObservers(on: player)
            player.replaceCurrentItem(with: next)
            self.observe(item: next, player: player)
            self.lastProgressAt = Date()
            if wasPlaying { player.play() }
        }
    }

    /// Drops every observer tied to the CURRENT item — including the player's
    /// periodic time observer, which `observe(item:player:)` re-adds — so a
    /// replaced item goes quiet and the swap doesn't leak one. The heartbeat is
    /// deliberately untouched: the stream is the same stream. Shared by the CDN
    /// swap and `stop()`.
    private func detachItemObservers(on player: AVPlayer?) {
        if let timeObserverToken, let player { player.removeTimeObserver(timeObserverToken) }
        timeObserverToken = nil
        statusObs?.invalidate(); statusObs = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        endObserver = nil; failObserver = nil; stallObserver = nil
        stallTask?.cancel(); stallTask = nil
    }

    private func observe(item: AVPlayerItem, player: AVPlayer) {
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.markEnded() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.markEnded(self?.isLive == true
                ? "The stream has ended" : "That's the end of the replay.") }
        }
        failObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.markEnded() }
        }
        stallObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.noteStall() }
        }
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.lastProgressAt = Date() }
        }
    }

    /// A stall alone isn't fatal (HLS blips constantly) — give it a 15s grace
    /// window; if no further progress lands by then, treat the source as gone.
    private func noteStall() {
        guard phase == .playing else { return }
        stallTask?.cancel()
        let sinceStall = Date()
        stallTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if self.lastProgressAt < sinceStall { self.markEnded() }
        }
    }

    private func markEnded(_ message: String? = nil) {
        guard phase != .ended else { return }
        endedMessage = message ?? (isLive ? "The stream has ended" : "Playback stopped unexpectedly.")
        phase = .ended
        stopHeartbeat()
        cdnWarmUpTask?.cancel(); cdnWarmUpTask = nil
        stallTask?.cancel(); stallTask = nil
        player?.pause()
    }

    /// L6b — auto-mute HLS playback while I'm publishing myself onto the
    /// stage as a guest (self-echo: my own voice would otherwise come back
    /// over the HLS pipeline's several-second delay). Purely a local volume
    /// gate — never touches AVAudioSession itself, which WhipPublisher/WebRTC
    /// owns while a guest publish is active (see WebRTCAudioCoexistence's
    /// header comment for why the HOST side needs a different fix and the
    /// viewer side doesn't).
    func setSelfEchoMuted(_ muted: Bool) {
        player?.isMuted = muted
    }

    private func startHeartbeat() {
        guard let heartbeatStreamId else { return }   // recordings never heartbeat
        heartbeatTask?.cancel()
        heartbeatTask = Task { [weak self] in
            await MemberAPI.sendHeartbeat(streamId: heartbeatStreamId)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }
                await MemberAPI.sendHeartbeat(streamId: heartbeatStreamId)
            }
        }
    }

    private func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    /// Tears everything down for good — called from `.onDisappear`. This is
    /// the ONE place the heartbeat timer and every observer are guaranteed to
    /// stop; nothing here merely "pauses" while the view is off-screen.
    func stop() {
        stopped = true
        stopHeartbeat()
        cdnWarmUpTask?.cancel(); cdnWarmUpTask = nil
        detachItemObservers(on: player)
        player?.pause()
        player = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

/// Bare AVPlayerViewController — no extra chrome of its own beyond the
/// system transport (scrub bar included, useful for replays); our title/LIVE
/// badge/viewer-count/close-✕ chrome renders in a SwiftUI overlay on top.
private struct LiveVideoSurface: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let vc = AVPlayerViewController()
        vc.player = player
        vc.showsPlaybackControls = true
        vc.videoGravity = .resizeAspect
        vc.entersFullScreenWhenPlaybackBegins = false
        vc.exitsFullScreenWhenPlaybackEnds = false
        return vc
    }

    func updateUIViewController(_ vc: AVPlayerViewController, context: Context) {
        if vc.player !== player { vc.player = player }
    }
}

/// The full-screen viewer player. Present with `.fullScreenCover(item:)`.
struct LiveViewerPlayerView: View {
    let item: LivePlayableItem
    @StateObject private var controller: LiveViewerPlayerController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var auth: AuthStore
    @State private var showReplays = false
    /// Replays opened from here default to the item's own scope (church item
    /// → church replays; a cell item → that cell's replays) so "Replays" from
    /// an ended stream lands somewhere relevant, not an unfiltered dump.
    let replaysScope: String?
    let replaysCellId: String?
    let replaysCellName: String?

    // L5 interactive stage — reactions/hand/chat/guest-invite. Gated to a
    // GENUINE live stream (never a recording): the pinned contract's stream
    // must be live for these endpoints anyway, and pretending a finished
    // replay has a live audience would be dishonest chrome.
    @StateObject private var pulseController: LivePulseController
    @StateObject private var reactionQueue = ReactionBurstQueue()
    // The floating chat overlay REPLACES the modal LiveChatSheet on the
    // viewer side (owner's exact vision) — visible by default, like an IG
    // Live comment stream; 💬 in the rail toggles it. The broadcaster keeps
    // the modal sheet unchanged (GoLiveBroadcastView).
    @State private var chatOverlayVisible = true
    @State private var handRaised = false
    @State private var handActionInFlight = false
    @State private var reactionCooldown = false
    @State private var respondingToInvite = false
    /// IG-style double-tap-the-video-to-love bursts — one big heart per tap,
    /// positioned at the tap point, self-removing after its pop animation.
    @State private var bigHearts: [BigHeartBurst] = []
    // Guest banner auto-collapse (owner taste pass, 2026-07-31): the gold
    // invite/"on stage soon" card is loud by design (it needs to be seen),
    // but persisting full-size for the rest of the stream buries the
    // content under it. It shows expanded for ~3s on every FRESH status
    // (invited → shown big; the moment it flips to accepted after a
    // response → shown big again), then auto-collapses into a small
    // tappable corner pill. `lastGuestBannerStatus` is what detects "fresh".
    @State private var guestBannerCollapsed = false
    @State private var lastGuestBannerStatus: String?
    @State private var guestBannerCollapseTask: Task<Void, Never>?
    // L6b — real WebRTC video once MY guest row is `accepted`: WhipPublisher
    // owns the actual camera+mic publish; `guestStageActive` just guards
    // against starting it twice for the same accepted window (see
    // `syncGuestStage`). GuestStagePiP (the draggable self-preview) replaces
    // the old static "video in the next update" banner entirely.
    @StateObject private var guestPublisher = WhipPublisher()
    @State private var guestStageActive = false
    // Gentle entrance for the chrome itself (host chip, LIVE/watching pills) —
    // Reduce Motion just skips the fade/slide and shows everything settled.
    @State private var chromeSettled = false

    private struct BigHeartBurst: Identifiable {
        let id = UUID()
        let point: CGPoint
    }

    init(item: LivePlayableItem, replaysScope: String? = nil, replaysCellId: String? = nil, replaysCellName: String? = nil) {
        self.item = item
        self.replaysScope = replaysScope
        self.replaysCellId = replaysCellId
        self.replaysCellName = replaysCellName
        _controller = StateObject(wrappedValue: LiveViewerPlayerController(
            isLive: item.isLive, heartbeatStreamId: item.heartbeatStreamId))
        _pulseController = StateObject(wrappedValue: LivePulseController(streamId: item.id, intervalSeconds: 5))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch controller.phase {
            case .loading:
                ProgressView().tint(Nuru.gold)
            case .playing:
                if item.isAudio {
                    LiveAudioBackdrop(title: item.title, isLive: item.isLive)
                } else if let p = controller.player {
                    LiveVideoSurface(player: p).ignoresSafeArea()
                }
            case .ended:
                endedState
            }
            // Double-tap-to-love, TikTok/IG-style. Scoped to a genuine live
            // stream only — a replay keeps AVPlayerViewController's native
            // scrub/tap-to-toggle-controls behavior untouched (this L5 layer
            // never mounts over a finished recording anyway). A transparent
            // full-bleed tap target UNDER the chrome/rail/chat overlays below:
            // their own Buttons still win the hit-test at their own bounds,
            // this only catches taps in the open video area.
            if item.isLive, controller.phase == .playing {
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(SpatialTapGesture(count: 2).onEnded { value in
                        handleDoubleTapHeart(at: value.location)
                    })
            }
        }
        .overlay(alignment: .top) {
            // Pinned via `.overlay(alignment: .top)`, NOT a plain ZStack
            // child — this ZStack's default alignment is `.center`, and
            // unlike the old `chrome` (which force-filled the frame with a
            // trailing `Spacer` so its own top-alignment governed things),
            // `topBar` is just its own intrinsic ~60pt height. Without an
            // explicit top alignment it would render vertically CENTERED,
            // not pinned under the safe area.
            if controller.phase != .ended { topBar }
        }
        .overlay {
            // The big hearts themselves — absolutely positioned at the tap
            // point, never hit-testable so they can never eat a later tap.
            ForEach(bigHearts) { burst in
                BigHeartBurstView().position(burst.point)
            }
            .allowsHitTesting(false)
        }
        .overlay(alignment: .bottomTrailing) {
            if item.isLive, controller.phase == .playing {
                FloatingReactionsOverlay(queue: reactionQueue)
                    .padding(.bottom, dockHeight + 20).padding(.trailing, 24)
            }
        }
        .overlay(alignment: .bottom) {
            // ONE bottom dock — owner spec: "EVERY control lives there".
            // Replaces the old right-edge floating rail; sits on its own
            // gradient scrim (LiveChromeScrim.bottom, applied inside
            // `liveBottomDock`) instead of floating bare over the content.
            if item.isLive, controller.phase == .playing {
                liveBottomDock
                    .opacity(chromeSettled ? 1 : 0)
                    .offset(y: chromeSettled ? 0 : 14)
            }
        }
        .overlay {
            // Floating chat — draggable, self-positioning (full-bleed overlay
            // so it can be dragged anywhere on screen; see
            // LiveFloatingChatOverlay's own header comment). Stays MOUNTED
            // whenever the player is live so its 3s poll never resets — 💬 in
            // the rail only toggles its own opacity/hit-testing, not its
            // presence in the tree.
            if item.isLive, controller.phase == .playing {
                LiveFloatingChatOverlay(
                    streamId: item.id, myUserId: auth.profile?.userId,
                    myFullName: auth.profile?.fullName, myAvatarUrl: auth.profile?.avatarUrl,
                    handsRaisedCount: pulseController.pulse?.hands.count ?? 0,
                    visible: $chatOverlayVisible
                )
            }
        }
        .overlay(alignment: guestBannerCollapsed ? .topTrailing : .top) {
            // Top padding tuned to clear the new ONE-LINE top bar (owner
            // redesign, 2026-08-01) — much shorter than the old three-row
            // chrome this used to clear, so the banner now sits right under
            // it instead of far down the screen.
            if item.isLive, controller.phase == .playing {
                guestInviteCard
                    .padding(.top, guestBannerCollapsed ? 66 : 92)
                    .padding(.trailing, guestBannerCollapsed ? 14 : 0)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: guestBannerCollapsed)
        .overlay {
            // L6b — the draggable self-preview once I'm an accepted guest.
            // Full-bleed so GuestStagePiP can position/drag itself, same
            // idiom as the floating chat overlay.
            if guestStageActive {
                GuestStagePiP(
                    publisher: guestPublisher,
                    onRetry: { Task { await retryGuestStage() } }
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { await controller.start(mediaPath: item.mediaPath,
                                       fallbackPath: item.mediaFallbackPath) }
        .task {
            guard item.isLive else { return }
            pulseController.start()
        }
        .onDisappear {
            controller.stop()
            pulseController.stop()
            guestBannerCollapseTask?.cancel()
            guestStageActive = false
            Task { await guestPublisher.stop() }
        }
        .onChange(of: pulseController.freshReactions) { _, fresh in
            guard !fresh.isEmpty else { return }
            for r in fresh { reactionQueue.spawn(emoji: r.emoji, reduceMotion: reduceMotion) }
            pulseController.clearFreshReactions()
        }
        .onChange(of: pulseController.pulse?.hands) { _, hands in
            guard !handActionInFlight, let myId = auth.profile?.userId else { return }
            handRaised = (hands ?? []).contains { $0.userId == myId }
        }
        .onChange(of: pulseController.pulse?.guests) { _, guests in
            scheduleGuestBannerAutoCollapse(for: guests)
            syncGuestStage(guests)
        }
        .onChange(of: guestStageActive) { _, active in
            controller.setSelfEchoMuted(active)
        }
        .sheet(isPresented: $showReplays) {
            LiveReplaysView(scope: replaysScope, cellId: replaysCellId, cellName: replaysCellName)
        }
    }

    // MARK: L6b — guest stage lifecycle (real WHIP publish)

    /// Starts publishing the FIRST time my `pulse.guests` row reads
    /// "accepted"; tears down the instant it stops being that (host removed
    /// me, I left via `leaveGuestStage`, or the stream ended and the pulse
    /// loop stops delivering my row at all — `guests` still resolves to nil
    /// status in that case, which the `default` branch below treats the same
    /// as removed).
    private func syncGuestStage(_ guests: [LiveGuestRow]?) {
        guard let myId = auth.profile?.userId else { return }
        let status = guests?.first(where: { $0.userId == myId })?.status
        switch status {
        case "accepted":
            guard !guestStageActive else { return }
            guestStageActive = true
            Task { await beginGuestPublishing() }
        default:
            guard guestStageActive else { return }
            guestStageActive = false
            Task { await guestPublisher.stop() }
        }
    }

    private func beginGuestPublishing() async {
        guard let myId = auth.profile?.userId else { return }
        guard let ingest = try? await MemberAPI.fetchLiveGuestIngest(streamId: item.id) else {
            guestPublisher.markFailed("Couldn't join the stage — try again.")
            return
        }
        await guestPublisher.start(whipURLString: ingest.whipUrl, user: myId, pass: ingest.token)
    }

    private func retryGuestStage() async {
        guestPublisher.resetToIdle()
        await beginGuestPublishing()
    }

    /// The self-preview's "Leave stage" pill — stops publishing AND tells the
    /// server (self = leave, per the pinned guest contract), then refreshes
    /// the pulse immediately so the banner/rail elsewhere reflect it without
    /// waiting out the rest of the 5s poll window.
    private func leaveGuestStage() async {
        guestStageActive = false
        await guestPublisher.stop()
        if let myId = auth.profile?.userId {
            try? await MemberAPI.removeLiveGuest(streamId: item.id, userId: myId)
        }
        await pulseController.pollNow()
    }

    /// Owner taste pass — the gold guest INVITE banner shows big on any FRESH
    /// "invited" status, then collapses to a corner pill 3s later. Scoped to
    /// `invited` only (L6b): once accepted, GuestStagePiP's own draggable
    /// self-preview takes over as the "you're on stage" chrome — there's no
    /// longer a static banner for that status to show/collapse.
    private func scheduleGuestBannerAutoCollapse(for guests: [LiveGuestRow]?) {
        guard let myId = auth.profile?.userId else { return }
        let status = guests?.first(where: { $0.userId == myId })?.status
        guard status != lastGuestBannerStatus else { return }
        lastGuestBannerStatus = status
        guestBannerCollapseTask?.cancel()
        guestBannerCollapsed = false
        guard status == "invited" else { return }
        guestBannerCollapseTask = Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            guestBannerCollapsed = true
        }
    }

    // MARK: Double-tap-to-love (video area)

    private func handleDoubleTapHeart(at point: CGPoint) {
        // fireReaction() already fires the .love() haptic (and no-ops silently
        // under the shared cooldown) — the big heart pop is purely visual and
        // never gated by that cooldown, exactly like IG's double-tap, which
        // always pops even if the last one was a moment ago.
        if reduceMotion {
            // Reduce Motion: no flying/popping heart — just the reaction
            // itself, same as every other reaction path under Reduce Motion
            // (ReactionBurstQueue's own static-counter fallback covers it).
            fireReaction(emoji: "love")
            return
        }
        let burst = BigHeartBurst(point: point)
        bigHearts.append(burst)
        fireReaction(emoji: "love")
        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            bigHearts.removeAll { $0.id == burst.id }
        }
    }

    // MARK: ONE bottom dock (owner redesign, 2026-08-01) — replaces the old
    // right-edge floating rail. Role flips to `.guestOnStage` the instant my
    // own `guestPublisher` is actively publishing, which fans the dock out
    // to a second row of stage-hardware controls (camera/switch/mic/
    // speaker/leave) — see LiveDockLayout.rows for the pure ordering logic
    // this reads, pinned by LiveDockChromeTests.

    private var dockRole: LiveDockRole { guestStageActive ? .guestOnStage : .viewer }
    /// Real (not guessed) height budget for the two overlays that must clear
    /// this dock without overlapping it — the floating reactions burst and
    /// LiveFloatingChatOverlay's own clamp. One row ≈ 78pt (44pt tile +
    /// caption + padding); a guest-on-stage dock adds a second row.
    private var dockHeight: CGFloat {
        LiveDockLayout.rows(role: dockRole).count > 1 ? 168 : 92
    }

    private var liveBottomDock: some View {
        VStack(spacing: 10) {
            ForEach(Array(LiveDockLayout.rows(role: dockRole).enumerated()), id: \.offset) { _, row in
                HStack(spacing: 16) {
                    ForEach(row) { dockButton(for: $0) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(alignment: .bottom) { LiveChromeScrim.bottom(height: dockHeight + 90) }
    }

    @ViewBuilder
    private func dockButton(for item: LiveDockItem) -> some View {
        switch item {
        case .reaction(let kind):
            LiveDockIconButton(
                systemImage: kind.systemImage,
                caption: reactionCount(kind).flatMap { $0 > 0 ? LiveCountFormat.abbreviated($0) : nil },
                accessibilityLabel: reactionAccessibilityLabel(kind)
            ) { fireReaction(emoji: kind.emoji) }
        case .raiseHand:
            LiveDockIconButton(
                systemImage: "hand.raised.fill", active: handRaised,
                accessibilityLabel: handRaised ? "Lower hand" : "Raise hand"
            ) { toggleHand() }
        case .chat:
            LiveDockIconButton(
                systemImage: "message.fill", active: chatOverlayVisible,
                accessibilityLabel: chatOverlayVisible ? "Hide live chat" : "Show live chat"
            ) { Haptics.tap(); chatOverlayVisible.toggle() }
        case .camera:
            LiveDockIconButton(
                systemImage: guestPublisher.isVideoEnabled ? "video.fill" : "video.slash.fill",
                active: !guestPublisher.isVideoEnabled, disabled: guestPublisher.state != .live,
                accessibilityLabel: guestPublisher.isVideoEnabled ? "Turn your camera off" : "Turn your camera on"
            ) { Haptics.tap(); guestPublisher.toggleVideo() }
        case .switchCamera:
            LiveDockIconButton(
                systemImage: "arrow.triangle.2.circlepath.camera.fill",
                disabled: guestPublisher.state != .live,
                accessibilityLabel: "Switch camera"
            ) { Haptics.tap(); Task { await guestPublisher.flipCamera() } }
        case .mic:
            LiveDockIconButton(
                systemImage: guestPublisher.isMuted ? "mic.slash.fill" : "mic.fill",
                active: guestPublisher.isMuted, disabled: guestPublisher.state != .live,
                accessibilityLabel: guestPublisher.isMuted ? "Unmute your mic" : "Mute your mic"
            ) { Haptics.tap(); guestPublisher.toggleMute() }
        case .speaker:
            LiveDockIconButton(
                systemImage: guestPublisher.isSpeakerOn ? "speaker.wave.2.fill" : "speaker.fill",
                active: !guestPublisher.isSpeakerOn, disabled: guestPublisher.state != .live,
                accessibilityLabel: guestPublisher.isSpeakerOn ? "Switch to earpiece" : "Switch to speaker"
            ) { Haptics.tap(); guestPublisher.toggleSpeaker() }
        case .leave:
            LiveDockDangerButton(title: "Leave stage") {
                Haptics.action(); Task { await leaveGuestStage() }
            }
        case .end, .documentPage:
            EmptyView()   // viewer/guest dock never shows broadcaster-only items
        }
    }

    /// One cooldown (mirrors the server's ≥1s/user rate limit across every
    /// reaction kind, not per-kind) and one optimistic particle spawn —
    /// shared by the dock's reaction buttons AND the double-tap-the-video
    /// gesture.
    private func fireReaction(emoji: String) {
        guard !reactionCooldown else { return }
        Haptics.love()
        reactionQueue.spawn(emoji: emoji, reduceMotion: reduceMotion)   // optimistic, instant
        reactionCooldown = true
        Task {
            try? await MemberAPI.reactToLiveStream(streamId: item.id, emoji: emoji)
            try? await Task.sleep(nanoseconds: 900_000_000)   // mirrors the server's ≥1s/user rate limit
            reactionCooldown = false
        }
    }

    /// TikTok-style abbreviated count ("999"/"1.2K") under a reaction
    /// button, sourced from the pulse's server-side tally so it reflects
    /// everyone's reactions, not just mine.
    private func reactionCount(_ kind: LiveReactionKind) -> Int? {
        guard let r = pulseController.pulse?.reactions else { return nil }
        switch kind {
        case .love: return r.love
        case .fire: return r.fire
        case .like: return r.like
        }
    }

    private func reactionAccessibilityLabel(_ kind: LiveReactionKind) -> String {
        switch kind {
        case .love: return "Send a love reaction"
        case .fire: return "Send a fire reaction"
        case .like: return "Send a like reaction"
        }
    }

    private func toggleHand() {
        guard !handActionInFlight else { return }
        handActionInFlight = true
        let newValue = !handRaised
        handRaised = newValue   // optimistic — instant per the owner's latency ask
        Haptics.tap()
        Task {
            try? await MemberAPI.setLiveHandRaised(streamId: item.id, raised: newValue)
            handActionInFlight = false
        }
    }

    /// The gold "invited on stage" card — shown while MY guest row is
    /// `invited`; swaps to the honest "joining soon" banner once `accepted`
    /// (L6 video itself is the next phase, so this never claims more than
    /// the plumbing that actually exists today). Auto-collapses to
    /// `collapsedGuestPill` 3s after appearing (`scheduleGuestBannerAutoCollapse`).
    ///
    /// DEFENSE-IN-DEPTH (owner screenshot bug, see LiveDiscoveryCenter.ingest's
    /// header comment for the actual root cause/fix): a guest row can only
    /// ever exist for a DIFFERENT stream than the one I'm broadcasting — the
    /// backend refuses to let a broadcaster invite themselves as a guest of
    /// their own stream — so the `item.id == BroadcastCenter...streamId`
    /// check below should never actually trigger. It costs nothing to keep
    /// as a second line of defense against this exact class of bug
    /// recurring some other way (e.g. a future change to how streams get
    /// discovered).
    @ViewBuilder private var guestInviteCard: some View {
        if item.id == BroadcastCenter.shared.controller?.session.stream.streamId {
            EmptyView()
        } else if let myId = auth.profile?.userId,
           let mine = pulseController.pulse?.guests.first(where: { $0.userId == myId }),
           mine.status == "invited" {
            // "accepted" no longer renders here at all — GuestStagePiP (a
            // separate full-bleed overlay, see `body`) is the entire "you're
            // on stage" chrome once accepted.
            if guestBannerCollapsed {
                collapsedGuestPill
            } else {
                guestInviteBanner
            }
        } else {
            EmptyView()
        }
    }

    /// The small tappable corner pill the invite banner collapses into.
    private var collapsedGuestPill: some View {
        Button {
            Haptics.tap()
            guestBannerCollapseTask?.cancel()
            guestBannerCollapsed = false
        } label: {
            HStack(spacing: 6) {
                Icon(.handHeart, size: 12, color: Nuru.navy)
                Text("Invited on stage")
                    .font(.inter(10.5, .bold)).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Nuru.gold, in: Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, y: 3)
        }
        .buttonStyle(.pressable)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
    }

    private var guestInviteBanner: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Icon(.handHeart, size: 18, color: Nuru.navy)
                Text("You're invited on stage").font(.inter(13, .bold)).foregroundStyle(Nuru.navy)
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.action()
                    Task { await respondToInvite(accept: true) }
                } label: {
                    Text("Accept").font(.inter(13, .bold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Nuru.navy, in: Capsule())
                }
                .buttonStyle(.pressable)
                Button {
                    Haptics.tap()
                    Task { await respondToInvite(accept: false) }
                } label: {
                    Text("Decline").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 38)
                        .background(Color.white.opacity(0.5), in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .disabled(respondingToInvite)
        .opacity(respondingToInvite ? 0.6 : 1)
        .padding(14)
        .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 12, y: 5)
        .padding(.horizontal, 24)
    }

    private func respondToInvite(accept: Bool) async {
        guard !respondingToInvite else { return }
        respondingToInvite = true
        defer { respondingToInvite = false }
        try? await MemberAPI.respondToLiveGuestInvite(streamId: item.id, accept: accept)
        await pulseController.pollNow()
    }

    // MARK: ONE top row (owner redesign, 2026-08-01) — close ✕ · host avatar
    // + name · stream title · LIVE pill · counters (viewers, hands raised),
    // all on a SINGLE line directly under the safe area. Replaces the old
    // three stacked rows (close+badges, host chip, title/subtitle) — see
    // LiveDockChrome.swift's header comment for why the top scrim ignores
    // safe area on its own while this HStack's controls stay safely inset by
    // SwiftUI's own default layout.

    /// Prefers the live pulse's own count (fresher, updates every 5s) over
    /// the snapshot `item.viewerCount` was built from; falls back to that
    /// snapshot until the first pulse poll lands.
    private var displayViewerCount: Int? {
        pulseController.pulse?.viewerCount ?? item.viewerCount
    }

    private var handsRaisedCount: Int { pulseController.pulse?.hands.count ?? 0 }

    /// Host name + stream title on ONE line via SwiftUI `Text` concatenation
    /// (each segment keeps its own font/weight) — the subtitle and the old
    /// separate "HOST" tag are dropped here in the name of fitting
    /// everything on one line without crowding; the subtitle is still shown
    /// in Replays/discovery, it just isn't essential chrome while watching.
    private var nameTitleLine: Text {
        var line = Text("")
        var hasName = false
        if item.isLive, let name = item.broadcasterName {
            line = Text(name).font(.inter(13, .bold)).foregroundStyle(.white)
            hasName = true
        }
        if hasName, !item.title.isEmpty {
            line = line + Text("  ·  ").font(.inter(11)).foregroundStyle(.white.opacity(0.45))
        }
        return line + Text(item.title).font(.inter(12, .medium)).foregroundStyle(.white.opacity(0.85))
    }

    private var topBar: some View {
        HStack(spacing: 9) {
            // 44pt — owner's tap-target floor, honored for every control on
            // this screen, top row included (the old close ✕ was 38pt).
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.x, size: 15, color: .white)
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Close")

            if item.isLive, let name = item.broadcasterName {
                Avatar(url: nil, name: name, size: 24)
                    .overlay(Circle().stroke(Color.white.opacity(0.5), lineWidth: 1.2))
            }

            nameTitleLine
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 6)

            if item.isLive {
                HStack(spacing: 4) {
                    PulsingLiveDot()
                    Text("LIVE").font(.inter(9, .bold)).kerning(1.2).foregroundStyle(.white)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(hex: 0xDC2626), in: Capsule())
            }
            if let vc = displayViewerCount {
                LiveTopStatChip(systemImage: "eye.fill", value: LiveCountFormat.abbreviated(vc))
                    .contentTransition(.numericText())
                    .animation(.easeOut(duration: 0.25), value: vc)
            }
            if handsRaisedCount > 0 {
                LiveTopStatChip(systemImage: "hand.raised.fill", value: "\(handsRaisedCount)", tint: Nuru.gold)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(alignment: .top) { LiveChromeScrim.top() }
        .allowsHitTesting(true)
        // TikTok-style gentle entrance — the chrome settles in with a soft
        // fade + slide-down rather than snapping on the instant playback
        // starts. Reduce Motion skips straight to the settled state.
        .opacity(chromeSettled ? 1 : 0)
        .offset(y: chromeSettled ? 0 : -10)
        .onAppear {
            guard !reduceMotion else { chromeSettled = true; return }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.82).delay(0.05)) { chromeSettled = true }
        }
    }

    // MARK: Ended state — never a spinner that hangs forever

    private var endedState: some View {
        VStack(spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 36)).foregroundStyle(Nuru.gold.opacity(0.85))
            VStack(spacing: 4) {
                Text(controller.endedMessage)
                    .font(.fraunces(19, .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text(item.title).font(.inter(12)).foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Button { Haptics.tap(); showReplays = true } label: {
                    Text("Replays").font(.inter(13, .bold)).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(Nuru.gold, in: Capsule())
                }
                .buttonStyle(.pressable)
                Button { Haptics.tap(); dismiss() } label: {
                    Text("Close").font(.inter(13, .semibold)).foregroundStyle(.white.opacity(0.75))
                        .padding(.horizontal, 20).padding(.vertical, 11)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        // Still gets its own close ✕ even though `topBar` is hidden in this phase.
        .overlay(alignment: .topLeading) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.x, size: 18, color: .white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, 16).padding(.top, 10)
        }
    }
}

/// One IG-style big heart pop for the video's double-tap gesture — scales up
/// past 1x then settles back down while fading out, over ~0.9s. Purely
/// decorative (`allowsHitTesting(false)` at the call site); never renders
/// under Reduce Motion (the caller skips spawning one in that case).
private struct BigHeartBurstView: View {
    @State private var scale: CGFloat = 0.4
    @State private var opacity: Double = 1

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.system(size: 88))
            .foregroundStyle(Color(hex: 0xE0245E))
            .shadow(color: .black.opacity(0.35), radius: 8)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { scale = 1.15 }
                withAnimation(.easeIn(duration: 0.25).delay(0.5)) { opacity = 0 }
                withAnimation(.easeOut(duration: 0.5).delay(0.35)) { scale = 1.0 }
            }
    }
}

/// Small pulsing red dot — the LIVE badge's heartbeat (matches Radio's PulsingDot
/// language; kept local since that one is private to RadioPlayerView.swift).
private struct PulsingLiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        Circle().fill(.white).frame(width: 6, height: 6)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

/// Audio-kind branded backdrop — navy + gold with a breathing waveform, the
/// Radio screen's "on air" aesthetic, standing in for a video surface that
/// doesn't exist for an audio-only stream.
private struct LiveAudioBackdrop: View {
    let title: String
    let isLive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(RadialGradient(colors: [Nuru.gold.opacity(0.28), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 380, height: 380)
                .blur(radius: 30)
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Nuru.gold.opacity(0.14)).frame(width: 132, height: 132)
                    Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1.5).frame(width: 132, height: 132)
                    Icon(.audioLines, size: 46, color: Nuru.gold)
                }
                waveform
                Text(isLive ? "LISTENING LIVE" : "REPLAY")
                    .font(.inter(10, .bold)).kerning(1.6)
                    .foregroundStyle(Nuru.gold.opacity(0.85))
                Text(title).font(.fraunces(18, .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { animate = true }
        }
    }

    private var waveform: some View {
        HStack(spacing: 4) {
            ForEach(0..<9, id: \.self) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(Nuru.gold.opacity(0.7))
                    .frame(width: 4, height: barHeight(i))
            }
        }
        .frame(height: 34)
        .accessibilityHidden(true)
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard !reduceMotion else { return 12 }
        let base: [CGFloat] = [10, 22, 14, 30, 18, 26, 12, 20, 16]
        let h = base[i % base.count]
        return animate ? h : max(6, h * 0.4)
    }
}
