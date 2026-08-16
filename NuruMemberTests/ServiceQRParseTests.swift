// Church service check-in — the scanner must ignore every QR that isn't a Nuru
// service code. A member pointing the camera at a random poster in the foyer
// should keep scanning, not post junk to the server, so `parseServiceQR` is the
// gate that stands between the camera and POST /services/{id}/attendance.
//
// Mirrors the backend's `parseServiceQrPayload` and Android's
// `ServiceQrParseTest` — all three must agree on the payload grammar, because a
// disagreement means one platform silently can't check anyone in.
import XCTest
@testable import NuruMember

final class ServiceQRParseTests: XCTestCase {

    // MARK: Payload grammar — `nuru-service:<service_id>:<token>`

    func testParsesAServicePayload() {
        let scan = parseServiceQR("nuru-service:11111111-1111-4111-8111-111111111111:abc123")
        XCTAssertEqual(scan?.serviceId, "11111111-1111-4111-8111-111111111111")
        XCTAssertEqual(scan?.scanToken, "abc123")
    }

    func testToleratesSurroundingWhitespace() {
        XCTAssertEqual(parseServiceQR("  nuru-service:s1:tok \n")?.serviceId, "s1")
    }

    func testRejectsCodesThatAreNotOurs() {
        XCTAssertNil(parseServiceQR("https://example.com/checkin"))
        XCTAssertNil(parseServiceQR("nuru-event:s1:tok"))       // the OTHER scanner's domain
        XCTAssertNil(parseServiceQR("nuru-service:s1"))         // no token
        XCTAssertNil(parseServiceQR("nuru-service:s1:tok:extra"))
        XCTAssertNil(parseServiceQR(""))
    }

    func testRejectsAPayloadWithAnEmptyIdOrToken() {
        XCTAssertNil(parseServiceQR("nuru-service::tok"))
        XCTAssertNil(parseServiceQR("nuru-service:s1:"))
    }

    // MARK: Streak copy — the numbers alone don't pastor anyone, so each status
    // has to read as a sentence. Wording is shared verbatim with Android.

    func testStreakNoteSpeaksPlainlyForEachStatus() {
        XCTAssertEqual(streak(.new).note,
                       "This is your first check-in. Your streak starts here.")
        XCTAssertEqual(streak(.active, current: 4).note,
                       "You've been here 4 services in a row.")
        XCTAssertEqual(streak(.active, current: 1).note,
                       "You're on the board — one service in a row.")
        XCTAssertEqual(streak(.atRisk, missRun: 1).note,
                       "You missed the last service. Come this week and your streak restarts.")
        XCTAssertEqual(streak(.broken, missRun: 3).note,
                       "You've missed 3 services in a row. Today is a good day to come back.")
    }

    // MARK: Wire decoding — the snake_case status must survive the decoder.

    func testDecodesTheStreakStatusFromTheWire() throws {
        let json = """
        {"current_streak":0,"longest_streak":5,"total_attended":5,"total_missed":2,
         "breaks":1,"current_miss_run":2,"last_attended_at":null,
         "last_service_date":null,"status":"at_risk"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s = try decoder.decode(AttendanceStreak.self, from: json)
        XCTAssertEqual(s.status, .atRisk)
        XCTAssertEqual(s.longestStreak, 5)
        XCTAssertEqual(s.breaks, 1)
        XCTAssertEqual(s.totalMissed, 2)
    }

    /// An unknown status must not throw — a future server value should degrade
    /// to `new` rather than break the whole attendance screen.
    func testAnUnknownStatusFallsBackRatherThanThrowing() throws {
        let json = """
        {"current_streak":1,"longest_streak":1,"total_attended":1,"total_missed":0,
         "breaks":0,"current_miss_run":0,"status":"something_new"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let s = try decoder.decode(AttendanceStreak.self, from: json)
        XCTAssertEqual(s.status, .new)
    }

    // MARK: Time formatting

    func testShortTimePullsHoursAndMinutesOutOfAnISOInstant() {
        XCTAssertEqual(shortTime("2026-03-01T09:14:22.000Z"), "09:14")
        XCTAssertEqual(shortTime("not-a-date"), "not-a-date")
    }

    // MARK: Helpers

    private func streak(_ status: AttendanceStreakStatus,
                        current: Int = 0,
                        missRun: Int = 0) -> AttendanceStreak {
        let json = """
        {"current_streak":\(current),"longest_streak":\(current),"total_attended":\(current),
         "total_missed":\(missRun),"breaks":0,"current_miss_run":\(missRun),
         "status":"\(status.rawValue)"}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        // Force-try is fine in a test: a decode failure here IS the failure.
        return try! decoder.decode(AttendanceStreak.self, from: json)
    }
}
