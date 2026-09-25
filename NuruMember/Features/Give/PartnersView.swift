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
// path (§5.6). Pause / resume / edit / cancel / reminders live on the pledge
// detail page (tap a pledge) — the list itself is read-only.
//
// The STATEMENT card's three numbers follow the rule shared with Android and
// the docs, computed HERE from the statement + the pledges, never sent:
//   Paid      = Σ payments[].amountMinor where pledgeId != nil
//   Pledged   = Σ over pledges not cancelled:
//                 monthly → amountMinor × (dueDay dates in that year from
//                           max(createdAt, 1 Jan) through 31 Dec)
//                 total   → targetMinor if dueOn falls in that year, else 0
//   Remaining = max(Pledged − Paid, 0)
import SwiftUI

@MainActor final class PartnersModel: ObservableObject {
    @Published var partnership: Partnership?
    @Published var loading = false
    @Published var error: String?
    /// The pledge / schedule id with an action in flight — its control shows a
    /// spinner and refuses a second tap.
    @Published var busyId: String?
    @Published var joining = false
    /// A failed action, surfaced once in an alert and cleared. Never silent.
    @Published var actionError: String?

    // Statements (GET /giving/statements?year=)
    @Published var statements: GivingStatements?
    @Published var statementsLoading = false
    @Published var statementsError: String?
    @Published var statementYear = Calendar.current.component(.year, from: Date())
    /// Every year fetched this session, by year — the pledge cards' "N of M
    /// kept this year" reads the CURRENT year's payments even while the
    /// statement card is showing an earlier year.
    @Published var statementsByYear: [Int: GivingStatements] = [:]

    var currentYearStatements: GivingStatements? {
        statementsByYear[Calendar.current.component(.year, from: Date())]
    }

    func load() async {
        loading = partnership == nil
        error = nil
        do { partnership = try await MemberAPI.partnership() }
        catch { if partnership == nil { self.error = (error as? APIError)?.errorDescription ?? "We couldn't load this just now." } }
        loading = false
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
        } catch {
            Haptics.error()
            actionError = (error as? APIError)?.errorDescription ?? "That didn't go through. Nothing has changed."
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

    /// Edit name / amount / due day. `title` nil = untouched, `.set` = a new
    /// custom name, `.clear` = an explicit null so the server falls back to
    /// its derived name. Returns true on success so the sheet can close.
    @discardableResult
    func edit(_ pledge: Pledge, amountMinor: Int?, dueDay: Int?,
              title: MemberAPI.PledgePatchBody.TitlePatch? = nil) async -> Bool {
        await patch(pledge.pledgeId, MemberAPI.PledgePatchBody(amountMinor: amountMinor, dueDay: dueDay, title: title))
    }

    @discardableResult
    private func patch(_ id: String, _ body: MemberAPI.PledgePatchBody) async -> Bool {
        guard busyId == nil else { return false }
        busyId = id
        defer { busyId = nil }
        do {
            _ = try await MemberAPI.updatePledge(id, patch: body)
            Haptics.success()
            await load()
            return true
        } catch {
            Haptics.error()
            actionError = (error as? APIError)?.errorDescription ?? "That didn't go through. Your pledge is unchanged."
            return false
        }
    }

    /// POST /giving/schedules/{id}/resume — the existing schedule path; it
    /// deliberately does NOT collect the cycle that was missed.
    func resumeSchedule(_ id: String) async {
        guard busyId == nil else { return }
        busyId = id
        defer { busyId = nil }
        do { try await MemberAPI.resumeSchedule(id); Haptics.success(); await load() }
        catch {
            Haptics.error()
            actionError = (error as? APIError)?.errorDescription ?? "That didn't go through. Your giving is unchanged."
        }
    }

    /// Always a real fetch (a year chip = GET /giving/statements?year=); the
    /// by-year cache is for the pledge cards, not for skipping the request.
    func loadStatements(year: Int? = nil) async {
        let y = year ?? statementYear
        statementYear = y
        statementsLoading = true
        statementsError = nil
        do {
            let s = try await MemberAPI.givingStatements(year: y)
            statements = s
            statementYear = s.year
            statementsByYear[s.year] = s
        } catch {
            statementsError = (error as? APIError)?.errorDescription ?? "We couldn't load your statement."
        }
        statementsLoading = false
    }
}

/// Pushed pages on the Partners stack.
enum PartnersRoute: Hashable {
    case pledge(String)          // a pledge's detail: payments + actions
    case receipt(String)         // a transaction's receipt
    case statement               // the full statement + PDF (GivingStatementView)
}

// MARK: - The statement arithmetic (shared rule — see the header comment)

enum PledgeMath {
    /// How many of a monthly pledge's due dates fall in `year`, counting from
    /// max(createdAt, 1 Jan) through `through` (31 Dec when nil), inclusive
    /// at both ends. A pledge created after `through` counts none.
    static func monthlyDueDates(_ p: Pledge, in year: Int, through: Date? = nil) -> Int {
        guard p.isMonthly else { return 0 }
        let cal = Calendar.current
        let day = min(28, max(1, p.dueDay ?? 1))
        guard var start = cal.date(from: DateComponents(year: year, month: 1, day: 1)),
              let yearEnd = cal.date(from: DateComponents(year: year, month: 12, day: 31)) else { return 0 }
        if let iso = p.createdAt, let created = PartnerFormat.date(iso) ?? giveParseDate(iso) {
            start = max(start, cal.startOfDay(for: created))
        }
        let end = through.map { cal.startOfDay(for: $0) } ?? yearEnd
        var n = 0
        for month in 1...12 {
            guard let d = cal.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            if d >= start && d <= end { n += 1 }
        }
        return n
    }

