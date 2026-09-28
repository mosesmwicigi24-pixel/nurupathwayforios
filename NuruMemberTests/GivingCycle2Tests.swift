// Giving Cycle 2 — honest money, pinned: PayPal is entered and sent in US
// cents (never a shilling number), the fee cover rides beside the total it is
// part of, totals are per currency (never one sum), the church's year is
// Nairobi's, and the footer promises only rails that can take money. The
// decoder is configured exactly like APIClient's: snake_case in, camelCase out.
import XCTest
@testable import NuruMember

final class GivingCycle2Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    /// The app's own grouping (the device locale), so these hold on any simulator.
    private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    // MARK: US-dollar entry ↔ minor units

    private func type(_ keys: [String], from start: String = "") -> String {
        keys.reduce(start) { UsdEntry.press($1, on: $0) }
    }

    func testDollarKeypadBuildsCents() {
        XCTAssertEqual(type(["1", "2", ".", "5"]), "12.5")
        XCTAssertEqual(UsdEntry.cents("12.5"), 1250)
        XCTAssertEqual(type(["0", ".", "0", "5"]), "0.05")
        XCTAssertEqual(UsdEntry.cents("0.05"), 5)
        XCTAssertEqual(type(["."]), "0.", "a point on an empty field reads 0.")
        XCTAssertEqual(type(["1", ".", "."]), "1.", "one point only")
        XCTAssertEqual(type(["1", ".", "2", "5", "9"]), "1.25", "two decimals, never three")
        XCTAssertEqual(type(["0", "7"]), "7", "a leading zero gives way")
        XCTAssertEqual(type(["9", "9", "9", "9", "9", "9"]), "99999", "five whole digits")
        XCTAssertEqual(type(["1", "2", "del"]), "1")
        XCTAssertEqual(type(["del"]), "")
        XCTAssertEqual(type(["x"]), "", "anything but a digit, point or delete is ignored")
    }

    func testDollarTextAndCentsRoundTrip() {
        XCTAssertEqual(UsdEntry.cents(""), 0)
        XCTAssertEqual(UsdEntry.cents("."), 0)
        XCTAssertEqual(UsdEntry.cents("12."), 1200)
        XCTAssertEqual(UsdEntry.cents("0.5"), 50)
        XCTAssertEqual(UsdEntry.cents("10000"), 1_000_000)
        XCTAssertEqual(UsdEntry.text(1250), "12.50")
        XCTAssertEqual(UsdEntry.text(1200), "12")
        XCTAssertEqual(UsdEntry.text(5), "0.05")
        XCTAssertEqual(UsdEntry.text(0), "")
        for cents in [1, 5, 50, 99, 100, 1250, 2500, 999_999] {
            XCTAssertEqual(UsdEntry.cents(UsdEntry.text(cents)), cents, "\(cents) survives the field")
        }
        XCTAssertEqual(UsdEntry.presetsCents, [500, 1000, 2500, 5000, 10000], "US$ 5 / 10 / 25 / 50 / 100")
    }

    func testMoneyIsAlwaysInItsOwnCurrency() {
        XCTAssertEqual(GiveMoney.format(2000, "USD"), "US$ 20.00")
        XCTAssertEqual(GiveMoney.format(123_450, "USD"), "US$ \(grouped(1234)).50")
        XCTAssertEqual(GiveMoney.format(100_000, "KES"), "KSh \(grouped(1000))")
        XCTAssertEqual(GiveMoney.format(100_050, "KES"), "KSh \(grouped(1000)).50", "shilling cents are shown, never dropped")
        XCTAssertEqual(GiveMoney.format(5, nil), "KSh 0.05")
        XCTAssertEqual(GiveMoney.format(2000, "eur"), "EUR 20.00")
        XCTAssertEqual(money(2000, "USD"), "US$ 20.00", "the shared helper speaks the same way")
    }

    // MARK: Cover the fee

    func testCoverFeeSplitsTheTotal() {
        let covered = CoverFee.split(giftMinor: 100_000, covering: true, currency: "KES")
        XCTAssertEqual(covered.amountMinor, 101_300, "amount_minor is the TOTAL charged (gift + fee)")
        XCTAssertEqual(covered.coverFeeMinor, 1_300, "cover_fee_minor is the fee part, whole shillings")

        let plain = CoverFee.split(giftMinor: 100_000, covering: false, currency: "KES")
        XCTAssertEqual(plain.amountMinor, 100_000)
        XCTAssertNil(plain.coverFeeMinor)

        let tiny = CoverFee.split(giftMinor: 10_000, covering: true, currency: "KES")
        XCTAssertEqual(tiny.amountMinor, 10_000, "no fee under KSh 100 — nothing to cover")
        XCTAssertNil(tiny.coverFeeMinor)

        let dollars = CoverFee.split(giftMinor: 2_000, covering: true, currency: "USD")
        XCTAssertEqual(dollars.amountMinor, 2_000, "the fee table is M-Pesa's — nothing covered on PayPal")
        XCTAssertNil(dollars.coverFeeMinor)
    }

    func testCoverFeeNeverExceedsHalfAndIsWholeShillings() {
        for ksh in [1, 50, 101, 500, 501, 999, 1_000, 2_500, 5_000, 10_000, 250_000] {
            let s = CoverFee.split(giftMinor: ksh * 100, covering: true, currency: "KES")
            if let fee = s.coverFeeMinor {
                XCTAssertEqual(s.amountMinor, ksh * 100 + fee)
                XCTAssertLessThanOrEqual(fee * 2, s.amountMinor, "the server refuses a cover above half")
                XCTAssertEqual(fee % 100, 0, "whole shillings for M-Pesa")
            }
        }
        XCTAssertEqual(CoverFee.feeKsh(forGiftKsh: 100), 0)
        XCTAssertEqual(CoverFee.feeKsh(forGiftKsh: 101), 7)
        XCTAssertEqual(CoverFee.feeKsh(forGiftKsh: 1_000), 13)
        XCTAssertEqual(CoverFee.feeKsh(forGiftKsh: 5_000), 57)
        XCTAssertEqual(CoverFee.feeKsh(forGiftKsh: 10_000), 120)
    }

    func testFeeCoverDecodesOnHistoryAndDetail() throws {
        let row = try decode(GivingRecord.self,
            #"{"transaction_id":"t1","amount_minor":101300,"currency":"KES","status":"succeeded","fund":"tithe","fee_cover_minor":1300}"#)
        XCTAssertEqual(row.feeCoverMinor, 1300)
        XCTAssertNil(try decode(GivingRecord.self, #"{"transaction_id":"t2","fee_cover_minor":null}"#).feeCoverMinor)
        XCTAssertNil(try decode(GivingRecord.self, #"{"transaction_id":"t3","fee_cover_minor":0}"#).feeCoverMinor, "0 = none")
        XCTAssertNil(try decode(GivingRecord.self, #"{"transaction_id":"t4"}"#).feeCoverMinor, "an older server sends none")
        let detail = try decode(GivingDetail.self,
            #"{"transaction_id":"t1","amount_minor":101300,"status":"succeeded","fee_cover_minor":1300,"ledger":[]}"#)
        XCTAssertEqual(detail.feeCoverMinor, 1300, "the receipt reads gift 1,000 · fee cover 13 · total 1,013")
    }

    // MARK: Totals — one currency and two

    func testTotalsLineWithOneCurrency() {
        let one = [CurrencyTotal(currency: "KES", totalMinor: 350_000)]
        XCTAssertEqual(GiveMoney.line(one), "KSh \(grouped(3500))")
        XCTAssertEqual(GiveMoney.headline(one).main, "KSh \(grouped(3500))")
        XCTAssertNil(GiveMoney.headline(one).rest, "nothing rides under a single currency")
        XCTAssertEqual(GiveMoney.line([]), "KSh 0")
        XCTAssertEqual(GiveMoney.line([CurrencyTotal(currency: "KES", totalMinor: 0)]), "KSh 0")
    }

    func testTotalsLineWithTwoCurrenciesNeverAddsThem() {
        let two = [CurrencyTotal(currency: "USD", totalMinor: 2_000), CurrencyTotal(currency: "KES", totalMinor: 350_000)]
        XCTAssertEqual(GiveMoney.line(two), "KSh \(grouped(3500)) + US$ 20.00", "shillings first, dollars added on — never summed")
        let head = GiveMoney.headline(two)
        XCTAssertEqual(head.main, "KSh \(grouped(3500))")
        XCTAssertEqual(head.rest, "+ US$ 20.00")
        let onlyDollars = [CurrencyTotal(currency: "USD", totalMinor: 2_000)]
        XCTAssertEqual(GiveMoney.headline(onlyDollars).main, "US$ 20.00")
        XCTAssertNil(GiveMoney.headline(onlyDollars).rest)
        XCTAssertEqual(GiveMoney.line(two + [CurrencyTotal(currency: "KES", totalMinor: 50_000)]),
                       "KSh \(grouped(4000)) + US$ 20.00", "a repeated currency is summed with itself only")
    }

    func testHistoryTotalsArePerCurrencyAndSettledOnly() throws {
        let rows = try decode([GivingRecord].self, """
        [{"transaction_id":"a","amount_minor":100000,"currency":"KES","status":"succeeded"},
         {"transaction_id":"b","amount_minor":2000,"currency":"USD","status":"succeeded"},
         {"transaction_id":"c","amount_minor":50000,"currency":"KES","status":"failed"},
         {"transaction_id":"d","amount_minor":25000,"currency":"KES","status":"processing"}]
        """)
        XCTAssertEqual(GiveMoney.totals(of: rows),
                       [CurrencyTotal(currency: "KES", totalMinor: 100_000), CurrencyTotal(currency: "USD", totalMinor: 2_000)])
    }

    func testStatementTotalsDecodeAndFoot() throws {
        let s = try decode(GivingStatements.self, """
        {"year":2026,"total_minor":350000,"currency":"KES",
         "totals":[{"currency":"KES","total_minor":350000},{"currency":"USD","total_minor":2000}],
         "by_pledge":[{"pledge_id":null,"title":"Gifts outside a pledge","currency":"KES","total_minor":150000},
                      {"pledge_id":"p1","title":"Building","currency":"KES","total_minor":200000},
                      {"pledge_id":null,"title":"Gifts outside a pledge","currency":"USD","total_minor":2000}],
         "by_fund":[{"code":"tithe","name":"Tithe","currency":"KES","total_minor":350000},
                    {"code":"tithe","name":"Tithe","currency":"USD","total_minor":2000}]}
        """)
        XCTAssertEqual(s.totals.map(\.currency), ["KES", "USD"])
        XCTAssertEqual(s.byFund.map(\.currency), ["KES", "USD"], "one row per fund per currency")
        XCTAssertNotEqual(s.byFund[0].id, s.byFund[1].id, "two rows of one fund never collide")
        XCTAssertEqual(s.giftTotals, [CurrencyTotal(currency: "KES", totalMinor: 150_000), CurrencyTotal(currency: "USD", totalMinor: 2_000)])
        XCTAssertEqual(s.pledgeTotals, [CurrencyTotal(currency: "KES", totalMinor: 200_000)])
        // Gifts + pledges = totals, per currency.
        for t in s.totals {
            let g = s.giftTotals.first { $0.currency == t.currency }?.totalMinor ?? 0
            let p = s.pledgeTotals.first { $0.currency == t.currency }?.totalMinor ?? 0
            XCTAssertEqual(g + p, t.totalMinor, "\(t.currency) foots")
        }
    }

    func testOlderStatementWithoutTotalsFallsBack() throws {
        let s = try decode(GivingStatements.self, #"{"year":2026,"total_minor":90000,"currency":"KES","by_fund":[{"code":"tithe","total_minor":90000}]}"#)
        XCTAssertEqual(s.totals, [CurrencyTotal(currency: "KES", totalMinor: 90_000)])
        XCTAssertEqual(s.byFund.first?.currency, "KES", "a row without a currency is shillings")
        XCTAssertTrue(try decode(GivingStatements.self, #"{"year":2026,"total_minor":0}"#).totals.isEmpty)
    }

    @MainActor
    func testStatementFiguresPreferTheServerAndFallBackPerCurrency() throws {
        let vm = GivingStatementViewModel()
        vm.history = try decode([GivingRecord].self, """
        [{"transaction_id":"a","amount_minor":100000,"currency":"KES","status":"succeeded","created_at":"2026-03-01T08:00:00Z"},
         {"transaction_id":"b","amount_minor":2000,"currency":"USD","status":"succeeded","created_at":"2026-03-02T08:00:00Z"},
         {"transaction_id":"c","amount_minor":50000,"currency":"KES","status":"succeeded","pledge_id":"p1","created_at":"2026-03-03T08:00:00Z"}]
        """)
        let local = vm.figures(in: 2026)
        XCTAssertEqual(local.total, [CurrencyTotal(currency: "KES", totalMinor: 150_000), CurrencyTotal(currency: "USD", totalMinor: 2_000)])
        XCTAssertEqual(local.gifts, [CurrencyTotal(currency: "KES", totalMinor: 100_000), CurrencyTotal(currency: "USD", totalMinor: 2_000)])
        XCTAssertEqual(local.pledges, [CurrencyTotal(currency: "KES", totalMinor: 50_000)])
        XCTAssertTrue(local.hasPledgeMoney)

        vm.statements[2026] = try decode(GivingStatements.self,
            #"{"year":2026,"totals":[{"currency":"KES","total_minor":170000}],"by_pledge":[{"pledge_id":null,"currency":"KES","total_minor":170000}]}"#)
        let server = vm.figures(in: 2026)
        XCTAssertEqual(server.total, [CurrencyTotal(currency: "KES", totalMinor: 170_000)], "the server's statement wins once it answers")
        XCTAssertFalse(server.hasPledgeMoney)
        let funds = vm.fundTotals(of: vm.records(in: 2026))
        XCTAssertEqual(funds.count, 2, "BY FUND: one row per fund per currency")
    }

    // MARK: The church's calendar

    func testYearIsNairobis() {
        XCTAssertEqual(GiveCalendar.year(of: "2025-12-31T21:30:00Z"), 2026, "00:30 on 1 Jan in Nairobi is the new year")
        XCTAssertEqual(GiveCalendar.year(of: "2025-12-31T20:59:00Z"), 2025)
        XCTAssertEqual(GiveCalendar.year(of: "2026-05-01"), 2026)
        XCTAssertNil(GiveCalendar.year(of: "garbage"))
    }

    // MARK: Rails' limits, pay mode, the footer

    private let rails = """
    {"methods":[
      {"key":"mpesa","label":"M-Pesa","enabled":true,"currency":"KES","min_minor":100,"max_minor":25000000,"whole_units":true,"recurring":true,"needs_phone":true},
      {"key":"paypal","label":"PayPal","enabled":true,"currency":"USD","min_minor":100,"max_minor":1000000,"whole_units":false,"recurring":false,"needs_phone":false},
      {"key":"card","label":"Card","enabled":false,"unavailable_reason":"coming_soon"}],
     "default_method":"mpesa"}
    """

    func testAmountRulesSayTheLimits() throws {
        let m = try decode(GivingMethods.self, rails)
        let mpesa = try XCTUnwrap(m.method("mpesa")), paypal = try XCTUnwrap(m.method("paypal"))
        XCTAssertNil(GiveAmountRules.problem(totalMinor: 100_000, rail: mpesa))
        XCTAssertEqual(GiveAmountRules.problem(totalMinor: 30_000_000, rail: mpesa),
                       "M-Pesa gifts are from KSh 1 to KSh \(grouped(250_000)).")
        XCTAssertEqual(GiveAmountRules.problem(totalMinor: 100_050, rail: mpesa), "M-Pesa takes whole shillings — no cents.")
        XCTAssertNil(GiveAmountRules.problem(totalMinor: 1_250, rail: paypal), "cents are fine on PayPal")
        XCTAssertEqual(GiveAmountRules.problem(totalMinor: 50, rail: paypal),
                       "PayPal gifts are from US$ 1.00 to US$ \(grouped(10_000)).00.")
    }

    func testPayingAPledgeTakesShillingRailsOnly() throws {
        let m = try decode(GivingMethods.self, rails)
        XCTAssertTrue(m.isSelectable("paypal"))
        XCTAssertFalse(m.isSelectable("paypal", shillingsOnly: true), "a dollar payment never counts against a shilling pledge")
        XCTAssertTrue(m.isSelectable("mpesa", shillingsOnly: true))
        XCTAssertEqual(m.offered(shillingsOnly: true).map(\.key), ["mpesa", "card"], "PayPal leaves the list in pay mode")
        XCTAssertEqual(m.selection(keeping: "paypal", shillingsOnly: true), "mpesa")
        XCTAssertEqual(m.currency("paypal"), "USD")
        XCTAssertEqual(m.currency("card"), "KES", "no currency named = shillings here")
    }

    func testFooterNamesOnlyRailsThatTakeMoney() throws {
        XCTAssertEqual(GivingMethods.fallback().secureNote(), "Secure · M-Pesa · Receipt sent instantly")
        XCTAssertEqual(try decode(GivingMethods.self, rails).secureNote(), "Secure · M-Pesa & PayPal · Receipt sent instantly")
        XCTAssertFalse(try decode(GivingMethods.self, rails).secureNote().localizedCaseInsensitiveContains("card"),
                       "never promises a card it cannot take")
    }
}
