// Give — the native port of the Figma GiveTab (Final Pathway Portal make). A cream
// hero, "repeat last gift", five funds, a centred big-number amount with presets +
// a custom keypad, a frequency switch with an honest recurring summary, a
// reorderable pay-method list with brand badges, cover-the-fee, active schedules
// (tap to manage or cancel), recent giving, a scripture strip and a quiet sticky
// CTA. Money is server-authoritative + online-only (§5.6): we create a real intent
// (mobile-money STK / PayPal approve) or a real server-charged schedule and NEVER
// fabricate a payment state — the ceremony polls GET /giving/transactions/{id}
// for the true outcome. The card path needs the Stripe SDK (SAQ-A tokenisation)
// and stays SOON.
//
// GIVING CYCLE 1 (2026-09-28): the M-Pesa prompt used to go to ONE hardcoded
// number for every member. It now goes to the number this member last gave from
// on this phone, else their profile number (`phone_on_file`), else one they type
// — validated as a Kenyan mobile number and sent as `phone_number`. The method
// list is the server's (GET /giving/methods): only rails that can take money are
// selectable, the rest wear SOON; weekly / monthly only on a recurring rail. A
// failed gift says why in the server's words (`failure.reason` + `hint`); a
// prompt still waiting on the phone (409 GIFT_IN_PROGRESS) is watched rather than
// failed; paused schedules are labelled and cancelled ones are not listed. The
// rules themselves live in GivingRules.swift.
//
// GIVING CYCLE 5 (2026-09-28): a gift that collects a pledge says so ("Collects
// your pledge “…”") and what its next prompt really asks (the rest of what is
// due, or nothing); a monthly pledge's collector changes its amount and day on
// the pledge. Paying a pledge or need, ITS currency decides the rails (a KES
// promise M-Pesa, a USD one PayPal).
//
// PLEDGE-PAY MODE (2026-09-26): while a pledge (or a need) preset is active the
// SERVER routes the money — a pledge to its own `pays_to` fund, a need to its
// department's fund — so "Repeat last gift", the fund chooser and the
// One-time / Weekly / Monthly switch step aside for one PAYING YOUR PLEDGE (or
// GIVING TO A NEED) card, and the CTA names what is being paid. A pledge
// instalment is one-time; the recurring rhythm is the pledge's own schedule.
//
// FRESHNESS: every created intent (pending), every resolved one and every
// schedule change posts .nuruGivingChanged, so the Partners tab and statement
// refetch (a settled pledge payment used to stay invisible there).
import SwiftUI
import UIKit
import Combine

/// Pushed pages on the Give stack. Partners is no longer one of them — it is
/// the Give tab's second segment (GiveTabView, PARTNERS_PROGRAMME §0).
enum GiveRoute: Hashable { case statement }

// MARK: - Funds (one look: §8.1 rules 1 and 7 — a gold-tint tile, navy icon;
// the walk's E17 found the Offering tile red and the Gift tile purple)

private struct Fund: Identifiable {
    let code, label, tagline: String
    let icon: Lucide
    let tint, fg: UInt32
    var id: String { code }
}
private let funds: [Fund] = [
    Fund(code: "tithe",        label: "Tithe",        tagline: "A faithful portion",  icon: .percent,   tint: Nuru.tileTint, fg: Nuru.tileIcon),
    Fund(code: "offering",     label: "Offering",     tagline: "Freewill worship",    icon: .handHeart, tint: Nuru.tileTint, fg: Nuru.tileIcon),
    Fund(code: "gift",         label: "Gift",         tagline: "A special gift",      icon: .gift,      tint: Nuru.tileTint, fg: Nuru.tileIcon),
    Fund(code: "mission",      label: "Mission",      tagline: "Beyond our walls",    icon: .globe,     tint: Nuru.tileTint, fg: Nuru.tileIcon),
    Fund(code: "discipleship", label: "Discipleship", tagline: "Growing the Pathway", icon: .bookOpen,  tint: Nuru.tileTint, fg: Nuru.tileIcon),
]
private let presets = [200, 500, 1000, 2500, 5000]

// MARK: - Pay methods (square, rounded-xl badges — the rail's mark in navy on
// gold tint, never a brand hue: §8.1 rule 1)

/// How a rail LOOKS. Which rails appear, and whether one can take money, is
/// the server's answer (GET /giving/methods) — this is only the paint.
private struct PayMethod: Identifiable {
    let key, label, sub: String
    let badgeText: String           // short logo text inside the badge
    let badgeBg, badgeFg: UInt32    // the one tile look (Nuru.tileTint / tileIcon)
    let icon: Lucide?               // shown instead of badge text when set
    var id: String { key }
}
private let methodLooks: [PayMethod] = [
    PayMethod(key: "mpesa",    label: "Pay with M-Pesa",             sub: "A prompt on your phone",   // never "STK push" (rule 8: no jargon)
              badgeText: "M-PESA", badgeBg: Nuru.tileTint, badgeFg: Nuru.tileIcon, icon: nil),
    PayMethod(key: "airtel",   label: "Pay with Airtel Money",       sub: "Mobile money",
              badgeText: "AIRTEL", badgeBg: Nuru.tileTint, badgeFg: Nuru.tileIcon, icon: nil),
    PayMethod(key: "equity",   label: "Pay with Equity Bank",        sub: "Bank account",
              badgeText: "", badgeBg: Nuru.tileTint, badgeFg: Nuru.tileIcon, icon: .landmark),
    PayMethod(key: "card",     label: "Pay with Card",               sub: "Visa · Mastercard",
              badgeText: "", badgeBg: Nuru.tileTint, badgeFg: Nuru.tileIcon, icon: .creditCard),
    PayMethod(key: "applepay", label: "Pay with Apple / Google Pay", sub: "Device wallet",
              badgeText: "", badgeBg: Nuru.tileTint, badgeFg: Nuru.tileIcon, icon: .wallet),
    PayMethod(key: "paypal",   label: "Pay with PayPal",             sub: "PayPal balance / linked",
              badgeText: "PP", badgeBg: Nuru.tileTint, badgeFg: Nuru.tileIcon, icon: nil),
]

/// A rail's paint; one the server lists that this build has no badge for
/// gets a plain wallet badge and the server's own label.
private func methodLook(_ rail: GivingMethod) -> PayMethod {
    methodLooks.first { $0.key == rail.key }
        ?? PayMethod(key: rail.key, label: "Pay with \(rail.label.isEmpty ? givingMethodName(rail.key) : rail.label)",
                     sub: "", badgeText: "", badgeBg: Nuru.tileTint, badgeFg: Nuru.tileIcon, icon: .wallet)
}

/// A gift's receipt to present (a notification's gift that did not fail).
private struct ReceiptLink: Identifiable { let id: String }

/// One row of the method list: the server's rail and how it looks.
private struct MethodRow: Identifiable {
    let look: PayMethod
    let rail: GivingMethod
    var key: String { rail.key }
    var id: String { rail.key }
}

// MARK: - Shared giving helpers (used by the statement + receipt screens too)

func givingMethodName(_ raw: String?) -> String {
    switch raw {
    case "mpesa": return "M-Pesa"
    case "airtel": return "Airtel Money"
    case "card": return "Card"
    case "paypal": return "PayPal"
    case "wallet", "applepay": return "Wallet"
    case "equity": return "Equity Bank"
    case .some(let s): return s.capitalized
    case .none: return "M-Pesa"
    }
}

func giveParseDate(_ iso: String) -> Date? {
    if let d = ISO8601DateFormatter.nuru.date(from: iso) { return d }
    if let d = ISO8601DateFormatter().date(from: iso) { return d }
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
    return f.date(from: String(iso.prefix(10)))
}

/// "Mon 5 Oct" — the one date shape (§8.1 rule 8), the year when not this year.
func giveDateShort(_ iso: String) -> String {
    guard let d = giveParseDate(iso) else { return String(iso.prefix(10)) }
    return NuruDates.day(d)
}

/// "Mon 5 Oct 2026" — a record kept, so always the year.
func giveDateFull(_ iso: String) -> String {
    guard let d = giveParseDate(iso) else { return String(iso.prefix(10)) }
    return NuruDates.day(d, withYear: true)
}

func giveTime(_ iso: String) -> String {
    guard let d = giveParseDate(iso) else { return "" }
    return NuruDates.time(d)
}

// MARK: - View model

@MainActor
final class GivingViewModel: ObservableObject {
    @Published var history: [GivingRecord] = []
    @Published var schedules: [GivingSchedule] = []
    /// The rails this member can give with here (GET /giving/methods). M-Pesa
    /// alone until the server answers — and for good if it cannot (Cycle 1).
    @Published var methods: GivingMethods = .fallback()
    /// True once the methods call has answered or failed at least once — the
    /// prompt number is chosen then, when `phone_on_file` is known.
    @Published var methodsSettled = false
    @Published var loading = true
    private var givingChanged: AnyCancellable?

    /// Reloads the year total / recent giving / schedules when money changes
    /// elsewhere (the Partners tab resuming a schedule, …) — debounced, and
    /// deaf to its own posts (Give already reloads after its own changes).
    init() {
        givingChanged = GivingSignal.observe(self) { [weak self] in
            Task { await self?.load() }
        }
    }

    /// Loads are numbered; an older reply never overwrites a newer one (the
    /// segment, the tab, the foreground and the signal can all ask at once).
    private var loadSeq = 0
    private var appliedHistorySeq = 0
    private var appliedSchedulesSeq = 0
    private var appliedMethodsSeq = 0
    private var appliedTotalsSeq = 0

    /// This year's giving per currency, as the server's statement counts it
    /// (GET /giving/statements `totals[]`, Giving Cycle 2) — nil until it
    /// answers, and the year pill then sums the history itself, per currency.
    @Published var serverYearTotals: [CurrencyTotal]?
    private var serverTotalsYear = 0
    /// This year's statement pledges, by id → shape (Giving Cycle 5): a gift
    /// that collects a MONTHLY pledge takes its amount and day from the
    /// pledge, so its sheet sends the member there to change them.
    @Published var pledgeShapes: [String: String] = [:]

    /// A pledge's shape when this year's statement named it; nil = unknown.
    func pledgeShape(_ id: String) -> String? { pledgeShapes[id] }

    /// Why the giving history never loaded — the strip at the top says it in
    /// §4's words (§9.4); nil once anything has.
    @Published var loadFailure: Error?
    /// The year's total is known — from the server's statement or the
    /// history. Until then the year pill says nothing: "KSh 0 given this
    /// year" was a fact nobody had read (§9.4).
    var yearKnown: Bool {
        appliedHistorySeq > 0 || serverTotalsYear == GiveCalendar.currentYear()
    }

    func load() async {
        loading = true
        loadSeq += 1
        let seq = loadSeq
        // The church's year, asked for by name: with no year the server
        // answers the latest year that had a gift, not necessarily this one.
        let year = GiveCalendar.currentYear()
        async let h = MemberAPI.givingHistory()
        async let s = MemberAPI.schedules()
        async let m = MemberAPI.givingMethods()
        async let t = MemberAPI.givingStatements(year: year)
        // A failed refetch keeps what is on screen (stale-while-revalidate)
        // rather than blanking the year pill and Recent giving.
        do {
            let v = try await h
            if seq > appliedHistorySeq { appliedHistorySeq = seq; history = v; loadFailure = nil }
        } catch {
            // Said only while nothing was ever shown — a failed refetch keeps
            // what is on screen.
            if appliedHistorySeq == 0 { loadFailure = error }
        }
        if let v = try? await s, seq > appliedSchedulesSeq { appliedSchedulesSeq = seq; schedules = v }
        // Methods too: a failed call keeps the last answer (M-Pesa alone if
        // there never was one); an answer with no rails in it is no answer.
        if let v = try? await m, seq > appliedMethodsSeq {
            appliedMethodsSeq = seq
            let next = v.methods.isEmpty ? GivingMethods.fallback(phoneOnFile: v.phoneOnFile) : v
            if next != methods { methods = next }
        }
        if let v = try? await t, v.year == year, seq > appliedTotalsSeq {
            appliedTotalsSeq = seq
            serverYearTotals = v.totals
            serverTotalsYear = year
            pledgeShapes = Dictionary(v.pledges.map { ($0.pledgeId, $0.shape) }, uniquingKeysWith: { a, _ in a })
        }
        if !methodsSettled { methodsSettled = true }
        loading = false
    }

    /// The schedules Give lists under RECURRING GIFTS (never a cancelled one).
    var listedSchedules: [GivingSchedule] { GiveSchedules.listed(schedules) }

    /// What the year pill says was given this (church) year, per currency —
    /// never one sum of shillings and dollars. The server's statement when it
    /// has answered for this year, else the history summed the same way.
    var yearTotals: [CurrencyTotal] {
        let year = GiveCalendar.currentYear()
        if let server = serverYearTotals, serverTotalsYear == year { return server }
        return GiveMoney.totals(of: history.filter { GiveCalendar.year(of: $0.createdAt) == year })
    }
    /// The last ORDINARY gift that went through — "Repeat last gift" must
    /// never re-pay a pledge instalment or a need: records carrying a
    /// `pledgeId` (or a `needId`, when the server sends one) are skipped. A
    /// failed or waiting gift is skipped too — it was never given, and Recent
    /// giving beside the card would say "No gifts yet" (Giving Cycle 10).
    /// Nil hides the card.
    var lastGift: GivingRecord? {
        history.first { GiveMoney.isSettled($0.status) && $0.pledgeId == nil && $0.needId == nil }
    }
}

// MARK: - Give

struct GivingView: View {
    /// True when hosted as the "Give" segment inside the Give tab (GiveTabView)
    /// rather than as its own top-level screen. The tab paints no band of its
    /// own (Partners UI v2): this header IS the band, so it clears the status
    /// bar itself and carries the GIVE · PARTNERS switch as its first row.
    var embeddedInYou: Bool = false
    /// The Give tab's current segment + the tab's selector — rendered as the
    /// band's first row when both are supplied (GiveTabView), omitted otherwise.
    var segment: GiveSegment? = nil
    var onSelectSegment: ((GiveSegment) -> Void)? = nil
    /// At the accessibility sizes the band scrolls with the page (§9.6 #4).
    @Environment(\.dynamicTypeSize) private var typeSize

    @StateObject private var vm = GivingViewModel()
    /// "Hide the amount" on the year pill — a member glancing at Give in
    /// company shouldn't have to show the room what they've given. Per
    /// device, default visible (UserDefaults `give.hideYearTotal`).
    @AppStorage("give.hideYearTotal") private var hideYearTotal = false
    @EnvironmentObject private var tabs: TabRouter
    /// Whose number to remember — the prompt number is kept per member.
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    /// Give's own stack (the statement, a receipt) — bound so a re-tap on the
    /// Give tab can return it to the top (§7.4 #17).
    @State private var path = NavigationPath()

    /// The Give form's normal state — what the tab opens with, and what a
    /// pledge / need payment returns it to once it went through.
    private static let defaultFundCode = "tithe"
    private static let defaultAmount = 1000

