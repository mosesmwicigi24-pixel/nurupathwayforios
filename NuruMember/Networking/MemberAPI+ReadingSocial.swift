// Reading & Social R1 — "Read with a Friend" endpoints (spec §3/§6). Wire
// shapes mirror packages/backend/src/modules/reading-social/{groups,invites}.ts
// exactly; see Models/ReadingSocial.swift for the tolerant DTOs. The public
// https://pathway.nuruplace.org/join/{token} landing page is served
// server-side (publicPage.ts) — the app never renders it; it only mints the
// token and hands the URL to the system share sheet.
import Foundation

extension MemberAPI {
    // MARK: Groups

    /// POST /reading/groups — create-or-get MY group for a plan. Omitting
    /// `memberUserIds` mints a solo group ready for an open share-link;
    /// passing ids sends targeted invites to already-accepted connections
    /// (403 CONSENT_REQUIRED otherwise — surfaced as APIError).
    @discardableResult
    static func createOrGetReadingGroup(planId: String, memberUserIds: [String]? = nil, name: String? = nil) async throws -> ReadingGroupRow {
        struct Body: Encodable { let planId: String; let memberUserIds: [String]?; let name: String? }
        return try await APIClient.shared.post("reading/groups",
            body: Body(planId: planId, memberUserIds: memberUserIds, name: name), as: ReadingGroupRow.self)
    }

    /// GET /reading/groups — my active + archived shared groups, each with
    /// its plan summary and every active member's progress.
    static func myReadingGroups() async throws -> [ReadingGroupRow] {
        try await APIClient.shared.get("reading/groups", as: Envelope<ReadingGroupRow>.self).data
    }

    /// GET /reading/groups/{id} — full detail; 403 FORBIDDEN_SCOPE for a non-member.
    static func readingGroup(_ id: String) async throws -> ReadingGroupRow {
        try await APIClient.shared.get("reading/groups/\(id)", as: ReadingGroupRow.self)
    }

    /// POST /reading/groups/{id}/archive — creator-only; ends the shared plan
    /// (membership/history kept).
    static func archiveReadingGroup(_ id: String) async throws {
        _ = try await APIClient.shared.postEmpty("reading/groups/\(id)/archive", as: EmptyResponse.self)
    }

    /// POST /reading/groups/{id}/leave — any active member; idempotent.
    static func leaveReadingGroup(_ id: String) async throws {
        _ = try await APIClient.shared.postEmpty("reading/groups/\(id)/leave", as: EmptyResponse.self)
    }

    // MARK: Invites

    /// POST /reading/groups/{id}/invites — `userId` set mints a targeted
    /// invite (requires an accepted connection); omitted mints a fresh
    /// open-link invite (no target, no expiry) for the native share sheet.
    @discardableResult
    static func createReadingInvite(groupId: String, userId: String? = nil, message: String? = nil) async throws -> ReadingInviteRow {
        struct Body: Encodable { let userId: String?; let message: String?; let clientMutationId: String }
        return try await APIClient.shared.post("reading/groups/\(groupId)/invites",
            body: Body(userId: userId, message: message, clientMutationId: UUID().uuidString), as: ReadingInviteRow.self)
    }

    /// GET /reading/groups/{id}/invites — pending + past invites for a group.
    static func listReadingInvites(groupId: String) async throws -> [ReadingInviteRow] {
        try await APIClient.shared.get("reading/groups/\(groupId)/invites", as: Envelope<ReadingInviteRow>.self).data
    }

    /// POST /reading/groups/{id}/invites/{invite_id}/revoke — inviter or the
    /// group's creator only.
    static func revokeReadingInvite(groupId: String, inviteId: String) async throws {
        _ = try await APIClient.shared.postEmpty("reading/groups/\(groupId)/invites/\(inviteId)/revoke", as: EmptyResponse.self)
    }

    /// GET /reading/invites/{token} — authenticated in-app preview, called
    /// right after a nuru://join/{token} deep link opens the app while
    /// signed in. 404 (surfaced as APIError) on unknown/expired/revoked/declined.
    static func readingInvitePreview(_ token: String) async throws -> ReadingInvitePreview {
        try await APIClient.shared.get("reading/invites/\(token)", as: ReadingInvitePreview.self)
    }

    /// POST /reading/invites/{token}/accept — redeems: joins the group,
    /// enrolls in the underlying plan, connects with the inviter. Idempotent.
    @discardableResult
    static func acceptReadingInvite(_ token: String) async throws -> ReadingInviteAcceptResult {
        try await APIClient.shared.postEmpty("reading/invites/\(token)/accept", as: ReadingInviteAcceptResult.self)
    }

    /// POST /reading/invites/{token}/decline — targeted invites only (403 on
    /// an open link — there's no single party to decline for everyone).
    static func declineReadingInvite(_ token: String) async throws {
        _ = try await APIClient.shared.postEmpty("reading/invites/\(token)/decline", as: EmptyResponse.self)
    }

    /// The public https://pathway.nuruplace.org/join/{token} share URL — the
    /// entire payload for every share channel (WhatsApp/social/copy/QR).
    static func readingJoinURL(token: String) -> URL {
        URL(string: "https://pathway.nuruplace.org/join/\(token)")!
    }
}
