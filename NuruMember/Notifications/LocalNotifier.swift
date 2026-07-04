// Local notification bridge — surfaces NEW server notifications (/me/notifications)
// as real iOS notifications: banner + Notification Center + default sound (iOS
// vibrates automatically when the phone is on silent/vibrate). True background
// push needs APNs (paid Apple team) — until then we post on every foreground
// sync, and taps deep-link to the in-app Notification Center.
import Foundation
import UserNotifications
import UIKit

extension Notification.Name {
    /// Posted when the member taps one of our iOS notifications — Home listens
    /// and pushes the in-app Notifications screen.
    static let nuruOpenNotifications = Notification.Name("nuru.openNotifications")
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

    /// Ask once after sign-in; safe to call repeatedly (no-op when decided).
    func requestPermission() {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Fetch the server inbox and post an iOS notification for anything unseen.
    /// First sync only records the baseline (no blast of old items on install).
    func sync() async {
        guard !syncing else { return }
        syncing = true; defer { syncing = false }
        guard let result = try? await MemberAPI.notifications() else { return }

        var seen = Set(UserDefaults.standard.stringArray(forKey: seenKey) ?? [])
        let firstRun = seen.isEmpty
        let fresh = result.rows.filter { $0.isUnread && !seen.contains($0.notificationId) }

        for n in result.rows { seen.insert(n.notificationId) }
        // Keep the seen-set bounded; the server inbox is the source of truth.
        UserDefaults.standard.set(Array(seen.suffix(400)), forKey: seenKey)

        try? await UNUserNotificationCenter.current().setBadgeCount(result.unread)
        guard !firstRun else { return }

        for n in fresh.prefix(5) {   // cap a burst; the rest are in the inbox
            let content = UNMutableNotificationContent()
            content.title = Self.title(for: n)
            if let body = Self.body(for: n) { content.body = body }
            content.sound = .default   // silent mode → vibration
            content.userInfo = ["notificationId": n.notificationId]
            let req = UNNotificationRequest(identifier: "nuru-\(n.notificationId)",
                                            content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(req)
        }
    }

    // Template → human copy (mirrors NotificationsView's mapping, condensed).
    private static func title(for n: NotificationRow) -> String {
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
        return "Nuru Pathway"
    }
    private static func body(for n: NotificationRow) -> String? {
        if let b = n.payload?.body, !b.isEmpty { return b }
        if let f = n.payload?.feedback, !f.isEmpty { return f }
        return nil
    }
}

extension LocalNotifier: UNUserNotificationCenterDelegate {
    /// Show banner + sound even while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    /// Tap → open the in-app Notification Center.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            NotificationCenter.default.post(name: .nuruOpenNotifications, object: nil)
        }
        completionHandler()
    }
}
