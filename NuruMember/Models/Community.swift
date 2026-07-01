// Community DTOs — Swift mirrors of the prayer-wall (and, later, chat) contracts
// in packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

struct PrayerReaction: Codable, Sendable {
    let emoji: String
    let count: Int
    let mine: Bool
}

struct PrayerWallPost: Codable, Sendable, Identifiable {
    let postId: String
    let authorUserId: String
    let authorName: String
    let authorAvatar: String?
    let title: String?
    let body: String
    let audioUrl: String?
    let isAnswered: Bool
    let createdAt: String
    let mine: Bool
    let prayCount: Int
    let iPrayed: Bool
    // Present on the wall list but omitted by the post-detail serializer — decode
    // defensively so opening a prayer never fails on a missing count.
    let commentCount: Int?
    let reactions: [PrayerReaction]

    var id: String { postId }
}

struct PrayerWallComment: Codable, Sendable, Identifiable {
    let commentId: String
    let authorUserId: String
    let authorName: String
    let authorAvatar: String?
    let body: String
    let audioUrl: String?
    let createdAt: String
    let mine: Bool

    var id: String { commentId }
}

struct PrayerWallDetail: Codable, Sendable {
    let post: PrayerWallPost
    let comments: [PrayerWallComment]
}
