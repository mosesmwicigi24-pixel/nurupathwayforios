// Experience Cycles 5–10, combined (pathway docs/EXPERIENCE.md §9): journeys,
// context, states under stress, one product, fewer and better things — the
// rules pinned. Payloads are decoded exactly like APIClient's: snake_case in.
import XCTest
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
}
