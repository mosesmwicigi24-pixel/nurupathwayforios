// Level detail — the native port of screens/LevelScreen.tsx (IMG_1899): a parallax
// navy hero with the level title, a stats strip, a "Walk in the light" verse card,
// a "walk it with your discipler" prompt, then THE MODULE TRAIL — a vertical list
// of module cards strung on a gold rail. Completed modules are checked; the next
// one is numbered/open; locked modules are dimmed and non-tappable (server is
// authoritative, §1.9). Authored level encouragements are woven between the rows
// in trail order, and when every module is done (and the level itself isn't) the
// trail ends at THE LEVEL GATE — the CTA into the level exam. Eligibility stays
// the server's: the CTA is a doorway, and the exam endpoint answers politely if
// the gate isn't actually open.
import SwiftUI

/// One row of the trail — module cards and encouragement cards interleave on the
/// same gold rail (encouragements slot in by their after_module_sequence).
enum LevelTrailItem: Identifiable {
    case module(LevelModule)
    case encouragement(LevelEncouragement)
    /// The mid-level stats card (owner spec: "around modules 5-8 you should
    /// have a card that captures all your stats") — woven in once, positionally,
    /// like an authored encouragement, but built from the member's own real data.
    case stats
    var id: String {
        switch self {
        case .module(let m): return "m-\(m.moduleId)"
        case .encouragement(let e): return "e-\(e.encouragementId)"
        case .stats: return "trail-stats-card"
        }
    }
}

@MainActor
final class LevelDetailViewModel: ObservableObject {
    @Published var modules: [LevelModule] = []
    @Published var encouragements: [LevelEncouragement] = []
    @Published var level: PathwayLevel?
    @Published var totalLevels = 7
    @Published var loading = true
    @Published var error: String?
    /// The member's paired discipler (GET /growth/mentor) — feeds the discipler
    /// name/avatar into both the within-level reminder and the mid-level stats
    /// card. Best-effort: nil renders a generic "your discipler" fallback.
    @Published var mentor: MentorInfo.Mentor?
    /// This level's mastery (GET /me/levels/{n}/score) — the same server band
    /// ("Deeply rooted" / "Growing" / "Sprouting" / "Just beginning") shown at
    /// level-end, surfaced early on the mid-level stats card too.
    @Published var levelScore: LevelScore?
    /// Current streak in days (GET /me/achievements) — the same figure the
    /// Pathway hub header already shows.
    @Published var streak = 0

    let levelNumber: Int
    init(levelNumber: Int) { self.levelNumber = levelNumber }

    func load() async {
        loading = true; error = nil
        async let mods = try? MemberAPI.levelModules(levelNumber)
        async let path = try? MemberAPI.pathway()
        async let enc = try? MemberAPI.levelEncouragements(levelNumber)
        async let mentorInfo = try? MemberAPI.mentor()
        async let score = try? MemberAPI.levelScore(levelNumber)
        async let ach = try? MemberAPI.achievements()
        let loaded = await mods
        if let summary = await path {
            level = summary.levels.first { $0.levelNumber == levelNumber }
            totalLevels = summary.levels.count
        }
        if let loaded { modules = loaded }
        else if level == nil { error = "Couldn't load this level." }
        // Best-effort: no encouragements (unauthored or failed fetch) renders nothing.
        encouragements = (await enc) ?? []
        mentor = (await mentorInfo)?.mentor
        levelScore = await score
        streak = (await ach)?.streak?.current ?? 0
        loading = false
    }

    /// Modules with encouragements woven in at their after_module_sequence slot.
    /// Each encouragement lands after the LAST module whose sequence ≤ its slot
    /// (tolerates sequence gaps and entry floors); 0 — or a slot below every
    /// visible module — surfaces at the head of the trail; a slot past the last
    /// module trails it. Order within a slot is the server's.
    /// Where the mid-level stats card lands — directly after the 6th module row
    /// (or the 5th on a shorter level; skipped on very short levels where the
    /// card would feel out of place before there's anything to look back on).
    private var statsCardAfterIndex: Int? {
        guard modules.count >= 4 else { return nil }
        return min(modules.count, 6) - 1
    }

