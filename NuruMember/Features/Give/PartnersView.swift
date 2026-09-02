// The Partners page — recognition, not receipts.
//
// Receipts live in Giving (history, statements, PDFs) and stay there. This page
// answers a different question: what has my faithfulness added up to?
//
// Everything is derived server-side from the member's giving schedule, so this
// view holds no second copy of the truth. Two rules from the design carry all
// the way into the copy, and both are easy to erode later:
//
//   · `kept` is cycles COLLECTED, never cycles scheduled. The label says
//     "collected" for exactly that reason — a partner whose June failed did not
//     keep June, and saying otherwise is flattery built on a false number.
//
//   · the season block is what the WHOLE CHURCH did while they partnered. Never
//     "your giving produced this". We cannot trace a shilling to a disciple and
//     the wording must not imply we can.
import SwiftUI

@MainActor final class PartnersModel: ObservableObject {
    @Published var partnership: Partnership?
    @Published var loading = false
    @Published var error: String?
    @Published var resuming = false

    func load() async {
        loading = true; error = nil
        partnership = try? await MemberAPI.partnership()
        if partnership == nil { error = "We couldn't load this just now." }
        loading = false
    }

    func resume(_ scheduleId: String) async {
        resuming = true
        defer { resuming = false }
        do { try await MemberAPI.resumeSchedule(scheduleId); await load() }
        // `catch` binds its own `error`, which shadows the published one.
        catch { self.error = "That didn't go through. Your giving is unchanged." }
    }
}

struct PartnersView: View {
    @StateObject private var vm = PartnersModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let p = vm.partnership {
                    if p.isPartner { partner(p) } else { invitation(p) }
                } else if vm.loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if vm.error != nil {
                    PartnerNotice(
                        title: "We couldn't load this just now",
                        message: "Your giving is unaffected. Pull down to try again.")
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationTitle("Partners")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.load() }
        .task { if vm.partnership == nil { await vm.load() } }
    }

    // MARK: - Someone who partners

    @ViewBuilder private func partner(_ p: Partnership) -> some View {
        PartnerStanding(partnership: p)

        // Shown ONLY when there is something to say. A partner whose giving is
        // collecting cleanly never sees a block shaped like a warning.
        if let t = p.trouble {
            PartnerTrouble(
                trouble: t,
                resuming: vm.resuming,
                onResume: p.scheduleId.map { id in { Task { await vm.resume(id) } } })
        }
        if let r = p.rhythm { PartnerRhythm(rhythm: r, currency: p.currency) }
        if let s = p.sinceYouBegan { PartnerSeason(season: s) }

        Text("Your gifts, receipts and statements stay in Giving.")
            .font(.nCaption).foregroundStyle(Nuru.ink400)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.top, 4)
    }

    // MARK: - Not a partner — today, or ever

    @ViewBuilder private func invitation(_ p: Partnership) -> some View {
        PartnerNotice(
            title: p.everPartnered ? "You have partnered before" : "Become a partner",
            message: p.everPartnered
                ? "Your partnership ended, and nothing is owed. If you would like to begin again, you can set up a monthly gift in Giving."
                : "A partner decides in advance to keep giving, month after month, so the church can plan beyond what arrives on a Sunday. You can begin in Giving — and change it or stop whenever you need to.")
    }
}

// MARK: - Standing

private struct PartnerStanding: View {
    let partnership: Partnership

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("YOUR STANDING")
                .font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)

            Text(headline)
                .font(.nuruDisplay(26)).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)

            if partnership.kept > 0 {
                HStack(spacing: 8) {
                    Text("\(partnership.kept)")
                        .font(.nuruDisplay(30)).foregroundStyle(Nuru.gold)
                    // "collected", never "kept" — the word carries the honesty
                    // rule the server enforces.
                    Text(partnership.kept == 1 ? "gift collected" : "gifts collected")
                        .font(.nBody).foregroundStyle(Nuru.ink600)
                }
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Nuru.gold.opacity(0.28), lineWidth: 1))
    }

    private var headline: String {
        guard let since = partnership.since, let month = Self.monthYear(since) else {
            return "You are a partner of this church."
        }
        return "You have partnered since \(month)."
    }

    static func monthYear(_ iso: String) -> String? {
        guard let d = PartnerFormat.date(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return f.string(from: d)
    }
}

// MARK: - Trouble (only when there is some)

