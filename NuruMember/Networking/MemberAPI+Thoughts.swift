// Selah — My Thoughts (/me/thoughts) + AI Prayer Points (/me/prayer/*).
// Reads go straight to the REST endpoints; writes go through the offline
// mutation queue (SyncCoordinator, domain "member_thoughts") exactly like the
// prayer journal — see ThoughtsViewModel. The AI routes are consent-gated
// server-side (CONSENT_REQUIRED) — callers surface that the same way Profile's
// "Nuru Intelligence" toggle does.
import Foundation

extension MemberAPI {
    /// GET /me/thoughts — newest first.
    static func thoughts() async throws -> [Thought] {
        try await APIClient.shared.get("me/thoughts", as: Envelope<Thought>.self).data
    }

    /// GET /me/thoughts/{id}
    static func thought(_ id: String) async throws -> Thought {
        try await APIClient.shared.get("me/thoughts/\(id)", as: Thought.self)
    }

    /// POST /me/prayer/assist — a short draft in the member's own voice, from
    /// optional seed points. Nothing is persisted server-side; the member
    /// edits/keeps it themselves (Gemini-in-Gmail idiom, docs: prayer-room-arc).
    static func prayerAssist(seed: String?) async throws -> String {
        struct Body: Encodable { let seed: String? }
        struct Res: Decodable { let suggestion: String }
        let trimmed = seed?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await APIClient.shared.post(
            "me/prayer/assist", body: Body(seed: (trimmed?.isEmpty ?? true) ? nil : trimmed), as: Res.self
        ).suggestion
    }

    /// POST /me/prayer/points — the corpus generator: distills concise prayer
    /// points from the member's own Selah thoughts + private prayers + their
    /// own published prayer-wall posts. [] when there's nothing to draw from yet.
    static func prayerPoints() async throws -> [String] {
        struct Res: Decodable { let points: [String] }
        return try await APIClient.shared.postEmpty("me/prayer/points", as: Res.self).points
    }
}
