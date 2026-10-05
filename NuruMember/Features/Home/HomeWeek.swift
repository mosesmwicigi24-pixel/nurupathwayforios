// YOUR WEEK (pathway docs/EXPERIENCE.md §6.1) — Home's one week block: five
// rows in the journey's order (Pathway · Plans · Events · Giving · Cell), each
// the next thing in that pillar, one line of when or where it stands, and the
// place a tap opens. Each pillar has one home; Home points to it once, here.
// (The "For you today" hero, the continue card, the minis, the plan banner,
// both cell cards and the upcoming list each told one of these stories again.)
//
// Pure (no views, no network): the tests pin every row's every form, and
// Android says the same words from the same table (YourWeek.kt). A row whose
// data failed to load (nil, or nothing) speaks in its "none" form — it never
// blocks the card. A row's forms are tried in the table's order; the first
// that holds shows. "This week" is today through the seventh day after, on
// the church's (Nairobi) clock — the server's own DUE window. Money keeps the
// Give code's own rules: which gift collects itself (PledgePace,
// ScheduleRhythm), so this row and Partners' DUE row never tell two stories.
import Foundation

struct HomeWeekRow: Equatable, Identifiable {
    enum Pillar: String, Equatable { case pathway, plans, events, giving, cell }

    /// Where a tap lands — the pillar's own home.
    enum Destination: Equatable {
        /// The journey's next step, inside the Pathway tab; nil = the tab itself.
        case journey(Journey.Destination?)
        /// That plan's day, inside the Plans tab (the plan's page as the back stop).
        case planDay(ReadingPlanRow)
        /// The plan catalogue — the Plans tab.
        case plans
        /// That gathering's page, inside the Events tab.
        case event(CalendarOccurrence)
        /// The Events tab.
        case events
        /// That pledge's page (Give ▸ Partners).
        case pledge(String)
        /// That recurring gift's sheet (Give).
        case schedule(String)
        /// Give ▸ Partners — the DUE list.
        case partners
        /// The Give form.
        case give
        /// The member's own cell page.
        case cell
        /// "Ask to be connected" — no cell yet (§9.2 #12).
        case cellConnect
        /// You ▸ Community.
        case community
    }

    let pillar: Pillar
    /// The next thing: "Take the Level 1 exam", the plan's title, "Give"…
    let title: String
    /// When or where it stands: "Level 1 · Exam ready", "Collected on Mon 5 Oct"…
    /// Empty only for a pathway that didn't load from a member not yet placed.
    let line: String
    let destination: Destination
    var id: Pillar { pillar }
}

enum HomeWeek {
    /// How far the week looks: today and the seven days after.
    static let weekDays = 7

    /// The five rows, in the journey's order.
    static func rows(journey: Journey?, enrolledLevel: Int?, plans: [ReadingPlanRow]?,
                     calendar: [CalendarOccurrence]?, homeEvents: [HomeEventRow]?, rsvps: [MyRsvp]?,
                     partnership: Partnership?, schedules: [GivingSchedule]?, railsLine: String,
                     cell: CellSummary.Cell?, cellAskedAt: String? = nil, planSealedHere: Bool = false,
                     now: Date = Date(), timeZone: TimeZone = GiveCalendar.nairobi) -> [HomeWeekRow] {
        [pathwayRow(journey, enrolledLevel: enrolledLevel),
         plansRow(plans, sealedHere: planSealedHere, now: now),
         eventsRow(calendar: calendar, home: homeEvents, rsvps: rsvps, now: now, timeZone: timeZone),
         givingRow(partnership: partnership, schedules: schedules, railsLine: railsLine, now: now),
         cellRow(cell, askedAt: cellAskedAt, timeZone: timeZone, now: now)]
    }

    /// Support God's work shows only while the week's giving row is "Give" —
    /// a member already giving isn't asked twice (§6.1, 7).
    static func asksToGive(_ rows: [HomeWeekRow]) -> Bool {
        rows.first { $0.pillar == .giving }?.destination == .give
    }

