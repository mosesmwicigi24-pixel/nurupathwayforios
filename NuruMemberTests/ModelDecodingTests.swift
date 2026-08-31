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

    // MARK: LiveStreamSummary — the CDN failover path
    //
    // `hls_fallback_url` is the direct-origin playlist the server sends
    // ALONGSIDE a CDN `hls_url` (live/service.ts). The viewer opens on it and
    // swaps to the CDN copy after a warm-up, so a just-started broadcast is
    // never served the edge's cached copy of the PREVIOUS one. Dropping the
    // field on the floor silently reinstates that flicker.

    func testLiveStreamCarriesTheDirectOriginFallback() throws {
        let s = try decode(LiveStreamSummary.self, """
        {"stream_id":"s1","scope":"church","title":"Sunday Service","kind":"video",
         "started_at":"2026-08-30T09:00:00Z",
         "hls_url":"https://cdn.example.org/live-cdn/church/index.m3u8",
         "hls_fallback_url":"/live/church/index.m3u8",
         "started_by_name":"Pastor","viewer_count":12}
        """)
        XCTAssertEqual(s.hlsFallbackUrl, "/live/church/index.m3u8")
        XCTAssertEqual(LivePlayableItem.live(s).mediaFallbackPath, "/live/church/index.m3u8")
    }

    /// No CDN configured — the server sends no fallback at all, and the player
    /// must simply open on hls_url.
    func testLiveStreamWithoutACdnHasNoFallback() throws {
        let s = try decode(LiveStreamSummary.self, """
        {"stream_id":"s2","scope":"cell","title":"Cell prayer","kind":"audio",
         "started_at":"2026-08-30T18:00:00Z","hls_url":"/live/cell-1/index.m3u8",
         "started_by_name":"Mary","viewer_count":3}
        """)
        XCTAssertNil(s.hlsFallbackUrl)
        XCTAssertNil(LivePlayableItem.live(s).mediaFallbackPath)
    }

    /// A recording races no mirror, so it never carries a fallback.
    func testRecordingHasNoFallbackPath() throws {
        let r = try decode(LiveRecordingRow.self, """
        {"stream_id":"s3","scope":"church","title":"Last Sunday","kind":"video",
         "started_at":"2026-08-23T09:00:00Z","ended_at":"2026-08-23T11:00:00Z",
         "recording_url":"/media/rec-3.m3u8"}
        """)
        XCTAssertNil(LivePlayableItem.recording(r).mediaFallbackPath)
    }
}
