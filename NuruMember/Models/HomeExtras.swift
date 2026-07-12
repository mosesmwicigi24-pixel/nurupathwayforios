// Home / media / announcement DTOs — Swift mirrors of the contract in
// packages/mobile/src/api/types.ts so Home can load every real card, image and
// video. Decoded with `.convertFromSnakeCase`.
import Foundation

struct ContentReaction: Codable, Sendable, Hashable {
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

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the hand-built videos in HomeView / ModuleView.
extension WelcomeVideo {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        mediaAssetId = (try? c.decodeIfPresent(String.self, forKey: .mediaAssetId)) ?? ""
        videoSource = (try? c.decodeIfPresent(String.self, forKey: .videoSource)) ?? "direct"
        caption = try? c.decodeIfPresent(String.self, forKey: .caption)
        durationSec = try? c.decodeIfPresent(Int.self, forKey: .durationSec)
        thumbnailUrl = try? c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
        reactions = try? c.decodeIfPresent([ContentReaction].self, forKey: .reactions)
        loveCount = try? c.decodeIfPresent(Int.self, forKey: .loveCount)
        liked = try? c.decodeIfPresent(Bool.self, forKey: .liked)
        externalUrl = try? c.decodeIfPresent(String.self, forKey: .externalUrl)
        externalVideoId = try? c.decodeIfPresent(String.self, forKey: .externalVideoId)
        url = try? c.decodeIfPresent(String.self, forKey: .url)
        expiresAt = try? c.decodeIfPresent(String.self, forKey: .expiresAt)
    }
}

/// POST /media/{id}/reactions.
struct ReactionToggleResult: Codable, Sendable {
    let on: Bool
    let reactions: [ContentReaction]
    let loveCount: Int
    let liked: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        on = (try? c.decodeIfPresent(Bool.self, forKey: .on)) ?? false
        reactions = (try? c.decodeIfPresent([ContentReaction].self, forKey: .reactions)) ?? []
        loveCount = (try? c.decodeIfPresent(Int.self, forKey: .loveCount)) ?? 0
        liked = (try? c.decodeIfPresent(Bool.self, forKey: .liked)) ?? false
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cellGroupId = (try? c.decodeIfPresent(String.self, forKey: .cellGroupId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        disciplerName = try? c.decodeIfPresent(String.self, forKey: .disciplerName)
        disciplerRole = try? c.decodeIfPresent(String.self, forKey: .disciplerRole)
        focus = try? c.decodeIfPresent(String.self, forKey: .focus)
        levelLabel = try? c.decodeIfPresent(String.self, forKey: .levelLabel)
        meets = try? c.decodeIfPresent(String.self, forKey: .meets)
        room = try? c.decodeIfPresent(String.self, forKey: .room)
        nextSession = try? c.decodeIfPresent(String.self, forKey: .nextSession)
        tone = try? c.decodeIfPresent(String.self, forKey: .tone)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        members = (try? c.decodeIfPresent(Int.self, forKey: .members)) ?? 0
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        cellName = try? c.decodeIfPresent(String.self, forKey: .cellName)
        roleLabel = (try? c.decodeIfPresent(String.self, forKey: .roleLabel)) ?? ""
    }
}

/// GET /growth/mentor — the member's assigned discipler + meeting notes.
struct MentorInfo: Codable, Sendable {
    struct Mentor: Codable, Sendable {
        let mentorUserId: String
        let fullName: String
        let avatarUrl: String?
        let cellName: String?
        let establishedAt: String?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            mentorUserId = try c.decode(String.self, forKey: .mentorUserId)
            fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
            avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
            cellName = try? c.decodeIfPresent(String.self, forKey: .cellName)
            establishedAt = try? c.decodeIfPresent(String.self, forKey: .establishedAt)
        }
    }
    struct Note: Codable, Sendable, Identifiable {
        let noteId: String
        let topic: String?
        let note: String
        let metAt: String?
        let nextMeetingAt: String?
        var id: String { noteId }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            noteId = try c.decode(String.self, forKey: .noteId)
            topic = try? c.decodeIfPresent(String.self, forKey: .topic)
            note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? ""
            metAt = try? c.decodeIfPresent(String.self, forKey: .metAt)
            nextMeetingAt = try? c.decodeIfPresent(String.self, forKey: .nextMeetingAt)
        }
    }
    let mentor: Mentor?
    let nextMeetingAt: String?
    let notes: [Note]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        mentor = try? c.decodeIfPresent(Mentor.self, forKey: .mentor)
        nextMeetingAt = try? c.decodeIfPresent(String.self, forKey: .nextMeetingAt)
        notes = (try? c.decodeIfPresent([Note].self, forKey: .notes)) ?? []
    }
}

