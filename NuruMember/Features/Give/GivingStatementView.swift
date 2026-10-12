// Giving statement — the native port of the Figma GivingStatement page. A navy
// masthead with the period total, a This year / Last year selector, fund-by-fund
// totals with a ruled grand total, and the day-grouped gift history (fund icon,
// time · method, provider ref, status chip). Read-only over GET /giving/history;
// tapping a gift opens its full receipt. Money stays in integer minor units
// end-to-end.
//
// GIVING CYCLE 2 (2026-09-28): money is per currency everywhere on the page —
// the header reads the server's statement (`totals[]`, split into gifts and
// pledge money by `by_pledge`) as "KSh 3,500" + "+ US$ 20.00", BY FUND has a
// row per fund per currency, and nothing adds shillings to dollars. The year
// is the church's (Nairobi) year, as the server counts it. The download is the
// SERVER's PDF for the chosen year (GET /giving/statement.pdf?year=) — it used
// to be drawn here, from local sums, and could disagree with the office.
//
// Statement v2 (PARTNERS_PROGRAMME §3d, owner-decided 2026-09-25): a giving
// statement is a financial record — it must reconcile with the member's bank
// and the church ledger — so pledge money is never EXCLUDED, it is SEPARATED.
// Whenever the period has ANY pledge-tied row (settled or not), BY FUND and
// the day list show gifts only and every pledge-tied row sits in one
// collapsed PARTNER PLEDGES card with a link to the Partners statement — so
// an unsettled pledge payment never drops out of both. When there is settled
// pledge money (Y > 0) the hero leads with Gifts X and says "Partner pledges
// Y · Total X+Y", and BY FUND's foot reads TOTAL GIFTS. (The server's PDF
// applies the same split: gifts by fund, a PARTNER PLEDGES section.)
import SwiftUI
import UIKit

private let settledStatuses: Set<String> = ["succeeded", "settled", "completed"]

/// Which stack the giving statement was pushed on. `.partners` links with
/// the Partners stack's own PartnersRoute (sharing its model); anywhere else
/// the page links with StatementRoute, which it registers itself.
enum GivingStatementHost { case give, partners }

/// The giving statement's own pushed page, registered by the page itself
/// (the receipt's ReceiptRoute idiom) so its "Partners statement" link works
/// on any stack — Give, a receipt on either stack, the gift ceremony's sheet.
enum StatementRoute: Hashable { case partnersStatement }

@MainActor
final class GivingStatementViewModel: ObservableObject {
    @Published var history: [GivingRecord] = []
    @Published var loading = true
    @Published var error: String?
    /// The server's statement per year (GET /giving/statements?year=, Giving
    /// Cycle 2): its per-currency `totals[]` and the gifts / pledges split are
    /// what the header shows — the same numbers as the PDF and the office.
    @Published var statements: [Int: GivingStatements] = [:]

    func load() async {
        loading = true; error = nil
        do { history = try await MemberAPI.givingHistory() }
        catch { self.error = NuruStateCopy.failure(error).sentence }   // §4, never raw text
        loading = false
    }

    /// The server's figures for one year. A failure keeps what is there (the
    /// header then sums the history itself, per currency).
    func loadStatement(_ year: Int) async {
        if let s = try? await MemberAPI.givingStatements(year: year), s.year == year { statements[year] = s }
    }

    /// Records inside one church (Nairobi) year — the calendar the server's
    /// totals and the PDF count by — newest first by the actual instant; a
    /// row whose timestamp cannot be read trails rather than sorting on its
    /// raw string.
    func records(in year: Int) -> [GivingRecord] {
        // The year by created_at (the statements' rule); the order, the day
        // and the time by the one time a gift shows (GiftTime, the walk's B7).
        history.filter { GiveCalendar.year(of: $0.createdAt) == year }
            .map { ($0, giveParseDate($0.shownAt)) }
            .sorted { a, b in
                switch (a.1, b.1) {
                case let (x?, y?): return x != y ? x > y : a.0.shownAt > b.0.shownAt
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.0.shownAt > b.0.shownAt
                }
            }
            .map(\.0)
    }

