// Typography, proven by tests rather than by eye (pathway docs/EXPERIENCE.md
// §8.1 rule 3, §8.2 #21, §8.3 — the owner, 2026-10-05: "check the fonts and
// put them in vigorous test to be the same").
//
// 1. The faces resolve: every face the code names loads by name, so a missing
//    or misspelt font can never fall back to the system face in silence.
// 2. The scale holds: a scan of every Swift file in the app fails on a text
//    size off the scale and on a system font used for text. Icons, emoji and
//    the home-screen widgets may use the system face, but each site is listed
//    below with its reason. The scan began as a ratchet (545 sizes off the
//    scale and 144 system-font text sites at d55d767; the count could only
//    fall) and now holds at zero.
// 3. What renders is what's asked for: a token-styled `Text` and the same
//    string in the named face render to identical pixels.
import XCTest
import SwiftUI
import UIKit
@testable import NuruMember

final class TypographyTests: XCTestCase {

    /// §8.1 rule 3: kicker and meta 11 · 12 · body 13–14 · content row title
    /// 15 · reading body 16 · card title 18 · 22 · screen title 26–28.
    static let scale: Set<CGFloat> = [11, 12, 13, 14, 15, 16, 18, 22, 26, 28]

    // MARK: - The ratchet (§8.3): it began at today's count and only fell

    /// Text sizes set in code that are off the scale (or computed where the
    /// scan can't prove they land on it). d55d767: 545 → zero in Cycle 4.
    static let offScaleCeiling = 0
    /// System-font sites not listed as an icon, emoji or widget — a system
    /// face used for text. d55d767: 144 → zero in Cycle 4.
    static let systemTextCeiling = 0

    // MARK: - 1. The faces resolve

    func testEveryFaceTheCodeNamesLoadsByName() throws {
        let named = try TypeScan.facesNamedInSource()
        XCTAssertTrue(named.isSuperset(of: ["Inter-Medium", "Inter-SemiBold", "Inter-Bold",
                                            "Fraunces-Medium", "Fraunces-SemiBold", "lucide"]),
                      "the scan must see the faces the type helpers name: \(named.sorted())")
        // The faces a member can pick for their own Selah thought load too.
        for f in SelahFont.allCases {
            XCTAssertNotNil(UIFont(name: f.rawValue, size: 16), "Selah's \(f.label) (\(f.rawValue)) doesn't load")
        }
        for face in named.sorted() {
            let font = UIFont(name: face, size: 14)
            XCTAssertNotNil(font, "\"\(face)\" is named in the code but doesn't load — every use would fall back to the system face in silence")
            if face != "lucide" {
                XCTAssertEqual(font?.fontName, face, "\"\(face)\" resolved to a different face")
            }
        }
    }

