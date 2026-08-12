// Liturgy voice — PURE logic only (no AVFoundation, no UIKit): how the hour's
// liturgy becomes something worth listening to. Kept separate from
// LiturgyVoice.swift (the AVSpeechSynthesizer-backed engine) so every rule
// here is testable on any platform, with no simulator/device audio stack.
//   • LiturgySpeechText  — HomeLiturgy's fields → an ordered list of spoken
//     segments, and the one genuinely fiddly bit: turning "Psalm 23:1" into
//     "Psalm twenty-three, verse one" rather than letting the synthesizer
//     guess at bare digits and a colon.
//   • LiturgyVoiceState  — a small TOTAL state machine (idle/playing/paused)
//     the engine drives; pure so its transitions are provable without ever
//     touching AVSpeechSynthesizer.
//   • LiturgyVoiceSelector — picks the best installed English voice from a
//     device-supplied candidate list; pure so the fallback ladder (enhanced →
//     default quality → nil, Commonwealth English before US) is provable
//     without depending on whatever voices happen to be on THIS machine.
//   • LiturgyAudioSource — PHASE 2 SEAM. `.recorded(URL)` is unused today
//     (see LiturgyVoice.swift/LiturgyCards.swift), but `preferred(...)` is
//     the one function that will need to change when the backend adds a
//     pastor-recorded liturgy URL — everything downstream already speaks
//     this enum.
import Foundation

// MARK: - Spoken text shaping

struct LiturgySpeechSegment: Equatable {
    let text: String
    /// Pause AFTER this segment, before the next one starts — a beat for
    /// "line" → "charge" → the verse quote, then no trailing pause after the
    /// final piece (nothing to wait for).
    let pauseAfter: TimeInterval
}