    func settledCount(in year: Int) -> Int { settledCount(records(in: year)) }

    // Statement v2 — gifts and partner pledges, separated (never excluded).

    /// Gifts: the year's records NOT tied to a pledge.
    func gifts(in year: Int) -> [GivingRecord] { records(in: year).filter { $0.pledgeId == nil } }

    /// Partner pledges: the year's records carrying a `pledge_id`.
    func pledgeRecords(in year: Int) -> [GivingRecord] { records(in: year).filter { $0.pledgeId != nil } }

    /// Settled money PER CURRENCY (Giving Cycle 2) — shillings and dollars
    /// are never one sum.
    func settledTotals(_ rs: [GivingRecord]) -> [CurrencyTotal] { GiveMoney.totals(of: rs) }

    func settledCount(_ rs: [GivingRecord]) -> Int {
        rs.filter { settledStatuses.contains($0.status) }.count
    }

    /// Settled totals per fund AND currency (a fund given to in shillings and
    /// in dollars is two rows, as on the server's statement), in order of
    /// first appearance, newest first.
    func fundTotals(of records: [GivingRecord]) -> [FundTotal] {
        var order: [String] = []
        var totals: [String: FundTotal] = [:]
        for r in records where settledStatuses.contains(r.status) {
            let cur = r.currency.uppercased()
            let key = "\(r.fund)|\(cur)"
            if totals[key] == nil { order.append(key); totals[key] = FundTotal(fund: r.fund, currency: cur, count: 0, totalMinor: 0) }
            totals[key]!.count += 1
            totals[key]!.totalMinor += r.amountMinor
        }
        return order.compactMap { totals[$0] }
    }

    /// One BY FUND row: a fund's settled gifts in one currency.
    struct FundTotal: Hashable {
        let fund: String
        let currency: String
        var count: Int
        var totalMinor: Int
        var id: String { "\(fund)|\(currency)" }
    }

    /// The given records grouped by the member's LOCAL calendar day, in the
    /// input order (newest first). Rows whose timestamp cannot be read keep
    /// their money in one trailing "—" group.
    func groups(of records: [GivingRecord]) -> [(key: String, label: String, records: [GivingRecord])] {
        let cal = Calendar.current
        let undated = "undated"
        var order: [String] = []
        var map: [String: [GivingRecord]] = [:]
        for r in records {
            let key: String
            if let d = giveParseDate(r.shownAt) {
                let c = cal.dateComponents([.year, .month, .day], from: d)
                key = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            } else {
                key = undated
            }
            if map[key] == nil { map[key] = []; order.append(key) }
            map[key]?.append(r)
        }
        if let i = order.firstIndex(of: undated) { order.append(order.remove(at: i)) }
        return order.map { (key: $0, label: $0 == undated ? "—" : dayLabel($0), records: map[$0] ?? []) }
    }

    /// The header's figures for `year`, per currency: the server's statement
    /// when it has answered — `totals[]`, split into gifts and pledge money by
    /// `by_pledge` — else the history summed the same way. Both come from ONE
    /// source, so gifts + pledges = total for every currency.
    func figures(in year: Int) -> StatementFigures {
        if let s = statements[year] {
            return StatementFigures(total: s.totals, gifts: s.giftTotals, pledges: s.pledgeTotals)
        }
        return StatementFigures(total: settledTotals(records(in: year)),
                                gifts: settledTotals(gifts(in: year)),
                                pledges: settledTotals(pledgeRecords(in: year)))
    }

    struct StatementFigures: Equatable {
        let total: [CurrencyTotal]
        let gifts: [CurrencyTotal]
        let pledges: [CurrencyTotal]
        /// Settled pledge money: the header splits Gifts / Partner pledges.
        var hasPledgeMoney: Bool { pledges.contains { $0.totalMinor != 0 } }
    }

    private func dayLabel(_ ymd: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: ymd) else { return ymd }
        return NuruDates.day(d)
    }
}

// MARK: - Fund meta (one look, as the Give tab's funds: §8.1 rules 1, 7)

