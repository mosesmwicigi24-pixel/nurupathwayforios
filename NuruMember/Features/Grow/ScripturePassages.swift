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

    /// How many verses a reference spans, when that can be read off it: a
    /// single verse is 1, "James 1:22-25" is 4. A cross-chapter span
    /// ("John 3:16-4:2") is not counted here and comes back nil.
    static func verseCount(_ ref: String) -> Int? {
        let t = normalize(ref)
        let all = NSRange(location: 0, length: (t as NSString).length)
        guard let m = pattern.firstMatch(in: t, range: all) else { return nil }
        func group(_ i: Int) -> Int? {
            let r = m.range(at: i)
            guard r.location != NSNotFound, let sr = Range(r, in: t) else { return nil }
            return Int(t[sr])
        }
        if group(5) != nil { return nil }
        guard let start = group(3) else { return nil }
        guard let end = group(4) else { return 1 }
        return end >= start ? end - start + 1 : nil
    }

    /// The verse a reference starts at ("James 1:22-25" → 22) — the number
    /// the first verse of its passage text carries.
    static func startVerse(_ ref: String) -> Int? {
        let t = normalize(ref)
        let all = NSRange(location: 0, length: (t as NSString).length)
        guard let m = pattern.firstMatch(in: t, range: all), let r = Range(m.range(at: 3), in: t) else { return nil }
        return Int(t[r])
    }

    /// Short passages open without a tap — anything under five verses.
    static func opensByDefault(_ ref: String) -> Bool {
        guard let n = verseCount(ref) else { return false }
        return n <= 4
    }

    /// "James 1:22-25" → "James 1": the prefix a single verse's own reference
    /// is built from ("James 1:23") when it is saved on its own.
    static func chapterPrefix(_ ref: String) -> String? {
        let t = normalize(ref)
        let all = NSRange(location: 0, length: (t as NSString).length)
        guard let m = pattern.firstMatch(in: t, range: all),
              let b = Range(m.range(at: 1), in: t), let c = Range(m.range(at: 2), in: t) else { return nil }
        return "\(t[b]) \(t[c])"
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

// MARK: - Passage text: one row per verse, long-press to keep one

/// YouVersion's stripped text carries its verse numbers inline ("22 Do not
/// merely listen… 23 Anyone who…"). Each verse gets its own line with the
/// number small, gold and raised, so the eye reads the words and merely
/// notices the numbers — and so a long press lands on ONE verse: save it to
/// the verse library, or copy it with its reference.
struct ScripturePassageText: View {
    let text: String
    /// The passage's own reference and translation — a long-pressed verse is
    /// saved under "Book C:V" built from these. Nil disables saving.
    var reference: String? = nil
    var version: String? = nil
    var size: CGFloat = 16
    @Environment(\.readerPalette) private var pal
    @State private var note: String?

    struct Verse: Identifiable, Equatable {
        let id: Int
        let number: String?
        let body: String
    }

    /// CANDIDATE verse numbers: a 1–3 digit token followed by a space and a
    /// word or an opening quote. Deliberately loose (a verse can begin
    /// lowercase); `verses(in:startingAt:)` keeps only the ones that run
    /// consecutively, which is what rejects "430 years" inside a verse.
    static let verseNumber: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"(?<=^|\s)(\d{1,3})(?=\s[A-Za-z“"'(\[])"#)
    }()

    /// The passage split at its verse numbers; a passage without numbers is
    /// one verse. Words before the first number (a heading) keep their place.
    ///
    /// Verse numbers run consecutively, so a candidate counts only when it is
    /// the next expected one — seeded from `startVerse` (the reference's first
    /// verse) or, failing that, the first candidate. That is what lets
    /// "24 and, after looking…" split while "was 430 years" stays prose.
    static func verses(in text: String, startingAt startVerse: Int? = nil) -> [Verse] {
        let ns = text as NSString
        let candidates = verseNumber.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var expected = startVerse ?? candidates.first.flatMap { Int(ns.substring(with: $0.range)) }
        let matches = candidates.filter { m in
            guard let n = Int(ns.substring(with: m.range)), n == expected else { return false }
            expected = n + 1
            return true
        }
        guard !matches.isEmpty else {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [Verse(id: 0, number: nil, body: t)]
        }
        var out: [Verse] = []
        let lead = ns.substring(to: matches[0].range.location).trimmingCharacters(in: .whitespacesAndNewlines)
        if !lead.isEmpty { out.append(Verse(id: 0, number: nil, body: lead)) }
        for (i, m) in matches.enumerated() {
            let from = m.range.location + m.range.length
            let to = i + 1 < matches.count ? matches[i + 1].range.location : ns.length
            let body = ns.substring(with: NSRange(location: from, length: to - from))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            out.append(Verse(id: out.count, number: ns.substring(with: m.range), body: body))
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Self.verses(in: text, startingAt: reference.flatMap(ScriptureRefs.startVerse))) { v in
                Text(attributed(v))
                    .nuruLineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        if verseReference(v) != nil {
                            Button { save(v) } label: { Label("Save to my verses", systemImage: "bookmark") }
                        }
                        Button {
                            UIPasteboard.general.string = copyText(v)
                            flash("Copied")
                        } label: { Label("Copy", systemImage: "doc.on.doc") }
                    }
            }
            if let note {
                Text(note).font(.inter(11, .semibold)).foregroundStyle(pal.goldDeep)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(pal.gold.opacity(0.12), in: Capsule())
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
    }

    private func attributed(_ v: Verse) -> AttributedString {
        var attr = AttributedString(v.body)
        attr.font = .fraunces(pal.fs(size), .regular)
        attr.foregroundColor = pal.ink
        guard let n = v.number else { return attr }
        var num = AttributedString(n + " ")
        num.font = .inter(pal.fs(10), .bold)
        num.foregroundColor = pal.gold
        num.baselineOffset = 5
        return num + attr
    }

    /// "James 1:23" for a numbered verse of "James 1:22-25"; the passage's
    /// own reference when it is a single unnumbered verse.
    private func verseReference(_ v: Verse) -> String? {
        guard let reference, ScriptureRefs.isReference(reference) else { return nil }
        if let n = v.number, let prefix = ScriptureRefs.chapterPrefix(reference) { return "\(prefix):\(n)" }
        return reference
    }

    private func copyText(_ v: Verse) -> String {
        if let r = verseReference(v) { return "\(v.body) — \(r)" }
        return v.body
    }

    private func save(_ v: Verse) {
        guard let ref = verseReference(v) else { return }
        Haptics.action()
        Task {
            do {
                try await MemberAPI.saveVerseQuick(reference: ref, version: version, text: v.body)
                Haptics.success()
                flash("Saved to your verses")
            } catch {
                Haptics.error()
                flash("Couldn't save — try again")
            }
        }
    }

    private func flash(_ text: String) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { note = text }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeOut(duration: 0.25)) { note = nil }
        }
    }
}

