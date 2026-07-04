// Discipleship Hub endpoint — the single read-aggregation that powers the
// student-facing Hub (discipler, progression, scores, reflections, meeting
// notes). Pure GET, no side effects: the DM is created lazily on the "Message"
// tap via the existing POST /chat/dms path, never here. Kept in its own file per
// the coordinated-dev split (mirrors +Progression.swift).
import Foundation

extension MemberAPI {
    /// GET /me/discipleship → { data: Discipleship } — everything the member's
    /// Discipleship Hub needs in one call. `data` is a single object (not a list),
    /// so it uses a bespoke object envelope rather than the collection `Envelope<T>`.
    static func discipleship() async throws -> Discipleship {
        struct Env: Decodable { let data: Discipleship }
        return try await APIClient.shared.get("me/discipleship", as: Env.self).data
    }

    // MARK: Discipler side (Instructor+ — the server scopes to the caller's flock)

    /// GET /disciples → { data: [rows], summary } — the leader's roster, with
    /// needs-action rows pre-sorted first by the server (never re-sorted here).
    static func disciples() async throws -> DiscipleRoster {
        try await APIClient.shared.get("disciples", as: DiscipleRoster.self)
    }

    /// GET /disciples/{id} → { data: DiscipleDossier } — one student's full
    /// dossier (member, progression, scores, engagement, reflections, activity).
    static func disciple(_ id: String) async throws -> DiscipleDossier {
        struct Env: Decodable { let data: DiscipleDossier }
        return try await APIClient.shared.get("disciples/\(id)", as: Env.self).data
    }
}
