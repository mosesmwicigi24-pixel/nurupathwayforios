// Bundled Sunday Letter illustrations — one per theme in the server's fixed
// vocabulary (LETTER_THEMES, packages/backend/src/modules/intelligence/prompts.ts:
// dawn, water, path, harvest, shelter, light, seed, garden, mountain, rest).
//
// Drawn procedurally with Canvas rather than shipped as bitmap/PDF assets in
// the catalogue: zero binary weight, crisp at any size and any text-scale
// setting, and — most importantly for a pastoral surface — impossible to ever
// render anything inappropriate, because there is no image, only geometry.
// Every theme shares one family treatment (the same navy "stationery" base
// LetterView already uses, one soft accent motif each) so all ten read as
// siblings, not a random assortment.
//
// The hero is its own fixed, self-contained "poster" — like the rest of
// LetterView's navy backdrop, it does NOT follow the system light/dark
// setting. That is deliberate: it guarantees the overlaid title text (always
// warm white) stays legible regardless of the device's appearance, exactly
// the "legible in both light and dark" requirement, without needing two
// palettes per theme.
import SwiftUI

/// The fixed imagery vocabulary for the Sunday Letter — mirrors `LETTER_THEMES`
/// in prompts.ts exactly (case names match the server's raw strings).
enum LetterTheme: String, CaseIterable, Sendable {
    case dawn, water, path, harvest, shelter, light, seed, garden, mountain, rest

    /// The fallback for anything the mapping doesn't recognise — an unknown
    /// theme, a legacy letter with no theme at all, or a future addition to
    /// the server's vocabulary the client hasn't shipped a motif for yet.
    /// `.light` reads as the most neutral, always-appropriate choice (a warm
    /// glow works for any pastoral mood), the same role a neutral default
    /// plays elsewhere in the app (e.g. the verse tableau's own fallback art).
    static let fallback: LetterTheme = .light

    /// TOTAL mapping, by construction: every `LetterTheme` case is handled by
    /// `LetterHero`'s exhaustive switch (see below), and every raw string that
    /// ISN'T one of the ten known cases resolves here to `.fallback` — so a
    /// letter can never render blank for want of a theme.
    static func resolve(_ raw: String?) -> LetterTheme {
        guard let raw, let known = LetterTheme(rawValue: raw) else { return fallback }
        return known
    }
}

// MARK: - Per-theme art configuration

/// One motif shape family, parameterised per theme below. Kept small
/// deliberately: each case reads as a single quiet gesture, not a busy scene —
/// "non-literal" per the brief, an impression of the theme rather than a
/// picture of it.
private enum LetterMotif {
    case horizonGlow     // dawn — a low soft light at the horizon
    case waves            // water — a few gentle horizontal swells
    case convergingLines  // path — lines receding toward a vanishing point
    case wheatStrokes     // harvest — clustered upright strokes
    case archRoof         // shelter — a simple enclosing arch
    case sunburst          // light — rays from an off-center point
    case seedRings         // seed — one point with expanding rings
    case leafCurves         // garden — a few curved, leaf-like strokes
    case ridgeLayers        // mountain — layered receding ridgelines
    case restBands            // rest — one soft orb over calm horizontal bands
}

private struct LetterArt {
    let base: Color        // the family's shared navy, tuned slightly warmer/cooler per theme
    let base2: Color
    let accent: Color      // the motif's own line/glow color
    let accent2: Color
    let motif: LetterMotif
}

extension LetterTheme {
    /// The theme's signature accent color — a single representative color for
    /// lightweight secondary UI (e.g. the archive list's mini swatch) that
    /// doesn't need the full illustration, just something in the same family.
    var accentColor: Color { art.accent }

    fileprivate var art: LetterArt {
        switch self {
        case .dawn:
            return LetterArt(base: Color(hex: 0x152238), base2: Color(hex: 0x0A1628),
                              accent: Color(hex: 0xE8CA6C), accent2: Color(hex: 0xB6862F), motif: .horizonGlow)
        case .water:
            return LetterArt(base: Color(hex: 0x0E2438), base2: Color(hex: 0x081828),
                              accent: Color(hex: 0x8FC4D9), accent2: Color(hex: 0x3A7590), motif: .waves)
        case .path:
            return LetterArt(base: Color(hex: 0x101F30), base2: Color(hex: 0x0A1628),
                              accent: Color(hex: 0xC9A227), accent2: Color(hex: 0x3D5C7A), motif: .convergingLines)
        case .harvest:
            return LetterArt(base: Color(hex: 0x1C1A28), base2: Color(hex: 0x11101C),
                              accent: Color(hex: 0xE0B85E), accent2: Color(hex: 0x8A6B1F), motif: .wheatStrokes)
        case .shelter:
            return LetterArt(base: Color(hex: 0x0F2038), base2: Color(hex: 0x081020),
                              accent: Color(hex: 0xC9A227), accent2: Color(hex: 0x2C4A66), motif: .archRoof)
        case .light:
            return LetterArt(base: Color(hex: 0x18213A), base2: Color(hex: 0x0A1628),
                              accent: Color(hex: 0xE6CA68), accent2: Color(hex: 0xA8861C), motif: .sunburst)
        case .seed:
            return LetterArt(base: Color(hex: 0x11241E), base2: Color(hex: 0x0A1628),
                              accent: Color(hex: 0x9BCB86), accent2: Color(hex: 0x3F6B33), motif: .seedRings)
        case .garden:
            return LetterArt(base: Color(hex: 0x13271F), base2: Color(hex: 0x0A1E16),
                              accent: Color(hex: 0x9BCB86), accent2: Color(hex: 0xC9A227), motif: .leafCurves)
        case .mountain:
            return LetterArt(base: Color(hex: 0x161F2E), base2: Color(hex: 0x0A1420),
                              accent: Color(hex: 0x8FA6BF), accent2: Color(hex: 0x2C4258), motif: .ridgeLayers)
        case .rest:
            return LetterArt(base: Color(hex: 0x0F1B2E), base2: Color(hex: 0x081020),
                              accent: Color(hex: 0xB9C4D4), accent2: Color(hex: 0x2C3B52), motif: .restBands)
        }
    }
}

