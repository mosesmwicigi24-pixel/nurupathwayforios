// Giving Cycle 6 — safe to give, pinned: the app's request keys are never in
// the server's own namespaces; a 429 RATE_LIMITED is said in the server's
// words and never sent again by itself; a 409 CONFLICT (the key is another
// gift's) spends the key so the member's next tap goes through; a resend's
// answer with no prompt ref yet is not an error; and a pledge is edited in
// its own currency — dollars with cents — its target sent as target_minor.
import XCTest
@testable import NuruMember

final class GivingCycle6Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> [String: Any] {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return try XCTUnwrap(JSONSerialization.jsonObject(with: e.encode(value)) as? [String: Any])
    }

    private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    // MARK: Request keys — never the server's

    func testTheAppsKeysAreNeverInTheServersNamespaces() {
        XCTAssertEqual(GiveKey.reservedPrefixes, ["sched:", "claim:", "pledge:", "web:", "website:", "office:"],
                       "the server's RESERVED_KEY, prefix for prefix")
        var seen = Set<String>()
        for _ in 0..<500 {
            let key = GiveKey.fresh()
            XCTAssertFalse(GiveKey.isReserved(key), key)
            XCTAssertFalse(key.contains(":"), "a UUID has no colon, so no namespace")
            XCTAssertTrue((8...255).contains(key.count), "the server takes 8–255 characters")
            XCTAssertNotNil(UUID(uuidString: key))
            seen.insert(key)
        }
        XCTAssertEqual(seen.count, 500, "never the same key twice")
        // The retry's next key is one of them too.
        let next = GiveRetry.key(after: nil, current: "used-key-0001")
        XCTAssertNotEqual(next, "used-key-0001")
        XCTAssertFalse(GiveKey.isReserved(next))
        XCTAssertNotNil(UUID(uuidString: next))
    }

    func testReservedKeysAreRecognisedAsTheServerRecognisesThem() {
        for key in ["sched:0000:first", "claim:1234", "pledge:abc", "web:x", "website:x", "office:x", "SCHED:x", "Website:x"] {
            XCTAssertTrue(GiveKey.isReserved(key), key)
        }
        for key in ["schedule-0001", "webhook-0001", "office-0001", "my-key:sched:", UUID().uuidString] {
            XCTAssertFalse(GiveKey.isReserved(key), key)
        }
    }

    // MARK: 429 RATE_LIMITED — the server's words; never sent again by itself

    func testARateLimitIsSaidInTheServersWordsAndNeverRetriedByItself() {
        let words = "We've sent several prompts to that number just now. Try again in 10 minutes, or give from your own number."
        let limited = APIError.http(status: 429, code: "RATE_LIMITED", message: words, details: nil)
        XCTAssertEqual(GiveRefusal.from(limited, fallback: "Something went wrong."), .message(words), "as the server said it")
        XCTAssertFalse(GiveRefusal.gotNoServerAnswer(limited), "an answer — the key is spent")
        XCTAssertEqual(GiveRetry.key(after: limited, current: "k-0001", fresh: { "k-0002" }), "k-0002")
        XCTAssertNil(GiveRetry.target(after: limited, retrying: "tx-1"),
                     "Try again goes back to the form — nothing is retried until the member chooses to")
        XCTAssertFalse(GiveRefusal.isKeyConflict(limited))
    }

    // MARK: 409 CONFLICT — the key is another gift's: a fresh one, and the next tap works

    func testAKeyConflictSpendsTheKeySoTheNextTapGoesThrough() {
        let conflict = APIError.http(status: 409, code: "CONFLICT", message: "That request key is already in use. Try again.", details: nil)
        XCTAssertTrue(GiveRefusal.isKeyConflict(conflict))
        XCTAssertEqual(GiveRetry.key(after: conflict, current: "k-0001", fresh: { "k-0002" }), "k-0002", "a fresh key")
        XCTAssertEqual(GiveRetry.target(after: conflict, retrying: "tx-1"), "tx-1",
                       "the gift itself was fine: the next Try again retries it with the fresh key")
        XCTAssertEqual(GiveRefusal.from(conflict, fallback: "x"), .message("That request key is already in use. Try again."),
                       "said once — never looped")

        // Other refusals are not key conflicts.
        let waiting = APIError.http(status: 409, code: "GIFT_IN_PROGRESS", message: "A prompt from a moment ago…", details: nil)
        let exists = APIError.http(status: 409, code: "SCHEDULE_EXISTS", message: "You already have one.", details: nil)
        let invalid = APIError.http(status: 422, code: "CONFLICT", message: "odd", details: nil)
        for e in [waiting, exists, invalid, APIError.offline] { XCTAssertFalse(GiveRefusal.isKeyConflict(e)) }
        XCTAssertNil(GiveRetry.target(after: exists, retrying: "tx-1"))
        XCTAssertEqual(GiveRetry.target(after: APIError.offline, retrying: "tx-1"), "tx-1", "no answer: the same gift, the same key")
        XCTAssertEqual(GiveRetry.key(after: APIError.offline, current: "k-0001", fresh: { "k-0002" }), "k-0001")
    }

    // MARK: A resend's answer — the prompt ref may not be known yet

    func testAResendWithNoPromptRefYetIsStillTheGift() throws {
        let sending = try decode(GivingIntentResult.self, #"""
        {"transaction_id":"t-1","status":"processing","provider":"mpesa","provider_ref":null,
         "idempotency_key":"k-0001","reused":true,"fund":{"code":"tithe","name":"Tithe"}}
        """#)
        XCTAssertEqual(sending.transactionId, "t-1", "watched by its transaction id")
        XCTAssertEqual(sending.provider, "mpesa")
        XCTAssertNil(sending.providerRef, "null while the prompt is still being sent — not an error")
        XCTAssertTrue(sending.reused)
        XCTAssertEqual(sending.fund?.name, "Tithe")

        let sent = try decode(GivingIntentResult.self, #"{"transaction_id":"t-1","status":"processing","provider":"mpesa","provider_ref":"ws_CO_1","reused":true}"#)
        XCTAssertEqual(sent.providerRef, "ws_CO_1", "once it is known")

        let older = try decode(GivingIntentResult.self, #"{"transaction_id":"t-1","status":"processing","reused":true}"#)
        XCTAssertNil(older.provider, "an older server's replay says neither")
        XCTAssertNil(older.providerRef)
    }

    // MARK: A pledge edited in its own currency

    func testADollarPledgeIsEditedInDollarsAndCents() throws {
        let monthly = try decode(Pledge.self, #"{"pledge_id":"u1","shape":"monthly","amount_minor":2050,"currency":"USD","due_day":5,"status":"active"}"#)
        XCTAssertEqual(MoneyEntry.prefix(monthly.currency), "US$", "never KSh")
        XCTAssertEqual(MoneyEntry.display(monthly.commitmentMinor, currency: monthly.currency), "20.50", "cents kept")
        XCTAssertEqual(PledgeAmountEdit.presets("USD"), UsdEntry.presetsCents, "Give's dollar amounts")

        let typed = MoneyEntry.sanitize("25.755", currency: "USD")
        XCTAssertEqual(typed, "25.75")
        let minor = try XCTUnwrap(MoneyEntry.minor(typed, currency: "USD"))
        XCTAssertEqual(minor, 2_575)
        XCTAssertEqual(PledgeAmountEdit.changed(minor, from: monthly), 2_575)

        let body = MemberAPI.PledgePatchBody.edit(monthly, commitmentMinor: 2_575, dueDay: 12, title: nil)
        let json = try encoded(body)
        XCTAssertEqual(json["amount_minor"] as? Int, 2_575, "US cents, as typed")
        XCTAssertEqual(json["due_day"] as? Int, 12)
        XCTAssertNil(json["target_minor"])
        XCTAssertNil(json["title"], "an untouched name is not sent")
    }

    func testATotalPledgesNewTargetIsSentAsItsTarget() throws {
        let usdTotal = try decode(Pledge.self, #"{"pledge_id":"u2","shape":"total","target_minor":150000,"currency":"USD","due_on":"2026-12-01","status":"active"}"#)
        let minor = try XCTUnwrap(MoneyEntry.minor(MoneyEntry.sanitize("1600.5", currency: "USD"), currency: "USD"))
        XCTAssertEqual(minor, 160_050)
        let json = try encoded(MemberAPI.PledgePatchBody.edit(usdTotal, commitmentMinor: minor, dueDay: 9, title: nil))
        XCTAssertEqual(json["target_minor"] as? Int, 160_050, "a total's promise is its target")
        XCTAssertNil(json["amount_minor"], "never amount_minor on a total pledge — its target would never move")
        XCTAssertNil(json["due_day"], "a total pledge has no due day")

        let kesTotal = try decode(Pledge.self, #"{"pledge_id":"k2","shape":"total","target_minor":5000000,"currency":"KES","due_on":"2026-12-01","status":"active"}"#)
        let kes = try encoded(MemberAPI.PledgePatchBody.edit(kesTotal, commitmentMinor: 6_000_000, dueDay: nil, title: .clear))
        XCTAssertEqual(kes["target_minor"] as? Int, 6_000_000)
        XCTAssertNil(kes["amount_minor"])
        XCTAssertTrue(kes["title"] is NSNull, "clearing the name is an explicit null")
    }

    func testAShillingPledgeStaysInWholeShillings() throws {
        let kes = try decode(Pledge.self, #"{"pledge_id":"k1","shape":"monthly","amount_minor":200000,"currency":"KES","due_day":5,"status":"active"}"#)
        XCTAssertEqual(MoneyEntry.prefix(kes.currency), "KSh")
        XCTAssertEqual(MoneyEntry.display(200_000, currency: "KES"), grouped(2000))
        XCTAssertEqual(MoneyEntry.display(150_050, currency: "KES"), "\(grouped(1500)).50", "an older amount with cents is shown as it is")
        XCTAssertEqual(PledgeAmountEdit.presets("KES"), [50_000, 100_000, 200_000, 500_000, 1_000_000, 2_000_000])
        XCTAssertEqual(MoneyEntry.sanitize("2,500", currency: "KES"), "2500")
        XCTAssertNil(MoneyEntry.minor("2500.50", currency: "KES"), "no cents on a shilling pledge")

        XCTAssertNil(PledgeAmountEdit.changed(200_000, from: kes), "the same amount is left as it is")
        XCTAssertNil(PledgeAmountEdit.changed(0, from: kes), "zero is not a promise")
        let json = try encoded(MemberAPI.PledgePatchBody.edit(kes, commitmentMinor: 250_000, dueDay: nil, title: .set("School fees")))
        XCTAssertEqual(json["amount_minor"] as? Int, 250_000)
        XCTAssertEqual(json["title"] as? String, "School fees")
        XCTAssertNil(json["target_minor"])
    }
}
