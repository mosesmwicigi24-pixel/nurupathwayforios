// Chat DTOs — Swift mirrors of the chat contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

struct ChatConversation: Codable, Sendable, Identifiable, Hashable {
    let conversationId: String
    let kind: String          // dm | group | space
    let isPublic: Bool
    let title: String?
    let topic: String?
    let category: String?
    let memberCount: Int
    let lastBody: String?
    let lastType: String?
    let lastAt: String?
    let lastAuthor: String?
    let unread: Int
    let avatarUrl: String?

    var id: String { conversationId }
    static func == (a: ChatConversation, b: ChatConversation) -> Bool { a.conversationId == b.conversationId }
    func hash(into h: inout Hasher) { h.combine(conversationId) }
}

struct DiscoverSpace: Codable, Sendable, Identifiable {
    let conversationId: String
    let title: String?
    let topic: String?
    let category: String?
    let memberCount: Int
    var id: String { conversationId }
}

struct ChatInbox: Codable, Sendable {
    let conversations: [ChatConversation]
    let discoverSpaces: [DiscoverSpace]
}

/// One row of GET /chat/people — a congregation member the caller may DM.
/// Achievement flair (level / badges / certs) is public aggregates only, and
/// every field is a tolerant optional so rows from older servers still decode.
struct ChatPerson: Codable, Sendable, Identifiable, Hashable {
    let userId: String
    let fullName: String
    let role: String?
    let avatarUrl: String?
    let congregation: String?   // present only for portal-staff callers
    let level: Int?             // pathway level (1 when not enrolled)
    let badgeCount: Int?        // unrevoked badges — count only
    let badgeIcons: [String]?   // up to 3 most-recent badge icon strings
    let certCount: Int?         // issued certificates — count only

    var id: String { userId }
}

struct ChatReaction: Codable, Sendable {
    let emoji: String
    let count: Int
    let mine: Bool
}

struct ChatMessage: Codable, Sendable, Identifiable {
    let messageId: String
    let authorUserId: String
    let authorName: String
    let authorAvatar: String?
    let body: String
    let msgType: String      // text | voice | image | file | video
    let attachmentUrl: String?
    let replyBody: String?
    let replyAuthor: String?
    let isEdited: Bool
    let createdAt: String
    let mine: Bool
    let reactions: [ChatReaction]
    let readCount: Int?
    let recipientCount: Int?
    let aiTag: String?

    var id: String { messageId }
}

struct ChatThreadDetail: Codable, Sendable {
    let conversationId: String
    let kind: String
    let isPublic: Bool
    let title: String?
    let topic: String?
    let memberCount: Int
    let joined: Bool
    let messages: [ChatMessage]
}
