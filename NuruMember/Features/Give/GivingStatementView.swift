// Giving statement — the native port of the Figma GivingStatement page. A navy
// masthead with the period total, a This year / Last year selector, fund-by-fund
// totals with a ruled grand total, and the day-grouped gift history (fund icon,
// time · method, provider ref, status chip). Read-only over GET /giving/history;
// tapping a gift opens its full receipt. The download affordance renders a
// one-page branded PDF with UIGraphicsPDFRenderer (no dependencies) and hands it
// to the share sheet. Money stays in integer minor units end-to-end.
//
// Statement v2 (PARTNERS_PROGRAMME §3d, owner-decided 2026-09-25): a giving
// statement is a financial record — it must reconcile with the member's bank
// and the church ledger — so pledge money is never EXCLUDED, it is SEPARATED.
// Whenever the period has ANY pledge-tied row (settled or not), BY FUND and
// the day list show gifts only and every pledge-tied row sits in one
// collapsed PARTNER PLEDGES card with a link to the Partners statement — so
// an unsettled pledge payment never drops out of both. When there is settled
// pledge money (Y > 0) the hero leads with Gifts X and says "Partner pledges
// Y · Total X+Y", and BY FUND's foot reads TOTAL GIFTS. This PDF is drawn
// on the phone (iOS never fetched /giving/statement.pdf), so it applies the
// same split itself: gifts by fund, a PARTNER PLEDGES section by pledge, and
// a grand total that foots to the unit.
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

    func load() async {
        loading = true; error = nil
        do { history = try await MemberAPI.givingHistory() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your statement." }
        loading = false
    }

    /// Records inside one calendar year, newest first by the actual instant;
    /// a row whose timestamp cannot be read trails rather than sorting on
    /// its raw string.
    func records(in year: Int) -> [GivingRecord] {
        history.filter { $0.createdAt.hasPrefix(String(year)) }
            .map { ($0, giveParseDate($0.createdAt)) }
            .sorted { a, b in
                switch (a.1, b.1) {
                case let (x?, y?): return x != y ? x > y : a.0.createdAt > b.0.createdAt
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return a.0.createdAt > b.0.createdAt
                }
            }
            .map(\.0)
    }

    func totalMinor(in year: Int) -> Int { settledMinor(records(in: year)) }

    func settledCount(in year: Int) -> Int { settledCount(records(in: year)) }

    // Statement v2 — gifts and partner pledges, separated (never excluded).

    /// Gifts: the year's records NOT tied to a pledge.
    func gifts(in year: Int) -> [GivingRecord] { records(in: year).filter { $0.pledgeId == nil } }

    /// Partner pledges: the year's records carrying a `pledge_id`.
    func pledgeRecords(in year: Int) -> [GivingRecord] { records(in: year).filter { $0.pledgeId != nil } }

    func settledMinor(_ rs: [GivingRecord]) -> Int {
        rs.filter { settledStatuses.contains($0.status) }.reduce(0) { $0 + $1.amountMinor }
    }

    func settledCount(_ rs: [GivingRecord]) -> Int {
        rs.filter { settledStatuses.contains($0.status) }.count
    }

    /// Settled totals per fund (order of first appearance, newest first).
    func fundTotals(in year: Int) -> [(fund: String, count: Int, totalMinor: Int)] {
        fundTotals(of: records(in: year))
    }

    /// Settled totals per fund over the given records (same order rule).
    func fundTotals(of records: [GivingRecord]) -> [(fund: String, count: Int, totalMinor: Int)] {
        var order: [String] = []
        var totals: [String: (count: Int, minor: Int)] = [:]
        for r in records where settledStatuses.contains(r.status) {
            if totals[r.fund] == nil { order.append(r.fund); totals[r.fund] = (0, 0) }
            totals[r.fund]!.count += 1
            totals[r.fund]!.minor += r.amountMinor
        }
        return order.map { (fund: $0, count: totals[$0]!.count, totalMinor: totals[$0]!.minor) }
    }

    /// Records grouped by calendar day, newest first.
    func groups(in year: Int) -> [(key: String, label: String, records: [GivingRecord])] {
        groups(of: records(in: year))
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
            if let d = giveParseDate(r.createdAt) {
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

    /// The period's settled pledge money by pledge (order of first
    /// appearance, newest first), for the PDF's PARTNER PLEDGES section. A
    /// row without a title reads "Partner pledge".
    func pledgeTotals(in year: Int) -> [(title: String, count: Int, totalMinor: Int)] {
        var order: [String] = []
        var rows: [String: (title: String, count: Int, minor: Int)] = [:]
        for r in pledgeRecords(in: year) where settledStatuses.contains(r.status) {
            let key = r.pledgeId ?? ""
            let t = r.pledgeTitle?.trimmingCharacters(in: .whitespaces) ?? ""
            if rows[key] == nil { order.append(key); rows[key] = ("", 0, 0) }
            if rows[key]!.title.isEmpty && !t.isEmpty { rows[key]!.title = t }
            rows[key]!.count += 1
            rows[key]!.minor += r.amountMinor
        }
        return order.map { k in
            let r = rows[k]!
            let base = r.title.isEmpty ? "Partner" : r.title
            return (title: base.lowercased().hasSuffix("pledge") ? base : "\(base) pledge", count: r.count, totalMinor: r.minor)
        }
    }

    private func dayLabel(_ ymd: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM-dd"
        guard let d = inF.date(from: ymd) else { return ymd }
        let out = DateFormatter(); out.dateFormat = "EEE, d MMM yyyy"
        return out.string(from: d)
    }
}

// MARK: - Fund meta (exact Figma palette; mirrors the Give tab funds)

private struct FundMeta { let icon: Lucide; let tint: UInt32; let fg: UInt32 }
private func fundMeta(_ code: String) -> FundMeta {
    switch code.lowercased() {
    case "tithe":        return FundMeta(icon: .percent,   tint: 0xFFF4DA, fg: 0xC89B3C)
    case "offering":     return FundMeta(icon: .handHeart, tint: 0xFEE2E2, fg: 0xDC2626)
    case "gift":         return FundMeta(icon: .gift,      tint: 0xF3E8FF, fg: 0xA855F7)
    case "mission":      return FundMeta(icon: .globe,     tint: 0xE0F2FE, fg: 0x0EA5E9)
    case "discipleship": return FundMeta(icon: .bookOpen,  tint: 0xDCFCE7, fg: 0x16A34A)
    default:             return FundMeta(icon: .gift,      tint: 0xFFF4DA, fg: 0xC89B3C)
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
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var shareFile: ShareFile?
    /// The PARTNER PLEDGES card starts collapsed.
    @State private var pledgesOpen = false

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }
    private var periodLabel: String { year == thisYear ? "this year" : "in \(year)" }

    /// Y — settled partner-pledge money in the period.
    private var pledgeMinor: Int { vm.settledMinor(vm.pledgeRecords(in: year)) }
    /// Settled pledge money: the hero splits and BY FUND's foot reads TOTAL GIFTS.
    private var hasPledgeMoney: Bool { pledgeMinor > 0 }
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
                        fundTotalsCard.gentleEntrance()
                        historyList
                        if hasPledgeRows { partnerPledgesCard }
                        Text("Statement reflects records held under Finance · receipts emailed per gift.")
                            .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 2)
                    }
                }
                .padding(Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .refreshable { await vm.load() }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.history.isEmpty { await vm.load() } }
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
                Icon(.handHeart, size: 20, color: Nuru.gold)
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
                    .font(.inter(10, .bold)).kerning(2.2).foregroundStyle(Nuru.gold)
                Spacer()
                circleButton(.download) {
                    Haptics.action()
                    share()
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                if hasPledgeMoney {
                    // Gifts X is the big number; the pledges and the grand
                    // total sit under it, so X + Y = Total is on screen.
                    let giftsMinor = vm.settledMinor(listed)
                    Text("Gifts").font(.inter(11)).foregroundStyle(.white.opacity(0.6))
                    Text(ksh(giftsMinor / 100))
                        .font(.fraunces(34, .semibold)).kerning(-1).foregroundStyle(.white)
                    Text("Partner pledges \(ksh(pledgeMinor / 100)) · Total \(ksh((giftsMinor + pledgeMinor) / 100))")
                        .font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, 2)
                } else {
                    Text("Total given").font(.inter(11)).foregroundStyle(.white.opacity(0.6))
                    Text(ksh(vm.totalMinor(in: year) / 100))
                        .font(.fraunces(34, .semibold)).kerning(-1).foregroundStyle(.white)
                }
                let n = vm.settledCount(listed)
                Text("\(n) gift\(n == 1 ? "" : "s") · \(periodLabel) · most recent first")
                    .font(.inter(11)).foregroundStyle(.white.opacity(0.55))
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

    private func circleButton(_ icon: Lucide, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white.opacity(0.10)).frame(width: 40, height: 40)
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                Icon(icon, size: 17, color: .white)
            }
        }.buttonStyle(.pressable)
    }

    // MARK: Period selector (This year / Last year)

    private var periodSelector: some View {
        HStack(spacing: 4) {
            segment("This year", thisYear)
            segment("Last year", thisYear - 1)
        }
        .padding(4)
        .background(Color(hex: 0x0A2540, alpha: 0.06),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                .foregroundStyle(on ? Nuru.navy : Color(hex: 0x5B6472))
                .frame(maxWidth: .infinity).frame(height: 38)
                .background(on ? Nuru.white : .clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .nuruShadow(on ? 0.6 : 0)
        }.buttonStyle(.plain)
    }

    // MARK: Fund-by-fund totals + ruled grand total

    private var fundTotalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("BY FUND")
                .font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                .padding(.bottom, 4)
            let totals = vm.fundTotals(of: listed)
            if totals.isEmpty {
                Text("No settled gifts \(periodLabel).")
                    .font(.nCardBody).foregroundStyle(Color(hex: 0x5B6472))
                    .padding(.vertical, Nuru.S.sm)
            } else {
                ForEach(Array(totals.enumerated()), id: \.element.fund) { i, t in
                    fundRow(t)
                    if i != totals.count - 1 { Divider().overlay(Nuru.border.opacity(0.6)) }
                }
            }
            // The card's total foots with its rows: gifts only when split.
            HStack {
                Text(hasPledgeMoney ? "TOTAL GIFTS" : "TOTAL GIVEN").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.navy)
                Spacer()
                Text(ksh(vm.settledMinor(listed) / 100))
                    .font(.fraunces(18, .bold)).foregroundStyle(Nuru.gold)
            }
            .padding(.top, 14)   // spacing separates the grand total — no ruled line
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func fundRow(_ t: (fund: String, count: Int, totalMinor: Int)) -> some View {
        let meta = fundMeta(t.fund)
        return HStack(spacing: 10) {
            ZStack {
                Circle().fill(Color(hex: meta.tint)).frame(width: 32, height: 32)
                Icon(meta.icon, size: 15, color: Color(hex: meta.fg))
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(t.fund.capitalized).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text("\(t.count) gift\(t.count == 1 ? "" : "s")")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
            }
            Spacer()
            Text(ksh(t.totalMinor / 100)).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
        }
        .padding(.vertical, 8)
    }

    // MARK: History grouped by day (per Figma)

    @ViewBuilder
    private var historyList: some View {
        if listed.isEmpty {
            Text("No gifts \(periodLabel).").font(.nBody).foregroundStyle(Nuru.muted)
                .frame(maxWidth: .infinity).padding(.top, Nuru.S.lg)
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
                Text(g.fund.capitalized)
                    .font(.inter(14, .bold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                Text("\(giveTime(g.createdAt)) · \(givingMethodName(g.method))")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                // A pledge payment says so — the complete record still tells
                // the member which gifts counted toward a pledge (the partners
                // statement lists only these). Absent on older servers.
                if let tag = pledgeTag(g) {
                    Text(tag)
                        .font(.inter(10, .semibold)).foregroundStyle(Nuru.goldChipText)
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
                            .font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
                        // Y and N count the same (settled) rows; a row still
                        // processing or failed is listed inside, and said here.
                        Text("\(ksh(pledgeMinor / 100)) · \(n) payment\(n == 1 ? "" : "s")\(unsettled > 0 ? " · \(unsettled) not settled" : "")")
                            .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                    }
                    Spacer(minLength: 8)
                    Icon(pledgesOpen ? .chevronUp : .chevronDown, size: 16, color: Nuru.navy)
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
            Icon(.arrowRight, size: 12, color: Nuru.gold)
        }
        .foregroundStyle(Nuru.gold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    // MARK: Share / download (native PDF, real aggregates only)

    /// The PDF carries SETTLED money only, split as the page is: gifts by
    /// fund, partner pledges by pledge. Gifts ∪ pledges is every settled row
    /// of the year and the two are disjoint, so Gifts + Partner pledges =
    /// totalMinor(in:) by construction. With no pledge money it is the
    /// pre-v2 PDF (every settled row under BY FUND).
    private func share() {
        let gifts = vm.gifts(in: year)
        let pledgeRows = vm.pledgeRecords(in: year)
        let data = StatementPDF.data(memberName: auth.profile?.fullName,
                                     year: year,
                                     gifts: vm.fundTotals(of: gifts),
                                     giftsMinor: vm.settledMinor(gifts),
                                     giftCount: vm.settledCount(gifts),
                                     pledges: vm.pledgeTotals(in: year),
                                     pledgesMinor: vm.settledMinor(pledgeRows),
                                     pledgeCount: vm.settledCount(pledgeRows))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nuru-giving-statement-\(year).pdf")
        do {
            try data.write(to: url)
            shareFile = ShareFile(url: url)
        } catch {
            Haptics.error()   // the tap did something — say the file didn't make it
        }
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

// MARK: - Branded statement PDF (UIGraphicsPDFRenderer — no dependencies)

private enum StatementPDF {
    typealias FundRow = (fund: String, count: Int, totalMinor: Int)
    typealias PledgeRow = (title: String, count: Int, totalMinor: Int)

    /// Statement v2 (§3d): gifts by fund; then, when there is pledge money, a
    /// separate PARTNER PLEDGES section by pledge with its own subtotal; then
    /// the grand total. Each subtotal is the sum of the rows above it and
    /// Gifts + Partner pledges = Total. Amounts print EXACTLY (cents when a
    /// figure has any), never truncated, so the page always foots. Breaks to
    /// a new page rather than drawing past the bottom margin.
    static func data(memberName: String?, year: Int,
                     gifts: [FundRow], giftsMinor: Int, giftCount: Int,
                     pledges: [PledgeRow], pledgesMinor: Int, pledgeCount: Int) -> Data {
        let W: CGFloat = 595, H: CGFloat = 842, margin: CGFloat = 48
        let navy = UIColor(red: 11 / 255, green: 31 / 255, blue: 51 / 255, alpha: 1)
        let gold = UIColor(red: 200 / 255, green: 155 / 255, blue: 60 / 255, alpha: 1)
        let ink = UIColor(red: 40 / 255, green: 40 / 255, blue: 45 / 255, alpha: 1)
        let muted = UIColor(red: 120 / 255, green: 128 / 255, blue: 140 / 255, alpha: 1)
        let hairline = UIColor(red: 232 / 255, green: 232 / 255, blue: 235 / 255, alpha: 1)
        let totalMinor = giftsMinor + pledgesMinor
        let split = pledgesMinor > 0

        func amount(_ minor: Int) -> String {
            let sign = minor < 0 ? "-" : ""
            let a = abs(minor)
            let whole = (a / 100).formatted(.number.grouping(.automatic))
            return a % 100 == 0 ? "\(sign)KSh \(whole)" : "\(sign)KSh \(whole).\(String(format: "%02d", a % 100))"
        }
        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
            (s as NSString).draw(at: CGPoint(x: x, y: y),
                                 withAttributes: [.font: font, .foregroundColor: color])
        }
        /// One line, cut with an ellipsis at `width` — a long pledge name
        /// never runs into its amount.
        func textClipped(_ s: String, _ x: CGFloat, _ y: CGFloat, width: CGFloat, _ font: UIFont, _ color: UIColor) {
            let para = NSMutableParagraphStyle()
            para.lineBreakMode = .byTruncatingTail
            (s as NSString).draw(in: CGRect(x: x, y: y, width: width, height: font.lineHeight + 2),
                                 withAttributes: [.font: font, .foregroundColor: color, .paragraphStyle: para])
        }
        func textRight(_ s: String, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(at: CGPoint(x: W - margin - size.width, y: y), withAttributes: attrs)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: W, height: H))
        return renderer.pdfData { ctx in
            ctx.beginPage()

            // Navy header band — the grand total, and (with pledge money) the
            // one line that shows it foots.
            navy.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: split ? 160 : 150))
            text("NURU PLACE", margin, 42, .boldSystemFont(ofSize: 11), gold)
            text("Giving statement", margin, 62, .boldSystemFont(ofSize: 24), .white)
            text("NURU PLACE CHURCH", margin, 98, .systemFont(ofSize: 11), UIColor(white: 0.85, alpha: 1))
            textRight(amount(totalMinor), 62, .boldSystemFont(ofSize: 24), gold)
            let countLine = split
                ? "\(giftCount) gift\(giftCount == 1 ? "" : "s") · \(pledgeCount) pledge payment\(pledgeCount == 1 ? "" : "s") · \(year)"
                : "\(giftCount) settled gifts · \(year)"
            textRight(countLine, 98, .systemFont(ofSize: 11), UIColor(white: 0.85, alpha: 1))
            if split {
                text("Gifts \(amount(giftsMinor))  ·  Partner pledges \(amount(pledgesMinor))  ·  Total \(amount(totalMinor))",
                     margin, 126, .boldSystemFont(ofSize: 11), .white)
            }

            var y: CGFloat = split ? 200 : 190
            func ensure(_ needed: CGFloat) {
                if y + needed > H - 70 { ctx.beginPage(); y = margin }
            }
            func row(_ label: String, _ value: String, valueColor: UIColor = ink) {
                text(label, margin, y, .systemFont(ofSize: 11), muted)
                textRight(value, y, .boldSystemFont(ofSize: 11), valueColor)
                hairline.setFill()
                ctx.fill(CGRect(x: margin, y: y + 18, width: W - margin * 2, height: 0.7))
                y += 28
            }
            func subtotal(_ label: String, _ minor: Int) {
                ensure(30)
                y += 4
                navy.setFill()
                ctx.fill(CGRect(x: margin, y: y, width: W - margin * 2, height: 1))
                y += 9
                text(label, margin, y, .boldSystemFont(ofSize: 10), navy)
                textRight(amount(minor), y - 1, .boldSystemFont(ofSize: 12), navy)
                y += 26
            }

            // Meta rows
            if let memberName, !memberName.isEmpty { row("Member", memberName) }
            row("Period", "1 Jan – 31 Dec \(year)")
            let gen = DateFormatter(); gen.dateFormat = "d MMM yyyy"
            row("Generated", gen.string(from: Date()))

            // Gifts by fund (gifts only when there is pledge money)
            y += 16
            ensure(52)
            text(split ? "GIFTS BY FUND" : "BY FUND", margin, y, .boldSystemFont(ofSize: 10), gold)
            y += 22
            for r in gifts {
                ensure(30)
                text(r.fund.capitalized, margin, y, .boldSystemFont(ofSize: 12), ink)
                text("\(r.count) gift\(r.count == 1 ? "" : "s")", margin + 140, y + 1, .systemFont(ofSize: 10), muted)
                textRight(amount(r.totalMinor), y, .boldSystemFont(ofSize: 12), ink)
                hairline.setFill()
                ctx.fill(CGRect(x: margin, y: y + 20, width: W - margin * 2, height: 0.7))
                y += 30
            }
            if gifts.isEmpty {
                text(split ? "No settled gifts outside a pledge this period." : "No settled gifts this period.",
                     margin, y, .systemFont(ofSize: 11), muted)
                y += 30
            }

            if split {
                subtotal("TOTAL GIFTS", giftsMinor)

                // Partner pledges by pledge, with their own subtotal
                y += 10
                ensure(52)
                text("PARTNER PLEDGES", margin, y, .boldSystemFont(ofSize: 10), gold)
                y += 22
                for p in pledges {
                    ensure(30)
                    textClipped(p.title, margin, y, width: 270, .boldSystemFont(ofSize: 12), ink)
                    text("\(p.count) payment\(p.count == 1 ? "" : "s")", margin + 290, y + 1, .systemFont(ofSize: 10), muted)
                    textRight(amount(p.totalMinor), y, .boldSystemFont(ofSize: 12), ink)
                    hairline.setFill()
                    ctx.fill(CGRect(x: margin, y: y + 20, width: W - margin * 2, height: 0.7))
                    y += 30
                }
                subtotal("TOTAL PARTNER PLEDGES", pledgesMinor)
            }

            // Ruled grand total
            ensure(60)
            y += 6
            navy.setFill()
            ctx.fill(CGRect(x: margin, y: y, width: W - margin * 2, height: 2))
            y += 12
            text("TOTAL GIVEN", margin, y, .boldSystemFont(ofSize: 11), navy)
            textRight(amount(totalMinor), y - 3, .boldSystemFont(ofSize: 16), gold)
            if split {
                y += 20
                text("Gifts + Partner pledges", margin, y, .systemFont(ofSize: 9), muted)
            }

            // Scripture + footer
            y += 46
            ensure(90)
            let verse = "\u{201C}Each of you should give what you have decided in your heart to give… for God loves a cheerful giver.\u{201D}"
            (verse as NSString).draw(in: CGRect(x: margin, y: y, width: W - margin * 2, height: 44),
                                     withAttributes: [.font: UIFont.italicSystemFont(ofSize: 12),
                                                      .foregroundColor: navy])
            y += 40
            text("2 Corinthians 9:7", margin, y, .boldSystemFont(ofSize: 10), gold)
            text("Official statement · Finance · Nuru Place", margin, H - 42, .systemFont(ofSize: 9), muted)
        }
    }
}

// MARK: - Shared giving atoms (used by the receipt screen too)

func ksh(_ n: Int) -> String { "KSh \(n.formatted(.number.grouping(.automatic)))" }

/// Currency-AWARE amount from minor units — PayPal gifts settle in USD
/// server-side; formatting everything as "KSh" printed the wrong symbol on
/// USD gifts while the Currency detail row said USD. Mirrors Android money().
func money(_ minor: Int, _ currency: String?) -> String {
    switch currency?.uppercased() {
    case nil, "", "KES": return ksh(minor / 100)
    case "USD": return "$" + String(format: "%.2f", Double(minor) / 100.0)
    case let c?: return c + " " + String(format: "%.2f", Double(minor) / 100.0)
    }
}

@ViewBuilder
func statusChip(_ status: String) -> some View {
    let (bg, fg, label): (Color, Color, String) = {
        switch status {
        case "succeeded", "settled", "completed": return (Nuru.successBg, Nuru.successText, "Succeeded")
        case "processing": return (Nuru.goldChipBg, Nuru.goldChipText, "Processing")
        case "failed": return (Nuru.danger.opacity(0.12), Nuru.danger, "Failed")
        case "refunded": return (Nuru.mutedBg, Nuru.ink600, "Refunded")
        default: return (Nuru.mutedBg, Nuru.ink600, status.capitalized)
        }
    }()
    Text(label).font(.nMicro).foregroundStyle(fg)
        .padding(.horizontal, 8).padding(.vertical, 3).background(bg, in: Capsule())
}
