// Local notification bridge — surfaces NEW server notifications (/me/notifications)
// as real iOS notifications: banner + Notification Center + default sound (iOS
// vibrates automatically when the phone is on silent/vibrate). True background
// push needs APNs (paid Apple team) — until then we post on every foreground
// sync, and taps deep-link to the in-app Notification Center.
//
// Sound (2026-09-28): each notification sounds by its kind and the member's
// Sound and vibration switch — the rules a real push follows (NuruPush) — and
// carries the same `nuru_kind` / `nuru_sound` keys, so the foreground rules
// below treat both alike: quiet in the open conversation, a ringing
// full-screen invite for a Live guest invite, sound only when it's on.
import Foundation
import UserNotifications
import UIKit

extension Notification.Name {
    /// Posted when the member taps one of our iOS notifications — Home listens
    /// and pushes the in-app Notifications screen.
    static let nuruOpenNotifications = Notification.Name("nuru.openNotifications")
    /// Posted with the tapped notification's userInfo (template + route ids) —
    /// RootView routes it to the EXACT in-app location (module, level,
    /// announcement, events/give/profile tab), falling back to the inbox.
    static let nuruNotificationTap = Notification.Name("nuru.notificationTap")
    /// Posted by any surface that wants the radio player open (Home's radio
    /// button, the ON AIR bar). RootView owns the ONE fullScreenCover — a
    /// single presentation source so covers never fight over the window.
    static let nuruOpenRadio = Notification.Name("nuru.openRadio")
}

@MainActor
final class LocalNotifier: NSObject, ObservableObject {
    static let shared = LocalNotifier()

    private let seenKey = "notif.seenIds"
    private var syncing = false

