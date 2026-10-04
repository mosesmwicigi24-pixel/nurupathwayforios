// Asking to notify (pathway docs/EXPERIENCE.md §7.2 #12). The phone's
// permission prompt used to appear cold — on first sign-in, before the member
// had asked for anything. Now it is asked only when the member turns on
// something that needs it (a daily reading reminder, the radio's "Remind me
// when we're live", push in Settings), and with one line saying why: the
// phone's own prompt can't carry a reason, so the app's short question comes
// first, once. Already allowed: nothing is asked. Turned off in the phone's
// Settings: the switch says where to turn it on, and stays off.
import SwiftUI
import UIKit
import UserNotifications

enum NotificationPermission {
    enum Status: Equatable { case allowed, undecided, denied }

    /// What the phone has said so far.
    static func status() async -> Status {
        status(of: await UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
    }

    /// Pure — pinned by tests.
    static func status(of s: UNAuthorizationStatus) -> Status {
        switch s {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .notDetermined: return .undecided
        default: return .denied
        }
    }

    /// The member turned on something that needs notifications: nil when they
    /// may be shown now; otherwise the question to put first (`why` is its one
    /// line).
    static func askIfNeeded(why: String) async -> NotificationAsk? {
        switch await status() {
        case .allowed: return nil
        case .undecided: return NotificationAsk(kind: .allow, why: why)
        case .denied: return NotificationAsk(kind: .openSettings, why: why)
        }
    }

    /// The phone's own prompt — only ever after the member said Continue.
    static func requestFromPhone() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }
}

/// The app's question before the phone's: "Allow notifications?" with the
/// one line saying why — or, when the phone's Settings have them off, where
/// to turn them on.
struct NotificationAsk: Identifiable, Equatable {
    enum Kind: Equatable { case allow, openSettings }
    let id = UUID()
    let kind: Kind
    /// The one line saying why ("So your daily reading reminder can reach you.").
    let why: String

    var title: String { kind == .allow ? "Allow notifications?" : "Notifications are off" }
    var message: String { kind == .allow ? why : "\(why) Turn them on for Nuru Pathway in Settings." }
}

extension View {
    /// Puts `ask` up as an alert. `answer(true)` once notices may be shown —
    /// the member said Continue and the phone said yes; false for Not now, a
    /// phone that said no, or notifications off in Settings.
    func notificationAsk(_ ask: Binding<NotificationAsk?>, answer: @escaping (Bool) -> Void) -> some View {
        modifier(NotificationAskModifier(ask: ask, answer: answer))
    }
}

private struct NotificationAskModifier: ViewModifier {
    @Binding var ask: NotificationAsk?
    let answer: (Bool) -> Void

    func body(content: Content) -> some View {
        content.alert(ask?.title ?? "",
                      isPresented: Binding(get: { ask != nil }, set: { if !$0 { ask = nil } }),
                      presenting: ask) { a in
            switch a.kind {
            case .allow:
                Button("Not now", role: .cancel) { answer(false) }
                Button("Continue") { Task { answer(await NotificationPermission.requestFromPhone()) } }
            case .openSettings:
                Button("Not now", role: .cancel) { answer(false) }
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    answer(false)
                }
            }
        } message: { a in
            Text(a.message)
        }
    }
}
