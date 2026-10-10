// Sunday Letters + AI-personalization consent (intelligence layer, Phase 1).
//   • GET  me/letters            — my letters, newest first
//   • GET  me/letters/latest     — { letter: ... | null }
//   • POST me/letters/{id}/read  — mark read (idempotent)
//   • GET  me/ai / POST me/ai/consent — the personalization covenant switch
//
// v2 (feat/sunday-letter-v2, matches packages/backend/src/modules/intelligence/
// letters.ts + prompts.ts on the same branch): the letter widened from
// {body, scripture_ref} to a fully composed personal letter — title (also the
// push text), a real-name salutation, a fixed-vocabulary theme the client maps
// to a bundled illustration (LetterTheme.resolve, LetterIllustrations.swift),
// and `highlights`/`next_step`/`share_line`. The backend's rowFromDb() already
// null-defaults title/salutation/theme/image_key before they hit the wire, but
// every field here is STILL decoded defensively — a letter written before this
// migration (or a future wire hiccup) must never render broken.
//
// v3 (pathway#512, the editorial letter — owner, 2026-10-07): additive and
// derived — `issue_no`, `reading_minutes`, `paragraphs`, `scripture` (the verse
// in full), `photo`, `figures` (0–3 of the week's true numbers), `signed_by`
// and `pdf_url` (a one-page A4). Every one decodes as OPTIONAL: a v2 server's
// letter has none of them, and renders exactly as before (LetterView).
import Foundation

/// One weekly pastoral letter, composed from the member's actual week.
struct PastoralLetter: Codable, Sendable, Identifiable {
    let letterId: String
    let weekOf: String
    /// A short line worth opening — also the push notification text. Legacy
    /// letters (pre-v2) never had one; defaults to a plain, honest title.
    let title: String
    /// Warm opening using the member's real first name, e.g. "Dear Grace,".
    let salutation: String
    /// Raw theme string from the server — resolve via `LetterTheme.resolve(_:)`
    /// before rendering; never assume it's one of the known cases.
    let theme: String
    /// Which bundled illustration to render — today always equals `theme`,
    /// but kept distinct because the backend may rotate variants later.
    let imageKey: String
    let body: String
    let scriptureRef: String?
    /// 2-3 true, concrete observations from the member's real week. Empty for
    /// legacy letters and for genuinely quiet weeks alike — never invented.
    let highlights: [String]
    /// One deterministic, server-computed next action (never AI-invented).
    /// Nil when there's nothing left to point at — the CTA section is omitted.
    let nextStep: LetterNextStep?
    /// One shareable line drawn from the letter's own words. Nil omits the
    /// share affordance entirely rather than falling back to sharing the body.
    let shareLine: String?
    let createdAt: String
    var readAt: String?

    // MARK: v3 — the editorial letter (all optional; nil on a v2 server)

    /// The member's own issue number — "No. 6".
    var issueNo: Int? = nil
    /// The letter's reading time, in whole minutes.
    var readingMinutes: Int? = nil
    /// The body as the paragraphs it is laid out in.
    var paragraphs: [String]? = nil
    /// The week's verse in full; `text` and `version` may be absent.
    var scripture: LetterScripture? = nil
    /// The week's photograph — a curated library image, with its words.
    var photo: LetterPhoto? = nil
    /// Up to three of the week's true figures ("10/10", "lessons finished").
    var figures: [LetterFigure] = []
    /// Who signs the letter — "Pastor Moses", "Nuru Place".
    var signedBy: LetterSigner? = nil
    /// The letter as a one-page A4, a path from the server's root
    /// ("/v1/me/letters/{id}/pdf") — resolved against the API's origin.
    var pdfUrl: String? = nil

    var id: String { letterId }
    var isUnread: Bool { readAt == nil }
    /// A v3 letter, laid out as board A (the editorial letter). A v2 letter
    /// — no paragraphs on the wire — keeps today's stationery exactly.
    var isEditorial: Bool { !(paragraphs ?? []).isEmpty }

    /// The same letter, read — every field carried over (v2 and v3 alike),
    /// only `readAt` set. Home's knock clears with it.
    func markedRead(at iso: String) -> PastoralLetter {
        var copy = self
        copy.readAt = iso
        return copy
    }

    /// Defaults matching the backend's own (letters.ts `DEFAULT_LETTER_*`) —
    /// kept here too so the client never depends solely on the server having
    /// applied them (belt-and-braces per the reliability doctrine: never trust
    /// the wire fully).
    static let defaultTitle = "Your Sunday Letter"
    static let defaultSalutation = "Dear friend,"
}

/// A single, deterministic next step — never AI-invented, computed server-side
/// from the member's real progress. `route`/`params` mirror the SAME deep-link
/// vocabulary `NextAction` already uses (see HomeView's `heroCard`): "module"
/// with a `moduleId` opens that exact lesson; anything else (today: "pathway")
/// lands generically on the Pathway tab.
struct LetterNextStep: Codable, Sendable, Hashable {
    let label: String
    let route: String
    let params: LetterNextStepParams?
}

struct LetterNextStepParams: Codable, Sendable, Hashable {
    let moduleId: String?
}

/// The week's verse in full (v3). `text` is nil when the server has no
/// stored text for the reference — the card then shows the reference alone.
struct LetterScripture: Codable, Sendable, Hashable {
    let ref: String
    let text: String?
    let version: String?
}

/// The week's photograph (v3): a curated library image and its words.
struct LetterPhoto: Codable, Sendable, Hashable {
    let id: String?
    let url: String
    let alt: String?
    let caption: String?
}

/// One of the week's true figures (v3): "10/10" · "lessons finished".
struct LetterFigure: Codable, Sendable, Hashable {
    let value: String
    let label: String
}

