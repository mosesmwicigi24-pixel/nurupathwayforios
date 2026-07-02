// Level detail — the native port of screens/LevelScreen.tsx (IMG_1899): a parallax
// navy hero with the level title, a stats strip, a "Walk in the light" verse card,
// a "walk it with your discipler" prompt, then THE MODULE TRAIL — a vertical list
// of module cards strung on a gold rail. Completed modules are checked; the next
// one is numbered/open; locked modules are dimmed and non-tappable (server is
// authoritative, §1.9).
import SwiftUI

@MainActor
final class LevelDetailViewModel: ObservableObject {
    @Published var modules: [LevelModule] = []
    @Published var level: PathwayLevel?
    @Published var totalLevels = 7
    @Published var loading = true
    @Published var error: String?

    let levelNumber: Int
    init(levelNumber: Int) { self.levelNumber = levelNumber }

    func load() async {
        loading = true; error = nil
        async let mods = try? MemberAPI.levelModules(levelNumber)
        async let path = try? MemberAPI.pathway()
        let loaded = await mods
        if let summary = await path {
            level = summary.levels.first { $0.levelNumber == levelNumber }
            totalLevels = summary.levels.count
        }
        if let loaded { modules = loaded }
        else if level == nil { error = "Couldn't load this level." }
        loading = false
    }

    // Derived stats for the strip card.
    var completed: Int { modules.filter(\.completed).count }
    var moduleCount: Int { max(modules.count, level?.totalModules ?? 0) }
    var pct: Int {
        guard moduleCount > 0 else { return 0 }
        return Int(round(Double(completed) / Double(moduleCount) * 100))
    }
    var minutes: Int {
        let fromMods = modules.compactMap(\.estimatedMinutes).reduce(0, +)
        return fromMods > 0 ? fromMods : (level?.minutes ?? 0)
    }
    var lessonCount: Int { moduleCount }
    var title: String { level?.title ?? "Level \(levelNumber)" }
    var verse: (text: String, ref: String) {
        if let theme = level?.theme, !theme.isEmpty {
            return ("He that followeth me shall not walk in darkness, but shall have the light of life.", theme)
        }
        return ("He that followeth me shall not walk in darkness, but shall have the light of life.", "John 8:12")
    }
}

struct LevelDetailView: View {
    let levelNumber: Int
    @StateObject private var vm: LevelDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var barShown = false

    init(levelNumber: Int) {
        self.levelNumber = levelNumber
        _vm = StateObject(wrappedValue: LevelDetailViewModel(levelNumber: levelNumber))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                VStack(spacing: Nuru.S.base) {
                    statsStrip
                    verseCard
                    disciplerCard
                    trailHeader
                    if vm.loading && vm.modules.isEmpty {
                        trailSkeleton
                    } else if vm.modules.isEmpty {
                        VStack(spacing: Nuru.S.md) {
                            Text(vm.error ?? "No modules yet.")
                                .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                            if vm.error != nil {
                                Button {
                                    Haptics.tap()
                                    Task { await vm.load() }
                                } label: {
                                    Text("Try again").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                                        .padding(.horizontal, 20).padding(.vertical, 10)
                                        .background(Nuru.gold, in: Capsule())
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.top, Nuru.S.lg)
                    } else {
                        moduleTrail
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
                // Stats strip should overlap the hero slightly.
                .offset(y: -Nuru.S.lg)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.modules.isEmpty && vm.level == nil { await vm.load() } }
        .refreshable { await vm.load() }
    }

    // MARK: - Hero (parallax-style image with dark gradient + overline + title)

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            // Hero image removed by design — the header is always the navy gradient.
            Nuru.heroGradient.clipped()

            // Dark legibility gradient from the bottom.
            LinearGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.35), Color(hex: 0x081C36).opacity(0.92)],
                startPoint: .top, endPoint: .bottom)

