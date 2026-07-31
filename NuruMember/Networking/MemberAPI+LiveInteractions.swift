// Nuru Live L5 — interactive-stage endpoints (raise-hand, reactions, live
// chat) + L6 guest scaffolding. Wire shapes are PINNED in
// docs/LIVE_INTERACTIVE.md; the backend is being built to the same doc in
// parallel, so every call here mirrors it exactly. See
// Models/LiveInteractions.swift for the tolerant DTOs.
import Foundation

extension MemberAPI {
    /// POST /live/streams/{id}/reactions {emoji: "like"|"love"} → 204.
    /// Append-only; server rate-limits to ≥1s/user — callers should debounce
    /// on the UI side too (see the viewer's reaction buttons) rather than
    /// relying on the server to silently absorb a tap flood.
    static func reactToLiveStream(streamId: String, emoji: String) async throws {
        struct Body: Encodable { let emoji: String }
        _ = try await APIClient.shared.post("live/streams/\(streamId)/reactions",
                                            body: Body(emoji: emoji), as: EmptyResponse.self)
    }

    /// POST /live/streams/{id}/hand {raised: Bool} → 204. One hand state per
    /// (stream, user) — this always targets the CALLING user; there is no
    /// per-target parameter, so a broadcaster cannot force another member's
    /// hand down through this endpoint (see LiveHandsGuestsSheet's "Lower"
    /// affordance, which is local-only for exactly this reason).
    static func setLiveHandRaised(streamId: String, raised: Bool) async throws {
        struct Body: Encodable { let raised: Bool }
        _ = try await APIClient.shared.post("live/streams/\(streamId)/hand",
                                            body: Body(raised: raised), as: EmptyResponse.self)
    }

    /// GET /live/streams/{id}/messages?since=<iso> → ascending, cap 200/poll.
    /// `since` omitted on the very first load (whole recent history up to
    /// the server's own cap); every poll after that passes the last message's
    /// `sent_at` as the cursor.
    static func fetchLiveMessages(streamId: String, since: String? = nil) async throws -> [LiveChatMessage] {
        var q: [String: String] = [:]
        if let since, !since.isEmpty { q["since"] = since }
        return try await APIClient.shared.get("live/streams/\(streamId)/messages", query: q,
                                              as: LiveMessagesEnvelope.self).messages
    }

    /// POST /live/streams/{id}/messages {body ≤500} → 201 the message.
    static func sendLiveMessage(streamId: String, body: String) async throws -> LiveChatMessage {
        struct Body: Encodable { let body: String }
        return try await APIClient.shared.post("live/streams/\(streamId)/messages",
                                                body: Body(body: body), as: LiveChatMessage.self)
    }

    /// GET /live/streams/{id}/pulse — the one poll for the whole interactive
    /// overlay (broadcaster 3s, viewer 5s; see LivePulseController and
    /// BroadcastController's own pulse-poll pairing with startViewerPolling).
    static func fetchLivePulse(streamId: String) async throws -> LivePulse {
        try await APIClient.shared.get("live/streams/\(streamId)/pulse", as: LivePulse.self)
    }

    // MARK: L6 guest scaffolding — state machine now, video in the next phase.

    /// POST /live/streams/{id}/guests/{userId} — broadcaster only, ≤6 active
    /// guests. No request body; the path alone identifies the invitee.
    static func inviteLiveGuest(streamId: String, userId: String) async throws {
        _ = try await APIClient.shared.postEmpty("live/streams/\(streamId)/guests/\(userId)", as: EmptyResponse.self)
    }

    /// POST /live/streams/{id}/guests/respond {accept: Bool} — the invitee's
    /// own accept/decline.
    static func respondToLiveGuestInvite(streamId: String, accept: Bool) async throws {
        struct Body: Encodable { let accept: Bool }
        _ = try await APIClient.shared.post("live/streams/\(streamId)/guests/respond",
                                            body: Body(accept: accept), as: EmptyResponse.self)
    }

    /// DELETE /live/streams/{id}/guests/{userId} — broadcaster removing a
    /// guest, OR a guest removing themselves (self = leave).
    static func removeLiveGuest(streamId: String, userId: String) async throws {
        _ = try await APIClient.shared.delete("live/streams/\(streamId)/guests/\(userId)", as: EmptyResponse.self)
    }
}
