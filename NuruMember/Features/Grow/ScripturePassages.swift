// Scripture woven into the plans — the passages themselves, not just their
// references (owner ask, 2026-09-04). Three places read from here:
//   · Go Deeper: each reference is a card that opens into the full passage.
//   · The teaching: a reference cited inline ("(James 2:17)") becomes a gold
//     link that opens the passage in a sheet, without leaving the page.
//   · A scripture segment authored with only a reference fetches its text, so
//     the pull-quote never shows a bare "Proverbs 13:4".
// Text comes from GET /scripture (YouVersion via the server, §3.3 — the client
// never talks to the provider), held in memory for the session on top of the
// server's month-long cache. Everything degrades to the reference alone.
import SwiftUI
import UIKit

// MARK: - References: find them, split them, normalise them

enum ScriptureRefs {
    /// The 66 books plus the common alternates. Longest names go first in the
    /// pattern so "1 John 4:8" is never read as "John 4:8".
    static let books: [String] = [
        "Genesis", "Exodus", "Leviticus", "Numbers", "Deuteronomy", "Joshua", "Judges", "Ruth",
        "1 Samuel", "2 Samuel", "1 Kings", "2 Kings", "1 Chronicles", "2 Chronicles", "Ezra",
        "Nehemiah", "Esther", "Job", "Psalms", "Psalm", "Proverbs", "Ecclesiastes",
        "Song of Songs", "Song of Solomon", "Isaiah", "Jeremiah", "Lamentations", "Ezekiel",
        "Daniel", "Hosea", "Joel", "Amos", "Obadiah", "Jonah", "Micah", "Nahum", "Habakkuk",
        "Zephaniah", "Haggai", "Zechariah", "Malachi",
        "Matthew", "Mark", "Luke", "John", "Acts", "Romans", "1 Corinthians", "2 Corinthians",
        "Galatians", "Ephesians", "Philippians", "Colossians", "1 Thessalonians",
        "2 Thessalonians", "1 Timothy", "2 Timothy", "Titus", "Philemon", "Hebrews", "James",
        "1 Peter", "2 Peter", "1 John", "2 John", "3 John", "Jude", "Revelation",
    ]

    /// "Book C:V", "Book C:V-V" or "Book C:V-C:V"; en and em dashes tolerated.
    static let pattern: NSRegularExpression = {
        let names = books.sorted { $0.count > $1.count }
            .map { NSRegularExpression.escapedPattern(for: $0) }
            .joined(separator: "|")
        let body = #"\b("# + names + #")\s+(\d{1,3}):(\d{1,3})(?:\s?[-–—]\s?(\d{1,3})(?::(\d{1,3}))?)?\b"#
        // A literal pattern over a fixed list — it cannot fail to compile.
        // swiftlint:disable:next force_try
        return try! NSRegularExpression(pattern: body)
    }()

    struct Match: Equatable {
        let nsRange: NSRange
        let reference: String
    }

    /// Every reference cited in a run of prose, in order.
    static func detect(in text: String) -> [Match] {
        let all = NSRange(location: 0, length: (text as NSString).length)
        return pattern.matches(in: text, range: all).compactMap { m in
            guard let r = Range(m.range, in: text) else { return nil }
            return Match(nsRange: m.range, reference: normalize(String(text[r])))
        }
    }

    /// True when the whole string is one reference and nothing else.
    static func isReference(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let m = detect(in: t).first, detect(in: t).count == 1 else { return false }
        return m.nsRange.location == 0 && m.nsRange.length == (t as NSString).length
    }

