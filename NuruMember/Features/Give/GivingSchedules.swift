// Giving Cycle 4 — a recurring gift the member controls, and the words around
// it, kept pure so they can be tested: when the gift falls (on the church's
// Nairobi calendar, the way the server computes it — a monthly gift keeps its
// own day, clamped into shorter months), the "Your rhythm" row, starting with
// a gift now or not, why a gift is paused, the dates a pause may run to, and
// what a change may send. The server re-checks every one of them.
import Foundation

// MARK: - When a recurring gift falls

enum ScheduleRhythm {
    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    /// "1st" · "2nd" · "3rd" · "4th" · "11th" · "12th" · "13th" · "21st" · "31st".
    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    static func isWeekly(_ frequency: String) -> Bool { frequency.lowercased() == "weekly" }

    /// The day a schedule falls on: weekly — the Nairobi weekday of its next
    /// prompt (Sunday 0 … Saturday 6, the server's numbering); monthly — its
    /// own day (`anchor_day`, kept when a short month clamps it), else the
    /// next prompt's day of the month. Nil when neither can be read.
    static func day(of s: GivingSchedule) -> Int? {
        let next = giveParseDate(s.nextRunAt)
        if isWeekly(s.frequency) {
            return next.map { GiveCalendar.calendar.component(.weekday, from: $0) - 1 }
        }
        if let a = s.anchorDay, (1...31).contains(a) { return a }
        return next.map { GiveCalendar.calendar.component(.day, from: $0) }
    }

    /// "every Sunday" · "every month on the 31st".
    static func cadence(frequency: String, day: Int) -> String {
        if isWeekly(frequency) { return "every \(weekdays[max(0, min(6, day))])" }
        return "every month on the \(ordinal(max(1, min(31, day))))"
    }

    /// "next Sun 5 Oct" — and when a monthly gift's own day does not exist
    /// that month (the 31st in November), the day it falls on instead:
    /// "next Mon 30 Nov, the last day of November".
    static func next(of s: GivingSchedule) -> String? {
        guard let d = giveParseDate(s.nextRunAt) else { return nil }
        var line = "next \(format(d, "EEE d MMM"))"
        if !isWeekly(s.frequency), let anchor = s.anchorDay {
            let actual = GiveCalendar.calendar.component(.day, from: d)
            if anchor > actual { line += ", the last day of \(format(d, "MMMM"))" }
        }
        return line
    }

    /// The Give form's "Your rhythm" row (PARTNERS_PROGRAMME §3a):
    /// "KSh 500 every Sunday · next Sun 5 Oct".
    static func rowText(for s: GivingSchedule) -> String? {
        guard let day = day(of: s) else { return nil }
        let head = "\(GiveMoney.format(s.amountMinor, s.currency)) \(cadence(frequency: s.frequency, day: day))"
        guard let next = next(of: s) else { return head }
        return "\(head) · \(next)"
    }

    /// The running schedule whose next prompt comes first — the rhythm row's.
    static func soonestActive(_ all: [GivingSchedule]) -> GivingSchedule? {
        all.filter { $0.status.lowercased() == "active" }
            .compactMap { s in giveParseDate(s.nextRunAt).map { (s, $0) } }
            .min { $0.1 < $1.1 }?.0
    }

    // MARK: Setting one up (the confirm step)

    /// The day a gift set up NOW falls on — the server keeps today's Nairobi
    /// weekday (weekly) or day of the month (monthly).
    static func setupDay(frequency: String, now: Date) -> Int {
        let cal = GiveCalendar.calendar
        return isWeekly(frequency) ? cal.component(.weekday, from: now) - 1 : cal.component(.day, from: now)
    }

    /// When the first prompt comes if nothing is given today: a week on, or
    /// the same day next month — clamped into a shorter month (31 Jan → 28/29
    /// Feb), as the server's calendar does.
    static func firstPrompt(frequency: String, now: Date) -> Date {
        let cal = GiveCalendar.calendar
        if isWeekly(frequency) { return cal.date(byAdding: .day, value: 7, to: now) ?? now }
        return cal.date(byAdding: .month, value: 1, to: now) ?? now   // Calendar clamps to the month's last day
    }

    /// "KSh 1,000 now, then every Sunday" · "… then every month on the 28th".
    static func startNowLine(amountLabel: String, frequency: String, now: Date) -> String {
        "\(amountLabel) now, then \(cadence(frequency: frequency, day: setupDay(frequency: frequency, now: now)))"
    }

    /// "Nothing is taken today — the first prompt comes on 5 Oct 2026."
    static func nothingTodayLine(frequency: String, now: Date) -> String {
        "Nothing is taken today — the first prompt comes on \(format(firstPrompt(frequency: frequency, now: now), "d MMM yyyy"))."
    }

    /// The same line from the server's own first prompt (`next_run_at`).
    static func nothingTodayLine(firstPromptISO: String) -> String {
        guard let d = giveParseDate(firstPromptISO) else { return "Nothing is taken today." }
        return "Nothing is taken today — the first prompt comes on \(format(d, "d MMM yyyy"))."
    }

