// Gift receipt v2 (2026-09-25) — one gift, the way a member wants to keep it:
// a green "gift received" hero (thank-you by first name, the amount, where it
// went, when), a clean details card (fund, pledge, method, the M-Pesa code
// with copy), a "100% reaches the fund" assurance line, Share (the server's
// branded PDF over the bearer client) + View statement, and the giver's verse.
// Read-only over GET /giving/transactions/{id}; the PDF is
// GET /giving/transactions/{id}/receipt.pdf. The double-entry ledger stays in
// the portal — members never see account codes here.
//
// Tolerant by design: fund_name / pledge / need / method_label / member_name
// are additions an older server omits, so every one of them falls back (fund
// code, local method map, the signed-in profile) rather than breaking the page.
import SwiftUI
import UIKit

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

/// Pages the receipt pushes onto WHICHEVER stack hosts it (Give or Partners):
/// the destination is declared by the receipt itself, so no host needs to
/// know about it.
enum ReceiptRoute: Hashable { case statement }

/// The receipt's read of a transaction status — the wire enum is
/// requires_action | processing | succeeded | failed | refunded, plus the
/// older pending / settled / cancelled spellings still in the history.
private enum ReceiptState {
    case succeeded, pending, failed, refunded
    case other(String)

    init(_ raw: String) {
        switch raw.lowercased() {
        case "succeeded", "settled", "completed":                  self = .succeeded
        case "requires_action", "processing", "pending", "initiated": self = .pending
        case "failed", "cancelled", "canceled", "expired":          self = .failed
        case "refunded":                                            self = .refunded
        case let s:                                                 self = .other(s)
        }
    }

}

struct GivingReceiptView: View {
    @StateObject private var vm: GivingReceiptViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var auth: AuthStore

    /// Opens the pledge this gift counts toward. Only a host with a pledge
    /// page on its stack (Partners) passes one; elsewhere the row is plain.
    private let onOpenPledge: ((String) -> Void)?

    @State private var downloading = false
    @State private var shareError: String?
    @State private var sharePayload: ReceiptSharePayload?
    @State private var copiedKey: String?

