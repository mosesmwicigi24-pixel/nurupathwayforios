// Selah's rich-text engine: a UITextView wrapped for SwiftUI (bold, italic,
// color, font, spacing — the five traits `ThoughtSpan` can persist) plus the
// plain-text ↔ NSAttributedString ↔ [ThoughtSpan] round-trip that keeps the
// wire shape exactly what ThoughtsService.ThoughtUpsert expects.
//
// Spacing round-trips per span, the same way bold/italic/color/font do: the
// toolbar's spacing menu writes a `ThoughtSpan.spacing` multiplier (0.8–2.5,
// matching packages/backend/src/modules/thoughts/service.ts) over the current
// selection — or the whole note when nothing is selected, the common "space
// this whole thought out" gesture. The member's global reading line-spacing
// preference (Nuru.lineSpacing, Theme/NuruTheme.swift) is layered on top at
// build() time, exactly like every other reading surface in the app.
import SwiftUI
import UIKit

// MARK: - Fonts a member can pick for a run of their thought

enum SelahFont: String, CaseIterable, Identifiable {
    case inter = "Inter-Medium"
    case fraunces = "Fraunces-Regular"
    case georgia = "Georgia"
    case noteworthy = "Noteworthy-Bold"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .inter: return "Inter"
        case .fraunces: return "Fraunces"
        case .georgia: return "Georgia"
        case .noteworthy: return "Noteworthy"
        }
    }
    func uiFont(size: CGFloat) -> UIFont { UIFont(name: rawValue, size: size) ?? .systemFont(ofSize: size) }
}

/// Line spacing presets — the toolbar menu writes one of these onto the
/// current selection (or the whole note) as a `ThoughtSpan.spacing`
/// multiplier. Same three-tier scale as the app-wide Settings → Line spacing
/// control (Compact/Default/Relaxed → 0.85/1.0/1.35) so a member's sense of
/// "cozy vs relaxed" means the same thing everywhere.
enum SelahSpacing: String, CaseIterable, Identifiable {
    case cozy, comfortable, relaxed
    var id: String { rawValue }
    var label: String {
        switch self {
        case .cozy: return "Cozy"
        case .comfortable: return "Comfortable"
        case .relaxed: return "Relaxed"
        }
    }
    /// The per-span multiplier persisted to `ThoughtSpan.spacing`.
    var multiplier: Double {
        switch self {
        case .cozy: return 0.85
        case .comfortable: return 1.0
        case .relaxed: return 1.35
        }
    }
    /// Nearest preset for a stored multiplier (used to redraw the doc default).
    static func nearest(_ multiplier: Double) -> SelahSpacing {
        allCases.min(by: { abs($0.multiplier - multiplier) < abs($1.multiplier - multiplier) }) ?? .comfortable
    }
}

// MARK: - Color palette a span.color can hold ("#RRGGBB")

enum SelahColor: String, CaseIterable, Identifiable {
    case ink = "#0B1F33"      // Nuru.navy — default
    case gold = "#C9A227"
    case crimson = "#B91C1C"
    case forest = "#166534"
    case ocean = "#1D4ED8"
    case plum = "#7C3AED"

    var id: String { rawValue }
    var uiColor: UIColor { UIColor(hex: rawValue) ?? UIColor(hex: SelahColor.ink.rawValue)! }
}

extension UIColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                   blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }
    /// "#RRGGBB", nil for anything that isn't plain RGB (e.g. dynamic colors).
    var hexString: String? {
        guard let c = cgColor.components, c.count >= 3 else { return nil }
        let r = Int((c[0] * 255).rounded()), g = Int((c[1] * 255).rounded()), b = Int((c[2] * 255).rounded())
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}

// MARK: - body + [ThoughtSpan] ⇄ NSAttributedString

enum SelahRichText {
    static let baseSize: CGFloat = 16
    static let baseFontName = SelahFont.inter.rawValue
    static let baseColorHex = SelahColor.ink.rawValue
    /// Points at a 1.0 multiplier, before either the per-span spacing choice
    /// or the global Nuru.lineSpacing preference are applied.
    static let anchorPoints: CGFloat = 6

