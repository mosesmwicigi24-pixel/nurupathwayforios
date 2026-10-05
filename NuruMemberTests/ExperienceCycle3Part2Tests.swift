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
}