    /// Each weight the helpers take draws its bundled face — regular is drawn
    /// as Inter Medium, the owner's global voice (2026-07-06).
    @MainActor
    func testEveryWeightDrawsItsBundledFace() throws {
        let key = Nuru.textScaleKey
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } }
        let pairs: [(Font, String)] = [
            (.inter(14), "Inter-Medium"), (.inter(14, .regular), "Inter-Medium"), (.inter(14, .medium), "Inter-Medium"),
            (.inter(14, .semibold), "Inter-SemiBold"), (.inter(14, .bold), "Inter-Bold"), (.inter(14, .heavy), "Inter-Bold"),
            (.fraunces(14, .regular), "Fraunces-Regular"), (.fraunces(14), "Fraunces-Medium"),
            (.fraunces(14, .semibold), "Fraunces-SemiBold"), (.fraunces(14, .bold), "Fraunces-Bold"),
        ]
        let sample = "Pathway 1,000"
        for (font, face) in pairs {
            let named = try XCTUnwrap(UIFont(name: face, size: 14), face)
            XCTAssertTrue(try Self.pixels(Text(sample).font(font)) == Self.pixels(Text(sample).font(Font(named))),
                          "\(font) should draw \(face)")
        }
    }

    // MARK: - 2. The scale holds

    func testTextSizesStayOnTheScale() throws {
        let report = try TypeScan.report()
        print("TypographyTests: \(report.sizedCalls) sized calls · \(report.offScale.count) off the scale · \(report.systemText.count) system-font text sites")
        XCTAssertGreaterThan(report.sizedCalls, 1000, "the scan must actually see the app's text (\(report.sizedCalls) sized calls)")
        let off = report.offScale
        let list = off.prefix(80).map(\.description).joined(separator: "\n")
        XCTAssertLessThanOrEqual(off.count, Self.offScaleCeiling,
            "\(off.count) text sizes are off the scale (ceiling \(Self.offScaleCeiling)) — use 11 · 12 · 13 · 14 · 15 · 16 · 18 · 22 · 26 · 28:\n\(list)")
        if off.count < Self.offScaleCeiling {
            print("TypographyTests: \(off.count) off the scale — lower offScaleCeiling from \(Self.offScaleCeiling)")
        }
    }

    func testNoSystemFontForText() throws {
        let report = try TypeScan.report()
        let unlisted = report.systemText
        let list = unlisted.prefix(80).map(\.description).joined(separator: "\n")
        XCTAssertLessThanOrEqual(unlisted.count, Self.systemTextCeiling,
            "\(unlisted.count) system-font sites aren't listed as an icon, emoji or widget (ceiling \(Self.systemTextCeiling)) — text is Inter or Fraunces:\n\(list)")
        XCTAssertTrue(report.staleListings.isEmpty,
            "listed system-font sites no longer in the code — remove them from TypeScan.listed:\n\(report.staleListings.joined(separator: "\n"))")
        // Icons and emoji may use the system face — each one listed, and each
        // on what it says it is.
        XCTAssertEqual(report.symbolsByFile, TypeScan.listedSymbols,
                       "`.symbol(` sites changed — list them in TypeScan.listedSymbols (an SF Symbol only where Lucide has no glyph)")
        XCTAssertEqual(report.emojiByFile, TypeScan.listedEmoji,
                       "`.emoji(` sites changed — list them in TypeScan.listedEmoji")
        XCTAssertTrue(report.misplaced.isEmpty,
                      "a symbol size on something that isn't an SF Symbol, or an emoji size on words:\n\(report.misplaced.map(\.description).joined(separator: "\n"))")
        if unlisted.count < Self.systemTextCeiling {
            print("TypographyTests: \(unlisted.count) system-font text sites — lower systemTextCeiling from \(Self.systemTextCeiling)")
        }
    }

    /// Type leaves the scale in one place only — the Sunday Letter's board A
    /// display type, site by site — and never spreads (owner, 2026-10-07).
    func testOnlyTheLettersDisplayTypeLeavesTheScale() throws {
        let editorial = TypeScan.listed.filter { $0.why == .editorial }
        XCTAssertEqual(editorial.count, 5, "the masthead, a figure, the opening quote, the signature, the drop cap")
        XCTAssertTrue(editorial.allSatisfy { $0.file == TypeScan.editorialFile },
                      "an editorial size outside the letter: \(editorial.filter { $0.file != TypeScan.editorialFile }.map(\.file))")
        // The letter's faces load, by name, as the faces test proves for every face.
        XCTAssertNotNil(UIFont(name: "MrsSaintDelafield-Regular", size: 52))
        XCTAssertNotNil(UIFont(name: "Fraunces72pt-Italic", size: 18))
        // Its own family: the app's Fraunces is untouched by it.
        XCTAssertNotEqual(UIFont(name: "Fraunces72pt-Italic", size: 18)?.familyName, UIFont(name: "Fraunces-Regular", size: 18)?.familyName)
    }

    /// Nothing under 11 pt, even when a label gives way: `.minimumScaleFactor(x)`
    /// times the size of the font set just before it stays at 11 or more.
    func testNothingShrinksUnderEleven() throws {
        let report = try TypeScan.report()
        XCTAssertGreaterThan(report.shrinkSites, 10, "the scan must see the app's shrinking labels")
        XCTAssertTrue(report.shrinksUnder11.isEmpty,
            "these can shrink under 11 pt — wrap to a second line instead, or shrink only the big type:\n\(report.shrinksUnder11.joined(separator: "\n"))")
        // The arithmetic, on fixtures.
        XCTAssertEqual(TypeScan.smallestSize(in: "Text(a).font(.inter(compact ? 12 : 14, .bold))"), 12)
        XCTAssertEqual(TypeScan.smallestSize(in: "Text(a).font(.nCardKicker).kerning(1.4)"), 11)
        XCTAssertEqual(TypeScan.smallestSize(in: "Text(a).font(.fraunces(pal.fs(16)))"), 16)
        XCTAssertNil(TypeScan.smallestSize(in: "Text(a).lineLimit(1)"))
    }

    /// The scan's own arithmetic, on fixtures — so a broken scanner can't pass by seeing nothing.
    func testTheScanReadsSizesTheWayTheCodeWritesThem() {
        let code = """
        Text("a").font(.inter(10, .bold)) // .inter(9) in a comment is ignored
        Text("b").font(.fraunces(18, .semibold))
        Text("c").font(.inter(compact ? 12 : 14))
        Text("d").font(.inter(compact ? 7 : 13))
        Text("e").font(.fraunces(pal.fs(16)))
        Text("f").font(.inter(pal.fs(13.5)))
        Text("g").font(.inter(size * 0.4))
        Text("h \\(name ?? "x // y") ").font(.inter(12))
        /* .fraunces(40) */ Image(systemName: "x").font(.system(size: 12))
        Text("i").font(.custom("Inter-Bold", size: 17))
        let u = UIFont(name: "Fraunces-Medium", size: 30)
        Text("j").font(.body)
        Text("k").font(.system(.title, design: .serif))
        let v = UIFont.systemFont(ofSize: 12); let w = x ?? .boldSystemFont(ofSize: 9)
        Text("l").font(.inter(NuruTypeSnap(size * 0.4)))
        Text("m").font(.inter(NuruType.snap(size * 0.4), .semibold))
        let t = Nuru.uiFont("Inter-SemiBold", 17)
        static let baseSize: CGFloat = 16
        let f = UIFont(descriptor: d, size: Editor.baseSize)
        """
        let sites = TypeScan.sites(file: "Fixture.swift", text: code)
        let sized = sites.filter { $0.kind.isSized }
        XCTAssertEqual(sized.map(\.arg), ["10", "18", "compact ? 12 : 14", "compact ? 7 : 13", "pal.fs(16)",
                                          "pal.fs(13.5)", "size * 0.4", "12", "17", "30", "NuruTypeSnap(size * 0.4)",
                                          "NuruType.snap(size * 0.4)", "17", "Editor.baseSize"])
        XCTAssertEqual(sized.map { TypeScan.onScale($0.value) },
                       [false, true, true, false, true, false, nil, true, false, false, nil, true, false, true])
        XCTAssertEqual(sized.last?.value, "16", "a file's own `let …: CGFloat = 16` is read in")
        XCTAssertEqual(sites.filter { !$0.kind.isSized }.map(\.kind),
                       [.system, .textStyle, .systemStyle, .uiSystem, .uiSystem])
        // The listed system face, and the placement check that keeps it honest.
        let marks = TypeScan.sites(file: "Marks.swift", text: """
        Image(systemName: "star.fill").font(.symbol(12))
        Text("🙏").font(.emoji(15))
        Text(reaction.emoji).font(.emoji(15))
        Text("Amen").font(.emoji(15))
        """)
        XCTAssertEqual(marks.map(\.kind), [.symbol, .emoji, .emoji, .emoji])
        XCTAssertEqual(marks.dropFirst().map { TypeScan.isEmojiText($0.context.components(separatedBy: "\n").last ?? "") },
                       [true, true, false], "words never wear the emoji size")
        XCTAssertEqual(sites.first?.line, 1)
        XCTAssertEqual(sites.first(where: { $0.arg == "30" })?.line, 11)
    }

    /// The app's own scale is the spec's, and `snap` only ever lands on it.
    func testTheAppsScaleIsTheSpecsAndSnapLandsOnIt() {
        XCTAssertEqual(Set(NuruType.scale), Self.scale)
        XCTAssertEqual(NuruType.scale, NuruType.scale.sorted(), "ascending, so a tie goes up")
        var x: CGFloat = 0
        while x <= 80 {
            XCTAssertTrue(Self.scale.contains(NuruType.snap(x)), "snap(\(x)) = \(NuruType.snap(x))")
            x += 0.25
        }
        XCTAssertEqual(NuruType.snap(4), 11, "nothing under 11")
        XCTAssertEqual(NuruType.snap(14.4), 14)
        XCTAssertEqual(NuruType.snap(17), 18, "halfway goes up")
        XCTAssertEqual(NuruType.snap(20), 22)
        XCTAssertEqual(NuruType.snap(40), 28, "nothing over 28")
    }

    // MARK: - 3. What renders is what's asked for

    @MainActor
    func testTokenStyledTextRendersInTheNamedFace() throws {
        let key = Nuru.textScaleKey
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer { if let saved { UserDefaults.standard.set(saved, forKey: key) } }

        let sample = "Level 1 of 6 · KSh 1,000 — Fraunces & Inter"
        let roles: [(String, Font, String, CGFloat)] = [
            ("kicker", .nCardKicker, "Inter-Bold", 11),
            ("meta", .nCardMeta, "Inter-Medium", 11),
            ("chip", .nChipLabel, "Inter-SemiBold", 12),
            ("card body", .nCardBody, "Inter-Medium", 13),
            ("body", .nBody, "Inter-Medium", 14),
            ("content row title", .nRowTitle, "Fraunces-SemiBold", 15),
            ("reading body", .nBodyLg, "Inter-Medium", 16),
            ("card title", .nCardTitle, "Fraunces-SemiBold", 18),
            ("title", .nTitle, "Fraunces-Medium", 22),
            ("screen title", .fraunces(26, .semibold), "Fraunces-SemiBold", 26),
            ("display", .nDisplay, "Fraunces-Medium", 28),
            // The rest of the semantic tokens, so the scan's token table is proven.
            ("heading", .nHeading, "Inter-Medium", 16),
            ("label", .nLabel, "Inter-Medium", 12),
            ("caption", .nCaption, "Inter-Medium", 12),
            ("micro", .nMicro, "Inter-Medium", 11),
            ("overline", .nOverline, "Inter-SemiBold", 11),
            ("action", .nActionLabel, "Inter-Bold", 13),
            ("card CTA", .nCardCTA, "Inter-SemiBold", 14),
        ]
        for (role, token, face, size) in roles {
            let named = try XCTUnwrap(UIFont(name: face, size: size), face)
            let a = try Self.pixels(Text(sample).font(token))
            let b = try Self.pixels(Text(sample).font(Font(named)))
            XCTAssertEqual(a.size, b.size, "\(role): the token's text box differs from \(face) \(size)")
            XCTAssertTrue(a == b, "\(role): the token renders different pixels from \(face) \(size)")
        }
        // The comparison has teeth: the system face at the same size never matches.
        let inter = try Self.pixels(Text(sample).font(.nBody))
        let system = try Self.pixels(Text(sample).font(.system(size: 14, weight: .medium)))
        XCTAssertFalse(inter == system, "a renderer that can't tell Inter from the system face proves nothing")
        let smaller = try Self.pixels(Text(sample).font(.inter(13)))
        XCTAssertFalse(inter == smaller, "nor one that can't tell 14 from 13")
        // Text with no font of its own, under the app's root default, is the
        // body in Inter — never the system face.
        let body = try XCTUnwrap(UIFont(name: "Inter-Medium", size: 14))
        XCTAssertTrue(try Self.pixels(VStack { Text(sample) }.nuruDefaultFont()) == Self.pixels(Text(sample).font(Font(body))),
                      "an unstyled Text under nuruDefaultFont() must draw Inter Medium 14")
        XCTAssertFalse(try Self.pixels(VStack { Text(sample) }) == Self.pixels(Text(sample).font(Font(body))),
                       "without the root default an unstyled Text is the system face — the check has teeth")
    }

    // MARK: - 4. The member's own text size reaches every surface

    /// The member's text size (Profile → Display — `Nuru.textScale`, the
    /// rig's `-nuru.textScale`) reaches every surface the app draws: a sheet,
    /// a cover, a hosted window, a bar — not only the system's Dynamic Type
    /// (the Android audit, 2026-10-07: its dialogs and sheets dropped it). The
    /// SwiftUI type helpers read it as they draw, wherever they draw; what can
    /// drop it is UIKit text set at a fixed size, and a SwiftUI root hosted
    /// outside the app's, which inherits no default font. A new one of either
    /// fails here.
    func testTheInAppTextSizeReachesEverySurface() throws {
        // 1. Every UIKit font a member reads carries it.
        let exempt: [(file: String, snippet: String, why: String)] = [
            ("Theme/NuruTheme.swift", "UIFont(name: face, size: points)", "the helper that scales"),
            ("Features/Live/LiveStageCompositor.swift", "Nuru.uiFont(\"Inter-Bold\", max(12, tileSize.height * 0.14))",
             "drawn into the broadcast video, in its pixels"),
        ]
        var fixed: [String] = [], seen = 0
        let scaledVar = try NSRegularExpression(pattern: #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*CGFloat\s*\{\s*\d+(?:\.\d+)?\s*\*\s*Nuru\.textScale\s*\}"#)
        for (rel, text) in try TypeScan.files() {
            let ns = text as NSString
            let carriers = Set(scaledVar.matches(in: text, range: NSRange(location: 0, length: ns.length))
                .map { ns.substring(with: $0.range(at: 1)) })
            for s in TypeScan.sites(file: rel, text: text) where s.kind == .uiFont || s.kind == .nuruUIFont {
                seen += 1
                if exempt.contains(where: { $0.file == rel && s.source.contains($0.snippet) }) { continue }
                let name = String(s.arg.split(separator: ".").last ?? "")
                let carries = s.source.contains("scaled: true") || s.arg.contains("Nuru.textScale") || carriers.contains(name)
                if !carries { fixed.append(s.description) }
            }
        }
        XCTAssertGreaterThan(seen, 10, "the scan must see the app's UIKit fonts")
        XCTAssertEqual(fixed, [], "a UIKit font at a fixed size drops the member's text size — `Nuru.uiFont(face, size, scaled: true)`")

        // 2. A SwiftUI root hosted outside the app's takes the default font itself.
        var hosted = 0
        for (rel, text) in try TypeScan.files() {
            let ns = text as NSString
            var at = ns.range(of: "UIHostingController(rootView:")
            while at.location != NSNotFound {
                hosted += 1
                let root = TypeScan.firstArgument(ns, from: at.location + "UIHostingController(".utf16.count)
                XCTAssertTrue(root.contains(".nuruDefaultFont()"), "\(rel): a hosted root inherits nothing from the app's — give it `.nuruDefaultFont()`")
                let next = at.location + at.length
                at = ns.range(of: "UIHostingController(rootView:", range: NSRange(location: next, length: ns.length - next))
            }
        }
        XCTAssertEqual(hosted, 1, "IncomingLiveInvite's own window — a new hosted root: check it carries the size")

        // 3. The tabs rebuild at a new size; overlays and covers above them take the default too.
        let root = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Shell/RootView.swift"), encoding: .utf8)
        XCTAssertTrue(root.contains(".nuruDefaultFont()\n        .id(textScale)"))
        XCTAssertTrue(root.contains("        .nuruDefaultFont()\n    }\n\n    // Type-ERASED per tab"), "the outermost default font")

        // 4. The bars follow it: set again the moment it changes.
        let app = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("NuruMemberApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("Self.followTextSize()"))
    }

    /// What it draws: at the largest in-app size (1.3) a scaled UIKit font,
    /// the Selah editor's text and the bars are 1.3× their design size — and
    /// the bars follow a change without a relaunch.
    @MainActor
    func testUIKitTextGrowsWithTheInAppTextSize() throws {
        let key = Nuru.textScaleKey
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            NuruMemberApp.configureAppearance()
        }
        UserDefaults.standard.set(1.3, forKey: key)
        XCTAssertEqual(Nuru.uiFont("Inter-SemiBold", 16, scaled: true).pointSize, 20.8, accuracy: 0.01)
        XCTAssertEqual(Nuru.uiFont("Inter-SemiBold", 16).pointSize, 16, accuracy: 0.01, "unscaled stays as asked")
        XCTAssertEqual(SelahRichText.baseSize, 20.8, accuracy: 0.01, "the Selah editor's text")
        XCTAssertEqual(SelahRichText.baseFont.pointSize, 20.8, accuracy: 0.01)
        func barTitle() -> CGFloat? {
            (UINavigationBar.appearance().standardAppearance.titleTextAttributes[.font] as? UIFont)?.pointSize
        }
        // The app's observer set the bars again when the size changed (the test runs in the app).
        XCTAssertEqual(try XCTUnwrap(barTitle()), 20.8, accuracy: 0.01, "the bars follow the change")
        UserDefaults.standard.set(1.0, forKey: key)
        XCTAssertEqual(try XCTUnwrap(barTitle()), 16, accuracy: 0.01)
        XCTAssertEqual((UINavigationBar.appearance().standardAppearance.buttonAppearance.normal.titleTextAttributes[.font] as? UIFont)?.pointSize ?? 0,
                       16, accuracy: 0.01)
    }

    // MARK: - Rendering

    struct Pixels: Equatable {
        let width: Int, height: Int, bytes: [UInt8]
        var size: CGSize { CGSize(width: width, height: height) }
    }

    /// Renders a view to RGBA bytes at 2×, with the size category pinned so
    /// a custom font's Dynamic Type scaling can't differ between the two sides.
    @MainActor
    static func pixels<V: View>(_ view: V) throws -> Pixels {
        let content = view
            .foregroundStyle(Color.black)
            .fixedSize()
            .padding(2)
            .background(Color.white)
            .environment(\.dynamicTypeSize, .large)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage, "ImageRenderer produced nothing")
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let ok = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(ok, "couldn't read the rendered pixels")
        return Pixels(width: w, height: h, bytes: bytes)
    }
}

