// The one way the app writes a date (EXPERIENCE.md §8.1 rule 8). The Cycle 3
// walk found eleven shapes for the same kind of fact (E16): "Sun, Oct 25",
// "Oct 5, 2026", "MON, 5 OCT 2026", "5 October 2026 · 11:59 AM", "paid
// 27 September"… YOUR WEEK's shape is the one: day first and short —
// "Sun 11 Oct" — with the year only when it isn't this year ("Fri 1 Jan
// 2027"), a time "9:00 AM", together "Sun 11 Oct · 9:00 AM".
import Foundation

enum NuruDates {
    /// An API timestamp, with or without fractional seconds.
    static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// "Sun 11 Oct"; "Fri 1 Jan 2027" when the year isn't this year — or
    /// always, `withYear`, for a record kept (a receipt's date).
    static func day(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current, withYear: Bool = false) -> String {
        format(date, !withYear && sameYear(date, now, timeZone) ? "EEE d MMM" : "EEE d MMM yyyy", timeZone)
    }

    /// "9:00 AM".
    static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, "h:mm a", timeZone)
    }

    /// "Sun 11 Oct · 9:00 AM".
    static func dayTime(_ date: Date, now: Date = Date(), timeZone: TimeZone = .current, withYear: Bool = false) -> String {
        "\(day(date, now: now, timeZone: timeZone, withYear: withYear)) · \(time(date, timeZone: timeZone))"
    }

    /// "October 2026" — a month heading, not a day.
    static func month(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, "MMMM yyyy", timeZone)
    }

    /// "Sunday 4 October 2026" — the Sunday Letter's dateline, set in full
    /// under its masthead as a printed letter's is (owner, 2026-10-07: the
    /// editorial letter, board A). The one long shape; every other day in the
    /// app stays "Sun 4 Oct".
    static func dateline(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, "EEEE d MMMM yyyy", timeZone)
    }

    private static func sameYear(_ a: Date, _ b: Date, _ timeZone: TimeZone) -> Bool {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        return cal.component(.year, from: a) == cal.component(.year, from: b)
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        lock.lock(); defer { lock.unlock() }
        let key = pattern + "|" + timeZone.identifier
        let f: DateFormatter
        if let hit = cache[key] {
            f = hit
        } else {
            f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = pattern
            cache[key] = f
        }
        return f.string(from: date)
    }
}