private struct FundMeta { let icon: Lucide; let tint: UInt32; let fg: UInt32 }
private func fundMeta(_ code: String) -> FundMeta {
    switch code.lowercased() {
    case "tithe":        return FundMeta(icon: .percent,   tint: Nuru.tileTint, fg: Nuru.tileIcon)
    case "offering":     return FundMeta(icon: .handHeart, tint: Nuru.tileTint, fg: Nuru.tileIcon)
    case "gift":         return FundMeta(icon: .gift,      tint: Nuru.tileTint, fg: Nuru.tileIcon)
    case "mission":      return FundMeta(icon: .globe,     tint: Nuru.tileTint, fg: Nuru.tileIcon)
    case "discipleship": return FundMeta(icon: .bookOpen,  tint: Nuru.tileTint, fg: Nuru.tileIcon)
    default:             return FundMeta(icon: .gift,      tint: Nuru.tileTint, fg: Nuru.tileIcon)
    }
}

// MARK: - Statement

struct GivingStatementView: View {
    /// The stack this page was pushed on — `.partners` from the Partners
    /// stack (its link then shares the Partners tab's model); everything else
    /// (the Give stack, a receipt's "View statement", the ceremony sheet) is
    /// `.give`, whose link uses the StatementRoute this page registers.
    var host: GivingStatementHost = .give

    @StateObject private var vm = GivingStatementViewModel()
    @Environment(\.dismiss) private var dismiss
    /// The church (Nairobi) year on screen — the calendar the server counts by.
    @State private var year = GiveCalendar.currentYear()
    @State private var shareFile: ShareFile?
    /// The server's PDF is on its way (the download button spins).
    @State private var downloading = false
    /// Why the PDF could not be had — one quiet line, never silent.
    @State private var downloadError: String?
    /// The PARTNER PLEDGES card starts collapsed.
    @State private var pledgesOpen = false

    private var thisYear: Int { GiveCalendar.currentYear() }
    private var periodLabel: String { year == thisYear ? "this year" : "in \(year)" }

    /// The header's per-currency figures — the server's when it has answered.
    private var figures: GivingStatementViewModel.StatementFigures { vm.figures(in: year) }
    /// Settled pledge money: the hero splits and BY FUND's foot reads TOTAL GIFTS.
    private var hasPledgeMoney: Bool { figures.hasPledgeMoney }
    /// ANY pledge-tied row, settled or not: the rows are separated and the
    /// PARTNER PLEDGES card shows. With none the page is the pre-v2 page.
    private var hasPledgeRows: Bool { !vm.pledgeRecords(in: year).isEmpty }
    /// What BY FUND and the day list are built from — gifts only when split.
    private var listed: [GivingRecord] { hasPledgeRows ? vm.gifts(in: year) : vm.records(in: year) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    periodSelector
                    if let downloadError {
                        Text(downloadError)
                            .font(.inter(11)).foregroundStyle(Color(hex: 0xDC2626))
                            .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                    if vm.loading && vm.history.isEmpty {
                        loadingSkeleton
                    } else if let e = vm.error, vm.history.isEmpty {
                        VStack(spacing: Nuru.S.sm) {
                            Text(e).font(.nBody).foregroundStyle(Nuru.muted)
                            Button {
                                Haptics.tap()
                                Task { await vm.load() }
                            } label: {
                                Text("Try again").font(.inter(11, .semibold)).foregroundStyle(.white)
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(Nuru.navy, in: Capsule())
                            }
                            .buttonStyle(.pressable)
                        }
                        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else if vm.history.isEmpty {
                        emptyState
                    } else {
                        if !listed.isEmpty { fundTotalsCard.gentleEntrance() }
                        historyList
                        if hasPledgeRows { partnerPledgesCard }
                        if !listed.isEmpty {
                            Text("Tap a gift to open its receipt.")
                                .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.top, 2)
                        }
                    }
                }
                .padding(Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .refreshable { await vm.load(); await vm.loadStatement(year) }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.history.isEmpty { await vm.load() } }
        // The server's figures for the year on screen (Giving Cycle 2).
        .task(id: year) { await vm.loadStatement(year) }
        .sheet(item: $shareFile) { f in ActivityShareSheet(url: f.url) }
        // Registered here, not on each stack, so the link works wherever
        // this page is pushed. A fresh PartnersModel, owned by the host.
        .navigationDestination(for: StatementRoute.self) { _ in PartnersStatementHost() }
    }