    /// Pledged for `year` across every pledge that is not cancelled.
    static func pledgedMinor(_ pledges: [Pledge], year: Int) -> Int {
        pledges.filter { $0.status != "cancelled" }.reduce(0) { acc, p in
            if p.isMonthly {
                return acc + (p.amountMinor ?? 0) * monthlyDueDates(p, in: year)
            }
            guard let due = p.dueOn, let d = giveParseDate(due),
                  Calendar.current.component(.year, from: d) == year else { return acc }
            return acc + (p.targetMinor ?? 0)
        }
    }

    /// Paid toward pledges in a statement: only payments that carry a pledge id.
    static func paidMinor(_ s: GivingStatements) -> Int {
        s.pledgePayments.reduce(0) { $0 + $1.amountMinor }
    }

    static func remainingMinor(pledged: Int, paid: Int) -> Int { max(pledged - paid, 0) }
}

extension GivingStatements {
    /// The payments attributed to a pledge, newest first — the only ones the
    /// Partners tab lists (gifts without a pledge stay on Give's statement).
    var pledgePayments: [PledgePayment] {
        payments
            .filter { $0.pledgeId != nil }
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
    @State private var path = NavigationPath()
    @State private var showNewPledge = false

    var body: some View {
        Group {
            if embedded {
                NavigationStack(path: $path) {
                    content
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: PartnersRoute.self) { destination($0) }
                }
            } else {
                content
                    .navigationTitle("Partners")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: PartnersRoute.self) { destination($0) }
            }
        }
        .task { if vm.partnership == nil { await vm.load() } }
        .fullScreenCover(isPresented: $showNewPledge) {
            NewPledgeFlow(isMember: vm.partnership?.isProgrammeMember ?? false,
                          pledgeOptions: vm.partnership?.pledgeOptions ?? [],
                          campaigns: vm.partnership?.campaigns ?? []) {
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
        case .statement:
            GivingStatementView()
        }
    }

