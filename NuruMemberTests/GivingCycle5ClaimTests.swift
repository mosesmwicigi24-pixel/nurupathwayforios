// Giving Cycle 5 — "I paid another way", pinned: the form keeps the server's
// rules before it sends (the pledge's currency, whole shillings, a day from
// a year ago to today on the church's calendar, a note of at most 300
// characters), the day the member taps is the day sent whatever the device's
// time zone, and every claim state reads in the member's words.
import XCTest
@testable import NuruMember

final class GivingCycle5ClaimTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    private let dateMessage = "Choose the day you paid — today or within the last year."

    private func problem(_ amount: String, _ currency: String = "KES", paidOn: String = "2026-09-20",
                         note: String = "", today: String = "2026-09-28") -> String? {
        ClaimRules.problem(amountText: amount, currency: currency, paidOn: paidOn, note: note, today: today)
    }

    // MARK: The day — today back to a year ago, on the church's calendar

    func testTheDayIsTodayOrWithinTheLastYear() {
        XCTAssertEqual(ClaimRules.dayRange(today: "2026-09-28"), "2025-09-28"..."2026-09-28")
        XCTAssertEqual(ClaimRules.dayRange(today: "2028-03-01").lowerBound, "2027-03-02", "365 days back across a 29 February")
        XCTAssertNil(problem("1500", paidOn: "2026-09-28"), "today")
        XCTAssertNil(problem("1500", paidOn: "2025-09-28"), "a year ago today")
        XCTAssertEqual(problem("1500", paidOn: "2026-09-29"), dateMessage, "never a day still to come")
        XCTAssertEqual(problem("1500", paidOn: "2025-09-27"), dateMessage, "never more than a year back")
        XCTAssertEqual(problem("1500", paidOn: "last week"), dateMessage)
    }

    func testTodayIsTheChurchsToday() throws {
        // 00:30 on 28 September in Nairobi is still the 27th in UTC.
        let lateUTC = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-27T21:30:00Z"))
        let today = PledgeMath.today(now: lateUTC)
        XCTAssertEqual(today, "2026-09-28")
        XCTAssertEqual(ClaimRules.dayRange(today: today).upperBound, "2026-09-28", "the church's today may be claimed")
    }

    func testTheDayTappedIsTheDaySentInAnyTimeZone() throws {
        for zone in ["Pacific/Honolulu", "Africa/Nairobi", "Asia/Tokyo", "Pacific/Kiritimati"] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = try XCTUnwrap(TimeZone(identifier: zone))
            let picked = ClaimRules.pickerDate("2026-09-12", calendar: cal)
            XCTAssertEqual(ClaimRules.day(ofPicker: picked, calendar: cal), "2026-09-12", zone)
            let range = ClaimRules.pickerRange(today: "2026-09-28", calendar: cal)
            XCTAssertTrue(range.contains(ClaimRules.pickerDate("2026-09-28", calendar: cal)), "\(zone): today can be picked")
            XCTAssertTrue(range.contains(ClaimRules.pickerDate("2025-09-28", calendar: cal)), "\(zone): a year ago can be picked")
            XCTAssertFalse(range.contains(ClaimRules.pickerDate("2026-09-29", calendar: cal)), "\(zone): tomorrow cannot")
            XCTAssertFalse(range.contains(ClaimRules.pickerDate("2025-09-27", calendar: cal)), "\(zone): past a year cannot")
        }
    }

    // MARK: The amount — the pledge's currency; shillings whole

    func testShillingsAreWhole() {
        XCTAssertEqual(MoneyEntry.minor("1500", currency: "KES"), 150_000)
        XCTAssertNil(MoneyEntry.minor("1500.50", currency: "KES"), "no cents on a shilling pledge")
        XCTAssertNil(MoneyEntry.minor("1500.00", currency: "KES"))
        XCTAssertNil(MoneyEntry.minor("0", currency: "KES"), "zero is not an amount")
        XCTAssertNil(MoneyEntry.minor("", currency: "KES"))
        XCTAssertNil(MoneyEntry.minor("12a", currency: "KES"))
        XCTAssertEqual(problem("1500.50"), "Shillings only — no cents.")
        XCTAssertEqual(problem(""), "Enter the amount you paid.")
        XCTAssertEqual(problem("0"), "Enter the amount you paid.")
        XCTAssertNil(problem("1500"))

        XCTAssertEqual(MoneyEntry.sanitize("1,500", currency: "KES"), "1500", "what is typed keeps digits only")
        XCTAssertEqual(MoneyEntry.sanitize("15.50", currency: "KES"), "1550")
        XCTAssertEqual(MoneyEntry.sanitize("1234567890", currency: "KES"), "123456789")
    }

    func testDollarsCarryCents() {
        XCTAssertEqual(MoneyEntry.minor("12.5", currency: "USD"), 1_250)
        XCTAssertEqual(MoneyEntry.minor("12.50", currency: "USD"), 1_250)
        XCTAssertEqual(MoneyEntry.minor("12", currency: "USD"), 1_200)
        XCTAssertEqual(MoneyEntry.minor("0.05", currency: "USD"), 5)
        XCTAssertEqual(MoneyEntry.minor(".5", currency: "USD"), 50)
        XCTAssertEqual(MoneyEntry.minor("12,5", currency: "USD"), 1_250, "a decimal comma reads as a point")
        XCTAssertNil(MoneyEntry.minor("12.345", currency: "USD"), "never past cents")
        XCTAssertNil(MoneyEntry.minor("1.2.3", currency: "USD"))
        XCTAssertNil(MoneyEntry.minor("0.00", currency: "USD"))
        XCTAssertNil(MoneyEntry.minor(".", currency: "USD"))
        XCTAssertNil(problem("20.00", "USD"))

        XCTAssertEqual(MoneyEntry.sanitize("12.345", currency: "USD"), "12.34")
        XCTAssertEqual(MoneyEntry.sanitize(".5", currency: "USD"), "0.5")
        XCTAssertEqual(MoneyEntry.sanitize("12,5", currency: "USD"), "12.5")
        XCTAssertEqual(MoneyEntry.sanitize("1.2.3", currency: "USD"), "1.23")
    }

    // MARK: The note — at most 300 characters

    func testTheNoteIsAtMost300Characters() {
        XCTAssertNil(problem("1500", note: String(repeating: "a", count: 300)))
        XCTAssertEqual(problem("1500", note: String(repeating: "a", count: 301)), "Keep the note to 300 characters.")
        XCTAssertNil(problem("1500", note: "  " + String(repeating: "a", count: 300) + "\n"), "counted as the server counts it: trimmed")
    }

    // MARK: What is sent

    func testTheBodyIsThePledgesCurrencyAndATrimmedNote() throws {
        let body = try XCTUnwrap(ClaimRules.body(amountText: "3000", currency: "kes", paidOn: "2026-09-12", note: "  Cash at the 9am service ", today: "2026-09-28"))
        XCTAssertEqual(body, MemberAPI.PledgeClaimBody(amountMinor: 300_000, currency: "KES", paidOn: "2026-09-12", note: "Cash at the 9am service"))
        let bare = try XCTUnwrap(ClaimRules.body(amountText: "20.00", currency: "USD", paidOn: "2026-09-12", note: "   ", today: "2026-09-28"))
        XCTAssertNil(bare.note, "an empty note is left out")
        XCTAssertEqual(bare.amountMinor, 2_000)
        XCTAssertNil(ClaimRules.body(amountText: "3000", currency: "KES", paidOn: "2026-09-29", note: "", today: "2026-09-28"),
                     "nothing is sent while the form has a problem")

        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: e.encode(bare)) as? [String: Any])
        XCTAssertEqual(json["amount_minor"] as? Int, 2_000)
        XCTAssertEqual(json["currency"] as? String, "USD")
        XCTAssertEqual(json["paid_on"] as? String, "2026-09-12")
        XCTAssertNil(json["note"], "no note, no key")
    }

    // MARK: The list — where each claim stands

    func testEachClaimStateReadsInTheMembersWords() throws {
        // As GET …/claims sends them: amounts as text, newest first.
        let claims = try decode(Envelope<PledgeClaim>.self, #"""
        {"data":[
          {"claim_id":"c3","pledge_id":"p1","amount_minor":"300000","currency":"KES","paid_on":"2026-09-12","note":"Cash at church","status":"pending","decided_at":null,"transaction_id":null,"created_at":"2026-09-12 10:00:00+03"},
          {"claim_id":"c2","pledge_id":"p1","amount_minor":"150000","currency":"KES","paid_on":"2025-12-20","note":null,"status":"confirmed","decided_at":"2025-12-22 09:00:00+03","transaction_id":"t9","created_at":"2025-12-20 18:00:00+03"},
          {"claim_id":"c1","pledge_id":"p1","amount_minor":"2000","currency":"USD","paid_on":"2026-09-01","note":"","status":"rejected","decided_at":"2026-09-03 09:00:00+03","transaction_id":null,"created_at":"2026-09-01 18:00:00+03"}
        ]}
        """#).data
        XCTAssertEqual(claims.map(\.amountMinor), [300_000, 150_000, 2_000], "amounts sent as text are read")
        XCTAssertEqual(claims.map { ClaimCopy.status($0.status) },
                       ["The office is checking it", "Recorded — thank you", "The office couldn't match it"])
        XCTAssertEqual(ClaimCopy.line(claims[0], today: "2026-09-28"), "KSh \(grouped(3000)) · paid 12 September")
        XCTAssertEqual(ClaimCopy.line(claims[1], today: "2026-09-28"), "KSh \(grouped(1500)) · paid 20 December 2025", "another year says which")
        XCTAssertEqual(ClaimCopy.line(claims[2], today: "2026-09-28"), "US$ 20.00 · paid 1 September")
        XCTAssertEqual(claims[0].note, "Cash at church")
        XCTAssertNil(claims[2].note, "an empty note reads as none")
        XCTAssertEqual(ClaimCopy.status("something new"), "The office is checking it", "a state this build doesn't know reads as waiting")
    }

    func testTheCreateAnswerIsAPendingClaim() throws {
        let c = try decode(PledgeClaim.self, #"{"claim_id":"c4","pledge_id":"p1","status":"pending","amount_minor":300000,"currency":"KES","paid_on":"2026-09-12","note":null,"created_at":"2026-09-28 10:00:00+03"}"#)
        XCTAssertEqual(c.id, "c4")
        XCTAssertEqual(c.status, "pending")
        XCTAssertEqual(c.amountMinor, 300_000)
        XCTAssertEqual(c.paidOn, "2026-09-12")
        XCTAssertNil(c.note)
    }

    func testTheAmountFieldsPrefixIsThePledgesCurrency() {
        XCTAssertEqual(MoneyEntry.prefix("KES"), "KSh")
        XCTAssertEqual(MoneyEntry.prefix("usd"), "US$")
        XCTAssertEqual(MoneyEntry.prefix("EUR"), "EUR")
    }
}
