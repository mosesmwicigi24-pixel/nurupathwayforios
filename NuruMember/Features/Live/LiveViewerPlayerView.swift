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
    private var lastProgressAt = Date()
    private var stopped = false

    init(isLive: Bool, heartbeatStreamId: String?) {
        self.isLive = isLive
        self.heartbeatStreamId = heartbeatStreamId
    }

    func start(mediaPath: String) async {
        guard let url = await MemberAPI.resolveLiveMediaURL(mediaPath) else {
            markEnded("Couldn't load this \(isLive ? "stream" : "recording").")
            return
        }
        guard !stopped else { return }   // the view was dismissed while we awaited resolution
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer
        observe(item: item, player: avPlayer)
        avPlayer.play()
        phase = .playing
        lastProgressAt = Date()
        startHeartbeat()
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
        stallTask?.cancel(); stallTask = nil
        if let timeObserverToken { player?.removeTimeObserver(timeObserverToken) }
        timeObserverToken = nil
        statusObs?.invalidate(); statusObs = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        endObserver = nil; failObserver = nil; stallObserver = nil
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
            if controller.phase != .ended { chrome }
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
                    .padding(.bottom, 230).padding(.trailing, 66)
            }
        }
        .overlay(alignment: .trailing) {
            if item.isLive, controller.phase == .playing {
                interactionRail.padding(.trailing, 12).padding(.bottom, 90)
                    .opacity(chromeSettled ? 1 : 0)
                    .offset(x: chromeSettled ? 0 : 14)
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
                    handsRaisedCount: pulseController.pulse?.hands.count ?? 0,
                    visible: $chatOverlayVisible
                )
            }
        }
        .overlay(alignment: guestBannerCollapsed ? .topTrailing : .top) {
            if item.isLive, controller.phase == .playing {
                guestInviteCard
                    .padding(.top, guestBannerCollapsed ? 104 : 168)
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
                    onLeave: { Task { await leaveGuestStage() } },
                    onRetry: { Task { await retryGuestStage() } }
                )
            }
        }
        .preferredColorScheme(.dark)
        .task { await controller.start(mediaPath: item.mediaPath) }
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

    // MARK: L5+ — reaction / hand / chat rail (TikTok-style vertical stack,
    // trailing edge) + the gold guest-invite card when a pastor has invited ME.

    private var interactionRail: some View {
        VStack(spacing: 14) {
            reactionButton(.love)
            reactionButton(.fire)
            reactionButton(.like)
            handToggleButton
            railButton(icon: "message.fill", active: chatOverlayVisible) {
                Haptics.tap(); chatOverlayVisible.toggle()
            }
            .accessibilityLabel(chatOverlayVisible ? "Hide live chat" : "Show live chat")
        }
    }

    /// One reaction button + its TikTok-style abbreviated count underneath
    /// ("999" / "1.2K" / "10K"), sourced from the pulse's server-side tally
    /// so it reflects everyone's reactions, not just mine.
    private func reactionButton(_ kind: LiveReactionKind) -> some View {
        VStack(spacing: 3) {
            Button {
                fireReaction(emoji: kind.emoji)
            } label: {
                Image(systemName: kind.systemImage)
                    .font(.system(size: 20))
                    .foregroundStyle(kind.tint)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.35), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            if let n = reactionCount(kind), n > 0 {
                Text(LiveCountFormat.abbreviated(n))
                    .font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.5), radius: 2)
            }
        }
        .accessibilityLabel(reactionAccessibilityLabel(kind))
    }

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

    /// Shared by the rail buttons AND the double-tap-the-video gesture — one
    /// cooldown (mirrors the server's ≥1s/user rate limit across every
    /// reaction kind, not per-kind) and one optimistic particle spawn.
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

    private var handToggleButton: some View {
        railButton(icon: "hand.raised.fill", active: handRaised) {
            guard !handActionInFlight else { return }
            handActionInFlight = true
            let newValue = !handRaised
            handRaised = newValue   // optimistic
            Haptics.tap()
            Task {
                try? await MemberAPI.setLiveHandRaised(streamId: item.id, raised: newValue)
                handActionInFlight = false
            }
        }
        .accessibilityLabel(handRaised ? "Lower hand" : "Raise hand")
    }

    private func railButton(icon: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? Nuru.navy : .white)
                .frame(width: 44, height: 44)
                .background(active ? Nuru.gold : Color.black.opacity(0.35), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.pressable)
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

    // MARK: Chrome — close ✕ · LIVE pill + eye "N watching" chip ·
    // broadcaster identity chip (IG-style) · title/subtitle · bottom scrim

    /// Prefers the live pulse's own count (fresher, updates every 5s) over
    /// the snapshot `item.viewerCount` was built from; falls back to that
    /// snapshot until the first pulse poll lands.
    private var displayViewerCount: Int? {
        pulseController.pulse?.viewerCount ?? item.viewerCount
    }

    private var chrome: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Button { Haptics.tap(); dismiss() } label: {
                    Icon(.x, size: 18, color: .white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.18), in: Circle())
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    if item.isLive {
                        HStack(spacing: 5) {
                            PulsingLiveDot()
                            Text("LIVE").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color(hex: 0xDC2626), in: Capsule())
                    }
                    if let vc = displayViewerCount {
                        HStack(spacing: 4) {
                            Icon(.eye, size: 10, color: .white.opacity(0.9))
                            Text("\(LiveCountFormat.abbreviated(vc)) watching")
                                .font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.9))
                                .contentTransition(.numericText())
                                .animation(.easeOut(duration: 0.25), value: vc)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.black.opacity(0.45), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 10)

            // Broadcaster identity chip — IG-style avatar + name, only when
            // we actually know who's live (`LivePlayableItem.broadcasterName`,
            // piped from `LiveStreamSummary.startedByName`; nil for a
            // recording, which never reaches this branch anyway since it
            // isn't `item.isLive`).
            if item.isLive, let name = item.broadcasterName {
                HStack(spacing: 7) {
                    // No `avatarUrl` on `LiveStreamSummary`/`LivePlayableItem`
                    // (only `startedByName` travels the wire today) — the
                    // initials idiom `Avatar(url: nil, ...)` already used here
                    // stands in until the wire carries one.
                    Avatar(url: nil, name: name, size: 28)
                        .overlay(Circle().stroke(Color.white.opacity(0.55), lineWidth: 1.5))
                    Text(name).font(.inter(12, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("HOST").font(.inter(8, .bold)).kerning(0.8).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, 6).padding(.vertical, 2.5)
                        .background(Nuru.gold, in: Capsule())
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(Color.black.opacity(0.32), in: Capsule())
                .padding(.horizontal, 16).padding(.top, 10)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.fraunces(17, .semibold)).foregroundStyle(.white)
                    .lineLimit(2)
                if let sub = item.subtitle, !sub.isEmpty {
                    Text(sub).font(.inter(12)).foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16).padding(.top, 8)

            Spacer(minLength: 0)
        }
        // Full-bleed bottom scrim (owner spec: "top+bottom gradient scrims")
        // — keeps the rail/chat/captions legible over a bright frame, same
        // idiom as the existing top scrim below.
        .background(alignment: .bottom) {
            LinearGradient(colors: [.clear, Color.black.opacity(0.6)], startPoint: .top, endPoint: .bottom)
                .frame(height: 260)
                .allowsHitTesting(false)
        }
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 170)
        }
        // Bottom too now (used to be top-only) — the new bottom scrim needs
        // to reach the true screen edge, matching the top one.
        .ignoresSafeArea(edges: item.isAudio ? Edge.Set() : [.top, .bottom])
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
        // Still gets its own close ✕ even though `chrome` is hidden in this phase.
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