// MARK: - The source scan

/// Reads every Swift file of the app target (NuruMember/) and finds where a
/// font is made: the type helpers (`.inter`, `.fraunces`, `.nuruDisplay`),
/// `.custom(face, size:)`, `UIFont(name:size:)`, and every system font. The
/// home-screen widgets (NuruWidgets/) are outside the app target and allowed
/// the system face (§8.3: "icons and home-screen widgets are allowed and
/// listed") — they are not scanned.
enum TypeScan {

    enum Kind: String {
        case inter, fraunces, nuruDisplay, custom, uiFont, nuruUIFont
        case system, systemStyle, textStyle, uiSystem
        /// The listed system face: an SF Symbol's size, an emoji's size.
        case symbol, emoji
        /// `.minimumScaleFactor(x)` — how far a label may give way.
        case shrink
        var isSized: Bool { [.inter, .fraunces, .nuruDisplay, .custom, .uiFont, .nuruUIFont].contains(self) }
    }

    struct Site: CustomStringConvertible {
        let kind: Kind
        let file: String
        let line: Int
        let arg: String
        let source: String
        /// The size with a file constant (`let baseSize: CGFloat = 16`) read in.
        var resolved: String? = nil
        /// The four lines before the site and its own line up to the call.
        var context: String = ""
        var value: String { resolved ?? arg }
        var description: String { "\(file):\(line)  \(kind.rawValue)(\(arg))  \(source)" }
    }