    @State private var fundCode = GivingView.defaultFundCode
    /// The gift in whole SHILLINGS — M-Pesa's amount. Kept while PayPal is
    /// chosen, so switching back restores it (Giving Cycle 2).
    @State private var amount = GivingView.defaultAmount
    /// The gift in US CENTS while PayPal is chosen — PayPal gifts are in
    /// dollars (the server refuses anything else); never a shilling number.
    @State private var usdCents = UsdEntry.defaultCents
    /// The pledge this gift counts toward (Partners → "Pay now"). Rides the
    /// intent body as `pledge_id` (PARTNERS_PROGRAMME §5) and clears once the
    /// server confirms the gift — a retry after a failure keeps it.
    @State private var pledgeId: String?
    /// The department need this gift is for (Departments → "Give to this
    /// need"). Rides the intent body as `need_id` (PARTNERS_PROGRAMME §4) so
    /// the server attributes it to the need's campaign; cleared once the
    /// server confirms the gift — a retry after a failure keeps it.
    @State private var needId: String?
    /// The pledge's name, from the preset — so the PAYING YOUR PLEDGE card can
    /// say WHICH pledge before the server has answered. Cleared with pledgeId.
    @State private var pledgeTitle: String?
    /// The promise in one line ("KSh 1,000 monthly · due on the 25th") and
    /// the pledge's `pays_to` fund — display only; the server routes.
    @State private var pledgeLine: String?
    @State private var paysTo: Pledge.FundRef?
    /// A department need's title + one line, for the GIVING TO A NEED card.
    @State private var needTitle: String?
    @State private var needLine: String?
    /// The pledge's or need's currency (Giving Cycle 5) — it decides the rails
    /// and the amount's money while paying one. Cleared with the pay mode.
    @State private var payCurrency: String?
    /// From the intent RESULT (pledge names contract): the fund the SERVER
    /// routed the gift to, and the pledge it counts toward. The ceremony reads
    /// these, never the chip, so a pledge payment is never described as a
    /// gift to whatever fund happened to be selected.
    @State private var intentFundName: String?
    @State private var intentPledgeTitle: String?
    @State private var intentIsPledge = false
    @State private var method = "mpesa"
    /// The member's order for the server's rails (up / down chevrons).
    @State private var methodOrder = GivingMethods.fallback().methods.map(\.key)
    @State private var freq = "once"          // once | weekly | monthly
    @State private var coverFee = false
    /// The number the mobile-money prompt goes to — as typed. Starts empty and
    /// is filled once (seedPhone): the member's last number on this phone,
    /// else their profile number, else it stays empty and the sheet asks.
    /// NEVER a built-in number (it once was one, for every member — Cycle 1).
    @State private var mpesaPhone = ""
    /// The value seedPhone last put there — replaced by a better default (the
    /// remembered number once the profile loads) only while still untouched.
    @State private var seededPhone: String?
    private let phoneMemory = GivingPhoneMemory()
    /// The E.164 number the accepted prompt was actually sent to — what the
    /// "Prompt sent to" chip says. Nil for PayPal and for a waiting prompt.
    @State private var promptPhone: String?
    /// The server's reason + hint for a gift the poll found failed.
    @State private var ceremonyFailure: GiftFailure?
    /// Set while the ceremony watches a prompt the server said was ALREADY
    /// waiting (409 GIFT_IN_PROGRESS) — described from that gift's own record,
    /// since it may not be the gift on the form.
    @State private var waitingGift: WaitingGift?
    /// Set while the ceremony shows a gift made on a pledge's page (Giving
    /// Cycle 9) — not the form's: its words are the pledge's, and closing it
    /// leaves the form (and any pledge it is paying) as it was.
    @State private var elsewhere: GiveWatch?
    /// The failed gift the ceremony is showing — "Try again" retries THIS gift
    /// on the server (Giving Cycle 3). Nil when the refusal made no gift: the
    /// member goes back to the form instead.
    @State private var retryTxId: String?
    /// That gift's method — whether its retry prompts a phone.
    @State private var retryMethod: String?
    /// The retry's idempotency key (GiveRetry.key): replayed only after an
    /// attempt that got no server answer, never across gifts.
    @State private var retryKey = GiveKey.fresh()
    /// A gift opened from a notification that did not fail after all — its
    /// receipt, in a sheet.
    @State private var receiptLink: ReceiptLink?
    /// "Named giving" (custom sheet, optional): set from the custom-amount
    /// keypad sheet. Rides the M-Pesa AccountReference + persists for
    /// receipts/statements/portal Finance.
    @State private var accountName = ""
    @AppStorage("giving.lastAccountName") private var lastAccountName = ""

    @State private var submitting = false
    @State private var showKeypad = false
    @State private var showMpesaSheet = false
    @State private var scheduleDetail: GivingSchedule?
    @State private var ceremony: String?      // nil | stk | success | failed | scheduled
    @State private var ceremonyNote = ""
    @State private var pendingTxId: String?
    @State private var successRef: String?
    @State private var scheduledNextAt = ""
    /// Said on the "scheduled" stage when today's first prompt could not go
    /// out (Giving Cycle 4): the server's reason + when the first prompt comes.
    @State private var scheduledNote: String?
    @State private var pollTask: Task<Void, Never>?
    /// When "Check your phone" began its wait, and whether it has passed the
    /// minute (StkWatch, EXPERIENCE.md §7.2 #5): the line turns to "Still
    /// processing…" and Done leads, while the watch keeps going.
    @State private var stkStartedAt = Date()
    @State private var stkLate = false
    /// Set when a pledge / need payment went through (or is pending): the
    /// form returns to its normal state once the ceremony has finished
    /// dismissing, so the closing cover never flashes a reset amount.
    @State private var resetFormAfterCeremony = false
    /// The idempotency key of the CURRENT submission. Reused on the next Pay
    /// tap ONLY when the previous attempt got no server answer (offline,
    /// timeout, transport) — the server returns the existing transaction for
    /// a replayed key, so a lost reply can never become a second STK. A new
    /// key after ANY HTTP response (success, 4xx, 5xx — reusing one after a
    /// genuine failure would lock the member out of retrying), after the
    /// ceremony resolves, and whenever the form changes (formSignature).
    @State private var submissionKey = GiveKey.fresh()
    /// PayPal order id (the intent's provider_ref) for the in-flight gift —
    /// captured after the member approves on PayPal, then cleared.
    @State private var paypalOrderId: String?
    @State private var paypalCaptureTask: Task<Void, Never>?

    private var fund: Fund { funds.first { $0.code == fundCode } ?? funds[0] }
    /// What the ceremony says the gift is for — the server's answer first.
    /// A pledge payment is ALWAYS "toward your pledge" (the server decides
    /// its fund and ignores the chip); the chip's label is the last resort,
    /// only for an ordinary gift on a server that sent no `fund`.
    private var ceremonyDestination: GiveDestination {
        if intentIsPledge { return .pledge(intentPledgeTitle) }
        if pledgeId != nil { return .pledge(pledgeTitle) }
        if let f = intentFundName { return .fund(f) }
        return .fund(fund.label)
    }
    /// The gift's currency: the selected rail's (M-Pesa KES, PayPal USD —
    /// Giving Cycle 2) — or, paying a pledge or need, ITS currency, which
    /// decides the rails (Giving Cycle 5).
    private var currency: String { payMode ? payCurrencyCode : vm.methods.currency(method) }
    /// The pledge's / need's currency while paying one (shillings when unsaid).
    private var payCurrencyCode: String { (payCurrency ?? "KES").uppercased() }
    /// The rails a pledge / need payment may use: its currency's only.
    private var payRailsCurrency: String? { payMode ? payCurrencyCode : nil }
    /// PayPal is chosen: the amount is entered, shown and sent in dollars.
    private var inDollars: Bool { currency == "USD" }
    /// The gift itself, in the rail's minor units.
    private var giftMinor: Int { inDollars ? usdCents : amount * 100 }
    /// What is charged, and how much of it is the fee cover (shilling rails
    /// only; `amount_minor` is the total, `cover_fee_minor` the fee part).
    private var charge: (amountMinor: Int, coverFeeMinor: Int?) {
        CoverFee.split(giftMinor: giftMinor, covering: coverFee, currency: currency)
    }
    private var totalMinor: Int { charge.amountMinor }
    /// "KSh 1,013" · "US$ 25.00" — the total, in its own currency.
    private var totalLabel: String { GiveMoney.format(totalMinor, currency) }
    /// Why the amount cannot go on the chosen rail (its limits, whole
    /// shillings for M-Pesa) — said under the amount; nil when it can.
    private var amountProblem: String? {
        guard giftMinor > 0, let rail = vm.methods.method(method),
              vm.methods.currency(method) == currency else { return nil }
        return GiveAmountRules.problem(totalMinor: totalMinor, rail: rail)
    }
    /// A pledge / need payment is always one-time (the switch is hidden), and
    /// so is a gift on a rail the server does not run schedules on.
    private var recurring: Bool { freq != "once" && !payMode && recurringAllowed }
    /// The selected rail can carry a weekly / monthly gift (server's word).
    private var recurringAllowed: Bool { vm.methods.allowsRecurring(method) }
    /// A pledge or need preset is active — the server routes the money.
    private var payMode: Bool { pledgeId != nil || needId != nil }
    /// The Give segment is what the member is looking at.
    private var giveOnScreen: Bool { (segment ?? .give) == .give && tabs.selected == .give }
    /// Everything a submission is made of. Any change = a different
    /// submission = a new idempotency key. (The phone is included too: a
    /// replayed key would return the old transaction, prompting the old number.)
    private var formSignature: String {
        [String(amount), String(usdCents), fundCode, method, pledgeId ?? "", needId ?? "", freq,
         accountName, String(coverFee), mpesaPhone].joined(separator: "|")
    }

