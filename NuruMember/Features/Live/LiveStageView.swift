// Nuru Live L7 — the broadcaster's own Zoom-style stage: one full-bleed
// main tile (whoever's spotlighted — host by default) plus a rail of
// thumbnails down the right edge for everyone else. Tapping a rail
// thumbnail promotes it to main and demotes whoever was main into the
// rail; tapping the current main tile again (when it's a guest) reverts to
// host. Replaces L6b/L6c's `GuestTileRail` (a fixed top-left rail drawn
// over an ALWAYS-raw-camera background that never reflected who was
// spotlighted) — see LiveStageCompositor's L7 header comment for why that
// mismatch mattered: the broadcast's composited frame could show a guest
// full-frame while the host's own screen kept showing raw camera + a
// small rail, i.e. exactly the "preview doesn't match what viewers
// receive" the task brief calls out.
//
// Geometry comes from LiveStageLayout — the SAME rect math
// LiveStageCompositor uses for the actual composited RTMP frame, just fed
// this view's screen size instead of the encoder's 1080x1920 canvas. Two
// renderers still can't literally share pixels (one draws into a
// CVPixelBuffer HaishinKit encodes, the other is a live SwiftUI/UIKit
// view tree), but they now share layout math and identical spotlight
// state (`BroadcastController.stageSpotlight`), so "who's main and where
// everyone else sits" can't drift even though the two are drawn by
// completely different renderers.
//
// Video surfaces are NOT created/destroyed on a spotlight swap — the SAME
// `MTHKViewRepresentable` (host) and `WebRTCVideoView` (each guest)
// instances persist for the whole broadcast; only their frame/position/
// corner-radius change, driven by `controller.stageSpotlight` and
// animated — that's what keeps a swap flicker-free (task quality bar: "no
// flicker on swap, no black frames on join/leave").
import HaishinKit
import SwiftUI
import WebRTC

struct LiveStageView: View {
    @ObservedObject var controller: BroadcastController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let swapDuration = 0.25

    private var spotlighted: UInt8 { controller.stageSpotlight.spotlighted }
    private var tiles: [BroadcastController.GuestTileState] { Array(controller.guestTiles.prefix(6)) }

    /// Rail participant order — host first, then guests in join order,
    /// filtered to whoever ISN'T spotlighted — mirrors
    /// `LiveStageCompositor.participants.filter { $0 != spotlighted }`
    /// exactly, so rail slot N here is the same participant as rail slot N
    /// in the composited broadcast frame.
    private var railTracks: [UInt8] {
        (([0] as [UInt8]) + tiles.map(\.track)).filter { $0 != spotlighted }
    }