/// A figure as it comes off the wire — each field on its own, so one odd
/// figure never costs the others.
private struct RawFigure: Decodable {
    let value: String?
    let label: String?
    private enum CodingKeys: String, CodingKey { case value, label }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        value = try? c.decodeIfPresent(String.self, forKey: .value)
        label = try? c.decodeIfPresent(String.self, forKey: .label)
    }
}

/// Who signs the letter (v3): "Pastor Moses" · "Nuru Place".
struct LetterSigner: Codable, Sendable, Hashable {
    let name: String
    let role: String?
}

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the mark-read patch in HomeView.
extension PastoralLetter {
    /// Trims and treats an empty string the same as a missing/null field —
    /// a letter's title/salutation must never render as a blank line.
    private static func nonEmpty(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        letterId = try c.decode(String.self, forKey: .letterId)
        weekOf = (try? c.decodeIfPresent(String.self, forKey: .weekOf)) ?? ""
        title = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .title)) ?? Self.defaultTitle
        salutation = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .salutation)) ?? Self.defaultSalutation
        let rawTheme = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .theme))
        theme = rawTheme ?? LetterTheme.fallback.rawValue
        imageKey = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .imageKey)) ?? theme
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        scriptureRef = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .scriptureRef))
        highlights = ((try? c.decodeIfPresent([String].self, forKey: .highlights)) ?? [])
            .compactMap(Self.nonEmpty)
        nextStep = try? c.decodeIfPresent(LetterNextStep.self, forKey: .nextStep)
        shareLine = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .shareLine))
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        readAt = try? c.decodeIfPresent(String.self, forKey: .readAt)
        // v3 — each optional and tolerant on its own: one odd field never
        // costs the letter (or the rest of the editorial layout).
        issueNo = (try? c.decodeIfPresent(Int.self, forKey: .issueNo)).flatMap { $0 > 0 ? $0 : nil }
        readingMinutes = (try? c.decodeIfPresent(Int.self, forKey: .readingMinutes)).flatMap { $0 > 0 ? $0 : nil }
        let paras = ((try? c.decodeIfPresent([String].self, forKey: .paragraphs)) ?? nil)?.compactMap(Self.nonEmpty)
        paragraphs = (paras?.isEmpty ?? true) ? nil : paras
        if let s = try? c.decodeIfPresent(LetterScripture.self, forKey: .scripture), let ref = Self.nonEmpty(s.ref) {
            scripture = LetterScripture(ref: ref, text: Self.nonEmpty(s.text), version: Self.nonEmpty(s.version))
        }
        if let p = try? c.decodeIfPresent(LetterPhoto.self, forKey: .photo), let url = Self.nonEmpty(p.url) {
            photo = LetterPhoto(id: p.id, url: url, alt: Self.nonEmpty(p.alt), caption: Self.nonEmpty(p.caption))
        }
        figures = ((try? c.decodeIfPresent([RawFigure].self, forKey: .figures)) ?? nil ?? [])
            .compactMap { f in Self.nonEmpty(f.value).map { LetterFigure(value: $0, label: Self.nonEmpty(f.label) ?? "") } }
        if let s = try? c.decodeIfPresent(LetterSigner.self, forKey: .signedBy), let name = Self.nonEmpty(s.name) {
            signedBy = LetterSigner(name: name, role: Self.nonEmpty(s.role))
        }
        pdfUrl = Self.nonEmpty(try? c.decodeIfPresent(String.self, forKey: .pdfUrl))
    }

    /// Convenience memberwise init — used by HomeView's optimistic mark-read
    /// patch, and by tests, without threading every field through JSON.
    init(letterId: String, weekOf: String, title: String = PastoralLetter.defaultTitle,
         salutation: String = PastoralLetter.defaultSalutation, theme: String = LetterTheme.fallback.rawValue,
         imageKey: String? = nil, body: String, scriptureRef: String?, highlights: [String] = [],
         nextStep: LetterNextStep? = nil, shareLine: String? = nil, createdAt: String, readAt: String?) {
        self.letterId = letterId
        self.weekOf = weekOf
        self.title = title
        self.salutation = salutation
        self.theme = theme
        self.imageKey = imageKey ?? theme
        self.body = body
        self.scriptureRef = scriptureRef
        self.highlights = highlights
        self.nextStep = nextStep
        self.shareLine = shareLine
        self.createdAt = createdAt
        self.readAt = readAt
    }
}

extension MemberAPI {
    static func letters() async throws -> [PastoralLetter] {
        try await APIClient.shared.get("me/letters", as: Envelope<PastoralLetter>.self).data
    }

    static func latestLetter() async throws -> PastoralLetter? {
        struct Res: Codable { let letter: PastoralLetter? }
        return try await APIClient.shared.get("me/letters/latest", as: Res.self).letter
    }

    @discardableResult
    static func markLetterRead(_ letterId: String) async throws -> String {
        struct Res: Codable { let letterId: String; let readAt: String }
        struct Empty: Encodable {}
        return try await APIClient.shared.post("me/letters/\(letterId)/read", body: Empty(), as: Res.self).readAt
    }

    static func aiConsent() async throws -> Bool {
        struct Res: Codable { let optOut: Bool }
        return try await APIClient.shared.get("me/ai", as: Res.self).optOut
    }

    @discardableResult
    static func setAiConsent(optOut: Bool) async throws -> Bool {
        struct Body: Encodable { let optOut: Bool }
        struct Res: Codable { let optOut: Bool }
        return try await APIClient.shared.post("me/ai/consent", body: Body(optOut: optOut), as: Res.self).optOut
    }
}
