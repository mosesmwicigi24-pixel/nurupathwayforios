// Nuru Live discovery — the two "invite loudly, never hijack" surfaces that
// AREN'T the full-screen player itself:
//   - LiveMiniPopup: Home's floating muted-preview mini-window.
//   - AppLiveBar: the slim app-wide strip shown on every other tab.
// Both are pure presentation — LiveDiscoveryCenter owns all the state.
import AVFoundation
import SwiftUI

// MARK: - Muted autoplay preview (Home mini-window)

/// Bare AVPlayerLayer, muted, aspect-fill — no transport chrome at all (this
/// is a silent teaser, not a player). Falls back to a static branded tile if
/// the stream fails to resolve/load, per the owner's "acceptable fallback".
@MainActor
private final class MutedPreviewController: ObservableObject {
    @Published private(set) var player: AVPlayer?
    @Published private(set) var failed = false
    private var statusObs: NSKeyValueObservation?

    func start(mediaPath: String) async {
        guard let url = await MemberAPI.resolveLiveMediaURL(mediaPath) else { failed = true; return }
        let item = AVPlayerItem(url: url)
        statusObs = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self] in self?.failed = true }
        }
        let p = AVPlayer(playerItem: item)
        p.isMuted = true
        p.play()
        player = p
    }

    func stop() {
        statusObs?.invalidate(); statusObs = nil
        player?.pause()
        player = nil
    }
}

private struct MutedPreviewSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PreviewLayerView { PreviewLayerView(player: player) }
    func updateUIView(_ v: PreviewLayerView, context: Context) { v.player = player }
}

private final class PreviewLayerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    var player: AVPlayer? {
        get { playerLayer?.player }
        set { playerLayer?.player = newValue }
    }
    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer?.player = player
        playerLayer?.videoGravity = .resizeAspectFill
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// Small pulsing red dot shared by both discovery surfaces below (kept local —
/// the player chrome's own `PulsingLiveDot` is private to that file).
private struct DiscoveryPulseDot: View {
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

/// Home's floating mini-window: muted autoplaying preview, title, pulsing
/// LIVE, "Join live" → the full unmuted player, ✕ to dismiss (collapses to
/// the ordinary LIVE banner card and never re-pops for this stream_id).
struct LiveMiniPopup: View {
    let stream: LiveStreamSummary
    let onJoin: () -> Void
    let onDismiss: () -> Void
    @StateObject private var preview = MutedPreviewController()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.navy)
                if !stream.isAudio, let p = preview.player, !preview.failed {
                    MutedPreviewSurface(player: p)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Icon(stream.isAudio ? .audioLines : .camera, size: 20, color: Nuru.gold)
                }
            }
            .frame(width: 56, height: 56)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 5) {
                    DiscoveryPulseDot()
                    Text("LIVE").font(.inter(9, .bold)).kerning(1.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Color(hex: 0xDC2626), in: Capsule())
                Text(stream.title).font(.inter(13, .semibold)).foregroundStyle(.white).lineLimit(1)
            }
            Spacer(minLength: 6)

            Button { Haptics.action(); onJoin() } label: {
                Text("Join live").font(.inter(12, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Nuru.gold, in: Capsule())
            }
            .buttonStyle(.pressable)

            Button { Haptics.tap(); onDismiss() } label: {
                Icon(.x, size: 14, color: .white.opacity(0.7))
                    .frame(width: 26, height: 26)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(10)
        .background(
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .padding(.horizontal, Nuru.S.base)
        .task {
            guard !stream.isAudio else { return }   // audio streams show the branded icon, nothing to preview
            await preview.start(mediaPath: stream.hlsUrl)
        }
        .onDisappear { preview.stop() }
    }
}

// MARK: - App-wide LIVE bar (every tab except Home, while a stream is
// watchable and the player isn't already open)

/// Slim 36pt gold/navy strip — mirrors the radio now-playing pill's "you're
/// missing something" idiom but for Nuru Live. Tapping opens the full player.
struct AppLiveBar: View {
    let stream: LiveStreamSummary
    let onTap: () -> Void

    var body: some View {
        Button { Haptics.tap(); onTap() } label: {
            HStack(spacing: 8) {
                DiscoveryPulseDot()
                Text("LIVE").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
                Text("—").foregroundStyle(.white.opacity(0.4))
                Text(stream.title)
                    .font(.inter(12, .semibold)).foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Icon(.chevronRight, size: 14, color: .white.opacity(0.6))
            }
            .padding(.horizontal, Nuru.S.base)
            .frame(height: 36)
            .background(Nuru.navy)
        }
        .buttonStyle(.pressableSubtle)
        .overlay(alignment: .top) { Rectangle().fill(Nuru.gold.opacity(0.4)).frame(height: 1) }
    }
}

// MARK: - A Live notice whose stream is over

/// "This Live has ended" (EXPERIENCE.md §7.2 #3, §7.3) — what a Live notice
/// opens, from a banner or the inbox, once its stream is over: calm, in the
/// player's own ended look, naming the stream, and one way out — "Go back",
/// the same action as §4's "This isn't here any more" (both apps). It
/// replaced a tap that landed on Home without a word (a banner) or in a
/// greeting sheet (the inbox). When /live/now didn't answer, it says why in
/// the one state language instead — "ended" is never a guess.
struct LiveEndedView: View {
    let notice: LiveEndedNotice
    let onBack: () -> Void

    private var title: String { notice.failure?.title ?? "This Live has ended" }
    private var line: String? { notice.failure?.line ?? notice.title }

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: notice.failure == nil ? "antenna.radiowaves.left.and.right.slash" : "wifi.slash")
                .font(.system(size: 36)).foregroundStyle(Nuru.gold.opacity(0.85))
            VStack(spacing: 6) {
                Text(title)
                    .font(.fraunces(21, .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                if let line {
                    Text(line).font(.inter(13)).foregroundStyle(.white.opacity(0.6))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button { Haptics.tap(); onBack() } label: {
                Text("Go back").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 28).padding(.vertical, 12)
                    .background(Nuru.gold, in: Capsule())
            }
            .buttonStyle(.pressable)
            .padding(.top, 6)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        )
        // The way back at the top too — every full-screen state has one (§7.1 rule 3).
        .overlay(alignment: .topLeading) {
            Button { Haptics.tap(); onBack() } label: {
                Icon(.arrowLeft, size: 18, color: .white)
                    .frame(width: 38, height: 38)
                    .background(Color.white.opacity(0.18), in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Go back")
            .padding(.horizontal, 16).padding(.top, 10)
        }
        .preferredColorScheme(.dark)
    }
}
