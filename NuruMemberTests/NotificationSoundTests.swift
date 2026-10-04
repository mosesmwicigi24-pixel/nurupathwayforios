// Notification sounds (owner, 2026-09-28: "a beep sound … or vibrations on any
// message that comes in", a place to mute it, and calls that ring), pinned:
// how a push's `nuru_kind` / `nuru_sound` read — and what a push from an older
// server reads as; what the app does with one that lands while it is open (the
// open conversation, another conversation, muted, a ring, a ring that missed
// its 30 s); the ring's clock, and an answered invite's second copy; the sound
// a local notification makes; the Sound and vibration preference on the wire;
// and the invite's words.
import UserNotifications
import XCTest
@testable import NuruMember

final class NotificationSoundTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    /// The exact keys of a ring push beside `aps` (the coordinator's contract).
    private var ringUserInfo: [AnyHashable: Any] {
        [
            "aps": ["alert": ["title": "You're invited to go live",
                              "body": "You've been invited to join \"Sunday service\" as a guest."],
                    "sound": "nuru_ring.caf"],
            "stream_id": "st-1",
            "title": "Sunday service",
            "template": "live_guest_invite",
            "nuru_kind": "ring",
            "nuru_sound": "on",
            "alert_title": "You're invited to go live",
            "alert_body": "You've been invited to join \"Sunday service\" as a guest.",
            "body": "You've been invited to join \"Sunday service\" as a guest.",
        ]
    }

    private func message(_ conversation: String?, sound: String = "on") -> NuruPush {
        var info: [AnyHashable: Any] = ["template": "chat_dm_message", "nuru_kind": "message", "nuru_sound": sound,
                                        "title": "Grace", "body": "See you Sunday"]
        if let conversation { info["conversation_id"] = conversation }
        return NuruPush(userInfo: info, deliveredAt: now)
    }

    // MARK: Reading a push

    func testAMessagePushReadsItsKindSoundAndConversation() {
        let p = message("c-1", sound: "off")
        XCTAssertEqual(p.kind, .message)
        XCTAssertFalse(p.soundOn)
        XCTAssertEqual(p.conversationId, "c-1")
        XCTAssertEqual(p.template, "chat_dm_message")
    }

    func testARingPushReadsItsStreamItsNameAndTheInviteWords() {
        let p = NuruPush(userInfo: ringUserInfo, deliveredAt: now)
        XCTAssertEqual(p.kind, .ring)
        XCTAssertTrue(p.soundOn)
        XCTAssertEqual(p.streamId, "st-1")
        XCTAssertEqual(p.title, "Sunday service")
        XCTAssertEqual(p.alertTitle, "You're invited to go live")
        XCTAssertEqual(p.alertBody, "You've been invited to join \"Sunday service\" as a guest.")
        XCTAssertEqual(p.ringStartedAt, now, "a push carries no send time — its ring runs from delivery")
    }

    func testAPushFromAnOlderServerReadsItsKindOffTheTemplateAndSounds() {
        XCTAssertEqual(NuruPush(userInfo: ["template": "chat_pastoral_message"]).kind, .message)
        XCTAssertEqual(NuruPush(userInfo: ["template": "live_guest_invite"]).kind, .ring)
        XCTAssertEqual(NuruPush(userInfo: ["template": "badge_awarded"]).kind, .update)
        XCTAssertEqual(NuruPush(userInfo: [:]).kind, .update)
        XCTAssertTrue(NuruPush(userInfo: ["template": "badge_awarded"]).soundOn, "no nuru_sound: it sounds, as before")
    }

    func testAKindThisAppDoesNotKnowFallsBackToTheTemplate() {
        let p = NuruPush(userInfo: ["template": "chat_broadcast", "nuru_kind": "shout"])
        XCTAssertEqual(p.kind, .message)
    }

    func testTheKindRuleIsTheServers() {
        for t in ["chat_dm_message", "chat_discipler_message", "chat_pastoral_message", "chat_broadcast"] {
            XCTAssertEqual(NuruPushKind.of(template: t), .message, t)
        }
        XCTAssertEqual(NuruPushKind.of(template: "live_guest_invite"), .ring)
        XCTAssertEqual(NuruPushKind.of(template: "live_stream_started"), .update)
        XCTAssertEqual(NuruPushKind.of(template: "giving_receipt"), .update)
    }

    func testALocalNotificationReadsItsInboxRowAndTheServersSendTime() throws {
        let p = NuruPush(userInfo: [
            "notificationId": "n-9", "template": "live_guest_invite", "nuru_kind": "ring", "nuru_sound": "off",
            "stream_id": "st-2", "conversation_id": "", "nuru_sent_at": "2026-09-28T13:41:50.123Z",
        ], deliveredAt: now)
        XCTAssertEqual(p.notificationId, "n-9")
        XCTAssertNil(p.conversationId, "an empty key reads as absent")
        XCTAssertFalse(p.soundOn)
        let sent = try XCTUnwrap(ISO8601DateFormatter.nuru.date(from: "2026-09-28T13:41:50.123Z"))
        XCTAssertEqual(p.ringStartedAt, sent, "the server's send time beats the local post time")
    }

    func testATappedNotificationsDeliveryTimeRunsItsRing() {
        let delivered = now.addingTimeInterval(-12)
        var info = ringUserInfo
        info[NuruPush.deliveredAtKey] = delivered
        XCTAssertEqual(NuruPush(userInfo: info).ringStartedAt, delivered)
    }

    // MARK: While the app is open

    func testAMessageForTheOpenConversationIsALightTapNotABanner() {
        let shown = message("c-1").foreground(openConversationId: "c-1", now: now)
        XCTAssertEqual(shown, .quiet(tap: true))
        XCTAssertEqual(shown.options, [])
    }

    func testAMessageForAnotherConversationShowsAndSounds() {
        let shown = message("c-2").foreground(openConversationId: "c-1", now: now)
        XCTAssertEqual(shown, .show(sound: true))
        XCTAssertEqual(shown.options, [.banner, .list, .badge, .sound])
        XCTAssertEqual(message("c-2").foreground(openConversationId: nil, now: now), .show(sound: true))
        XCTAssertEqual(message(nil).foreground(openConversationId: "c-1", now: now), .show(sound: true))
    }

    func testMutedNotificationsStillShowButMakeNoSoundAndNoTap() {
        let other = message("c-2", sound: "off").foreground(openConversationId: "c-1", now: now)
        XCTAssertEqual(other, .show(sound: false))
        XCTAssertEqual(other.options, [.banner, .list, .badge])
        XCTAssertEqual(message("c-1", sound: "off").foreground(openConversationId: "c-1", now: now), .quiet(tap: false))
        let update = NuruPush(userInfo: ["template": "badge_awarded", "nuru_kind": "update", "nuru_sound": "off"])
        XCTAssertEqual(update.foreground(openConversationId: nil, now: now), .show(sound: false))
    }

    func testAnUpdateShowsAndSounds() {
        let update = NuruPush(userInfo: ["template": "event_reminder_1h", "nuru_kind": "update", "nuru_sound": "on"])
        XCTAssertEqual(update.foreground(openConversationId: "c-1", now: now), .show(sound: true))
    }

    func testARingRingsInsteadOfABanner() {
        let shown = NuruPush(userInfo: ringUserInfo, deliveredAt: now).foreground(openConversationId: nil, now: now.addingTimeInterval(2))
        XCTAssertEqual(shown, .ring)
        XCTAssertEqual(shown.options, [], "no banner, and not the push's own 26 s sound")
    }

    func testAMutedRingStillTakesTheScreen() {
        var info = ringUserInfo
        info["nuru_sound"] = "off"
        XCTAssertEqual(NuruPush(userInfo: info, deliveredAt: now).foreground(openConversationId: nil, now: now), .ring,
                       "muted, the invite still comes up — silently")
    }

    func testARingThatMissedItsThirtySecondsIsAQuietBanner() {
        let late = NuruPush(userInfo: ringUserInfo, deliveredAt: now.addingTimeInterval(-31))
        XCTAssertEqual(late.foreground(openConversationId: nil, now: now), .show(sound: false))
    }

    func testARingWithoutAStreamCannotRing() {
        var info = ringUserInfo
        info["stream_id"] = nil
        XCTAssertEqual(NuruPush(userInfo: info, deliveredAt: now).foreground(openConversationId: nil, now: now), .show(sound: false))
    }

    // MARK: The ring's clock

    func testTheRingRunsThirtySecondsFromTheInvite() {
        XCTAssertEqual(NuruRing.remaining(since: now, now: now), 30)
        XCTAssertEqual(NuruRing.remaining(since: now, now: now.addingTimeInterval(12)), 18)
        XCTAssertEqual(NuruRing.remaining(since: now, now: now.addingTimeInterval(29.5)), 0.5, accuracy: 0.0001)
        XCTAssertEqual(NuruRing.remaining(since: now, now: now.addingTimeInterval(30)), 0)
        XCTAssertEqual(NuruRing.remaining(since: now, now: now.addingTimeInterval(300)), 0)
    }

    func testAPhoneClockBehindTheServersNeverRingsLonger() {
        XCTAssertEqual(NuruRing.remaining(since: now.addingTimeInterval(8), now: now), 30)
    }

    func testItBuzzesEveryOneAndAHalfSecondsUntilTheWindowCloses() {
        let full = NuruRing.buzzOffsets(remaining: 30)
        XCTAssertEqual(full.count, 20)
        XCTAssertEqual(full.first, 0)
        XCTAssertEqual(full.last, 28.5)
        XCTAssertEqual(NuruRing.buzzOffsets(remaining: 2), [0, 1.5])
        XCTAssertEqual(NuruRing.buzzOffsets(remaining: 0), [])
        XCTAssertEqual(NuruRing.buzzOffsets(remaining: 90).count, 20, "never past the 30 s window")
    }

    func testItRingsWholeRingsEveryFourSecondsNonePastTheWindow() {
        XCTAssertEqual(NuruRing.ringOffsets(remaining: 30), [0, 4, 8, 12, 16, 20, 24, 28])
        XCTAssertEqual(NuruRing.ringOffsets(remaining: 5.3), [0, 4])
        XCTAssertEqual(NuruRing.ringOffsets(remaining: 5.1), [0], "a ring at 4 s would run past 5.1")
        XCTAssertEqual(NuruRing.ringOffsets(remaining: 1), [], "too little left for one whole ring — the buzz still says it")
        XCTAssertEqual(NuruRing.ringOffsets(remaining: 0), [])
    }

    func testAnAnsweredInviteDoesNotRingAgainWhenItsOtherCopyLands() {
        let answered = ["st-1": now]
        XCTAssertTrue(NuruRing.isEcho(of: "st-1", answered: answered, now: now.addingTimeInterval(2)),
                      "its push answered, then its inbox copy on the next sync")
        XCTAssertTrue(NuruRing.isEcho(of: "st-1", answered: answered, now: now.addingTimeInterval(29)))
        XCTAssertFalse(NuruRing.isEcho(of: "st-1", answered: answered, now: now.addingTimeInterval(30)),
                       "by then any copy of that invite is past its own 30 s")
        XCTAssertFalse(NuruRing.isEcho(of: "st-2", answered: answered, now: now), "another stream's invite rings")
        XCTAssertFalse(NuruRing.isEcho(of: "st-1", answered: [:], now: now))
    }

    // MARK: A local notification's sound

    func testALocalNotificationSoundsByItsKind() {
        XCTAssertEqual(NuruPush.localSound(kind: .message, soundOn: true, ringing: false), .standard)
        XCTAssertEqual(NuruPush.localSound(kind: .update, soundOn: true, ringing: true), .standard)
        XCTAssertEqual(NuruPush.localSound(kind: .ring, soundOn: true, ringing: true), .ring)
        XCTAssertEqual(NuruPush.localSound(kind: .ring, soundOn: true, ringing: false), .none, "a missed invite arrives quietly")
        for kind in [NuruPushKind.message, .update, .ring] {
            XCTAssertEqual(NuruPush.localSound(kind: kind, soundOn: false, ringing: true), .none, "\(kind) muted")
        }
        XCTAssertNotNil(NuruPushSound.ring.notificationSound)
        XCTAssertNil(NuruPushSound.none.notificationSound)
    }

    // MARK: The preference on the wire

    private func decodePrefs(_ json: String) throws -> NotificationPreferences {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(NotificationPreferences.self, from: Data(json.utf8))
    }

    func testSoundIsOnWhenTheServerSaysNothing() throws {
        let p = try decodePrefs(#"{"push_enabled":true,"email_enabled":false,"sms_enabled":false}"#)
        XCTAssertTrue(p.soundEnabled)
        XCTAssertFalse(p.emailEnabled)
    }

    func testAMutedMemberReadsAsMuted() throws {
        let p = try decodePrefs(#"{"push_enabled":true,"email_enabled":true,"sms_enabled":false,"sound_enabled":false}"#)
        XCTAssertFalse(p.soundEnabled)
    }

    func testTheSaveSendsSoundWithTheThreeChannels() throws {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        let body = NotificationPreferences(pushEnabled: true, emailEnabled: false, smsEnabled: true, soundEnabled: false)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: e.encode(body)) as? [String: Bool])
        XCTAssertEqual(json, ["push_enabled": true, "email_enabled": false, "sms_enabled": true, "sound_enabled": false])
    }

    // MARK: The inbox and the invite's words

    func testAnInboxRowCarriesItsConversationAndStream() throws {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let row = try d.decode(NotificationRow.self, from: Data(#"""
        {"notification_id":"n-1","template":"live_guest_invite","status":"sent","scheduled_for":"2026-09-28T13:41:50.000Z",
         "sent_at":"2026-09-28T13:41:51.000Z","read_at":null,"payload":{"stream_id":"st-1","title":"Sunday service"}}
        """#.utf8))
        XCTAssertEqual(row.payload?.streamId, "st-1")
        XCTAssertEqual(row.payload?.title, "Sunday service")
        let chat = try d.decode(NotifPayload.self, from: Data(#"{"conversation_id":"c-1","title":"Grace","body":"Hi"}"#.utf8))
        XCTAssertEqual(chat.conversationId, "c-1")
    }

    func testTheInviteWordsAreTheServersOwn() {
        XCTAssertEqual(LiveInviteCopy.heading, "You're invited to go live")
        XCTAssertEqual(LiveInviteCopy.message(streamTitle: "Sunday service"),
                       "You've been invited to join \"Sunday service\" as a guest.")
        XCTAssertEqual(LiveInviteCopy.message(streamTitle: nil), "You've been invited to join a live broadcast as a guest.")
        XCTAssertEqual(LiveInviteCopy.message(streamTitle: ""), "You've been invited to join a live broadcast as a guest.")
    }

    // MARK: The open conversation

    @MainActor
    func testOnlyTheThreadThatMarkedItselfClearsTheMark() {
        OpenConversation.opened("c-1")
        OpenConversation.opened("c-2")      // B pushed over A: B's appear first…
        OpenConversation.closed("c-1")      // …then A's disappear — B stays open
        XCTAssertEqual(OpenConversation.id, "c-2")
        OpenConversation.closed("c-2")
        XCTAssertNil(OpenConversation.id)
    }
}
