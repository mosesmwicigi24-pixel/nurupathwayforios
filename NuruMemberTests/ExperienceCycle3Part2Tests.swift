// Experience Cycle 3, part 2 — the areas Cycle 3 skipped, pinned (pathway
// docs/EXPERIENCE.md §7.4). Fixtures are the local API's own payloads for the
// test members (Ada = student1: "First Steps" day 1 with The Word and Respond
// done, Talk it Over open), decoded exactly like APIClient's: snake_case in.
import XCTest
@testable import NuruMember

final class ExperienceCycle3Part2Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: Fixtures — a plan day as /growth/plans/{id} serves it

    private func segment(_ id: String, _ sort: Int, _ kind: String, _ title: String, done: Bool) -> [String: Any] {
        ["segment_id": id, "sort": sort, "kind": kind, "title": title, "reference": NSNull(),
         "content": "Words.", "video_url": NSNull(), "image_url": NSNull(), "completed": done]
    }

    /// "First Steps" day 1 as the local API serves Ada: five segments, Talk
    /// it Over the only one open.
    private func adasDayOne(talkDone: Bool = false, nothingDone: Bool = false) -> [[String: Any]] {
        [segment("s1", 1, "scripture", "Today's Reading", done: !nothingDone),
         segment("s2", 2, "devotional", "Devotional", done: !nothingDone),
         segment("s3", 3, "talk", "Talk it Over", done: talkDone && !nothingDone),
         segment("s4", 4, "devotional", "Pray", done: !nothingDone),
         segment("s5", 5, "reading", "Go Deeper", done: !nothingDone)]
    }

    private func segments(_ rows: [[String: Any]]) throws -> [PlanSegment] { try decode([PlanSegment].self, rows) }

    private func day(_ n: Int, _ segs: [[String: Any]], completed: Bool = false, locked: Bool = false) -> [String: Any] {
        ["day_number": n, "reference": "John \(n)", "title": "Day \(n)", "content": NSNull(),
         "segments": segs, "completed": completed, "locked": locked]
    }

    private func detail(_ days: [[String: Any]]) throws -> ReadingPlanDetail {
        try decode(ReadingPlanDetail.self, [
            "plan_id": "first-steps", "title": "First Steps", "day_count": days.count,
            "current_day": 1, "completed_days": [Int](), "enrolled": true, "days": days])
    }

    // MARK: §7.4 #2 — one grouping of a day's parts

    func testADayHasTheHubsPartsInTheHubsOrder() throws {
        let parts = PlanDayParts.parts(try segments(adasDayOne()))
        XCTAssertEqual(parts.map(\.kind), [.word, .respond, .talk], "The Word · Respond · Talk it Over")
        XCTAssertEqual(parts.map(\.id), ["word", "respond", "talk"])
        XCTAssertEqual(parts[0].segments.map(\.segmentId), ["s1", "s2", "s5"], "Scripture, teaching and Go Deeper are one part")
        XCTAssertEqual(parts[1].segments.map(\.segmentId), ["s4"], "the prayer is Respond")
        // The reader's index is the part's first place in the study order:
        // s1 s2 s3(talk) s4(pray) s5(go deeper) → word 0, talk 2, respond 3.
        XCTAssertEqual(parts.map(\.firstIndex), [0, 3, 2])

        var withVideo = adasDayOne()
        withVideo.append(segment("v1", 9, "video", "Watch", done: false))
        let media = PlanDayParts.parts(try segments(withVideo))
        XCTAssertEqual(media.map(\.kind), [.media, .word, .respond, .talk], "a video stands alone, first")
        XCTAssertEqual(media.first?.id, "v1")
        XCTAssertTrue(PlanDayParts.parts([]).isEmpty)
    }

    func testAdasDayOneIsTwoOfThreePartsWithOneLeft() throws {
        let segs = try segments(adasDayOne())
        let p = PlanDayParts.progress(segs)
        XCTAssertEqual(p.done, 2)
        XCTAssertEqual(p.total, 3)
        XCTAssertEqual(PlanDayParts.pill(segs), "1 part left")

        XCTAssertEqual(PlanDayParts.pill(try segments(adasDayOne(nothingDone: true))), "Start", "a day not begun says Start")
        XCTAssertEqual(PlanDayParts.progress(segs, alsoDone: ["s3"]).done, 3, "a part finished this session counts")

        // Only The Word done: two parts left.
        var wordOnly = adasDayOne(nothingDone: true)
        for i in [0, 1, 4] { wordOnly[i]["completed"] = true }
        XCTAssertEqual(PlanDayParts.pill(try segments(wordOnly)), "2 parts left")
    }

    func testThePlansButtonFollowsProgress() throws {
        let fresh = adasDayOne(nothingDone: true)
        XCTAssertEqual(PlanDayParts.planButton(try detail([day(1, fresh), day(2, fresh, locked: true)])),
                       "Begin Day 1", "nothing done yet")
        XCTAssertEqual(PlanDayParts.planButton(try detail([day(1, adasDayOne()), day(2, fresh, locked: true)])),
                       "Continue · Day 1", "Ada: two parts of day 1 done — never Begin Day 1")
        let sealed = adasDayOne(talkDone: true)
        XCTAssertEqual(PlanDayParts.planButton(try detail([day(1, sealed, completed: true), day(2, fresh)])),
                       "Continue · Day 2", "the day the member is on")
        XCTAssertEqual(PlanDayParts.planButton(try detail([day(1, sealed, completed: true), day(2, sealed, completed: true)])),
                       "Read again")
    }

    // MARK: §7.4 #4 — the streak card: today is ticked only once a day is sealed

    func testTodaysLineCountsTheDayUnderWay() throws {
        let p = PlanDayParts.progress(try segments(adasDayOne()))
        XCTAssertEqual(PlanDayParts.todayLine(done: p.done, total: p.total), "Today: 2 of 3 parts", "Ada, before Talk it Over")
        XCTAssertNil(PlanDayParts.todayLine(done: 0, total: 3), "a day not begun keeps the invitation")
        XCTAssertNil(PlanDayParts.todayLine(done: 3, total: 3), "a sealed day is the tick, not a count")
    }

    func testATickNeverSitsBesideAZeroDayStreak() {
        XCTAssertEqual(StreakWords.count(0, todayDone: true), 1, "a day sealed today is a day of the streak")
        XCTAssertEqual(StreakWords.count(4, todayDone: true), 4)
        XCTAssertEqual(StreakWords.count(0, todayDone: false), 0)
        XCTAssertEqual(StreakWords.count(-2, todayDone: false), 0)
        XCTAssertEqual(StreakWords.title(StreakWords.count(0, todayDone: true)), "1-day streak")

        XCTAssertEqual(StreakWords.line(0, todayDone: false, today: "Today: 2 of 3 parts"), "Today: 2 of 3 parts",
                       "Ada before Talk it Over: no tick, the day's progress")
        XCTAssertEqual(StreakWords.line(1, todayDone: true, today: nil), "Today's reading is done 🔥")
        XCTAssertEqual(StreakWords.line(1, todayDone: true, today: "Today: 1 of 3 parts"), "Today's reading is done 🔥",
                       "a sealed day outranks the next day's progress")
        XCTAssertEqual(StreakWords.line(0, todayDone: false, today: nil), "Read today to start your streak 🔥")
        XCTAssertEqual(StreakWords.line(3, todayDone: false, today: nil), "Read today to keep it alive 🔥")
    }

    func testTheSealedDayIsTheNairobiDayAndForgottenAtSignOut() throws {
        let suite = "nuru.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let iso = ISO8601DateFormatter()
        let morning = try XCTUnwrap(iso.date(from: "2026-10-05T05:00:00Z"))   // 08:00 in Nairobi
        let lateEvening = try XCTUnwrap(iso.date(from: "2026-10-05T20:59:59Z")) // 23:59:59 in Nairobi
        let nextDay = try XCTUnwrap(iso.date(from: "2026-10-05T21:00:00Z"))    // midnight in Nairobi

        XCTAssertFalse(PlanDayLog.sealedToday(now: morning, in: defaults), "nothing sealed yet")
        PlanDayLog.noteSealed(now: morning, in: defaults)
        XCTAssertTrue(PlanDayLog.sealedToday(now: morning, in: defaults))
        XCTAssertTrue(PlanDayLog.sealedToday(now: lateEvening, in: defaults), "the same Nairobi day")
        XCTAssertFalse(PlanDayLog.sealedToday(now: nextDay, in: defaults), "the day turns at Nairobi's midnight")
        PlanDayLog.forget(in: defaults)
        XCTAssertFalse(PlanDayLog.sealedToday(now: morning, in: defaults), "signed out: the next member starts clean")
    }

    // MARK: §7.4 #3 — one card for the plan in progress

    private func planRow(_ id: String, enrolled: Bool = false, finished: Bool = false) -> [String: Any] {
        ["plan_id": id, "title": "Plan \(id)", "description": "Words.", "day_count": 7, "enrolled": enrolled,
         "current_day": 1, "completed_at": finished ? "2026-10-01T08:00:00Z" : NSNull()]
    }

    func testThePlanBeingReadIsNeverPromotedBesideItsContinueCard() throws {
        let rows = try decode([ReadingPlanRow].self, [planRow("first-steps", enrolled: true), planRow("b"), planRow("c")])
        // The local API's promos for Ada, in its order.
        let promos = try decode([PlanPromo].self, [
            ["plan_id": "first-steps", "slot": "continue", "kicker": "PICK UP WHERE YOU LEFT OFF"],
            ["plan_id": "b", "slot": "fresh", "kicker": "WORTH YOUR WEEK"],
            ["plan_id": "c", "slot": "fresh", "kicker": "FROM THE LIBRARY"],
        ])
        let resolved = PlanPicks.resolve(promos, in: rows)
        XCTAssertEqual(resolved.map(\.plan.planId), ["b", "c"], "First Steps has its one card: Continue reading")
        XCTAssertEqual(resolved.first?.kicker, "WORTH YOUR WEEK", "the hero is the next promo, in the server's order")

        XCTAssertTrue(PlanPicks.isBeingRead(rows[0]))
        XCTAssertFalse(PlanPicks.isBeingRead(rows[1]), "not started")
        let finished = try decode(ReadingPlanRow.self, planRow("done", enrolled: true, finished: true))
        XCTAssertFalse(PlanPicks.isBeingRead(finished), "a finished plan is not in Continue reading")
    }

    // MARK: §7.4 #6 — Events opens on the first tab that has something

    func testEventsOpensOnTheFirstTabThatHasSomething() {
        XCTAssertEqual(EventsViewModel.openingSegment(today: 0, upcoming: 12, rsvps: 1), .upcoming,
                       "Ada on a weekday: nothing today, the gatherings are Upcoming")
        XCTAssertEqual(EventsViewModel.openingSegment(today: 1, upcoming: 12, rsvps: 1), .today)
        XCTAssertEqual(EventsViewModel.openingSegment(today: 0, upcoming: 0, rsvps: 2), .rsvps)
        XCTAssertEqual(EventsViewModel.openingSegment(today: 0, upcoming: 0, rsvps: 0), .today, "nothing anywhere")
    }

    // MARK: §7.4 #7, #8 — the series the member follows, and the time once

    private func series(_ id: String, _ cadence: String, next: String? = nil, following: Bool = false) -> EventSeries {
        EventSeries(seriesId: id, title: "Series \(id)", category: "worship", cadence: cadence, nextAt: next,
                    nextOccurrenceId: nil, nextEndAt: nil, location: nil, following: following, newCount: 0)
    }

    func testSeriesYouFollowHoldsOnlyFollowedSeries() {
        let all = [series("a", "One-off · 3:00 PM"), series("b", "Every Sunday · 9:00 AM", following: true),
                   series("c", "Monthly · 3:00 PM"), series("d", "Every Sunday · 2:00 PM", following: true)]
        let split = EventSeries.split(all)
        XCTAssertEqual(split.following.map(\.seriesId), ["b", "d"])
        XCTAssertEqual(split.more.map(\.seriesId), ["a", "c"], "the rest, in the server's order")
        XCTAssertTrue(EventSeries.split([series("x", "Daily · 6:00 AM")]).following.isEmpty, "Ada follows none")
    }

    func testTheSeriesLineSaysItsTimeOnce() {
        let sunday = "2026-10-11T06:00:00.000Z"
        // The local API's own labels, as served for Ada.
        XCTAssertEqual(EventSeries.cadenceLine("Every Sunday · 9:00 AM", nextAt: sunday), "Every Sunday · 9:00 AM")
        XCTAssertEqual(EventSeries.cadenceLine("One-off · 3:00 PM", nextAt: nil), "One-off · 3:00 PM",
                       "a past one-off keeps its time")
        XCTAssertEqual(EventSeries.cadenceLine("Monthly · 3:30 PM", nextAt: "2026-10-25T12:30:00.000Z"), "Monthly · 3:30 PM")
        // A label without a time (an older server) borrows the next gathering's.
        let time = Ev.timeOfDate(Ev.date(sunday))
        XCTAssertEqual(EventSeries.cadenceLine("weekly", nextAt: sunday), "Every \(Ev.weekday(sunday, "EEEE")) · \(time)")
        XCTAssertEqual(EventSeries.cadenceLine("once", nextAt: nil), "One-off")
    }

    // MARK: §7.4 #12 — an announcement that isn't there speaks §4's words

    func testAMissingAnnouncementIsTheStateCardWithGoBack() {
        // The server's own answer for an announcement this member can't open.
        let gone = APIError.http(status: 404, code: "NOT_FOUND", message: "Announcement not found")
        let copy = NuruStateCopy.failure(gone, deviceOnline: true)
        XCTAssertEqual(copy.title, "This isn't here any more", "never the raw \"Announcement not found\"")
        XCTAssertEqual(copy.line, "It may have been moved or removed.")
        XCTAssertEqual(copy.action, .goBack, "Go back — Try again could not work")
        // A server error is ours, and retries.
        let ours = NuruStateCopy.failure(APIError.http(status: 503, code: nil, message: "Bad gateway"), deviceOnline: true)
        XCTAssertEqual(ours.title, "Something went wrong on our side")
        XCTAssertEqual(ours.action, .retry)
    }

    // MARK: §7.4 #15 — the Community header says what it counts

    func testTheCommunityHeaderCountsMessages() {
        XCTAssertEqual(ChatInboxViewModel.headerLine(unread: 0), "No new messages",
                       "never \"You're all caught up\" beside a bell with unread notices")
        XCTAssertEqual(ChatInboxViewModel.headerLine(unread: 1), "1 new message")
        XCTAssertEqual(ChatInboxViewModel.headerLine(unread: 4), "4 new messages")
        XCTAssertNil(ChatInboxViewModel.headerLine(unread: nil), "no count before the inbox has answered")
    }
}
