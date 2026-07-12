// Events / calendar DTOs — Swift mirrors of the event contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

struct EventAttendee: Codable, Sendable, Identifiable {
    let userId: String
    let fullName: String
    let avatarUrl: String?
    var id: String { userId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
    }
}

/// GET /calendar — one scheduled occurrence in the window.
struct CalendarOccurrence: Codable, Sendable, Identifiable, Hashable {
    let occurrenceId: String
    let seriesId: String
    let title: String
    let description: String?
    let location: String?
    let category: String?
    let primaryImageUrl: String?
    let startAt: String
    let endAt: String
    // Wire truth (calendar/service.ts projectRange): cancelled occurrences are
    // dropped server-side; a moved one arrives with rescheduled=true and the new
    // start/end already applied. status is the series status (draft|active).
    let status: String?
    let rescheduled: Bool?
    let going: Int
    let attendees: [EventAttendee]?

    var id: String { occurrenceId }

    static func == (a: CalendarOccurrence, b: CalendarOccurrence) -> Bool { a.occurrenceId == b.occurrenceId }
    func hash(into h: inout Hasher) { h.combine(occurrenceId) }

    private enum CodingKeys: String, CodingKey {
        case occurrenceId, seriesId, title, description, location, category
        case primaryImageUrl, startAt, endAt, status, rescheduled, going, attendees
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        occurrenceId = try c.decode(String.self, forKey: .occurrenceId)
        seriesId = (try? c.decodeIfPresent(String.self, forKey: .seriesId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        primaryImageUrl = try? c.decodeIfPresent(String.self, forKey: .primaryImageUrl)
        startAt = (try? c.decodeIfPresent(String.self, forKey: .startAt)) ?? ""
        endAt = (try? c.decodeIfPresent(String.self, forKey: .endAt)) ?? ""
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        rescheduled = try? c.decodeIfPresent(Bool.self, forKey: .rescheduled)
        going = (try? c.decodeIfPresent(Int.self, forKey: .going)) ?? 0
        attendees = try? c.decodeIfPresent([EventAttendee].self, forKey: .attendees)
    }
}

/// GET /calendar/series — a followable event series (Events "Series you follow").
struct EventSeries: Codable, Sendable, Identifiable {
    let seriesId: String
    let title: String
    let category: String?
    let cadence: String
    let nextAt: String?
    let nextOccurrenceId: String?
    let nextEndAt: String?
    let location: String?
    let following: Bool
    let newCount: Int
    var id: String { seriesId }
}

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the optimistic follow-toggle in EventsView.
extension EventSeries {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        seriesId = try c.decode(String.self, forKey: .seriesId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        cadence = (try? c.decodeIfPresent(String.self, forKey: .cadence)) ?? ""
        nextAt = try? c.decodeIfPresent(String.self, forKey: .nextAt)
        nextOccurrenceId = try? c.decodeIfPresent(String.self, forKey: .nextOccurrenceId)
        nextEndAt = try? c.decodeIfPresent(String.self, forKey: .nextEndAt)
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        following = (try? c.decodeIfPresent(Bool.self, forKey: .following)) ?? false
        newCount = (try? c.decodeIfPresent(Int.self, forKey: .newCount)) ?? 0
    }
}

/// POST /calendar/series/{id}/follow — toggle result for "Series you follow".
struct SeriesFollowResult: Codable, Sendable {
    let seriesId: String
    let following: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        seriesId = (try? c.decodeIfPresent(String.self, forKey: .seriesId)) ?? ""
        following = (try? c.decodeIfPresent(Bool.self, forKey: .following)) ?? false
    }
}

/// GET /home/featured-event — the admin-featured event anchoring the hero.
struct FeaturedEvent: Codable, Sendable {
    let seriesId: String
    let title: String
    let description: String?
    let location: String?
    let category: String?
    let primaryImageUrl: String?
    let dtstartLocal: String
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        seriesId = (try? c.decodeIfPresent(String.self, forKey: .seriesId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        primaryImageUrl = try? c.decodeIfPresent(String.self, forKey: .primaryImageUrl)
        dtstartLocal = (try? c.decodeIfPresent(String.self, forKey: .dtstartLocal)) ?? ""
    }
}

/// GET /events/{id} — full detail with RSVP state + roster.
struct EventDetail: Codable, Sendable {
    struct RsvpCounts: Codable, Sendable { let going: Int?; let maybe: Int?; let declined: Int? }
    let eventId: String
    let title: String
    let occursAt: String
    let description: String?
    let location: String?
    let category: String?
    let primaryImageUrl: String?
    /// Wire truth (calendar/service.ts getEvent): [primary, …gallery] — feeds the
    /// detail gallery. primaryImageUrl stays for the hero fallback.
    let images: [String]?
    let videoUrl: String?
    let rsvpCounts: RsvpCounts
    let myRsvp: String?
    let attendees: [EventAttendee]?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        eventId = try c.decode(String.self, forKey: .eventId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        occursAt = (try? c.decodeIfPresent(String.self, forKey: .occursAt)) ?? ""
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        location = try? c.decodeIfPresent(String.self, forKey: .location)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        primaryImageUrl = try? c.decodeIfPresent(String.self, forKey: .primaryImageUrl)
        images = try? c.decodeIfPresent([String].self, forKey: .images)
        videoUrl = try? c.decodeIfPresent(String.self, forKey: .videoUrl)
        rsvpCounts = (try? c.decodeIfPresent(RsvpCounts.self, forKey: .rsvpCounts))
            ?? RsvpCounts(going: nil, maybe: nil, declined: nil)
        myRsvp = try? c.decodeIfPresent(String.self, forKey: .myRsvp)
        attendees = try? c.decodeIfPresent([EventAttendee].self, forKey: .attendees)
    }
}

/// GET /me/rsvps — the member's RSVPs.
struct MyRsvp: Codable, Sendable, Identifiable {
    let rsvpId: String
    let status: String
    let eventId: String
    let title: String
    /// Null when the series has no next occurrence — one such row must not
    /// sink the whole list (it did: strict decode + try? upstream).
    let occursAt: String?
    var id: String { rsvpId }
}

/// GET /events/{id}/posts — one buzz post on the event wall ("Who's coming").
/// Reaction fields are `var` so the screen can apply optimistic updates.
struct EventPost: Codable, Sendable, Identifiable {
    let postId: String
    let authorUserId: String
    let authorName: String
    let authorAvatar: String?
    let body: String?
    let imageUrl: String?
    let createdAt: String
    let mine: Bool
    let rsvpStatus: String?
    var cheerCount: Int
    var loveCount: Int
    var myReaction: String?   // "cheer" | "love" | nil
    var id: String { postId }
}

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the optimistic insert in EventDetailView.
extension EventPost {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        postId = try c.decode(String.self, forKey: .postId)
        authorUserId = (try? c.decodeIfPresent(String.self, forKey: .authorUserId)) ?? ""
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
        rsvpStatus = try? c.decodeIfPresent(String.self, forKey: .rsvpStatus)
        cheerCount = (try? c.decodeIfPresent(Int.self, forKey: .cheerCount)) ?? 0
        loveCount = (try? c.decodeIfPresent(Int.self, forKey: .loveCount)) ?? 0
        myReaction = try? c.decodeIfPresent(String.self, forKey: .myReaction)
    }
}

/// POST /events/{id}/posts/{postId}/react — fresh counts + my reaction.
struct EventPostReactionResult: Codable, Sendable {
    let cheerCount: Int
    let loveCount: Int
    let myReaction: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cheerCount = (try? c.decodeIfPresent(Int.self, forKey: .cheerCount)) ?? 0
        loveCount = (try? c.decodeIfPresent(Int.self, forKey: .loveCount)) ?? 0
        myReaction = try? c.decodeIfPresent(String.self, forKey: .myReaction)
    }
}

/// POST /events/{id}/posts — creation receipt (idempotent on client_mutation_id).
struct EventPostCreateResult: Codable, Sendable {
    let postId: String
    let duplicate: Bool
}
