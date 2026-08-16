// Nuru Live L5 — floating reaction particles, shared by the broadcaster HUD
// (fed from pulse.recent_reactions — everyone else's hearts/thumbs) and the
// viewer overlay (fed from BOTH a local optimistic tap on ❤️/👍 AND the
// pulse, so a viewer's own reaction floats instantly and others' trickle in
// on the 5s poll). Classic live-stream feel: rises from the bottom-right,
// drifts with a little random x-jitter, eases out over ~2s. Capped at ~10
// concurrent particles; under Reduce Motion, swaps to a static counter chip
// instead of suppressing the feature entirely.
import SwiftUI

/// "like" | "love" | "fire" → the glyph + tint a particle renders as. "fire"
/// added alongside like/love (owner ask, 2026-07-31) — the backend accepts it
/// as a third `emoji` value on the same pinned `POST .../reactions` endpoint.
enum LiveReactionKind {
    case like, love, fire

    init(emoji: String) {
        switch emoji {
        case "love": self = .love
        case "fire": self = .fire
        default: self = .like
        }
    }

    var emoji: String { self == .love ? "love" : self == .fire ? "fire" : "like" }
    var systemImage: String {
        switch self {
        case .love: return "heart.fill"
        case .fire: return "flame.fill"
        case .like: return "hand.thumbsup.fill"
        }
    }
    var tint: Color {
        switch self {
        case .love: return Color(hex: 0xE0245E)
        case .fire: return Color(hex: 0xF97316)
        case .like: return Nuru.gold
        }
    }
}

/// TikTok-style abbreviated counter — "999", "1.2K", "10K", "3.4M". Never
/// shows more than one decimal, and drops a trailing ".0" ("10.0K" → "10K").
enum LiveCountFormat {
    static func abbreviated(_ n: Int) -> String {
        switch n {
        case ..<1000:
            return "\(n)"
        case ..<1_000_000:
            return format(Double(n) / 1000, suffix: "K")
        default:
            return format(Double(n) / 1_000_000, suffix: "M")
        }
    }

    private static func format(_ value: Double, suffix: String) -> String {
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() {
            return "\(Int(rounded))\(suffix)"
        }
        return String(format: "%.1f%@", rounded, suffix)
    }
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
