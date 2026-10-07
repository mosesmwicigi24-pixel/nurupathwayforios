// Shared UI primitives — the native equivalents of the React Native theme/
// components.tsx (Card, PButton, BrandMark). Composed from Nuru tokens; no raw
// hex in feature screens.
import SwiftUI

/// The gold "N" badge / wordmark used across the app.
struct BrandMark: View {
    var size: CGFloat = 36
    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(Nuru.goldGradient)
            .frame(width: size, height: size)
            .overlay(
                Text("N")
                    .font(.nuruDisplay(size * 0.56, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .stroke(.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Nuru.gold.opacity(0.45), radius: size * 0.18, y: size * 0.08)
    }
}

/// One header per tab (EXPERIENCE.md §8.1 rules 2–3) — its words in the
/// type roles both apps share: the gold kicker in caps (Inter 11 bold,
/// tracking 1.4), the Fraunces screen title (26, wrapping to two lines, never
/// cut), and one Inter line of what matters now. Each tab keeps its own band,
/// switch and bell around it; this is only the words, so every tab reads alike.
struct NuruHeaderText: View {
    var kicker: String? = nil
    let title: String
    var line: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let kicker, !kicker.isEmpty {
                Text(kicker.uppercased())
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.eyebrow)
                    .padding(.bottom, 6)
            }
            Text(title)
                .font(.fraunces(26, .semibold)).kerning(-0.52).foregroundStyle(Nuru.navy)
                .nuruLineLimit(2).minimumScaleFactor(0.85)
                .fixedSize(horizontal: false, vertical: true)
                // Never "Foundatio / ns" at the largest size (§9.6 #4).
                .nuruWholeWords(title, font: .fraunces(26, .semibold), kerning: -0.52)
            if let line, !line.isEmpty {
                Text(line)
                    .font(.inter(13)).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// A line limit for the sizes most members read at; at the accessibility
/// sizes the text wraps in full — it grows with the phone's text size and is
/// never cut (EXPERIENCE.md §9.6 #4). Titles still wrap to two lines at the
/// everyday sizes (§8.1 rule 9).
struct NuruLineLimit: ViewModifier {
    let lines: Int
    @Environment(\.dynamicTypeSize) private var size
    func body(content: Content) -> some View {
        content.lineLimit(size.isAccessibilitySize ? nil : lines)
    }
}

extension View {
    /// `.lineLimit(lines)` at the everyday sizes, none at the accessibility
    /// sizes (§9.6 #4).
    func nuruLineLimit(_ lines: Int) -> some View { modifier(NuruLineLimit(lines: lines)) }

    /// A bar's words (the tab bar, a segment switch) grow with the phone's
    /// text size only as far as the bar has room — by default up to the
    /// largest everyday size — and stop there. In a fixed bar the
    /// accessibility sizes would cut them ("H… Pa… Pl…"), so, as the system's
    /// own bars do, a long press shows them large instead (the Large Content
    /// Viewer, on each of the bar's buttons). §9.6 #4.
    func nuruBarText(upTo largest: DynamicTypeSize = .xxxLarge) -> some View { dynamicTypeSize(...largest) }

    /// A figure drawn inside a fixed shape (a progress ring) keeps the
    /// everyday size, so it never spills out of its shape at the larger text
    /// sizes; the screen's own words carry the same fact, and grow. §9.6 #4.
    func nuruFixedFigure() -> some View { dynamicTypeSize(...DynamicTypeSize.large) }

    /// Display type — set larger than any reading text already — grows with
    /// the phone's text size as far as the largest everyday size and stops
    /// there (§9.6 #4): the Sunday Letter's masthead, figures, opening quote
    /// and signature. The words a member reads (the title, the letter) grow on.
    func nuruDisplayType() -> some View { dynamicTypeSize(...DynamicTypeSize.xxxLarge) }

    /// The title never breaks a word (`NuruWholeWords`): `text` is the string
    /// shown, `font` and `kerning` its own.
    func nuruWholeWords(_ text: String, font: Font, kerning: CGFloat = 0) -> some View {
        modifier(NuruWholeWords(text: text, font: font, kerning: kerning))
    }
}

/// A title that never breaks a word (§8.1 rule 9; §9.6 #4). At the
/// accessibility text sizes a long word in a display face can be wider than
/// the line, and the text then breaks inside it: Pathway's "Foundatio / ns of
/// / Faith" at the largest size. There the title steps down through the
/// Dynamic Type sizes, one at a time from the member's own, to the largest
/// at which its widest word fits the line, and wraps between words as usual.
/// At the everyday sizes every word fits, and the title is untouched.
struct NuruWholeWords: ViewModifier {
    let text: String
    let font: Font
    var kerning: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var size

    func body(content: Content) -> some View {
        if size.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                ForEach(Self.steps(from: size), id: \.self) { step in
                    NuruWholeWordsLayout {
                        content
                        stick
                    }
                    .environment(\.dynamicTypeSize, step)
                }
            }
        } else {
            content
        }
    }

    /// The member's size, then each smaller one.
    static func steps(from size: DynamicTypeSize) -> [DynamicTypeSize] {
        DynamicTypeSize.allCases.filter { $0 <= size }.reversed()
    }

    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// Every word on a line of its own, unwrapped: as wide as the widest.
    private var stick: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Self.words(text).enumerated()), id: \.offset) { _, word in
                Text(word).font(font).kerning(kerning).lineLimit(1).fixedSize()
            }
        }
        .hidden()
        .accessibilityHidden(true)
    }
}

