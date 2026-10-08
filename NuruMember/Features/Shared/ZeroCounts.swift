// No zero counts (pathway docs/EXPERIENCE.md §7.4 #9, and the Cycle 3 part 2
// follow-up): a summary says only the counts that are above zero, and a
// summary with none says nothing — "0 updates across 0 spaces" told a member
// nothing. Pure; the tests pin each line. A count chip on a tab follows the
// same rule in its view (`if count > 0`), as Community's chips already did.
import Foundation

enum ZeroCounts {
    /// "3 updates", "1 update" — nil at zero.
    static func count(_ n: Int, _ one: String, _ many: String) -> String? {
        n > 0 ? "\(n) \(n == 1 ? one : many)" : nil
    }

    /// Community's assistant card: "The AI assistant · 3 updates across 2
    /// spaces" — the role alone when nothing is waiting.
    static func assistantLine(unread: Int, spaces: Int) -> String {
        guard let updates = count(unread, "update", "updates") else { return "The AI assistant" }
        guard let across = count(spaces, "space", "spaces") else { return "The AI assistant · \(updates)" }
        return "The AI assistant · \(updates) across \(across)"
    }

    /// Home's prayer card pill: "4 praying · 2 replies" — nil (no pill) when
    /// no one has prayed or replied yet.
    static func prayerLine(praying: Int, replies: Int) -> String? {
        let parts = [count(praying, "praying", "praying"), count(replies, "reply", "replies")].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The prayer journal's header: "3 ACTIVE · 1 ANSWERED" — nil when the
    /// journal is empty.
    static func journalHeader(active: Int, answered: Int) -> String? {
        let parts = [active > 0 ? "\(active) ACTIVE" : nil, answered > 0 ? "\(answered) ANSWERED" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The calendar's header: "12 upcoming · October 2026", or the month alone.
    static func calendarHeader(upcoming: Int, month: String) -> String {
        count(upcoming, "upcoming", "upcoming").map { "\($0) · \(month)" } ?? month
    }

    /// A broadcaster's closing line: "You were live for 4:12 · peak 9
    /// watching" — the time alone when nobody watched.
    static func liveSummary(duration: String, peak: Int) -> String {
        guard peak > 0 else { return "You were live for \(duration)" }
        return "You were live for \(duration) · peak \(peak) watching"
    }
}
