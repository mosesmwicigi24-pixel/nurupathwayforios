// Experience Cycles 5–10, combined (pathway docs/EXPERIENCE.md §9): journeys,
// context, states under stress, one product, fewer and better things — the
// rules pinned. Payloads are decoded exactly like APIClient's: snake_case in.
import XCTest
import SwiftUI
@testable import NuruMember

final class ExperienceCycle5Tests: XCTestCase {

    // MARK: Fixtures — the wire shapes

    func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func module(_ id: String, level: Int = 1, seq: Int, _ status: String, completed: Bool = false,
                kind: String = "none", title: String? = nil, minutes: Int = 10) -> [String: Any] {
        ["module_id": id, "level_number": level, "module_sequence_number": seq, "title": title ?? "Module \(id)",
         "summary": NSNull(), "estimated_minutes": minutes, "evaluation_kind": kind, "quiz_pass_mark": 70,
         "completed": completed, "status": status, "progress": completed ? 100 : 0, "locked": status == "locked"]
    }

    // MARK: §9.2 #1 — the exam has one name and a front door

    func testTheExamHasOneName() throws {
        XCTAssertEqual(ExamWords.name(1), "Level 1 exam")
        // The server titles the exam container "Level 1 Review"; a row shows the one name.
        let rows = try decode([LevelModule].self, [
            module("exam", seq: 900, "next", kind: "exit_exam", title: "Level 1 Review"),
            module("m1", seq: 1, "completed", completed: true, title: "God & His Nature")])
        XCTAssertEqual(ExamWords.rowTitle(rows[0]), "Level 1 exam")
        XCTAssertEqual(ExamWords.rowTitle(rows[1]), "God & His Nature")
        XCTAssertEqual(ExamWords.passedTitle(1), "You passed the Level 1 exam")
        XCTAssertEqual(ExamWords.failLine(1, passMark: 80),
                       "You need 80% to pass the Level 1 exam. Look back over Level 1's lessons — then try again.")
    }

    func testTheExamOpensOnItsFrontDoorWithTheServersCountAndMark() {
        let door = ExamWords.frontDoor(levelNumber: 1, questionCount: 91, passMark: 80)
        XCTAssertEqual(door.title, "The Level 1 exam")
        XCTAssertEqual(door.facts, "91 questions · pass mark 80%")
        XCTAssertEqual(door.lines, ["Your answers are kept if you leave — you pick up at the question you were on.",
                                    "A pass opens the way to Level 2."])
        XCTAssertEqual(door.begin, "Begin")
        // The last level opens the way to being sent (§3's words for it).
        XCTAssertEqual(ExamWords.frontDoor(levelNumber: 6, questionCount: 40, passMark: 80, isLastLevel: true).lines.last,
                       "A pass opens the way to being sent.")
        // An older server sends no mark: the count alone, never "pass mark nil%".
        XCTAssertEqual(ExamWords.facts(questionCount: 12, passMark: nil), "12 questions")
        XCTAssertEqual(ExamWords.facts(questionCount: 1, passMark: 0), "1 question")
        // One name: no word on the way in or out calls it a review or a module.
        let words = [door.title, door.facts] + door.lines + [ExamWords.passedTitle(1), ExamWords.failLine(1, passMark: 80)]
        for w in words {
            XCTAssertFalse(w.lowercased().contains("review") || w.lowercased().contains("module"), w)
        }
    }

    // MARK: §9.2 #2 — "What needs you today" never repeats a YOUR WEEK row

    func nudge(_ kind: String, route: String = "", _ params: [String: Any] = [:]) throws -> HomeNudge {
        try decode(HomeNudge.self, ["id": kind, "kind": kind, "title": kind, "body": "", "cta_label": "Open",
                                    "route": route, "params": params, "accent": "gold", "priority": 50])
    }

    func plan(_ id: String, day: Int = 2, done: [Int] = [1], lastFinished: String? = nil) throws -> ReadingPlanRow {
        var row: [String: Any] = ["plan_id": id, "title": "First Steps", "day_count": 7, "current_day": day,
                                  "completed_days": done, "enrolled": true]
        if let lastFinished { row["last_day_finished_at"] = lastFinished }
        return try decode(ReadingPlanRow.self, row)
    }

    func testTheRailDropsANudgeAYourWeekRowAlreadyAsks() throws {
        let examWeek = [HomeWeekRow(pillar: .pathway, title: "Take the Level 1 exam", line: "Level 1 · Exam ready",
                                    destination: .journey(.exam(1)))]
        // Ada: the server's exam nudge (route level_exam) over the row that offers it.
        XCTAssertTrue(HomeWeek.repeats(try nudge("level_review", route: "level_exam", ["levelNumber": 1]), in: examWeek))
        XCTAssertTrue(HomeWeek.repeats(try nudge("level_review", ["level_number": 1]), in: examWeek))
        let learningWeek = [HomeWeekRow(pillar: .pathway, title: "Continue · Identity in Christ", line: "Level 1",
                                        destination: .journey(.module("m6")))]
        XCTAssertFalse(HomeWeek.repeats(try nudge("level_review", ["levelNumber": 1]), in: learningWeek))
        XCTAssertTrue(HomeWeek.repeats(try nudge("quiz_in_progress", ["moduleId": "m6"]), in: learningWeek))
        XCTAssertFalse(HomeWeek.repeats(try nudge("quiz_in_progress", ["moduleId": "m2"]), in: learningWeek))

        let week = learningWeek + [
            HomeWeekRow(pillar: .plans, title: "First Steps", line: "Day 2 of 7 · today's reading", destination: .planDay(try plan("p1"))),
            HomeWeekRow(pillar: .cell, title: "Dev Cell A", line: "Next gathering Mon 5 Oct", destination: .cell)]
        XCTAssertTrue(HomeWeek.repeats(try nudge("plan_day_due", ["planId": "p1"]), in: week))
        XCTAssertFalse(HomeWeek.repeats(try nudge("plan_day_due", ["planId": "p9"]), in: week))
        XCTAssertTrue(HomeWeek.repeats(try nudge("cell_gathering"), in: week))
        // Reflection, the letter, invites and messages are no row's — they stay.
        for k in ["reflection_due", "letter_unread", "reading_invite", "chat_unread"] {
            XCTAssertFalse(HomeWeek.repeats(try nudge(k), in: week), k)
        }
        // No cell: the row asks to be connected; a gathering isn't its.
        let noCell = [HomeWeekRow(pillar: .cell, title: "Ask to be connected", line: "", destination: .community)]
        XCTAssertFalse(HomeWeek.repeats(try nudge("cell_gathering"), in: noCell))
    }

    // MARK: §9.2 #3 — "Day 3 done today · Day 4 next"; one streak; one first day

    /// Mon 5 Oct 2026, 15:00 in Nairobi.
    let monday = ISO8601DateFormatter().date(from: "2026-10-05T12:00:00Z")!

    func testTodaysReadingIsOneStoryOnHomeAndPlans() throws {
        // Ada: First Steps, Days 1–3 done, Day 3 finished this morning.
        let ada = try plan("first", day: 4, done: [1, 2, 3], lastFinished: "2026-10-05T08:45:28.123Z")
        XCTAssertTrue(PlanLines.readToday(ada, now: monday))
        XCTAssertEqual(PlanLines.todayLine(ada, readToday: true, now: monday), "Day 3 done today · Day 4 next")
        XCTAssertEqual(PlanLines.cardLine(ada, readToday: true, now: monday), "Day 3 done today · Day 4 next")
        let row = HomeWeek.plansRow([ada], now: monday)
        XCTAssertEqual(row.line, "Day 3 done today · Day 4 next")
        // Read yesterday: today's reading is still to do.
        let yesterday = try plan("first", day: 4, done: [1, 2, 3], lastFinished: "2026-10-04T18:00:00Z")
        XCTAssertFalse(PlanLines.readToday(yesterday, now: monday))
        XCTAssertEqual(HomeWeek.plansRow([yesterday], now: monday).line, "Day 4 of 7 · today's reading")
        // This phone sealed a day today before the server says so.
        XCTAssertEqual(HomeWeek.plansRow([yesterday], sealedHere: true, now: monday).line, "Day 3 done today · Day 4 next")
        // Day 1 read today.
        XCTAssertEqual(PlanLines.doneLine(try plan("first", day: 1, done: []), readToday: true), "Done today · Day 1 next")
        // Nairobi's midnight, not UTC's: 22:30 UTC on the 4th is the 5th in Nairobi.
        let lateNight = try plan("first", day: 4, done: [1, 2, 3], lastFinished: "2026-10-04T22:30:00Z")
        XCTAssertTrue(PlanLines.readToday(lateNight, now: monday))
    }

    func testTheStreakIsOneStreakCountedOneWay() {
        // Today counts once the member was active today — at least 1.
        XCTAssertEqual(StreakWords.days(0, activeToday: false), 0)
        XCTAssertEqual(StreakWords.days(0, activeToday: true), 1)
        XCTAssertEqual(StreakWords.days(4, activeToday: true), 4)
        XCTAssertEqual(StreakWords.days(-1, activeToday: false), 0)
        XCTAssertEqual(StreakWords.title(StreakWords.days(0, activeToday: true)), "1-day streak")
        // No emoji in the words (§8.1 rule 7).
        for line in [StreakWords.line(0), StreakWords.line(3), StreakWords.line(1, todayDone: true, today: nil)] {
            XCTAssertFalse(line.unicodeScalars.contains { $0.properties.isEmojiPresentation }, line)
        }
    }

    func testEveryWeekStripStartsOnSunday() {
        XCTAssertEqual(HomeWeekChain.days, ["S", "M", "T", "W", "T", "F", "S"])
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Africa/Nairobi")!
        XCTAssertEqual(HomeWeekChain.todayIndex(monday, calendar: cal), 1, "Monday sits second, after Sunday")
        let sunday = monday.addingTimeInterval(-86_400)
        XCTAssertEqual(HomeWeekChain.todayIndex(sunday, calendar: cal), 0)
    }

