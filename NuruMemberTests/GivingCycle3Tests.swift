// Giving Cycle 3 — recovery, pinned: "Try again" retries the failed GIFT on
// the server (never a hand-rebuilt copy that could lose its pledge), with a
// key that is replayed only when the last attempt got no answer; a refusal
// sends the member back to the form; a `giving_gift_failed` notification opens
// that gift's result and says why in the server's words. The decoder is
// configured exactly like APIClient's: snake_case in, camelCase out.
import XCTest
@testable import NuruMember

final class GivingCycle3Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    private let refused = APIError.http(status: 422, code: "UNPROCESSABLE",
                                        message: "Only a gift that did not go through can be tried again.", details: nil)

    // MARK: Retry flow state

    func testTryAgainRetriesTheFailedGiftOrGoesBackToTheForm() {
        XCTAssertEqual(GiveRetry.action(failedTransactionId: "t1"), .retry(transactionId: "t1"),
                       "a gift that failed is retried on the server")
        XCTAssertEqual(GiveRetry.action(failedTransactionId: nil), .backToForm,
                       "a refusal that made no gift (a 422, offline before sending) goes back to the form")
        XCTAssertEqual(GiveRetry.action(failedTransactionId: ""), .backToForm)
    }

    func testAfterAnErrorTheSameGiftIsRetriedOnlyWhenTheServerNeverAnswered() {
        XCTAssertEqual(GiveRetry.target(after: APIError.offline, retrying: "t1"), "t1")
        XCTAssertEqual(GiveRetry.target(after: APIError.transport("reset"), retrying: "t1"), "t1")
        XCTAssertEqual(GiveRetry.target(after: URLError(.timedOut), retrying: "t1"), "t1")
        XCTAssertNil(GiveRetry.target(after: refused, retrying: "t1"),
                     "the server said no — the same request would be refused again")
        XCTAssertNil(GiveRetry.target(after: APIError.http(status: 500, code: nil, message: "x", details: nil), retrying: "t1"))
    }

    func testTheRetryKeyIsReplayedOnlyAfterNoAnswer() {
        var n = 0
        let fresh = { () -> String in n += 1; return "fresh-\(n)" }
        XCTAssertEqual(GiveRetry.key(after: APIError.offline, current: "K", fresh: fresh), "K",
                       "no answer: the same key, so a retry that did land is found, not doubled")
        XCTAssertEqual(GiveRetry.key(after: refused, current: "K", fresh: fresh), "fresh-1", "after any answer: a new key")
        XCTAssertEqual(GiveRetry.key(after: nil, current: "K", fresh: fresh), "fresh-2", "after success: a new key")
    }

    func testARetrySequenceEndsBackAtTheForm() {
        // Failed gift t1 → Try again (offline) → Try again (refused) → form.
        var target: String? = "t1"
        var key = "K1"
        XCTAssertEqual(GiveRetry.action(failedTransactionId: target), .retry(transactionId: "t1"))
        target = GiveRetry.target(after: APIError.offline, retrying: "t1")
        key = GiveRetry.key(after: APIError.offline, current: key, fresh: { "K2" })
        XCTAssertEqual(target, "t1"); XCTAssertEqual(key, "K1")
        XCTAssertEqual(GiveRetry.action(failedTransactionId: target), .retry(transactionId: "t1"))
        target = GiveRetry.target(after: refused, retrying: "t1")
        key = GiveRetry.key(after: refused, current: key, fresh: { "K2" })
        XCTAssertNil(target); XCTAssertEqual(key, "K2")
        XCTAssertEqual(GiveRetry.action(failedTransactionId: target), .backToForm)
    }

    func testAPromptStillWaitingIsWatchedNotFailed() throws {
        let details = try decode(ErrorDetails.self, #"{"transaction_id":"t9"}"#)
        let waiting = APIError.http(status: 409, code: "GIFT_IN_PROGRESS", message: "A prompt is waiting.", details: details)
        XCTAssertEqual(GiveRefusal.from(waiting, fallback: "x"), .promptWaiting(transactionId: "t9", message: "A prompt is waiting."))
        XCTAssertTrue(GiveRefusal.gotNoServerAnswer(APIError.offline))
        XCTAssertFalse(GiveRefusal.gotNoServerAnswer(waiting))
    }

    func testRetryAnswerCarriesRetryOf() throws {
        let r = try decode(GivingIntentResult.self,
            #"{"transaction_id":"t2","status":"processing","provider":"mpesa","provider_ref":"ws_CO_1","reused":false,"retry_of":"t1"}"#)
        XCTAssertEqual(r.transactionId, "t2")
        XCTAssertEqual(r.retryOf, "t1")
        XCTAssertNil(try decode(GivingIntentResult.self, #"{"transaction_id":"t3"}"#).retryOf, "an ordinary intent retries nothing")
    }

    // MARK: giving_gift_failed

    private let failedPush = """
    {"notification_id":"n1","template":"giving_gift_failed","status":"sent","scheduled_for":"2026-09-28T08:00:00Z",
     "payload":{"transaction_id":"t1","amount_minor":100000,"currency":"KES","fund":"tithe","failure_code":"unreachable",
                "reason":"The M-Pesa prompt couldn't reach the phone.","hint":"Check the phone is on and has signal, then try again."}}
    """

    func testFailedGiftNotificationOpensThatGift() throws {
        let n = try decode(NotificationRow.self, failedPush)
        XCTAssertEqual(n.payload?.transactionId, "t1")
        XCTAssertEqual(GiveLink.from(template: n.template, transactionId: n.payload?.transactionId), .failedGift(transactionId: "t1"))
        XCTAssertNil(GiveLink.from(template: "giving_gift_failed", transactionId: nil), "no gift named → the generic Give tab")
        XCTAssertNil(GiveLink.from(template: "giving_receipt", transactionId: "t1"), "a receipt notice is not a failure")
    }

    func testFailedGiftNotificationSaysWhyInTheServersWords() throws {
        let n = try decode(NotificationRow.self, failedPush)
        XCTAssertEqual(GivingNotificationCopy.title(template: n.template, payload: n.payload), "Your gift didn't go through")
        XCTAssertEqual(GivingNotificationCopy.body(template: n.template, payload: n.payload),
                       "The M-Pesa prompt couldn't reach the phone. Check the phone is on and has signal, then try again.")
        let bare = try decode(NotificationRow.self, #"{"notification_id":"n2","template":"giving_gift_failed","payload":{}}"#)
        XCTAssertEqual(GivingNotificationCopy.body(template: bare.template, payload: bare.payload),
                       "The payment didn't complete. Open Give to try again.", "the server's own fallback words")
        XCTAssertNil(GivingNotificationCopy.title(template: "badge_awarded", payload: nil), "other templates keep their own words")
    }

    func testOneOddPayloadFieldNeverBlanksTheNotification() throws {
        let n = try decode(NotificationRow.self,
            #"{"notification_id":"n3","template":"giving_gift_failed","payload":{"level_number":"three","amount_minor":"1000","transaction_id":"t4","reason":"Declined."}}"#)
        XCTAssertNotNil(n.payload, "an odd field used to throw and drop the whole payload")
        XCTAssertNil(n.payload?.levelNumber)
        XCTAssertNil(n.payload?.amountMinor)
        XCTAssertEqual(n.payload?.transactionId, "t4", "the tap still lands on the gift")
        XCTAssertEqual(n.payload?.reason, "Declined.")
    }
}
