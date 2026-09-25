// The first tests in the app pin its most load-bearing decoding contract:
// DTOs are tolerant per-field (one odd message must never blank a thread),
// but identities are strict (a row with no id is not a row). The decoder is
// configured exactly like APIClient's: snake_case in, camelCase out.
import XCTest
@testable import NuruMember

final class ModelDecodingTests: XCTestCase {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: ChatMessage

    func testChatMessageDecodesFullWirePayload() throws {
        let m = try decode(ChatMessage.self, """
        {"message_id":"m1","author_user_id":"u1","author_name":"Pastor",
         "body":"Grace and peace","msg_type":"text","is_edited":false,
         "created_at":"2026-07-17T01:00:00Z","mine":false,"reactions":[],
         "read_count":2,"recipient_count":60,"broadcast_id":"b1"}
        """)
        XCTAssertEqual(m.messageId, "m1")
        XCTAssertEqual(m.broadcastId, "b1", "broadcast_id is the mark that dresses a thread as Talk with Pastor")
        XCTAssertEqual(m.recipientCount, 60)
    }

    func testChatMessageToleratesAnEmptyObject() throws {
        // Tolerance is the contract: a malformed message decodes to defaults
        // instead of throwing and blanking the whole thread.
        let m = try decode(ChatMessage.self, "{}")
        XCTAssertEqual(m.messageId, "")
        XCTAssertEqual(m.msgType, "text")
        XCTAssertNil(m.broadcastId)
        XCTAssertTrue(m.reactions.isEmpty)
    }

