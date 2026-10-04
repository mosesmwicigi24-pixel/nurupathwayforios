// Experience Cycle 3 — interaction design, pinned (pathway docs/EXPERIENCE.md
// §7): every tap lands where it points, every screen has a way out, and Back
// returns you where you were. The journey's exam rule itself (`exam_available`)
// sits with the other journey tests in ExperienceCycle1Tests; here are the
// rest — the exam row and the exam screen's refusal. Payloads are decoded
// exactly like APIClient's: snake_case in.
import XCTest
@testable import NuruMember

final class ExperienceCycle3Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func module(_ id: String, seq: Int, _ status: String, completed: Bool = false,
                        kind: String = "none", examAvailable: Bool? = nil) throws -> LevelModule {
        var row: [String: Any] = [
            "module_id": id, "level_number": 1, "module_sequence_number": seq, "title": "Module \(id)",
            "summary": NSNull(), "estimated_minutes": 10, "evaluation_kind": kind, "quiz_pass_mark": 70,
            "completed": completed, "status": status, "progress": completed ? 100 : 0, "locked": status == "locked"]
        if let examAvailable { row["exam_available"] = examAvailable }
        return try decode(LevelModule.self, row)
    }

    // MARK: #1 — an exam that can't be taken is never a way in

    func testAnOpenExamRowWithNoQuestionsOpensSoon() throws {
        XCTAssertTrue(try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: false).examOpensSoon)
        XCTAssertFalse(try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: true).examOpensSoon)
        XCTAssertFalse(try module("exam", seq: 11, "next", kind: "exit_exam").examOpensSoon, "absent = available")
        XCTAssertFalse(try module("exam", seq: 11, "locked", kind: "exit_exam", examAvailable: false).examOpensSoon,
                       "still behind the lessons: it reads locked, as before")
        XCTAssertFalse(try module("exam", seq: 11, "completed", completed: true, kind: "exit_exam", examAvailable: false).examOpensSoon,
                       "a passed exam is passed")
        XCTAssertFalse(try module("m1", seq: 1, "next", examAvailable: false).examOpensSoon, "a lesson is never the exam")
    }

    @MainActor
    func testContinueNeverLandsOnAnExamThatOpensSoon() throws {
        let vm = PathwayViewModel()
        vm.modulesByLevel[1] = [try module("m10", seq: 10, "completed", completed: true),
                                try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: false)]
        XCTAssertNil(vm.resumeModule(in: 1), "every lesson done and the exam not open: nothing to continue")
        vm.modulesByLevel[1] = [try module("m10", seq: 10, "completed", completed: true),
                                try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: true)]
        XCTAssertEqual(vm.resumeModule(in: 1)?.moduleId, "exam", "an open exam is still the next step")
        vm.modulesByLevel[1] = [try module("m9", seq: 9, "next"),
                                try module("exam", seq: 11, "locked", kind: "exit_exam", examAvailable: false)]
        XCTAssertEqual(vm.resumeModule(in: 1)?.moduleId, "m9")
    }

    /// The exam screen's refusal is the server's words with Go back — any
    /// refusal; anything else speaks §4 with Try again.
    func testTheExamsRefusalKeepsTheServersWords() {
        let notReady = APIError.http(status: 422, code: "UNPROCESSABLE",
                                     message: "Your Level 1 exam isn't ready yet — we'll let you know when it opens.")
        XCTAssertEqual(LevelExamViewModel.refusal(notReady, deviceOnline: true),
                       "Your Level 1 exam isn't ready yet — we'll let you know when it opens.")
        let gate = APIError.http(status: 409, code: "GATE_LOCKED", message: "Finish every module in this level before the exam")
        XCTAssertEqual(LevelExamViewModel.refusal(gate, deviceOnline: true), "Finish every module in this level before the exam")
        XCTAssertNil(LevelExamViewModel.refusal(APIError.http(status: 500, code: "INTERNAL", message: "boom"), deviceOnline: true),
                     "ours: Try again, never the raw words")
        XCTAssertNil(LevelExamViewModel.refusal(APIError.offline, deviceOnline: false))
        XCTAssertNil(LevelExamViewModel.refusal(APIError.http(status: 404, code: "NOT_FOUND", message: "Level not found"), deviceOnline: true),
                     "not found is §4's own state")
    }

    // MARK: #2 — the pledge page: collected automatically, paying is a choice

    private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    /// Ada's Kenya trip — `schedule_id` set on an older row.
    private func pledge(_ id: String = "p-kenya", scheduleId: String? = nil) throws -> Pledge {
        let sid = scheduleId.map { #""\#($0)""# } ?? "null"
        return try decode(Pledge.self, json: #"{"pledge_id":"\#(id)","shape":"monthly","amount_minor":500000,"currency":"KES","due_day":5,"title":"Kenya trip","status":"active","schedule_id":\#(sid)}"#)
    }

    /// A recurring gift — bound to `pledge` when given (its collector).
    private func gift(_ id: String, pledge: String? = nil, status: String = "active") throws -> GivingSchedule {
        let bound = pledge.map { #""pledge":{"pledge_id":"\#($0)","title":"Kenya trip"}"# } ?? #""pledge":null"#
        return try decode(GivingSchedule.self, json: #"""
        {"schedule_id":"\#(id)","fund":"mission","amount_minor":500000,"currency":"KES","method":"mpesa",
         "frequency":"monthly","status":"\#(status)","next_run_at":"2026-10-05T06:01:00.000Z",\#(bound),"next_amount_minor":500000}
        """#)
    }

    func testThePledgePagePaysEarlyWhileItsCollectorRuns() throws {
        let kenya = try pledge()
        let collector = try gift("s1", pledge: "p-kenya")
        XCTAssertTrue(PledgePace.paysEarly(kenya, schedules: [collector]), "collected automatically: Pay early + Pause, both quiet")
        guard case .collected(let id, let line) = PledgePace.offer(for: kenya, methods: nil, schedules: [collector]) else {
            return XCTFail("the page's card says the same thing")
        }
        XCTAssertEqual(id, "s1")
        XCTAssertTrue(line.hasPrefix("Collected automatically — next KSh 5,000"), line)

        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: [try gift("s1", pledge: "p-kenya", status: "paused")]),
                       "a paused collector collects nothing: Pay now")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: []), "no collector: Pay now stays the gold primary")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: nil), "the gifts not known yet: never guessed")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: [try gift("s2", pledge: "p-other")]), "another pledge's collector")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: [try gift("s4", status: "cancelled")]))
        XCTAssertTrue(PledgePace.paysEarly(try pledge(scheduleId: "s3"), schedules: [try gift("s3")]),
                      "an older row, bound by the pledge's own schedule_id")
    }
}