    var trailItems: [LevelTrailItem] {
        guard !encouragements.isEmpty else {
            var items = modules.map { LevelTrailItem.module($0) }
            if let at = statsCardAfterIndex, items.indices.contains(at) { items.insert(.stats, at: at + 1) }
            return items
        }
        var slots: [Int: [LevelEncouragement]] = [:]   // module index (-1 = trail head)
        for e in encouragements {
            let idx = e.afterModuleSequence <= 0
                ? -1
                : (modules.lastIndex { $0.moduleSequenceNumber <= e.afterModuleSequence } ?? -1)
            slots[idx, default: []].append(e)
        }
        let statsAt = statsCardAfterIndex
        var items: [LevelTrailItem] = (slots[-1] ?? []).map { .encouragement($0) }
        for (i, m) in modules.enumerated() {
            items.append(.module(m))
            if i == statsAt { items.append(.stats) }
            items += (slots[i] ?? []).map { .encouragement($0) }
        }
        return items
    }

    /// The member passed the exam and is waiting to be ushered onward by a
    /// discipler (§1.9). While set, the exam gate is replaced by the waiting card.
    var awaitingReview: Bool { level?.awaitingReview ?? false }

    /// The trail is fully walked but the level isn't passed (and not already awaiting
    /// a discipler's usher) — surface the exam gate. The fields here are the pathway
    /// API's own (module `completed`, level `status`, `awaitingReview`); the true
    /// eligibility answer stays the server's (§1.9).
    var examAvailable: Bool {
        !modules.isEmpty && modules.allSatisfy(\.completed) && level?.status != .completed && !awaitingReview
            && (level?.examPublished ?? true)   // hidden until the admin publishes the exam
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
    @State private var hasAppeared = false
    /// The within-level "walk with your discipler" reminder pop-up — see
    /// DisciplerReminderPolicy for the remind-don't-nag re-appearance rules.
    @State private var showReminder = false

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
        // Coming back from a pushed screen (quiz, exam) may have changed progress
        // or the level's status — refresh quietly so the trail and the exam gate
        // reflect the server's latest answer.
        .onAppear {
            if hasAppeared { Task { await vm.load() } }
            else { hasAppeared = true }
        }
        // The within-level reminder — checked once the level finishes loading
        // (also re-checked on the "came back" refresh above; the policy's
        // session guard keeps it to at most one appearance per level per visit).
        .onChange(of: vm.loading) { _, loading in
            if !loading { maybeShowDisciplerReminder() }
        }
        .overlay(alignment: .bottom) {
            if showReminder {
                DisciplerReminderCard(
                    mentorName: vm.mentor?.fullName,
                    mentorAvatarUrl: vm.mentor?.avatarUrl,
                    onMessage: { dismissReminder() },
                    onDismiss: {
                        DisciplerReminderPolicy.markDismissed(level: levelNumber)
                        dismissReminder()
                    }
                )
                .padding(.horizontal, Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace + Nuru.S.md)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                .task(id: showReminder) {
                    // Auto-dismiss after ~1 minute if untouched — a reminder, not a demand.
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                    guard !Task.isCancelled else { return }
                    dismissReminder()
                }
            }
        }
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
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
            }
            Text("“\(vm.verse.text)”")
                .font(.fraunces(16, .medium)).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(vm.verse.ref)
                .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
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
                        .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
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

    // MARK: - Module trail (cards strung on a gold rail, encouragements woven in,
    // and — once every module is done — the level gate at the end)

