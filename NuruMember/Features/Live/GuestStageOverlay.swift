// Nuru Live L6b — the GUEST's own small self-preview once they're actually
// publishing (or connecting/failed) — replaces the old static "You're on
// stage soon — video joins in the next update" gold banner for an ACCEPTED
// guest. The gold INVITE banner itself (status == "invited", not yet
// accepted) is untouched — see LiveViewerPlayerView.guestInviteCard.
//
// Draggable anywhere on screen, same idiom as LiveFloatingChatOverlay
// (GestureState translation + settled offset, clamped to stay on screen and
// clear of the top/bottom chrome) — default corner is top-trailing, tucked
// under the LIVE/watching pills.
import SwiftUI
import WebRTC

struct GuestStagePiP: View {
    @ObservedObject var publisher: WhipPublisher
    let onLeave: () -> Void
    let onRetry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var settledOffset: CGSize = .zero

    private static let tileSize = CGSize(width: 96, height: 128)
    private static let margin: CGFloat = 14
    private static let topInset: CGFloat = 190
    private static let bottomInset: CGFloat = 230

    private var screen: CGSize { UIScreen.main.bounds.size }
    private var defaultOrigin: CGPoint {
        CGPoint(x: screen.width - Self.tileSize.width - Self.margin, y: Self.topInset)
    }
    private var origin: CGPoint {
        let raw = CGPoint(x: defaultOrigin.x + settledOffset.width + dragTranslation.width,
                           y: defaultOrigin.y + settledOffset.height + dragTranslation.height)
        let minX = Self.margin
        let maxX = max(minX, screen.width - Self.tileSize.width - Self.margin)
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
        VStack(spacing: 6) {
            tile
            actionsRow
            if publisher.state == .live {
                Text("Muted while on stage").font(.inter(8.5, .semibold)).foregroundStyle(.white.opacity(0.65))
            }
        }
        .frame(width: Self.tileSize.width + 24)
        .position(x: origin.x + Self.tileSize.width / 2, y: origin.y + 60)
        .gesture(dragGesture)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: publisher.state)
    }

    @ViewBuilder private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.black)
            switch publisher.state {
            case .idle, .connecting:
                VStack(spacing: 6) {
                    ProgressView().tint(Nuru.gold)
                    Text("Joining stage…").font(.inter(9, .semibold)).foregroundStyle(.white.opacity(0.8))
                }
            case .live:
                WebRTCVideoView(track: publisher.localVideoTrack)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack {
                    HStack {
                        Spacer()
                        muteButton
                    }
                    Spacer()
                }
                .padding(6)
            case .failed(let message):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16)).foregroundStyle(Nuru.gold)
                    Text(message).font(.inter(8, .semibold)).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center).lineLimit(3)
                        .padding(.horizontal, 6)
                }
            case .ended:
                EmptyView()
            }
        }
        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.gold.opacity(0.6), lineWidth: 1.5))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private var muteButton: some View {
        Button {
            Haptics.tap()
            publisher.toggleMute()
        } label: {
            Image(systemName: publisher.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(publisher.isMuted ? "Unmute your mic" : "Mute your mic")
    }

    @ViewBuilder private var actionsRow: some View {
        if case .failed = publisher.state {
            Button {
                Haptics.tap()
                onRetry()
            } label: {
                Text("Retry").font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(Nuru.gold, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        Button {
            Haptics.action()
            onLeave()
        } label: {
            Text("Leave stage").font(.inter(9.5, .bold)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(hex: 0xDC2626), in: Capsule())
        }
        .buttonStyle(.pressable)
    }
}