    /// "Proverbs 13:4; James 1:22–25" → ["Proverbs 13:4", "James 1:22-25"].
    /// A comma splits only when BOTH sides name a book — "Genesis 1:1, 3"
    /// stays one line. Pieces that are not references come back untouched,
    /// so an authored note ("Read the whole chapter") still renders.
    static func split(_ refs: String) -> [String] {
        refs.components(separatedBy: CharacterSet(charactersIn: ";\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .flatMap { piece -> [String] in
                let parts = piece.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count > 1, parts.allSatisfy(isReference) { return parts }
                return [piece]
            }
            .map { isReference($0) ? normalize($0) : $0 }
    }

    /// The form /scripture accepts: "Book C:V-V" — plain hyphen, single spaces.
    static func normalize(_ ref: String) -> String {
        var s = ref.trimmingCharacters(in: .whitespacesAndNewlines)
        s = s.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "—", with: "-")
        s = s.replacingOccurrences(of: #"\s*-\s*"#, with: "-", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        return s
    }

    // The link a cited reference carries inside attributed prose. A private
    // scheme so the reader's own openURL handler claims it and nothing else.
    static let scheme = "nuru-scripture"

    static func url(for ref: String) -> URL? {
        var c = URLComponents()
        c.scheme = scheme
        c.host = "passage"
        c.queryItems = [URLQueryItem(name: "ref", value: ref)]
        return c.url
    }

    static func reference(from url: URL) -> String? {
        guard url.scheme == scheme,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return nil }
        return items.first { $0.name == "ref" }?.value
    }
}

// MARK: - Passage store (session cache over GET /scripture)

actor ScripturePassageStore {
    static let shared = ScripturePassageStore()
    private var cache: [String: ScripturePassage] = [:]

    func passage(_ ref: String) async throws -> ScripturePassage {
        let key = ScriptureRefs.normalize(ref)
        if let hit = cache[key] { return hit }
        let p = try await MemberAPI.scripture(key)
        cache[key] = p
        return p
    }
}

/// One passage's fetch state — shared by the card, the sheet and the quote.
@MainActor
final class ScripturePassageLoader: ObservableObject {
    @Published var passage: ScripturePassage?
    @Published var loading = false
    @Published var failed = false

    func load(_ ref: String) async {
        guard passage == nil, !loading else { return }
        loading = true; failed = false
        do { passage = try await ScripturePassageStore.shared.passage(ref) } catch { failed = true }
        loading = false
    }
}

private func passageCaption(_ p: ScripturePassage) -> String {
    let v = p.version.trimmingCharacters(in: .whitespaces)
    return v.isEmpty ? p.reference : "\(p.reference) · \(v)"
}

// MARK: - Passage text with gold verse numbers

/// YouVersion's stripped text carries its verse numbers inline ("22 Do not
/// merely listen… 23 Anyone who…"); set them small, gold and raised so the
/// eye reads the words and merely notices the numbers.
struct ScripturePassageText: View {
    let text: String
    var size: CGFloat = 16
    @Environment(\.readerPalette) private var pal

