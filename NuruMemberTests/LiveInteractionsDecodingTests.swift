// Nuru Live L5 — pins the interactive-stage wire contract from
// docs/LIVE_INTERACTIVE.md the same way ModelDecodingTests pins chat: every
// DTO must tolerate a missing/malformed field (the backend is being built to
// this same pinned doc in parallel, so a field arriving late or renamed must
// never crash the overlay) without losing the fields that ARE present.
import XCTest
@testable import NuruMember

final class LiveInteractionsDecodingTests: XCTestCase {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: LiveChatMessage / LiveMessagesEnvelope

    func testLiveChatMessageDecodesFullWirePayload() throws {
        let m = try decode(LiveChatMessage.self, """
        {"message_id":"m1","user_id":"u1","full_name":"Pastor John",
         "avatar_url":"https://cdn/a.jpg","body":"Welcome everyone!",
         "sent_at":"2026-07-31T09:00:00Z"}
        """)
        XCTAssertEqual(m.messageId, "m1")
        XCTAssertEqual(m.userId, "u1")
        XCTAssertEqual(m.fullName, "Pastor John")
        XCTAssertEqual(m.body, "Welcome everyone!")
    }

    func testLiveChatMessageToleratesAnEmptyObject() throws {
        let m = try decode(LiveChatMessage.self, "{}")
        XCTAssertEqual(m.fullName, "Member")
        XCTAssertEqual(m.body, "")
        XCTAssertNil(m.avatarUrl)
    }

    func testLiveMessagesEnvelopeToleratesMissingArray() throws {
        let env = try decode(LiveMessagesEnvelope.self, "{}")
        XCTAssertTrue(env.messages.isEmpty)
    }

    func testLiveMessagesEnvelopeDecodesAscendingList() throws {
        let env = try decode(LiveMessagesEnvelope.self, """
        {"messages":[{"message_id":"m1","user_id":"u1","full_name":"A","body":"hi","sent_at":"2026-07-31T09:00:00Z"},
                      {"message_id":"m2","user_id":"u2","full_name":"B","body":"hey","sent_at":"2026-07-31T09:00:05Z"}]}
        """)
        XCTAssertEqual(env.messages.count, 2)
        XCTAssertEqual(env.messages.last?.messageId, "m2")
    }

    // MARK: LivePulse — the one poll for the whole interactive overlay

    func testLivePulseToleratesAnEmptyObject() throws {
        let p = try decode(LivePulse.self, "{}")
        XCTAssertEqual(p.viewerCount, 0)
        XCTAssertEqual(p.reactions.like, 0)
        XCTAssertEqual(p.reactions.love, 0)
        XCTAssertTrue(p.recentReactions.isEmpty)
        XCTAssertTrue(p.hands.isEmpty)
        XCTAssertTrue(p.guests.isEmpty)
    }

    func testLivePulseDecodesFullWirePayload() throws {
        let p = try decode(LivePulse.self, """
        {"viewer_count":42,"reactions":{"like":10,"love":7,"fire":3},
         "recent_reactions":[{"emoji":"love","at":"2026-07-31T09:00:01Z"}],
         "hands":[{"user_id":"u1","full_name":"Grace","avatar_url":null,"raised_at":"2026-07-31T09:00:00Z"}],
         "guests":[{"user_id":"u2","full_name":"Sam","avatar_url":null,"status":"accepted"}]}
        """)
        XCTAssertEqual(p.viewerCount, 42)
        XCTAssertEqual(p.reactions.like, 10)
        XCTAssertEqual(p.reactions.love, 7)
        XCTAssertEqual(p.reactions.fire, 3)
        XCTAssertEqual(p.recentReactions.first?.emoji, "love")
        XCTAssertEqual(p.hands.first?.fullName, "Grace")
        XCTAssertEqual(p.guests.first?.status, "accepted")
        XCTAssertTrue(p.guests.first?.isActive == true)
    }

    /// The backend added `fire` as a third reaction kind alongside like/love
    /// AFTER L5 shipped (owner ask, 2026-07-31) — a pulse response from
    /// before that must still decode cleanly, with `fire` defaulting to 0
    /// rather than the whole payload failing.
    func testLiveReactionCountsTreatsFireAsOptional() throws {
        let counts = try decode(LiveReactionCounts.self, #"{"like":5,"love":2}"#)
        XCTAssertEqual(counts.like, 5)
        XCTAssertEqual(counts.love, 2)
        XCTAssertEqual(counts.fire, 0)
    }

    func testLiveReactionKindMapsFireEmojiAndRoundTrips() {
        XCTAssertEqual(LiveReactionKind(emoji: "fire").emoji, "fire")
        XCTAssertEqual(LiveReactionKind(emoji: "love").emoji, "love")
        // An unrecognized/legacy emoji string falls back to "like" rather
        // than crashing the reaction rail or the particle overlay.
        XCTAssertEqual(LiveReactionKind(emoji: "🤷").emoji, "like")
    }

    func testLiveGuestRowIsActiveOnlyWhileInvitedOrAccepted() throws {
        let removed = try decode(LiveGuestRow.self, #"{"user_id":"u1","status":"removed"}"#)
        XCTAssertFalse(removed.isActive)
        let invited = try decode(LiveGuestRow.self, #"{"user_id":"u1","status":"invited"}"#)
        XCTAssertTrue(invited.isActive)
    }

    // MARK: LiveHandRow — defaults a missing name rather than blanking the row

    func testLiveHandRowDefaultsAMissingName() throws {
        let h = try decode(LiveHandRow.self, #"{"user_id":"u1"}"#)
        XCTAssertEqual(h.userId, "u1")
        XCTAssertEqual(h.fullName, "Member")
    }

    // MARK: LiveCountFormat — the rail's TikTok-style abbreviated counters

    func testLiveCountFormatAbbreviatesLikeTikTok() {
        XCTAssertEqual(LiveCountFormat.abbreviated(0), "0")
        XCTAssertEqual(LiveCountFormat.abbreviated(999), "999")
        XCTAssertEqual(LiveCountFormat.abbreviated(1200), "1.2K")
        XCTAssertEqual(LiveCountFormat.abbreviated(10_000), "10K")
        XCTAssertEqual(LiveCountFormat.abbreviated(3_400_000), "3.4M")
    }
}
