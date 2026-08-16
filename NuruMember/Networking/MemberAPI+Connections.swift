// Chat connections API — consent-gated peer relationships (Chat Redesign
// C1/C2 backend, C3a client). Wire shapes mirror
// packages/backend/src/modules/chat/connections.ts + chat/index.ts exactly;
// see ChatConnections.swift for the tolerant DTOs.
import Foundation

extension MemberAPI {
    // MARK: Connection requests

    /// POST /chat/connections/requests — ask to connect. If the other party
    /// already has a pending ask to the caller, the server resolves BOTH
    /// sides to accepted immediately (`result.mutual == true`).
    @discardableResult
    static func requestConnection(userId: String, message: String? = nil) async throws -> RequestConnectionResult {
        struct Body: Encodable { let userId: String; let message: String?; let clientMutationId: String }
        return try await APIClient.shared.post(
            "chat/connections/requests",
            body: Body(userId: userId, message: message, clientMutationId: UUID().uuidString),
            as: RequestConnectionResult.self)
    }

    /// GET /chat/connections/requests?direction=incoming|outgoing.
    static func listConnectionRequests(direction: String) async throws -> [ConnectionRequestRow] {
        try await APIClient.shared.get(
            "chat/connections/requests", query: ["direction": direction],
            as: Envelope<ConnectionRequestRow>.self).data
    }

    /// POST /chat/connections/requests/{id}/accept — recipient only.
    @discardableResult
    static func acceptConnectionRequest(_ requestId: String) async throws -> ConnectionRequestDecision {
        try await APIClient.shared.postEmpty("chat/connections/requests/\(requestId)/accept", as: ConnectionRequestDecision.self)
    }

    /// POST /chat/connections/requests/{id}/decline — recipient only.
    @discardableResult
    static func declineConnectionRequest(_ requestId: String) async throws -> ConnectionRequestDecision {
        try await APIClient.shared.postEmpty("chat/connections/requests/\(requestId)/decline", as: ConnectionRequestDecision.self)
    }

    /// DELETE /chat/connections/requests/{id} — requester-only cancel.
    @discardableResult
    static func cancelConnectionRequest(_ requestId: String) async throws -> ConnectionRequestDecision {
        try await APIClient.shared.delete("chat/connections/requests/\(requestId)", as: ConnectionRequestDecision.self)
    }

    // MARK: Connections

    /// GET /chat/connections — my accepted peers ("who can I already chat with").
    static func listConnections() async throws -> [ConnectionRow] {
        try await APIClient.shared.get("chat/connections", as: Envelope<ConnectionRow>.self).data
    }

    /// POST /chat/connections/{user_id}/remove — either party; existing DM
    /// history is kept (no-data-loss), only the pair reverts to not-connected.
    @discardableResult
    static func removeConnection(_ userId: String) async throws -> ConnectionActionResult {
        try await APIClient.shared.postEmpty("chat/connections/\(userId)/remove", as: ConnectionActionResult.self)
    }

    /// POST /chat/connections/{user_id}/block.
    @discardableResult
    static func blockConnection(_ userId: String) async throws -> ConnectionActionResult {
        try await APIClient.shared.postEmpty("chat/connections/\(userId)/block", as: ConnectionActionResult.self)
    }

    /// POST /chat/connections/{user_id}/unblock — blocker-only; 404 if the
    /// caller never blocked this person (nothing to undo).
    @discardableResult
    static func unblockConnection(_ userId: String) async throws -> ConnectionActionResult {
        try await APIClient.shared.postEmpty("chat/connections/\(userId)/unblock", as: ConnectionActionResult.self)
    }
}
