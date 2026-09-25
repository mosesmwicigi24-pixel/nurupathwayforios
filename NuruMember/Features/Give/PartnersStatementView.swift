// The Partners statement — its own page, pushed from the Partners tab (the
// standing card's "Statement" and the preview card's "Partners statement and
// PDF") and from the giving statement's PARTNER PLEDGES card (via
// PartnersStatementHost on the Give stack). Owner, 2026-09-25: "Have the
// statement separate for partners and give statements separate."
//
// Statement v2 (PARTNERS_PROGRAMME §3d, owner-decided 2026-09-25) leads with
// what the partnership did, then the ledger:
//   · a navy hero that REPLACES the cream band — thank-you, partner since ·
//     tier, and three tiles: disciples carried (NEVER "0" — below the first
//     it shows the progress toward it, full width, with Kept and Given side
//     by side beneath), commitments kept N of M (kept = a due date paid in
//     full, on time or late), given toward pledges. Back + share sit on a
//     pinned navy bar above it: with the system back button hidden iOS has
//     no swipe-back here, so the way back must never scroll away;
//   · FAITHFULNESS — twelve squares, Jan→Dec, and one summary line;
//   · COMMITMENTS — the year's pledges, what remains this year, and for a
//     department need how far the whole church has got;
//   · SINCE YOU BEGAN — what the WHOLE church did while this member
//     partnered (never "your money produced this");
//   · PAYMENTS by month with the year's total, the PDF, the giving statement.
// Every v2 block is optional on the wire and hidden when absent. With no
// `impact` (an older server) there are no tiles and the Pledged / Paid /
// Remaining card stays in their place.
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
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.giveSegmentVisible) private var segmentVisible

    /// Not covered by a page pushed over it (onAppear / onDisappear).
    @State private var onScreen = false
    /// What the member can actually see: this page, on the Give tab, in the
    /// visible segment. Tabs and segments stay mounted (keep-alive), so
    /// onScreen alone stays true behind another tab.
    private var visible: Bool { onScreen && segmentVisible && tabs.selected == .give }
    @State private var downloading = false
    @State private var downloadError: String?
    @State private var shareFile: PartnersStatementFile?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 12) {
                        yearChips
                        if vm.refreshFailed && vm.statements != nil {
                            Text("Couldn't refresh just now — showing what we last had.")
                                .font(.inter(11)).foregroundStyle(Nuru.ink400)
                                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                        }
                        statementContent
                        actions
                    }
                    .padding(.horizontal, Nuru.S.base)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .refreshable {
                await vm.load()
                await vm.loadStatements()
            }
        }
        // The PAGE starts at the screen's top edge and the pinned bar pads
        // itself below the status bar — so the hero begins directly under
        // the bar and scrolled content passes straight under it. (Ignoring
        // the safe area on the bar alone drew it up into the status bar but
        // left its old slot reserved: a dead ~59pt paper band beneath it.)
        .ignoresSafeArea(edges: .top)
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Stale-while-revalidate: ALWAYS refetch on appear (and on coming
        // back to the foreground while visible) — what is cached stays up.
        .task { await vm.refresh(withStatement: true) }
        .onAppear { onScreen = true }
        .onDisappear { onScreen = false }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && visible { Task { await vm.refresh(withStatement: true) } }
        }
        // Shown again (tab or segment switched back): stale-while-revalidate.
        .onChange(of: visible) { _, v in
            if v { Task { await vm.refresh(withStatement: true) } }
        }
        // Processing rows resolve by themselves: while this page is on
        // screen, in the foreground and showing any, refetch every 10 s for
        // at most 2 minutes. SwiftUI cancels the loop the moment any of the
        // three stops being true (the id flips) or the page goes away.
        .task(id: shouldPollPending) { await pollPending() }
        .sheet(item: $shareFile) { f in PartnersStatementShareSheet(url: f.url) }
    }

    /// Poll only while the member can see Processing rows.
    private var shouldPollPending: Bool {
        visible && scenePhase == .active && hasPendingRows
    }

    private var hasPendingRows: Bool {
        !(vm.statements?.pendingPledgePayments.isEmpty ?? true)
    }

    /// Every 10 s, at most 12 times (2 minutes): a quiet refetch of the year
    /// on screen (stale replies are ignored by the model). Stops as soon as
    /// no Processing row remains. When one resolves, the partnership is
    /// refetched once too, so the pledge cards and the due list agree.
    private func pollPending() async {
        guard shouldPollPending else { return }
        let deadline = Date().addingTimeInterval(120)
        var pendingCount = vm.statements?.pendingPledgePayments.count ?? 0
        while Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if Task.isCancelled { return }
            await vm.loadStatements()
            if Task.isCancelled { return }
            let now = vm.statements?.pendingPledgePayments.count ?? 0
            if now < pendingCount { await vm.load() }
            pendingCount = now
            if now == 0 { return }
        }
    }

    /// The statement on screen — nil while a year is loading, so the hero
    /// never shows last year's tiles under this year's eyebrow.
    private var shownStatements: GivingStatements? {
        vm.statementsLoading ? nil : vm.statements
    }

    // MARK: Top bar — pinned navy: back, share. The hero below it scrolls, so
    // the way back is always on screen however tall the hero grows.

    private var topBar: some View {
        HStack {
            squareButton(.arrowLeft, label: "Back") { dismiss() }
            Spacer()
            squareButton(.share, label: "Share PDF", busy: downloading) { download() }
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, NuruSafeArea.top + 8)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .background(Nuru.navy)
    }

    private func squareButton(_ icon: Lucide, label: String, busy: Bool = false, action: @escaping () -> Void) -> some View {
        Button { Haptics.tap(); action() } label: {
            ZStack {
                if busy { ProgressView().tint(.white).scaleEffect(0.8) }
                else { Icon(icon, size: 18, color: .white) }
            }
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel(label)
    }

    // MARK: Hero — eyebrow, thank-you, standing, the three tiles

    private var hero: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PARTNERS STATEMENT · \(String(vm.statementYear))")
                .font(.inter(10, .bold)).kerning(1.8)
                .foregroundStyle(Color(hex: 0xE6CA68))
            Text(thankYouLine)
                .font(.fraunces(24, .semibold)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let line = standingText {
                Text(line).font(.inter(12)).foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 4)
            }
            if let s = shownStatements, let tiles = HeroTiles(s) {
                tileRow(tiles, s.currency).padding(.top, 16)
            }
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 6)
        .padding(.bottom, Nuru.S.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.navy, in: UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
    }

    /// "Thank you, Grace." — the first word of the member's name; plain
    /// "Thank you." when there is none.
    private var thankYouLine: String {
        let full = (auth.profile?.fullName ?? "").trimmingCharacters(in: .whitespaces)
        let first = full.split(separator: " ").first.map(String.init) ?? ""
        return first.isEmpty ? "Thank you." : "Thank you, \(first)."
    }

    /// "Partner since Sep 2026 · Gold" — the tier only when the server named one.
    private var standingText: String? {
        guard let p = vm.partnership else { return nil }
        var parts = [partnerSinceLine(p)]
        if let t = p.tier, !t.name.isEmpty { parts.append(t.name) }
        return parts.joined(separator: " · ")
    }

    /// The hero's three tiles, each nil when its data is absent. The whole
    /// value is nil when there is no `impact` (older server) or no tile has
    /// anything to say — the Pledged / Paid / Remaining card then stays.
    private struct HeroTiles {
        enum Disciples {
            case carried(Int)
            /// Below the first disciple: paid toward it, of what one costs.
            case toward(towardMinor: Int, perMinor: Int)
        }
        let disciples: Disciples?
        /// "Kept" has ONE meaning — a due date paid in full, on time or late
        /// (owner, 2026-09-25): kept = on time + late, over those that fell due.
        let kept: (kept: Int, due: Int, late: Int)?
        let givenMinor: Int?

        /// What one disciple through a level costs (giving-tier economics:
        /// KSh 20,000). Used ONLY when the server's `per_disciple_minor` is
        /// missing or not positive, so the bar never divides by zero — the
        /// same fallback as Android's DISCIPLE_COST_MINOR.
        static let discipleCostMinor = 2_000_000

        init?(_ s: GivingStatements) {
            guard let i = s.impact else { return nil }
            if let n = i.disciplesCarried, n >= 1 {
                disciples = .carried(n)
            } else if i.disciplesCarried != nil {
                // Below the first: progress toward it — never a bare 0. The
                // server's toward_next; a partial answer that left it at 0
                // (or out) while money was paid reads the paid remainder.
                let per = (i.perDiscipleMinor ?? 0) > 0 ? i.perDiscipleMinor! : Self.discipleCostMinor
                let sent = i.towardNextMinor ?? 0
                let toward = sent > 0 ? sent : max(i.paidMinor ?? 0, 0) % per
                disciples = .toward(towardMinor: min(max(toward, 0), per), perMinor: per)
            } else {
                disciples = nil   // no disciples_carried on the wire: no tile
            }
            if let f = s.faithfulness, let due = f.dueCount, due > 0, f.keptOnTime != nil || f.late != nil {
                let late = max(0, f.late ?? 0)
                kept = (max(0, f.keptOnTime ?? 0) + late, due, late)
            } else {
                kept = nil
            }
            givenMinor = i.paidMinor.flatMap { $0 >= 0 ? $0 : nil }
            if disciples == nil && kept == nil && givenMinor == nil { return nil }
        }
    }

    /// Three across when the disciples tile holds a count. Below the first
    /// disciple its sentence needs the width: that tile goes full width and
    /// Kept + Given sit side by side beneath it.
    @ViewBuilder private func tileRow(_ t: HeroTiles, _ currency: String) -> some View {
        if let d = t.disciples, case .toward = d {
            VStack(spacing: 8) {
                disciplesTile(d, currency)
                if t.kept != nil || t.givenMinor != nil {
                    HStack(alignment: .top, spacing: 8) { keptAndGiven(t, currency) }
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 8) {
                if let d = t.disciples { disciplesTile(d, currency) }
                keptAndGiven(t, currency)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private func keptAndGiven(_ t: HeroTiles, _ currency: String) -> some View {
        if let k = t.kept {
            heroTile("KEPT", a11y: "\(k.kept) of \(k.due) commitments kept\(k.late > 0 ? ", \(k.late) late" : "")") {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(k.kept)").font(.fraunces(26, .semibold)).foregroundStyle(.white)
                    Text("of \(k.due)").font(.inter(12, .semibold)).foregroundStyle(.white.opacity(0.75))
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                // "9 of 10 · 1 late" — the late ones are kept, and said.
                tileCaption(k.late > 0 ? "commitments · \(k.late) late" : "commitments")
            }
        }
        if let g = t.givenMinor {
            heroTile("GIVEN", a11y: "Given \(money(g, currency)) toward pledges") {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(Self.currencyPrefix(currency)).font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.75))
                    Text(Self.compactAmount(g)).font(.fraunces(26, .semibold)).foregroundStyle(.white)
                }
                .lineLimit(1).minimumScaleFactor(0.6)
                tileCaption("toward pledges")
            }
        }
    }

    @ViewBuilder private func disciplesTile(_ d: HeroTiles.Disciples, _ currency: String) -> some View {
        switch d {
        case .carried(let n):
            heroTile("DISCIPLES CARRIED", a11y: "\(n) disciple\(n == 1 ? "" : "s") carried through a level") {
                Text("\(n)").font(.fraunces(26, .semibold)).foregroundStyle(Nuru.gold)
                    .lineLimit(1).minimumScaleFactor(0.6)
                tileCaption("through a level")
            }
        case .toward(let toward, let per):
            let ofLine = "\(money(toward, currency)) of \(PartnerFormat.grouped(per / 100))"
            heroTile("DISCIPLES CARRIED",
                     a11y: "\(money(toward, currency)) of \(money(per, currency)) toward carrying one disciple through a level") {
                GeometryReader { geo in
                    let f = Double(toward) / Double(per)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule().fill(Nuru.gold)
                            .frame(width: f > 0 ? max(4, geo.size.width * f) : 0)
                    }
                }
                .frame(height: 5)
                .padding(.top, 6)
                Text(ofLine).font(.inter(11, .semibold)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .padding(.top, 4)
                tileCaption("toward carrying one disciple through a level")
            }
        }
    }

    private func heroTile<V: View>(_ label: String, a11y: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.inter(9, .semibold)).kerning(0.8)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1).minimumScaleFactor(0.65)
                .padding(.bottom, 2)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private func tileCaption(_ s: String) -> some View {
        Text(s).font(.inter(10)).foregroundStyle(.white.opacity(0.7))
            .fixedSize(horizontal: false, vertical: true)
    }

    /// "850", "2.5k", "22k", "1.2M" — the tile's short form, in whole units
    /// and rounded DOWN so it never overstates; the full amount rides the
    /// tile's accessibility label. Integer arithmetic only.
    static func compactAmount(_ minor: Int) -> String {
        let major = max(0, minor) / 100
        func tenths(_ t: Int) -> String { t % 10 == 0 ? "\(t / 10)" : "\(t / 10).\(t % 10)" }
        switch major {
        case ..<1_000: return "\(major)"
        case ..<10_000: return tenths(major / 100) + "k"
        case ..<1_000_000: return "\(major / 1_000)k"
        case ..<10_000_000: return tenths(major / 100_000) + "M"
        default: return "\(major / 1_000_000)M"
        }
    }

    static func currencyPrefix(_ currency: String?) -> String {
        switch currency?.uppercased() {
        case nil, "", "KES": return "KSh"
        case "USD": return "$"
        case let c?: return c
        }
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

    // MARK: The statement — faithfulness, commitments, season, payments

    @ViewBuilder private var statementContent: some View {
        if let s = vm.statements, !vm.statementsLoading {
            let figures = Figures(s, vm.partnership)
            // No hero tiles (an older server sends no `impact`): the three
            // numbers stay on their card.
            if HeroTiles(s) == nil { summaryCard(figures, s.currency) }
            if let months = s.months, let strip = MonthStrip(months) {
                faithfulnessSection(strip, s.faithfulness, year: s.year)
            }
            commitmentsSection(figures.pledges, year: s.year, currency: s.currency)
            if let sentence = seasonSentence(s.season) { seasonCard(sentence) }
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

    // MARK: Faithfulness — twelve squares, Jan→Dec, and one line

    /// The twelve slots, Jan→Dec, from `months` — placed by the entry's own
    /// month when readable, else by its position. Nil when every slot is
    /// "none" (no monthly commitment in the year: nothing to show).
    private struct MonthStrip {
        let slots: [String]

        init?(_ months: [GivingStatements.MonthStatus]) {
            var slots = Array(repeating: "none", count: 12)
            for (idx, m) in months.enumerated() {
                let i = m.month.map { $0 - 1 } ?? idx
                guard (0..<12).contains(i) else { continue }
                slots[i] = m.status
            }
            // A partner with only total pledges has no monthly rhythm to show.
            guard slots.contains(where: { ["kept", "late", "missed", "upcoming"].contains($0) }) else { return nil }
            self.slots = slots
        }

        func indices(_ status: String) -> [Int] { slots.indices.filter { slots[$0] == status } }
    }

    /// Gregorian month names in the device's language — always twelve.
    private static let monthCalendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = .current
        return c
    }()

    private func faithfulnessSection(_ strip: MonthStrip, _ faithfulness: GivingStatements.Faithfulness?,
                                     year: Int) -> some View {
        let short = Self.monthCalendar.shortMonthSymbols
        return VStack(alignment: .leading, spacing: 8) {
            eyebrow("FAITHFULNESS")
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 0) {
                    ForEach(0..<12, id: \.self) { i in
                        MonthSquare(status: strip.slots[i])
                        if i < 11 { Spacer(minLength: 2) }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(stripAccessibility(strip))
                HStack {
                    Text(short.first ?? "Jan")
                    Spacer()
                    Text(short.last ?? "Dec")
                }
                .font(.inter(9, .medium)).foregroundStyle(Nuru.ink400)
                .accessibilityHidden(true)
                if let line = faithfulnessLine(strip, faithfulness, year: year) {
                    Text(line)
                        .font(.inter(11)).foregroundStyle(Nuru.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
            .partnerCard()
        }
    }

    /// "8 kept on time · 1 late · 2 missed · next due 5 Oct" — counted per
    /// COMMITMENT from the statement's `faithfulness` (the squares are the
    /// picture by month; two instalments can fall in one month). Zero parts
    /// are left out; the month counts stand in only when `faithfulness` is
    /// absent. "next due" only for the year being lived. Nil when nothing is
    /// left to say — the line is then hidden.
    private func faithfulnessLine(_ strip: MonthStrip, _ f: GivingStatements.Faithfulness?, year: Int) -> String? {
        let onTime: Int, late: Int, missed: Int
        if let f {
            onTime = max(0, f.keptOnTime ?? 0)
            late = max(0, f.late ?? 0)
            missed = max(0, f.missed ?? f.dueCount.map { $0 - onTime - late } ?? 0)
        } else {
            onTime = strip.indices("kept").count
            late = strip.indices("late").count
            missed = strip.indices("missed").count
        }
        var parts: [String] = []
        if onTime > 0 { parts.append("\(onTime) kept on time") }
        if late > 0 { parts.append("\(late) late") }
        if missed > 0 { parts.append("\(missed) missed") }
        if year == Calendar.current.component(.year, from: Date()), let next = nextPledgeDue() {
            parts.append("next due \(Self.dayMonth(next))")
        }
        guard !parts.isEmpty else { return nil }
        let line = parts.joined(separator: " · ")
        return line.prefix(1).uppercased() + line.dropFirst()
    }

    /// The soonest upcoming due date across ACTIVE monthly pledges. For each
    /// pledge: the SERVER's `progress.nextDue` when it is today or later — it
    /// is ledger-correct (payments fill due dates oldest first, so once
    /// September is paid it says November); otherwise — overdue, or absent —
    /// the next occurrence of its `due_day` (1–28) on or after today, so an
    /// overdue pledge still contributes its next upcoming date. With no
    /// partnership loaded, the statement rows' `due_day`. Nil when none.
    private func nextPledgeDue() -> Date? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        func fromDueDay(_ raw: Int) -> Date? {
            let day = min(28, max(1, raw))
            let y = cal.component(.year, from: today), m = cal.component(.month, from: today)
            guard let thisMonth = cal.date(from: DateComponents(year: y, month: m, day: day)) else { return nil }
            return thisMonth >= today ? thisMonth : cal.date(byAdding: .month, value: 1, to: thisMonth)
        }
        let candidates: [Date]
        if let p = vm.partnership {
            candidates = p.pledges
                .filter { $0.isMonthly && $0.status == "active" }
                .compactMap { pl -> Date? in
                    if let iso = pl.progress.nextDue, !iso.isEmpty, let d = giveParseDate(iso),
                       cal.startOfDay(for: d) >= today {
                        return cal.startOfDay(for: d)
                    }
                    return pl.dueDay.flatMap(fromDueDay)
                }
        } else {
            candidates = (vm.statements?.pledges ?? [])
                .filter { $0.isMonthly && $0.status == "active" }
                .compactMap { $0.dueDay.flatMap(fromDueDay) }
        }
        return candidates.min()
    }

    /// "5 Oct" this year, "5 Jan 2027" when it falls in the next.
    private static func dayMonth(_ d: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()
        f.dateFormat = cal.component(.year, from: d) == cal.component(.year, from: Date()) ? "d MMM" : "d MMM yyyy"
        return f.string(from: d)
    }

    private func stripAccessibility(_ strip: MonthStrip) -> String {
        let full = Self.monthCalendar.monthSymbols
        let words = strip.slots.enumerated().map { i, st -> String in
            let w: String
            switch st {
            case "kept": w = "kept on time"
            case "late": w = "kept late"
            case "missed": w = "missed"
            case "upcoming": w = "upcoming"
            default: w = "nothing due"
            }
            return "\(full[i]) \(w)"
        }
        return "Faithfulness: " + words.joined(separator: ", ")
    }

    // MARK: Commitments — one row each; tap opens the pledge

    private func commitmentsSection(_ pledges: [GivingStatements.StatementPledge], year: Int, currency: String) -> some View {
        // Σ remaining_year_minor; a row without it counts max(pledged −
        // paid, 0). Hidden when NO row carries it (older server / local-math
        // rows) — the same rule as Android's remainingThisYear.
        let carries = pledges.contains { $0.remainingYearMinor != nil }
        let remaining = pledges.reduce(0) { $0 + ($1.remainingYearMinor ?? max($1.pledgedMinor - $1.paidMinor, 0)) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                eyebrow("COMMITMENTS")
                Spacer()
                if carries {
                    Text("Remaining this year").font(.inter(11)).foregroundStyle(Nuru.ink400)
                    Text(money(remaining, currency))
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
                }
            }
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

    // MARK: Since you began — the whole church, never this member's money

    /// "12 levels completed and 30 plans finished across the church while
    /// you have partnered." A zero (or absent) half is left out; with nothing
    /// to say at all, or no season block, the card is hidden.
    private func seasonSentence(_ season: GivingStatements.Season?) -> String? {
        guard let season else { return nil }
        var parts: [String] = []
        if let n = season.levelsCompleted, n > 0 { parts.append("\(n) level\(n == 1 ? "" : "s") completed") }
        if let n = season.plansFinished, n > 0 { parts.append("\(n) plan\(n == 1 ? "" : "s") finished") }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " and ") + " across the church while you have partnered."
    }

    private func seasonCard(_ sentence: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SINCE YOU BEGAN").font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Nuru.gold)
            Text(sentence).font(.fraunces(17, .medium)).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    // MARK: Payments — by month, subtotals, the year's total; tap opens the receipt

    private func paymentsSection(_ s: GivingStatements) -> some View {
        let rows = s.pledgePayments
        let pending = s.pendingPledgePayments
        let groups = monthGroups(rows)
        // Settled rows only — a payment still processing is never totalled.
        let listTotal = rows.reduce(0) { $0 + $1.amountMinor }
        return VStack(alignment: .leading, spacing: 8) {
            eyebrow("PAYMENTS")
            if rows.isEmpty && pending.isEmpty {
                Text("No pledge payments in \(String(s.year)).")
                    .font(.inter(13)).foregroundStyle(Nuru.ink600)
                    .partnerCard()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if !pending.isEmpty {
                        HStack(alignment: .firstTextBaseline) {
                            Text("PROCESSING")
                                .font(.inter(10, .bold)).kerning(1.1).foregroundStyle(Nuru.urgentText)
                            Spacer()
                            Text("not yet counted").font(.inter(11)).foregroundStyle(Nuru.ink400)
                        }
                        .padding(.bottom, 2)
                        ForEach(Array(pending.enumerated()), id: \.element.id) { i, pay in
                            NavigationLink(value: PartnersRoute.receipt(pay.transactionId)) {
                                PendingPledgePaymentRow(payment: pay, title: paymentTitle(pay, s))
                            }
                            .buttonStyle(.pressableSubtle)
                            .disabled(pay.transactionId.isEmpty)
                            if i != pending.count - 1 { Divider().overlay(Nuru.border) }
                        }
                    }
                    ForEach(Array(groups.enumerated()), id: \.element.key) { gi, g in
                        HStack(alignment: .firstTextBaseline) {
                            Text(g.label.uppercased())
                                .font(.inter(10, .bold)).kerning(1.1).foregroundStyle(Nuru.goldChipText)
                            Spacer()
                            Text(money(g.subtotal, s.currency))
                                .font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
                        }
                        .padding(.top, gi == 0 && pending.isEmpty ? 0 : 16)
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
                // `kept` counts DUE DATES kept; counting payments, it is
                // capped at the due count — never "3 of 2".
                return GivingStatements.StatementPledge(
                    pledgeId: pl.pledgeId, title: pl.displayTitle, shape: pl.shape,
                    amountMinor: pl.amountMinor, targetMinor: pl.targetMinor, currency: pl.currency,
                    status: pl.status, dueDay: pl.dueDay, dueOn: pl.dueOn, createdAt: pl.createdAt,
                    pledgedMinor: pledged, paidMinor: paid, kept: min(pays.count, dueCount), dueCount: dueCount)
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
            HStack(spacing: 8) {
                Text(paidLine).font(.inter(11)).foregroundStyle(Nuru.ink600).lineLimit(1)
                Spacer(minLength: 8)
                // A department need: how far the WHOLE church has got —
                // the server sends it for need pledges only.
                if let pct = pledge.churchProgressPercent {
                    Text("Church raised \(Int(min(100, max(0, pct)).rounded(.down)))%")
                        .font(.inter(10, .semibold)).foregroundStyle(Nuru.goldLo)
                        .lineLimit(1)
                }
            }
        }
        .contentShape(Rectangle())
    }

    /// Monthly with due dates behind it: "KSh 6,000 paid · 3 of 4 kept" —
    /// the server's `kept` (due dates paid in full, on time or late) over
    /// its `due_count`, as sent. A total pledge, or a monthly one nothing
    /// has fallen due on yet: "KSh 20,000 paid" (Android parity).
    private var paidLine: String {
        let paid = money(pledge.paidMinor, pledge.currency)
        guard pledge.isMonthly, pledge.dueCount > 0 else { return "\(paid) paid" }
        return "\(paid) paid · \(pledge.kept) of \(pledge.dueCount) kept"
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

// MARK: - One month of the faithfulness strip

private struct MonthSquare: View {
    let status: String

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        Group {
            switch status {
            case "kept": shape.fill(Color(hex: 0x16A34A))
            case "late": shape.fill(Nuru.gold)
            case "missed": shape.fill(Nuru.navy)
            case "upcoming":
                shape.fill(Color.white)
                    .overlay(shape.strokeBorder(Color(hex: 0xB5BDC9), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
            default: shape.fill(Color(hex: 0xEEF1F5))
            }
        }
        .frame(width: 20, height: 20)
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

// MARK: - The Partners statement on the GIVE stack

/// The Partners statement reached from the giving statement's PARTNER
/// PLEDGES card while on the Give stack (GiveRoute.partnersStatement). It
/// owns a fresh PartnersModel for as long as the page is on the stack (a
/// @StateObject, so a re-render of the Give tab never rebuilds it), and it
/// registers the PartnersRoute pages the statement links to — a pledge, a
/// receipt, the giving statement — which otherwise only the Partners stack
/// knows. Pledge actions report failures through the same alert the
/// Partners tab shows; nothing fails silently here either.
struct PartnersStatementHost: View {
    @StateObject private var vm = PartnersModel()

    var body: some View {
        PartnersStatementView(vm: vm)
            .navigationDestination(for: PartnersRoute.self) { route in
                switch route {
                case .pledge(let id):
                    PledgeDetailView(pledgeId: id, seed: vm.partnership?.pledges.first { $0.pledgeId == id }, vm: vm)
                case .receipt(let tx):
                    GivingReceiptView(transactionId: tx)
                case .partnersStatement:
                    PartnersStatementView(vm: vm)
                case .statement:
                    GivingStatementView()
                }
            }
            .alert("That didn't go through", isPresented: Binding(get: { vm.actionError != nil }, set: { if !$0 { vm.actionError = nil } })) {
                Button("OK") { vm.actionError = nil }
            } message: { Text(vm.actionError ?? "") }
    }
}

// MARK: - A pledge payment still processing (`pending[]`)

/// Shown at the top of PAYMENTS (and of the Partners tab's preview) with an
/// amber chip — "Waiting for M-Pesa" while an STK prompt is out, else
/// "Processing". The amount is muted: it is NEVER counted in any total until
/// the server settles it and it moves into the ledger below.
struct PendingPledgePaymentRow: View {
    let payment: PledgePayment
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
                HStack(spacing: 6) {
                    Text(chipText)
                        .font(.inter(10, .bold)).foregroundStyle(Nuru.urgentText)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Nuru.urgentBg, in: Capsule())
                    if giveParseDate(payment.at) != nil {
                        Text(giveDateShort(payment.at)).font(.inter(11)).foregroundStyle(Nuru.ink400)
                    }
                }
            }
            Spacer(minLength: 8)
            Text(money(payment.amountMinor, payment.currency))
                .font(.inter(13, .semibold)).foregroundStyle(Nuru.ink400)
                .lineLimit(1).layoutPriority(1)
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Not yet counted in your totals")
    }

    private var chipText: String {
        switch payment.method {
        case "mpesa": return "Waiting for M-Pesa"
        case "airtel": return "Waiting for Airtel Money"
        default: return "Processing"
        }
    }
}
