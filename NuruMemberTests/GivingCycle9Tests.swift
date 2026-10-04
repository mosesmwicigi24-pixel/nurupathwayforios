// Giving Cycle 9 — intelligence, pinned: a total pledge's pace in words
// (one collection or several, dollars in cents); when the pledge's page
// offers to collect it at that pace (shillings only, M-Pesa taking recurring
// gifts, nothing collecting it already) and exactly what that sends; the
// gift that already collects a pledge, in words; and the Partners statement
// per currency — the server's summary_by_currency as sent, or counted here
// by the same rule on an older server (the pinned two-currency case).
import XCTest
@testable import NuruMember

final class GivingCycle9Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    private let paysTo = #""pays_to":{"code":"discipleship","name":"Discipleship"}"#

    /// A KES total pledge of KSh 20,000 by 31 Dec, paced at KSh 5,000 × 4 —
    /// `over` replaces fields (nil = JSON null).
    private func paced(_ over: [String: Any?] = [:]) throws -> Pledge {
        var o: [String: Any] = [
            "pledge_id": "p-roof", "shape": "total", "target_minor": 2_000_000, "currency": "KES",
            "due_on": "2026-12-31", "status": "active", "title": "Roof",
            "pays_to": ["code": "discipleship", "name": "Discipleship"],
            "pace": ["per_month_minor": 500_000, "collections_left": 4, "by": "2026-12-31"],
        ]
        for (k, v) in over { o[k] = v ?? NSNull() }
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(Pledge.self, from: JSONSerialization.data(withJSONObject: o))
    }

    private func methods(mpesaEnabled: Bool = true, recurring: Bool = true) -> GivingMethods {
        GivingMethods(methods: [GivingMethod(key: "mpesa", label: "M-Pesa", enabled: mpesaEnabled, unavailableReason: nil,
                                             currency: "KES", minMinor: 100, maxMinor: 25_000_000,
                                             wholeUnits: true, recurring: recurring, needsPhone: true)],
                      phoneOnFile: nil, defaultMethod: "mpesa")
    }

    private func schedule(_ id: String, pledge: String?, status: String = "active", next: String = "500000",
                          nextRunAt: String = "2026-10-28T06:00:00Z") throws -> GivingSchedule {
        let bound = pledge.map { #""pledge":{"pledge_id":"\#($0)","title":"Roof"}"# } ?? #""pledge":null"#
        return try decode(GivingSchedule.self, #"""
        {"schedule_id":"\#(id)","fund":"discipleship","amount_minor":500000,"currency":"KES","method":"mpesa",
         "frequency":"monthly","status":"\#(status)","next_run_at":"\#(nextRunAt)",\#(bound),"next_amount_minor":\#(next)}
        """#)
    }

    // MARK: The pace, in words

    func testThePaceReadsAsTheWayToReachThePledge() throws {
        let p = try paced()
        XCTAssertEqual(p.pace, Pledge.Pace(perMonthMinor: 500_000, collectionsLeft: 4, by: "2026-12-31"))
        XCTAssertEqual(PledgePace.line(p, today: "2026-09-28"),
                       "To reach KSh \(grouped(20000)) by 31 Dec: KSh \(grouped(5000)) a month — 4 collections")

        let last = try decode(Pledge.self, #"{"pledge_id":"p1","shape":"total","target_minor":2000000,"currency":"KES","status":"active","pace":{"per_month_minor":2000000,"collections_left":1,"by":"2026-09-28"}}"#)
        XCTAssertEqual(PledgePace.line(last, today: "2026-09-28"),
                       "To reach KSh \(grouped(20000)) by 28 Sep: KSh \(grouped(20000)) a month — 1 collection", "one collection, singular")

        let dollars = try decode(Pledge.self, #"{"pledge_id":"p2","shape":"total","target_minor":10001,"currency":"USD","status":"active","pace":{"per_month_minor":2501,"collections_left":4,"by":"2026-12-31"}}"#)
        XCTAssertEqual(PledgePace.line(dollars, today: "2026-09-28"),
                       "To reach US$ 100.01 by 31 Dec: US$ 25.01 a month — 4 collections", "cents stay cents")

        let nextYear = try decode(Pledge.self, #"{"pledge_id":"p3","shape":"total","target_minor":900000,"currency":"KES","status":"active","pace":{"per_month_minor":300000,"collections_left":3,"by":"2027-01-31"}}"#)
        XCTAssertEqual(PledgePace.line(nextYear, today: "2026-12-10"),
                       "To reach KSh \(grouped(9000)) by 31 Jan 2027: KSh \(grouped(3000)) a month — 3 collections", "another year says which")
    }

    func testNoPaceIsNoLine() throws {
        for json in [
            #"{"pledge_id":"m","shape":"monthly","amount_minor":100000,"currency":"KES","status":"active","pace":null}"#,
            #"{"pledge_id":"t","shape":"total","target_minor":100000,"currency":"KES","status":"active"}"#,
            #"{"pledge_id":"x","shape":"total","target_minor":100000,"currency":"KES","status":"active","pace":{"per_month_minor":0,"collections_left":4,"by":"2026-12-31"}}"#,
            #"{"pledge_id":"y","shape":"total","target_minor":100000,"currency":"KES","status":"active","pace":{"per_month_minor":500,"collections_left":0,"by":"2026-12-31"}}"#,
            #"{"pledge_id":"z","shape":"total","target_minor":100000,"currency":"KES","status":"active","pace":{"per_month_minor":500,"collections_left":2}}"#,
        ] {
            let p = try decode(Pledge.self, json)
            XCTAssertNil(p.pace, json)
            XCTAssertNil(PledgePace.line(p), json)
        }
    }

    // MARK: When to offer "Collect it automatically at this pace"

    func testTheOfferIsForAShillingPledgeWithMPesaAndNothingCollectingIt() throws {
        let p = try paced()
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(), schedules: []), .collect(amountMinor: 500_000))
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(), schedules: [try schedule("s-other", pledge: "p-else")]),
                       .collect(amountMinor: 500_000), "a gift collecting another pledge doesn't count")
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(), schedules: [try schedule("s-old", pledge: "p-roof", status: "cancelled")]),
                       .collect(amountMinor: 500_000), "a cancelled gift collects nothing")

        // Not until both are known.
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(), schedules: nil), .none)
        XCTAssertEqual(PledgePace.offer(for: p, methods: nil, schedules: []), .none)
        // Shillings only.
        let usd = try paced(["currency": "USD"])
        XCTAssertEqual(usd.currency, "USD")
        XCTAssertEqual(PledgePace.offer(for: usd, methods: methods(), schedules: []), .none)
        // M-Pesa must take recurring gifts here.
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(mpesaEnabled: false), schedules: []), .none)
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(recurring: false), schedules: []), .none)
        XCTAssertEqual(PledgePace.offer(for: p, methods: GivingMethods(methods: [], phoneOnFile: nil, defaultMethod: nil), schedules: []), .none)
        // A pledge to pace, active, and with a fund to pay.
        let noPace = try decode(Pledge.self, #"{"pledge_id":"p-roof","shape":"total","target_minor":2000000,"currency":"KES","status":"active",\#(paysTo)}"#)
        XCTAssertEqual(PledgePace.offer(for: noPace, methods: methods(), schedules: []), .none)
        XCTAssertEqual(PledgePace.offer(for: try paced(["status": "paused"]), methods: methods(), schedules: []), .none)
        XCTAssertEqual(PledgePace.offer(for: try paced(["pays_to": nil]), methods: methods(), schedules: []), .none)
    }

    func testAGiftAlreadyCollectingThePledgeIsShownInstead() throws {
        let p = try paced()
        let sept28 = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-28T09:00:00Z"))
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(), schedules: [try schedule("s-1", pledge: "p-roof")], now: sept28),
                       .collected(scheduleId: "s-1", line: "Collected automatically — next KSh \(grouped(5000)) on 28 Oct"))
        // Shown whatever the rails say — it is already there.
        if case .collected = PledgePace.offer(for: p, methods: nil, schedules: [try schedule("s-1", pledge: "p-roof")]) {} else {
            XCTFail("the gift collecting it is shown even before the rails are known")
        }
        // A running one first; a paused one still collects it.
        let both = [try schedule("s-paused", pledge: "p-roof", status: "paused", next: "null"), try schedule("s-run", pledge: "p-roof")]
        XCTAssertEqual(PledgePace.collector(of: p, in: both)?.scheduleId, "s-run")
        XCTAssertEqual(PledgePace.offer(for: p, methods: methods(), schedules: [both[0]]),
                       .collected(scheduleId: "s-paused", line: "Collected automatically — paused"))
    }

    func testTheCollectedRowSaysWhatTheNextPromptAsks() throws {
        let sept28 = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-28T09:00:00Z"))
        XCTAssertEqual(PledgePace.collectedLine(try schedule("s", pledge: "p", next: "300000"), now: sept28),
                       "Collected automatically — next KSh \(grouped(3000)) on 28 Oct", "only what's left")
        XCTAssertEqual(PledgePace.collectedLine(try schedule("s", pledge: "p", next: "0"), now: sept28),
                       "Collected automatically — nothing to pay next time")
        XCTAssertEqual(PledgePace.collectedLine(try schedule("s", pledge: "p", next: "null"), now: sept28),
                       "Collected automatically", "no prompt coming: no next")
        XCTAssertEqual(PledgePace.collectedLine(try schedule("s", pledge: "p", next: "500000", nextRunAt: "2026-10-27T22:30:00Z"), now: sept28),
                       "Collected automatically — next KSh \(grouped(5000)) on 28 Oct", "the church's day: 01:30 on the 28th in Nairobi")
        // Another year's prompt names its year (the Android parity pass).
        XCTAssertEqual(PledgePace.collectedLine(try schedule("s", pledge: "p", next: "500000", nextRunAt: "2027-01-05T06:00:00Z"), now: sept28),
                       "Collected automatically — next KSh \(grouped(5000)) on 5 Jan 2027")
    }

    // MARK: What "Collect it automatically at this pace" sends

    func testTheRequestIsAMonthlyMPesaGiftBoundToThePledgeFromNow() throws {
        let p = try paced()
        let body = try XCTUnwrap(PledgePace.scheduleBody(for: p, key: "c9-key-00000001"))
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: e.encode(body)) as? [String: Any])
        XCTAssertEqual(json["pledge_id"] as? String, "p-roof")
        XCTAssertEqual(json["fund"] as? String, "discipleship", "the pledge's pays_to")
        XCTAssertEqual(json["amount_minor"] as? Int, 500_000, "the pace")
        XCTAssertEqual(json["currency"] as? String, "KES")
        XCTAssertEqual(json["frequency"] as? String, "monthly")
        XCTAssertEqual(json["method"] as? String, "mpesa")
        XCTAssertEqual(json["first_charge"] as? String, "now", "the pace counts one collection today")
        XCTAssertEqual(json["idempotency_key"] as? String, "c9-key-00000001")
        XCTAssertNil(json["phone_number"], "the member's own number")
        XCTAssertEqual(Set(json.keys), ["pledge_id", "fund", "amount_minor", "currency", "frequency", "method", "first_charge", "idempotency_key"])

        let fresh = try XCTUnwrap(PledgePace.scheduleBody(for: p))
        XCTAssertFalse(GiveKey.isReserved(fresh.idempotencyKey), "a fresh key, never the server's")
        XCTAssertNotNil(UUID(uuidString: fresh.idempotencyKey))
        XCTAssertNil(PledgePace.scheduleBody(for: try paced(["pays_to": nil])), "nowhere to pay: nothing to send")
    }

    // MARK: The Partners statement, per currency

    /// KES total 30,000 paid 25,000; USD total 500.00 paid 200.00; and an
    /// older USD 99.99 recorded toward the KES pledge.
    private let payments = #"""
    [{"transaction_id":"t1","amount_minor":2500000,"currency":"KES","at":"2026-09-10T09:00:00Z","pledge_id":"p-kes"},
     {"transaction_id":"t2","amount_minor":20000,"currency":"USD","at":"2026-09-10T09:00:00Z","pledge_id":"p-usd"},
     {"transaction_id":"t3","amount_minor":9999,"currency":"USD","at":"2026-09-10T09:00:00Z","pledge_id":"p-kes"}]
    """#

    private let pinned = [
        PartnerFigures(currency: "KES", pledgedMinor: 3_000_000, paidMinor: 2_500_000, remainingMinor: 500_000),
        PartnerFigures(currency: "USD", pledgedMinor: 50_000, paidMinor: 29_999, remainingMinor: 30_000),
    ]

    func testTheServersPerCurrencySummaryIsShownAsSent() throws {
        let s = try decode(GivingStatements.self, #"""
        {"year":2026,"pledged_minor":3000000,"paid_minor":2500000,"remaining_minor":500000,"summary_currency":"KES",
         "summary_by_currency":[{"currency":"KES","pledged_minor":3000000,"paid_minor":2500000,"remaining_minor":500000},
                                {"currency":"USD","pledged_minor":50000,"paid_minor":29999,"remaining_minor":30000}],
         "pledges":[{"pledge_id":"p-kes","shape":"total","currency":"KES","pledged_minor":3000000,"paid_minor":2500000,"remaining_year_minor":500000},
                    {"pledge_id":"p-usd","shape":"total","currency":"USD","pledged_minor":50000,"paid_minor":20000,"remaining_year_minor":30000}],
         "payments":\#(payments)}
        """#)
        XCTAssertEqual(s.summaryCurrency, "KES")
        XCTAssertEqual(s.summaryByCurrency, pinned)
        XCTAssertEqual(PledgeMath.figures(s, pledges: []), pinned, "KES 30,000 / 25,000 / 5,000 and USD 500.00 / 299.99 / 300.00")
        XCTAssertEqual(s.pledges.first { $0.pledgeId == "p-kes" }?.paidMinor, 2_500_000, "the dollar gift is not the roof's shillings")
    }

    func testAnOlderServerIsCountedHereByTheSameRule() throws {
        let s = try decode(GivingStatements.self, #"{"year":2026,"payments":\#(payments)}"#)
        XCTAssertNil(s.summaryCurrency)
        XCTAssertNil(s.summaryByCurrency, "absent on an older server")
        let kes = try decode(Pledge.self, #"{"pledge_id":"p-kes","shape":"total","target_minor":3000000,"currency":"KES","due_on":"2026-11-30","status":"active","created_at":"2026-01-10T07:00:00Z"}"#)
        let usd = try decode(Pledge.self, #"{"pledge_id":"p-usd","shape":"total","target_minor":50000,"currency":"USD","due_on":"2026-11-30","status":"active","created_at":"2026-01-10T07:00:00Z"}"#)
        XCTAssertEqual(PledgeMath.figures(s, pledges: [kes, usd]), pinned, "the same figures, counted here")
        let rows = PledgeMath.localRows(s, pledges: [kes, usd], today: "2026-09-28")
        XCTAssertEqual(rows.first { $0.pledgeId == "p-kes" }?.paidMinor, 2_500_000, "a payment counts only in its pledge's currency")
        XCTAssertEqual(rows.first { $0.pledgeId == "p-usd" }?.paidMinor, 20_000)
    }

    func testAnEmptyCurrencyIsLeftOutAndNothingAtAllIsOneRow() throws {
        let some = try decode(GivingStatements.self, #"""
        {"year":2026,"summary_currency":"KES",
         "summary_by_currency":[{"currency":"KES","pledged_minor":0,"paid_minor":0,"remaining_minor":0},
                                {"currency":"USD","pledged_minor":"50000","paid_minor":"20000","remaining_minor":"30000"},
                                {"pledged_minor":1}]}
        """#)
        XCTAssertEqual(some.summaryByCurrency?.count, 2, "a row without a currency is dropped")
        XCTAssertEqual(PledgeMath.figures(some, pledges: []),
                       [PartnerFigures(currency: "USD", pledgedMinor: 50_000, paidMinor: 20_000, remainingMinor: 30_000)],
                       "a currency with nothing in it is left out; figures sent as text are read")
        let none = try decode(GivingStatements.self, #"{"year":2026,"summary_currency":"USD","summary_by_currency":[]}"#)
        XCTAssertEqual(PledgeMath.figures(none, pledges: []), [PartnerFigures(currency: "USD", pledgedMinor: 0, paidMinor: 0, remainingMinor: 0)])
    }
}
