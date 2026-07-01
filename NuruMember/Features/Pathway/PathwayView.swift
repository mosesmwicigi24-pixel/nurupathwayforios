// Pathway tab — native port of the RN Pathway dashboard (IMG_1895–1898). Navy
// header (greeting, level status, streak pill, progress ring), a "pick up where
// you left off" continue card, a reminders card, then THE JOURNEY: the active
// level's module trail plus locked level cards and the Summit hero.
import SwiftUI

/// Value-based routes pushed within the Pathway tab.
enum PathwayRoute: Hashable {
    case level(Int)
    case module(String)   // moduleId
    case quiz(String)     // moduleId
}

@MainActor
final class PathwayViewModel: ObservableObject {
    @Published var summary: PathwaySummary?
    @Published var streak = 0
    @Published var activeModules: [LevelModule] = []
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        async let pathway = try? MemberAPI.pathway()
        async let ach = try? MemberAPI.achievements()
        let p = await pathway
        summary = p
        streak = await ach?.streak.current ?? 0
        if let active = active(in: p) {
            activeModules = (try? await MemberAPI.levelModules(active.levelNumber)) ?? []
        }
        if summary == nil { error = "Couldn't load your pathway." }
        loading = false
    }

    private func active(in p: PathwaySummary?) -> PathwayLevel? {
        guard let p else { return nil }
        return p.levels.first { $0.status == .active }
            ?? p.levels.first { $0.levelNumber == p.currentLevel }
            ?? p.levels.first
    }
    var activeLevel: PathwayLevel? { active(in: summary) }
    var continueModule: LevelModule? {
        activeModules.first { $0.status == .next } ?? activeModules.first { !$0.completed && !$0.locked }
    }
    var overallPct: Int {
        guard let p = summary else { return 0 }
        let total = p.levels.reduce(0) { $0 + $1.totalModules }
        let done = p.levels.reduce(0) { $0 + $1.completedModules }
        return total > 0 ? Int(round(Double(done) / Double(total) * 100)) : 0
    }
}