    /// The paragraph style for a given spacing multiplier — the per-span
    /// override AND the document base both go through this, so the global
    /// reading preference (Nuru.lineSpacing) always applies on top.
    static func paragraphStyle(forMultiplier multiplier: Double) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = anchorPoints * CGFloat(multiplier) * Nuru.lineSpacing
        return style
    }

    /// Compose the editor's starting attributed string from the stored plain
    /// body + its formatting spans (server truth → on-screen truth).
    static func build(body: String, spans: [ThoughtSpan]?, spacing: SelahSpacing) -> NSAttributedString {
        let base: [NSAttributedString.Key: Any] = [
            .font: UIFont(name: baseFontName, size: baseSize) ?? .systemFont(ofSize: baseSize),
            .foregroundColor: UIColor(hex: baseColorHex) ?? .black,
            .paragraphStyle: paragraphStyle(forMultiplier: spacing.multiplier),
        ]
        let ns = NSMutableAttributedString(string: body, attributes: base)
        let length = (body as NSString).length
        for span in spans ?? [] {
            let start = max(0, min(span.start, length))
            let end = max(start, min(span.end, length))
            guard end > start else { continue }
            let range = NSRange(location: start, length: end - start)
            if span.bold == true || span.italic == true {
                let fontName = span.font ?? baseFontName
                var uiFont = UIFont(name: fontName, size: baseSize) ?? .systemFont(ofSize: baseSize)
                var traits: UIFontDescriptor.SymbolicTraits = []
                if span.bold == true { traits.insert(.traitBold) }
                if span.italic == true { traits.insert(.traitItalic) }
                if let d = uiFont.fontDescriptor.withSymbolicTraits(traits) { uiFont = UIFont(descriptor: d, size: baseSize) }
                ns.addAttribute(.font, value: uiFont, range: range)
            } else if let fontName = span.font {
                ns.addAttribute(.font, value: SelahFont(rawValue: fontName)?.uiFont(size: baseSize)
                                 ?? UIFont(name: fontName, size: baseSize) ?? .systemFont(ofSize: baseSize), range: range)
            }
            if let hex = span.color, let c = UIColor(hex: hex) {
                ns.addAttribute(.foregroundColor, value: c, range: range)
            }
            if let m = span.spacing {
                ns.addAttribute(.paragraphStyle, value: paragraphStyle(forMultiplier: m), range: range)
            }
        }
        return ns
    }

    /// Reverse direction: scan the edited attributed string's runs and emit one
    /// ThoughtSpan per run whose bold/italic/color/font/spacing differs from
    /// baseline. Adjacent runs with identical formatting are merged into one
    /// span. `documentSpacing` is the note's current default (the toolbar's
    /// no-selection choice) — a run's spacing round-trips as an explicit
    /// per-span override only when it differs from that default.
    static func extract(_ attr: NSAttributedString, documentSpacing: SelahSpacing) -> (body: String, spans: [ThoughtSpan]) {
        var spans: [ThoughtSpan] = []
        var pending: ThoughtSpan?
        let docPoints = paragraphStyle(forMultiplier: documentSpacing.multiplier).lineSpacing
        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length), options: []) { attrs, range, _ in
            let font = attrs[.font] as? UIFont
            let traits = font?.fontDescriptor.symbolicTraits ?? []
            let isBold = traits.contains(.traitBold)
            let isItalic = traits.contains(.traitItalic)
            let colorHex = (attrs[.foregroundColor] as? UIColor)?.hexString
            let fontFamily = font.flatMap { f in SelahFont.allCases.first { $0.rawValue == f.fontName }?.rawValue }
                ?? (font?.fontName != baseFontName ? font?.fontName : nil)

            // A run's own paragraph style differs from the document default →
            // an explicit per-span spacing override, stored as a 0.8–2.5 multiplier.
            let runPoints = (attrs[.paragraphStyle] as? NSParagraphStyle)?.lineSpacing
            let spacingOverride: Double? = {
                guard let pts = runPoints, abs(pts - docPoints) > 0.4 else { return nil }
                let raw = Double(pts / max(Nuru.lineSpacing, 0.01) / anchorPoints)
                return min(max(raw, 0.8), 2.5)
            }()

            let differsFromBase = isBold || isItalic
                || (colorHex != nil && colorHex != baseColorHex)
                || (fontFamily != nil && fontFamily != baseFontName)
                || spacingOverride != nil
            guard differsFromBase else {
                if let p = pending { spans.append(p); pending = nil }
                return
            }
            let span = ThoughtSpan(
                start: range.location, end: range.location + range.length,
                bold: isBold ? true : nil, italic: isItalic ? true : nil,
                color: (colorHex != nil && colorHex != baseColorHex) ? colorHex : nil,
                font: (fontFamily != nil && fontFamily != baseFontName) ? fontFamily : nil,
                spacing: spacingOverride)
            if var p = pending, p.end == span.start, p.bold == span.bold, p.italic == span.italic,
               p.color == span.color, p.font == span.font, p.spacing == span.spacing {
                p.end = span.end
                pending = p
            } else {
                if let p = pending { spans.append(p) }
                pending = span
            }
        }
        if let p = pending { spans.append(p) }
        return (attr.string, Array(spans.prefix(2000)))
    }
}

// MARK: - Live controller bridging SwiftUI toolbar buttons ↔ the hosted UITextView

@MainActor
final class RichEditorController: ObservableObject {
    weak var textView: UITextView?
    @Published var selectionBold = false
    @Published var selectionItalic = false
    @Published var isEmpty = true