    private var moduleTrail: some View {
        let items = vm.trailItems
        let showGate = vm.examAvailable
        let showWaiting = vm.awaitingReview
        return VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                // The rail runs on into the exam gate / waiting node when showing.
                let isLast = idx == items.count - 1 && !showGate && !showWaiting
                switch item {
                case .module(let m): moduleRow(m, isLast: isLast)
                case .encouragement(let e): encouragementRow(e, isLast: isLast)
                case .stats: statsCardRow(isLast: isLast)
                }
            }
            if showWaiting { awaitingRow }
            else if showGate { examGateRow }
        }
    }

    // MARK: - Awaiting-discipler node (exam passed — waiting to be ushered onward)

    private var awaitingRow: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Nuru.goldTint).frame(width: 36, height: 36)
                        .overlay(Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
                    Text("🌿").font(.system(size: 16))
                }
            }
            .frame(width: 36)

            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(spacing: 6) {
                    Icon(.handHeart, size: 12, color: Nuru.goldChipText)
                    Text("AWAITING YOUR DISCIPLER")
                        .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                }
                Text("Level \(vm.levelNumber) complete")
                    .font(.nCardTitle).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You've passed the exam. Awaiting your discipler's blessing to continue to the next level.")
                    .font(.nCardBody).foregroundStyle(Nuru.ink600)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
            .padding(.bottom, Nuru.S.base)
        }
        .fixedSize(horizontal: false, vertical: true)
        .gentleEntrance()
    }

    // MARK: - Encouragement row (a small gold moment strung on the same rail)

    private func encouragementRow(_ e: LevelEncouragement, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Nuru.goldTint).frame(width: 28, height: 28)
                        .overlay(Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
                    if let emoji = e.emoji, !emoji.isEmpty {
                        Text(emoji).font(.system(size: 12))
                    } else {
                        Icon(.sparkles, size: 12, color: Nuru.gold)
                    }
                }
                .padding(.top, 4)
                if !isLast {
                    Rectangle()
                        .fill(Nuru.gold.opacity(0.35))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            EncouragementTrailCard(item: e)
                .padding(.bottom, Nuru.S.base)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Mid-level stats card row (woven in around module 5-6 — see
    // statsCardAfterIndex). A real snapshot of the member's own progress, not
    // an authored moment, so it gets its own node styling (a gold trending-up
    // seal) rather than the sparkle used for encouragements.

    private func statsCardRow(isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Nuru.gold).frame(width: 28, height: 28)
                    Icon(.trendingUp, size: 13, color: .white)
                }
                if !isLast {
                    Rectangle().fill(Nuru.gold.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
                }
            }
            .frame(width: 36)

            MidLevelStatsCard(
                completed: vm.completed, total: vm.moduleCount, pct: vm.pct,
                band: vm.levelScore?.band, streak: vm.streak, mentorName: vm.mentor?.fullName
            )
            .padding(.bottom, Nuru.S.base)
        }
        .fixedSize(horizontal: false, vertical: true)
        .gentleEntrance()
    }

    // MARK: - The level gate (exam CTA — the trail's final node)

    private var examGateRow: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Nuru.gold).frame(width: 36, height: 36)
                    Icon(.award, size: 16, color: .white)
                }
            }
            .frame(width: 36)

            NavigationLink(value: PathwayRoute.exam(vm.levelNumber)) {
                ExamGateCard(levelNumber: vm.levelNumber)
            }
            .buttonStyle(.pressable)
            .simultaneousGesture(TapGesture().onEnded { Haptics.action() })
            .padding(.bottom, Nuru.S.base)
        }
        .fixedSize(horizontal: false, vertical: true)
        .gentleEntrance()
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
                    // The level's exam container opens the exam; every other module
                    // opens its lesson reader.
                    NavigationLink(value: m.isExam ? PathwayRoute.exam(m.levelNumber) : PathwayRoute.module(m.moduleId)) {
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

    // The module NUMBER never leaves the node — your place on the trail stays
    // readable. State lives in the medallion + a small corner seal: gold fill
    // with a navy check-seal when done, muted with a lock-seal when locked,
    // gold-tinted with the gold number for the open/next module.
    private func node(_ m: LevelModule) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(m.completed ? Nuru.gold : (m.locked ? Nuru.mutedBg : Nuru.goldTint))
                    .frame(width: 36, height: 36)
                Text("\(m.moduleSequenceNumber)")
                    .font(.inter(14, .bold))
                    .foregroundStyle(m.completed ? Nuru.navy : (m.locked ? Nuru.faint : Nuru.gold))
            }
            if m.completed {
                ZStack {
                    Circle().fill(Nuru.navy).frame(width: 15, height: 15)
                    Icon(.check, size: 8, color: .white)
                }
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .offset(x: 4, y: -3)
            } else if m.locked {
                ZStack {
                    Circle().fill(Nuru.mutedBg).frame(width: 15, height: 15)
                    Icon(.lock, size: 8, color: Nuru.faint)
                }
                .overlay(Circle().stroke(.white, lineWidth: 1.5))
                .offset(x: 4, y: -3)
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

    // MARK: - Discipler reminder pop-up (within-level, not end-of-level)

    /// Eligible once the member is genuinely mid-level: ≥3 modules done, the
    /// exam gate isn't showing yet, and they're not already awaiting a
    /// discipler's usher (that's the existing end-of-level element — this adds
    /// a WITHIN-level presence, it doesn't replace it).
    private func maybeShowDisciplerReminder() {
        guard vm.completed >= 3, !vm.examAvailable, !vm.awaitingReview else { return }
        guard DisciplerReminderPolicy.shouldShow(level: levelNumber) else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.25) : .spring(response: 0.5, dampingFraction: 0.85)) {
            showReminder = true
        }
    }

    private func dismissReminder() {
        withAnimation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 0.9)) {
            showReminder = false
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
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                Spacer()
                statusBadge
            }
            Text(module.title)
                .font(.nCardTitle).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let summary = module.summary, !summary.isEmpty {
                Text(summary)
                    .font(.nCardBody).foregroundStyle(Nuru.muted).lineLimit(2)
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

// MARK: - Encouragement card (gold-accented moment between module rows)

private struct EncouragementTrailCard: View {
    let item: LevelEncouragement

    /// Kicker per authored kind — splash/cheer/sticker/note/celebration/nudge/verse.
    private var kicker: String {
        switch (item.kind ?? "").lowercased() {
        case "celebration", "cheer": return "CELEBRATE"
        case "nudge":                return "KEEP GOING"
        case "verse":                return "A VERSE FOR YOU"
        case "note":                 return "A NOTE FOR YOU"
        default:                     return "ENCOURAGEMENT"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            if let img = item.imageUrl, !img.isEmpty, let url = URL(string: img) {
                // Color.clear owns the layout size; the fill image lives in an
                // overlay so its oversized "fill" width can never inflate the
                // card column (the radio-screen edge-spill bug family —
                // `.frame(height:)` alone left the width unclamped).
                Color.clear
                    .overlay {
                        CachedAsyncImage(url: url) { p in
                            (p.image ?? Image(systemName: "photo")).resizable().scaledToFill()
                        }
                    }
                    .clipped()
                    .frame(height: 120)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            HStack(spacing: 6) {
                Icon(.sparkles, size: 11, color: Nuru.goldChipText)
                Text(kicker)
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
            }
            if let title = item.title, !title.isEmpty {
                Text(title)
                    .font(.nRowTitle).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let body = item.body, !body.isEmpty {
                Text(body)
                    .font(.nCardBody).foregroundStyle(Nuru.ink600)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let ref = item.scriptureRef, !ref.isEmpty {
                Text(ref)
                    .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }
}

// MARK: - Exam gate card (navy + gold — the trail's ceremonial final door)

private struct ExamGateCard: View {
    let levelNumber: Int

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(spacing: 6) {
                Icon(.award, size: 12, color: Nuru.goldGlow)
                Text("THE LEVEL GATE")
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldGlow)
            }
            Text("Take the Level \(levelNumber) exam")
                .font(.nCardTitle).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Every module is complete — the exam draws from the whole level and opens the way forward.")
                .font(.nCardBody).foregroundStyle(Color.white.opacity(0.65))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Text("Begin the exam").font(.inter(13, .bold)).foregroundStyle(Nuru.navyDeep)
                Icon(.arrowRight, size: 13, color: Nuru.navyDeep)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Nuru.goldGradient, in: Capsule())
            .padding(.top, 4)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Nuru.navy700, Nuru.navyCeremony],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
            .stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
        .shadow(color: Nuru.navyCeremony.opacity(0.35), radius: 12, y: 6)
    }
}

// MARK: - Mid-level stats card (owner spec: "around modules 5-8 you should
// have a card that captures all your stats, beautiful, with imagery, that
// reminds and encourages you"). Navy-gradient + gold accents — same ceremonial
// palette as the level gate — with the member's real, server-provided progress
// (modules done, mastery band, streak) and the same discipler affordance as
// the reminder pop-up. Static: it lives in the trail, not a popup.

private struct MidLevelStatsCard: View {
    let completed: Int
    let total: Int
    let pct: Int
    let band: String?
    let streak: Int
    let mentorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack(spacing: 6) {
                Icon(.trendingUp, size: 12, color: Nuru.goldGlow)
                Text("YOUR JOURNEY SO FAR")
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldGlow)
            }
            Text("Look how far you've come")
                .font(.nCardTitle).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .center, spacing: Nuru.S.base) {
                StatsRing(pct: pct)
                VStack(alignment: .leading, spacing: 8) {
                    statLine("\(completed) of \(total)", "modules complete")
                    if let band, !band.isEmpty { statLine(band, "your mastery so far") }
                    if streak > 0 { statLine("\(streak)-day", "streak") }
                }
            }

            Text("Walk the rest with your discipler\(mentorName.map { " — \($0) is right there with you" } ?? "").")
                .font(.nCardBody).foregroundStyle(Color.white.opacity(0.7))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            NavigationLink(value: AppRoute.discipleshipHub) {
                HStack(spacing: 6) {
                    Icon(.messageCircle, size: 13, color: Nuru.navyDeep)
                    Text("Message your discipler").font(.inter(13, .bold)).foregroundStyle(Nuru.navyDeep)
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
                .background(Nuru.goldGradient, in: Capsule())
            }
            .buttonStyle(.pressable)
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Nuru.navy700, Nuru.navyCeremony],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
            .stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
        .shadow(color: Nuru.navyCeremony.opacity(0.35), radius: 12, y: 6)
    }

    private func statLine(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.inter(15, .bold)).foregroundStyle(.white)
            Text(label).font(.inter(11, .medium)).foregroundStyle(Color.white.opacity(0.55))
        }
    }
}

