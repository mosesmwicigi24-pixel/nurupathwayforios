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

    // MARK: Cycle 3 close walk B4 — a done Talk says so

    func testADoneTalkSaysCompletedWithAQuietWayBack() {
        XCTAssertEqual(TalkWords.done, "Completed ✓")
        XCTAssertEqual(TalkWords.back(day: 4), "Back to Day 4")
    }

    // MARK: Cycle 3 close walk B12 — the real version and build

    func testSettingsSaysTheInstalledVersionAndBuild() {
        XCTAssertEqual(AppVersion.line(["CFBundleShortVersionString": "1.1", "CFBundleVersion": "130"]), "Nuru Pathway · 1.1 (130)")
        XCTAssertEqual(AppVersion.line(["CFBundleShortVersionString": "1.1"]), "Nuru Pathway · 1.1")
        XCTAssertEqual(AppVersion.line([:]), "Nuru Pathway")
        let live = AppVersion.line()
        XCTAssertFalse(live.contains("v1.0"))
        XCTAssertTrue(live.hasPrefix("Nuru Pathway · "), "the test host carries a version: \(live)")
    }

    // MARK: Cycle 3 close walk B11 — notices iOS can deliver, and no others

    func testNoticesPromiseOnlyWhatThisPhoneDelivers() throws {
        XCTAssertFalse(IOSNoticeWords.rsvpSaved.contains("we'll remind you"), "no reminder iOS can't deliver")
        XCTAssertTrue(IOSNoticeWords.rsvpSaved.contains("inbox"))
        XCTAssertTrue(IOSNoticeWords.pledgeReminder.contains("inbox"))
        XCTAssertFalse(IOSNoticeWords.bannersTitle.lowercased().contains("push"), "iOS has no remote push yet")
        let d = try XCTUnwrap(UserDefaults(suiteName: "B11.\(UUID().uuidString)"))
        XCTAssertTrue(IOSNoticeWords.bannersOn(d), "unset reads as on, as the switch shows it")
        d.set(false, forKey: IOSNoticeWords.bannersKey)
        XCTAssertFalse(IOSNoticeWords.bannersOn(d), "off means no banners")
    }

    // MARK: Cycle 3 close walk B5 — Home refreshes in place

    func testHomeRefreshesInPlaceWithinItsGuards() {
        let now = Date()
        let long = now.addingTimeInterval(-60)
        XCTAssertTrue(HomeRefresh.should(loading: false, loaded: true, online: true, last: long, now: now))
        XCTAssertTrue(HomeRefresh.should(loading: false, loaded: true, online: nil, last: long, now: now), "unknown network: try")
        XCTAssertFalse(HomeRefresh.should(loading: false, loaded: false, online: true, last: long, now: now), "the first load is the load's, with its skeleton")
        XCTAssertFalse(HomeRefresh.should(loading: true, loaded: true, online: true, last: long, now: now), "never on top of a load")
        XCTAssertFalse(HomeRefresh.should(loading: false, loaded: true, online: false, last: long, now: now), "offline: keep what's shown")
        XCTAssertFalse(HomeRefresh.should(loading: false, loaded: true, online: true, last: now.addingTimeInterval(-10), now: now),
                       "at most every \(Int(HomeRefresh.minimumGap)) s")
    }

    // MARK: Cycle 3 close walk B6 — a featured gathering only while it meets again; E16 one date shape

    func testTheFeaturedGatheringShowsItsNextMeetingOrNoCard() throws {
        let nairobi = try XCTUnwrap(TimeZone(identifier: "Africa/Nairobi"))
        let now = try XCTUnwrap(NuruDates.parse("2026-10-05T14:00:00Z"))
        // The walk's case: a weekly series first met 30 Aug and has ended — old server, no next_at.
        let ended = try decode(FeaturedEvent.self, ["series_id": "s1", "title": "Pathway Discipleship Classes",
                                                    "dtstart_local": "2026-08-30T14:00:00", "next_at": NSNull()])
        XCTAssertNil(ended.nextStart(now: now, timeZone: nairobi), "never the series' first date, five weeks gone")
        // A newer server says when it next meets.
        let weekly = try decode(FeaturedEvent.self, ["series_id": "s2", "title": "Sunday Service",
                                                     "dtstart_local": "2026-08-30T09:00:00",
                                                     "next_at": "2026-10-11T06:00:00.000Z", "next_end_at": "2026-10-11T10:00:00.000Z"])
        let next = try XCTUnwrap(weekly.nextStart(now: now, timeZone: nairobi))
        XCTAssertEqual(NuruDates.dayTime(next, now: now, timeZone: nairobi), "Sun 11 Oct · 9:00 AM")
        // Kept while the meeting runs; gone once it has ended.
        let during = try XCTUnwrap(NuruDates.parse("2026-10-11T08:00:00Z"))
        XCTAssertNotNil(weekly.nextStart(now: during, timeZone: nairobi))
        let after = try XCTUnwrap(NuruDates.parse("2026-10-11T10:30:00Z"))
        XCTAssertNil(weekly.nextStart(now: after, timeZone: nairobi))
        // A one-off still ahead, from a server without next_at.
        let ahead = try decode(FeaturedEvent.self, ["series_id": "s3", "title": "Ablaze", "dtstart_local": "2026-10-16T15:00:00"])
        XCTAssertNotNil(ahead.nextStart(now: now, timeZone: nairobi))
    }

    // MARK: Cycle 3 close walk E10 — the carousel shows a series once, at its next date

    func testTheCarouselShowsASeriesOnceAtItsNextDate() throws {
        func row(_ occ: String, _ series: String, _ at: String) throws -> HomeEventRow {
            try decode(HomeEventRow.self, ["occurrence_id": occ, "series_id": series, "title": "Welcome to Ablaze",
                                           "starts_at": at])
        }
        let rows = [try row("oct", "ablaze", "2026-10-25T12:30:00Z"), try row("nov", "ablaze", "2026-11-25T12:30:00Z"),
                    try row("dec", "ablaze", "2026-12-25T12:30:00Z"), try row("svc", "sunday", "2026-10-11T06:00:00Z"),
                    try row("solo", "", "2026-10-16T12:00:00Z")]
        XCTAssertEqual(HomeFeatured.carouselEvents(rows, featuredSeriesId: nil, onNowOccurrenceId: nil).map(\.occurrenceId),
                       ["oct", "svc", "solo"], "Ablaze once, at 25 Oct — never three times")
    }

    // MARK: Cycle 3 close walk B7 — one gift, one time

    @MainActor
    func testAGiftShowsOneTimeOnTheStatementAndTheReceipt() throws {
        let gift: [String: Any] = ["transaction_id": "t1", "amount_minor": 20000, "currency": "KES", "status": "settled",
                                   "fund": "tithe", "created_at": "2026-10-05T08:58:00.000Z", "settled_at": "2026-10-05T08:59:00.000Z"]
        let record = try decode(GivingRecord.self, gift)
        let detail = try decode(GivingDetail.self, gift)
        XCTAssertEqual(record.shownAt, "2026-10-05T08:59:00.000Z", "a settled gift shows when it settled")
        XCTAssertEqual(record.shownAt, detail.shownAt, "the statement and the receipt say the same time")
        var pending = gift; pending["status"] = "pending"; pending["settled_at"] = NSNull()
        XCTAssertEqual(try decode(GivingRecord.self, pending).shownAt, "2026-10-05T08:58:00.000Z", "not settled: when it was given")

        // Which year a gift counts in stays created_at (the statements' rule):
        // given 23:59:50 on 31 Dec (EAT), settled ten seconds into 1 Jan.
        var lateNight = gift; lateNight["transaction_id"] = "t2"
        lateNight["created_at"] = "2025-12-31T20:59:50.000Z"; lateNight["settled_at"] = "2025-12-31T21:00:10.000Z"
        let vm = GivingStatementViewModel()
        vm.history = [record, try decode(GivingRecord.self, lateNight)]
        XCTAssertEqual(vm.records(in: 2025).map(\.transactionId), ["t2"])
        XCTAssertEqual(vm.records(in: 2026).map(\.transactionId), ["t1"])
    }

    // MARK: Android walk A5 / iOS walk E13, E18 — no internal ids shown as facts

    func testNoInternalIdIsShownAsAFactToRead() throws {
        func source(_ rel: String) throws -> String {
            try String(contentsOf: TypeScan.appRoot.appendingPathComponent(rel), encoding: .utf8)
        }
        let receipt = try source("Features/Give/GivingReceiptView.swift")
        XCTAssertFalse(receipt.contains("transactionId.prefix(8)) + \"…\""), "the receipt never prints the internal transaction id")
        let profile = try source("Features/Profile/ProfileView.swift")
        XCTAssertFalse(profile.contains("Text(memberIdLabel)"), "Profile never opens on a raw member ID")
        XCTAssertTrue(profile.contains("\"Copy member ID\""), "the ID still copies whole, from the foot")
        let statement = try source("Features/Give/GivingStatementView.swift")
        XCTAssertFalse(statement.contains("held under Finance"), "no internal department names")
    }

    // MARK: Cycle 3 close walk E3 — one gold primary on Plans

    func testPlansHasOneGoldPrimaryAndOneWayToStartAPlan() throws {
        XCTAssertFalse(PlanPromoWords.cta.hasPrefix("Begin"), "a promo opens the plan; starting is the plan page's Begin Day 1")
        let view = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Grow/ReadingPlansView.swift"), encoding: .utf8)
        XCTAssertEqual(view.components(separatedBy: "primary: continueReading.isEmpty").count - 1, 2,
                       "only the hero promo may be gold, and only while no plan is being read")
        XCTAssertFalse(view.contains("primary: true"))
        XCTAssertTrue(view.contains("PlansPrimaryLabel(text: \"Continue · Day"), "the plan in progress holds the gold")
    }

    // MARK: Cycle 3 close walk E7 — Give lists only rails that work

    func testGiveListsOnlyTheRailsThatCanTakeTheGift() {
        func rail(_ key: String, _ enabled: Bool, _ currency: String, reason: String? = nil) -> GivingMethod {
            GivingMethod(key: key, label: key, enabled: enabled, unavailableReason: reason, currency: currency,
                         minMinor: 100, maxMinor: 1_000_000, wholeUnits: true, recurring: true, needsPhone: key == "mpesa")
        }
        let m = GivingMethods(methods: [rail("mpesa", true, "KES"), rail("airtel", false, "KES", reason: "coming_soon"),
                                        rail("paypal", false, "USD", reason: "coming_soon"), rail("card", true, "KES")],
                              phoneOnFile: nil, defaultMethod: "mpesa")
        XCTAssertEqual(GivingRails.listed(m), ["mpesa"], "no SOON rows, and no card this build can't complete")
        XCTAssertEqual(GivingRails.listed(m, onlyCurrency: "USD"), [], "a USD pledge with PayPal off lists nothing (the note says why)")
        let both = GivingMethods(methods: [rail("mpesa", true, "KES"), rail("airtel", false, "KES"), rail("paypal", true, "KES")],
                                 phoneOnFile: nil, defaultMethod: "mpesa")
        XCTAssertEqual(GivingRails.listed(both), ["mpesa", "paypal"])
        XCTAssertEqual(GivingRails.moved(["mpesa", "airtel", "paypal"], listed: ["mpesa", "paypal"], from: 1, by: -1),
                       ["paypal", "mpesa", "airtel"], "one tap moves a rail past its listed neighbour")
        XCTAssertEqual(GivingRails.moved(["mpesa", "airtel", "paypal"], listed: ["mpesa", "paypal"], from: 0, by: 1),
                       ["airtel", "paypal", "mpesa"])
    }

    // MARK: Cycle 3 close walk E5 — Map view says what the journey says

    func testMapViewSpeaksTheJourneysWordsForAFinishedLevel() throws {
        let s = try summary(current: 1, adasLevelOne)
        let j = try XCTUnwrap(Journey.derive(s, trail: try adasTrail()))
        XCTAssertEqual(j.stage, .examReady)
        let one = try XCTUnwrap(s.levels.first { $0.levelNumber == 1 })
        let card = LevelsMapWords.continueCard(level: one, journey: j)
        XCTAssertEqual(card.title, "Take the Level 1 exam", "never CONTINUE YOUR JOURNEY over a level whose modules are done")
        XCTAssertFalse(card.kicker.contains("CONTINUE"))
        XCTAssertEqual(LevelsMapWords.lockLine(levelNumber: 2, journey: j),
                       "Pass the Level 1 exam — then your leader opens Level 2", "never \"Complete Level 1\" for a level that is")
        XCTAssertEqual(LevelsMapWords.lockLine(levelNumber: 3, journey: j), "Complete Level 2 to unlock")
        // Still walking modules: the card continues, the next level waits on this one.
        let walking = try summary(current: 1, level(1, "active", done: 4, of: 10))
        let jw = try XCTUnwrap(Journey.derive(walking))
        let w1 = try XCTUnwrap(walking.levels.first { $0.levelNumber == 1 })
        XCTAssertEqual(LevelsMapWords.continueCard(level: w1, journey: jw).kicker, "CONTINUE YOUR JOURNEY")
        XCTAssertEqual(LevelsMapWords.lockLine(levelNumber: 2, journey: jw), "Complete Level 1 to unlock")
    }

    // MARK: Android walk A1 — no standing until there is one

    func testNoPartnerStandingBeforeAPledgeOrAGiftThatWentThrough() throws {
        // Ben, verbatim from the local API (2026-10-05): a schedule whose first collection failed.
        let ben: [String: Any] = ["is_partner": true, "ever_partnered": true, "status": "active",
                                  "since": "2026-10-05T07:08:32.900Z", "kept": 0, "given_minor": 0, "currency": "KES",
                                  "membership": NSNull(),
                                  "tier": ["name": "carries one disciple through a level, every year",
                                           "monthly_minor": 170000, "disciples_per_year": 1],
                                  "pledges": [], "due": [],
                                  "trouble": ["paused": false, "consecutive_failures": 1, "last_failed_at": "2026-10-05T02:08:32.930Z"]]
        XCTAssertFalse(PartnerStanding.isReal(try decode(Partnership.self, ben)),
                       "no \"Partner since\", no \"0 gifts kept\", no tier beside a gift that failed")
        var kept = ben; kept["kept"] = 1; kept["given_minor"] = 200000
        XCTAssertTrue(PartnerStanding.isReal(try decode(Partnership.self, kept)), "a gift that went through")
        XCTAssertFalse(PartnerStanding.notYet.contains("0"))
    }

    // MARK: Android walk A7 — a pledge not yet begun says when it starts

    func testAMonthlyPledgeNotYetBegunSaysWhenItStarts() throws {
        // Ada's "Kenya trip", verbatim from the local API (2026-10-05).
        let kenya: [String: Any] = ["pledge_id": "p1", "title": "Kenya trip", "shape": "monthly", "amount_minor": 500000,
                                    "currency": "KES", "due_day": 5, "status": "active",
                                    "starts_on": "2026-11-05", "created_at": "2026-10-05 10:08:32.861599+03",
                                    "progress": ["paid_minor": 0, "period_paid_minor": 0, "next_due": "2026-11-05", "label": "on_track"]]
        let p = try decode(Pledge.self, kenya)
        XCTAssertEqual(PledgeWords.progressLine(p, today: "2026-10-05"), "Starts Thu 5 Nov",
                       "never \"KSh 0 of KSh 5,000 this month\" in a month it was never due")
        XCTAssertEqual(PledgeWords.progressLine(p, today: "2026-11-05"), "KSh 0 of KSh 5,000 this month",
                       "from its first day, the month's progress — and no \"KSh 0 given in all\"")
    }

    // MARK: Cycle 3 close walk E18 — sheets fit what they hold

    func testAFittedSheetIsAsTallAsItsContent() {
        XCTAssertEqual(PSheetFit.height(content: 160, chrome: 58, screen: 874), 218, "a name field and Save: no empty lower half")
        XCTAssertEqual(PSheetFit.height(content: 40, chrome: 58, screen: 874), 200, "never under the floor")
        XCTAssertEqual(PSheetFit.height(content: 2000, chrome: 58, screen: 874), 874 * 0.9, accuracy: 0.01, "a long list scrolls inside 90%")
    }

    // MARK: Android walk A3 — no fact before it loads

    func testHomeSaysNothingItDoesNotKnowYet() {
        XCTAssertEqual(HomeHeaderWords.greeting("Good evening", fullName: nil), "Good evening.", "never \"Friend\" for a name not loaded")
        XCTAssertEqual(HomeHeaderWords.greeting("Good evening", fullName: "Ada Thriving"), "Good evening, Ada.")
        XCTAssertFalse(HomeHeaderWords.showsScore(nil), "no ring before the score comes back")
        XCTAssertFalse(HomeHeaderWords.showsScore(0), "and no \"0\" ring (§7.4 #9)")
        XCTAssertTrue(HomeHeaderWords.showsScore(26))
    }

    // MARK: §7.4 owner decision — the location switch waits for the server

    func testTheLocationSwitchWaitsForTheServerEverywhereItIsTurned() throws {
        XCTAssertTrue(LocationSharing.noFixLine(denied: true).hasPrefix("Couldn't save that. "))
        XCTAssertTrue(LocationSharing.noFixLine(denied: false).hasPrefix("Couldn't save that. "))
        var sources = ""
        for rel in ["Features/Profile/SettingsView.swift", "Features/Shell/LocationInvite.swift", "Features/Shell/RootView.swift"] {
            sources += try String(contentsOf: TypeScan.appRoot.appendingPathComponent(rel), encoding: .utf8)
        }
        XCTAssertEqual(sources.components(separatedBy: "try? await MemberAPI.shareLocation").count - 1, 1,
                       "only the silent refresh for a member who already said yes may ignore the answer")
        XCTAssertFalse(sources.contains("try? await MemberAPI.stopSharingLocation"), "stopping waits for the server too")
        XCTAssertFalse(sources.contains("isOn: $shareLocation"), "the switch never moves ahead of the server")
    }

    // MARK: §7.4 owner decision — hearts never claim "Saved"

    func testHeartsOnTheDevotionalAndPlanPagesNeverClaimSaved() throws {
        XCTAssertEqual(HeartWords.label, "Like")
        for rel in ["Features/Grow/DevotionalView.swift", "Features/Grow/ReadingPlansView.swift"] {
            let src = try String(contentsOf: TypeScan.appRoot.appendingPathComponent(rel), encoding: .utf8)
            XCTAssertFalse(src.contains("loved ? \"Saved\""), rel)
            XCTAssertFalse(src.contains("saved ? \"Saved\""), rel)
        }
    }

    // MARK: Cycle 4 item 4 — Home's verse Save says why it failed

    @MainActor
    func testTheVerseSaveFailureIsSaidInWords() throws {
        let vm = HomeViewModel()
        XCTAssertNil(vm.verseSaveLine)
        let src = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Home/HomeView.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("verseSaveLine = NuruStateCopy.saveFailureLine(error)"), "felt AND said, in §4's words")
        XCTAssertTrue(NuruStateCopy.saveFailureLine(URLError(.notConnectedToInternet), deviceOnline: false).hasPrefix("Couldn't save that. "))
    }

    // MARK: Cycle 4 item 4 — nothing typed or recorded is lost to a failed send; failures are said

    func testAFailedSendKeepsTheWordsAndSaysWhy() throws {
        let offline = URLError(.notConnectedToInternet)
        let send = NuruStateCopy.sendFailureLine(offline, deviceOnline: false)
        XCTAssertTrue(send.hasPrefix("Couldn't send that. You're offline."))
        XCTAssertTrue(send.hasSuffix("Your words are kept — send again when you're ready."))
        XCTAssertTrue(NuruStateCopy.deleteFailureLine(offline, deviceOnline: false).hasSuffix("It's still here."))
        func src(_ rel: String) throws -> String {
            try String(contentsOf: TypeScan.appRoot.appendingPathComponent(rel), encoding: .utf8)
        }
        // The live chat composers no longer clear the words before the server has them.
        XCTAssertFalse(try src("Features/Live/LiveChatSheet.swift").contains("guard let sent = try? await MemberAPI.sendLiveMessage"))
        XCTAssertFalse(try src("Features/Live/LiveFloatingChatOverlay.swift").contains("guard let sent = try? await MemberAPI.sendLiveMessage"))
        for (rel, line) in [("Features/Community/PrayerWallDetailView.swift", "commentLine = NuruStateCopy.sendFailureLine(error)"),
                            ("Features/Community/PrayerWallDetailView.swift", "answeredLine = NuruStateCopy.saveFailureLine(error)"),
                            ("Features/Events/EventDetailView.swift", "postLine = NuruStateCopy.sendFailureLine("),
                            ("Features/Chat/ChatThreadView.swift", "voiceFailLine = NuruStateCopy.sendFailureLine("),
                            ("Features/Live/NuruLiveTabView.swift", "deleteFailureLine = NuruStateCopy.deleteFailureLine(error)"),
                            ("Features/Live/GoLiveBroadcastView.swift", "deleteFailureLine = NuruStateCopy.deleteFailureLine(error)")] {
            XCTAssertTrue(try src(rel).contains(line), "\(rel): the failure is said in §4's words")
        }
    }

    // MARK: §8.1 rule 1 — no other hues

    /// A hex colour's family: nil for the palette's own (neutrals, golds,
    /// navies) and the state colours (green, red); else the hue that isn't
    /// ours. The same thresholds as the scan that found 255 sites.
    private static func offPaletteFamily(_ hex: UInt32) -> String? {
        let r = Double((hex >> 16) & 0xFF) / 255, g = Double((hex >> 8) & 0xFF) / 255, b = Double(hex & 0xFF) / 255
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        guard d > 0 else { return nil }
        let sat = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
        var h: Double
        if mx == r { h = (g - b) / d + (g < b ? 6 : 0) } else if mx == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
        h *= 60
        if sat < 0.18 || l > 0.94 || l < 0.08 { return nil }
        if (30...55).contains(h) { return nil }                       // gold / amber
        if (195...225).contains(h) && (l < 0.45 || sat < 0.45) { return nil }   // navy, blue-grey
        if (90...160).contains(h) || h >= 345 || h <= 12 { return nil }       // green / red: state
        if h > 12 && h < 30 { return "orange" }
        if h > 160 && h < 195 { return "teal" }
        if (195...225).contains(h) { return "blue" }
        if h > 225 && h < 270 { return "indigo" }
        if h >= 270 && h < 330 { return "purple" }
        return "pink"
    }

    func testNoOtherHuesThanThePalettesAndTheStates() throws {
        // The classifier itself: the walk's purple Gift tile and indigo row
        // are caught; gold, navy and the state green/red are not.
        XCTAssertEqual(Self.offPaletteFamily(0xA855F7), "purple")
        XCTAssertEqual(Self.offPaletteFamily(0x6366F1), "indigo")
        XCTAssertEqual(Self.offPaletteFamily(0x0EA5E9), "blue")
        XCTAssertNil(Self.offPaletteFamily(0xC89B3C)); XCTAssertNil(Self.offPaletteFamily(0x0B1F33))
        XCTAssertNil(Self.offPaletteFamily(0x16A34A)); XCTAssertNil(Self.offPaletteFamily(0xDC2626))
        // Art and reaction effects are their own media; the RSVP "maybe"
        // amber is a state that reads orange to the scan.
        let allowed: Set<String> = ["Features/Home/LetterIllustrations.swift", "Features/Live/LiveReactionEffects.swift",
                                    "Features/Live/LiveViewerPlayerView.swift", "Features/Events/EventsView.swift"]
        let hex = try NSRegularExpression(pattern: "0x([0-9A-Fa-f]{6})\\b")
        var found: [String] = []
        for (rel, text) in try TypeScan.files() where !allowed.contains(rel) && !rel.hasSuffix("NuruTheme.swift") {
            for m in hex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range(at: 1), in: text), let v = UInt32(text[r], radix: 16),
                      let fam = Self.offPaletteFamily(v) else { continue }
                found.append("\(rel): \(fam) 0x\(text[r])")
            }
        }
        XCTAssertEqual(found, [], "§8.1 rule 1: paper, white, navy, gold — green, amber and red only for state")
    }

    // MARK: §8.1 rule 7 — one icon family in 14 / 18 / 22, one bell

    func testIconsAreFourteenEighteenOrTwentyTwoAndTheBellIsOne() throws {
        let sized = try NSRegularExpression(pattern: "Icon\\(\\.[a-zA-Z0-9]+, size: ([0-9]+(?:\\.[0-9]+)?)")
        var offScale: [String] = []
        var display = 0
        var bellLooks = 0
        for (rel, text) in try TypeScan.files() {
            for m in sized.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range(at: 1), in: text), let v = Double(text[r]) else { continue }
                if v >= 24 { display += 1; continue }   // a display glyph (a hero, a state card), not an icon in a row
                if ![14.0, 18.0, 22.0].contains(v) { offScale.append("\(rel): \(text[r])") }
            }
            if !rel.hasSuffix("NuruBell.swift") { bellLooks += text.components(separatedBy: "NuruBell(look:").count - 1 }
        }
        XCTAssertEqual(offScale, [], "§8.1 rule 7: icons at 14, 18 or 22")
        XCTAssertLessThanOrEqual(display, 53, "display glyphs are listed, never grow")
        XCTAssertEqual(bellLooks, 0, "one bell on every tab: NuruBell() — the same size, tile and icon")
        XCTAssertEqual(NuruBell.Look.standard.size, 44)
        XCTAssertEqual(NuruBell.Look.standard.iconSize, 18)
    }

    // MARK: §8.1 rule 4 — the primary is gold fill with navy text

    func testThePrimaryButtonIsGoldWithNavyText() throws {
        XCTAssertEqual(PButton(title: "Go", action: {}).variant, .gold, "the shared button's default is the one primary")
        let src = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Shared/Components.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains(".foregroundStyle(Nuru.navy)\n            .background(variant == .gold"), "navy text on gold")
        let journal = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Grow/PrayerJournalView.swift"), encoding: .utf8)
        XCTAssertTrue(journal.contains("Text(\"Add Prayer\").font(.nActionLabel).foregroundStyle(Nuru.navy)"))
    }

    // MARK: Walk E21 — the Events week strip and "N this week" mean the same seven days

    @MainActor
    func testTheEventsWeekStripStartsTodayAndMatchesTheWeekCount() throws {
        let vm = EventsViewModel()
        let week = vm.week
        XCTAssertEqual(week.count, EventsWeek.days)
        XCTAssertTrue(week.first?.isToday == true, "today first — never two days back")
        let src = try String(contentsOf: TypeScan.appRoot.appendingPathComponent("Features/Events/EventsView.swift"), encoding: .utf8)
        XCTAssertTrue(src.contains("value: EventsWeek.days, to: todayStart"), "the count uses the same window")
    }

    // MARK: §8.1 rule 8 — the people list never shows a raw role

    func testThePeopleListNeverShowsARawRole() {
        XCTAssertEqual(PersonWords.subtitle(role: "Student", level: 2, congregation: nil), "Level 2", "never \"Student\"")
        XCTAssertEqual(PersonWords.subtitle(role: "Student", level: nil, congregation: "Nuru Place"), "Member · Nuru Place")
        XCTAssertEqual(PersonWords.subtitle(role: "Instructor", level: 1, congregation: nil), "Teacher")
        XCTAssertEqual(PersonWords.subtitle(role: "SuperAdmin", level: 1, congregation: nil), "Church staff")
        for role in ["Student", "Instructor", "Admin", "SuperAdmin"] {
            XCTAssertFalse(PersonWords.subtitle(role: role, level: 1, congregation: nil).contains(role) && role != "Admin")
        }
    }

    // MARK: Walk E18 — the cell page's empty leader seat; no raw role

    func testTheCellLeaderSlotSaysNoRawRole() {
        XCTAssertNil(CellLeaderWords.role("Student"))
        XCTAssertNil(CellLeaderWords.role(nil))
        XCTAssertEqual(CellLeaderWords.role("Instructor"), "Teacher")
        XCTAssertEqual(CellLeaderWords.role("SuperAdmin"), "Church staff")
        XCTAssertEqual(Lucide.armchair.rawValue, "\u{E2C0}", "the empty seat, from the bundled Lucide font")
    }

    // MARK: Walk E22 — the key verse is the verse, the reference under it

    func testTheKeyVerseIsTheVerseNeverTheReferenceInQuotes() {
        XCTAssertTrue(ScriptureRefs.isReference("John 1:1-18"))
        XCTAssertNil(KeyVerseWords.text(line: "John 1:1-18", isReference: true, fetched: nil),
                     "before the words come: no quoted reference")
        XCTAssertEqual(KeyVerseWords.text(line: "John 3:16", isReference: true, fetched: " For God so loved the world… "),
                       "For God so loved the world…")
        XCTAssertEqual(KeyVerseWords.text(line: "Be still, and know that I am God.", isReference: false, fetched: nil),
                       "Be still, and know that I am God.", "authored words stay as written")
        XCTAssertEqual(KeyVerseWords.caption(reference: "John 3:16", version: "NIV"), "John 3:16 · NIV")
        XCTAssertEqual(KeyVerseWords.caption(reference: "John 3:16", version: nil), "John 3:16")
    }

    func testOneDateShapeWithTheYearOnlyWhenItIsNotThisYear() throws {
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(NuruDates.parse("2026-10-05T12:00:00Z"))
        let sameYear = try XCTUnwrap(NuruDates.parse("2026-10-25T15:30:00Z"))
        let nextYear = try XCTUnwrap(NuruDates.parse("2027-01-01T09:00:00Z"))
        XCTAssertEqual(NuruDates.day(sameYear, now: now, timeZone: utc), "Sun 25 Oct")
        XCTAssertEqual(NuruDates.day(nextYear, now: now, timeZone: utc), "Fri 1 Jan 2027")
        XCTAssertEqual(NuruDates.time(sameYear, timeZone: utc), "3:30 PM")
        XCTAssertEqual(NuruDates.dayTime(sameYear, now: now, timeZone: utc), "Sun 25 Oct · 3:30 PM")
    }

    func testTheFoldedLevelAndItsCountAgree() throws {
        let trail = try adasTrail()
        let lvl = try decode(PathwayLevel.self, adasLevelOne)
        XCTAssertEqual(PathwayTrail.foldLine(trail, expanded: false), "20 of 20 modules done · Show")
        XCTAssertEqual("\(lvl.lessonsDone) of \(lvl.lessonCount)", "20 of 20", "the line above the fold says the same")
    }
}
