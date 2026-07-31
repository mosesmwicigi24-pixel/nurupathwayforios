// Nuru Live L6b — the GUEST's own small self-preview once they're actually
// publishing (or connecting/failed) — replaces the old static "You're on
// stage soon — video joins in the next update" gold banner for an ACCEPTED
// guest. The gold INVITE banner itself (status == "invited", not yet
// accepted) is untouched — see LiveViewerPlayerView.guestInviteCard.
//
// Draggable anywhere on screen, same idiom as LiveFloatingChatOverlay
// (GestureState translation + settled offset, clamped to stay on screen and
// clear of the top/bottom chrome).
//
// OWNER REDESIGN (2026-08-01):
//   - Default corner moved from top-TRAILING to top-LEADING (owner spec:
//     "the floating self-preview moves to the LEFT") — it used to sit under
//     the LIVE/watching pills on the right; now it sits under the single top
//     row on the left, clear of the counters cluster on the right.
//   - Minimizable: a tap on the small chevron collapses the whole tile to a
//     round handle (same visual language as LiveFloatingChatOverlay's own
//     bubble), tap the handle to restore. `GuestPreviewVisibility`
//     (LiveDockChrome.swift) is the pure reducer behind this — collapsed
//     state persists for as long as this view stays mounted (i.e. the
//     lifetime of one stage session), and a FRESH stage window always starts
//     expanded again (see that enum's header comment).
//   - Mute + "Leave stage" are GONE from this tile — every control now lives
//     in the unified bottom dock (`LiveDockLayout`/`LiveViewerPlayerView`'s
//     `liveBottomDock`), per the owner's "nothing floats over the content,
//     EVERY control lives in the dock" spec. This view is now JUST the video
//     surface + drag + minimize — a Retry affordance stays INLINE for a
//     `.failed` connection though (mirrors LiveStageView's own
//     `guestFailureOverlay` precedent: a connection-recovery action stays on
//     the tile it's actually about, not exported to a global dock).
import SwiftUI
import WebRTC

struct GuestStagePiP: View {
    @ObservedObject var publisher: WhipPublisher
    let onRetry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @GestureState private var dragTranslation: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @State private var visibility: GuestPreviewVisibility = .expanded

    private static let tileSize = CGSize(width: 92, height: 122)
    private static let handleDiameter: CGFloat = 46
    private static let margin: CGFloat = 14
    /// Clears the single top row (see LiveViewerPlayerView's `topBar`).
    private static let topInset: CGFloat = 78
    /// Clears the two-row bottom dock (see LiveDockLayout.rows — up to two
    /// rows of 44pt controls once a guest is on stage).
    private static let bottomInset: CGFloat = 196

    private var screen: CGSize { UIScreen.main.bounds.size }
    private var currentSize: CGSize {
        visibility == .collapsed ? CGSize(width: Self.handleDiameter, height: Self.handleDiameter) : Self.tileSize
    }
    private var defaultOrigin: CGPoint {
        CGPoint(x: Self.margin, y: Self.topInset)
    }
    private var origin: CGPoint {
        let raw = CGPoint(x: defaultOrigin.x + settledOffset.width + dragTranslation.width,
                           y: defaultOrigin.y + settledOffset.height + dragTranslation.height)
        let minX = Self.margin
        let maxX = max(minX, screen.width - currentSize.width - Self.margin)
        let minY = Self.topInset
        let maxY = max(minY, screen.height - Self.bottomInset - currentSize.height)
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
        Group {
            if visibility == .collapsed { handle } else { expandedTile }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .position(x: origin.x + currentSize.width / 2, y: origin.y + currentSize.height / 2)
        .gesture(dragGesture)
        .transition(.scale(scale: 0.6).combined(with: .opacity))
        .animation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8), value: publisher.state)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: visibility)
        // A fresh stage window (accepted → left → re-accepted) always starts
        // back at `.expanded` — see GuestPreviewVisibility's header comment.
        .onAppear { visibility = visibility.reduce(.stageBecameActive) }
    }

    // MARK: Expanded — video + minimize chevron (+ Retry inline if failed)

    @ViewBuilder private var expandedTile: some View {
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
                    .opacity(publisher.isVideoEnabled ? 1 : 0.25)
                if !publisher.isVideoEnabled {
                    Image(systemName: "video.slash.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.85))
                }
            case .failed(let message):
                VStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16)).foregroundStyle(Nuru.gold)
                    Text(message).font(.inter(8, .semibold)).foregroundStyle(.white.opacity(0.85))
                        .multilineTextAlignment(.center).lineLimit(3)
                        .padding(.horizontal, 6)
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
            case .ended:
                EmptyView()
            }
        }
        .frame(width: Self.tileSize.width, height: Self.tileSize.height)
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.gold.opacity(0.6), lineWidth: 1.5))
        .overlay(alignment: .topTrailing) { minimizeButton }
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
    }

    private var minimizeButton: some View {
        Button {
            Haptics.tap()
            visibility = visibility.reduce(.toggle)
        } label: {
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.pressable)
        .padding(4)
        .accessibilityLabel("Minimize your self-preview")
    }

    // MARK: Collapsed — a small round handle, tap to restore

    private var handle: some View {
        Button {
            Haptics.tap()
            visibility = visibility.reduce(.toggle)
        } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().stroke(Nuru.gold.opacity(0.6), lineWidth: 1.5)
                Image(systemName: "person.crop.rectangle.fill")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(Nuru.gold)
            }
        }
        .environment(\.colorScheme, .dark)
        .buttonStyle(.pressable)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .accessibilityLabel("Restore your self-preview")
    }
}
