// Giving Cycle 5 — partnership, pinned: a gift that collects a pledge says so
// and asks only what the pledge still owes; the pledge's currency decides the
// rails; every Partners notice opens its pledge and says what the server's
// push says; and older servers (without the new fields) still decode. The
// decoder is configured exactly like APIClient's: snake_case in, camelCase out.
import XCTest
@testable import NuruMember

final class GivingCycle5Tests: XCTestCase {

    func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    private func schedule(_ fields: String) throws -> GivingSchedule {
        try decode(GivingSchedule.self, #"{"schedule_id":"s1","fund":"mission","amount_minor":500000,"currency":"KES","method":"mpesa","frequency":"monthly","status":"active",\#(fields)}"#)
    }

    // MARK: Schedule rows — pledge / next_amount_minor

    func testScheduleRowsDecodeThePledgeAndTheNextAmount() throws {
        let s = try schedule(#""pledge":{"pledge_id":"p1","title":"Kenya trip"},"next_amount_minor":300000"#)
        XCTAssertEqual(s.pledge?.pledgeId, "p1")
        XCTAssertEqual(s.pledge?.title, "Kenya trip")
        XCTAssertEqual(s.nextAmountMinor, 300_000)
        let plain = try schedule(#""pledge":null,"next_amount_minor":null"#)
        XCTAssertNil(plain.pledge); XCTAssertNil(plain.nextAmountMinor)
        let older = try schedule("\"anchor_day\":5")
        XCTAssertNil(older.pledge, "an older server sends neither")
        XCTAssertNil(older.nextAmountMinor)
    }

    func testScheduleCopyForAPledgeCollector() throws {
        let rest = try schedule(#""pledge":{"pledge_id":"p1","title":"Kenya trip"},"next_amount_minor":300000"#)
        XCTAssertEqual(ScheduleCopy.pledgeLine(rest), "Collects your pledge \u{201C}Kenya trip\u{201D}")
        XCTAssertEqual(ScheduleCopy.nextLine(rest), "Next: KSh \(grouped(3000)) — the rest of what's due")

        let paid = try schedule(#""pledge":{"pledge_id":"p1","title":"Kenya trip"},"next_amount_minor":0"#)
        XCTAssertEqual(ScheduleCopy.nextLine(paid), "Nothing to pay next time — your pledge is already paid")

        let whole = try schedule(#""pledge":{"pledge_id":"p1","title":"Kenya trip"},"next_amount_minor":500000"#)
        XCTAssertNil(ScheduleCopy.nextLine(whole), "the whole amount needs no line")

        let stopping = try schedule(#""pledge":{"pledge_id":"p1","title":"Kenya trip"},"next_amount_minor":null"#)
        XCTAssertNil(ScheduleCopy.nextLine(stopping), "no prompt coming (paused, cancelled, stopping) → no next line")

        let ordinary = try schedule(#""next_amount_minor":500000"#)
        XCTAssertNil(ScheduleCopy.pledgeLine(ordinary))
        XCTAssertNil(ScheduleCopy.nextLine(ordinary))
    }

    func testAMonthlyPledgesCollectorIsChangedOnThePledge() throws {
        let s = try schedule(#""pledge":{"pledge_id":"p1","title":"Kenya trip"}"#)
        XCTAssertTrue(ScheduleCopy.followsMonthlyPledge(s) { $0 == "p1" ? "monthly" : nil })
        XCTAssertFalse(ScheduleCopy.followsMonthlyPledge(s) { _ in "total" }, "a total pledge's collector keeps its own amount")
        XCTAssertFalse(ScheduleCopy.followsMonthlyPledge(s) { _ in nil }, "unknown shape: let the server answer")
        XCTAssertFalse(ScheduleCopy.followsMonthlyPledge(try schedule("\"anchor_day\":5")) { _ in "monthly" })

        let details = try decode(ErrorDetails.self, #"{"pledge_id":"p1"}"#)
        XCTAssertEqual(details.pledgeId, "p1")
        let refusal = APIError.http(status: 422, code: "UNPROCESSABLE",
                                    message: "This gift collects your pledge \u{201C}Kenya trip\u{201D}. Change the pledge's amount and this gift follows it.",
                                    details: details)
        XCTAssertEqual(GiveRefusal.from(refusal, deviceOnline: true).message,
                       "This gift collects your pledge \u{201C}Kenya trip\u{201D}. Change the pledge's amount and this gift follows it.")
    }

    // MARK: The pledge's currency decides the rails

    private let rails = """
    {"methods":[
      {"key":"mpesa","label":"M-Pesa","enabled":true,"currency":"KES","min_minor":100,"max_minor":25000000,"whole_units":true,"recurring":true,"needs_phone":true},
      {"key":"paypal","label":"PayPal","enabled":%@,"unavailable_reason":%@,"currency":"USD","min_minor":100,"max_minor":1000000,"whole_units":false,"recurring":false,"needs_phone":false}],
     "default_method":"mpesa"}
    """

    private func methods(paypal: Bool) throws -> GivingMethods {
        try decode(GivingMethods.self, String(format: rails, paypal ? "true" : "false", paypal ? "null" : "\"coming_soon\""))
    }

    func testAKESPledgeOffersMpesaAndAUSDPledgePayPal() throws {
        let m = try methods(paypal: true)
        XCTAssertEqual(m.offered(onlyCurrency: "KES").map(\.key), ["mpesa"])
        XCTAssertEqual(m.offered(onlyCurrency: "USD").map(\.key), ["paypal"])
        XCTAssertEqual(m.selection(keeping: "mpesa", onlyCurrency: "USD"), "paypal", "a USD pledge moves off M-Pesa")
        XCTAssertEqual(m.selection(keeping: "paypal", onlyCurrency: "KES"), "mpesa")
        XCTAssertFalse(m.isSelectable("mpesa", onlyCurrency: "usd"), "the currency is read case-blind")
    }

    func testAUSDPledgeWhilePayPalIsOffSaysWhy() throws {
        let m = try methods(paypal: false)
        XCTAssertNil(m.selection(keeping: "mpesa", onlyCurrency: "USD"), "nothing can take a dollar gift here")
        XCTAssertEqual(m.unavailableNote(forCurrency: "USD"), "Gifts toward this are in US dollars — PayPal giving is coming soon.")
        XCTAssertEqual(m.unavailableNote(forCurrency: "EUR"),
                       "Gifts toward this are in EUR, and there's no way to give in EUR here yet.")
        let mismatch = APIError.http(status: 422, code: "CURRENCY_MISMATCH",
                                     message: "This pledge is in USD. Give toward it in USD.", details: nil)
        XCTAssertEqual(GiveRefusal.from(mismatch, deviceOnline: true).message, "This pledge is in USD. Give toward it in USD.",
                       "the server's words when it refuses another currency")
    }

    // MARK: Partners notices — routing by payload keys

    private func notice(_ template: String, _ payload: String) throws -> NotificationRow {
        try decode(NotificationRow.self, #"{"notification_id":"n1","template":"\#(template)","status":"sent","payload":\#(payload)}"#)
    }

    func testPartnersNoticesOpenThePledge() throws {
        for template in ["giving_schedule_covered", "giving_schedule_stopped", "pledge_fulfilled",
                         "pledge_claim_confirmed", "pledge_claim_rejected", "pledge_due_soon", "pledge_overdue"] {
            let n = try notice(template, #"{"pledge_id":"p1","schedule_id":"s1","title":"Kenya trip"}"#)
            XCTAssertEqual(PledgeLink.from(template: n.template, pledgeId: n.payload?.pledgeId), "p1", template)
        }
        XCTAssertNil(PledgeLink.from(template: "pledge_fulfilled", pledgeId: nil), "no pledge named → Partners itself")
        XCTAssertNil(PledgeLink.from(template: "giving_schedule_failed", pledgeId: "p1"),
                     "a failed charge opens its schedule's sheet, not the pledge")
        XCTAssertEqual(GiveLink.from(template: "giving_schedule_failed", transactionId: nil, scheduleId: "s1"),
                       .schedule(scheduleId: "s1"))
        XCTAssertNil(PledgeLink.from(template: "giving_gift_failed", pledgeId: "p1"))
    }

    func testCoveredAndStoppedSayWhatTheServerSays() throws {
        let covered = try notice("giving_schedule_covered",
            #"{"schedule_id":"s1","pledge_id":"p1","title":"Kenya trip","frequency":"monthly","currency":"KES","covered_through":"2026-11-05","next_prompt_at":"2026-12-05T06:00:00Z"}"#)
        XCTAssertEqual(GivingNotificationCopy.title(template: covered.template, payload: covered.payload), "Nothing to pay this month")
        XCTAssertEqual(GivingNotificationCopy.body(template: covered.template, payload: covered.payload),
                       "\u{201C}Kenya trip\u{201D} is already paid through 5 November, so no M-Pesa prompt is coming this time. Thank you.")
        XCTAssertEqual(covered.payload?.coveredThrough, "2026-11-05")

        func stopped(_ reason: String) throws -> NotificationRow {
            try notice("giving_schedule_stopped",
                #"{"schedule_id":"s1","pledge_id":"p1","title":"Kenya trip","reason":"\#(reason)","until_on":"2026-10-31","amount_minor":500000,"currency":"KES","frequency":"monthly"}"#)
        }
        let fulfilled = try stopped("pledge_fulfilled")
        XCTAssertEqual(GivingNotificationCopy.title(template: fulfilled.template, payload: fulfilled.payload), "Your pledge is complete")
        XCTAssertEqual(GivingNotificationCopy.body(template: fulfilled.template, payload: fulfilled.payload),
                       "\u{201C}Kenya trip\u{201D} is fulfilled, so its automatic M-Pesa prompts have stopped. Thank you for carrying it through.")
        let ended = try stopped("pledge_ended")
        XCTAssertEqual(GivingNotificationCopy.title(template: ended.template, payload: ended.payload), "Your pledge has ended")
        XCTAssertEqual(GivingNotificationCopy.body(template: ended.template, payload: ended.payload),
                       "\u{201C}Kenya trip\u{201D} ended on 31 October, so its automatic prompts have stopped. Open Partners to make a new pledge.")
        let cancelled = try stopped("pledge_cancelled")
        XCTAssertEqual(GivingNotificationCopy.title(template: cancelled.template, payload: cancelled.payload), "Automatic prompts stopped")
        XCTAssertEqual(GivingNotificationCopy.body(template: cancelled.template, payload: cancelled.payload),
                       "\u{201C}Kenya trip\u{201D} was cancelled, so its recurring gift has stopped too.")
    }

    func testPledgeNoticesSayWhatTheServerSays() throws {
        let done = try notice("pledge_fulfilled", #"{"pledge_id":"p1","title":"Roof sheets","target_minor":300000,"currency":"KES","schedule_stopped":true}"#)
        XCTAssertEqual(GivingNotificationCopy.title(template: done.template, payload: done.payload), "Pledge fulfilled — thank you",
                       "the Partners words come first — the payload's title is the pledge's name")
        XCTAssertEqual(GivingNotificationCopy.body(template: done.template, payload: done.payload),
                       "You completed your Roof sheets. Every shilling carried someone further. Its automatic prompts have stopped. Open Partners to see it.")
        let doneQuiet = try notice("pledge_fulfilled", #"{"pledge_id":"p1","title":"Roof sheets","schedule_stopped":false}"#)
        XCTAssertEqual(GivingNotificationCopy.body(template: doneQuiet.template, payload: doneQuiet.payload),
                       "You completed your Roof sheets. Every shilling carried someone further. Open Partners to see it.")

        let confirmed = try notice("pledge_claim_confirmed", #"{"pledge_id":"p1","title":"Kenya trip","amount_minor":250000,"currency":"KES"}"#)
        XCTAssertEqual(GivingNotificationCopy.title(template: confirmed.template, payload: confirmed.payload), "Your payment is recorded")
        XCTAssertEqual(GivingNotificationCopy.body(template: confirmed.template, payload: confirmed.payload),
                       "KSh \(grouped(2500)) toward Kenya trip has been confirmed by the office. Thank you.")
        let rejected = try notice("pledge_claim_rejected", #"{"pledge_id":"p1","title":"Kenya trip","amount_minor":1250,"currency":"USD"}"#)
        XCTAssertEqual(GivingNotificationCopy.title(template: rejected.template, payload: rejected.payload), "We couldn't match that payment")
        XCTAssertEqual(GivingNotificationCopy.body(template: rejected.template, payload: rejected.payload),
                       "The office could not find US$ 12.50 toward Kenya trip. Reply in Community or give again from Partners.")

        let soon = try notice("pledge_due_soon", #"{"pledge_id":"p1","title":"Kenya trip","amount_minor":200000,"currency":"KES","due_on":"2026-10-05","days_away":1}"#)
        XCTAssertEqual(GivingNotificationCopy.title(template: soon.template, payload: soon.payload), "Kenya trip — due tomorrow")
        let late = try notice("pledge_overdue", #"{"pledge_id":"p1","title":"Kenya trip","amount_minor":200000,"currency":"KES","due_on":"2026-10-05"}"#)
        XCTAssertEqual(GivingNotificationCopy.body(template: late.template, payload: late.payload),
                       "KSh \(grouped(2000)) was due on 5 October. No pressure — give when you can, or tell us if you paid another way.")
    }

    func testTheHeadsUpForAPartPaidPledgeAsksOnlyTheRest() throws {
        let partial = try notice("giving_schedule_heads_up",
            #"{"schedule_id":"s1","amount_minor":300000,"currency":"KES","frequency":"monthly","fund_name":"Mission","prompt_at":"2026-11-05T06:00:00Z","pledge_title":"Kenya trip","partial":true}"#)
        XCTAssertEqual(GivingNotificationCopy.body(template: partial.template, payload: partial.payload),
                       "An M-Pesa prompt for KSh \(grouped(3000)) — the rest of what's due on \u{201C}Kenya trip\u{201D} — is coming to your phone in a few minutes. Enter your PIN to give.")
        let whole = try notice("giving_schedule_heads_up",
            #"{"schedule_id":"s1","amount_minor":500000,"currency":"KES","frequency":"monthly","fund_name":"Mission","pledge_title":"Kenya trip","partial":false}"#)
        XCTAssertEqual(GivingNotificationCopy.body(template: whole.template, payload: whole.payload),
                       "An M-Pesa prompt for KSh \(grouped(5000)) to Mission is coming to your phone in a few minutes. Enter your PIN to give.")
        XCTAssertNil(PledgeLink.from(template: partial.template, pledgeId: partial.payload?.pledgeId), "the heads-up opens Give")
    }

    func testNewPayloadKeysAreOptionalAndTolerant() throws {
        let bare = try notice("pledge_fulfilled", "{}")
        XCTAssertNil(bare.payload?.pledgeId); XCTAssertNil(bare.payload?.scheduleStopped)
        XCTAssertNil(bare.payload?.coveredThrough); XCTAssertNil(bare.payload?.partial)
        let odd = try notice("giving_schedule_covered", #"{"pledge_id":"p1","schedule_stopped":"yes","days_away":"one","partial":1}"#)
        XCTAssertEqual(odd.payload?.pledgeId, "p1", "an odd field never loses the pledge the tap opens")
        XCTAssertNil(odd.payload?.scheduleStopped)
        XCTAssertNil(odd.payload?.daysAway)
        XCTAssertEqual(GivingNotificationCopy.dayWords("2027-01-05"), "5 January")
        XCTAssertEqual(GivingNotificationCopy.dayWords("soon"), "soon")
    }
}
