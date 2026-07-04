// Celebration layer — the app's "human moments". Warm, once-only pop-ups and
// confetti fired by REAL server milestones (rhythm complete, streak marks, new
// badges, a confirmed gift, a prayer landing on the wall). Mirrors the Android
// member app's celebration layer.
//
// Rules of the house:
//   · Server truth only — a moment fires from data the server returned, never
//     from optimistic client state.
//   · Once only — every moment carries a key; fired keys persist in
//     UserDefaults so a milestone never replays across launches.
//   · One at a time — moments queue; the next appears after the current one
//     is dismissed.
import SwiftUI

@MainActor
final class CelebrationCenter: ObservableObject {
    static let shared = CelebrationCenter()

    struct Moment: Identifiable, Equatable {
        let id = UUID()
        let key: String
        let title: String
        let subtitle: String?
        let confetti: Bool
    }

    /// The moment currently on screen (nil = nothing showing).
    @Published private(set) var current: Moment?
    private var queue: [Moment] = []

    /// Keys that have already celebrated — persisted so a milestone fires once
    /// EVER, not once per launch.
    private var firedKeys: Set<String>
    private static let storeKey = "nuru.celebrations.fired"

    private init() {
        firedKeys = Set(UserDefaults.standard.stringArray(forKey: Self.storeKey) ?? [])
    }

    /// Fire a celebration for a server milestone. No-op when this key has
    /// already celebrated. `confetti: false` renders as a gold top banner that
    /// auto-dismisses after 3s instead of the full confetti card.
    func fire(key: String, title: String, subtitle: String? = nil, confetti: Bool = true) {
        guard !firedKeys.contains(key) else { return }
        firedKeys.insert(key)
        UserDefaults.standard.set(Array(firedKeys), forKey: Self.storeKey)
        let moment = Moment(key: key, title: title, subtitle: subtitle, confetti: confetti)
        if current == nil { present(moment) } else { queue.append(moment) }
    }

    func dismiss() {
        current = nil
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        // A small breath between back-to-back moments so each one lands.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            if current == nil { present(next) }
        }
    }

    private func present(_ moment: Moment) {
        current = moment
        if moment.confetti {
            Haptics.success()
        } else {
            Haptics.tap()
            // Banners are glanceable — they excuse themselves after 3s.
            let id = moment.id
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                if current?.id == id { dismiss() }
            }
        }
    }
}

// MARK: - Host (mounted ONCE over the root tab shell)

struct CelebrationHost: View {
    @ObservedObject private var center = CelebrationCenter.shared

    var body: some View {
        ZStack {
            if let moment = center.current {
                if moment.confetti {
                    confettiMoment(moment)
                        .transition(.opacity)
                } else {
                    banner(moment)
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: center.current?.id)
    }

    // Full ceremony: dim scrim, the shared gold confetti burst, and a warm
    // centered card — Fraunces title, Inter subtitle, gold "Amen 🙌" dismiss.
    private func confettiMoment(_ moment: CelebrationCenter.Moment) -> some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { center.dismiss() }
            CelebrationConfetti()
                .allowsHitTesting(false)
            card(moment)
        }
    }

    private func card(_ moment: CelebrationCenter.Moment) -> some View {
        VStack(spacing: 0) {
            Text("🎉").font(.system(size: 44))
            Text(moment.title)
                .font(.fraunces(22, .semibold))
                .foregroundStyle(Nuru.navy)
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.md)
            if let subtitle = moment.subtitle {
                Text(subtitle)
                    .font(.inter(14))
                    .foregroundStyle(Nuru.muted)
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.sm)
            }
            Button {
                Haptics.tap()
                center.dismiss()
            } label: {
                Text("Amen 🙌")
                    .font(.inter(16, .bold))
                    .foregroundStyle(Nuru.navyDeep)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Nuru.goldGradient,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.top, Nuru.S.lg)
        }
        .padding(Nuru.S.lg)
        .frame(maxWidth: 340)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .nuruShadow(1.4)
        .padding(.horizontal, Nuru.S.xl)
        .gentleEntrance()
    }

    // Quiet moment: a gold banner under the status bar, gone in 3s.
    private func banner(_ moment: CelebrationCenter.Moment) -> some View {
        VStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(moment.title)
                    .font(.inter(14, .bold)).foregroundStyle(Nuru.goldChipText)
                if let subtitle = moment.subtitle {
                    Text(subtitle)
                        .font(.inter(12)).foregroundStyle(Nuru.goldChipText.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Nuru.S.base)
            .padding(.vertical, Nuru.S.md)
            .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Nuru.gold.opacity(0.45), lineWidth: 1))
            .nuruShadow()
            .padding(.horizontal, Nuru.S.base)
            .padding(.top, 62)
            .onTapGesture { center.dismiss() }
            .transition(.move(edge: .top).combined(with: .opacity))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Confetti (the ONE shared gold/white burst)

/// The app's single confetti emitter — the quiz-pass / level-exam ceremony
/// burst, lifted here so every celebration reuses it (QuizView and
/// LevelExamView had private mirrored copies; they now use this one).
/// One-shot pattern: the flight is kicked on the NEXT runloop (never in the
/// same transaction that inserts the view — SwiftUI would coalesce it to the
/// end state → invisible), pieces stay opaque through most of the fall and
/// fade only at the tail, and Reduce Motion renders nothing.
struct CelebrationConfetti: View {
    private struct Piece: Identifiable {
        let id: Int
        let x: CGFloat        // 0…1 horizontal origin
        let dx: CGFloat, dy: CGFloat, w: CGFloat, h: CGFloat
        let spin: Double
        let color: Color
        let delay: Double
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var fly = false
    @State private var fade = false

    // Gold family + white + amber — legible on navy and paper alike.
    private let pieces: [Piece] = {
        let palette: [Color] = [Color(hex: 0xC9A227), Color(hex: 0xE6C068),
                                .white, Color(hex: 0xF5D77A)]
        return (0..<90).map { i in
            Piece(id: i,
                  x: CGFloat.random(in: 0.03...0.97),
                  dx: CGFloat.random(in: -80...80),
                  dy: CGFloat.random(in: 560...980),
                  w: CGFloat.random(in: 5...9),
                  h: CGFloat.random(in: 9...16),
                  spin: Double.random(in: -900...900),
                  color: palette[i % palette.count],
                  delay: Double.random(in: 0...0.6))
        }
    }()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                ForEach(pieces) { p in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(p.color)
                        .frame(width: p.w, height: p.h)
                        .rotationEffect(.degrees(fly ? p.spin : 0))
                        .position(x: geo.size.width * p.x + (fly ? p.dx : 0),
                                  y: fly ? p.dy : -20)
                        .opacity(fade ? 0 : 1)
                        .animation(.easeOut(duration: 3.4).delay(p.delay), value: fly)
                        .animation(.easeIn(duration: 0.7).delay(3.0 + p.delay), value: fade)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            guard !reduceMotion else { return }
            // Kick on the next runloop so the fall actually animates.
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 60_000_000)
                fly = true
                fade = true
            }
        }
    }
}
