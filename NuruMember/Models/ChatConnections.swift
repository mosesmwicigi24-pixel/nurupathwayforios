// Chat connections — consent-gated peer relationships (Chat Redesign C1/C2,
// docs/CHAT_REDESIGN.md, docs/CHAT_REDESIGN_PLAN.md §2.2/§4, C3a client phase).
// Mirrors packages/backend/src/modules/chat/connections.ts's wire shapes.
// Every DTO is tolerant (defaulted optionals) — an unknown/older server shape
// must never blank the whole Chat tab.
import Foundation

/// Client-side connection state between the caller and one other member.
/// Not sent on the wire — derived locally from `GET /chat/connections` +
/// `GET /chat/connections/requests?direction=...`.
enum ConnectionState: Equatable, Sendable {
    case notConnected
    case requestSent(requestId: String)
    case requestReceived(requestId: String)
    case connected
    case blocked
}

/// One row of GET /chat/connections/requests — a pending ask, incoming or
/// outgoing depending on which `direction` was fetched.
struct ConnectionRequestRow: Codable, Sendable, Identifiable, Hashable {
    let requestId: String
    let status: String
    let message: String?
    let createdAt: String?
    let userId: String
    let fullName: String
    let avatarUrl: String?

    var id: String { requestId }
    static func == (a: ConnectionRequestRow, b: ConnectionRequestRow) -> Bool { a.requestId == b.requestId }
    func hash(into h: inout Hasher) { h.combine(requestId) }

    /// Memberwise — needed alongside the tolerant decoder below for call
    /// sites that build a row by hand (e.g. cancelling a request from the
    /// directory row, which only has the id + person on hand).
    init(requestId: String, status: String, message: String?, createdAt: String?,
         userId: String, fullName: String, avatarUrl: String?) {
        self.requestId = requestId; self.status = status; self.message = message
        self.createdAt = createdAt; self.userId = userId; self.fullName = fullName
        self.avatarUrl = avatarUrl
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        requestId = try c.decode(String.self, forKey: .requestId)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
    }
}

/// One row of GET /chat/connections — an accepted (chat-able) peer.
struct ConnectionRow: Codable, Sendable, Identifiable, Hashable {
    let userId: String
    let fullName: String
    let avatarUrl: String?
    let status: String   // accepted | blocked | removed
    let establishedAt: String?

    var id: String { userId }
    static func == (a: ConnectionRow, b: ConnectionRow) -> Bool { a.userId == b.userId }
    func hash(into h: inout Hasher) { h.combine(userId) }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "accepted"
        establishedAt = try? c.decodeIfPresent(String.self, forKey: .establishedAt)
    }
}

/// POST /chat/connections/requests response.
struct RequestConnectionResult: Codable, Sendable {
    let requestId: String
    let status: String
    let duplicate: Bool?
    let mutual: Bool?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        requestId = (try? c.decodeIfPresent(String.self, forKey: .requestId)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        duplicate = try? c.decodeIfPresent(Bool.self, forKey: .duplicate)
        mutual = try? c.decodeIfPresent(Bool.self, forKey: .mutual)
    }
}

/// POST .../accept | /decline | DELETE .../requests/{id} response shape
/// (all three share `{ request_id, status, already }`).
struct ConnectionRequestDecision: Codable, Sendable {
    let requestId: String
    let status: String
    let already: Bool?
}

/// POST /chat/connections/{user_id}/remove | /block | /unblock response shape
/// (all three share `{ user_id, status }`).
struct ConnectionActionResult: Codable, Sendable {
    let userId: String
    let status: String
}
