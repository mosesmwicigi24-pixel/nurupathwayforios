// Interactions — the app-wide feel toolkit.
//
// One shared vocabulary for how Nuru responds to touch: haptics that confirm
// without shouting, a press style that makes every card feel physical, and a
// shimmer for content that is on its way. Screens adopt these instead of
// hand-rolling their own so the whole app answers the hand the same way.
import SwiftUI
import UIKit

// MARK: - Haptics (pre-warmed, fire-and-forget)

enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let notify = UINotificationFeedbackGenerator()
    private static let select = UISelectionFeedbackGenerator()

    /// Card taps, chips, toggles — a whisper of contact.
    static func tap() { light.impactOccurred() }
    /// Primary CTAs and confirmed sends — slightly firmer.
    static func action() { medium.impactOccurred() }
    /// Reactions, likes, hearts — soft and warm.
    static func love() { soft.impactOccurred() }
    /// A completed thing: quiz passed, gift sent, broadcast delivered.
    static func success() { notify.notificationOccurred(.success) }
    /// Something failed and the UI is saying so.
    static func error() { notify.notificationOccurred(.error) }
    /// Segment switches, pickers, tab changes.
    static func selection() { select.selectionChanged() }
}

// MARK: - Pressable (cards and rows that give under the finger)

/// Scale-and-settle press feedback: 0.98 with a quick spring, the universal
/// "this is a real object" cue. Use `.buttonStyle(.pressable)` on tappable
/// cards/rows in place of `.plain` — visual only, no haptic (callers add one
/// where the tap *means* something).
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.98
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    /// For big hero cards where 0.98 would move too many pixels.
    static var pressableSubtle: PressableStyle { PressableStyle(scale: 0.99) }
}

// MARK: - Shimmer (skeletons that feel alive, not frozen)

/// A soft highlight sweeping the placeholder — communicates "coming" rather
/// than "stuck". Holds still under Reduce Motion.
private struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(colors: [.clear, .white.opacity(0.45), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: geo.size.width * 0.6)
                        .offset(x: geo.size.width * phase)
                }
                .allowsHitTesting(false)
            )
            .clipped()
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) { phase = 1.6 }
            }
    }
}

extension View {
    /// Shimmering placeholder block. Typical use:
    /// `RoundedRectangle(cornerRadius: 12).fill(Nuru.surface).frame(height: 72).nuruShimmer()`
    func nuruShimmer() -> some View { modifier(Shimmer()) }
}

// MARK: - Gentle entrance (content that settles in, never pops)

/// Fade-and-rise on first appearance — 8pt of travel, nothing theatrical.
/// Stagger with `delay` when a few siblings arrive together (cap ~4 steps).
private struct GentleEntrance: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 8)
            .onAppear {
                guard !shown else { return }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.85).delay(delay)) { shown = true }
            }
    }
}

extension View {
    func gentleEntrance(delay: Double = 0) -> some View { modifier(GentleEntrance(delay: delay)) }
}