    // MARK: §9.2 #4 — a first day leads with the path's first step; verbs on every row

    func level(_ n: Int, _ status: String, done: Int = 0, of total: Int = 0, title: String? = nil,
               theme: String? = nil, awaiting: Bool = false) -> [String: Any] {
        ["level_number": n, "title": title ?? "Level \(n) title", "theme": theme ?? NSNull(), "description": NSNull(),
         "total_modules": total, "completed_modules": done, "lessons_total": total, "lessons_completed": done,
         "minutes": 0, "status": status, "awaiting_review": awaiting, "exam_published": true, "exam_available": true]
    }

    func summary(current: Int = 1, _ levels: [[String: Any]]) throws -> PathwaySummary {
        try decode(PathwaySummary.self, ["current_level": current, "levels": levels])
    }

    /// Ben (new, nothing started): Level 1's ten lessons, the first open.
    func bensJourney() throws -> Journey {
        let s = try summary([level(1, "active", done: 0, of: 10, title: "Foundations of Faith"),
                             level(2, "locked"), level(3, "locked")])
        let trail = try decode([LevelModule].self, [module("m1", seq: 1, "next", title: "God & His Nature"),
                                                    module("m2", seq: 2, "locked", title: "God's Plan for Humanity")])
        return try XCTUnwrap(Journey.derive(s, trail: trail))
    }

    func testAFirstDayLeadsWithStartLevelOne() throws {
        let ben = try bensJourney()
        XCTAssertTrue(ben.isFirstDay)
        let row = HomeWeek.pathwayRow(ben, enrolledLevel: 1)
        XCTAssertEqual(row.title, "Start Level 1 · God & His Nature")
        // No zero counts: what lies ahead.
        XCTAssertEqual(row.line, "Level 1 · 10 modules")
        XCTAssertEqual(ben.progressLine.bold, "10 modules")
        XCTAssertEqual(PathwayTrail.headerLine(try summary([level(1, "active", done: 0, of: 10)]).levels.first,
                                               position: 1, of: 6), "Level 1 of 6 · 10 modules")
        XCTAssertEqual(ben.progressPercent, 0, "Pathway's ring stays hidden at 0")
        // The second lesson continues; Level 2's first lesson is not a first day.
        let cara = try XCTUnwrap(Journey.derive(try summary([level(1, "active", done: 2, of: 10)]),
                                                trail: try decode([LevelModule].self, [module("m3", seq: 3, "next", title: "Salvation by Grace")])))
        XCTAssertFalse(cara.isFirstDay)
        XCTAssertEqual(HomeWeek.pathwayRow(cara, enrolledLevel: 1).title, "Continue · Salvation by Grace")
        let levelTwo = try XCTUnwrap(Journey.derive(try summary(current: 2, [level(1, "completed", done: 10, of: 10), level(2, "active", done: 0, of: 8)]),
                                                    trail: try decode([LevelModule].self, [module("n1", level: 2, seq: 1, "next", title: "Abiding")])))
        XCTAssertFalse(levelTwo.isFirstDay)
        XCTAssertEqual(HomeWeek.pathwayRow(levelTwo, enrolledLevel: 2).title, "Start Level 2 · Abiding")
    }

    func testEveryWeekRowSaysItsVerb() throws {
        let begun = try plan("p1", day: 1, done: [])
        XCTAssertEqual(HomeWeek.plansRow([begun], now: monday).title, "Start · First Steps")
        let cara = try plan("p1", day: 2, done: [1], lastFinished: "2026-10-01T09:33:50.486Z")
        XCTAssertEqual(HomeWeek.plansRow([cara], now: monday).title, "Continue · First Steps")
        let ada = try plan("p1", day: 4, done: [1, 2, 3], lastFinished: "2026-10-05T08:45:28.123Z")
        XCTAssertEqual(HomeWeek.plansRow([ada], now: monday).title, "Done today · First Steps")
        XCTAssertEqual(HomeWeek.plansRow(nil).title, "Start a reading plan")
        let quiet = HomeWeek.eventsRow(calendar: [], home: [], rsvps: [], now: monday, timeZone: TimeZone(identifier: "Africa/Nairobi")!)
        XCTAssertEqual(quiet.title, "See the church calendar")
        XCTAssertEqual(quiet.line, "No gatherings this week")
    }

    func testOnAFirstDayTheReflectionWaitsButAPersonNeverDoes() throws {
        let ben = try bensJourney()
        let week = [HomeWeek.pathwayRow(ben, enrolledLevel: 1)]
        func held(_ n: HomeNudge) -> Bool { ben.isFirstDay && n.kind == "reflection_due" }
        XCTAssertTrue(held(try nudge("reflection_due", route: "devotional")))
        for k in ["chat_unread", "reading_invite", "letter_unread"] { XCTAssertFalse(held(try nudge(k)), k) }
        XCTAssertFalse(HomeWeek.repeats(try nudge("reflection_due"), in: week), "held for the first day, not as a repeat")
    }

    // MARK: §9.2 #5 — a pause named kindly, once

    func testAPauseIsNamedByTheDayItBeganAndTheDayThatWaits() throws {
        // Cara: First Steps, Day 1 finished on Thursday 1 Oct; Monday now.
        let cara = try plan("first", day: 2, done: [1], lastFinished: "2026-10-01T09:33:50.486Z")
        XCTAssertNotNil(PlanLines.pausedOn(cara, now: monday))
        XCTAssertEqual(PlanLines.todayLine(cara, readToday: false, now: monday), "You paused on Thursday — Day 2 is waiting")
        XCTAssertEqual(PlanLines.cardLine(cara, readToday: false, now: monday), "You paused on Thursday — Day 2 is waiting")
        XCTAssertEqual(HomeWeek.plansRow([cara], now: monday).line, "You paused on Thursday — Day 2 is waiting")
        // Further back than a week: the date.
        let longAgo = try plan("first", day: 2, done: [1], lastFinished: "2026-09-24T09:00:00Z")
        XCTAssertEqual(PlanLines.todayLine(longAgo, readToday: false, now: monday), "You paused on Thu 24 Sep — Day 2 is waiting")
        // Yesterday's reading is not a pause; nor a plan with no day finished, nor a finished plan.
        XCTAssertNil(PlanLines.pausedOn(try plan("first", day: 2, done: [1], lastFinished: "2026-10-04T18:00:00Z"), now: monday))
        XCTAssertNil(PlanLines.pausedOn(try plan("first", day: 1, done: []), now: monday))
        var finished = try decode(ReadingPlanRow.self,
                                  ["plan_id": "first", "title": "First Steps", "day_count": 7, "current_day": 7,
                                   "completed_days": [1, 2, 3, 4, 5, 6, 7], "enrolled": true,
                                   "completed_at": "2026-10-02T08:00:00Z", "last_day_finished_at": "2026-10-02T08:00:00Z"])
        XCTAssertNil(PlanLines.pausedOn(finished, now: monday))
        finished = cara
        // Read today, the done line wins.
        XCTAssertEqual(PlanLines.todayLine(finished, readToday: true, now: monday), "Day 1 done today · Day 2 next")
        // Never a count of days missed.
        XCTAssertFalse(PlanLines.todayLine(cara, readToday: false, now: monday).contains("days"))
    }

    // MARK: §9.2 #7 — "Level 2 is being prepared — we'll let you know"

    func testANextLevelWithNoLessonsIsBeingPrepared() throws {
        // Eli: passed the Level 1 exam; Level 2 has no lessons.
        let eli = try summary([level(1, "awaiting_review", done: 10, of: 10, awaiting: true), level(2, "locked"), level(3, "locked")])
        let j = try XCTUnwrap(Journey.derive(eli))
        XCTAssertEqual(j.stage, .awaitingUsher)
        XCTAssertEqual(j.title, "Level 2 is being prepared")
        XCTAssertEqual(j.line, "You passed the Level 1 exam — we'll let you know when Level 2 opens.")
        XCTAssertFalse(j.line.contains("leader") || j.line.contains("discipler"), "one word, no promise")
        XCTAssertTrue(UsherWords.nextPreparing(after: 1, in: eli))
        // A Level 2 with lessons keeps the leader's words.
        let ready = try summary([level(1, "awaiting_review", done: 10, of: 10, awaiting: true), level(2, "locked", of: 8)])
        let jr = try XCTUnwrap(Journey.derive(ready))
        XCTAssertEqual(jr.title, "Level 2 is next")
        XCTAssertEqual(jr.line, "You passed the Level 1 exam. Your leader will open Level 2 — you'll get a notice.")
        XCTAssertFalse(UsherWords.nextPreparing(after: 1, in: ready))
        // Map view's lock lines say the same.
        let ada = try XCTUnwrap(Journey.derive(try summary([level(1, "completed", done: 10, of: 10), level(2, "locked")])))
        XCTAssertEqual(ada.stage, .examReady)
        XCTAssertEqual(LevelsMapWords.lockLine(levelNumber: 2, journey: ada, preparing: true),
                       "Pass the Level 1 exam — Level 2 is being prepared")
        XCTAssertEqual(LevelsMapWords.lockLine(levelNumber: 2, journey: j, preparing: true),
                       "Level 2 is being prepared — we'll let you know")
        XCTAssertEqual(LevelsMapWords.lockLine(levelNumber: 3, journey: j, preparing: true), "Level 3 is being prepared")
    }

    // MARK: §9.2 #8 — with no discipler, it's said once

