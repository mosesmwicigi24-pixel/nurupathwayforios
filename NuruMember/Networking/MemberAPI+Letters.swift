// Sunday Letters + AI-personalization consent (intelligence layer, Phase 1).
//   • GET  me/letters            — my letters, newest first
//   • GET  me/letters/latest     — { letter: ... | null }
//   • POST me/letters/{id}/read  — mark read (idempotent)
//   • GET  me/ai / POST me/ai/consent — the personalization covenant switch
import Foundation

/// One weekly pastoral letter, composed from the member's actual week.
struct PastoralLetter: Codable, Sendable, Identifiable {
    let letterId: String
    let weekOf: String
    let body: String
    let scriptureRef: String?
    let createdAt: String
    let readAt: String?

    var id: String { letterId }
    var isUnread: Bool { readAt == nil }
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
