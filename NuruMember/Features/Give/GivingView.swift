// Give — the native port of the Figma GiveTab (Final Pathway Portal make). A cream
// hero, "repeat last gift", five funds, a centred big-number amount with presets +
// a custom keypad, a frequency switch with an honest recurring summary, a
// reorderable pay-method list (M-Pesa / Airtel / Equity / Card / Apple-Google /
// PayPal) with brand badges, cover-the-fee, active schedules (tap to manage or
// cancel), recent giving, a scripture strip and a quiet sticky CTA. Money is
// server-authoritative + online-only (§5.6): we create a real intent (mobile-money
// STK / PayPal approve) or a real server-charged schedule and NEVER fabricate a
// payment state — the ceremony polls GET /giving/transactions/{id} for the true
// outcome. The card path needs the Stripe SDK (SAQ-A tokenisation) and stays SOON.
import SwiftUI
import UIKit

enum GiveRoute: Hashable { case statement }

// MARK: - Funds (exact Figma palette)

private struct Fund: Identifiable {
    let code, label, tagline: String
    let icon: Lucide
    let tint, fg: UInt32
    var id: String { code }
}
private let funds: [Fund] = [
    Fund(code: "tithe",        label: "Tithe",        tagline: "A faithful portion",  icon: .percent,   tint: 0xFFF4DA, fg: 0xC89B3C),
    Fund(code: "offering",     label: "Offering",     tagline: "Freewill worship",    icon: .handHeart, tint: 0xFEE2E2, fg: 0xDC2626),
    Fund(code: "gift",         label: "Gift",         tagline: "A special gift",      icon: .gift,      tint: 0xF3E8FF, fg: 0xA855F7),
    Fund(code: "mission",      label: "Mission",      tagline: "Beyond our walls",    icon: .globe,     tint: 0xE0F2FE, fg: 0x0EA5E9),
    Fund(code: "discipleship", label: "Discipleship", tagline: "Growing the Pathway", icon: .bookOpen,  tint: 0xDCFCE7, fg: 0x16A34A),
]
private let presets = [200, 500, 1000, 2500, 5000]

// MARK: - Pay methods (Figma brand badges — square, rounded-xl)

private struct PayMethod: Identifiable {
    let key, label, sub: String
    let provider: String?           // nil → "SOON" (no provider wired)
    let badgeText: String           // short logo text inside the badge
    let badgeBg, badgeFg: UInt32    // brand colours for the badge
    let icon: Lucide?               // shown instead of badge text when set
    var id: String { key }
}
private let baseMethods: [PayMethod] = [
    PayMethod(key: "mpesa",    label: "Pay with M-Pesa",             sub: "STK push to your phone",  provider: "mpesa",
              badgeText: "M-PESA", badgeBg: 0x16A34A, badgeFg: 0xFFFFFF, icon: nil),
    PayMethod(key: "airtel",   label: "Pay with Airtel Money",       sub: "Mobile money",            provider: "airtel",
              badgeText: "AIRTEL", badgeBg: 0xDC2626, badgeFg: 0xFFFFFF, icon: nil),
    PayMethod(key: "equity",   label: "Pay with Equity Bank",        sub: "Bank account",            provider: nil,
              badgeText: "", badgeBg: 0xA6093D, badgeFg: 0xFFFFFF, icon: .landmark),
    PayMethod(key: "card",     label: "Pay with Card",               sub: "Visa · Mastercard",       provider: "card",
              badgeText: "", badgeBg: 0xEEF2FF, badgeFg: 0x6366F1, icon: .creditCard),
    PayMethod(key: "applepay", label: "Pay with Apple / Google Pay", sub: "Device wallet",           provider: nil,
              badgeText: "", badgeBg: 0xEEF2FF, badgeFg: 0x6366F1, icon: .wallet),
    PayMethod(key: "paypal",   label: "Pay with PayPal",             sub: "PayPal balance / linked", provider: "paypal",
              badgeText: "PP", badgeBg: 0xE8F1FB, badgeFg: 0x0070BA, icon: nil),
]

private let registeredPhone = "+254700706875"

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

func giveDateShort(_ iso: String) -> String {
    guard let d = giveParseDate(iso) else { return String(iso.prefix(10)) }
    let f = DateFormatter(); f.dateFormat = "d MMM"
    return f.string(from: d)
}

