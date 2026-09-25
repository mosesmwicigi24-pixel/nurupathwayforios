// The Partners statement — its own page, pushed from the Partners tab (the
// standing card's "Statement" and the preview card's "Partners statement and
// PDF"). Owner, 2026-09-25: "Have the statement separate for partners and
// give statements separate." This page is the partners' record for one year:
// the pledges that lived in it, what was promised / paid / left, and the
// payments that counted toward a pledge — with its own server-rendered PDF
// (GET /giving/partners/statement.pdf?year=). The general giving statement
// (every gift, every fund) stays one tap away at the bottom, so the complete
// record is never hidden behind the partners' view of it.
//
// Numbers: the server's pledged_minor / paid_minor / remaining_minor and
// pledges[] are preferred when present. A server that predates them sends
// none, and the same figures are computed here with PledgeMath from the
// partnership's pledges + the statement's payments — the rule written in
// PartnersView's header, so the preview card and this page always agree.
import SwiftUI
import UIKit

struct PartnersStatementView: View {
    /// The Partners tab's model — one statement cache and one selected year
    /// for the preview card and this page (they must never disagree).
    @ObservedObject var vm: PartnersModel
    @Environment(\.dismiss) private var dismiss

    @State private var downloading = false
    @State private var downloadError: String?
    @State private var shareFile: PartnersStatementFile?

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    yearChips
                    if let p = vm.partnership { standingLine(p) }
                    statementContent
                    actions
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .refreshable {
                await vm.load()
                await vm.loadStatements()
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            if vm.partnership == nil { await vm.load() }
            if vm.statements == nil { await vm.loadStatements() }
        }
        .sheet(item: $shareFile) { f in PartnersStatementShareSheet(url: f.url) }
    }

    // MARK: Header — the cream band: back, share, kicker + title

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                squareButton(.arrowLeft, label: "Back") { dismiss() }
                Spacer()
                squareButton(.share, label: "Share PDF", busy: downloading) { download() }
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("PARTNERS").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0x9A7A2A))
                Text("Partners statement")
                    .font(.fraunces(26, .semibold)).foregroundStyle(Nuru.navy)
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

    private func squareButton(_ icon: Lucide, label: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            ZStack {
                if busy { ProgressView().tint(Nuru.navy).scaleEffect(0.8) }
                else { Icon(icon, size: 18, color: Nuru.navy) }
            }
            .frame(width: 40, height: 40)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(label)
    }

    // MARK: Year chips — the same years, the same selection, as the Partners tab

    private var yearChips: some View {
        HStack(spacing: 6) {
            ForEach(vm.statementYears, id: \.self) { y in
                let on = vm.statementYear == y
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation { downloadError = nil }
                    Task { await vm.loadStatements(year: y) }
                } label: {
                    Text(String(y)).font(.inter(12, .semibold))
                        .foregroundStyle(on ? .white : Nuru.navy)
                        .padding(.horizontal, 12).frame(height: 30)
                        .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
            Spacer(minLength: 0)
        }
    }

    /// "Partner since Sep 2026 · Gold" — the tier only when the server named one.
    private func standingLine(_ p: Partnership) -> some View {
        var parts = [partnerSinceLine(p)]
        if let t = p.tier, !t.name.isEmpty { parts.append(t.name) }
        return Text(parts.joined(separator: " · "))
            .font(.inter(12)).foregroundStyle(Nuru.ink600)
    }

    // MARK: The statement — summary, pledges, payments

    @ViewBuilder private var statementContent: some View {
        if let s = vm.statements, !vm.statementsLoading {
            let figures = Figures(s, vm.partnership)
            summaryCard(figures, s.currency)
            pledgesSection(figures.pledges, year: s.year)
            paymentsSection(s)
        } else if vm.statementsLoading || (vm.statements == nil && vm.statementsError == nil) {
            ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 40)
        } else if let e = vm.statementsError {
            HStack(spacing: 10) {
                Text(e).font(.nCaption).foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button { Haptics.tap(); Task { await vm.loadStatements() } } label: {
                    Text("Try again").font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                }
                .buttonStyle(.plain)
            }
            .partnerCard()
        }
    }

    private func summaryCard(_ f: Figures, _ currency: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            summaryColumn("Pledged", money(f.pledged, currency), Nuru.navy)
            summaryColumn("Paid", money(f.paid, currency), Nuru.successText)
            summaryColumn("Remaining", money(f.remaining, currency), Nuru.goldLo)
        }
        .partnerCard()
    }

    private func summaryColumn(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased()).font(.inter(9, .semibold)).kerning(1.2).foregroundStyle(Nuru.ink400)
            Text(value).font(.inter(16, .semibold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Your pledges — one row each; tap opens the pledge

    private func pledgesSection(_ pledges: [GivingStatements.StatementPledge], year: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            eyebrow("YOUR PLEDGES")
            if pledges.isEmpty {
                Text("No pledges in \(String(year)).")
                    .font(.inter(13)).foregroundStyle(Nuru.ink600)
                    .partnerCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(pledges.enumerated()), id: \.element.id) { i, pl in
                        NavigationLink(value: PartnersRoute.pledge(pl.pledgeId)) {
                            StatementPledgeRow(pledge: pl)
                        }
                        .buttonStyle(.pressableSubtle)
                        .disabled(pl.pledgeId.isEmpty)
                        if i != pledges.count - 1 {
                            Divider().overlay(Nuru.border).padding(.vertical, 12)
                        }
                    }
                }
                .partnerCard()
            }
        }
    }

    // MARK: Payments — by month, subtotals, the year's total; tap opens the receipt

    private func paymentsSection(_ s: GivingStatements) -> some View {
        let rows = s.pledgePayments
        let groups = monthGroups(rows)
        let listTotal = rows.reduce(0) { $0 + $1.amountMinor }
        return VStack(alignment: .leading, spacing: 8) {
            eyebrow("PAYMENTS")
            if rows.isEmpty {
                Text("No pledge payments in \(String(s.year)).")
                    .font(.inter(13)).foregroundStyle(Nuru.ink600)
                    .partnerCard()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(groups.enumerated()), id: \.element.key) { gi, g in
                        HStack(alignment: .firstTextBaseline) {
                            Text(g.label.uppercased())
                                .font(.inter(10, .bold)).kerning(1.1).foregroundStyle(Nuru.goldChipText)
                            Spacer()
                            Text(money(g.subtotal, s.currency))
                                .font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
                        }
                        .padding(.top, gi == 0 ? 0 : 16)
                        .padding(.bottom, 2)
                        ForEach(Array(g.rows.enumerated()), id: \.element.id) { i, pay in
                            NavigationLink(value: PartnersRoute.receipt(pay.transactionId)) {
                                StatementPaymentLine(payment: pay, title: paymentTitle(pay, s))
                            }
                            .buttonStyle(.pressableSubtle)
                            .disabled(pay.transactionId.isEmpty)
                            if i != g.rows.count - 1 {
                                Divider().overlay(Nuru.border)
                            }
                        }
                    }

                    // The year's total is the sum of the rows above it — the
                    // one number on this card that must foot with the list.
                    Divider().overlay(Nuru.navy.opacity(0.35)).padding(.top, 12)
                    HStack(alignment: .firstTextBaseline) {
                        Text("TOTAL PAID \(String(s.year))")
                            .font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.navy)
                        Spacer()
                        Text(money(listTotal, s.currency))
                            .font(.fraunces(18, .bold)).foregroundStyle(Nuru.gold)
                    }
                    .padding(.top, 10)
                }
                .partnerCard()
            }
        }
    }

    /// Newest month first (the payments are already newest first), grouped
    /// by the member's LOCAL month — a gift at 22:30 UTC on the 30th is a
    /// gift on the 1st in Nairobi, and the row's day says so.
    private func monthGroups(_ rows: [PledgePayment]) -> [(key: String, label: String, subtotal: Int, rows: [PledgePayment])] {
        let cal = Calendar.current
        var order: [String] = []
        var map: [String: [PledgePayment]] = [:]
        for r in rows {
            let key: String
            if let d = giveParseDate(r.at) {
                let y = cal.component(.year, from: d), m = cal.component(.month, from: d)
                key = String(format: "%04d-%02d", y, m)
            } else {
                key = String(r.at.prefix(7))
            }
            if map[key] == nil { map[key] = []; order.append(key) }
            map[key]?.append(r)
        }
        return order.map { k in
            let rs = map[k] ?? []
            return (key: k, label: monthLabel(k), subtotal: rs.reduce(0) { $0 + $1.amountMinor }, rows: rs)
        }
    }

    private func monthLabel(_ ym: String) -> String {
        let inF = DateFormatter(); inF.dateFormat = "yyyy-MM"
        guard let d = inF.date(from: ym) else { return ym }
        let out = DateFormatter(); out.dateFormat = "MMMM yyyy"
        return out.string(from: d)
    }

    /// The row's own title, else the statement's byPledge title, else the
    /// partnership's pledge name, else "Pledge".
    private func paymentTitle(_ pay: PledgePayment, _ s: GivingStatements) -> String {
        if let t = pay.pledgeTitle { return t }
        guard let id = pay.pledgeId else { return "Pledge" }
        if let t = s.pledgeTitle(for: id) { return t }
        if let pl = vm.partnership?.pledges.first(where: { $0.pledgeId == id }) { return pl.displayTitle }
        return "Pledge"
    }

    // MARK: Actions — the PDF, and the way to the complete record

    private var actions: some View {
        VStack(spacing: 10) {
            Button { download() } label: {
                HStack(spacing: 8) {
                    if downloading { ProgressView().tint(.white).scaleEffect(0.8) }
                    else { Icon(.download, size: 14, color: .white) }
                    Text(downloading ? "Preparing PDF…" : "Download PDF").font(.inter(14, .bold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Nuru.navy, in: Capsule())
            }
            .buttonStyle(.pressable)
            .disabled(downloading)

            if let downloadError {
                Text(downloadError)
                    .font(.inter(11)).foregroundStyle(Color(hex: 0xDC2626))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }

            // The complete record — every gift, pledged or not — is the
            // general statement; a partner must still be able to reach it.
            NavigationLink(value: PartnersRoute.statement) {
                HStack(spacing: 6) {
                    Text("Giving statement").font(.inter(14, .semibold))
                    Icon(.arrowRight, size: 12, color: Nuru.navy)
                }
                .foregroundStyle(Nuru.navy)
                .frame(maxWidth: .infinity).frame(height: 48)
                .background(Nuru.white, in: Capsule())
                .overlay(Capsule().stroke(Nuru.navy, lineWidth: 1.2))
            }
            .buttonStyle(.pressable)
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })

            Text("Every gift, pledged or not, is on your giving statement.")
                .font(.inter(11)).foregroundStyle(Nuru.ink400)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    /// The server's PDF for the year on screen, fetched over the bearer
    /// client into a temp file and handed to the share sheet. A 200 that is
    /// not a PDF is refused; every failure is one quiet line under the button.
    private func download() {
        guard !downloading else { return }
        downloading = true
        withAnimation { downloadError = nil }
        let year = vm.statementYear
        Task {
            defer { downloading = false }
            do {
                let data = try await MemberAPI.partnersStatementPdf(year: year)
                guard data.starts(with: Array("%PDF".utf8)) else {
                    throw APIError.decoding("statement.pdf did not return a PDF")
                }
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("nuru-partners-statement-\(year).pdf")
                try data.write(to: url, options: .atomic)
                Haptics.success()
                shareFile = PartnersStatementFile(url: url)
            } catch {
                Haptics.error()
                withAnimation { downloadError = Self.downloadMessage(for: error) }
            }
        }
    }

    private static func downloadMessage(for error: Error) -> String {
        if let api = error as? APIError {
            if case let .http(status, _, _, _) = api, status == 404 {
                return "There's no partners statement for you yet."
            }
            if api.isNetwork { return "You appear to be offline — the PDF needs a connection." }
        }
        return "The PDF isn't available right now. The statement above is still complete."
    }

    // MARK: The page's numbers — server first, PledgeMath when absent

    private struct Figures {
        let pledged: Int
        let paid: Int
        let remaining: Int
        let pledges: [GivingStatements.StatementPledge]

        init(_ s: GivingStatements, _ p: Partnership?) {
            let localPledged = PledgeMath.pledgedMinor(p?.pledges ?? [], year: s.year)
            let localPaid = PledgeMath.paidMinor(s)
            pledged = s.pledgedMinor ?? localPledged
            paid = s.paidMinor ?? localPaid
            remaining = s.remainingMinor ?? PledgeMath.remainingMinor(pledged: pledged, paid: paid)
            pledges = s.pledges.isEmpty ? Self.localPledges(s, p) : s.pledges
        }

        /// The fallback rows: every partnership pledge that lived in the
        /// year (a due date in it, or a payment in it), with the year's
        /// pledged / paid / kept computed by the same rule as the summary.
        /// A cancelled pledge appears only when money was paid toward it
        /// that year (so the payments are explained) and pledges nothing.
        static func localPledges(_ s: GivingStatements, _ p: Partnership?) -> [GivingStatements.StatementPledge] {
            guard let p else { return [] }
            let cal = Calendar.current
            let year = s.year
            let thisYear = cal.component(.year, from: Date())
            let dueThrough: Date? = year == thisYear ? Date() : nil
            return p.pledges.compactMap { pl in
                let pays = s.payments.filter { $0.pledgeId == pl.pledgeId }
                let paid = pays.reduce(0) { $0 + $1.amountMinor }
                let cancelled = pl.status == "cancelled"
                if cancelled && pays.isEmpty { return nil }
                let pledged: Int
                let dueCount: Int
                if pl.isMonthly {
                    let dues = PledgeMath.monthlyDueDates(pl, in: year)
                    guard dues > 0 || !pays.isEmpty else { return nil }
                    pledged = cancelled ? 0 : (pl.amountMinor ?? 0) * dues
                    dueCount = PledgeMath.monthlyDueDates(pl, in: year, through: dueThrough)
                } else {
                    let dueInYear = pl.dueOn.flatMap(giveParseDate)
                        .map { cal.component(.year, from: $0) == year } ?? false
                    guard dueInYear || !pays.isEmpty else { return nil }
                    pledged = (cancelled || !dueInYear) ? 0 : (pl.targetMinor ?? 0)
                    dueCount = dueInYear ? 1 : 0
                }
                return GivingStatements.StatementPledge(
                    pledgeId: pl.pledgeId, title: pl.displayTitle, shape: pl.shape,
                    amountMinor: pl.amountMinor, targetMinor: pl.targetMinor, currency: pl.currency,
                    status: pl.status, dueDay: pl.dueDay, dueOn: pl.dueOn, createdAt: pl.createdAt,
                    pledgedMinor: pledged, paidMinor: paid, kept: pays.count, dueCount: dueCount)
            }
        }
    }
}

// MARK: - One pledge as the statement reports it

private struct StatementPledgeRow: View {
    let pledge: GivingStatements.StatementPledge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(pledge.title.isEmpty ? "Pledge" : pledge.title)
                        .font(.inter(15, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    Text(pledgeAmountLine(pledge))
                        .font(.inter(12)).foregroundStyle(Nuru.ink600).lineLimit(1)
                }
                Spacer(minLength: 8)
                stateChip
            }
            Text(paidLine).font(.inter(11)).foregroundStyle(Nuru.ink600).lineLimit(1)
        }
        .contentShape(Rectangle())
    }

    /// Monthly: "KSh 6,000 paid · 3 of 4 kept" (`kept` is cycles COLLECTED,
    /// never scheduled; paying ahead never reads "5 of 4"). Total: "KSh 20,000 paid".
    private var paidLine: String {
        let paid = money(pledge.paidMinor, pledge.currency)
        guard pledge.isMonthly else { return "\(paid) paid" }
        return "\(paid) paid · \(pledge.kept) of \(max(pledge.dueCount, pledge.kept)) kept"
    }

    private var stateChip: some View {
        let (bg, fg, text): (Color, Color, String) = {
            switch pledge.status {
            case "paused": return (Nuru.mutedBg, Nuru.ink600, "Paused")
            case "fulfilled": return (Nuru.successBg, Nuru.successText, "Fulfilled")
            case "cancelled": return (Nuru.mutedBg, Nuru.ink600, "Cancelled")
            default:
                if pledge.isMonthly {
                    return pledge.kept < pledge.dueCount
                        ? (Nuru.goldChipBg, Nuru.goldChipText, "Behind")
                        : (Nuru.successBg, Nuru.successText, "On track")
                }
                // A total pledge is behind only once its date has passed unfulfilled.
                if let iso = pledge.dueOn, let d = giveParseDate(iso), d < Calendar.current.startOfDay(for: Date()) {
                    return (Nuru.goldChipBg, Nuru.goldChipText, "Behind")
                }
                return (Nuru.successBg, Nuru.successText, "On track")
            }
        }()
        return Text(text).font(.inter(10, .bold)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 3).background(bg, in: Capsule())
    }
}

// MARK: - One payment line: day · pledge title over method + receipt code · amount

private struct StatementPaymentLine: View {
    let payment: PledgePayment
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Text(dayLabel)
                .font(.inter(12, .semibold)).foregroundStyle(Nuru.ink600)
                .frame(width: 54, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
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

    /// "Sat 20" — the month is the group header above.
    private var dayLabel: String {
        guard let d = giveParseDate(payment.at) else { return String(payment.at.prefix(10).suffix(2)) }
        let f = DateFormatter(); f.dateFormat = "EEE d"
        return f.string(from: d)
    }

    /// Method label when the server sends the rail, else the fund; then the
    /// receipt code. Nothing is guessed.
    private var meta: String {
        var parts: [String] = []
        if let m = payment.method {
            parts.append(givingMethodName(m))
        } else if let name = payment.fundName {
            parts.append(name)
        } else if let f = payment.fund, !f.isEmpty {
            parts.append(f.capitalized)
        }
        if let r = payment.receiptCode, !r.isEmpty { parts.append(r) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Share sheet plumbing (the giving statement's idiom)

private struct PartnersStatementFile: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct PartnersStatementShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