    /// After sign-in: taps on our notifications route through here. It no
    /// longer asks the phone for permission — that prompt used to appear
    /// cold, before the member had asked for anything (EXPERIENCE.md §7.2
    /// #12). Permission is asked only when the member turns on something that
    /// needs it (NotificationPermission). Safe to call repeatedly.
    func attach() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// Fetch the server inbox and post an iOS notification for anything unseen.
    /// First sync only records the baseline (no blast of old items on install).
    func sync() async {
        guard !syncing else { return }
        syncing = true; defer { syncing = false }
        let ticket = InboxBadge.shared.ticket()
        guard let result = try? await MemberAPI.notifications() else { return }
        // Every bell's dot (§7.2 #4) — the same count as the icon's badge below.
        InboxBadge.shared.land(result.unread, ticket: ticket)

        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let firstRun = seen.isEmpty
        let fresh = result.rows.filter { $0.isUnread && !seen.contains($0.notificationId) }

        for n in result.rows { seen.insert(n.notificationId) }
        // Keep the seen-set bounded; the server inbox is the source of truth.
        UserDefaults.standard.set(Array(seen.suffix(400)), forKey: seenKey)

        try? await UNUserNotificationCenter.current().setBadgeCount(result.unread)
        guard !firstRun, !fresh.isEmpty else { return }
        // Settings' "Banners on this phone" (B11): off means none.
        guard IOSNoticeWords.bannersOn() else { return }
        let soundOn = await Self.soundEnabled()
        let now = Date()

        for n in fresh.prefix(5) {   // cap a burst; the rest are in the inbox
            let content = UNMutableNotificationContent()
            content.title = Self.title(for: n)
            if let body = Self.body(for: n) { content.body = body }
            // Sounds by kind (silent mode → vibration): the ring only while
            // the invite's 30 s run — from when the SERVER sent it, since the
            // app may open long after — and nothing at all when muted.
            let kind = NuruPushKind.of(template: n.template)
            let sentAt = n.sentAt.flatMap { ISO8601DateFormatter.nuru.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            let ringing = NuruRing.remaining(since: sentAt ?? now, now: now) > 0
            content.sound = NuruPush.localSound(kind: kind, soundOn: soundOn, ringing: ringing).notificationSound
            // One conversation's messages stack together, as a push's thread-id does.
            if kind == .message, let c = n.payload?.conversationId, !c.isEmpty { content.threadIdentifier = c }
            // Carry the routing payload so a TAP lands where the inbox row
            // would (NoticeRouter — one router for both, §7.2 #3) …
            var info = NoticeTarget(n).userInfo
            info["notificationId"] = n.notificationId
            // … and how it sounds and shows (NuruPush), in a push's own keys.
            // A Live guest invite rings for its stream (`title`, carried by the
            // routing keys for a Live notice, is the stream's name).
            info["nuru_kind"] = kind.rawValue
            info["nuru_sound"] = soundOn ? "on" : "off"
            info["nuru_sent_at"] = n.sentAt ?? ""
            info["conversation_id"] = n.payload?.conversationId ?? ""
            info["stream_id"] = n.payload?.streamId ?? ""
            info["alert_title"] = content.title
            info["alert_body"] = content.body
            content.userInfo = info
            let req = UNNotificationRequest(identifier: "nuru-\(n.notificationId)",
                                            content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(req)
        }
    }

    /// Sound and vibration: the server's `sound_enabled`, so a choice made on
    /// another phone holds here — or, offline, the switch's cached value.
    /// Asked only when there is something to post.
    private static func soundEnabled() async -> Bool {
        if let prefs = try? await MemberAPI.notificationPreferences() { return prefs.soundEnabled }
        return UserDefaults.standard.object(forKey: NuruPush.soundPrefKey) as? Bool ?? true
    }

    // Template → human copy (mirrors NotificationsView's mapping, condensed).
    private static func title(for n: NotificationRow) -> String {
        // Giving and Partners notices say what happened (a failed gift is not
        // a receipt) — ahead of `payload.title`, which on the Partners notices
        // is the pledge's name.
        if let t = GivingNotificationCopy.title(template: n.template, payload: n.payload) { return t }
        // A Live guest invite's `title` is the STREAM's name — the notice
        // says what happened, in the server's own words for the push.
        if n.template == "live_guest_invite" { return LiveInviteCopy.heading }
        if let t = n.payload?.title, !t.isEmpty { return t }
        let t = n.template
        if t.hasPrefix("reflection_approved") { return "Reflection approved" }
        if t.hasPrefix("reflection_returned") { return "Reflection returned" }
        if t.hasPrefix("reflection") { return "Reflection reviewed" }
        if t.hasPrefix("level") { return "Level complete!" }
        if t.hasPrefix("badge") { return "New badge earned" }
        if t.hasPrefix("certificate") { return "Certificate ready" }
        if t.hasPrefix("event_reminder_1h") { return "Event starting soon" }
        if t.hasPrefix("event") { return "Upcoming gathering" }
        if t.hasPrefix("giving") { return "Giving receipt" }
        if t.hasPrefix("announcement") { return "New announcement" }
        // Chat Redesign C3b — the join-review flow notifies both directions.
        if t.hasPrefix("space_join_requested") { return "New join request" }
        if t.hasPrefix("space_join_accepted") { return "You're in!" }
        if t.hasPrefix("space_join_declined") { return "Join request declined" }
        if t.hasPrefix("connection") { return "Connection request" }
        // Read with a Friend (reading-social R1).
        if t == "plan_group_invite_received" { return "Read together?" }
        if t == "plan_group_invite_accepted" { return "They joined your plan!" }
        if t == "plan_group_member_joined" { return "New reading partner" }
        if t == "plan_group_day_completed" { return "Reading update" }
        // Departments (PARTNERS_PROGRAMME §4).
        if t == "serve_request_approved" { return "You're on the team" }
        if t == "serve_request_declined" { return "About your request to serve" }
        if t.hasPrefix("serve_request") { return "Request to serve" }
        if t == "department_post" { return "News from your department" }
        if t == "department_need_approved" { return "A need is open for giving" }
        if t.hasPrefix("department_need") { return "Department need" }
        // Locked-pastoral rule (spec: generic copy, no preview) applied to ANY
        // pastoral-flavoured template, present or future, lock or no lock —
        // a preview leak is worse than a too-quiet notification.
        if t.hasPrefix("pastoral") { return "You have a new private pastoral message." }
        return "Nuru Pathway"
    }
    private static func body(for n: NotificationRow) -> String? {
        // Never surface pastoral content in a banner (C3b).
        if n.template.hasPrefix("pastoral") { return nil }
        if n.template == "live_guest_invite" { return LiveInviteCopy.message(streamTitle: n.payload?.title) }
        if let b = n.payload?.body, !b.isEmpty { return b }
        if let f = n.payload?.feedback, !f.isEmpty { return f }
        return GivingNotificationCopy.body(template: n.template, payload: n.payload)
    }
}

extension LocalNotifier: UNUserNotificationCenterDelegate {
    /// While the app is open (NuruPush.foreground): a message for the
    /// conversation on screen is a light tap, not a banner; a Live guest
    /// invite rings full-screen instead of a banner; anything else shows as
    /// a banner, sounding only when the member's Sound and vibration is on.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let push = NuruPush(userInfo: notification.request.content.userInfo, deliveredAt: notification.date)
        Task { @MainActor in
            var shown = push.foreground(openConversationId: OpenConversation.id, now: Date())
            switch shown {
            case .quiet(let tap):
                if tap { Haptics.tap() }
            case .ring:
                // No ring while the member is broadcasting (or with no window
                // to ring in) — then it's a quiet banner, never nothing.
                let rang = IncomingLiveInvite(push: push).map { IncomingLiveInviteCenter.shared.ring($0) } ?? false
                if !rang { shown = .show(sound: false) }
            case .show:
                break
            }
            completionHandler(shown.options)
        }
    }

    /// Tap → land on the EXACT target (RootView routes by the userInfo payload;
    /// anything unroutable falls back to the in-app Notification Center there).
    /// Opening from the banner also counts as reading it.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        var info = response.notification.request.content.userInfo
        // When iOS delivered it — a tapped Live invite still rings if its
        // 30 s haven't run out (RootView), else opens the stream.
        info[NuruPush.deliveredAtKey] = response.notification.date
        Task { @MainActor in
            NotificationCenter.default.post(name: .nuruNotificationTap, object: nil,
                                            userInfo: info as? [String: Any])
            if let id = info["notificationId"] as? String, !id.isEmpty {
                try? await MemberAPI.markNotificationsRead([id])
                await InboxBadge.shared.refresh()   // the bells, once it's read
            }
        }
        completionHandler()
    }
}
