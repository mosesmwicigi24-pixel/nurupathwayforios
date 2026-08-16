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
    /// Voice-note preview length in whole seconds (attachment_meta->>'duration'
    /// of the last message) — lets the inbox row read "Voice note · 0:42".
    var lastDuration: Int? = nil
    let unread: Int
    let avatarUrl: String?
    /// DM rows only: the other participant's user id (backend is adding
    /// `peer_user_id` to GET /chat/conversations). Optional + defaulted so rows
    /// from older servers — and existing memberwise-init call sites — still work.
    var peerUserId: String? = nil
    /// `chat_conversations.type` — DIRECT/SPACE/DISCIPLER/PASTORAL/BROADCAST/
    /// BROADCAST_RESPONSE (Chat Redesign C4). The server-authoritative way to
    /// tell a discipler/pastoral 1:1 apart from an ordinary DM; nil on an older
    /// server, in which case callers fall back to the client-taught cached-id
    /// heuristic (see ChatInboxViewModel.dms, PastoralPrefs).
    var type: String? = nil
    /// This caller has muted the conversation (server-side, per-member; Chat
    /// Redesign C4 mute). Additive — nil/false on a server that predates it.
    var muted: Bool = false

    var id: String { conversationId }
    static func == (a: ChatConversation, b: ChatConversation) -> Bool { a.conversationId == b.conversationId }
    func hash(into h: inout Hasher) { h.combine(conversationId) }
}

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the screens that build placeholder conversations by hand.
extension ChatConversation {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "space"
        isPublic = (try? c.decodeIfPresent(Bool.self, forKey: .isPublic)) ?? false
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        topic = try? c.decodeIfPresent(String.self, forKey: .topic)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        lastBody = try? c.decodeIfPresent(String.self, forKey: .lastBody)
        lastType = try? c.decodeIfPresent(String.self, forKey: .lastType)
        lastAt = try? c.decodeIfPresent(String.self, forKey: .lastAt)
        lastAuthor = try? c.decodeIfPresent(String.self, forKey: .lastAuthor)
        lastDuration = try? c.decodeIfPresent(Int.self, forKey: .lastDuration)
        unread = (try? c.decodeIfPresent(Int.self, forKey: .unread)) ?? 0
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        peerUserId = try? c.decodeIfPresent(String.self, forKey: .peerUserId)
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
    }
}

struct DiscoverSpace: Codable, Sendable, Identifiable {
    let conversationId: String
    let title: String?
    let topic: String?
    let category: String?
    let memberCount: Int
    var id: String { conversationId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        topic = try? c.decodeIfPresent(String.self, forKey: .topic)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
    }
}

struct ChatInbox: Codable, Sendable {
    let conversations: [ChatConversation]
    let discoverSpaces: [DiscoverSpace]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conversations = (try? c.decodeIfPresent([ChatConversation].self, forKey: .conversations)) ?? []
        discoverSpaces = (try? c.decodeIfPresent([DiscoverSpace].self, forKey: .discoverSpaces)) ?? []
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        role = try? c.decodeIfPresent(String.self, forKey: .role)
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        congregation = try? c.decodeIfPresent(String.self, forKey: .congregation)
        level = try? c.decodeIfPresent(Int.self, forKey: .level)
        badgeCount = try? c.decodeIfPresent(Int.self, forKey: .badgeCount)
        badgeIcons = try? c.decodeIfPresent([String].self, forKey: .badgeIcons)
        certCount = try? c.decodeIfPresent(Int.self, forKey: .certCount)
    }
}

struct ChatReaction: Codable, Sendable {
    let emoji: String
    let count: Int
    let mine: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        emoji = (try? c.decodeIfPresent(String.self, forKey: .emoji)) ?? ""
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
    }
}

/// Voice attachment meta — { duration (sec), waveform [0..100] }.
struct ChatAttachmentMeta: Codable, Sendable {
    var duration: Int? = nil
    var waveform: [Int]? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        duration = try? c.decodeIfPresent(Int.self, forKey: .duration)
        waveform = try? c.decodeIfPresent([Int].self, forKey: .waveform)
    }
    init(duration: Int?, waveform: [Int]?) { self.duration = duration; self.waveform = waveform }
}