    /// True when an attempt got NO server answer — the only case in which
    /// the same idempotency key may be sent again.
    private static func gotNoServerAnswer(_ error: Error) -> Bool { GiveRefusal.gotNoServerAnswer(error) }
    private var cadenceWord: String { freq == "weekly" ? "week" : "month" }
    /// The server's rails in the member's order, each with its paint — the
    /// shilling rails only while paying a pledge or need (pledges are in
    /// shillings; a dollar payment would count against a shilling promise).
    /// The rails Give lists: only those that can take this gift (§2: never
    /// name a rail the member can't use — the Cycle 3 walk's E7 found "Pay
    /// with Airtel Money · SOON", "PayPal · SOON", "Card · SOON").
    private var orderedMethods: [MethodRow] {
        let shown = Set(GivingRails.listed(vm.methods, onlyCurrency: payRailsCurrency))
        return methodOrder.compactMap { k in
            guard shown.contains(k) else { return nil }
            return vm.methods.method(k).map { MethodRow(look: methodLook($0), rail: $0) }
        }
    }
    private var freqLabel: String {
        switch freq { case "weekly": return "weekly"; case "monthly": return "monthly"; default: return "one-time" }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottom) {
                Nuru.paper.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                    // At the accessibility sizes the band scrolls with the
                    // page: pinned, it filled two thirds of the screen and the
                    // form scrolled in a sliver under it (§9.6 #4).
                    if typeSize.isAccessibilitySize { headerBlock }
                    VStack(alignment: .leading, spacing: Nuru.S.md) {
                        // Give's reads didn't come (offline, our side): say so
                        // first, in §4's words — the form below still stands.
                        if let f = vm.loadFailure, !vm.yearKnown {
                            NuruStateView(state: .failed(NuruStateCopy.failure(f)),
                                          retry: { Task { await vm.load() } }, compact: true)
                        }
                        // What is already in motion leads (EXPERIENCE.md §9.1
                        // rule 6, §9.2 #6): the recurring gifts — running or
                        // paused — come first, each told once; a one-time gift
                        // is the choice below. A weekly tithe used to sit under
                        // the fold twice ("Your rhythm" and a RECURRING GIFTS
                        // rail) beneath a pre-filled one-time tithe. A pledge
                        // payment still leads with its own card. Android's
                        // 8cfa45d, row for row.
                        if !payMode && !vm.listedSchedules.isEmpty {
                            overline("RECURRING GIFTS")
                            ForEach(vm.listedSchedules) { recurringGiftRow($0) }
                            overline("GIVE ONCE").padding(.top, Nuru.S.sm)
                        }
                        if !payMode, let g = vm.lastGift { repeatCard(g) }
                        if payMode { payModeCard.transition(.opacity) } else { fundsSection }
                        amountCard
                        if !payMode && recurringAllowed { frequencyRow }
                        if recurring {
                            recurringSummary.transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        methodSection
                        // The fee table is M-Pesa's, in shillings — nothing to
                        // cover on a dollar rail.
                        if !inDollars { coverFeeRow }
                        recentSection
                        scriptureStrip
                        secureNote
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace + 80)
                    }
                    .scrollsToTopOnReselect(.give)   // a re-tap at the root returns to the top (B10)
                }
                .safeAreaInset(edge: .top, spacing: 0) { if !typeSize.isAccessibilitySize { headerBlock } }
                ctaBar
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .nuruEdgeSwipeBack()   // back by the edge swipe on every pushed page (B9)
            .navigationDestination(for: GivingRecord.self) { GivingReceiptView(transactionId: $0.transactionId) }
            .navigationDestination(for: GiveRoute.self) { route in
                switch route {
                case .statement: GivingStatementView()
                }
            }
            .inboxDestinations()   // the band's bell
        }
        .popsToRoot(on: .give, path: $path, when: { segment == nil || segment == .give })
        // Stale-while-revalidate (2026-09-26: the year pill sat at KSh 0 after
        // pledge payments landed without a ceremony — a scheduled charge,
        // another device). Refetch whenever this segment is SHOWN — first
        // mount, the segment switched back, the Give tab re-selected (tabs
        // and segments stay mounted, so .task alone never re-runs) — and on
        // return to the foreground; what is on screen stays meanwhile.
        .task { seedPhone(); await vm.load() }
        // The server's rails (Cycle 1): keep the member's order, move off a
        // rail that can no longer be picked, and fill the prompt number once
        // `phone_on_file` is known (or known to be unavailable).
        .onChange(of: vm.methods) { _, m in syncMethods(m) }
        // Paying a pledge or need takes its currency's rails only (Giving
        // Cycle 5): a KES promise M-Pesa, a USD one PayPal.
        .onChange(of: payMode) { _, _ in syncMethods(vm.methods) }
        .onChange(of: payCurrency) { _, _ in syncMethods(vm.methods) }
        .onChange(of: vm.methodsSettled) { _, _ in seedPhone() }
        .onChange(of: auth.profile?.userId) { _, _ in seedPhone() }
        // (A seed skipped while the number sheet was open lands once it shuts.)
        .onChange(of: showMpesaSheet) { _, open in if !open { seedPhone() } }
        .onChange(of: segment) { _, s in
            if s == .give && tabs.selected == .give { Task { await vm.load() } }
        }
        .onChange(of: tabs.selected) { _, _ in
            if giveOnScreen { Task { await vm.load() } }
        }
        // Partners "Pay now" / a due item: land with the pledge's fund and the
        // amount still owed already in place, as a one-time gift, and remember
        // the pledge so the intent carries `pledge_id`. Consumed once.
        .onReceive(tabs.$givePreset) { preset in
            guard let preset else { return }
            if let f = preset.fund, funds.contains(where: { $0.code == f }) { fundCode = f }
            // Keep the body's fund consistent with where the pledge pays
            // (the server routes pledge money regardless).
            if let f = preset.paysTo?.code, funds.contains(where: { $0.code == f }) { fundCode = f }
            // In the pledge's / need's own money (Giving Cycle 5): US cents for
            // a dollar pledge, never read as shillings.
            payCurrency = (preset.pledgeId != nil || preset.needId != nil) ? preset.currency?.uppercased() : nil
            if let m = preset.amountMinor, m > 0 {
                if (preset.currency ?? "KES").uppercased() == "USD" { usdCents = m } else { amount = m / 100 }
            }
            pledgeId = preset.pledgeId
            pledgeTitle = preset.pledgeId == nil ? nil : preset.pledgeTitle
            pledgeLine = preset.pledgeId == nil ? nil : preset.pledgeAmountLine
            paysTo = preset.pledgeId == nil ? nil : preset.paysTo
            needId = preset.needId
            needTitle = preset.needId == nil ? nil : preset.needTitle
            needLine = preset.needId == nil ? nil : preset.needLine
            freq = "once"
            DispatchQueue.main.async { tabs.givePreset = nil }
        }
        // A giving notification's gift (Giving Cycle 3) — consumed once.
        .onReceive(tabs.$giveLink) { link in
            guard let link else { return }
            DispatchQueue.main.async { tabs.giveLink = nil }
            open(link)
        }
        // A gift made on a pledge's page (Giving Cycle 9: collected at its
        // pace) — the same result screen as "give now". Consumed once, and
        // never over a gift already on screen.
        .onReceive(tabs.$giveWatch) { watch in
            guard let watch else { return }
            DispatchQueue.main.async { tabs.giveWatch = nil }
            guard ceremony == nil, !submitting else { return }
            show(watch)
        }
        .sheet(item: $receiptLink) { link in
            NavigationStack {
                GivingReceiptView(transactionId: link.id)
                    .navigationDestination(for: GivingRecord.self) { GivingReceiptView(transactionId: $0.transactionId) }
            }
        }
        // A different submission from here on — never replay the old key.
        .onChange(of: formSignature) { _, _ in submissionKey = GiveKey.fresh() }
        // Returning from the PayPal approval in Safari → nudge the capture;
        // and back from anywhere → refetch the year total / recent giving.
        .onChange(of: scenePhase) { _, p in
            if p == .active { attemptPayPalCapture() }
            if p == .active && giveOnScreen { Task { await vm.load() } }
        }
        .sheet(isPresented: $showKeypad) {
            // Shillings for M-Pesa; dollars and cents while PayPal is chosen.
            GiveKeypadSheet(initialMinor: giftMinor, currency: currency, fundLabel: payLabel ?? fund.label,
                            initialName: accountName.isEmpty ? lastAccountName : accountName) { minor, name in
                if inDollars { usdCents = minor } else { amount = minor / 100 }
                accountName = name ?? ""
                if let name, !name.isEmpty { lastAccountName = name }
            }
        }
        .sheet(isPresented: $showMpesaSheet) {
            // Confirms the number the prompt goes to — for a one-time gift and
            // for a schedule, which prompts it every cycle. Hands back E.164.
            MobileMoneySheet(methodKey: method, phone: $mpesaPhone,
                             phoneOnFile: vm.methods.phoneOnFile,
                             frequency: recurring ? freq : nil,
                             amountLabel: totalLabel) { number, giveNow in
                let provider = method
                if recurring {
                    Task { await createSchedule(provider: provider, phone: number, giveNow: giveNow) }
                } else {
                    Task { await submitIntent(provider: provider, currency: currency, phone: number) }
                }
            }
        }
        .sheet(item: $scheduleDetail) { s in
            ScheduleDetailSheet(schedule: s,
                                rail: vm.methods.method(s.method),
                                phoneOnFile: vm.methods.phoneOnFile,
                                followsMonthlyPledge: ScheduleCopy.followsMonthlyPledge(s) { vm.pledgeShape($0) },
                                onOpenPledge: { id in
                                    // The pledge is where its collector's
                                    // amount and day are changed (Cycle 5).
                                    scheduleDetail = nil
                                    tabs.openPledge(id)
                                },
                                onClose: { scheduleDetail = nil },
                                onUpdated: {   // changed in place — the sheet stays
                                    GivingSignal.post(from: vm)
                                    Task { await vm.load() }
                                },
                                onChanged: {   // cancelled, paused or resumed
                                    scheduleDetail = nil
                                    GivingSignal.post(from: vm)   // Partners' standing derives from schedules
                                    Task { await vm.load() }
                                })
        }
        .fullScreenCover(isPresented: Binding(get: { ceremony != nil }, set: { if !$0 { endCeremony() } }),
                         onDismiss: {
                             if resetFormAfterCeremony {
                                 resetFormAfterCeremony = false
                                 withAnimation(.easeInOut(duration: 0.2)) { resetFormToDefaults() }
                             }
                         }) {
            // A waiting prompt (409 GIFT_IN_PROGRESS) is described from its
            // own record — it may not be the gift on the form.
            GiveCeremonyView(stage: ceremony ?? "failed",
                             note: ceremonyNote,
                             failure: ceremonyFailure,
                             amountLabel: waitingGift?.amountLabel ?? totalLabel,
                             fundLabel: elsewhere.map { "your pledge \u{201C}\($0.pledgeTitle)\u{201D}" } ?? fund.label,
                             destination: waitingGift?.destination ?? ceremonyDestination,
                             giftName: waitingGift != nil ? waitingGift?.giftName : (accountName.isEmpty ? nil : accountName),
                             phone: waitingGift == nil ? promptPhone : nil,
                             refCode: successRef,
                             txId: pendingTxId,
                             cadenceWord: elsewhere.map { ScheduleRhythm.isWeekly($0.frequency) ? "week" : "month" } ?? cadenceWord,
                             nextChargeLabel: scheduledNextAt.isEmpty ? nil : giveDateFull(scheduledNextAt),
                             scheduledNote: scheduledNote,
                             nothingTodayLine: scheduledNextAt.isEmpty ? nil : ScheduleRhythm.nothingTodayLine(firstPromptISO: scheduledNextAt),
                             retrying: submitting,
                             stkLate: stkLate,
                             onDone: { endCeremony() },
                             // Giving Cycle 3: a failed gift is retried on the
                             // server (same fund, amount, pledge, fee cover)
                             // and watched; a refusal that made no gift goes
                             // back to the form with the amount and fund kept.
                             onRetry: { tryAgain() })
        }
    }

    // MARK: Header (cream hero — matches the Figma header; do not restyle)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            // ONE band (Partners UI v2): the GIVE · PARTNERS switch is the
            // band's first row, so the "GIVE" eyebrow it replaced is gone —
            // the tab's bell at its right (§6.2).
            if let segment, let onSelectSegment {
                GiveSwitchRow(selection: segment, onSelect: onSelectSegment)
                    .padding(.bottom, 12)
            }
            // The one header's words (§8.1 rules 2–3); the switch above
            // names the tab, so no eyebrow repeats it.
            NuruHeaderText(title: "Sow into the Kingdom", line: "Generosity is worship — a quiet, joyful act.")

            if vm.yearKnown {
            HStack(spacing: 10) {
                // The year pill opens the statement — the same page "View
                // statement" reaches further down.
                NavigationLink(value: GiveRoute.statement) {
                    HStack(spacing: 8) {
                        Icon(.badgeCheck, size: 14, color: Nuru.gold)
                        Text(yearPillText)
                            .font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                            .nuruLineLimit(1).minimumScaleFactor(0.85)   // "KSh 1,200 giv…" at the largest (§9.6 #4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    // A capsule while it is one line; a rounded card when the
                    // largest sizes wrap it, so the ends never crowd the words.
                    .background(Color.white, in: yearPillShape)
                    .overlay(yearPillShape.stroke(Nuru.gold.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityHint("Opens your giving statement")

                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.15)) { hideYearTotal.toggle() }
                } label: {
                    Icon(hideYearTotal ? .eyeOff : .eye, size: 14, color: Nuru.navy)
                        .frame(width: 36, height: 36)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(hideYearTotal ? "Show the amount given this year" : "Hide the amount given this year")
                Spacer(minLength: 0)
            }
            .padding(.top, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        // Right under the status bar: the tab no longer reserves a band above
        // this one, so clear the REAL inset (NuruSafeArea) — never a fixed 60.
        .padding(.top, embeddedInYou ? NuruSafeArea.top + 8 : 60)
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

    private var yearPillShape: AnyShape {
        typeSize.isAccessibilitySize ? AnyShape(RoundedRectangle(cornerRadius: 20, style: .continuous)) : AnyShape(Capsule())
    }

    /// "KSh 12,340 given this year" — or bullets while the member has chosen
    /// to hide it. The word "given" stays, so the pill still says what it is.
    /// Per currency (Giving Cycle 2): "KSh 3,500 + US$ 20.00 given this year"
    /// — shillings and dollars are never added together.
    private var yearPillText: String {
        hideYearTotal ? "KSh •••• given this year" : "\(GiveMoney.line(vm.yearTotals)) given this year"
    }

    // MARK: Repeat last gift

    private func repeatCard(_ g: GivingRecord) -> some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { applyRepeat(g) }
        } label: {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.gold)
                        .frame(width: 36, height: 36)
                    Icon(.repeat, size: 18, color: Nuru.navy)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat last gift").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    // Whole at the largest size: "KSh 200…" (§9.6 #4).
                    Text("\(money(g.amountMinor, g.currency)) · \(g.fund.capitalized) · via \(givingMethodName(g.method))")
                        .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                        .nuruLineLimit(1).fixedSize(horizontal: false, vertical: true)
                    if typeSize.isAccessibilitySize {
                        Text("Give again")
                            .font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                            .padding(.top, 4)
                    }
                }
                Spacer(minLength: Nuru.S.sm)
                if !typeSize.isAccessibilitySize {
                    Text("Give again")
                        .font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.priorityBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    // MARK: Funds

    private var fundsSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            overline("CHOOSE A FUND")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(funds) { f in fundCard(f) }
                }
                .padding(.vertical, 2)
            }
            // (A pledge / need payment never shows this chooser — the pay-mode
            // card says where the server routes it.)
        }
    }

    private func fundCard(_ f: Fund) -> some View {
        let on = f.code == fundCode
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { fundCode = f.code }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: f.tint))
                        .frame(width: 36, height: 36)
                    Icon(f.icon, size: 18, color: Color(hex: f.fg))
                }
                Text(f.label).font(.inter(13, .semibold)).kerning(-0.13).foregroundStyle(Nuru.navy)
                    .nuruLineLimit(1).minimumScaleFactor(0.85)
                    .fixedSize(horizontal: false, vertical: true)
                    .nuruWholeWords(f.label, font: .inter(13, .semibold), kerning: -0.13)
                    .padding(.top, 8)
                Text(f.tagline).font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                    .nuruLineLimit(2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            // The rail scrolls sideways: at the largest sizes a card is wider
            // and its words whole ("Offeri…", "A faithf…"; §9.6 #4).
            .frame(width: typeSize.isAccessibilitySize ? 240 : 124, alignment: .leading)
            .padding(12)
            .background(on ? Nuru.priorityBg : Nuru.white,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 2 : 1))
        }
        .buttonStyle(.pressable)
    }

    // MARK: Amount (centred, per Figma)

    private var amountCard: some View {
        VStack(spacing: 0) {
            Button {
                Haptics.tap()
                showKeypad = true
            } label: {
                VStack(spacing: 4) {
                    Text("AMOUNT").font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        // PayPal takes dollars (Giving Cycle 2): the field says
                        // so, and shows cents.
                        Text(inDollars ? "US$" : "KSh").font(.inter(14, .medium)).foregroundStyle(Color(hex: 0x74808F))
                        Text(inDollars ? GiveMoney.number(usdCents) : amount.formatted(.number.grouping(.automatic)))
                            .font(.fraunces(28, .semibold)).kerning(-1.2).foregroundStyle(Nuru.navy)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .contentTransition(.numericText(value: Double(giftMinor)))
                    }
                    Text(amountSubtitle).font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if inDollars {
                        Text("PayPal gifts are in US dollars")
                            .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x0070BA))
                    }
                    if let amountProblem {
                        Text(amountProblem)
                            .font(.inter(11)).foregroundStyle(Nuru.danger)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            presetsRow.padding(.top, Nuru.S.base)
            // The custom choice, BELOW the suggested amounts on its own row
            // (owner's revision, 2026-08-24) — inside the chip flow it wrapped
            // or scrolled out of sight, and a giver who wants their own number
            // should never have to hunt for the door.
            Button {
                Haptics.tap()
                showKeypad = true
            } label: {
                HStack(spacing: 6) {
                    Icon(.pencil, size: 14, color: Nuru.gold)
                    // Whole at the largest size: "Enter a custo…" (§9.6 #4).
                    Text("Enter a custom amount").font(.inter(13, .bold)).foregroundStyle(Nuru.gold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity).frame(minHeight: 38)
                .background(Nuru.white, in: Capsule())
                .overlay(Capsule().stroke(Nuru.gold.opacity(0.55), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .padding(.top, 8)
        }
        .padding(Nuru.S.screen)
        .frame(maxWidth: .infinity)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    /// The suggested amounts in the rail's own money: KSh 200 … 5,000, or
    /// US$ 5 … 100 while PayPal is chosen. Minor units either way.
    private var presetMinors: [Int] { inDollars ? UsdEntry.presetsCents : presets.map { $0 * 100 } }

    /// One line of pills, as Android (§8.2 #7) — they wrapped "5,000" onto
    /// a row of its own, pushing "Enter a custom amount" under the Give button.
    private var presetsRow: some View {
        NuruAmountPills(amounts: presetMinors, selected: giftMinor,
                        label: { ($0 / 100).formatted(.number.grouping(.automatic)) }) { v in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if inDollars { usdCents = v } else { amount = v / 100 }
            }
        }
    }

    // MARK: Frequency

    private var frequencyRow: some View {
        HStack(spacing: 4) {
            ForEach([("once", "One-time"), ("weekly", "Weekly"), ("monthly", "Monthly")], id: \.0) { key, label in
                let on = freq == key
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { freq = key }
                } label: {
                    Text(label)
                        .font(.inter(13, .semibold))
                        .foregroundStyle(on ? Nuru.navy : Color(hex: 0x5B6472))
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(on ? Nuru.white : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .nuruShadow(on ? 0.6 : 0)
                }.buttonStyle(.plain)
                .accessibilityShowsLargeContentViewer()
            }
        }
        .padding(4)
        .background(Color(hex: 0x0A2540, alpha: 0.06),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        // A bar: "One… Wee… Mon…" at the largest size (§9.6 #4); a long press
        // shows a choice large.
        .nuruBarText()
    }

    /// Honest recurring summary. The day is the server's (today's Nairobi
    /// weekday, or today's day of the month); whether the first gift is today
    /// or next cycle is the member's choice at the next step (Giving Cycle 4).
    private var recurringSummary: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.gold)
                    .frame(width: 36, height: 36)
                Icon(.repeat, size: 18, color: Nuru.navy)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(totalLabel) every \(cadenceWord)")
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text("\(recurringDayLine.prefix(1).uppercased() + recurringDayLine.dropFirst()) — start with a gift today, or from the next one. Cancel anytime.")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.priorityBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
    }

    /// "every Sunday" · "every month on the 28th" — the day a gift set up
    /// today falls on.
    private var recurringDayLine: String {
        ScheduleRhythm.cadence(frequency: freq, day: ScheduleRhythm.setupDay(frequency: freq, now: Date()))
    }

    // MARK: Recurring gifts (EXPERIENCE.md §9.2 #6) — leading the tab

    /// One recurring gift, full width (§9.1 rule 6): its rhythm and when it
    /// next prompts ("KSh 1,000 every Monday · next Mon 12 Oct"), its fund and
    /// the pledge it collects, what the next prompt really asks, a pause or a
    /// failing prompt in words; a tap opens its sheet (change, pause, resume,
    /// cancel). It was told twice — "Your rhythm" under the amount and a
    /// half-width card in a rail below the fold.
    private func recurringGiftRow(_ s: GivingSchedule) -> some View {
        let paused = s.status.lowercased() == "paused"
        let fund = funds.first { $0.code == s.fund }?.label ?? s.fund.capitalized
        let title = paused
            ? "\(money(s.amountMinor, s.currency)) \(ScheduleRhythm.isWeekly(s.frequency) ? "weekly" : "monthly") · Paused"
            : (ScheduleRhythm.rowText(for: s) ?? "\(money(s.amountMinor, s.currency)) \(ScheduleRhythm.isWeekly(s.frequency) ? "weekly" : "monthly")")
        return Button {
            Haptics.tap()
            scheduleDetail = s
        } label: {
            HStack(spacing: Nuru.S.md) {
                Icon(.repeat, size: 18, color: Nuru.navy)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: Nuru.tileTint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.nRowTitle).foregroundStyle(Nuru.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(paused ? "\(fund) · \(PauseCopy.cardLine(for: s))" : fund)
                        .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                        .fixedSize(horizontal: false, vertical: true)
                    // The pledge it collects, and what the next prompt really asks.
                    ForEach([ScheduleCopy.pledgeLine(s), ScheduleCopy.nextLine(s)].compactMap { $0 }, id: \.self) { line in
                        Text(line).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // Why its last prompt failed, while it still fails — the server's words.
                    if let f = s.lastFailure, !f.reason.isEmpty {
                        Text(f.reason).font(.inter(12, .semibold)).foregroundStyle(Nuru.urgentText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Nuru.S.sm)
                Icon(.chevronRight, size: 18, color: Nuru.ink300)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens your recurring gift")
    }

    // MARK: Pay methods

    private var methodSection: some View {
        let rails = orderedMethods
        return VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack {
                overline(rails.count == 1 ? "HOW YOU'LL PAY" : "CHOOSE HOW TO PAY")
                Spacer()
                // Order is a choice only between two or more.
                if rails.count > 1 {
                    HStack(spacing: 4) {
                        Icon(.gripVertical, size: 14, color: Color(hex: 0x74808F))
                        Text("Reorder").font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
                    }
                }
            }
            if rails.isEmpty {
                // Nothing can take this gift from this phone: say so, in place.
                Text(payRailsCurrency.map { vm.methods.unavailableNote(forCurrency: $0) }
                     ?? "Giving from this phone isn't available right now.")
                    .font(.nCardBody).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: Nuru.S.sm) {
                ForEach(Array(rails.enumerated()), id: \.element.id) { idx, m in
                    methodRow(m, index: idx, reorderable: rails.count > 1)
                }
            }
        }
    }

    @ViewBuilder
    private func methodRow(_ m: MethodRow, index: Int, reorderable: Bool) -> some View {
        // A rail the server says cannot take money here (or this build cannot
        // complete) wears SOON / UNAVAILABLE and cannot be picked.
        let badge = vm.methods.unavailableBadge(m.key)
        let on = method == m.key && badge == nil
        let soon = badge != nil
        HStack(spacing: 8) {
            Button {
                guard !soon, method != m.key else { return }
                Haptics.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selectMethod(m.key) }
            } label: {
                HStack(spacing: Nuru.S.md) {
                    methodBadge(m.look)
                    VStack(alignment: .leading, spacing: 2) {
                        // Whole at the largest size: "Pay wi…", "0700 0…" (§9.6 #4).
                        Text(m.look.label).font(.inter(14, .semibold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                            .nuruLineLimit(1).minimumScaleFactor(0.85)
                            .fixedSize(horizontal: false, vertical: true)
                        if on {
                            Text(activeDetail(m)).font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                                .nuruLineLimit(1).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: Nuru.S.sm)
                    if let badge {
                        Text(badge)
                            .font(.inter(11, .bold)).kerning(0.5).foregroundStyle(Nuru.goldChipText)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Nuru.goldChipBg, in: Capsule())
                    }
                    if on {
                        ZStack {
                            Circle().fill(Nuru.gold).frame(width: 24, height: 24)
                            Icon(.check, size: 14, color: Nuru.navy)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if reorderable {
                VStack(spacing: 2) {
                    Button { nudgeMethod(from: index, by: -1) } label: {
                        Icon(.chevronUp, size: 14, color: Nuru.ink300)
                            .frame(width: 26, height: 22).contentShape(Rectangle())   // easier to hit
                    }.buttonStyle(.plain).disabled(index == 0)
                    Button { nudgeMethod(from: index, by: 1) } label: {
                        Icon(.chevronDown, size: 14, color: Nuru.ink300)
                            .frame(width: 26, height: 22).contentShape(Rectangle())
                    }.buttonStyle(.plain).disabled(index == orderedMethods.count - 1)
                }
                Icon(.gripVertical, size: 18, color: Color(hex: 0xC4C9D0))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? Nuru.priorityBg : Nuru.white,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 1.5 : 1))
        .opacity(soon ? 0.7 : 1)
    }

    /// Under the selected rail: the number its prompt will go to, once there
    /// is a valid one (the sheet asks for it otherwise).
    private func activeDetail(_ m: MethodRow) -> String {
        guard m.rail.needsPhone, let number = KenyanPhone.normalize(mpesaPhone) else { return m.look.sub }
        return KenyanPhone.display(number)
    }

    private func methodBadge(_ m: PayMethod) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: m.badgeBg)).frame(width: 52, height: 40)
            if let icon = m.icon {
                Icon(icon, size: 18, color: Color(hex: m.badgeFg))
            } else {
                // The rail's short name whole, at the 11 pt floor (§8.1 rule 3) —
                // the badge is wide enough that it never shrinks under it.
                Text(m.badgeText)
                    .font(.inter(11, .heavy)).kerning(-0.2)
                    .foregroundStyle(Color(hex: m.badgeFg))
                    .lineLimit(1).fixedSize()
            }
        }
        // A figure in a fixed shape keeps the everyday size (§9.6 #4): the
        // rail's name spilled out of its badge; the row's own words grow.
        .nuruFixedFigure()
    }

    // MARK: Cover fee

    private var coverFeeRow: some View {
        Toggle(isOn: $coverFee) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cover the transaction fee").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Text("Adds \(ksh(CoverFee.feeKsh(forGiftKsh: amount))) — 100% reaches the fund")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
            }
        }
        .tint(Nuru.gold)
        .padding(12)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .onChange(of: coverFee) { _, _ in Haptics.tap() }
    }

    // MARK: Recent giving

    private var recentGifts: [GivingRecord] {
        Array(vm.history.filter { GiveMoney.isSettled($0.status) }.prefix(3))
    }

    // MARK: Pay mode — PAYING YOUR PLEDGE / GIVING TO A NEED

    /// Replaces "Repeat last gift", the fund chooser and the frequency switch
    /// while a pledge or need preset is active: what is being paid, the
    /// promise, where the server sends the money, and a quiet way back to an
    /// ordinary gift (the old chip's "Remove").
    private var payModeCard: some View {
        let isPledge = pledgeId != nil
        let title = isPledge ? (pledgeTitle ?? "Your pledge") : (needTitle ?? "A department need")
        let line = isPledge ? pledgeLine : needLine
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Icon(isPledge ? .heartHandshake : .target, size: 14, color: Nuru.gold)
                overline(isPledge ? "PAYING YOUR PLEDGE" : "GIVING TO A NEED")
            }
            Text(title)
                .font(.fraunces(18, .semibold)).foregroundStyle(Nuru.navy)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            if let line, !line.isEmpty {
                Text(line).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                    .padding(.top, 3)
            }
            HStack(spacing: 6) {
                Icon(.shieldCheck, size: 14, color: Color(hex: 0x74808F))
                Text(routedLine).font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
            }
            .padding(.top, 10)
            Button {
                Haptics.selection()
                withAnimation(.easeInOut(duration: 0.2)) { clearPayMode() }
            } label: {
                Text("Give to a fund instead")
                    .font(.inter(12, .semibold)).foregroundStyle(Nuru.ink600).underline()
            }
            .buttonStyle(.plain)
            .padding(.top, 12)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.priorityBg, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    /// "Goes to the Discipleship fund" — the pledge's `pays_to` (a name that
    /// already says "fund" is not doubled). "Routed by the church" when the
    /// server sent none, and for a need (its department's fund is the
    /// server's call).
    private var routedLine: String {
        guard pledgeId != nil, let to = paysTo else { return "Routed by the church" }
        let name = to.name.isEmpty ? to.code.capitalized : to.name
        return name.lowercased().hasSuffix("fund") ? "Goes to the \(name)" : "Goes to the \(name) fund"
    }

    /// "Building pledge" — a title that already ends in the word is not doubled.
    private var pledgeLabel: String {
        let t = (pledgeTitle ?? "").trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return "Your pledge" }
        return t.lowercased().hasSuffix("pledge") ? t : "\(t) pledge"
    }

    /// What the gift is, in pay mode (nil otherwise) — the keypad's label.
    private var payLabel: String? {
        if pledgeId != nil { return pledgeLabel }
        if needId != nil { return needTitle ?? "A department need" }
        return nil
    }

    /// Under the amount: "<title> pledge · one-time" in pay mode, else the
    /// fund and the frequency.
    private var amountSubtitle: String {
        if let payLabel { return "\(payLabel) · one-time" }
        return "\(fund.label) · \(freqLabel)"
    }

    /// Back to an ordinary gift — the pledge / need no longer rides the intent.
    private func clearPayMode() {
        pledgeId = nil; pledgeTitle = nil; pledgeLine = nil; paysTo = nil
        needId = nil; needTitle = nil; needLine = nil
        payCurrency = nil
    }

    /// The form's normal state: the default fund and amount, one-time.
    private func resetFormToDefaults() {
        fundCode = Self.defaultFundCode
        amount = Self.defaultAmount
        freq = "once"
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                // The link under the overline at the largest sizes: beside it,
                // "View statemen / t" (§9.6 #4).
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        overline("RECENT GIVING")
                        statementLink
                    }
                } else {
                    HStack {
                        overline("RECENT GIVING")
                        Spacer()
                        statementLink
                    }
                }
            }
            .padding(.horizontal, Nuru.S.base).padding(.top, 14).padding(.bottom, 6)

            if recentGifts.isEmpty {
                HStack(spacing: 8) {
                    Icon(.handHeart, size: 14, color: Nuru.gold)
                    Text("No gifts yet — your first one will appear here the moment it settles.")
                        .font(.nCardBody).foregroundStyle(Color(hex: 0x5B6472))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Nuru.S.base).padding(.bottom, 14)
            } else {
                ForEach(Array(recentGifts.enumerated()), id: \.element.id) { i, g in
                    NavigationLink(value: g) { recentRow(g) }.buttonStyle(.pressable)
                    if i != recentGifts.count - 1 {
                        Divider().overlay(Nuru.border).padding(.leading, Nuru.S.base)
                    }
                }
            }
        }
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // Always reachable — the statement page has its own empty state, so the
    // giving record + receipts stay discoverable even before the first gift.
    private var statementLink: some View {
        NavigationLink(value: GiveRoute.statement) {
            HStack(spacing: 3) {
                Text("View statement").font(.inter(12, .semibold))
                Icon(.arrowRight, size: 14, color: Nuru.gold)
            }.foregroundStyle(Nuru.gold)
        }
    }

    private func recentRow(_ g: GivingRecord) -> some View {
        Group {
            // The amount under the words at the largest sizes: beside it the
            // date and rail were cut ("Mon 5 O…"; §9.6 #4).
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    recentWords(g)
                    recentAmount(g).padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack {
                    recentWords(g)
                    Spacer()
                    recentAmount(g).layoutPriority(1)
                }
            }
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, 11)
        .contentShape(Rectangle())
    }

    private func recentWords(_ g: GivingRecord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(g.fund.capitalized).font(.inter(14, .semibold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                .nuruLineLimit(1).fixedSize(horizontal: false, vertical: true)
            Text("\(giveDateShort(g.shownAt)) · \(givingMethodName(g.method))")
                .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                .nuruLineLimit(1).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func recentAmount(_ g: GivingRecord) -> some View {
        Text(money(g.amountMinor, g.currency))
            .font(.inter(14, .semibold)).kerning(-0.14).foregroundStyle(Nuru.navy)
            .lineLimit(1)
    }

    // MARK: Scripture + secure note

    private var scriptureStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\u{201C}Each of you should give what you have decided in your heart to give.\u{201D}")
                .font(.fraunces(15, .medium)).italic().foregroundStyle(Nuru.navy)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            Text("2 Corinthians 9:7").font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0xA8861C))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(
            LinearGradient(colors: [Nuru.gold.opacity(0.10), Nuru.paper],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.gold.opacity(0.2), lineWidth: 1))
    }

    private var secureNote: some View {
        HStack(spacing: 6) {
            Icon(.shieldCheck, size: 14, color: Color(hex: 0x74808F))
            // Only rails that can take money here (it used to promise cards).
            Text(vm.methods.secureNote())
                .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    // MARK: Sticky CTA (quiet gold outline, per Figma)

    private var ctaBar: some View {
        Button {
            Haptics.action()
            Task { await give() }
        } label: {
            HStack(spacing: 6) {
                if submitting {
                    ProgressView().tint(Nuru.navy).scaleEffect(0.8)
                    Text("Processing…")
                } else if pledgeId != nil {
                    // A long pledge name takes a second line before the label
                        // would shrink under 11 pt (14 × 0.8 = 11.2).
                    Text("Pay \(totalLabel) toward \(pledgeTitle ?? "your pledge")")
                        .font(.inter(14, .bold)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Icon(.arrowRight, size: 14, color: Nuru.navy)
                } else if needId != nil {
                    Text("Give \(totalLabel) to \(needTitle ?? "this need")")
                        .font(.inter(14, .bold)).multilineTextAlignment(.center)
                        .lineLimit(2).minimumScaleFactor(0.8)
                    Icon(.arrowRight, size: 14, color: Nuru.navy)
                } else if recurring {
                    Icon(.repeat, size: 14, color: Nuru.navy)
                    Text("Schedule \(totalLabel) / \(cadenceWord)")
                } else {
                    Text("Give \(totalLabel)")
                    Icon(.arrowRight, size: 14, color: Nuru.navy)
                }
            }
            // A BLOCK, not an outline (owner, 2026-08-24): the transparent
            // fill let the fee row read straight through the button. Solid
            // gold with ink text — the same voice as every primary CTA.
            .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(
                LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Nuru.gold.opacity(0.35), radius: 8, x: 0, y: 4)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        // Nothing to give, or an amount the rail cannot take (said under it).
        .disabled(submitting || giftMinor <= 0 || amountProblem != nil)
        .opacity(giftMinor <= 0 || amountProblem != nil ? 0.5 : 1)
        .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.lg)
        // Above the floating tab bar, not behind it. 28pt put this bar UNDER
        // the shell's ~96pt floating tabs — on every device only a gold sliver
        // peeked out beneath them (owner's screenshot, 2026-08-23). The give
        // button is the whole point of the screen; it rides clear of the bar.
        .padding(.bottom, Nuru.tabBarSpace + 10)
        .background(
            // Solid paper behind the button and the tab area — the fade lives
            // only in the top fifth, so nothing ever shows through the block.
            LinearGradient(stops: [.init(color: Nuru.paper.opacity(0), location: 0),
                                   .init(color: Nuru.paper, location: 0.18)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    // MARK: Actions

    private func give() async {
        guard giftMinor > 0, amountProblem == nil, !submitting else { return }
        ceremonyFailure = nil; waitingGift = nil; setRetryTarget(nil, method: nil)
        // Only a rail the server says can take money here (Cycle 1). The form
        // moves off any other as the methods load, so landing here means none
        // can — say so rather than send a request that cannot succeed.
        guard vm.methods.isSelectable(method, onlyCurrency: payRailsCurrency), let rail = vm.methods.method(method) else {
            // Paying a USD pledge while PayPal is off says why in its terms.
            ceremonyNote = payMode ? vm.methods.unavailableNote(forCurrency: payCurrencyCode)
                                   : vm.methods.unavailableNote(method)
            ceremony = "failed"; return
        }
        if rail.needsPhone {
            // Mobile money — a one-time gift or a schedule alike: confirm the
            // number the prompt goes to; the sheet sends it (as E.164).
            showMpesaSheet = true
            return
        }
        if recurring { await createSchedule(provider: method, phone: nil, giveNow: false); return }
        switch method {
        case "paypal":
            // In dollars (Giving Cycle 2) — never a shilling number.
            await submitIntent(provider: "paypal", currency: currency, phone: nil)
        default:
            // A rail with no in-app flow (a card needs the Stripe step, SAQ-A)
            // is never selectable; surfaced rather than faked if it ever is.
            ceremonyNote = vm.methods.unavailableNote(method); ceremony = "failed"
        }
    }

    /// POST /giving/schedules — a real server-charged recurring gift. The server
    /// makes the first charge on the next cycle boundary (never faked here).
    /// `phone` is the number every cycle's prompt goes to (Cycle 1).
    private func createSchedule(provider: String, phone: String?, giveNow: Bool) async {
        guard vm.methods.allowsRecurring(provider) else {
            ceremonyNote = "Recurring gifts work with M-Pesa for now."
            ceremony = "failed"
            return
        }
        guard !submitting else { return }   // one request in flight, ever
        submitting = true; defer { submitting = false }
        ceremonyFailure = nil; waitingGift = nil; setRetryTarget(nil, method: nil)
        scheduledNote = nil
        intentFundName = nil; intentPledgeTitle = nil; intentIsPledge = false
        let frequency = freq
        do {
            // "Start with a gift now" (Giving Cycle 4): the first prompt goes
            // out at once as the schedule's first cycle; otherwise nothing is
            // taken today.
            let res = try await MemberAPI.createSchedule(fund: fund.code, amountMinor: totalMinor, currency: currency,
                                                         frequency: frequency, method: provider,
                                                         idempotencyKey: submissionKey, phoneNumber: phone,
                                                         firstCharge: giveNow ? "now" : "next")
            submissionKey = GiveKey.fresh()   // answered — a replay (`reused`) is handled the same
            if let phone { phoneMemory.remember(phone, for: auth.profile?.userId) }
            Haptics.success()   // the server really created the schedule
            GivingSignal.post(from: vm)   // Partners' standing derives from schedules
            scheduledNextAt = res.nextRunAt
            if giveNow, let first = res.firstCharge {
                // Today's gift is on its way to the phone — watch it like any
                // other gift; the schedule is already standing behind it.
                let kind = ScheduleRhythm.isWeekly(frequency) ? "weekly" : "monthly"
                await beginWatching(first, provider: provider, phone: phone,
                                    note: "Your \(kind) gift is set up — this is its first prompt.")
            } else if giveNow {
                // The schedule stands; only today's prompt could not go out.
                scheduledNote = [res.firstChargeError, ScheduleRhythm.setUpLine(frequency: frequency, firstPromptISO: res.nextRunAt)]
                    .compactMap { $0 }.joined(separator: " ")
                ceremony = "scheduled"
            } else {
                ceremony = "scheduled"
            }
            await vm.load()
        } catch {
            // Keep the key ONLY when the server never answered.
            if !Self.gotNoServerAnswer(error) { submissionKey = GiveKey.fresh() }
            switch GiveRefusal.from(error) {
            case let .promptWaiting(tx, message):
                // A prompt is already on the phone: nothing was created — watch
                // that one; the member can set the schedule up after it.
                await watchWaitingPrompt(tx, message: message)
            case let .message(text):
                // The server's own words — 409 SCHEDULE_EXISTS and the 422s too.
                ceremonyNote = text
                ceremony = "failed"
                Haptics.error()
            }
        }
    }

    private func submitIntent(provider: String, currency: String, phone: String?) async {
        // One intent in flight, ever — a double tap on the M-Pesa sheet's
        // confirm (it calls back before its dismissal lands) is refused here.
        guard giftMinor > 0, !submitting else { return }
        submitting = true; defer { submitting = false }
        paypalOrderId = nil
        intentFundName = nil; intentPledgeTitle = nil; intentIsPledge = false
        waitingGift = nil; ceremonyFailure = nil; promptPhone = nil
        setRetryTarget(nil, method: nil)
        // `amount_minor` is the TOTAL charged; `cover_fee_minor` the part of
        // it that covers the fee (Giving Cycle 2), so the receipt can say so.
        let charge = self.charge
        do {
            let res = try await MemberAPI.giving(fund: fund.code, amountMinor: charge.amountMinor,
                                                 currency: currency, method: provider, phoneNumber: phone,
                                                 accountName: accountName.isEmpty ? nil : accountName,
                                                 pledgeId: pledgeId, needId: needId,
                                                 idempotencyKey: submissionKey,
                                                 coverFeeMinor: charge.coverFeeMinor)
            // The server answered: this key is spent. A replay (`reused: true`,
            // the existing transaction) is handled exactly like a fresh one.
            submissionKey = GiveKey.fresh()
            await beginWatching(res, provider: provider, phone: phone)
        } catch {
            // Keep the key ONLY when the server never answered — the next
            // Pay tap then replays it and gets the transaction back if the
            // request did land. After any HTTP response, a fresh key: a 409
            // CONFLICT (the key is another gift's) then goes through on the
            // next tap, and a 429 RATE_LIMITED (several prompts to a number
            // not the member's own) is said in the server's words — neither
            // is ever sent again without a tap (Giving Cycle 6).
            if !Self.gotNoServerAnswer(error) { submissionKey = GiveKey.fresh() }
            switch GiveRefusal.from(error) {
            case let .promptWaiting(tx, message):
                // Not a failure: this member's prompt from a moment ago is
                // still on their phone (409 GIFT_IN_PROGRESS). Watch that one.
                await watchWaitingPrompt(tx, message: message)
            case let .message(text):
                // The server's own words (the 422s included), shown as-is.
                ceremonyNote = text
                ceremony = "failed"
                Haptics.error()
            }
        }
    }

    /// The server made (or found) the gift — a new one, a retry, a schedule's
    /// first — and the ceremony watches it: the number the prompt went to is
    /// remembered and shown, where the SERVER routed the money is what the
    /// ceremony says, PayPal opens its approval, and the poll reports the truth.
    private func beginWatching(_ res: GivingIntentResult, provider: String?, phone: String?, note: String = "") async {
        // The server took a prompt to this number: it is where the next
        // gift from this phone starts (kept per member), and what the
        // ceremony says the prompt went to.
        if let phone {
            phoneMemory.remember(phone, for: auth.profile?.userId)
            promptPhone = phone
        }
        pendingTxId = res.transactionId
        // A resend of the same key answers with the gift's provider_ref —
        // null while its prompt is still being sent (Giving Cycle 6). Not an
        // error: the gift is watched by its transaction id either way.
        successRef = res.providerRef
        // The server's word on where the gift went (pledge names
        // contract) — the ceremony reads this, not the chip.
        intentFundName = res.fund.flatMap { $0.name.isEmpty ? nil : $0.name }
        if let p = res.pledge {
            intentIsPledge = true
            intentPledgeTitle = p.title.isEmpty ? pledgeTitle : p.title
        }
        if (res.provider ?? provider) == "paypal", let url = res.approveUrl.flatMap(URL.init) {
            // The intent's provider_ref IS the PayPal order id — we capture it
            // once the member approves and comes back (see attemptPayPalCapture).
            paypalOrderId = res.providerRef
            await UIApplication.shared.open(url)
            ceremonyNote = "Approve in PayPal, then return to the app."
        } else {
            ceremonyNote = note   // mobile-money STK push
        }
        ceremony = "stk"
        // The intent exists (pending) — Partners shows it as Processing.
        GivingSignal.post(from: vm)
        startWatching(res.transactionId)
    }

    /// "Try again" on the failed result (Giving Cycle 3): the gift that failed
    /// is retried BY THE SERVER — same fund, amount, currency, pledge or need,
    /// name and fee cover (POST /giving/transactions/{id}/retry) — with its
    /// own idempotency key, and the ceremony watches the new gift like any
    /// other. A prompt still waiting is watched instead (GIFT_IN_PROGRESS);
    /// a refusal says why, and the next Try again goes back to the form.
    private func retryGift(_ failedTx: String) async {
        guard !submitting else { return }
        submitting = true; defer { submitting = false }
        paypalOrderId = nil
        intentFundName = nil; intentPledgeTitle = nil; intentIsPledge = false
        // Mobile money prompts the number that gift went to — else the
        // member's own; PayPal and cards prompt no phone. A gift made on a
        // pledge's page (Giving Cycle 9) went to the profile's number, and
        // its retry sends none so the server prompts that number again —
        // never the one on this form.
        let prompts = retryMethod == "mpesa" || retryMethod == "airtel"
        let phone = prompts && elsewhere == nil ? (promptPhone ?? KenyanPhone.normalize(mpesaPhone)) : nil
        do {
            let res = try await MemberAPI.retryGift(failedTx, idempotencyKey: retryKey, phoneNumber: phone)
            retryKey = GiveRetry.key(after: nil, current: retryKey)
            ceremonyFailure = nil
            retryTxId = nil
            await beginWatching(res, provider: retryMethod, phone: phone)
        } catch {
            // A fresh key after any answer; the same gift stays the target
            // only when there was no answer or only the key was refused (409
            // CONFLICT) — a 429 RATE_LIMITED sends the member back to the
            // form, and nothing is ever retried without a tap (Giving Cycle 6).
            retryKey = GiveRetry.key(after: error, current: retryKey)
            retryTxId = GiveRetry.target(after: error, retrying: failedTx)
            switch GiveRefusal.from(error) {
            case let .promptWaiting(tx, message):
                await watchWaitingPrompt(tx, message: message)
            case let .message(text):
                // Still the failed result — now saying why the retry was refused.
                ceremonyFailure = nil
                ceremonyNote = text
                ceremony = "failed"
                Haptics.error()
            }
        }
    }

    /// Points "Try again" at a failed gift. A different gift gets a fresh
    /// retry key — a key is never replayed across gifts.
    private func setRetryTarget(_ tx: String?, method: String?) {
        if tx != retryTxId { retryKey = GiveKey.fresh() }
        retryTxId = tx
        retryMethod = method
    }

    /// The failed result's "Try again": retry the gift that failed, or — when
    /// the refusal made no gift — back to the form, amount and fund kept.
    private func tryAgain() {
        switch GiveRetry.action(failedTransactionId: retryTxId) {
        case .retry(let tx): Task { await retryGift(tx) }
        case .backToForm: endCeremony()
        }
    }

    /// A giving notification's target (Giving Cycle 3). A failed gift opens
    /// its result — why, what to do, Try again — described from its own
    /// record; one that did not fail (it may have been paid since) opens its
    /// receipt. Never over a gift already on screen.
    private func open(_ link: GiveLink) {
        switch link {
        case .failedGift(let tx):
            guard ceremony == nil, !submitting else { return }
            Task {
                let d = try? await MemberAPI.givingDetail(tx)
                guard ceremony == nil, !submitting else { return }
                guard let d, ["failed", "cancelled"].contains(d.status) else {
                    receiptLink = ReceiptLink(id: tx)
                    return
                }
                waitingGift = WaitingGift(d)
                ceremonyFailure = d.failure.flatMap { $0.reason.isEmpty ? nil : $0 }
                ceremonyNote = ceremonyFailure == nil ? "The payment didn't complete — no charge was made." : ""
                pendingTxId = tx
                successRef = nil
                promptPhone = nil
                setRetryTarget(tx, method: d.method)
                ceremony = "failed"
            }
        case .schedule(let id):
            // A failed or paused recurring gift (Giving Cycle 4): its sheet —
            // why, and Resume / Change / Pause. Fresh from the server first.
            guard ceremony == nil else { return }
            Task {
                if !vm.schedules.contains(where: { $0.scheduleId == id }) { await vm.load() }
                guard ceremony == nil, let s = vm.schedules.first(where: { $0.scheduleId == id }),
                      s.status.lowercased() != "cancelled" else { return }
                scheduleDetail = s
            }
        }
    }

    /// A gift made on a pledge's page (Giving Cycle 9: "Collect it
    /// automatically at this pace") on this screen's own ceremony — the same
    /// one "give now" shows: its first prompt watched and settled from the
    /// server's record (Try again included), a prompt already on the phone
    /// watched instead, or — when today's prompt could not go out — the gift
    /// standing behind it, with the server's reason.
    private func show(_ watch: GiveWatch) {
        elsewhere = watch
        ceremonyFailure = nil
        setRetryTarget(nil, method: nil)
        promptPhone = nil
        // Described as the pledge's collection until the server's record of
        // the prompt arrives (settle reads it).
        waitingGift = WaitingGift(amountLabel: watch.amountLabel, destination: .pledge(watch.pledgeTitle), giftName: nil)
        let kind = ScheduleRhythm.isWeekly(watch.frequency) ? "weekly" : "monthly"
        switch watch.outcome {
        case .firstPrompt(let tx):
            pendingTxId = tx
            successRef = nil
            ceremonyNote = "Your \(kind) gift is set up — this is its first prompt."
            ceremony = "stk"
            startWatching(tx)
        case let .waiting(tx, message):
            Task { await watchWaitingPrompt(tx, message: message) }
        case let .scheduled(note, nextRunAt):
            scheduledNextAt = nextRunAt
            scheduledNote = [note, ScheduleRhythm.setUpLine(frequency: watch.frequency, firstPromptISO: nextRunAt)]
                .compactMap { $0 }.joined(separator: " ")
            ceremony = "scheduled"
        }
    }

    /// 409 GIFT_IN_PROGRESS: a prompt this member was sent a moment ago is
    /// still waiting on their phone, and a second would only fail as "busy".
    /// Rather than fail, the ceremony watches THAT transaction — the same
    /// polling as a fresh gift — and describes it from the server's record of
    /// it (amount, fund, pledge), since it may not be the gift on the form.
    private func watchWaitingPrompt(_ txId: String, message: String) async {
        pendingTxId = txId
        successRef = nil
        ceremonyNote = message
        waitingGift = .unknown
        let detail = try? await MemberAPI.givingDetail(txId)
        if let detail { waitingGift = WaitingGift(detail) }
        ceremony = "stk"
        // Already over by the time we asked? Show how it ended.
        if let detail, await settle(detail) { return }
        startWatching(txId)
    }

    /// Starts watching the gift on "Check your phone" — the stage's minute
    /// starts now (StkWatch). `resume` (a PayPal capture that came back after
    /// the watch ended) watches again without turning a late stage back.
    private func startWatching(_ txId: String, resume: Bool = false) {
        stkStartedAt = Date()
        if !resume { stkLate = false }
        pollTask?.cancel()
        pollTask = Task { await watchOutcome(txId) }
    }

    /// Polls the REAL transaction while the stage is on screen — every 3 s for
    /// the first minute, then every 10 s up to five (StkWatch, §7.2 #5), so an
    /// answer that comes late still lands. The ceremony only ever shows the
    /// server's status, never a fabricated one; past the minute it says it is
    /// still processing, and Done leads.
    private func watchOutcome(_ txId: String) async {
        let started = stkStartedAt
        while let delay = StkWatch.nextDelay(elapsed: Date().timeIntervalSince(started)) {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if Task.isCancelled || ceremony != "stk" { return }
            noteLateIfDue(since: started)
            guard let d = try? await MemberAPI.givingDetail(txId) else { continue }
            // The member may have closed the ceremony while that was in flight.
            if Task.isCancelled || ceremony != "stk" { return }
            if await settle(d) { return }
        }
        if ceremony == "stk" { noteLateIfDue(since: started) }
    }

    /// Past the minute: "Still processing — it will show in Recent giving
    /// once it clears." and Done as the primary. Once.
    private func noteLateIfDue(since started: Date) {
        guard !stkLate, StkWatch.isLate(elapsed: Date().timeIntervalSince(started)) else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            stkLate = true
            ceremonyNote = StkWatch.lateLine
        }
    }

    /// Applies the server's record of the watched gift to the ceremony: true
    /// once it is final (succeeded or failed), false while still processing.
    private func settle(_ d: GivingDetail) async -> Bool {
        if waitingGift != nil { waitingGift = WaitingGift(d) }
        switch d.status {
        case "succeeded", "settled", "completed":
            // Show the M-Pesa SMS receipt code when it's landed with the
            // settlement; fall back to a short transaction id, never ws_CO_.
            successRef = d.receiptCode ?? String(d.transactionId.prefix(8)).uppercased()
            ceremony = "success"
            Haptics.success()   // only on the server's confirmed outcome
            GivingSignal.post(from: vm)   // Partners: the pledge payment is in
            await vm.load()
            return true
        case "failed", "cancelled":
            // Why, in the server's words, when it says (Cycle 1) — the old
            // generic line only for a server that sends no reason.
            ceremonyFailure = d.failure.flatMap { $0.reason.isEmpty ? nil : $0 }
            ceremonyNote = ceremonyFailure == nil ? "The payment didn't complete — no charge was made." : ""
            // "Try again" retries THIS gift on the server (Cycle 3).
            setRetryTarget(d.transactionId, method: d.method)
            ceremony = "failed"
            Haptics.error()
            GivingSignal.post(from: vm)   // Partners: drop the Processing row
            return true
        default:
            // Still processing. For a PayPal gift the money only moves when WE
            // capture the approved order (§5.6) — nudge that along each tick;
            // the ceremony still keys off the polled status above.
            attemptPayPalCapture()
            return false
        }
    }

    /// POST /giving/paypal/capture for the pending order — fired on return to
    /// foreground and on poll ticks while still processing. One attempt in
    /// flight at a time; a terminal server answer ("succeeded" — which is also
    /// what an already-captured replay returns — or "failed") stops further
    /// attempts. Errors (member hasn't approved yet, transient network) are
    /// swallowed and simply retried on the next trigger. The success ceremony
    /// fires ONLY from the polled transaction status — never from here.
    private func attemptPayPalCapture() {
        guard let orderId = paypalOrderId, ceremony == "stk", paypalCaptureTask == nil else { return }
        paypalCaptureTask = Task {
            defer { paypalCaptureTask = nil }
            if let r = try? await MemberAPI.capturePayPal(orderId: orderId),
               r.status == "succeeded" || r.status == "failed" {
                paypalOrderId = nil   // settled either way — the poll reports the truth
                // If the watch already lapsed (long PayPal detour), restart it so
                // the ceremony can resolve from the server's status.
                if let tx = pendingTxId, ceremony == "stk" {
                    startWatching(tx, resume: true)
                }
            }
        }
    }

    private func endCeremony() {
        // One celebration per gift (§7.4 #14, §8.2 #17): the gift's own
        // success screen ("Thank you for your generosity · KSh 1,000 · Tithe ·
        // Ref …"). A second "Thank you for sowing · Amen 🙌" card used to fire
        // here on the way out and land later, on whatever tab came next.
        // Double-pay guard: a pledge / need payment that SUCCEEDED, or is
        // still PENDING ("stk" — the intent exists: STK prompt out, PayPal
        // approval, or the poll lapsed while processing), must not be payable
        // again with one more tap. However the ceremony is closed, the
        // binding goes now and the form returns to its normal state (fund
        // chooser, frequency, default amount) once the cover has gone. A
        // FAILED payment keeps the binding so the member can retry. A gift
        // made on a pledge's page (Giving Cycle 9) was not the form's: the
        // form is left as it was.
        if elsewhere == nil && (ceremony == "success" || ceremony == "stk") {
            if payMode { resetFormAfterCeremony = true }
            clearPayMode()
        }
        elsewhere = nil
        // The ceremony resolved: the next Pay is a new submission. A FAILED
        // ceremony leaves the key as the submit path set it — already fresh
        // if the server answered, kept only if it never did (so the retry
        // replays it and gets the transaction back if the request landed).
        if ceremony != "failed" { submissionKey = GiveKey.fresh() }
        // Closing stops only the watching — the gift itself is the server's
        // and goes on as it was (§7.2 #5); the reload below shows how it ends.
        pollTask?.cancel(); pollTask = nil
        paypalCaptureTask?.cancel(); paypalCaptureTask = nil
        paypalOrderId = nil
        ceremony = nil; ceremonyNote = ""
        stkLate = false
        // Closed: nothing is left to retry from here.
        retryTxId = nil; retryMethod = nil
        scheduledNextAt = ""
        scheduledNote = nil
        // intentFundName / intentPledgeTitle / intentIsPledge are NOT reset
        // here: the cover re-renders during its dismiss, and clearing them in
        // the same pass as pledgeId would flash the chip's fund over a pledge
        // payment's success line. Every submitIntent resets them first.
        Task { await vm.load() }
    }

    private func applyRepeat(_ g: GivingRecord) {
        if funds.contains(where: { $0.code == g.fund }) { fundCode = g.fund }
        // Only onto a rail that can take money here NOW (Cycle 1).
        if let m = g.method, vm.methods.isSelectable(m) { selectMethod(m) }
        if g.currency.uppercased() == "USD" {
            // A PayPal gift repeats in dollars — and only on PayPal; its cents
            // are never read as shillings (Giving Cycle 2).
            if vm.methods.currency(method) == "USD" { usdCents = g.amountMinor }
        } else if vm.methods.currency(method) == "KES" {
            // The gift itself, not the fee it covered (Cycle 2): the switch
            // below adds the fee again when it was covered last time.
            let fee = g.feeCoverMinor ?? 0
            amount = max(0, g.amountMinor - fee) / 100
            coverFee = fee > 0
        }
        accountName = g.accountName ?? ""
    }

    /// Selects a rail. One that cannot carry a schedule turns the gift back to
    /// one-time, so the hidden switch never comes back set to a rhythm.
    private func selectMethod(_ key: String) {
        method = key
        if !vm.methods.allowsRecurring(key) && freq != "once" { freq = "once" }
    }

    /// The server's rails arrived or changed: keep the member's order, move off
    /// a rail that can no longer be picked, and fill the prompt number.
    private func syncMethods(_ m: GivingMethods) {
        let order = GivingRails.mergedOrder(current: methodOrder, server: m.methods.map(\.key))
        if order != methodOrder { methodOrder = order }
        if let pick = m.selection(keeping: method, onlyCurrency: payRailsCurrency), pick != method {
            selectMethod(pick)
        } else if !m.allowsRecurring(method) && freq != "once" {
            freq = "once"
        }
        seedPhone()
    }

    /// Fills the prompt number while the member has not chosen one: the number
    /// they last gave from on this phone, else their profile number (Cycle 1).
    /// Never while the number sheet is open, never over a number they typed,
    /// and never a number that is not theirs.
    private func seedPhone() {
        guard !showMpesaSheet, mpesaPhone.isEmpty || mpesaPhone == seededPhone else { return }
        let remembered = phoneMemory.phone(for: auth.profile?.userId)
        guard let next = GivingPhoneMemory.initial(remembered: remembered, onFile: vm.methods.phoneOnFile),
              next != mpesaPhone else { return }
        mpesaPhone = next
        seededPhone = next
    }

    /// Reorder with a light tap and a spring, so rows glide instead of jumping.
    private func nudgeMethod(from index: Int, by delta: Int) {
        Haptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            moveMethod(from: index, by: delta)
        }
    }

    /// Moves a listed rail past its listed neighbour — rails not listed (they
    /// can't take this gift) keep their place in the saved order unseen.
    private func moveMethod(from index: Int, by delta: Int) {
        methodOrder = GivingRails.moved(methodOrder, listed: orderedMethods.map(\.key), from: index, by: delta)
    }

    // MARK: Helpers

    private func overline(_ s: String) -> some View {
        Text(s).font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
    }
}

// MARK: - Custom keypad sheet (staged value; confirm applies)

private let giftNamePresets = ["Tithe", "Offering", "Building", "Missions", "Thanksgiving", "First Fruits"]

private struct GiveKeypadSheet: View {
    /// The amount it opens on, in the rail's minor units.
    let initialMinor: Int
    /// "KES" — whole shillings; "USD" — dollars and cents, for PayPal
    /// (Giving Cycle 2).
    var currency: String = "KES"
    let fundLabel: String
    /// Last-used gift name (remembered across sessions) — preselects subtly
    /// without forcing a choice.
    var initialName: String = ""
    /// The chosen amount in minor units (shillings × 100, or US cents).
    var onConfirm: (Int, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""
    @State private var name = ""
    @FocusState private var nameFocused: Bool

    private var inDollars: Bool { currency.uppercased() == "USD" }
    /// The entry in minor units.
    private var minor: Int { inDollars ? UsdEntry.cents(value) : (Int(value) ?? 0) * 100 }
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var presetMinors: [Int] { inDollars ? UsdEntry.presetsCents : presets.map { $0 * 100 } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.base) {
                HStack {
                    Text("CUSTOM AMOUNT · \(fundLabel.uppercased())")
                        .font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                    Spacer()
                    Button { dismiss() } label: { Icon(.x, size: 18, color: Nuru.navy) }.buttonStyle(.plain)
                }
                .padding(.top, Nuru.S.lg)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(inDollars ? "US$" : "KSh").font(.inter(13, .medium)).foregroundStyle(Color(hex: 0x74808F))
                    Text(inDollars ? (value.isEmpty ? "0" : value) : (minor / 100).formatted(.number.grouping(.automatic)))
                        .font(.fraunces(28, .semibold)).kerning(-1.1).foregroundStyle(Nuru.navy)
                }
                .frame(maxWidth: .infinity)
                if inDollars {
                    Text("PayPal gifts are in US dollars")
                        .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x0070BA))
                }

                // The same pills as the form (§8.1 rule 6) — the typed amount,
                // when it is one of them, is the chosen one.
                NuruAmountPills(amounts: presetMinors, selected: minor,
                                label: { ($0 / 100).formatted(.number.grouping(.automatic)) }) { v in
                    value = inDollars ? UsdEntry.text(v) : String(v / 100)
                }

                keys

                nameSection

                Button {
                    Haptics.action()
                    nameFocused = false
                    onConfirm(minor, trimmedName.isEmpty ? nil : trimmedName); dismiss()
                } label: {
                    // It sets the amount and closes; the gift itself is the
                    // form's "Give KSh X" — one way to give, and the last tap
                    // before money moves names the money (§7.1 rule 7; §9.6
                    // #3). Android's words.
                    Text("Set amount")
                        .font(.inter(15, .bold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(minor <= 0)
                .opacity(minor <= 0 ? 0.4 : 1)
            }
            .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.lg)
        }
        .onAppear {
            value = inDollars ? UsdEntry.text(initialMinor) : (initialMinor > 0 ? String(initialMinor / 100) : "")
            name = initialName
        }
        .presentationDetents([.height(720)])
        .presentationDragIndicator(.visible)
    }

    // MARK: Name your gift (optional) — like an M-Pesa Paybill account name

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME YOUR GIFT (OPTIONAL)")
                .font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))

            FlowWrap(spacing: 6) {
                ForEach(giftNamePresets, id: \.self) { p in
                    let on = name == p
                    Button {
                        Haptics.selection()
                        name = on ? "" : p
                    } label: {
                        // Chips: chosen navy, the rest white with a hairline (§8.1 rule 6).
                        Text(p)
                            .font(.inter(12, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
                            .padding(.horizontal, 11).frame(height: 32)
                            .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }

            HStack(spacing: Nuru.S.sm) {
                Icon(.pencil, size: 14, color: Color(hex: 0x74808F))
                TextField("e.g. \u{201C}For Mom\u{2019}s healing\u{201D}", text: $name)
                    .focused($nameFocused)
                    .font(.inter(13, .medium)).foregroundStyle(Nuru.navy)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 14).frame(height: 46)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))

            Text("Shows on the church's M-Pesa statement — like a Paybill account name.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
        }
        .padding(.top, 2)
    }

    private var keys: some View {
        // Dollars take cents: the "00" key becomes the decimal point.
        let all = ["1", "2", "3", "4", "5", "6", "7", "8", "9", inDollars ? "." : "00", "0", "del"]
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(all, id: \.self) { k in
                Button { press(k) } label: {
                    Group {
                        if k == "del" {
                            Image(systemName: "delete.left")
                                .font(.symbol(19)).foregroundStyle(Color(hex: 0x5B6472))
                        } else {
                            Text(k).font(.inter(18, .semibold)).foregroundStyle(Nuru.navy)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 54)
                    .background(k == "del" ? Color.clear : Nuru.surface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(k == "del" ? Color.clear : Nuru.border, lineWidth: 1))
                    .contentShape(Rectangle())
                }.buttonStyle(.pressable)
            }
        }
    }

    private func press(_ k: String) {
        Haptics.tap()
        if inDollars { value = UsdEntry.press(k, on: value); return }
        switch k {
        case "del":
            value = String(value.dropLast())
        case "00":
            if !value.isEmpty && value != "0" { value = String((value + "00").prefix(7)) }
        default:
            if value == "0" { value = k } else { value = String((value + k).prefix(7)) }
        }
    }
}

// MARK: - Mobile-money number sheet (M-Pesa / Airtel)

/// Confirms the number the prompt goes to (Giving Cycle 1). It opens on the
/// member's own number when Give has one — the one they last gave from, else
/// their profile's — or empty, and sends nothing until the field holds a
/// Kenyan mobile number. Hands the number back as E.164.
private struct MobileMoneySheet: View {
    let methodKey: String            // mpesa | airtel
    @Binding var phone: String
    /// The profile's number (the server's `phone_on_file`) — offered as a
    /// one-tap choice only when the field holds a different one.
    let phoneOnFile: String?
    /// "weekly" | "monthly" when this confirms a schedule (every cycle
    /// prompts this number); nil for a one-time gift.
    var frequency: String? = nil
    /// The gift, as the form says it ("KSh 1,000") — the start-now line's.
    var amountLabel: String = ""
    /// The number (E.164), and — for a schedule — whether to start with a
    /// gift now (Giving Cycle 4).
    var onSubmit: (String, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    /// "Start with a gift now" (Giving Cycle 4) — on by default: the first
    /// prompt goes out now, while the member is holding the phone.
    @State private var giveNow = true
    /// What the sheet says, measured — the sheet is exactly that tall
    /// (EXPERIENCE.md §8.2 #11). A fixed 430pt left its lower half empty.
    @State private var contentHeight: CGFloat = 360

    private var isMpesa: Bool { methodKey != "airtel" }
    private var railName: String { isMpesa ? "M-Pesa" : "Airtel Money" }
    private var tint: Color { Nuru.navy }   // the rail is named, not coloured (§8.1 rule 1)
    private var check: KenyanPhone.Check { KenyanPhone.check(phone) }
    /// The number as E.164 — nil until the field holds a valid one.
    private var number: String? { KenyanPhone.normalize(phone) }
    private var numberOnFile: String? {
        guard let f = phoneOnFile.flatMap(KenyanPhone.normalize), f != number else { return nil }
        return f
    }
    private var cadenceWord: String? { frequency.map { ScheduleRhythm.isWeekly($0) ? "week" : "month" } }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text(isMpesa ? "M-PESA NUMBER" : "AIRTEL MONEY NUMBER")
                    .font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                Spacer()
                Button { dismiss() } label: { Icon(.x, size: 18, color: Nuru.navy) }.buttonStyle(.plain)
            }
            .padding(.top, Nuru.S.lg)

            Text(cadenceWord.map { "Every \($0), we'll send the \(railName) prompt to this number — enter your PIN there to give." }
                 ?? "We'll send the \(railName) prompt to this number — enter your PIN there to give.")
                .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Nuru.S.sm) {
                    Icon(.smartphone, size: 18, color: tint)
                    TextField("07XX XXX XXX", text: $phone)
                        .keyboardType(.phonePad)
                        .font(.inter(15, .semibold)).foregroundStyle(Nuru.navy)
                }
                .padding(.horizontal, 14).frame(height: 52)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(check == .invalid ? Color(hex: 0xF0B4B4) : Nuru.border, lineWidth: 1))

                // Why it cannot be sent yet — the server's own words for a
                // number it would refuse (422 PHONE_REQUIRED).
                if check == .invalid {
                    Text(KenyanPhone.invalidMessage)
                        .font(.inter(11)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                } else if check == .empty {
                    Text("Add the \(railName) number to prompt for this gift.")
                        .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
                }
            }

            if let onFile = numberOnFile {
                Button { phone = KenyanPhone.display(onFile) } label: {
                    HStack(spacing: 5) {
                        Icon(.repeat, size: 14, color: Nuru.goldLo)
                        Text("Use my number (\(KenyanPhone.display(onFile)))")
                            .font(.inter(12, .semibold)).foregroundStyle(Nuru.goldLo)
                    }
                }.buttonStyle(.plain)
            }

            if let frequency { startNowRow(frequency) }

            Button {
                guard let number else { return }
                Haptics.action()
                dismiss(); onSubmit(number, frequency != nil && giveNow)
            } label: {
                // The last tap before money moves names the money (§7.2 #6):
                // "Give KSh 1,000"; a recurring start keeps "Start Monthly Gift".
                Text(GiveButton.mobileMoneyLabel(amountLabel: amountLabel, frequency: frequency))
                    .font(.inter(15, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(number == nil)
            .opacity(number == nil ? 0.4 : 1)

            HStack(spacing: 5) {
                Icon(.lock, size: 14, color: Color(hex: 0x74808F))
                Text(cadenceWord == nil ? "Number used only for this transaction prompt"
                                        : "Number used only for this gift's prompts")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.lg)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { g in
            Color.clear
                .onAppear { contentHeight = g.size.height }
                .onChange(of: g.size.height) { _, h in contentHeight = h }
        })
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(contentHeight)])
        .presentationDragIndicator(.visible)
        // One phone format (§8.1 rule 8, Cycle 1): the field reads the number
        // as a Kenyan reads it — "0700 000 000", never "+254700000000". The
        // prompt still goes out as E.164 (normalized on the way out).
        .onAppear { if let n = KenyanPhone.normalize(phone) { phone = KenyanPhone.display(n) } }
    }

    /// "Start with a gift now" (Giving Cycle 4): on — "KSh 1,000 now, then
    /// every Sunday"; off — "Nothing is taken today — the first prompt comes
    /// on 5 Oct 2026." Both are exactly what the server will do.
    private func startNowRow(_ frequency: String) -> some View {
        Toggle(isOn: $giveNow) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start with a gift now").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Text(giveNow ? ScheduleRhythm.startNowLine(amountLabel: amountLabel, frequency: frequency, now: Date())
                             : ScheduleRhythm.nothingTodayLine(frequency: frequency, now: Date()))
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Nuru.gold)
        .padding(12)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .onChange(of: giveNow) { _, _ in Haptics.tap() }
    }
}