private struct PartnerTrouble: View {
    let trouble: Partnership.Trouble
    let resuming: Bool
    let onResume: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(trouble.paused ? "Your giving is paused" : "One gift didn't go through")
                .font(.nHeading).foregroundStyle(Nuru.ink)
            Text(message)
                .font(.nBody).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)

            if trouble.paused, let onResume {
                Button(action: onResume) {
                    HStack(spacing: 8) {
                        if resuming { ProgressView().tint(.white) }
                        Text(resuming ? "Starting again…" : "Start it again")
                            .font(.nLabel)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 12)
                    .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.white)
                }
                .disabled(resuming)
                .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // Plain, and never alarming. Nothing is owed, and we say so first.
    private var message: String {
        if trouble.paused {
            return "We tried a few times and couldn't collect it, so we stopped trying rather than keep charging you. Nothing is owed. Starting again picks up from your next gift — it will not collect the one that was missed."
        }
        return "We couldn't collect your last gift. We'll try again shortly, and nothing is owed in the meantime."
    }
}

// MARK: - Rhythm

private struct PartnerRhythm: View {
    let rhythm: Partnership.Rhythm
    let currency: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("YOUR RHYTHM")
                .font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(amount).font(.nuruDisplay(22)).foregroundStyle(Nuru.ink)
                Text(rhythm.frequency == "weekly" ? "each week" : "each month")
                    .font(.nBody).foregroundStyle(Nuru.ink600)
            }
            PartnerRow(label: "Method", value: method)
            PartnerRow(label: "Fund", value: rhythm.fund.capitalized)
            PartnerRow(label: "Next gift", value: nextGift)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var amount: String {
        "\(currency) \(PartnerFormat.grouped(rhythm.amountMinor / 100))"
    }
    private var method: String {
        switch rhythm.method {
        case "mpesa": return "M-Pesa"
        case "airtel": return "Airtel Money"
        default: return "Card"
        }
    }
    // Paused schedules carry no next date, and we say the true thing rather
    // than showing a stale one.
    private var nextGift: String {
        guard let next = rhythm.nextRunAt, let d = PartnerFormat.date(next) else {
            return "Paused"
        }
        let f = DateFormatter(); f.dateFormat = "d MMMM"
        return f.string(from: d)
    }
}

private struct PartnerRow: View {
    let label: String, value: String
    var body: some View {
        HStack {
            Text(label).font(.nBody).foregroundStyle(Nuru.ink600)
            Spacer(minLength: 12)
            Text(value).font(.nBody).foregroundStyle(Nuru.ink)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - The season (church-wide, never attributed)

private struct PartnerSeason: View {
    let season: Partnership.Season

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("SINCE YOU BEGAN")
                .font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)

            // The framing IS the honesty. "Across the church" is doing real
            // work in this sentence — remove it and the page starts claiming
            // something we cannot prove.
            Text("Across the church, in the season you have been partnering:")
                .font(.nBody).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                if season.levelsCompleted > 0 {
                    PartnerCount(n: season.levelsCompleted,
                                 one: "disciple finished a level",
                                 many: "disciples finished a level")
                }
                if season.modulesCompleted > 0 {
                    PartnerCount(n: season.modulesCompleted,
                                 one: "module completed", many: "modules completed")
                }
                if season.plansFinished > 0 {
                    PartnerCount(n: season.plansFinished,
                                 one: "reading plan finished", many: "reading plans finished")
                }
                if season.levelsCompleted == 0 && season.modulesCompleted == 0
                    && season.plansFinished == 0 {
                    Text("It is early days. This will fill as the church walks on.")
                        .font(.nBody).foregroundStyle(Nuru.ink400)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct PartnerCount: View {
    let n: Int, one: String, many: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(n)")
                .font(.nuruDisplay(24)).foregroundStyle(Nuru.gold)
                .frame(minWidth: 44, alignment: .leading)
            Text(n == 1 ? one : many)
                .font(.nBody).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Notices

private struct PartnerNotice: View {
    let title: String
    let message: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.nuruDisplay(24)).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(message).font(.nBodyLg).foregroundStyle(Nuru.ink600)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(22)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.top, 24)
    }
}

// MARK: - Formatting

/// Timestamps arrive from Postgres with OR without fractional seconds depending
/// on the column, and the shared `ISO8601DateFormatter.nuru` only accepts the
/// fractional form. Trying both is the difference between a real date and a
/// screen that quietly says "Paused" when nothing is paused.
enum PartnerFormat {
    private static let withMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static func date(_ iso: String) -> Date? {
        withMillis.date(from: iso) ?? plain.date(from: iso)
    }

    private static let number: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        f.maximumFractionDigits = 0
        return f
    }()
    static func grouped(_ n: Int) -> String {
        number.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}
