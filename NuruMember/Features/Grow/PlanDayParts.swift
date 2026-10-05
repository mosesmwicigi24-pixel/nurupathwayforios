// The parts of a plan day (pathway docs/EXPERIENCE.md §7.4 #2, #4) — ONE
// grouping for the day hub's rows, the plan page's "1 part left" and the
// Plans streak card's "Today: 2 of 3 parts", so the three never count a day
// differently. Pure: no views, no network; the tests pin it. Android groups
// the same way: each Watch / Listen alone · The Word (Scripture, teaching,
// Go Deeper) · Respond (the prayer) · Talk it Over — and a part is done when
// every one of its segments is.
import Foundation

enum PlanDayParts {
    enum Kind: Equatable { case media, word, respond, talk }

    struct Part: Equatable {
        /// The media segment's own id, else "word" / "respond" / "talk".
        let id: String
        let kind: Kind
        let segments: [PlanSegment]
        /// Where the part starts in `ordered(_:)` — the reader's index.
        let firstIndex: Int
    }

    /// The study flow: watch/listen first (media sets the scene), then the
    /// Word (Scripture), the teaching, Talk it Over, the prayer, and Go
    /// Deeper for the hungry.
    static func rank(_ s: PlanSegment) -> Int {
        switch s.kind.lowercased() {
        case "video", "audio": return 0
        case "scripture": return 1
        case "talk": return 3
        case "reading": return 5
        default: return s.title.lowercased().hasPrefix("pray") ? 4 : 2   // Pray after Talk; teaching before
        }
    }

    /// The segments in study order — stable within a rank (the authored sort
    /// breaks ties).
    static func ordered(_ segments: [PlanSegment]) -> [PlanSegment] {
        segments.sorted { rank($0) == rank($1) ? $0.sort < $1.sort : rank($0) < rank($1) }
    }

    /// The day's parts in the hub's order: each video or audio alone, then
    /// The Word, Respond, and Talk it Over (the family's conversation stands
    /// alone).
    static func parts(_ segments: [PlanSegment]) -> [Part] {
        let segs = ordered(segments)
        var out: [Part] = []
        for (i, s) in segs.enumerated() where rank(s) == 0 {
            out.append(Part(id: s.segmentId, kind: .media, segments: [s], firstIndex: i))
        }
        let groups: [(id: String, kind: Kind, ranks: Set<Int>)] = [
            ("word", .word, [1, 2, 5]), ("respond", .respond, [4]), ("talk", .talk, [3]),
        ]
        for (id, kind, ranks) in groups {
            let hit = segs.enumerated().filter { ranks.contains(rank($0.element)) }
            if let first = hit.first {
                out.append(Part(id: id, kind: kind, segments: hit.map(\.element), firstIndex: first.offset))
            }
        }
        return out
    }

    /// Parts done of all. `alsoDone`: segments finished this session, ahead
    /// of the next fetch.
    static func progress(_ segments: [PlanSegment], alsoDone: Set<String> = []) -> (done: Int, total: Int) {
        let all = parts(segments)
        let done = all.filter { p in p.segments.allSatisfy { $0.completed || alsoDone.contains($0.segmentId) } }
        return (done.count, all.count)
    }

    /// The pill on the day the member is on, on the plan's page (§7.4 #2):
    /// "1 part left" once the day is begun, "Start" before.
    static func pill(_ segments: [PlanSegment]) -> String {
        let p = progress(segments)
        let left = p.total - p.done
        guard p.done > 0, left > 0 else { return "Start" }
        return left == 1 ? "1 part left" : "\(left) parts left"
    }

    /// The Plans streak card's line while today's day is under way (§7.4 #4):
    /// "Today: 2 of 3 parts". Nil before the first part (the card keeps its
    /// invitation) and once the day is done.
    static func todayLine(done: Int, total: Int) -> String? {
        guard done > 0, done < total else { return nil }
        return "Today: \(done) of \(total) parts"
    }

    /// The plan page's gold button (§7.4 #2): "Begin Day 1" until anything of
    /// the plan is done — a day, or any part of one; then "Continue · Day N",
    /// the day the member is on; "Read again" once every day is done.
    static func planButton(_ d: ReadingPlanDetail) -> String {
        let finished = d.days.filter { $0.completed == true }.count
        if !d.days.isEmpty && finished >= d.days.count { return "Read again" }
        let begun = finished > 0 || d.days.contains { ($0.segments ?? []).contains(where: \.completed) }
        return begun ? "Continue · Day \(d.continueDay?.dayNumber ?? 1)" : "Begin Day 1"
    }
}

/// The Plans streak card's "today" (EXPERIENCE.md §7.4 #4): a day finished
/// today on THIS phone (PlanDayLog — the instant tick, before the next
/// fetch), or on ANY phone — an enrolled plan whose `last_day_finished_at`
/// falls on today's Nairobi day. Pure; the tests pin the Nairobi midnight.
enum StreakToday {
    static func done(plans: [ReadingPlanRow], sealedHere: Bool, now: Date = Date()) -> Bool {
        sealedHere || finishedToday(plans, now: now)
    }

    /// Any enrolled plan's last finished day is today, on the church's
    /// (Nairobi) calendar — the same day the server's streak counts.
    static func finishedToday(_ plans: [ReadingPlanRow], now: Date = Date()) -> Bool {
        let today = PlanPicks.nairobiDay(now)
        return plans.contains { p in
            guard p.enrolled, let at = p.lastDayFinishedAt.flatMap(date) else { return false }
            return PlanPicks.nairobiDay(at) == today
        }
    }