func giveDateFull(_ iso: String) -> String {
    guard let d = giveParseDate(iso) else { return String(iso.prefix(10)) }
    let f = DateFormatter(); f.dateFormat = "d MMM yyyy"
    return f.string(from: d)
}

func giveTime(_ iso: String) -> String {
    guard let d = giveParseDate(iso) else { return "" }
    let f = DateFormatter(); f.dateFormat = "h:mm a"
    return f.string(from: d)
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
    @Environment(\.scenePhase) private var scenePhase

    @State private var fundCode = "tithe"
    @State private var amount = 1000
    @State private var method = "mpesa"
    @State private var methodOrder = baseMethods.map(\.key)
    @State private var freq = "once"          // once | weekly | monthly
    @State private var coverFee = false
    @State private var mpesaPhone = registeredPhone

    @State private var submitting = false
    @State private var showKeypad = false
    @State private var showMpesaSheet = false
    @State private var scheduleDetail: GivingSchedule?
    @State private var ceremony: String?      // nil | stk | success | failed | scheduled
    @State private var ceremonyNote = ""
    @State private var pendingTxId: String?
    @State private var successRef: String?
    @State private var scheduledNextAt = ""
    @State private var pollTask: Task<Void, Never>?
    /// PayPal order id (the intent's provider_ref) for the in-flight gift —
    /// captured after the member approves on PayPal, then cleared.
    @State private var paypalOrderId: String?
    @State private var paypalCaptureTask: Task<Void, Never>?

    private var fund: Fund { funds.first { $0.code == fundCode } ?? funds[0] }
    private var fee: Int { coverFee ? feeFor(amount) : 0 }
    private var total: Int { amount + fee }
    private var recurring: Bool { freq != "once" }
    private var cadenceWord: String { freq == "weekly" ? "week" : "month" }
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
                        if recurring {
                            recurringSummary.transition(.opacity.combined(with: .move(edge: .top)))
                        }
                        methodSection
                        coverFeeRow
                        if !vm.schedules.isEmpty { schedulesSection }
                        recentSection
                        scriptureStrip
                        secureNote
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
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
        // Returning from the PayPal approval in Safari → nudge the capture.
        .onChange(of: scenePhase) { _, p in
            if p == .active { attemptPayPalCapture() }
        }
        .sheet(isPresented: $showKeypad) {
            GiveKeypadSheet(initial: amount, fundLabel: fund.label) { amount = $0 }
        }
        .sheet(isPresented: $showMpesaSheet) {
            MobileMoneySheet(methodKey: method, phone: $mpesaPhone) {
                let provider = method == "airtel" ? "airtel" : "mpesa"
                Task { await submitIntent(provider: provider, currency: "KES", phone: mpesaPhone) }
            }
        }
        .sheet(item: $scheduleDetail) { s in
            ScheduleDetailSheet(schedule: s,
                                onClose: { scheduleDetail = nil },
                                onCancelled: { scheduleDetail = nil; Task { await vm.load() } })
        }
        .fullScreenCover(isPresented: Binding(get: { ceremony != nil }, set: { if !$0 { endCeremony() } })) {
            GiveCeremonyView(stage: ceremony ?? "failed",
                             note: ceremonyNote,
                             amountLabel: ksh(total),
                             fundLabel: fund.label,
                             phone: (method == "mpesa" || method == "airtel") ? mpesaPhone : nil,
                             refCode: successRef,
                             txId: pendingTxId,
                             cadenceWord: cadenceWord,
                             nextChargeLabel: scheduledNextAt.isEmpty ? nil : giveDateFull(scheduledNextAt),
                             onDone: { endCeremony() },
                             onRetry: { endCeremony(); Task { await give() } })
        }
    }

    // MARK: Header (cream hero — matches the Figma header; do not restyle)

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("GIVE")
                .font(.inter(9, .bold)).kerning(1.62).foregroundStyle(Color(hex: 0x9A7A2A))
            Text("Sow into the Kingdom")
                .font(.fraunces(24, .semibold)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .padding(.top, 4)
            Text("Generosity is worship — a quiet, joyful act.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
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
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { applyRepeat(g) }
        } label: {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.gold)
                        .frame(width: 36, height: 36)
                    Icon(.repeat, size: 16, color: Nuru.navy)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeat last gift").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    Text("\(ksh(g.amountMinor / 100)) · \(g.fund.capitalized) · via \(givingMethodName(g.method))")
                        .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472)).lineLimit(1)
                }
                Spacer(minLength: Nuru.S.sm)
                Text("Give again")
                    .font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
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
                    Icon(f.icon, size: 17, color: Color(hex: f.fg))
                }
                Text(f.label).font(.inter(13, .semibold)).kerning(-0.13).foregroundStyle(Nuru.navy)
                    .lineLimit(1).minimumScaleFactor(0.85)
                    .padding(.top, 8)
                Text(f.tagline).font(.inter(10)).foregroundStyle(Color(hex: 0x5B6472))
                    .lineLimit(2).truncationMode(.tail).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
            .frame(width: 124, alignment: .leading)
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
                    Text("AMOUNT").font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("KSh").font(.inter(14, .medium)).foregroundStyle(Color(hex: 0x74808F))
                        Text(amount.formatted(.number.grouping(.automatic)))
                            .font(.fraunces(42, .semibold)).kerning(-1.2).foregroundStyle(Nuru.navy)
                            .contentTransition(.numericText(value: Double(amount)))
                    }
                    Text("\(fund.label) · \(freqLabel)").font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            presetsRow.padding(.top, Nuru.S.base)
        }
        .padding(Nuru.S.screen)
        .frame(maxWidth: .infinity)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private var presetsRow: some View {
        FlowWrap(spacing: 6, centered: true) {
            ForEach(presets, id: \.self) { v in
                let on = amount == v
                Button {
                    guard !on else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { amount = v }
                } label: {
                    Text(v.formatted(.number.grouping(.automatic)))
                        .font(.inter(13, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
                        .padding(.horizontal, 14).frame(height: 34)
                        .background(on ? Nuru.navy : Nuru.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                }.buttonStyle(.pressable)
            }
            Button {
                Haptics.tap()
                showKeypad = true
            } label: {
                Text("Custom")
                    .font(.inter(13, .bold)).foregroundStyle(Nuru.gold)
                    .padding(.horizontal, 14).frame(height: 34)
                    .background(Nuru.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.gold, lineWidth: 1))
            }.buttonStyle(.pressable)
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
            }
        }
        .padding(4)
        .background(Color(hex: 0x0A2540, alpha: 0.06),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Honest recurring summary — the server charges on the NEXT cycle boundary
    /// (backend createSchedule), so we say exactly that.
    private var recurringSummary: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.gold)
                    .frame(width: 36, height: 36)
                Icon(.repeat, size: 16, color: Nuru.navy)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(ksh(total)) every \(cadenceWord)")
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text("First charge \(giveDateFull(nextCycleISO())) · then every \(cadenceWord). Cancel anytime.")
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

    private func nextCycleISO() -> String {
        let cal = Calendar.current
        let next = freq == "weekly"
            ? cal.date(byAdding: .day, value: 7, to: Date())
            : cal.date(byAdding: .month, value: 1, to: Date())
        return ISO8601DateFormatter().string(from: next ?? Date())
    }

    // MARK: Pay methods

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack {
                overline("CHOOSE HOW TO PAY")
                Spacer()
                HStack(spacing: 4) {
                    Icon(.gripVertical, size: 11, color: Color(hex: 0x74808F))
                    Text("Reorder").font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
                }
            }
            VStack(spacing: Nuru.S.sm) {
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
        HStack(spacing: 8) {
            Button {
                guard !soon, method != m.key else { return }
                Haptics.selection()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { method = m.key }
            } label: {
                HStack(spacing: Nuru.S.md) {
                    methodBadge(m)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.label).font(.inter(14, .semibold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                            .lineLimit(1).minimumScaleFactor(0.85)
                        if on {
                            Text(activeDetail(m)).font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472)).lineLimit(1)
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
                            Icon(.check, size: 13, color: Nuru.navy)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
            Icon(.gripVertical, size: 16, color: Color(hex: 0xC4C9D0))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(on ? Nuru.priorityBg : Nuru.white,
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 1.5 : 1))
        .opacity(soon ? 0.7 : 1)
    }

    private func activeDetail(_ m: PayMethod) -> String {
        (m.key == "mpesa" || m.key == "airtel") ? mpesaPhone : m.sub
    }

    private func methodBadge(_ m: PayMethod) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: m.badgeBg)).frame(width: 40, height: 40)
            if let icon = m.icon {
                Icon(icon, size: 18, color: Color(hex: m.badgeFg))
            } else {
                Text(m.badgeText)
                    .font(.inter(m.badgeText.count > 3 ? 8 : 11, .heavy)).kerning(-0.2)
                    .foregroundStyle(Color(hex: m.badgeFg))
                    .minimumScaleFactor(0.5).lineLimit(1).padding(.horizontal, 2)
            }
        }
    }

    // MARK: Cover fee

    private var coverFeeRow: some View {
        Toggle(isOn: $coverFee) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Cover the transaction fee").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Text("Adds \(ksh(feeFor(amount))) — 100% reaches the fund")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
            }
        }
        .tint(Nuru.gold)
        .padding(12)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .onChange(of: coverFee) { _, _ in Haptics.tap() }
    }

    // MARK: Active schedules (horizontal scroll, tap to manage)

    private var schedulesSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            overline("ACTIVE SCHEDULES")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(vm.schedules) { s in
                        Button {
                            Haptics.tap()
                            scheduleDetail = s
                        } label: { scheduleCard(s) }
                            .buttonStyle(.pressable)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func scheduleCard(_ s: GivingSchedule) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Icon(.repeat, size: 12, color: Nuru.gold)
                Text(s.frequency == "weekly" ? "WEEKLY" : "MONTHLY")
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xA8861C))
            }
            Text(ksh(s.amountMinor / 100))
                .font(.inter(15, .bold)).kerning(-0.15).foregroundStyle(Nuru.navy)
                .lineLimit(1).minimumScaleFactor(0.8)
                .padding(.top, 5)
            Text(s.fund.capitalized).font(.nCardBody).foregroundStyle(Color(hex: 0x5B6472))
                .lineLimit(1).truncationMode(.tail)
                .padding(.top, 1)
            Text("Next \(giveDateShort(s.nextRunAt))").font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                .lineLimit(1)
                .padding(.top, 5)
        }
        .frame(width: 150, alignment: .leading)
        .padding(12)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Recent giving

    private var recentGifts: [GivingRecord] {
        let settled: Set<String> = ["succeeded", "settled", "completed"]
        return Array(vm.history.filter { settled.contains($0.status) }.prefix(3))
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                overline("RECENT GIVING")
                Spacer()
                // Always reachable — the statement page has its own empty state, so the
                // giving record + receipts stay discoverable even before the first gift.
                NavigationLink(value: GiveRoute.statement) {
                    HStack(spacing: 3) {
                        Text("View statement").font(.inter(12, .semibold))
                        Icon(.arrowRight, size: 11, color: Nuru.gold)
                    }.foregroundStyle(Nuru.gold)
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

    private func recentRow(_ g: GivingRecord) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(g.fund.capitalized).font(.inter(14, .semibold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                    .lineLimit(1)
                Text("\(giveDateShort(g.createdAt)) · \(givingMethodName(g.method))")
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472)).lineLimit(1)
            }
            Spacer()
            Text(ksh(g.amountMinor / 100))
                .font(.inter(14, .semibold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                .lineLimit(1).layoutPriority(1)
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, 11)
        .contentShape(Rectangle())
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
            Icon(.shieldCheck, size: 13, color: Color(hex: 0x74808F))
            Text("Secure · M-Pesa & card · Receipt sent instantly")
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
                    ProgressView().tint(Nuru.goldLo).scaleEffect(0.8)
                    Text("Processing…")
                } else if recurring {
                    Icon(.repeat, size: 14, color: Nuru.gold)
                    Text("Schedule \(ksh(total)) / \(cadenceWord)")
                } else {
                    Text("Give \(ksh(total))")
                    Icon(.arrowRight, size: 14, color: Nuru.gold)
                }
            }
            .font(.inter(14, .semibold)).foregroundStyle(Nuru.gold)
            .frame(maxWidth: .infinity).frame(height: 44)
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(submitting || amount <= 0)
        .opacity(amount <= 0 ? 0.5 : 1)
        .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.lg).padding(.bottom, 28)
        .background(
            LinearGradient(stops: [.init(color: Nuru.paper.opacity(0), location: 0),
                                   .init(color: Nuru.paper, location: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
        )
    }

    // MARK: Actions

    private func give() async {
        guard amount > 0 else { return }
        guard let m = baseMethods.first(where: { $0.key == method }), let provider = m.provider else {
            ceremonyNote = "This method is coming soon."; ceremony = "failed"; return
        }
        if recurring { await createSchedule(provider: provider); return }
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

    /// POST /giving/schedules — a real server-charged recurring gift. The server
    /// makes the first charge on the next cycle boundary (never faked here).
    private func createSchedule(provider: String) async {
        guard provider == "mpesa" || provider == "airtel" else {
            ceremonyNote = provider == "card"
                ? "Recurring card gifts need the Stripe step — coming soon. Use M-Pesa or Airtel Money."
                : "Recurring gifts work with M-Pesa or Airtel Money for now."
            ceremony = "failed"
            return
        }
        submitting = true; defer { submitting = false }
        struct Body: Encodable {
            let fund: String; let amountMinor: Int; let currency: String
            let frequency: String; let method: String; let idempotencyKey: String
        }
        struct Created: Decodable {
            let scheduleId: String; let status: String; let nextRunAt: String; let reused: Bool
        }
        do {
            let res = try await APIClient.shared.post("giving/schedules",
                body: Body(fund: fund.code, amountMinor: total * 100, currency: "KES",
                           frequency: freq, method: provider, idempotencyKey: UUID().uuidString),
                as: Created.self)
            scheduledNextAt = res.nextRunAt
            ceremony = "scheduled"
            Haptics.success()   // the server really created the schedule
            await vm.load()
        } catch {
            ceremonyNote = (error as? APIError)?.errorDescription ?? "Couldn't create the schedule."
            ceremony = "failed"
            Haptics.error()
        }
    }

    private func submitIntent(provider: String, currency: String, phone: String?) async {
        guard amount > 0 else { return }
        submitting = true; defer { submitting = false }
        paypalOrderId = nil
        do {
            let res = try await MemberAPI.giving(fund: fund.code, amountMinor: total * 100,
                                                 currency: currency, method: provider, phoneNumber: phone)
            pendingTxId = res.transactionId
            successRef = res.providerRef
            if provider == "paypal", let url = res.approveUrl.flatMap(URL.init) {
                // The intent's provider_ref IS the PayPal order id — we capture it
                // once the member approves and comes back (see attemptPayPalCapture).
                paypalOrderId = res.providerRef
                await UIApplication.shared.open(url)
                ceremonyNote = "Approve in PayPal, then return to the app."
            } else {
                ceremonyNote = ""   // mobile-money STK push
            }
            ceremony = "stk"
            let tx = res.transactionId
            pollTask?.cancel()
            pollTask = Task { await watchOutcome(tx) }
        } catch {
            ceremonyNote = (error as? APIError)?.errorDescription ?? "Something went wrong."
            ceremony = "failed"
            Haptics.error()
        }
    }

    /// Polls the REAL transaction for up to ~60s — the ceremony only ever shows
    /// the server's status, never a fabricated one.
    private func watchOutcome(_ txId: String) async {
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if Task.isCancelled || ceremony != "stk" { return }
            guard let d = try? await MemberAPI.givingDetail(txId) else { continue }
            switch d.status {
            case "succeeded", "settled", "completed":
                successRef = d.providerRef ?? String(d.transactionId.prefix(8)).uppercased()
                ceremony = "success"
                Haptics.success()   // only on the server's confirmed outcome
                await vm.load()
                return
            case "failed", "cancelled":
                ceremonyNote = "The payment didn't complete — no charge was made."
                ceremony = "failed"
                Haptics.error()
                return
            default:
                // Still processing. For a PayPal gift the money only moves when WE
                // capture the approved order (§5.6) — nudge that along each tick;
                // the ceremony still keys off the polled status above.
                attemptPayPalCapture()
            }
        }
        if ceremony == "stk" {
            ceremonyNote = "Still processing — your gift will appear in Recent giving once it clears."
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
                // If the 60s poll already lapsed (long PayPal detour), restart it so
                // the ceremony can resolve from the server's status.
                if let tx = pendingTxId, ceremony == "stk" {
                    pollTask?.cancel()
                    pollTask = Task { await watchOutcome(tx) }
                }
            }
        }
    }

    private func endCeremony() {
        pollTask?.cancel(); pollTask = nil
        paypalCaptureTask?.cancel(); paypalCaptureTask = nil
        paypalOrderId = nil
        ceremony = nil; ceremonyNote = ""
        scheduledNextAt = ""
        Task { await vm.load() }
    }

    private func applyRepeat(_ g: GivingRecord) {
        amount = g.amountMinor / 100
        if funds.contains(where: { $0.code == g.fund }) { fundCode = g.fund }
        if let m = g.method, baseMethods.contains(where: { $0.key == m }) { method = m }
    }

    /// Reorder with a light tap and a spring, so rows glide instead of jumping.
    private func nudgeMethod(from index: Int, by delta: Int) {
        Haptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            moveMethod(from: index, by: delta)
        }
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
        Text(s).font(.inter(9, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0xA8861C))
    }
}

