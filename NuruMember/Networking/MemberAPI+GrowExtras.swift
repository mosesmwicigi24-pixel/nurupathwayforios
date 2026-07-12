// Grow extras — plan-day reflections + sharing a journal prayer to the public
// prayer wall. Same typed-facade pattern as MemberAPI.swift: screens call these
// statics, never APIClient directly. Wire JSON is snake_case; APIClient's
// encoder/decoder convert to/from camelCase automatically.
import Foundation

/// One saved plan-day reflection row, as returned by both the POST (201) and
/// the GET (`{ "data": row-or-null }`) reflection endpoints.
struct PlanDayReflection: Decodable, Sendable {
    // id/timestamps nullable on the wire (Android made them so) — a sparse
    // row must not fail the reflection load.
    let id: String?
    let planId: String
    let dayNumber: Int
    let body: String
    let createdAt: String?
    let updatedAt: String?
}

extension MemberAPI {
    // MARK: Plan-day reflections (growth module)

    /// GET /growth/plans/{planId}/days/{dayNumber}/reflection → `{ data: row-or-null }`.
    /// Null means the member hasn't written one for this day yet.
    static func planDayReflection(planId: String, dayNumber: Int) async throws -> PlanDayReflection? {
        struct Env: Decodable { let data: PlanDayReflection? }
        return try await APIClient.shared.get(
            "growth/plans/\(planId)/days/\(dayNumber)/reflection", as: Env.self).data
    }

    /// POST /growth/plans/{planId}/days/{dayNumber}/reflection — body 1..4000
    /// chars. UPSERT semantics: resubmitting the same day updates the existing
    /// row. A fresh lowercase-UUID client_mutation_id is minted per submit so
    /// replays are idempotent server-side (§2.1/§3.6).
    @discardableResult
    static func savePlanDayReflection(planId: String, dayNumber: Int, body: String) async throws -> PlanDayReflection {
        struct Body: Encodable { let body: String; let clientMutationId: String }
        return try await APIClient.shared.post(
            "growth/plans/\(planId)/days/\(dayNumber)/reflection",
            body: Body(body: body, clientMutationId: UUID().uuidString.lowercased()),
            as: PlanDayReflection.self)
    }

    // MARK: Prayer journal → prayer wall

    /// POST /me/prayers/{id}/share-to-wall → 201 `{ post_id }` — copies one of
    /// MY private journal prayers onto the congregation's public wall.
    /// Idempotent server-side: re-sharing the same entry returns the existing
    /// wall post instead of creating a duplicate.
    @discardableResult
    static func sharePrayerToWall(_ entryId: String) async throws -> String {
        struct Res: Decodable { let postId: String }
        return try await APIClient.shared.postEmpty("me/prayers/\(entryId)/share-to-wall", as: Res.self).postId
    }
}

// MARK: - Talk it Over (the shared plan-day conversation)

/// One response in a plan day's shared "Talk it Over" thread.
struct TalkPost: Decodable, Sendable, Identifiable {
    let postId: String
    let dayNumber: Int
    let body: String
    let createdAt: String
    let userId: String
    let name: String
    let avatarUrl: String?
    let likeCount: Int
    let liked: Bool
    var id: String { postId }
}

extension MemberAPI {
    /// GET /growth/plans/{planId}/days/{n}/talk → `{ data: [TalkPost] }` oldest first.
    static func talkList(planId: String, dayNumber: Int) async throws -> [TalkPost] {
        struct Env: Decodable { let data: [TalkPost] }
        return try await APIClient.shared.get(
            "growth/plans/\(planId)/days/\(dayNumber)/talk", as: Env.self).data
    }

    /// POST …/talk — add my response (1..2000 chars). Returns the saved row.
    static func talkPost(planId: String, dayNumber: Int, body: String) async throws -> TalkPost {
        struct Body: Encodable { let body: String }
        return try await APIClient.shared.post(
            "growth/plans/\(planId)/days/\(dayNumber)/talk",
            body: Body(body: body), as: TalkPost.self)
    }

    /// POST /growth/talk/{id}/like — toggle my encouragement heart.
    static func talkLike(_ postId: String) async throws -> (liked: Bool, likeCount: Int) {
        struct Res: Decodable { let liked: Bool; let likeCount: Int }
        let r = try await APIClient.shared.postEmpty("growth/talk/\(postId)/like", as: Res.self)
        return (r.liked, r.likeCount)
    }

    /// POST …/talk/assist — AI compose help. No draft → a first-person starter
    /// from the day's questions; with a draft → the member's words polished
    /// (voice kept). Returns a SUGGESTION only; the member edits and posts.
    static func talkAssist(planId: String, dayNumber: Int, draft: String?) async throws -> String {
        struct Body: Encodable { let draft: String? }
        struct Res: Decodable { let suggestion: String }
        return try await APIClient.shared.post(
            "growth/plans/\(planId)/days/\(dayNumber)/talk/assist",
            body: Body(draft: draft), as: Res.self).suggestion
    }
}