    /// The server's ISO-8601 stamp, with or without fractional seconds.
    static func date(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

/// The Nairobi day on which this phone last saw the server seal a plan day
/// (§7.4 #4) — the Plans streak card ticks today only then. Written only
/// from the server's own answer (the last part's `day_complete`, or the
/// day's complete-day 200), never from a guess, and forgotten at sign-out so
/// the next member starts clean. A day sealed on another phone is not
/// ticked here: the card under-claims, it never ticks a day that wasn't.
enum PlanDayLog {
    static let key = "nuru.plans.daySealedOn"

    static func noteSealed(now: Date = Date(), in defaults: UserDefaults = .standard) {
        defaults.set(PlanPicks.nairobiDay(now), forKey: key)
    }

    static func sealedToday(now: Date = Date(), in defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: key) != nil else { return false }
        return defaults.integer(forKey: key) == PlanPicks.nairobiDay(now)
    }

    static func forget(in defaults: UserDefaults = .standard) { defaults.removeObject(forKey: key) }
}

extension PlanDayUnlockAck {
    /// The server sealed a day — the LAST part's ack says so, computed in the
    /// same transaction as the write. Tell the day hub and the plan page, and
    /// note the day for the streak card. Every part that can end a day (a
    /// part's "Finished", Talk it Over's post or its gold button) ends here.
    @MainActor
    static func announce(_ ack: SegmentCompleteResult, planId: String?) {
        guard ack.dayComplete else { return }
        PlanDayLog.noteSealed()
        NotificationCenter.default.post(
            name: .nuruPlanDayUnlocked,
            object: PlanDayUnlockAck(planId: planId, dayNumber: ack.dayNumber,
                                     nextDayNumber: ack.nextDayNumber, nextDayUnlocked: ack.nextDayUnlocked))
    }
}

/// One story about today for the plan being read, on Home and on Plans
/// (EXPERIENCE.md §9.2 #3): its day is "today's reading" only while today's
/// reading is still to do; once a day of it was finished today, it is done
/// for today and the next day waits — "Day 3 done today · Day 4 next". Home
/// said "Day 4 of 7 · today's reading" beside Plans' "Today's reading is
/// done". Pure; Android's planTodayLine / planCardLine, word for word.
enum PlanLines {
    /// The day to read — the server's `current_day` (it moves past every
    /// finished day, never beyond the last), else the one after the finished
    /// days; held to 1…the plan's length.
    static func day(_ p: ReadingPlanRow) -> Int {
        let raw = p.currentDay ?? ((p.completedDays?.count ?? 0) + 1)
        return min(max(1, raw), max(1, p.dayCount))
    }

    /// A day of this plan was finished today, on the church's (Nairobi)
    /// calendar — by the server's `last_day_finished_at` (any phone), or by
    /// this phone's own note of a day it sealed.
    static func readToday(_ p: ReadingPlanRow, sealedHere: Bool = false, now: Date = Date()) -> Bool {
        if sealedHere { return true }
        guard let at = p.lastDayFinishedAt.flatMap(StreakToday.date) else { return false }
        return PlanPicks.nairobiDay(at) == PlanPicks.nairobiDay(now)
    }

    /// Home's YOUR WEEK line.
    static func todayLine(_ p: ReadingPlanRow, readToday: Bool, now: Date = Date()) -> String {
        doneOrPausedLine(p, readToday: readToday, now: now) ?? "Day \(day(p)) of \(p.dayCount) · today's reading"
    }

    /// The Plans tab's continue card: the same story as Home's row, else
    /// "Today · " and the plan's own subtitle.
    static func cardLine(_ p: ReadingPlanRow, readToday: Bool, now: Date = Date()) -> String {
        if let line = doneOrPausedLine(p, readToday: readToday, now: now) { return line }
        let sub = (p.subtitle ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return "Today · " + (sub.isEmpty ? "Day \(day(p)) of \(p.dayCount)" : sub)
    }

    /// The day read today and the one that waits, in one breath.
    static func doneLine(_ p: ReadingPlanRow, readToday: Bool, now: Date = Date()) -> String? {
        guard readToday else { return nil }
        let d = day(p)
        return d > 1 ? "Day \(d - 1) done today · Day \(d) next" : "Done today · Day \(d) next"
    }

    /// The two lines Home and Plans share: today's day read, or a pause named.
    static func doneOrPausedLine(_ p: ReadingPlanRow, readToday: Bool, now: Date = Date()) -> String? {
        if let done = doneLine(p, readToday: readToday, now: now) { return done }
        return pausedOn(p, now: now).map { pauseLine(pausedOn: $0, waitingDay: day(p), now: now) }
    }

    /// When the member paused the plan (§9.1 rule 5): the moment its last day
    /// was finished, when that fell two or more church (Nairobi) days ago —
    /// not yesterday's reading, not today's. Nil while it's being read, once
    /// it's finished, and before any day is (the server says only when a day
    /// was finished).
    static func pausedOn(_ p: ReadingPlanRow, now: Date = Date()) -> Date? {
        guard p.enrolled, p.completedAt == nil,
              let at = p.lastDayFinishedAt.flatMap(StreakToday.date) else { return nil }
        return PlanPicks.nairobiDay(at) <= PlanPicks.nairobiDay(now) - 2 ? at : nil
    }

    /// A pause named kindly, once (EXPERIENCE.md §9.1 rule 5): when, and the
    /// day that waits — "You paused on Thursday — Day 2 is waiting" — never a
    /// count of days missed. The weekday within the week; "Thu 24 Sep"
    /// further back. Android's pauseLine, word for word.
    static func pauseLine(pausedOn at: Date, waitingDay: Int, now: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = GiveCalendar.nairobi
        f.dateFormat = PlanPicks.nairobiDay(now) - PlanPicks.nairobiDay(at) < 7 ? "EEEE" : "EEE d MMM"
        return "You paused on \(f.string(from: at)) — Day \(waitingDay) is waiting"
    }
}