struct PathwayView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = PathwayViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Nuru.S.base) {
                    header
                    if vm.loading && vm.summary == nil {
                        ProgressView().padding(.top, Nuru.S.xl)
                    } else if let summary = vm.summary {
                        if let m = vm.continueModule { continueCard(m) }
                        if let a = vm.activeLevel { remindersCard(a) }
                        journey(summary)
                        summitHero
                    } else {
                        errorState
                    }
                }
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .ignoresSafeArea(edges: .top)
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .navigationDestination(for: PathwayRoute.self) { r in
                switch r {
                case .level(let n): LevelDetailView(levelNumber: n)
                case .module(let id): ModuleView(moduleId: id)
                case .quiz(let id): QuizView(moduleId: id)
                }
            }
        }
        .background(Color.clear.preferredColorScheme(.dark))   // full-bleed navy header → white status bar
        .task { if vm.summary == nil { await vm.load() } }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            Text("YOUR PATHWAY").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(greeting), \(firstName).").font(.fraunces(22, .semibold)).foregroundStyle(.white)
                    if let a = vm.activeLevel {
                        Text("Level \(a.levelNumber) of \(vm.summary?.levels.count ?? 7) · \(a.title)")
                            .font(.nCaption).foregroundStyle(Nuru.onNavyDim)
                        Text("\(a.completedModules) of \(a.totalModules) modules complete")
                            .font(.nMicro).foregroundStyle(Nuru.onNavyFaint)
                    }
                }
                Spacer(minLength: Nuru.S.sm)
                VStack(alignment: .trailing, spacing: Nuru.S.sm) {
                    HStack(spacing: 4) {
                        Icon(.flame, size: 11, color: Nuru.goldChipText)
                        Text("\(vm.streak)-day streak").font(.inter(10, .bold)).foregroundStyle(Nuru.goldChipText)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5).background(Nuru.goldChipBg, in: Capsule())
                    progressRing
                }
            }
            // Level progress dots
            HStack(spacing: 4) {
                ForEach(0..<(vm.summary?.levels.count ?? 7), id: \.self) { i in
                    Capsule().fill(i < (vm.activeLevel?.levelNumber ?? 1) ? Nuru.gold : Color.white.opacity(0.18))
                        .frame(width: i == (vm.activeLevel?.levelNumber ?? 1) - 1 ? 18 : 6, height: 4)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen).padding(.top, 64).padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    private var progressRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.15), lineWidth: 4).frame(width: 48, height: 48)
            Circle().trim(from: 0, to: CGFloat(vm.overallPct) / 100)
                .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                .frame(width: 48, height: 48)
            Text("\(vm.overallPct)%").font(.inter(11, .bold)).foregroundStyle(.white)
        }
    }

    // MARK: continue card

    private func continueCard(_ m: LevelModule) -> some View {
        NavigationLink(value: PathwayRoute.module(m.moduleId)) {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack {
                    Text("PICK UP WHERE YOU LEFT OFF").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.goldGlow)
                    Spacer()
                }
                Text(m.title).font(.fraunces(18, .semibold)).foregroundStyle(.white)
                HStack(spacing: Nuru.S.sm) {
                    Text(vm.activeLevel?.title ?? "").font(.nMicro).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Color.white.opacity(0.12), in: Capsule())
                    Text("Module \(m.moduleSequenceNumber) of \(vm.activeLevel?.totalModules ?? 0)\(m.estimatedMinutes.map { " · \($0) min" } ?? "")")
                        .font(.nMicro).foregroundStyle(Nuru.onNavyDim)
                }
                ProgressView(value: m.progress).tint(Nuru.gold)
                HStack {
                    Spacer()
                    HStack(spacing: 4) { Text("Continue").font(.inter(13, .bold)).foregroundStyle(Nuru.navyDeep); Icon(.chevronRight, size: 13, color: Nuru.navyDeep) }
                        .padding(.horizontal, 16).padding(.vertical, 9).background(Nuru.gold, in: Capsule())
                }
            }
            .padding(Nuru.S.base)
            .background(
                LinearGradient(colors: [Nuru.navy700, Color(hex: 0x5A5326), Color(hex: 0x7A6A2E)], startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .nuruShadow()
            .padding(.horizontal, Nuru.S.screen)
        }
        .buttonStyle(.plain)
    }

    private func remindersCard(_ a: PathwayLevel) -> some View {
        let pct = a.totalModules > 0 ? Int(round(Double(a.completedModules) / Double(a.totalModules) * 100)) : 0
        return NavigationLink(value: PathwayRoute.level(a.levelNumber)) {
            HStack(spacing: Nuru.S.md) {
                Icon(.award, size: 22, color: .white)
                VStack(alignment: .leading, spacing: 2) {
                    Text("ALMOST THERE").font(.inter(10, .bold)).kerning(1).foregroundStyle(.white.opacity(0.85))
                    Text("\(a.title) · \(pct)%").font(.inter(14, .bold)).foregroundStyle(.white)
                    Text("Finish this level to earn your certificate").font(.nMicro).foregroundStyle(.white.opacity(0.8))
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 16, color: .white)
            }
            .padding(Nuru.S.base)
            .background(LinearGradient(colors: [Nuru.success, Color(hex: 0x2E8B57)], startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.horizontal, Nuru.S.screen)
        }
        .buttonStyle(.plain)
    }

    // MARK: the journey

    private func journey(_ summary: PathwaySummary) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text("THE JOURNEY").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
                Spacer()
                Text("Level \(vm.activeLevel?.levelNumber ?? 1) of \(summary.levels.count)").font(.nMicro).foregroundStyle(Nuru.faint)
            }
            ForEach(summary.levels) { level in
                if level.levelNumber == vm.activeLevel?.levelNumber {
                    activeLevelCard(level)
                } else {
                    lockedLevelCard(level, currentLevel: summary.currentLevel)
                }
            }
        }
        .padding(.horizontal, Nuru.S.screen)
    }

    private func activeLevelCard(_ level: PathwayLevel) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack {
                Text("LEVEL \(level.levelNumber)").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.gold)
                Spacer()
                Text("IN PROGRESS").font(.nMicro).foregroundStyle(Nuru.goldChipText)
                    .padding(.horizontal, 8).padding(.vertical, 3).background(Nuru.goldChipBg, in: Capsule())
            }
            Text(level.title).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
            if let theme = level.theme { Text(theme).font(.nCaption).foregroundStyle(Nuru.muted) }
            HStack(spacing: Nuru.S.sm) {
                ProgressView(value: level.totalModules > 0 ? Double(level.completedModules) / Double(level.totalModules) : 0).tint(Nuru.gold)
                Text("\(level.completedModules)/\(level.totalModules)").font(.nMicro).foregroundStyle(Nuru.faint)
            }
            ForEach(vm.activeModules.prefix(3)) { m in moduleTrailRow(m) }
            NavigationLink(value: PathwayRoute.level(level.levelNumber)) {
                Text("View all \(level.totalModules) modules ›").font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4])))
            }
            .buttonStyle(.plain)
            HStack(spacing: Nuru.S.base) {
                statChip(.bookOpen, "\(level.completedModules)/\(level.totalModules) modules")
                if level.minutes > 0 { statChip(.clock, formatMinutes(level.minutes)) }
                statChip(.trendingUp, "\(level.totalModules > 0 ? Int(round(Double(level.completedModules)/Double(level.totalModules)*100)) : 0)% done")
            }
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func moduleTrailRow(_ m: LevelModule) -> some View {
        let tint: Color = m.completed ? Nuru.goldTint : Nuru.surface
        return HStack(spacing: Nuru.S.md) {
            ZStack {
                Circle().fill(m.completed ? Nuru.gold : Nuru.mutedBg).frame(width: 30, height: 30)
                Icon(m.completed ? .check : .lock, size: 13, color: m.completed ? .white : Nuru.faint)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(m.title).font(.inter(13, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Text(m.completed ? "Completed" : "Locked").font(.nMicro)
                    .foregroundStyle(m.completed ? Nuru.successText : Nuru.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.sm)
        .background(tint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func lockedLevelCard(_ level: PathwayLevel, currentLevel: Int) -> some View {
        let locked = LevelGating.isLevelLocked(level.levelNumber, currentLevel: currentLevel, serverStatus: level.status)
        return VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack {
                Text("LEVEL \(level.levelNumber)").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.gold)
                Spacer()
                if locked { Text("LOCKED").font(.nMicro).foregroundStyle(Nuru.faint).padding(.horizontal, 8).padding(.vertical, 3).background(Nuru.mutedBg, in: Capsule()) }
            }
            Text(level.title).font(.fraunces(17, .semibold)).foregroundStyle(Nuru.ink)
            if let theme = level.theme { Text(theme).font(.nCaption).foregroundStyle(Nuru.muted) }
            HStack(spacing: Nuru.S.base) {
                statChip(.bookOpen, "\(level.completedModules)/\(level.totalModules) modules")
                statChip(.clock, level.minutes > 0 ? formatMinutes(level.minutes) : "0 min")
            }
            HStack(spacing: Nuru.S.sm) {
                Icon(.award, size: 14, color: Nuru.ink400)
                Text("Certificate awaiting you").font(.nCaption).foregroundStyle(Nuru.muted)
                Spacer()
            }
            .padding(Nuru.S.sm).background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Text(locked ? "Complete Level \(currentLevel) to unlock" : "Tap to continue").font(.nMicro).foregroundStyle(Nuru.faint)
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .opacity(locked ? 0.85 : 1)
    }

    private var summitHero: some View {
        VStack(spacing: 4) {
            Icon(.award, size: 24, color: Nuru.gold)
            Text("THE SUMMIT").font(.inter(11, .bold)).kerning(2).foregroundStyle(Nuru.goldGlow)
            Text("Commissioned").font(.fraunces(22, .semibold)).foregroundStyle(.white)
            Text("Sent to make disciples · Matthew 28:19").font(.nCaption).foregroundStyle(Nuru.onNavyDim)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl)
        .background(Nuru.ceremonyGradient, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .padding(.horizontal, Nuru.S.screen)
    }

    private func statChip(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) { Icon(icon, size: 11, color: Nuru.goldLo); Text(text).font(.nMicro).foregroundStyle(Nuru.ink600) }
    }

    private var errorState: some View {
        VStack(spacing: Nuru.S.md) {
            Text(vm.error ?? "Something went wrong.").font(.nBody).foregroundStyle(Nuru.muted)
            Button("Try again") { Task { await vm.load() } }.font(.inter(14, .semibold)).foregroundStyle(Nuru.gold)
        }.padding(Nuru.S.xl)
    }

    private var firstName: String { (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend" }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }
    private func formatMinutes(_ m: Int) -> String { m >= 60 ? "\(m/60)h \(m%60)m" : "\(m)m" }
}
