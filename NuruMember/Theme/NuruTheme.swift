// Nuru Pathway design system — a Swift port of the mobile app's design tokens
// (packages/mobile/src/theme/tokens.ts), so the native iOS member app shares the
// exact visual language as the React Native app it replaces: warm paper, white
// cards that float on one soft shadow, gold used with restraint, Inter body type.
// Sized for the phone canvas (the mobile type scale, NOT the iPad-bumped one).
import SwiftUI
import CoreText

enum Nuru {
    // MARK: Surfaces
    static let paper      = Color(hex: 0xF6F4EE)   // app background (warm off-white)
    static let white      = Color(hex: 0xFFFFFF)   // cards / surfaces
    static let surface    = Color(hex: 0xFBF8F1)   // inset tiles inside white cards
    static let coolPaper  = Color(hex: 0xF7F9FC)   // calendar / portal background
    static let chatPaper  = Color(hex: 0xE8E1D3)   // chat thread background
    static let background  = paper                 // alias used widely

    // MARK: Navy (brand)
    static let navy         = Color(hex: 0x0B1F33) // headers, tab bar, chrome
    static let navyDeep     = Color(hex: 0x00132F) // primary brand / button base
    static let navy700      = Color(hex: 0x143559) // gradient top / hover
    static let navyMid      = Color(hex: 0x315F8C) // hero gradient mid tone
    static let navyCeremony = Color(hex: 0x081C36) // full-dark ceremony screens
    static let dark         = navyDeep

    // MARK: Gold (accent — used sparingly)
    static let gold       = Color(hex: 0xC89B3C)
    static let goldHi     = Color(hex: 0xE0B85E)
    static let goldLo     = Color(hex: 0xA87F2E)
    static let goldGlow   = Color(hex: 0xE6CA68)
    static let goldLight  = Color(hex: 0xE6C068)
    static let goldTint   = Color(hex: 0xFFF4C7)
    static let goldChipBg   = Color(hex: 0xFFF4DA)
    static let goldChipText = Color(hex: 0x7A5A14)

    // MARK: Ink (text)
    static let ink     = Color(hex: 0x0B0B0C)   // primary text on light
    static let ink600  = Color(hex: 0x68758A)   // secondary text
    static let ink400  = Color(hex: 0x8B95A5)   // tertiary text
    static let ink300  = Color(hex: 0xB5BDC9)   // chevrons / faint
    // semantic aliases
    static let foreground = ink
    static let muted   = ink600
    static let faint   = ink400
    static let border  = Color(hex: 0x0A2540, alpha: 0.10)
    static let track   = Color(hex: 0x0A2540, alpha: 0.10)
    static let inputBg = Color(hex: 0xEEF1F5)
    static let mutedBg = Color(hex: 0xEEF1F5)
    static let tintBlue = Color(hex: 0xE8EEF7)

    // MARK: Status / feedback
    static let success = Color(hex: 0x1E7F4F)
    static let warning = Color(hex: 0xB45309)
    static let danger  = Color(hex: 0xD4183D)
    static let error   = danger
    static let successBg   = Color(hex: 0xDCFCE7)
    static let successText = Color(hex: 0x166534)
    static let verseBg   = Color(hex: 0xFFF8E6)
    static let urgentBg  = Color(hex: 0xFFF8DD)
    static let urgentText = Color(hex: 0x8A6B10)
    static let activeBadgeBg   = Color(hex: 0xDDF4C6)
    static let activeBadgeText = Color(hex: 0x22612A)
    static let online = Color(hex: 0x25D366)   // presence dot
    static let myBubble = Color(hex: 0xDDF4C6) // chat outgoing bubble

    // On-navy text
    static let onNavy      = Color.white
    static let onNavyDim   = Color.white.opacity(0.55)
    static let onNavyFaint = Color.white.opacity(0.40)

    /// Engagement band → color (harmonised with the mobile palette).
    static func bandColor(_ band: String?) -> Color {
        switch band?.lowercased() {
        case "thriving":          return Color(hex: 0x1E7F4F)
        case "steady":            return Color(hex: 0x1B5FAE)
        case "watch":             return Color(hex: 0xB45309)
        case "at_risk", "at risk": return Color(hex: 0xD4183D)
        default:                  return ink600
        }
    }

