// Events / calendar DTOs — Swift mirrors of the event contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

struct EventAttendee: Codable, Sendable, Identifiable {
    let userId: String
    let fullName: String
    let avatarUrl: String?
    var id: String { userId }
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

/// POST /calendar/series/{id}/follow — toggle result for "Series you follow".
struct SeriesFollowResult: Codable, Sendable {
    let seriesId: String
    let following: Bool
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
}

/// GET /me/rsvps — the member's RSVPs.
struct MyRsvp: Codable, Sendable, Identifiable {
    let rsvpId: String
    let status: String
    let eventId: String
    let title: String
    let occursAt: String
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

/// POST /events/{id}/posts/{postId}/react — fresh counts + my reaction.
struct EventPostReactionResult: Codable, Sendable {
    let cheerCount: Int
    let loveCount: Int
    let myReaction: String?
}

/// POST /events/{id}/posts — creation receipt (idempotent on client_mutation_id).
struct EventPostCreateResult: Codable, Sendable {
    let postId: String
    let duplicate: Bool
}
