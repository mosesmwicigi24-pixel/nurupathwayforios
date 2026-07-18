// Chat Redesign C3b — the two private-relationship threads and the space
// join-request flow. Wire shapes verified against the live backend modules
// (pathway packages/backend/src/modules/{chat,pastoral}):
//   GET  /chat/discipler/conversation → { conversation_id }            (404 no_discipler)
//   POST /chat/pastoral               → { conversation_id, pastor_user_id, source }
//   GET  /chat/pastoral/inbox         → { data: [rows] }               (403 password_required)
//   POST /chat/spaces/{id}/join-requests → { status, request_id? }
import Foundation

/// POST /chat/pastoral — my one private pastoral thread, created lazily.
/// `source` says how the pastor was resolved: "assigned" (explicit row),
/// "congregation_default", or "fallback_superadmin".
struct PastoralThread: Codable, Sendable {
    let conversationId: String
    let pastorUserId: String
    let source: String?
    private enum CodingKeys: String, CodingKey { case conversationId, pastorUserId, source }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        pastorUserId = (try? c.decodeIfPresent(String.self, forKey: .pastorUserId)) ?? ""
        source = try? c.decodeIfPresent(String.self, forKey: .source)
    }
}

/// One row of the pastor-facing GET /chat/pastoral/inbox.
struct PastoralInboxRow: Codable, Sendable, Identifiable {
    let conversationId: String
    let memberUserId: String
    let memberName: String
    let memberAvatarUrl: String?
    let lastBody: String?
    let lastAt: String?
    let updatedAt: String?
    /// Non-nil for a member whose thread was client-side "Archived" (§ Talk
    /// with My Pastor ⋮ menu) — the pastor's inbox still lists it (no-data-loss,
    /// past + present per PastoralService.inbox), just distinguishable here.
    let archivedAt: String?
    var id: String { conversationId }
    private enum CodingKeys: String, CodingKey {
        case conversationId, memberUserId, memberName, memberAvatarUrl, lastBody, lastAt, updatedAt, archivedAt
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        memberUserId = (try? c.decodeIfPresent(String.self, forKey: .memberUserId)) ?? ""
        memberName = (try? c.decodeIfPresent(String.self, forKey: .memberName)) ?? "Member"
        memberAvatarUrl = try? c.decodeIfPresent(String.self, forKey: .memberAvatarUrl)
        lastBody = try? c.decodeIfPresent(String.self, forKey: .lastBody)
        lastAt = try? c.decodeIfPresent(String.self, forKey: .lastAt)
        updatedAt = try? c.decodeIfPresent(String.self, forKey: .updatedAt)
        archivedAt = try? c.decodeIfPresent(String.self, forKey: .archivedAt)
    }
}

/// POST /chat/spaces/{id}/join-requests — the reviewed-join path. "pending"
/// means a leader was notified and will accept/decline; "already_member" is the
/// server telling a stale client it can just open the space.
struct SpaceJoinRequestResult: Codable, Sendable {
    let status: String            // "pending" | "already_member"
    let requestId: String?
    private enum CodingKeys: String, CodingKey { case status, requestId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        requestId = try? c.decodeIfPresent(String.self, forKey: .requestId)
    }
}

extension MemberAPI {
    /// GET /chat/discipler/conversation — resolve (lazily creating) my DISCIPLER
    /// thread with my CURRENT assignment. Throws 404 (details.no_discipler) when
    /// nobody is assigned — the tab's empty state, not an error.
    static func disciplerConversation() async throws -> String {
        struct Res: Decodable { let conversationId: String }
        return try await APIClient.shared.get("chat/discipler/conversation", as: Res.self).conversationId
    }

    /// POST /chat/pastoral — create-or-open MY pastoral thread. No step-up:
    /// this is the member's own conversation, not oversight into anyone else's.
    static func openPastoralThread() async throws -> PastoralThread {
        try await APIClient.shared.postEmpty("chat/pastoral", as: PastoralThread.self)
    }

    /// GET /chat/pastoral/inbox — pastor/SuperAdmin side. Server-gated behind
    /// the same fresh-password step-up as Broadcast (403 password_required).
    static func pastoralInbox() async throws -> [PastoralInboxRow] {
        struct Res: Decodable { let data: [PastoralInboxRow] }
        return try await APIClient.shared.get("chat/pastoral/inbox", as: Res.self).data
    }

    /// POST /chat/spaces/{id}/join-requests — file a reviewed join request for a
    /// space the immediate `/join` path refused.
    static func requestSpaceJoin(_ conversationId: String, message: String? = nil) async throws -> SpaceJoinRequestResult {
        struct Body: Encodable { let message: String? }
        return try await APIClient.shared.post("chat/spaces/\(conversationId)/join-requests",
            body: Body(message: message), as: SpaceJoinRequestResult.self)
    }
}