// MARK: - Go Deeper: one reference, opened into its passage on tap

struct ScriptureRefCard: View {
    let reference: String
    @Environment(\.readerPalette) private var pal
    @StateObject private var loader = ScripturePassageLoader()
    @State private var open: Bool

    /// Anything under five verses opens without a tap — the hungry reader
    /// should not have to ask for four lines.
    init(reference: String) {
        self.reference = reference
        _open = State(initialValue: ScriptureRefs.opensByDefault(reference))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.tap()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { open.toggle() }
                if open { Task { await loader.load(reference) } }
            } label: {
                HStack(spacing: 10) {
                    Icon(.bookOpen, size: 15, color: pal.goldDeep)
                    Text(reference).font(.inter(pal.fs(13.5), .semibold)).foregroundStyle(pal.ink)
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
                            ScripturePassageText(text: p.text, reference: reference, version: p.version, size: 16)
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
        .task { if open { await loader.load(reference) } }
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
                    Text(reference).font(.fraunces(pal.fs(20), .medium)).kerning(-0.4).foregroundStyle(pal.ink)
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
                            ScripturePassageText(text: p.text, reference: reference, version: p.version, size: 17)
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
        attr.font = .inter(pal.fs(size), .medium)
        attr.foregroundColor = pal.ink
        for m in ScriptureRefs.detect(in: text) {
            guard let ar = Range(m.nsRange, in: attr), let url = ScriptureRefs.url(for: m.reference) else { continue }
            attr[ar].link = url
            attr[ar].font = .inter(pal.fs(size), .semibold)
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
                     caption: loader.passage.map(passageCaption) ?? reference,
                     version: loader.passage?.version)
            .task { await loader.load(reference) }
    }
}
