// Give — the native port of screens/GivingScreen.tsx. Year-given pill, five funds,
// big-number amount + presets, frequency (one-time/weekly/monthly), payment
// methods, cover-the-fee, a sticky CTA, and recent giving. Money is
// server-authoritative + online-only (§5.6): we create a real intent (mobile
// money STK / PayPal approve) and NEVER fabricate a gift. The card path needs the
// Stripe SDK (client-side tokenisation, SAQ-A) and is flagged "soon".
import SwiftUI

enum GiveRoute: Hashable { case statement }

private struct Fund: Identifiable {
    let code, label, tagline: String; let icon: Lucide; let tint, fg: UInt32
    var id: String { code }
}
private let funds: [Fund] = [
    Fund(code: "tithe", label: "Tithe", tagline: "A faithful portion", icon: .target, tint: 0xFFF4C7, fg: 0xA87F2E),
    Fund(code: "offering", label: "Offering", tagline: "Freewill worship", icon: .handHeart, tint: 0xFEE2E2, fg: 0xB91C1C),
    Fund(code: "gift", label: "Gift", tagline: "A special gift", icon: .gift, tint: 0xF3E8FF, fg: 0x7E22CE),
    Fund(code: "mission", label: "Mission", tagline: "Beyond our walls", icon: .map, tint: 0xE0F2FE, fg: 0x0369A1),
    Fund(code: "discipleship", label: "Discipleship", tagline: "Growing the Pathway", icon: .bookOpen, tint: 0xDCFCE7, fg: 0x166534),
]
private let presets = [200, 500, 1000, 2500, 5000]

