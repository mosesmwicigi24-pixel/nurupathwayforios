// The verse, beheld — not only read.
//   • VerseTableauHeader — the day's server-curated photograph (grapes on the
//     vine, bread, wheat at dawn…) with the verse set in serif over a warm
//     scrim. Falls back to nothing (the plain cream card stands alone) when
//     the day carries no art or the image can't load — never a broken frame.
//   • SelahDivider — a quiet rest between text-dense stretches of the feed:
//     two hairlines meeting at a small gold cross ("Selah" — pause, and lift).
//   • Share-as-picture — renders the tableau (image + verse + brand line) to
//     a real photograph for WhatsApp/anywhere via ImageRenderer.
// Ornament rule (the fusion lesson, ios#72): everything decorative lives in
// overlays CLIPPED to owned frames — nothing here can inflate layout.
import SwiftUI

/// The deep-navy veil laid over a tableau photograph so the type stays legible:
/// the image shows through (a bit hidden), the navy deepens toward the base
/// where the text sits. Shared by the verse tableau and the liturgy card so the
/// two read as one family. Owned+clipped by its host — never inflates layout.
struct DeepNavyBlock: View {
    private static let navy = Color(hex: 0x0A1628)
    var body: some View {
        LinearGradient(stops: [
            .init(color: Self.navy.opacity(0.40), location: 0),
            .init(color: Self.navy.opacity(0.58), location: 0.45),
            .init(color: Self.navy.opacity(0.97), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - The tableau header (sits above the cream verse body)

struct VerseTableauHeader: View {
    let art: VerseArt
    let verseText: String?
    let reference: String
    let version: String

    // Long verses step down gently so the photograph still breathes (owner,
    // 2026-08-25: smaller — the words keep to the image's lower third); the
    // steps are written where the verse is drawn, so the type test reads them.

    /// At the accessibility sizes the card grows to hold the whole verse
    /// (§9.6 #4): drawn over a fixed 216 pt photograph it climbed over its
    /// own kicker. At the everyday sizes it is the same 216 pt tableau.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Icon(.bookOpen, size: 14, color: Color(hex: 0xF2DDA0))
                Text("VERSE FOR TODAY").font(.nCardKicker).kerning(1.4)
                    .foregroundStyle(Color(hex: 0xF2DDA0))
                Spacer(minLength: 0)
                Text(version.uppercased())
                    .font(.inter(11, .bold)).kerning(1).foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.white.opacity(0.16), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
            }
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 6) {
                if let t = verseText, !t.isEmpty {
                    // Long verses step down 14 → 13 → 12 and may give way to
                    // 11 (12 × 0.92) — never under it.
                    Text("\u{201C}\(t)\u{201D}")
                        .font(.fraunces(t.count > 220 ? 12 : t.count > 140 ? 13 : 14)).foregroundStyle(.white)
                        .nuruLineSpacing(3)
                        .nuruLineLimit(4)
                        .minimumScaleFactor(0.92)
                        .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(reference)
                    .font(.inter(11, .bold)).kerning(0.3)
                    .foregroundStyle(Color(hex: 0xF2DDA0))
                    .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, minHeight: 216, alignment: .leading)
        .background {
            Color.clear
                .overlay {
                    CachedAsyncImage(url: URL(string: art.url)) { phase in
                        if let img = phase.image {
                            img.resizable().scaledToFill()
                        } else {
                            // Loading / failed: a quiet navy field so the white
                            // verse text always has contrast — never a flash.
                            LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1C33)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing)
                        }
                    }
                }
                .clipped()   // the fill overlay can never spill past the owned frame
                // The photograph SHOWS (owner, 2026-08-25): no full veil — a slim
                // top scrim for the kicker and a bottom-third scrim for the verse,
                // so the words occupy only the image's lower third.
                .overlay {
                    LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                           .init(color: .clear, location: 0.28)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                           .init(color: Color(hex: 0x0A1C33).opacity(0.85), location: 0.78),
                                           .init(color: Color(hex: 0x06111F).opacity(0.95), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                // Grown to hold a large verse, the words cover the whole image:
                // it is veiled so they always read.
                .overlay { if typeSize.isAccessibilitySize { Color(hex: 0x06111F).opacity(0.7) } }
        }
        .clipped()
        .accessibilityLabel(Text(art.alt))
    }
}

// MARK: - Selah — a rest between words

/// Two hairlines meeting at a small gold cross. Placed between text-dense
/// stretches of Home so the eye is given somewhere quiet to land.
struct SelahDivider: View {
    var body: some View {
        HStack(spacing: 14) {
            LinearGradient(colors: [.clear, Nuru.gold.opacity(0.45)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            ZStack {
                RoundedRectangle(cornerRadius: 1).fill(Nuru.gold.opacity(0.75)).frame(width: 2.5, height: 13)
                RoundedRectangle(cornerRadius: 1).fill(Nuru.gold.opacity(0.75)).frame(width: 9, height: 2.5).offset(y: -2)
            }
            LinearGradient(colors: [Nuru.gold.opacity(0.45), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .frame(height: 16)
        .padding(.horizontal, 44)
        .accessibilityHidden(true)
    }
}

/// Dark cards never touch on Home (owner, 2026-10-07): where a dark card
/// would sit directly on another dark card, or on a photograph's dark edge,
/// the quiet Selah divider is set between them. Nothing moves — the owner's
/// order stands (verse → video → letter → reflection → liturgy); a rest is
/// added. The check runs over the feed as it was assembled, so it holds
/// whichever rows a day brings: on a first day the reflection waits (§9.2
/// #4) and the navy letter would sit on the liturgy's photograph; while a
/// service is near, "Live now" would sit on the letter.
enum HomeQuietDivider {
    enum Edge: Equatable { case light, dark }

    /// What a Home row shows at its top and bottom edge, by the row's id. A
    /// photograph's edge counts as dark: the hour's and the day's photographs
    /// carry a dark scrim at the top (a navy field while they load), and a
    /// gathering's poster can be any tone — a rest too many is quiet, a dark
    /// seam is not.
    static func edges(of id: String) -> (top: Edge, bottom: Edge) {
        switch id {
        // Navy cards, edge to edge: Nuru Live, Radio on air, Live now, and
        // the Sunday Letter in every state. ("Support God's work" is a paper
        // card since the owner's 2026-10-08 decision.)
        case "livebanner", "onair", "livenow", "letter":
            return (.dark, .dark)
        // A photograph above a light caption: the verse's tableau, the
        // liturgy's hour, a featured gathering's poster.
        case "verse", "liturgy", "event":
            return (.dark, .light)
        default:
            return (.light, .light)
        }
    }

    /// True when the upper row's bottom edge and the lower row's top edge are
    /// both dark.
    static func touch(_ upper: String, _ lower: String) -> Bool {
        edges(of: upper).bottom == .dark && edges(of: lower).top == .dark
    }

    /// The divider's own id between two rows — stable, so SwiftUI keeps it.
    static func dividerId(_ upper: String, _ lower: String) -> String { "quiet:\(upper)|\(lower)" }

    /// The rows as assembled, with a divider wherever two dark edges would
    /// touch, and nothing else changed.
    static func parted<Row>(_ rows: [Row], id: (Row) -> String,
                            divider: (_ upper: String, _ lower: String) -> Row) -> [Row] {
        var out: [Row] = []
        out.reserveCapacity(rows.count + 2)
        var above: String?
        for row in rows {
            let here = id(row)
            if let above, touch(above, here) { out.append(divider(above, here)) }
            out.append(row)
            above = here
        }
        return out
    }

    /// The same, over the rows' ids alone.
    static func parted(_ ids: [String]) -> [String] {
        parted(ids, id: { $0 }, divider: { dividerId($0, $1) })
    }
}

// MARK: - Share as a picture

/// The postcard we render to a photograph: the day's art, the verse in serif,
/// the reference, and a quiet brand line — text set by us, never baked into
/// the image, so it is always crisp and always spelled right.
struct VerseShareCard: View {
    let artImage: UIImage
    let verseText: String
    let reference: String
    let version: String

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Image(uiImage: artImage)
                .resizable().scaledToFill()
                .frame(width: 390, height: 480)
                .clipped()
            LinearGradient(stops: [
                .init(color: .black.opacity(0.10), location: 0),
                .init(color: .black.opacity(0.72), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 10) {
                Text("\u{201C}\(verseText)\u{201D}")
                    .font(.fraunces(verseText.count > 200 ? 18 : 22))
                    .foregroundStyle(.white).nuruLineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(reference) · \(version.uppercased())")
                    .font(.inter(13, .bold)).kerning(0.4)
                    .foregroundStyle(Color(hex: 0xF2DDA0))
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 1).fill(Nuru.gold).frame(width: 2.5, height: 12)
                        RoundedRectangle(cornerRadius: 1).fill(Nuru.gold).frame(width: 9, height: 2.5).offset(y: -2)
                    }
                    Text("Nuru Pathway").font(.inter(12, .semibold)).foregroundStyle(.white.opacity(0.8))
                }
                .padding(.top, 2)
            }
            .padding(22)
        }
        .frame(width: 390, height: 480)
    }
}

enum VerseImageShare {
    /// Fetch the art (URLCache-warm after the card rendered) and compose the
    /// postcard at @3x. Returns nil quietly on any failure — the caller then
    /// falls back to text sharing rather than showing an error for a nicety.
    @MainActor
    static func render(art: VerseArt, verseText: String, reference: String, version: String) async -> UIImage? {
        guard let url = URL(string: art.url),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let img = UIImage(data: data) else { return nil }
        let renderer = ImageRenderer(content: VerseShareCard(
            artImage: img, verseText: verseText, reference: reference, version: version))
        renderer.scale = 3
        return renderer.uiImage
    }
}

/// Identifiable wrapper so the rendered picture can drive a .sheet(item:).
struct VerseImagePayload: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// UIActivityViewController wrapper for handing the rendered picture to the
/// system share sheet (WhatsApp, Save Image, AirDrop…).
struct VerseShareSheet: UIViewControllerRepresentable {
    let image: UIImage
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [image], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