// MARK: - The hero

/// The letter's hero illustration — a themed backdrop with room for a title
/// to be overlaid on top (LetterView supplies the text; this view only draws
/// the picture + the legibility scrim beneath where text will sit).
struct LetterHero: View {
    /// Accepts the raw `image_key` (or `theme`) string straight off the wire —
    /// resolution (including the unknown-theme fallback) happens inside.
    let imageKey: String
    var height: CGFloat = 220

    private var theme: LetterTheme { LetterTheme.resolve(imageKey) }
    private var art: LetterArt { theme.art }

    var body: some View {
        ZStack {
            LinearGradient(colors: [art.base, art.base2], startPoint: .top, endPoint: .bottom)
            Canvas { ctx, size in draw(motif: art.motif, accent: art.accent, accent2: art.accent2, ctx: &ctx, size: size) }
            // Bottom scrim — guarantees the overlaid title (always warm white)
            // stays legible over any motif, regardless of the device's own
            // light/dark setting (the hero never follows system appearance).
            LinearGradient(colors: [.clear, .clear, Color.black.opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(height: height)
        .clipped()
        .accessibilityHidden(true)
    }

    // Exhaustive over `LetterMotif` — adding a theme without a matching case
    // here is a compile error, which is what keeps the mapping total in
    // practice (LetterTheme.resolve keeps it total for unknown *strings*).
    private func draw(motif: LetterMotif, accent: Color, accent2: Color, ctx: inout GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        switch motif {
        case .horizonGlow:
            let horizon = h * 0.72
            var glow = ctx
            glow.addFilter(.blur(radius: 30))
            glow.fill(Path(ellipseIn: CGRect(x: w/2 - 90, y: horizon - 60, width: 180, height: 180)),
                      with: .color(accent.opacity(0.55)))
            ctx.fill(Path(ellipseIn: CGRect(x: w/2 - 26, y: horizon - 26, width: 52, height: 52)),
                     with: .color(accent))
            var line = Path()
            line.move(to: CGPoint(x: 0, y: horizon))
            line.addLine(to: CGPoint(x: w, y: horizon))
            ctx.stroke(line, with: .color(accent2.opacity(0.6)), lineWidth: 1)

        case .waves:
            for i in 0..<3 {
                let baseY = h * (0.42 + Double(i) * 0.16)
                var p = Path()
                p.move(to: CGPoint(x: -20, y: baseY))
                p.addCurve(to: CGPoint(x: w * 0.5, y: baseY),
                           control1: CGPoint(x: w * 0.15, y: baseY - 16), control2: CGPoint(x: w * 0.35, y: baseY + 16))
                p.addCurve(to: CGPoint(x: w + 20, y: baseY),
                           control1: CGPoint(x: w * 0.65, y: baseY - 16), control2: CGPoint(x: w * 0.85, y: baseY + 16))
                ctx.stroke(p, with: .color((i == 1 ? accent : accent2).opacity(0.55 - Double(i) * 0.08)), lineWidth: 1.5)
            }

        case .convergingLines:
            let vanish = CGPoint(x: w * 0.5, y: h * 0.38)
            for dx in stride(from: -0.9, through: 0.9, by: 0.45) {
                var p = Path()
                p.move(to: CGPoint(x: w * (0.5 + dx), y: h))
                p.addLine(to: vanish)
                ctx.stroke(p, with: .color(accent2.opacity(0.4)), lineWidth: 1)
            }
            var glow = ctx
            glow.addFilter(.blur(radius: 24))
            glow.fill(Path(ellipseIn: CGRect(x: vanish.x - 40, y: vanish.y - 40, width: 80, height: 80)),
                      with: .color(accent.opacity(0.35)))

        case .wheatStrokes:
            let count = 9
            for i in 0..<count {
                let x = w * (0.18 + Double(i) / Double(count - 1) * 0.64)
                let sway: CGFloat = i.isMultiple(of: 2) ? 10 : -8
                var p = Path()
                p.move(to: CGPoint(x: x, y: h * 0.82))
                p.addQuadCurve(to: CGPoint(x: x + sway, y: h * 0.32), control: CGPoint(x: x + sway * 0.4, y: h * 0.55))
                ctx.stroke(p, with: .color(accent.opacity(0.65)), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: x + sway - 4, y: h * 0.30, width: 8, height: 12)),
                         with: .color(accent2.opacity(0.8)))
            }

        case .archRoof:
            var roof = Path()
            roof.move(to: CGPoint(x: w * 0.18, y: h * 0.62))
            roof.addLine(to: CGPoint(x: w * 0.5, y: h * 0.28))
            roof.addLine(to: CGPoint(x: w * 0.82, y: h * 0.62))
            ctx.stroke(roof, with: .color(accent.opacity(0.7)), lineWidth: 2)
            var glow = ctx
            glow.addFilter(.blur(radius: 26))
            glow.fill(Path(ellipseIn: CGRect(x: w * 0.5 - 50, y: h * 0.5, width: 100, height: 60)),
                      with: .color(accent2.opacity(0.5)))

        case .sunburst:
            let center = CGPoint(x: w * 0.72, y: h * 0.34)
            var glow = ctx
            glow.addFilter(.blur(radius: 28))
            glow.fill(Path(ellipseIn: CGRect(x: center.x - 60, y: center.y - 60, width: 120, height: 120)),
                      with: .color(accent.opacity(0.5)))
            for i in 0..<10 {
                let angle = Double(i) / 10 * .pi * 2
                var p = Path()
                let r1: CGFloat = 26, r2: CGFloat = 60
                p.move(to: CGPoint(x: center.x + cos(angle) * r1, y: center.y + sin(angle) * r1))
                p.addLine(to: CGPoint(x: center.x + cos(angle) * r2, y: center.y + sin(angle) * r2))
                ctx.stroke(p, with: .color(accent2.opacity(0.5)), lineWidth: 1)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 16, y: center.y - 16, width: 32, height: 32)),
                     with: .color(accent))

        case .seedRings:
            let center = CGPoint(x: w * 0.5, y: h * 0.58)
            for r in stride(from: 18, through: 70, by: 17) {
                ctx.stroke(Path(ellipseIn: CGRect(x: center.x - CGFloat(r), y: center.y - CGFloat(r),
                                                   width: CGFloat(r) * 2, height: CGFloat(r) * 2)),
                           with: .color(accent2.opacity(0.35)), lineWidth: 1)
            }
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 6, y: center.y - 6, width: 12, height: 12)),
                     with: .color(accent))

        case .leafCurves:
            for i in 0..<4 {
                let x = w * (0.24 + Double(i) * 0.18)
                let y = h * (i.isMultiple(of: 2) ? 0.36 : 0.58)
                var p = Path()
                p.move(to: CGPoint(x: x, y: y + 30))
                p.addQuadCurve(to: CGPoint(x: x + 34, y: y), control: CGPoint(x: x + 4, y: y - 6))
                p.addQuadCurve(to: CGPoint(x: x, y: y + 30), control: CGPoint(x: x + 26, y: y + 26))
                ctx.fill(p, with: .color((i.isMultiple(of: 2) ? accent : accent2).opacity(0.45)))
            }

        case .ridgeLayers:
            let layers: [(CGFloat, Double)] = [(0.66, 0.3), (0.52, 0.5), (0.40, 0.8)]
            for (yFrac, opacity) in layers {
                var p = Path()
                p.move(to: CGPoint(x: 0, y: h))
                p.addLine(to: CGPoint(x: 0, y: h * yFrac + 20))
                p.addLine(to: CGPoint(x: w * 0.3, y: h * yFrac - 10))
                p.addLine(to: CGPoint(x: w * 0.55, y: h * yFrac + 14))
                p.addLine(to: CGPoint(x: w * 0.8, y: h * yFrac - 16))
                p.addLine(to: CGPoint(x: w, y: h * yFrac + 8))
                p.addLine(to: CGPoint(x: w, y: h))
                p.closeSubpath()
                ctx.fill(p, with: .color(accent2.opacity(opacity * 0.55)))
            }
            ctx.stroke(Path(ellipseIn: CGRect(x: w * 0.68, y: h * 0.16, width: 34, height: 34)),
                       with: .color(accent.opacity(0.5)), lineWidth: 1.5)

        case .restBands:
            var glow = ctx
            glow.addFilter(.blur(radius: 30))
            glow.fill(Path(ellipseIn: CGRect(x: w * 0.6, y: h * 0.18, width: 70, height: 70)),
                      with: .color(accent.opacity(0.4)))
            for i in 0..<3 {
                let y = h * (0.58 + Double(i) * 0.12)
                var p = Path()
                p.move(to: CGPoint(x: 0, y: y))
                p.addLine(to: CGPoint(x: w, y: y))
                ctx.stroke(p, with: .color(accent2.opacity(0.3 - Double(i) * 0.06)), lineWidth: 1)
            }
        }
    }
}