    /// "What needs you today" never repeats a YOUR WEEK row (EXPERIENCE.md
    /// §9.1 rule 3): a server nudge that points where a row already points —
    /// the exam the Pathway row offers, the plan day the Plans row opens, the
    /// cell the Cell row opens, the test inside the module the Pathway row
    /// continues — is the same ask twice on one page ("Take the Level 1
    /// exam" over "Take the Level 1 exam"). The row keeps it; the rail drops
    /// it. Reflection, the letter, invites and messages are no row's — they
    /// stay. Android's YourWeek.repeats, the same rule.
    static func repeats(_ n: HomeNudge, in week: [HomeWeekRow]) -> Bool {
        let key = n.route.isEmpty ? n.kind : n.route
        let p = n.params
        switch key {
        case "level_exam", "level_review":
            guard let level = p?.levelNumber else { return false }
            return week.contains { $0.destination == .journey(.exam(level)) }
        case "plan", "plan_day_due":
            guard let id = p?.planId, !id.isEmpty else { return false }
            return week.contains { if case .planDay(let plan) = $0.destination { return plan.planId == id }; return false }
        case "cell", "cell_gathering":
            return week.contains { $0.destination == .cell }
        case "quiz", "quiz_in_progress":
            guard let id = p?.moduleId, !id.isEmpty else { return false }
            return week.contains { $0.destination == .journey(.module(id)) }
        default:
            return false
        }
    }

    // MARK: Pathway — always

    /// The journey's next step (EXPERIENCE.md §3): its title, "Level N · " +
    /// the header pill, and its own destination — a step with nothing to tap
    /// (the exam not yet open, a level being prepared) opens the Pathway tab.
    /// Without the journey (it didn't load — Home's strip says why): "Your
    /// pathway" and the member's level alone, when known.
    static func pathwayRow(_ j: Journey?, enrolledLevel: Int?) -> HomeWeekRow {
        guard let j else {
            return HomeWeekRow(pillar: .pathway, title: "Open your pathway", line: enrolledLevel.map { "Level \($0)" } ?? "",
                               destination: .journey(nil))
        }
        // Each row says its verb (EXPERIENCE.md §9.1 rule 3): a lesson to read
        // is "Continue · God's Plan for Humanity"; a level not yet begun is
        // "Start Level 1 · God & His Nature" — a first day leads with the
        // path's first step (rule 4). The other stages' titles are their own
        // verbs or facts ("Take the Level 1 exam", "Level 2 is being prepared").
        let title: String
        if j.stage == .learning, j.destination != nil, j.totalModules > 0 {
            title = j.completedModules == 0 ? "Start Level \(j.levelNumber) · \(j.title)" : "Continue · \(j.title)"
        } else {
            title = j.title
        }
        return HomeWeekRow(pillar: .pathway, title: title, line: "Level \(j.levelNumber) · \(j.pill)",
                           destination: .journey(j.destination))
    }

    // MARK: Plans

    /// The plan being read (ReadingPlanRow.active — the same one the Plans
    /// tab continues first and its header names), opening its day; else the
    /// invitation to start one. Its line is the one story about today
    /// (PlanLines, §9.2 #3): "Day 3 done today · Day 4 next" once today's day
    /// is read — this phone sealed it (`sealedHere`) or any phone did.
    static func plansRow(_ plans: [ReadingPlanRow]?, sealedHere: Bool = false, now: Date = Date()) -> HomeWeekRow {
        guard let p = ReadingPlanRow.active(in: plans ?? []) else {
            return HomeWeekRow(pillar: .plans, title: "Start a reading plan",
                               line: "A few minutes a day — with the whole family of God.", destination: .plans)
        }
        let read = PlanLines.readToday(p, sealedHere: sealedHere, now: now)
        // Its verb (§9.1 rule 3): "Done today ·" once today's day is read,
        // "Start ·" before the first day, "Continue ·" between.
        let verb = read ? "Done today" : ((p.completedDays ?? []).isEmpty && PlanLines.day(p) == 1 ? "Start" : "Continue")
        return HomeWeekRow(pillar: .plans, title: "\(verb) · \(p.title)", line: PlanLines.todayLine(p, readToday: read, now: now),
                           destination: .planDay(p))
    }

    // MARK: Events

