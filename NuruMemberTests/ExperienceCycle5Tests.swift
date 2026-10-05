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

    func testTheExamReadsItsPassMarkFromTheServer() throws {
        let exam = try decode(AssembledExam.self, ["level_number": 1, "question_count": 91, "pass_mark": 80, "questions": []])
        XCTAssertEqual(exam.passMark, 80)
        XCTAssertEqual(exam.questionCount, 91)
        // Postgres NUMERIC arrives as a string from production.
        XCTAssertEqual(try decode(AssembledExam.self, ["level_number": 1, "question_count": 3, "pass_mark": "80.00", "questions": []]).passMark, 80)
        // An older server: absent, so the door says the count alone.
        XCTAssertNil(try decode(AssembledExam.self, ["level_number": 1, "question_count": 3, "questions": []]).passMark)
    }
}