    /// "Your weekly gift is set up — the first prompt comes on 5 Oct 2026."
    static func setUpLine(frequency: String, firstPromptISO: String) -> String {
        let kind = isWeekly(frequency) ? "weekly" : "monthly"
        guard let d = giveParseDate(firstPromptISO) else { return "Your \(kind) gift is set up." }
        return "Your \(kind) gift is set up — the first prompt comes on \(format(d, "d MMM yyyy"))."
    }

    /// What Partners' DUE row says for a running recurring gift, in place of
    /// Pay (owner, 2026-09-28): "Collected on Mon 5 Oct". Pay only opened a
    /// separate one-time gift while the gift still prompted on its day — the
    /// member gave twice that cycle. `dueOn` is the server's Nairobi date of
    /// the next prompt; nil when it is not one.
    static func collectedOn(_ dueOn: String) -> String? {
        guard let d = PauseDates.date(dueOn) else { return nil }
        return "Collected on \(format(d, "EEE d MMM"))"
    }

    /// A date on the church's calendar, in English (the app's language).
    static func format(_ date: Date, _ pattern: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = GiveCalendar.nairobi
        f.dateFormat = pattern
        return f.string(from: date)
    }
}

// MARK: - A gift that collects a pledge (Giving Cycle 5)

enum ScheduleCopy {
    /// "Collects your pledge “Kenya trip”" — nil for an ordinary gift.
    static func pledgeLine(_ s: GivingSchedule) -> String? {
        guard let p = s.pledge else { return nil }
        let title = p.title.trimmingCharacters(in: .whitespaces)
        return "Collects your pledge \u{201C}\(title.isEmpty ? "Your pledge" : title)\u{201D}"
    }

    /// What the next prompt will ask, when it is not simply the gift's
    /// amount: "Next: KSh 3,000 — the rest of what's due" · "Nothing to pay
    /// next time — your pledge is already paid". Nil when no prompt is coming
    /// (paused, cancelled, stopping), on older servers, and when it asks the
    /// whole amount.
    static func nextLine(_ s: GivingSchedule) -> String? {
        guard let next = s.nextAmountMinor else { return nil }
        if next == 0 { return "Nothing to pay next time — your pledge is already paid" }
        if next < s.amountMinor { return "Next: \(GiveMoney.format(next, s.currency)) — the rest of what's due" }
        return nil
    }

    /// The pledge collector's amount and day are its MONTHLY pledge's (the
    /// server refuses to change them here, 422 with `details.pledge_id`):
    /// true when this gift collects a pledge whose shape is known to be
    /// monthly. Unknown shape = let the server answer.
    static func followsMonthlyPledge(_ s: GivingSchedule, pledgeShape: (String) -> String?) -> Bool {
        guard let id = s.pledge?.pledgeId else { return false }
        return pledgeShape(id) == "monthly"
    }
}

// MARK: - Why a gift is paused

enum PauseCopy {
    enum Reason: Equatable {
        /// Three prompts in a row did not go through — the member resumes it.
        case failures
        /// The member paused it, until `resumeOn` (a Nairobi date) or until resumed.
        case member(resumeOn: String?)
        /// It follows its pledge — resume the pledge (Partners) to resume it.
        case pledge
        /// Paused, reason not said (an older server).
        case unknown
    }

    /// Nil while the schedule is not paused.
    static func reason(of s: GivingSchedule) -> Reason? {
        guard s.status.lowercased() == "paused" else { return nil }
        switch s.pauseReason?.lowercased() {
        case "failures": return .failures
        case "member": return .member(resumeOn: s.resumeOn)
        case "pledge": return .pledge
        default: return .unknown
        }
    }

    /// The sheet's line: "Paused after 3 prompts didn't go through" · "Paused
    /// until 5 Oct 2026" · "Paused" · "Paused with its pledge — resume the
    /// pledge in Partners". Nil while not paused.
    static func line(for s: GivingSchedule) -> String? {
        switch reason(of: s) {
        case nil: return nil
        case .failures: return "Paused after 3 prompts didn't go through"
        case .member(let on): return on.flatMap(dayLabel).map { "Paused until \($0)" } ?? "Paused"
        case .pledge: return "Paused with its pledge — resume the pledge in Partners"
        case .unknown: return "Paused"
        }
    }

    /// A paused gift the member can resume here — never one that follows its
    /// pledge (the server refuses: resume the pledge instead).
    static func canResume(_ s: GivingSchedule) -> Bool {
        guard let r = reason(of: s) else { return false }
        return r != .pledge
    }

    /// The small card's line under a paused gift: when it comes back on its
    /// own, else that nothing is owed.
    static func cardLine(for s: GivingSchedule) -> String {
        if case .member(let on)? = reason(of: s), let day = on.flatMap(shortDayLabel) { return "Resumes \(day)" }
        return "Nothing is owed"
    }

