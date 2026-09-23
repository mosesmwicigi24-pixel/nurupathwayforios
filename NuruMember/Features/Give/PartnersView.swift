// The Partners portal — Give → Partners (PARTNERS_PROGRAMME §2, contract §5).
//
// Six things, in this order: standing (or the invitation to join), what is
// due, the member's pledges, statements, the season block, and the door to a
// new pledge. Everything is derived server-side (progress is computed, never
// stored — §1), so this view holds no second copy of the truth. Two rules
// from the original design still carry all the way into the copy:
//
//   · `kept` is cycles COLLECTED, never cycles scheduled. The label says
//     "collected" for exactly that reason.
//   · the season block is what the WHOLE CHURCH did while they partnered.
//     Never "your giving produced this".
//
// Joining needs no fund, no campaign and no money (§1) — the Join button
// posts `{}` and that is the whole ceremony. "Pay now" never charges here: it
// opens Give pre-filled (fund, amount still due) with the pledge id riding the
// intent body (§1 rule a), so money stays on the one server-authoritative
// path (§5.6). "I paid another way" (claims, §1 rule d) is phase 2 and is
// shown disabled rather than hidden, so the member knows it is coming.
import SwiftUI

@MainActor final class PartnersModel: ObservableObject {
    @Published var partnership: Partnership?
    @Published var loading = false
    @Published var error: String?
    /// The pledge / schedule id with an action in flight — its card shows a
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

    /// Edit amount / due day. Returns true on success so the sheet can close.
    @discardableResult
    func edit(_ pledge: Pledge, amountMinor: Int?, dueDay: Int?) async -> Bool {
        await patch(pledge.pledgeId, MemberAPI.PledgePatchBody(amountMinor: amountMinor, dueDay: dueDay))
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

    func loadStatements(year: Int? = nil) async {
        let y = year ?? statementYear
        statementYear = y
        statementsLoading = true
        statementsError = nil
        do {
            let s = try await MemberAPI.givingStatements(year: y)
            statements = s
            statementYear = s.year
        } catch {
            statementsError = (error as? APIError)?.errorDescription ?? "We couldn't load your statement."
        }
        statementsLoading = false
    }
}

/// Pushed pages on the Partners stack.
enum PartnersRoute: Hashable {
    case pledge(String)          // a pledge's payments
    case receipt(String)         // a transaction's receipt
    case statement               // the full statement + PDF (GivingStatementView)
}

struct PartnersView: View {
    /// True when hosted as the "Partners" segment inside the Give tab (the
    /// only way in now): the capsule above already clears the status bar, so
    /// the header is a cream band with a little breathing room and the page
    /// owns its own NavigationStack for receipts / the statement / a pledge.
    var embedded: Bool = false

    @StateObject private var vm = PartnersModel()
    @EnvironmentObject private var tabs: TabRouter
    @State private var path = NavigationPath()
    @State private var showNewPledge = false
    @State private var editing: Pledge?
    @State private var cancelling: Pledge?

