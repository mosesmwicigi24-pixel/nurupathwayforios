// A department's notification words, pinned against the server's push copy
// (workers/dispatch.ts PUSH_TEMPLATE_COPY) for rows decoded exactly as
// GET /v1/me/notifications sends them — snake_case, with the payloads
// departments/service.ts schedules — so the inbox and the banner say what the
// push said. The decoder is configured like APIClient's.
import XCTest
@testable import NuruMember

final class DepartmentNotificationCopyTests: XCTestCase {

    private func row(_ template: String, payload: String) throws -> NotificationRow {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let json = """
        {"notification_id":"n1","template":"\(template)","payload":\(payload),"status":"sent",
         "scheduled_for":"2026-09-28T08:00:00.000Z","sent_at":"2026-09-28T08:00:01.000Z","read_at":null}
        """
        return try d.decode(NotificationRow.self, from: Data(json.utf8))
    }

    private func title(_ n: NotificationRow) -> String? {
        DepartmentNotificationCopy.title(template: n.template, payload: n.payload)
    }

    private func body(_ n: NotificationRow) -> String? {
        DepartmentNotificationCopy.body(template: n.template, payload: n.payload)
    }

    // MARK: the payloads departments/service.ts sends

    func testServeRequestReceivedTellsTheLeaderWhoAskedAndWhere() throws {
        let n = try row("serve_request_received",
                        payload: #"{"department_id":"d1","department":"Worship","name":"Grace Wanjiru"}"#)
        XCTAssertEqual(n.payload?.departmentId, "d1", "the tap still opens the department page")
        XCTAssertEqual(title(n), "Grace Wanjiru wants to serve in Worship")
        XCTAssertEqual(body(n), "Open the portal to welcome them in.")
    }

    func testServeRequestApprovedWelcomesTheMemberIn() throws {
        let n = try row("serve_request_approved", payload: #"{"department_id":"d1","department":"Worship"}"#)
        XCTAssertEqual(title(n), "Welcome to Worship")
        XCTAssertEqual(body(n), "Your request to serve was approved. Open Departments to see what's next.")
    }

    func testServeRequestDeclinedPointsToOtherDepartments() throws {
        let n = try row("serve_request_declined", payload: #"{"department_id":"d1","department":"Worship"}"#)
        XCTAssertEqual(title(n), "About Worship")
        XCTAssertEqual(body(n),
                       "The leader couldn't take you on right now. Other departments would love your hands \u{2014} open Departments.")
    }

    func testDepartmentPostIsHeadedByTheDepartmentAndCarriesItsPreview() throws {
        let n = try row("department_post",
                        payload: #"{"department_id":"d1","department":"Worship","preview":"Rehearsal moved to 5pm this week"}"#)
        XCTAssertEqual(title(n), "Worship")
        XCTAssertEqual(body(n), "Rehearsal moved to 5pm this week")
    }

    // MARK: dispatch.ts's fallbacks — a field missing, empty, or no payload at all

    func testMissingFieldsFallBackToTheServersWords() throws {
        let received = try row("serve_request_received", payload: #"{"department_id":"d1"}"#)
        XCTAssertEqual(title(received), "Someone wants to serve in your department")
        let approved = try row("serve_request_approved", payload: #"{"department_id":"d1"}"#)
        XCTAssertEqual(title(approved), "Welcome to the department")
        let declined = try row("serve_request_declined", payload: #"{"department_id":"d1"}"#)
        XCTAssertEqual(title(declined), "About the department")
        let post = try row("department_post", payload: #"{"department_id":"d1"}"#)
        XCTAssertEqual(title(post), "Your department")
        XCTAssertEqual(body(post), "A new post from your department.")
    }

    func testAnEmptyStringCountsAsMissing() throws {
        // dispatch.ts str(): "" is no value.
        let received = try row("serve_request_received", payload: #"{"department":"","name":""}"#)
        XCTAssertEqual(title(received), "Someone wants to serve in your department")
        let post = try row("department_post", payload: #"{"department":"","preview":""}"#)
        XCTAssertEqual(title(post), "Your department")
        XCTAssertEqual(body(post), "A new post from your department.")
    }

    func testARowWithNoPayloadStillHasTheServersWords() throws {
        let n = try row("serve_request_declined", payload: "null")
        XCTAssertNil(n.payload)
        XCTAssertEqual(title(n), "About the department")
        XCTAssertEqual(body(n),
                       "The leader couldn't take you on right now. Other departments would love your hands \u{2014} open Departments.")
    }

    // MARK: only these four templates

    func testOtherTemplatesAreLeftToTheirOwnWords() {
        for t in ["department_need_open", "department_need_approved", "department_need_rejected",
                  "department_need_closed", "giving_receipt", "badge_awarded", "serve_request", ""] {
            XCTAssertNil(DepartmentNotificationCopy.title(template: t, payload: nil), t)
            XCTAssertNil(DepartmentNotificationCopy.body(template: t, payload: nil), t)
        }
    }
}