    @MainActor
    func testNoDisciplerIsSaidOnceInOneSentence() throws {
        XCTAssertEqual(DisciplerStore.noneLine, "No discipler yet — your leader will pair you")
        // Offers of a discipler (Pathway's row, the level page, Community's tab) wait for one the server names.
        XCTAssertFalse(DisciplerStore.offers(nil))
        let none = try decode(MentorInfo.self, ["mentor": NSNull(), "notes": []])
        XCTAssertFalse(DisciplerStore.offers(none.mentor))
    }

    // MARK: §9.2 #9 — the rail names each level by its own theme

    func testTheRailNamesEachLevelByItsTheme() throws {
        let s = try summary([level(1, "active", of: 10, title: "Foundations of Faith", theme: "Foundations"),
                             level(3, "locked", title: "Foundations of Grace & Kingdom Perspective", theme: "Grace"),
                             level(6, "locked", title: "Level 6"),
                             level(7, "locked", title: " ", theme: " ")])
        XCTAssertEqual(s.levels.map(levelShortName), ["Foundations", "Grace", "Level 6", "Level 7"],
                       "never two \"Foundations\"; no theme: the title itself, never a stray first word")
    }

    // MARK: §9.2 #10 — the ring counts the exam as the level's last step

    func testTheExamIsTheLevelsLastStep() throws {
        XCTAssertEqual(Journey.levelFraction(lessonsDone: 10, lessonCount: 10, examPassed: false), 10.0 / 11, accuracy: 0.0001)
        XCTAssertEqual(Journey.levelFraction(lessonsDone: 10, lessonCount: 10, examPassed: true), 1)
        XCTAssertEqual(Journey.levelFraction(lessonsDone: 0, lessonCount: 0, examPassed: false), 0, "nothing published: nothing walked")
        // Ada (exam not sat) and Eli (exam passed) no longer read the same ring.
        let ada = try XCTUnwrap(Journey.derive(try summary([level(1, "completed", done: 10, of: 10), level(2, "locked"), level(3, "locked"),
                                                            level(4, "locked"), level(5, "locked"), level(6, "locked")])))
        let eli = try XCTUnwrap(Journey.derive(try summary([level(1, "awaiting_review", done: 10, of: 10, awaiting: true), level(2, "locked"),
                                                            level(3, "locked"), level(4, "locked"), level(5, "locked"), level(6, "locked")])))
        XCTAssertEqual(ada.progressPercent, 15)   // (10/11) / 6
        XCTAssertEqual(eli.progressPercent, 17)   // 1 / 6
        // The level's own percent: 91 until the exam is passed, then 100.
        let one = try summary([level(1, "completed", done: 10, of: 10)]).levels[0]
        XCTAssertEqual(Journey.levelPercent(one, journey: ada), 91)
        let passed = try summary([level(1, "awaiting_review", done: 10, of: 10, awaiting: true)]).levels[0]
        XCTAssertEqual(Journey.levelPercent(passed, journey: eli), 100)
    }

    // MARK: §9.2 #12 — "Find your cell" becomes "Ask to be connected"

    func testAskingToBeConnectedSaysWhereItWent() throws {
        let nairobi = TimeZone(identifier: "Africa/Nairobi")!
        XCTAssertEqual(CellConnectWords.sent("2026-10-05T09:30:00Z", now: monday, timeZone: nairobi),
                       "Sent to your pastor on Mon 5 Oct — they'll connect you")
        XCTAssertEqual(CellConnectWords.sent("2025-12-28T09:30:00Z", now: monday, timeZone: nairobi),
                       "Sent to your pastor on Sun 28 Dec 2025 — they'll connect you", "the year when it isn't this year")
        XCTAssertEqual(CellConnectWords.sent("not a date", now: monday), "Sent to your pastor — they'll connect you")
        // The row: before and after asking.
        let ask = HomeWeek.cellRow(nil, timeZone: nairobi, now: monday)
        XCTAssertEqual(ask.title, "Find your cell")
        XCTAssertEqual(ask.line, "Ask to be connected — tell the church where you live.")
        XCTAssertEqual(ask.destination, .cellConnect)
        XCTAssertEqual(HomeWeek.cellRow(nil, askedAt: "2026-10-05T09:30:00Z", timeZone: nairobi, now: monday).line,
                       "Sent to your pastor on Mon 5 Oct — they'll connect you")
        // "Ask the church" waits for the server's bounds.
        XCTAssertFalse(CellConnectWords.canAsk(area: "K", availability: "Evenings", note: ""))
        XCTAssertTrue(CellConnectWords.canAsk(area: "Kasarani", availability: "Weekday evenings", note: ""))
        XCTAssertFalse(CellConnectWords.canAsk(area: "Kasarani", availability: "Weekday evenings", note: String(repeating: "a", count: 301)))
        // The wire: in a cell, asked, neither.
        XCTAssertTrue(try decode(CellConnectionStatus.self, ["in_cell": true, "request": NSNull()]).inCell)
        let asked = try decode(CellConnectionStatus.self, ["in_cell": false,
                                                           "request": ["requested_at": "2026-10-05T09:30:00Z", "conversation_id": "c1"]])
        XCTAssertEqual(asked.request?.conversationId, "c1")
    }

    // MARK: §9.3 #1 — a claim the office is checking sits on the DUE row it covers

    func due(_ id: String = "roof", dueOn: String = "2026-12-31", amount: Int = 2_000_000, claim: Int? = nil,
             kind: String = "pledge", currency: String = "KES", overdueSince: String? = nil) throws -> DueItem {
        var row: [String: Any] = ["kind": kind, "id": id, "title": "Roof sheets for the new hall", "amount_minor": amount,
                                  "currency": currency, "due_on": dueOn, "action": "pay", "pending_minor": 0]
        if let claim { row["pending_claim_minor"] = claim }
        if let overdueSince { row["overdue_since"] = overdueSince }
        return try decode(DueItem.self, row)
    }

    func testAClaimBeingCheckedIsSaidOnItsRowNeverSubtracted() throws {
        let ada = try due(claim: 200_000)
        XCTAssertEqual(ada.claimLine, "KSh 2,000 is being checked by the office")
        XCTAssertEqual(ada.amountMinor, 2_000_000, "the row still asks what is owed")
        XCTAssertNil(try due(claim: 0).claimLine)
        XCTAssertNil(try due().claimLine, "an older server: nothing is said")
        XCTAssertNil(try due(claim: 200_000, kind: "schedule").claimLine, "a recurring gift's run carries no claims")
        // Postgres NUMERIC can arrive as a string.
        let numeric = try decode(DueItem.self, ["kind": "pledge", "id": "roof", "title": "Roof", "amount_minor": 2_000_000,
                                                "currency": "KES", "due_on": "2026-12-31", "action": "pay",
                                                "pending_claim_minor": "200000"])
        XCTAssertEqual(numeric.pendingClaimMinor, 200_000)
    }

    // MARK: §9.3 #2 — "DUE" only within the fortnight

    func testDueOnlyWithinTheFortnight() throws {
        let today = "2026-10-05"
        XCTAssertTrue(HomeWeek.dueIsSoon(try due(dueOn: "2026-10-19"), today: today), "the 14th day")
        XCTAssertFalse(HomeWeek.dueIsSoon(try due(dueOn: "2026-10-20"), today: today), "the 15th day is coming up")
        XCTAssertFalse(HomeWeek.dueIsSoon(try due(dueOn: "2026-12-31"), today: today), "Ada's 31 Dec, 87 days ahead")
        XCTAssertTrue(HomeWeek.dueIsSoon(try due(dueOn: "2026-10-01"), today: today), "overdue is always due")
        XCTAssertTrue(HomeWeek.dueIsSoon(try due(dueOn: "2026-12-31", overdueSince: "2026-09-01"), today: today),
                      "late by the server's word")
        XCTAssertTrue(HomeWeek.dueIsSoon(try due(dueOn: ""), today: today), "an undated row stays DUE")
    }

    // MARK: §9.3 #3 — the time of day agrees

    func testTheGreetingKeepsTheLiturgysClock() {
        // Never "Good afternoon" over EVENING, nor "Good morning" over NIGHT.
        for h in 0..<24 {
            let part = ChurchClock.part(hour: h)
            let greeting = HomeHeaderWords.timeGreeting(hour: h, sunday: false)
            switch part {
            case .evening: XCTAssertEqual(greeting, "Good evening", "\(h):00")
            case .night: XCTAssertEqual(greeting, "Rest well", "\(h):00")
            case .morning: XCTAssertEqual(greeting, "Good morning", "\(h):00")
            case .midday: XCTAssertTrue(["Good morning", "Good afternoon"].contains(greeting), "\(h):00")
            }
        }
        XCTAssertEqual(HomeHeaderWords.timeGreeting(hour: 16, sunday: false), "Good evening", "Ben at 16:32")
        XCTAssertEqual(HomeHeaderWords.timeGreeting(hour: 1, sunday: false), "Rest well", "after midnight")
        XCTAssertEqual(HomeHeaderWords.timeGreeting(hour: 16, sunday: true), "Happy Lord's Day")
        // The church's clock: 13:30 UTC is 16:30 in Nairobi.
        XCTAssertEqual(ChurchClock.part(ISO8601DateFormatter().date(from: "2026-10-05T13:30:00Z")!), .evening)
    }

    // MARK: Cycle 4 walk, §8.1 rule 8 — the rhythm tiles in plain words

    func testTheRhythmTilesSpeakPlainly() {
        XCTAssertEqual(RhythmTileWords.status("prayer", done: true), "Prayed")
        XCTAssertEqual(RhythmTileWords.status("word", done: true), "Read")
        XCTAssertEqual(RhythmTileWords.status("reflection", done: true), "Written")
        for k in ["prayer", "word", "reflection"] {
            XCTAssertEqual(RhythmTileWords.status(k, done: false), "Not yet")
            for w in [RhythmTileWords.status(k, done: true), RhythmTileWords.status(k, done: false)] {
                XCTAssertNotEqual(w, w.uppercased(), "never a capitalised status that reads like data")
            }
        }
    }

