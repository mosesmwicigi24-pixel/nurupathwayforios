// Experience Cycle 2 — information hierarchy, pinned (pathway docs/EXPERIENCE.md
// §6): Home's YOUR WEEK, every row in every form of §6.1's table, in the
// journey's order, each falling back to its "none" form when its data didn't
// come (§6.1) — "this week" being today through the seventh day after, on the
// church's clock; the Events and Plans headers' one line, and a quiet Events
// week (§6.2, §6.5); a finished level's trail folding away (§6.3); and a
// pledge its collector takes care of saying "Collected on …" on Partners' DUE
// list instead of Pay — on the church's Nairobi calendar, and only when the
// prompt comes on or before the instalment's date (§6.4). The same rules as
// Android's YourWeek / EventsHeader / PathwayTrail / pledgeCollectedOn.
// Payloads are decoded exactly like APIClient's: snake_case in.
import XCTest
@testable import NuruMember

final class ExperienceCycle2Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    private func json<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: Fixtures — GET /giving/partnership `due[]` + `pledges[]`, GET /giving/schedules rows

    /// Ada's Kenya trip instalment: KSh 5,000 due Mon 5 Oct.
    private func instalment(_ id: String = "p-kenya", dueOn: String = "2026-10-05", kind: String = "pledge",
                            action: String = "pay", amount: Int = 500_000, pending: Int = 0,
                            overdueSince: String? = nil, title: String = "Kenya trip") throws -> DueItem {
        try decode(DueItem.self, dueJSON(id, title, dueOn: dueOn, amount: amount, pending: pending,
                                         overdueSince: overdueSince, action: action, kind: kind))
    }

    private func dueJSON(_ id: String, _ title: String, dueOn: String, amount: Int, pending: Int = 0,
                         overdueSince: String? = nil, overdueCount: Int = 0, action: String = "pay",
                         kind: String = "pledge") -> String {
        let since = overdueSince.map { #""\#($0)""# } ?? "null"
        return #"{"kind":"\#(kind)","id":"\#(id)","title":"\#(title)","currency":"KES","amount_minor":\#(amount),"due_on":"\#(dueOn)","action":"\#(action)","pending_minor":\#(pending),"overdue_count":\#(overdueCount),"overdue_since":\#(since)}"#
    }

    /// The pledge a DUE row belongs to — `schedule_id` set on an older row.
    private func pledge(_ id: String = "p-kenya", scheduleId: String? = nil) throws -> Pledge {
        let sid = scheduleId.map { #""\#($0)""# } ?? "null"
        return try decode(Pledge.self, #"{"pledge_id":"\#(id)","shape":"monthly","amount_minor":500000,"currency":"KES","due_day":5,"title":"Kenya trip","status":"active","schedule_id":\#(sid)}"#)
    }

    /// A recurring gift — bound to `pledge` when given (its collector).
    private func gift(_ id: String, pledge: String? = nil, pledgeTitle: String = "Kenya trip",
                      status: String = "active", nextRunAt: String = "2026-10-05T06:01:00.000Z",
                      next: String = "500000", frequency: String = "monthly") throws -> GivingSchedule {
        let bound = pledge.map { #""pledge":{"pledge_id":"\#($0)","title":"\#(pledgeTitle)"}"# } ?? #""pledge":null"#
        return try decode(GivingSchedule.self, #"""
        {"schedule_id":"\#(id)","fund":"mission","amount_minor":500000,"currency":"KES","method":"mpesa",
         "frequency":"\#(frequency)","status":"\#(status)","next_run_at":"\#(nextRunAt)",\#(bound),"next_amount_minor":\#(next)}
        """#)
    }

    /// The §6.4 rule end to end, as Partners runs it: the pledge's collector, then its day, in words.
    private func collected(_ item: DueItem, _ gifts: [GivingSchedule]) throws -> String? {
        PledgePace.collectedDay(item, by: PledgePace.collector(of: try pledge(item.id), in: gifts))
            .flatMap(ScheduleRhythm.collectedOn)
    }

    // MARK: §6.4 — a pledge collected automatically says so

    func testAPledgeItsCollectorPromptsOnTheDayIsCollected() throws {
        // Ada: the Kenya trip's collector prompts at 09:01 on the due day.
        let item = try instalment()
        let s = try gift("s-kenya", pledge: "p-kenya")
        XCTAssertEqual(PledgePace.collectedDay(item, by: s), "2026-10-05")
        XCTAssertEqual(try collected(item, [s]), "Collected on Mon 5 Oct", "the same words as a running recurring gift's DUE row")
    }

    func testACollectorPromptingBeforeTheDateCollectsIt_onItsOwnDay() throws {
        XCTAssertEqual(try collected(try instalment(), [try gift("s-kenya", pledge: "p-kenya", nextRunAt: "2026-10-03T06:01:00.000Z")]),
                       "Collected on Sat 3 Oct", "the chip says when the prompt comes, not when the instalment falls")
    }

    func testACollectorPromptingAfterTheDateCountsAsNone() throws {
        // The instalment was due 1 Oct; the next prompt is 5 Oct — it would be late.
        XCTAssertNil(try collected(try instalment(dueOn: "2026-10-01"), [try gift("s-kenya", pledge: "p-kenya")]))
    }

    func testAPledgeWithNoCollectorKeepsPay() throws {
        let item = try instalment()
        XCTAssertNil(try collected(item, []))
        XCTAssertNil(try collected(item, [try gift("s-tithe")]), "an ordinary gift collects no pledge")
        XCTAssertNil(try collected(item, [try gift("s-roof", pledge: "p-roof")]), "another pledge's collector")
        XCTAssertNil(PledgePace.collectedDay(item, by: nil))
    }

    func testAPausedOrCancelledCollectorCountsAsNone() throws {
        let item = try instalment()
        XCTAssertNil(try collected(item, [try gift("s", pledge: "p-kenya", status: "paused")]), "a paused collector prompts nothing")
        XCTAssertNil(try collected(item, [try gift("s", pledge: "p-kenya", status: "cancelled")]))
        // A running collector wins over a paused one for the same pledge.
        let both = [try gift("s-old", pledge: "p-kenya", status: "paused"), try gift("s-run", pledge: "p-kenya")]
        XCTAssertEqual(PledgePace.collector(of: try pledge(), in: both)?.scheduleId, "s-run")
        XCTAssertEqual(try collected(item, both), "Collected on Mon 5 Oct")
    }

    func testACollectorAskingNothingKeepsPay() throws {
        XCTAssertNil(try collected(try instalment(), [try gift("s", pledge: "p-kenya", next: "0")]),
                     "0: the pledge is already covered — no prompt comes")
        XCTAssertNil(try collected(try instalment(), [try gift("s", pledge: "p-kenya", next: "null")]),
                     "no amount: a collector stopping with its pledge, or an older server — never claimed")
    }

    func testOnlyAPledgesPayRowIsConsidered() throws {
        let s = try gift("s-kenya", pledge: "p-kenya")
        XCTAssertNil(PledgePace.collectedDay(try instalment(kind: "schedule"), by: s), "a schedule row has its own chip")
        XCTAssertNil(PledgePace.collectedDay(try instalment(action: "resume"), by: s), "a paused pledge keeps Resume")
        XCTAssertNil(PledgePace.collectedDay(try instalment(dueOn: ""), by: s))
        XCTAssertNil(PledgePace.collectedDay(try instalment(), by: try gift("s", pledge: "p-kenya", nextRunAt: "")))
    }

    func testTheDaysAreNairobis() throws {
        // 22:30 UTC on the 4th is 01:30 on the 5th in Nairobi: the prompt's
        // day is the 5th, whatever the timestamp's string starts with.
        let late = try gift("s", pledge: "p-kenya", nextRunAt: "2026-10-04T22:30:00Z")
        XCTAssertEqual(PledgePace.collectedDay(try instalment(dueOn: "2026-10-05"), by: late), "2026-10-05")
        XCTAssertNil(PledgePace.collectedDay(try instalment(dueOn: "2026-10-04"), by: late),
                     "due the 4th, prompted the 5th — late, so Pay stays")
    }

    func testAnOlderRowsCollectorIsFoundByThePledgesScheduleId() throws {
        // The gift row carries no `pledge`; the pledge names its schedule.
        let gifts = [try gift("s-legacy"), try gift("s-tithe")]
        XCTAssertEqual(PledgePace.collector(of: try pledge(scheduleId: "s-legacy"), in: gifts)?.scheduleId, "s-legacy")
        XCTAssertNil(PledgePace.collector(of: try pledge(), in: gifts))
        XCTAssertNil(PledgePace.collector(of: try pledge(""), in: [try gift("s", pledge: "")]))
    }

    // MARK: §6.1 — YOUR WEEK

    /// Sunday 4 Oct 2026, noon in Nairobi — Ada's morning.
    private let now = ISO8601DateFormatter().date(from: "2026-10-04T09:00:00Z")!
    private let nairobi = TimeZone(identifier: "Africa/Nairobi")!

    // Pathway fixtures — /me/pathway, six levels, `current` takes `row`.
    private func level(_ n: Int, _ status: String, done: Int = 0, of total: Int = 0,
                       examPublished: Bool = true) -> [String: Any] {
        ["level_number": n, "title": "Level \(n) title", "theme": NSNull(), "description": NSNull(),
         "total_modules": total, "completed_modules": done, "minutes": 0, "status": status,
         "awaiting_review": false, "exam_published": examPublished]
    }
    private func journey(current: Int, _ row: [String: Any], trail: [[String: Any]] = []) throws -> Journey? {
        let levels: [[String: Any]] = (1...6).map { n in
            n == current ? row : (n < current ? level(n, "completed", done: 10, of: 10) : level(n, "locked"))
        }
        let summary = try json(PathwaySummary.self, ["current_level": current, "levels": levels])
        return Journey.derive(summary, trail: try json([LevelModule].self, trail))
    }
    private func module(_ id: String, level: Int, seq: Int, _ status: String, completed: Bool = false) -> [String: Any] {
        ["module_id": id, "level_number": level, "module_sequence_number": seq, "title": "Module \(id)",
         "summary": NSNull(), "estimated_minutes": 10, "evaluation_kind": "none", "quiz_pass_mark": 70,
         "completed": completed, "status": status, "progress": completed ? 100 : 0, "locked": status == "locked"]
    }

    private func plan(_ id: String, _ title: String, days: Int = 10, current: Int? = 1, done: [Int]? = [],
                      enrolled: Bool = true, completedAt: String? = nil) throws -> ReadingPlanRow {
        try json(ReadingPlanRow.self, ["plan_id": id, "title": title, "day_count": days,
                                       "current_day": current.map { $0 as Any } ?? NSNull(),
                                       "completed_days": done.map { $0 as Any } ?? NSNull(),
                                       "enrolled": enrolled, "completed_at": completedAt.map { $0 as Any } ?? NSNull()])
    }

    private func occurrence(_ id: String, _ title: String, at: String, end: String = "") throws -> CalendarOccurrence {
        try json(CalendarOccurrence.self, ["occurrence_id": id, "series_id": "series-\(id)", "title": title,
                                           "start_at": at, "end_at": end, "going": 0])
    }
    private func homeEvent(_ id: String, _ title: String, at: String, rsvp: String? = nil) throws -> HomeEventRow {
        try json(HomeEventRow.self, ["occurrence_id": id, "series_id": "series-\(id)", "title": title,
                                     "venue": "Main hall", "starts_at": at, "my_rsvp": rsvp.map { $0 as Any } ?? NSNull()])
    }
    private func rsvp(_ eventId: String, _ title: String, at: String?, status: String = "going") throws -> MyRsvp {
        try json(MyRsvp.self, ["rsvp_id": "r-\(eventId)", "status": status, "event_id": eventId, "title": title,
                               "occurs_at": at.map { $0 as Any } ?? NSNull()])
    }

    private let kenyaPledge = #"{"pledge_id":"p-kenya","shape":"monthly","amount_minor":500000,"currency":"KES","due_day":5,"title":"Kenya trip","status":"active","schedule_id":"s-kenya"}"#
    private let roofPledge = #"{"pledge_id":"p-roof","shape":"total","target_minor":2000000,"currency":"KES","due_on":"2026-12-31","title":"Roof sheets for the new hall","status":"active"}"#

    /// GET /giving/partnership — the pledges and the merged DUE list.
    private func standing(pledges: [String] = [], due: [String] = []) throws -> Partnership {
        try decode(Partnership.self, #"{"is_partner":true,"pledges":[\#(pledges.joined(separator: ","))],"due":[\#(due.joined(separator: ","))]}"#)
    }

    private func cell(next: String? = nil, members: Int = 6) throws -> CellSummary.Cell? {
        let n: Any = next.map { ["start_at": $0] as [String: Any] } ?? NSNull()
        return try json(CellSummary.self, ["cell": ["cell_group_id": "c-a", "name": "Dev Cell A", "members": members,
                                                    "attendance": ["attended": 8, "expected": 8], "next": n]]).cell
    }

    private func eventsRow(calendar: [CalendarOccurrence]? = nil, home: [HomeEventRow]? = nil, rsvps: [MyRsvp]? = nil) -> HomeWeekRow {
        HomeWeek.eventsRow(calendar: calendar, home: home, rsvps: rsvps, now: now, timeZone: nairobi)
    }
    private func givingRow(_ p: Partnership?, _ s: [GivingSchedule]?) -> HomeWeekRow {
        HomeWeek.givingRow(partnership: p, schedules: s, railsLine: "Tithe & offering · M-Pesa", now: now)
    }
    private func eventOf(_ row: HomeWeekRow) -> CalendarOccurrence? {
        if case .event(let occ) = row.destination { return occ }
        return nil
    }

    // Pathway — always

    func testThePathwayRowIsTheJourneysNextStep() throws {
        // Ada: every Level 1 module done, the exam published.
        let r = HomeWeek.pathwayRow(try journey(current: 1, level(1, "completed", done: 20, of: 20)), enrolledLevel: 1)
        XCTAssertEqual(r.title, "Take the Level 1 exam")
        XCTAssertEqual(r.line, "Level 1 · Exam ready")
        XCTAssertEqual(r.destination, .journey(.exam(1)))

        let walking = HomeWeek.pathwayRow(try journey(current: 2, level(2, "active", done: 3, of: 10),
                                                      trail: [module("b", level: 2, seq: 4, "next")]), enrolledLevel: 2)
        XCTAssertEqual(walking.title, "Continue · Module b")
        XCTAssertEqual(walking.line, "Level 2 · 3 of 10 modules")
        XCTAssertEqual(walking.destination, .journey(.module("b")))
    }

    func testAPathwayStepWithNothingToTapOpensThePathwayTab() throws {
        let r = HomeWeek.pathwayRow(try journey(current: 1, level(1, "completed", done: 20, of: 20, examPublished: false)),
                                    enrolledLevel: 1)
        XCTAssertEqual(r.title, "Level 1 complete")
        XCTAssertEqual(r.line, "Level 1 · Exam opens soon")
        XCTAssertEqual(r.destination, .journey(nil), "the exam is in review — the Pathway tab")
    }

    func testThePathwayRowStandsWhenThePathwayDidNotLoad() {
        let r = HomeWeek.pathwayRow(nil, enrolledLevel: 1)
        XCTAssertEqual(r.title, "Open your pathway")
        XCTAssertEqual(r.line, "Level 1", "the level alone")
        XCTAssertEqual(r.destination, .journey(nil), "the Pathway tab itself")
        XCTAssertEqual(HomeWeek.pathwayRow(nil, enrolledLevel: nil).line, "", "a member not yet placed: no level is invented")
    }

    // Plans

    func testThePlansRowIsThePlanBeingRead() throws {
        let rooted = try plan("rooted", "Rooted: 10 Days in the Psalms")
        let r = HomeWeek.plansRow([try plan("john", "Gospel of John", enrolled: false), rooted])
        XCTAssertEqual(r.title, "Start · Rooted: 10 Days in the Psalms")
        XCTAssertEqual(r.line, "Day 1 of 10 · today's reading")
        XCTAssertEqual(r.destination, .planDay(rooted), "that plan's day")
    }

    func testAFinishedOrUnstartedPlanIsNotTheOneBeingRead() throws {
        // Ada today: the catalogue's first plan, never started — the old minis
        // card showed it as "Day 1 of 10".
        let catalogue = [try plan("rooted", "Rooted: 10 Days in the Psalms", current: nil, done: nil, enrolled: false)]
        let none = HomeWeek.plansRow(catalogue)
        XCTAssertEqual(none.title, "Start a reading plan")
        XCTAssertEqual(none.line, "A few minutes a day — with the whole family of God.")
        XCTAssertEqual(none.destination, .plans)
        let finished = try plan("fear", "Fear Not", completedAt: "2026-09-30T08:00:00Z")
        let reading = try plan("new", "New Grace", current: 4)
        XCTAssertTrue(HomeWeek.plansRow([finished, reading]).title.hasSuffix("· New Grace"), "the first enrolled, UNFINISHED plan")
        // A failed read is never a fact (final walk M4): it says so, and
        // never invites a member who may be reading one to start a plan.
        XCTAssertEqual(HomeWeek.plansRow(nil).title, "Your reading plans", "the plans didn't load")
        XCTAssertEqual(HomeWeek.plansRow(nil).line, "Didn't load just now")
        XCTAssertEqual(HomeWeek.plansRow([]), none)
    }

    func testThePlansDayLine() throws {
        XCTAssertEqual(try plan("a", "A", current: 3).dayLine, "Day 3 of 10")
        XCTAssertEqual(try plan("a", "A", current: nil, done: [1, 2]).dayLine, "Day 3 of 10", "one past the days done")
        XCTAssertEqual(try plan("a", "A", current: 14).dayLine, "Day 10 of 10", "never past the last day")
        XCTAssertEqual(try plan("a", "A", days: 0, current: nil, done: nil).dayLine, "Day 1")
    }

    // Events — this week: today through the seventh day after

    func testTheEventsRowIsTheGatheringTheMemberIsGoingTo() throws {
        let sooner = try homeEvent("occ-1", "Prayer breakfast", at: "2026-10-06T05:00:00.000Z")
        let youth = try homeEvent("occ-2", "Youth night", at: "2026-10-10T15:00:00.000Z", rsvp: "going")
        let r = eventsRow(home: [sooner, youth])
        XCTAssertEqual(r.title, "Going · Youth night", "what the member said yes to comes first")
        XCTAssertNil(r.ask, "going is where things stand, not a step (owner, 2026-10-07: colour option A)")
        XCTAssertEqual(r.line, "Sat 10 Oct · 6:00 PM")
        XCTAssertEqual(eventOf(r)?.occurrenceId, "occ-2")
    }

    func testTheCalendarCuratedRowsAndRsvpsAreOneList() throws {
        // The church calendar knows the gathering (and its end); the member's
        // RSVP says they're going — their answer has the last word.
        let service = try occurrence("occ-7", "Sunday service", at: "2026-10-11T06:00:00.000Z", end: "2026-10-11T08:30:00.000Z")
        let r = eventsRow(calendar: [service], home: [], rsvps: [try rsvp("occ-7", "Sunday service", at: "2026-10-11T06:00:00.000Z")])
        XCTAssertEqual(r.title, "Going · Sunday service")
        XCTAssertEqual(r.line, "Sun 11 Oct · 9:00 AM")
        XCTAssertEqual(eventOf(r)?.endAt, "2026-10-11T08:30:00.000Z", "the calendar's end rides along to the event page")
        // Known only to the RSVP list.
        let away = eventsRow(home: [], rsvps: [try rsvp("ev-9", "Leaders' retreat", at: "2026-10-08T07:30:00.000Z")])
        XCTAssertEqual(away.title, "Going · Leaders' retreat")
        XCTAssertEqual(away.line, "Thu 8 Oct · 10:30 AM")
        XCTAssertEqual(eventOf(away)?.occurrenceId, "ev-9", "the RSVP's event id is the occurrence the page loads")
        // A calendar gathering nobody curated still counts.
        XCTAssertEqual(eventsRow(calendar: [try occurrence("occ-8", "Cell night", at: "2026-10-07T16:00:00.000Z")]).line,
                       "Wed 7 Oct · 7:00 PM")
    }

    func testOtherwiseTheSoonestGatheringThisWeek() throws {
        let later = try homeEvent("occ-2", "Youth night", at: "2026-10-10T15:00:00.000Z")
        let sunday = try homeEvent("occ-1", "Sunday service", at: "2026-10-11T06:00:00.000Z")
        let r = eventsRow(home: [sunday, later], rsvps: [])
        XCTAssertEqual(r.title, "Join · Youth night")
        XCTAssertEqual(r.ask, .init(verb: "Join", subject: "Youth night"), "an unanswered gathering asks (colour option A)")
        XCTAssertEqual(r.line, "Sat 10 Oct · 6:00 PM")
        XCTAssertEqual(eventOf(r)?.occurrenceId, "occ-2")
    }

    func testTheWeekIsTodayThroughTheSeventhDayAfter() throws {
        let lastDay = try homeEvent("occ-1", "Sunday service", at: "2026-10-11T17:00:00.000Z")   // Sun 11 Oct, 8 PM
        XCTAssertEqual(eventsRow(home: [lastDay]).title, "Join · Sunday service", "the seventh day after counts")
        let eighth = try homeEvent("occ-2", "Monday prayer", at: "2026-10-12T04:00:00.000Z")     // Mon 12 Oct, 7 AM
        XCTAssertEqual(eventsRow(home: [eighth]).title, "See the church calendar", "the eighth does not")
        let earlier = try homeEvent("occ-0", "This morning", at: "2026-10-04T06:00:00.000Z", rsvp: "going")
        XCTAssertEqual(eventsRow(home: [earlier]).title, "See the church calendar", "one already begun is not upcoming")
    }

    func testADeclinedGatheringOnlyWhenNothingElseIsOn() throws {
        let declined = try homeEvent("occ-1", "Prayer breakfast", at: "2026-10-06T05:00:00.000Z", rsvp: "declined")
        let maybe = try homeEvent("occ-2", "Youth night", at: "2026-10-10T15:00:00.000Z", rsvp: "maybe")
        XCTAssertEqual(eventsRow(home: [declined, maybe]).title, "Join · Youth night", "a maybe still stands; a no steps aside")
        let alone = eventsRow(home: [declined])
        XCTAssertEqual(alone.title, "Join · Prayer breakfast", "the only gathering this week — said, even though declined")
        XCTAssertNil(alone.ask, "one the member declined is not their next step (colour option A)")
        XCTAssertEqual(alone.line, "Tue 6 Oct · 8:00 AM", "never \"You're going\"")
        // A no in the RSVP list outranks the curated row's silence.
        let saidNo = eventsRow(home: [try homeEvent("occ-1", "Prayer breakfast", at: "2026-10-06T05:00:00.000Z"), maybe],
                               rsvps: [try rsvp("occ-1", "Prayer breakfast", at: "2026-10-06T05:00:00.000Z", status: "declined")])
        XCTAssertEqual(saidNo.title, "Join · Youth night")
    }

    func testNoGatheringIsAQuietRow() throws {
        let none = eventsRow(calendar: [])
        XCTAssertEqual(none.title, "See the church calendar")
        XCTAssertNil(none.ask, "the calendar is a standing invitation, not a step (colour option A)")
        XCTAssertEqual(none.line, "No gatherings this week")
        XCTAssertEqual(none.destination, .events)
        XCTAssertEqual(eventsRow(calendar: [], home: [], rsvps: []), none, "Ada today: nothing on the calendar")
        XCTAssertEqual(eventsRow(calendar: [], rsvps: [try rsvp("ev-1", "No date", at: nil)]), none, "an RSVP with no next occurrence")
        // The calendar didn't load: the week is not known to be quiet (final walk M4).
        XCTAssertEqual(eventsRow().line, "Didn't load just now")
        XCTAssertEqual(eventsRow().title, "See the church calendar")
    }

    // Giving

    func testAPledgeCollectedThisWeekLeadsTheGivingRow() throws {
        // Ada: the Kenya trip's collector prompts Mon 5 Oct, the weekly tithe Sun 11 Oct.
        let p = try standing(pledges: [kenyaPledge, roofPledge],
                             due: [dueJSON("p-kenya", "Kenya trip", dueOn: "2026-10-05", amount: 500_000),
                                   dueJSON("p-roof", "Roof sheets for the new hall", dueOn: "2026-12-31", amount: 2_000_000)])
        let gifts = [try gift("s-tithe", nextRunAt: "2026-10-11T06:01:00.108Z", next: "100000", frequency: "weekly"),
                     try gift("s-kenya", pledge: "p-kenya")]
        let r = givingRow(p, gifts)
        XCTAssertEqual(r.title, "Giving · Kenya trip")
        XCTAssertEqual(r.line, "Collected on Mon 5 Oct")
        XCTAssertEqual(r.destination, .pledge("p-kenya"), "its pledge")
        XCTAssertFalse(HomeWeek.asksToGive([r]), "a member already giving isn't asked twice")
    }

    func testARecurringGiftCollectedThisWeek() throws {
        let empty = try standing()
        let weekly = givingRow(empty, [try gift("s-tithe", nextRunAt: "2026-10-11T06:01:00.108Z", frequency: "weekly")])
        XCTAssertEqual(weekly.title, "Giving · Your weekly gift")
        XCTAssertNil(weekly.ask, "a gift collecting itself asks nothing (colour option A)")
        XCTAssertEqual(weekly.line, "Collected on Sun 11 Oct", "the seventh day after counts")
        XCTAssertEqual(weekly.destination, .schedule("s-tithe"), "the gift's sheet")
        let monthly = givingRow(empty, [try gift("s-month", nextRunAt: "2026-10-07T06:00:00Z")])
        XCTAssertEqual(monthly.title, "Giving · Your monthly gift")
        XCTAssertEqual(monthly.line, "Collected on Wed 7 Oct")
    }

    func testAGiftThatPromptsNothingThisWeekIsNotTheRow() throws {
        let give = givingRow(try standing(), [try gift("s-far", nextRunAt: "2026-10-12T06:00:00Z"),
                                              try gift("s-paid", nextRunAt: "2026-10-06T06:00:00Z", next: "0"),
                                              try gift("s-stopping", pledge: "p-old", nextRunAt: "2026-10-06T06:00:00Z", next: "null")])
        XCTAssertEqual(give.title, "Give", "the eighth day, nothing to pay, a collector stopping with its pledge")
        // A paused gift is never offered as a new "Give" (final walk M2):
        // Home says what Give says (FinalFixesTests).
        XCTAssertEqual(givingRow(try standing(), [try gift("s-paused", status: "paused", nextRunAt: "2026-10-06T06:00:00Z")]).title,
                       "Paused · Your monthly gift")
        XCTAssertNil(give.ask, "Give is a standing invitation, not a step (colour option A)")
        XCTAssertEqual(give.line, "Tithe & offering · M-Pesa", "the rails line — only rails that work here")
        XCTAssertEqual(give.destination, .give)
        XCTAssertTrue(HomeWeek.asksToGive([give]))
    }

    func testAPledgeOwedByHandIsTheServersDueRow() throws {
        let soon = try standing(pledges: [roofPledge],
                                due: [dueJSON("p-roof", "Roof sheets for the new hall", dueOn: "2026-10-08", amount: 2_000_000)])
        let r = givingRow(soon, [])
        XCTAssertEqual(r.title, "Pay · Roof sheets for the new hall")
        XCTAssertEqual(r.ask, .init(verb: "Pay", subject: "Roof sheets for the new hall"), "money owed by hand asks (colour option A)")
        XCTAssertEqual(r.line, "KSh 20,000 due Thu 8 Oct")
        XCTAssertEqual(r.destination, .partners)
        XCTAssertFalse(HomeWeek.asksToGive([r]))
        // Nothing is urgent before it is (§9.3 rule 2): Ada's Roof sheets, due
        // 31 Dec, is not this week's ask — Partners lists it under COMING UP.
        let total = try standing(pledges: [roofPledge],
                                 due: [dueJSON("p-roof", "Roof sheets for the new hall", dueOn: "2026-12-31", amount: 2_000_000)])
        XCTAssertEqual(givingRow(total, []).title, "Give")
    }

    func testAnOverdueInstalmentSaysSince() throws {
        // Partners' own phrase — "overdue since …".
        let late = try standing(due: [dueJSON("p-camp", "Youth camp", dueOn: "2026-10-01", amount: 300_000)])
        XCTAssertEqual(givingRow(late, []).line, "KSh 3,000 overdue since Thu 1 Oct")
        // The server says how late: the oldest unpaid instalment sets the date.
        let behind = try standing(due: [dueJSON("p-camp", "Youth camp", dueOn: "2026-10-04", amount: 600_000,
                                                overdueSince: "2026-09-01", overdueCount: 2)])
        XCTAssertEqual(givingRow(behind, []).line, "KSh 6,000 overdue since Tue 1 Sep")
        XCTAssertEqual(givingRow(behind, []).title, "Pay · Youth camp")
        let counted = try standing(due: [dueJSON("p-camp", "Youth camp", dueOn: "2026-10-04", amount: 300_000, overdueCount: 1)])
        XCTAssertEqual(givingRow(counted, []).line, "KSh 3,000 overdue since Sun 4 Oct", "late by the server's count, dated by its row")
    }

    func testAPausedOrLateCollectorIsNoCollector() throws {
        // Due 1 Oct, the collector's next prompt is 5 Oct: Partners shows Pay,
        // so Home says what is owed — never "Collected on Mon 5 Oct".
        let late = try standing(pledges: [kenyaPledge], due: [dueJSON("p-kenya", "Kenya trip", dueOn: "2026-10-01", amount: 500_000)])
        let r = givingRow(late, [try gift("s-kenya", pledge: "p-kenya")])
        XCTAssertEqual(r.title, "Pay · Kenya trip")
        XCTAssertEqual(r.line, "KSh 5,000 overdue since Thu 1 Oct")
        XCTAssertEqual(r.destination, .partners)
        let paused = try standing(pledges: [kenyaPledge], due: [dueJSON("p-kenya", "Kenya trip", dueOn: "2026-10-05", amount: 500_000)])
        XCTAssertEqual(givingRow(paused, [try gift("s-kenya", pledge: "p-kenya", status: "paused")]).line, "KSh 5,000 due Mon 5 Oct",
                       "a paused collector prompts nothing — the instalment is the member's to pay")
    }

    func testMoneyAlreadyOnItsWayIsNotAskedTwice() throws {
        let onItsWay = try standing(due: [dueJSON("p-roof", "Roof", dueOn: "2026-10-06", amount: 500_000, pending: 500_000)])
        XCTAssertEqual(givingRow(onItsWay, []).title, "Give", "every shilling is already on its way")
        let partly = try standing(due: [dueJSON("p-roof", "Roof", dueOn: "2026-10-06", amount: 500_000, pending: 200_000)])
        XCTAssertEqual(givingRow(partly, []).line, "KSh 3,000 due Tue 6 Oct", "only what is still uncovered")
        let paused = try standing(due: [dueJSON("p-roof", "Roof", dueOn: "2026-10-06", amount: 500_000, action: "resume")])
        XCTAssertEqual(givingRow(paused, []).title, "Give", "a paused pledge's Resume is not a payment")
    }

    func testTheTablesOrderIsThePriority() throws {
        // A pledge owed by hand, and two gifts collecting this week: a gift
        // collected this week outranks the pledge, and the soonest leads.
        let p = try standing(due: [dueJSON("p-roof", "Roof", dueOn: "2026-10-05", amount: 500_000)])
        let r = givingRow(p, [try gift("s-tithe", nextRunAt: "2026-10-09T06:00:00Z", frequency: "weekly"),
                              try gift("s-month", nextRunAt: "2026-10-06T06:00:00Z")])
        XCTAssertEqual(r.title, "Giving · Your monthly gift")
        XCTAssertEqual(r.line, "Collected on Tue 6 Oct")
    }

    func testEitherReadFailingSaysSo() throws {
        let p = try standing(pledges: [kenyaPledge], due: [dueJSON("p-kenya", "Kenya trip", dueOn: "2026-10-05", amount: 500_000)])
        let gifts = [try gift("s-kenya", pledge: "p-kenya")]
        XCTAssertEqual(givingRow(p, nil), givingRow(nil, gifts), "nothing about a gift or a pledge is said on a guess")
        // Nor "Give" as if nothing were in motion (final walk M4).
        XCTAssertEqual(givingRow(nil, gifts).title, "Your giving")
        XCTAssertEqual(givingRow(nil, gifts).line, "Didn't load just now")
        XCTAssertEqual(givingRow(nil, gifts).destination, .give)
        XCTAssertFalse(HomeWeek.asksToGive([givingRow(nil, gifts)]))
    }

    // Cell — the member's own

    func testTheCellRowIsTheMembersOwnCell() throws {
        let r = HomeWeek.cellRow(try cell(next: "2026-10-08T15:00:00.000Z"), timeZone: nairobi)
        XCTAssertEqual(r.title, "Gather · Dev Cell A")
        XCTAssertEqual(r.line, "Next gathering Thu 8 Oct")
        XCTAssertEqual(r.destination, .cell)
    }

    func testACellWithNoNextGatheringSaysSo() throws {
        // Ada: Dev Cell A, six members, no gathering set.
        XCTAssertEqual(HomeWeek.cellRow(try cell(), timeZone: nairobi).line, "Next gathering not set · 6 members")
        XCTAssertEqual(HomeWeek.cellRow(try cell(members: 1), timeZone: nairobi).line, "Next gathering not set · 1 member")
    }

    func testNoCellOfTheirOwnIsTheWayToFindOne() throws {
        // The week reads only the member's cell summary; the church's featured
        // cell is the church's pick, not theirs — it never fills this row.
        let r = HomeWeek.cellRow(try json(CellSummary.self, ["cell": NSNull()]).cell, timeZone: nairobi)
        XCTAssertEqual(r.title, "Find your cell")
        // "Ask to be connected" (§9.2 #12) — it opened Community, which has no way to find one.
        XCTAssertEqual(r.line, "Ask to be connected — tell the church where you live.")
        XCTAssertEqual(r.destination, .cellConnect)
        // The summary didn't load: never "Find your cell" (final walk M4).
        XCTAssertEqual(HomeWeek.cellRow(nil, loaded: false, timeZone: nairobi).title, "Your cell")
        XCTAssertNil(HomeWeek.cellRow(nil, loaded: false, timeZone: nairobi).ask)
    }

    // The block

    func testTheWeekIsFiveRowsInTheJourneysOrder() throws {
        let rows = HomeWeek.rows(journey: nil, enrolledLevel: nil, plans: nil, calendar: nil, homeEvents: nil, rsvps: nil,
                                 partnership: nil, schedules: nil, railsLine: "Tithe & offering", cell: nil,
                                 cellLoaded: false, now: now, timeZone: nairobi)
        XCTAssertEqual(rows.map(\.pillar), [.pathway, .plans, .events, .giving, .cell])
        // Nothing loaded: every row says so — never a "none" form, never an
        // ask (final walk M4) — and the card still stands.
        XCTAssertEqual(rows.map(\.title), ["Open your pathway", "Your reading plans", "See the church calendar", "Your giving", "Your cell"])
        XCTAssertFalse(HomeWeek.asksToGive(rows))
        // Loaded and empty, each row is its none form.
        let none = HomeWeek.rows(journey: nil, enrolledLevel: nil, plans: [], calendar: [], homeEvents: [], rsvps: [],
                                 partnership: try standing(), schedules: [], railsLine: "Tithe & offering", cell: nil,
                                 now: now, timeZone: nairobi)
        XCTAssertEqual(none.map(\.title), ["Open your pathway", "Start a reading plan", "See the church calendar", "Give", "Find your cell"])
        XCTAssertTrue(HomeWeek.asksToGive(none))
    }

    // MARK: §6.2 / §6.5 — one header line on Events and Plans; a quiet week is quiet

    func testTheEventsHeaderSaysWhatIsNext() throws {
        let later = try occurrence("occ-2", "Youth night", at: "2026-10-10T15:00:00.000Z")
        let monday = try occurrence("occ-1", "Prayer breakfast", at: "2026-10-05T05:00:00.000Z")
        XCTAssertEqual(EventsHeader.line([later, monday], now: now, timeZone: nairobi), "Next: Prayer breakfast · Mon 5 Oct",
                       "the soonest, whatever order the calendar sent")
        XCTAssertFalse(EventsHeader.isQuiet([later], now: now, timeZone: nairobi))
        XCTAssertEqual(EventsHeader.fromToday([later, monday], now: now, timeZone: nairobi).map(\.occurrenceId), ["occ-1", "occ-2"])
    }

    func testTheEventsHeaderLooksAcrossAllTheTabLoadsFromToday() throws {
        // Three weeks out is still what's next — and not a quiet week.
        let harvest = try occurrence("occ-9", "Harvest", at: "2026-10-25T06:00:00.000Z")
        XCTAssertEqual(EventsHeader.line([harvest], now: now, timeZone: nairobi), "Next: Harvest · Sun 25 Oct")
        XCTAssertFalse(EventsHeader.isQuiet([harvest], now: now, timeZone: nairobi))
        // From today on the church's day: this morning's gathering still counts.
        let dawn = try occurrence("occ-3", "Morning prayer", at: "2026-10-04T04:00:00.000Z")
        XCTAssertEqual(EventsHeader.line([dawn], now: now, timeZone: nairobi), "Next: Morning prayer · Sun 4 Oct")
    }

    func testNothingFromTodayOnIsAQuietWeek() throws {
        // Ada: nothing on the calendar.
        XCTAssertEqual(EventsHeader.line([], now: now, timeZone: nairobi), "Nothing planned this week")
        XCTAssertTrue(EventsHeader.isQuiet([], now: now, timeZone: nairobi))
        // The tab loads a week back: only past gatherings in range is still quiet.
        let lastSunday = try occurrence("occ-0", "Last Sunday", at: "2026-09-27T06:00:00.000Z")
        XCTAssertTrue(EventsHeader.isQuiet([lastSunday], now: now, timeZone: nairobi))
        XCTAssertEqual(EventsHeader.line([lastSunday], now: now, timeZone: nairobi), "Nothing planned this week")
    }

    func testThePlansHeaderNamesThePlanBeingRead() throws {
        // The same plan and day as Home's week row.
        let rooted = try plan("rooted", "Rooted: 10 Days in the Psalms")
        XCTAssertEqual(ReadingPlanRow.activeLine(in: [try plan("john", "Gospel of John", enrolled: false), rooted]),
                       "Rooted: 10 Days in the Psalms · Day 1 of 10")
        XCTAssertNil(ReadingPlanRow.activeLine(in: [try plan("john", "Gospel of John", enrolled: false)]),
                     "none being read — the tagline stands")
    }

    // MARK: §6.3 — a finished level folds away

    private func lessons(_ n: Int, level: Int = 1, done: Int? = nil) throws -> [LevelModule] {
        let finished = done ?? n
        return try json([LevelModule].self, (1...n).map { i in
            module("m\(i)", level: level, seq: i, i <= finished ? "completed" : (i == finished + 1 ? "next" : "locked"),
                   completed: i <= finished)
        })
    }

    func testAFinishedLevelFoldsIntoOneRowThatOpensAndCloses() throws {
        // Ada: every Level 1 module done, the exam ready.
        let j = try journey(current: 1, level(1, "completed", done: 20, of: 20))
        let mods = try lessons(20)
        XCTAssertTrue(PathwayTrail.folds(j, levelNumber: 1, modules: mods))
        XCTAssertEqual(PathwayTrail.foldLine(mods, expanded: false), "20 of 20 modules done · Show")
        XCTAssertEqual(PathwayTrail.foldLine(mods, expanded: true), "20 of 20 modules done · Hide")
    }

    func testEveryStagePastLearningFolds() throws {
        let soon = try journey(current: 1, level(1, "completed", done: 20, of: 20, examPublished: false))
        XCTAssertEqual(soon?.stage, .examSoon)
        XCTAssertTrue(PathwayTrail.folds(soon, levelNumber: 1, modules: try lessons(20)))
        var passed = level(1, "completed", done: 20, of: 20)
        passed["awaiting_review"] = true
        let usher = try journey(current: 1, passed)
        XCTAssertEqual(usher?.stage, .awaitingUsher)
        XCTAssertTrue(PathwayTrail.folds(usher, levelNumber: 1, modules: try lessons(20)))
    }

    func testALevelStillBeingWalkedOrAnotherLevelStaysOpen() throws {
        let walking = try journey(current: 2, level(2, "active", done: 3, of: 10))
        XCTAssertFalse(PathwayTrail.folds(walking, levelNumber: 2, modules: try lessons(10, level: 2, done: 3)), "still learning")
        let finished = try journey(current: 1, level(1, "completed", done: 20, of: 20))
        XCTAssertFalse(PathwayTrail.folds(finished, levelNumber: 2, modules: try lessons(5, level: 2, done: 0)),
                       "only the member's own level folds")
        XCTAssertFalse(PathwayTrail.folds(finished, levelNumber: 1, modules: []), "nothing to fold")
        XCTAssertFalse(PathwayTrail.folds(nil, levelNumber: 1, modules: try lessons(20)), "no journey, no fold")
    }

    func testTheFoldCountsLessonsNotTheExam() throws {
        // Prod's shape: ten lessons and the exam row, still "active" at 10 of 11.
        var rows = (1...10).map { module("m\($0)", level: 1, seq: $0, "completed", completed: true) }
        var exam = module("exam", level: 1, seq: 11, "next")
        exam["evaluation_kind"] = "exit_exam"
        rows.append(exam)
        let mods = try json([LevelModule].self, rows)
        let j = try journey(current: 1, level(1, "active", done: 10, of: 11), trail: rows)
        XCTAssertEqual(j?.stage, .examReady)
        XCTAssertTrue(PathwayTrail.folds(j, levelNumber: 1, modules: mods))
        XCTAssertEqual(PathwayTrail.foldLine(mods, expanded: false), "10 of 10 modules done · Show", "the exam is a step, not a module")
    }

    func testTheTrailsExamRowIsGoneWhileTheHeroShowsTheExam() throws {
        let ready = try journey(current: 1, level(1, "completed", done: 20, of: 20))
        XCTAssertTrue(PathwayTrail.examRowHidden(ready, levelNumber: 1))
        XCTAssertFalse(PathwayTrail.examRowHidden(ready, levelNumber: 2), "another level's exam row stays")
        let soon = try journey(current: 1, level(1, "completed", done: 20, of: 20, examPublished: false))
        XCTAssertFalse(PathwayTrail.examRowHidden(soon, levelNumber: 1), "the hero isn't showing an exam to take")
        XCTAssertFalse(PathwayTrail.examRowHidden(nil, levelNumber: 1))
    }
}
