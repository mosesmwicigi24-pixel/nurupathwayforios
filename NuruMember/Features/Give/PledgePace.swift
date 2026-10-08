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
// collects shows that gift instead, and a DUE instalment that gift collects
// on or before its date says so (EXPERIENCE.md §6.4). Pure, so it is pinned
// by tests.
import Foundation

enum PledgePace {
    /// "To reach KSh 20,000 by Thu 31 Dec: KSh 5,000 a month — 4 collections"
    /// ("1 collection"; dollars in cents). Nil without a pace.
    static func line(_ pledge: Pledge, today: String = PledgeMath.today()) -> String? {
        guard let pace = pledge.pace else { return nil }
        let target = GiveMoney.format(pledge.targetMinor ?? 0, pledge.currency)
        let each = GiveMoney.format(pace.perMonthMinor, pledge.currency)
        let n = pace.collectionsLeft
        return "To reach \(target) by \(shortDay(pace.by, today: today)): \(each) a month — \(n) collection\(n == 1 ? "" : "s")"
    }

    /// "Thu 31 Dec" — "Wed 31 Mar 2027" in another year than `today`'s: the
    /// one date shape (§8.1 rule 8), as the card's "by Thu 31 Dec" above it.
    /// A calendar day as given, never shifted by a time zone.
    static func shortDay(_ day: String, today: String) -> String {
        guard PledgeMath.isDay(String(day.prefix(10))) else { return String(day.prefix(10)) }
        return PledgeMath.dayLabel(day, today: today)
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

    /// The recurring gift that already collects `pledge`: one bound to it —
    /// by the gift's own `pledge`, or (an older row) the pledge's own
    /// `schedule_id` — that is running, else one that is paused (it still
    /// collects the pledge once resumed; a second would only compete with
    /// it). A cancelled one collects nothing.
    static func collector(of pledge: Pledge, in schedules: [GivingSchedule]) -> GivingSchedule? {
        guard !pledge.pledgeId.isEmpty else { return nil }
        let own = pledge.scheduleId.flatMap { $0.isEmpty ? nil : $0 }
        let mine = schedules.filter { $0.pledge?.pledgeId == pledge.pledgeId || (own != nil && $0.scheduleId == own) }
        return mine.first { $0.status.lowercased() == "active" } ?? mine.first { $0.status.lowercased() == "paused" }
    }

    /// The pledge page's pay button (EXPERIENCE.md §7.2 #2, §7.1 rule 6):
    /// while a collector is running for the pledge — the page says "Collected
    /// automatically — next …" — paying by hand is a choice, "Pay early",
    /// quiet beside Pause; the call to action is the church's own prompt.
    /// With no collector running (none, a paused one, or the gifts not known
    /// yet) "Pay now" stays the gold primary. Labels only: either button pays
    /// the same way.
    static func paysEarly(_ pledge: Pledge, schedules: [GivingSchedule]?) -> Bool {
        guard let schedules, let s = collector(of: pledge, in: schedules) else { return false }
        return s.status.lowercased() == "active"
    }

    /// The church-calendar day ("2026-10-05") a DUE instalment is collected
    /// by its pledge's collector (EXPERIENCE.md §6.4): the collector running,
    /// its next prompt asking for money (`next_amount_minor` > 0 — 0 is a
    /// pledge already covered, nil a collector stopping with its pledge or an
    /// older server) and falling on or before the instalment's date, both
    /// read as Nairobi days. Partners then says "Collected on …", as it does
    /// for a running recurring gift — Pay there only made a second, one-time
    /// gift for money the prompt was about to take. Nil, and Pay stays, for
    /// anything else: a row that is not a pledge's Pay row, no collector, a
    /// paused one, one that asks nothing, one prompting after the date (the
    /// instalment would be late). Paying early by hand stays possible from
    /// the pledge's page either way. Android's pledgeCollectedOn, the same rule.
    static func collectedDay(_ item: DueItem, by collector: GivingSchedule?) -> String? {
        guard item.kind == "pledge", item.action == "pay",
              let s = collector, s.status.lowercased() == "active", (s.nextAmountMinor ?? 0) > 0,
              let prompt = giveParseDate(s.nextRunAt), PauseDates.date(item.dueOn) != nil else { return nil }
        let day = PauseDates.wire(prompt)
        return day <= String(item.dueOn.prefix(10)) ? day : nil
    }

    /// The offer, from what the server said: nothing until the recurring
    /// gifts are known; the gift that already collects the pledge, when one
    /// does; else "collect it at this pace" only for an active shilling pledge
    /// with a pace, when M-Pesa takes recurring gifts here (GET /giving/methods)
    /// and the pledge says where its money goes.
    static func offer(for pledge: Pledge, methods: GivingMethods?, schedules: [GivingSchedule]?, now: Date = Date()) -> Offer {
        guard let schedules else { return .none }
        if let s = collector(of: pledge, in: schedules) {
            return .collected(scheduleId: s.scheduleId, line: collectedLine(s, now: now))
        }
        guard let pace = pledge.pace, pledge.status == "active", !pledge.isMonthly,
              pledge.currency.uppercased() == "KES",
              let methods, methods.allowsRecurring("mpesa"),
              !(pledge.paysTo?.code ?? "").isEmpty else { return .none }
        return .collect(amountMinor: pace.perMonthMinor)
    }

    /// "Collected automatically — next KSh 5,000 on Wed 28 Oct" · "… — nothing to
    /// pay next time" (the pledge is paid through it) · "… — paused" · just
    /// "Collected automatically" when no prompt is coming (it is stopping
    /// with its pledge). `next_amount_minor` is the server's word for what
    /// the next prompt asks.
    static func collectedLine(_ s: GivingSchedule, now: Date = Date()) -> String {
        let head = "Collected automatically"
        if s.status.lowercased() == "paused" { return "\(head) — paused" }
        guard let next = s.nextAmountMinor else { return head }
        if next == 0 { return "\(head) — nothing to pay next time" }
        // The one date shape (§8.1 rule 8): "on Wed 28 Oct", the year only
        // when it isn't this year.
        let when = giveParseDate(s.nextRunAt).map { " on \(NuruDates.day($0, now: now, timeZone: GiveCalendar.nairobi))" } ?? ""
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