    private static let verseNumber: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?<=^|\s)(\d{1,3})(?=\s[A-Z“"'(\[])"#)
    }()

    var body: some View {
        Text(attributed)
            .nuruLineSpacing(7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        var attr = AttributedString(text)
        attr.font = .fraunces(size, .regular)
        attr.foregroundColor = pal.ink
        let all = NSRange(location: 0, length: (text as NSString).length)
        for m in Self.verseNumber.matches(in: text, range: all) {
            guard let ar = Range(m.range, in: attr) else { continue }
            attr[ar].font = .inter(10, .bold)
            attr[ar].foregroundColor = pal.gold
            attr[ar].baselineOffset = 5
        }
        return attr
    }
}

// MARK: - Go Deeper: one reference, opened into its passage on tap

struct ScriptureRefCard: View {
    let reference: String
    @Environment(\.readerPalette) private var pal
    @StateObject private var loader = ScripturePassageLoader()
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
                if open { Task { await loader.load(reference) } }
            } label: {
                HStack(spacing: 10) {
                    Icon(.bookOpen, size: 15, color: pal.goldDeep)
                    Text(reference).font(.inter(13.5, .semibold)).foregroundStyle(pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if loader.loading {
                        ProgressView().tint(pal.goldDeep).scaleEffect(0.8)
                    } else {
                        Icon(open ? .chevronUp : .chevronDown, size: 15, color: pal.inkDim)
                    }
                }
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(open ? "Hide \(reference)" : "Read \(reference)")

            if open {
                if let p = loader.passage {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(pal.gold).frame(width: 3)
                        VStack(alignment: .leading, spacing: 8) {
                            ScripturePassageText(text: p.text, size: 16)
                            Text(passageCaption(p).uppercased())
                                .font(.inter(10.5, .bold)).kerning(1.2).foregroundStyle(pal.inkDim)
                        }
                    }
                    .padding(.horizontal, 14).padding(.bottom, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                } else if loader.failed {
                    Button {
                        Task { await loader.load(reference) }
                    } label: {
                        Text("Couldn't load this passage — tap to try again.")
                            .font(.inter(12, .medium)).foregroundStyle(pal.inkDim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14).padding(.bottom, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(pal.gold.opacity(open ? 0.3 : 0), lineWidth: 1))
    }
}

/// The Go Deeper block: every reference as its own card; any authored note
/// between them stays a plain line.
struct DayGoDeeperPassages: View {
    let refs: String
    @Environment(\.readerPalette) private var pal

    var body: some View {
        let lines = ScriptureRefs.split(refs)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                if ScriptureRefs.isReference(line) {
                    ScriptureRefCard(reference: line)
                } else {
                    Text(line).font(.inter(13, .medium)).foregroundStyle(pal.ink)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4)
                }
            }
        }
    }
}

// MARK: - A cited reference, read in place

struct ScriptureSheetItem: Identifiable, Equatable {
    let reference: String
    var id: String { reference }
}

struct ScripturePassageSheet: View {
    let reference: String
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var pal
    @StateObject private var loader = ScripturePassageLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Icon(.bookOpen, size: 16, color: PL.gold)
                    .frame(width: 36, height: 36)
                    .background(PL.gold.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("SCRIPTURE").font(.inter(10, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                    Text(reference).font(.fraunces(20, .medium)).kerning(-0.4).foregroundStyle(pal.ink)
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: {
                    Icon(.x, size: 16, color: pal.ink)
                        .frame(width: 34, height: 34)
                        .background(pal.ink.opacity(0.06), in: Circle())
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Close")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let p = loader.passage {
                        HStack(alignment: .top, spacing: 12) {
                            RoundedRectangle(cornerRadius: 2).fill(pal.gold).frame(width: 3)
                            ScripturePassageText(text: p.text, size: 17)
                        }
                        if !p.version.isEmpty {
                            Text(p.version.uppercased())
                                .font(.inter(10.5, .bold)).kerning(1.2).foregroundStyle(pal.inkDim)
                        }
                    } else if loader.failed {
                        Text("Couldn't load this passage — check your connection and try again.")
                            .font(.inter(13)).foregroundStyle(pal.inkDim)
                            .fixedSize(horizontal: false, vertical: true)
                        Button { Task { await loader.load(reference) } } label: {
                            Text("Try again").font(.inter(13, .bold)).foregroundStyle(pal.goldDeep)
                        }
                        .buttonStyle(.pressable)
                    } else {
                        HStack { Spacer(); ProgressView().tint(pal.gold); Spacer() }
                            .padding(.vertical, 30)
                    }
                }
                .padding(.horizontal, 20).padding(.bottom, 28)
            }
        }
        .background(pal.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await loader.load(reference) }
    }
}

// MARK: - Prose with the references it cites as links

/// One paragraph of teaching; every reference it cites is a gold, underlined
/// link. The parent's `openURL` handler decides what a tap opens.
struct ScriptureLinkedText: View {
    let text: String
    var size: CGFloat = 16
    @Environment(\.readerPalette) private var pal

    var body: some View {
        Text(attributed)
            .tint(pal.goldDeep)
            .nuruLineSpacing(7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var attributed: AttributedString {
        var attr = AttributedString(text)
        attr.font = .inter(size, .medium)
        attr.foregroundColor = pal.ink
        for m in ScriptureRefs.detect(in: text) {
            guard let ar = Range(m.nsRange, in: attr), let url = ScriptureRefs.url(for: m.reference) else { continue }
            attr[ar].link = url
            attr[ar].font = .inter(size, .semibold)
            attr[ar].foregroundColor = pal.goldDeep
            attr[ar].underlineStyle = .single
        }
        return attr
    }
}

// MARK: - Scripture segment authored with only a reference

/// The day's pull-quote when the author gave a reference and no text: fetch
/// the passage, show the reference alone until it lands (or if it never does).
struct DayScriptureQuote: View {
    let reference: String
    @StateObject private var loader = ScripturePassageLoader()

    var body: some View {
        DayPullQuote(text: loader.passage?.text ?? reference,
                     caption: loader.passage.map(passageCaption) ?? reference)
            .task { await loader.load(reference) }
    }
}