    func testTheExamReadsItsPassMarkFromTheServer() throws {
        let exam = try decode(AssembledExam.self, ["level_number": 1, "question_count": 91, "pass_mark": 80, "questions": []])
        XCTAssertEqual(exam.passMark, 80)
        XCTAssertEqual(exam.questionCount, 91)
        // Postgres NUMERIC arrives as a string from production.
        XCTAssertEqual(try decode(AssembledExam.self, ["level_number": 1, "question_count": 3, "pass_mark": "80.00", "questions": []]).passMark, 80)
        // An older server: absent, so the door says the count alone.
        XCTAssertNil(try decode(AssembledExam.self, ["level_number": 1, "question_count": 3, "questions": []]).passMark)
    }

    // MARK: Cycle 4 walk — every back control is the "←" arrow

    /// Map view's back was a "‹" while every other pushed page wore "←" — and
    /// so were ten more, from a plan's pages to the inbox. A chevron left now
    /// only steps a pager, each listed here by its line.
    func testEveryBackControlIsTheArrow() throws {
        let pagers: Set<String> = [
            "Features/Pathway/ModuleView.swift: arrow(.chevronLeft, enabled: current > 0) { onSelect(current - 1) }",
            "Features/Events/CalendarView.swift: navButton(.chevronLeft) { stepMonth(-1) }",
        ]
        var found: Set<String> = []
        for (rel, text) in try TypeScan.files() where rel != "Theme/LucideIcons.swift" {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) where line.contains(".chevronLeft") {
                found.insert("\(rel): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertEqual(found, pagers, "a back control wears Lucide's arrow-left, like every pushed page; a chevron only steps a pager")
    }

    // MARK: Cycle 4 walk — no zero counts: "0 of 0 done" is "Level N is being prepared"

    func testALevelWithNothingPublishedIsBeingPreparedNeverZeroOfZero() throws {
        let s = try summary([level(1, "active", done: 3, of: 10), level(2, "active", done: 0, of: 10),
                             level(3, "locked", done: 0, of: 0), level(4, "completed", done: 1, of: 1)])
        let (walking, notBegun, empty, single) = (s.levels[0], s.levels[1], s.levels[2], s.levels[3])
        XCTAssertEqual(PathwayTrail.sectionCountLine(empty), "Level 3 is being prepared")
        XCTAssertEqual(PathwayTrail.emptyListLine(empty), "Its modules open soon — we'll let you know.")
        XCTAssertEqual(PathwayTrail.cardCountLine(empty), "Level 3 is being prepared")
        // Not begun: what lies ahead, never "0 of 10".
        XCTAssertEqual(PathwayTrail.sectionCountLine(notBegun), "10 modules")
        XCTAssertEqual(PathwayTrail.cardCountLine(notBegun), "10 modules")
        XCTAssertEqual(PathwayTrail.sectionCountLine(walking), "3 of 10 done")
        XCTAssertEqual(PathwayTrail.cardCountLine(walking), "3/10 modules")
        XCTAssertEqual(PathwayTrail.sectionCountLine(single), "1 of 1 done")
        XCTAssertEqual(PathwayTrail.emptyListLine(walking), "Modules open as you progress.",
                       "a level with lessons the member can't see yet opens as they go")
        for l in s.levels {
            XCTAssertFalse(PathwayTrail.sectionCountLine(l).hasPrefix("0 "), "no zero count")
            XCTAssertFalse(PathwayTrail.cardCountLine(l).hasPrefix("0/"), "no zero count")
        }
    }

    // MARK: Owner, 2026-10-06 — the featured video takes its own shape

    func testTheFeaturedVideoTakesItsOwnShape() throws {
        // Portrait gets a tall frame, landscape a wide one: width ÷ height.
        XCTAssertEqual(try XCTUnwrap(VideoShape.ratio(CGSize(width: 1080, height: 1920))), 1080.0 / 1920.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(VideoShape.ratio(CGSize(width: 1920, height: 1080))), 1920.0 / 1080.0, accuracy: 0.0001)
        // A portrait clip stored landscape with a 90° turn is portrait: the
        // stored size through the track's transform, as absolute values —
        // a pure turn, and the turn-and-shift an iPhone writes.
        for t in [CGAffineTransform(rotationAngle: .pi / 2), CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0),
                  CGAffineTransform(rotationAngle: -.pi / 2)] {
            let seen = VideoShape.displaySize(natural: CGSize(width: 1920, height: 1080), transform: t)
            XCTAssertEqual(seen.width, 1080, accuracy: 0.5)
            XCTAssertEqual(seen.height, 1920, accuracy: 0.5)
        }
        XCTAssertEqual(VideoShape.displaySize(natural: CGSize(width: 1920, height: 1080), transform: .identity),
                       CGSize(width: 1920, height: 1080))
        // Clamped to 9:20 … 21:9; nothing for a size with no area.
        XCTAssertEqual(VideoShape.ratio(CGSize(width: 100, height: 1000)), 9.0 / 20.0)
        XCTAssertEqual(VideoShape.ratio(CGSize(width: 4000, height: 1000)), 21.0 / 9.0)
        XCTAssertNil(VideoShape.ratio(.zero))
        XCTAssertNil(VideoShape.ratio(CGSize(width: 1920, height: 0)))
        // Before anything is known, 16:9; the video's own shape (remembered
        // or measured) beats its thumbnail's.
        XCTAssertEqual(VideoShape.resolve(video: nil, thumbnail: nil), 16.0 / 9.0)
        XCTAssertEqual(VideoShape.resolve(video: nil, thumbnail: 0.5625), 0.5625)
        XCTAssertEqual(VideoShape.resolve(video: 0.5625, thumbnail: 16.0 / 9.0), 0.5625)
        // An embed's player keeps its own 16:9; a file's shape is read.
        for s in ["youtube", "vimeo", "YouTube"] { XCTAssertFalse(VideoShape.learnsShape(source: s), s) }
        for s in ["direct", "cloudinary", "private"] { XCTAssertTrue(VideoShape.learnsShape(source: s), s) }
        // Home's player fills its frame (no bars); every other host fits.
        let u = try XCTUnwrap(URL(string: "https://example.com/v.mp4"))
        XCTAssertTrue(InlineVideoPlayer.html(for: u, fill: true).contains("object-fit:cover"))
        XCTAssertTrue(InlineVideoPlayer.html(for: u).contains("object-fit:contain"))
    }

    @MainActor
    func testAMeasuredShapeIsRememberedForTheNextFirstPaint() throws {
        let suite = "nuru.tests.videoShape.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = VideoShapeStore(defaults: defaults)
        XCTAssertNil(store.ratio(for: "m1"), "nothing remembered yet: the card starts at 16:9")
        store.remember(1080.0 / 1920.0, for: "m1")
        XCTAssertEqual(try XCTUnwrap(store.ratio(for: "m1")), 0.5625, accuracy: 0.0001)
        // The next launch: a fresh store over the same defaults has it at once.
        let next = VideoShapeStore(defaults: defaults)
        XCTAssertEqual(try XCTUnwrap(next.ratio(for: "m1")), 0.5625, accuracy: 0.0001)
        XCTAssertNil(next.ratio(for: "m2"), "remembered per media asset")
        next.remember(10, for: "m3")
        XCTAssertEqual(next.ratio(for: "m3"), 21.0 / 9.0, "remembered clamped")
        next.remember(.nan, for: "m4")
        XCTAssertNil(next.ratio(for: "m4"), "nothing nonsensical is kept")
    }

    // MARK: Cycle 4 walk — one Word score, the server's

    func testMemoryVersesShowTheServersWordScore() throws {
        let b = try decode(ScoreBreakdown.self, ["score": 2, "band": "Just beginning",
                                                 "components": ["consistency": 5, "memorization": 0, "breadth": 0],
                                                 "detail": ["verses_engaged": 0, "verses_mastered": 0]])
        let w = WordScoreWords(b)
        XCTAssertEqual(w.score, 2, "Home's Word score, not mastered ÷ total")
        XCTAssertEqual(w.band, "Just beginning", "the server's band: one score vocabulary")
        XCTAssertEqual(w.consistency, 0.05, accuracy: 0.0001)
        XCTAssertEqual(w.memorization, 0)
        XCTAssertEqual(w.breadth, 0)
        // Out-of-range values are held to the ring and the bars.
        let wild = WordScoreWords(try decode(ScoreBreakdown.self, ["score": 140, "band": "Deeply rooted", "components": ["consistency": 250]]))
        XCTAssertEqual(wild.score, 100)
        XCTAssertEqual(wild.consistency, 1)
        XCTAssertEqual(wild.breadth, 0, "a part the server didn't send is empty, never invented")
        // The page no longer works a score out of its own verses.
        let src = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Grow/MemoryVerseView.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("Seedling"), "one band vocabulary: the server's")
        XCTAssertTrue(src.contains("MemberAPI.scoreDetail(.word)"))
    }

    // MARK: Cycle 4 walk — a verse under its own reference

    @MainActor
    func testTheLevelPagesVerseIsCreditedToItsOwnReference() throws {
        XCTAssertEqual(LevelPageVerse.ref, "John 8:12")
        let vm = LevelDetailViewModel(levelNumber: 1)
        vm.level = try decode(PathwayLevel.self, level(1, "active", done: 3, of: 10, title: "Foundations of Faith", theme: "Foundations"))
        XCTAssertEqual(vm.verse.ref, "John 8:12", "never the level's theme")
        XCTAssertEqual(vm.verse.text, LevelPageVerse.text)
    }

    // MARK: Cycle 4 walk — one lesson time, the server's

