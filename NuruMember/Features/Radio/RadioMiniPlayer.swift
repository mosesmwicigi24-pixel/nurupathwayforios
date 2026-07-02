// Floating now-playing ISLAND — the design's Dynamic-Island-style capsule shown
// by the shell while Nuru Radio is tuned and the full player page is closed.
// Driven entirely by RadioCenter.shared: pulsing red dot · 10-bar gold wave
// (dances while playing, settles to half-height when paused) · gold play/pause.
// Tapping the dot/wave area calls `onOpen` (the shell reopens the full player);
// the parent owns placement — this file only builds the capsule itself, with
// its own spring-in/out transition when the station tunes/powers down.
import SwiftUI

// MARK: - MiniWave — small animated waveform (island + recordings rows)

/// The design's MiniWave: `count` slim bars whose base heights follow a fixed
/// sin/cos contour; while playing each bar loops scaleY 0.4→1 on its own
/// staggered period, paused they all settle at half height. Deterministic
/// TimelineView drive (no fire-and-forget repeatForever), so pausing never
/// strands a bar mid-loop; holds still under Reduce Motion.
struct RadioMiniWave: View {
    let playing: Bool
    var count: Int = 9
    var height: CGFloat = 16
    var color: Color = Nuru.gold

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var active: Bool { playing && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !active)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<count, id: \.self) { i in
                    Capsule()
                        .fill(color)
                        .frame(width: 2, height: baseHeight(i))
                        .scaleEffect(y: scaleY(i, t), anchor: .center)
                }
            }
            .frame(height: height)
        }
        .accessibilityHidden(true)
    }

    /// Design contour: 0.35 + 0.65·|sin(i·1.5)·0.6 + cos(i·0.7)·0.4|, min 3pt.
    private func baseHeight(_ i: Int) -> CGFloat {
        let base = 0.35 + 0.65 * abs(sin(Double(i) * 1.5) * 0.6 + cos(Double(i) * 0.7) * 0.4)
        return max(3, height * base)
    }

    /// Playing: loop between 0.4 and 1 with the design's staggered periods
    /// (0.55 + (i%5)·0.1 per half-cycle). Paused/Reduce Motion: 0.5.
    private func scaleY(_ i: Int, _ t: Double) -> CGFloat {
        guard active else { return 0.5 }
        let halfCycle = 0.55 + Double(i % 5) * 0.1
        let phase = sin((t / halfCycle) * .pi + Double(i) * 1.7)   // -1…1, offset per bar
        return 0.4 + 0.6 * CGFloat((phase + 1) / 2)
    }
}

// MARK: - The island capsule

struct RadioMiniPlayer: View {
    @ObservedObject private var center = RadioCenter.shared
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dotDim = false

    init(onOpen: @escaping () -> Void) { self.onOpen = onOpen }

    // ── Hardware geometry ──────────────────────────────────────────────
    /// True on Dynamic Island phones (top safe-area inset ≥ 51pt). Apps cannot
    /// draw INSIDE the cutout (iOS composites the black island over foreground
    /// apps — Apple Music's in-island wave is the SYSTEM's, shown once the app
    /// backgrounds; ours does that too via Now Playing). In-app we hang a slim
    /// dock off the island's bottom edge instead: narrower than the cutout and
    /// overlapping its bottom curve, so black merges into black and it reads
    /// as the island growing a chin with a living wave.
    static var isIslandDevice: Bool { topInset >= 51 }
    static var topInset: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 59
    }
    /// Cutout ≈ 126×37 with its top edge ~11pt down. The dock tucks under it:
    /// y = 11 + 37 − overlap. Never wider than the island, never beside it —
    /// so it can't collide with the clock or the wifi/battery cluster.
    static var dockTop: CGFloat { isIslandDevice ? 41 : topInset + 4 }

    var body: some View {
        // The `if let` lives inside a container so the spring transition
        // actually runs when the radio is tuned/stopped (attached to conditional
        // content directly, SwiftUI would pop it in with no animation).
        ZStack {
            if center.program != nil {
                if Self.isIslandDevice { islandDock } else { floatingCapsule }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.65), value: center.program?.id)
    }

    // ── Island dock (hangs from the cutout's bottom edge) ──────────────
    private var islandDock: some View {
        HStack(spacing: 7) {
            Button {
                Haptics.tap()
                onOpen()
            } label: {
                HStack(spacing: 5) {
                    pulsingDot
                    RadioMiniWave(playing: center.playing, count: 6, height: 10)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Open Nuru Radio")

            Button {
                Haptics.tap()
                center.togglePlay()
            } label: {
                Image(systemName: center.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Nuru.gold)
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: center.playing ? 0 : 0.5)
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .animation(.easeInOut(duration: 0.2), value: center.playing)
            .accessibilityLabel(center.playing ? "Pause radio" : "Play radio")
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        // Squared top / round bottom — the seam hides under the island's own
        // bottom curve, so dock + cutout read as one black shape.
        .background(Color.black, in: UnevenRoundedRectangle(
            topLeadingRadius: 6, bottomLeadingRadius: 13,
            bottomTrailingRadius: 13, topTrailingRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityHint("Nuru Radio is playing — opens the full player")
    }

    // ── Free-floating capsule (notch / older devices) ──────────────────
    private var floatingCapsule: some View {
        HStack(spacing: 8) {
            Button {
                Haptics.tap()
                onOpen()
            } label: {
                HStack(spacing: 8) {
                    pulsingDot
                    RadioMiniWave(playing: center.playing, count: 10, height: 16)
                }
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Open Nuru Radio")

            Button {
                Haptics.tap()
                center.togglePlay()
            } label: {
                Image(systemName: center.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Nuru.gold)
                    .contentTransition(.symbolEffect(.replace))
                    .offset(x: center.playing ? 0 : 1)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .animation(.easeInOut(duration: 0.2), value: center.playing)
            .accessibilityLabel(center.playing ? "Pause radio" : "Play radio")
        }
        .padding(.vertical, 6)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .background(Color.black, in: Capsule())
        .shadow(color: .black.opacity(0.7), radius: 14, y: 12)
        .transition(.offset(y: -24).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
        .accessibilityHint("Nuru Radio is playing — opens the full player")
    }

    /// 6pt red dot, breathing 1→0.2→1 over ~1s (static under Reduce Motion).
    private var pulsingDot: some View {
        Circle()
            .fill(Color(hex: 0xEF4444))
            .frame(width: 6, height: 6)
            .opacity(dotDim ? 0.2 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true)) {
                    dotDim = true
                }
            }
    }
}
