// Ekklesia — the intercessory watch (Prayer Room tab 5, the Home card, the
// invitations). Writes carry client-made ids + client_mutation_id held by the
// caller across retries, so a second tap never brings a need twice (§3.6).
import Foundation

extension MemberAPI {
    private struct NoBody: Encodable {}

    /// GET /ekklesia?status=active|answered — the watch and its needs.
    static func ekklesia(status: String = "active") async throws -> EkklesiaOverview {
        try await APIClient.shared.get("ekklesia", query: ["status": status], as: EkklesiaOverview.self)
    }

    /// GET /ekklesia/summary — the Home card and the invitations read this.
    static func ekklesiaSummary() async throws -> EkklesiaSummary {
        try await APIClient.shared.get("ekklesia/summary", as: EkklesiaSummary.self)
    }

    /// POST /ekklesia/join — stand on the watch.
    @discardableResult
    static func ekklesiaJoin() async throws -> EkklesiaJoinRes {
        try await APIClient.shared.post("ekklesia/join", body: NoBody(), as: EkklesiaJoinRes.self)
    }

    /// POST /ekklesia/leave
    static func ekklesiaLeave() async throws {
        _ = try await APIClient.shared.post("ekklesia/leave", body: NoBody(), as: EmptyResponse.self)
    }

    /// POST /ekklesia/requests — bring a need (ids held by the caller).
    static func ekklesiaBring(requestId: String, clientMutationId: String, title: String, body: String, forWhom: String?, urgent: Bool) async throws {
        struct Body: Encodable { let requestId: String; let title: String; let body: String; let forWhom: String?; let urgency: String; let clientMutationId: String }
        _ = try await APIClient.shared.post("ekklesia/requests",
            body: Body(requestId: requestId, title: title, body: body, forWhom: forWhom, urgency: urgent ? "urgent" : "normal", clientMutationId: clientMutationId),
            as: EmptyResponse.self)
    }

    /// GET /ekklesia/requests/{id}
    static func ekklesiaRequest(_ id: String) async throws -> EkklesiaRequestDetail {
        try await APIClient.shared.get("ekklesia/requests/\(id)", as: EkklesiaRequestDetail.self)
    }

    /// DELETE /ekklesia/requests/{id} — withdraw (requester) or take down (leader).
    static func ekklesiaWithdraw(_ id: String) async throws {
        _ = try await APIClient.shared.delete("ekklesia/requests/\(id)", as: EmptyResponse.self)
    }

    /// POST /ekklesia/requests/{id}/intercede — "I interceded today" (one per day).
    @discardableResult
    static func ekklesiaIntercede(_ id: String) async throws -> EkklesiaIntercedeRes {
        try await APIClient.shared.post("ekklesia/requests/\(id)/intercede", body: NoBody(), as: EkklesiaIntercedeRes.self)
    }

    /// POST /ekklesia/requests/{id}/updates — write back (update | testimony).
    static func ekklesiaWriteBack(_ id: String, updateId: String, clientMutationId: String, body: String, testimony: Bool) async throws {
        struct Body: Encodable { let updateId: String; let body: String; let kind: String; let clientMutationId: String }
        _ = try await APIClient.shared.post("ekklesia/requests/\(id)/updates",
            body: Body(updateId: updateId, body: body, kind: testimony ? "testimony" : "update", clientMutationId: clientMutationId),
            as: EmptyResponse.self)
    }

    /// POST /ekklesia/requests/{id}/answered
    static func ekklesiaAnswered(_ id: String, answered: Bool, note: String?) async throws {
        struct Body: Encodable { let answered: Bool; let note: String? }
        _ = try await APIClient.shared.post("ekklesia/requests/\(id)/answered", body: Body(answered: answered, note: note), as: EmptyResponse.self)
    }

    /// POST /ekklesia/requests/{id}/pinned — leaders only.
    static func ekklesiaPinned(_ id: String, pinned: Bool) async throws {
        struct Body: Encodable { let pinned: Bool }
        _ = try await APIClient.shared.post("ekklesia/requests/\(id)/pinned", body: Body(pinned: pinned), as: EmptyResponse.self)
    }
}
