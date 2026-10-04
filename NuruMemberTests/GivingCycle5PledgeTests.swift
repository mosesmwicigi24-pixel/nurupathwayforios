// Giving Cycle 5 — a pledge's promise, pinned: "Charge me automatically"
// first collects on the first due day strictly after today on the church's
// (Nairobi) calendar; the Partners statement counts exactly as the server's
// partnerStatementMath.ts does — instalments from the later of starts_on and
// the creation day, none after until_on, remaining owed PER PLEDGE, never a
// sum across currencies; and the new fields decode, and are absent on older
// servers. The decoder is configured exactly like APIClient's.
import XCTest
@testable import NuruMember

final class GivingCycle5PledgeTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    private func pledge(_ id: String, _ fields: String) throws -> Pledge {
        try decode(Pledge.self, #"{"pledge_id":"\#(id)",\#(fields)}"#)
    }

    private var paymentSeq = 0
    private func payment(_ pledgeId: String?, _ minor: Int, _ currency: String = "KES") -> String {
        paymentSeq += 1
        let pledge = pledgeId.map { #""\#($0)""# } ?? "null"
        return #"{"transaction_id":"t\#(paymentSeq)","amount_minor":\#(minor),"currency":"\#(currency)","at":"2026-06-01T09:00:00Z","pledge_id":\#(pledge)}"#
    }

    private func payments(_ rows: [String]) throws -> [PledgePayment] {
        try decode([PledgePayment].self, "[\(rows.joined(separator: ","))]")
    }

    private func promises(_ pledges: [Pledge], year: Int) -> [PledgeMath.Promise] {
        pledges.map { PledgeMath.Promise(pledgeId: $0.pledgeId, currency: $0.currency, pledgedMinor: PledgeMath.pledgedInYear($0, year: year)) }
    }

    // MARK: "Charge me automatically" — the first collection

    func testTheFirstCollectionIsTheFirstDueDayStrictlyAfterToday() {
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-10-05", day: 5), "2026-11-05", "made on its own due day: never today — next month")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-10-04", day: 5), "2026-10-05", "the day before: tomorrow")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-10-06", day: 5), "2026-11-05")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-01-31", day: 28), "2026-02-28", "due the 28th, made at the month's end")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-02-28", day: 28), "2026-03-28", "the 28th of February is today")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-12-10", day: 5), "2027-01-05", "December → January of the next year")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-12-05", day: 5), "2027-01-05")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-12-31", day: 28), "2027-01-28")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-10-01", day: 31), "2026-10-28", "a day past the 28th is the 28th")
        XCTAssertEqual(PledgeMath.firstDueAfter("2026-10-01", day: 0), "2026-11-01", "held to the 1st at least")
    }

    func testTheFirstCollectionReadsAsADay() {
        XCTAssertEqual(PledgeMath.dayLabel("2026-10-05", today: "2026-09-28"), "5 October")
        XCTAssertEqual(PledgeMath.dayLabel("2027-01-05", today: "2026-12-10"), "5 January 2027", "another year says which")
    }

    func testTodayIsTheChurchsDay() throws {
        let lateUTC = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-30T21:30:00Z"))
        XCTAssertEqual(PledgeMath.today(now: lateUTC), "2026-10-01", "00:30 in Nairobi is already the 1st")
        XCTAssertEqual(PledgeMath.firstDueAfter(PledgeMath.today(now: lateUTC), day: 1), "2026-11-01",
                       "made on the 1st in Nairobi, due the 1st → not today, next month")
    }

    // MARK: The church's day of a server date

    func testServerDatesReadAsTheChurchsDay() {
        XCTAssertEqual(PledgeMath.churchDay("2026-07-31 22:30:00.123456+00"), "2026-08-01", "Postgres text, UTC — 01:30 on 1 August in Nairobi")
        XCTAssertEqual(PledgeMath.churchDay("2026-07-31 22:30:00+00"), "2026-08-01")
        XCTAssertEqual(PledgeMath.churchDay("2026-08-01 01:30:00+03"), "2026-08-01")
        XCTAssertEqual(PledgeMath.churchDay("2026-07-31 23:59:59+03:00"), "2026-07-31")
        XCTAssertEqual(PledgeMath.churchDay("2026-07-31T22:30:00Z"), "2026-08-01", "ISO-8601")
        XCTAssertEqual(PledgeMath.churchDay("2026-07-31T22:30:00.123Z"), "2026-08-01")
        XCTAssertEqual(PledgeMath.churchDay("2026-07-31"), "2026-07-31", "a bare day is a calendar day, never shifted")
        XCTAssertNil(PledgeMath.churchDay("soon"))
        XCTAssertNil(PledgeMath.churchDay(""))
        XCTAssertNil(PledgeMath.churchDay(nil))
    }

    // MARK: Instalments — from the pledge's start, none after until_on

    func testInstalmentsRunFromTheStartToUntilOn() throws {
        // (c) monthly KSh 100 due the 5th, made 1 Aug 2026, until 31 Oct 2026.
        let p = try pledge("c", #""shape":"monthly","amount_minor":10000,"currency":"KES","due_day":5,"created_at":"2026-08-01 09:00:00+03","until_on":"2026-10-31","status":"active""#)
        XCTAssertEqual(PledgeMath.instalments(p, in: 2026), ["2026-08-05", "2026-09-05", "2026-10-05"], "5 Aug, 5 Sep, 5 Oct only")
        XCTAssertEqual(PledgeMath.pledgedInYear(p, year: 2026), 30_000, "KSh 300 pledged in 2026")
        XCTAssertEqual(PledgeMath.pledgedInYear(p, year: 2027), 0, "nothing after until_on")
        XCTAssertEqual(PledgeMath.instalments(p, in: 2026, through: "2026-09-05"), ["2026-08-05", "2026-09-05"], "fallen due so far")
    }

    func testAPledgeCollectedAutomaticallyStartsAtItsFirstCollection() throws {
        // Made on 28 Sep, due the 5th, collected from 5 Oct (starts_on).
        let p = try pledge("auto", #""shape":"monthly","amount_minor":100000,"due_day":5,"created_at":"2026-09-28T07:00:00Z","starts_on":"2026-10-05","status":"active""#)
        XCTAssertEqual(PledgeMath.start(p), "2026-10-05")
        XCTAssertEqual(PledgeMath.instalments(p, in: 2026), ["2026-10-05", "2026-11-05", "2026-12-05"])
        XCTAssertEqual(PledgeMath.pledgedInYear(p, year: 2026), 300_000)
        XCTAssertEqual(PledgeMath.nextInstalment(p, onOrAfter: "2026-09-28"), "2026-10-05")

        // A starts_on before the creation day never reaches back past it.
        let early = try pledge("early", #""shape":"monthly","amount_minor":100000,"due_day":5,"created_at":"2026-09-28T07:00:00Z","starts_on":"2026-09-01","status":"active""#)
        XCTAssertEqual(PledgeMath.start(early), "2026-09-28")
        XCTAssertEqual(PledgeMath.instalments(early, in: 2026), ["2026-10-05", "2026-11-05", "2026-12-05"])

        // Made on its own due day without automatic collection: that day counts.
        let sameDay = try pledge("same", #""shape":"monthly","amount_minor":100000,"due_day":28,"created_at":"2026-09-28T07:00:00Z","status":"active""#)
        XCTAssertEqual(PledgeMath.nextInstalment(sameDay, onOrAfter: "2026-09-28"), "2026-09-28")

        let ending = try pledge("end", #""shape":"monthly","amount_minor":100000,"due_day":5,"created_at":"2026-01-01T07:00:00Z","until_on":"2026-10-31","status":"active""#)
        XCTAssertEqual(PledgeMath.nextInstalment(ending, onOrAfter: "2026-10-01"), "2026-10-05")
        XCTAssertNil(PledgeMath.nextInstalment(ending, onOrAfter: "2026-10-06"), "none after until_on")
    }

    // MARK: Pledged · Paid · Remaining — the pinned cases

    func testRemainingIsOwedPerPledge() throws {
        // (a) Kenya trip: KSh 18,000 pledged, 9,000 paid; a KSh 300 total pledge paid KSh 500.
        let trip = try pledge("trip", #""shape":"total","target_minor":1800000,"currency":"KES","due_on":"2026-12-01","created_at":"2026-02-01T07:00:00Z","status":"active""#)
        let small = try pledge("small", #""shape":"total","target_minor":30000,"currency":"KES","due_on":"2026-11-30","created_at":"2026-02-01T07:00:00Z","status":"active""#)
        let pays = try payments([payment("trip", 900_000), payment("small", 50_000)])
        let f = PledgeMath.figures(promises([trip, small], year: 2026), payments: pays)
        XCTAssertEqual(f, [PartnerFigures(currency: "KES", pledgedMinor: 1_830_000, paidMinor: 950_000, remainingMinor: 900_000)],
                       "KSh 9,000 still owed on the trip — the KSh 200 paid beyond the small pledge never hides it (was 8,800)")
    }

    func testTheStatementFootsAcrossMonthlyTotalAndCancelledPledges() throws {
        // (b) monthly KSh 1,000 from 1 Jan 2026 due the 5th (12,000 pledged, 4,000 paid);
        //     a total KSh 3,000 due 30 Nov paid 5,000; a cancelled total KSh 5,000 paid 1,000.
        let monthly = try pledge("m", #""shape":"monthly","amount_minor":100000,"currency":"KES","due_day":5,"created_at":"2026-01-01 08:00:00+03","status":"active""#)
        let total = try pledge("t", #""shape":"total","target_minor":300000,"currency":"KES","due_on":"2026-11-30","created_at":"2026-01-01 08:00:00+03","status":"active""#)
        let cancelled = try pledge("x", #""shape":"total","target_minor":500000,"currency":"KES","due_on":"2026-12-31","created_at":"2026-01-01 08:00:00+03","status":"cancelled""#)
        XCTAssertEqual(PledgeMath.pledgedInYear(monthly, year: 2026), 1_200_000)
        XCTAssertEqual(PledgeMath.pledgedInYear(cancelled, year: 2026), 0, "a cancelled pledge pledges nothing")
        let rows = [payment("m", 100_000), payment("m", 100_000), payment("m", 100_000), payment("m", 100_000),
                    payment("t", 500_000), payment("x", 100_000), payment(nil, 70_000)]
        let pays = try payments(rows)
        let expected = [PartnerFigures(currency: "KES", pledgedMinor: 1_500_000, paidMinor: 1_000_000, remainingMinor: 800_000)]
        XCTAssertEqual(PledgeMath.figures(promises([monthly, total, cancelled], year: 2026), payments: pays), expected,
                       "a gift outside a pledge is never counted")

        // The same, the way an older server's statement is read: no pledges[]
        // rows, no server numbers — the partnership's pledges (which leave the
        // cancelled one out) and the year's payments.
        let s = try decode(GivingStatements.self, #"{"year":2026,"payments":[\#(rows.joined(separator: ","))]}"#)
        XCTAssertEqual(PledgeMath.figures(s, pledges: [monthly, total]), expected)
    }

    func testTheServersOwnNumbersLeadWhenTheYearIsInOneCurrency() throws {
        let s = try decode(GivingStatements.self, #"""
        {"year":2026,"pledged_minor":1500000,"paid_minor":1000000,"remaining_minor":800000,
         "pledges":[{"pledge_id":"m","shape":"monthly","currency":"KES","pledged_minor":1200000,"paid_minor":400000,"remaining_year_minor":800000}],
         "payments":[\#(payment("m", 400_000))]}
        """#)
        XCTAssertEqual(PledgeMath.figures(s, pledges: []),
                       [PartnerFigures(currency: "KES", pledgedMinor: 1_500_000, paidMinor: 1_000_000, remainingMinor: 800_000)],
                       "as sent — the server is the authority")
    }

    // MARK: Never a sum across currencies

    func testEachCurrencyIsCountedOnItsOwn() throws {
        let kes = try pledge("k", #""shape":"monthly","amount_minor":100000,"currency":"KES","due_day":5,"created_at":"2026-01-01T05:00:00Z","status":"active""#)
        let usd = try pledge("u", #""shape":"total","target_minor":10000,"currency":"USD","due_on":"2026-12-01","created_at":"2026-01-01T05:00:00Z","status":"active""#)
        let pays = try payments([payment("k", 300_000), payment("u", 2_000, "USD")])
        let f = PledgeMath.figures(promises([usd, kes], year: 2026), payments: pays)
        XCTAssertEqual(f, [
            PartnerFigures(currency: "KES", pledgedMinor: 1_200_000, paidMinor: 300_000, remainingMinor: 900_000),
            PartnerFigures(currency: "USD", pledgedMinor: 10_000, paidMinor: 2_000, remainingMinor: 8_000),
        ], "shillings first, dollars beside them — never added together")

        // A dollar paid toward a shilling pledge (an old, wrong-currency gift)
        // is counted as dollars paid, never as shillings toward the pledge.
        let stray = try payments([payment("k", 5_000, "USD")])
        let g = PledgeMath.figures(promises([kes], year: 2026), payments: stray)
        XCTAssertEqual(g.first { $0.currency == "KES" }?.remainingMinor, 1_200_000)
        XCTAssertEqual(g.first { $0.currency == "USD" }?.paidMinor, 5_000)
    }

    func testAMixedYearIsCountedPerCurrencyFromTheServersRows() throws {
        // The server's own three sums add currencies together, so a mixed
        // year is counted here from its per-pledge rows.
        let s = try decode(GivingStatements.self, #"""
        {"year":2026,"pledged_minor":1210000,"paid_minor":302000,"remaining_minor":908000,
         "pledges":[{"pledge_id":"k","shape":"monthly","currency":"KES","pledged_minor":1200000,"paid_minor":300000},
                    {"pledge_id":"u","shape":"total","currency":"USD","pledged_minor":10000,"paid_minor":2000}],
         "payments":[\#(payment("k", 300_000)),\#(payment("u", 2_000, "USD"))]}
        """#)
        XCTAssertEqual(PledgeMath.figures(s, pledges: []), [
            PartnerFigures(currency: "KES", pledgedMinor: 1_200_000, paidMinor: 300_000, remainingMinor: 900_000),
            PartnerFigures(currency: "USD", pledgedMinor: 10_000, paidMinor: 2_000, remainingMinor: 8_000),
        ])
    }

    func testNothingAtAllIsOneRowOfShillingZeros() throws {
        let s = try decode(GivingStatements.self, #"{"year":2026}"#)
        XCTAssertEqual(PledgeMath.figures(s, pledges: []), [PartnerFigures(currency: "KES", pledgedMinor: 0, paidMinor: 0, remainingMinor: 0)])
    }

    func testAmountsInSeveralCurrenciesReadAsOneLine() {
        XCTAssertEqual(PledgeMath.line([CurrencyTotal(currency: "USD", totalMinor: 2_000), CurrencyTotal(currency: "KES", totalMinor: 300_000)]),
                       "KSh \(grouped(3000)) + US$ 20.00")
        XCTAssertEqual(PledgeMath.line([CurrencyTotal(currency: "KES", totalMinor: 0)]), "KSh 0")
        XCTAssertEqual(PledgeMath.line([CurrencyTotal(currency: "USD", totalMinor: 0)]), "US$ 0.00", "zero in the currency there is")
        XCTAssertEqual(PledgeMath.line([]), "KSh 0")
    }

    // MARK: Decoding — new fields, and older servers without them

    func testAPledgeCarriesItsStartAndEnd() throws {
        let p = try pledge("p", #""shape":"monthly","amount_minor":100000,"due_day":5,"starts_on":"2026-10-05","until_on":"2027-06-30""#)
        XCTAssertEqual(p.startsOn, "2026-10-05")
        XCTAssertEqual(p.untilOn, "2027-06-30")
        let older = try pledge("p", #""shape":"monthly","amount_minor":100000,"due_day":5"#)
        XCTAssertNil(older.startsOn, "an older server sends neither")
        XCTAssertNil(older.untilOn)
        let nulls = try pledge("p", #""shape":"monthly","starts_on":null,"until_on":"""#)
        XCTAssertNil(nulls.startsOn); XCTAssertNil(nulls.untilOn)
    }

    func testTheCreateAnswerSaysReusedAndWhyCollectionWasNotSetUp() throws {
        let reused = try decode(PledgeResult.self, #"{"pledge_id":"p1","shape":"monthly","amount_minor":100000,"reused":true}"#)
        XCTAssertEqual(reused.pledge.pledgeId, "p1")
        XCTAssertTrue(reused.reused, "the same pledge a moment ago — never a second one")
        XCTAssertNil(reused.autoScheduleError)

        let made = try decode(PledgeResult.self, #"{"pledge_id":"p2","shape":"monthly","auto_schedule_error":"Add an M-Pesa number to your profile first."}"#)
        XCTAssertFalse(made.reused)
        XCTAssertEqual(made.autoScheduleError, "Add an M-Pesa number to your profile first.")

        let nested = try decode(PledgeResult.self, #"{"pledge":{"pledge_id":"p3","shape":"total"},"reused":true}"#)
        XCTAssertEqual(nested.pledge.pledgeId, "p3")
        XCTAssertTrue(nested.reused)

        let older = try decode(PledgeResult.self, #"{"pledge_id":"p4","shape":"total","auto_schedule_error":"  "}"#)
        XCTAssertFalse(older.reused, "absent reads as a new pledge")
        XCTAssertNil(older.autoScheduleError, "blank reads as none")
    }
}