    var body: some View {
        GeometryReader { geo in
            let canvas = geo.size
            let mainRect = LiveStageLayout.mainRect(canvas: canvas)
            let radius = LiveStageLayout.cornerRadius(canvas: canvas)
            let railRectByTrack = Dictionary(
                uniqueKeysWithValues: zip(railTracks, LiveStageLayout.railRects(count: railTracks.count, canvas: canvas))
            )

            ZStack {
                hostTile(mainRect: mainRect, railRectByTrack: railRectByTrack, radius: radius)
                ForEach(tiles) { tile in
                    guestTile(tile, mainRect: mainRect, railRectByTrack: railRectByTrack, radius: radius)
                }
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Host tile

    @ViewBuilder
    private func hostTile(mainRect: CGRect, railRectByTrack: [UInt8: CGRect], radius: CGFloat) -> some View {
        let isMain = spotlighted == 0
        let rect = isMain ? mainRect : (railRectByTrack[0] ?? mainRect)
        MTHKViewRepresentable(previewSource: controller, videoGravity: .resizeAspectFill)
            .overlay(alignment: .bottomLeading) {
                if !isMain { railChrome(name: "You", isMuted: false) }
            }
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: isMain ? 0 : radius, style: .continuous))
            .overlay {
                if !isMain {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
                }
            }
            .shadow(color: .black.opacity(isMain ? 0 : 0.35), radius: isMain ? 0 : 8, y: isMain ? 0 : 4)
            .position(x: rect.midX, y: rect.midY)
            .zIndex(isMain ? 0 : 1)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isMain else { return }
                Haptics.tap()
                controller.tapStageTile(0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isMain ? "You — main video" : "You — tap to make main video")
            .accessibilityAddTraits(isMain ? [] : .isButton)
            .animation(reduceMotion ? nil : .easeInOut(duration: Self.swapDuration), value: rect)
    }

    // MARK: - Guest tile

    @ViewBuilder
    private func guestTile(
        _ tile: BroadcastController.GuestTileState,
        mainRect: CGRect,
        railRectByTrack: [UInt8: CGRect],
        radius: CGFloat
    ) -> some View {
        let isMain = spotlighted == tile.track
        let rect = isMain ? mainRect : (railRectByTrack[tile.track] ?? mainRect)
        let isMuted = controller.guestMuteHeuristic[tile.userId] ?? false
        ZStack {
            Color.black
            switch tile.subscriber.state {
            case .connecting:
                ProgressView().tint(Nuru.gold)
            case .live:
                WebRTCVideoView(track: tile.subscriber.videoTrack)
            case .failed(let message):
                guestFailureOverlay(message: message, subscriber: tile.subscriber, compact: !isMain)
            case .ended:
                EmptyView()
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !isMain { railChrome(name: tile.fullName, isMuted: isMuted) }
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: isMain ? 0 : radius, style: .continuous))
        .overlay {
            if !isMain {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1.5)
            }
        }
        .shadow(color: .black.opacity(isMain ? 0 : 0.35), radius: isMain ? 0 : 8, y: isMain ? 0 : 4)
        .position(x: rect.midX, y: rect.midY)
        .zIndex(isMain ? 0 : 1)
        .contentShape(Rectangle())
        .onTapGesture {
            Haptics.tap()
            controller.tapStageTile(tile.track)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            (isMain ? "\(tile.fullName) — main video" : "\(tile.fullName) — tap to make main video")
                + (isMuted ? ", muted" : "")
        )
        .accessibilityAddTraits(.isButton)
        // A `.failed` guest still needs a VoiceOver-reachable Retry — the
        // in-tile Retry button is visually present but this view collapses
        // its children into one accessibility element (so tapping ANYWHERE
        // on the tile spotlights it, not just a tiny button), so expose
        // Retry as a custom action instead, same as pre-L7 GuestTileRail did.
        .accessibilityAction(named: "Retry") {
            if case .failed = tile.subscriber.state {
                Task { await tile.subscriber.retry() }
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Self.swapDuration), value: rect)
    }

    @ViewBuilder
    private func guestFailureOverlay(message: String, subscriber: WhepSubscriber, compact: Bool) -> some View {
        VStack(spacing: compact ? 3 : 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: compact ? 13 : 22)).foregroundStyle(Nuru.gold.opacity(0.9))
            Text(message).font(.inter(compact ? 7 : 12, .semibold)).foregroundStyle(.white.opacity(0.85))
                .multilineTextAlignment(.center).lineLimit(compact ? 3 : 4)
                .padding(.horizontal, compact ? 5 : 24)
            Button {
                Task { await subscriber.retry() }
            } label: {
                Text("Retry").font(.inter(compact ? 7 : 13, .bold)).foregroundStyle(Nuru.gold)
                    .padding(.horizontal, compact ? 8 : 16).padding(.vertical, compact ? 3 : 8)
                    .background(Capsule().fill(Color.white.opacity(0.15)))
            }
        }
    }

    /// Name + mic-muted indicator over the bottom of a RAIL tile only — the
    /// main tile is full-bleed chrome, matching task requirement C. Uses a
    /// real SF Symbol (unlike the composited broadcast, which is limited to
    /// HaishinKit's text-only screen objects — see
    /// `LiveStageCompositor.setMuted`'s header comment).
    @ViewBuilder
    private func railChrome(name: String, isMuted: Bool) -> some View {
        HStack(spacing: 4) {
            if isMuted {
                Image(systemName: "mic.slash.fill").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            }
            Text(name).font(.inter(9, .bold)).foregroundStyle(.white).lineLimit(1)
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .center, endPoint: .bottom))
        .allowsHitTesting(false)
    }
}
