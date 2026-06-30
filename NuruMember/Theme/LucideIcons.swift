// Lucide icons (ISC-licensed, github.com/lucide-icons/lucide) — the SAME icon set
// the React Native app uses (lucide-react-native). Bundled as the official Lucide
// font (Resources/Fonts/lucide.ttf) and rendered as glyphs, so every icon matches
// the RN app exactly instead of an SF Symbol approximation.
import SwiftUI

enum Lucide: String {
    case house = "\u{E0F5}"
    case bookOpen = "\u{E05F}"
    case bookMarked = "\u{E3F1}"
    case calendarDays = "\u{E2B9}"
    case messageCircle = "\u{E116}"
    case handHeart = "\u{E5B9}"
    case user = "\u{E19F}"
    case bell = "\u{E059}"
    case chevronRight = "\u{E06F}"
    case chevronLeft = "\u{E06E}"
    case flame = "\u{E0D2}"
    case sun = "\u{E178}"
    case quote = "\u{E239}"
    case sparkles = "\u{E412}"
    case heart = "\u{E0F2}"
    case book = "\u{E05E}"
    case clock = "\u{E087}"
    case check = "\u{E06C}"
    case target = "\u{E180}"
    case messageSquareText = "\u{E575}"
    case users = "\u{E1A4}"
    case calendarClock = "\u{E304}"
    case mapPin = "\u{E111}"
    case megaphone = "\u{E235}"
    case play = "\u{E13C}"
    case share2 = "\u{E156}"
    case badgeCheck = "\u{E241}"
    case map = "\u{E110}"
    case circleCheckBig = "\u{E07C}"
    case checkCircle2 = "\u{E226}"
    case arrowLeft = "\u{E048}"
    case arrowRight = "\u{E049}"
    case plus = "\u{E13D}"
    case x = "\u{E1B2}"
    case send = "\u{E152}"
    case trash2 = "\u{E18E}"
    case bookmark = "\u{E060}"
    case eye = "\u{E0BA}"
    case eyeOff = "\u{E0BB}"
    case lock = "\u{E10B}"
    case mail = "\u{E10F}"
    case leaf = "\u{E2DE}"
    case list = "\u{E106}"
    case pencil = "\u{E1F9}"
    case circle = "\u{E076}"
    case square = "\u{E167}"
    case squareCheck = "\u{E559}"
    case squareCheckBig = "\u{E16A}"
    case audioLines = "\u{E55A}"
    case hand = "\u{E1D7}"
    case calendar = "\u{E063}"
    case gift = "\u{E0E1}"
    case graduationCap = "\u{E234}"
    case sparkle = "\u{E47E}"
    case playCircle = "\u{E080}"
}

/// Renders one Lucide glyph. `size` is the icon's point size (≈ its RN `size` prop).
struct Icon: View {
    let glyph: Lucide
    var size: CGFloat = 20
    var color: Color = Nuru.ink

    init(_ glyph: Lucide, size: CGFloat = 20, color: Color = Nuru.ink) {
        self.glyph = glyph; self.size = size; self.color = color
    }

    var body: some View {
        Text(glyph.rawValue)
            .font(.custom("lucide", fixedSize: size))
            .foregroundStyle(color)
    }
}