/// Small gold progress ring on a dark ground (PWProgressRing's palette flipped
/// for the navy card — see PathwayView.swift's hub ring for the light version).
private struct StatsRing: View {
    let pct: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.18), lineWidth: 6)
            Circle().trim(from: 0, to: shown ? CGFloat(max(0, min(100, pct))) / 100 : 0)
                .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.9), value: pct)
            Text("\(pct)%").font(.inter(14, .bold)).foregroundStyle(.white)
                .contentTransition(.numericText())
                .animation(.default, value: pct)
        }
        .frame(width: 60, height: 60)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true }
            else { withAnimation(.spring(response: 0.8, dampingFraction: 0.9).delay(0.15)) { shown = true } }
        }
    }
}

// MARK: - Within-level discipler reminder pop-up (owner spec: "a pop-up
// appears that says work with your discipler, stays about a minute, then
// disappears — and it can pop again later; its work is to REMIND you"). A
// floating card, not a modal — it never blocks the trail underneath.

/// Remind-don't-nag policy: at most once per app session per level (in-memory,
/// resets on relaunch), and never again within 24h of an explicit X dismissal
/// (persisted so the quiet period survives relaunches too).
enum DisciplerReminderPolicy {
    static var shownThisSession = Set<Int>()

    private static func key(_ level: Int) -> String { "nuru.discipler.reminder.dismissedAt.level.\(level)" }