    init(transactionId: String, onOpenPledge: ((String) -> Void)? = nil) {
        _vm = StateObject(wrappedValue: GivingReceiptViewModel(transactionId: transactionId))
        self.onOpenPledge = onOpenPledge
    }

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
        .navigationDestination(for: ReceiptRoute.self) { route in
            switch route {
            case .statement: GivingStatementView()
            }
        }
        .task { if vm.detail == nil { await vm.load() } }
        .sheet(item: $sharePayload) { p in ReceiptShareSheet(items: p.items) }
    }

    // MARK: Header — cream band, back + title + share

    private var header: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy).frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Back")
            Text("Receipt").font(.fraunces(20, .semibold)).foregroundStyle(Nuru.navy)
            Spacer()
            // Same action as the primary "Share receipt" button below.
            if let d = vm.detail {
                Button { share(d) } label: {
                    Group {
                        if downloading { ProgressView().tint(Nuru.navy).scaleEffect(0.8) }
                        else { Icon(.share, size: 16, color: Nuru.navy) }
                    }
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .disabled(downloading)
                .accessibilityLabel("Share receipt")
            }
        }
        .padding(.horizontal, Nuru.S.lg)
        // Right under the status bar — the real inset, never a fixed 60.
        .padding(.top, NuruSafeArea.top + 8)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.22)).frame(width: 176, height: 176).blur(radius: 44).offset(x: 40, y: -60)
                }
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // MARK: Loading — the receipt's silhouette (hero, details, two buttons)

    private var loadingSkeleton: some View {
        VStack(spacing: Nuru.S.base) {
            VStack(spacing: Nuru.S.md) {
                Circle().fill(Nuru.surface).frame(width: 72, height: 72).nuruShimmer()
                RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(width: 90, height: 10).nuruShimmer()
                RoundedRectangle(cornerRadius: 8).fill(Nuru.surface).frame(width: 170, height: 36).nuruShimmer()
                RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(width: 140, height: 12).nuruShimmer()
            }
            .frame(maxWidth: .infinity).padding(Nuru.S.lg).receiptCard(radius: Nuru.R.card)
            VStack(spacing: 18) {
                ForEach(0..<5, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(height: 12).nuruShimmer()
                }
            }
            .padding(Nuru.S.base).receiptCard(radius: 20)
            HStack(spacing: 10) {
                Capsule().fill(Nuru.surface).frame(height: 48).nuruShimmer()
                Capsule().fill(Nuru.surface).frame(height: 48).nuruShimmer()
            }
        }
        .padding(Nuru.S.screen)
    }

    // MARK: Content

    private func content(_ d: GivingDetail) -> some View {
        let state = ReceiptState(d.status)
        return ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.base) {
                hero(d, state).gentleEntrance()
                details(d).gentleEntrance(delay: 0.06)
                whereItWent(d).gentleEntrance(delay: 0.10)
                actions(d).gentleEntrance(delay: 0.14)
                verseFooter.gentleEntrance(delay: 0.18)
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    // MARK: Hero — the green

    private func hero(_ d: GivingDetail, _ state: ReceiptState) -> some View {
        let look = heroLook(state, d)
        return VStack(spacing: Nuru.S.md) {
            ZStack {
                Circle().fill(look.circle).frame(width: 72, height: 72)
                Icon(look.glyph, size: 32, color: look.glyphColor)
            }
            .padding(.bottom, 2)

            Text(look.eyebrow)
                .font(.inter(10, .semibold)).kerning(1.6).foregroundStyle(look.eyebrowColor)

            if look.thanks, let first = firstName(d) {
                Text("Thank you, \(first).")
                    .font(.fraunces(18)).foregroundStyle(Nuru.navy)
            }

            // Amount: the number in Fraunces, the currency small and quiet.
            let parts = amountParts(d.amountMinor, d.currency)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(parts.symbol).font(.inter(15, .semibold)).foregroundStyle(Color(hex: 0x74808F))
                Text(parts.number).font(.fraunces(40, .semibold)).kerning(-0.8).foregroundStyle(Nuru.navy)
            }
            .padding(.top, 2)

            Text(destinationPhrase(d))
                .font(.inter(14)).foregroundStyle(Color(hex: 0x59667C))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            // "Named giving" (custom sheet, optional): the member's own label
            // for this gift, right under where it went.
            if let name = d.accountName, !name.isEmpty {
                Text("\u{201C}\(name)\u{201D}").font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
            }

            Text(whenLine(d.settledAt ?? d.createdAt))
                .font(.inter(12)).foregroundStyle(Color(hex: 0x8B95A5))

            // A status chip ONLY when the gift is not (yet) received — the
            // green circle already says "received" for the happy path.
            if let chip = look.chip {
                Text(chip.label).font(.inter(11, .semibold)).foregroundStyle(chip.fg)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(chip.bg, in: Capsule())
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Nuru.S.lg + 4).padding(.horizontal, Nuru.S.lg)
        .receiptCard(radius: Nuru.R.card)
    }

    private struct HeroLook {
        let circle: Color, glyph: Lucide, glyphColor: Color
        let eyebrow: String, eyebrowColor: Color
        let thanks: Bool
        let chip: (label: String, bg: Color, fg: Color)?
    }

    private func heroLook(_ state: ReceiptState, _ d: GivingDetail) -> HeroLook {
        switch state {
        case .succeeded:
            return HeroLook(circle: Color(hex: 0xDCFCE7), glyph: .badgeCheck, glyphColor: Color(hex: 0x16A34A),
                            eyebrow: "GIFT RECEIVED", eyebrowColor: Color(hex: 0x166534), thanks: true, chip: nil)
        case .pending:
            // "Waiting for M-Pesa" / "Waiting for Airtel Money"; other rails
            // have no phone prompt to wait on, so say what is true.
            let label = methodLabel(d)
            let waiting = isMobileMoney(d) ? "Waiting for \(label)" : "Waiting for confirmation"
            return HeroLook(circle: Color(hex: 0xFFF4DA), glyph: .clock, glyphColor: Color(hex: 0x7A5A14),
                            eyebrow: "GIFT PENDING", eyebrowColor: Color(hex: 0x7A5A14), thanks: true,
                            chip: (waiting, Color(hex: 0xFFF4DA), Color(hex: 0x7A5A14)))
        case .failed:
            return HeroLook(circle: Color(hex: 0xFEE2E2), glyph: .circleX, glyphColor: Color(hex: 0xDC2626),
                            eyebrow: "GIFT NOT COMPLETED", eyebrowColor: Color(hex: 0xDC2626), thanks: false,
                            chip: ("Not completed", Color(hex: 0xFEE2E2), Color(hex: 0xDC2626)))
        case .refunded:
            return HeroLook(circle: Nuru.mutedBg, glyph: .repeat, glyphColor: Nuru.ink600,
                            eyebrow: "GIFT REFUNDED", eyebrowColor: Nuru.ink600, thanks: false,
                            chip: ("Refunded", Nuru.mutedBg, Nuru.ink600))
        case .other(let raw):
            return HeroLook(circle: Nuru.mutedBg, glyph: .clock, glyphColor: Nuru.ink600,
                            eyebrow: "GIFT", eyebrowColor: Nuru.ink600, thanks: true,
                            chip: (raw.replacingOccurrences(of: "_", with: " ").capitalized, Nuru.mutedBg, Nuru.ink600))
        }
    }

    // MARK: Details card

    private func details(_ d: GivingDetail) -> some View {
        let ref = d.receiptCode ?? d.providerRef
        let refLabel = referenceLabel(d)
        // Never two rows called "Reference": when the provider code already
        // owns that word, the internal id is "Transaction".
        let idLabel = (ref != nil && refLabel == "Reference") ? "Transaction" : "Reference"
        return VStack(spacing: 0) {
            row("Fund", fundDisplayName(d))
            if let p = d.pledge, !p.title.isEmpty {
                hairline
                pledgeRow(p)
            }
            if let name = d.accountName, !name.isEmpty {
                hairline
                row("Gift name", name)
            }
            hairline
            row("Method", methodLabel(d))
            if let ref, !ref.isEmpty {
                hairline
                row(refLabel, ref, mono: true, copy: (key: "ref", text: ref))
            }
            hairline
            row("Date", whenFull(d.settledAt ?? d.createdAt))
            hairline
            row(idLabel, String(d.transactionId.prefix(8)) + "…", mono: true, copy: (key: "txid", text: d.transactionId))
        }
        .padding(.horizontal, Nuru.S.base)
        .receiptCard(radius: 20)
    }

    private var hairline: some View { Rectangle().fill(Nuru.border).frame(height: 1) }

    private func row(_ label: String, _ value: String, mono: Bool = false,
                     copy: (key: String, text: String)? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Nuru.S.md) {
            Text(label).font(.inter(13)).foregroundStyle(Color(hex: 0x68758A))
            Spacer(minLength: Nuru.S.md)
            if let copy {
                Button {
                    copyToPasteboard(copy.text, key: copy.key)
                } label: {
                    HStack(spacing: 6) {
                        valueText(value, mono: mono)
                        if copiedKey == copy.key {
                            HStack(spacing: 3) {
                                Icon(.check, size: 12, color: Color(hex: 0x16A34A))
                                Text("Copied").font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x16A34A))
                            }
                            .transition(.opacity)
                        } else {
                            Icon(.copy, size: 14, color: Color(hex: 0x8B95A5))
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy \(label)")
            } else {
                valueText(value, mono: mono)
            }
        }
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private func valueText(_ value: String, mono: Bool) -> some View {
        if mono {
            Text(value).font(.inter(14, .semibold)).monospacedDigit().kerning(0.4)
                .foregroundStyle(Nuru.ink).multilineTextAlignment(.trailing)
        } else {
            Text(value).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).multilineTextAlignment(.trailing)
        }
    }

    /// The pledge row: a link into the pledge page when the host has one,
    /// a plain value when it does not.
    @ViewBuilder
    private func pledgeRow(_ p: GivingIntentResult.PledgeRef) -> some View {
        if let onOpenPledge, !p.pledgeId.isEmpty {
            Button {
                Haptics.tap()
                onOpenPledge(p.pledgeId)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: Nuru.S.md) {
                    Text("Pledge").font(.inter(13)).foregroundStyle(Color(hex: 0x68758A))
                    Spacer(minLength: Nuru.S.md)
                    HStack(spacing: 4) {
                        Text(p.title).font(.inter(14, .semibold)).foregroundStyle(Nuru.navy).multilineTextAlignment(.trailing)
                        Icon(.chevronRight, size: 14, color: Nuru.navy)
                    }
                }
                .padding(.vertical, 13)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the pledge")
        } else {
            row("Pledge", p.title)
        }
    }

    private func copyToPasteboard(_ text: String, key: String) {
        UIPasteboard.general.string = text
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.15)) { copiedKey = key }
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            if copiedKey == key { withAnimation(.easeOut(duration: 0.2)) { copiedKey = nil } }
        }
    }

    // MARK: Where it went

    private func whereItWent(_ d: GivingDetail) -> some View {
        var line = "100% of this gift reaches the \(fundDisplayName(d)) fund."
        if d.pledge != nil { line += " · counts toward your pledge" }
        return HStack(alignment: .top, spacing: 8) {
            Icon(.shieldCheck, size: 14, color: Color(hex: 0x16A34A))
            Text(line).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    // MARK: Actions

    private func actions(_ d: GivingDetail) -> some View {
        VStack(spacing: Nuru.S.sm) {
            HStack(spacing: 10) {
                Button { share(d) } label: {
                    HStack(spacing: 8) {
                        if downloading {
                            ProgressView().tint(.white).scaleEffect(0.85)
                            Text("Preparing…").font(.inter(14, .semibold)).foregroundStyle(.white)
                        } else {
                            Icon(.share, size: 16, color: .white)
                            Text("Share receipt").font(.inter(14, .semibold)).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.navy, in: Capsule())
                }
                .buttonStyle(.pressable)
                .disabled(downloading)

                NavigationLink(value: ReceiptRoute.statement) {
                    HStack(spacing: 8) {
                        Icon(.fileText, size: 16, color: Nuru.navy)
                        Text("View statement").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                    }
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.navy.opacity(0.35), lineWidth: 1.2))
                }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            }
            if let shareError {
                Text(shareError)
                    .font(.inter(11)).foregroundStyle(Color(hex: 0xDC2626))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    /// Share = the server's branded PDF, fetched over the bearer client into
    /// a temp file, handed to the system sheet with a one-line summary. When
    /// the PDF cannot be had (older server, offline, not a PDF), the summary
    /// line is shared on its own and a quiet line says so.
    private func share(_ d: GivingDetail) {
        guard !downloading else { return }
        Haptics.tap()
        downloading = true
        withAnimation { shareError = nil }
        let text = shareText(d)
        Task {
            defer { downloading = false }
            do {
                let data = try await MemberAPI.givingReceiptPdf(d.transactionId)
                // A 200 that is not a PDF (a proxy page, a JSON body) must not
                // be shared as one.
                guard data.starts(with: Array("%PDF".utf8)) else {
                    throw APIError.decoding("receipt.pdf did not return a PDF")
                }
                let stem = d.receiptCode.flatMap { $0.isEmpty ? nil : $0 } ?? String(d.transactionId.prefix(8))
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("nuru-receipt-\(stem).pdf")
                try data.write(to: url, options: .atomic)
                Haptics.success()
                sharePayload = ReceiptSharePayload(items: [url, text])
            } catch {
                Haptics.error()
                withAnimation { shareError = "The PDF isn't available right now — sharing the details instead." }
                sharePayload = ReceiptSharePayload(items: [text])
            }
        }
    }

    /// "KSh 500 to the Discipleship fund · M-Pesa UIPJ27PBO3 · 25 Sep 2026"
    private func shareText(_ d: GivingDetail) -> String {
        var method = methodLabel(d)
        if let ref = d.receiptCode ?? d.providerRef, !ref.isEmpty { method += " \(ref)" }
        return "\(money(d.amountMinor, d.currency)) \(destinationPhrase(d)) · \(method) · \(giveDateFull(d.settledAt ?? d.createdAt))"
    }

    // MARK: Verse footer — the Give page's verse card

    private var verseFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\u{201C}God loves a cheerful giver.\u{201D}")
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

    // MARK: Derived copy (every one tolerant of an older payload)

    /// First word of the server's member_name; else the signed-in profile's;
    /// else nil (and the thank-you line is left out).
    private func firstName(_ d: GivingDetail) -> String? {
        let full = [d.memberName, auth.profile?.fullName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let first = full?.split(separator: " ").first, !first.isEmpty else { return nil }
        return String(first)
    }

    private func fundDisplayName(_ d: GivingDetail) -> String {
        if let n = d.fundName?.trimmingCharacters(in: .whitespaces), !n.isEmpty { return n }
        return d.fund.isEmpty ? "General" : d.fund.capitalized
    }

    /// "toward your Building pledge" · "to Chairs for the hall" · "to the Tithe fund".
    /// A title that already ends in the word is not doubled.
    private func destinationPhrase(_ d: GivingDetail) -> String {
        if let p = d.pledge, !p.title.isEmpty {
            return p.title.lowercased().hasSuffix("pledge") ? "toward your \(p.title)" : "toward your \(p.title) pledge"
        }
        if let n = d.need, !n.title.isEmpty { return "to \(n.title)" }
        let fund = fundDisplayName(d)
        return fund.lowercased().hasSuffix("fund") ? "to the \(fund)" : "to the \(fund) fund"
    }

    private func methodLabel(_ d: GivingDetail) -> String {
        if let l = d.methodLabel?.trimmingCharacters(in: .whitespaces), !l.isEmpty { return l }
        return givingMethodName(d.method)
    }

    private func isMobileMoney(_ d: GivingDetail) -> Bool {
        let m = (d.method ?? "").lowercased()
        let l = methodLabel(d).lowercased()
        return m == "mpesa" || m == "airtel" || l.contains("m-pesa") || l.contains("airtel")
    }

    /// The provider code's row label: the rail's own word for it.
    private func referenceLabel(_ d: GivingDetail) -> String {
        let m = (d.method ?? "").lowercased()
        let l = methodLabel(d).lowercased()
        if m == "mpesa" || l.contains("m-pesa") { return "M-Pesa receipt" }
        if m == "airtel" || l.contains("airtel") { return "Airtel receipt" }
        return "Reference"
    }

    /// ("KSh", "500") · ("$", "5.00") · ("USD", "5.00") — integer minor units in,
    /// the same rounding as money().
    private func amountParts(_ minor: Int, _ currency: String) -> (symbol: String, number: String) {
        switch currency.uppercased() {
        case "", "KES": return ("KSh", (minor / 100).formatted(.number.grouping(.automatic)))
        case "USD": return ("$", String(format: "%.2f", Double(minor) / 100.0))
        case let c: return (c, String(format: "%.2f", Double(minor) / 100.0))
        }
    }

    /// "Thu 25 Sep 2026 · 8:11 PM"
    private func whenLine(_ iso: String) -> String {
        guard let d = giveParseDate(iso) else { return String(iso.prefix(10)) }
        let f = DateFormatter(); f.dateFormat = "EEE d MMM yyyy · h:mm a"
        return f.string(from: d)
    }

    /// "25 September 2026 · 8:11 PM"
    private func whenFull(_ iso: String) -> String {
        guard let d = giveParseDate(iso) else { return String(iso.prefix(10)) }
        let f = DateFormatter(); f.dateFormat = "d MMMM yyyy · h:mm a"
        return f.string(from: d)
    }
}

// MARK: - Share sheet plumbing

private struct ReceiptSharePayload: Identifiable {
    let items: [Any]
    let id = UUID()
}

/// UIActivityViewController wrapper — the PDF file (when we have it) plus
/// the one-line summary, so Messages/Mail attach the file and carry the text.
private struct ReceiptShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

private extension View {
    func receiptCard(radius: CGFloat) -> some View {
        background(Nuru.white, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