    /// "2026-10-05" → "5 Oct 2026".
    static func dayLabel(_ ymd: String) -> String? { PauseDates.date(ymd).map { ScheduleRhythm.format($0, "d MMM yyyy") } }
    private static func shortDayLabel(_ ymd: String) -> String? { PauseDates.date(ymd).map { ScheduleRhythm.format($0, "d MMM") } }
}

// MARK: - Pausing until a date

/// "Until a date" (Giving Cycle 4): from tomorrow to a year from today, on the
/// church's calendar — the server refuses anything else.
enum PauseDates {
    static func range(now: Date) -> ClosedRange<Date> {
        let cal = GiveCalendar.calendar
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today
        let limit = cal.date(byAdding: .year, value: 1, to: today) ?? tomorrow
        return tomorrow...max(tomorrow, limit)
    }

    static func isAllowed(_ date: Date, now: Date) -> Bool {
        let r = range(now: now)
        let day = GiveCalendar.calendar.startOfDay(for: date)
        return day >= r.lowerBound && day <= r.upperBound
    }

    /// The Nairobi date the server reads: "2026-10-05".
    static func wire(_ date: Date) -> String { ScheduleRhythm.format(date, "yyyy-MM-dd") }

    /// "2026-10-05" → that day's start in Nairobi.
    static func date(_ ymd: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = GiveCalendar.nairobi
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(ymd.prefix(10)))
    }
}

// MARK: - Changing a gift (PATCH /giving/schedules/{id})

/// What a change sends — only what changed. `phone`: a number of the
/// schedule's own, back to the profile number (JSON null), or untouched.
struct SchedulePatch: Encodable, Equatable {
    enum Phone: Equatable { case unchanged, number(String), profile }

    var amountMinor: Int? = nil
    var day: Int? = nil
    var phone: Phone = .unchanged
    var headsUp: Bool? = nil

    var isEmpty: Bool { amountMinor == nil && day == nil && phone == .unchanged && headsUp == nil }

    private enum CodingKeys: String, CodingKey { case amountMinor, day, phoneNumber, headsUp }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(amountMinor, forKey: .amountMinor)
        try c.encodeIfPresent(day, forKey: .day)
        switch phone {
        case .unchanged: break
        case .number(let n): try c.encode(n, forKey: .phoneNumber)
        case .profile: try c.encodeNil(forKey: .phoneNumber)
        }
        try c.encodeIfPresent(headsUp, forKey: .headsUp)
    }
}

/// The Change form, as typed.
struct ScheduleDraft: Equatable {
    var amountText: String
    var day: Int
    var phoneText: String
    var useProfileNumber: Bool
}

enum ScheduleEdit {
    /// The form as the schedule is now.
    static func draft(of s: GivingSchedule) -> ScheduleDraft {
        ScheduleDraft(amountText: String(s.amountMinor / 100),
                      day: ScheduleRhythm.day(of: s) ?? (ScheduleRhythm.isWeekly(s.frequency) ? 0 : 1),
                      phoneText: s.phoneNumber ?? "",
                      useProfileNumber: s.phoneNumber == nil)
    }

    struct Plan: Equatable {
        /// What would be sent; nil when nothing changed or something is wrong.
        var patch: SchedulePatch?
        /// Why it cannot be sent, in the server's terms; nil when it can.
        var problem: String?
    }

    /// What Save would send — whole shillings inside the rail's limits, a
    /// real day, a Kenyan mobile number — or why not. Only changes are sent.
    static func plan(_ d: ScheduleDraft, for s: GivingSchedule, rail: GivingMethod?) -> Plan {
        var patch = SchedulePatch()

        let typed = d.amountText.filter { !$0.isWhitespace && $0 != "," }
        guard !typed.isEmpty else { return Plan(patch: nil, problem: "Enter an amount.") }
        guard typed.allSatisfy({ $0.isASCII && $0.isNumber }), let ksh = Int(typed) else {
            return Plan(patch: nil, problem: "Enter whole shillings — no cents.")
        }
        guard ksh > 0 else { return Plan(patch: nil, problem: "Enter an amount.") }
        let minor = ksh * 100
        if let rail, let problem = GiveAmountRules.problem(totalMinor: minor, rail: rail) {
            return Plan(patch: nil, problem: problem)
        }
        if minor != s.amountMinor { patch.amountMinor = minor }

        let weekly = ScheduleRhythm.isWeekly(s.frequency)
        guard (weekly ? 0...6 : 1...31).contains(d.day) else { return Plan(patch: nil, problem: "Choose a day.") }
        if d.day != ScheduleRhythm.day(of: s) { patch.day = d.day }

        if d.useProfileNumber {
            if s.phoneNumber != nil { patch.phone = .profile }
        } else {
            let text = d.phoneText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return Plan(patch: nil, problem: "Add the number to prompt, or use your profile number.") }
            guard let e164 = KenyanPhone.normalize(text) else { return Plan(patch: nil, problem: KenyanPhone.invalidMessage) }
            if e164 != s.phoneNumber.flatMap(KenyanPhone.normalize) { patch.phone = .number(e164) }
        }

        return Plan(patch: patch.isEmpty ? nil : patch, problem: nil)
    }
}
