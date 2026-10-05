// What a notice can promise on iOS (the walk's B11; §2: promise only what
// works). This build has no remote push: nothing reaches the phone while the
// app is closed. It shows new notices as banners when it opens (LocalNotifier)
// and keeps two reminders it schedules itself — a plan's daily reading and a
// radio show. Every other reminder is the server's, and lands in the inbox.
import Foundation

enum IOSNoticeWords {
    /// After "Going" on a gathering — the server's day-before reminder.
    static let rsvpSaved = "Saved · a reminder will be in your inbox the day before."
    /// A pledge's reminder switch — the server's reminder before it's due.
    static let pledgeReminder = "Remind me in my inbox before it's due"
    /// Settings' first switch — what it really turns on and off here.
    static let bannersTitle = "Banners on this phone"
    static let bannersLine = "New notices when you open the app — the inbox keeps them all"
    /// The banners switch (the server's push preference, cached here) gates
    /// LocalNotifier's banners; unset reads as on, as the switch shows it.
    static let bannersKey = "nuru.notif.push"
    static func bannersOn(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: bannersKey) as? Bool ?? true
    }
}
