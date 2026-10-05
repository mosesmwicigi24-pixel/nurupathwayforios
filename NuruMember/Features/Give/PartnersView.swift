// The Partners portal — the Give tab's PARTNERS segment (PARTNERS_PROGRAMME
// §2, contract §5; Partners UI v2, owner-approved 2026-09-24).
//
// One band (shared with Give — the GIVE · PARTNERS switch is its first row),
// then white cards in this order: STANDING · DUE · PLEDGES · STATEMENT. No
// paragraphs of explanation: the cards say what is true and offer the one
// action each thing needs. Everything is derived server-side (progress is
// computed, never stored — §1), so this view holds no second copy of the
// truth. Two rules from the original design still carry into the copy:
//
//   · `kept` is cycles COLLECTED, never cycles scheduled.
//   · nothing here ever claims "your money produced this".
//
// Joining needs no fund, no campaign and no money (§1) — the Join button
// posts `{}` and that is the whole ceremony. "Pay" never charges here: it
// opens Give pre-filled (fund, amount still due) with the pledge id riding the
// intent body (§1 rule a), so money stays on the one server-authoritative
// path (§5.6). Pause / resume / edit / cancel / reminders and "I paid another
// way" (PledgeClaims.swift) live on the pledge detail page (tap a pledge) —
// the list itself is read-only.
//
// The STATEMENT card's three numbers follow the rule shared with the server
// (partnerStatementMath.ts), Android and the docs — per currency, as the
// server sends them (`summary_by_currency`, Giving Cycle 9); an older server
// sends none, and the same rule is counted here (PledgeMath, Giving Cycle 5):
//   Paid      = Σ payments[].amountMinor where pledgeId != nil
//   Pledged   = Σ over pledges not cancelled:
//                 monthly → amountMinor × (dueDay dates in that year from
//                           max(start, 1 Jan) through min(until_on, 31 Dec)),
//                           start = the later of starts_on and the creation
//                           day — the church's (Nairobi) days
//                 total   → targetMinor if dueOn falls in that year, else 0
//   Remaining = Σ per pledge max(Pledged_i − Paid_i, 0)
// never added across currencies.
//
// The card is the PREVIEW. "Statement" on the standing card and "Partners
// statement and PDF" under the card both open PartnersStatementView — the
// partners' own statement (pledges + pledge payments + its own PDF), kept
// separate from the general giving statement (owner, 2026-09-25).
//
// FRESHNESS (live bug, 2026-09-26: a KSh 1,000 pledge payment settled but the
// Partners tab and statement kept the numbers they loaded first — both Give
// segments stay mounted, and they only ever loaded when empty). Now:
//   · stale-while-revalidate — this tab and the Partners statement ALWAYS
//     refetch the partnership + the year on screen when they appear, when the
//     segment is selected and when the app returns to the foreground, keeping
//     what they have on screen meanwhile (no spinner when there is a cache);
//   · one app-wide signal (.nuruGivingChanged) — Give posts it when a gift
//     intent is created (pending) or resolves, and when a schedule changes;
//     this model reloads on it (debounced 0.5s), and Give's own model too.
import SwiftUI
import Combine

extension Notification.Name {
    /// Posted whenever money or a schedule changed on this device (a gift
    /// intent created or resolved, a schedule created / cancelled / resumed).
    /// `object` is the model that posted, so it can ignore its own signal.
    static let nuruGivingChanged = Notification.Name("nuru.givingChanged")
}

/// Give ⇄ Partners freshness — one place to post the signal from.
enum GivingSignal {
    static func post(from sender: AnyObject? = nil) {
        NotificationCenter.default.post(name: .nuruGivingChanged, object: sender)
    }

    /// Debounced (0.5s) subscription that skips `owner`'s own posts.
    static func observe(_ owner: AnyObject, _ action: @escaping @MainActor () -> Void) -> AnyCancellable {
        NotificationCenter.default.publisher(for: .nuruGivingChanged)
            .filter { [weak owner] n in (n.object as AnyObject?) !== owner }
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { _ in Task { @MainActor in action() } }
    }
}

@MainActor final class PartnersModel: ObservableObject {
    @Published var partnership: Partnership?
    @Published var loading = false
    /// Why the portal didn't load (nothing to show yet) — spoken through the
    /// one state language (NuruStateCopy), never as the server's raw text.
    @Published var failure: Error?
    /// The pledge / schedule id with an action in flight — its control shows a
    /// spinner and refuses a second tap.
    @Published var busyId: String?
    @Published var joining = false
    /// A failed action, surfaced once in an alert and cleared. Never silent.
    @Published var actionError: String?
    /// A pledge just made whose automatic collection could not be set up
    /// (`auto_schedule_error`, Giving Cycle 5): its page says why, by pledge
    /// id, until the member dismisses it.
    @Published var pledgeNotices: [String: String] = [:]
    /// The recurring gifts (GET /giving/schedules) — which DUE instalments a
    /// pledge's collector takes care of (EXPERIENCE.md §6.4). Nil until the
    /// first answer; a failed read keeps what was known. While unknown every
    /// instalment keeps Pay: nothing is said to be collected by guesswork.
    @Published var schedules: [GivingSchedule]?

    // Statements (GET /giving/statements?year=)
    @Published var statements: GivingStatements?
    @Published var statementsLoading = false
    @Published var statementsError: String?
    @Published var statementYear = Calendar.current.component(.year, from: Date())
    /// Every year fetched this session, by year — the pledge cards' "N of M
    /// kept this year" reads the CURRENT year's payments even while the
    /// statement card is showing an earlier year.
    @Published var statementsByYear: [Int: GivingStatements] = [:]
    /// A quiet refetch failed while cached data stayed on screen — the pages
    /// say so in one muted line instead of swapping the page for an error.
    @Published private(set) var partnershipRefreshFailed = false
    @Published private(set) var statementsRefreshFailed = false
    var refreshFailed: Bool { partnershipRefreshFailed || statementsRefreshFailed }

    private var refreshing = false
    /// Visible (non-quiet) statement loads in flight — the spinner stays up
    /// until the LAST one lands, so two quick year taps never flash a year.
    private var statementLoadsInFlight = 0
    /// Every statement request is numbered; a response is filed only when no
    /// NEWER request for the same year has landed first — a slow reply (a
    /// poll tick, a refresh) never overwrites fresher data.
    private var statementsSeq = 0
    private var appliedSeqByYear: [Int: Int] = [:]
    /// The same rule for the partnership: an older reply never overwrites a newer one.
    private var partnershipSeq = 0
    private var partnershipApplied = 0
    private var givingChanged: AnyCancellable?

    init() {
        givingChanged = GivingSignal.observe(self) { [weak self] in
            Task { await self?.refresh() }
        }
    }

    var currentYearStatements: GivingStatements? {
        statementsByYear[Calendar.current.component(.year, from: Date())]
    }

    /// The year chips, newest first: this year back to the join year, at
    /// most four. One source for the Partners tab's preview card AND the
    /// full PartnersStatementView, so the two can never disagree.
    var statementYears: [Int] {
        let cal = Calendar.current
        let now = cal.component(.year, from: Date())
        let joinISO = partnership?.membership?.joinedAt ?? partnership?.since
        let joinYear = joinISO
            .flatMap { PartnerFormat.date($0) ?? giveParseDate($0) }
            .map { cal.component(.year, from: $0) } ?? now
        let first = max(min(joinYear, now), now - 3)
        return Array((first...now).reversed())
    }

    func load() async {
        loading = partnership == nil
        failure = nil
        partnershipSeq += 1
        let seq = partnershipSeq
        // Beside the partnership, so the DUE list renders once with both —
        // never Pay first, then a chip a moment later.
        async let gifts = try? MemberAPI.schedules()
        do {
            let p = try await MemberAPI.partnership()
            if seq > partnershipApplied {
                partnershipApplied = seq
                partnership = p
            }
            partnershipRefreshFailed = false
        } catch {
            if partnership == nil { failure = error }
            else { partnershipRefreshFailed = true }
        }
        if let g = await gifts { schedules = g }
        loading = false
    }

    /// Stale-while-revalidate: refetch the partnership and the year on
    /// screen (and this year's cache for the pledge cards when an earlier
    /// year is on screen). What is cached stays up meanwhile. Concurrent
    /// calls (appear + foreground + the signal) coalesce into one.
    /// `withStatement`: the Partners statement page itself asks — it must
    /// load even for a member who has left the programme (reached from the
    /// giving statement's PARTNER PLEDGES card).
    func refresh(withStatement: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        await load()
        // The statement loads for a partner, for an unknown standing (the
        // partnership failed to load), whenever one is already on screen,
        // and when the statement page asks.
        guard withStatement || statements != nil || (partnership?.isProgrammeMember ?? true) else { return }
        await loadStatements()
        let now = Calendar.current.component(.year, from: Date())
        if statementYear != now {
            statementsSeq += 1
            let seq = statementsSeq
            do { fileStatement(try await MemberAPI.givingStatements(year: now), seq: seq) }
            catch { statementsRefreshFailed = true }
        }
    }

    /// Files a fetched statement in the by-year cache unless a newer request
    /// for that year already landed. True when filed (i.e. not stale).
    @discardableResult
    private func fileStatement(_ s: GivingStatements, seq: Int) -> Bool {
        guard seq > (appliedSeqByYear[s.year] ?? 0) else { return false }
        appliedSeqByYear[s.year] = seq
        statementsByYear[s.year] = s
        return true
    }

    /// POST /giving/partners/join {} — then reload so standing/tier are the
    /// server's, not a guess.
    func join() async {
        joining = true
        defer { joining = false }
        do {
            try await MemberAPI.joinPartners()
            Haptics.success()
            await load()
            await loadStatements()   // the STATEMENT section appears with membership
        } catch {
            Haptics.error()
            actionError = GiveRefusal.from(error).message
        }
    }

    /// PATCH status — pause / resume / cancel. The list is reloaded from the
    /// server so the card's label (paused, on track…) is the computed one.
    func setStatus(_ pledge: Pledge, _ status: String) async {
        await patch(pledge.pledgeId, MemberAPI.PledgePatchBody(status: status))
    }

    func setReminders(_ pledge: Pledge, _ on: Bool) async {
        await patch(pledge.pledgeId, MemberAPI.PledgePatchBody(remindersEnabled: on))
    }

