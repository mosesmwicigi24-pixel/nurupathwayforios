// Broadcast — one word from the pastor to the whole church, and every answer to
// it in one place.
//
// A broadcast is not a group room: it is delivered as an individual DM to every
// member, so a reply is a private 1:1 thread that only the sender can open. Each
// response therefore already carries the conversation it came from — "open the
// thread" is a navigation, not a creation, and the broadcast is already its top
// message.
//
// Tolerant decoding lives in extensions so the synthesized memberwise init
// survives — the compose screen builds a sent broadcast by hand from the send's
// own reply, without waiting for a refetch (Chat.swift's idiom).
import Foundation

/// A broadcast as every path describes it — the send, the list, the detail.
struct Broadcast: Codable, Sendable, Identifiable, Hashable {
    let broadcastId: String
    let body: String
    var msgType: String = "text"
    var attachmentUrl: String? = nil
    /// "all" (the whole church) | "congregation" (narrowed on purpose).
    var audience: String = "all"
    /// How many members it reached, recorded at send time.
    var recipientCount: Int = 0
    /// How many have opened it (two blue ticks), and how many wrote back.
    var seenCount: Int = 0
    var repliedCount: Int = 0
    var createdAt: String? = nil

    var id: String { broadcastId }
    static func == (a: Broadcast, b: Broadcast) -> Bool { a.broadcastId == b.broadcastId }
    func hash(into h: inout Hasher) { h.combine(broadcastId) }
}

extension Broadcast {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        broadcastId = try c.decode(String.self, forKey: .broadcastId) // identity — must be real
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        msgType = (try? c.decodeIfPresent(String.self, forKey: .msgType)) ?? "text"
        attachmentUrl = try? c.decodeIfPresent(String.self, forKey: .attachmentUrl)
        audience = (try? c.decodeIfPresent(String.self, forKey: .audience)) ?? "all"
        recipientCount = (try? c.decodeIfPresent(Int.self, forKey: .recipientCount)) ?? 0
        seenCount = (try? c.decodeIfPresent(Int.self, forKey: .seenCount)) ?? 0
        repliedCount = (try? c.decodeIfPresent(Int.self, forKey: .repliedCount)) ?? 0
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
    }
}

/// The answer POST /chat/broadcast gives: the message AS SENT, whole, so the
/// page shows it immediately without a second round trip.
struct BroadcastSent: Codable, Sendable {
    let broadcastId: String
    let body: String
    var audience: String = "all"
    var recipientCount: Int = 0
    var createdAt: String? = nil
    var sent: Int = 0
    var duplicate: Bool = false

    /// The sent thing, as the list and detail would describe it — so the compose
    /// screen can hand it straight to the same views.
    var asBroadcast: Broadcast {
        Broadcast(broadcastId: broadcastId, body: body, audience: audience,
                  recipientCount: recipientCount, createdAt: createdAt)
    }
}

extension BroadcastSent {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        broadcastId = try c.decode(String.self, forKey: .broadcastId)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        audience = (try? c.decodeIfPresent(String.self, forKey: .audience)) ?? "all"
        recipientCount = (try? c.decodeIfPresent(Int.self, forKey: .recipientCount)) ?? 0
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        sent = (try? c.decodeIfPresent(Int.self, forKey: .sent)) ?? 0
        duplicate = (try? c.decodeIfPresent(Bool.self, forKey: .duplicate)) ?? false
    }
}

/// Someone answering the broadcast. `conversationId` IS the private thread with
/// them, already holding the broadcast as its first message.
struct BroadcastResponse: Codable, Sendable, Identifiable, Hashable {
    let messageId: String
    let conversationId: String
    var body: String = ""
    var msgType: String = "text"
    var attachmentUrl: String? = nil
    var createdAt: String? = nil
    var userId: String = ""
    var fullName: String = ""
    var avatarUrl: String? = nil
    /// How many messages this person has written in the thread — 1 is a first
    /// word, more is a conversation already under way.
    var fromThem: Int = 1

    var id: String { messageId }
    static func == (a: BroadcastResponse, b: BroadcastResponse) -> Bool { a.messageId == b.messageId }
    func hash(into h: inout Hasher) { h.combine(messageId) }
}

extension BroadcastResponse {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        messageId = try c.decode(String.self, forKey: .messageId)
        conversationId = try c.decode(String.self, forKey: .conversationId) // the door to the thread
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        msgType = (try? c.decodeIfPresent(String.self, forKey: .msgType)) ?? "text"
        attachmentUrl = try? c.decodeIfPresent(String.self, forKey: .attachmentUrl)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "Someone"
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        fromThem = (try? c.decodeIfPresent(Int.self, forKey: .fromThem)) ?? 1
    }
}

/// One person the broadcast reached — the ticks.
///   delivered → one blue tick. Always true: a broadcast is written into every
///     recipient's thread server-side in one transaction, so arrival is a fact.
///   seen → two blue ticks. They opened the thread after it landed.
struct BroadcastRecipient: Codable, Sendable, Identifiable, Hashable {
    let userId: String
    var fullName: String = ""
    var avatarUrl: String? = nil
    var delivered: Bool = true
    var deliveredAt: String? = nil
    var seen: Bool = false
    var seenAt: String? = nil

    var id: String { userId }
    static func == (a: BroadcastRecipient, b: BroadcastRecipient) -> Bool { a.userId == b.userId }
    func hash(into h: inout Hasher) { h.combine(userId) }
}

extension BroadcastRecipient {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "Someone"
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        delivered = (try? c.decodeIfPresent(Bool.self, forKey: .delivered)) ?? true
        deliveredAt = try? c.decodeIfPresent(String.self, forKey: .deliveredAt)
        seen = (try? c.decodeIfPresent(Bool.self, forKey: .seen)) ?? false
        seenAt = try? c.decodeIfPresent(String.self, forKey: .seenAt)
    }
}

/// GET /chat/broadcasts/{id} — the message, the answers, and the ticks.
struct BroadcastDetail: Codable, Sendable {
    let broadcastId: String
    var body: String = ""
    var msgType: String = "text"
    var attachmentUrl: String? = nil
    var audience: String = "all"
    var recipientCount: Int = 0
    var createdAt: String? = nil
    var responses: [BroadcastResponse] = []
    var recipients: [BroadcastRecipient] = []
    var deliveredCount: Int = 0
    var seenCount: Int = 0
}

extension BroadcastDetail {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        broadcastId = try c.decode(String.self, forKey: .broadcastId)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        msgType = (try? c.decodeIfPresent(String.self, forKey: .msgType)) ?? "text"
        attachmentUrl = try? c.decodeIfPresent(String.self, forKey: .attachmentUrl)
        audience = (try? c.decodeIfPresent(String.self, forKey: .audience)) ?? "all"
        recipientCount = (try? c.decodeIfPresent(Int.self, forKey: .recipientCount)) ?? 0
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        responses = (try? c.decodeIfPresent([BroadcastResponse].self, forKey: .responses)) ?? []
        recipients = (try? c.decodeIfPresent([BroadcastRecipient].self, forKey: .recipients)) ?? []
        deliveredCount = (try? c.decodeIfPresent(Int.self, forKey: .deliveredCount)) ?? 0
        seenCount = (try? c.decodeIfPresent(Int.self, forKey: .seenCount)) ?? 0
    }
}

/// GET /chat/broadcasts — the last few sent, and how many there are in all.
struct BroadcastList: Codable, Sendable {
    var data: [Broadcast] = []
    var total: Int = 0
}