struct ChatMessage: Codable, Sendable, Identifiable {
    // Tolerant like Android's DTOs: one odd message must never blank a thread.
    var messageId: String = ""
    var authorUserId: String = ""
    var authorName: String = ""
    var authorAvatar: String? = nil
    var body: String = ""
    var msgType: String = "text" // text | voice | image | file | video
    var attachmentUrl: String? = nil
    var attachmentMeta: ChatAttachmentMeta? = nil
    var replyBody: String? = nil
    var replyAuthor: String? = nil
    var isEdited: Bool = false
    var createdAt: String = ""
    var mine: Bool = false
    var reactions: [ChatReaction] = []
    var readCount: Int? = nil
    var recipientCount: Int? = nil
    var aiTag: String? = nil
    /// Set when this message was delivered by a broadcast — the mark that lets a
    /// member's thread dress itself as "Talk with Pastor" instead of a plain DM.
    var broadcastId: String? = nil

    var id: String { messageId }
    init(messageId: String, authorUserId: String, authorName: String, authorAvatar: String?,
         body: String, msgType: String, attachmentUrl: String?, attachmentMeta: ChatAttachmentMeta? = nil,
         replyBody: String?, replyAuthor: String?, isEdited: Bool, createdAt: String, mine: Bool,
         reactions: [ChatReaction], readCount: Int?, recipientCount: Int?, aiTag: String?) {
        self.messageId = messageId; self.authorUserId = authorUserId; self.authorName = authorName
        self.authorAvatar = authorAvatar; self.body = body; self.msgType = msgType
        self.attachmentUrl = attachmentUrl; self.attachmentMeta = attachmentMeta
        self.replyBody = replyBody; self.replyAuthor = replyAuthor; self.isEdited = isEdited
        self.createdAt = createdAt; self.mine = mine; self.reactions = reactions
        self.readCount = readCount; self.recipientCount = recipientCount; self.aiTag = aiTag
    }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        messageId = (try? c.decodeIfPresent(String.self, forKey: .messageId)) ?? ""
        authorUserId = (try? c.decodeIfPresent(String.self, forKey: .authorUserId)) ?? ""
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        msgType = (try? c.decodeIfPresent(String.self, forKey: .msgType)) ?? "text"
        attachmentUrl = try? c.decodeIfPresent(String.self, forKey: .attachmentUrl)
        attachmentMeta = try? c.decodeIfPresent(ChatAttachmentMeta.self, forKey: .attachmentMeta)
        replyBody = try? c.decodeIfPresent(String.self, forKey: .replyBody)
        replyAuthor = try? c.decodeIfPresent(String.self, forKey: .replyAuthor)
        isEdited = (try? c.decodeIfPresent(Bool.self, forKey: .isEdited)) ?? false
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
        reactions = (try? c.decodeIfPresent([ChatReaction].self, forKey: .reactions)) ?? []
        readCount = try? c.decodeIfPresent(Int.self, forKey: .readCount)
        recipientCount = try? c.decodeIfPresent(Int.self, forKey: .recipientCount)
        aiTag = try? c.decodeIfPresent(String.self, forKey: .aiTag)
        broadcastId = try? c.decodeIfPresent(String.self, forKey: .broadcastId)
    }
}

/// Shared response shape for the author-only mutation endpoints:
/// PATCH /chat/messages/{id} → { message_id, body, is_edited }
/// DELETE /chat/messages/{id} → { message_id, deleted }
struct ChatMessageMutationResult: Codable, Sendable {
    let messageId: String
    let body: String?
    let isEdited: Bool?
    let deleted: Bool?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        messageId = (try? c.decodeIfPresent(String.self, forKey: .messageId)) ?? ""
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        isEdited = try? c.decodeIfPresent(Bool.self, forKey: .isEdited)
        deleted = try? c.decodeIfPresent(Bool.self, forKey: .deleted)
    }
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
    /// Same server `type` as ChatConversation (Chat Redesign C4) — additive.
    var type: String? = nil
    /// Same server per-member mute as ChatConversation — additive.
    var muted: Bool = false
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        conversationId = try c.decode(String.self, forKey: .conversationId)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "space"
        isPublic = (try? c.decodeIfPresent(Bool.self, forKey: .isPublic)) ?? false
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        topic = try? c.decodeIfPresent(String.self, forKey: .topic)
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        joined = (try? c.decodeIfPresent(Bool.self, forKey: .joined)) ?? false
        messages = (try? c.decodeIfPresent([ChatMessage].self, forKey: .messages)) ?? []
        type = try? c.decodeIfPresent(String.self, forKey: .type)
        muted = (try? c.decodeIfPresent(Bool.self, forKey: .muted)) ?? false
    }
}