/// GET /me/cell-summary — the member's cell card.
struct CellSummary: Codable, Sendable {
    struct Cell: Codable, Sendable {
        struct Leader: Codable, Sendable {
            let name: String
            let role: String?
            let avatarUrl: String?
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
                role = try? c.decodeIfPresent(String.self, forKey: .role)
                avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
            }
        }
        struct Attendance: Codable, Sendable { let attended: Int; let expected: Int }
        struct Next: Codable, Sendable {
            let startAt: String
            let location: String?
            init(from d: Decoder) throws {
                let c = try d.container(keyedBy: CodingKeys.self)
                startAt = (try? c.decodeIfPresent(String.self, forKey: .startAt)) ?? ""
                location = try? c.decodeIfPresent(String.self, forKey: .location)
            }
        }
        let cellGroupId: String
        let name: String
        let members: Int
        let leader: Leader?
        let attendance: Attendance
        let next: Next?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            cellGroupId = (try? c.decodeIfPresent(String.self, forKey: .cellGroupId)) ?? ""
            name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
            members = (try? c.decodeIfPresent(Int.self, forKey: .members)) ?? 0
            leader = try? c.decodeIfPresent(Leader.self, forKey: .leader)
            attendance = (try? c.decodeIfPresent(Attendance.self, forKey: .attendance))
                ?? Attendance(attended: 0, expected: 0)
            next = try? c.decodeIfPresent(Next.self, forKey: .next)
        }
    }
    let cell: Cell?
}

// Tolerant decoding in an extension so the memberwise init stays available for
// the sparse-payload fallback above.
extension CellSummary.Cell.Attendance {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        attended = (try? c.decodeIfPresent(Int.self, forKey: .attended)) ?? 0
        expected = (try? c.decodeIfPresent(Int.self, forKey: .expected)) ?? 0
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        announcementId = try c.decode(String.self, forKey: .announcementId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        sentAt = try? c.decodeIfPresent(String.self, forKey: .sentAt)
        bannerExpiresAt = try? c.decodeIfPresent(String.self, forKey: .bannerExpiresAt)
        primaryImageUrl = try? c.decodeIfPresent(String.self, forKey: .primaryImageUrl)
        galleryImageUrls = try? c.decodeIfPresent([String].self, forKey: .galleryImageUrls)
        videoUrl = try? c.decodeIfPresent(String.self, forKey: .videoUrl)
        opened = (try? c.decodeIfPresent(Bool.self, forKey: .opened)) ?? false
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        announcementId = try c.decode(String.self, forKey: .announcementId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        sentAt = try? c.decodeIfPresent(String.self, forKey: .sentAt)
        primaryImageUrl = try? c.decodeIfPresent(String.self, forKey: .primaryImageUrl)
        galleryImageUrls = try? c.decodeIfPresent([String].self, forKey: .galleryImageUrls)
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
        videoUrl = try? c.decodeIfPresent(String.self, forKey: .videoUrl)
        opened = (try? c.decodeIfPresent(Bool.self, forKey: .opened)) ?? false
    }
}

/// GET /home/featured-announcement.
struct FeaturedAnnouncement: Codable, Sendable {
    let announcementId: String
    let title: String
    let body: String
    let primaryImageUrl: String?
    let galleryImageUrls: [String]?
    let sentAt: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        announcementId = try c.decode(String.self, forKey: .announcementId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        primaryImageUrl = try? c.decodeIfPresent(String.self, forKey: .primaryImageUrl)
        galleryImageUrls = try? c.decodeIfPresent([String].self, forKey: .galleryImageUrls)
        sentAt = try? c.decodeIfPresent(String.self, forKey: .sentAt)
    }
}

/// GET /moments — curated photo gallery.
struct Moment: Codable, Sendable, Identifiable {
    let momentId: String
    let imageUrl: String
    let caption: String?
    let tag: String?
    let createdAt: String
    var id: String { momentId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        momentId = try c.decode(String.self, forKey: .momentId)
        imageUrl = (try? c.decodeIfPresent(String.self, forKey: .imageUrl)) ?? ""
        caption = try? c.decodeIfPresent(String.self, forKey: .caption)
        tag = try? c.decodeIfPresent(String.self, forKey: .tag)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
}