    /// Why a listed site may set a size the scan can't read, or use the system face.
    enum Why: String {
        case typeHelper = "the type helpers themselves"
        case icon = "an icon (a glyph, not text)"
        case emoji = "an emoji (drawn by Apple Color Emoji whatever the face)"
        case logo = "the brand mark's letter, drawn in proportion to the mark"
        case video = "drawn into the broadcast video frame, sized in the frame's pixels"
        case fallback = "the release-only fallback if a bundled face failed to load — unreachable while the faces test passes"
        /// The one place type is set off the scale on purpose, each site listed.
        case editorial = "the Sunday Letter's editorial display type (owner, 2026-10-07: board A) — its masthead, drop cap, figures, opening quote and signature"
    }

    /// The editorial letter is the only file whose type may leave the scale.
    static let editorialFile = "Features/Home/LetterEditorialView.swift"

    /// Sites allowed outside the rules: (file, a snippet of the site's line, why).
    /// Every entry must still match a site — a stale entry fails the test.
    static let listed: [(file: String, snippet: String, why: Why)] = [
        ("Theme/NuruTheme.swift", ".custom(interFace(weight), size: size * Nuru.textScale)", .typeHelper),
        ("Theme/NuruTheme.swift", ".custom(frauncesFace(weight), size: size * Nuru.textScale)", .typeHelper),
        ("Theme/NuruTheme.swift", ".custom(frauncesFace(weight), size: size * Nuru.textScale)", .typeHelper),
        ("Theme/NuruTheme.swift", ".custom(\"Fraunces72pt-Italic\", size: size * Nuru.textScale)", .typeHelper),
        ("Theme/NuruTheme.swift", "if let font = UIFont(name: face, size: points) { return font }", .typeHelper),
        ("Theme/NuruTheme.swift", "return UIFont.systemFont(ofSize: points)", .fallback),
        ("Theme/NuruTheme.swift", ".system(size: size, weight: weight)", .icon),
        ("Theme/NuruTheme.swift", "static func emoji(_ size: CGFloat) -> Font { .system(size: size) }", .emoji),
        ("Theme/LucideIcons.swift", ".custom(\"lucide\", fixedSize: size)", .icon),
        ("Features/Shared/Components.swift", ".font(.nuruDisplay(size * 0.56, weight: .semibold))", .logo),
        ("Features/Live/LiveStageCompositor.swift", ".font: Nuru.uiFont(\"Inter-Bold\", max(12, tileSize.height * 0.14)),", .video),
        // The Sunday Letter, board A: display sizes the scale doesn't hold.
        (editorialFile, ".font(.frauncesItalic(34))", .editorial),
        (editorialFile, ".font(.fraunces(34, .medium))", .editorial),
        (editorialFile, ".font(.fraunces(44))", .editorial),
        (editorialFile, ".font(.custom(\"MrsSaintDelafield-Regular\", size: 52 * Nuru.textScale))", .editorial),
        (editorialFile, "Nuru.uiFont(\"Fraunces-SemiBold\", 58, scaled: true)", .editorial),
    ]

