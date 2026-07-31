// Nuru Live — WHEP subscribe retry fix (2026-07-31 production incident).
// Pins the PURE decision logic WhepSubscriber's retry loop runs on: bounded
// exponential backoff, retryable-vs-terminal error classification, and
// retry-window expiry. See WhepRetryPolicy's header comment for the
// production-log evidence this is built from — this test does not exercise
// a real WebRTC/MediaMTX round trip, only the policy math.
import XCTest
@testable import NuruMember

final class WhepRetryPolicyTests: XCTestCase {
    // MARK: Backoff schedule — ~0.5s doubling to an 8s cap.

    func testBackoffDoublesFromHalfASecondUpToAnEightSecondCap() {
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 1), 0.5)
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 2), 1.0)
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 3), 2.0)
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 4), 4.0)
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 5), 8.0)
        // Stays capped, never grows past 8s no matter how many attempts.
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 6), 8.0)
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 20), 8.0)
    }

    func testBackoffForAttemptZeroOrNegativeIsZero() {
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: 0), 0)
        XCTAssertEqual(WhepRetryPolicy.backoffDelay(forAttempt: -1), 0)
    }

    // MARK: Window expiry

    func testWindowIsNotExpiredImmediately() {
        let startedAt = Date()
        XCTAssertFalse(WhepRetryPolicy.isWindowExpired(startedAt: startedAt, now: startedAt))
    }

    func testWindowIsNotExpiredJustBeforeTheDeadline() {
        let startedAt = Date()
        let now = startedAt.addingTimeInterval(WhepRetryPolicy.window - 1)
        XCTAssertFalse(WhepRetryPolicy.isWindowExpired(startedAt: startedAt, now: now))
    }

    func testWindowIsExpiredExactlyAtTheDeadline() {
        let startedAt = Date()
        let now = startedAt.addingTimeInterval(WhepRetryPolicy.window)
        XCTAssertTrue(WhepRetryPolicy.isWindowExpired(startedAt: startedAt, now: now))
    }

    func testWindowIsExpiredWellPastTheDeadline() {
        let startedAt = Date()
        let now = startedAt.addingTimeInterval(WhepRetryPolicy.window + 45)
        XCTAssertTrue(WhepRetryPolicy.isWindowExpired(startedAt: startedAt, now: now))
    }

    // MARK: Classification — the actual production bug

    /// "no stream is available" on the WHEP POST surfaces as a 404
    /// `WebRTCSDPError.httpStatus` — this MUST be "not yet", never a
    /// terminal failure, or the original bug (host gives up permanently
    /// while the guest is seconds from being ready) comes right back.
    func testHTTP404NoStreamAvailableIsRetryable() {
        XCTAssertEqual(WhepRetryPolicy.classify(WebRTCSDPError.httpStatus(404)), .retryable)
    }

    func testServerErrorStatusesAreRetryable() {
        XCTAssertEqual(WhepRetryPolicy.classify(WebRTCSDPError.httpStatus(500)), .retryable)
        XCTAssertEqual(WhepRetryPolicy.classify(WebRTCSDPError.httpStatus(503)), .retryable)
    }

    func testUnknownHTTPStatusIsRetryable() {
        // -1 is what WhipHTTP.post uses when the response isn't even an
        // HTTPURLResponse (e.g. a network drop) — must not be treated as a
        // permanent failure either.
        XCTAssertEqual(WhepRetryPolicy.classify(WebRTCSDPError.httpStatus(-1)), .retryable)
    }

    func testMissingAnswerOrDescriptionIsRetryable() {
        XCTAssertEqual(WhepRetryPolicy.classify(WebRTCSDPError.noAnswer), .retryable)
        XCTAssertEqual(WhepRetryPolicy.classify(WebRTCSDPError.noDescription), .retryable)
    }

    /// A structurally-bad WHEP URL can never succeed no matter how many
    /// times it's retried — this is the one case that should fail fast
    /// instead of burning the whole retry window.
    func testBadURLIsTerminal() {
        XCTAssertEqual(WhepRetryPolicy.classify(WebRTCSDPError.badURL), .terminal("Bad stage link."))
    }

    func testGenericNetworkErrorIsRetryable() {
        XCTAssertEqual(WhepRetryPolicy.classify(URLError(.timedOut)), .retryable)
        XCTAssertEqual(WhepRetryPolicy.classify(URLError(.networkConnectionLost)), .retryable)
    }

    func testCompletelyUnrecognizedErrorDefaultsToRetryable() {
        struct SomeOtherError: Error {}
        XCTAssertEqual(WhepRetryPolicy.classify(SomeOtherError()), .retryable)
    }

    // MARK: Cancellation — Leave Stage / teardown must stop the loop
    // silently, never surface as a visible error.

    func testTaskCancellationErrorIsClassifiedAsCancelled() {
        XCTAssertEqual(WhepRetryPolicy.classify(CancellationError()), .cancelled)
    }

    func testURLErrorCancelledIsClassifiedAsCancelled() {
        XCTAssertEqual(WhepRetryPolicy.classify(URLError(.cancelled)), .cancelled)
    }
}
