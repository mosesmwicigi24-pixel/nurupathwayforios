// What each reader reads aloud (member suggestion, 2026-11-21) — pure, so
// ListenAndNightReadingTests pins it. Each function follows its screen's own
// order, so what a member hears is what they see, top to bottom. Android's
// twins: feature/grow/ReaderListen.kt, feature/pathway/ModuleListen.kt and
// EditorialLetter.listenPieces.
import Foundation

enum ReaderListen {
    // MARK: A plan's part (PlanSegmentView)

    /// A plan part, in PlanSegmentView's order. `passages` holds the texts
    /// fetched for bare references, keyed by ScriptureRefs.normalize. The
    /// Watch/Listen part is a film or a recording with keynotes beside it —
    /// reading the keynotes over it would talk over the speaker, so it has none.
    static func planPart(part: String?, group: [PlanSegment], dayTitle: String?,
                         passages: [String: String]) -> [ListenPiece] {
        switch part {
        case "word"?:
            var out: [ListenPiece] = []
            if let t = dayTitle?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
                out.append(.heading(t))
            }
            for seg in group {
                out.append(contentsOf: wordPieces(seg, passages: passages))
            }
            return out
        case "respond"?:
            return group.compactMap { seg in
                guard let c = nonBlank(seg.content) else { return nil }
                return .prose(c)
            }
        default:
            return []
        }
    }

    private static func wordPieces(_ seg: PlanSegment, passages: [String: String]) -> [ListenPiece] {
        switch seg.kind.lowercased() {
        case "scripture":
            let ref = nonBlank(seg.reference)
            let start = ref.flatMap { ScriptureRefs.startVerse($0) }
            var text = nonBlank(seg.content)
            if text == nil, let r = ref, ScriptureRefs.isReference(r) {
                text = passages[ScriptureRefs.normalize(r)]
            }
            if let text { return [.scripture(text: text, reference: ref, startVerse: start)] }
            if let ref { return [.heading(ref)] }
            return []
        case "reading":
            // Go Deeper names passages to open — say which, not all of them.
            guard let refs = nonBlank(seg.content) else { return [] }
            let lines = ScriptureRefs.split(refs)
            guard !lines.isEmpty else { return [] }
            return [.heading("Go deeper"), .prose(lines.joined(separator: "\n\n"))]
        default:
            guard let c = nonBlank(seg.content) else { return [] }
            return [.prose(c)]
        }
    }

    /// The bare references in a Word part whose passages have to be fetched
    /// before they can be read (the same fetch DayScriptureQuote makes, so the
    /// session cache answers it).
    static func passagesToFetch(part: String?, group: [PlanSegment]) -> [String] {
        guard part == "word" else { return [] }
        return group.compactMap { seg in
            guard seg.kind.lowercased() == "scripture", nonBlank(seg.content) == nil,
                  let r = nonBlank(seg.reference), ScriptureRefs.isReference(r) else { return nil }
            return r
        }
    }

    // MARK: Today's devotional (DevotionalView)

    /// Title, the verse, the body — then the reflection prompt, so the
    /// listener is left with the question.
    static func devotional(_ d: Devotional) -> [ListenPiece] {
        var out: [ListenPiece] = [.heading(d.title)]
        if let text = nonBlank(d.scriptureText) {
            out.append(.scripture(text: text, reference: d.scriptureRef,
                                  startVerse: d.scriptureRef.flatMap { ScriptureRefs.startVerse($0) }))
        }
        if nonBlank(d.body) != nil { out.append(.prose(d.body)) }
        if let prompt = nonBlank(d.reflectionPrompt) {
            out.append(.heading("Reflection"))
            out.append(.prose(prompt))
        }
        return out
    }

    // MARK: The Sunday Letter

    /// The editorial letter (LetterEditorialView), in the page's order: the
    /// title, the salutation, the letter, the verse, and who signed it. The
    /// pull quote repeats a line of the letter and the week's figures are a
    /// table, so neither is read.
    static func letter(_ l: PastoralLetter) -> [ListenPiece] {
        var out: [ListenPiece] = []
        if let t = nonBlank(l.title) { out.append(.heading(t)) }
        if let s = nonBlank(l.salutation) { out.append(.prose(s)) }
        for p in LetterEditorialWords.paragraphs(l) { out.append(.prose(p)) }
        if let s = LetterEditorialWords.scripture(l) {
            if let words = nonBlank(s.text) {
                out.append(.scripture(text: words, reference: s.ref, startVerse: ScriptureRefs.startVerse(s.ref)))
            } else {
                out.append(.prose("Scripture: \(s.ref)"))
            }
        }
        out.append(.prose(signature(LetterEditorialWords.signer(l))))
        return out
    }

    /// A v2 letter (LetterView's stationery): the title, the salutation, the
    /// reference card above the letter, the letter, the week's moments, and
    /// the church's signature.
    static func classicLetter(_ l: PastoralLetter) -> [ListenPiece] {
        var out: [ListenPiece] = []
        if let t = nonBlank(l.title) { out.append(.heading(t)) }
        if let s = nonBlank(l.salutation) { out.append(.prose(s)) }
        if let ref = nonBlank(l.scriptureRef) { out.append(.prose("Scripture: \(ref)")) }
        if nonBlank(l.body) != nil { out.append(.prose(l.body)) }
        let moments = l.highlights.compactMap { nonBlank($0) }
        if !moments.isEmpty {
            out.append(.heading("This week"))
            out.append(.prose(moments.joined(separator: "\n\n")))
        }
        out.append(.prose("With grace, Nuru Place."))
        return out
    }

    /// "With grace, Pastor Moses, Senior Pastor." — the name, then the role
    /// when there is one, as the signature shows them.
    static func signature(_ signer: LetterSigner) -> String {
        let parts = [nonBlank(signer.name), nonBlank(signer.role)].compactMap { $0 }
        let who = parts.isEmpty ? "Nuru Place" : parts.joined(separator: ", ")
        return "With grace, \(who)."
    }

    // MARK: A Pathway lesson (ModuleView)

    /// The lesson's own order on this phone: its title, then each section by
    /// number, with the key verse where the first section shows it — after
    /// that section's words. The reflection box, the gate and the quiz are
    /// things to do, not to hear.
    static func module(_ m: ModuleDetail) -> [ListenPiece] {
        var out: [ListenPiece] = []
        if let t = nonBlank(m.title) { out.append(.heading(t)) }
        let pages = mlPages(m).filter { nonBlank($0) != nil }
        let keyVerse = (m.keyVerses ?? []).first { nonBlank($0) != nil }
        for (i, page) in pages.enumerated() {
            // "Section 2" only when there is more than one — a one-section
            // lesson just begins.
            if pages.count > 1 { out.append(.heading("Section \(i + 1)")) }
            out.append(.prose(page))
            if i == 0, let verse = keyVerse {
                out.append(.heading("Key verse"))
                out.append(.prose(verse))
            }
        }
        if pages.isEmpty, let verse = keyVerse {
            out.append(.heading("Key verse"))
            out.append(.prose(verse))
        }
        return out
    }

    // MARK: Helpers

    private static func nonBlank(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }
}
