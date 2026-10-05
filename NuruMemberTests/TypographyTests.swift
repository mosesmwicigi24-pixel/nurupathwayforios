// Typography, proven by tests rather than by eye (pathway docs/EXPERIENCE.md
// §8.1 rule 3, §8.2 #21, §8.3 — the owner, 2026-10-05: "check the fonts and
// put them in vigorous test to be the same").
//
// 1. The faces resolve: every face the code names loads by name, so a missing
//    or misspelt font can never fall back to the system face in silence.
// 2. The scale holds: a scan of every Swift file in the app fails on a text
//    size off the scale and on a system font used for text. Icons, emoji and
//    the home-screen widgets may use the system face, but each site is listed
//    below with its reason. The scan began as a ratchet (the count may only
//    fall) and ends at zero.
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

    // MARK: - The ratchet (§8.3): these may only fall

    /// Text sizes set in code that are off the scale (or computed where the
    /// scan can't prove they land on it). Measured at d55d767: 545; falling
    /// as each area moves onto the scale.
    static let offScaleCeiling = 365
    /// System-font sites not listed as an icon, emoji or widget — a system
    /// face used for text. Measured at d55d767: 144.
    static let systemTextCeiling = 137

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
        if unlisted.count < Self.systemTextCeiling {
            print("TypographyTests: \(unlisted.count) system-font text sites — lower systemTextCeiling from \(Self.systemTextCeiling)")
        }
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
    }

    /// Sites allowed outside the rules: (file, a snippet of the site's line, why).
    /// Every entry must still match a site — a stale entry fails the test.
    static let listed: [(file: String, snippet: String, why: Why)] = [
        ("Theme/NuruTheme.swift", ".custom(interFace(weight), size: size * Nuru.textScale)", .typeHelper),
        ("Theme/NuruTheme.swift", ".custom(frauncesFace(weight), size: size * Nuru.textScale)", .typeHelper),
        ("Theme/NuruTheme.swift", ".custom(frauncesFace(weight), size: size * Nuru.textScale)", .typeHelper),
        ("Theme/NuruTheme.swift", "if let font = UIFont(name: face, size: size) { return font }", .typeHelper),
        ("Theme/NuruTheme.swift", "return UIFont.systemFont(ofSize: size)", .fallback),
        ("Theme/LucideIcons.swift", ".custom(\"lucide\", fixedSize: size)", .icon),
        ("Features/Shared/Components.swift", ".font(.nuruDisplay(size * 0.56, weight: .semibold))", .logo),
        ("Features/Live/LiveStageCompositor.swift", ".font: Nuru.uiFont(\"Inter-Bold\", max(12, tileSize.height * 0.14)),", .video),
    ]

    struct Report {
        var sizedCalls = 0
        var offScale: [Site] = []
        var systemText: [Site] = []
        var staleListings: [String] = []
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
        func consume(_ s: Site) -> Bool {
            if let i = remaining.firstIndex(where: { !$0.used && $0.file == s.file && s.source.contains($0.snippet) }) {
                remaining[i].used = true
                return true
            }
            return false
        }
        for (rel, text) in try files() {
            for s in sites(file: rel, text: text) {
                if s.kind.isSized {
                    report.sizedCalls += 1
                    if onScale(s.value) == true { continue }
                    if onScale(s.value) == nil, consume(s) { continue }
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

    // MARK: Faces

    /// Every string literal in the app that names a bundled face family.
    static func facesNamedInSource() throws -> Set<String> {
        var faces = Set<String>()
        let re = try NSRegularExpression(pattern: #""((?:Inter|Fraunces)-[A-Za-z]+|lucide)""#)
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
            (.nuruDisplay, re(#"(?<![A-Za-z0-9_])(?<!func )nuruDisplay\("#)),
            (.custom, re(#"\.custom\("#)),
            (.uiFont, re(#"UIFont\(name:"#)),
            (.nuruUIFont, re(#"Nuru\.uiFont\("#)),
            (.uiFont, re(#"UIFont\(descriptor:"#)),
            (.system, re(#"\.system\(size:"#)),
            (.systemStyle, re(#"\.system\(\s*\.(?:\#(textStyles))\b"#)),
            (.textStyle, re(#"(?:\.font\(\s*|(?<![A-Za-z0-9_])Font)\.(?:\#(textStyles))\b"#)),
            (.uiSystem, re(#"\.(?:systemFont|boldSystemFont|italicSystemFont|monospacedSystemFont|monospacedDigitSystemFont)\(ofSize:|UIFont\.preferredFont\("#)),
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
        // The file's own size constants: `let name: CGFloat = 16` (a `var` can change, so never).
        var constants: [String: String] = [:]
        if let cre = try? NSRegularExpression(pattern: #"\blet\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*CGFloat\s*=\s*(\d+(?:\.\d+)?)\b"#) {
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
                }
                let line = lineOf(m.range.location)
                let src = line - 1 < lines.count ? lines[line - 1].trimmingCharacters(in: .whitespaces) : ""
                out.append((m.range.location, Site(kind: kind, file: file, line: line, arg: arg, source: src,
                                                   resolved: kind.isSized ? resolve(arg) : nil)))
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