    private var content: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    sections
                }
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
        if let p = vm.partnership {
            if p.isProgrammeMember {
                StandingCard(partnership: p,
                             onPledge: { Haptics.tap(); showNewPledge = true },
                             onStatement: { Haptics.tap(); path.append(PartnersRoute.statement) })
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
        } else if vm.loading {
            ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.top, 60)
        } else {
            errorState
        }
    }

    // MARK: The band (the same cream band Give paints — one band, not two)

    private var band: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let segment, let onSelectSegment {
                SplitSegmentBar(selection: segment, onSelect: onSelectSegment)
                    .padding(.bottom, 12)
            }
            Text("Walk with the church")
                .font(.fraunces(24, .semibold)).kerning(-0.48).foregroundStyle(Nuru.navy)
            Text("Decide in advance. The church can plan.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
                .padding(.top, 4)
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
                .font(.fraunces(20, .semibold)).foregroundStyle(Nuru.ink)
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

    private func dueSection(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow("DUE")
            VStack(spacing: 0) {
                ForEach(Array(p.due.enumerated()), id: \.element.id) { i, item in
                    dueRow(item, p)
                    if i != p.due.count - 1 {
                        Divider().overlay(Nuru.border).padding(.vertical, 10)
                    }
                }
            }
            .partnerCard()
        }
    }

    private func dueRow(_ item: DueItem, _ p: Partnership) -> some View {
        let busy = vm.busyId == item.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("\(money(item.amountMinor, item.currency)) · \(relativeDay(item.dueOn))")
                    .font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                Text(dueSubtitle(item, p))
                    .font(.inter(12)).foregroundStyle(Nuru.ink600).lineLimit(1)
            }
            Spacer(minLength: 8)
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
            tabs.openGive(preset: GivePreset(fund: pl?.fund?.code, amountMinor: item.amountMinor, pledgeId: item.id,
                                             pledgeTitle: pl?.displayTitle ?? (item.title.isEmpty ? nil : item.title)))
        default:
            tabs.openGive(preset: GivePreset(fund: nil, amountMinor: item.amountMinor, pledgeId: nil))
        }
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

    /// "9 of 12 kept this year" — payments this year carrying this pledge id
    /// (from the CURRENT year's statement) over the due dates elapsed so far.
    /// Nil until that statement has loaded; the card then shows no left text.
    private func keptLine(_ pledge: Pledge) -> String? {
        guard pledge.isMonthly, let s = vm.currentYearStatements else { return nil }
        let year = Calendar.current.component(.year, from: Date())
        let kept = s.payments.filter { $0.pledgeId == pledge.pledgeId }.count
        let elapsed = PledgeMath.monthlyDueDates(pledge, in: year, through: Date())
        return "\(kept) of \(max(elapsed, kept)) kept this year"
    }

    // MARK: Statement — year chips, three numbers, the pledge payments

    private var statementYears: [Int] {
        let cal = Calendar.current
        let now = cal.component(.year, from: Date())
        let joinISO = vm.partnership?.membership?.joinedAt ?? vm.partnership?.since
        let joinYear = joinISO
            .flatMap { PartnerFormat.date($0) ?? giveParseDate($0) }
            .map { cal.component(.year, from: $0) } ?? now
        let first = max(min(joinYear, now), now - 3)
        return Array((first...now).reversed())
    }

    private func statementSection(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                eyebrow("STATEMENT")
                Spacer()
                yearChips
            }
            statementCard(p)
        }
        .task { if vm.statements == nil { await vm.loadStatements() } }
    }

    private var yearChips: some View {
        HStack(spacing: 6) {
            ForEach(statementYears, id: \.self) { y in
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
        let pledged = PledgeMath.pledgedMinor(p.pledges, year: s.year)
        let paid = PledgeMath.paidMinor(s)
        let remaining = PledgeMath.remainingMinor(pledged: pledged, paid: paid)
        let rows = s.pledgePayments
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                summaryColumn("Pledged", money(pledged, s.currency), Nuru.navy)
                summaryColumn("Paid", money(paid, s.currency), Nuru.successText)
                summaryColumn("Remaining", money(remaining, s.currency), Nuru.goldLo)
            }

            Divider().overlay(Nuru.border).padding(.vertical, 14)

            if rows.isEmpty {
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
                Haptics.tap(); path.append(PartnersRoute.statement)
            } label: {
                HStack(spacing: 4) {
                    Text("Full statement and PDF").font(.inter(13, .semibold))
                    Icon(.arrowRight, size: 12, color: Nuru.gold)
                }
                .foregroundStyle(Nuru.gold)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            .buttonStyle(.plain)
        }
    }

    private func summaryColumn(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.inter(9, .semibold)).kerning(1.2).foregroundStyle(Nuru.ink400)
            Text(value).font(.inter(16, .semibold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The statement's own title for the pledge, else the pledge's name.
    private func paymentTitle(_ pay: PledgePayment, _ s: GivingStatements, _ p: Partnership) -> String {
        guard let id = pay.pledgeId else { return "Pledge" }
        if let t = s.pledgeTitle(for: id) { return t }
        if let pl = p.pledges.first(where: { $0.pledgeId == id }) { return pl.displayTitle }
        return "Pledge"
    }

    // MARK: Error / retry states

    private var errorState: some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.circleHelp, size: 28, color: Nuru.muted)
            Text("We couldn't load this just now").font(.inter(15, .bold)).foregroundStyle(Nuru.ink)
            Text(vm.error ?? "Your giving is unaffected.")
                .font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                .padding(.horizontal, Nuru.S.xl)
            Button { Haptics.tap(); Task { await vm.load() } } label: {
                Text("Try again").font(.inter(12, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Nuru.navy, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
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

// MARK: - Atoms shared by the cards

/// ONE-word eyebrow: `.inter(9, .semibold)`, kerning 1.6, goldLo.
private func eyebrow(_ s: String) -> some View {
    Text(s).font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Nuru.goldLo)
}

/// The Partners card: white, border stroke, radius 16, 16pt padding.
private struct PartnerCardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}
private extension View {
    func partnerCard() -> some View { modifier(PartnerCardStyle()) }
}

private func ordinal(_ n: Int) -> String {
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
/// isn't this one). Shared by the card and the detail page so they agree.
private func pledgeAmountLine(_ p: Pledge) -> String {
    if p.isMonthly {
        var parts = ["\(money(p.amountMinor ?? 0, p.currency)) monthly"]
        if let d = p.dueDay { parts.append("due on the \(ordinal(d))") }
        return parts.joined(separator: " · ")
    }
    var parts = [money(p.targetMinor ?? 0, p.currency)]
    if let iso = p.dueOn, let d = giveParseDate(iso) {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: d) == cal.component(.year, from: Date())
        parts.append("by \(sameYear ? giveDateShort(iso) : giveDateFull(iso))")
    }
    return parts.joined(separator: " · ")
}

// MARK: - Standing

private struct StandingCard: View {
    let partnership: Partnership
    let onPledge: () -> Void
    let onStatement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            eyebrow("STANDING")

            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(sinceLine).font(.inter(16, .semibold)).foregroundStyle(Nuru.ink)
                    Text(keptLine).font(.inter(12)).foregroundStyle(Nuru.ink600)
                }
                Spacer(minLength: 8)
                if let t = partnership.tier, !t.name.isEmpty {
                    HStack(spacing: 5) {
                        Icon(.award, size: 12, color: Nuru.goldChipText)
                        Text(t.name).font(.inter(11, .bold)).foregroundStyle(Nuru.goldChipText)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Nuru.goldChipBg, in: Capsule())
                    .accessibilityElement(children: .ignore)
                    // The tier sentence lives here and nowhere on screen.
                    .accessibilityLabel("\(t.name) partner — \(money(t.monthlyMinor, partnership.currency)) a month. KSh 20,000 carries one disciple through a level.")
                }
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

    /// "Partner since Sep 2026" — month + year from the membership's joinedAt,
    /// else the derived `since`; just "Partner" when neither is present.
    private var sinceLine: String {
        let iso = partnership.membership?.joinedAt ?? partnership.since
        guard let iso, let d = PartnerFormat.date(iso) ?? giveParseDate(iso) else { return "Partner" }
        let f = DateFormatter(); f.dateFormat = "MMM yyyy"
        return "Partner since \(f.string(from: d))"
    }

    /// "N gifts kept · on track" — `kept` is what was COLLECTED, never scheduled.
    private var keptLine: String {
        let n = partnership.kept
        let gifts = n == 1 ? "1 gift kept" : "\(n) gifts kept"
        let paused = partnership.membership?.status == "paused" || partnership.status == "paused"
        return "\(gifts) · \(paused ? "paused" : "on track")"
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
                .font(.system(size: 13, weight: .semibold))
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
                    Text(pledge.displayTitle).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
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
                    Text(n).font(.inter(11)).foregroundStyle(Nuru.ink600).lineLimit(1)
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
        return "\(money(paid, pledge.currency)) paid · \((toGo / 100).formatted(.number.grouping(.automatic))) to go"
    }

    private var nextLine: String? {
        if fulfilled || paused { return nil }
        guard let n = pledge.progress.nextDue, !n.isEmpty else { return nil }
        return "Next \(giveDateShort(n))"
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
        return Text(text).font(.inter(10, .bold)).foregroundStyle(fg)
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

// MARK: - A pledge's detail (GET /giving/pledges/{id}) — payments + actions

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
                    if let p = pledge {
                        VStack(alignment: .leading, spacing: 4) {
                            // The name is the page's header; this card carries the promise.
                            Text(pledgeAmountLine(p)).font(.nuruDisplay(22)).foregroundStyle(Nuru.ink)
                            Text("\(money(p.paidTowardMinor, p.currency)) of \(money(p.commitmentMinor, p.currency))\(p.isMonthly ? " this month" : "") · \(money(p.progress.paidMinor, p.currency)) given in all")
                                .font(.nCaption).foregroundStyle(Nuru.ink600)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

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
                            Text("PAYMENTS").font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
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
                }
                .padding(Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .refreshable { await load() }
        }
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
        .confirmationDialog(
            "Cancel \u{201C}\(cancelling?.displayTitle ?? "this pledge")\u{201D}?",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible
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
        catch { if detail == nil { self.error = (error as? APIError)?.errorDescription ?? "We couldn't load this pledge." } }
        loading = false
    }

    // MARK: Actions — every one a server round-trip; the page never relabels itself

    @ViewBuilder private func actions(_ p: Pledge) -> some View {
        let paused = p.status == "paused"
        let fulfilled = p.status == "fulfilled" || p.progress.label == "fulfilled"
        if !fulfilled && p.status != "cancelled" {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Button {
                        Haptics.action()
                        tabs.openGive(preset: GivePreset(
                            fund: p.fund?.code,
                            amountMinor: p.remainingMinor > 0 ? p.remainingMinor : p.commitmentMinor,
                            pledgeId: p.pledgeId,
                            pledgeTitle: p.displayTitle))
                    } label: {
                        HStack(spacing: 6) {
                            Text("Pay now").font(.inter(13, .bold))
                            Icon(.arrowRight, size: 12, color: Nuru.navy)
                        }
                        .foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                            else { Icon(paused ? .play : .pause, size: 12, color: Nuru.navy) }
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

                // Claims (§1 rule d) are a later phase — say so, rather than hide it.
                HStack(spacing: 6) {
                    Icon(.check, size: 12, color: Nuru.ink300)
                    Text("I paid another way").font(.inter(12, .semibold)).foregroundStyle(Nuru.ink300)
                    Text("coming soon").font(.inter(10, .semibold)).foregroundStyle(Nuru.ink400)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Nuru.mutedBg, in: Capsule())
                    Spacer(minLength: 0)
                }
                .accessibilityHint("Coming soon")

                Toggle(isOn: Binding(get: { p.remindersEnabled },
                                     set: { on in Task { await vm.setReminders(p, on); await load() } })) {
                    HStack(spacing: 8) {
                        Icon(.bell, size: 13, color: Nuru.gold)
                        Text("Remind me before it's due").font(.inter(13)).foregroundStyle(Nuru.ink)
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

    private func smallAction(_ title: String, _ icon: Lucide, tint: Color = Nuru.ink600, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 5) {
                Icon(icon, size: 12, color: tint)
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
        .ignoresSafeArea(edges: .top)
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
