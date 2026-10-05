// Experience Cycle 4 — visual language, pinned (pathway docs/EXPERIENCE.md
// §8): every "X of Y modules" counts lessons (the exam is its own step), so
// a finisher reads "20 of 20" everywhere and never "20 of 21". Payloads are
// decoded exactly like APIClient's: snake_case in.
import XCTest
@testable import NuruMember

final class ExperienceCycle4Tests: XCTestCase {

    // MARK: Fixtures — the /me/pathway and /levels/{n}/modules wire shapes

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// `lessons` nil = the keys absent (a server that predates them).
    private func level(_ n: Int, _ status: String, done: Int = 0, of total: Int = 0,
                       lessons: (done: Int, of: Int)? = nil, examAvailable: Bool? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "level_number": n, "title": "Level \(n) title", "theme": NSNull(), "description": NSNull(),
            "total_modules": total, "completed_modules": done, "minutes": 0, "status": status,
            "awaiting_review": false, "exam_published": true]
        if let lessons {
            row["lessons_completed"] = lessons.done
            row["lessons_total"] = lessons.of
        }
        if let examAvailable { row["exam_available"] = examAvailable }
        return row
    }

    private func summary(current: Int, _ row: [String: Any]) throws -> PathwaySummary {
        let levels: [[String: Any]] = (1...6).map { n in
            if n == current { return row }
            return n < current ? level(n, "completed", done: 10, of: 10) : level(n, "locked")
        }
        return try decode(PathwaySummary.self, ["current_level": current, "levels": levels])
    }

    private func module(_ id: String, level: Int, seq: Int, _ status: String,
                        completed: Bool = false, kind: String = "none") -> [String: Any] {
        ["module_id": id, "level_number": level, "module_sequence_number": seq, "title": "Module \(id)",
         "summary": NSNull(), "estimated_minutes": 10, "evaluation_kind": kind, "quiz_pass_mark": 70,
         "completed": completed, "status": status, "progress": completed ? 100 : 0, "locked": status == "locked"]
    }

    /// Ada's Level 1 as the local API (and production) serves it: twenty
    /// lessons done, the exam a module at seq 900 that is open and not passed.
    private func adasTrail() throws -> [LevelModule] {
        var rows = (1...20).map { module("m\($0)", level: 1, seq: $0, "completed", completed: true) }
        rows.append(module("exam", level: 1, seq: 900, "next", kind: "exit_exam"))
        return try decode([LevelModule].self, rows)
    }

    /// Ada's /me/pathway level 1, verbatim from the local API (2026-10-05).
    private var adasLevelOne: [String: Any] {
        level(1, "active", done: 20, of: 21, lessons: (20, 20), examAvailable: true)
    }

    // MARK: §8.2 #4 — the lesson counts decode, and fall back

    func testLessonCountsDecodeAndFallBackToTheModuleCounts() throws {
        let new = try decode(PathwayLevel.self, adasLevelOne)
        XCTAssertEqual(new.lessonsTotal, 20)
        XCTAssertEqual(new.lessonsCompleted, 20)
        XCTAssertEqual(new.lessonCount, 20, "the exam is never counted as a module")
        XCTAssertEqual(new.lessonsDone, 20)
        XCTAssertEqual(new.totalModules, 21, "the server's own count is kept as sent")

        let older = try decode(PathwayLevel.self, level(1, "active", done: 20, of: 21))
        XCTAssertNil(older.lessonsTotal)
        XCTAssertEqual(older.lessonCount, 21, "absent → the module counts, as before")
        XCTAssertEqual(older.lessonsDone, 20)
    }

    // MARK: §8.2 #4 — the journey counts lessons; the exam is its own step

    func testAdaReadsTwentyOfTwentyAndTheExamIsHerStep() throws {
        let s = try summary(current: 1, adasLevelOne)
        let j = try XCTUnwrap(Journey.derive(s, trail: try adasTrail()))
        XCTAssertEqual(j.stage, .examReady)
        XCTAssertEqual(j.completedModules, 20)
        XCTAssertEqual(j.totalModules, 20, "never 20 of 21")
        XCTAssertEqual(j.pill, "Exam ready")
        XCTAssertEqual(j.title, "Take the Level 1 exam")
        XCTAssertEqual(j.destination, .exam(1))
        XCTAssertEqual(j.progressPercent, 17)
        // Home's week row says the same step.
        let row = HomeWeek.pathwayRow(j, enrolledLevel: 1)
        XCTAssertEqual(row.title, "Take the Level 1 exam")
        XCTAssertEqual(row.line, "Level 1 · Exam ready")
    }

    /// Before the trail lands (Home's first paint) or when it fails, the
    /// summary's own numbers say the exam is next — never "20 of 20 modules ·
    /// Continue" beside a finished level.
    func testTheExamStepWithoutTheTrail() throws {
        let ready = try XCTUnwrap(Journey.derive(try summary(current: 1, adasLevelOne)))
        XCTAssertEqual(ready.stage, .examReady)
        XCTAssertEqual(ready.destination, .exam(1))
        XCTAssertEqual(ready.pill, "Exam ready")

        let empty = try XCTUnwrap(Journey.derive(try summary(current: 1, adasLevelOne), trail: []))
        XCTAssertEqual(empty.stage, .examReady, "a failed trail read ([]) speaks from the summary too")

        let noQuestions = level(1, "active", done: 20, of: 21, lessons: (20, 20), examAvailable: false)
        let soon = try XCTUnwrap(Journey.derive(try summary(current: 1, noQuestions)))
        XCTAssertEqual(soon.stage, .examSoon, "an exam with no questions is never offered")
        XCTAssertNil(soon.destination)

        // A lesson still to walk: learning, in lessons.
        let walking = try XCTUnwrap(Journey.derive(try summary(current: 1,
            level(1, "active", done: 19, of: 21, lessons: (19, 20), examAvailable: true))))
        XCTAssertEqual(walking.stage, .learning)
        XCTAssertEqual(walking.pill, "19 of 20 modules")
        XCTAssertEqual(walking.line, "19 of 20 modules in Level 1")
        XCTAssertEqual(walking.levelPercent, 95)
    }

    /// The trail's word wins over the numbers: an exam row the server still
    /// locks is never offered (§7.1 rule 2 — offer only what will work).
    func testTheTrailsExamRowOutranksTheNumbers() throws {
        var rows = (1...20).map { module("m\($0)", level: 1, seq: $0, "completed", completed: true) }
        rows.append(module("exam", level: 1, seq: 900, "locked", kind: "exit_exam"))
        let t = try decode([LevelModule].self, rows)
        let j = try XCTUnwrap(Journey.derive(try summary(current: 1, adasLevelOne), trail: t))
        XCTAssertNotEqual(j.stage, .examReady)
        XCTAssertNotEqual(j.destination, .exam(1))
    }

    func testLearningCountsLessonsNotTheExam() throws {
        // Level 2 at three lessons of ten, its published exam counted in the total.
        let s = try summary(current: 2, level(2, "active", done: 3, of: 11, lessons: (3, 10)))
        let j = try XCTUnwrap(Journey.derive(s))
        XCTAssertEqual(j.stage, .learning)
        XCTAssertEqual(j.pill, "3 of 10 modules")
        XCTAssertEqual(j.line, "3 of 10 modules in Level 2")
        XCTAssertEqual(j.progressLine.bold, "3 of 10 modules")
        XCTAssertEqual(j.levelPercent, 30)
        XCTAssertEqual(j.progressPercent, 22)  // (1 + 0.3) / 6
    }

    func testAnOlderServerKeepsItsModuleCounts() throws {
        // No lesson fields: exactly as before — the summary's numbers alone
        // never invent an exam step.
        let j = try XCTUnwrap(Journey.derive(try summary(current: 1, level(1, "active", done: 20, of: 21))))
        XCTAssertEqual(j.stage, .learning)
        XCTAssertEqual(j.pill, "20 of 21 modules")
    }

    // MARK: §8.2 #1 — one header: Pathway's one line

    func testPathwaysHeaderLineSaysWhereTheLevelStands() throws {
        let ada = try decode(PathwayLevel.self, adasLevelOne)
        XCTAssertEqual(PathwayTrail.headerLine(ada, position: 1, of: 6), "Level 1 of 6 · 20 of 20 modules")
        let walking = try decode(PathwayLevel.self, level(2, "active", done: 3, of: 11, lessons: (3, 10)))
        XCTAssertEqual(PathwayTrail.headerLine(walking, position: 2, of: 6), "Level 2 of 6 · 3 of 10 modules")
        let older = try decode(PathwayLevel.self, level(2, "active", done: 3, of: 10))
        XCTAssertEqual(PathwayTrail.headerLine(older, position: 2, of: 6), "Level 2 of 6 · 3 of 10 modules")
        let unpublished = try decode(PathwayLevel.self, level(2, "active"))
        XCTAssertEqual(PathwayTrail.headerLine(unpublished, position: 2, of: 6), "Level 2 of 6 · Modules open soon",
                       "never \"0 of 0 modules\"")
        XCTAssertEqual(PathwayTrail.headerLine(nil, position: 1, of: 6), "Level 1 of 6")
    }

    // MARK: §8.2 #2 — one icon per pillar (both apps draw these)

    func testEachWeekPillarWearsItsOneIcon() {
        XCTAssertEqual(HomeWeekCard.icon(.pathway), .bookOpen)
        XCTAssertEqual(HomeWeekCard.icon(.plans), .bookMarked)
        XCTAssertEqual(HomeWeekCard.icon(.events), .calendar)
        XCTAssertEqual(HomeWeekCard.icon(.giving), .handHeart)
        XCTAssertEqual(HomeWeekCard.icon(.cell), .users)
    }

    // MARK: §8.2 #5 — the streak in Android's words

    func testTheStreakSpeaksAndroidsWords() {
        XCTAssertEqual(StreakWords.title(0), "0-day streak")
        XCTAssertEqual(StreakWords.line(0), "Read today to start your streak 🔥")
        XCTAssertEqual(StreakWords.title(1), "1-day streak")
        XCTAssertEqual(StreakWords.title(12), "12-day streak")
        XCTAssertEqual(StreakWords.line(12), "Read today to keep it alive 🔥")
        XCTAssertEqual(StreakWords.title(-1), "0-day streak", "never a negative day")
    }

    // MARK: §8.2 #6 — the featured plan: one rule over the same inputs

    private func plan(_ id: String, enrolled: Bool = false, description: String? = "Words.") -> [String: Any] {
        ["plan_id": id, "title": "Plan \(id)", "description": description ?? NSNull(), "day_count": 10, "enrolled": enrolled]
    }
    private func plans(_ rows: [[String: Any]]) throws -> [ReadingPlanRow] { try decode([ReadingPlanRow].self, rows) }

    func testTheDayNumberIsTheNairobiCalendarDay() throws {
        let iso = ISO8601DateFormatter()
        // 2026-10-05 is day 20731 from 1970-01-01.
        XCTAssertEqual(PlanPicks.nairobiDay(try XCTUnwrap(iso.date(from: "2026-10-05T05:00:00Z"))), 20731)
        // Nairobi's midnight is 21:00 UTC the evening before — the day turns
        // there, not at 03:00 (the UTC day still said the 4th until then).
        XCTAssertEqual(PlanPicks.nairobiDay(try XCTUnwrap(iso.date(from: "2026-10-04T20:59:59Z"))), 20730)
        XCTAssertEqual(PlanPicks.nairobiDay(try XCTUnwrap(iso.date(from: "2026-10-04T21:00:00Z"))), 20731)
        XCTAssertEqual(PlanPicks.nairobiDay(try XCTUnwrap(iso.date(from: "2026-10-05T20:59:59Z"))), 20731)
    }

    func testThePlanOfTheDayIsTheFirstNotStartedInTheServersOrder() throws {
        let rows = try plans([plan("c", enrolled: true), plan("b"), plan("a")])
        XCTAssertEqual(PlanPicks.planOfDay(rows)?.planId, "b", "the server's order — never re-sorted")
        XCTAssertEqual(PlanPicks.planOfDay(try plans([plan("x", enrolled: true)]))?.planId, "x")
        XCTAssertNil(PlanPicks.planOfDay([]))
    }

    func testTheMidPromoTurnsEveryOtherNairobiDay() throws {
        // Pool: not started, not the plan of the day, with words — p2, p3, p5.
        let rows = try plans([plan("p1"), plan("p2"), plan("p3"), plan("p4", enrolled: true),
                              plan("p5"), plan("p6", description: nil)])
        let pod = PlanPicks.planOfDay(rows)?.planId
        XCTAssertEqual(pod, "p1")
        // 20731 / 2 = 10365; 10365 % 3 = 0 → p2. 20732 / 2 = 10366 → 1 → p3.
        XCTAssertEqual(PlanPicks.midPromo(rows, planOfDayId: pod, day: 20731)?.planId, "p2")
        XCTAssertEqual(PlanPicks.midPromo(rows, planOfDayId: pod, day: 20730)?.planId, "p2", "two days per pick")
        XCTAssertEqual(PlanPicks.midPromo(rows, planOfDayId: pod, day: 20732)?.planId, "p3")
        XCTAssertEqual(PlanPicks.midPromo(rows, planOfDayId: pod, day: 20734)?.planId, "p5")
        XCTAssertNil(PlanPicks.midPromo(try plans([plan("only")]), planOfDayId: "only", day: 20731))
    }

    func testTheServersPromosLeadInItsOrderOnceEach() throws {
        let rows = try plans([plan("a"), plan("b"), plan("c")])
        let promos = try decode([PlanPromo].self, [
            ["plan_id": "gone", "slot": "fresh", "kicker": "WORTH YOUR WEEK"],
            ["plan_id": "c", "slot": "fresh", "kicker": "FROM THE LIBRARY", "reason": "A few minutes a day is all it asks."],
            ["plan_id": "a", "slot": "fresh", "kicker": "  "],
            ["plan_id": "c", "slot": "cell", "kicker": "YOUR CELL IS READING"],
        ])
        let resolved = PlanPicks.resolve(promos, in: rows)
        XCTAssertEqual(resolved.map(\.plan.planId), ["c", "a"], "unknown plans dropped, a plan never twice, the server's order kept")
        XCTAssertEqual(resolved.first?.kicker, "FROM THE LIBRARY", "the hero is the server's first")
        XCTAssertEqual(resolved.last?.kicker, "FOR YOU", "a blank kicker reads as Android's")
        XCTAssertTrue(PlanPicks.resolve([], in: rows).isEmpty)
    }

    // MARK: §8.2 #14 — one icon per notice family

    func testEveryNoticeFamilyWearsItsOneIcon() {
        let table: [(String, Lucide)] = [
            ("badge_awarded", .badgeCheck), ("certificate_issued", .award),
            ("level_completed", .trendingUp), ("level_ushered", .trendingUp),
            ("reflection_returned", .messageSquareText),
            ("serve_request_approved", .heartHandshake), ("department_need_open", .heartHandshake),
            ("giving_receipt", .handHeart), ("pledge_due_soon", .handHeart), ("payment_failed", .handHeart),
            ("event_reminder_24h", .calendarDays), ("event_cancelled", .calendarDays),
            ("announcement", .megaphone),
            ("live_stream_started", .radio), ("live_guest_invite", .radio),
            ("chat_dm_message", .messageCircle), ("connection_request_received", .userPlus),
            ("plan_group_invite_received", .bookMarked), ("plan_day_due", .bookMarked), ("reading_invite", .bookMarked),
            ("module_completed", .bookOpen), ("quiz_passed", .bookOpen),
            ("prayer_chain", .leaf), ("verse_review", .leaf),
            ("sunday_letter", .mail), ("streak_milestone", .flame), ("cell_gathering", .users),
            ("security_alert", .shield),
            ("reengage", .bell), ("community_blessing", .bell), ("", .bell),
        ]
        for (template, icon) in table {
            XCTAssertEqual(NoticeFamily.icon(template), icon, template)
        }
        XCTAssertNotEqual(NoticeFamily.icon("live_stream_started"), .settings, "a Live is never a gear")
        XCTAssertEqual(NoticeFamily.icon("LIVE_STREAM_STARTED"), .radio, "case never matters")
    }

    // MARK: §8.2 #16 — the exam's refusal is §4's one state card

    func testTheExamsRefusalIsTheStateCardWithGoBack() {
        let words = "Your Level 1 exam isn't ready yet — we'll let you know when it opens."
        let copy = LevelExamView.refusalCopy(words)
        XCTAssertEqual(copy.cause, .refusal)
        XCTAssertEqual(copy.title, words, "the server's own words, as it wrote them")
        XCTAssertNil(copy.line)
        XCTAssertEqual(copy.action, .goBack, "never Try again — it would only be refused again")
    }

    // MARK: Cycle 4 visual notes — an announcement's body is markdown

    /// It rendered raw through a plain `Text` ("**great people**"). Now the
    /// lesson's renderer draws it — and keeps the author's line breaks, where a
    /// lesson keeps markdown's soft wrap.
    func testAnAnnouncementsBodyIsMarkdownWithItsLineBreaksKept() {
        let body = "Greetings **great people**.\n\n## This week\n- Bring a friend\n- Bring a Bible\n\nYours in Service,\nDiscipleship Dept."
        let blocks = MLMarkdown.parse(body, hardBreaks: true)
        XCTAssertEqual(blocks.count, 4)
        guard blocks.count == 4 else { return }
        if case let .paragraph(t) = blocks[0] { XCTAssertEqual(t, "Greetings **great people**.") } else { XCTFail("paragraph") }
        if case let .heading(level, t) = blocks[1] { XCTAssertEqual(level, 2); XCTAssertEqual(t, "This week") } else { XCTFail("heading") }
        if case let .bullet(items) = blocks[2] { XCTAssertEqual(items, ["Bring a friend", "Bring a Bible"]) } else { XCTFail("list") }
        if case let .paragraph(t) = blocks[3] {
            XCTAssertEqual(t, "Yours in Service,\nDiscipleship Dept.", "the sign-off keeps its two lines")
        } else { XCTFail("sign-off") }
        // The emphasis is drawn, never shown as asterisks.
        XCTAssertEqual(String(MLMarkdown.inline("Greetings **great people**.").characters), "Greetings great people.")
        // A lesson's single line break is still markdown's soft wrap.
        if case let .paragraph(t)? = MLMarkdown.parse("one\ntwo").first { XCTAssertEqual(t, "one two") } else { XCTFail("lesson") }
    }

    // MARK: Cycle 4 B1 — a discipler is offered only when the server names one

    /// The walk found a discipler offered in five places to members with none
    /// (Home, Pathway, the level page ×3, Community). Each asks the one store,
    /// fed by GET /growth/mentor; "mentor": null — what Ada and build7 get from
    /// the local API — offers nothing.
    func testADisciplerIsOfferedOnlyWhenTheServerNamesOne() throws {
        let none = try decode(MentorInfo.self, ["mentor": NSNull(), "next_meeting_at": NSNull(), "notes": []])
        XCTAssertNil(none.mentor)
        XCTAssertFalse(DisciplerStore.offers(none.mentor))
        let paired = try decode(MentorInfo.self, ["mentor": ["mentor_user_id": "u1", "full_name": "Ann Wanjiru"], "notes": []])
        XCTAssertEqual(paired.mentor?.fullName, "Ann Wanjiru")
        XCTAssertTrue(DisciplerStore.offers(paired.mentor))
    }

    /// One word for who opens the next level (E2): §3's "your leader", the
    /// same sentence on the hero, the level's fold, the level page and the
    /// exam's pass screen — never "your discipler's blessing".
    func testWhoOpensTheNextLevelIsSaidOneWay() throws {
        XCTAssertEqual(UsherWords.line(passed: 1),
                       "You passed the Level 1 exam. Your leader will open Level 2 — you'll get a notice.")
        var row = level(1, "awaiting_review", done: 10, of: 10)
        row["awaiting_review"] = true
        let j = try XCTUnwrap(Journey.derive(try summary(current: 1, row)))
        XCTAssertEqual(j.stage, .awaitingUsher)
        XCTAssertEqual(j.line, UsherWords.line(passed: 1), "the hero says the same sentence")
        XCTAssertFalse(j.line.contains("discipler"))
    }

    // MARK: Cycle 3 close walk B2 — the trail's exam row is the exam step

    /// Ada's Level 1: twenty lessons done, the exam row open. The trail drew
    /// that row as "MODULE 21 · Level 1 Review · Start this module"; it is the
    /// exam step now, and the one place the exam is offered — no gate card
    /// beside it saying it twice — and never counted as a module.
    @MainActor
    func testTheTrailsExamRowIsTheExamStepAndTheOnlyOffer() throws {
        let vm = LevelDetailViewModel(levelNumber: 1)
        let trail = try adasTrail()
        vm.modules = trail
        vm.level = try decode(PathwayLevel.self, adasLevelOne)
        vm.journey = Journey.derive(try summary(current: 1, adasLevelOne), trail: trail)
        let exam = try XCTUnwrap(vm.modules.last)
        XCTAssertTrue(exam.isExam)
        XCTAssertFalse(exam.locked)
        XCTAssertFalse(vm.examAvailable, "the row offers the exam; a gate beside it would offer it twice")
        XCTAssertEqual(vm.completed, 20)
        XCTAssertEqual(vm.moduleCount, 20, "the exam row is never counted as a module")
        // Without an exam row (an older server), the gate is the trail's end.
        vm.modules = Array(trail.dropLast())
        XCTAssertTrue(vm.examAvailable)
    }

    // MARK: Cycle 3 close walk B3 — no progress claimed before there is any

    func testANeverOpenedModuleIsUpNextNotInProgress() throws {
        let fresh = try decode([LevelModule].self, [module("m1", level: 1, seq: 1, "next")]).first!
        XCTAssertEqual(fresh.progress, 0)
        XCTAssertEqual(ModuleRowWords.openCaption(progress: fresh.progress), "Up next · tap to start")
        XCTAssertEqual(ModuleRowWords.openAction(progress: fresh.progress), "Start")
        XCTAssertEqual(ModuleRowWords.openCaption(progress: 40), "In progress · tap to continue")
        XCTAssertEqual(ModuleRowWords.openAction(progress: 40), "Resume")
    }

    // MARK: Android walk A4 / iOS E18 — one way to name a few people

    func testOneJoinerForAFewNames() {
        XCTAssertNil(NameList.join([], others: 0))
        XCTAssertEqual(NameList.join(["Ada"], others: 0), "Ada")
        XCTAssertEqual(NameList.join(["Ada", "Ben"], others: 0), "Ada and Ben")
        XCTAssertEqual(NameList.join(["Ada", "Ben", "Cara"], others: 0), "Ada, Ben and Cara")
        XCTAssertEqual(NameList.join(["Dee", "Cara", "Builder"], others: 2), "Dee, Cara, Builder and 2 others",
                       "never \"Dee, Cara and Builder and 2 others\"")
        XCTAssertEqual(NameList.join(["Eli"], others: 1), "Eli and 1 other")
        XCTAssertEqual(NameList.join(["Dee", "Cara", "Builder"], others: 2, stable: true), "Builder, Cara, Dee and 2 others",
                       "a stable order, so the line doesn't reshuffle on every load")
    }

    // MARK: Android walk A2 — "before you" only when it's true

    func testFootprintsSayBeforeYouOnlyWhileTheModuleIsYetToDo() throws {
        let r = try decode(FootprintsRes.self, ["count": 3, "scope": "cell",
                                                "footprints": [["first_name": "Eli", "completed_at": "2026-10-04T08:00:00Z"],
                                                               ["first_name": "Dee", "completed_at": "2026-10-03T08:00:00Z"]]])
        XCTAssertEqual(FootprintsStrip.line(r, mineDone: false), "Eli, Dee and 1 other walked here before you.")
        XCTAssertEqual(FootprintsStrip.line(r, mineDone: true), "Eli, Dee and 1 other walked here too.",
                       "a member who finished first never reads that Eli walked it before them")
        XCTAssertNil(FootprintsStrip.line(try decode(FootprintsRes.self, ["count": 0, "scope": "cell", "footprints": []]), mineDone: false))
    }

    func testTheFoldedLevelAndItsCountAgree() throws {
        let trail = try adasTrail()
        let lvl = try decode(PathwayLevel.self, adasLevelOne)
        XCTAssertEqual(PathwayTrail.foldLine(trail, expanded: false), "20 of 20 modules done · Show")
        XCTAssertEqual("\(lvl.lessonsDone) of \(lvl.lessonCount)", "20 of 20", "the line above the fold says the same")
    }
}