    func testChatMessageWithoutBroadcastIdIsAPlainMessage() throws {
        let m = try decode(ChatMessage.self, #"{"message_id":"m2","body":"hi"}"#)
        XCTAssertNil(m.broadcastId)
    }

    // MARK: ChatConversation

    func testConversationDecodesWithOnlyItsIdentity() throws {
        let c = try decode(ChatConversation.self, #"{"conversation_id":"c1"}"#)
        XCTAssertEqual(c.conversationId, "c1")
        XCTAssertEqual(c.kind, "space")
        XCTAssertEqual(c.unread, 0)
        XCTAssertNil(c.peerUserId)
    }

    func testConversationWithoutIdentityRefusesToDecode() {
        XCTAssertThrowsError(try decode(ChatConversation.self, #"{"kind":"dm"}"#))
    }

    func testConversationUnreadAndPeerSurviveTheWire() throws {
        let c = try decode(ChatConversation.self,
            #"{"conversation_id":"c2","kind":"dm","unread":7,"peer_user_id":"u9"}"#)
        XCTAssertEqual(c.unread, 7, "the honest unread counter feeds the segment chips")
        XCTAssertEqual(c.peerUserId, "u9")
    }

    // MARK: ChatInbox

    func testInboxToleratesMissingSections() throws {
        let inbox = try decode(ChatInbox.self, "{}")
        XCTAssertTrue(inbox.conversations.isEmpty)
        XCTAssertTrue(inbox.discoverSpaces.isEmpty)
    }

    // MARK: Broadcast

    func testBroadcastDecodesWithOnlyItsIdentity() throws {
        let b = try decode(Broadcast.self, #"{"broadcast_id":"b1"}"#)
        XCTAssertEqual(b.broadcastId, "b1")
        XCTAssertEqual(b.audience, "all", "unspecified audience defaults to the whole church")
        XCTAssertEqual(b.seenCount, 0)
        XCTAssertEqual(b.repliedCount, 0)
    }

    func testBroadcastWithoutIdentityRefusesToDecode() {
        XCTAssertThrowsError(try decode(Broadcast.self, #"{"body":"hello"}"#))
    }

    func testBroadcastCountsDecodeFromTheWire() throws {
        let b = try decode(Broadcast.self, """
        {"broadcast_id":"b2","body":"Sunday!","audience":"congregation",
         "recipient_count":60,"seen_count":41,"replied_count":9,
         "created_at":"2026-07-16T09:00:00Z"}
        """)
        XCTAssertEqual(b.audience, "congregation")
        XCTAssertEqual(b.recipientCount, 60)
        XCTAssertEqual(b.seenCount, 41)
        XCTAssertEqual(b.repliedCount, 9)
    }
}

// MARK: - Statement v2

// Statement v2 (PARTNERS_PROGRAMME §3d) — the additive blocks on
// GET /giving/statements are decoded tolerantly: present → read, absent or
// null → nil (the Partners statement then hides the block), and an odd
// number shape (string, fractional) never throws. The decoder is configured
// exactly like APIClient's: snake_case in, camelCase out.

final class StatementV2DecodingTests: XCTestCase {

    private func decode(_ json: String) throws -> GivingStatements {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(GivingStatements.self, from: Data(json.utf8))
    }

    func testFullV2PayloadDecodes() throws {
        let s = try decode("""
        {"year":2026,"years":[2026],"total_minor":0,"currency":"KES",
         "impact":{"paid_minor":2200000,"per_disciple_minor":2000000,"disciples_carried":1,"toward_next_minor":200000},
         "months":[{"month":1,"status":"kept","due_minor":200000,"paid_minor":200000},
                   {"month":7,"status":"LATE","due_minor":200000,"paid_minor":200000},
                   {"month":10,"status":"upcoming","due_minor":200000,"paid_minor":0}],
         "faithfulness":{"kept_on_time":8,"late":1,"missed":1,"due_count":10},
         "season":{"from":"2026-01-10","levels_completed":4,"modules_completed":30,"plans_finished":12},
         "pledges":[{"pledge_id":"p1","title":"Building","shape":"total","remaining_year_minor":500000,"church_progress_percent":42.7}]}
        """)
        XCTAssertEqual(s.impact?.disciplesCarried, 1)
        XCTAssertEqual(s.impact?.towardNextMinor, 200000)
        XCTAssertEqual(s.impact?.perDiscipleMinor, 2000000)
        XCTAssertEqual(s.months?.count, 3)
        XCTAssertEqual(s.months?[1].month, 7)
        XCTAssertEqual(s.months?[1].status, "late", "status is lower-cased")
        XCTAssertEqual(s.faithfulness?.keptOnTime, 8)
        XCTAssertEqual(s.faithfulness?.dueCount, 10)
        XCTAssertEqual(s.season?.levelsCompleted, 4)
        XCTAssertEqual(s.season?.plansFinished, 12)
        XCTAssertEqual(s.pledges.first?.remainingYearMinor, 500000)
        XCTAssertEqual(s.pledges.first?.churchProgressPercent ?? -1, 42.7, accuracy: 0.001)
    }

    func testOlderServerLeavesEveryV2BlockNil() throws {
        let s = try decode(#"{"year":2026,"pledges":[{"pledge_id":"p1"}]}"#)
        XCTAssertNil(s.impact)
        XCTAssertNil(s.months)
        XCTAssertNil(s.faithfulness)
        XCTAssertNil(s.season)
        XCTAssertNil(s.pledges.first?.remainingYearMinor)
        XCTAssertNil(s.pledges.first?.churchProgressPercent)
    }

    func testNullsAndEmptyMonthsAreAbsent() throws {
        let s = try decode(#"{"impact":null,"months":[],"faithfulness":null,"season":null,"pledges":[{"pledge_id":"p1","church_progress_percent":null}]}"#)
        XCTAssertNil(s.impact)
        XCTAssertNil(s.months, "an empty strip is no strip")
        XCTAssertNil(s.season)
        XCTAssertNil(s.pledges.first?.churchProgressPercent)
    }

    func testOddNumberShapesAndTheTowardNextAlias() throws {
        let s = try decode("""
        {"impact":{"paid_minor":"600000","disciples_carried":0,"toward_next":600000.0},
         "months":[{"month":"2026-03","status":"missed"},{"month":"12","status":"kept"},{"status":"none"}],
         "faithfulness":{"kept_on_time":"2","due_count":3.0}}
        """)
        XCTAssertEqual(s.impact?.paidMinor, 600000, "a string number is read")
        XCTAssertEqual(s.impact?.disciplesCarried, 0, "0 is a value, not absent")
        XCTAssertEqual(s.impact?.towardNextMinor, 600000, "`toward_next` (the doc's name) is read too")
        XCTAssertEqual(s.months?[0].month, 3, "a yyyy-MM month is read")
        XCTAssertEqual(s.months?[1].month, 12)
        XCTAssertNil(s.months?[2].month, "no month → the strip places it by position")
        XCTAssertEqual(s.faithfulness?.keptOnTime, 2)
        XCTAssertEqual(s.faithfulness?.dueCount, 3)
        XCTAssertNil(s.faithfulness?.late)
    }

    func testPendingRowsDecodeAndStayOutOfTotals() throws {
        let s = try decode("""
        {"year":2026,"payments":[{"transaction_id":"t1","amount_minor":100000,"pledge_id":"p1","at":"2026-09-20T08:00:00Z"}],
         "pending":[{"transaction_id":"t2","amount_minor":100000,"currency":"KES","at":"2026-09-26T07:00:00Z",
                     "status":"processing","method":"mpesa","pledge_id":"p1","pledge_title":"General partnership"},
                    {"transaction_id":"t1","amount_minor":100000,"pledge_id":"p1","at":"2026-09-20T08:00:00Z"},
                    {"transaction_id":"t3","amount_minor":5000,"at":"2026-09-26T07:00:00Z"}]}
        """)
        XCTAssertEqual(s.pending.count, 3)
        XCTAssertEqual(s.pending.first?.method, "mpesa")
        XCTAssertEqual(s.pending.first?.pledgeTitle, "General partnership")
        let shown = s.pendingPledgePayments
        XCTAssertEqual(shown.map(\.transactionId), ["t2"],
                       "a row already settled, and a row with no pledge, are not Processing rows")
        XCTAssertEqual(PledgeMath.paidMinor(s), 100000, "a pending payment is never counted as paid")
    }

    func testPendingAbsentIsEmpty() throws {
        XCTAssertTrue(try decode(#"{"year":2026}"#).pending.isEmpty)
    }

    func testPaysToDecodesOnPledgeAndDueItem() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let pl = try d.decode(Pledge.self, from: Data(#"{"pledge_id":"p1","pays_to":{"code":"discipleship","name":"Discipleship"}}"#.utf8))
        XCTAssertEqual(pl.paysTo?.name, "Discipleship")
        let bare = try d.decode(Pledge.self, from: Data(#"{"pledge_id":"p1"}"#.utf8))
        XCTAssertNil(bare.paysTo, "an older server sends none — Give says 'Routed by the church'")
        let due = try d.decode(DueItem.self, from: Data(#"{"kind":"pledge","id":"p1","pays_to":{"code":"missions","name":"Missions"}}"#.utf8))
        XCTAssertEqual(due.paysTo?.code, "missions")
    }

    func testDuePendingMinorDecodesAndSplitsTheInstalment() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        func due(_ json: String) throws -> DueItem { try d.decode(DueItem.self, from: Data(json.utf8)) }
        let none = try due(#"{"kind":"pledge","id":"p1","amount_minor":100000,"action":"pay"}"#)
        XCTAssertEqual(none.pendingMinor, 0, "absent = 0")
        XCTAssertFalse(none.fullyPending)
        let part = try due(#"{"kind":"pledge","id":"p1","amount_minor":100000,"action":"pay","pending_minor":"40000"}"#)
        XCTAssertEqual(part.uncoveredMinor, 60000, "Pay covers only the remainder")
        XCTAssertFalse(part.fullyPending)
        let all = try due(#"{"kind":"pledge","id":"p1","amount_minor":100000,"action":"pay","pending_minor":100000}"#)
        XCTAssertTrue(all.fullyPending, "all of it on its way → Processing, no Pay")
        let resume = try due(#"{"kind":"pledge","id":"p1","amount_minor":100000,"action":"resume","pending_minor":100000}"#)
        XCTAssertFalse(resume.fullyPending, "a resume row is never a payment")
    }

    func testDueOverdueFieldsDecodeTolerantly() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let late = try d.decode(DueItem.self, from: Data(#"{"kind":"pledge","id":"p1","amount_minor":400000,"due_on":"2026-08-10","overdue_count":2,"overdue_since":"2026-08-10"}"#.utf8))
        XCTAssertEqual(late.overdueCount, 2)
        XCTAssertEqual(late.overdueSince, "2026-08-10")
        let plain = try d.decode(DueItem.self, from: Data(#"{"kind":"pledge","id":"p1","amount_minor":200000,"due_on":"2026-10-26"}"#.utf8))
        XCTAssertEqual(plain.overdueCount, 0, "absent = 0")
        XCTAssertNil(plain.overdueSince)
    }

    @MainActor
    func testRepeatLastGiftSkipsPledgeAndNeedGifts() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let rows = try d.decode([GivingRecord].self, from: Data("""
        [{"transaction_id":"t3","amount_minor":100000,"status":"succeeded","fund":"discipleship","pledge_id":"p1","created_at":"2026-09-26T08:00:00Z"},
         {"transaction_id":"t2","amount_minor":50000,"status":"succeeded","fund":"mission","need_id":"n1","created_at":"2026-09-25T08:00:00Z"},
         {"transaction_id":"t1","amount_minor":20000,"status":"succeeded","fund":"tithe","created_at":"2026-09-20T08:00:00Z"}]
        """.utf8))
        XCTAssertEqual(rows[1].needId, "n1")
        let vm = GivingViewModel()
        vm.history = rows
        XCTAssertEqual(vm.lastGift?.transactionId, "t1", "the last ORDINARY gift, never a pledge or need payment")
        vm.history = Array(rows.prefix(2))
        XCTAssertNil(vm.lastGift, "no ordinary gift → no Repeat card")
    }

    func testCompactAmountRoundsDownAndNeverOverstates() {
        XCTAssertEqual(PartnersStatementView.compactAmount(85_000), "850")
        XCTAssertEqual(PartnersStatementView.compactAmount(250_000), "2.5k")
        XCTAssertEqual(PartnersStatementView.compactAmount(299_999), "2.9k")
        XCTAssertEqual(PartnersStatementView.compactAmount(2_200_000), "22k")
        XCTAssertEqual(PartnersStatementView.compactAmount(1_999_999), "19k")
        XCTAssertEqual(PartnersStatementView.compactAmount(125_000_000), "1.2M")
        XCTAssertEqual(PartnersStatementView.compactAmount(-5), "0")
    }
}