    /// Where an SF Symbol keeps the system face (`.symbol(size)`), per file.
    /// The icon family is Lucide (§8.1 rule 7); these are the glyphs it lacks.
    static let listedSymbols: [String: Int] = [
        "Features/Attendance/ServiceCheckInView.swift": 1,
        "Features/Chat/BroadcastViews.swift": 5,
        "Features/Chat/ChatThreadView.swift": 3,
        "Features/Chat/ChatView.swift": 6,
        "Features/Chat/ChatVoice.swift": 1,
        "Features/Chat/PastoralViews.swift": 2,
        "Features/Community/DiscussionsView.swift": 2,
        "Features/Community/SelahEditorView.swift": 1,
        "Features/Departments/DepartmentDetailView.swift": 1,
        "Features/Events/CheckInScannerView.swift": 1,
        "Features/Give/GivingView.swift": 5,
        "Features/Give/PartnerInviteSheet.swift": 1,
        "Features/Give/PartnersView.swift": 2,
        "Features/Grow/PlanSegmentView.swift": 2,
        "Features/Grow/PrayerJournalView.swift": 1,
        "Features/Grow/ReadingPlanCards.swift": 3,
        "Features/Grow/ReadingPlansView.swift": 3,
        "Features/Grow/ResourcesLibraryView.swift": 1,
        "Features/Home/CellRosterView.swift": 1,
        "Features/Home/HomeCards.swift": 4,
        "Features/Home/HomeView.swift": 6,
        "Features/Home/LiturgyRecorder.swift": 2,
        "Features/Home/ShareToChatSheet.swift": 1,
        "Features/Live/BroadcastSourceSheet.swift": 1,
        "Features/Live/BroadcastStudioCard.swift": 1,
        "Features/Live/GoLiveBroadcastView.swift": 4,
        "Features/Live/GuestStageOverlay.swift": 4,
        "Features/Live/LiveDiscoveryUI.swift": 1,
        "Features/Live/LiveDockChrome.swift": 2,
        "Features/Live/LiveFloatingChatOverlay.swift": 4,
        "Features/Live/LiveReactionEffects.swift": 2,
        "Features/Live/LiveStageView.swift": 2,
        "Features/Live/LiveViewerPlayerView.swift": 2,
        "Features/Live/NuruLiveTabView.swift": 1,
        "Features/Pathway/ModuleView.swift": 2,
        "Features/Pathway/PathwayView.swift": 2,
        "Features/Pathway/VoiceNoteCard.swift": 3,
        "Features/Radio/RadioMiniPlayer.swift": 1,
        "Features/Radio/RadioPlayerView.swift": 8,
    ]

    /// Where an emoji is sized (`.emoji(size)`), per file.
    static let listedEmoji: [String: Int] = [
        "Features/Chat/ChatThreadView.swift": 2,
        "Features/Chat/ChatView.swift": 1,
        "Features/Community/PrayerWallDetailView.swift": 1,
        "Features/Community/PrayerWallView.swift": 2,
        "Features/Discipleship/DisciplerDossierView.swift": 1,
        "Features/Events/EventDetailView.swift": 1,
        "Features/Home/HomeCards.swift": 1,
        "Features/Home/HomeView.swift": 3,
        "Features/Home/LiturgyCards.swift": 2,
        "Features/Pathway/LevelDetailView.swift": 1,
        "Features/Pathway/LevelExamView.swift": 3,
        "Features/Pathway/ModuleView.swift": 1,
        "Features/Pathway/QuizView.swift": 3,
        "Features/Profile/GiftsView.swift": 1,
        "Features/Radio/RadioPlayerView.swift": 2,
        "Features/Shared/CelebrationCenter.swift": 1,
        "Features/Shell/LocationInvite.swift": 1
    ]

    struct Report {
        var sizedCalls = 0
        var offScale: [Site] = []
        var systemText: [Site] = []
        var staleListings: [String] = []
        var symbolsByFile: [String: Int] = [:]
        var emojiByFile: [String: Int] = [:]
        var misplaced: [Site] = []
        var shrinkSites = 0
        var shrinksUnder11: [String] = []
    }

    // MARK: Files

