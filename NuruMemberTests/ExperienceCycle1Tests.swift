// Experience Cycle 1 — the foundation, pinned (pathway docs/EXPERIENCE.md
// §4): the one state language for every failure — offline only when the
// phone has no network, an ended session asks to sign in, a 5xx is ours, a
// 404 offers the way back, and only our own refusals keep their words.
import XCTest
@testable import NuruMember

final class ExperienceCycle1Tests: XCTestCase {

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
}