// MARK: - Custom keypad sheet (staged value; confirm applies)

private struct GiveKeypadSheet: View {
    let initial: Int
    let fundLabel: String
    var onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value = ""

    private var num: Int { Int(value) ?? 0 }

    var body: some View {
        VStack(spacing: Nuru.S.base) {
            HStack {
                Text("CUSTOM AMOUNT · \(fundLabel.uppercased())")
                    .font(.inter(10, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                Spacer()
                Button { dismiss() } label: { Icon(.x, size: 18, color: Nuru.navy) }.buttonStyle(.plain)
            }
            .padding(.top, Nuru.S.lg)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("KSh").font(.inter(13, .medium)).foregroundStyle(Color(hex: 0x74808F))
                Text(num.formatted(.number.grouping(.automatic)))
                    .font(.fraunces(38, .semibold)).kerning(-1.1).foregroundStyle(Nuru.navy)
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { v in
                    Button { value = String(v) } label: {
                        Text(v.formatted(.number.grouping(.automatic)))
                            .font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                            .padding(.horizontal, 11).frame(height: 32)
                            .background(Nuru.surface, in: Capsule())
                            .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity)

            keys

            Spacer(minLength: 0)

            Button {
                Haptics.action()
                onConfirm(num); dismiss()
            } label: {
                Text("Give \(ksh(num))")
                    .font(.inter(15, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(num <= 0)
            .opacity(num <= 0 ? 0.4 : 1)
        }
        .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.lg)
        .onAppear { value = initial > 0 ? String(initial) : "" }
        .presentationDetents([.height(560)])
        .presentationDragIndicator(.visible)
    }

    private var keys: some View {
        let all = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "del"]
        let cols = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)
        return LazyVGrid(columns: cols, spacing: 10) {
            ForEach(all, id: \.self) { k in
                Button { press(k) } label: {
                    Group {
                        if k == "del" {
                            Image(systemName: "delete.left")
                                .font(.system(size: 19)).foregroundStyle(Color(hex: 0x5B6472))
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

private struct MobileMoneySheet: View {
    let methodKey: String            // mpesa | airtel
    @Binding var phone: String
    var onSubmit: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var isMpesa: Bool { methodKey != "airtel" }
    private var tint: Color { Color(hex: isMpesa ? 0x16A34A : 0xDC2626) }
    private var valid: Bool { phone.filter(\.isNumber).count >= 9 }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text(isMpesa ? "M-PESA NUMBER" : "AIRTEL MONEY NUMBER")
                    .font(.inter(10, .semibold)).kerning(1.6).foregroundStyle(Color(hex: 0x74808F))
                Spacer()
                Button { dismiss() } label: { Icon(.x, size: 18, color: Nuru.navy) }.buttonStyle(.plain)
            }
            .padding(.top, Nuru.S.lg)

            Text("We'll send the payment prompt to this number. Your registered number loads by default — edit it for this gift if you like.")
                .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Nuru.S.sm) {
                Icon(.smartphone, size: 17, color: tint)
                TextField("07XX XXX XXX", text: $phone)
                    .keyboardType(.phonePad)
                    .font(.inter(15, .semibold)).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 14).frame(height: 52)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(valid ? Nuru.border : Color(hex: 0xF0B4B4), lineWidth: 1))

            if phone != registeredPhone {
                Button { phone = registeredPhone } label: {
                    HStack(spacing: 5) {
                        Icon(.repeat, size: 12, color: Nuru.goldLo)
                        Text("Use my registered number (\(registeredPhone))")
                            .font(.inter(12, .semibold)).foregroundStyle(Nuru.goldLo)
                    }
                }.buttonStyle(.plain)
            }

            Button {
                guard valid else { return }
                Haptics.action()
                dismiss(); onSubmit()
            } label: {
                Text("Give Now")
                    .font(.inter(15, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(!valid)
            .opacity(valid ? 1 : 0.4)

            HStack(spacing: 5) {
                Icon(.lock, size: 12, color: Color(hex: 0x74808F))
                Text("Number used only for this transaction prompt")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x74808F))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Nuru.S.screen).padding(.bottom, Nuru.S.lg)
        .presentationDetents([.height(400)])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Schedule detail sheet (real cancel via POST /giving/schedules/{id}/cancel)

private struct ScheduleDetailSheet: View {
    let schedule: GivingSchedule
    var onClose: () -> Void
    var onCancelled: () -> Void
    @State private var confirming = false
    @State private var busy = false
    @State private var errorText: String?

    private var freqLabel: String { schedule.frequency == "weekly" ? "Every week" : "Every month" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Recurring gift")
                    .font(.fraunces(18, .semibold)).kerning(-0.36).foregroundStyle(Nuru.navy)
                Spacer()
                Button { onClose() } label: {
                    ZStack {
                        Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                        Icon(.x, size: 15, color: Nuru.navy)
                    }
                }.buttonStyle(.plain)
            }
            .padding(.top, Nuru.S.lg)

            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Nuru.gold.opacity(0.1)).frame(width: 44, height: 44)
                    Icon(.repeat, size: 19, color: Nuru.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(ksh(schedule.amountMinor / 100)).font(.inter(17, .bold)).foregroundStyle(Nuru.navy)
                    Text("\(freqLabel) · \(schedule.fund.capitalized)")
                        .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                }
            }
            .padding(.top, Nuru.S.base)

            detailRows.padding(.top, Nuru.S.md)

            if let e = errorText {
                Text(e).font(.inter(12)).foregroundStyle(Nuru.danger).padding(.top, Nuru.S.sm)
            }

            if confirming {
                confirmBox.padding(.top, Nuru.S.base)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                cancelButton.padding(.top, Nuru.S.base)
            }
            Spacer(minLength: 0)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.85), value: confirming)
        .padding(.horizontal, Nuru.S.screen)
        .presentationDetents([.height(500)])
        .presentationDragIndicator(.visible)
    }

    private var detailRows: some View {
        VStack(spacing: 0) {
            row("Fund", schedule.fund.capitalized)
            Divider().overlay(Nuru.border)
            row("Amount", ksh(schedule.amountMinor / 100))
            Divider().overlay(Nuru.border)
            row("Frequency", freqLabel)
            Divider().overlay(Nuru.border)
            row("Next charge", giveDateFull(schedule.nextRunAt))
            Divider().overlay(Nuru.border)
            row("Method", givingMethodName(schedule.method))
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
            Spacer()
            Text(value).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
        }
        .padding(.vertical, 10)
    }

    private var cancelButton: some View {
        Button {
            Haptics.tap()
            confirming = true
        } label: {
            Text("Cancel schedule")
                .font(.inter(13, .bold)).foregroundStyle(Color(hex: 0xDC2626))
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(Color(hex: 0xFEF2F2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(hex: 0xFECACA), lineWidth: 1))
        }.buttonStyle(.plain)
    }

    private var confirmBox: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cancel this recurring gift?")
                .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0xB91C1C))
            Text("Future charges stop. To change the amount, cancel and set up a new schedule.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: Nuru.S.sm) {
                Button { confirming = false } label: {
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

    private func cancelNow() {
        busy = true; errorText = nil
        Task { @MainActor in
            do {
                try await MemberAPI.cancelSchedule(schedule.scheduleId)
                Haptics.success()   // server confirmed the cancellation
                onCancelled()
            } catch {
                errorText = (error as? APIError)?.errorDescription ?? "Couldn't cancel — try again."
                busy = false
                Haptics.error()
            }
        }
    }
}

// MARK: - Ceremony (full-screen; only ever shows the server's real status)

private struct GiveCeremonyView: View {
    let stage: String                // stk | success | failed | scheduled
    let note: String
    let amountLabel: String
    let fundLabel: String
    let phone: String?
    let refCode: String?
    let txId: String?
    let cadenceWord: String
    let nextChargeLabel: String?
    var onDone: () -> Void
    var onRetry: () -> Void
    @State private var showReceipt = false

    var body: some View {
        ZStack {
            (stage == "stk" ? Nuru.navy : Nuru.paper).ignoresSafeArea()
            switch stage {
            case "stk":
                StkStage(amountLabel: amountLabel, fundLabel: fundLabel, phone: phone, note: note)
            case "success":
                SuccessStage(amountLabel: amountLabel, fundLabel: fundLabel, refCode: refCode,
                             hasReceipt: txId != nil,
                             onViewReceipt: { showReceipt = true }, onDone: onDone)
            case "scheduled":
                ScheduledStage(amountLabel: amountLabel, fundLabel: fundLabel,
                               cadenceWord: cadenceWord, nextChargeLabel: nextChargeLabel, onDone: onDone)
            default:
                FailedStage(note: note, onRetry: onRetry, onDone: onDone)
            }
        }
        .sheet(isPresented: $showReceipt) {
            if let txId { GivingReceiptView(transactionId: txId) }
        }
    }
}

private struct StkStage: View {
    let amountLabel, fundLabel: String
    let phone: String?
    let note: String

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
            (Text("Enter your PIN to complete ")
                + Text(amountLabel).foregroundColor(Nuru.gold).fontWeight(.semibold)
                + Text(" to \(fundLabel)."))
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
                    Icon(.smartphone, size: 13, color: Nuru.gold)
                    Text("Prompt sent to \(phone)").font(.inter(11)).foregroundStyle(.white)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())
                .padding(.top, Nuru.S.md)
            }
            HStack(spacing: 6) {
                ProgressView().tint(.white.opacity(0.5)).scaleEffect(0.7)
                Text("Waiting up to 60s…").font(.inter(11)).foregroundStyle(.white.opacity(0.5))
            }
            .padding(.top, Nuru.S.lg)
            Spacer()
        }
    }
}