    // MARK: Loading / empty states

    /// Shimmering placeholder in the statement's silhouette (fund card + rows).
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            VStack(spacing: 14) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: 10) {
                        Circle().fill(Nuru.surface).frame(width: 32, height: 32).nuruShimmer()
                        RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(height: 12).nuruShimmer()
                    }
                }
            }
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Nuru.white).frame(height: 68).nuruShimmer()
        }
    }

    private var emptyState: some View {
        VStack(spacing: Nuru.S.sm) {
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.1)).frame(width: 48, height: 48)
                Icon(.handHeart, size: 22, color: Nuru.gold)
            }
            Text("No gifts yet").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
            Text("When you give, your full record and receipts live here.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
    }

    // MARK: Navy masthead (per Figma)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                circleButton(.arrowLeft) { dismiss() }
                Spacer()
                Text("GIVING STATEMENT")
                    .font(.inter(11, .bold)).kerning(2.2).foregroundStyle(Nuru.gold)
                Spacer()
                circleButton(.download, busy: downloading) {
                    Haptics.action()
                    download()
                }
                .disabled(downloading)
                .accessibilityLabel("Download the statement PDF")
            }
            VStack(alignment: .leading, spacing: 2) {
                // Per currency (Giving Cycle 2): the shilling figure is the big
                // number, any other currency rides under it ("+ US$ 20.00") —
                // never one sum. The server's statement when it has answered.
                let f = figures
                if listed.isEmpty && !hasPledgeMoney {
                    // Nothing in the period: no "Total given KSh 0" — the page
                    // says "No gifts …" once, below (§7.4 #9; the walk's E14
                    // found KSh 0 said four ways).
                    EmptyView()
                } else if hasPledgeMoney {
                    // Gifts X is the big number; the pledges and the grand
                    // total sit under it, so X + Y = Total is on screen.
                    let gifts = GiveMoney.headline(f.gifts)
                    Text("Gifts").font(.inter(11)).foregroundStyle(.white.opacity(0.6))
                    Text(gifts.main)
                        .font(.fraunces(28, .semibold)).kerning(-1).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let rest = gifts.rest {
                        Text(rest).font(.inter(12, .semibold)).foregroundStyle(.white.opacity(0.8))
                    }
                    Text("Partner pledges \(GiveMoney.line(f.pledges)) · Total \(GiveMoney.line(f.total))")
                        .font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 2)
                } else {
                    let total = GiveMoney.headline(f.total)
                    Text("Total given").font(.inter(11)).foregroundStyle(.white.opacity(0.6))
                    Text(total.main)
                        .font(.fraunces(28, .semibold)).kerning(-1).foregroundStyle(.white)
                        .lineLimit(1).minimumScaleFactor(0.6)
                    if let rest = total.rest {
                        Text(rest).font(.inter(12, .semibold)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                let n = vm.settledCount(listed)
                if n > 0 {   // no zero counts (§7.4 #9) — the page below says "No gifts …"
                    Text("\(n) gift\(n == 1 ? "" : "s") · \(periodLabel) · most recent first")
                        .font(.inter(11)).foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.top, Nuru.S.base)
        }
        .padding(.horizontal, Nuru.S.screen).padding(.top, 54).padding(.bottom, Nuru.S.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                // Calm, realistic generosity image under a deep navy scrim — sets
                // the giving tone without competing with the white figures.
                if let u = URL(string: "https://images.unsplash.com/photo-1532629345422-7515f3d16bb6?auto=format&fit=crop&w=1080&q=80") {
                    // Color.clear owns the layout size; the fill image lives in
                    // an overlay so its oversized "fill" size can never inflate
                    // the header ZStack or bleed past the rounded clip (the
                    // radio-screen edge-spill bug family).
                    Color.clear
                        .overlay {
                            CachedAsyncImage(url: u) { p in
                                (p.image ?? Image(systemName: "photo")).resizable().scaledToFill()
                            }
                        }
                        .clipped()
                        .opacity(0.45)
                }
                LinearGradient(colors: [Nuru.navy.opacity(0.88), Color(hex: 0x06182C).opacity(0.94)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Nuru.gold.opacity(0.33), .clear], center: .topTrailing, startRadius: 0, endRadius: 200)
                    .blur(radius: 30)
            }
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
            .ignoresSafeArea(edges: .top)
        )
    }

    private func circleButton(_ icon: Lucide, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(0.10)).frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                else { Icon(icon, size: 18, color: .white) }
            }
        }.buttonStyle(.pressable)
    }

    // MARK: Period selector (This year / Last year)

    /// Full pills (§8.1 rule 6; final walk #38): selected navy, unselected
    /// white with a hairline — not the grey track.
    private var periodSelector: some View {
        HStack(spacing: 8) {
            segment("This year", thisYear)
            segment("Last year", thisYear - 1)
        }
    }

    private func segment(_ label: String, _ y: Int) -> some View {
        let on = year == y
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { year = y }
        } label: {
            Text(label)
                .font(.inter(13, .semibold))
                .foregroundStyle(on ? Color.white : Nuru.ink600)
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                .overlay(Capsule().stroke(on ? Color.clear : Nuru.border, lineWidth: 1))
        }.buttonStyle(.plain)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }

    // MARK: Fund-by-fund totals + ruled grand total

    private var fundTotalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BY FUND")
                .font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                .padding(.bottom, 4)
            let totals = vm.fundTotals(of: listed)
            if totals.isEmpty {
                Text("No settled gifts \(periodLabel).")
                    .font(.nCardBody).foregroundStyle(Color(hex: 0x5B6472))
                    .padding(.vertical, Nuru.S.sm)
            } else {
                ForEach(Array(totals.enumerated()), id: \.element.id) { i, t in
                    fundRow(t)
                    if i != totals.count - 1 { Divider().overlay(Nuru.border.opacity(0.6)) }
                }
            }
            // The card's total foots with its rows: gifts only when split, and
            // per currency — "KSh 3,500 + US$ 20.00", never one sum.
            HStack(alignment: .firstTextBaseline) {
                Text(hasPledgeMoney ? "TOTAL GIFTS" : "TOTAL GIVEN").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.navy)
                Spacer()
                Text(GiveMoney.line(vm.settledTotals(listed)))
                    .font(.fraunces(18, .bold)).foregroundStyle(Nuru.gold)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2).minimumScaleFactor(0.7)
            }
            .padding(.top, 14)   // spacing separates the grand total — no ruled line
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    /// One fund in one currency — its amount in that currency.
    private func fundRow(_ t: GivingStatementViewModel.FundTotal) -> some View {
        let meta = fundMeta(t.fund)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: meta.tint)).frame(width: 32, height: 32)
                Icon(meta.icon, size: 14, color: Color(hex: meta.fg))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(t.fund.capitalized).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text("\(t.count) gift\(t.count == 1 ? "" : "s")")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
            }
            Spacer()
            Text(money(t.totalMinor, t.currency)).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
        }
        .padding(.vertical, 8)
    }

    // MARK: History grouped by day (per Figma)

    @ViewBuilder
    private var historyList: some View {
        if listed.isEmpty {
            // The empty period in §4's state card (final walk C16's class) —
            // not a bare line under the header.
            NuruStateView(state: .empty(title: "No gifts \(periodLabel)"))
                .padding(.top, Nuru.S.sm)
        } else {
            ForEach(Array(vm.groups(of: listed).enumerated()), id: \.element.key) { idx, group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label.uppercased())
                        .font(.inter(11, .bold)).kerning(1.1).foregroundStyle(Color(hex: 0xA8861C))
                    ForEach(group.records) { r in
                        NavigationLink(value: r) { giftCard(r) }.buttonStyle(.pressableSubtle)
                    }
                }
                .padding(.top, Nuru.S.sm)
                // Stagger fades out after the first few groups — long statements
                // shouldn't feel slower to arrive.
                .gentleEntrance(delay: 0.05 + Double(min(idx, 3)) * 0.05)
            }
        }
    }

    private func giftCard(_ g: GivingRecord) -> some View {
        let meta = fundMeta(g.fund)
        return HStack(spacing: Nuru.S.md) {
            ZStack {
                Circle().fill(Color(hex: meta.tint)).frame(width: 44, height: 44)
                Icon(meta.icon, size: 18, color: Color(hex: meta.fg))
            }
            VStack(alignment: .leading, spacing: 2) {
                // A gift is a content row (§8.1 rule 3: Fraunces 15 semibold;
                // final walk #38 — it was Inter).
                Text(g.fund.capitalized)
                    .font(.nRowTitle).foregroundStyle(Nuru.navy)
                Text("\(giveTime(g.shownAt)) · \(givingMethodName(g.method))")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                // A pledge payment says so — the complete record still tells
                // the member which gifts counted toward a pledge (the partners
                // statement lists only these). Absent on older servers.
                if let tag = pledgeTag(g) {
                    Text(tag)
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Nuru.goldChipBg, in: Capsule())
                        .lineLimit(1)
                }
                // "Named giving" (custom sheet, optional): the member's own
                // label for this gift, when set.
                if let name = g.accountName, !name.isEmpty {
                    Text("\u{201C}\(name)\u{201D}")
                        .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x5B6472))
                        .lineLimit(1)
                }
                // Show the M-Pesa SMS receipt code (UG3J29U3OL) once settled;
                // never the internal checkout id — hide the line if absent.
                if let ref = g.receiptCode, !ref.isEmpty {
                    Text("Ref \(ref)")
                        .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                        .lineLimit(1)
                }
                // A failed gift says why, in the server's words (Giving
                // Cycle 1): what happened, then what to do next.
                if g.status == "failed", let f = g.failure, !f.reason.isEmpty {
                    Text(f.reason)
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                    if !f.hint.isEmpty {
                        Text(f.hint)
                            .font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            Spacer(minLength: Nuru.S.sm)
            VStack(alignment: .trailing, spacing: 5) {
                Text(money(g.amountMinor, g.currency))
                    .font(.inter(14, .bold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                statusChip(g.status)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Borderless per the design direction — soft shadow + spacing separate
        // the gift cards; no hairline.
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .nuruShadow(0.6)
    }

    /// "Building pledge" — a title that already ends in the word is not
    /// doubled. A pledge payment whose title the server did not send reads
    /// "Partner pledge" (Android parity); a gift outside a pledge has no tag.
    private func pledgeTag(_ g: GivingRecord) -> String? {
        guard g.pledgeId != nil || g.pledgeTitle != nil else { return nil }
        guard let t = g.pledgeTitle?.trimmingCharacters(in: .whitespaces), !t.isEmpty else { return "Partner pledge" }
        return t.lowercased().hasSuffix("pledge") ? t : "\(t) pledge"
    }

    // MARK: Partner pledges — one collapsed card (any pledge-tied row)

    private var partnerPledgesCard: some View {
        let rows = vm.pledgeRecords(in: year)
        let n = vm.settledCount(rows)
        let unsettled = rows.count - n
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                Haptics.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { pledgesOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("PARTNER PLEDGES")
                            .font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                        // Y and N count the same (settled) rows; a row still
                        // processing or failed is listed inside, and said here.
                        // Y is per currency (Giving Cycle 2).
                        Text("\(GiveMoney.line(vm.settledTotals(rows))) · \(n) payment\(n == 1 ? "" : "s")\(unsettled > 0 ? " · \(unsettled) not settled" : "")")
                            .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    Icon(pledgesOpen ? .chevronUp : .chevronDown, size: 18, color: Nuru.navy)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(pledgesOpen ? "Expanded" : "Collapsed")
            .accessibilityHint(pledgesOpen ? "Hides the pledge payments" : "Shows the pledge payments")

            if pledgesOpen {
                ForEach(vm.groups(of: rows), id: \.key) { group in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(group.label.uppercased())
                            .font(.inter(11, .bold)).kerning(1.1).foregroundStyle(Color(hex: 0xA8861C))
                        ForEach(group.records) { r in
                            NavigationLink(value: r) { giftCard(r) }.buttonStyle(.pressableSubtle)
                        }
                    }
                    .padding(.top, 14)
                }
                partnersStatementLink
                    .padding(.top, 14)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .gentleEntrance(delay: 0.1)
    }

    /// Pushes the Partners statement on whichever stack this page is on.
    @ViewBuilder private var partnersStatementLink: some View {
        switch host {
        case .partners:
            NavigationLink(value: PartnersRoute.partnersStatement) { partnersStatementLabel }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        case .give:
            NavigationLink(value: StatementRoute.partnersStatement) { partnersStatementLabel }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        }
    }

    private var partnersStatementLabel: some View {
        HStack(spacing: 4) {
            Text("Partners statement").font(.inter(13, .semibold))
            Icon(.arrowRight, size: 14, color: Nuru.gold)
        }
        .foregroundStyle(Nuru.gold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: Download — the server's PDF (Giving Cycle 2)

    /// The giving statement PDF for the year on screen, as the SERVER renders
    /// it (GET /giving/statement.pdf?year=): Nairobi dates, per-currency
    /// totals, the same numbers the office sees — it used to be drawn on the
    /// phone from local sums. Fetched over the bearer client into a temp file
    /// and handed to the share sheet; a 200 that is not a PDF is refused, and
    /// every failure is one quiet line under the year switch.
    private func download() {
        guard !downloading else { return }
        downloading = true
        withAnimation { downloadError = nil }
        let year = self.year
        Task {
            defer { downloading = false }
            do {
                let data = try await MemberAPI.givingStatementPdf(year: year)
                guard data.starts(with: Array("%PDF".utf8)) else {
                    throw APIError.decoding("statement.pdf did not return a PDF")
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("nuru-giving-statement-\(year).pdf")
                try data.write(to: url, options: .atomic)
                Haptics.success()
                shareFile = ShareFile(url: url)
            } catch {
                Haptics.error()
                withAnimation { downloadError = Self.downloadMessage(for: error) }
            }
        }
    }

    /// Offline only when the phone has no network (§4) — a timeout while it
    /// has one was ours, and the PDF just isn't available right now.
    private static func downloadMessage(for error: Error) -> String {
        if NuruStateCopy.failure(error).cause == .offline {
            return "You're offline — the PDF needs a connection."
        }
        return "The PDF isn't available right now. The statement below is still complete."
    }
}

private struct ShareFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Shared giving atoms (used by the receipt screen too)

func ksh(_ n: Int) -> String { "KSh \(n.formatted(.number.grouping(.automatic)))" }

/// Currency-AWARE amount from minor units — PayPal gifts settle in USD
/// server-side; formatting everything as "KSh" printed the wrong symbol on
/// USD gifts while the Currency detail row said USD. Mirrors Android money().
/// One formatter for every Give surface (Giving Cycle 2): "KSh 1,234",
/// "US$ 20.00" — shilling cents are shown when there are any, never dropped.
func money(_ minor: Int, _ currency: String?) -> String { GiveMoney.format(minor, currency) }

@ViewBuilder
func statusChip(_ status: String) -> some View {
    let (bg, fg, label): (Color, Color, String) = {
        switch status {
        // A member's word, not the server's status (§8.1 rule 8; final walk
        // #38: "Succeeded").
        case "succeeded", "settled", "completed": return (Nuru.successBg, Nuru.successText, "Received")
        case "processing", "pending", "initiated": return (Nuru.goldChipBg, Nuru.goldChipText, "Processing")
        case "requires_action": return (Nuru.goldChipBg, Nuru.goldChipText, "Waiting for you")
        case "failed", "cancelled", "canceled", "expired": return (Nuru.danger.opacity(0.12), Nuru.danger, "Failed")
        case "refunded": return (Nuru.mutedBg, Nuru.ink600, "Refunded")
        default: return (Nuru.mutedBg, Nuru.ink600, status.replacingOccurrences(of: "_", with: " ").capitalized)
        }
    }()
    Text(label).font(.nMicro).foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3).background(bg, in: Capsule())
}
