// Giving Cycle 1 — the rules behind the Give form, pinned: the M-Pesa prompt
// goes to a real Kenyan number the member chose (never a built-in one, never
// another member's), the method list is the server's, a failed gift carries
// the server's reason, a prompt still waiting is watched rather than failed,
// and RECURRING GIFTS never lists a cancelled schedule. The decoder is
// configured exactly like APIClient's: snake_case in, camelCase out.
import XCTest
@testable import NuruMember

final class GivingCycle1Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    // MARK: Kenyan mobile numbers

    func testKenyanNumbersNormaliseToE164() {
        let cases: [(String, String)] = [
            ("0712345678", "+254712345678"),
            ("0110 123 456", "+254110123456"),
            ("+254 711 222 333", "+254711222333"),
            ("254711222333", "+254711222333"),
            ("+254110123456", "+254110123456"),
            ("2541 10 123 456", "+254110123456"),
            ("0712-345-678", "+254712345678"),
            ("  0712 345 678  ", "+254712345678"),
            ("712345678", "+254712345678"),                              // nine digits — the server reads it too
            ("\u{202A}+254 712 345 678\u{202C}", "+254712345678"),       // Contacts' direction marks
        ]
        for (raw, e164) in cases {
            XCTAssertEqual(KenyanPhone.normalize(raw), e164, raw)
            XCTAssertEqual(KenyanPhone.check(raw), .valid(e164), raw)
        }
    }

    func testNotAKenyanMobileNumberIsInvalid() {
        for raw in ["12345", "0812345678", "+254 812 345 678", "07123456789", "071234567",
                    "0712abc678", "+1 415 555 0100", "254 0712 345 678", "++254711222333", "+"] {
            XCTAssertNil(KenyanPhone.normalize(raw), raw)
            XCTAssertEqual(KenyanPhone.check(raw), .invalid, raw)
        }
    }

    func testEmptyIsEmptyNotInvalid() {
        XCTAssertEqual(KenyanPhone.check(""), .empty, "an empty field asks; it does not scold")
        XCTAssertEqual(KenyanPhone.check("   "), .empty)
        XCTAssertNil(KenyanPhone.normalize(""))
    }

    /// Giving Cycle 10 (parity with Android's kenyanMobileDisplay): the screen
    /// reads a number the way a Kenyan does, never "+254711222333".
    func testANumberIsShownTheWayAKenyanReadsIt() {
        XCTAssertEqual(KenyanPhone.display("+254711222333"), "0711 222 333")
        XCTAssertEqual(KenyanPhone.display("254111222333"), "0111 222 333")
        XCTAssertEqual(KenyanPhone.display("0722 000 111"), "0722 000 111")
        XCTAssertEqual(KenyanPhone.display("+1 415 555 0100"), "+1 415 555 0100", "not a Kenyan mobile → as given")
    }

    // MARK: The number a prompt goes to

    func testInitialNumberIsLastUsedThenProfileThenNone() {
        XCTAssertEqual(GivingPhoneMemory.initial(remembered: "0722000111", onFile: "+254711222333"), "+254722000111",
                       "the number they last gave from on this phone comes first")
        XCTAssertEqual(GivingPhoneMemory.initial(remembered: nil, onFile: "+254711222333"), "+254711222333")
        XCTAssertEqual(GivingPhoneMemory.initial(remembered: "garbage", onFile: "+254711222333"), "+254711222333")
        XCTAssertNil(GivingPhoneMemory.initial(remembered: nil, onFile: nil), "nothing known → empty, and the sheet asks")
        XCTAssertNil(GivingPhoneMemory.initial(remembered: nil, onFile: "12345"))
    }

    func testRememberedNumberIsKeptPerMember() throws {
        let suite = "GivingCycle1Tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let memory = GivingPhoneMemory(defaults: defaults)

        memory.remember("0711 222 333", for: "u1")
        XCTAssertEqual(memory.phone(for: "u1"), "+254711222333", "kept as E.164")
        XCTAssertNil(memory.phone(for: "u2"), "another member on this phone never inherits u1's number")
        XCTAssertNil(memory.phone(for: nil))

        memory.remember("12345", for: "u2")
        XCTAssertNil(memory.phone(for: "u2"), "only a real Kenyan mobile number is remembered")
        memory.remember("0722000111", for: nil)
        XCTAssertEqual(memory.phone(for: "u1"), "+254711222333", "no member, nothing stored")

        memory.remember("0722000111", for: "u1")
        XCTAssertEqual(memory.phone(for: "u1"), "+254722000111", "the latest accepted number wins")
    }

    // MARK: GET /giving/methods

    private let methodsJSON = """
    {"methods":[
      {"key":"mpesa","label":"M-Pesa","enabled":true,"unavailable_reason":null,"currency":"KES",
       "min_minor":100,"max_minor":25000000,"whole_units":true,"recurring":true,"needs_phone":true},
      {"key":"airtel","label":"Airtel Money","enabled":false,"unavailable_reason":"coming_soon","currency":"KES",
       "min_minor":100,"max_minor":15000000,"whole_units":true,"recurring":false,"needs_phone":true},
      {"key":"paypal","label":"PayPal","enabled":false,"unavailable_reason":"coming_soon","currency":"USD",
       "min_minor":100,"max_minor":1000000,"whole_units":false,"recurring":false,"needs_phone":false},
      {"key":"card","label":"Card","enabled":false,"unavailable_reason":"coming_soon","currency":null,
       "min_minor":100,"max_minor":100000000,"whole_units":false,"recurring":false,"needs_phone":false}],
     "phone_on_file":"+254711222333","default_method":"mpesa"}
    """

    func testMethodsDecodeEnabledAndDisabledRails() throws {
        let m = try decode(GivingMethods.self, methodsJSON)
        XCTAssertEqual(m.methods.map(\.key), ["mpesa", "airtel", "paypal", "card"])
        XCTAssertEqual(m.phoneOnFile, "+254711222333")
        XCTAssertEqual(m.defaultMethod, "mpesa")

        let mpesa = try XCTUnwrap(m.method("mpesa"))
        XCTAssertTrue(mpesa.enabled)
        XCTAssertNil(mpesa.unavailableReason)
        XCTAssertEqual(mpesa.currency, "KES")
        XCTAssertEqual(mpesa.minMinor, 100)
        XCTAssertEqual(mpesa.maxMinor, 25_000_000)
        XCTAssertTrue(mpesa.wholeUnits)
        XCTAssertTrue(mpesa.recurring)
        XCTAssertTrue(mpesa.needsPhone)

        let airtel = try XCTUnwrap(m.method("airtel"))
        XCTAssertFalse(airtel.enabled)
        XCTAssertEqual(airtel.unavailableReason, "coming_soon")
        XCTAssertNil(m.method("card")?.currency, "a null currency is any currency")

        XCTAssertTrue(m.isSelectable("mpesa"))
        XCTAssertFalse(m.isSelectable("airtel"), "no Airtel provider — never offered as if it could take money")
        XCTAssertFalse(m.isSelectable("paypal"))
        XCTAssertFalse(m.isSelectable("card"))
        XCTAssertFalse(m.isSelectable("equity"), "a rail the server does not list is not offered")
        XCTAssertNil(m.unavailableBadge("mpesa"))
        XCTAssertEqual(m.unavailableBadge("airtel"), "SOON")
        XCTAssertEqual(m.unavailableBadge("card"), "SOON")
        XCTAssertTrue(m.allowsRecurring("mpesa"))
        XCTAssertFalse(m.allowsRecurring("airtel"))
        XCTAssertFalse(m.allowsRecurring("paypal"))
    }

    func testMethodsToleratesNullsAndAbsentFields() throws {
        let m = try decode(GivingMethods.self,
            #"{"methods":[{"key":"mpesa"}],"phone_on_file":null,"default_method":null}"#)
        XCTAssertEqual(m.methods.count, 1)
        XCTAssertNil(m.phoneOnFile)
        XCTAssertNil(m.defaultMethod)
        let mpesa = try XCTUnwrap(m.method("mpesa"))
        XCTAssertFalse(mpesa.enabled, "an absent `enabled` is NOT enabled")
        XCTAssertFalse(mpesa.recurring)
        XCTAssertFalse(m.isSelectable("mpesa"))
        XCTAssertEqual(m.unavailableBadge("mpesa"), "UNAVAILABLE")

        XCTAssertTrue(try decode(GivingMethods.self, "{}").methods.isEmpty)
        XCTAssertTrue(try decode(GivingMethods.self, #"{"methods":[{"label":"no key"}]}"#).methods.isEmpty,
                      "a rail with no key is not a rail — an unreadable list reads as none (Give falls back)")
        XCTAssertTrue(try decode(GivingMethods.self, #"{"methods":[{"key":""}],"phone_on_file":""}"#).methods.isEmpty)
    }

    func testFallbackIsMpesaAlone() {
        let f = GivingMethods.fallback()
        XCTAssertEqual(f.methods.map(\.key), ["mpesa"])
        XCTAssertTrue(f.isSelectable("mpesa"))
        XCTAssertTrue(f.allowsRecurring("mpesa"))
        XCTAssertNil(f.phoneOnFile)
        XCTAssertEqual(GivingMethods.fallback(phoneOnFile: "+254711222333").phoneOnFile, "+254711222333")
    }

    func testCardEnabledOnTheServerStaysSoonInThisBuild() throws {
        // A dev server enables cards (for a web checkout); this app has no
        // Stripe SDK, so it must not offer one.
        let m = try decode(GivingMethods.self,
            #"{"methods":[{"key":"card","label":"Card","enabled":true},{"key":"mpesa","label":"M-Pesa","enabled":true}],"default_method":"card"}"#)
        XCTAssertFalse(m.isSelectable("card"))
        XCTAssertEqual(m.unavailableBadge("card"), "SOON")
        XCTAssertEqual(m.selection(keeping: "card"), "mpesa", "the server's default is skipped when this build cannot take it")
    }

    func testMpesaSwitchedOffSaysUnavailableNotSoon() throws {
        let off = try decode(GivingMethods.self,
            #"{"methods":[{"key":"mpesa","label":"M-Pesa","enabled":false,"unavailable_reason":"unavailable"}]}"#)
        XCTAssertEqual(off.unavailableBadge("mpesa"), "UNAVAILABLE")
        XCTAssertEqual(off.unavailableNote("mpesa"), "M-Pesa isn't available for giving right now.")
        XCTAssertNil(off.selection(keeping: "mpesa"), "nothing selectable → nothing selected")
        let soon = try decode(GivingMethods.self, methodsJSON)
        XCTAssertEqual(soon.unavailableNote("airtel"), "Airtel Money giving is coming soon.")
    }

    func testSelectionKeepsTheCurrentRailThenTheDefault() throws {
        let m = try decode(GivingMethods.self, methodsJSON)
        XCTAssertEqual(m.selection(keeping: "mpesa"), "mpesa")
        XCTAssertEqual(m.selection(keeping: "airtel"), "mpesa", "off a rail that cannot be picked, onto the default")
        let both = try decode(GivingMethods.self,
            #"{"methods":[{"key":"mpesa","enabled":true},{"key":"paypal","enabled":true}],"default_method":"mpesa"}"#)
        XCTAssertEqual(both.selection(keeping: "paypal"), "paypal", "a member's still-valid choice is kept")
    }

    func testMergedOrderKeepsTheMembersOrder() {
        let server = ["mpesa", "airtel", "paypal", "card"]
        XCTAssertEqual(GivingRails.mergedOrder(current: ["mpesa"], server: server), server,
                       "new rails arrive in the server's order")
        XCTAssertEqual(GivingRails.mergedOrder(current: ["paypal", "mpesa", "airtel", "card"], server: server),
                       ["paypal", "mpesa", "airtel", "card"], "the member's reorder survives a refresh")
        XCTAssertEqual(GivingRails.mergedOrder(current: ["paypal", "mpesa", "equity"], server: ["mpesa", "paypal"]),
                       ["paypal", "mpesa"], "a rail the server stopped listing drops out")
        XCTAssertEqual(GivingRails.mergedOrder(current: [], server: ["mpesa", "mpesa"]), ["mpesa"])
    }

    // MARK: `failure` on history and detail

    func testFailureDecodesOnHistoryRows() throws {
        let rows = try decode([GivingRecord].self, """
        [{"transaction_id":"t1","status":"failed","fund":"tithe","amount_minor":100000,"created_at":"2026-09-28T08:00:00Z",
          "failure":{"code":"cancelled","reason":"The M-Pesa prompt was cancelled.",
                     "hint":"Nothing was taken. Give again whenever you're ready.","retryable":false}},
         {"transaction_id":"t2","status":"succeeded","fund":"tithe","amount_minor":100000,"created_at":"2026-09-28T08:00:00Z","failure":null},
         {"transaction_id":"t3","status":"failed","fund":"tithe","amount_minor":100000,"created_at":"2026-09-28T08:00:00Z"},
         {"transaction_id":"t4","status":"failed","fund":"tithe","failure":"declined"}]
        """)
        XCTAssertEqual(rows.count, 4)
        XCTAssertEqual(rows[0].failure?.code, "cancelled")
        XCTAssertEqual(rows[0].failure?.reason, "The M-Pesa prompt was cancelled.")
        XCTAssertEqual(rows[0].failure?.hint, "Nothing was taken. Give again whenever you're ready.")
        XCTAssertEqual(rows[0].failure?.retryable, false)
        XCTAssertNil(rows[1].failure, "null → no reason")
        XCTAssertNil(rows[2].failure, "absent (an older server) → no reason")
        XCTAssertNil(rows[3].failure, "a malformed failure never fails the row")
        XCTAssertEqual(rows[3].transactionId, "t4")
    }

    func testFailureDecodesOnTransactionDetail() throws {
        let failed = try decode(GivingDetail.self, """
        {"transaction_id":"t1","status":"failed","fund":"tithe","amount_minor":100000,"created_at":"2026-09-28T08:00:00Z",
         "ledger":[],
         "failure":{"code":"unreachable","reason":"The M-Pesa prompt couldn't reach the phone.",
                    "hint":"Check the phone is on and has signal, then try again.","retryable":true}}
        """)
        XCTAssertEqual(failed.failure?.code, "unreachable")
        XCTAssertEqual(failed.failure?.reason, "The M-Pesa prompt couldn't reach the phone.")
        XCTAssertEqual(failed.failure?.hint, "Check the phone is on and has signal, then try again.")
        XCTAssertEqual(failed.failure?.retryable, true)
        XCTAssertNil(try decode(GivingDetail.self, #"{"transaction_id":"t2","status":"succeeded","failure":null}"#).failure)
        XCTAssertNil(try decode(GivingDetail.self, #"{"transaction_id":"t3","status":"failed"}"#).failure)
        let partial = try decode(GivingDetail.self, #"{"transaction_id":"t4","status":"failed","failure":{"code":"busy"}}"#)
        XCTAssertEqual(partial.failure?.reason, "", "missing words read as empty — the views then show none")
        XCTAssertEqual(partial.failure?.retryable, false)
    }

    // MARK: RECURRING GIFTS

    func testSchedulesDecodeTheCycle1Fields() throws {
        let s = try decode(GivingSchedule.self, """
        {"schedule_id":"s1","fund":"tithe","amount_minor":100000,"currency":"KES","frequency":"monthly","method":"mpesa",
         "status":"paused","next_run_at":"2026-10-01T06:00:00Z","created_at":"2026-09-01T06:00:00Z",
         "phone_number":"+254711222333","retry_at":"2026-09-28T12:00:00Z",
         "last_failure":{"code":"insufficient_funds","reason":"There wasn't enough in the M-Pesa account.",
                         "hint":"Nothing was taken. Top up, or try a smaller amount.","retryable":false}}
        """)
        XCTAssertEqual(s.status, "paused")
        XCTAssertEqual(s.phoneNumber, "+254711222333")
        XCTAssertEqual(s.retryAt, "2026-09-28T12:00:00Z")
        XCTAssertEqual(s.lastFailure?.code, "insufficient_funds")
        XCTAssertEqual(s.lastFailure?.reason, "There wasn't enough in the M-Pesa account.")

        let bare = try decode(GivingSchedule.self,
            #"{"schedule_id":"s2","phone_number":null,"retry_at":null,"last_failure":null}"#)
        XCTAssertNil(bare.phoneNumber, "null = the profile's number")
        XCTAssertNil(bare.retryAt)
        XCTAssertNil(bare.lastFailure)
        XCTAssertNil(try decode(GivingSchedule.self, #"{"schedule_id":"s3"}"#).lastFailure, "an older server sends none")
    }

    func testActiveSchedulesListActiveThenPausedNeverCancelled() throws {
        let all = try decode([GivingSchedule].self, """
        [{"schedule_id":"c1","status":"cancelled"},
         {"schedule_id":"p1","status":"paused"},
         {"schedule_id":"a1","status":"active"},
         {"schedule_id":"x1","status":"ended"},
         {"schedule_id":"a2","status":"ACTIVE"}]
        """)
        XCTAssertEqual(GiveSchedules.listed(all).map(\.scheduleId), ["a1", "a2", "p1"],
                       "running first, then paused; never cancelled, never a status this build does not know")
        XCTAssertTrue(GiveSchedules.listed(Array(all.prefix(1))).isEmpty,
                      "only cancelled schedules → no RECURRING GIFTS strip at all")
    }

    // MARK: A refused gift

    func testGiftInProgressWatchesTheWaitingPrompt() throws {
        let details = try decode(ErrorDetails.self, #"{"transaction_id":"tx-9"}"#)
        XCTAssertEqual(details.transactionId, "tx-9")
        let words = "A prompt from a moment ago is still waiting on your phone. Approve it, or wait a minute and try again."
        let err = APIError.http(status: 409, code: "GIFT_IN_PROGRESS", message: words, details: details)
        XCTAssertEqual(GiveRefusal.from(err, deviceOnline: true),
                       .promptWaiting(transactionId: "tx-9", message: words))
    }

    func testEveryOtherRefusalShowsTheServersWords() {
        let range = APIError.http(status: 422, code: "AMOUNT_OUT_OF_RANGE",
                                  message: "M-Pesa gifts are from KSh 1 to KSh 250,000.", details: nil)
        XCTAssertEqual(GiveRefusal.from(range, deviceOnline: true), .message("M-Pesa gifts are from KSh 1 to KSh 250,000."))
        let phone = APIError.http(status: 422, code: "PHONE_REQUIRED",
                                  message: "Add the M-Pesa number to prompt for this gift.", details: nil)
        XCTAssertEqual(GiveRefusal.from(phone, deviceOnline: true).message, "Add the M-Pesa number to prompt for this gift.")
        let exists = APIError.http(status: 409, code: "SCHEDULE_EXISTS",
                                   message: "You already give KSh 1,000 every month to Tithe. Change that gift instead of adding a second one.",
                                   details: nil)
        XCTAssertEqual(GiveRefusal.from(exists, deviceOnline: true).message,
                       "You already give KSh 1,000 every month to Tithe. Change that gift instead of adding a second one.")
        let noTx = APIError.http(status: 409, code: "GIFT_IN_PROGRESS", message: "Still waiting.", details: nil)
        XCTAssertEqual(GiveRefusal.from(noTx, deviceOnline: true), .message("Still waiting."),
                       "no transaction to watch → just the words")
        // No answer speaks the one state language (EXPERIENCE.md §4, §7.3):
        // offline only when the phone has no network; otherwise it was ours.
        XCTAssertEqual(GiveRefusal.from(APIError.offline, deviceOnline: false),
                       .message("You're offline. Connect to the internet, then try again."))
        XCTAssertEqual(GiveRefusal.from(APIError.offline, deviceOnline: true),
                       .message("Something went wrong on our side. It isn't you — please try again in a moment."))
        XCTAssertEqual(GiveRefusal.from(URLError(.badURL), deviceOnline: true),
                       .message("Something went wrong on our side. It isn't you — please try again in a moment."))
    }

    func testErrorDetailsTolerateOddShapes() throws {
        let d = try decode(ErrorDetails.self,
            #"{"transaction_id":42,"password_required":"yes","max_age_seconds":900,"min_minor":100}"#)
        XCTAssertNil(d.transactionId, "an odd shape reads as absent — it never fails the error itself")
        XCTAssertNil(d.passwordRequired)
        XCTAssertEqual(d.maxAgeSeconds, 900)
        XCTAssertEqual(try decode(ErrorDetails.self, #"{"password_required":true}"#).passwordRequired, true,
                       "the step-up detail still reads")
    }
}
