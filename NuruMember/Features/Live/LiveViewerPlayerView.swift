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
    @State private var showReplays = false
    /// Replays opened from here default to the item's own scope (church item
    /// → church replays; a cell item → that cell's replays) so "Replays" from
    /// an ended stream lands somewhere relevant, not an unfiltered dump.
    let replaysScope: String?
    let replaysCellId: String?
    let replaysCellName: String?

    init(item: LivePlayableItem, replaysScope: String? = nil, replaysCellId: String? = nil, replaysCellName: String? = nil) {
        self.item = item
        self.replaysScope = replaysScope
        self.replaysCellId = replaysCellId
        self.replaysCellName = replaysCellName
        _controller = StateObject(wrappedValue: LiveViewerPlayerController(
            isLive: item.isLive, heartbeatStreamId: item.heartbeatStreamId))
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
            if controller.phase != .ended { chrome }
        }
        .preferredColorScheme(.dark)
        .task { await controller.start(mediaPath: item.mediaPath) }
        .onDisappear { controller.stop() }
        .sheet(isPresented: $showReplays) {
            LiveReplaysView(scope: replaysScope, cellId: replaysCellId, cellName: replaysCellName)
        }
    }

    // MARK: Chrome — close ✕ · LIVE badge + viewer count · title/subtitle

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
                    if let vc = item.viewerCount {
                        HStack(spacing: 4) {
                            Icon(.users, size: 10, color: .white.opacity(0.9))
                            Text("\(vc) watching").font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Color.black.opacity(0.45), in: Capsule())
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 10)

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
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.7), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 170)
        }
        .ignoresSafeArea(edges: item.isAudio ? Edge.Set() : Edge.Set.top)
        .allowsHitTesting(true)
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
