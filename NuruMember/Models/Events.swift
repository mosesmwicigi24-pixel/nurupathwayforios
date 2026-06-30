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
    let going: Int
    let attendees: [EventAttendee]?

    var id: String { occurrenceId }

    static func == (a: CalendarOccurrence, b: CalendarOccurrence) -> Bool { a.occurrenceId == b.occurrenceId }
    func hash(into h: inout Hasher) { h.combine(occurrenceId) }

    private enum CodingKeys: String, CodingKey {
        case occurrenceId, seriesId, title, description, location, category
        case primaryImageUrl, startAt, endAt, going, attendees
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
