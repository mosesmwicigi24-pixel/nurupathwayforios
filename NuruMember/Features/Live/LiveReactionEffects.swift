// Nuru Live L5 — floating reaction particles, shared by the broadcaster HUD
// (fed from pulse.recent_reactions — everyone else's hearts/thumbs) and the
// viewer overlay (fed from BOTH a local optimistic tap on ❤️/👍 AND the
// pulse, so a viewer's own reaction floats instantly and others' trickle in
// on the 5s poll). Classic live-stream feel: rises from the bottom-right,
// drifts with a little random x-jitter, eases out over ~2s. Capped at ~10
// concurrent particles; under Reduce Motion, swaps to a static counter chip
// instead of suppressing the feature entirely.
import SwiftUI

/// "like" | "love" → the glyph + tint a particle renders as.
enum LiveReactionKind {
    case like, love

    init(emoji: String) { self = emoji == "love" ? .love : .like }

    var systemImage: String { self == .love ? "heart.fill" : "hand.thumbsup.fill" }
    var tint: Color { self == .love ? Color(hex: 0xE0245E) : Nuru.gold }
}

private struct LiveReactionParticle: Identifiable {
    let id = UUID()
    let kind: LiveReactionKind
    let xJitter: CGFloat = CGFloat.random(in: -30...30)
}

/// One instance per screen (broadcaster HUD, viewer player) — owns the live
/// particle set and the Reduce-Motion fallback counter.
@MainActor
final class ReactionBurstQueue: ObservableObject {
    @Published fileprivate var particles: [LiveReactionParticle] = []
    @Published private(set) var reduceMotionTotal = 0
    private let cap = 10

    func spawn(emoji: String, reduceMotion: Bool) {
        if reduceMotion {
            reduceMotionTotal += 1
            return
        }
        guard particles.count < cap else { return }   // classic live-stream feel, not a firehose
        particles.append(LiveReactionParticle(kind: LiveReactionKind(emoji: emoji)))
    }

    fileprivate func remove(_ id: UUID) {
        particles.removeAll { $0.id == id }
    }
}

/// Pin with `.overlay(alignment: .bottomTrailing)` over the video/preview
/// surface. Hit-testing is disabled throughout — it never steals a tap from
/// the controls underneath.
struct FloatingReactionsOverlay: View {
    @ObservedObject var queue: ReactionBurstQueue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if reduceMotion {
                if queue.reduceMotionTotal > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "heart.fill").font(.system(size: 11)).foregroundStyle(Color(hex: 0xE0245E))
                        Text("\(queue.reduceMotionTotal)").font(.inter(11, .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.black.opacity(0.45), in: Capsule())
                }
            } else {
                ForEach(queue.particles) { particle in
                    LiveReactionParticleView(particle: particle) { queue.remove(particle.id) }
                }
            }
        }
        .allowsHitTesting(false)
        .frame(width: 70, height: 240)
    }
}

private struct LiveReactionParticleView: View {
    fileprivate let particle: LiveReactionParticle
    let onFinished: () -> Void
    @State private var rise: CGFloat = 0
    @State private var fade: Double = 1

    var body: some View {
        Image(systemName: particle.kind.systemImage)
            .font(.system(size: 22))
            .foregroundStyle(particle.kind.tint)
            .shadow(color: .black.opacity(0.3), radius: 3)
            .offset(x: particle.xJitter, y: -rise)
            .opacity(fade)
            .onAppear {
                withAnimation(.easeOut(duration: 2.0)) {
                    rise = 220
                    fade = 0
                }
                Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    onFinished()
                }
            }
    }
}