    static var appRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NuruMember", isDirectory: true)
    }

    static func files() throws -> [(rel: String, text: String)] {
        let root = appRoot
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw NSError(domain: "TypeScan", code: 1, userInfo: [NSLocalizedDescriptionKey: "can't read the app's source at \(root.path) — the scan runs on a simulator beside the checkout"])
        }
        var out: [(String, String)] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in e where url.pathExtension == "swift" {
            let path = url.standardizedFileURL.path
            let rel = path.hasPrefix(rootPath + "/") ? String(path.dropFirst(rootPath.count + 1)) : url.lastPathComponent
            out.append((rel, try String(contentsOf: url, encoding: .utf8)))
        }
        guard out.count > 100 else {
            throw NSError(domain: "TypeScan", code: 2, userInfo: [NSLocalizedDescriptionKey: "only \(out.count) Swift files under \(root.path)"])
        }
        return out.sorted { $0.0 < $1.0 }
    }

    // MARK: Run

    private static var cached: Report?
    /// One scan per test run — the sources don't change under a running suite.
    static func report() throws -> Report {
        if let cached { return cached }
        let r = try run()
        cached = r
        return r
    }

    static func run() throws -> Report {
        var report = Report()
        var remaining = listed.map { (file: $0.file, snippet: $0.snippet, why: $0.why, used: false) }
        func consume(_ s: Site, editorialOnly: Bool = false) -> Bool {
            if let i = remaining.firstIndex(where: {
                !$0.used && $0.file == s.file && s.source.contains($0.snippet) && (!editorialOnly || $0.why == .editorial)
            }) {
                remaining[i].used = true
                return true
            }
            return false
        }
        for (rel, text) in try files() {
            for s in sites(file: rel, text: text) {
                if s.kind == .shrink {
                    report.shrinkSites += 1
                    let factor = smallest(s.arg)          // a ternary's smaller factor
                    let size = smallestSize(in: s.context)
                    if let factor, let size {
                        if size * factor < 11 - 0.001 {
                            report.shrinksUnder11.append("\(s.file):\(s.line)  \(size) pt × \(factor) = \(String(format: "%.1f", size * factor)) pt  \(s.source)")
                        }
                    } else {
                        report.shrinksUnder11.append("\(s.file):\(s.line)  can't tell what shrinks (factor \(s.arg)) — set the font beside it  \(s.source)")
                    }
                    continue
                }
                if s.kind == .symbol {
                    report.symbolsByFile[s.file, default: 0] += 1
                    if !(s.context.contains("Image(systemName") || s.context.contains("systemImage:")) { report.misplaced.append(s) }
                    continue
                }
                if s.kind == .emoji {
                    report.emojiByFile[s.file, default: 0] += 1
                    if !isEmojiText(s.context) { report.misplaced.append(s) }
                    // An emoji in a line of words takes the type scale's step
                    // (as Android draws it); only a picture-sized one (over 28)
                    // stands outside it.
                    if let v = Double(s.arg.trimmingCharacters(in: .whitespaces)) {
                        if v <= 28, !TypographyTests.scale.contains(CGFloat(v)) { report.offScale.append(s) }
                    } else if onScale(s.arg) != true {
                        report.offScale.append(s)
                    }
                    continue
                }
                if s.kind.isSized {
                    report.sizedCalls += 1
                    if onScale(s.value) == true { continue }
                    if onScale(s.value) == nil, consume(s) { continue }
                    // A size off the scale stands only as the letter's listed display type.
                    if onScale(s.value) == false, consume(s, editorialOnly: true) { continue }
                    report.offScale.append(s)
                } else {
                    if consume(s) { continue }
                    report.systemText.append(s)
                }
            }
        }
        report.staleListings = remaining.filter { !$0.used }.map { "\($0.file): \($0.snippet) (\($0.why.rawValue))" }
        return report
    }

    /// The semantic tokens' sizes (NuruTheme.swift) — each pinned to its face
    /// and size, pixel for pixel, by testTokenStyledTextRendersInTheNamedFace.
    static let tokenSizes: [String: CGFloat] = [
        "nDisplay": 28, "nTitle": 22, "nHeading": 16, "nBody": 14, "nBodyLg": 16,
        "nLabel": 12, "nCaption": 12, "nMicro": 11, "nOverline": 11,
        "nCardKicker": 11, "nCardTitle": 18, "nRowTitle": 15, "nCardBody": 13,
        "nCardMeta": 11, "nChipLabel": 12, "nActionLabel": 13, "nCardCTA": 14,
    ]

    /// The smallest size the LAST font set in this code can draw: a literal,
    /// a ternary's smaller step, a reader's `pal.fs(base)`, a token. Nil when
    /// no font is set here.
    static func smallestSize(in code: String) -> CGFloat? {
        let ns = code as NSString
        let all = NSRange(location: 0, length: ns.length)
        guard let fontRE = try? NSRegularExpression(pattern: #"(?<![A-Za-z0-9_])(?:inter|fraunces|nuruDisplay)\(|\.(n[A-Z][A-Za-z]+)\b"#),
              let last = fontRE.matches(in: code, range: all).last else { return nil }
        if last.range(at: 1).location != NSNotFound {
            return tokenSizes[ns.substring(with: last.range(at: 1))]
        }
        return smallest(firstArgument(ns, from: last.range.location + last.range.length))
    }

    static func smallest(_ raw: String) -> CGFloat? {
        let a = raw.trimmingCharacters(in: .whitespaces)
        if let v = Double(a) { return CGFloat(v) }
        if let (yes, no) = ternary(a) {
            guard let y = smallest(yes), let n = smallest(no) else { return nil }
            return min(y, n)
        }
        if a.hasPrefix("NuruType.snap(") { return 11 }
        if let r = a.range(of: ".fs("), a.hasSuffix(")") {
            return smallest(String(a[r.upperBound..<a.index(before: a.endIndex)]))
        }
        return nil
    }

    /// The statement draws an emoji: a `Text` of a literal with no letters or
    /// digits ("🙏", "✍️"), or of an expression that names an emoji.
    static func isEmojiText(_ context: String) -> Bool {
        guard let r = context.range(of: "Text(", options: .backwards) else { return false }
        let inner = String(context[r.upperBound...].prefix(60))
        if inner.hasPrefix("\"") {
            let literal = inner.dropFirst().prefix { $0 != "\"" }
            return !literal.isEmpty && !literal.contains { $0.isASCII && ($0.isLetter || $0.isNumber) }
        }
        return inner.prefix { $0 != ")" }.lowercased().contains("emoji")
    }

    // MARK: Faces

    /// Every string literal in the app that names a bundled face family.
    static func facesNamedInSource() throws -> Set<String> {
        var faces = Set<String>()
        let re = try NSRegularExpression(pattern: #""((?:Inter|Fraunces|Fraunces72pt|MrsSaintDelafield)-[A-Za-z]+|lucide)""#)
        for (_, text) in try files() {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                faces.insert(ns.substring(with: m.range(at: 1)))
            }
        }
        return faces
    }

    // MARK: Is a size on the scale?

    /// true / false when the argument can be read; nil when it is computed in
    /// a way the scan can't prove (it must then be listed, or it counts as off).
    static func onScale(_ raw: String) -> Bool? {
        let a = raw.trimmingCharacters(in: .whitespaces)
        if let v = Double(a) { return TypographyTests.scale.contains(CGFloat(v)) }
        // A ternary of sizes: every result must be on the scale.
        if let (yes, no) = ternary(a) {
            switch (onScale(yes), onScale(no)) {
            case (true?, true?): return true
            case (false?, _), (_, false?): return false
            default: return nil
            }
        }
        // `NuruType.snap(…)` lands on the scale by construction.
        if a.hasPrefix("NuruType.snap("), a.hasSuffix(")") { return true }
        // A reader's own size multiplier over a base size: the base must be on the scale.
        if let r = a.range(of: ".fs("), a.hasSuffix(")"),
           a[a.startIndex..<r.lowerBound].allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) {
            return onScale(String(a[r.upperBound..<a.index(before: a.endIndex)]))
        }
        return nil
    }

    /// Splits `cond ? a : b` at its top level.
    static func ternary(_ s: String) -> (String, String)? {
        let c = Array(s)
        var depth = 0, q: Int?
        for i in c.indices {
            switch c[i] {
            case "(", "[", "{": depth += 1
            case ")", "]", "}": depth -= 1
            case "?" where depth == 0 && q == nil:
                // `x ?? y` is not a ternary, nor is an optional chain `a?.b`.
                if i + 1 < c.count, c[i + 1] == "?" || c[i + 1] == "." { continue }
                if i > 0, c[i - 1] == "?" { continue }
                q = i
            case ":" where depth == 0 && q != nil:
                return (String(c[(q! + 1)..<i]), String(c[(i + 1)...]))
            default: break
            }
        }
        return nil
    }

    // MARK: Finding the sites

    private static let textStyles = "largeTitle|title|title2|title3|headline|subheadline|body|callout|footnote|caption|caption2"
    private static let patterns: [(Kind, NSRegularExpression)] = {
        func re(_ p: String) -> NSRegularExpression { try! NSRegularExpression(pattern: p) }
        return [
            // With or without a leading dot (the semantic tokens call `fraunces(28…)`), never a definition.
            (.inter, re(#"(?<![A-Za-z0-9_])(?<!func )inter\("#)),
            (.fraunces, re(#"(?<![A-Za-z0-9_])(?<!func )fraunces\("#)),
            // The letter's true italic (Fraunces 72pt Italic): its sizes hold the scale too.
            (.fraunces, re(#"(?<![A-Za-z0-9_])(?<!func )frauncesItalic\("#)),
            (.nuruDisplay, re(#"(?<![A-Za-z0-9_])(?<!func )nuruDisplay\("#)),
            (.custom, re(#"\.custom\("#)),
            (.uiFont, re(#"UIFont\(name:"#)),
            (.nuruUIFont, re(#"Nuru\.uiFont\("#)),
            (.uiFont, re(#"UIFont\(descriptor:"#)),
            (.system, re(#"\.system\(size:"#)),
            (.systemStyle, re(#"\.system\(\s*\.(?:\#(textStyles))\b"#)),
            (.textStyle, re(#"(?:\.font\(\s*|(?<![A-Za-z0-9_])Font)\.(?:\#(textStyles))\b"#)),
            (.uiSystem, re(#"\.(?:systemFont|boldSystemFont|italicSystemFont|monospacedSystemFont|monospacedDigitSystemFont)\(ofSize:|UIFont\.preferredFont\("#)),
            (.symbol, re(#"(?<![A-Za-z0-9_])\.symbol\("#)),
            (.emoji, re(#"(?<![A-Za-z0-9_])\.emoji\("#)),
            (.shrink, re(#"\.minimumScaleFactor\("#)),
        ]
    }()

    static func sites(file: String, text: String) -> [Site] {
        let code = stripComments(text)
        let ns = code as NSString
        let lines = text.components(separatedBy: "\n")
        // Line starts, to turn an offset into a line number.
        var starts: [Int] = [0]
        for (i, u) in (code as NSString).utf16Array.enumerated() where u == 10 { starts.append(i + 1) }
        func lineOf(_ offset: Int) -> Int {
            var lo = 0, hi = starts.count - 1
            while lo < hi { let mid = (lo + hi + 1) / 2; if starts[mid] <= offset { lo = mid } else { hi = mid - 1 } }
            return lo + 1
        }
        // The file's own size constants: `let name: CGFloat = 16` (a `var` can change, so never)
        // — and a size that carries the member's text size, `var name: CGFloat { 16 * Nuru.textScale }`,
        // read as its design size.
        var constants: [String: String] = [:]
        for pattern in [#"\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*CGFloat\s*=\s*(\d+(?:\.\d+)?)\b"#,
                        #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*CGFloat\s*\{\s*(\d+(?:\.\d+)?)\s*\*\s*Nuru\.textScale\s*\}"#] {
            guard let cre = try? NSRegularExpression(pattern: pattern) else { continue }
            for m in cre.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                constants[ns.substring(with: m.range(at: 1))] = ns.substring(with: m.range(at: 2))
            }
        }
        func resolve(_ arg: String) -> String {
            let a = arg.trimmingCharacters(in: .whitespaces)
            guard !a.isEmpty, a.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }),
                  let last = a.split(separator: ".").last, let v = constants[String(last)] else { return arg }
            return v
        }
        var out: [(Int, Site)] = []
        for (kind, re) in patterns {
            for m in re.matches(in: code, range: NSRange(location: 0, length: ns.length)) {
                let after = m.range.location + m.range.length
                var arg = ""
                switch kind {
                case .inter, .fraunces, .nuruDisplay, .system:
                    arg = firstArgument(ns, from: after)
                case .custom:
                    arg = labelled(ns, from: after, "size") ?? labelled(ns, from: after, "fixedSize") ?? ""
                case .uiFont:
                    // `UIFont(name:` or `UIFont(descriptor:` — read `size:` from the call's start.
                    let open = ns.range(of: "(", options: [], range: m.range).location
                    arg = labelled(ns, from: open + 1, "size") ?? ""
                case .nuruUIFont:
                    arg = secondArgument(ns, from: after)
                case .systemStyle, .textStyle, .uiSystem:
                    arg = ns.substring(with: m.range)
                case .symbol, .emoji, .shrink:
                    arg = firstArgument(ns, from: after)
                }
                let line = lineOf(m.range.location)
                let src = line - 1 < lines.count ? lines[line - 1].trimmingCharacters(in: .whitespaces) : ""
                // The statement up to the call: four lines back, never past it.
                let from = starts[max(0, line - 5)]
                let ctx = (text as NSString).substring(with: NSRange(location: from, length: m.range.location - from))
                out.append((m.range.location, Site(kind: kind, file: file, line: line, arg: arg, source: src,
                                                   resolved: kind.isSized ? resolve(arg) : nil, context: ctx)))
            }
        }
        return out.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The first top-level argument of a call whose `(` ends just before `from`.
    static func firstArgument(_ s: NSString, from: Int) -> String {
        var depth = 0, i = from, inString = false
        while i < s.length {
            let c = s.character(at: i)
            if inString {
                if c == 92 { i += 2; continue }               // backslash
                if c == 34 { inString = false }                // "
            } else if c == 34 { inString = true }
            else if c == 40 || c == 91 || c == 123 { depth += 1 }       // ( [ {
            else if c == 41 || c == 93 || c == 125 {                       // ) ] }
                if depth == 0 { break }
                depth -= 1
            } else if c == 44 && depth == 0 { break }                       // ,
            i += 1
        }
        return s.substring(with: NSRange(location: from, length: i - from)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The second top-level argument of a call whose `(` ends just before `from`.
    static func secondArgument(_ s: NSString, from: Int) -> String {
        var i = from
        // Walk past the first argument (as written, with its own nesting) to its comma.
        var depth = 0, inString = false
        while i < s.length {
            let c = s.character(at: i)
            if inString {
                if c == 92 { i += 2; continue }
                if c == 34 { inString = false }
            } else if c == 34 { inString = true }
            else if c == 40 || c == 91 || c == 123 { depth += 1 }
            else if c == 41 || c == 93 || c == 125 { if depth == 0 { return "" }; depth -= 1 }
            else if c == 44 && depth == 0 { break }
            i += 1
        }
        return i < s.length ? firstArgument(s, from: i + 1) : ""
    }

    /// The value of `label:` at the top level of the call that starts at `from`.
    static func labelled(_ s: NSString, from: Int, _ label: String) -> String? {
        var depth = 0, i = from, inString = false
        let l = label + ":"
        while i < s.length {
            let c = s.character(at: i)
            if inString {
                if c == 92 { i += 2; continue }
                if c == 34 { inString = false }
            } else if c == 34 { inString = true }
            else if c == 40 || c == 91 || c == 123 { depth += 1 }
            else if c == 41 || c == 93 || c == 125 {
                if depth == 0 { return nil }
                depth -= 1
            } else if depth == 0, i + l.utf16.count <= s.length,
                      s.substring(with: NSRange(location: i, length: l.utf16.count)) == l,
                      i == 0 || !isIdentifier(s.character(at: i - 1)) {
                return firstArgument(s, from: i + l.utf16.count)
            }
            i += 1
        }
        return nil
    }

    private static func isIdentifier(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95
    }

    /// The source with every comment blanked (line structure kept) and string
    /// literals intact — interpolations, multi-line and raw strings included.
    static func stripComments(_ text: String) -> String {
        let u = Array(text.utf16)
        var out = u
        var i = 0
        // A stack of contexts: code, a string (with how it closes), an interpolation's paren depth.
        enum Ctx { case code(parens: Int, interp: Bool), string(multi: Bool, hashes: Int) }
        var stack: [Ctx] = [.code(parens: 0, interp: false)]
        func at(_ k: Int, _ s: String) -> Bool {
            let p = Array(s.utf16)
            guard k + p.count <= u.count else { return false }
            return Array(u[k..<(k + p.count)]) == p
        }
        while i < u.count {
            switch stack.last! {
            case let .code(parens, interp):
                if at(i, "//") {
                    while i < u.count && u[i] != 10 { out[i] = 32; i += 1 }
                    continue
                }
                if at(i, "/*") {
                    var depth = 0
                    repeat {
                        if at(i, "/*") { depth += 1; out[i] = 32; out[i + 1] = 32; i += 2; continue }
                        if at(i, "*/") { depth -= 1; out[i] = 32; out[i + 1] = 32; i += 2; continue }
                        if u[i] != 10 { out[i] = 32 }
                        i += 1
                    } while depth > 0 && i < u.count
                    continue
                }
                var hashes = 0
                while i + hashes < u.count && u[i + hashes] == 35 { hashes += 1 }   // #
                if i + hashes < u.count && u[i + hashes] == 34 {                       // "
                    let multi = at(i + hashes, "\"\"\"")
                    i += hashes + (multi ? 3 : 1)
                    stack.append(.string(multi: multi, hashes: hashes))
                    continue
                }
                if u[i] == 40 { stack[stack.count - 1] = .code(parens: parens + 1, interp: interp) }
                if u[i] == 41 {
                    if interp && parens == 0 { stack.removeLast(); i += 1; continue }
                    stack[stack.count - 1] = .code(parens: max(0, parens - 1), interp: interp)
                }
                i += 1
            case let .string(multi, hashes):
                let close = String(repeating: "\"", count: multi ? 3 : 1) + String(repeating: "#", count: hashes)
                if u[i] == 92 {                                                       // backslash
                    let esc = String(repeating: "#", count: hashes)
                    if at(i + 1, esc + "(") {                                          // interpolation
                        i += 1 + hashes + 1
                        stack.append(.code(parens: 0, interp: true))
                        continue
                    }
                    if hashes == 0 { i += 2; continue }
                }
                if at(i, close) { i += close.utf16.count; stack.removeLast(); continue }
                if !multi && u[i] == 10 { stack.removeLast() }                       // unterminated: recover
                i += 1
            }
        }
        return String(utf16CodeUnits: out, count: out.count)
    }
}

private extension NSString {
    var utf16Array: [unichar] { (self as String).utf16.map { $0 } }
}
