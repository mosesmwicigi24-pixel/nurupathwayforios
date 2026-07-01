// Give — the native port of screens/GivingScreen.tsx. A navy hero, "repeat last
// gift", five funds, a big-number amount with presets + a custom keypad, a
// frequency switch, a reorderable pay-method list (M-Pesa / Airtel / Equity /
// Card / Apple-Google / PayPal), cover-the-fee, active schedules, recent giving
// and a sticky CTA. Money is server-authoritative + online-only (§5.6): we
// create a real intent (mobile-money STK / PayPal approve) and NEVER fabricate a
// gift. The card path needs the Stripe SDK (client-side tokenisation, SAQ-A) and
// is flagged "SOON".
import SwiftUI

enum GiveRoute: Hashable { case statement }

// MARK: - Funds

private struct Fund: Identifiable {
    let code, label, tagline: String
    let icon: Lucide
    let tint, fg: UInt32
    var id: String { code }
}
private let funds: [Fund] = [
    Fund(code: "tithe",        label: "Tithe",        tagline: "A faithful portion",  icon: .percent,  tint: 0xFFF4C7, fg: 0xA87F2E),
    Fund(code: "offering",     label: "Offering",     tagline: "Freewill worship",    icon: .handHeart, tint: 0xFEE2E2, fg: 0xB91C1C),
    Fund(code: "gift",         label: "Gift",         tagline: "A special gift",      icon: .gift,     tint: 0xF3E8FF, fg: 0x7E22CE),
    Fund(code: "mission",      label: "Mission",      tagline: "Beyond our walls",    icon: .globe,    tint: 0xE0F2FE, fg: 0x0369A1),
    Fund(code: "discipleship", label: "Discipleship", tagline: "Growing the Pathway", icon: .bookOpen, tint: 0xDCFCE7, fg: 0x166534),
]
private let presets = [200, 500, 1000, 2500, 5000]

// MARK: - Pay methods

private struct PayMethod: Identifiable {
    let key, label, sub: String
    let provider: String?           // nil → "SOON" (no provider wired)
    let badgeText: String           // short logo text inside the disc
    let badgeBg, badgeFg: UInt32    // brand colours for the disc
    let icon: Lucide?               // shown instead of badge text when set
    var id: String { key }
}
private let baseMethods: [PayMethod] = [
    PayMethod(key: "mpesa",  label: "Pay with M-Pesa",            sub: "STK push to your phone", provider: "mpesa",
              badgeText: "M-PESA", badgeBg: 0x16A34A, badgeFg: 0xFFFFFF, icon: nil),
    PayMethod(key: "airtel", label: "Pay with Airtel Money",      sub: "Mobile money",           provider: "airtel",
              badgeText: "AIRTEL", badgeBg: 0xDC2626, badgeFg: 0xFFFFFF, icon: nil),
    PayMethod(key: "equity", label: "Pay with Equity Bank",       sub: "Bank account",           provider: nil,
              badgeText: "", badgeBg: 0x9D174D, badgeFg: 0xFFFFFF, icon: .landmark),
    PayMethod(key: "card",   label: "Pay with Card",              sub: "Visa · Mastercard",      provider: "card",
              badgeText: "", badgeBg: 0xE0E7FF, badgeFg: 0x4338CA, icon: .creditCard),
    PayMethod(key: "applepay", label: "Pay with Apple / Google Pay", sub: "Device wallet",       provider: nil,
              badgeText: "", badgeBg: 0xE0E7FF, badgeFg: 0x4338CA, icon: .wallet),
    PayMethod(key: "paypal", label: "Pay with PayPal",            sub: "PayPal balance / linked", provider: "paypal",
              badgeText: "PP", badgeBg: 0xDBEAFE, badgeFg: 0x1D4ED8, icon: nil),
]

private func feeFor(_ a: Int) -> Int {
    switch a {
    case ...100: return 0
    case ...500: return 7
    case ...1000: return 13
    case ...1500: return 23
    case ...2500: return 33
    case ...3500: return 53
    case ...5000: return 57
    default: return Int((Double(a) * 0.012).rounded())
    }
}

// MARK: - View model

@MainActor
final class GivingViewModel: ObservableObject {
    @Published var history: [GivingRecord] = []
    @Published var schedules: [GivingSchedule] = []
    @Published var loading = true