    /// Edit name / amount / due day. `amountMinor` is the new promise in the
    /// pledge's own currency — a monthly amount or a total's target (the body
    /// sends it as the one the pledge reads). `title` nil = untouched, `.set`
    /// = a new custom name, `.clear` = an explicit null so the server falls
    /// back to its derived name. Returns true on success so the sheet can close.
    @discardableResult
    func edit(_ pledge: Pledge, amountMinor: Int?, dueDay: Int?,
              title: MemberAPI.PledgePatchBody.TitlePatch? = nil) async -> Bool {
        await patch(pledge.pledgeId, .edit(pledge, commitmentMinor: amountMinor, dueDay: dueDay, title: title))
    }

    @discardableResult
    private func patch(_ id: String, _ body: MemberAPI.PledgePatchBody) async -> Bool {
        guard busyId == nil else { return false }
        busyId = id
        defer { busyId = nil }
        do {
            _ = try await MemberAPI.updatePledge(id, patch: body)
            Haptics.success()
            // A pledge's amount, day, pause and cancel move the recurring gift
            // that collects it (Giving Cycle 5) — Give's list hears of it.
            GivingSignal.post(from: self)
            await load()
            return true
        } catch {
            Haptics.error()
            actionError = GiveRefusal.from(error).message
            return false
        }
    }

    /// POST /giving/schedules/{id}/resume — the existing schedule path; it
    /// deliberately does NOT collect the cycle that was missed. Give's
    /// schedules list hears about it through the signal.
    func resumeSchedule(_ id: String) async {
        guard busyId == nil else { return }
        busyId = id
        defer { busyId = nil }
        do { try await MemberAPI.resumeSchedule(id); Haptics.success(); GivingSignal.post(from: self); await load() }
        catch {
            Haptics.error()
            actionError = GiveRefusal.from(error).message
        }
    }

    /// Always a real fetch (a year chip = GET /giving/statements?year=); the
    /// by-year cache is for the pledge cards, not for skipping the request.
    /// Stale-while-revalidate: when this year's statement is already on
    /// screen the refetch is QUIET — no spinner, and a failure keeps it (and
    /// says so via `statementsRefreshFailed`) rather than replacing it.
    func loadStatements(year: Int? = nil) async {
        let y = year ?? statementYear
        statementYear = y
        let quiet = statements?.year == y
        if !quiet { statementLoadsInFlight += 1; statementsLoading = true }
        statementsError = nil
        statementsSeq += 1
        let seq = statementsSeq
        do {
            let s = try await MemberAPI.givingStatements(year: y)
            // Stale (a newer request for this year already landed): ignored.
            // Another year chosen while this was in flight: filed, not shown.
            if fileStatement(s, seq: seq), statementYear == y {
                statements = s
                statementYear = s.year
            }
            statementsRefreshFailed = false
        } catch {
            if quiet { statementsRefreshFailed = true }
            else { statementsError = NuruStateCopy.failure(error).sentence }
        }
        if !quiet {
            statementLoadsInFlight -= 1
            statementsLoading = statementLoadsInFlight > 0
        }
    }
}

/// Pushed pages on the Partners stack.
enum PartnersRoute: Hashable {
    case pledge(String)          // a pledge's detail: payments + actions
    case receipt(String)         // a transaction's receipt
    case partnersStatement       // the partners statement + its PDF (PartnersStatementView)
    case statement               // the GENERAL giving statement (GivingStatementView) — the complete record
}

// MARK: - The statement arithmetic (shared rule — see the header comment)

enum PledgeMath {
    // MARK: The church's calendar — Africa/Nairobi, as the server counts days