/// The title and its hidden measuring stick. Given a width, it is the title.
/// Asked for its ideal width, as ViewThatFits asks, it answers with the
/// widest word's (and a point to spare), so ViewThatFits takes the first
/// size at which that word fits the line.
private struct NuruWholeWordsLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 2 else { return subviews.first?.sizeThatFits(proposal) ?? .zero }
        guard proposal.width == nil else { return subviews[0].sizeThatFits(proposal) }
        let widest = subviews[1].sizeThatFits(.unspecified).width.rounded(.up) + 1
        let title = subviews[0].sizeThatFits(ProposedViewSize(width: widest, height: proposal.height))
        return CGSize(width: widest, height: title.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let title = subviews.first else { return }
        title.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        if subviews.count == 2 {
            subviews[1].place(at: bounds.origin, anchor: .topLeading, proposal: .unspecified)
        }
    }
}

/// Side by side at the everyday sizes; one above another at the
/// accessibility sizes, where side by side cut or broke their words
/// ("PLED / GED", "REMAI / NING"; §9.6 #4).
struct NuruAdaptiveStack<Content: View>: View {
    var spacing: CGFloat? = nil
    var rowAlignment: VerticalAlignment = .center
    @ViewBuilder var content: () -> Content
    @Environment(\.dynamicTypeSize) private var size

    var body: some View {
        if size.isAccessibilitySize {
            VStack(alignment: .leading, spacing: spacing) { content() }
        } else {
            HStack(alignment: rowAlignment, spacing: spacing) { content() }
        }
    }
}

/// A white card that floats on one soft shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = Nuru.S.base
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            // White, radius 24, a hairline, the one soft shadow (§8.1 rule 5).
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}

/// §8.1 rule 4: the one primary — gold fill, navy text, radius 14; a
/// secondary — white, a hairline, navy text. (The shared button drew white
/// text on gold, and a navy primary.)
enum PButtonVariant { case gold, secondary }

/// The shared action button, full-width, with a busy state.
struct PButton: View {
    var title: String
    var variant: PButtonVariant = .gold
    var busy: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // Both branches live in a fixed-height ZStack, so the swap to a
                // spinner never moves the layout — it just crossfades in place.
                if busy { ProgressView().tint(Nuru.navy).transition(.opacity) }
                else { Text(title).font(.inter(16, .semibold)).transition(.opacity) }
            }
            .frame(maxWidth: .infinity, minHeight: Nuru.buttonHeightLg)
            .foregroundStyle(Nuru.navy)
            .background(variant == .gold ? AnyShapeStyle(Nuru.goldGradient) : AnyShapeStyle(Nuru.white),
                        in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous)
                .stroke(variant == .gold ? Color.clear : Nuru.border, lineWidth: 1))
            .opacity(disabled || busy ? 0.6 : 1)
            .animation(.easeOut(duration: 0.18), value: busy)
        }
        .buttonStyle(.pressable)
        .disabled(disabled || busy)
    }
}

/// Circular avatar — the member's photo, or their initials on a tinted disc
/// (the native port of components/Avatar.tsx).
struct Avatar: View {
    var url: String?
    var name: String
    var size: CGFloat = 36

    var body: some View {
        ZStack {
            Circle().fill(Nuru.tintBlue)
            if let url, let u = URL(string: url) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { initials }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initials: some View {
        Text(Self.initials(name))
            .font(.inter(NuruType.snap(size * 0.4), .semibold))
            .foregroundStyle(Nuru.navyMid)
            // Letters drawn inside a fixed circle keep the everyday size: at
            // the largest text size "AT" spilled past the circle and was cut
            // (§9.6 #4). The name beside the photo carries the same words.
            .nuruFixedFigure()
    }

    static func initials(_ name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        let chars = parts.compactMap { $0.first }.map(String.init)
        return chars.joined().uppercased()
    }
}

/// Relative "time ago" label (m / h / date) — mirrors the RN `ago()` helper.
func timeAgo(_ iso: String) -> String {
    guard let date = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
    let mins = max(0, Int(Date().timeIntervalSince(date) / 60))
    if mins < 1 { return "now" }        // "0m" read like a glitch
    if mins < 60 { return "\(mins)m" }
    if mins < 1440 { return "\(mins / 60)h" }
    return NuruDates.day(date)
}

extension ISO8601DateFormatter {
    /// Tolerates fractional seconds (the API serialises timestamps with millis).
    static let nuru: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

/// A labelled text field styled to the design tokens.
struct NuruField: View {
    var placeholder: String
    @Binding var text: String
    var secure: Bool = false
    var keyboard: UIKeyboardType = .default

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.nBody)
        .padding(.horizontal, Nuru.S.base)
        .frame(height: Nuru.buttonHeightMd)
        .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }
}
