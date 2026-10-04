// How a notification sounds and shows — the member app's half of the push
// contract the server set on 2026-09-28 (pathway dispatch.ts `fcmMessage`),
// after the owner asked for "a beep sound … or vibrations on any message that
// comes in", a place to mute it, and calls that ring. Every push carries
// `template`, `nuru_kind` ("message" | "update" | "ring") and `nuru_sound`
// ("on" | "off") beside `aps`. APNs plays the server's sound — "default", the
// bundled nuru_ring.caf for a ring, none for a member who muted — and this
// file decides what the app does with one that lands while it is OPEN:
//   • a message in the conversation on screen: no banner, no sound, a light tap;
//   • a Live guest invite: the full-screen incoming invite, ringing for 30 s;
//   • anything else: banner, list and badge, sounding only when it's "on".
// The local notifications LocalNotifier posts from the inbox carry the same
// keys, so one set of rules covers both. Pure — pinned by NotificationSoundTests.
import Foundation
import UserNotifications

/// What a notification is, for sound: a chat message, a Live guest invite
/// that rings like a call, or any other update. The server's `pushKind()`.
enum NuruPushKind: String, Sendable {
    case message, update, ring

    static func of(template: String) -> NuruPushKind {
        if template == "live_guest_invite" { return .ring }
        if template.hasPrefix("chat_") { return .message }
        return .update
    }
}

/// The keys of one push (or local notification) the app reads to show it.
/// Tolerant: a push from a server that predates them reads its kind off
/// `template` and sounds, as every foreground notification did before.
struct NuruPush: Equatable, Sendable {
    /// Settings' Sound and vibration switch, cached on the phone (the server's
    /// `sound_enabled` is the truth; this stands in when it can't answer).
    static let soundPrefKey = "nuru.notif.sound"
    /// The ring the server names as a ring push's APNs sound — bundled, ≤ 30 s.
    static let ringSoundName = "nuru_ring.caf"
    /// Set by LocalNotifier on a tapped notification's userInfo: when iOS
    /// delivered it (a tap can land long after — the ring's 30 s run from here).
    static let deliveredAtKey = "nuru_delivered_at"

    var template: String
    var kind: NuruPushKind
    /// `nuru_sound` — off only when the member muted Sound and vibration.
    var soundOn: Bool
    var conversationId: String?
    var streamId: String?
    /// A ring's `title` — the STREAM's name.
    var title: String?
    /// A ring's invite words (`alert_title` / `alert_body`).
    var alertTitle: String?
    var alertBody: String?
    /// The inbox row a local notification was posted from (`notificationId`).
    var notificationId: String?
    /// When the invite started ringing: `nuru_sent_at` on a local notification
    /// (the server's send time — the app may open minutes after the invite),
    /// else when iOS delivered it.
    var ringStartedAt: Date?

    init(template: String, kind: NuruPushKind? = nil, soundOn: Bool = true,
         conversationId: String? = nil, streamId: String? = nil, title: String? = nil,
         alertTitle: String? = nil, alertBody: String? = nil, notificationId: String? = nil,
         ringStartedAt: Date? = nil) {
        self.template = template
        self.kind = kind ?? NuruPushKind.of(template: template)
        self.soundOn = soundOn
        self.conversationId = conversationId
        self.streamId = streamId
        self.title = title
        self.alertTitle = alertTitle
        self.alertBody = alertBody
        self.notificationId = notificationId
        self.ringStartedAt = ringStartedAt
    }

    init(userInfo: [AnyHashable: Any], deliveredAt: Date? = nil) {
        // A real push's keys are the notification's own (snake_case); the
        // local ones LocalNotifier posts are camelCase for its routing ids.
        func string(_ keys: String...) -> String? {
            for key in keys {
                if let s = userInfo[key] as? String, !s.isEmpty { return s }
            }
            return nil
        }
        let template = string("template") ?? ""
        let sentAt = string("nuru_sent_at").flatMap {
            ISO8601DateFormatter.nuru.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
        }
        self.init(
            template: template,
            kind: string("nuru_kind").flatMap(NuruPushKind.init(rawValue:)),
            soundOn: string("nuru_sound") != "off",
            conversationId: string("conversation_id", "conversationId"),
            streamId: string("stream_id", "streamId"),
            title: string("title"),
            alertTitle: string("alert_title"),
            alertBody: string("alert_body"),
            notificationId: string("notificationId", "notification_id"),
            ringStartedAt: sentAt ?? (userInfo[Self.deliveredAtKey] as? Date) ?? deliveredAt)
    }