    var body: some View {
        Group {
            if embedded {
                NavigationStack(path: $path) {
                    content
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: PartnersRoute.self) { route in
                            switch route {
                            case .pledge(let id): PledgeDetailView(pledgeId: id, seed: vm.partnership?.pledges.first { $0.pledgeId == id })
                            case .receipt(let tx): GivingReceiptView(transactionId: tx)
                            case .statement: GivingStatementView()
                            }
                        }
                }
            } else {
                content
                    .navigationTitle("Partners")
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: PartnersRoute.self) { route in
                        switch route {
                        case .pledge(let id): PledgeDetailView(pledgeId: id, seed: vm.partnership?.pledges.first { $0.pledgeId == id })
                        case .receipt(let tx): GivingReceiptView(transactionId: tx)
                        case .statement: GivingStatementView()
                        }
                    }
            }
        }
        .task { if vm.partnership == nil { await vm.load() } }
        .fullScreenCover(isPresented: $showNewPledge) {
            NewPledgeFlow(isMember: vm.partnership?.isProgrammeMember ?? false,
                          campaigns: vm.partnership?.campaigns ?? []) {
                Task { await vm.load() }
            }
        }
        .sheet(item: $editing) { p in
            EditPledgeSheet(pledge: p) { amountMinor, dueDay in
                await vm.edit(p, amountMinor: amountMinor, dueDay: dueDay)
            }
        }
        .confirmationDialog(
            "Cancel this pledge?",
            isPresented: Binding(get: { cancelling != nil }, set: { if !$0 { cancelling = nil } }),
            titleVisibility: .visible
        ) {
            Button("Cancel the pledge", role: .destructive) {
                if let p = cancelling { Haptics.action(); Task { await vm.setStatus(p, "cancelled") } }
                cancelling = nil
            }
            Button("Keep it", role: .cancel) { cancelling = nil }
        } message: {
            Text("Nothing already given is affected, and nothing further is owed. You can make a new pledge any time.")
        }
        .alert("That didn't go through", isPresented: Binding(get: { vm.actionError != nil }, set: { if !$0 { vm.actionError = nil } })) {
            Button("OK") { vm.actionError = nil }
        } message: { Text(vm.actionError ?? "") }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                if embedded { header }
                VStack(alignment: .leading, spacing: 20) {
                    if let p = vm.partnership {
                        if p.isProgrammeMember { PartnerStanding(partnership: p) } else { joinHero(p) }
                        if let t = p.trouble {
                            PartnerTrouble(
                                trouble: t,
                                resuming: vm.busyId != nil && vm.busyId == p.scheduleId,
                                onResume: p.scheduleId.map { id in { Task { await vm.resumeSchedule(id) } } })
                        }
                        if !p.due.isEmpty { dueSection(p) }
                        pledgesSection(p)
                        if p.isProgrammeMember || !p.pledges.isEmpty { statementsSection }
                        if let r = p.rhythm, p.pledges.isEmpty { PartnerRhythm(rhythm: r, currency: p.currency) }
                        if let s = p.sinceYouBegan, p.isProgrammeMember { PartnerSeason(season: s) }
                        Text("Your gifts, receipts and statements stay in Giving.")
                            .font(.nCaption).foregroundStyle(Nuru.ink400)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 4)
                    } else if vm.loading {
                        ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.top, 60)
                    } else {
                        errorState
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, embedded ? Nuru.S.base : 8)
                .padding(.bottom, embedded ? Nuru.tabBarSpace : 40)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .refreshable { await vm.load() }
    }

    // MARK: Header (cream band — the Give screen's own idiom, do not restyle)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PARTNERS")
                .font(.inter(9, .bold)).kerning(1.62).foregroundStyle(Color(hex: 0x9A7A2A))
            Text("Walk with the church")
                .font(.fraunces(24, .semibold)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .padding(.top, 4)
            Text("A partner decides in advance to keep giving, so the church can plan beyond a Sunday.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, Nuru.S.base)
        .padding(.bottom, 20)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // MARK: Not yet a partner — the invitation, warm and without a price tag

    private func joinHero(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("JOIN THE PARTNERS PROGRAMME")
                .font(.nMicro).tracking(1.4).foregroundStyle(Nuru.gold.opacity(0.9))
            Text(p.everPartnered ? "Welcome back." : "Become a partner of this church.")
                .font(.nuruDisplay(26)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(p.everPartnered
                 ? "Your earlier partnership ended, and nothing is owed. Joining again takes one tap — a pledge can come later, or not at all."
                 : "Joining costs nothing and asks for nothing today. It simply says: count me in. A pledge — monthly, or a total by a date — can come later, or not at all.")
                .font(.nBody).foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.action()
                Task { await vm.join() }
            } label: {
                HStack(spacing: 8) {
                    if vm.joining { ProgressView().tint(Nuru.navy).scaleEffect(0.8) }
                    Text(vm.joining ? "Joining…" : "Join the programme").font(.inter(15, .bold))
                    if !vm.joining { Icon(.arrowRight, size: 15, color: Nuru.navy) }
                }
                .foregroundStyle(Nuru.navy)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(vm.joining)

            Button {
                Haptics.tap(); showNewPledge = true
            } label: {
                HStack(spacing: 6) {
                    Icon(.plus, size: 13, color: .white)
                    Text("Add a pledge").font(.inter(13, .semibold)).foregroundStyle(.white)
                }
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.16), lineWidth: 1))
            }
            .buttonStyle(.pressableSubtle)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.18), radius: 20, y: 10)
    }

    // MARK: Due — soonest first, one action each

    private func dueSection(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DUE").font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)
            VStack(spacing: 8) {
                ForEach(p.due) { item in dueRow(item, p) }
            }
        }
    }

    private func dueRow(_ item: DueItem, _ p: Partnership) -> some View {
        let busy = vm.busyId == item.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title.isEmpty ? (item.kind == "schedule" ? "Recurring gift" : "Pledge") : item.title)
                    .font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(2)
                Text("\(money(item.amountMinor, item.currency)) · \(dueWord(item.dueOn))")
                    .font(.nCaption).foregroundStyle(Nuru.ink600)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.action()
                act(on: item, p)
            } label: {
                HStack(spacing: 6) {
                    if busy { ProgressView().tint(.white).scaleEffect(0.7) }
                    Text(item.action == "resume" ? "Resume" : "Pay now").font(.inter(12, .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14).frame(height: 36)
                .background(Nuru.navyDeep, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(busy)
        }
        .padding(14)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.gold.opacity(0.28), lineWidth: 1))
    }

    private func act(on item: DueItem, _ p: Partnership) {
        switch (item.kind, item.action) {
        case ("schedule", "resume"):
            Task { await vm.resumeSchedule(item.id) }
        case ("pledge", "resume"):
            if let pl = p.pledges.first(where: { $0.pledgeId == item.id }) { Task { await vm.setStatus(pl, "active") } }
        case ("pledge", _):
            let pl = p.pledges.first { $0.pledgeId == item.id }
            tabs.openGive(preset: GivePreset(fund: pl?.fund?.code, amountMinor: item.amountMinor, pledgeId: item.id))
        default:
            tabs.openGive(preset: GivePreset(fund: nil, amountMinor: item.amountMinor, pledgeId: nil))
        }
    }

    private func dueWord(_ ymd: String) -> String {
        guard let d = giveParseDate(ymd) else { return ymd }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "due today" }
        if cal.isDateInTomorrow(d) { return "due tomorrow" }
        if d < Date() { return "was due \(giveDateShort(ymd))" }
        return "due \(giveDateShort(ymd))"
    }

    // MARK: My pledges

    private func pledgesSection(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("MY PLEDGES").font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)
                Spacer()
                Button {
                    Haptics.tap(); showNewPledge = true
                } label: {
                    HStack(spacing: 4) {
                        Icon(.plus, size: 12, color: Nuru.gold)
                        Text("Add a pledge").font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                    }
                }
                .buttonStyle(.plain)
            }
            let live = p.pledges.filter { $0.status != "cancelled" }
            if live.isEmpty {
                pledgesEmpty(p)
            } else {
                VStack(spacing: 12) {
                    ForEach(live) { pledge in
                        PledgeCard(
                            pledge: pledge,
                            busy: vm.busyId == pledge.pledgeId,
                            onPayNow: {
                                tabs.openGive(preset: GivePreset(
                                    fund: pledge.fund?.code,
                                    amountMinor: pledge.remainingMinor > 0 ? pledge.remainingMinor : pledge.commitmentMinor,
                                    pledgeId: pledge.pledgeId))
                            },
                            onPauseResume: { Task { await vm.setStatus(pledge, pledge.status == "paused" ? "active" : "paused") } },
                            onEdit: { editing = pledge },
                            onCancel: { cancelling = pledge },
                            onReminders: { on in Task { await vm.setReminders(pledge, on) } },
                            onPayments: { path.append(PartnersRoute.pledge(pledge.pledgeId)) })
                    }
                }
            }
        }
    }

    private func pledgesEmpty(_ p: Partnership) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(p.isProgrammeMember ? "No pledges yet" : "A pledge is a promise you set")
                .font(.nHeading).foregroundStyle(Nuru.ink)
            Text("Monthly, or a total by a date — toward a fund, a campaign, or the church as a whole. Change it, pause it or end it whenever you need to.")
                .font(.nBody).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Statements — by year, by pledge, by fund, then the payments

    private var statementsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("STATEMENTS").font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)
                Spacer()
                Button {
                    Haptics.tap(); path.append(PartnersRoute.statement)
                } label: {
                    HStack(spacing: 3) {
                        Text("Full statement & PDF").font(.inter(12, .semibold))
                        Icon(.arrowRight, size: 11, color: Nuru.gold)
                    }.foregroundStyle(Nuru.gold)
                }
                .buttonStyle(.plain)
            }

            if let s = vm.statements {
                yearChips(s.years)
                if vm.statementsLoading {
                    ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 20)
                } else {
                    statementBody(s)
                }
            } else if vm.statementsLoading {
                ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if let e = vm.statementsError {
                retryRow(e) { Task { await vm.loadStatements() } }
            }
        }
        .task { if vm.statements == nil { await vm.loadStatements() } }
    }

    private func yearChips(_ years: [Int]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(years.sorted(by: >), id: \.self) { y in
                    let on = vm.statementYear == y
                    Button {
                        guard !on else { return }
                        Haptics.selection()
                        Task { await vm.loadStatements(year: y) }
                    } label: {
                        Text(String(y)).font(.inter(13, .semibold))
                            .foregroundStyle(on ? .white : Nuru.navy)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(on ? Nuru.navy : Nuru.surface, in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    private func statementBody(_ s: GivingStatements) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("TOTAL GIVEN · \(String(s.year))").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.navy)
                Spacer()
                Text(money(s.totalMinor, s.currency)).font(.fraunces(18, .bold)).foregroundStyle(Nuru.gold)
            }
            .padding(.bottom, s.byPledge.isEmpty && s.byFund.isEmpty ? 0 : 12)

            if !s.byPledge.isEmpty {
                Text("BY PLEDGE").font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                    .padding(.top, 4)
                ForEach(s.byPledge) { row in
                    statementRow(row.title.isEmpty ? "Pledge" : row.title, money(row.totalMinor, s.currency))
                }
            }
            if !s.byFund.isEmpty {
                Text("BY FUND").font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                    .padding(.top, 10)
                ForEach(s.byFund) { row in
                    statementRow(row.name.isEmpty ? row.code.capitalized : row.name, money(row.totalMinor, s.currency))
                }
            }
            if s.byPledge.isEmpty && s.byFund.isEmpty && s.payments.isEmpty {
                Text("No gifts recorded in \(String(s.year)).")
                    .font(.nCardBody).foregroundStyle(Color(hex: 0x5B6472))
                    .padding(.top, 10)
            }
            if !s.payments.isEmpty {
                Text("PAYMENTS").font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                    .padding(.top, 12)
                ForEach(s.payments) { pay in
                    PaymentRow(payment: pay) { path.append(PartnersRoute.receipt(pay.transactionId)) }
                }
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func statementRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
            Spacer(minLength: 12)
            Text(value).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
        }
        .padding(.vertical, 7)
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
        .padding(14)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

// MARK: - One pledge

/// A pledge card: shape and target, the progress bar, the computed label, the
/// next due date, and the actions. Every action is a server round-trip —
/// the card never changes its own label.
private struct PledgeCard: View {
    let pledge: Pledge
    let busy: Bool
    let onPayNow: () -> Void
    let onPauseResume: () -> Void
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onReminders: (Bool) -> Void
    let onPayments: () -> Void

    private var paused: Bool { pledge.status == "paused" }
    private var fulfilled: Bool { pledge.status == "fulfilled" || pledge.progress.label == "fulfilled" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pledge.targetTitle).font(.nHeading).foregroundStyle(Nuru.ink).lineLimit(2)
                    Text(shapeLine).font(.nCaption).foregroundStyle(Nuru.ink600)
                }
                Spacer(minLength: 8)
                labelChip
            }

            // Progress — this period for monthly, toward the target for total.
            VStack(alignment: .leading, spacing: 6) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Nuru.navy.opacity(0.10))
                        Capsule().fill(fulfilled ? Nuru.success : Nuru.gold)
                            .frame(width: max(4, geo.size.width * pledge.fraction))
                    }
                }
                .frame(height: 7)
                HStack(spacing: 6) {
                    Text(money(pledge.paidTowardMinor, pledge.currency)).font(.nLabel).foregroundStyle(Nuru.ink)
                    Text("of \(money(pledge.commitmentMinor, pledge.currency))\(pledge.isMonthly ? " this month" : "")")
                        .font(.nCaption).foregroundStyle(Nuru.ink600)
                    Spacer(minLength: 8)
                    Text(nextDueLine).font(.nCaption).foregroundStyle(Nuru.ink600)
                }
            }

            // Actions
            if !fulfilled && pledge.status != "cancelled" {
                HStack(spacing: 8) {
                    Button { Haptics.action(); onPayNow() } label: {
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

                    Button { Haptics.tap(); onPauseResume() } label: {
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
                    smallAction("Edit", .pencil) { onEdit() }
                    Divider().frame(height: 16).overlay(Nuru.border)
                    smallAction("Payments", .list) { onPayments() }
                    Divider().frame(height: 16).overlay(Nuru.border)
                    smallAction("Cancel", .x, tint: Nuru.danger) { onCancel() }
                }
                .disabled(busy)

                // Claims (§1 rule d) are phase 2 — say so, rather than hide it.
                HStack(spacing: 6) {
                    Icon(.check, size: 12, color: Nuru.ink300)
                    Text("I paid another way").font(.inter(12, .semibold)).foregroundStyle(Nuru.ink300)
                    Text("coming soon").font(.inter(10, .semibold)).foregroundStyle(Nuru.ink400)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Nuru.mutedBg, in: Capsule())
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
                .accessibilityHint("Coming soon")

                Toggle(isOn: Binding(get: { pledge.remindersEnabled }, set: { onReminders($0) })) {
                    HStack(spacing: 8) {
                        Icon(.bell, size: 13, color: Nuru.gold)
                        Text("Remind me before it's due").font(.inter(13)).foregroundStyle(Nuru.ink)
                    }
                }
                .tint(Nuru.gold)
                .disabled(busy)
            } else {
                Button { Haptics.tap(); onPayments() } label: {
                    HStack(spacing: 4) {
                        Text("See payments").font(.inter(12, .semibold))
                        Icon(.arrowRight, size: 11, color: Nuru.gold)
                    }.foregroundStyle(Nuru.gold)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(fulfilled ? Nuru.success.opacity(0.35) : Nuru.gold.opacity(0.22), lineWidth: 1))
        .opacity(paused ? 0.92 : 1)
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

    private var shapeLine: String {
        if pledge.isMonthly {
            let day = pledge.dueDay.map { " · due on the \(ordinal($0))" } ?? ""
            return "\(money(pledge.amountMinor ?? 0, pledge.currency)) every month\(day)"
        }
        let by = pledge.dueOn.map { " by \(giveDateFull($0))" } ?? ""
        return "\(money(pledge.targetMinor ?? 0, pledge.currency)) in total\(by)"
    }

    private var nextDueLine: String {
        if fulfilled { return "Fulfilled" }
        if paused { return "Paused" }
        guard let n = pledge.progress.nextDue, !n.isEmpty else { return "" }
        return "Next: \(giveDateShort(n))"
    }

    private var labelChip: some View {
        let (bg, fg, text): (Color, Color, String) = {
            switch (pledge.status, pledge.progress.label) {
            case ("paused", _), (_, "paused"): return (Nuru.mutedBg, Nuru.ink600, "Paused")
            case ("fulfilled", _), (_, "fulfilled"): return (Nuru.successBg, Nuru.successText, "Fulfilled")
            case (_, "behind"): return (Nuru.urgentBg, Nuru.urgentText, "Behind")
            default: return (Nuru.goldChipBg, Nuru.goldChipText, "On track")
            }
        }()
        return Text(text).font(.nMicro).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3).background(bg, in: Capsule())
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
}

/// One payment line — amount, date, receipt code — tapping opens the receipt.
struct PaymentRow: View {
    let payment: PledgePayment
    let onOpen: () -> Void

    var body: some View {
        Button { Haptics.tap(); onOpen() } label: {
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
                if let s = payment.status, !s.isEmpty, !["succeeded", "settled", "completed"].contains(s) {
                    statusChip(s)
                }
                Icon(.chevronRight, size: 14, color: Nuru.ink300)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressableSubtle)
    }
}

// MARK: - A pledge's payments (GET /giving/pledges/{id})

struct PledgeDetailView: View {
    let pledgeId: String
    /// The list's copy of the pledge, so the header renders before the fetch.
    var seed: Pledge? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var detail: PledgeDetail?
    @State private var loading = true
    @State private var error: String?

    private var pledge: Pledge? { detail?.pledge ?? seed }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    if let p = pledge {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.targetTitle).font(.nuruDisplay(22)).foregroundStyle(Nuru.ink)
                            Text("\(money(p.paidTowardMinor, p.currency)) of \(money(p.commitmentMinor, p.currency))\(p.isMonthly ? " this month" : "") · \(money(p.progress.paidMinor, p.currency)) given in all")
                                .font(.nCaption).foregroundStyle(Nuru.ink600)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
    }

    private func load() async {
        loading = detail == nil
        error = nil
        do { detail = try await MemberAPI.pledge(pledgeId) }
        catch { if detail == nil { self.error = (error as? APIError)?.errorDescription ?? "We couldn't load this pledge." } }
        loading = false
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
                Text("PARTNERS").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0x9A7A2A))
                Text("Pledge payments").font(.fraunces(26, .semibold)).foregroundStyle(Nuru.navy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
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

/// PaymentRow's label without the button — for use inside a NavigationLink.
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

// MARK: - Standing

private struct PartnerStanding: View {
    let partnership: Partnership

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR STANDING")
                .font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)

            Text(headline)
                .font(.nuruDisplay(26)).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                if let t = partnership.tier, !t.name.isEmpty {
                    HStack(spacing: 5) {
                        Icon(.award, size: 12, color: Nuru.goldChipText)
                        Text(t.name).font(.inter(11, .bold)).foregroundStyle(Nuru.goldChipText)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Nuru.goldChipBg, in: Capsule())
                }
                if partnership.membership?.status == "paused" {
                    Text("Paused").font(.inter(11, .bold)).foregroundStyle(Nuru.ink600)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Nuru.mutedBg, in: Capsule())
                }
            }

            if partnership.kept > 0 {
                HStack(spacing: 8) {
                    Text("\(partnership.kept)")
                        .font(.nuruDisplay(30)).foregroundStyle(Nuru.gold)
                    // "collected", never "kept" — the word carries the honesty
                    // rule the server enforces.
                    Text(partnership.kept == 1 ? "gift collected" : "gifts collected")
                        .font(.nBody).foregroundStyle(Nuru.ink600)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Nuru.gold.opacity(0.28), lineWidth: 1))
    }

    private var headline: String {
        let iso = partnership.membership?.joinedAt ?? partnership.since
        guard let iso, let month = Self.monthYear(iso) else {
            return "You are a partner of this church."
        }
        return "You have partnered since \(month)."
    }

    static func monthYear(_ iso: String) -> String? {
        guard let d = PartnerFormat.date(iso) ?? giveParseDate(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Trouble (only when there is some)

private struct PartnerTrouble: View {
    let trouble: Partnership.Trouble
    let resuming: Bool
    let onResume: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(trouble.paused ? "Your giving is paused" : "One gift didn't go through")
                .font(.nHeading).foregroundStyle(Nuru.ink)
            Text(message)
                .font(.nBody).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)

            if trouble.paused, let onResume {
                Button(action: onResume) {
                    HStack(spacing: 8) {
                        if resuming { ProgressView().tint(.white) }
                        Text(resuming ? "Starting again…" : "Start it again")
                            .font(.nLabel)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .disabled(resuming)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Plain, and never alarming. Nothing is owed, and we say so first.
    private var message: String {
        if trouble.paused {
            return "We tried a few times and couldn't collect it, so we stopped trying rather than keep charging you. Nothing is owed. Starting again picks up from your next gift — it will not collect the one that was missed."
        }
        return "We couldn't collect your last gift. We'll try again shortly, and nothing is owed in the meantime."
    }
}

// MARK: - Rhythm (a schedule without a pledge — pre-programme partners)

private struct PartnerRhythm: View {
    let rhythm: Partnership.Rhythm
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR RHYTHM")
                .font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(amount).font(.nuruDisplay(22)).foregroundStyle(Nuru.ink)
                Text(rhythm.frequency == "weekly" ? "each week" : "each month")
                    .font(.nBody).foregroundStyle(Nuru.ink600)
            }
            PartnerRow(label: "Method", value: givingMethodName(rhythm.method))
            PartnerRow(label: "Fund", value: rhythm.fund.capitalized)
            PartnerRow(label: "Next gift", value: nextGift)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var amount: String {
        "\(currency) \(PartnerFormat.grouped(rhythm.amountMinor / 100))"
    }
    // Paused schedules carry no next date, and we say the true thing rather
    // than showing a stale one.
    private var nextGift: String {
        guard let next = rhythm.nextRunAt, let d = PartnerFormat.date(next) else {
            return "Paused"
        }
        let f = DateFormatter(); f.dateFormat = "d MMMM"
        return f.string(from: d)
    }
}

private struct PartnerRow: View {
    let label: String, value: String
    var body: some View {
        HStack {
            Text(label).font(.nBody).foregroundStyle(Nuru.ink600)
            Spacer(minLength: 12)
            Text(value).font(.nBody).foregroundStyle(Nuru.ink)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - The season (church-wide, never attributed)

private struct PartnerSeason: View {
    let season: Partnership.Season

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SINCE YOU BEGAN")
                .font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)

            // The framing IS the honesty. "Across the church" is doing real
            // work in this sentence — remove it and the page starts claiming
            // something we cannot prove.
            Text("Across the church, in the season you have been partnering:")
                .font(.nBody).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                if season.levelsCompleted > 0 {
                    PartnerCount(n: season.levelsCompleted,
                                 one: "disciple finished a level",
                                 many: "disciples finished a level")
                }
                if season.modulesCompleted > 0 {
                    PartnerCount(n: season.modulesCompleted,
                                 one: "module completed", many: "modules completed")
                }
                if season.plansFinished > 0 {
                    PartnerCount(n: season.plansFinished,
                                 one: "reading plan finished", many: "reading plans finished")
                }
                if season.levelsCompleted == 0 && season.modulesCompleted == 0
                    && season.plansFinished == 0 {
                    Text("It is early days. This will fill as the church walks on.")
                        .font(.nBody).foregroundStyle(Nuru.ink400)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PartnerCount: View {
    let n: Int, one: String, many: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.nuruDisplay(24)).foregroundStyle(Nuru.gold)
                .frame(minWidth: 44, alignment: .leading)
            Text(n == 1 ? one : many)
                .font(.nBody).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
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