    func refreshSelectionState() {
        guard let tv = textView else { return }
        isEmpty = tv.attributedText.length == 0
        let attrs: [NSAttributedString.Key: Any]
        if tv.selectedRange.length > 0, tv.selectedRange.location + tv.selectedRange.length <= tv.attributedText.length {
            attrs = tv.attributedText.attributes(at: tv.selectedRange.location, effectiveRange: nil)
        } else {
            attrs = tv.typingAttributes
        }
        let traits = (attrs[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        selectionBold = traits.contains(.traitBold)
        selectionItalic = traits.contains(.traitItalic)
    }

    func toggleBold() { toggleTrait(.traitBold) }
    func toggleItalic() { toggleTrait(.traitItalic) }

    private func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let font = (value as? UIFont) ?? UIFont(name: SelahRichText.baseFontName, size: SelahRichText.baseSize)!
                var traits = font.fontDescriptor.symbolicTraits
                if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
                let desc = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
                mutable.addAttribute(.font, value: UIFont(descriptor: desc, size: SelahRichText.baseSize), range: subrange)
            }
            tv.attributedText = mutable
            tv.selectedRange = range
        } else {
            let font = (tv.typingAttributes[.font] as? UIFont) ?? UIFont(name: SelahRichText.baseFontName, size: SelahRichText.baseSize)!
            var traits = font.fontDescriptor.symbolicTraits
            if traits.contains(trait) { traits.remove(trait) } else { traits.insert(trait) }
            let desc = font.fontDescriptor.withSymbolicTraits(traits) ?? font.fontDescriptor
            tv.typingAttributes[.font] = UIFont(descriptor: desc, size: SelahRichText.baseSize)
        }
        refreshSelectionState()
    }

    func applyColor(_ color: SelahColor) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.addAttribute(.foregroundColor, value: color.uiColor, range: range)
            tv.attributedText = mutable
            tv.selectedRange = range
        } else {
            tv.typingAttributes[.foregroundColor] = color.uiColor
        }
    }

    func applyFont(_ font: SelahFont) {
        guard let tv = textView else { return }
        let range = tv.selectedRange
        let size = SelahRichText.baseSize
        if range.length > 0 {
            let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
            mutable.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
                let existing = (value as? UIFont)?.fontDescriptor.symbolicTraits ?? []
                let desc = font.uiFont(size: size).fontDescriptor.withSymbolicTraits(existing) ?? font.uiFont(size: size).fontDescriptor
                mutable.addAttribute(.font, value: UIFont(descriptor: desc, size: size), range: subrange)
            }
            tv.attributedText = mutable
            tv.selectedRange = range
        } else {
            tv.typingAttributes[.font] = font.uiFont(size: size)
        }
    }

    /// Selection present → per-span override (persists as `ThoughtSpan.spacing`
    /// on just that range, like bold/italic/color/font). No selection → the
    /// whole note, the common "space this thought out" gesture, which also
    /// becomes the document's default for future typing.
    func applySpacing(_ spacing: SelahSpacing) {
        guard let tv = textView else { return }
        let style = SelahRichText.paragraphStyle(forMultiplier: spacing.multiplier)
        let selection = tv.selectedRange
        let mutable = NSMutableAttributedString(attributedString: tv.attributedText)
        let range = selection.length > 0 ? selection : NSRange(location: 0, length: mutable.length)
        mutable.addAttribute(.paragraphStyle, value: style, range: range)
        tv.attributedText = mutable
        tv.selectedRange = selection
        var typing = tv.typingAttributes
        typing[.paragraphStyle] = style
        tv.typingAttributes = typing
    }
}

/// UITextView bridge. `onChange` fires the live attributed string back up so
/// the caller always has the latest content for autosave-on-dismiss / Save.
struct RichTextEditor: UIViewRepresentable {
    let controller: RichEditorController
    let initial: NSAttributedString
    let placeholder: String
    let onChange: (NSAttributedString) -> Void

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.attributedText = initial
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.textContainerInset = UIEdgeInsets(top: 14, left: 10, bottom: 14, right: 10)
        tv.delegate = context.coordinator
        tv.typingAttributes = [
            .font: UIFont(name: SelahRichText.baseFontName, size: SelahRichText.baseSize) ?? .systemFont(ofSize: SelahRichText.baseSize),
            .foregroundColor: UIColor(hex: SelahRichText.baseColorHex) ?? .black,
        ]
        controller.textView = tv
        controller.refreshSelectionState()
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextViewDelegate {
        let parent: RichTextEditor
        init(_ parent: RichTextEditor) { self.parent = parent }
        func textViewDidChange(_ tv: UITextView) {
            parent.onChange(tv.attributedText)
            parent.controller.refreshSelectionState()
        }
        func textViewDidChangeSelection(_ tv: UITextView) {
            parent.controller.refreshSelectionState()
        }
    }
}