// MARK: - Schedule sheet (Giving Cycle 4: change, pause, resume, heads-up, cancel)

/// One recurring gift, and what the member can do with it (Giving Cycle 4):
/// change its amount, day or number (PATCH), pause it until they resume or
/// until a date, resume it, switch the heads-up off, or cancel it. Why a
/// paused gift is paused is said first. Every action is the server's to
/// accept, and its words are shown when it refuses.
private struct ScheduleDetailSheet: View {
    /// The rail's limits (M-Pesa) for a changed amount; nil = not checked here.
    let rail: GivingMethod?
    /// The profile's number — offered as "Use my profile number".
    let phoneOnFile: String?
    /// It collects a MONTHLY pledge (Giving Cycle 5): its amount and day are
    /// the pledge's, changed there — not here.
    var followsMonthlyPledge: Bool = false
    /// Opens the pledge (the Partners segment) — "Change it on the pledge".
    var onOpenPledge: (String) -> Void = { _ in }
    var onClose: () -> Void
    /// Changed in place (amount, day, number, heads-up): the list reloads,
    /// the sheet stays with the server's answer.
    var onUpdated: () -> Void
    /// Cancelled, paused or resumed: the sheet closes and the list reloads.
    var onChanged: () -> Void

    private enum Mode { case view, change, pause, confirmCancel }