private struct SuccessStage: View {
    let amountLabel, fundLabel: String
    let refCode: String?
    let hasReceipt: Bool
    var onViewReceipt: () -> Void
    var onDone: () -> Void

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
                .font(.fraunces(24, .medium)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.lg).padding(.horizontal, Nuru.S.xl)
                .gentleEntrance(delay: 0.08)
            Text(refCode.map { "\(amountLabel) · \(fundLabel) · Ref \($0)" } ?? "\(amountLabel) · \(fundLabel)")
                .font(.inter(13)).foregroundStyle(Color(hex: 0x5B6472))
                .padding(.top, Nuru.S.sm)
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
                .font(.fraunces(24, .medium)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .padding(.top, Nuru.S.lg)
                .gentleEntrance(delay: 0.08)
            Text("\(amountLabel) to \(fundLabel) every \(cadenceWord).")
                .font(.inter(13)).foregroundStyle(Color(hex: 0x5B6472))
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
                .gentleEntrance(delay: 0.16)
            if let nextChargeLabel {
                HStack(spacing: 6) {
                    Icon(.repeat, size: 12, color: Nuru.goldLo)
                    Text("First charge \(nextChargeLabel) · cancel anytime")
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
                .font(.fraunces(20, .medium)).kerning(-0.4).foregroundStyle(Nuru.navy)
                .padding(.top, Nuru.S.base)
            Text(note.isEmpty ? "Your amount and fund are saved. Try again whenever you're ready." : note)
                .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
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
                    Text("Try again")
                        .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }.buttonStyle(.plain)
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
