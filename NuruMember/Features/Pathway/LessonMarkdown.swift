// LessonMarkdown — a small, purpose-built Markdown parser + SwiftUI renderer for
// the lesson reader. The lesson body arrives as Markdown-flavoured text; the old
// reader dumped each line into a plain `Text`, so headings showed literal `###`,
// scripture showed literal `>`, and the "Practical Application" grid showed raw
// `| … | … |` pipes. This module fixes that: it lexes the content into typed
// blocks (headings, blockquotes, tables, lists, rules, paragraphs) and renders
// each one properly using the reader's `ML.*` palette.
//
// Design notes:
// • Inline runs (**bold**, *italic*, `_italic_`) go through AttributedString's
//   Markdown initialiser, with a plain-text fallback if parsing throws — so a
//   malformed run degrades to legible text rather than crashing.
// • Blockquotes become a gold-ruled scripture callout; a trailing "— Attribution"
//   line is split out and set in gold.
// • Tables render as a real grid (bold header on a faint gold fill, hairline row
//   separators, rounded container) and scroll horizontally if they overflow.
// • Body copy stays at the reader's established size/colour: Inter 15, ML.bodyInk,
//   lineSpacing 6.
//
// The palette (`ML`) lives in ModuleView.swift; this file is in the same module
// and target, so it references it directly.
import SwiftUI

// MARK: - Block model

/// One parsed Markdown block. `MLMarkdown.parse` turns raw lesson text into an
/// ordered list of these; `MLMarkdownView` renders them top-to-bottom.
enum MLBlock: Identifiable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bullet([String])                 // grouped consecutive bullet items
    case numbered([(Int, String)])         // grouped consecutive "1." items
    case quote(body: String, attribution: String?)
    case table(header: [String], rows: [[String]])
    case rule

    var id: String {
        switch self {
        case let .heading(l, t):    return "h\(l)-\(t.hashValue)"
        case let .paragraph(t):     return "p-\(t.hashValue)"
        case let .bullet(items):    return "ul-\(items.joined(separator: "|").hashValue)"
        case let .numbered(items):  return "ol-\(items.map(\.1).joined(separator: "|").hashValue)"
        case let .quote(b, a):      return "q-\(b.hashValue)-\(a?.hashValue ?? 0)"
        case let .table(h, r):      return "t-\(h.joined().hashValue)-\(r.count)"
        case .rule:                 return "hr-\(UUID().uuidString)"
        }
    }
}

// MARK: - Parser

enum MLMarkdown {