    @State private var current: GivingSchedule
    @State private var mode: Mode = .view
    @State private var draft: ScheduleDraft
    @State private var pauseUntilDate = false
    @State private var resumeDate: Date
    @State private var headsUp: Bool
    @State private var busy = false
    @State private var errorText: String?
    /// A refused change named the pledge that owns it (details.pledge_id).
    @State private var errorPledgeId: String?

    init(schedule: GivingSchedule, rail: GivingMethod?, phoneOnFile: String?,
         followsMonthlyPledge: Bool = false, onOpenPledge: @escaping (String) -> Void = { _ in },
         onClose: @escaping () -> Void, onUpdated: @escaping () -> Void, onChanged: @escaping () -> Void) {
        self.rail = rail
        self.phoneOnFile = phoneOnFile
        self.followsMonthlyPledge = followsMonthlyPledge
        self.onOpenPledge = onOpenPledge
        self.onClose = onClose
        self.onUpdated = onUpdated
        self.onChanged = onChanged
        _current = State(initialValue: schedule)
        _draft = State(initialValue: ScheduleEdit.draft(of: schedule))
        _resumeDate = State(initialValue: PauseDates.range(now: Date()).lowerBound)
        _headsUp = State(initialValue: schedule.headsUp)
    }

    private var weekly: Bool { ScheduleRhythm.isWeekly(current.frequency) }
    private var paused: Bool { current.status.lowercased() == "paused" }
    private var freqLabel: String { weekly ? "Every week" : "Every month" }
    private var plan: ScheduleEdit.Plan { ScheduleEdit.plan(draft, for: current, rail: rail) }
    private var profileNumber: String? { phoneOnFile.flatMap(KenyanPhone.normalize) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                summary.padding(.top, Nuru.S.base)

                // Why it is paused, first (and Resume, when it is ours to resume).
                if let why = PauseCopy.line(for: current) {
                    pausedBox(why).padding(.top, Nuru.S.md)
                }
                // Why the last charge failed, while it is still failing — the
                // server's own words, reason then what to do.
                if let f = current.lastFailure, !f.reason.isEmpty {
                    failureBox(f).padding(.top, Nuru.S.md)
                }

                switch mode {
                case .view:
                    detailRows.padding(.top, Nuru.S.md)
                    // "Tell me before each prompt" is a push a few minutes before
                    // M-Pesa asks for the PIN — this phone can't receive one yet,
                    // and an inbox notice comes too late to help, so iOS doesn't
                    // offer it (the walk's B11; §2: promise only what works).
                    actionButtons.padding(.top, Nuru.S.base)
                case .change:
                    changeForm.padding(.top, Nuru.S.base)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .pause:
                    pauseForm.padding(.top, Nuru.S.base)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                case .confirmCancel:
                    detailRows.padding(.top, Nuru.S.md)
                    confirmBox.padding(.top, Nuru.S.base)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                if let e = errorText {
                    Text(e).font(.inter(12)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Nuru.S.sm)
                    if let id = errorPledgeId {
                        outlineButton("Change it on the pledge") { onOpenPledge(id) }
                            .padding(.top, Nuru.S.sm)
                    }
                }
            }
            .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.xl)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: mode)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Header + summary

    private var header: some View {
        HStack {
            Text("Recurring gift")
                .font(.fraunces(18, .semibold)).kerning(-0.36).foregroundStyle(Nuru.navy)
            if paused {
                Text("Paused").font(.nMicro).foregroundStyle(Nuru.ink600)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Nuru.mutedBg, in: Capsule())
            }
            Spacer()
            Button { onClose() } label: {
                ZStack {
                    Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                    Icon(.x, size: 14, color: Nuru.navy)
                }
            }.buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.top, Nuru.S.lg)
    }

    private var summary: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Nuru.gold.opacity(0.1)).frame(width: 44, height: 44)
                Icon(.repeat, size: 18, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(money(current.amountMinor, current.currency)).font(.inter(18, .bold)).foregroundStyle(Nuru.navy)
                Text("\(dayLine) · \(current.fund.capitalized)")
                    .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                // Giving Cycle 5: a gift that collects a pledge asks only what
                // the pledge still owes.
                ForEach([ScheduleCopy.pledgeLine(current), ScheduleCopy.nextLine(current)].compactMap { $0 }, id: \.self) { line in
                    Text(line).font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// "Every Sunday" · "Every month on the 31st".
    private var dayLine: String {
        guard let day = ScheduleRhythm.day(of: current) else { return freqLabel }
        let text = ScheduleRhythm.cadence(frequency: current.frequency, day: day)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    // MARK: Paused / failing

    private func pausedBox(_ why: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Icon(.pause, size: 14, color: Nuru.ink600)
                Text(why).font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            // A gift that follows its pledge comes back with the pledge — no
            // Resume here (the server would refuse).
            if PauseCopy.canResume(current) {
                Button { resume() } label: {
                    ZStack {
                        if busy { ProgressView().tint(.white) }
                        else { Text("Resume").font(.inter(13, .bold)).foregroundStyle(.white) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Nuru.navy, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain).disabled(busy)
                Text("Resuming never collects a missed gift.")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.mutedBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func failureBox(_ f: GiftFailure) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.symbol(13, weight: .semibold))
                .foregroundStyle(Nuru.urgentText)
            VStack(alignment: .leading, spacing: 3) {
                Text(f.reason).font(.inter(12, .semibold)).foregroundStyle(Nuru.urgentText)
                if !f.hint.isEmpty {
                    Text(f.hint).font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.urgentBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Details

    private var detailRows: some View {
        VStack(spacing: 0) {
            row("Fund", current.fund.capitalized)
            Divider().overlay(Nuru.border)
            row("Amount", money(current.amountMinor, current.currency))
            Divider().overlay(Nuru.border)
            row("When", dayLine)
            Divider().overlay(Nuru.border)
            // A paused gift charges nothing — its old date is not a promise.
            if paused {
                row("Next prompt", "None while paused")
            } else {
                row("Next prompt", giveParseDate(current.nextRunAt).map { ScheduleRhythm.format($0, "EEE d MMM yyyy") } ?? "Not set")
            }
            Divider().overlay(Nuru.border)
            row("Method", givingMethodName(current.method))
            Divider().overlay(Nuru.border)
            // Its own number, else the profile's (followed if it changes).
            row("Prompts", current.phoneNumber.map(KenyanPhone.display) ?? "Your profile number")
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
            Spacer()
            Text(value).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    /// "Tell me before each prompt" — a push a few minutes before M-Pesa asks
    /// for the PIN, so the prompt is expected, not mistaken for a scam. Not
    /// offered on iOS until it has remote push (B11); kept for that day.
    private var headsUpRow: some View {
        Toggle(isOn: Binding(get: { headsUp }, set: { on in headsUp = on; setHeadsUp(on) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Tell me before each prompt").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Text("A notification a few minutes before M-Pesa asks for your PIN.")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(Nuru.gold)
        .disabled(busy)
        .padding(12)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private var actionButtons: some View {
        VStack(spacing: Nuru.S.sm) {
            HStack(spacing: Nuru.S.sm) {
                outlineButton("Change") {
                    draft = ScheduleEdit.draft(of: current)
                    errorText = nil
                    mode = .change
                }
                // Pausing is for a running gift; a paused one resumes above.
                if !paused {
                    outlineButton("Pause") {
                        pauseUntilDate = false
                        resumeDate = PauseDates.range(now: Date()).lowerBound
                        errorText = nil
                        mode = .pause
                    }
                }
            }
            Button {
                Haptics.tap()
                errorText = nil
                mode = .confirmCancel
            } label: {
                Text("Cancel schedule")
                    .font(.inter(13, .bold)).foregroundStyle(Color(hex: 0xDC2626))
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Color(hex: 0xFEF2F2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color(hex: 0xFECACA), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    private func outlineButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Text(title)
                .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.navy.opacity(0.35), lineWidth: 1.2))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    // MARK: Change (amount · day · number)

    private var changeForm: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Text("CHANGE THIS GIFT")
                .font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))

            if followsMonthlyPledge, let pledge = current.pledge {
                // Its amount and day are the pledge's (Giving Cycle 5).
                Text("The amount and day come from your pledge \u{201C}\(pledge.title)\u{201D} — change them there and this gift follows.")
                    .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                    .fixedSize(horizontal: false, vertical: true)
                outlineButton("Change it on the pledge") { onOpenPledge(pledge.pledgeId) }
            } else {
                amountAndDayFields
            }

            numberFields

            if let problem = plan.problem {
                Text(problem).font(.inter(11)).foregroundStyle(Nuru.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Nuru.S.sm) {
                outlineButton("Back") { errorText = nil; errorPledgeId = nil; mode = .view }
                Button { save() } label: {
                    ZStack {
                        if busy { ProgressView().tint(Nuru.navy) }
                        else { Text("Save changes").font(.inter(13, .bold)).foregroundStyle(Nuru.navy) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy || plan.patch == nil)
                .opacity(plan.patch == nil ? 0.5 : 1)
            }
            .padding(.top, 2)
        }
    }

    /// Amount — whole shillings, inside M-Pesa's limits — and the day.
    @ViewBuilder private var amountAndDayFields: some View {
        // Amount — whole shillings, inside M-Pesa's limits.
        fieldLabel("Amount")
        HStack(spacing: Nuru.S.sm) {
            Text("KSh").font(.inter(14, .medium)).foregroundStyle(Color(hex: 0x74808F))
            TextField("1,000", text: $draft.amountText)
                .keyboardType(.numberPad)
                .font(.inter(15, .semibold)).foregroundStyle(Nuru.navy)
        }
        .padding(.horizontal, 14).frame(height: 48)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))

        // Day — the next prompt moves there.
        fieldLabel(weekly ? "Day of the week" : "Day of the month")
        if weekly {
            FlowWrap(spacing: 6) {
                ForEach(0..<7, id: \.self) { d in
                    let on = draft.day == d
                    Button {
                        Haptics.selection()
                        draft.day = d
                    } label: {
                        Text(String(ScheduleRhythm.weekdays[d].prefix(3)))
                            .font(.inter(12, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
                            .padding(.horizontal, 12).frame(height: 34)
                            .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        } else {
            Menu {
                ForEach(1...31, id: \.self) { d in
                    Button("On the \(ScheduleRhythm.ordinal(d))") { draft.day = d }
                }
            } label: {
                HStack {
                    Text("On the \(ScheduleRhythm.ordinal(draft.day))")
                        .font(.inter(15, .semibold)).foregroundStyle(Nuru.navy)
                    Spacer()
                    Icon(.chevronDown, size: 14, color: Nuru.ink600)
                }
                .padding(.horizontal, 14).frame(height: 48)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            if draft.day >= 29 {
                Text("In a shorter month, the prompt comes on its last day.")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
            }
        }
    }

    /// Number — its own, or back to the profile's.
    @ViewBuilder private var numberFields: some View {
        // Number — its own, or back to the profile's.
        fieldLabel("M-Pesa number")
        if !draft.useProfileNumber {
            HStack(spacing: Nuru.S.sm) {
                Icon(.smartphone, size: 18, color: Nuru.navy)
                TextField("07XX XXX XXX", text: $draft.phoneText)
                    .keyboardType(.phonePad)
                    .font(.inter(15, .semibold)).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 14).frame(height: 48)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        if let profile = profileNumber {
            Button {
                Haptics.selection()
                draft.useProfileNumber.toggle()
                if !draft.useProfileNumber && draft.phoneText.isEmpty { draft.phoneText = profile }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: draft.useProfileNumber ? "checkmark.circle.fill" : "circle")
                        .font(.symbol(16)).foregroundStyle(draft.useProfileNumber ? Nuru.gold : Nuru.ink300)
                    Text("Use my profile number (\(profile))")
                        .font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                }
            }.buttonStyle(.plain)
        }
    }

    private func fieldLabel(_ s: String) -> some View {
        Text(s).font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x5B6472))
    }

    // MARK: Pause (until I resume · until a date)

    private var pauseForm: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Text("PAUSE THIS GIFT")
                .font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
            Text("Nothing is prompted while it's paused, and nothing is owed.")
                .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                .fixedSize(horizontal: false, vertical: true)
            pauseOption("Until I resume", on: !pauseUntilDate) { pauseUntilDate = false }
            pauseOption("Until a date", on: pauseUntilDate) { pauseUntilDate = true }
            if pauseUntilDate {
                // Tomorrow to a year from today, on the church's calendar.
                DatePicker("Resume on", selection: $resumeDate, in: PauseDates.range(now: Date()),
                           displayedComponents: .date)
                    .environment(\.timeZone, GiveCalendar.nairobi)
                    .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                    .tint(Nuru.gold)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Text("It comes back on its own at its next day on or after \(ScheduleRhythm.format(resumeDate, "d MMM yyyy")).")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: Nuru.S.sm) {
                outlineButton("Back") { errorText = nil; mode = .view }
                Button { pause() } label: {
                    ZStack {
                        if busy { ProgressView().tint(.white) }
                        else { Text("Pause gift").font(.inter(13, .bold)).foregroundStyle(.white) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Nuru.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain).disabled(busy)
            }
            .padding(.top, 2)
        }
    }

    private func pauseOption(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .font(.symbol(17)).foregroundStyle(on ? Nuru.gold : Nuru.ink300)
                Text(title).font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Spacer()
            }
            .padding(.horizontal, 12).frame(height: 44)
            .background(on ? Nuru.priorityBg : Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 1.5 : 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Cancel (confirmed)

    private var confirmBox: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cancel this recurring gift?")
                .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0xB91C1C))
            Text("Future prompts stop. Gifts already given are not affected — to change the amount or day, use Change instead.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Nuru.S.sm) {
                Button { mode = .view } label: {
                    Text("Keep it")
                        .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }.buttonStyle(.plain)
                Button { cancelNow() } label: {
                    ZStack {
                        if busy { ProgressView().tint(.white) }
                        else { Text("Cancel schedule").font(.inter(13, .bold)).foregroundStyle(.white) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Color(hex: 0xDC2626), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }.buttonStyle(.plain).disabled(busy)
            }
            .padding(.top, Nuru.S.sm)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xFEF2F2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0xFECACA), lineWidth: 1))
    }

    // MARK: Actions — each one the server's to accept

    /// PATCH only what changed; the sheet then shows the server's row.
    private func save() {
        guard !busy, let patch = plan.patch else { return }
        busy = true; errorText = nil; errorPledgeId = nil
        Task { @MainActor in
            do {
                let updated = try await MemberAPI.updateSchedule(current.scheduleId, patch)
                // A bare answer (no amount) keeps what is here; the reload fixes it.
                if updated.amountMinor > 0 { current = updated }
                draft = ScheduleEdit.draft(of: current)
                headsUp = current.headsUp
                mode = .view
                Haptics.success()   // the server accepted the change
                onUpdated()
            } catch {
                // The server's words — SCHEDULE_EXISTS, AMOUNT_OUT_OF_RANGE,
                // PHONE_REQUIRED, and (Giving Cycle 5) a monthly pledge's
                // collector whose amount / day are the pledge's.
                errorText = GiveRefusal.from(error).message
                if case let .http(_, _, _, details)? = error as? APIError { errorPledgeId = details?.pledgeId }
                Haptics.error()
            }
            busy = false
        }
    }

    /// The heads-up switch, saved as soon as it is flipped (reverted if the
    /// server says no).
    private func setHeadsUp(_ on: Bool) {
        guard on != current.headsUp, !busy else { return }
        busy = true; errorText = nil
        Task { @MainActor in
            do {
                let updated = try await MemberAPI.updateSchedule(current.scheduleId, SchedulePatch(headsUp: on))
                // The server's row when it sent one; else what it accepted.
                if updated.amountMinor > 0 { current = updated } else { current.headsUp = on }
                headsUp = current.headsUp
                onUpdated()
            } catch {
                headsUp = current.headsUp
                errorText = GiveRefusal.from(error).message
                Haptics.error()
            }
            busy = false
        }
    }

    /// POST …/pause — until resumed, or until the chosen (Nairobi) date.
    private func pause() {
        guard !busy else { return }
        if pauseUntilDate && !PauseDates.isAllowed(resumeDate, now: Date()) {
            errorText = "Choose a date from tomorrow to a year from now."
            return
        }
        busy = true; errorText = nil
        let resumeOn = pauseUntilDate ? PauseDates.wire(resumeDate) : nil
        Task { @MainActor in
            do {
                try await MemberAPI.pauseSchedule(current.scheduleId, resumeOn: resumeOn)
                Haptics.success()   // the server paused it
                onChanged()
            } catch {
                errorText = GiveRefusal.from(error).message
                busy = false
                Haptics.error()
            }
        }
    }

    /// POST …/resume — the same action as the Partners tab's Resume. It never
    /// collects the cycle that was missed.
    private func resume() {
        guard !busy else { return }
        busy = true; errorText = nil
        Task { @MainActor in
            do {
                try await MemberAPI.resumeSchedule(current.scheduleId)
                Haptics.success()   // server confirmed the resume
                onChanged()
            } catch {
                errorText = GiveRefusal.from(error).message
                busy = false
                Haptics.error()
            }
        }
    }

    private func cancelNow() {
        guard !busy else { return }
        busy = true; errorText = nil
        Task { @MainActor in
            do {
                try await MemberAPI.cancelSchedule(current.scheduleId)
                Haptics.success()   // server confirmed the cancellation
                onChanged()
            } catch {
                errorText = GiveRefusal.from(error).message
                busy = false
                Haptics.error()
            }
        }
    }
}

// MARK: - Ceremony (full-screen; only ever shows the server's real status)

/// Where a gift goes, as the ceremony says it. `.fund` is the server's fund
/// name (the chip's label only as a last resort); `.pledge` carries the
/// pledge's title, nil when the server named none.
private enum GiveDestination {
    case fund(String)
    case pledge(String?)

    /// "to Tithe" · "toward your Building fund pledge" · "toward your pledge".
    /// A title that already ends in "pledge" is not doubled.
    var phrase: String {
        switch self {
        case .fund(let name): return "to \(name)"
        case .pledge(let title):
            guard let title, !title.isEmpty else { return "toward your pledge" }
            return title.lowercased().hasSuffix("pledge") ? "toward your \(title)" : "toward your \(title) pledge"
        }
    }
}

/// A prompt the server said was ALREADY waiting on the member's phone (409
/// GIFT_IN_PROGRESS), described from the server's record of that gift — it
/// may not be the one on the form. Until the record is read the amount is
/// unknown (""), and the STK stage says only that a prompt is waiting.
private struct WaitingGift {
    var amountLabel: String
    var destination: GiveDestination?
    var giftName: String?

    static let unknown = WaitingGift(amountLabel: "", destination: nil, giftName: nil)

    init(amountLabel: String, destination: GiveDestination?, giftName: String?) {
        self.amountLabel = amountLabel; self.destination = destination; self.giftName = giftName
    }

    init(_ d: GivingDetail) {
        amountLabel = money(d.amountMinor, d.currency)
        if let p = d.pledge {
            destination = .pledge(p.title.isEmpty ? nil : p.title)
        } else if let n = d.need, !n.title.isEmpty {
            destination = .fund(n.title)
        } else {
            let name = (d.fundName ?? "").trimmingCharacters(in: .whitespaces)
            destination = .fund(name.isEmpty ? (d.fund.isEmpty ? "General" : d.fund.capitalized) : name)
        }
        giftName = d.accountName.flatMap { $0.isEmpty ? nil : $0 }
    }
}

private struct GiveCeremonyView: View {
    let stage: String                // stk | success | failed | scheduled
    let note: String
    /// Why a polled gift failed, in the server's words (Cycle 1) — the
    /// failed stage shows it in place of the generic note.
    var failure: GiftFailure? = nil
    let amountLabel: String
    /// The chip's label — the scheduled stage's only source (schedules do
    /// not go through an intent, so there is no server answer to read).
    let fundLabel: String
    /// The intent RESULT's answer for the STK + success stages.
    let destination: GiveDestination
    /// "Named giving" (custom sheet, optional): the member's own label for
    /// this gift — shown alongside the fund wherever it currently shows.
    var giftName: String? = nil
    let phone: String?
    let refCode: String?
    let txId: String?
    let cadenceWord: String
    let nextChargeLabel: String?
    /// The scheduled stage's word when today's first prompt could not go out.
    var scheduledNote: String? = nil
    /// The scheduled stage's line when nothing was asked of today.
    var nothingTodayLine: String? = nil
    /// A retry of the failed gift is on its way (Try again spins).
    var retrying: Bool = false
    /// "Check your phone" has passed its minute (StkWatch): Done leads.
    var stkLate: Bool = false
    var onDone: () -> Void
    var onRetry: () -> Void
    @State private var showReceipt = false

    var body: some View {
        ZStack {
            (stage == "stk" ? Nuru.navy : Nuru.paper).ignoresSafeArea()
            switch stage {
            case "stk":
                StkStage(amountLabel: amountLabel, destination: destination, giftName: giftName, phone: phone, note: note,
                         late: stkLate, onClose: onDone)
            case "success":
                SuccessStage(amountLabel: amountLabel, destination: destination, giftName: giftName, refCode: refCode,
                             hasReceipt: txId != nil,
                             onViewReceipt: { showReceipt = true }, onDone: onDone)
            case "scheduled":
                ScheduledStage(amountLabel: amountLabel, fundLabel: fundLabel,
                               cadenceWord: cadenceWord, nextChargeLabel: nextChargeLabel,
                               note: scheduledNote, nothingTodayLine: nothingTodayLine, onDone: onDone)
            default:
                FailedStage(note: note, failure: failure,
                            giftLine: amountLabel.isEmpty ? nil : "\(amountLabel) \(destination.phrase)",
                            busy: retrying, onRetry: onRetry, onDone: onDone)
            }
        }
        .sheet(isPresented: $showReceipt) {
            // A stack of its own so the receipt's "View statement" can push
            // the statement; the receipt draws its own header (no nav bar).
            // The statement it reaches pushes its gift rows as GivingRecord
            // values, so this stack must know them (the Partners statement
            // link registers itself on the statement page).
            if let txId {
                NavigationStack {
                    GivingReceiptView(transactionId: txId)
                        .navigationDestination(for: GivingRecord.self) { GivingReceiptView(transactionId: $0.transactionId) }
                }
            }
        }
    }
}

/// "Check your phone" (EXPERIENCE.md §7.2 #5, §7.1 rule 3): a quiet Close from
/// the start — it used to have no button at all, and a prompt answered late
/// trapped the member on this navy screen. Past the minute the line says it is
/// still processing and Done leads; either way the watch keeps going while
/// the stage is on screen, and closing leaves the gift as it is.
private struct StkStage: View {
    let amountLabel: String
    let destination: GiveDestination
    var giftName: String? = nil
    let phone: String?
    let note: String
    /// Past the minute (StkWatch): "Still processing…", Done as the primary.
    var late: Bool = false
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.15)).frame(width: 80, height: 80)
                ProgressView().tint(Nuru.gold).scaleEffect(1.5)
            }
            Text("Check your phone")
                .font(.fraunces(22, .medium)).kerning(-0.44).foregroundStyle(.white)
                .padding(.top, Nuru.S.lg)
            // "Enter your PIN to complete KSh 1,000 toward your Building fund
            // pledge." / "… to Tithe." — the server's answer, never the chip's.
            // No amount = a waiting prompt whose record is not read yet: say
            // only what is known.
            Group {
                if amountLabel.isEmpty {
                    Text("Enter your PIN on the prompt that's waiting on your phone.")
                } else {
                    Text("Enter your PIN to complete ")
                        + Text(amountLabel).foregroundColor(Nuru.gold).fontWeight(.semibold)
                        + Text(" \(destination.phrase)\(giftName.map { " \u{2014} \u{201C}\($0)\u{201D}" } ?? "").")
                }
            }
            .font(.inter(13)).foregroundColor(.white.opacity(0.7))
            .multilineTextAlignment(.center)
            .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
            if !note.isEmpty {
                Text(note).font(.inter(12)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
            }
            if let phone {
                HStack(spacing: 6) {
                    Icon(.smartphone, size: 14, color: Nuru.gold)
                    Text("Prompt sent to \(KenyanPhone.display(phone))").font(.inter(11)).foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
                .padding(.top, Nuru.S.md)
            }
            // True only for the prompt's first minute — gone once it isn't.
            if !late {
                HStack(spacing: 6) {
                    ProgressView().tint(.white.opacity(0.5)).scaleEffect(0.7)
                    Text("Waiting up to 60s…").font(.inter(11)).foregroundStyle(.white.opacity(0.5))
                }
                .padding(.top, Nuru.S.lg)
                .transition(.opacity)
            }
            Spacer()
            Group {
                if late {
                    Button(action: onClose) {
                        Text("Done")
                            .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: onClose) {
                        Text("Close")
                            .font(.inter(14, .semibold)).foregroundStyle(.white.opacity(0.7))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Nuru.S.xl).padding(.bottom, Nuru.S.xl)
            .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.25), value: late)
    }
}

private struct SuccessStage: View {
    let amountLabel: String
    let destination: GiveDestination
    var giftName: String? = nil
    let refCode: String?
    let hasReceipt: Bool
    var onViewReceipt: () -> Void
    var onDone: () -> Void

    /// "Tithe" · "toward your Building fund pledge" — plus the gift's own
    /// name when it has one. The same line the STK stage promised.
    private var fundAndName: String {
        let base: String
        switch destination {
        case .fund(let name): base = name
        case .pledge: base = destination.phrase
        }
        return giftName.map { "\(base) \u{2014} \u{201C}\($0)\u{201D}" } ?? base
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            // This stage only ever renders on the server's confirmed outcome —
            // let the moment settle in quietly rather than snap.
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.18)).frame(width: 108, height: 108)
                Circle().fill(Nuru.gold).frame(width: 80, height: 80)
                Icon(.check, size: 34, color: Nuru.navy)
            }
            .gentleEntrance()
            Text("Thank you for your generosity")
                .font(.fraunces(26, .medium)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.lg).padding(.horizontal, Nuru.S.xl)
                .gentleEntrance(delay: 0.08)
            Text(refCode.map { "\(amountLabel) · \(fundAndName) · Ref \($0)" } ?? "\(amountLabel) · \(fundAndName)")
                .font(.inter(13)).foregroundStyle(Color(hex: 0x5B6472))
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
                .gentleEntrance(delay: 0.16)
            Spacer()
            VStack(spacing: Nuru.S.sm) {
                if hasReceipt {
                    Button(action: onViewReceipt) {
                        Text("View receipt")
                            .font(.inter(14, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(Nuru.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain)
                }
                Button(action: onDone) {
                    Text("Done")
                        .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, Nuru.S.xl).padding(.bottom, Nuru.S.xl)
        }
    }
}

private struct ScheduledStage: View {
    let amountLabel, fundLabel, cadenceWord: String
    let nextChargeLabel: String?
    /// Giving Cycle 4: set when the member asked to start with a gift now but
    /// today's prompt could not go out — the server's reason and when the
    /// first prompt comes. Nil when nothing was asked of today.
    var note: String? = nil
    /// "Nothing is taken today — the first prompt comes on 5 Oct 2026."
    var nothingTodayLine: String? = nil
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.18)).frame(width: 108, height: 108)
                Circle().fill(Nuru.gold).frame(width: 80, height: 80)
                Icon(.repeat, size: 32, color: Nuru.navy)
            }
            .gentleEntrance()
            Text("Schedule created")
                .font(.fraunces(26, .medium)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .padding(.top, Nuru.S.lg)
                .gentleEntrance(delay: 0.08)
            Text("\(amountLabel) to \(fundLabel) every \(cadenceWord).")
                .font(.inter(13)).foregroundStyle(Color(hex: 0x5B6472))
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
                .gentleEntrance(delay: 0.16)
            if let note {
                // Today's prompt could not go out — the schedule still stands.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.symbol(13, weight: .semibold))
                        .foregroundStyle(Nuru.urgentText)
                    Text(note).font(.inter(12, .semibold)).foregroundStyle(Nuru.urgentText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Nuru.urgentBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, Nuru.S.md).padding(.horizontal, Nuru.S.xl)
            } else if let nothingTodayLine {
                Text(nothingTodayLine)
                    .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
            }
            if nextChargeLabel != nil {
                HStack(spacing: 6) {
                    Icon(.repeat, size: 14, color: Nuru.goldLo)
                    Text("Change, pause or cancel it anytime")
                        .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x8A6D18))
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Nuru.priorityBg, in: Capsule())
                .overlay(Capsule().stroke(Nuru.gold.opacity(0.33), lineWidth: 1))
                .padding(.top, Nuru.S.md)
            }
            Spacer()
            Button(action: onDone) {
                Text("Done")
                    .font(.inter(14, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, Nuru.S.xl).padding(.bottom, Nuru.S.xl)
        }
    }
}

private struct FailedStage: View {
    let note: String
    /// The server's reason + hint (Cycle 1), shown verbatim when it sent them.
    var failure: GiftFailure? = nil
    /// Which gift this was ("KSh 1,000 to Tithe") — so a gift opened from a
    /// notification says which one failed. Nil when unknown.
    var giftLine: String? = nil
    /// Try again is on its way (Giving Cycle 3): the button spins and waits.
    var busy: Bool = false
    var onRetry: () -> Void
    var onDone: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color(hex: 0xFEE2E2)).frame(width: 64, height: 64)
                Icon(.x, size: 26, color: Color(hex: 0xDC2626))
            }
            Text("That didn't go through")
                .font(.fraunces(22, .medium)).kerning(-0.4).foregroundStyle(Nuru.navy)
                .padding(.top, Nuru.S.base)
            if let giftLine {
                Text(giftLine)
                    .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x74808F))
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.xs).padding(.horizontal, Nuru.S.xl)
            }
            if let failure, !failure.reason.isEmpty {
                // What happened, then what to do next (and whether money moved).
                Text(failure.reason)
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
                if !failure.hint.isEmpty {
                    Text(failure.hint)
                        .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                        .multilineTextAlignment(.center)
                        .padding(.top, Nuru.S.xs).padding(.horizontal, Nuru.S.xl)
                }
            } else {
                Text(note.isEmpty ? "Your amount and fund are saved. Try again whenever you're ready." : note)
                    .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
            }
            Spacer()
            HStack(spacing: Nuru.S.sm) {
                Button(action: onDone) {
                    Text("Close")
                        .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }.buttonStyle(.plain)
                Button(action: onRetry) {
                    ZStack {
                        if busy { ProgressView().tint(Nuru.navy) }
                        else { Text("Try again").font(.inter(14, .bold)).foregroundStyle(Nuru.navy) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .accessibilityHint("Tries the same gift again")
            }
            .padding(.horizontal, Nuru.S.xl).padding(.bottom, Nuru.S.xl)
        }
    }
}

// MARK: - Wrapping chip row (optionally centred, for the preset pills)

private struct FlowWrap: Layout {
    var spacing: CGFloat = 8
    var centered = false

    private func rows(_ subviews: Subviews, maxWidth: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var out: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { out.append([]); x = 0 }
            out[out.count - 1].append((index: i, size: s))
            x += s.width + spacing
        }
        return out
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rs = rows(subviews, maxWidth: maxWidth)
        var h: CGFloat = 0
        for (i, row) in rs.enumerated() {
            h += (row.map { $0.size.height }.max() ?? 0) + (i > 0 ? spacing : 0)
        }
        if maxWidth == .infinity {
            let w = rs.first.map { $0.reduce(CGFloat(0)) { $0 + $1.size.width + spacing } } ?? 0
            return CGSize(width: w, height: h)
        }
        return CGSize(width: maxWidth, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rs = rows(subviews, maxWidth: bounds.width)
        var y = bounds.minY
        for row in rs {
            let rowH = row.map { $0.size.height }.max() ?? 0
            let rowW = row.reduce(CGFloat(0)) { $0 + $1.size.width } + spacing * CGFloat(max(0, row.count - 1))
            var x = centered ? bounds.minX + max(0, (bounds.width - rowW) / 2) : bounds.minX
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += rowH + spacing
        }
    }
}
