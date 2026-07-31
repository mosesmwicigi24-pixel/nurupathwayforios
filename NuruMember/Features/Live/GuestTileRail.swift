// Nuru Live L6b — the broadcaster's rail of live guest video tiles, one per
// accepted guest with a running WhepSubscriber (BroadcastController.guestTiles,
// diffed against the pulse roster on every 3s poll). Rendered as a single
// draggable unit over the camera preview in GoLiveBroadcastView — same
// drag-anywhere idiom as LiveFloatingChatOverlay, default top-leading corner
// (the chat overlay defaults bottom-leading, the hands/source buttons live
// top-trailing, so this is the one open corner).
import SwiftUI
import WebRTC

struct GuestTileRail: View {
    let tiles: [BroadcastController.GuestTileState]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    private static let tileSize = CGSize(width: 96, height: 128)
    private static let spacing: CGFloat = 8
    private static let margin: CGFloat = 12
    private static let topInset: CGFloat = 150
    private static let bottomInset: CGFloat = 210

    private var screen: CGSize { UIScreen.main.bounds.size }
    private var shown: [BroadcastController.GuestTileState] { Array(tiles.prefix(6)) }
    private var railWidth: CGFloat {
        guard !shown.isEmpty else { return 0 }
        return CGFloat(shown.count) * Self.tileSize.width + CGFloat(shown.count - 1) * Self.spacing
    }
    private var defaultOrigin: CGPoint { CGPoint(x: Self.margin, y: Self.topInset) }
    private var origin: CGPoint {
        let raw = CGPoint(x: defaultOrigin.x + settledOffset.width + dragTranslation.width,
                           y: defaultOrigin.y + settledOffset.height + dragTranslation.height)
        let minX = Self.margin
        let maxX = max(minX, screen.width - railWidth - Self.margin)
        let minY = Self.topInset
        let maxY = max(minY, screen.height - Self.bottomInset - Self.tileSize.height)
        return CGPoint(x: min(max(raw.x, minX), maxX), y: min(max(raw.y, minY), maxY))
    }
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                settledOffset.width += value.translation.width
                settledOffset.height += value.translation.height
            }
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(shown) { tile in
                GuestTileView(tile: tile)
            }
        }
        .frame(width: max(railWidth, 1), height: Self.tileSize.height, alignment: .leading)
        .position(x: origin.x + railWidth / 2, y: origin.y + Self.tileSize.height / 2)
        .gesture(dragGesture)
        .opacity(shown.isEmpty ? 0 : 1)
        .allowsHitTesting(!shown.isEmpty)
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.82), value: shown.map(\.id))
    }
}

private struct GuestTileView: View {
    @ObservedObject var subscriber: WhepSubscriber
    let fullName: String

    init(tile: BroadcastController.GuestTileState) {
        subscriber = tile.subscriber
        fullName = tile.fullName
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.black)
            switch subscriber.state {
            case .connecting:
                ProgressView().tint(Nuru.gold)
            case .live:
                WebRTCVideoView(track: subscriber.videoTrack)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14)).foregroundStyle(Nuru.gold.opacity(0.85))
            case .ended:
                EmptyView()
            }
            LinearGradient(colors: [.clear, .black.opacity(0.75)], startPoint: .center, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .allowsHitTesting(false)
            Text(fullName).font(.inter(9, .bold)).foregroundStyle(.white).lineLimit(1)
                .padding(.horizontal, 6).padding(.bottom, 5)
        }
        .frame(width: 96, height: 128)
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.white.opacity(0.2), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
    }
}
