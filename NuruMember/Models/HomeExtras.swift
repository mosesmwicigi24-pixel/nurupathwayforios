// Home / media / announcement DTOs — Swift mirrors of the contract in
// packages/mobile/src/api/types.ts so Home can load every real card, image and
// video. Decoded with `.convertFromSnakeCase`.
import Foundation

struct ContentReaction: Codable, Sendable, Hashable {
    let emoji: String
    let count: Int
    let mine: Bool
}

/// GET /home/welcome-video — a homepage welcome video (external link or hosted url).
struct WelcomeVideo: Codable, Sendable {
    let mediaAssetId: String
    let videoSource: String          // cloudinary | youtube | vimeo | direct | private
    let caption: String?
    let durationSec: Int?
    let thumbnailUrl: String?
    let reactions: [ContentReaction]?
    let loveCount: Int?
    let liked: Bool?
    // external sources
    let externalUrl: String?
    let externalVideoId: String?
    // hosted (cloudinary)
    let url: String?
    let expiresAt: String?

    /// The playable URL (external link, else hosted signed url).
    var playUrl: String? { externalUrl ?? url }
}

/// POST /media/{id}/reactions.
struct ReactionToggleResult: Codable, Sendable {
    let on: Bool
    let reactions: [ContentReaction]
    let loveCount: Int
    let liked: Bool
}

/// GET /home/featured-cell — "This week at Nuru".
struct FeaturedCell: Codable, Sendable {
    let cellGroupId: String
    let name: String
    let disciplerName: String?
    let disciplerRole: String?
    let focus: String?
    let levelLabel: String?
    let meets: String?
    let room: String?
    let nextSession: String?
    let tone: String?
    let imageUrl: String?
    let members: Int
}

/// GET /home/disciplers — "Meet your discipler" carousel.
struct Discipler: Codable, Sendable, Identifiable {
    let userId: String
    let fullName: String
    let message: String?
    let avatarUrl: String?
    let cellName: String?
    let roleLabel: String
    var id: String { userId }
}

/// GET /me/cell-summary — the member's cell card.
struct CellSummary: Codable, Sendable {
    struct Cell: Codable, Sendable {
        struct Leader: Codable, Sendable { let name: String; let role: String?; let avatarUrl: String? }
        struct Attendance: Codable, Sendable { let attended: Int; let expected: Int }
        struct Next: Codable, Sendable { let startAt: String; let location: String? }
        let cellGroupId: String
        let name: String
        let members: Int
        let leader: Leader?
        let attendance: Attendance
        let next: Next?
    }
    let cell: Cell?
}

/// GET /me/announcements.
struct MyAnnouncement: Codable, Sendable, Identifiable {
    let announcementId: String
    let title: String
    let body: String
    let sentAt: String?
    let bannerExpiresAt: String?
    let primaryImageUrl: String?
    let galleryImageUrls: [String]?
    let videoUrl: String?
    let opened: Bool
    var id: String { announcementId }
}

/// GET /announcements/{id}.
struct AnnouncementDetail: Codable, Sendable {
    let announcementId: String
    let title: String
    let body: String
    let sentAt: String?
    let primaryImageUrl: String?
    let galleryImageUrls: [String]?
    let images: [String]
    let videoUrl: String?
    let opened: Bool
}

/// GET /home/featured-announcement.
struct FeaturedAnnouncement: Codable, Sendable {
    let announcementId: String
    let title: String
    let body: String
    let primaryImageUrl: String?
    let galleryImageUrls: [String]?
    let sentAt: String?
}

/// GET /moments — curated photo gallery.
struct Moment: Codable, Sendable, Identifiable {
    let momentId: String
    let imageUrl: String
    let caption: String?
    let tag: String?
    let createdAt: String
    var id: String { momentId }
}
