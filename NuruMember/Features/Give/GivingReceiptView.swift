// Giving receipt — the native port of screens/GivingReceiptScreen.tsx. One gift's
// full detail: the amount, fund, method, status, date, transaction reference, and
// the double-entry ledger trail. Read-only over GET /giving/transactions/{id}.
import SwiftUI

@MainActor
final class GivingReceiptViewModel: ObservableObject {
    @Published var detail: GivingDetail?
    @Published var loading = true
    @Published var error: String?

    let transactionId: String
    init(transactionId: String) { self.transactionId = transactionId }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.givingDetail(transactionId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this receipt." }
        loading = false
    }
}

struct GivingReceiptView: View {
    @StateObject private var vm: GivingReceiptViewModel
    @Environment(\.dismiss) private var dismiss

    init(transactionId: String) { _vm = StateObject(wrappedValue: GivingReceiptViewModel(transactionId: transactionId)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.loading && vm.detail == nil {
                loadingSkeleton
                Spacer()
            } else if let d = vm.detail {
                content(d)
            } else {
                Spacer()
                VStack(spacing: Nuru.S.sm) {
                    Text(vm.error ?? "Couldn't load this receipt.").font(.nBody).foregroundStyle(Nuru.muted)
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
                Spacer()
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
    }

    /// Shimmering placeholder in the receipt's silhouette — the amount ceremony
    /// card and the details card — so nothing jumps when the real one lands.
    private var loadingSkeleton: some View {
        VStack(spacing: Nuru.S.base) {
            VStack(spacing: Nuru.S.sm) {
                Circle().fill(Nuru.surface).frame(width: 64, height: 64).nuruShimmer()
                RoundedRectangle(cornerRadius: 8).fill(Nuru.surface).frame(width: 160, height: 30).nuruShimmer()
                RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(width: 100, height: 12).nuruShimmer()
            }
            .frame(maxWidth: .infinity).padding(Nuru.S.lg).receiptCard()
            VStack(spacing: 14) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(height: 12).nuruShimmer()
                }
            }
            .padding(Nuru.S.base).receiptCard()
        }
        .padding(Nuru.S.screen)
    }

    // Cream Figma header — consistent with the rest of the ScreenShell chrome.
    private var header: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy).frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            Text("Receipt").font(.fraunces(20, .semibold)).foregroundStyle(Nuru.navy)
            Spacer()
        }
        .padding(.horizontal, Nuru.S.lg).padding(.top, 60).padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.22)).frame(width: 176, height: 176).blur(radius: 44).offset(x: 40, y: -60)
                }
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private func content(_ d: GivingDetail) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.base) {
                // Amount ceremony
                VStack(spacing: Nuru.S.sm) {
                    ZStack { Circle().fill(Nuru.successBg).frame(width: 64, height: 64); Icon(.badgeCheck, size: 30, color: Nuru.success) }
                    Text(ksh(d.amountMinor / 100)).font(.fraunces(36, .bold)).foregroundStyle(Nuru.ink)
                    Text("to \(d.fund.capitalized)").font(.nBody).foregroundStyle(Nuru.muted)
                    statusChip(d.status)
                }
                .frame(maxWidth: .infinity).padding(Nuru.S.lg).receiptCard()
                .gentleEntrance()

                // Details
                VStack(spacing: 0) {
                    detailRow("Date", whenString(d.settledAt ?? d.createdAt))
                    Divider()
                    if let m = d.method { detailRow("Method", m.capitalized); Divider() }
                    detailRow("Currency", d.currency.uppercased())
                    if let ref = d.providerRef { Divider(); detailRow("Reference", ref) }
                    Divider(); detailRow("Transaction", String(d.transactionId.prefix(8)) + "…")
                }
                .padding(.horizontal, Nuru.S.base).receiptCard()
                .gentleEntrance(delay: 0.06)

                // Ledger trail
                if !d.ledger.isEmpty {
                    VStack(alignment: .leading, spacing: Nuru.S.sm) {
                        Text("LEDGER").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                        ForEach(d.ledger) { e in
                            HStack {
                                Text(e.side.uppercased()).font(.nMicro).foregroundStyle(e.side == "debit" ? Color(hex: 0x1B5FAE) : Nuru.success)
                                    .frame(width: 56, alignment: .leading)
                                Text(e.account).font(.nCaption).foregroundStyle(Nuru.ink)
                                Spacer()
                                Text(ksh(e.amountMinor / 100)).font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(Nuru.S.base).frame(maxWidth: .infinity, alignment: .leading).receiptCard()
                    .gentleEntrance(delay: 0.12)
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.nCaption).foregroundStyle(Nuru.muted)
            Spacer()
            Text(value).font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
        }
        .padding(.vertical, Nuru.S.md)
    }

    private func whenString(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return iso }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy · h:mm a"; return f.string(from: d)
    }
}

private extension View {
    func receiptCard() -> some View {
        background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