    /// This week (from now through the seventh day after): the soonest
    /// gathering the member is going to, "EEE d MMM · h:mm a · You're going";
    /// else the soonest they have not said no to (one they declined only when
    /// nothing else is on); else "No gatherings this week". The gatherings
    /// are the church calendar Home reads (it carries the end the event page
    /// needs), its curated rows and the member's RSVPs — their own answers
    /// have the last word.
    static func eventsRow(calendar: [CalendarOccurrence]?, home: [HomeEventRow]?, rsvps: [MyRsvp]?,
                          now: Date, timeZone: TimeZone) -> HomeWeekRow {
        struct Gathering { let occ: CalendarOccurrence; let title: String; let start: Date; var rsvp: String? }
        var order: [String] = []
        var byId: [String: Gathering] = [:]
        func put(_ id: String, _ g: Gathering) {
            if byId[id] == nil { order.append(id) }
            byId[id] = g
        }
        for o in calendar ?? [] {
            guard let start = parse(o.startAt) else { continue }
            put(o.occurrenceId, Gathering(occ: o, title: o.title, start: start, rsvp: nil))
        }
        for e in home ?? [] {
            let known = byId[e.occurrenceId]
            guard let start = known?.start ?? parse(e.startsAt) else { continue }
            let title = known.flatMap { $0.title.isEmpty ? nil : $0.title } ?? e.title
            put(e.occurrenceId, Gathering(occ: known?.occ ?? CalendarOccurrence(homeEvent: e), title: title,
                                          start: start, rsvp: e.myRsvp ?? known?.rsvp))
        }
        for r in rsvps ?? [] {
            let status = r.status.trimmingCharacters(in: .whitespaces)
            guard !status.isEmpty else { continue }
            if var known = byId[r.eventId] {
                known.rsvp = status
                byId[r.eventId] = known
            } else if let start = r.occursAt.flatMap(parse) {
                put(r.eventId, Gathering(occ: CalendarOccurrence(rsvp: r), title: r.title, start: start, rsvp: status))
            }
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let lastDay = cal.date(byAdding: .day, value: weekDays, to: cal.startOfDay(for: now)) ?? now
        var inWeek: [(order: Int, gathering: Gathering)] = []
        for (i, id) in order.enumerated() {
            guard let g = byId[id], !g.title.isEmpty, g.start >= now, cal.startOfDay(for: g.start) <= lastDay else { continue }
            inWeek.append((i, g))
        }
        // Soonest first; a tie keeps the order the reads gave.
        inWeek.sort { a, b in
            if a.gathering.start != b.gathering.start { return a.gathering.start < b.gathering.start }
            return a.order < b.order
        }
        let week = inWeek.map { $0.gathering }
        // Each row says its verb (§9.1 rule 3): "Going ·" a gathering the
        // member said yes to, "Join ·" one they haven't answered, and "See the
        // church calendar" in a quiet week.
        if let g = week.first(where: { $0.rsvp?.lowercased() == "going" }) {
            return HomeWeekRow(pillar: .events, title: "Going · \(g.title)", line: when(g.start, timeZone),
                               destination: .event(g.occ))
        }
        if let g = week.first(where: { $0.rsvp?.lowercased() != "declined" }) ?? week.first {
            return HomeWeekRow(pillar: .events, title: "Join · \(g.title)", line: when(g.start, timeZone), destination: .event(g.occ))
        }
        return HomeWeekRow(pillar: .events, title: "See the church calendar", line: "No gatherings this week",
                           destination: .events)
    }

    // MARK: Giving

    /// From GET /giving/partnership (its DUE rows and pledges) and GET
    /// /giving/schedules, in the table's order:
    /// 1. a running recurring gift — or a pledge's collector — prompts this
    ///    week asking for money: the pledge's title, or "Your weekly gift" /
    ///    "Your monthly gift"; "Collected on EEE d MMM"; its pledge / the
    ///    gift's sheet. A pledge whose instalment its collector does not
    ///    reach (paused, or prompting after the date) is not collected — it
    ///    is owed (2), exactly as Partners' DUE row says (§6.4);
    /// 2. the first instalment Partners lists to pay that no collector takes
    ///    (the server's DUE list — it decides what is due): the pledge's
    ///    title; "KSh X due EEE d MMM", "KSh X overdue since EEE d MMM" once
    ///    the server says it is late; Partners. Money already on its way is
    ///    never asked for twice — only the uncovered rest, and none at all
    ///    while every shilling of it is;
    /// 3. otherwise "Give" and the rails that work here; Give.
    /// Either read failed → "Give": nothing about a gift or a pledge is said
    /// on a guess.
    static func givingRow(partnership: Partnership?, schedules: [GivingSchedule]?, railsLine: String,
                          now: Date) -> HomeWeekRow {
        let give = HomeWeekRow(pillar: .giving, title: "Give", line: railsLine, destination: .give)
        guard let p = partnership, let gifts = schedules else { return give }
        let today = PauseDates.wire(now)
        func pledge(_ id: String) -> Pledge? { p.pledges.first { $0.pledgeId == id } }
        let owedByHand = p.due.filter { d in
            d.kind == "pledge" && d.action == "pay" && !d.fullyPending
                && PledgePace.collectedDay(d, by: pledge(d.id).flatMap { PledgePace.collector(of: $0, in: gifts) }) == nil
        }
        let owedIds = Set(owedByHand.map(\.id))

        // 1 · A gift that collects itself this week — the soonest.
        var soonest: (gift: GivingSchedule, day: String, pledgeId: String?)?
        for s in gifts where s.status.lowercased() == "active" {
            guard let at = giveParseDate(s.nextRunAt) else { continue }
            let day = PauseDates.wire(at)
            guard let n = days(from: today, to: day), (0...weekDays).contains(n) else { continue }
            let pledgeId = s.pledge?.pledgeId
                ?? p.pledges.first { !($0.scheduleId ?? "").isEmpty && $0.scheduleId == s.scheduleId }?.pledgeId
            // What the prompt asks: 0 is nothing (a pledge already covered); a
            // pledge's collector with no amount is stopping with its pledge.
            let asks = pledgeId != nil ? (s.nextAmountMinor ?? 0) > 0 : s.nextAmountMinor != 0
            guard asks, !(pledgeId.map { owedIds.contains($0) } ?? false) else { continue }
            if soonest.map({ day < $0.day }) ?? true { soonest = (s, day, pledgeId) }
        }
        // "Giving ·" — in motion, nothing to do (§9.1 rule 3).
        if let c = soonest, let line = ScheduleRhythm.collectedOn(c.day) {
            if let id = c.pledgeId {
                let title = pledge(id)?.displayTitle ?? c.gift.pledge.flatMap { $0.title.isEmpty ? nil : $0.title } ?? "Your pledge"
                return HomeWeekRow(pillar: .giving, title: "Giving · \(title)", line: line, destination: .pledge(id))
            }
            return HomeWeekRow(pillar: .giving, title: "Giving · " + (ScheduleRhythm.isWeekly(c.gift.frequency) ? "Your weekly gift" : "Your monthly gift"),
                               line: line, destination: .schedule(c.gift.scheduleId))
        }

        // 2 · The first instalment owed by hand, in the server's DUE order.
        if let d = owedByHand.first {
            let title = !d.title.isEmpty ? d.title : (pledge(d.id)?.displayTitle ?? "Pledge")
            let amount = GiveMoney.format(d.uncoveredMinor, d.currency)
            let line: String
            if overdue(d, today: today) {
                line = "\(amount) overdue" + ((dayLabel(d.overdueSince) ?? dayLabel(d.dueOn)).map { " since \($0)" } ?? "")
            } else {
                line = "\(amount) due" + (dayLabel(d.dueOn).map { " \($0)" } ?? "")
            }
            return HomeWeekRow(pillar: .giving, title: "Pay · \(title)", line: line, destination: .partners)
        }
        return give
    }

    /// The server says it is late — overdue instalments behind it, or since
    /// when — else (an older server) its date has passed on the church's
    /// calendar. Android's dueOverdue, the same rule.
    static func overdue(_ d: DueItem, today: String) -> Bool {
        guard d.kind == "pledge" else { return false }
        if d.overdueCount > 0 || d.overdueSince != nil { return true }
        return days(from: today, to: String(d.dueOn.prefix(10))).map { $0 < 0 } ?? false
    }

    // MARK: Cell

    /// The member's OWN cell (GET /me/cell-summary) — never the congregation's
    /// featured cell, which is the church's pick, not theirs: its name and
    /// next gathering, else the honest "not set" and how many walk in it. No
    /// cell (or the read failed): the way to find one.
    static func cellRow(_ c: CellSummary.Cell?, askedAt: String? = nil, timeZone: TimeZone,
                        now: Date = Date()) -> HomeWeekRow {
        guard let c else {
            // "Ask to be connected" (§9.2 #12): it opened Community, which has
            // no way to find a cell. Once asked — on any phone — it says so.
            return HomeWeekRow(pillar: .cell, title: "Find your cell",
                               line: askedAt.map { CellConnectWords.sent($0, now: now, timeZone: timeZone) } ?? CellConnectWords.weekLine,
                               destination: .cellConnect)
        }
        let line = c.next.flatMap { parse($0.startAt) }.map { "Next gathering \(format($0, "EEE d MMM", timeZone))" }
            ?? "Next gathering not set · \(c.members) \(c.members == 1 ? "member" : "members")"
        return HomeWeekRow(pillar: .cell, title: "Gather · " + (c.name.isEmpty ? "Your cell" : c.name), line: line, destination: .cell)
    }

    // MARK: Helpers

    private static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    /// "Sun 11 Oct · 9:00 AM".
    private static func when(_ date: Date, _ timeZone: TimeZone) -> String { format(date, "EEE d MMM · h:mm a", timeZone) }

    /// "Mon 5 Oct" for a church-calendar day ("2026-10-05"); nil when not one.
    private static func dayLabel(_ ymd: String?) -> String? {
        ymd.flatMap { PauseDates.date($0) }.map { ScheduleRhythm.format($0, "EEE d MMM") }
    }

    /// Whole days from one church-calendar day to another (YYYY-MM-DD).
    private static func days(from: String, to: String) -> Int? {
        guard let a = PauseDates.date(from), let b = PauseDates.date(to) else { return nil }
        return GiveCalendar.calendar.dateComponents([.day], from: a, to: b).day
    }
}
