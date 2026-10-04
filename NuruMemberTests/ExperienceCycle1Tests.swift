// Experience Cycle 1 — the foundation, pinned (pathway docs/EXPERIENCE.md
// §3–§4): the member's journey stage for every row of the table (and Levels
// 2–6 with nothing published — the case that used to commission a Level 1
// finisher), journey progress counted in levels and never 100 before the
// summit, the summit only at the finish, awaiting_review as its own level
// state, the one state language for every failure (offline only when the
// phone has no network), and the small truths (the giving card names only
// rails that work, one phone format). Payloads are decoded exactly like
// APIClient's: snake_case in.
import XCTest
@testable import NuruMember

final class ExperienceCycle1Tests: XCTestCase {

    // MARK: Fixtures — the /me/pathway and /levels/{n}/modules wire shapes

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    /// `examAvailable` nil = the key absent (a server that predates it).
    private func level(_ n: Int, _ status: String, done: Int = 0, of total: Int = 0,
                       awaiting: Bool = false, examPublished: Bool = true, examAvailable: Bool? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "level_number": n, "title": "Level \(n) title", "theme": NSNull(), "description": NSNull(),
            "total_modules": total, "completed_modules": done, "minutes": 0, "status": status,
            "awaiting_review": awaiting, "exam_published": examPublished]
        if let examAvailable { row["exam_available"] = examAvailable }
        return row
    }

    /// Six levels: `current` takes `row`; before it completed (10/10), after it
    /// locked with nothing published — today's real catalogue shape.
    private func summary(current: Int, _ row: [String: Any]) throws -> PathwaySummary {
        let levels: [[String: Any]] = (1...6).map { n in
            if n == current { return row }
            return n < current ? level(n, "completed", done: 10, of: 10) : level(n, "locked")
        }
        return try decode(PathwaySummary.self, ["current_level": current, "levels": levels])
    }

    private func module(_ id: String, level: Int, seq: Int, _ status: String,
                        completed: Bool = false, kind: String = "none", examAvailable: Bool? = nil) -> [String: Any] {
        var row: [String: Any] = [
            "module_id": id, "level_number": level, "module_sequence_number": seq, "title": "Module \(id)",
            "summary": NSNull(), "estimated_minutes": 10, "evaluation_kind": kind, "quiz_pass_mark": 70,
            "completed": completed, "status": status, "progress": completed ? 100 : 0, "locked": status == "locked"]
        if let examAvailable { row["exam_available"] = examAvailable }
        return row
    }

    private func trail(_ rows: [[String: Any]]) throws -> [LevelModule] {
        try decode([LevelModule].self, rows)
    }

    // MARK: §3 — every row of the table

    func testLearningContinuesTheNextModule() throws {
        let s = try summary(current: 2, level(2, "active", done: 3, of: 10))
        let t = try trail([module("a", level: 2, seq: 3, "completed", completed: true),
                           module("b", level: 2, seq: 4, "next"),
                           module("c", level: 2, seq: 5, "locked")])
        let j = try XCTUnwrap(Journey.derive(s, trail: t))
        XCTAssertEqual(j.stage, .learning)
        XCTAssertEqual(j.pill, "3 of 10 modules")
        XCTAssertEqual(j.kicker, "Continue · Level 2")
        XCTAssertEqual(j.title, "Module b")
        XCTAssertEqual(j.line, "3 of 10 modules in Level 2")
        XCTAssertEqual(j.actionLabel, "Continue")
        XCTAssertEqual(j.destination, .module("b"))
        XCTAssertEqual(j.destination?.route, .module("b"))
        XCTAssertEqual(j.levelPercent, 30)
        XCTAssertFalse(j.summitReached)
    }

    func testLearningAtZeroSaysStart() throws {
        let s = try summary(current: 1, level(1, "active", done: 0, of: 20))
        let j = try XCTUnwrap(Journey.derive(s, trail: try trail([module("m1", level: 1, seq: 1, "next")])))
        XCTAssertEqual(j.stage, .learning)
        XCTAssertEqual(j.pill, "0 of 20 modules")
        XCTAssertEqual(j.kicker, "Start · Level 1")
        XCTAssertEqual(j.actionLabel, "Start")
        XCTAssertEqual(j.destination, .module("m1"))
    }

    func testLearningWithoutItsTrailOpensTheLevel() throws {
        // The trail hasn't loaded (or failed): the step still speaks, from the summary.
        let j = try XCTUnwrap(Journey.derive(try summary(current: 2, level(2, "active", done: 4, of: 10))))
        XCTAssertEqual(j.title, "Level 2 title")
        XCTAssertEqual(j.destination, .level(2))
        // A trail for another level is ignored.
        let other = try trail([module("x", level: 1, seq: 1, "next")])
        XCTAssertEqual(Journey.derive(try summary(current: 2, level(2, "active", done: 4, of: 10)), trail: other)?.destination, .level(2))
    }

    func testContinueNeverReopensAFinishedModule() throws {
        // Every trail row done but the summary still says active (counts can
        // drift): no module to "continue" — the step opens the level instead.
        let s = try summary(current: 2, level(2, "active", done: 9, of: 10))
        let t = try trail([module("a", level: 2, seq: 1, "completed", completed: true),
                           module("b", level: 2, seq: 2, "completed", completed: true)])
        XCTAssertEqual(Journey.derive(s, trail: t)?.destination, .level(2))
    }

    func testExamReadyWhenEveryModuleIsDoneAndTheExamIsPublished() throws {
        let s = try summary(current: 1, level(1, "completed", done: 20, of: 20))
        let j = try XCTUnwrap(Journey.derive(s, trail: try trail([module("m20", level: 1, seq: 20, "completed", completed: true)])))
        XCTAssertEqual(j.stage, .examReady)
        XCTAssertEqual(j.pill, "Exam ready")
        XCTAssertEqual(j.kicker, "Exam ready · Level 1")
        XCTAssertEqual(j.title, "Take the Level 1 exam")
        XCTAssertEqual(j.line, "Every module is done — the exam opens the way to Level 2.")
        XCTAssertEqual(j.actionLabel, "Begin the exam")
        XCTAssertEqual(j.destination, .exam(1))
        XCTAssertEqual(j.destination?.route, .exam(1))
        XCTAssertEqual(j.levelPercent, 100)
        XCTAssertFalse(j.summitReached)
    }

    func testExamReadyWhenTheTrailsOwnExamRowIsNext() throws {
        // Prod's shape: the exit-exam row counts as a module, so the summary
        // still says active (10 of 11) — but the exam is what's left.
        let s = try summary(current: 1, level(1, "active", done: 10, of: 11))
        let t = try trail([module("m10", level: 1, seq: 10, "completed", completed: true),
                           module("exam", level: 1, seq: 11, "next", kind: "exit_exam")])
        let j = try XCTUnwrap(Journey.derive(s, trail: t))
        XCTAssertEqual(j.stage, .examReady)
        XCTAssertEqual(j.destination, .exam(1), "the exam row opens the exam, never the lesson reader")
        XCTAssertEqual(j.progressPercent, 17, "every module done counts the level whole — the same in either shape")
    }

    func testTheLastLevelsExamOpensTheWayToBeingSent() throws {
        let j = try XCTUnwrap(Journey.derive(try summary(current: 6, level(6, "completed", done: 8, of: 8))))
        XCTAssertEqual(j.stage, .examReady)
        XCTAssertEqual(j.line, "Every module is done — the exam opens the way to being sent.", "there is no Level 7")
    }

    func testExamSoonWhenTheExamIsNotPublished() throws {
        let s = try summary(current: 1, level(1, "completed", done: 20, of: 20, examPublished: false))
        let j = try XCTUnwrap(Journey.derive(s))
        XCTAssertEqual(j.stage, .examSoon)
        XCTAssertEqual(j.pill, "Exam opens soon")
        XCTAssertEqual(j.kicker, "Exam opens soon · Level 1")
        XCTAssertEqual(j.title, "Level 1 complete")
        XCTAssertEqual(j.line, "Every module is done. The exam opens soon — we'll let you know.")
        XCTAssertNil(j.actionLabel)
        XCTAssertNil(j.destination)
    }

    // MARK: §7.2 #1 — the exam is offered only when it can be taken

    /// Cycle 3: a published exam with no questions answered 422 behind "Exam
    /// ready". `exam_available` (published AND questions) decides: available
    /// → examReady; not → examSoon in §3's words, nothing to tap; absent (an
    /// older server) → exactly as before.
    func testExamReadyNeedsTheExamToBeAvailable() throws {
        let ready = try XCTUnwrap(Journey.derive(try summary(current: 1, level(1, "completed", done: 20, of: 20, examAvailable: true))))
        XCTAssertEqual(ready.stage, .examReady)
        XCTAssertEqual(ready.destination, .exam(1))

        let soon = try XCTUnwrap(Journey.derive(try summary(current: 1, level(1, "completed", done: 20, of: 20, examAvailable: false))))
        XCTAssertEqual(soon.stage, .examSoon, "published with no questions is not ready")
        XCTAssertEqual(soon.pill, "Exam opens soon")
        XCTAssertEqual(soon.kicker, "Exam opens soon · Level 1")
        XCTAssertEqual(soon.title, "Level 1 complete")
        XCTAssertEqual(soon.line, "Every module is done. The exam opens soon — we'll let you know.")
        XCTAssertNil(soon.actionLabel)
        XCTAssertNil(soon.destination, "nothing may open the exam")
        XCTAssertEqual(soon.progressLine.bold, "Level 1 complete")

        let older = try XCTUnwrap(Journey.derive(try summary(current: 1, level(1, "completed", done: 20, of: 20))))
        XCTAssertEqual(older.stage, .examReady, "no exam_available key: as before, published = ready")
        let unpublished = try XCTUnwrap(Journey.derive(try summary(current: 1, level(1, "completed", done: 20, of: 20,
                                                                                    examPublished: false, examAvailable: true))))
        XCTAssertEqual(unpublished.stage, .examSoon, "available never outranks unpublished")
    }

    /// Prod's shape: the trail's own exam row (`exam_available` on it) is the
    /// step at "10 of 11". Next but not available → examSoon; available or
    /// absent → examReady. A level saying not-available holds it too.
    func testTheTrailsExamRowIsOfferedOnlyWhenAvailable() throws {
        func journey(row: Bool?, level levelAvailable: Bool? = nil) throws -> Journey {
            let s = try summary(current: 1, level(1, "active", done: 10, of: 11, examAvailable: levelAvailable))
            let t = try trail([module("m10", level: 1, seq: 10, "completed", completed: true),
                               module("exam", level: 1, seq: 11, "next", kind: "exit_exam", examAvailable: row)])
            return try XCTUnwrap(Journey.derive(s, trail: t))
        }
        XCTAssertEqual(try journey(row: true).stage, .examReady)
        XCTAssertEqual(try journey(row: nil).stage, .examReady, "an older server: as before")
        let soon = try journey(row: false)
        XCTAssertEqual(soon.stage, .examSoon)
        XCTAssertNil(soon.destination)
        XCTAssertEqual(soon.progressPercent, 17, "every lesson done counts the level whole either way")
        XCTAssertEqual(try journey(row: true, level: false).stage, .examSoon, "the level's own word counts too")
    }

    /// Ada on the local API once the server serves the field: Level 1 at 20
    /// of 20, published, no questions — "Exam opens soon" on Home's pill and
    /// the week row; nothing opens the exam.
    func testAdasPathwayWithAnEmptyExamOpensSoon() throws {
        let levels: [[String: Any]] = [level(1, "completed", done: 20, of: 20, examAvailable: false)]
            + (2...6).map { level($0, "locked", examAvailable: false) }
        let j = try XCTUnwrap(Journey.derive(try decode(PathwaySummary.self, ["current_level": 1, "levels": levels])))
        XCTAssertEqual(j.stage, .examSoon)
        let row = HomeWeek.pathwayRow(j, enrolledLevel: 1)
        XCTAssertEqual(row.title, "Level 1 complete")
        XCTAssertEqual(row.line, "Level 1 · Exam opens soon")
        XCTAssertEqual(row.destination, .journey(nil), "the week row opens the Pathway tab, never the exam")
    }

    func testExamAvailableDecodesAndDefaultsToAvailable() throws {
        XCTAssertFalse(try decode(PathwayLevel.self, level(1, "completed", examAvailable: false)).examAvailable)
        XCTAssertTrue(try decode(PathwayLevel.self, level(1, "completed", examAvailable: true)).examAvailable)
        XCTAssertTrue(try decode(PathwayLevel.self, level(1, "completed")).examAvailable, "absent = available")
        let rows = try trail([module("exam", level: 1, seq: 11, "next", kind: "exit_exam", examAvailable: false),
                              module("exam2", level: 1, seq: 11, "next", kind: "exit_exam"),
                              module("m1", level: 1, seq: 1, "next")])
        XCTAssertEqual(rows.map(\.examAvailable), [false, true, true])
    }

    func testAwaitingUsherOnceTheExamIsPassed() throws {
        // The server says it twice: status "awaiting_review" and awaiting_review: true.
        let s = try summary(current: 1, level(1, "awaiting_review", done: 20, of: 20, awaiting: true))
        let j = try XCTUnwrap(Journey.derive(s))
        XCTAssertEqual(j.stage, .awaitingUsher)
        XCTAssertEqual(j.pill, "Exam passed")
        XCTAssertEqual(j.kicker, "Exam passed · Level 1")
        XCTAssertEqual(j.title, "Level 2 is next")
        XCTAssertEqual(j.line, "You passed the Level 1 exam. Your leader will open Level 2 — you'll get a notice.")
        XCTAssertEqual(j.actionLabel, "See Level 1")
        XCTAssertEqual(j.destination, .level(1))
        XCTAssertFalse(j.summitReached)
    }

    func testFinishedWhenTheLastLevelAwaitsItsUsher() throws {
        let s = try summary(current: 6, level(6, "awaiting_review", done: 8, of: 8, awaiting: true))
        let j = try XCTUnwrap(Journey.derive(s))
        XCTAssertEqual(j.stage, .finished)
        XCTAssertEqual(j.pill, "Commissioned")
        XCTAssertEqual(j.title, "You have been commissioned")
        XCTAssertEqual(j.line, "Sent to make disciples — Matthew 28:19")
        XCTAssertEqual(j.actionLabel, "See your journey")
        XCTAssertEqual(j.destination, .walk)
        XCTAssertEqual(j.destination?.route, .walk)
        XCTAssertTrue(j.summitReached)
        XCTAssertEqual(j.progressPercent, 100)
    }

    func testFinishedStaysFinishedAfterTheFinalUsher() throws {
        // After the last usher the summary no longer says awaiting; the trail's
        // exam row still says passed.
        let s = try summary(current: 6, level(6, "active", done: 8, of: 9))
        let t = try trail([module("m8", level: 6, seq: 8, "completed", completed: true),
                           module("exam6", level: 6, seq: 9, "completed", completed: true, kind: "exit_exam")])
        XCTAssertEqual(Journey.derive(s, trail: t)?.stage, .finished)
    }

    func testALevelWithNothingPublishedYet() throws {
        // Ushered into Level 2, which has no modules yet.
        let j = try XCTUnwrap(Journey.derive(try summary(current: 2, level(2, "active"))))
        XCTAssertEqual(j.stage, .learning)
        XCTAssertEqual(j.pill, "Modules open soon")
        XCTAssertEqual(j.title, "Level 2 is being prepared")
        XCTAssertEqual(j.line, "Its modules open soon — we'll let you know.")
        XCTAssertNil(j.destination)
        XCTAssertFalse(j.summitReached)
        XCTAssertEqual(j.progressPercent, 17)
        XCTAssertEqual(j.progressLine.bold, "Level 2 is being prepared")
    }

    /// Ada on the local API, verbatim: Level 1 at 20 of 20 with its exam
    /// published, Levels 2–6 locked with 0 modules each. Was: "Begin today",
    /// "0 modules left before Level 2", a 100% ring and "You have been commissioned".
    func testAdasPathwayIsExamReadyNotCommissioned() throws {
        let levels: [[String: Any]] = [level(1, "completed", done: 20, of: 20)] + (2...6).map { level($0, "locked") }
        let s = try decode(PathwaySummary.self, ["current_level": 1, "levels": levels])
        let j = try XCTUnwrap(Journey.derive(s))
        XCTAssertEqual(j.stage, .examReady)
        XCTAssertEqual(j.pill, "Exam ready")
        XCTAssertEqual(j.progressPercent, 17, "Level 1 of 6 — never 20 of 20 published modules = 100%")
        XCTAssertFalse(j.summitReached)
        XCTAssertEqual(j.progressLine.bold, "Take the Level 1 exam")
        XCTAssertEqual(j.progressLine.rest, "")
    }

    func testTheSummitIsReachedOnlyAtFinished() throws {
        let cases: [(PathwaySummary, Journey.Stage)] = [
            (try summary(current: 2, level(2, "active", done: 3, of: 10)), .learning),
            (try summary(current: 2, level(2, "active")), .learning),
            (try summary(current: 1, level(1, "completed", done: 20, of: 20)), .examReady),
            (try summary(current: 1, level(1, "completed", done: 20, of: 20, examPublished: false)), .examSoon),
            (try summary(current: 5, level(5, "awaiting_review", done: 9, of: 9, awaiting: true)), .awaitingUsher),
            (try summary(current: 6, level(6, "completed", done: 8, of: 8)), .examReady),
            (try summary(current: 6, level(6, "awaiting_review", done: 8, of: 8, awaiting: true)), .finished),
        ]
        for (s, stage) in cases {
            let j = try XCTUnwrap(Journey.derive(s))
            XCTAssertEqual(j.stage, stage)
            XCTAssertEqual(j.summitReached, stage == .finished, "\(stage)")
        }
    }

    func testNoLevelsNoJourney() throws {
        XCTAssertNil(Journey.derive(nil))
        XCTAssertNil(Journey.derive(try decode(PathwaySummary.self, ["current_level": 1, "levels": [[String: Any]]()])))
    }

    // MARK: §3 — journey progress, counted in levels

    func testJourneyProgressIsCountedInLevels() throws {
        // (levels before the current + the current fraction) / all levels
        XCTAssertEqual(Journey.derive(try summary(current: 3, level(3, "active", done: 5, of: 10)))?.progressPercent, 42)  // 2.5 / 6
        XCTAssertEqual(Journey.derive(try summary(current: 1, level(1, "active", done: 0, of: 20)))?.progressPercent, 0)
        XCTAssertEqual(Journey.derive(try summary(current: 4, level(4, "awaiting_review", done: 7, of: 7, awaiting: true)))?.progressPercent, 67)  // 4 / 6
        XCTAssertEqual(Journey.derive(try summary(current: 6, level(6, "awaiting_review", done: 8, of: 8, awaiting: true)))?.progressPercent, 100)
        let j = try XCTUnwrap(Journey.derive(try summary(current: 3, level(3, "active", done: 5, of: 10))))
        XCTAssertEqual(j.progress, 2.5 / 6, accuracy: 0.0001)
    }

    func testProgressNeverReadsOneHundredBeforeTheSummit() throws {
        // Every module of the last level done, its exam still ahead: 99, and
        // the summit hasn't fired.
        let ready = try XCTUnwrap(Journey.derive(try summary(current: 6, level(6, "completed", done: 8, of: 8))))
        XCTAssertEqual(ready.progressPercent, 99)
        XCTAssertFalse(ready.summitReached)
        XCTAssertEqual(Journey.derive(try summary(current: 6, level(6, "completed", done: 8, of: 8, examPublished: false)))?.progressPercent, 99)
        XCTAssertEqual(Journey.derive(try summary(current: 6, level(6, "active", done: 7, of: 8)))?.progressPercent, 98)  // 5.875 / 6
        XCTAssertEqual(Journey.derive(try summary(current: 6, level(6, "active", done: 799, of: 800)))?.progressPercent, 99,
                       "rounding never reaches 100 either")
        let sent = try XCTUnwrap(Journey.derive(try summary(current: 6, level(6, "awaiting_review", done: 8, of: 8, awaiting: true))))
        XCTAssertEqual(sent.progressPercent, 100)
        XCTAssertTrue(sent.summitReached)
    }

    func testALockedNextModuleOpensItsLevel() throws {
        // The next lesson is still behind its gate: the server would refuse it,
        // so the step opens the level page.
        let s = try summary(current: 2, level(2, "active", done: 3, of: 10))
        let t = try trail([module("a", level: 2, seq: 3, "completed", completed: true),
                           module("b", level: 2, seq: 4, "locked")])
        let j = try XCTUnwrap(Journey.derive(s, trail: t))
        XCTAssertEqual(j.title, "Module b")
        XCTAssertEqual(j.actionLabel, "Continue")
        XCTAssertEqual(j.destination, .level(2))
    }

    func testPastTheLastLevelIsCommissioned() throws {
        let levels: [[String: Any]] = (1...6).map { level($0, "completed", done: 8, of: 8) }
        let s = try decode(PathwaySummary.self, ["current_level": 7, "levels": levels])
        let j = try XCTUnwrap(Journey.derive(s))
        XCTAssertEqual(j.stage, .finished)
        XCTAssertEqual(j.levelNumber, 6)
        XCTAssertEqual(j.progressPercent, 100)
    }

    // MARK: awaiting_review is its own level state

    func testAwaitingReviewDecodesAsItsOwnState() throws {
        let both = try decode(PathwayLevel.self, level(1, "awaiting_review", done: 20, of: 20, awaiting: true))
        XCTAssertEqual(both.status, .awaitingReview, "not locked — the member just passed this level's exam")
        XCTAssertTrue(both.isAwaitingReview)
        XCTAssertTrue(both.walked)
        // Either signal alone is enough.
        XCTAssertTrue(try decode(PathwayLevel.self, level(1, "awaiting_review")).isAwaitingReview)
        XCTAssertTrue(try decode(PathwayLevel.self, level(1, "active", awaiting: true)).isAwaitingReview)
        // A completed level is walked; a locked one is not; an unknown word still reads locked.
        XCTAssertTrue(try decode(PathwayLevel.self, level(1, "completed", done: 10, of: 10)).walked)
        XCTAssertFalse(try decode(PathwayLevel.self, level(2, "locked")).walked)
        XCTAssertEqual(try decode(PathwayLevel.self, level(3, "some_future_word")).status, .locked)
    }

    // MARK: §3 — the small words around the step

    func testAlmostThereNeverShowsAtOneHundred() {
        XCTAssertFalse(HomeResumeHero.showsAlmostThere(100))
        XCTAssertTrue(HomeResumeHero.showsAlmostThere(99))
        XCTAssertTrue(HomeResumeHero.showsAlmostThere(60))
        XCTAssertFalse(HomeResumeHero.showsAlmostThere(59))
        XCTAssertNil(Journey.momentum(levelPercent: 100))
        XCTAssertEqual(Journey.momentum(levelPercent: 60), "Almost there — finish strong 🎉")
        XCTAssertEqual(Journey.momentum(levelPercent: 30), "Just 70% to your next badge")
    }

    func testTheProgressLineSaysTheNextStep() throws {
        let walking = try XCTUnwrap(Journey.derive(try summary(current: 2, level(2, "active", done: 3, of: 10))))
        XCTAssertEqual(walking.progressLine.bold, "3 of 10 modules")
        XCTAssertEqual(walking.progressLine.rest, " in Level 2")
        let passed = try XCTUnwrap(Journey.derive(try summary(current: 1, level(1, "awaiting_review", done: 20, of: 20, awaiting: true))))
        XCTAssertEqual(passed.progressLine.bold, "Level 2 is next")
    }

    // MARK: §4 — one state language

    private let noAnswers: [Error] = [APIError.offline, APIError.transport("The network connection was lost."),
                                      URLError(.timedOut), URLError(.notConnectedToInternet)]

    func testOfflineOnlyWhenThePhoneHasNoNetwork() {
        for e in noAnswers {
            let c = NuruStateCopy.failure(e, deviceOnline: false)
            XCTAssertEqual(c.cause, .offline)
            XCTAssertEqual(c.title, "You're offline")
            XCTAssertEqual(c.line, "Connect to the internet, then try again.")
            XCTAssertEqual(c.action, .retry)
        }
        XCTAssertEqual(NuruStateCopy.failure(APIError.offline, showingSaved: true, deviceOnline: false).line,
                       "Showing what you last saw — we'll refresh when you're back.")
    }

    func testNoAnswerWhileThePhoneHasANetworkIsOurs() {
        // A timeout or a dropped call while the device's path is up: the server
        // didn't answer — never blame the member's connection.
        for e in noAnswers {
            XCTAssertEqual(NuruStateCopy.failure(e, deviceOnline: true), .serverSide)
        }
        // Before the monitor's first report, a failed call reads as offline.
        XCTAssertEqual(NuruStateCopy.failure(APIError.offline, deviceOnline: nil).cause, .offline)
        XCTAssertEqual(NuruState.resolve(loading: false, isEmpty: true, failure: APIError.offline,
                                         empty: .empty(title: "x"), deviceOnline: true), .failed(.serverSide))
    }

    func testAnEndedSessionAsksToSignInNeverShowsTheTokenText() {
        let raw = APIError.http(status: 401, code: "TOKEN_EXPIRED", message: "Invalid or expired access token")
        for e: Error in [raw, APIError.unauthorized] {
            let c = NuruStateCopy.failure(e)
            XCTAssertEqual(c, .sessionEnded)
            XCTAssertEqual(c.title, "Your session has ended")
            XCTAssertEqual(c.line, "Sign in again to pick up where you left off.")
            XCTAssertEqual(c.action, .signIn)
            XCTAssertFalse(c.title.contains("token") || (c.line ?? "").contains("token"))
        }
    }

    func testServerErrorsAreOurs() {
        for status in [500, 502, 503] {
            let c = NuruStateCopy.failure(APIError.http(status: status, code: "INTERNAL", message: "relation \"x\" does not exist"))
            XCTAssertEqual(c.title, "Something went wrong on our side")
            XCTAssertEqual(c.line, "It isn't you — please try again in a moment.")
            XCTAssertEqual(c.action, .retry)
        }
        XCTAssertEqual(NuruStateCopy.failure(APIError.decoding("keyNotFound(…)")), .serverSide, "an unreadable answer is ours too")
        XCTAssertEqual(NuruStateCopy.failure(APIError.http(status: 400, code: nil, message: "bad request")), .serverSide,
                       "a 4xx without our envelope is not our words")
    }

    func testNotFoundOffersTheWayBack() {
        let c = NuruStateCopy.failure(APIError.http(status: 404, code: "NOT_FOUND", message: "Module not found"))
        XCTAssertEqual(c.title, "This isn't here any more")
        XCTAssertEqual(c.line, "It may have been moved or removed.")
        XCTAssertEqual(c.action, .goBack)
    }

    func testOurOwnRefusalsKeepTheirWords() {
        let unprocessable = NuruStateCopy.failure(APIError.http(status: 422, code: "UNPROCESSABLE", message: "No exam questions for this level"))
        XCTAssertEqual(unprocessable.cause, .refusal)
        XCTAssertEqual(unprocessable.title, "No exam questions for this level")
        XCTAssertNil(unprocessable.line)
        XCTAssertNil(unprocessable.action, "the screen decides what the member can do next")
        XCTAssertEqual(NuruStateCopy.failure(APIError.http(status: 409, code: "GATE_LOCKED",
                                                           message: "Finish every module in this level before the exam")).title,
                       "Finish every module in this level before the exam")
    }

    func testTheStateRuleContentFirst() {
        let empty = NuruState.empty(title: "Nothing yet")
        XCTAssertNil(NuruState.resolve(loading: true, isEmpty: false, failure: APIError.offline, empty: empty,
                                       deviceOnline: false), "content wins")
        XCTAssertEqual(NuruState.resolve(loading: true, isEmpty: true, failure: nil, empty: empty), .loading)
        XCTAssertEqual(NuruState.resolve(loading: false, isEmpty: true, failure: APIError.unauthorized, empty: empty),
                       .failed(.sessionEnded))
        XCTAssertEqual(NuruState.resolve(loading: false, isEmpty: true, failure: nil, empty: empty), empty)
    }

    // MARK: Small truths — the rails that work, one phone format

    private func methods(_ enabled: Set<String>) -> GivingMethods {
        let rails: [(String, String, String?)] = [("mpesa", "M-Pesa", "KES"), ("airtel", "Airtel Money", "KES"),
                                                 ("paypal", "PayPal", "USD"), ("card", "Card", nil)]
        return GivingMethods(methods: rails.map { rail in
            let (key, label, cur) = rail
            return GivingMethod(key: key, label: label, enabled: enabled.contains(key),
                         unavailableReason: enabled.contains(key) ? nil : "coming_soon", currency: cur,
                         minMinor: 100, maxMinor: 1_000_000, wholeUnits: key != "paypal" && key != "card",
                         recurring: key == "mpesa", needsPhone: key == "mpesa" || key == "airtel")
        }, phoneOnFile: nil, defaultMethod: "mpesa")
    }

    func testTheGivingCardNamesOnlyRailsThatWork() {
        XCTAssertEqual(GivingMethods.homeGiveLine(nil), "Tithe & offering", "not loaded yet: no rails named")
        XCTAssertEqual(GivingMethods.homeGiveLine(methods(["mpesa"])), "Tithe & offering · M-Pesa")
        XCTAssertEqual(GivingMethods.homeGiveLine(methods(["mpesa", "card"])), "Tithe & offering · M-Pesa",
                       "a card the app can't carry is never promised, even where the server could take one")
        XCTAssertEqual(GivingMethods.homeGiveLine(methods(["mpesa", "paypal"])), "Tithe & offering · M-Pesa, PayPal")
        XCTAssertEqual(GivingMethods.homeGiveLine(methods([])), "Tithe & offering")
    }

    func testTheGivingCardReadsTheLiveMethodsAnswer() throws {
        // GET /giving/methods on the local API, verbatim in shape: only M-Pesa enabled.
        let json: [String: Any] = [
            "methods": [
                ["key": "mpesa", "label": "M-Pesa", "enabled": true, "unavailable_reason": NSNull(), "currency": "KES",
                 "min_minor": 100, "max_minor": 25_000_000, "whole_units": true, "recurring": true, "needs_phone": true],
                ["key": "airtel", "label": "Airtel Money", "enabled": false, "unavailable_reason": "coming_soon", "currency": "KES",
                 "min_minor": 100, "max_minor": 15_000_000, "whole_units": true, "recurring": false, "needs_phone": true],
                ["key": "paypal", "label": "PayPal", "enabled": false, "unavailable_reason": "coming_soon", "currency": "USD",
                 "min_minor": 100, "max_minor": 1_000_000, "whole_units": false, "recurring": false, "needs_phone": false],
                ["key": "card", "label": "Card", "enabled": false, "unavailable_reason": "coming_soon", "currency": NSNull(),
                 "min_minor": 100, "max_minor": 100_000_000, "whole_units": false, "recurring": false, "needs_phone": false],
            ],
            "phone_on_file": "+254700000000", "default_method": "mpesa",
        ]
        XCTAssertEqual(GivingMethods.homeGiveLine(try decode(GivingMethods.self, json)), "Tithe & offering · M-Pesa")
    }

    func testProfileReadsThePhoneAsGiveDoes() {
        XCTAssertEqual(KenyanPhone.display("+254700000000"), "0700 000 000")
        XCTAssertEqual(KenyanPhone.display("+447700900123"), "+447700900123", "not a Kenyan mobile: as given")
    }
}