    /// Parse a Markdown lesson body into ordered blocks. Blank lines separate
    /// blocks; runs of like items (bullets, numbered, quote lines, table rows)
    /// are coalesced into one block.
    static func parse(_ raw: String) -> [MLBlock] {
        let lines = raw
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        var blocks: [MLBlock] = []
        var paragraph: [String] = []       // buffered wrapped lines of a paragraph
        var i = 0

        func flushParagraph() {
            let joined = paragraph.joined(separator: " ").trimmingCharacters(in: .whitespaces)
            if !joined.isEmpty { blocks.append(.paragraph(joined)) }
            paragraph.removeAll()
        }

        while i < lines.count {
            let rawLine = lines[i]
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            // Blank line → paragraph break.
            if line.isEmpty { flushParagraph(); i += 1; continue }

            // Horizontal rule: --- / *** / ___ on their own line.
            if isRule(line) { flushParagraph(); blocks.append(.rule); i += 1; continue }

            // ATX heading.
            if let (level, text) = heading(line) {
                flushParagraph()
                blocks.append(.heading(level: level, text: text))
                i += 1; continue
            }

            // Table: a "| … |" line followed by a "| --- | --- |" separator row.
            if isTableRow(line), i + 1 < lines.count,
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph()
                let header = tableCells(line)
                i += 2   // consume header + separator
                var rows: [[String]] = []
                while i < lines.count {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    guard isTableRow(r) else { break }
                    rows.append(normalizeRow(tableCells(r), width: header.count))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // Blockquote: one or more consecutive "> …" lines.
            if line.hasPrefix(">") {
                flushParagraph()
                var quoteLines: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    quoteLines.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(makeQuote(quoteLines))
                continue
            }

            // Bullet list: consecutive "- " / "* " / "• " / "● " lines.
            if bulletBody(line) != nil {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let b = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let body = bulletBody(b) else { break }
                    items.append(body)
                    i += 1
                }
                blocks.append(.bullet(items))
                continue
            }

            // Numbered list: consecutive "1. " / "2) " lines.
            if numberedBody(line) != nil {
                flushParagraph()
                var items: [(Int, String)] = []
                while i < lines.count {
                    let n = lines[i].trimmingCharacters(in: .whitespaces)
                    guard let pair = numberedBody(n) else { break }
                    items.append(pair)
                    i += 1
                }
                blocks.append(.numbered(items))
                continue
            }

            // Otherwise: part of a paragraph.
            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    // MARK: Line classifiers

    private static func isRule(_ line: String) -> Bool {
        guard line.count >= 3 else { return false }
        let set = Set(line)
        return set == ["-"] || set == ["*"] || set == ["_"]
    }

    /// ATX heading: 1–6 leading `#`, a space, then text. Returns (level, text)
    /// with any trailing `#` closers stripped.
    private static func heading(_ line: String) -> (Int, String)? {
        var level = 0
        var idx = line.startIndex
        while idx < line.endIndex, line[idx] == "#", level < 6 {
            level += 1; idx = line.index(after: idx)
        }
        guard level > 0, idx < line.endIndex, line[idx] == " " else { return nil }
        let text = line[idx...]
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : (level, text)
    }

    private static func isTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.dropFirst().contains("|")
    }

    /// A separator row is all `|`, `-`, `:`, and spaces, with at least one `-`.
    private static func isTableSeparator(_ line: String) -> Bool {
        guard isTableRow(line) else { return false }
        let inner = line.filter { $0 != "|" && $0 != " " }
        guard !inner.isEmpty else { return false }
        return inner.allSatisfy { $0 == "-" || $0 == ":" }
    }

    /// Split "| a | b | c |" into ["a","b","c"] (leading/trailing pipes dropped).
    private static func tableCells(_ line: String) -> [String] {
        var s = line
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        return s.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Pad/trim a body row to the header width so the grid stays rectangular.
    private static func normalizeRow(_ cells: [String], width: Int) -> [String] {
        if cells.count == width { return cells }
        if cells.count < width { return cells + Array(repeating: "", count: width - cells.count) }
        return Array(cells.prefix(width))
    }

    private static func bulletBody(_ line: String) -> String? {
        for marker in ["- ", "* ", "• ", "● "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    /// "12. text" / "3) text" → (12, "text"). Only when a body follows.
    private static func numberedBody(_ line: String) -> (Int, String)? {
        var idx = line.startIndex
        var digits = ""
        while idx < line.endIndex, line[idx].isNumber { digits.append(line[idx]); idx = line.index(after: idx) }
        guard !digits.isEmpty, let n = Int(digits), idx < line.endIndex else { return nil }
        let sep = line[idx]
        guard sep == "." || sep == ")" else { return nil }
        let after = line.index(after: idx)
        guard after < line.endIndex, line[after] == " " else { return nil }
        let body = String(line[after...]).trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? nil : (n, body)
    }

    /// Turn quote lines into a scripture callout, splitting a trailing
    /// "— Attribution" (em-dash, en-dash, or double-hyphen) into its own field.
    private static func makeQuote(_ lines: [String]) -> MLBlock {
        let joined = lines.joined(separator: "\n")
        // Find the last attribution marker at a line start or after the verse.
        for marker in ["\u{2014}", "\u{2013}", "--"] {   // — – --
            if let r = joined.range(of: marker, options: .backwards) {
                let body = String(joined[..<r.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                let attr = String(joined[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !body.isEmpty, !attr.isEmpty, attr.count <= 60 {
                    return .quote(body: stripWrappingQuotes(body), attribution: attr)
                }
            }
        }
        return .quote(body: stripWrappingQuotes(joined.trimmingCharacters(in: .whitespacesAndNewlines)),
                      attribution: nil)
    }

    /// True when a blockquote's attribution reads like a scripture reference —
    /// "Romans 12:2", "1 Corinthians 13:4-7", "Galatians 1:10 (WEB)" — as
    /// opposed to a person's name or a generic dash-off attribution. Deliberately
    /// conservative (requires a "chapter:verse" shape) so an ordinary quote with
    /// no scripture reference never gets hijacked into the verse-card styling.
    static func isScriptureReference(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, t.count <= 40 else { return false }
        let pattern = #"^[1-3]?\s?[A-Za-z][A-Za-z.\s]{1,28}\d{1,3}:\d{1,3}(-\d{1,3})?"#
        return t.range(of: pattern, options: .regularExpression) != nil
    }

    private static func stripWrappingQuotes(_ s: String) -> String {
        var t = s
        let opens: Set<Character> = ["\"", "\u{201C}"]
        let closes: Set<Character> = ["\"", "\u{201D}"]
        if let f = t.first, opens.contains(f) { t.removeFirst() }
        if let l = t.last, closes.contains(l) { t.removeLast() }
        return t.trimmingCharacters(in: .whitespaces)
    }

    // MARK: Inline

    /// Render inline **bold** / *italic* / _italic_ via AttributedString(markdown:),
    /// falling back to the plain string on any failure. Stray leading inline
    /// `>`/`#` marks are stripped first (defensive — the block lexer already
    /// consumes real ones).
    static func inline(_ s: String) -> AttributedString {
        var cleaned = s
        while let f = cleaned.first, f == ">" || f == "#" {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        }
        let opts = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace)
        if let attr = try? AttributedString(markdown: cleaned, options: opts) {
            return attr
        }
        return AttributedString(cleaned)
    }
}

// MARK: - Renderer

/// Renders parsed Markdown blocks in a leading-aligned column. Spacing between
/// blocks is tuned per neighbouring types so headings breathe and lists hug.
struct MLMarkdownView: View {
    let blocks: [MLBlock]

    init(_ content: String) { self.blocks = MLMarkdown.parse(content) }
    init(blocks: [MLBlock]) { self.blocks = blocks }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { idx, block in
                blockView(block)
                    .padding(.top, topSpacing(idx))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Space above a block, decided by what precedes it.
    private func topSpacing(_ idx: Int) -> CGFloat {
        guard idx > 0 else { return 0 }
        switch blocks[idx] {
        case .heading:  return 26
        case .rule:     return 22
        case .table:    return 18
        case .quote:    return 18
        default:        return 14
        }
    }

    @ViewBuilder
    private func blockView(_ block: MLBlock) -> some View {
        switch block {
        case let .heading(level, text):
            MLHeadingBlock(level: level, text: text)
        case let .paragraph(text):
            MLParagraphText(text)
        case let .bullet(items):
            MLBulletList(items: items)
        case let .numbered(items):
            MLNumberedList(items: items)
        case let .quote(body, attribution):
            // A blockquote whose attribution reads like "Romans 12:2" (a real
            // scripture reference, not a person's name or a generic dash-off)
            // renders as the shared VerseQuoteCard so scripture looks the same
            // everywhere it's quoted. An ordinary blockquote — no attribution,
            // or one that isn't a Book chapter:verse — keeps its plain callout.
            if let attribution, MLMarkdown.isScriptureReference(attribution) {
                VerseQuoteCard(verse: body, reference: attribution,
                                background: ML.surface, ink: ML.navy, gold: ML.gold)
            } else {
                MLQuoteCard(verse: body, attribution: attribution)
            }
        case let .table(header, rows):
            MLTableBlock(header: header, rows: rows)
        case .rule:
            Rectangle().fill(ML.border).frame(height: 1)
        }
    }
}

// MARK: Block renderers

/// Body paragraph — the reader's established copy style, with inline emphasis.
private struct MLParagraphText: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(MLMarkdown.inline(text))
            .font(.inter(15)).foregroundStyle(ML.bodyInk)
            .nuruLineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// `#`/`##`/`###`+ → descending Fraunces headings in navy. The `#` marks never
/// render. h4–h6 collapse onto the smallest step.
private struct MLHeadingBlock: View {
    let level: Int
    let text: String
    var body: some View {
        Text(MLMarkdown.inline(text))
            .font(.fraunces(size, .semibold)).kerning(-0.4)
            .foregroundStyle(ML.navy)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
    private var size: CGFloat {
        switch level {
        case 1:  return 22
        case 2:  return 19
        case 3:  return 17
        default: return 15.5
        }
    }
}

private struct MLBulletList: View {
    let items: [String]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(ML.navy).frame(width: 5, height: 5).offset(y: -2)
                    Text(MLMarkdown.inline(item))
                        .font(.inter(15)).foregroundStyle(ML.bodyInk)
                        .nuruLineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

private struct MLNumberedList: View {
    let items: [(Int, String)]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, pair in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(pair.0).")
                        .font(.inter(14, .bold)).foregroundStyle(ML.gold)
                        .frame(minWidth: 20, alignment: .trailing)
                    Text(MLMarkdown.inline(pair.1))
                        .font(.inter(15)).foregroundStyle(ML.bodyInk)
                        .nuruLineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

/// Blockquote → gold-ruled scripture callout on a cream surface: the verse in
/// italic Fraunces, the "— Romans 12:2" attribution in gold beneath it.
private struct MLQuoteCard: View {
    let verse: String
    let attribution: String?
    var body: some View {
        VStack(alignment: .leading, spacing: attribution == nil ? 0 : 8) {
            Text(MLMarkdown.inline(verse))
                .font(.fraunces(16.5, .regular)).italic()
                .foregroundStyle(ML.navy)
                .nuruLineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let attribution {
                Text(attribution)
                    .font(.inter(12, .semibold)).kerning(0.3)
                    .foregroundStyle(ML.gold)
            }
        }
        .padding(.vertical, Nuru.S.base)
        .padding(.horizontal, Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ML.surface)
        .overlay(alignment: .leading) { Rectangle().fill(ML.gold).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Pipe table → a real grid: bold header on a faint gold fill, hairline row
/// separators, rounded container. Columns size to content; the whole grid
/// scrolls horizontally when it would overflow the reader width.
private struct MLTableBlock: View {
    let header: [String]
    let rows: [[String]]

    private let minColumn: CGFloat = 108
    private let cellH: CGFloat = 8
    private let cellV: CGFloat = 10

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                headerRow
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    Rectangle().fill(ML.border).frame(height: 1)
                    bodyRow(row, even: idx % 2 == 0)
                }
            }
            .frame(minWidth: totalMinWidth, alignment: .leading)
            .background(ML.surface)
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(ML.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Table with \(header.count) columns and \(rows.count) rows")
    }

    private var totalMinWidth: CGFloat { minColumn * CGFloat(max(header.count, 1)) }

    private var headerRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(header.enumerated()), id: \.offset) { i, cell in
                if i > 0 { Rectangle().fill(ML.border).frame(width: 1) }
                Text(MLMarkdown.inline(cell))
                    .font(.inter(12.5, .bold)).foregroundStyle(ML.navy)
                    .frame(minWidth: minColumn, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, cellH).padding(.vertical, cellV)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(ML.gold.opacity(0.14))
    }

    private func bodyRow(_ row: [String], even: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(row.enumerated()), id: \.offset) { i, cell in
                if i > 0 { Rectangle().fill(ML.border).frame(width: 1) }
                Text(MLMarkdown.inline(cell))
                    .font(.inter(13)).foregroundStyle(ML.bodyInk)
                    .lineSpacing(4)
                    .frame(minWidth: minColumn, maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, cellH).padding(.vertical, cellV)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .background(even ? Color.clear : ML.surface.opacity(0.5))
    }
}