            VStack(alignment: .leading, spacing: 4) {
                Text(overline.uppercased())
                    .font(.inter(11, .bold)).kerning(1.6)
                    .foregroundStyle(Nuru.goldGlow)
                Text(vm.title)
                    .font(.fraunces(30, .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.bottom, Nuru.S.xl + Nuru.S.sm)
        }
        .frame(height: 280)
        .overlay(alignment: .topLeading) {
            // Custom back button (nav bar is hidden).
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .nuruShadow()
                    .contentShape(Circle())
            }
            .buttonStyle(.pressable)
            .padding(.leading, Nuru.S.screen)
            .padding(.top, 58)
        }
    }

    /// Short overline above the serif title (the title's first word, e.g. "Foundations").
    private var overline: String { vm.title.split(separator: " ").first.map(String.init) ?? "Level \(levelNumber)" }

    // MARK: - Stats strip

    private var statsStrip: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(vm.completed) of \(vm.moduleCount) modules")
                        .font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
                        .contentTransition(.numericText())
                        .animation(.default, value: vm.completed)
                    Spacer()
                    Text("\(vm.pct)%")
                        .font(.inter(13, .bold)).foregroundStyle(Nuru.gold)
                        .contentTransition(.numericText())
                        .animation(.default, value: vm.pct)
                }
                progressBar(Double(vm.pct) / 100)
                HStack(spacing: Nuru.S.sm) {
                    statChip(.clock, "≈ \(vm.minutes) min")
                    statChip(.bookOpen, "\(vm.lessonCount) lessons")
                }
            }
        }
    }

    private func statChip(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 12, color: Nuru.goldLo)
            Text(text).font(.inter(12, .medium)).foregroundStyle(Nuru.ink600)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Nuru.surface, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: - Verse card

    private var verseCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(spacing: 6) {
                Icon(.quote, size: 13, color: Nuru.goldChipText)
                Text("WALK IN THE LIGHT")
                    .font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.goldChipText)
            }
            Text("“\(vm.verse.text)”")
                .font(.fraunces(16, .medium)).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(vm.verse.ref)
                .font(.inter(12, .semibold)).foregroundStyle(Nuru.goldLo)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    // MARK: - Discipler card

    private var disciplerCard: some View {
        Card {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    Circle().fill(Nuru.goldTint).frame(width: 44, height: 44)
                    Icon(.handHeart, size: 20, color: Nuru.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("WALK IT WITH YOUR DISCIPLER")
                        .font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.goldChipText)
                    Text("A discipler will walk with you")
                        .font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                    Text("Tap to learn more")
                        .font(.nMicro).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: Nuru.S.sm)
                HStack(spacing: 6) {
                    Icon(.messageCircle, size: 14, color: .white)
                    Text("Chat").font(.inter(13, .bold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 14).padding(.vertical, 9)
                .background(Nuru.navyDeep, in: Capsule())
            }
        }
    }

    // MARK: - Trail header

    private var trailHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("YOUR MODULE TRAIL")
                    .font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
                Text("Learn step by step")
                    .font(.fraunces(20, .semibold)).foregroundStyle(Nuru.ink)
            }
            Spacer()
            Text("\(vm.lessonCount) lessons")
                .font(.inter(12, .semibold)).foregroundStyle(Nuru.ink600)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Nuru.white, in: Capsule())
                .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        }
        .padding(.top, Nuru.S.sm)
    }

    // MARK: - Module trail (cards strung on a gold rail)

    private var moduleTrail: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.modules.enumerated()), id: \.element.id) { idx, m in
                moduleRow(m, isLast: idx == vm.modules.count - 1)
            }
        }
    }

    /// Shimmering placeholder trail while the real modules are fetched — same
    /// rail-and-card silhouette so content settles in place.
    private var trailSkeleton: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                HStack(alignment: .top, spacing: Nuru.S.md) {
                    VStack(spacing: 0) {
                        Circle().fill(Nuru.mutedBg).frame(width: 36, height: 36)
                        if i < 2 {
                            Rectangle().fill(Nuru.gold.opacity(0.15)).frame(width: 2).frame(maxHeight: .infinity)
                        }
                    }
                    .frame(width: 36)
                    VStack(alignment: .leading, spacing: 10) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Nuru.mutedBg).frame(width: 76, height: 8)
                        RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Nuru.mutedBg).frame(width: 180, height: 14)
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Nuru.mutedBg).frame(maxWidth: .infinity).frame(height: 10)
                        HStack(spacing: Nuru.S.sm) {
                            Capsule().fill(Nuru.mutedBg).frame(width: 64, height: 24)
                            Capsule().fill(Nuru.mutedBg).frame(width: 52, height: 24)
                        }
                    }
                    .padding(Nuru.S.base)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    .padding(.bottom, Nuru.S.base)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .nuruShimmer()
        .accessibilityLabel("Loading modules")
    }

    @ViewBuilder
    private func moduleRow(_ m: LevelModule, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            // Rail + node on the left.
            VStack(spacing: 0) {
                node(m)
                if !isLast {
                    Rectangle()
                        .fill(Nuru.gold.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            // The card itself, tappable unless locked. A locked tap never opens
            // content (server-authoritative, §1.9) — it answers with a refusal
            // shake; the card's footer already says what unlocks it.
            Group {
                if m.locked {
                    LockedTrailCard(module: m)
                } else {
                    NavigationLink(value: PathwayRoute.module(m.moduleId)) {
                        ModuleTrailCard(module: m)
                    }
                    .buttonStyle(.pressable)
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                }
            }
            .padding(.bottom, Nuru.S.base)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func node(_ m: LevelModule) -> some View {
        ZStack {
            Circle()
                .fill(m.completed ? Nuru.gold : (m.locked ? Nuru.mutedBg : Nuru.goldTint))
                .frame(width: 36, height: 36)
            if m.completed {
                Icon(.check, size: 15, color: .white)
            } else if m.locked {
                Icon(.lock, size: 13, color: Nuru.faint)
            } else {
                Text("\(m.moduleSequenceNumber)")
                    .font(.inter(14, .bold)).foregroundStyle(Nuru.gold)
            }
        }
    }

    // MARK: - Helpers

    private func progressBar(_ value: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Nuru.gold.opacity(0.15)).frame(height: 5)
                Capsule().fill(Nuru.gold)
                    .frame(width: (barShown ? max(0, min(1, value)) : 0) * geo.size.width, height: 5)
                    .animation(.spring(response: 0.8, dampingFraction: 0.9), value: value)
            }
        }
        .frame(height: 5)
        .onAppear {
            guard !barShown else { return }
            if reduceMotion { barShown = true }
            else { withAnimation(.spring(response: 0.8, dampingFraction: 0.9).delay(0.1)) { barShown = true } }
        }
    }
}

