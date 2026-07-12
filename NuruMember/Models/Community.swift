// Community DTOs — Swift mirrors of the prayer-wall (and, later, chat) contracts
// in packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

struct PrayerReaction: Codable, Sendable {
    let emoji: String
    let count: Int
    let mine: Bool
}

struct PrayerWallPost: Codable, Sendable, Identifiable {
    // Tolerant end-to-end (Android parity): a sparse field degrades one row,
    // never the whole wall.
    var postId: String = ""
    var authorUserId: String = ""
    var authorName: String = ""
    var authorAvatar: String? = nil
    var title: String? = nil
    var body: String = ""
    var audioUrl: String? = nil
    /// Voice-prayer bars (0–100), recorded by the composer — playback renders
    /// them and fills as audio plays.
    var audioWaveform: [Int]? = nil
    var isAnswered: Bool = false
    var createdAt: String = ""
    var mine: Bool = false
    var prayCount: Int = 0
    var iPrayed: Bool = false
    var commentCount: Int? = nil
    var reactions: [PrayerReaction] = []

    var id: String { postId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        postId = (try? c.decodeIfPresent(String.self, forKey: .postId)) ?? ""
        authorUserId = (try? c.decodeIfPresent(String.self, forKey: .authorUserId)) ?? ""
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        audioUrl = try? c.decodeIfPresent(String.self, forKey: .audioUrl)
        audioWaveform = try? c.decodeIfPresent([Int].self, forKey: .audioWaveform)
        isAnswered = (try? c.decodeIfPresent(Bool.self, forKey: .isAnswered)) ?? false
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
        prayCount = (try? c.decodeIfPresent(Int.self, forKey: .prayCount)) ?? 0
        iPrayed = (try? c.decodeIfPresent(Bool.self, forKey: .iPrayed)) ?? false
        commentCount = try? c.decodeIfPresent(Int.self, forKey: .commentCount)
        reactions = (try? c.decodeIfPresent([PrayerReaction].self, forKey: .reactions)) ?? []
    }
}

struct PrayerWallComment: Codable, Sendable, Identifiable {
    let commentId: String
    let authorUserId: String
    let authorName: String
    let authorAvatar: String?
    let body: String
    let audioUrl: String?
    var audioWaveform: [Int]? = nil
    let createdAt: String
    let mine: Bool

    var id: String { commentId }
}

struct PrayerWallDetail: Codable, Sendable {
    let post: PrayerWallPost
    let comments: [PrayerWallComment]
}