    func load() async {
        loading = true
        async let h = MemberAPI.givingHistory()
        async let s = MemberAPI.schedules()
        history = (try? await h) ?? []
        schedules = (try? await s) ?? []
        loading = false
    }

    var yearTotalMinor: Int {
        let yr = Calendar.current.component(.year, from: Date())
        let settled: Set<String> = ["succeeded", "settled", "completed"]
        return history
            .filter { settled.contains($0.status) && $0.createdAt.prefix(4) == String(yr) }
            .reduce(0) { $0 + $1.amountMinor }
    }
    var lastGift: GivingRecord? { history.first }
}

// MARK: - Give

struct GivingView: View {
    @StateObject private var vm = GivingViewModel()

    @State private var fundCode = "tithe"
    @State private var amount = 200
    @State private var method = "mpesa"
    @State private var methodOrder = baseMethods.map(\.key)
    @State private var freq = "once"          // once | weekly | monthly
    @State private var coverFee = false
    @State private var mpesaPhone = "+254700706875"

    @State private var submitting = false
    @State private var showKeypad = false
    @State private var showMpesaSheet = false
    @State private var ceremony: String?      // nil | "stk" | "success" | "failed"
    @State private var ceremonyNote = ""

    private var fund: Fund { funds.first { $0.code == fundCode } ?? funds[0] }
    private var fee: Int { coverFee ? feeFor(amount) : 0 }
    private var total: Int { amount + fee }
    private var orderedMethods: [PayMethod] {
        methodOrder.compactMap { k in baseMethods.first { $0.key == k } }
    }
    private var freqLabel: String {
        switch freq { case "weekly": return "weekly"; case "monthly": return "monthly"; default: return "one-time" }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Nuru.paper.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Nuru.S.md) {
                        if let g = vm.lastGift { repeatCard(g) }
                        fundsSection
                        amountCard
                        frequencyRow
                        methodSection
                        coverFeeRow
                        if !vm.schedules.isEmpty { schedulesSection }
                        recentSection
                        scriptureStrip
                        secureNote
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.lg)
                    .padding(.bottom, Nuru.tabBarSpace + 80)
                }
                .safeAreaInset(edge: .top, spacing: 0) { headerBlock }
                ctaBar
            }
            .ignoresSafeArea(edges: .top)
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GivingRecord.self) { GivingReceiptView(transactionId: $0.transactionId) }
            .navigationDestination(for: GiveRoute.self) { _ in GivingStatementView() }
        }
        .task { if vm.history.isEmpty { await vm.load() } }
        .sheet(isPresented: $showKeypad) { keypadSheet }
        .sheet(isPresented: $showMpesaSheet) { mpesaSheet }
        .sheet(isPresented: Binding(get: { ceremony != nil }, set: { if !$0 { ceremony = nil } })) {
            ceremonySheet
        }
    }

    // MARK: Header (navy hero, rounded bottom)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GIVE")
                .font(.inter(9, .bold)).kerning(1.62).foregroundStyle(Color(hex: 0x9A7A2A))
            Text("Sow into the Kingdom")
                .font(.fraunces(24, .semibold)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .padding(.top, 4)
            Text("Generosity is worship — a quiet, joyful act.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x68758A))
                .padding(.top, 4)

            HStack(spacing: 8) {
                Icon(.badgeCheck, size: 14, color: Nuru.gold)
                Text("KSh \((vm.yearTotalMinor / 100).formatted(.number.grouping(.automatic))) given this year")
                    .font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Nuru.gold.opacity(0.45), lineWidth: 1))
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 20)
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

    // MARK: Repeat last gift

    private func repeatCard(_ g: GivingRecord) -> some View {
        Button { applyRepeat(g) } label: {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.goldChipBg)
                        .frame(width: 44, height: 44)
                    Icon(.repeat, size: 18, color: Nuru.goldLo)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Repeat last gift").font(.inter(15, .bold)).foregroundStyle(Nuru.ink)
                    Text("Ksh \((g.amountMinor / 100).formatted(.number.grouping(.automatic))) · \(g.fund.capitalized) · Via \(methodName(g.method))")
                        .font(.inter(12)).foregroundStyle(Nuru.muted).lineLimit(1)
                }
                Spacer(minLength: Nuru.S.sm)
                Text("Give again")
                    .font(.inter(13, .bold)).foregroundStyle(Nuru.ink)
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.goldTint.opacity(0.55), in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Funds

    private var fundsSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            overline("CHOOSE A FUND")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Nuru.S.md) {
                    ForEach(funds) { f in
                        let on = f.code == fundCode
                        Button { fundCode = f.code } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(hex: f.tint))
                                        .frame(width: 36, height: 36)
                                    Icon(f.icon, size: 17, color: Color(hex: f.fg))
                                }
                                Text(f.label).font(.inter(14, .bold)).foregroundStyle(Nuru.ink)
                                Text(f.tagline).font(.inter(11)).foregroundStyle(Nuru.muted).lineLimit(1)
                            }
                            .frame(width: 124, alignment: .leading)
                            .padding(12)
                            .background(on ? Nuru.priorityBg : Nuru.white,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 2 : 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: Amount

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            overline("AMOUNT")
            Button { showKeypad = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("KSh").font(.fraunces(22, .semibold)).foregroundStyle(Nuru.ink300)
                    Text(amount.formatted(.number.grouping(.automatic)))
                        .font(.fraunces(38, .bold)).foregroundStyle(Nuru.ink)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            Text("\(fund.label) · \(freqLabel)").font(.inter(13)).foregroundStyle(Nuru.muted)

            FlowWrap(spacing: Nuru.S.sm) {
                ForEach(presets, id: \.self) { v in
                    let on = amount == v
                    Button { amount = v } label: {
                        Text(v.formatted(.number.grouping(.automatic)))
                            .font(.inter(13, .semibold)).foregroundStyle(on ? .white : Nuru.ink)
                            .padding(.horizontal, 18).frame(height: 38)
                            .background(on ? Nuru.navy : Nuru.surface, in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                Button { showKeypad = true } label: {
                    Text("Custom")
                        .font(.inter(13, .semibold)).foregroundStyle(Nuru.goldLo)
                        .padding(.horizontal, 18).frame(height: 38)
                        .overlay(Capsule().stroke(Nuru.gold, lineWidth: 1))
                }.buttonStyle(.plain)
            }
        }
        .padding(Nuru.S.base).giveCard()
    }

    // MARK: Frequency

    private var frequencyRow: some View {
        HStack(spacing: 4) {
            ForEach([("once", "One-time"), ("weekly", "Weekly"), ("monthly", "Monthly")], id: \.0) { key, label in
                let on = freq == key
                Button { freq = key } label: {
                    Text(label)
                        .font(.inter(14, on ? .semibold : .regular))
                        .foregroundStyle(on ? Nuru.ink : Nuru.muted)
                        .frame(maxWidth: .infinity).frame(height: 44)
                        .background(on ? Nuru.white : .clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        .nuruShadow(on ? 1 : 0)
                }.buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color(hex: 0x0A2540, alpha: 0.06),
                    in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }

    // MARK: Pay methods

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                overline("CHOOSE HOW TO PAY")
                Spacer()
                HStack(spacing: 5) {
                    Icon(.gripVertical, size: 12, color: Nuru.ink300)
                    Text("Drag to reorder").font(.inter(12, .semibold)).foregroundStyle(Nuru.muted)
                }
            }
            VStack(spacing: Nuru.S.md) {
                ForEach(Array(orderedMethods.enumerated()), id: \.element.id) { idx, m in
                    methodRow(m, index: idx)
                }
            }
        }
    }

    @ViewBuilder
    private func methodRow(_ m: PayMethod, index: Int) -> some View {
        let on = method == m.key
        let soon = m.provider == nil
        Button { if !soon { method = m.key } } label: {
            HStack(spacing: Nuru.S.md) {
                methodBadge(m)
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.label).font(.inter(14, .bold)).foregroundStyle(Nuru.ink)
                    if on && m.key == "mpesa" {
                        Text(mpesaPhone).font(.inter(11)).foregroundStyle(Nuru.muted)
                    } else {
                        Text(m.sub).font(.inter(11)).foregroundStyle(Nuru.muted)
                    }
                }
                Spacer(minLength: Nuru.S.sm)
                if soon {
                    Text("SOON")
                        .font(.inter(10, .bold)).kerning(0.5).foregroundStyle(Nuru.goldChipText)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Nuru.goldChipBg, in: Capsule())
                }
                if on {
                    ZStack {
                        Circle().fill(Nuru.gold).frame(width: 24, height: 24)
                        Icon(.check, size: 13, color: .white)
                    }
                }
                VStack(spacing: 2) {
                    Button { moveMethod(from: index, by: -1) } label: {
                        Icon(.chevronUp, size: 14, color: Nuru.ink300)
                    }.buttonStyle(.plain).disabled(index == 0)
                    Button { moveMethod(from: index, by: 1) } label: {
                        Icon(.chevronDown, size: 14, color: Nuru.ink300)
                    }.buttonStyle(.plain).disabled(index == orderedMethods.count - 1)
                }
                Icon(.gripVertical, size: 15, color: Nuru.ink300)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(on ? Nuru.goldTint.opacity(0.45) : Nuru.white,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 2 : 1))
            .opacity(soon ? 0.7 : 1)
        }
        .buttonStyle(.plain)
    }

    private func methodBadge(_ m: PayMethod) -> some View {
        ZStack {
            Circle().fill(Color(hex: m.badgeBg)).frame(width: 40, height: 40)
            if let icon = m.icon {
                Icon(icon, size: 17, color: Color(hex: m.badgeFg))
            } else {
                Text(m.badgeText)
                    .font(.inter(m.badgeText.count > 3 ? 7 : 11, .heavy))
                    .foregroundStyle(Color(hex: m.badgeFg))
                    .minimumScaleFactor(0.5).lineLimit(1).padding(.horizontal, 2)
            }
        }
    }

    // MARK: Cover fee

    private var coverFeeRow: some View {
        Toggle(isOn: $coverFee) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Cover the transaction fee").font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                Text("100% of your gift reaches the fund").font(.inter(12)).foregroundStyle(Nuru.muted)
            }
        }
        .tint(Nuru.gold)
        .padding(Nuru.S.base).giveCard()
    }

    // MARK: Active schedules

    private var schedulesSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            overline("ACTIVE SCHEDULES")
            let cols = [GridItem(.flexible(), spacing: Nuru.S.md), GridItem(.flexible(), spacing: Nuru.S.md)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: Nuru.S.md) {
                ForEach(vm.schedules) { s in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Icon(.repeat, size: 13, color: Nuru.goldLo)
                            Text(s.frequency.uppercased())
                                .font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.goldLo)
                        }
                        Text("KSh \((s.amountMinor / 100).formatted(.number.grouping(.automatic)))")
                            .font(.fraunces(20, .semibold)).foregroundStyle(Nuru.ink)
                        Text(s.fund.capitalized).font(.inter(12)).foregroundStyle(Nuru.muted)
                        Text("Next \(shortDate(s.nextRunAt))").font(.inter(11)).foregroundStyle(Nuru.faint)
                            .padding(.top, 2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
            }
        }
    }

    // MARK: Recent giving

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack {
                overline("RECENT GIVING")
                Spacer()
                // Always reachable — the statement page has its own empty state, so the
                // giving record + receipts stay discoverable even before the first gift.
                NavigationLink(value: GiveRoute.statement) {
                    HStack(spacing: 3) {
                        Text("View statement").font(.inter(13, .semibold))
                        Icon(.chevronRight, size: 12, color: Nuru.goldLo)
                    }.foregroundStyle(Nuru.goldLo)
                }
            }
            VStack(spacing: 0) {
                if vm.history.isEmpty {
                    Text("Your gifts will appear here.")
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, Nuru.S.sm)
                } else {
                    let rows = Array(vm.history.prefix(5))
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, g in
                        NavigationLink(value: g) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(g.fund.capitalized).font(.inter(15, .bold)).foregroundStyle(Nuru.ink)
                                    Text("\(shortDate(g.createdAt)) · \(methodName(g.method))")
                                        .font(.inter(12)).foregroundStyle(Nuru.muted)
                                }
                                Spacer()
                                Text("KSh \((g.amountMinor / 100).formatted(.number.grouping(.automatic)))")
                                    .font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
                            }
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.plain)
                        if i != rows.count - 1 { Divider().overlay(Nuru.border) }
                    }
                }
            }
            .padding(.horizontal, Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
    }

    // MARK: Scripture + secure note

    private var scriptureStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\u{201C}")
                .font(.fraunces(34, .bold)).foregroundStyle(Nuru.gold.opacity(0.5))
                .frame(height: 18, alignment: .top)
            Text("Each of you should give what you have decided in your heart to give.")
                .font(.fraunces(16, .medium)).italic().foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("— 2 Corinthians 9:7").font(.inter(12, .semibold)).foregroundStyle(Nuru.goldLo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.lg)
        .background(Nuru.goldTint.opacity(0.4), in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
    }

    private var secureNote: some View {
        HStack(spacing: 7) {
            Icon(.shieldCheck, size: 14, color: Nuru.muted)
            Text("Secure · M-Pesa & card · Receipt sent instantly")
                .font(.inter(12)).foregroundStyle(Nuru.muted)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 2)
    }

    // MARK: Sticky CTA

    private var ctaBar: some View {
        VStack(spacing: 0) {
            PButton(title: submitting ? "Processing…" : "Give KSh \((total).formatted(.number.grouping(.automatic)))  →",
                    variant: .gold, busy: submitting) {
                Task { await give() }
            }
        }
        .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.md).padding(.bottom, 28)
        .background(Nuru.paper.opacity(0.97))
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }

    // MARK: Keypad sheet

    private var keypadSheet: some View {
        VStack(spacing: Nuru.S.lg) {
            overline("CUSTOM AMOUNT · \(fund.label.uppercased())").padding(.top, Nuru.S.lg)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("KSh").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.ink300)
                Text(amount.formatted(.number.grouping(.automatic)))
                    .font(.fraunces(48, .bold)).foregroundStyle(Nuru.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            let keys = ["1","2","3","4","5","6","7","8","9","00","0","del"]
            let cols = Array(repeating: GridItem(.flexible(), spacing: Nuru.S.md), count: 3)
            LazyVGrid(columns: cols, spacing: Nuru.S.base) {
                ForEach(keys, id: \.self) { k in
                    Button { tapKey(k) } label: {
                        Group {
                            if k == "del" { Icon(.x, size: 20, color: Nuru.ink) }
                            else { Text(k).font(.fraunces(26, .medium)).foregroundStyle(Nuru.ink) }
                        }
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
            PButton(title: "Give KSh \((amount).formatted(.number.grouping(.automatic)))", variant: .gold) {
                showKeypad = false
            }
        }
        .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.lg)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func tapKey(_ k: String) {
        var s = amount == 0 ? "" : String(amount)
        switch k {
        case "del": s = String(s.dropLast())
        case "00": s += "00"
        default: s += k
        }
        if s.count > 9 { s = String(s.prefix(9)) }
        amount = Int(s) ?? 0
    }

    // MARK: M-Pesa number sheet

    private var mpesaSheet: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            HStack {
                overline("M-PESA NUMBER")
                Spacer()
                Button { showMpesaSheet = false } label: { Icon(.x, size: 18, color: Nuru.muted) }
                    .buttonStyle(.plain)
            }
            .padding(.top, Nuru.S.lg)
            Text("We'll send the payment prompt to this number.")
                .font(.inter(13)).foregroundStyle(Nuru.muted)
            HStack(spacing: Nuru.S.sm) {
                Icon(.smartphone, size: 16, color: Nuru.muted)
                TextField("+254…", text: $mpesaPhone)
                    .keyboardType(.phonePad)
                    .font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
            }
            .padding(.horizontal, Nuru.S.base).frame(height: 52)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))

            PButton(title: "Give Now", variant: .gold, busy: submitting) {
                showMpesaSheet = false
                Task { await submitIntent(provider: "mpesa", currency: "KES", phone: mpesaPhone) }
            }
            Text("Used only for this transaction prompt")
                .font(.inter(12)).foregroundStyle(Nuru.faint)
                .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.lg)
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
    }

    // MARK: Ceremony

    @ViewBuilder
    private var ceremonySheet: some View {
        VStack(spacing: Nuru.S.lg) {
            Spacer()
            if ceremony == "stk" {
                Icon(.clock, size: 44, color: Nuru.gold)
                Text("Check your phone").font(.nTitle).foregroundStyle(Nuru.ink)
                Text(ceremonyNote.isEmpty ? "Approve the prompt to complete your KSh \((total).formatted(.number.grouping(.automatic))) gift." : ceremonyNote)
                    .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            } else if ceremony == "success" {
                Icon(.badgeCheck, size: 44, color: Nuru.success)
                Text("Thank you!").font(.nTitle).foregroundStyle(Nuru.ink)
                Text("Your KSh \((total).formatted(.number.grouping(.automatic))) gift to \(fund.label) is received.")
                    .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            } else {
                Icon(.x, size: 44, color: Nuru.danger)
                Text("Couldn't complete").font(.nTitle).foregroundStyle(Nuru.ink)
                Text(ceremonyNote.isEmpty ? "No charge was made. Please try again." : ceremonyNote)
                    .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            }
            Spacer()
            PButton(title: "Done", variant: .navy) { ceremony = nil; Task { await vm.load() } }
        }
        .padding(Nuru.S.screen)
        .presentationDetents([.medium])
    }

    // MARK: Actions

    private func give() async {
        guard amount > 0 else { return }
        guard let provider = baseMethods.first(where: { $0.key == method })?.provider else {
            ceremonyNote = "This method is coming soon."; ceremony = "failed"; return
        }
        switch provider {
        case "mpesa", "airtel":
            // Mobile money: confirm the number, then push the STK prompt.
            showMpesaSheet = true
        case "card":
            // Card requires the Stripe SDK (client-side tokenisation, SAQ-A) — not
            // yet integrated. Surfaced rather than faked.
            ceremonyNote = "Card giving needs the Stripe step — coming soon. Try M-Pesa for now."
            ceremony = "failed"
        case "paypal":
            await submitIntent(provider: "paypal", currency: "USD", phone: nil)
        default:
            ceremonyNote = "This method is coming soon."; ceremony = "failed"
        }
    }

    private func submitIntent(provider: String, currency: String, phone: String?) async {
        guard amount > 0 else { return }
        submitting = true; defer { submitting = false }
        do {
            let res = try await MemberAPI.giving(fund: fund.code, amountMinor: total * 100,
                                                 currency: currency, method: provider, phoneNumber: phone)
            if provider == "paypal", let url = res.approveUrl.flatMap(URL.init) {
                await UIApplication.shared.open(url)
                ceremonyNote = "Approve in PayPal, then return to the app."; ceremony = "stk"
            } else {
                ceremonyNote = ""; ceremony = "stk"   // mobile-money STK push
            }
        } catch {
            ceremonyNote = (error as? APIError)?.errorDescription ?? "Something went wrong."
            ceremony = "failed"
        }
    }

    private func applyRepeat(_ g: GivingRecord) {
        amount = g.amountMinor / 100
        if funds.contains(where: { $0.code == g.fund }) { fundCode = g.fund }
        if let m = g.method, baseMethods.contains(where: { $0.key == m }) { method = m }
    }

    private func moveMethod(from index: Int, by delta: Int) {
        let to = index + delta
        guard to >= 0, to < methodOrder.count else { return }
        var arr = methodOrder
        // map ordered index back to underlying key
        let key = orderedMethods[index].key
        if let realIdx = arr.firstIndex(of: key) {
            arr.remove(at: realIdx)
            arr.insert(key, at: max(0, min(arr.count, realIdx + delta)))
            methodOrder = arr
        }
    }

    // MARK: Helpers

    private func overline(_ s: String) -> some View {
        Text(s).font(.inter(11, .bold)).kerning(1.5).foregroundStyle(Nuru.ink600)
    }

    private func methodName(_ raw: String?) -> String {
        switch raw {
        case "mpesa": return "M-Pesa"
        case "airtel": return "Airtel Money"
        case "card": return "Card"
        case "paypal": return "PayPal"
        case .some(let s): return s.capitalized
        case .none: return "M-Pesa"
        }
    }

    private func shortDate(_ iso: String) -> String {
        let inFmt = ISO8601DateFormatter()
        inFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = inFmt.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
            ?? parseLoose(iso)
        guard let d = date else { return String(iso.prefix(10)) }
        let out = DateFormatter(); out.dateFormat = "MMM d"
        return out.string(from: d)
    }
    private func parseLoose(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        return f.date(from: String(s.prefix(10)))
    }
}

// MARK: - Card chrome

private extension View {
    func giveCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}

// MARK: - Simple wrapping HStack (preset pills + Custom)

private struct FlowWrap: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x - bounds.minX + s.width > maxWidth, x > bounds.minX {
                x = bounds.minX; y += rowH + spacing; rowH = 0
            }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowH = max(rowH, s.height)
        }
    }
}