// MARK: - Locked trail card (refusal shake — lock state itself is the server's)

private struct LockedTrailCard: View {
    let module: LevelModule
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakes = 0

    var body: some View {
        Button {
            Haptics.error()
            if !reduceMotion { withAnimation(.linear(duration: 0.35)) { shakes += 1 } }
        } label: {
            ModuleTrailCard(module: module)
        }
        .buttonStyle(.pressableSubtle)
        .modifier(PWLockedShake(animatableData: CGFloat(shakes)))
        .accessibilityHint("Locked. Unlocks when you finish the one before.")
    }
}

// MARK: - Module trail card

private struct ModuleTrailCard: View {
    let module: LevelModule

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text("MODULE \(module.moduleSequenceNumber)")
                    .font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.gold)
                Spacer()
                statusBadge
            }
            Text(module.title)
                .font(.fraunces(17, .semibold)).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = module.summary, !summary.isEmpty {
                Text(summary)
                    .font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2)
            }
            if module.completed {
                progressBarRow
            }
            chipsRow
            footerLine
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .opacity(module.locked ? 0.7 : 1)
    }

    @ViewBuilder
    private var statusBadge: some View {
        if module.completed {
            Text("DONE")
                .font(.inter(10, .bold)).kerning(0.5).foregroundStyle(Nuru.successText)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Nuru.successBg, in: Capsule())
        } else if module.locked {
            Text("LOCKED")
                .font(.inter(10, .bold)).kerning(0.5).foregroundStyle(Nuru.faint)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Nuru.mutedBg, in: Capsule())
        }
    }

    private var progressBarRow: some View {
        HStack(spacing: Nuru.S.sm) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.gold.opacity(0.15)).frame(height: 5)
                    Capsule().fill(Nuru.gold).frame(width: geo.size.width, height: 5)
                }
            }
            .frame(height: 5)
            Text("100%").font(.inter(11, .bold)).foregroundStyle(Nuru.gold)
        }
    }

    private var chipsRow: some View {
        HStack(spacing: Nuru.S.sm) {
            if let mins = module.estimatedMinutes {
                chip(.clock, "\(mins) min")
            }
            if module.requiresQuiz {
                chip(.pencil, "Quiz")
            }
        }
    }

    private func chip(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 11, color: Nuru.goldLo)
            Text(text).font(.inter(12, .medium)).foregroundStyle(Nuru.ink600)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Nuru.surface, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    @ViewBuilder
    private var footerLine: some View {
        if module.completed {
            Text("Completed — nicely done.")
                .font(.nMicro).foregroundStyle(Nuru.successText)
        } else if module.locked {
            Text("Unlocks when you finish the one before.")
                .font(.nMicro).foregroundStyle(Nuru.faint)
        } else {
            HStack(spacing: 4) {
                Text("Start this module").font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                Icon(.chevronRight, size: 12, color: Nuru.gold)
            }
        }
    }
}

private extension LevelModule {
    var requiresQuiz: Bool { evaluationKind.lowercased().contains("quiz") }
}
