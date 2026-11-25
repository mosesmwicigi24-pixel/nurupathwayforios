// Read aloud — the pure half (member suggestion, 2026-11-21: "a voice-reading
// feature that can read the written content aloud … listen to the teachings
// and articles instead of having to read everything"). ReadAloud.swift owns
// the on-device AVSpeechSynthesizer; everything decidable ahead of time — what
// is said, in what order, cut where — lives here, with no AVFoundation and no
// UIKit, so plain XCTest pins it (ListenAndNightReadingTests), the rule
// LiturgyVoiceLogic.swift set. Android's twin: feature/listen/ListenScript.kt.
//
// A reading is a list of PARAGRAPHS: the unit the player counts ("3 of 12")
// and skips by. Each one is kept well under what one utterance should carry,
// so a skip never repeats more than a few sentences.
import Foundation

struct ListenVoiceCandidate: Equatable {
    let identifier: String
    let language: String
    /// 0 = default, 1 = enhanced, 2 = premium.
    let quality: Int
}

enum ListenVoiceSelector {
    static func choose(from candidates: [ListenVoiceCandidate]) -> ListenVoiceCandidate? {
        candidates.filter { $0.language.lowercased() == "en" || $0.language.lowercased().hasPrefix("en-") }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality { return lhs.quality > rhs.quality }
                let l = LiturgyVoiceSelector.preferredLocales.firstIndex(of: lhs.language) ?? Int.max
                let r = LiturgyVoiceSelector.preferredLocales.firstIndex(of: rhs.language) ?? Int.max
                return l != r ? l < r : lhs.identifier < rhs.identifier
            }.first
    }
}

/// One block of a reading, as the screen shows it.
enum ListenPiece: Equatable {
    /// A title or a section's name — read once, with a pause after it.
    case heading(String)
    /// Authored prose: plain text or the lessons' light markdown. Blank lines
    /// separate paragraphs.
    case prose(String)
    /// A Bible passage. Its reference is read first ("Romans 8, verses 28 to
    /// 30"), then the verses WITHOUT their inline numbers — "22 Do not merely
    /// listen 23 Anyone who…" read aloud is a list of numbers.
    case scripture(text: String, reference: String?, startVerse: Int?)
}

enum ListenScript {
    /// Comfortably short for one utterance, and short enough that a skip
    /// back never repeats more than a few sentences.
    static let maxChars = 1200

    /// The paragraphs read aloud for `pieces`, in order. Empty when there is
    /// nothing to say — the screen then offers no Listen control at all.
    static func paragraphs(_ pieces: [ListenPiece], maxChars: Int = ListenScript.maxChars) -> [String] {
        var out: [String] = []
        for piece in pieces {
            let raw: [String]
            switch piece {
            case .heading(let text):
                if let s = speakable(text) { raw = [withStop(s)] } else { raw = [] }
            case .prose(let text):
                raw = prose(text)
            case let .scripture(text, reference, startVerse):
                raw = scripture(text: text, reference: reference, startVerse: startVerse)
            }
            for paragraph in raw {
                out.append(contentsOf: chunk(paragraph, maxChars: maxChars))
            }
        }
        return out
    }

    private static func prose(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        var out: [String] = []
        for para in split(normalized, by: blankLine) {
            // Lines inside one paragraph run together; a list item or a
            // heading line keeps its own pause.
            var lines: [String] = []
            for line in para.components(separatedBy: "\n") {
                let listLike = contains(listMarker, line) || contains(headingMarker, line)
                guard let s = speakable(line) else { continue }
                lines.append(listLike ? withStop(s) : s)
            }
            let joined = lines.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty { out.append(joined) }
        }
        return out
    }

    private static func scripture(text: String, reference: String?, startVerse: Int?) -> [String] {
        var out: [String] = []
        let ref = (reference ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !ref.isEmpty { out.append("\(naturalReference(ref)).") }
        let verses: [String] = ScripturePassageText.verses(in: text, startingAt: startVerse)
            .map { $0.body.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !verses.isEmpty { out.append(collapse(verses.joined(separator: " "))) }
        return out
    }

    /// A line of authored text as it should sound: markdown marks, links and
    /// tags gone, references read as words, whitespace collapsed. Nil when
    /// nothing is left (a rule, an image, an empty line).
    static func speakable(_ raw: String) -> String? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty || contains(rule, s) || contains(tableRule, s) { return nil }
        // A table row reads as its cells, one pause between each.
        if s.hasPrefix("|") {
            var row = s
            row.removeFirst()
            if row.hasSuffix("|") { row.removeLast() }
            s = row.components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: ", ")
            if let last = s.last, !".!?".contains(last) { s += "." }
        }
        s = replace(image, in: s, with: "")
        s = replace(link, in: s, with: "$1")
        s = replace(tag, in: s, with: " ")
        s = replace(headingMarker, in: s, with: "")
        s = replace(quoteMarker, in: s, with: "")
        s = replace(listMarker, in: s, with: "")
        s = replace(bold, in: s, with: "$2")
        s = replace(italicStar, in: s, with: "$1")
        s = replace(italicUnderscore, in: s, with: "$1")
        s = s.replacingOccurrences(of: "`", with: "")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        s = naturalizeReferences(s)
        let out = collapse(s)
        return out.contains(where: { $0.isLetter || $0.isNumber }) ? out : nil
    }