    /// What to do with this notification when it lands while the app is open.
    func foreground(openConversationId: String?, now: Date) -> NuruForeground {
        switch kind {
        case .ring:
            // A ring needs its stream and time left on the clock. One that
            // can't ring (the app opened a minute after the invite) shows as
            // a quiet banner — a missed call, not a 26-second ring.
            guard streamId != nil,
                  NuruRing.remaining(since: ringStartedAt ?? now, now: now) > 0 else { return .show(sound: false) }
            return .ring
        case .message:
            if let open = openConversationId, open == conversationId { return .quiet(tap: soundOn) }
            return .show(sound: soundOn)
        case .update:
            return .show(sound: soundOn)
        }
    }

    /// The sound a LOCAL notification makes — the server's rule for a push:
    /// the default sound, the ring for a Live invite with time left on its
    /// clock, and none for a member who muted (or an invite already missed).
    static func localSound(kind: NuruPushKind, soundOn: Bool, ringing: Bool) -> NuruPushSound {
        guard soundOn else { return .none }
        guard kind == .ring else { return .standard }
        return ringing ? .ring : .none
    }
}

/// A local notification's sound, testable (UNNotificationSound isn't).
enum NuruPushSound: Equatable {
    case none, standard, ring

    var notificationSound: UNNotificationSound? {
        switch self {
        case .none: return nil
        case .standard: return .default
        case .ring: return UNNotificationSound(named: UNNotificationSoundName(NuruPush.ringSoundName))
        }
    }
}

/// What the app does with a notification that lands while it is open.
enum NuruForeground: Equatable {
    /// Banner, Notification Center and badge — with its sound only when on.
    case show(sound: Bool)
    /// Nothing on screen — a message in the conversation already open — and
    /// a light tap in its place when Sound and vibration are on.
    case quiet(tap: Bool)
    /// A Live guest invite: the full-screen incoming invite, not a banner.
    case ring

    var options: UNNotificationPresentationOptions {
        switch self {
        case .show(let sound): return sound ? [.banner, .list, .badge, .sound] : [.banner, .list, .badge]
        case .quiet, .ring: return []
        }
    }
}

/// The ring's clock: 30 s from when the invite went out; a ring every 4 s
/// (nuru_ring_once.caf, 1.2 s — the cadence of the push's own 26 s file) and
/// a buzz every 1.5 s.
enum NuruRing {
    static let window: TimeInterval = 30
    static let ringEvery: TimeInterval = 4
    static let ringLength: TimeInterval = 1.2
    static let buzzEvery: TimeInterval = 1.5

    /// Seconds of ringing left for an invite that started at `start`. Never
    /// more than the window — a phone clock a little behind the server's must
    /// not ring longer — and never less than zero.
    static func remaining(since start: Date, now: Date) -> TimeInterval {
        let elapsed = max(0, now.timeIntervalSince(start))
        return max(0, window - elapsed)
    }

    /// When to ring across `remaining` seconds: now, then every 4 s — only
    /// whole rings, none running past the window.
    static func ringOffsets(remaining: TimeInterval) -> [TimeInterval] {
        let last = min(remaining, window) - ringLength
        guard last >= 0 else { return [] }
        return Array(stride(from: 0, through: last, by: ringEvery))
    }

    /// When to buzz across `remaining` seconds: now, then every 1.5 s.
    static func buzzOffsets(remaining: TimeInterval) -> [TimeInterval] {
        guard remaining > 0 else { return [] }
        return Array(stride(from: 0, to: min(remaining, window), by: buzzEvery))
    }

    /// A ring for a stream whose invite the member answered (Join or Not now)
    /// less than a window ago is the same invite arriving again — its push,
    /// then its inbox copy on the next sync — and must not ring twice. Any
    /// copy of that invite is past its own 30 s by the time this lapses (a
    /// re-invite inside it still reaches the player's invite card).
    static func isEcho(of streamId: String, answered: [String: Date], now: Date) -> Bool {
        guard let at = answered[streamId] else { return false }
        return now.timeIntervalSince(at) < window
    }
}

/// A Live guest invite's words — the server's own copy for its push (pathway
/// dispatch.ts PUSH_TEMPLATE_COPY.live_guest_invite), for the local
/// notification and for a push that doesn't carry `alert_title`/`alert_body`.
enum LiveInviteCopy {
    static let heading = "You're invited to go live"

    static func message(streamTitle: String?) -> String {
        guard let t = streamTitle, !t.isEmpty else { return "You've been invited to join a live broadcast as a guest." }
        return "You've been invited to join \"\(t)\" as a guest."
    }
}

/// The conversation on screen right now — ChatThreadView marks it while it is
/// visible, so a message for it lands as a light tap instead of a banner.
@MainActor
enum OpenConversation {
    private(set) static var id: String?

    static func opened(_ id: String) { self.id = id }
    /// Only the thread that marked itself clears the mark — pushing thread B
    /// over thread A can run B's appear before A's disappear.
    static func closed(_ id: String) { if self.id == id { self.id = nil } }
}