    /// "2026-10-05" — string order is date order.
    static func ymd(_ y: Int, _ m: Int, _ d: Int) -> String {
        String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// The church's day (YYYY-MM-DD) of an instant.
    static func churchDay(of date: Date) -> String {
        let c = GiveCalendar.calendar.dateComponents([.year, .month, .day], from: date)
        return ymd(c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// A pledge's date as the church's day (the server's `partnerDate`): a
    /// bare YYYY-MM-DD as it is — a calendar day, never shifted; a timestamp
    /// → its Nairobi day ("2026-07-31 22:30:00+00" is 1 August); nil when
    /// absent or unreadable.
    static func churchDay(_ text: String?) -> String? {
        guard let s = text?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if isDay(s) { return s }
        return instant(s).map { churchDay(of: $0) }
    }

    /// Exactly YYYY-MM-DD.
    static func isDay(_ s: String) -> Bool {
        let c = Array(s)
        guard c.count == 10, c[4] == "-", c[7] == "-" else { return false }
        return c.enumerated().allSatisfy { i, ch in i == 4 || i == 7 || (ch.isASCII && ch.isNumber) }
    }

    /// An ISO-8601 instant, or Postgres timestamptz text as the server sends
    /// `created_at` ("2026-08-01 06:12:33.123456+00": a space for the "T",
    /// up to microseconds, a "+00" / "+03:00" / "Z" offset — none reads as
    /// UTC). Nil when it is neither.
    static func instant(_ text: String) -> Date? {
        let s = text.trimmingCharacters(in: .whitespaces)
        if let d = PartnerFormat.date(s) { return d }
        let c = Array(s)
        func num(_ at: Int, _ len: Int) -> Int? {
            guard at + len <= c.count, c[at..<at + len].allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(String(c[at..<at + len]))
        }
        guard c.count >= 19, c[4] == "-", c[7] == "-", c[10] == " " || c[10] == "T", c[13] == ":", c[16] == ":",
              let y = num(0, 4), let mo = num(5, 2), let d = num(8, 2),
              let h = num(11, 2), let mi = num(14, 2), let sec = num(17, 2) else { return nil }
        var i = 19
        var nanos = 0
        if i < c.count, c[i] == "." {
            i += 1
            var digits = ""
            while i < c.count, c[i].isASCII, c[i].isNumber { digits.append(c[i]); i += 1 }
            nanos = (Int(String((digits + "000").prefix(3))) ?? 0) * 1_000_000
        }
        var offset = 0
        if i < c.count {
            if c[i] == "Z", i == c.count - 1 {
                offset = 0
            } else if c[i] == "+" || c[i] == "-" {
                let rest = String(c[(i + 1)...]).replacingOccurrences(of: ":", with: "")
                guard rest.count == 2 || rest.count == 4, rest.allSatisfy({ $0.isASCII && $0.isNumber }),
                      let hh = Int(rest.prefix(2)), let mm = Int(rest.count == 4 ? String(rest.suffix(2)) : "0") else { return nil }
                offset = (hh * 3600 + mm * 60) * (c[i] == "-" ? -1 : 1)
            } else {
                return nil
            }
        }
        guard let zone = TimeZone(secondsFromGMT: offset) else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: sec, nanosecond: nanos))
    }

    /// Today on the church's calendar.
    static func today(now: Date = Date()) -> String { churchDay(of: now) }

    // MARK: A monthly pledge's instalments

    /// The first day a pledge's instalments can fall due: the later of its
    /// `starts_on` (a pledge collected automatically starts at its first
    /// collection) and its creation day. Nil when it has neither.
    static func start(_ p: Pledge) -> String? {
        let created = churchDay(p.createdAt)
        let starts = churchDay(p.startsOn)
        guard let created else { return starts }
        guard let starts else { return created }
        return max(starts, created)
    }

    /// The `dueDay`-of-the-month dates (held to 1–28) in `year`, on or after
    /// `from` (1 January when earlier or nil) and on or before `through`
    /// (31 December when later or nil) — the server's dueDatesInYear, listed.
    static func dueDates(in year: Int, dueDay: Int, from: String?, through: String?) -> [String] {
        let jan1 = ymd(year, 1, 1), dec31 = ymd(year, 12, 31)
        let start = from.map { max($0, jan1) } ?? jan1
        let end = through.map { min($0, dec31) } ?? dec31
        guard end >= start else { return [] }
        let day = min(28, max(1, dueDay))
        return (1...12).map { ymd(year, $0, day) }.filter { $0 >= start && $0 <= end }
    }

    /// A monthly pledge's instalments in `year`: its due day each month from
    /// its start, none after its `until_on` — and, given `through` (today,
    /// for "fallen due so far"), none after that day. A total pledge has none.
    static func instalments(_ p: Pledge, in year: Int, through: String? = nil) -> [String] {
        guard p.isMonthly else { return [] }
        var end = churchDay(p.untilOn)
        if let through { end = end.map { min($0, through) } ?? through }
        return dueDates(in: year, dueDay: p.dueDay ?? 1, from: start(p), through: end)
    }

    /// What one pledge promises in `year` (§3a): nothing once cancelled; a
    /// total pledge its target when `due_on` falls in the year; a monthly one
    /// its amount on each of its instalments in the year.
    static func pledgedInYear(_ p: Pledge, year: Int) -> Int {
        if p.status == "cancelled" { return 0 }
        guard p.isMonthly else {
            guard let due = churchDay(p.dueOn), Int(due.prefix(4)) == year else { return 0 }
            return p.targetMinor ?? 0
        }
        return (p.amountMinor ?? 0) * instalments(p, in: year).count
    }

    // MARK: "Charge me automatically" — the first collection

    /// The first `day`-of-the-month date strictly AFTER `from` (YYYY-MM-DD) —
    /// a pledge's first automatic collection, never today (the server's
    /// firstDueAfter; a day past the 28th is the 28th).
    static func firstDueAfter(_ from: String, day: Int) -> String {
        let d = min(28, max(1, day))
        guard let y = Int(from.prefix(4)), let m = Int(from.dropFirst(5).prefix(2)) else { return from }
        let same = ymd(y, m, d)
        if same > from { return same }
        return m == 12 ? ymd(y + 1, 1, d) : ymd(y, m + 1, d)
    }

    /// "5 October" — "5 January 2027" when it falls in another year than `today`.
    static func dayLabel(_ day: String, today: String) -> String {
        let words = GivingNotificationCopy.dayWords(day)
        return day.prefix(4) == today.prefix(4) ? words : "\(words) \(day.prefix(4))"
    }

    /// A monthly pledge's first instalment on or after `day`: its due day,
    /// never before its start; nil once that is past its `until_on`.
    static func nextInstalment(_ p: Pledge, onOrAfter day: String) -> String? {
        guard p.isMonthly else { return nil }
        let from = max(day, start(p) ?? day)
        let d = min(28, max(1, p.dueDay ?? 1))
        guard let y = Int(from.prefix(4)), let m = Int(from.dropFirst(5).prefix(2)) else { return nil }
        let same = ymd(y, m, d)
        let next = same >= from ? same : (m == 12 ? ymd(y + 1, 1, d) : ymd(y, m + 1, d))
        if let until = churchDay(p.untilOn), next > until { return nil }
        return next
    }

    // MARK: Pledged · Paid · Remaining — per currency

    /// One pledge's promise for the year, in its own currency.
    struct Promise: Equatable {
        let pledgeId: String
        let currency: String
        let pledgedMinor: Int
    }

    /// The year's three numbers per currency, shillings first:
    ///   Pledged   = Σ the promises
    ///   Paid      = Σ the payments that carry a pledge id
    ///   Remaining = Σ per pledge max(pledged − paid toward it, 0)
    /// Remaining is owed PER PLEDGE (Giving Cycle 5): money beyond one pledge
    /// — one paid ahead, or a cancelled one paid this year — never hides what
    /// another still owes. Nothing is added across currencies, and a payment
    /// counts toward a pledge only in the pledge's own currency. A currency
    /// with nothing in it is left out; nothing at all is one row of zeros.
    static func figures(_ promises: [Promise], payments: [PledgePayment]) -> [PartnerFigures] {
        var pledged: [String: Int] = [:], paid: [String: Int] = [:], remaining: [String: Int] = [:]
        var paidToward: [String: Int] = [:]     // "pledgeId|CUR"
        for x in payments {
            guard let id = x.pledgeId, !id.isEmpty else { continue }
            let cur = x.currency.uppercased()
            paid[cur, default: 0] += x.amountMinor
            paidToward["\(id)|\(cur)", default: 0] += x.amountMinor
        }
        for p in promises {
            let cur = p.currency.uppercased()
            pledged[cur, default: 0] += p.pledgedMinor
            remaining[cur, default: 0] += max(p.pledgedMinor - (paidToward["\(p.pledgeId)|\(cur)"] ?? 0), 0)
        }
        let rows = Set(pledged.keys).union(paid.keys)
            .map { PartnerFigures(currency: $0, pledgedMinor: pledged[$0] ?? 0, paidMinor: paid[$0] ?? 0, remainingMinor: remaining[$0] ?? 0) }
            .sorted { a, b in a.currency == "KES" ? b.currency != "KES" : (b.currency == "KES" ? false : a.currency < b.currency) }
        let live = rows.filter { $0.pledgedMinor != 0 || $0.paidMinor != 0 || $0.remainingMinor != 0 }
        return live.isEmpty ? [PartnerFigures(currency: rows.first?.currency ?? "KES", pledgedMinor: 0, paidMinor: 0, remainingMinor: 0)] : live
    }

    /// The STATEMENT numbers for `s` — one rule for the Partners tab's card
    /// and the Partners statement, so they never disagree: the server's own
    /// per-currency figures, as sent (`summary_by_currency`, Giving Cycle 9;
    /// a currency with nothing in it is left out). An older server sends
    /// none: its own three numbers when the year is in ONE currency (its sums
    /// did not separate currencies); otherwise per currency from its
    /// `pledges[]` rows and payments; with no rows, from the partnership's
    /// pledges by the same rule.
    static func figures(_ s: GivingStatements, pledges: [Pledge]) -> [PartnerFigures] {
        if let sent = s.summaryByCurrency {
            let live = sent.filter { $0.pledgedMinor != 0 || $0.paidMinor != 0 || $0.remainingMinor != 0 }
            if !live.isEmpty { return live }
            let currency = s.summaryCurrency ?? sent.first?.currency ?? "KES"
            return [PartnerFigures(currency: currency, pledgedMinor: 0, paidMinor: 0, remainingMinor: 0)]
        }
        let promises: [Promise] = s.pledges.isEmpty
            ? pledges.map { Promise(pledgeId: $0.pledgeId, currency: $0.currency, pledgedMinor: pledgedInYear($0, year: s.year)) }
            : s.pledges.map { Promise(pledgeId: $0.pledgeId, currency: $0.currency, pledgedMinor: $0.pledgedMinor) }
        let computed = figures(promises, payments: s.payments)
        guard computed.count == 1, let one = computed.first else { return computed }
        return [PartnerFigures(currency: one.currency,
                               pledgedMinor: s.pledgedMinor ?? one.pledgedMinor,
                               paidMinor: s.paidMinor ?? one.paidMinor,
                               remainingMinor: s.remainingMinor.map { max($0, 0) } ?? one.remainingMinor)]
    }

    /// The statement's per-pledge rows when the server sends none (an older
    /// server): every partnership pledge that lived in the year (an
    /// instalment or due date in it, or a payment in it), with the year's
    /// pledged / paid / kept by the same rule as the figures. A payment
    /// counts toward a pledge only in the pledge's own currency (Giving
    /// Cycle 9, as the server's rows). A cancelled pledge appears only when
    /// money was paid toward it that year, and pledges nothing.
    static func localRows(_ s: GivingStatements, pledges: [Pledge], today: String = PledgeMath.today()) -> [GivingStatements.StatementPledge] {
        let year = s.year
        // Fallen due so far: this year through today; any other, whole.
        let dueThrough: String? = Int(today.prefix(4)) == year ? today : nil
        return pledges.compactMap { pl in
            let pays = s.payments.filter { $0.pledgeId == pl.pledgeId && $0.currency.uppercased() == pl.currency.uppercased() }
            let paid = pays.reduce(0) { $0 + $1.amountMinor }
            let cancelled = pl.status == "cancelled"
            if cancelled && pays.isEmpty { return nil }
            let pledged = pledgedInYear(pl, year: year)
            let dueCount: Int
            if pl.isMonthly {
                guard !instalments(pl, in: year).isEmpty || !pays.isEmpty else { return nil }
                dueCount = instalments(pl, in: year, through: dueThrough).count
            } else {
                let dueInYear = churchDay(pl.dueOn).map { Int($0.prefix(4)) == year } ?? false
                guard dueInYear || !pays.isEmpty else { return nil }
                dueCount = dueInYear ? 1 : 0
            }
            // `kept` counts DUE DATES kept; counting payments, it is capped
            // at the due count — never "3 of 2".
            return GivingStatements.StatementPledge(
                pledgeId: pl.pledgeId, title: pl.displayTitle, shape: pl.shape,
                amountMinor: pl.amountMinor, targetMinor: pl.targetMinor, currency: pl.currency,
                status: pl.status, dueDay: pl.dueDay, dueOn: pl.dueOn, createdAt: pl.createdAt,
                pledgedMinor: pledged, paidMinor: paid, kept: min(pays.count, dueCount), dueCount: dueCount)
        }
    }

    /// Paid toward pledges in a statement: only payments that carry a pledge
    /// id (one currency's worth — see `figures` for more than one).
    static func paidMinor(_ s: GivingStatements) -> Int {
        s.pledgePayments.reduce(0) { $0 + $1.amountMinor }
    }

    /// The year's pledge payments per currency, shillings first — for lines
    /// that must never add currencies together.
    static func paidByCurrency(_ rows: [PledgePayment]) -> [CurrencyTotal] {
        GiveMoney.ordered(GiveMoney.merged(rows.map { CurrencyTotal(currency: $0.currency, totalMinor: $0.amountMinor) }))
    }

    /// Amounts in any currencies as one line, shillings first: "KSh 3,000 +
    /// US$ 20.00". All zero reads as zero in the first currency there is.
    static func line(_ totals: [CurrencyTotal]) -> String {
        let merged = GiveMoney.ordered(GiveMoney.merged(totals))
        guard merged.contains(where: { $0.totalMinor != 0 }) else {
            return GiveMoney.format(0, merged.first?.currency ?? "KES")
        }
        return GiveMoney.line(merged)
    }
}

extension GivingStatements {
    /// The payments attributed to a pledge, newest first — the only ones the
    /// Partners tab lists (gifts without a pledge stay on Give's statement).
    var pledgePayments: [PledgePayment] {
        payments
            .filter { $0.pledgeId != nil }
            .sorted { (giveParseDate($0.at) ?? .distantPast) > (giveParseDate($1.at) ?? .distantPast) }
    }

    /// Pledge payments still processing (`pending[]`), newest first — shown,
    /// NEVER totalled. A row the settled list already carries is dropped (it
    /// settled between the two reads), and only rows dated in this
    /// statement's year (or undated) are kept.
    var pendingPledgePayments: [PledgePayment] {
        let settled = Set(payments.map(\.transactionId))
        let cal = Calendar.current
        return pending
            .filter { $0.pledgeId != nil && !settled.contains($0.transactionId) }
            .filter { pay in giveParseDate(pay.at).map { cal.component(.year, from: $0) == year } ?? true }
            .sorted { (giveParseDate($0.at) ?? .distantPast) > (giveParseDate($1.at) ?? .distantPast) }
    }

    /// The statement's own title for a pledge (byPledge), when it has one.
    func pledgeTitle(for pledgeId: String) -> String? {
        let t = byPledge.first { $0.pledgeId == pledgeId }?.title ?? ""
        return t.isEmpty ? nil : t
    }
}

// MARK: - The screen

struct PartnersView: View {
    /// True when hosted as the "Partners" segment inside the Give tab (the
    /// only way in now): the page paints the shared band itself — the
    /// GIVE · PARTNERS switch, the title, one muted line — and owns its own
    /// NavigationStack for receipts / the statement / a pledge.
    var embedded: Bool = false
    /// The Give tab's current segment + the tab's selector — rendered as the
    /// band's first row when both are supplied (GiveTabView).
    var segment: GiveSegment? = nil
    var onSelectSegment: ((GiveSegment) -> Void)? = nil

    @StateObject private var vm = PartnersModel()
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    @State private var showNewPledge = false

    /// This page is what the member is looking at: its segment is selected
    /// (or it is not embedded) and the Give tab is the current tab.
    private var onScreen: Bool { (segment == nil || segment == .partners) && tabs.selected == .give }

