// Wave 3 — footprints on the trail + Your Walk.
//   • GET modules/{id}/footprints — cell-mates who already completed this
//     module (faces + when), so nobody reads alone.
//   • GET me/walk — the member's whole journey as one descending thread of
//     real events (began, modules, reflections, levels, certificates,
//     verses, plans, badges). Counted server-side, never guessed.
import Foundation

struct Footprint: Codable, Sendable {
    let firstName: String
    let avatarUrl: String?
    let completedAt: String
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        firstName = (try? c.decodeIfPresent(String.self, forKey: .firstName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        completedAt = (try? c.decodeIfPresent(String.self, forKey: .completedAt)) ?? ""
    }
}

struct FootprintsRes: Codable, Sendable {
    let count: Int
    let scope: String            // "cell" | "congregation"
    let footprints: [Footprint]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? "cell"
        footprints = (try? c.decodeIfPresent([Footprint].self, forKey: .footprints)) ?? []
    }
}

struct WalkEvent: Codable, Sendable, Identifiable {
    let kind: String             // began|module|reflection|level|certificate|verse|plan|badge
    let title: String
    let detail: String?
    let quote: String?
    let occurredAt: String

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        detail = try? c.decodeIfPresent(String.self, forKey: .detail)
        quote = try? c.decodeIfPresent(String.self, forKey: .quote)
        occurredAt = (try? c.decodeIfPresent(String.self, forKey: .occurredAt)) ?? ""
    }

    var id: String { "\(kind)-\(title)-\(occurredAt)" }

    /// "Mon 5 Oct" — the year only when it isn't this year (§8.1 rule 8; it
    /// read "5 Oct 2026").
    var dateLine: String { Self.dateLine(occurredAt) }

    static func dateLine(_ occurredAt: String, now: Date = Date(), timeZone: TimeZone = .current) -> String {
        if let d = NuruDates.parse(occurredAt) { return NuruDates.day(d, now: now, timeZone: timeZone) }
        // A Postgres timestamp ("2026-10-05 09:12:44.123+03") or a bare day:
        // the calendar day it names.
        let ymd = String(occurredAt.prefix(10))
        guard PledgeMath.isDay(ymd), let d = PauseDates.date(ymd) else { return "" }
        return NuruDates.day(d, now: now, timeZone: GiveCalendar.nairobi)
    }

    /// The title with its quotation marks curled ("Finished “Fear Not”") —
    /// the server writes straight ones (§8.1 rule 3's type, final walk #12).
    var shownTitle: String { NuruQuotes.curl(title) }
}

/// Straight double quotes, curled: an opening mark after a space, a bracket
/// or the start; a closing mark otherwise. Server text keeps its words.
enum NuruQuotes {
    static func curl(_ s: String) -> String {
        guard s.contains("\"") else { return s }
        var out = ""
        var prev: Character? = nil
        for ch in s {
            if ch == "\"" {
                let opens = prev == nil || prev!.isWhitespace || "([{\u{2014}\u{2013}-".contains(prev!)
                out.append(opens ? "\u{201C}" : "\u{201D}")
            } else {
                out.append(ch)
            }
            prev = ch
        }
        return out
    }
}

struct WalkRes: Codable, Sendable {
    let data: [WalkEvent]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        data = (try? c.decodeIfPresent([WalkEvent].self, forKey: .data)) ?? []
    }
}

extension MemberAPI {
    static func footprints(moduleId: String) async throws -> FootprintsRes {
        try await APIClient.shared.get("modules/\(moduleId)/footprints", as: FootprintsRes.self)
    }

    static func myWalk() async throws -> [WalkEvent] {
        try await APIClient.shared.get("me/walk", as: WalkRes.self).data
    }
}