    // MARK: Gradients
    static let navyGradient = LinearGradient(
        colors: [navy700, navy, Color(hex: 0x07203A)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let heroGradient = LinearGradient(
        colors: [Color(hex: 0x1A406B), navy, navyDeep],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ceremonyGradient = LinearGradient(
        colors: [Color(hex: 0x0E2A4A), navyCeremony, Color(hex: 0x03101F)],
        startPoint: .top, endPoint: .bottom)
    static let goldGradient = LinearGradient(
        colors: [Color(hex: 0xE5BC3A), Color(hex: 0xC9A227), Color(hex: 0xA8861C)],
        startPoint: .top, endPoint: .bottom)
    static let primaryButton = LinearGradient(
        colors: [Color(hex: 0x143559), Color(hex: 0x0A2540), Color(hex: 0x07203A)],
        startPoint: .top, endPoint: .bottom)

    // MARK: Radii / spacing (8pt grid; mobile values)
    enum R {
        static let control: CGFloat = 14
        static let button: CGFloat = 14
        static let card: CGFloat = 24
        static let hero: CGFloat = 30
        static let pill: CGFloat = 999
    }
    enum S {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let base: CGFloat = 16
        static let screen: CGFloat = 20
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }
    /// Bottom-scroll clearance so the last card never hides behind the tab bar.
    static let tabBarSpace: CGFloat = 96

    static let buttonHeightLg: CGFloat = 56
    static let buttonHeightMd: CGFloat = 48

    // MARK: Fonts — register the bundled OFL faces (Inter + Fraunces).
    static func registerFonts() {
        let faces = ["Inter-Regular", "Inter-Medium", "Inter-SemiBold", "Inter-Bold",
                     "Fraunces-Regular", "Fraunces-Medium", "Fraunces-SemiBold", "Fraunces-Bold"]
        for f in faces {
            if let url = Bundle.main.url(forResource: f, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

// MARK: - Typography (Inter body · Fraunces display) — mobile type scale

extension Font {
    static func inter(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(interFace(weight), size: size)
    }
    static func fraunces(_ size: CGFloat, _ weight: Font.Weight = .medium) -> Font {
        .custom(frauncesFace(weight), size: size)
    }
    static func nuruDisplay(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom(frauncesFace(weight), size: size)
    }

    // Semantic scale — matches tokens.ts `type` (designed at ~390pt).
    static var nDisplay: Font  { fraunces(28, .medium) }
    static var nTitle: Font    { fraunces(22, .medium) }
    static var nHeading: Font  { inter(16, .medium) }
    static var nBody: Font     { inter(14, .regular) }
    static var nBodyLg: Font   { inter(16, .regular) }
    static var nLabel: Font    { inter(12, .medium) }
    static var nCaption: Font  { inter(12, .regular) }
    static var nMicro: Font    { inter(11, .medium) }
    static var nOverline: Font { inter(11, .semibold) }
}

private func interFace(_ w: Font.Weight) -> String {
    switch w {
    case .bold, .heavy, .black: return "Inter-Bold"
    case .semibold:             return "Inter-SemiBold"
    case .medium:               return "Inter-Medium"
    default:                    return "Inter-Regular"
    }
}
// Display/headers use the Fraunces serif for ceremony moments; body stays Inter.
private func frauncesFace(_ w: Font.Weight) -> String {
    switch w {
    case .bold, .heavy, .black: return "Fraunces-Bold"
    case .semibold:             return "Fraunces-SemiBold"
    case .medium:               return "Fraunces-Medium"
    default:                    return "Fraunces-Regular"
    }
}

// MARK: - Depth (one soft card shadow — never stack)

extension View {
    func nuruShadow(_ strength: Double = 1) -> some View {
        shadow(color: Color(hex: 0x0A2540).opacity(0.06 * strength),
               radius: 12 * strength, x: 0, y: 6 * strength)
    }
}