private struct PayMethod: Identifiable {
    let key, label, sub: String; let provider: String?
    var id: String { key }
}
private let methods: [PayMethod] = [
    PayMethod(key: "mpesa", label: "M-Pesa", sub: "STK push to your phone", provider: "mpesa"),
    PayMethod(key: "airtel", label: "Airtel Money", sub: "Mobile money", provider: "airtel"),
    PayMethod(key: "card", label: "Card", sub: "Visa · Mastercard", provider: "card"),
    PayMethod(key: "paypal", label: "PayPal", sub: "PayPal balance / linked", provider: "paypal"),
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

@MainActor
final class GivingViewModel: ObservableObject {
    @Published var history: [GivingRecord] = []
    @Published var loading = true

    func load() async {
        loading = true
        history = (try? await MemberAPI.givingHistory()) ?? []
        loading = false
    }

    var yearTotalMinor: Int {
        let yr = Calendar.current.component(.year, from: Date())
        let settled: Set<String> = ["succeeded", "settled", "completed"]
        return history.filter { settled.contains($0.status) && $0.createdAt.prefix(4) == String(yr) }.reduce(0) { $0 + $1.amountMinor }
    }
    var lastGift: GivingRecord? { history.first }
}

struct GivingView: View {
    @StateObject private var vm = GivingViewModel()

    @State private var fundCode = "tithe"
    @State private var amount = 1000
    @State private var amountText = "1000"
    @State private var method = "mpesa"
    @State private var freq = "once"   // once | weekly | monthly
    @State private var coverFee = false
    @State private var submitting = false
    @State private var ceremony: String?   // nil | "stk" | "success" | "failed"
    @State private var ceremonyNote = ""

    private var fund: Fund { funds.first { $0.code == fundCode } ?? funds[0] }
    private var fee: Int { coverFee ? feeFor(amount) : 0 }
    private var total: Int { amount + fee }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                Nuru.paper.ignoresSafeArea()
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: Nuru.S.base) {
                        headerBlock
                        fundsRow
                        amountCard
                        frequencyRow
                        methodList
                        coverFeeRow
                        recentGiving
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, 60)
                    .padding(.bottom, 150)
                }
                ctaBar
            }
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: GivingRecord.self) { GivingReceiptView(transactionId: $0.transactionId) }
            .navigationDestination(for: GiveRoute.self) { _ in GivingStatementView() }
        }
        .task { if vm.history.isEmpty { await vm.load() } }
        .sheet(isPresented: Binding(get: { ceremony != nil }, set: { if !$0 { ceremony = nil } })) {
            ceremonySheet
        }
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Give").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.ink)
            HStack(spacing: 6) {
                Icon(.badgeCheck, size: 13, color: Nuru.gold)
                Text("\(ksh(vm.yearTotalMinor / 100)) given this year").font(.inter(12, .semibold)).foregroundStyle(Nuru.goldLo)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(Capsule().stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
            .padding(.top, Nuru.S.md)
        }
    }

    private var fundsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(funds) { f in
                    let on = f.code == fundCode
                    Button { fundCode = f.code } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            ZStack { RoundedRectangle(cornerRadius: 10).fill(Color(hex: f.tint)).frame(width: 34, height: 34); Icon(f.icon, size: 16, color: Color(hex: f.fg)) }
                            Text(f.label).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                            Text(f.tagline).font(.nMicro).foregroundStyle(Nuru.faint).lineLimit(1)
                        }
                        .frame(width: 124, alignment: .leading)
                        .padding(Nuru.S.md)
                        .background(on ? Nuru.priorityBg : Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Nuru.gold : Nuru.border, lineWidth: 2))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            Text("AMOUNT (KES)").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.gold)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("KSh").font(.inter(16, .semibold)).foregroundStyle(Nuru.muted)
                TextField("0", text: $amountText)
                    .keyboardType(.numberPad)
                    .font(.fraunces(40, .bold)).foregroundStyle(Nuru.ink)
                    .onChange(of: amountText) { _, v in amount = Int(v.filter(\.isNumber)) ?? 0 }
            }
            HStack(spacing: Nuru.S.sm) {
                ForEach(presets, id: \.self) { v in
                    let on = amount == v
                    Button { amount = v; amountText = String(v) } label: {
                        Text(ksh(v)).font(.inter(12, .semibold)).foregroundStyle(on ? .white : Nuru.ink600)
                            .padding(.horizontal, 14).frame(height: 34)
                            .background(on ? Nuru.navy : Nuru.surface, in: Capsule())
                    }.buttonStyle(.plain)
                }
            }
        }
        .padding(Nuru.S.base).giveCard()
    }

    private var frequencyRow: some View {
        HStack(spacing: 4) {
            ForEach([("once", "One-time"), ("weekly", "Weekly"), ("monthly", "Monthly")], id: \.0) { key, label in
                let on = freq == key
                Button { freq = key } label: {
                    Text(label).font(.inter(13, on ? .semibold : .regular)).foregroundStyle(on ? Nuru.ink : Nuru.ink600)
                        .frame(maxWidth: .infinity).frame(height: 42)
                        .background(on ? Nuru.white : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .nuruShadow(on ? 1 : 0)
                }.buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(Color(hex: 0x0A2540, alpha: 0.06), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }

    private var methodList: some View {
        VStack(spacing: Nuru.S.sm) {
            ForEach(methods) { m in
                let on = method == m.key
                let soon = m.provider == nil
                Button { if !soon { method = m.key } } label: {
                    HStack(spacing: Nuru.S.md) {
                        ZStack {
                            Circle().fill(on ? Nuru.goldTint : Nuru.surface).frame(width: 38, height: 38)
                            Icon(m.key == "card" ? .gift : m.key == "paypal" ? .handHeart : .check, size: 16, color: on ? Nuru.gold : Nuru.ink600)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m.label).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                            Text(m.sub).font(.nMicro).foregroundStyle(Nuru.faint)
                        }
                        Spacer(minLength: 0)
                        if soon {
                            Text("soon").font(.nMicro).foregroundStyle(Nuru.faint)
                                .padding(.horizontal, 8).padding(.vertical, 3).background(Nuru.mutedBg, in: Capsule())
                        } else {
                            ZStack {
                                Circle().stroke(on ? Nuru.gold : Nuru.border, lineWidth: 2).frame(width: 20, height: 20)
                                if on { Circle().fill(Nuru.gold).frame(width: 12, height: 12) }
                            }
                        }
                    }
                    .padding(Nuru.S.md)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Nuru.gold : Nuru.border, lineWidth: on ? 2 : 1))
                    .opacity(soon ? 0.6 : 1)
                }.buttonStyle(.plain)
            }
        }
    }

    private var coverFeeRow: some View {
        Toggle(isOn: $coverFee) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Cover the processing fee").font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
                Text(fee > 0 ? "Adds \(ksh(fee)) so the full gift goes to ministry" : "The church keeps a little more")
                    .font(.nMicro).foregroundStyle(Nuru.faint)
            }
        }
        .tint(Nuru.gold)
        .padding(Nuru.S.base).giveCard()
    }

    private var recentGiving: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack {
                Text("Recent giving").font(.nHeading).foregroundStyle(Nuru.ink)
                Spacer()
                if !vm.history.isEmpty {
                    NavigationLink(value: GiveRoute.statement) {
                        Text("Statement ›").font(.inter(12, .semibold)).foregroundStyle(Nuru.goldLo)
                    }
                }
            }
            if vm.history.isEmpty {
                Text("Your gifts will appear here.").font(.nCaption).foregroundStyle(Nuru.muted)
            } else {
                ForEach(vm.history.prefix(5)) { g in
                    NavigationLink(value: g) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(ksh(g.amountMinor / 100)).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                                Text(g.fund.capitalized).font(.nMicro).foregroundStyle(Nuru.faint)
                            }
                            Spacer()
                            Text(statusLabel(g.status)).font(.nMicro).foregroundStyle(statusColor(g.status))
                                .padding(.horizontal, 8).padding(.vertical, 3).background(statusBg(g.status), in: Capsule())
                            Icon(.chevronRight, size: 12, color: Nuru.ink300)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    if g.id != vm.history.prefix(5).last?.id { Divider() }
                }
            }
        }
        .padding(Nuru.S.base).giveCard()
    }

    private var ctaBar: some View {
        VStack(spacing: 0) {
            PButton(title: submitting ? "Processing…" : "Give \(ksh(total))", variant: .gold, busy: submitting) {
                Task { await give() }
            }
        }
        .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.md).padding(.bottom, 28)
        .background(Nuru.paper.opacity(0.96))
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }

    @ViewBuilder
    private var ceremonySheet: some View {
        VStack(spacing: Nuru.S.lg) {
            Spacer()
            if ceremony == "stk" {
                Icon(.clock, size: 44, color: Nuru.gold)
                Text("Check your phone").font(.nTitle).foregroundStyle(Nuru.ink)
                Text(ceremonyNote.isEmpty ? "Approve the prompt to complete your \(ksh(total)) gift." : ceremonyNote)
                    .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            } else if ceremony == "success" {
                Icon(.badgeCheck, size: 44, color: Nuru.success)
                Text("Thank you!").font(.nTitle).foregroundStyle(Nuru.ink)
                Text("Your \(ksh(total)) gift to \(fund.label) is received.").font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
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

    private func give() async {
        guard amount > 0 else { return }
        guard let provider = methods.first(where: { $0.key == method })?.provider else {
            ceremonyNote = "This method is coming soon."; ceremony = "failed"; return
        }
        if provider == "card" {
            // Card requires the Stripe SDK (client-side tokenisation, SAQ-A) — not
            // yet integrated. Surfaced rather than faked.
            ceremonyNote = "Card giving needs the Stripe step — coming soon. Try M-Pesa for now."
            ceremony = "failed"; return
        }
        submitting = true; defer { submitting = false }
        do {
            let currency = provider == "paypal" ? "USD" : "KES"
            let res = try await MemberAPI.giving(fund: fund.code, amountMinor: total * 100, currency: currency, method: provider)
            if provider == "paypal", let url = res.approveUrl.flatMap(URL.init) {
                await UIApplication.shared.open(url)
                ceremonyNote = "Approve in PayPal, then return to the app."; ceremony = "stk"
            } else {
                ceremony = "stk"   // mobile money STK push
            }
        } catch {
            ceremonyNote = (error as? APIError)?.errorDescription ?? "Something went wrong."
            ceremony = "failed"
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s { case "succeeded", "settled", "completed": return "Succeeded"
        case "processing": return "Processing"; case "failed": return "Failed"
        case "refunded": return "Refunded"; default: return s.capitalized }
    }
    private func statusColor(_ s: String) -> Color {
        switch s { case "succeeded", "settled", "completed": return Nuru.successText
        case "processing": return Nuru.goldChipText; case "failed": return Nuru.danger; default: return Nuru.ink600 }
    }
    private func statusBg(_ s: String) -> Color {
        switch s { case "succeeded", "settled", "completed": return Nuru.successBg
        case "processing": return Nuru.goldChipBg; case "failed": return Nuru.danger.opacity(0.12); default: return Nuru.mutedBg }
    }
}

private extension View {
    func giveCard() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