enum LiturgySpeechText {
    /// The order mirrors exactly what the card SHOWS (HomeLiturgyCard.body):
    /// the hour's line, then the charge (if any), then either the companion
    /// verse (its text, then its reference spoken naturally) or — when there
    /// is no companion verse — the bare scripture reference alone. A member
    /// hearing this should never learn LESS than what they can already read.
    static func segments(line: String, charge: String?, verseLineText: String?,
                          verseLineReference: String?, scriptureRef: String?) -> [LiturgySpeechSegment] {
        var out: [LiturgySpeechSegment] = []
        let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanLine.isEmpty { out.append(.init(text: cleanLine, pauseAfter: 0.55)) }

        let cleanCharge = (charge ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanCharge.isEmpty { out.append(.init(text: cleanCharge, pauseAfter: 0.5)) }

        let cleanVerseText = (verseLineText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanVerseText.isEmpty {
            out.append(.init(text: cleanVerseText, pauseAfter: 0.4))
            let ref = spokenReference(verseLineReference ?? "")
            if !ref.isEmpty { out.append(.init(text: ref, pauseAfter: 0)) }
        } else {
            let cleanRef = (scriptureRef ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanRef.isEmpty {
                let ref = spokenReference(cleanRef)
                if !ref.isEmpty { out.append(.init(text: ref, pauseAfter: 0)) }
            }
        }
        return out
    }

    /// "Psalm 23:1" → "Psalm twenty-three, verse one"
    /// "John 15:1-4" → "John fifteen, verses one to four"
    /// "1 Corinthians 13:4-7" → "First Corinthians thirteen, verses four to seven"
    /// "Genesis 1" (chapter only, no colon) → "Genesis one"
    ///
    /// TOTAL and safe: a reference that doesn't match the expected
    /// "book chapter[:verse[-verse]]" shape is handed back lightly trimmed
    /// rather than thrown away — the voice always says SOMETHING for a real
    /// reference string instead of going silent on an odd one.
    static func spokenReference(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // The LAST space splits "<book…> <locator>" — works for multi-word
        // books too ("Song of Solomon 2:1" → book "Song of Solomon").
        guard let lastSpace = trimmed.range(of: " ", options: .backwards) else {
            return trimmed // no locator to convert — hand it back as-is
        }
        let bookRaw = String(trimmed[trimmed.startIndex..<lastSpace.lowerBound])
        let locator = String(trimmed[lastSpace.upperBound...])
        let book = spokenBookName(bookRaw)

        let parts = locator.split(separator: ":", maxSplits: 1)
        guard let chapterPart = parts.first, let chapter = Int(chapterPart) else {
            return trimmed // not "chapter" or "chapter:verse(s)" — hand back untouched
        }
        let chapterWords = spellOut(chapter)

        guard parts.count > 1 else { return "\(book) \(chapterWords)" } // chapter-only

        let verses = String(parts[1])
        if let dash = verses.range(of: "-") {
            let startStr = String(verses[verses.startIndex..<dash.lowerBound])
            let endStr = String(verses[dash.upperBound...])
            if let start = Int(startStr), let end = Int(endStr) {
                return "\(book) \(chapterWords), verses \(spellOut(start)) to \(spellOut(end))"
            }
            // A rare cross-chapter range ("26:69-27:26") — endStr is itself
            // "chapter:verse". Best-effort rather than silence.
            if let start = Int(startStr) {
                return "\(book) \(chapterWords) verse \(spellOut(start)), through \(spokenReference("\(bookRaw) \(endStr)"))"
            }
            return trimmed
        }
        guard let verse = Int(verses) else { return "\(book) \(chapterWords)" }
        return "\(book) \(chapterWords), verse \(spellOut(verse))"
    }

    /// "1 Corinthians" → "First Corinthians", "2 Timothy" → "Second Timothy",
    /// "3 John" → "Third John" — the only numeral-prefixed book names in
    /// Scripture. Everything else passes through untouched.
    static func spokenBookName(_ book: String) -> String {
        let trimmed = book.trimmingCharacters(in: .whitespaces)
        let ordinals: [(digit: String, word: String)] = [("1", "First"), ("2", "Second"), ("3", "Third")]
        for o in ordinals where trimmed.hasPrefix("\(o.digit) ") {
            return o.word + trimmed.dropFirst(o.digit.count)
        }
        return trimmed
    }

    private static func spellOut(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .spellOut
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? String(n)
    }
}

// MARK: - Playback state machine (pure — the engine is the only AVFoundation caller)

/// What the member (or the system, e.g. a phone call ending) is asking for.
enum LiturgyVoiceTransition { case start, pause, resume, stop, finish }

enum LiturgyVoiceState: Equatable {
    case idle, playing, paused

    /// TOTAL: every (state, transition) pair returns a defined next state,
    /// so the engine can never land somewhere undefined.
    ///   - `.start` only takes effect from `.idle`; already-active states
    ///     hold (a redundant tap on an already-speaking card is a no-op).
    ///   - `.pause` only takes effect from `.playing`.
    ///   - `.resume` only takes effect from `.paused`.
    ///   - `.stop` / `.finish` always land on `.idle`, from any state.
    func applying(_ transition: LiturgyVoiceTransition) -> LiturgyVoiceState {
        switch (self, transition) {
        case (.idle, .start): return .playing
        case (.playing, .pause): return .paused
        case (.paused, .resume): return .playing
        case (_, .stop), (_, .finish): return .idle
        default: return self
        }
    }
}

// MARK: - Voice selection (pure — AVSpeechSynthesisVoice.speechVoices() maps to this)

/// Mirrors the fields of `AVSpeechSynthesisVoice` the selector cares about,
/// without depending on the real (not constructible in a test target) class.
struct LiturgyVoiceCandidate: Equatable {
    let identifier: String
    let language: String   // BCP-47, e.g. "en-GB"
    let isEnhancedOrPremium: Bool
}

enum LiturgyVoiceSelector {
    /// Locales tried in order, most-preferred first. The congregation is
    /// Kenyan-English-speaking; Apple ships no en-KE voice as of this build,
    /// so we reach for the nearest Commonwealth English accents ahead of
    /// en-US rather than defaulting to American English by omission.
    static let preferredLocales = ["en-GB", "en-NG", "en-ZA", "en-AU", "en-IE", "en-US"]

    /// Choose the voice AVSpeechUtterance should use, or nil to leave the
    /// system's own default voice in place (still English on virtually every
    /// device, just not hand-picked).
    ///
    /// Priority: audio QUALITY first — any Enhanced/Premium English voice
    /// beats every default-quality English voice regardless of locale, since
    /// naturalness is the whole point of "a voice worth listening to." Locale
    /// preference is the tie-breaker WITHIN a quality tier. A device with no
    /// English voice at all returns nil rather than picking something in the
    /// wrong language.
    static func choose(from candidates: [LiturgyVoiceCandidate]) -> LiturgyVoiceCandidate? {
        let english = candidates.filter { $0.language.hasPrefix("en") }
        guard !english.isEmpty else { return nil }
        let enhanced = english.filter(\.isEnhancedOrPremium)
        let pool = enhanced.isEmpty ? english : enhanced
        return pool.sorted { localeRank($0.language) < localeRank($1.language) }.first
    }

    private static func localeRank(_ language: String) -> Int {
        preferredLocales.firstIndex { language.hasPrefix($0) } ?? preferredLocales.count
    }
}

// MARK: - Audio source (today: synthesis only — PHASE 2 seam for a recording)

enum LiturgyAudioSource: Equatable {
    case synthesized([LiturgySpeechSegment])
    /// PHASE 2, not built: a pastor-recorded reading of the liturgy. The
    /// engine (LiturgyVoice.swift) already knows how to play this — the only
    /// missing piece is a URL on the wire (HomeLiturgy has none yet).
    case recorded(URL)

    /// Recorded audio is ALWAYS preferred over synthesis when present — the
    /// whole point of leaving this seam. Today every call site passes
    /// `recordedUrlString: nil` (no such field exists on HomeLiturgy yet), so
    /// this always resolves to `.synthesized`; the day the backend adds one,
    /// the call site changes by ONE argument and the engine needs no changes.
    static func preferred(recordedUrlString: String?, segments: [LiturgySpeechSegment]) -> LiturgyAudioSource {
        let trimmed = (recordedUrlString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, let url = URL(string: trimmed) {
            return .recorded(url)
        }
        return .synthesized(segments)
    }
}
