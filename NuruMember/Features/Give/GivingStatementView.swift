// Giving statement — the native port of the Figma GivingStatement page. A navy
// masthead with the period total, a This year / Last year selector, fund-by-fund
// totals with a ruled grand total, and the day-grouped gift history (fund icon,
// time · method, provider ref, status chip). Read-only over GET /giving/history;
// tapping a gift opens its full receipt. The download affordance renders a
// one-page branded PDF with UIGraphicsPDFRenderer (no dependencies) and hands it
// to the share sheet. Money stays in integer minor units end-to-end.
import SwiftUI
import UIKit

private let settledStatuses: Set<String> = ["succeeded", "settled", "completed"]

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

    /// Records inside one calendar year, newest first.
    func records(in year: Int) -> [GivingRecord] {
        history.filter { $0.createdAt.hasPrefix(String(year)) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func totalMinor(in year: Int) -> Int {
        records(in: year).filter { settledStatuses.contains($0.status) }
            .reduce(0) { $0 + $1.amountMinor }
    }

    func settledCount(in year: Int) -> Int {
        records(in: year).filter { settledStatuses.contains($0.status) }.count
    }

    /// Settled totals per fund (order of first appearance, newest first).
    func fundTotals(in year: Int) -> [(fund: String, count: Int, totalMinor: Int)] {
        var order: [String] = []
        var totals: [String: (count: Int, minor: Int)] = [:]
        for r in records(in: year) where settledStatuses.contains(r.status) {
            if totals[r.fund] == nil { order.append(r.fund); totals[r.fund] = (0, 0) }
            totals[r.fund]!.count += 1
            totals[r.fund]!.minor += r.amountMinor
        }
        return order.map { (fund: $0, count: totals[$0]!.count, totalMinor: totals[$0]!.minor) }
    }

    /// Records grouped by calendar day, newest first.
    func groups(in year: Int) -> [(key: String, label: String, records: [GivingRecord])] {
        var order: [String] = []
        var map: [String: [GivingRecord]] = [:]
        for r in records(in: year) {
            let key = String(r.createdAt.prefix(10))
            if map[key] == nil { map[key] = []; order.append(key) }
            map[key]?.append(r)
        }
        return order.map { (key: $0, label: dayLabel($0), records: map[$0] ?? []) }
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
    @StateObject private var vm = GivingStatementViewModel()
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var shareFile: ShareFile?

    private var thisYear: Int { Calendar.current.component(.year, from: Date()) }
    private var periodLabel: String { year == thisYear ? "this year" : "in \(year)" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    periodSelector
                    if vm.loading && vm.history.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else if let e = vm.error, vm.history.isEmpty {
                        Text(e).font(.nBody).foregroundStyle(Nuru.muted)
                            .frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else if vm.history.isEmpty {
                        Text("No gifts yet.").font(.nBody).foregroundStyle(Nuru.muted)
                            .frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else {
                        fundTotalsCard
                        historyList
                        Text("Statement reflects records held under Finance · receipts emailed per gift.")
                            .font(.inter(11)).foregroundStyle(Color(hex: 0x9CA3AF))
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
                circleButton(.download) { share() }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Total given").font(.inter(11)).foregroundStyle(.white.opacity(0.6))
                Text(ksh(vm.totalMinor(in: year) / 100))
                    .font(.fraunces(34, .semibold)).kerning(-1).foregroundStyle(.white)
                Text("\(vm.settledCount(in: year)) gifts · \(periodLabel) · most recent first")
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
                    CachedAsyncImage(url: u) { p in
                        (p.image ?? Image(systemName: "photo")).resizable().scaledToFill()
                    }
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
        }.buttonStyle(.plain)
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
        return Button { year = y } label: {
            Text(label)
                .font(.inter(13, .semibold))
                .foregroundStyle(on ? Nuru.navy : Color(hex: 0x6B7280))
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
            let totals = vm.fundTotals(in: year)
            if totals.isEmpty {
                Text("No settled gifts \(periodLabel).")
                    .font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
                    .padding(.vertical, Nuru.S.sm)
            } else {
                ForEach(Array(totals.enumerated()), id: \.element.fund) { i, t in
                    fundRow(t)
                    if i != totals.count - 1 { Divider().overlay(Nuru.border.opacity(0.6)) }
                }
            }
            HStack {
                Text("TOTAL GIVEN").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(Nuru.navy)
                Spacer()
                Text(ksh(vm.totalMinor(in: year) / 100))
                    .font(.fraunces(18, .bold)).foregroundStyle(Nuru.gold)
            }
            .padding(.top, 10)
            .overlay(alignment: .top) { Rectangle().fill(Nuru.navy).frame(height: 2) }
            .padding(.top, 6)
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
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x9CA3AF))
            }
            Spacer()
            Text(ksh(t.totalMinor / 100)).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
        }
        .padding(.vertical, 8)
    }

    // MARK: History grouped by day (per Figma)

    @ViewBuilder
    private var historyList: some View {
        if vm.records(in: year).isEmpty {
            Text("No gifts \(periodLabel).").font(.nBody).foregroundStyle(Nuru.muted)
                .frame(maxWidth: .infinity).padding(.top, Nuru.S.lg)
        } else {
            ForEach(vm.groups(in: year), id: \.key) { group in
                VStack(alignment: .leading, spacing: 10) {
                    Text(group.label.uppercased())
                        .font(.inter(11, .bold)).kerning(1.1).foregroundStyle(Color(hex: 0xA8861C))
                    ForEach(group.records) { r in
                        NavigationLink(value: r) { giftCard(r) }.buttonStyle(.plain)
                    }
                }
                .padding(.top, Nuru.S.sm)
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
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x9CA3AF))
                if let ref = g.providerRef {
                    Text("Ref \(ref)")
                        .font(.inter(10, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Nuru.S.sm)
            VStack(alignment: .trailing, spacing: 5) {
                Text(ksh(g.amountMinor / 100))
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

    // MARK: Share / download (native PDF, real aggregates only)

    private func share() {
        let totals = vm.fundTotals(in: year)
        let data = StatementPDF.data(memberName: auth.profile?.fullName,
                                     year: year,
                                     rows: totals,
                                     totalMinor: vm.totalMinor(in: year),
                                     giftCount: vm.settledCount(in: year))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nuru-giving-statement-\(year).pdf")
        do {
            try data.write(to: url)
            shareFile = ShareFile(url: url)
        } catch { /* nothing to share */ }
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

// MARK: - One-page branded statement PDF (UIGraphicsPDFRenderer — no dependencies)

private enum StatementPDF {
    static func data(memberName: String?, year: Int,
                     rows: [(fund: String, count: Int, totalMinor: Int)],
                     totalMinor: Int, giftCount: Int) -> Data {
        let W: CGFloat = 595, H: CGFloat = 842, margin: CGFloat = 48
        let navy = UIColor(red: 11 / 255, green: 31 / 255, blue: 51 / 255, alpha: 1)
        let gold = UIColor(red: 200 / 255, green: 155 / 255, blue: 60 / 255, alpha: 1)
        let ink = UIColor(red: 40 / 255, green: 40 / 255, blue: 45 / 255, alpha: 1)
        let muted = UIColor(red: 120 / 255, green: 128 / 255, blue: 140 / 255, alpha: 1)
        let hairline = UIColor(red: 232 / 255, green: 232 / 255, blue: 235 / 255, alpha: 1)

        func text(_ s: String, _ x: CGFloat, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
            (s as NSString).draw(at: CGPoint(x: x, y: y),
                                 withAttributes: [.font: font, .foregroundColor: color])
        }
        func textRight(_ s: String, _ y: CGFloat, _ font: UIFont, _ color: UIColor) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (s as NSString).size(withAttributes: attrs)
            (s as NSString).draw(at: CGPoint(x: W - margin - size.width, y: y), withAttributes: attrs)
        }

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: W, height: H))
        return renderer.pdfData { ctx in
            ctx.beginPage()

            // Navy header band
            navy.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: W, height: 150))
            text("NURU PLACE", margin, 42, .boldSystemFont(ofSize: 11), gold)
            text("Giving statement", margin, 62, .boldSystemFont(ofSize: 24), .white)
            text("NURU PLACE CHURCH", margin, 98, .systemFont(ofSize: 11), UIColor(white: 0.85, alpha: 1))
            textRight("KSh \((totalMinor / 100).formatted(.number.grouping(.automatic)))",
                      62, .boldSystemFont(ofSize: 24), gold)
            textRight("\(giftCount) settled gifts · \(year)", 98, .systemFont(ofSize: 11),
                      UIColor(white: 0.85, alpha: 1))

            // Meta rows
            var y: CGFloat = 190
            func row(_ label: String, _ value: String, valueColor: UIColor = ink) {
                text(label, margin, y, .systemFont(ofSize: 11), muted)
                textRight(value, y, .boldSystemFont(ofSize: 11), valueColor)
                hairline.setFill()
                ctx.fill(CGRect(x: margin, y: y + 18, width: W - margin * 2, height: 0.7))
                y += 28
            }
            if let memberName, !memberName.isEmpty { row("Member", memberName) }
            row("Period", "1 Jan – 31 Dec \(year)")
            let gen = DateFormatter(); gen.dateFormat = "d MMM yyyy"
            row("Generated", gen.string(from: Date()))

            // Fund-by-fund totals
            y += 16
            text("BY FUND", margin, y, .boldSystemFont(ofSize: 10), gold)
            y += 22
            for r in rows {
                text(r.fund.capitalized, margin, y, .boldSystemFont(ofSize: 12), ink)
                text("\(r.count) gift\(r.count == 1 ? "" : "s")", margin + 140, y + 1, .systemFont(ofSize: 10), muted)
                textRight("KSh \((r.totalMinor / 100).formatted(.number.grouping(.automatic)))",
                          y, .boldSystemFont(ofSize: 12), ink)
                hairline.setFill()
                ctx.fill(CGRect(x: margin, y: y + 20, width: W - margin * 2, height: 0.7))
                y += 30
            }
            if rows.isEmpty {
                text("No settled gifts this period.", margin, y, .systemFont(ofSize: 11), muted)
                y += 30
            }

            // Ruled grand total
            y += 6
            navy.setFill()
            ctx.fill(CGRect(x: margin, y: y, width: W - margin * 2, height: 2))
            y += 12
            text("TOTAL GIVEN", margin, y, .boldSystemFont(ofSize: 11), navy)
            textRight("KSh \((totalMinor / 100).formatted(.number.grouping(.automatic)))",
                      y - 3, .boldSystemFont(ofSize: 16), gold)

            // Scripture + footer
            y += 46
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