    func testALessonHasOneTimeTheServers() throws {
        XCTAssertEqual(LessonTime.label(22), "22 min", "the trail's words for the server's estimated_minutes")
        XCTAssertNil(LessonTime.label(nil), "no estimate from the server: no time, never one worked out from the words")
        XCTAssertNil(LessonTime.label(0))
        // The lesson's detail carries the same figure the trail shows.
        let d = try decode(ModuleDetail.self, ["module_id": "m9", "level_number": 1, "module_sequence_number": 9,
                                               "title": "Relationships & Community", "lesson_content": "word " + String(repeating: "word ", count: 2600),
                                               "estimated_minutes": 22, "evaluation_kind": "quiz", "quiz_pass_mark": 70,
                                               "current_version": 1, "locked": false])
        XCTAssertEqual(LessonTime.label(d.estimatedMinutes), "22 min", "2,600 words would have read as ≈ 13 min")
        let src = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Pathway/ModuleView.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("min read"), "no second, word-counted time")
    }

    // MARK: §9.5 #1 — every state line in §4's words

    /// A failure line says what really happened, in §4's words: no raw server
    /// or exception text (APIError.errorDescription passed decoding details
    /// and transport messages straight to the member), and never "check your
    /// connection" when it wasn't the connection (§2) — nine screens said it
    /// whatever the cause, and check-in called a timeout "offline".
    func testNoStateLineLeaksRawTextOrGuessesTheCause() throws {
        var raw: [String] = [], guesses: [String] = []
        for (rel, text) in try TypeScan.files() where !rel.hasPrefix("Networking/") && rel != "Features/Shared/StateLanguage.swift" {
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("//") { continue }
                // The assistant reads it only to hear "unavailable"; it never shows it.
                if t.contains(".errorDescription"), !(rel == "Features/Chat/NuruAssistantView.swift" && t.hasPrefix("let msg =")) {
                    raw.append("\(rel):\(i + 1)")
                }
                if t.lowercased().contains("check your connection") { guesses.append("\(rel):\(i + 1)") }
            }
        }
        XCTAssertEqual(raw, [], "raw server or exception text never reaches a member (§4)")
        XCTAssertEqual(guesses, [], "never \"check your connection\" on a guess (§2)")
        // What the lines now say, by cause.
        XCTAssertEqual(NuruStateCopy.failureLine("Couldn't check you in.", APIError.transport("The request timed out."), deviceOnline: true),
                       "Couldn't check you in. Something went wrong on our side. It isn't you — please try again in a moment.",
                       "a timeout on a working network is our side, not \"offline\"")
        XCTAssertEqual(NuruStateCopy.failureLine("Couldn't check you in.", APIError.offline, deviceOnline: false),
                       "Couldn't check you in. You're offline. Connect to the internet, then try again.")
        XCTAssertEqual(NuruStateCopy.failureLine("Couldn't check you in.", APIError.http(status: 409, code: "CONFLICT", message: "Check-in has closed for this service"), deviceOnline: true),
                       "Couldn't check you in. Check-in has closed for this service", "the server's own refusal, as it said it")
        XCTAssertEqual(NuruStateCopy.failureLine("Couldn't save your reflection.", APIError.decoding("keyNotFound(…)"), deviceOnline: true),
                       "Couldn't save your reflection. Something went wrong on our side. It isn't you — please try again in a moment.",
                       "never the decoder's own words")
    }

    // MARK: §9.6 #3 — one way to do each thing

    func testOneWayToShareAndOneWayToGive() throws {
        func src(_ rel: String) throws -> String { try String(contentsOf: TypeScan.appRoot.appendingPathComponent(rel), encoding: .utf8) }
        // A gathering offered Share twice (a disc over its photo, and beside
        // "Add to calendar"); a receipt twice (its header, and "Share receipt").
        XCTAssertEqual(try src("Features/Events/EventDetailView.swift").components(separatedBy: "icon: .share2").count - 1, 1,
                       "a gathering offers Share once, beside Add to calendar")
        XCTAssertEqual(try src("Features/Give/GivingReceiptView.swift").components(separatedBy: "Button { share(d) }").count - 1, 1,
                       "a receipt offers Share once: \"Share receipt\"")
        // The amount sheet sets the amount; only the form's button gives.
        let give = try src("Features/Give/GivingView.swift")
        let start = try XCTUnwrap(give.range(of: "private struct GiveKeypadSheet"))
        let rest = give[start.upperBound...]
        let end = rest.range(of: "\nprivate struct ")?.lowerBound ?? rest.endIndex
        let sheet = String(rest[..<end])
        XCTAssertTrue(sheet.contains("Text(\"Set amount\")"), "Android's words")
        XCTAssertFalse(sheet.contains("Text(\"Give \\("), "the last tap before money moves is the one that names the money")
    }

    // MARK: §9.6 #4 — text grows with the phone's text size, and is never cut

    /// The height a view takes across a phone's width at a text size.
    @MainActor
    func renderedHeight<V: View>(_ view: V, _ size: DynamicTypeSize, width: CGFloat = 375) throws -> CGFloat {
        let r = ImageRenderer(content: view.frame(width: width).environment(\.dynamicTypeSize, size))
        r.proposedSize = ProposedViewSize(width: width, height: nil)
        return CGFloat(try XCTUnwrap(r.cgImage, "nothing rendered").height) / r.scale
    }

    /// At the largest accessibility size, on a 375-pt phone, the shared pieces
    /// every screen is built from wrap their words in full: given twice and
    /// four times the words, each is taller again. A piece that cut its text
    /// at N lines would stop growing (the tab header, the YOUR WEEK rows and
    /// "What needs you today" cut at two lines).
    @MainActor
    func testAtTheLargestTextSizeTextWrapsAndIsNeverCut() throws {
        let base = "Practical Life Questions and the Way of Grace"
        let texts = [base, [base, base].joined(separator: " — "), [base, base, base, base].joined(separator: " — ")]
        func nudge(_ t: String) throws -> HomeNudge {
            try decode(HomeNudge.self, ["id": "n1", "kind": "plan_day_due", "title": t, "body": t, "cta_label": "Open", "route": "plan"])
        }
        let pieces: [(String, (String) throws -> AnyView)] = [
            ("the tab header", { t in AnyView(NuruHeaderText(kicker: "Pathway", title: t, line: t)) }),
            ("a YOUR WEEK row", { t in AnyView(HomeWeekCard(rows: [HomeWeekRow(pillar: .pathway, title: t, line: t, destination: .plans)], open: { _ in })) }),
            ("a \"What needs you today\" card", { t in AnyView(HomeNeedsYouCard(nudge: try nudge(t), fixedWidth: nil, action: {})) }),
            ("the primary button", { t in AnyView(PButton(title: t, action: {})) }),
        ]
        for (name, piece) in pieces {
            let h = try texts.map { try renderedHeight(try piece($0), .accessibility5) }
            XCTAssertLessThan(h[0], h[1], "\(name) stopped growing — its words are cut at the largest size")
            XCTAssertLessThan(h[1], h[2], "\(name) stopped growing — its words are cut at the largest size")
        }
        // Text grows with the phone's text size (the custom faces scale with
        // Dynamic Type): the same header is far taller at the largest size.
        let header = NuruHeaderText(kicker: "Pathway", title: "Foundations of Faith", line: "Level 1 of 6 · 10 of 10 modules")
        XCTAssertGreaterThan(try renderedHeight(header, .accessibility5), 1.8 * (try renderedHeight(header, .large)))
        // At the everyday sizes a title still wraps to two lines (§8.1 rule 9).
        let everyday = try texts.map { try renderedHeight(NuruHeaderText(title: $0), .large) }
        XCTAssertEqual(everyday[1], everyday[2], accuracy: 1, "two lines at the everyday sizes, as designed")
    }

    /// Every other fixed line limit is a place text can still be cut at the
    /// largest size. The count may only fall: a new one is a choice to make
    /// on purpose (or `.nuruLineLimit`, which lifts at the accessibility sizes).
    func testFixedLineLimitsOnlyFall() throws {
        var n = 0
        for (_, text) in try TypeScan.files() {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false)
            where line.contains(".lineLimit(") && !line.contains("content.lineLimit(size") {
                n += line.components(separatedBy: ".lineLimit(").count - 1
            }
        }
        XCTAssertLessThanOrEqual(n, Self.fixedLineLimitCeiling, "a new fixed line limit can cut text at the largest size — use .nuruLineLimit, which lifts there")
    }
    static let fixedLineLimitCeiling = 257

    // MARK: Cycle 4 walk — a finished lesson offers the way on

    func testAFinishedLessonOffersTheWayOn() throws {
        func trail(_ rows: [[String: Any]]) throws -> [LevelModule] { try decode([LevelModule].self, rows) }
        let m9 = module("m9", seq: 9, "completed", completed: true, kind: "quiz", title: "Relationships & Community")
        let m10 = module("m10", seq: 10, "completed", completed: true, kind: "quiz", title: "Practical Life Questions")
        let exam = module("x", seq: 900, "next", kind: "exit_exam", title: "Level 1 Review")
        // Out of order on the wire: the sequence decides.
        let ada = try trail([exam, m10, m9])
        XCTAssertEqual(LessonOnward.after(moduleId: "m9", levelNumber: 1, in: ada),
                       .lesson(id: "m10", number: 10, title: "Practical Life Questions"))
        XCTAssertEqual(LessonOnward.after(moduleId: "m10", levelNumber: 1, in: ada), .exam(level: 1),
                       "after the last lesson: the Level 1 exam")
        // The words: "Next lesson ›", or the exam by its one name.
        let next = LessonOnward.lesson(id: "m10", number: 10, title: "Practical Life Questions")
        XCTAssertEqual(next.kicker, "UP NEXT · MODULE 10")
        XCTAssertEqual(next.actionLabel, "Next lesson ›")
        XCTAssertEqual(LessonOnward.exam(level: 1).title, "Take the Level 1 exam")
        XCTAssertEqual(LessonOnward.exam(level: 1).actionLabel, "Begin the exam ›")
        // An exam with no questions yet: said in §7.3's words, not offered.
        var unready = exam; unready["exam_available"] = false
        let soon = try XCTUnwrap(LessonOnward.after(moduleId: "m10", levelNumber: 1, in: try trail([m9, m10, unready])))
        XCTAssertEqual(soon, .examSoon(level: 1))
        XCTAssertEqual(soon.title, "Level 1 complete")
        XCTAssertEqual(soon.line, "Every module is done. The exam opens soon — we'll let you know.")
        XCTAssertNil(soon.actionLabel)
        // Passed (Eli): nothing more on this level — Back is the way out.
        let passed = module("x", seq: 900, "completed", completed: true, kind: "exit_exam")
        XCTAssertNil(LessonOnward.after(moduleId: "m10", levelNumber: 1, in: try trail([m9, m10, passed])))
        // A next lesson still behind its gate is never offered (the server would refuse it).
        let gated = module("m10", seq: 10, "locked", title: "Practical Life Questions")
        XCTAssertNil(LessonOnward.after(moduleId: "m9", levelNumber: 1, in: try trail([m9, gated, exam])))
        // An exam row still locked, or none at all: nothing to offer.
        XCTAssertNil(LessonOnward.after(moduleId: "m10", levelNumber: 1,
                                        in: try trail([m9, m10, module("x", seq: 900, "locked", kind: "exit_exam")])))
        XCTAssertNil(LessonOnward.after(moduleId: "m10", levelNumber: 1, in: try trail([m9, m10])))
        XCTAssertNil(LessonOnward.after(moduleId: "gone", levelNumber: 1, in: ada), "a lesson not in its level's list")
    }

    // MARK: §9.6 #1 — a card that repeats another card goes

    func testEachPlanIsOnThePlansTabOnce() throws {
        func row(_ id: String, enrolled: Bool = false, done: Bool = false, days: Int = 10) -> [String: Any] {
            ["plan_id": id, "title": "Plan \(id)", "day_count": days, "enrolled": enrolled,
             "completed_at": done ? "2026-10-01T09:00:00Z" : NSNull(), "description": "Words for \(id)"]
        }
        let plans = try decode([ReadingPlanRow].self, [row("first-steps", enrolled: true, days: 7), row("who-am-i"),
                                                        row("origin"), row("fear-not"), row("done", enrolled: true, done: true)])
        let promos = try decode([PlanPromo].self, [["slot": "hero", "plan_id": "who-am-i", "kicker": "WORTH YOUR WEEK"],
                                                   ["slot": "library", "plan_id": "origin", "kicker": "FROM THE LIBRARY"]])
        let resolved = PlanPicks.resolve(promos, in: plans)
        // Being read, or promoted: a card of its own — so not again in the grid.
        XCTAssertEqual(PlanPicks.withOwnCard(plans, promos: resolved, planOfDay: nil, midPromo: nil),
                       ["first-steps", "who-am-i", "origin"])
        // No promos from the server: the plan of the day and the mid-page pick.
        let pod = PlanPicks.planOfDay(plans)
        let mid = PlanPicks.midPromo(plans, planOfDayId: pod?.planId, day: 20731)
        let own = PlanPicks.withOwnCard(plans, promos: [], planOfDay: pod, midPromo: mid)
        XCTAssertTrue(own.contains("first-steps"))
        XCTAssertTrue(own.contains(try XCTUnwrap(pod).planId))
        XCTAssertTrue(own.contains(try XCTUnwrap(mid).planId))
        // A finished plan has no card above: it stays in the grid.
        XCTAssertFalse(own.contains("done"))
        // Home's progress card no longer repeats YOUR WEEK's next step.
        let home = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Home/HomeView.swift"), encoding: .utf8)
        XCTAssertFalse(home.contains("let line = j.progressLine"), "Home points to the Pathway once — YOUR WEEK's row")
    }

    func testProfilesMilestonesTellTheJourneysOneStory() throws {
        // Ada: every lesson done, the exam ready — Profile said "in progress · Keep going".
        let ada = try XCTUnwrap(Journey.derive(try summary([level(1, "completed", done: 10, of: 10)])))
        let words = try XCTUnwrap(ProfileMilestoneWords.current(level: 1, journey: ada))
        XCTAssertEqual(words.label, "Level 1 · Exam ready")
        XCTAssertEqual(words.meta, "Take the Level 1 exam")
        // Walking: the journey's count, never "in progress".
        let walking = try XCTUnwrap(Journey.derive(try summary([level(1, "active", done: 3, of: 10)])))
        XCTAssertEqual(ProfileMilestoneWords.current(level: 1, journey: walking)?.label, "Level 1 · 3 of 10 modules")
        // Not known yet, or another level: no row on a guess.
        XCTAssertNil(ProfileMilestoneWords.current(level: 1, journey: nil))
        XCTAssertNil(ProfileMilestoneWords.current(level: 2, journey: ada))
        let src = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Profile/ProfileView.swift"), encoding: .utf8)
        XCTAssertFalse(src.contains("in progress\", meta: \"Keep going\""))
    }

    /// The chrome on every screen at the largest sizes: a bar's words grow
    /// through the everyday sizes and stop at the largest of them (at the
    /// accessibility sizes the tab bar read "H… Pa… Pl…" and Give's switch
    /// "PARTN…"), and a figure inside a fixed ring keeps the everyday size
    /// (Home's ring read "↑2(").
    @MainActor
    func testBarsAndRingsHoldTheirTypeAtTheLargestSizes() throws {
        let label = Text("Pathway").font(.inter(11, .medium))
        XCTAssertGreaterThan(try renderedHeight(label.nuruBarText(), .xxxLarge, width: 200),
                             try renderedHeight(label.nuruBarText(), .large, width: 200), "a bar's words grow…")
        XCTAssertEqual(try renderedHeight(label.nuruBarText(), .accessibility5, width: 200),
                       try renderedHeight(label.nuruBarText(), .xxxLarge, width: 200), accuracy: 0.5, "…and stop at the largest everyday size")
        let figure = Text("26").font(.fraunces(13, .semibold))
        XCTAssertEqual(try renderedHeight(figure.nuruFixedFigure(), .accessibility5, width: 60),
                       try renderedHeight(figure.nuruFixedFigure(), .large, width: 60), accuracy: 0.5, "a ring's figure stays inside its ring")
        // Home's verse tableau: the owner's 216 pt photograph at the everyday
        // sizes, even for a long verse; at the largest it grows to hold the
        // whole verse (drawn over the fixed photo, it climbed over its kicker).
        let art = try decode(VerseArt.self, ["url": "", "alt": "A quiet field"])
        let verse = "Likewise the Spirit helps us in our weakness. For we do not know what to pray for as we ought, but the Spirit himself intercedes for us."
        let tableau = VerseTableauHeader(art: art, verseText: verse, reference: "Romans 8:26", version: "ESV")
        XCTAssertEqual(try renderedHeight(tableau, .large), 216, accuracy: 0.5, "the everyday tableau is unchanged")
        XCTAssertGreaterThan(try renderedHeight(tableau, .accessibility5), 300, "the largest size holds the whole verse")
        func src(_ rel: String) throws -> String { try String(contentsOf: TypeScan.appRoot.appendingPathComponent(rel), encoding: .utf8) }
        XCTAssertTrue(try src("Features/Shell/RootView.swift").contains(".nuruBarText(upTo: .large)"), "the tab bar keeps the standard size")
        XCTAssertTrue(try src("Features/Shell/SplitSegmentBar.swift").contains(".nuruBarText()"), "the Give | Partners switch")
        XCTAssertEqual(try renderedHeight(label.nuruBarText(upTo: .large), .accessibility5, width: 200),
                       try renderedHeight(label.nuruBarText(upTo: .large), .large, width: 200), accuracy: 0.5)
        for (rel, rings) in [("Features/Home/HomeView.swift", 2), ("Features/Pathway/PathwayView.swift", 2),
                             ("Features/Pathway/LevelDetailView.swift", 1), ("Features/Grow/MemoryVerseView.swift", 1),
                             ("Features/Profile/ProfileView.swift", 1)] {
            XCTAssertEqual(try src(rel).components(separatedBy: ".nuruFixedFigure()").count - 1, rings, rel)
        }
    }

    // MARK: §9.6 #4, largest text — the verse card holds its words; a name never breaks a word

    /// A view's pixels across a width, at a text size.
    @MainActor
    func renderedPixels<V: View>(_ view: V, _ size: DynamicTypeSize, width: CGFloat = 343) throws -> (h: Int, bytes: [UInt8]) {
        let r = ImageRenderer(content: view.frame(width: width).environment(\.dynamicTypeSize, size))
        r.proposedSize = ProposedViewSize(width: width, height: nil)
        r.scale = 2
        let image = try XCTUnwrap(r.cgImage, "nothing rendered")
        let w = image.width, h = image.height
        var bytes = [UInt8](repeating: 0, count: w * h * 4)
        let drawn = bytes.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        XCTAssertTrue(drawn, "couldn't read the rendered pixels")
        return (h, bytes)
    }

    /// Home's verse card. At the default size it is the owner's 216 pt
    /// tableau pixel for pixel — the tableau as it was before 84d2acb rebuilt
    /// it, kept below as the reference. At the largest size it grows to hold
    /// every word: drawn over a fixed 216 pt photograph the verse ran out of
    /// the card's top and under its kicker; now the kicker row is above the
    /// verse and the card is as tall as its words.
    @MainActor
    func testTheVerseCardIsTheOwnersTableauAndHoldsItsWordsAtTheLargest() throws {
        let art = try decode(VerseArt.self, ["url": "", "alt": "A quiet field"])
        let verses = ["Pray without ceasing.",
                      "Likewise the Spirit helps us in our weakness. For we do not know what to pray for as we ought, but the Spirit himself intercedes for us.",
                      String(repeating: "And we know that for those who love God all things work together for good. ", count: 3)]
        for v in verses {
            let now = try renderedPixels(VerseTableauHeader(art: art, verseText: v, reference: "Romans 8:26", version: "ESV"), .large)
            let before = try renderedPixels(VerseTableauBefore84d2acb(art: art, verseText: v, reference: "Romans 8:26", version: "ESV"), .large)
            XCTAssertEqual(now.h, 432, "216 pt at 2×")
            XCTAssertEqual(now.h, before.h)
            XCTAssertTrue(now.bytes == before.bytes, "the default-size tableau is the owner's, pixel for pixel: \"\(v.prefix(24))…\"")
        }
        // At the largest size the card is as tall as its words: more words, a taller card.
        func height(_ v: String) throws -> CGFloat {
            try renderedHeight(VerseTableauHeader(art: art, verseText: v, reference: "Romans 8:26", version: "ESV"), .accessibility5, width: 343)
        }
        XCTAssertGreaterThan(try height(verses[0]), 216)
        XCTAssertGreaterThan(try height(verses[1]), try height(verses[0]) + 100, "it grows with the verse, never a fixed height")
    }

    /// Production's six levels: their names and short names.
    static let productionLevelNames = [
        "Foundations of Faith", "Inner Transformation", "Foundations of Grace & Kingdom Perspective",
        "Life & Power of the Holy Spirit", "Kingdom Culture, Leadership & Multiplication", "Level 6",
        "Foundations", "Transformation", "Grace", "Spirit", "Leadership",
    ]

    /// At the largest size a long word in a display face was wider than the
    /// line and broke in two: Pathway's "Foundatio / ns of / Faith". Every word
    /// of every level's name, set in each title that shows a level's name, at
    /// that title's line on a 375 pt phone, takes one line: no taller than the
    /// same word on a line with room to spare (a word broken in two is two
    /// lines).
    @MainActor
    func testALevelsNameNeverBreaksAWordAtTheLargestSize() throws {
        let words = Set(Self.productionLevelNames.flatMap { NuruWholeWords.words($0) }).sorted()
        // Each title that shows a level's name, and its line on a 375 pt
        // phone. The two private cards are set exactly as their views set them.
        let titles: [(String, CGFloat, (String) -> AnyView)] = [
            ("Pathway's header", 335, { AnyView(NuruHeaderText(title: $0)) }),
            ("a header beside the bell", 283, { AnyView(NuruHeaderText(title: $0)) }),
            ("the level page's hero", 335, { AnyView(LevelHeroTitle(overline: "Level 3", title: $0)) }),
            ("Map view's level card", 200, { w in
                AnyView(Text(w).font(.nRowTitle).kerning(-0.3).nuruLineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).nuruWholeWords(w, font: .nRowTitle, kerning: -0.3)) }),
            ("Pathway's section kicker", 300, { w in
                let u = w.uppercased()
                return AnyView(Text(u).font(.nCardKicker).kerning(1.4).nuruLineLimit(2)
                    .fixedSize(horizontal: false, vertical: true).nuruWholeWords(u, font: .nCardKicker, kerning: 1.4)) }),
        ]
        for (title, line, view) in titles {
            for w in words {
                let set = try renderedHeight(view(w), .accessibility5, width: line)
                let roomy = try renderedHeight(view(w), .accessibility5, width: 4000)
                XCTAssertLessThanOrEqual(set, roomy + 0.5, "\"\(w)\" breaks mid-word in \(title) at \(Int(line)) pt")
            }
        }
        // The check has teeth: the bare title broke "Transformation" (and "Foundations").
        for w in ["Transformation", "Foundations"] {
            let bare = Text(w).font(.fraunces(26, .semibold)).kerning(-0.52).fixedSize(horizontal: false, vertical: true)
            XCTAssertGreaterThan(try renderedHeight(bare, .accessibility5, width: 335),
                                 try renderedHeight(bare, .accessibility5, width: 4000) + 1, "\(w) broke without the guard")
        }
        // The whole name too: no word of it is broken.
        let name = "Kingdom Culture, Leadership & Multiplication"
        XCTAssertEqual(NuruWholeWords.words(name), ["Kingdom", "Culture,", "Leadership", "&", "Multiplication"])
        // At the everyday sizes the guard is inert: the same pixels as the bare title.
        for size in [DynamicTypeSize.large, .xxxLarge] {
            for t in ["Foundations of Faith", "Inner Transformation", "Grow in the Word"] {
                let guarded = try renderedPixels(Text(t).font(.fraunces(26, .semibold)).kerning(-0.52)
                    .fixedSize(horizontal: false, vertical: true)
                    .nuruWholeWords(t, font: .fraunces(26, .semibold), kerning: -0.52), size, width: 335)
                let bare = try renderedPixels(Text(t).font(.fraunces(26, .semibold)).kerning(-0.52)
                    .fixedSize(horizontal: false, vertical: true), size, width: 335)
                XCTAssertTrue(guarded.bytes == bare.bytes, "\(size): \"\(t)\" is untouched at the everyday sizes")
            }
        }
        // Down only as far as it must: a word that fits keeps the member's size.
        XCTAssertEqual(try renderedHeight(NuruHeaderText(title: "Faith"), .accessibility5, width: 335),
                       try renderedHeight(NuruHeaderText(title: "Faith"), .accessibility5, width: 4000), accuracy: 0.5)
        XCTAssertEqual(NuruWholeWords.steps(from: .accessibility2), [.accessibility2, .accessibility1, .xxxLarge, .xxLarge, .xLarge, .large, .medium, .small, .xSmall])
    }

    // MARK: Owner, 2026-10-07 — colour option A: navy for the church's voice and the next step

    /// The read letter says its Sunday and "Read again"; before a letter
    /// exists, its own words with the countdown on its line.
    func testTheLetterSaysItsSundayAndReadAgain() {
        let wednesday = ISO8601DateFormatter().date(from: "2026-10-07T05:00:00Z")!
        XCTAssertEqual(HomeLetterWords.readLine(weekOf: "2026-10-04", now: wednesday), "Sun 4 Oct · Read again")
        XCTAssertEqual(HomeLetterWords.readLine(weekOf: "2025-12-28", now: wednesday), "Sun 28 Dec 2025 · Read again",
                       "the year when it isn't this year")
        XCTAssertEqual(HomeLetterWords.readLine(weekOf: "2026-10-04T00:00:00Z", now: wednesday), "Sun 4 Oct · Read again",
                       "the calendar date sent, never shifted by a time zone")
        XCTAssertEqual(HomeLetterWords.readLine(weekOf: "", now: wednesday), "Read again")
        XCTAssertEqual(HomeLetterWords.arrivalLine(countdown: "In 4 days"), "Written for your week · In 4 days")
        // Every state is navy now: the read and waiting cards are the one quiet card.
        let home = try? String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Home/HomeView.swift"), encoding: .utf8)
        XCTAssertEqual(home?.components(separatedBy: "HomeLetterQuietCard(").count, 3, "read and before a letter exists")
    }

    /// The week's one next step is the first row, in the week's own order,
    /// that asks the member to act now; it leads the card, and the other rows
    /// follow in their order. Nothing asks: no band.
    func testTheWeeksNextStepIsTheFirstRowThatAsks() {
        func row(_ p: HomeWeekRow.Pillar, _ title: String, _ ask: HomeWeekRow.Ask? = nil) -> HomeWeekRow {
            HomeWeekRow(pillar: p, title: title, line: "", destination: .plans, ask: ask)
        }
        let ada = [row(.pathway, "Take the Level 1 exam", .init(verb: "Begin", subject: "Take the Level 1 exam")),
                   row(.plans, "Continue · First Steps", .init(verb: "Continue", subject: "First Steps")),
                   row(.events, "Going · Sunday Service"), row(.giving, "Giving · Your weekly gift"),
                   row(.cell, "Gather · Dev Cell A")]
        let a = HomeWeek.cardOrder(ada)
        XCTAssertEqual(a.step?.pillar, .pathway)
        XCTAssertEqual(a.rest.map(\.pillar), [.plans, .events, .giving, .cell])
        // Eli: his level waits and today's reading is done; a gathering asks next.
        let eli = [row(.pathway, "Level 2 is being prepared"), row(.plans, "Done today · First Steps"),
                   row(.events, "Join · Sunday Service", .init(verb: "Join", subject: "Sunday Service")),
                   row(.giving, "Pay · Roof sheets", .init(verb: "Pay", subject: "Roof sheets")),
                   row(.cell, "Find your cell", .init(verb: "Ask", subject: "Find your cell"))]
        let e = HomeWeek.cardOrder(eli)
        XCTAssertEqual(e.step?.pillar, .events, "the first that asks, not the most urgent-sounding")
        XCTAssertEqual(e.rest.map(\.pillar), [.pathway, .plans, .giving, .cell], "the rest keep the week's order")
        let quiet = [row(.pathway, "Level 2 is being prepared"), row(.plans, "Start a reading plan"),
                     row(.events, "See the church calendar"), row(.giving, "Give"), row(.cell, "Gather · Dev Cell A")]
        XCTAssertNil(HomeWeek.cardOrder(quiet).step)
        XCTAssertEqual(HomeWeek.cardOrder(quiet).rest.map(\.pillar), [.pathway, .plans, .events, .giving, .cell])
    }

    /// Each row says whether it asks, with one of the owner's five verbs.
    func testEachRowSaysWhetherItAsksAndWithWhichVerb() throws {
        let verbs: Set<String> = ["Begin", "Continue", "Join", "Pay", "Ask"]
        // Pathway: a first lesson and the exam begin, a lesson continues; a level waiting asks nothing.
        let ben = try bensJourney()
        XCTAssertEqual(HomeWeek.pathwayRow(ben, enrolledLevel: 1).ask, .init(verb: "Begin", subject: "God & His Nature"))
        let cara = try XCTUnwrap(Journey.derive(try summary([level(1, "active", done: 2, of: 10)]),
                                                trail: try decode([LevelModule].self, [module("m3", seq: 3, "next", title: "Salvation by Grace")])))
        XCTAssertEqual(HomeWeek.pathwayRow(cara, enrolledLevel: 1).ask, .init(verb: "Continue", subject: "Salvation by Grace"))
        let ada = try XCTUnwrap(Journey.derive(try summary([level(1, "completed", done: 10, of: 10), level(2, "locked")])))
        XCTAssertEqual(HomeWeek.pathwayRow(ada, enrolledLevel: 1).ask, .init(verb: "Begin", subject: "Take the Level 1 exam"))
        let eli = try XCTUnwrap(Journey.derive(try summary([level(1, "awaiting_review", done: 10, of: 10, awaiting: true),
                                                            level(2, "locked")])))
        XCTAssertNil(HomeWeek.pathwayRow(eli, enrolledLevel: 1).ask)
        XCTAssertNil(HomeWeek.pathwayRow(nil, enrolledLevel: 1).ask)
        // Plans: today's day begins or continues; done today, or no plan, asks nothing.
        XCTAssertEqual(HomeWeek.plansRow([try plan("p1", day: 1, done: [])], now: monday).ask, .init(verb: "Begin", subject: "First Steps"))
        XCTAssertEqual(HomeWeek.plansRow([try plan("p1", day: 2, done: [1], lastFinished: "2026-10-01T09:33:50.486Z")], now: monday).ask?.verb,
                       "Continue")
        XCTAssertNil(HomeWeek.plansRow([try plan("p1", day: 4, done: [1, 2, 3], lastFinished: "2026-10-05T08:45:28.123Z")], now: monday).ask)
        XCTAssertNil(HomeWeek.plansRow(nil).ask, "starting a plan is a standing invitation")
        // Cell: no cell asks to be connected, until it has asked; a cell asks nothing.
        let nairobi = TimeZone(identifier: "Africa/Nairobi")!
        XCTAssertEqual(HomeWeek.cellRow(nil, timeZone: nairobi, now: monday).ask, .init(verb: "Ask", subject: "Find your cell"))
        XCTAssertNil(HomeWeek.cellRow(nil, askedAt: "2026-10-05T09:30:00Z", timeZone: nairobi, now: monday).ask)
        // (Events and Giving: ExperienceCycle2Tests — Join and Pay ask; Going, Giving ·, Give and the calendar don't.)
        for r in [HomeWeek.pathwayRow(ben, enrolledLevel: 1), HomeWeek.pathwayRow(cara, enrolledLevel: 1),
                  HomeWeek.pathwayRow(ada, enrolledLevel: 1), HomeWeek.cellRow(nil, timeZone: nairobi, now: monday)] {
            XCTAssertTrue(verbs.contains(try XCTUnwrap(r.ask).verb), "one of the owner's five verbs")
        }
    }

    // MARK: Owner, 2026-10-07 — a quiet divider when dark cards would touch

    /// Ben's first day: the reflection waits (§9.2 #4), so nothing stands
    /// between the navy letter and the liturgy's photograph — the quiet
    /// divider does. Nothing moves.
    func testOnAFirstDayAQuietDividerPartsTheLetterFromTheLiturgysPhotograph() throws {
        // The rows Home assembles on Ben's first day: nothing needs him yet,
        // and the reflection is held.
        let firstDay = ["verse", "video", "letter", "liturgy", "week", "rhythm", "echo", "selah1",
                        "celebrations", "progress", "selah2", "grow", "encourage"]
        let parted = HomeQuietDivider.parted(firstDay)
        XCTAssertEqual(parted, ["verse", "video", "letter", "quiet:letter|liturgy", "liturgy", "week", "rhythm", "echo",
                                "selah1", "celebrations", "progress", "selah2", "grow", "encourage"])
        // Nothing moves: less the divider, the owner's order is as it was.
        XCTAssertEqual(parted.filter { !$0.hasPrefix("quiet:") }, firstDay)
        // Another day, what needs the member (or the reflection) stands between them.
        for between in ["needsyou", "priority"] {
            let day = ["verse", "video", "letter", between, "liturgy", "week"]
            XCTAssertEqual(HomeQuietDivider.parted(day), day, between)
        }
    }

    /// While a service is near, "Live now" (navy) would sit on the letter (navy).
    func testLiveNowOnTheLetterIsPartedToo() {
        XCTAssertEqual(HomeQuietDivider.parted(["verse", "video", "livenow", "letter", "needsyou", "liturgy"]),
                       ["verse", "video", "livenow", "quiet:livenow|letter", "letter", "needsyou", "liturgy"])
        // On a first day, both.
        XCTAssertEqual(HomeQuietDivider.parted(["verse", "video", "livenow", "letter", "liturgy", "week"]),
                       ["verse", "video", "livenow", "quiet:livenow|letter", "letter", "quiet:letter|liturgy", "liturgy", "week"])
    }

    /// Dark edges are the navy cards' and the photographs'; everything else
    /// on Home is light, and needs no rest.
    func testDarkEdgesAreTheNavyCardsAndThePhotographs() {
        // Nuru Live and Radio on air, over the verse's photograph.
        XCTAssertEqual(HomeQuietDivider.parted(["livebanner", "onair", "verse", "video"]),
                       ["livebanner", "quiet:livebanner|onair", "onair", "quiet:onair|verse", "verse", "video"])
        // The verse's and the liturgy's captions are light: what follows them touches no dark edge.
        XCTAssertFalse(HomeQuietDivider.touch("verse", "letter"))
        XCTAssertFalse(HomeQuietDivider.touch("liturgy", "week"))
        XCTAssertFalse(HomeQuietDivider.touch("encourage", "give"))
        for light in ["loaderror", "video", "needsyou", "priority", "week", "rhythm", "echo", "selah1", "prayerwall",
                      "celebrations", "announcement", "progress", "selah2", "grow", "encourage"] {
            XCTAssertEqual(HomeQuietDivider.edges(of: light).top, .light, light)
            XCTAssertEqual(HomeQuietDivider.edges(of: light).bottom, .light, light)
        }
    }

    /// Home runs the check over the rows it assembled, last; and every row it
    /// can append has its edges named here, so a new dark card cannot slip in
    /// unparted.
    func testHomesFeedPartsItsAssembledRowsAndNamesEveryRowsEdges() throws {
        let home = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Home/HomeView.swift"), encoding: .utf8)
        XCTAssertTrue(home.contains("return HomeQuietDivider.parted(s, id: { $0.id })"))
        let re = try NSRegularExpression(pattern: #"s\.append\(\("([a-z0-9]+)""#)
        let appended = Set(re.matches(in: home, range: NSRange(home.startIndex..., in: home)).compactMap {
            Range($0.range(at: 1), in: home).map { String(home[$0]) }
        })
        let dark: Set = ["livebanner", "onair", "livenow", "letter", "give", "verse", "liturgy", "event"]
        let light: Set = ["loaderror", "video", "needsyou", "priority", "week", "rhythm", "echo", "selah1", "prayerwall",
                          "celebrations", "announcement", "progress", "selah2", "grow", "encourage"]
        XCTAssertEqual(appended, dark.union(light), "a new Home row: name its edges in HomeQuietDivider.edges(of:)")
        for id in dark {
            let e = HomeQuietDivider.edges(of: id)
            XCTAssertTrue(e.top == .dark || e.bottom == .dark, id)
        }
    }
}