    static func dismissedRecently(level: Int) -> Bool {
        let ts = UserDefaults.standard.double(forKey: key(level))
        guard ts > 0 else { return false }
        return Date().timeIntervalSince1970 - ts < 24 * 3600
    }

    static func markDismissed(level: Int) {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key(level))
    }

    /// True (and marks the session) the first time this level qualifies this
    /// session and isn't in its post-dismissal quiet period.
    static func shouldShow(level: Int) -> Bool {
        guard !shownThisSession.contains(level), !dismissedRecently(level: level) else { return false }
        shownThisSession.insert(level)
        return true
    }
}

private struct DisciplerReminderCard: View {
    let mentorName: String?
    let mentorAvatarUrl: String?
    let onMessage: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            Avatar(url: mentorAvatarUrl, name: mentorName ?? "Your discipler", size: 44)
            VStack(alignment: .leading, spacing: 6) {
                Text("WALK WITH YOUR DISCIPLER")
                    .font(.nCardKicker).kerning(1.2).foregroundStyle(Nuru.goldChipText)
                Text(mentorName.map { "\($0) is walking this with you" } ?? "A discipler is walking this with you")
                    .font(.inter(14.5, .bold)).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("You're making real progress — you don't have to walk it alone.")
                    .font(.nCardBody).foregroundStyle(Nuru.ink600)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    NavigationLink(value: AppRoute.discipleshipHub) {
                        HStack(spacing: 6) {
                            Icon(.messageCircle, size: 13, color: .white)
                            Text("Message").font(.inter(13, .bold)).foregroundStyle(.white)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Nuru.navyDeep, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap(); onMessage() })
                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }
            Button {
                Haptics.tap()
                onDismiss()
            } label: {
                Icon(.x, size: 13, color: Nuru.faint)
                    .frame(width: 26, height: 26)
                    .background(Nuru.mutedBg, in: Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
        .nuruShadow(1.4)
    }
}
