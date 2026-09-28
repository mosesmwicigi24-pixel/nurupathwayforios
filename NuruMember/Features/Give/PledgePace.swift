// Giving Cycle 9 — a total pledge's pace, and collecting it at that pace.
//
// The server says the pace (`Pledge.pace`): what is still owed spread over the
// monthly collections left — one today, then the same day each month through
// the pledge's date — rounded up to whole shillings, so the last is never
// short. The pledge's page says it in one line and, for a shilling pledge
// while M-Pesa takes recurring gifts here and nothing collects the pledge yet,
// offers to collect it at that pace: a monthly M-Pesa gift bound to the
// pledge, its first prompt now (the pace counts one collection today). Each
// month's prompt asks only what is left and the gift stops when the pledge is
// reached (the server's Cycle 5 rule). A pledge a recurring gift already
// collects shows that gift instead. Pure, so it is pinned by tests.
import Foundation

enum PledgePace {
    /// "To reach KSh 20,000 by 31 Dec: KSh 5,000 a month — 4 collections"
    /// ("1 collection"; dollars in cents). Nil without a pace.
    static func line(_ pledge: Pledge, today: String = PledgeMath.today()) -> String? {
        guard let pace = pledge.pace else { return nil }
        let target = GiveMoney.format(pledge.targetMinor ?? 0, pledge.currency)
        let each = GiveMoney.format(pace.perMonthMinor, pledge.currency)
        let n = pace.collectionsLeft
        return "To reach \(target) by \(shortDay(pace.by, today: today)): \(each) a month — \(n) collection\(n == 1 ? "" : "s")"
    }

    /// "31 Dec" — "31 Mar 2027" in another year than `today`'s. A calendar
    /// day as given, never shifted by a time zone.
    static func shortDay(_ day: String, today: String) -> String {
        let parts = day.prefix(10).split(separator: "-")
        guard parts.count == 3, let m = Int(parts[1]), let d = Int(parts[2]), (1...12).contains(m) else { return String(day.prefix(10)) }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        let base = "\(d) \(months[m - 1])"
        return day.prefix(4) == today.prefix(4) ? base : "\(base) \(parts[0])"
    }

    /// What a pledge's page offers about collecting it automatically.
    enum Offer: Equatable {
        /// "Collect it automatically at this pace": this much each month.
        case collect(amountMinor: Int)
        /// A recurring gift already collects the pledge — shown instead,
        /// opening its sheet.
        case collected(scheduleId: String, line: String)
        /// Nothing to offer, or not known yet.
        case none
    }

    /// The recurring gift that already collects `pledge`: one bound to it
    /// that is running — else one that is paused (it still collects the
    /// pledge once resumed; a second would only compete with it). A
    /// cancelled one collects nothing.
    static func collector(of pledge: Pledge, in schedules: [GivingSchedule]) -> GivingSchedule? {
        let mine = schedules.filter { !pledge.pledgeId.isEmpty && $0.pledge?.pledgeId == pledge.pledgeId }
        return mine.first { $0.status.lowercased() == "active" } ?? mine.first { $0.status.lowercased() == "paused" }
    }

    /// The offer, from what the server said: nothing until the recurring
    /// gifts are known; the gift that already collects the pledge, when one
    /// does; else "collect it at this pace" only for an active shilling pledge
    /// with a pace, when M-Pesa takes recurring gifts here (GET /giving/methods)
    /// and the pledge says where its money goes.
    static func offer(for pledge: Pledge, methods: GivingMethods?, schedules: [GivingSchedule]?) -> Offer {
        guard let schedules else { return .none }
        if let s = collector(of: pledge, in: schedules) {
            return .collected(scheduleId: s.scheduleId, line: collectedLine(s))
        }
        guard let pace = pledge.pace, pledge.status == "active", !pledge.isMonthly,
              pledge.currency.uppercased() == "KES",
              let methods, methods.allowsRecurring("mpesa"),
              !(pledge.paysTo?.code ?? "").isEmpty else { return .none }
        return .collect(amountMinor: pace.perMonthMinor)
    }

    /// "Collected automatically — next KSh 5,000 on 28 Oct" · "… — nothing to
    /// pay next time" (the pledge is paid through it) · "… — paused" · just
    /// "Collected automatically" when no prompt is coming (it is stopping
    /// with its pledge). `next_amount_minor` is the server's word for what
    /// the next prompt asks.
    static func collectedLine(_ s: GivingSchedule) -> String {
        let head = "Collected automatically"
        if s.status.lowercased() == "paused" { return "\(head) — paused" }
        guard let next = s.nextAmountMinor else { return head }
        if next == 0 { return "\(head) — nothing to pay next time" }
        let when = giveParseDate(s.nextRunAt).map { " on \(ScheduleRhythm.format($0, "d MMM"))" } ?? ""
        return "\(head) — next \(GiveMoney.format(next, s.currency))\(when)"
    }

    /// POST /giving/schedules for "Collect it automatically at this pace": a
    /// monthly M-Pesa gift of the pace's amount, bound to the pledge, its
    /// first prompt now — on the pledge's own fund (`pays_to`, which the
    /// server keeps for a bound gift anyway), to the member's own number, with
    /// a fresh key. Nil when the pledge has no pace or no fund to pay.
    static func scheduleBody(for pledge: Pledge, key: String = GiveKey.fresh()) -> MemberAPI.ScheduleCreateBody? {
        guard let pace = pledge.pace, let fund = pledge.paysTo?.code, !fund.isEmpty else { return nil }
        return MemberAPI.ScheduleCreateBody(fund: fund, amountMinor: pace.perMonthMinor, currency: "KES",
                                            frequency: "monthly", method: "mpesa", idempotencyKey: key,
                                            firstCharge: "now", pledgeId: pledge.pledgeId)
    }
}