/// The verse tableau as it was before 84d2acb (3137194), kept as the
/// default-size reference: a fixed 216 pt photograph with its words overlaid.
private struct VerseTableauBefore84d2acb: View {
    let art: VerseArt
    let verseText: String?
    let reference: String
    let version: String

    var body: some View {
        Color.clear
            .frame(height: 216)
            .overlay {
                CachedAsyncImage(url: URL(string: art.url)) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    } else {
                        LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1C33)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            }
            .clipped()
            .overlay {
                LinearGradient(stops: [.init(color: .black.opacity(0.35), location: 0),
                                       .init(color: .clear, location: 0.28)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                LinearGradient(stops: [.init(color: .clear, location: 0.5),
                                       .init(color: Color(hex: 0x0A1C33).opacity(0.85), location: 0.78),
                                       .init(color: Color(hex: 0x06111F).opacity(0.95), location: 1)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Icon(.bookOpen, size: 14, color: Color(hex: 0xF2DDA0))
                    Text("VERSE FOR TODAY").font(.nCardKicker).kerning(1.4)
                        .foregroundStyle(Color(hex: 0xF2DDA0))
                    Spacer(minLength: 0)
                    Text(version.uppercased())
                        .font(.inter(11, .bold)).kerning(1).foregroundStyle(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(.white.opacity(0.16), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.25), lineWidth: 1))
                }
                .padding(Nuru.S.base)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    if let t = verseText, !t.isEmpty {
                        Text("\u{201C}\(t)\u{201D}")
                            .font(.fraunces(t.count > 220 ? 12 : t.count > 140 ? 13 : 14)).foregroundStyle(.white)
                            .nuruLineSpacing(3)
                            .lineLimit(4)
                            .minimumScaleFactor(0.92)
                            .shadow(color: .black.opacity(0.45), radius: 3, y: 1)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(reference)
                        .font(.inter(11, .bold)).kerning(0.3)
                        .foregroundStyle(Color(hex: 0xF2DDA0))
                        .shadow(color: .black.opacity(0.5), radius: 2, y: 1)
                }
                .padding(Nuru.S.base)
            }
            .accessibilityLabel(Text(art.alt))
    }
}
