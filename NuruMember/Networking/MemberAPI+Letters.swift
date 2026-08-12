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
    let readAt: String?

    var id: String { letterId }
    var isUnread: Bool { readAt == nil }

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