    /// Every Bible reference inside a run of prose, read as words: "as Romans
    /// 8:28 says" → "as Romans 8, verse 28 says". Only a real book name counts
    /// (ScriptureRefs.books), so "the 10:30 service" stays as it is.
    static func naturalizeReferences(_ text: String) -> String {
        let ns = text as NSString
        let matches = ScriptureRefs.pattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return text }
        let out = NSMutableString(string: text)
        for m in matches.reversed() {
            out.replaceCharacters(in: m.range, with: naturalReference(ns.substring(with: m.range)))
        }
        return out as String
    }

    /// "Psalm 23:1" → "Psalm 23, verse 1"; "John 15:1-4" → "John 15, verses 1
    /// to 4"; "John 3:16-4:2" → "John 3, verse 16 to chapter 4, verse 2". Not
    /// a reference → unchanged (trimmed).
    static func naturalReference(_ reference: String) -> String {
        let t = ScriptureRefs.normalize(reference)
        let ns = t as NSString
        guard let m = ScriptureRefs.pattern.firstMatch(in: t, range: NSRange(location: 0, length: ns.length)),
              m.range.location == 0, m.range.length == ns.length else {
            return reference.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        func group(_ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        }
        let book = group(1) ?? ""
        let chapter = group(2) ?? ""
        let verse = group(3) ?? ""
        if let second = group(4) {
            if let secondVerse = group(5) {
                return "\(book) \(chapter), verse \(verse) to chapter \(second), verse \(secondVerse)"
            }
            return "\(book) \(chapter), verses \(verse) to \(second)"
        }
        return "\(book) \(chapter), verse \(verse)"
    }

    /// `text` cut at sentence ends so no piece is longer than `maxChars`; a
    /// single sentence longer than that is cut at its last space.
    static func chunk(_ text: String, maxChars: Int = ListenScript.maxChars) -> [String] {
        if text.count <= maxChars { return [text] }
        let sentences = split(text, by: sentenceEnd)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        var out: [String] = []
        var current = ""
        func flush() {
            if !current.isEmpty {
                out.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
        }
        for sentence in sentences {
            var rest = sentence
            while rest.count > maxChars {
                flush()
                let cut = lastSpace(in: rest, atOrBefore: maxChars) ?? maxChars
                out.append(String(rest.prefix(cut)).trimmingCharacters(in: .whitespaces))
                rest = String(rest.dropFirst(cut)).trimmingCharacters(in: .whitespaces)
            }
            if !current.isEmpty && current.count + 1 + rest.count > maxChars { flush() }
            if !current.isEmpty { current += " " }
            current += rest
        }
        flush()
        return out
    }

    /// A stable key for one reading's words — the player tells "the same
    /// reading, still open" from "a different one" by it. FNV-1a, so it is
    /// the same on every run (Swift's own hashValue is seeded per launch).
    static func key(_ paragraphs: [String]) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for (i, p) in paragraphs.enumerated() {
            if i > 0 { hash = (hash ^ 0x01) &* 0x0000_0100_0000_01B3 }
            for byte in p.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        }
        return "\(paragraphs.count)-" + String(hash, radix: 16)
    }

    // MARK: Helpers

    private static func collapse(_ s: String) -> String {
        s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func withStop(_ s: String) -> String {
        guard let last = s.last else { return s }
        return ".!?:;\"\u{201D}\u{2019})".contains(last) ? s : s + "."
    }

    /// The index of the last space at or before `limit`, if past the start.
    private static func lastSpace(in s: String, atOrBefore limit: Int) -> Int? {
        let chars = Array(s)
        var i = min(limit, chars.count - 1)
        while i > 0 {
            if chars[i] == " " { return i }
            i -= 1
        }
        return nil
    }

    private static func contains(_ regex: NSRegularExpression, _ s: String) -> Bool {
        regex.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) != nil
    }

    private static func replace(_ regex: NSRegularExpression, in s: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length),
                                       withTemplate: template)
    }

    /// `text` split where `regex` matches (the matches themselves dropped).
    private static func split(_ text: String, by regex: NSRegularExpression) -> [String] {
        let ns = text as NSString
        var out: [String] = []
        var start = 0
        for m in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
            start = m.range.location + m.range.length
        }
        out.append(ns.substring(from: start))
        return out
    }

    private static func rx(_ pattern: String) -> NSRegularExpression {
        // Literal patterns — they cannot fail to compile.
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: pattern)
    }

    private static let blankLine = rx(#"\n\s*\n"#)
    private static let rule = rx(#"^([-*_]\s*){3,}$"#)
    private static let tableRule = rx(#"^\|?[\s:|-]*-[\s:|-]*$"#)
    private static let image = rx(#"!\[[^\]]*\]\([^)]*\)"#)
    private static let link = rx(#"\[([^\]]+)\]\([^)]*\)"#)
    private static let tag = rx(#"<[^>]+>"#)
    private static let headingMarker = rx(#"^\s*#{1,6}\s+"#)
    private static let quoteMarker = rx(#"^\s*>\s?"#)
    private static let listMarker = rx(#"^\s*(?:[-*+•]|\d{1,3}[.)])\s+"#)
    private static let bold = rx(#"(\*\*|__)(.+?)\1"#)
    private static let italicStar = rx(#"(?<![\w*])\*(?!\s)(.+?)(?<!\s)\*(?![\w*])"#)
    private static let italicUnderscore = rx(#"(?<![\w_])_(?!\s)(.+?)(?<!\s)_(?![\w_])"#)
    private static let sentenceEnd = rx(#"(?<=[.!?…]["”’)]?)\s+"#)
}

/// The listening speeds the player cycles through, slowest first. 1 is the
/// reading pace — the engine is set a little slower than its default under it
/// (`baseRate`), so "1×" reads like a person reading to you, not an
/// announcement (the liturgy voice uses 0.86).
enum ListenSpeed {
    static let storageKey = "nuru.listen.speed"
    static let steps: [Double] = [0.8, 1.0, 1.25, 1.5]
    static let baseRate: Double = 0.92

    /// The step after `speed`; an odd value moves on from its nearest step.
    static func next(after speed: Double) -> Double {
        var nearest = 1
        var best = Double.greatestFiniteMagnitude
        for (i, step) in steps.enumerated() {
            let d = abs(step - speed)
            if d < best { best = d; nearest = i }
        }
        return steps[(nearest + 1) % steps.count]
    }

    /// "0.8×", "1×", "1.25×", "1.5×".
    static func label(_ speed: Double) -> String {
        if speed == speed.rounded() { return "\(Int(speed))×" }
        return String(format: "%g", speed) + "×"
    }

    /// The utterance rate for `speed`, inside what the engine accepts.
    static func rate(for speed: Double, defaultRate: Float, minimum: Float, maximum: Float) -> Float {
        let r = defaultRate * Float(baseRate * speed)
        return min(max(r, minimum), maximum)
    }
}

/// Where the player is.
enum ListenStatus: Equatable {
    case idle, playing, paused
}

/// What a reader needs to draw its Listen controls for one reading.
struct ListenReading: Equatable {
    let words: [String]
    let key: String

    init(words: [String]) {
        self.words = words
        self.key = ListenScript.key(words)
    }

    init(pieces: [ListenPiece]) {
        self.init(words: ListenScript.paragraphs(pieces))
    }

    static let empty = ListenReading(words: [])
}

/// The Listen controls for one reading, from the player's state — pure, so the
/// rules (offered, active, the bar's words) are pinned without a device.
struct ListenControls: Equatable {
    let reading: ListenReading
    /// Listen may be shown at all: something to read, and nothing in the way
    /// (VoiceOver, the church live) — or this reading is already loaded.
    let available: Bool
    /// This reading is loaded (playing or paused) — the bar is up.
    let active: Bool
    let playing: Bool
    let index: Int
    let speed: Double

    var total: Int { reading.words.count }

    static func resolve(_ reading: ListenReading, loadedKey: String?, status: ListenStatus,
                        index: Int, offered: Bool, speed: Double) -> ListenControls {
        let active = !reading.words.isEmpty && loadedKey == reading.key && status != .idle
        return ListenControls(reading: reading,
                              available: !reading.words.isEmpty && (offered || active),
                              active: active,
                              playing: active && status == .playing,
                              index: active ? min(max(index, 0), max(reading.words.count - 1, 0)) : 0,
                              speed: speed)
    }

    /// The header button's glyph: headphones to start, pause while reading,
    /// play while paused.
    var glyph: Lucide {
        if active && playing { return .pause }
        if active { return .play }
        return .headphones
    }

    /// What the header button does, for VoiceOver and the large-content viewer.
    var label: String {
        if active && playing { return "Pause reading aloud" }
        if active { return "Resume reading aloud" }
        return "Listen — read this aloud"
    }

    /// A pill's word (the lesson's meta row).
    var pillWord: String {
        if active { return playing ? "Pause" : "Resume" }
        return "Listen"
    }

    var stateLine: String { playing ? "Reading aloud" : "Paused" }
    var placeLine: String { "\(index + 1) of \(total)" }
    var progress: Double { total > 0 ? Double(index + 1) / Double(total) : 0 }
}