    var body: some View {
        Group {
            if embedded {
                NavigationStack(path: $path) {
                    content
                        .nuruEdgeSwipeBack()   // back by the edge swipe on every pushed page (B9)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: PartnersRoute.self) { destination($0) }
                        // The general statement (reached from the partners
                        // statement's "Giving statement") pushes its gift rows
                        // as GivingRecord values — this stack must know them.
                        .navigationDestination(for: GivingRecord.self) { GivingReceiptView(transactionId: $0.transactionId) }
                        .inboxDestinations()   // the band's bell
                }
            } else {
                content
                    .navigationTitle("Partners")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: PartnersRoute.self) { destination($0) }
            }
        }
        // Stale-while-revalidate: ALWAYS refetch on appear, on selecting the
        // segment (both segments stay mounted, so appear alone is not enough)
        // and on returning to the foreground — cached data stays up meanwhile.
        .task { await vm.refresh() }
        .onChange(of: segment) { _, s in
            if s == .partners { Task { await vm.refresh() } }
        }
        // Tabs stay mounted too (RootView keep-alive): the Give tab coming
        // back with this segment showing is an "appear" that .task never sees.
        .onChange(of: tabs.selected) { _, _ in
            if onScreen { Task { await vm.refresh() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && onScreen { Task { await vm.refresh() } }
        }
        // A pledge notice, or a gift that collects a pledge (Giving Cycle 5):
        // that pledge's page, with this list as the back stop. Consumed once.
        .onReceive(tabs.$pledgeLink) { id in
            guard let id else { return }
            DispatchQueue.main.async { tabs.pledgeLink = nil }
            path = NavigationPath([PartnersRoute.pledge(id)])
        }
        // A re-tap on Give while Partners shows returns to its top (§7.4 #17).
        .popsToRoot(on: .give, path: $path, when: { segment == nil || segment == .partners })
        .fullScreenCover(isPresented: $showNewPledge) {
            NewPledgeFlow(isMember: vm.partnership?.isProgrammeMember ?? false,
                          pledgeOptions: vm.partnership?.pledgeOptions ?? [],
                          campaigns: vm.partnership?.campaigns ?? []) { pledge, autoScheduleError in
                // Made, but its automatic collection could not be set up
                // (Giving Cycle 5): land on the pledge, which says why.
                if let note = autoScheduleError, !pledge.pledgeId.isEmpty {
                    vm.pledgeNotices[pledge.pledgeId] = note
                    path.append(PartnersRoute.pledge(pledge.pledgeId))
                }
                // Pledged is derived from the pledges, so a reload of the
                // partnership + the year on screen is enough — never jump the
                // member back to this year if they were reading an earlier one.
                Task {
                    await vm.load()
                    await vm.loadStatements()
                }
            }
        }
        .alert("That didn't go through", isPresented: Binding(get: { vm.actionError != nil }, set: { if !$0 { vm.actionError = nil } })) {
            Button("OK") { vm.actionError = nil }
        } message: { Text(vm.actionError ?? "") }
    }

    @ViewBuilder private func destination(_ route: PartnersRoute) -> some View {
        switch route {
        case .pledge(let id):
            PledgeDetailView(pledgeId: id, seed: vm.partnership?.pledges.first { $0.pledgeId == id }, vm: vm)
        case .receipt(let tx):
            // This stack has a pledge page, so the receipt's Pledge row can
            // open it; the Give stack has none and leaves the row plain.
            GivingReceiptView(transactionId: tx) { id in path.append(PartnersRoute.pledge(id)) }
        case .partnersStatement:
            PartnersStatementView(vm: vm)
        case .statement:
            GivingStatementView(host: .partners)
        }
    }

    private var content: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    sections
                }
                .scrollsToTopOnReselect(.give)   // a re-tap at the root returns to the top (B10)
                .padding(.horizontal, Nuru.S.base)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, embedded ? Nuru.tabBarSpace : 40)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if embedded { band }
            }
            .refreshable {
                await vm.load()
                await vm.loadStatements()
            }
        }
        .ignoresSafeArea(edges: embedded ? .top : [])
    }

    @ViewBuilder private var sections: some View {
        if vm.partnership != nil && vm.refreshFailed {
            Text("Couldn't refresh just now — showing what we last had.")
                .font(.inter(11)).foregroundStyle(Nuru.ink400)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        if let p = vm.partnership {
            if p.isProgrammeMember {
                StandingCard(partnership: p,
                             faithfulness: vm.currentYearStatements?.faithfulness,
                             onPledge: { Haptics.tap(); showNewPledge = true },
                             onStatement: { Haptics.tap(); path.append(PartnersRoute.partnersStatement) })
                if !p.due.isEmpty { dueSection(p) }
                if let t = p.trouble {
                    TroubleRow(
                        trouble: t,
                        resuming: vm.busyId != nil && vm.busyId == p.scheduleId,
                        onResume: p.scheduleId.map { id in { Task { await vm.resumeSchedule(id) } } })
                }
                pledgesSection(p)
                statementSection(p)
            } else {
                joinCard(p)
            }
        } else if let f = vm.failure, !vm.loading {
            errorState(f)
        } else {
            // Loading — and the first frame before the first read begins.
            ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.top, 60)
        }
    }

    // MARK: The band (the same cream band Give paints — one band, not two)

    private var band: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let segment, let onSelectSegment {
                GiveSwitchRow(selection: segment, onSelect: onSelectSegment)
                    .padding(.bottom, 12)
            }
            // The one header's words (§8.1 rules 2–3); the switch above
            // names the tab, so no eyebrow repeats it.
            NuruHeaderText(title: "Walk with the church", line: "Decide in advance. The church can plan.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        // Right under the status bar — the real inset, never a fixed 60.
        .padding(.top, NuruSafeArea.top + 8)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Not yet a partner — one card, one line, one button

    private func joinCard(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow("JOIN THE PARTNERS PROGRAMME")
            Text("Become a partner")
                .font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
            Text("Joining costs nothing today. A pledge can come later.")
                .font(.inter(13)).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.action()
                Task { await vm.join() }
            } label: {
                HStack(spacing: 8) {
                    if vm.joining { ProgressView().tint(Nuru.navy).scaleEffect(0.8) }
                    Text(vm.joining ? "Joining…" : "Join the programme").font(.inter(14, .bold))
                    if !vm.joining { Icon(.arrowRight, size: 14, color: Nuru.navy) }
                }
                .foregroundStyle(Nuru.navy)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Nuru.gold, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(vm.joining)
            .padding(.top, 4)
        }
        .partnerCard()
    }

    // MARK: Due — soonest first, one action each

    /// "DUE" only within the fortnight; further out the same rows read
    /// "COMING UP" (EXPERIENCE.md §9.3 rule 2) — Pay still there, for paying
    /// early. A total pledge's 31 Dec read "DUE" 87 days ahead.
    private func dueSection(_ p: Partnership) -> some View {
        let today = PauseDates.wire(Date())
        let soon = p.due.filter { HomeWeek.dueIsSoon($0, today: today) }
        let later = p.due.filter { !HomeWeek.dueIsSoon($0, today: today) }
        return VStack(alignment: .leading, spacing: 16) {
            if !soon.isEmpty { dueGroup("DUE", soon, p) }
            if !later.isEmpty { dueGroup("COMING UP", later, p) }
        }
    }

    private func dueGroup(_ label: String, _ rows: [DueItem], _ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow(label)
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, item in
                    dueRow(item, p)
                    if i != rows.count - 1 {
                        Divider().overlay(Nuru.border).padding(.vertical, 10)
                    }
                }
            }
            .partnerCard()
        }
    }

    private func dueRow(_ item: DueItem, _ p: Partnership) -> some View {
        let busy = vm.busyId == item.id
        // `pending_minor`: money toward this instalment already started. All
        // of it → Processing, no Pay (a second tap would pay it twice). Part
        // of it → Pay stays, for what is still uncovered.
        let partial = item.kind == "pledge" && item.action != "resume" && item.pendingMinor > 0 && !item.fullyPending
        let when = dueWhen(item)
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(partial
                     ? "\(money(item.uncoveredMinor, item.currency)) left · \(when.text)"
                     : "\(money(item.amountMinor, item.currency)) · \(when.text)")
                    .font(.nRowTitle)   // a content row (§8.1 rule 3)
                    .foregroundStyle(when.overdue ? Nuru.goldChipText : Nuru.ink)
                Text(partial
                     ? "\(dueSubtitle(item, p)) · \(money(item.pendingMinor, item.currency)) processing"
                     : dueSubtitle(item, p))
                    .font(.inter(12)).foregroundStyle(Nuru.ink600).lineLimit(1)
                // What the office is already checking, on the row it covers
                // (§9.3 rule 1): said, never subtracted — the row and Pay
                // still ask what is owed.
                if let claim = item.claimLine {
                    Text(claim)
                        .font(.inter(12, .semibold)).foregroundStyle(Nuru.goldChipText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            if item.fullyPending {
                Text(pendingChipText(item))
                    .font(.inter(11, .bold)).foregroundStyle(Nuru.urgentText)
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Nuru.urgentBg, in: Capsule())
                    .accessibilityLabel("\(pendingChipText(item)) — this payment is already on its way")
            } else if item.kind == "schedule", item.action != "resume", let collected = ScheduleRhythm.collectedOn(item.dueOn) {
                // A running recurring gift collects itself — no Pay, which
                // gave a second, one-time gift (owner, 2026-09-28). A tap
                // opens the gift's own sheet on Give (pause, change).
                collectedChip(collected, label: "\(collected), automatically. Opens the recurring gift.") {
                    tabs.openGive(link: .schedule(scheduleId: item.id))
                }
            } else if let pledge = p.pledges.first(where: { $0.pledgeId == item.id }),
                      let day = PledgePace.collectedDay(item, by: vm.schedules.flatMap { PledgePace.collector(of: pledge, in: $0) }),
                      let collected = ScheduleRhythm.collectedOn(day) {
                // A pledge whose collector prompts on or before the date says
                // so too (EXPERIENCE.md §6.4) — the same chip. A tap opens the
                // pledge, where paying early by hand stays possible.
                collectedChip(collected, label: "\(collected), automatically. Opens the pledge.") {
                    path.append(PartnersRoute.pledge(item.id))
                }
            } else {
                Button {
                    Haptics.action()
                    act(on: item, p)
                } label: {
                    HStack(spacing: 6) {
                        if busy { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text(item.action == "resume" ? "Resume" : "Pay").font(.inter(13, .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 36)
                    .background(Nuru.navy, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(busy)
            }
        }
    }

    /// "Collected on Mon 5 Oct" — the gold chip a DUE row wears in place of
    /// Pay when a prompt will take care of it: a running recurring gift, or
    /// a pledge's collector (§6.4). One look for both.
    private func collectedChip(_ text: String, label: String, open: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            open()
        } label: {
            Text(text)
                .font(.inter(12, .semibold)).foregroundStyle(Nuru.goldChipText)
                .lineLimit(1).minimumScaleFactor(0.92)
                .padding(.horizontal, 12).frame(height: 32)
                .background(Nuru.goldChipBg, in: Capsule())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(label)
    }

    /// "Waiting for M-Pesa" when the rail of the in-flight payment is known
    /// (the statement's `pending[]` row for this pledge), else "Processing".
    private func pendingChipText(_ item: DueItem) -> String {
        switch vm.currentYearStatements?.pending.first(where: { $0.pledgeId == item.id })?.method {
        case "mpesa": return "Waiting for M-Pesa"
        case "airtel": return "Waiting for Airtel Money"
        default: return "Processing"
        }
    }

    /// "Recurring gift · M-Pesa" for a schedule run; the pledge's title otherwise.
    private func dueSubtitle(_ item: DueItem, _ p: Partnership) -> String {
        if item.kind == "schedule" {
            let method = p.rhythm.map { givingMethodName($0.method) }
            return ["Recurring gift", method].compactMap { $0 }.joined(separator: " · ")
        }
        return item.title.isEmpty ? "Pledge" : item.title
    }

    private func act(on item: DueItem, _ p: Partnership) {
        switch (item.kind, item.action) {
        case ("schedule", "resume"):
            Task { await vm.resumeSchedule(item.id) }
        case ("pledge", "resume"):
            if let pl = p.pledges.first(where: { $0.pledgeId == item.id }) { Task { await vm.setStatus(pl, "active") } }
        case ("pledge", _):
            let pl = p.pledges.first { $0.pledgeId == item.id }
            // Pre-fill only what is still uncovered — money already on its
            // way toward this instalment is never asked for twice.
            tabs.openGive(preset: GivePreset(fund: pl?.fund?.code,
                                             amountMinor: item.pendingMinor > 0 ? item.uncoveredMinor : item.amountMinor,
                                             pledgeId: item.id,
                                             pledgeTitle: pl?.displayTitle ?? (item.title.isEmpty ? nil : item.title),
                                             pledgeAmountLine: pl.map { pledgeAmountLine($0) },
                                             paysTo: item.paysTo ?? pl?.paysTo,
                                             currency: pl?.currency ?? item.currency))
        default:
            tabs.openGive(preset: GivePreset(fund: nil, amountMinor: item.amountMinor, pledgeId: nil))
        }
    }

    /// When a DUE row is due. A pledge instalment whose date (or the
    /// server's `overdue_since`) has passed reads "overdue since 10 Aug" —
    /// "2 overdue since 10 Aug" when `overdue_count` ≥ 2, the date from
    /// `overdue_since` when present — in amber (goldChipText, 0x7A5A14).
    /// Otherwise today · tomorrow · in N days · the date. A schedule row is
    /// never "overdue" (a paused schedule owes nothing).
    private func dueWhen(_ item: DueItem) -> (text: String, overdue: Bool) {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func past(_ iso: String?) -> Bool {
            guard let iso, let d = giveParseDate(iso) else { return false }
            return cal.startOfDay(for: d) < today
        }
        guard item.kind == "pledge", past(item.dueOn) || past(item.overdueSince) else {
            return (relativeDay(item.dueOn), false)
        }
        let iso = item.overdueSince ?? item.dueOn
        let sameYear = giveParseDate(iso).map { cal.component(.year, from: $0) == cal.component(.year, from: today) } ?? true
        let since = sameYear ? giveDateShort(iso) : giveDateFull(iso)
        return (item.overdueCount >= 2 ? "\(item.overdueCount) overdue since \(since)" : "overdue since \(since)", true)
    }

    /// today · tomorrow · in N days · else the date.
    private func relativeDay(_ ymd: String) -> String {
        guard let d = giveParseDate(ymd) else { return ymd }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today" }
        if cal.isDateInTomorrow(d) { return "tomorrow" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: d)).day ?? 0
        if days > 1 && days <= 14 { return "in \(days) days" }
        return giveDateShort(ymd)
    }

    // MARK: Pledges — read-only cards; tap for the detail + actions

    private func pledgesSection(_ p: Partnership) -> some View {
        let live = p.pledges.filter { $0.status != "cancelled" }
        let active = live.filter { $0.status == "active" }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                eyebrow("PLEDGES")
                Spacer()
                if !live.isEmpty {
                    Text("\(active) active").font(.inter(11)).foregroundStyle(Nuru.ink400)
                }
            }
            if live.isEmpty {
                Text("No pledges yet — monthly, or a total by a date.")
                    .font(.inter(13)).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)
                    .partnerCard()
            } else {
                VStack(spacing: 12) {
                    ForEach(live) { pledge in
                        Button {
                            Haptics.tap()
                            path.append(PartnersRoute.pledge(pledge.pledgeId))
                        } label: {
                            PledgeCard(pledge: pledge, keptLine: keptLine(pledge))
                        }
                        .buttonStyle(.pressableSubtle)
                    }
                }
            }
        }
    }

    /// "9 of 12 kept this year". The SERVER's figures first: the CURRENT
    /// year's statement `pledges[]` entry for this pledge (matched by
    /// pledge_id) carries `kept` / `due_count` from its FIFO instalment ledger
    /// — payments fill due dates oldest first, kept = on time or late, and
    /// due_count counts only RESOLVED instalments (one due today and unpaid
    /// is not yet counted). Shown as sent.
    /// Fallback, only when that entry is absent (an older server): payments
    /// this year carrying this pledge id, capped at its instalments fallen due
    /// so far (from its start, none after until_on) — never "3 of 2". Nil
    /// until the statement has loaded, or while nothing has fallen due
    /// (due_count 0); the card then shows no text.
    private func keptLine(_ pledge: Pledge) -> String? {
        guard pledge.isMonthly, let s = vm.currentYearStatements else { return nil }
        if !pledge.pledgeId.isEmpty,
           let entry = s.pledges.first(where: { $0.pledgeId == pledge.pledgeId }) {
            guard entry.dueCount > 0 else { return nil }
            return "\(entry.kept) of \(entry.dueCount) kept this year"
        }
        let today = PledgeMath.today()
        let elapsed = PledgeMath.instalments(pledge, in: Int(today.prefix(4)) ?? s.year, through: today).count
        guard elapsed > 0 else { return nil }
        let paid = s.payments.filter { $0.pledgeId == pledge.pledgeId }.count
        return "\(min(paid, elapsed)) of \(elapsed) kept this year"
    }

    // MARK: Statement — year chips, three numbers, the pledge payments (the preview)

    private func statementSection(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                eyebrow("STATEMENT")
                Spacer()
                yearChips
            }
            statementCard(p)
        }
        // No load here: vm.refresh() (appear / segment / foreground / signal)
        // and join() both load the statement.
    }

    private var yearChips: some View {
        HStack(spacing: 6) {
            ForEach(vm.statementYears, id: \.self) { y in
                let on = vm.statementYear == y
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    Task { await vm.loadStatements(year: y) }
                } label: {
                    Text(String(y)).font(.inter(12, .semibold))
                        .foregroundStyle(on ? .white : Nuru.navy)
                        .padding(.horizontal, 11).frame(height: 28)
                        .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
    }

    @ViewBuilder private func statementCard(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let s = vm.statements, !vm.statementsLoading {
                statementBody(s, p)
            } else if vm.statementsLoading || (vm.statements == nil && vm.statementsError == nil) {
                ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let e = vm.statementsError {
                retryRow(e) { Task { await vm.loadStatements() } }
            }
        }
        .partnerCard()
    }

    private func statementBody(_ s: GivingStatements, _ p: Partnership) -> some View {
        // One line per currency (shillings first), never one sum across them.
        let figures = PledgeMath.figures(s, pledges: p.pledges)
        let rows = s.pledgePayments
        let pending = s.pendingPledgePayments
        // Three "KSh 0" tiles say nothing (§7.4 #9; the walks' E14/A1 for
        // Ben): the figures show once any of them is more than nothing.
        let anyFigure = figures.contains { $0.pledgedMinor != 0 || $0.paidMinor != 0 || $0.remainingMinor != 0 }
        return VStack(alignment: .leading, spacing: 0) {
            if anyFigure {
                HStack(alignment: .top, spacing: 8) {
                    summaryColumn("Pledged", figures.map { money($0.pledgedMinor, $0.currency) }, Nuru.navy)
                    summaryColumn("Paid", figures.map { money($0.paidMinor, $0.currency) }, Nuru.successText)
                    summaryColumn("Remaining", figures.map { money($0.remainingMinor, $0.currency) }, Nuru.goldLo)
                }

                Divider().overlay(Nuru.border).padding(.vertical, 14)
            }

            // Still processing: listed first, never in Paid above.
            ForEach(pending) { pay in
                Button { Haptics.tap(); path.append(PartnersRoute.receipt(pay.transactionId)) } label: {
                    PendingPledgePaymentRow(payment: pay, title: pay.pledgeTitle ?? paymentTitle(pay, s, p))
                }
                .buttonStyle(.pressableSubtle)
                .disabled(pay.transactionId.isEmpty)
                Divider().overlay(Nuru.border)
            }
            if rows.isEmpty && pending.isEmpty {
                Text("No pledge payments in \(String(s.year)).")
                    .font(.inter(13)).foregroundStyle(Nuru.ink600)
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, pay in
                    StatementPaymentRow(payment: pay, title: paymentTitle(pay, s, p)) {
                        path.append(PartnersRoute.receipt(pay.transactionId))
                    }
                    if i != rows.count - 1 {
                        Divider().overlay(Nuru.border)
                    }
                }
            }

            Button {
                Haptics.tap(); path.append(PartnersRoute.partnersStatement)
            } label: {
                HStack(spacing: 4) {
                    Text("Partners statement and PDF").font(.inter(13, .semibold))
                    Icon(.arrowRight, size: 14, color: Nuru.gold)
                }
                .foregroundStyle(Nuru.gold)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryColumn(_ label: String, _ values: [String], _ tint: Color) -> some View {
        partnerSummaryColumn(label, values, tint)
    }

    /// The statement's own title for the pledge, else the pledge's name.
    private func paymentTitle(_ pay: PledgePayment, _ s: GivingStatements, _ p: Partnership) -> String {
        guard let id = pay.pledgeId else { return "Pledge" }
        if let t = s.pledgeTitle(for: id) { return t }
        if let pl = p.pledges.first(where: { $0.pledgeId == id }) { return pl.displayTitle }
        return "Pledge"
    }

    // MARK: Error / retry states

    /// Nothing loaded yet and the read failed — what really happened, in the
    /// one state language (§4). (A failed refresh over a loaded portal keeps
    /// the portal and says so in its own row.)
    private func errorState(_ failure: Error) -> some View {
        NuruStateView(state: .failed(.failure(failure)), retry: { Task { await vm.load() } })
            .padding(.top, 24)
    }

    private func retryRow(_ message: String, retry: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(message).font(.nCaption).foregroundStyle(Nuru.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button { Haptics.tap(); retry() } label: {
                Text("Try again").font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Atoms shared by the cards (and by PartnersStatementView)

/// ONE-word eyebrow: `.inter(9, .semibold)`, kerning 1.6, goldLo.
func eyebrow(_ s: String) -> some View {
    Text(s).font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Nuru.goldLo)
}

/// The Partners card: white, border stroke, radius 16, 16pt padding.
struct PartnerCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}
extension View {
    func partnerCard() -> some View { modifier(PartnerCardStyle()) }
}

/// One column of the Pledged / Paid / Remaining card: the label, then one
/// amount per currency — the same currency on the same line in every column.
func partnerSummaryColumn(_ label: String, _ values: [String], _ tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 3) {
        Text(label.uppercased()).font(.inter(11, .semibold)).kerning(1.2).foregroundStyle(Nuru.ink400)
        ForEach(Array(values.enumerated()), id: \.offset) { _, value in
            Text(value).font(.inter(16, .semibold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
}

/// "Partner since Sep 2026" — month + year from the membership's joinedAt,
/// else the derived `since`; just "Partner" when neither is present. The
/// standing card and the partners statement share it so they agree.
func partnerSinceLine(_ partnership: Partnership) -> String {
    let iso = partnership.membership?.joinedAt ?? partnership.since
    guard let iso, let d = PartnerFormat.date(iso) ?? giveParseDate(iso) else { return "Partner" }
    let f = DateFormatter(); f.dateFormat = "MMM yyyy"
    return "Partner since \(f.string(from: d))"
}

func ordinal(_ n: Int) -> String {
    let suffix: String
    switch n % 100 {
    case 11, 12, 13: suffix = "th"
    default:
        switch n % 10 {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
    }
    return "\(n)\(suffix)"
}

/// The promise in one line, under the pledge's name: "KSh 2,000 monthly ·
/// due on the 5th", or "KSh 50,000 · by 15 Dec" (the year only when it
/// isn't this one). Shared by the card, the detail page and the partners
/// statement so they agree.
func pledgeAmountLine(_ p: Pledge) -> String {
    pledgeAmountLine(isMonthly: p.isMonthly, amountMinor: p.amountMinor, targetMinor: p.targetMinor,
                     currency: p.currency, dueDay: p.dueDay, dueOn: p.dueOn)
}

func pledgeAmountLine(_ p: GivingStatements.StatementPledge) -> String {
    pledgeAmountLine(isMonthly: p.isMonthly, amountMinor: p.amountMinor, targetMinor: p.targetMinor,
                     currency: p.currency, dueDay: p.dueDay, dueOn: p.dueOn)
}

func pledgeAmountLine(isMonthly: Bool, amountMinor: Int?, targetMinor: Int?,
                      currency: String, dueDay: Int?, dueOn: String?) -> String {
    if isMonthly {
        var parts = ["\(money(amountMinor ?? 0, currency)) monthly"]
        if let d = dueDay { parts.append("due on the \(ordinal(d))") }
        return parts.joined(separator: " · ")
    }
    var parts = [money(targetMinor ?? 0, currency)]
    if let iso = dueOn, let d = giveParseDate(iso) {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: Date())
        parts.append("by \(sameYear ? giveDateShort(iso) : giveDateFull(iso))")
    }
    return parts.joined(separator: " · ")
}

// MARK: - Standing

private struct StandingCard: View {
    let partnership: Partnership
    /// The CURRENT year's statement `faithfulness` — nil until it loads (or
    /// on an older server).
    let faithfulness: GivingStatements.Faithfulness?
    let onPledge: () -> Void
    let onStatement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            eyebrow("STANDING")

            // A standing only once there is one — a pledge or a gift that
            // went through (the Android walk's A1: Ben read "Partner since
            // Oct 2026 · 0 gifts kept" and a tier beside a gift that failed).
            if PartnerStanding.isReal(partnership) {
                standingRow
            } else {
                Text(PartnerStanding.notYet)
                    .font(.nCardBody).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                // The ONLY gold-filled button on the page.
                Button(action: onPledge) {
                    HStack(spacing: 6) {
                        Icon(.plus, size: 14, color: Nuru.navy)
                        Text("Make a pledge").font(.inter(14, .bold))
                    }
                    .foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Nuru.gold, in: Capsule())
                }
                .buttonStyle(.pressable)

                Button(action: onStatement) {
                    Text("Statement").font(.inter(14, .semibold))
                        .foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(Nuru.navy, lineWidth: 1.2))
                }
                .buttonStyle(.pressable)
            }
        }
        .partnerCard()
    }

    /// Since · kept, and the tier — shown once the standing is real.
    private var standingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(sinceLine).font(.inter(16, .semibold)).foregroundStyle(Nuru.ink)
                Text(keptLine).font(.inter(12)).foregroundStyle(Nuru.ink600)
            }
            Spacer(minLength: 8)
            if let t = partnership.tier, !t.name.isEmpty {
                HStack(spacing: 5) {
                    Icon(.award, size: 14, color: Nuru.goldChipText)
                    Text(t.name).font(.inter(11, .bold)).foregroundStyle(Nuru.goldChipText)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Nuru.goldChipBg, in: Capsule())
                .accessibilityElement(children: .ignore)
                // The tier sentence lives here and nowhere on screen.
                .accessibilityLabel("\(t.name) partner — \(money(t.monthlyMinor, partnership.currency)) a month. KSh 20,000 carries one disciple through a level.")
            }
        }
    }

    /// "Partner since Sep 2026" — the shared formatter (partnerSinceLine).
    private var sinceLine: String { partnerSinceLine(partnership) }

    /// The standing line. "Kept" has ONE meaning — a due date paid in full,
    /// on time or late (owner, 2026-09-25):
    ///   · a partner with pledges: "<kept_on_time + late> commitments kept
    ///     this year · on track|behind" from the CURRENT year's statement
    ///     `faithfulness` — the count left out while it is 0 and nothing has
    ///     fallen due yet (or before that statement has loaded);
    ///   · a schedule-only partner (no live pledge): "N gifts kept" —
    ///     `partnership.kept`, the recurring schedule's collected cycles
    ///     (which is why it read "0 gifts kept" beside "2 of 2 kept").
    private var keptLine: String {
        let paused = partnership.membership?.status == "paused" || partnership.status == "paused"
        guard partnership.pledges.contains(where: { $0.status != "cancelled" }) else {
            let n = partnership.kept
            let gifts = n == 1 ? "1 gift kept" : "\(n) gifts kept"
            return "\(gifts) · \(paused ? "paused" : "on track")"
        }
        let state = paused ? "paused" : (behind ? "behind" : "on track")
        let kept = max(0, faithfulness?.keptOnTime ?? 0) + max(0, faithfulness?.late ?? 0)
        let due = max(0, faithfulness?.dueCount ?? 0)
        guard faithfulness != nil, kept > 0 || due > 0 else {
            return state.prefix(1).uppercased() + state.dropFirst()
        }
        return "\(kept) commitment\(kept == 1 ? "" : "s") kept this year · \(state)"
    }

    /// Behind when a resolved instalment went unkept this year
    /// (`faithfulness`: missed, else kept < due), or when the server labels
    /// any active pledge behind — so this line never says "on track" above a
    /// pledge card that says "Behind".
    private var behind: Bool {
        if let f = faithfulness, let due = f.dueCount {
            let kept = max(0, f.keptOnTime ?? 0) + max(0, f.late ?? 0)
            if (f.missed.map { $0 > 0 } ?? (kept < due)) { return true }
        }
        return partnership.pledges.contains { $0.status == "active" && $0.progress.label == "behind" }
    }
}

// MARK: - Trouble (only when there is some — one compact amber row)

private struct TroubleRow: View {
    let trouble: Partnership.Trouble
    let resuming: Bool
    let onResume: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.symbol(13, weight: .semibold))
                .foregroundStyle(Nuru.urgentText)
            Text(trouble.paused ? "Your giving is paused — nothing is owed." : "One gift didn't go through — nothing is owed.")
                .font(.inter(12, .semibold)).foregroundStyle(Nuru.urgentText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if trouble.paused, let onResume {
                Button { Haptics.action(); onResume() } label: {
                    HStack(spacing: 6) {
                        if resuming { ProgressView().tint(.white).scaleEffect(0.7) }
                        Text("Resume").font(.inter(12, .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(Nuru.navy, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(resuming)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.urgentBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - One pledge (read-only card; the detail page holds the actions)

private struct PledgeCard: View {
    let pledge: Pledge
    /// "9 of 12 kept this year" — supplied by the screen (needs the statement).
    let keptLine: String?

    private var paused: Bool { pledge.status == "paused" || pledge.progress.label == "paused" }
    private var fulfilled: Bool { pledge.status == "fulfilled" || pledge.progress.label == "fulfilled" }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    // The pledge's NAME leads (pledge names contract); the
                    // promise itself sits under it.
                    // A pledge is a content row (§8.1 rule 3); its name wraps
                    // to two lines rather than being cut (rule 9).
                    Text(pledge.displayTitle).font(.nRowTitle).foregroundStyle(Nuru.ink)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Text(pledgeAmountLine(pledge)).font(.inter(12)).foregroundStyle(Nuru.ink600).lineLimit(1)
                }
                Spacer(minLength: 8)
                stateChip
            }

            // 6pt gold bar — this period for monthly, toward the target for total.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.mutedBg)
                    Capsule().fill(Nuru.gold)
                        .frame(width: max(pledge.fraction > 0 ? 6 : 0, geo.size.width * pledge.fraction))
                }
            }
            .frame(height: 6)
            .accessibilityLabel("\(Int((pledge.fraction * 100).rounded())) percent")

            HStack(spacing: 8) {
                Text(leftLine).font(.inter(11)).foregroundStyle(Nuru.ink600).lineLimit(1)
                Spacer(minLength: 8)
                if let n = nextLine {
                    Text(n.text)
                        .font(.inter(11, n.overdue ? .semibold : .regular))
                        .foregroundStyle(n.overdue ? Nuru.goldChipText : Nuru.ink600)
                        .lineLimit(1)
                }
            }
        }
        .partnerCard()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(paused ? 0.92 : 1)
    }

    /// Monthly: "9 of 12 kept this year"; total: "KSh 20,000 paid · 30,000 to go".
    private var leftLine: String {
        if pledge.isMonthly { return keptLine ?? "" }
        let paid = pledge.progress.paidMinor
        let toGo = max(0, (pledge.targetMinor ?? 0) - paid)
        return "\(money(paid, pledge.currency)) paid · \(GiveMoney.figures(toGo, pledge.currency)) to go"
    }

    /// "Next 10 Oct" — or, once the server's next due has passed unpaid (it
    /// is then the oldest unpaid instalment), "Overdue since 10 Aug" in amber.
    private var nextLine: (text: String, overdue: Bool)? {
        if fulfilled || paused { return nil }
        guard let n = pledge.progress.nextDue, !n.isEmpty else { return nil }
        let cal = Calendar.current
        if let d = giveParseDate(n), cal.startOfDay(for: d) < cal.startOfDay(for: Date()) {
            let sameYear = cal.component(.year, from: d) == cal.component(.year, from: Date())
            return ("Overdue since \(sameYear ? giveDateShort(n) : giveDateFull(n))", true)
        }
        return ("Next \(giveDateShort(n))", false)
    }

    private var stateChip: some View {
        let (bg, fg, text): (Color, Color, String) = {
            switch (pledge.status, pledge.progress.label) {
            case ("paused", _), (_, "paused"): return (Nuru.mutedBg, Nuru.ink600, "Paused")
            case ("fulfilled", _), (_, "fulfilled"): return (Nuru.successBg, Nuru.successText, "Fulfilled")
            case (_, "behind"): return (Nuru.goldChipBg, Nuru.goldChipText, "Behind")
            default: return (Nuru.successBg, Nuru.successText, "On track")
            }
        }()
        return Text(text).font(.inter(11, .bold)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3).background(bg, in: Capsule())
    }
}

/// One statement line: "20 Sep · Monthly pledge" over "Tithe · UIKJ2713B5",
/// amount right-aligned; tapping opens the receipt.
private struct StatementPaymentRow: View {
    let payment: PledgePayment
    let title: String
    let onOpen: () -> Void

    var body: some View {
        Button { Haptics.tap(); onOpen() } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(giveDateShort(payment.at)) · \(title)")
                        .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
                    if !meta.isEmpty {
                        Text(meta).font(.inter(11)).foregroundStyle(Nuru.ink400).lineLimit(1)
                    }
                }
                Spacer(minLength: 8)
                Text(money(payment.amountMinor, payment.currency))
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    .lineLimit(1).layoutPriority(1)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }

    /// Fund when known, then the receipt code (the row's own `method` is not
    /// on the wire, so it is never guessed).
    private var meta: String {
        var parts: [String] = []
        if let f = payment.fund, !f.isEmpty { parts.append(f.capitalized) }
        if let r = payment.receiptCode, !r.isEmpty { parts.append(r) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - A pledge's detail (GET /giving/pledges/{id}) — payments + actions,
// and what the member told the office they paid another way (…/claims)

struct PledgeDetailView: View {
    let pledgeId: String
    /// The list's copy of the pledge, so the header renders before the fetch.
    var seed: Pledge? = nil
    /// The screen's model — actions (pause / resume / edit / cancel /
    /// reminders) go through it so the list reloads with the server's labels.
    @ObservedObject var vm: PartnersModel

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabs: TabRouter
    @State private var detail: PledgeDetail?
    @State private var loading = true
    @State private var error: String?
    @State private var editing: Pledge?
    @State private var cancelling: Pledge?
    /// "I paid another way" is open for this pledge.
    @State private var claiming: Pledge?
    /// What the member has told the office (GET …/claims), newest first;
    /// nil until it has loaded.
    @State private var claims: [PledgeClaim]?
    @State private var claimsFailed = false
    @ObservedObject private var sync = SyncCoordinator.shared
    /// What collecting this pledge automatically needs to know (Giving Cycle
    /// 9): the rails (GET /giving/methods) and the recurring gifts (GET
    /// /giving/schedules). Nil until they answer — the offer waits for both.
    @State private var methods: GivingMethods?
    @State private var schedules: [GivingSchedule]?
    /// "Collect it automatically at this pace": in flight, its refusal in the
    /// server's words, and its key (kept only when no answer came).
    @State private var startingPace = false
    @State private var paceError: String?
    @State private var paceKey = GiveKey.fresh()

    /// Freshest first: the fetched detail, then the list's live copy, then the seed.
    private var pledge: Pledge? {
        detail?.pledge ?? vm.partnership?.pledges.first { $0.pledgeId == pledgeId } ?? seed
    }
    private var busy: Bool { vm.busyId == pledgeId }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    if let note = vm.pledgeNotices[pledgeId] {
                        autoScheduleNotice(note)
                    }
                    if let p = pledge {
                        VStack(alignment: .leading, spacing: 4) {
                            // The name is the page's header; this card carries the promise.
                            Text(pledgeAmountLine(p)).font(.nuruDisplay(22)).foregroundStyle(Nuru.ink)
                            Text(PledgeWords.progressLine(p))
                                .font(.nCaption).foregroundStyle(Nuru.ink600)
                            // A total pledge's pace (Giving Cycle 9), as the server sets it.
                            if let pace = PledgePace.line(p) {
                                HStack(alignment: .top, spacing: 6) {
                                    Icon(.calendarClock, size: 14, color: Nuru.gold).padding(.top, 2)
                                    Text(pace).font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.top, 6)
                            }
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                        collectionCard(p)
                        actions(p)
                    }
                    if loading && detail == nil {
                        ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let e = error, detail == nil {
                        VStack(spacing: Nuru.S.sm) {
                            Text(e).font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                            Button { Haptics.tap(); Task { await load() } } label: {
                                Text("Try again").font(.inter(11, .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(Nuru.navy, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else if let d = detail {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("PAYMENTS").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                            if d.payments.isEmpty {
                                Text("No payments yet — the first one will appear here the moment it settles.")
                                    .font(.nCardBody).foregroundStyle(Color(hex: 0x5B6472))
                                    .padding(.top, 10)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                ForEach(d.payments) { pay in
                                    NavigationLink(value: PartnersRoute.receipt(pay.transactionId)) {
                                        PaymentRowLabel(payment: pay)
                                    }
                                    .buttonStyle(.pressableSubtle)
                                }
                            }
                        }
                        .padding(Nuru.S.base)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    }
                    claimsCard
                }
                .padding(Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .refreshable { await load() }
        }
        // The PAGE starts at the screen's top edge and the header pads itself
        // below the status bar (the header ignoring the safe area on its own
        // left its old slot reserved: a dead ~59pt band under it).
        .ignoresSafeArea(edges: .top)
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(item: $editing) { p in
            EditPledgeSheet(pledge: p) { amountMinor, dueDay, title in
                let ok = await vm.edit(p, amountMinor: amountMinor, dueDay: dueDay, title: title)
                if ok { await load() }
                return ok
            }
        }
        .sheet(item: $claiming) { p in
            PledgeClaimSheet(pledge: p) { body in await sendClaim(p, body) }
        }
        // An alert, not a confirmation dialog: on this iOS a dialog hides its cancel answer (EXPERIENCE.md §7.3).
        .alert(
            "Cancel \u{201C}\(cancelling?.displayTitle ?? "this pledge")\u{201D}?",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } })
        ) {
            Button("Cancel the pledge", role: .destructive) {
                if let p = cancelling {
                    Haptics.action()
                    Task { await vm.setStatus(p, "cancelled"); await load() }
                }
                cancelling = nil
            }
            Button("Keep it", role: .cancel) { cancelling = nil }
        } message: {
            Text("Nothing already given is affected, and nothing further is owed. You can make a new pledge any time.")
        }
    }

    private func load() async {
        loading = detail == nil
        error = nil
        do { detail = try await MemberAPI.pledge(pledgeId) }
        catch { if detail == nil { self.error = NuruStateCopy.failure(error).sentence } }
        loading = false
        await loadClaims()
        await loadCollection()
    }

    /// The rails and the recurring gifts, side by side. A failed read keeps
    /// what is on screen — with either unknown, nothing is offered (a second
    /// collector must never be offered by guesswork).
    private func loadCollection() async {
        async let m = try? MemberAPI.givingMethods()
        async let s = try? MemberAPI.schedules()
        let (rails, gifts) = await (m, s)
        if let rails { methods = rails }
        if let gifts { schedules = gifts }
    }

    /// Collecting it automatically (Giving Cycle 9): the offer at the pace,
    /// or the recurring gift that already collects the pledge, which opens
    /// its sheet. Nothing when neither applies.
    @ViewBuilder private func collectionCard(_ p: Pledge) -> some View {
        switch PledgePace.offer(for: p, methods: methods, schedules: schedules) {
        case .collect:
            VStack(alignment: .leading, spacing: 8) {
                Button { Task { await collectAtPace(p) } } label: {
                    HStack(spacing: 8) {
                        if startingPace { ProgressView().tint(Nuru.navy).scaleEffect(0.8) }
                        else { Icon(.calendarClock, size: 14, color: Nuru.navy) }
                        Text(startingPace ? "Setting it up…" : "Collect it automatically at this pace").font(.inter(13, .bold))
                    }
                    .foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.navy, lineWidth: 1.2))
                }
                .buttonStyle(.pressable)
                .disabled(startingPace || busy || !sync.isOnline)
                Text("Each month asks only what's left, and stops when you reach it.")
                    .font(.nCaption).foregroundStyle(Nuru.ink400)
                    .fixedSize(horizontal: false, vertical: true)
                if !sync.isOnline {
                    Text("You're offline — setting this up needs a connection.")
                        .font(.inter(11)).foregroundStyle(Nuru.ink400)
                } else if let paceError {
                    Text(paceError).font(.inter(12)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .partnerCard()
        case let .collected(scheduleId, line):
            Button {
                Haptics.tap()
                // Its sheet (Resume / Change / Pause) lives on Give.
                tabs.openGive(link: .schedule(scheduleId: scheduleId))
            } label: {
                HStack(spacing: 8) {
                    Icon(.repeat, size: 14, color: Nuru.gold)
                    Text(line).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Icon(.chevronRight, size: 14, color: Nuru.ink300)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
            .partnerCard()
        case .none:
            EmptyView()
        }
    }

    /// POST /giving/schedules at the pace (Giving Cycle 9): a monthly M-Pesa
    /// gift bound to the pledge, its first prompt now — shown on Give's own
    /// result screen, as "give now" is (the prompt watched; or, when today's
    /// could not go out, the gift standing with the server's reason). A
    /// refusal is the server's words; the key is spent by any answer and
    /// kept only when none came, so a resend finds the same gift.
    private func collectAtPace(_ p: Pledge) async {
        guard !startingPace, sync.isOnline, let body = PledgePace.scheduleBody(for: p, key: paceKey) else { return }
        Haptics.action()
        startingPace = true
        paceError = nil
        defer { startingPace = false }
        let label = GiveMoney.format(body.amountMinor, body.currency)
        do {
            let made = try await MemberAPI.createSchedule(body)
            paceKey = GiveKey.fresh()
            Haptics.success()
            GivingSignal.post()   // Give's recurring gifts and Partners hear of it
            if let first = made.firstCharge {
                tabs.openGive(watch: GiveWatch(outcome: .firstPrompt(transactionId: first.transactionId),
                                               amountLabel: label, pledgeTitle: p.displayTitle))
            } else {
                tabs.openGive(watch: GiveWatch(outcome: .scheduled(note: made.firstChargeError, nextRunAt: made.nextRunAt),
                                               amountLabel: label, pledgeTitle: p.displayTitle))
            }
            await load()
        } catch {
            if !GiveRefusal.gotNoServerAnswer(error) { paceKey = GiveKey.fresh() }
            switch GiveRefusal.from(error) {
            case let .promptWaiting(tx, message):
                // A prompt from a moment ago is still on the phone: nothing
                // was made — watch that one, as Give does.
                tabs.openGive(watch: GiveWatch(outcome: .waiting(transactionId: tx, message: message),
                                               amountLabel: label, pledgeTitle: p.displayTitle))
            case let .message(text):
                Haptics.error()
                paceError = text
            }
        }
    }

    /// A failed read keeps what is on screen; with nothing yet, one quiet line says so.
    private func loadClaims() async {
        do {
            claims = try await MemberAPI.pledgeClaims(pledgeId)
            claimsFailed = false
        } catch {
            claimsFailed = claims == nil
        }
    }

    /// POST the claim (online only — the sheet will not send offline). Nil
    /// when the office has it: it joins the list as pending. Otherwise the
    /// words to show — the server's own for a refusal (currency, day, told
    /// already, five waiting).
    private func sendClaim(_ p: Pledge, _ body: MemberAPI.PledgeClaimBody) async -> String? {
        do {
            let claim = try await MemberAPI.claimPledgePayment(p.pledgeId, body)
            claims = [claim] + (claims ?? []).filter { $0.id != claim.id }
            claimsFailed = false
            await loadClaims()
            return nil
        } catch {
            if GiveRefusal.gotNoServerAnswer(error) {
                return "We couldn't reach the church just now. Try again in a moment."
            }
            return GiveRefusal.from(error).message
        }
    }

    /// PAID ANOTHER WAY — each thing the member told the office and where it
    /// stands. Hidden while there is none.
    @ViewBuilder private var claimsCard: some View {
        if let claims, !claims.isEmpty {
            let today = PledgeMath.today()
            VStack(alignment: .leading, spacing: 0) {
                Text("PAID ANOTHER WAY").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                    .padding(.bottom, 4)
                ForEach(claims) { claim in
                    PledgeClaimRow(claim: claim, today: today)
                }
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        } else if claimsFailed {
            Text("We couldn't load what you've told the office. Pull down to try again.")
                .font(.inter(11)).foregroundStyle(Nuru.ink400)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
    }

    // MARK: Actions — every one a server round-trip; the page never relabels itself

    @ViewBuilder private func actions(_ p: Pledge) -> some View {
        let paused = p.status == "paused"
        let fulfilled = p.status == "fulfilled" || p.progress.label == "fulfilled"
        // The church collects it automatically (the card above says so):
        // paying is a choice — "Pay early", as quiet as Pause (§7.2 #2).
        let early = PledgePace.paysEarly(p, schedules: schedules)
        if !fulfilled && p.status != "cancelled" {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        Haptics.action()
                        tabs.openGive(preset: GivePreset(
                            fund: p.fund?.code,
                            amountMinor: p.remainingMinor > 0 ? p.remainingMinor : p.commitmentMinor,
                            pledgeId: p.pledgeId,
                            pledgeTitle: p.displayTitle,
                            pledgeAmountLine: pledgeAmountLine(p),
                            paysTo: p.paysTo,
                            // Its currency decides the rails (Giving Cycle 5).
                            currency: p.currency))
                    } label: {
                        HStack(spacing: 6) {
                            Text(early ? "Pay early" : "Pay now").font(.inter(13, early ? .semibold : .bold))
                            Icon(.arrowRight, size: 14, color: Nuru.navy)
                        }
                        .foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(early ? Nuru.surface : Nuru.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(early ? Nuru.border : .clear, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .disabled(paused || busy)
                    .opacity(paused ? 0.5 : 1)

                    Button {
                        Haptics.tap()
                        Task { await vm.setStatus(p, paused ? "active" : "paused"); await load() }
                    } label: {
                        HStack(spacing: 6) {
                            if busy { ProgressView().tint(Nuru.navy).scaleEffect(0.7) }
                            else { Icon(paused ? .play : .pause, size: 14, color: Nuru.navy) }
                            Text(paused ? "Resume" : "Pause").font(.inter(13, .semibold))
                        }
                        .foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                    .disabled(busy)
                }

                HStack(spacing: 0) {
                    smallAction("Edit", .pencil) { editing = p }
                    Divider().frame(height: 16).overlay(Nuru.border)
                    smallAction("Cancel", .x, tint: Nuru.danger) { cancelling = p }
                }
                .disabled(busy)

                // "I paid another way" (§1 rule d, Giving Cycle 5): tell the
                // office about money given outside the app. Online only —
                // a claim about money is never queued.
                VStack(alignment: .leading, spacing: 4) {
                    Button { Haptics.tap(); claiming = p } label: {
                        HStack(spacing: 6) {
                            Icon(.check, size: 14, color: sync.isOnline ? Nuru.navy : Nuru.ink300)
                            Text("I paid another way").font(.inter(12, .semibold))
                                .foregroundStyle(sync.isOnline ? Nuru.navy : Nuru.ink300)
                            Spacer(minLength: 0)
                            Icon(.chevronRight, size: 14, color: Nuru.ink300)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!sync.isOnline || busy)
                    if !sync.isOnline {
                        Text("You're offline — telling the office needs a connection.")
                            .font(.inter(11)).foregroundStyle(Nuru.ink400)
                    }
                }

                Toggle(isOn: Binding(get: { p.remindersEnabled },
                                     set: { on in Task { await vm.setReminders(p, on); await load() } })) {
                    HStack(spacing: 8) {
                        Icon(.bell, size: 14, color: Nuru.gold)
                        // The server's reminder lands in the inbox; no remote push
                        // on this phone yet (B11).
                        Text(IOSNoticeWords.pledgeReminder).font(.inter(13)).foregroundStyle(Nuru.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(Nuru.gold)
                .disabled(busy)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
    }

    /// "Charge me automatically" could not be set up when the pledge was
    /// made (Giving Cycle 5): the pledge stands, and the server's words say
    /// why. One amber row (TroubleRow's look) until dismissed.
    private func autoScheduleNotice(_ note: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.symbol(13, weight: .semibold))
                .foregroundStyle(Nuru.urgentText)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your pledge is made — automatic collection isn't set up.")
                    .font(.inter(12, .semibold)).foregroundStyle(Nuru.urgentText)
                    .fixedSize(horizontal: false, vertical: true)
                Text(note).font(.inter(12)).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button { Haptics.tap(); vm.pledgeNotices[pledgeId] = nil } label: {
                Icon(.x, size: 14, color: Nuru.ink400).frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.urgentBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func smallAction(_ title: String, _ icon: Lucide, tint: Color = Nuru.ink600, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 5) {
                Icon(icon, size: 14, color: tint)
                Text(title).font(.inter(12, .semibold)).foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity).frame(height: 32)
        }
        .buttonStyle(.plain)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("YOUR PLEDGE").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0x9A7A2A))
                // The pledge's name IS the page title (pledge names contract).
                Text(pledge?.displayTitle ?? "Your pledge")
                    .font(.fraunces(26, .semibold)).foregroundStyle(Nuru.navy)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, NuruSafeArea.top + 8)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }
}

/// One payment line for the detail page — amount, date, receipt code — as a
/// NavigationLink label.
private struct PaymentRowLabel: View {
    let payment: PledgePayment
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(Nuru.goldChipBg).frame(width: 32, height: 32)
                Icon(.handHeart, size: 14, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(money(payment.amountMinor, payment.currency)).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text([giveDateFull(payment.at), payment.receiptCode].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
            }
            Spacer(minLength: 8)
            Icon(.chevronRight, size: 14, color: Nuru.ink300)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

// MARK: - Formatting

/// Timestamps arrive from Postgres with OR without fractional seconds depending
/// on the column, and the shared `ISO8601DateFormatter.nuru` only accepts the
/// fractional form. Trying both is the difference between a real date and a
/// screen that quietly says "Paused" when nothing is paused.
enum PartnerFormat {
    private static let withMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(_ iso: String) -> Date? {
        withMillis.date(from: iso) ?? plain.date(from: iso)
    }

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()
    static func grouped(_ n: Int) -> String {
        number.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

/// Whether the Partners page has a standing to show (the Android walk's A1;
/// §7.4 #9, no zero facts): a pledge that isn't cancelled, or a gift that
/// went through. A schedule set up whose first collection failed is not yet
/// a standing — no "Partner since", no "0 gifts kept", no tier.
enum PartnerStanding {
    static func isReal(_ p: Partnership) -> Bool {
        p.pledges.contains { $0.status != "cancelled" } || p.kept > 0 || p.givenMinor > 0
    }
    static let notYet = "Your standing shows here after your first gift or pledge."
}

/// A pledge's progress line on its page. The Android walk's A7: a monthly
/// pledge that begins on 5 Nov read "KSh 0 of 5,000 this month" in October —
/// a month it was never due. Until its first day it says when it starts.
/// Display only: the numbers are the server's, untouched.
enum PledgeWords {
    static func progressLine(_ p: Pledge, today: String = PledgeMath.today()) -> String {
        let given = p.progress.paidMinor > 0 ? "\(money(p.progress.paidMinor, p.currency)) given in all" : nil
        if p.isMonthly, let start = PledgeMath.start(p), start > today, let starts = startsLine(start) {
            return [starts, given].compactMap { $0 }.joined(separator: " · ")
        }
        let toward = "\(money(p.paidTowardMinor, p.currency)) of \(money(p.commitmentMinor, p.currency))\(p.isMonthly ? " this month" : "")"
        return [toward, given].compactMap { $0 }.joined(separator: " · ")
    }

    /// "Starts Thu 5 Nov" — the calendar day sent, never shifted (§8.1 rule 8).
    static func startsLine(_ ymd: String) -> String? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = GiveCalendar.nairobi
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: ymd) else { return nil }
        return "Starts \(NuruDates.day(d, timeZone: GiveCalendar.nairobi))"
    }
}
