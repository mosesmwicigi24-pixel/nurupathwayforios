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

/// A white card that floats on one soft shadow.
struct Card<Content: View>: View {
    var padding: CGFloat = Nuru.S.base
    @ViewBuilder var content: () -> Content
    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .nuruShadow()
    }
}

enum PButtonVariant { case navy, gold }

/// Primary action button (navy or gold), full-width, with a busy state.
struct PButton: View {
    var title: String
    var variant: PButtonVariant = .navy
    var busy: Bool = false
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(.white) }
                else { Text(title).font(.inter(16, .semibold)) }
            }
            .frame(maxWidth: .infinity, minHeight: Nuru.buttonHeightLg)
            .foregroundStyle(.white)
            .background(variant == .gold ? Nuru.goldGradient : Nuru.primaryButton,
                        in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
            .opacity(disabled || busy ? 0.6 : 1)
        }
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
                AsyncImage(url: u) { phase in
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
            .font(.inter(size * 0.4, .semibold))
            .foregroundStyle(Nuru.navyMid)
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
    if mins < 60 { return "\(mins)m" }
    if mins < 1440 { return "\(mins / 60)h" }
    let f = DateFormatter(); f.dateFormat = "MMM d"
    return f.string(from: date)
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
