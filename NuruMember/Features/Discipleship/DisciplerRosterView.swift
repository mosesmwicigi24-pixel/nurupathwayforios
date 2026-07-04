// Discipler roster — the leader's view of their flock, fed by GET /disciples.
// A cream header ("Your disciples" + "N walking with you · M awaiting action"),
// then one row per student: avatar, name, level · cell, and the health chips
// (band pill, gold "Usher · L{n}" when a level advancement awaits, pending-
// reflection count, streak and recency). The server pre-sorts needs-action
// first — this screen NEVER re-sorts. Tapping a row pushes the student's
// dossier. Pure read: nothing here advances a level or originates gating (§1.9).
import SwiftUI

@MainActor
final class DisciplerRosterViewModel: ObservableObject {
    @Published var roster: DiscipleRoster?
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { roster = try await MemberAPI.disciples() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your disciples." }
        loading = false
    }
}

struct DisciplerRosterView: View {
    @StateObject private var vm = DisciplerRosterViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.md) {
                        if vm.loading && vm.roster == nil {
                            skeleton
                        } else if let roster = vm.roster {
                            if roster.data.isEmpty {
                                emptyCard
                            } else {
                                // Server order preserved — needs-action rows first.
                                ForEach(Array(roster.data.enumerated()), id: \.element.id) { i, row in
                                    NavigationLink(value: row) { rosterRow(row) }
                                        .buttonStyle(.pressable)
                                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                                        .gentleEntrance(delay: Double(min(i, 8)) * 0.04)
                                }
                            }
                        } else if let err = vm.error {
                            errorCard(err)
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(for: DiscipleRoster.Row.self) { DisciplerDossierView(row: $0) }
        .task { if vm.roster == nil { await vm.load() } }
    }

    // MARK: cream header (matches DiscipleshipHubView anatomy)

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("SHEPHERD THE FLOCK")
                    .font(.nCardKicker).tracking(1.4)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Text("Your disciples")
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.navy)
                if let s = vm.roster?.summary {
                    Text(subline(s))
                        .font(.inter(12)).foregroundStyle(Color(hex: 0x59667C))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.25)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }

    private func subline(_ s: DiscipleRoster.Summary) -> String {
        let walking = "\(s.totalStudents) walking with you"
        guard s.awaitingAction > 0 else { return walking }
        return "\(walking) · \(s.awaitingAction) awaiting action"
    }

    // MARK: student row — avatar · name · level/cell · health chips

    private func rosterRow(_ row: DiscipleRoster.Row) -> some View {
        HStack(alignment: .top, spacing: Nuru.S.base) {
            Avatar(url: row.avatarUrl, name: row.fullName, size: 48)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.fullName)
                        .font(.inter(15, .bold)).foregroundStyle(Nuru.ink)
                        .lineLimit(1)
                    Spacer(minLength: Nuru.S.sm)
                    Icon(.chevronRight, size: 15, color: Nuru.ink300)
                }
                Text(row.cellName.map { "Level \(row.currentLevel) · \($0)" } ?? "Level \(row.currentLevel)")
                    .font(.nCardMeta).foregroundStyle(Nuru.muted)
                    .lineLimit(1)

                // Health chips — needs-action first, matching the server's priorities.
                HStack(spacing: 6) {
                    if let band = row.band { bandPill(band) }
                    if let level = row.awaitingLevel { usherPill(level) }
                    if row.pendingReflections > 0 { reflectionsChip(row.pendingReflections) }
                }

                // Quiet meta line — streak + recency.
                HStack(spacing: Nuru.S.sm) {
                    if row.streakDays > 0 {
                        Text("🔥 \(row.streakDays)-day")
                            .font(.nMicro).foregroundStyle(Nuru.goldLo)
                    }
                    Text(lastActiveLabel(row.daysSinceLastActivity))
                        .font(.nMicro)
                        .foregroundStyle((row.daysSinceLastActivity ?? 0) >= 7 && row.daysSinceLastActivity != nil
                                         ? Nuru.danger : Nuru.faint)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .contentShape(Rectangle())
    }

    /// Engagement band → small colored pill (thriving green / steady blue /
    /// watch gold / at_risk red — the shared Nuru band palette).
    private func bandPill(_ band: String) -> some View {
        let color = Nuru.bandColor(band)
        return Text(Self.bandLabel(band))
            .font(.inter(10, .bold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    /// Gold "Usher · L{n}" — a level advancement is waiting on THIS leader.
    private func usherPill(_ level: Int) -> some View {
        HStack(spacing: 3) {
            Icon(.sparkles, size: 9, color: Color(hex: 0x8A6D18))
            Text("Usher · L\(level)")
                .font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x8A6D18))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Nuru.goldTint.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
    }

    /// "{n} reflections" (or "1 reflection") awaiting review.
    private func reflectionsChip(_ n: Int) -> some View {
        Text(n == 1 ? "1 reflection" : "\(n) reflections")
            .font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x1B5FAE))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color(hex: 0x1B5FAE).opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: 0x1B5FAE).opacity(0.22), lineWidth: 1))
    }

    private func lastActiveLabel(_ days: Int?) -> String {
        guard let days else { return "No activity yet" }
        return days == 0 ? "Active today" : "Last active \(days)d ago"
    }

    static func bandLabel(_ band: String) -> String {
        switch band.lowercased() {
        case "thriving": return "Thriving"
        case "steady":   return "Steady"
        case "watch":    return "Watch"
        case "at_risk":  return "At risk"
        default:         return band.capitalized
        }
    }

    // MARK: loading skeleton (mirrors the row anatomy)

    private var skeleton: some View {
        VStack(spacing: Nuru.S.md) {
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: Nuru.S.base) {
                    Circle().fill(Nuru.surface).frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 150, height: 12)
                        RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 100, height: 9)
                        RoundedRectangle(cornerRadius: 8).fill(Nuru.surface).frame(width: 120, height: 16)
                    }
                    Spacer(minLength: 0)
                }
                .padding(Nuru.S.base)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                .nuruShimmer()
            }
        }
    }

    // MARK: error state (load failed — offer retry)

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: Nuru.S.md) {
            Text(message).font(.nCardBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            Button { Haptics.tap(); Task { await vm.load() } } label: {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: empty state (no assignments yet)

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                    .fill(Nuru.goldTint).frame(width: 48, height: 48)
                Icon(.users, size: 22, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("No disciples assigned yet")
                    .font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("When members are placed in your care, their journeys will live here.")
                    .font(.nCardBody).foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }
}
