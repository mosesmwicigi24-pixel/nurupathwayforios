// Giving statement — the native port of screens/GivingStatementScreen.tsx. A
// grouped-by-day history of the member's gifts with a settled-only total, payment
// method, provider reference and a per-gift status chip. Read-only over
// GET /giving/history; tapping a gift opens its full receipt.
import SwiftUI

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

    var totalMinor: Int { history.filter { settledStatuses.contains($0.status) }.reduce(0) { $0 + $1.amountMinor } }

    /// Records grouped by calendar day, newest first.
    var groups: [(key: String, label: String, records: [GivingRecord])] {
        let sorted = history.sorted { $0.createdAt > $1.createdAt }
        var order: [String] = []
        var map: [String: [GivingRecord]] = [:]
        for r in sorted {
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

struct GivingStatementView: View {
    @StateObject private var vm = GivingStatementViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    totalCard
                    if vm.loading && vm.history.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else if vm.history.isEmpty {
                        Text("No gifts yet.").font(.nBody).foregroundStyle(Nuru.muted).padding(.top, Nuru.S.xl)
                    } else {
                        ForEach(vm.groups, id: \.key) { group in
                            Text(group.label).font(.inter(11, .bold)).kerning(0.5).foregroundStyle(Nuru.faint)
                                .padding(.top, Nuru.S.sm)
                            ForEach(group.records) { r in
                                NavigationLink(value: r) { giftRow(r) }.buttonStyle(.plain)
                            }
                        }
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
    }

    private var header: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: .white).frame(width: 40, height: 40).background(Color.white.opacity(0.10), in: Circle())
            }
            Text("Statement").font(.fraunces(20, .semibold)).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, Nuru.S.lg).padding(.top, 54).padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("TOTAL GIVEN").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.gold)
            Text(ksh(vm.totalMinor / 100)).font(.fraunces(32, .bold)).foregroundStyle(Nuru.ink)
            Text("Settled gifts only").font(.nCaption).foregroundStyle(Nuru.muted)
        }
        .padding(Nuru.S.base).frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func giftRow(_ r: GivingRecord) -> some View {
        HStack(spacing: Nuru.S.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text(ksh(r.amountMinor / 100)).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                Text(r.fund.capitalized + (r.method != nil ? " · \(r.method!.capitalized)" : "")).font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Spacer(minLength: 0)
            statusChip(r.status)
            Icon(.chevronRight, size: 13, color: Nuru.ink300)
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

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
