// Experience Cycle 2 — information hierarchy, pinned (pathway docs/EXPERIENCE.md
// §6): a pledge its collector takes care of says "Collected on …" on Partners'
// DUE list instead of Pay — on the church's Nairobi calendar, and only when
// the prompt asks for money and comes on or before the instalment's date
// (§6.4). The same rule as Android's pledgeCollectedOn. Payloads are decoded
// exactly like APIClient's: snake_case in.
import XCTest
@testable import NuruMember

final class ExperienceCycle2Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
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
}
