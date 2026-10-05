// Pathway tab — rebuilt line-by-line from the Figma Make source of truth
// (components/LevelsOverview.tsx). Navy header with a gold "Welcome back"
// overline, a serif title + subtitle and a 74px progress ring, three glass stat
// cards, a "Continue your journey" active-level card with a per-level tone strip,
// then the six level cards ("Choose your level"). Exact Figma palette + tracking;
// bound to the real PathwaySummary. Reusable pieces are separate View structs
// (matches the Figma components and keeps this view's generated type small).
import SwiftUI

/// Value-based routes pushed within the Pathway tab.
enum PathwayRoute: Hashable {
    case level(Int)
    case module(String)   // moduleId
    case quiz(String)     // moduleId
    case exam(Int)        // levelNumber — the level gate (§1.9 rule 2)
    case map              // the full levels map ("Map view")
    case walk             // Your Walk — the member's whole journey (Wave 3)
}

// Exact Figma palette (LevelsOverview.tsx) — kept local so this page is 1:1 with
// the design rather than the app's near-equivalents.
private enum PW {
    static let navy      = Color(hex: 0x0A2540)
    static let gold      = Color(hex: 0xC9A227)
    static let bg        = Color(hex: 0xF4F0E8)
    static let ink       = Color(hex: 0x0B0B0C)   // primary heading
    static let ink2      = Color(hex: 0x59667C)   // secondary
    static let ink3      = Color(hex: 0x6F7E93)   // tertiary / locked
    static let goldDeep  = Color(hex: 0xA8861C)   // overlines
    static let goldTint  = Color(hex: 0xFFF4C7)   // completed tile
    static let mutedBg   = Color(hex: 0xEEF1F5)   // locked tile
    static let chevron   = Color(hex: 0xB5BDC9)

    // Per-level gradient tone (from LEVELS[].tone: from → via → to).
    static func tone(_ id: Int) -> [Color] {
        switch id {
        case 1:  return [0x123B62, 0x0A2540, 0xD8B84D].map { Color(hex: $0) }
        case 2:  return [0x0A2540, 0x315F8C, 0xC9A227].map { Color(hex: $0) }
        case 3:  return [0x1C2A44, 0x334155, 0x8B7355].map { Color(hex: $0) }
        case 4:  return [0x0F2B46, 0x1E4E6E, 0x7EA7C7].map { Color(hex: $0) }
        case 5:  return [0x14213D, 0x5C4A22, 0xC9A227].map { Color(hex: $0) }
        default: return [0x081C36, 0x17324F, 0xE7D9A3].map { Color(hex: $0) }
        }
    }

    // Figma subtitles (used only when the backend level carries no theme/description).
    static let subtitle: [Int: String] = [
        1: "God, His Word, prayer & the Church",
        2: "Who God is — His character and heart",
        3: "Grace, repentance, and new life",
        4: "Who you are in Him",
        5: "How Scripture forms faith and life",
        6: "Walking in the Spirit's gifts and power",
    ]

    // PathwayHub additions
    static let goldLight  = Color(hex: 0xE6C068)
    static let navyDeep   = Color(hex: 0x081C36)
    static let surface    = Color(hex: 0xFBF8F1)
    static let border     = Color(hex: 0x0A2540, alpha: 0.08)
    static let badgeEmoji = ["🪨", "🕊️", "🌿", "🔥", "📖", "👑", "⭐", "🏅"]
}

// Small helpers shared by the PathwayHub subviews (mirror the Figma functions).
// (The greeting left Pathway with Cycle 4 — it belongs to Home alone, §8.1.)
private func pwShortName(_ t: String) -> String {
    let w = t.split(separator: " ").first.map(String.init) ?? ""
    guard let f = w.first else { return "" }
    return String(f).uppercased() + w.dropFirst().lowercased()
}

/// The reward the member is working toward — the first not-yet-complete level.
struct PWReward { let name: String; let emoji: String; let remaining: Int; let pct: Int }

private func nextReward(_ s: PathwaySummary) -> PWReward? {
    guard let idx = s.levels.firstIndex(where: { !$0.walked }) else { return nil }
    let l = s.levels[idx]
    // Lessons — the exam is a step of its own, never "a module" (§8.2 #4).
    let remaining = max(l.lessonCount - l.lessonsDone, 0)
    let pct = l.lessonCount > 0 ? min(100, Int((Double(l.lessonsDone) / Double(l.lessonCount) * 100).rounded())) : 0
    return PWReward(name: pwShortName(l.title), emoji: PW.badgeEmoji[idx % PW.badgeEmoji.count], remaining: remaining, pct: pct)
}

@MainActor
final class PathwayViewModel: ObservableObject {
    @Published var summary: PathwaySummary?
    @Published var modulesByLevel: [Int: [LevelModule]] = [:]   // real module trails, cached per level
    @Published var loading = true
    /// Why the pathway didn't load — spoken through the one state language
    /// (NuruStateCopy), never as the server's raw text.
    @Published var failure: Error?

    func load() async {
        loading = true; failure = nil
        do {
            summary = try await MemberAPI.pathway()
        } catch {
            summary = nil
            failure = error
        }
        // The current level's trail is re-read on every load (pull-to-refresh
        // included): the journey's next step is read from it.
        if let current = summary?.currentLevel { await fetchModules(current, force: true) }
        loading = false
    }

    /// Lazily fetch (and cache) a level's real module trail — driven by taps on
    /// the journey rail so each level's list is the server's, not a placeholder.
    func fetchModules(_ levelNumber: Int, force: Bool = false) async {
        if !force, modulesByLevel[levelNumber] != nil { return }
        modulesByLevel[levelNumber] = (try? await MemberAPI.levelModules(levelNumber)) ?? []
    }

    /// The member's journey (EXPERIENCE.md §3) — the same derivation Home reads.
    var journey: Journey? {
        Journey.derive(summary, trail: summary.flatMap { modulesByLevel[$0.currentLevel] })
    }

    private func active(in p: PathwaySummary?) -> PathwayLevel? {
        guard let p else { return nil }
        return p.levels.first { $0.status == .active }
            ?? p.levels.first { $0.levelNumber == p.currentLevel }
            ?? p.levels.first
    }
    var activeLevel: PathwayLevel? { active(in: summary) }

    /// The module to resume in a level (status-driven from the real trail) —
    /// nil once every module is done: a finished level has nothing to resume,
    /// and "Continue" must never re-open a finished module — nor an exam that
    /// can't be taken yet (EXPERIENCE.md §7.2 #1: it would only answer 422).
    func resumeModule(in levelNumber: Int) -> LevelModule? {
        let mods = (modulesByLevel[levelNumber] ?? []).filter { !$0.examOpensSoon }
        return mods.first { $0.status == .next } ?? mods.first { !$0.completed }
    }

    /// The level (if any) the member just passed and is now waiting to be ushered
    /// past — surfaced by the pathway API's `awaitingReview` flag. Drives the
    /// "awaiting your discipler" banner; the next level stays locked while set.
    var awaitingLevel: PathwayLevel? { summary?.levels.first { $0.isAwaitingReview } }

    var levelsDone: Int { summary?.levels.filter(\.walked).count ?? 0 }
    // Lessons, every count the member reads (§8.2 #4): the exam is a step.
    var doneModules: Int { summary?.levels.reduce(0) { $0 + min($1.lessonsDone, $1.lessonCount) } ?? 0 }
    var totalModules: Int { summary?.levels.reduce(0) { $0 + $1.lessonCount } ?? 0 }
    var levelCount: Int { summary?.levels.count ?? 6 }
    // (The old overallPct — modules done ÷ every PUBLISHED module — is gone: with
    // Levels 2–6 unpublished it read Level 1's twenty as 100% and commissioned
    // the member. The ring and the summit read the journey, counted in levels.)
    func pct(_ l: PathwayLevel) -> Int { l.lessonCount > 0 ? min(100, Int(round(Double(l.lessonsDone) / Double(l.lessonCount) * 100))) : 0 }
}

struct PathwayView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @StateObject private var vm = PathwayViewModel()
    /// Whether a discipler is paired (GET /growth/mentor) — the Discipleship
    /// Hub row shows only then (Cycle 4, B1).
    @ObservedObject private var disciplers = DisciplerStore.shared
    @State private var path = NavigationPath()
    @State private var selectedLevelNumber: Int?

    /// The level whose module list is shown inline (defaults to the active level).
    private var selectedLevel: PathwayLevel? {
        guard let s = vm.summary else { return nil }
        let target = selectedLevelNumber ?? vm.activeLevel?.levelNumber
        return s.levels.first { $0.levelNumber == target } ?? vm.activeLevel
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if vm.loading && vm.summary == nil {
                        PathwaySkeleton()
                    } else if let s = vm.summary, !s.levels.isEmpty {
                        content(s)
                    } else {
                        // Includes a decoded-but-empty levels array — rendering
                        // "Level 1 of 0" with dead CTAs is worse than retrying.
                        errorState.padding(.horizontal, 20).padding(.top, 120)
                    }
                }
                .scrollsToTopOnReselect(.pathway)   // a re-tap at the root returns to the top (B10)
                // Full width whatever the state: a narrow error column left the
                // ScrollView (and its cream) hugging it, with white bands beside.
                .frame(maxWidth: .infinity)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .ignoresSafeArea(edges: .top)
            .background(PW.bg.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .nuruEdgeSwipeBack()   // back by the edge swipe on every pushed page (B9)
            .navigationDestination(for: PathwayRoute.self) { r in
                switch r {
                case .level(let n): LevelDetailView(levelNumber: n)
                case .module(let id): ModuleView(moduleId: id)
                case .quiz(let id):
                    QuizView(moduleId: id, onPassAdvance: { nextId in
                        // Pop the quiz; open the server-unlocked next module (if any).
                        if !path.isEmpty { path.removeLast() }
                        if let nextId { path.append(PathwayRoute.module(nextId)) }
                    })
                case .exam(let n):
                    // §1.9 (new): passing the exam NO LONGER auto-advances. The
                    // member now waits to be ushered by a discipler — so Continue
                    // just refreshes the (authoritative) pathway and pops back to the
                    // hub, where the level shows its "awaiting your discipler" state
                    // and the next level stays LOCKED until awaitingReview clears.
                    LevelExamView(levelNumber: n, onPassContinue: {
                        Task { @MainActor in
                            await vm.load()   // pull the fresh awaiting-review / status
                            if !path.isEmpty { path.removeLast() }   // pop the exam → the hub
                        }
                    })
                case .map: LevelsMapView(vm: vm) { path.append(PathwayRoute.level($0)) }
                case .walk: YourWalkView()
                }
            }
            // The Pathway stack registers only PathwayRoute; the Discipleship Hub
            // is an AppRoute, so register it here too (the tab has no .nuruDestinations()),
            // with the bell's inbox and the announcement a row of it opens.
            .navigationDestination(for: AppRoute.self) { r in
                switch r {
                case .discipleshipHub: DiscipleshipHubView()
                case .notifications: NotificationsView()
                case .announcement(let id): AnnouncementDetailView(announcementId: id)
                case .announcementsList: AnnouncementsAllView()
                default: EmptyView()
                }
            }
        }
        .task { if vm.summary == nil { await vm.load() } }
        .task(id: selectedLevel?.levelNumber) {
            if let n = selectedLevel?.levelNumber { await vm.fetchModules(n) }
        }
        // Cross-tab deep link (Home nudges, notifications): land exactly on the
        // module/level inside THIS tab, with the Pathway hub as the back stop.
        .onReceive(tabs.$pathwayLink) { link in
            guard let link else { return }
            path = NavigationPath()
            path.append(link)
            DispatchQueue.main.async { tabs.pathwayLink = nil }
        }
        .popsToRoot(on: .pathway, path: $path)   // a re-tap returns to the hub (§7.4 #17)
    }

    /// Routes a module id to its screen: the level's exam container opens the
    /// level exam; every other module opens the lesson reader. Keeps the "resume"
    /// affordances (hero card, milestones) correct now that the exam is the last
    /// unlocked step in a finished trail.
    private func openModuleId(_ id: String) {
        if let m = vm.modulesByLevel.values.flatMap({ $0 }).first(where: { $0.moduleId == id }), m.isExam {
            path.append(PathwayRoute.exam(m.levelNumber))
        } else {
            path.append(PathwayRoute.module(id))
        }
    }

    // MARK: content — the PathwayHub layout (hero → journey rail → level modules → milestones → summit)

    private func content(_ s: PathwaySummary) -> some View {
        let active = vm.activeLevel
        let journey = vm.journey
        return VStack(spacing: 0) {
            PathwayHubHeader(
                vm: vm, active: active, journey: journey,
                open: { d in
                    if case .module(let id) = d { openModuleId(id) } else { path.append(d.route) }
                })

            VStack(alignment: .leading, spacing: 24) {
                // Awaiting the usher (the exam passed; the next level stays LOCKED
                // until awaitingReview clears server-side) is the hero's own story
                // — "Level N+1 is next · Your leader will open Level N+1" (§3). A
                // second card said it again as "Awaiting your discipler's
                // blessing" (E2: one card, one word for who opens the level).

                // Studying together, apart (Wave 2): who from your cell opened
                // a lesson this week. Renders nothing when nobody has.
                CellPresenceLine().gentleEntrance()

                PathwayJourneyRail(
                    levels: s.levels, current: journey?.levelNumber,
                    selected: selectedLevel?.levelNumber ?? -1,
                    onSelect: { n in
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.2)) { selectedLevelNumber = n }
                    },
                    onMap: { path.append(PathwayRoute.map) })
                    .gentleEntrance()

                if let sel = selectedLevel {
                    PathwaySelectedModules(
                        level: sel, nextPreparing: UsherWords.nextPreparing(after: sel.levelNumber, in: s),
                        modules: vm.modulesByLevel[sel.levelNumber] ?? [],
                        loading: vm.modulesByLevel[sel.levelNumber] == nil,
                        resume: vm.resumeModule(in: sel.levelNumber),
                        // The fold and the exam row are the journey's call, for
                        // the member's own level only (§6.3).
                        journey: journey,
                        openModule: { openModuleId($0) },
                        openExam: { path.append(PathwayRoute.exam($0)) })
                        .gentleEntrance(delay: 0.05)
                }

                // Discipleship Hub link — a warm door into the relationship home
                // (discipler, feedback, meeting notes), only for a discipler the
                // server names (Cycle 4, B1).
                if disciplers.hasDiscipler {
                    PathwayDisciplershipRow { path.append(AppRoute.discipleshipHub) }
                        .gentleEntrance(delay: 0.08)
                }

                PathwayWalkRow { path.append(PathwayRoute.walk) }
                    .gentleEntrance(delay: 0.09)

                PathwayMilestones(
                    levels: s.levels, reward: nextReward(s),
                    openResume: {
                        if let a = active, let m = vm.resumeModule(in: a.levelNumber) {
                            openModuleId(m.moduleId)
                        }
                    })
                    .gentleEntrance(delay: 0.1)

                PathwaySummitCard(reached: journey?.summitReached ?? false, levels: s.levels, firstName: firstName)
                    .gentleEntrance(delay: 0.15)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
        }
    }

    /// The pathway didn't come — in the one state language (§4). A summary
    /// that arrived with no levels is the server's fault, not the member's.
    private var errorState: some View {
        NuruStateView(state: .failed(vm.failure.map { NuruStateCopy.failure($0) } ?? .serverSide),
                      retry: { Task { await vm.load() } })
    }

    private var firstName: String { (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend" }
}

// MARK: - PathwayHub · cinematic hero (your current level)

private struct PathwayHubHeader: View {
    @ObservedObject var vm: PathwayViewModel
    let active: PathwayLevel?
    /// The member's journey — the hero card's next step and the ring (§3).
    let journey: Journey?
    let open: (Journey.Destination) -> Void

    private var idx: Int {
        guard let a = active, let levels = vm.summary?.levels else { return 0 }
        return levels.firstIndex { $0.levelNumber == a.levelNumber } ?? 0
    }
    private var activePct: Int { active.map { vm.pct($0) } ?? 0 }
    /// Modules still to walk — said only while the member is walking them
    /// (an exam row left in the trail is the exam, not "1 module to go").
    private var remaining: Int {
        guard journey?.stage == .learning else { return 0 }
        return active.map { max($0.lessonCount - $0.lessonsDone, 0) } ?? 0
    }

    var body: some View {
        // Fresh Figma PathwayHub: LIGHT cream hero (navy text) with a navy Continue CTA.
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(PW.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)

            VStack(alignment: .leading, spacing: 0) {
                topBar
                // One header (EXPERIENCE.md §8.1 rule 2): PATHWAY (the top
                // bar's kicker) · the level · one line of where it stands. The
                // greeting belongs to Home alone.
                NuruHeaderText(title: active?.title ?? "Your pathway",
                               line: PathwayTrail.headerLine(active, position: idx + 1, of: vm.levelCount))
                    .padding(.top, 12)
                // The level's bar once a lesson is done — not an empty "0/10"
                // on a first day (§9.2 #4; the line above says "10 modules").
                if (active?.lessonsDone ?? 0) > 0 {
                HStack(spacing: 8) {
                    PWBar(pct: activePct, height: 6,
                          fill: .linearGradient(colors: [PW.gold, PW.goldLight], startPoint: .leading, endPoint: .trailing),
                          track: PW.navy.opacity(0.10))
                    Text("\(active.map { min($0.lessonsDone, $0.lessonCount) } ?? 0)/\(active?.lessonCount ?? 0)")
                        .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x59667C))
                        .contentTransition(.numericText())
                        .animation(.default, value: active?.lessonsDone)
                }.padding(.top, 16)
                }
                if remaining > 0 {
                    HStack(spacing: 6) {
                        Icon(.sparkles, size: 14, color: Color(hex: 0x9A7A2A))
                        Text(remaining == 1 ? "Just 1 module left to level up 🎉" : "Only \(remaining) modules to complete this level")
                            .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    }.padding(.top, 8)
                }
                continueCard.padding(.top, 16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.top, NuruSafeArea.top + 8).padding(.bottom, 20)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))
        .overlay(alignment: .bottom) { Rectangle().fill(PW.border).frame(height: 1) }
    }

    private var topBar: some View {
        HStack {
            // (The streak is named on Home's rhythm card and Plans, not here
            // — one streak, §9.2 #3.)
            Text("PATHWAY").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.eyebrow)
            Spacer()
            HStack(spacing: 8) {
                // The one bell (§7.2 #4) — it was decorative here, opening
                // nothing under a painted-on dot.
                NuruBell()
                // Shown once there is progress to show — never a "0%" ring on
                // a first day (§9.2 #4).
                if let pct = journey?.progressPercent, pct > 0 { PWHeaderRing(pct: pct) }
            }
        }
    }

    // Navy CTA that pops on the light header (fresh Figma) — the journey's
    // next step: the module to continue, the exam to take, the level a leader
    // will open. A step with no action (the exam still in review) just says so.
    private var continueCard: some View {
        Button { if let d = journey?.destination { Haptics.tap(); open(d) } } label: {
            HStack(spacing: 12) {
                Icon(journey?.stage.glyph ?? .playCircle, size: 22, color: PW.navy)
                    .frame(width: 44, height: 44)
                    .background(PW.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text((journey?.kicker ?? "Your pathway").uppercased())
                        .font(.inter(11, .bold)).kerning(1.28).foregroundStyle(PW.goldLight).lineLimit(1)
                    Text(journey?.title ?? "Your pathway").font(.inter(14, .semibold)).foregroundStyle(.white).lineLimit(2)
                    if let line = journey?.line {
                        Text(line).font(.inter(11)).foregroundStyle(.white.opacity(0.7))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let label = journey?.actionLabel {
                        HStack(spacing: 4) {
                            Text(label).font(.inter(11, .bold))
                            Icon(.chevronRight, size: 14, color: PW.navy)
                        }
                        .foregroundStyle(PW.navy)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(PW.gold, in: Capsule())
                        .padding(.top, 8)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(LinearGradient(colors: [PW.navy, PW.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color(hex: 0x0A1628).opacity(0.5), radius: 17, y: 10)
        }
        .buttonStyle(.pressable)
        .disabled(journey?.destination == nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint(journey?.actionLabel ?? "")
    }
}

extension Journey.Stage {
    /// The step's glyph once it is no longer a lesson to continue (each surface
    /// keeps its own play glyph for that): the exam, its wait, the person who
    /// opens the next level, the summit. Home's continue card wears the same.
    var glyph: Lucide? {
        switch self {
        case .learning: return nil
        case .examReady: return .award
        case .examSoon: return .clock
        case .awaitingUsher: return .heartHandshake
        case .finished: return .sparkles
        }
    }
}

private struct PWHeaderRing: View {
    let pct: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        ZStack {
            Circle().stroke(PW.navy.opacity(0.12), lineWidth: 3)
            Circle().trim(from: 0, to: shown ? CGFloat(max(0, min(100, pct))) / 100 : 0)
                .stroke(PW.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.9), value: pct)
            Text("\(pct)%").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
                .contentTransition(.numericText())
                .animation(.default, value: pct)
        }
        .frame(width: 40, height: 40)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true }
            else { withAnimation(.spring(response: 0.8, dampingFraction: 0.9).delay(0.1)) { shown = true } }
        }
    }
}

// MARK: - PathwayHub · Discipleship Hub link (walk with your discipler)

/// A single navy-avatar row that opens the student's Discipleship Hub — the fuller
/// home for the discipleship relationship. Purely a doorway (the Hub loads its own
/// data); styled to sit calmly among the pathway cards.
private struct PathwayDisciplershipRow: View {
    let onTap: () -> Void
    var body: some View {
        Button { Haptics.tap(); onTap() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [PW.gold, Color(hex: 0xA87F29)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Icon(.heartHandshake, size: 22, color: PW.navy)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("WALK WITH YOUR DISCIPLER").font(.inter(11, .bold)).kerning(1.28).foregroundStyle(PW.goldDeep)
                    Text("Your Discipleship Hub").font(.inter(14, .semibold)).foregroundStyle(PW.navy).lineLimit(1)
                    Text("Message, feedback & meeting notes").font(.inter(11)).foregroundStyle(PW.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: PW.chevron)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PW.border, lineWidth: 1))
            .shadow(color: PW.navy.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens your Discipleship Hub.")
    }
}

private struct PathwayWalkRow: View {
    let onTap: () -> Void
    var body: some View {
        Button { Haptics.tap(); onTap() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(LinearGradient(colors: [PW.navy, Color(hex: 0x1B3A5C)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Icon(.flag, size: 22, color: PW.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("EVERY STEP, REMEMBERED").font(.inter(11, .bold)).kerning(1.28).foregroundStyle(PW.goldDeep)
                    Text("Your Walk").font(.inter(14, .semibold)).foregroundStyle(PW.navy).lineLimit(1)
                    Text("Your whole journey on one gold thread").font(.inter(11)).foregroundStyle(PW.ink2).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: PW.chevron)
            }
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PW.border, lineWidth: 1))
            .shadow(color: PW.navy.opacity(0.05), radius: 8, y: 3)
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens Your Walk, a timeline of your whole journey.")
    }
}

// MARK: - PathwayHub · journey rail

private struct PathwayJourneyRail: View {
    let levels: [PathwayLevel]
    /// The member's own level (the journey's) — wears "▾ You" whatever its
    /// status: still walking it, every module done, or its exam passed.
    let current: Int?
    let selected: Int
    let onSelect: (Int) -> Void
    let onMap: () -> Void

    private var currentIndex: Int? {
        if let current, let i = levels.firstIndex(where: { $0.levelNumber == current }) { return i }
        return levels.firstIndex { $0.status == .active }
    }

    /// The level right after the member's — "up next" wears a gold ring and
    /// its own "▾ Next" marker, but only while it is still locked (an
    /// awaiting-review hand-off leaves it locked too, which is exactly when
    /// the member most wants to see where the thread goes).
    private var upNextIndex: Int? {
        guard let a = currentIndex else { return nil }
        let i = a + 1
        return i < levels.count && levels[i].status == .locked ? i : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("THE JOURNEY · \(levels.count) LEVELS").font(.inter(11, .bold)).kerning(1.62).foregroundStyle(PW.goldDeep)
                Spacer()
                Button { Haptics.tap(); onMap() } label: {
                    Text("Map view").font(.inter(11, .bold)).foregroundStyle(PW.gold)
                        .padding(.vertical, 10).padding(.leading, 16)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.vertical, -10)   // hit area grows; layout doesn't move
            }.padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { i, lvl in
                        PWJourneyNode(level: lvl, number: i + 1, selected: lvl.levelNumber == selected,
                                      isCurrent: i == currentIndex,
                                      upNext: i == upNextIndex) { onSelect(lvl.levelNumber) }
                        if i < levels.count - 1 {
                            // Connectors ahead of the member read at 0.28 — 0.12
                            // vanished into the cream (locked-rail pass, 2026-09).
                            Capsule().fill(lvl.walked ? PW.gold : PW.navy.opacity(0.28))
                                .frame(width: 28, height: 3).padding(.top, 40)
                        }
                    }
                }
                .padding(.horizontal, 2)
            }
        }
    }
}

private struct PWJourneyNode: View {
    let level: PathwayLevel
    let number: Int
    let selected: Bool
    /// The member's own level — "▾ You" and the navy ring.
    var isCurrent: Bool = false
    /// The locked level right after the member's — gold ring + "▾ Next".
    var upNext: Bool = false
    let onTap: () -> Void
    /// Walked: ushered past, or its exam passed (awaiting the usher) — never
    /// shown locked (an awaiting level used to decode as locked).
    private var done: Bool { level.walked }
    private var active: Bool { isCurrent }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(active ? "▾ You" : (upNext ? "▾ Next" : " ")).font(.inter(11, .bold)).kerning(0.7)
                    .foregroundStyle(active ? PW.gold : (upNext ? PW.gold : Color.clear)).frame(height: 10)
                // The level NUMBER never leaves the circle — completion becomes a
                // corner check-seal; locked levels keep their number with a lock-seal.
                // Locked = cream surface + navy ring (was flat mutedBg with ink3
                // numerals — invisible on the cream page); up-next rings gold.
                ZStack(alignment: .topTrailing) {
                    ZStack {
                        Circle()
                            .fill(done || active
                                  ? AnyShapeStyle(LinearGradient(colors: [PW.gold, Color(hex: 0xA87F29)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(PW.surface))
                            .frame(width: 48, height: 48)
                            .overlay {
                                if active {
                                    Circle().stroke(PW.navy, lineWidth: 2)
                                } else if !done {
                                    Circle().stroke(upNext ? PW.gold : PW.navy.opacity(0.28), lineWidth: upNext ? 2 : 1.5)
                                }
                            }
                        Text("\(number)").font(.inter(15, .bold))
                            .foregroundStyle(done || active ? PW.navy : PW.navy.opacity(0.75))
                    }
                    if done {
                        ZStack {
                            Circle().fill(PW.navy).frame(width: 16, height: 16)
                            Icon(.check, size: 14, color: .white)
                        }
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 3, y: -2)
                    } else if !active {
                        ZStack {
                            Circle().fill(PW.goldTint).frame(width: 16, height: 16)
                            Icon(.lock, size: 14, color: PW.goldDeep)
                        }
                        .overlay(Circle().stroke(.white, lineWidth: 1.5))
                        .offset(x: 3, y: -2)
                    }
                }
                .overlay { if selected { Circle().stroke(PW.gold, lineWidth: 2).frame(width: 54, height: 54) } }
                Text(pwShortName(level.title))
                    .font(.inter(11, active ? .bold : .medium))
                    .foregroundStyle(active ? PW.navy : (upNext ? PW.goldDeep : PW.ink2))
                    .lineLimit(1)
            }
            .frame(width: 68)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - PathwayHub · the trail's rules (EXPERIENCE.md §6.3)

/// Pure, so the tests pin them; Android's PathwayTrail, the same rules.
enum PathwayTrail {
    /// The member's own level, once they are past learning it (every module
    /// done — the exam ready, or soon, or passed): its list folds into one
    /// row. Any other level's list, and a level still being learned, stays open.
    static func folds(_ journey: Journey?, levelNumber: Int, modules: [LevelModule]) -> Bool {
        guard let j = journey else { return false }
        return j.stage != .learning && j.levelNumber == levelNumber && !modules.isEmpty
    }

    /// The Pathway header's one line (§8.1 rule 2, §8.2 #1): "Level 1 of 6 ·
    /// 20 of 20 modules" — where the level sits on the road, then its lessons
    /// (the exam is its own step, §8.2 #4). A level with nothing published yet
    /// says so in the journey's words rather than "0 of 0 modules".
    static func headerLine(_ level: PathwayLevel?, position: Int, of count: Int) -> String {
        let place = "Level \(position) of \(count)"
        guard let level else { return place }
        guard level.lessonCount > 0 else { return place + " · Modules open soon" }
        // Nothing done yet: what lies ahead, never "0 of 10" (§9.2 #4).
        let done = min(level.lessonsDone, level.lessonCount)
        return place + (done == 0 ? " · \(level.lessonCount) modules" : " · \(done) of \(level.lessonCount) modules")
    }

    /// The folded row's words: "20 of 20 modules done · Show" — the level's
    /// lessons, its exam being a step, not a module — and "· Hide" once open.
    static func foldLine(_ modules: [LevelModule], expanded: Bool) -> String {
        let lessons = modules.filter { !$0.isExam }
        let done = lessons.filter { $0.completed || $0.status == .completed }.count
        return "\(done) of \(lessons.count) modules done · \(expanded ? "Hide" : "Show")"
    }

    /// The hero shows the exam step — the journey at its exam on this level —
    /// so the trail's own exam row is not shown again (nor offered by its
    /// "Continue →").
    static func examRowHidden(_ journey: Journey?, levelNumber: Int) -> Bool {
        guard let j = journey else { return false }
        return j.stage == .examReady && j.levelNumber == levelNumber
    }
}

// MARK: - PathwayHub · selected level's modules (inline, real trail)

private struct PathwaySelectedModules: View {
    let level: PathwayLevel
    /// The level after this one has no lessons yet (§9.2 #7).
    var nextPreparing: Bool = false
    let modules: [LevelModule]
    let loading: Bool
    let resume: LevelModule?
    /// The member's journey (§3) — whether this level's list folds, and
    /// whether the hero above already shows its exam.
    let journey: Journey?
    let openModule: (String) -> Void
    let openExam: (Int) -> Void
    /// The folded list, opened — per level, closed again on another level.
    @State private var expanded = false

    /// Once the member is past learning their own level (the exam ready, or
    /// soon, or passed), its list folds into one row that expands (§6.3).
    private var folds: Bool { PathwayTrail.folds(journey, levelNumber: level.levelNumber, modules: modules) }
    /// The hero shows the exam step — the trail's own exam row (prod's
    /// exit-exam module) is not shown again. The gate row that used to stand
    /// at the foot of a fully-walked trail only ever repeated the hero, and is
    /// gone. The server remains the eligibility authority either way.
    private var examHidden: Bool { PathwayTrail.examRowHidden(journey, levelNumber: level.levelNumber) }
    private var awaitingReview: Bool { level.isAwaitingReview }
    /// "Continue →" goes where the list's open row goes — never to an exam
    /// the hero already offers.
    private var resumeShown: LevelModule? { resume.flatMap { examHidden && $0.isExam ? nil : $0 } }

    // Progression order — completed, then the one in progress, then locked (each
    // by sequence). Identical to raw sequence for a clean curriculum; for real
    // data it keeps finished modules from being buried below locked ones.
    private var ordered: [LevelModule] {
        func rank(_ m: LevelModule) -> Int { m.status == .completed ? 0 : m.status == .next ? 1 : 2 }
        return modules.filter { !(examHidden && $0.isExam) }.sorted { a, b in
            rank(a) != rank(b) ? rank(a) < rank(b) : a.moduleSequenceNumber < b.moduleSequenceNumber
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title.uppercased()).font(.inter(11, .bold)).kerning(1.62).foregroundStyle(PW.goldDeep).lineLimit(1)
                    Text("\(min(level.lessonsDone, level.lessonCount)) of \(level.lessonCount) done").font(.inter(11)).foregroundStyle(PW.ink2)
                }
                Spacer()
                if let r = resumeShown {
                    Button { Haptics.tap(); openModule(r.moduleId) } label: {
                        Text("Continue →").font(.inter(11, .bold)).foregroundStyle(PW.gold)
                            .padding(.vertical, 10).padding(.leading, 16)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, -10)   // hit area grows; layout doesn't move
                }
            }.padding(.horizontal, 4)
            VStack(spacing: 0) {
                if loading {
                    skeletonRows
                } else if ordered.isEmpty {
                    Text("Modules open as you progress.").font(.nCardBody).foregroundStyle(PW.ink3)
                        .frame(maxWidth: .infinity).padding(.vertical, 26)
                } else {
                    if folds { PWFoldRow(line: PathwayTrail.foldLine(modules, expanded: expanded), expanded: expanded) {
                        withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
                    } }
                    if !folds || expanded {
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { i, m in
                            PWModuleRow(module: m, last: (i == ordered.count - 1) && !awaitingReview) {
                                // An exam that can't be taken yet opens nothing (§7.2 #1).
                                guard m.status != .locked, !m.examOpensSoon else { return }
                                if m.isExam { openExam(level.levelNumber) } else { openModule(m.moduleId) }
                            }
                            // Fresh Figma: after the first 4 modules — a moment to surrender to His Word.
                            if i == 3 && ordered.count > 4 { PWSurrenderFigure() }
                        }
                        // Exam passed → waiting to be ushered by a discipler (§1.9).
                        if awaitingReview { PWAwaitingRow(levelNumber: level.levelNumber, nextPreparing: nextPreparing) }
                    }
                }
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PW.border, lineWidth: 1))
        }
        .onChange(of: level.levelNumber) { _, _ in expanded = false }
    }

    /// Shimmering placeholder rows while a level's real trail is fetched.
    private var skeletonRows: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { i in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(PW.mutedBg).frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(PW.mutedBg).frame(width: 150, height: 10)
                        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(PW.mutedBg).frame(width: 72, height: 8)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .overlay(alignment: .bottom) { if i < 2 { Rectangle().fill(PW.border).frame(height: 1) } }
            }
        }
        .nuruShimmer()
    }
}

private struct PWModuleRow: View {
    let module: LevelModule
    let last: Bool
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakes = 0
    @State private var lockHint = false
    private var done: Bool { module.status == .completed }
    /// The exam row is open but its exam has no questions yet: it says
    /// "opens soon", wears no lock and no "Start exam", and is not a link
    /// (EXPERIENCE.md §7.2 #1 — the server would answer 422).
    private var opensSoon: Bool { module.examOpensSoon }
    private var active: Bool { module.status == .next && !opensSoon }
    private var locked: Bool { module.status == .locked }
    private var isExam: Bool { module.isExam }

    /// Caption under the title — the exam row speaks in exam language ("locked
    /// until you finish the modules", "ready — tap to begin", "passed").
    private var caption: String {
        // The exam's row is titled "Level N exam" (ExamWords, §9.1 rule 1) —
        // its line doesn't name it again. Android's words.
        if isExam {
            return done ? "Passed"
                 : opensSoon ? "Opens soon"
                 : active ? "Ready — tap to begin"
                 : "Finish every module to unlock it"
        }
        return done ? "Completed"
             : active ? ModuleRowWords.openCaption(progress: module.progress)
             : lockHint ? "Finish the previous module to unlock" : "Locked"
    }

    var body: some View {
        if opensSoon {
            rowLabel.accessibilityElement(children: .combine)
        } else {
            Button(action: handleTap) { rowLabel }
                .buttonStyle(.pressable)
                .modifier(PWLockedShake(animatableData: CGFloat(shakes)))
                .accessibilityHint(locked ? "Locked. Finish the previous module to unlock." : "")
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 12) {
            // The module NUMBER stays put; completion/locks move to a corner
            // seal. The exam tile keeps its award identity.
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(done ? AnyShapeStyle(PW.gold.opacity(0.13))
                              : active ? AnyShapeStyle(LinearGradient(colors: [PW.gold, Color(hex: 0xA87F29)], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : isExam ? AnyShapeStyle(PW.gold.opacity(0.10))
                              : AnyShapeStyle(PW.mutedBg))
                        .frame(width: 32, height: 32)
                    if isExam { Icon(.award, size: 14, color: done || active ? PW.goldDeep : PW.goldDeep) }
                    else {
                        Text("\(module.moduleSequenceNumber)")
                            .font(.inter(13, .bold))
                            .foregroundStyle(done ? PW.goldDeep : active ? PW.navy : PW.ink3)
                    }
                }
                if done {
                    ZStack {
                        Circle().fill(PW.navy).frame(width: 13, height: 13)
                        Icon(.check, size: 14, color: .white)
                    }
                    .overlay(Circle().stroke(.white, lineWidth: 1.2))
                    .offset(x: 4, y: -3)
                } else if !active && !done && !opensSoon {
                    ZStack {
                        Circle().fill(PW.mutedBg).frame(width: 13, height: 13)
                        Icon(.lock, size: 14, color: PW.ink3)
                    }
                    .overlay(Circle().stroke(.white, lineWidth: 1.2))
                    .offset(x: 4, y: -3)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                // Locked titles stay legible ink (only the caption goes faint) —
                // #8B95A5-on-white washed the whole card out on device.
                Text(ExamWords.rowTitle(module)).font(.inter(13, (active || isExam) ? .bold : .medium))
                    .foregroundStyle(locked && !isExam ? PW.ink2 : PW.navy).lineLimit(1)
                Text(caption)
                    .font(.inter(11, (active || isExam) ? .bold : .medium))
                    .foregroundStyle(active || (isExam && !done) ? PW.goldDeep : PW.ink3)
            }
            Spacer(minLength: 0)
            if active {
                Text(isExam ? "Start exam" : ModuleRowWords.openAction(progress: module.progress))
                    .font(.inter(11, .bold)).foregroundStyle(PW.gold)
                    .padding(.horizontal, 10).padding(.vertical, 5).background(PW.navy, in: Capsule())
            } else if done {
                Icon(.chevronRight, size: 14, color: Color(hex: 0xCBD5E1))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(active ? PW.gold.opacity(0.05) : isExam ? PW.gold.opacity(0.03) : Color.clear)
        .overlay(alignment: .bottom) { if !last { Rectangle().fill(PW.border).frame(height: 1) } }
    }

    /// Locked rows stay locked (server-authoritative) — a tap just answers with a
    /// gentle refusal shake and a hint of what unlocks it.
    private func handleTap() {
        guard locked else { Haptics.tap(); onTap(); return }
        Haptics.error()
        if !reduceMotion { withAnimation(.linear(duration: 0.35)) { shakes += 1 } }
        guard !lockHint else { return }
        withAnimation(.easeInOut(duration: 0.2)) { lockHint = true }
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { lockHint = false }
        }
    }
}

/// A finished level's trail, folded (§6.3): "20 of 20 modules done · Show" —
/// a tap opens the list, "· Hide" folds it again. Android's FoldedTrailRow.
private struct PWFoldRow: View {
    let line: String
    let expanded: Bool
    let onTap: () -> Void

    var body: some View {
        Button { Haptics.tap(); onTap() } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(PW.gold.opacity(0.13))
                        .frame(width: 32, height: 32)
                    Icon(.check, size: 14, color: PW.goldDeep)
                }
                Text(line).font(.inter(13, .semibold)).foregroundStyle(PW.navy).lineLimit(1)
                Spacer(minLength: 0)
                Icon(expanded ? .chevronUp : .chevronDown, size: 14, color: PW.ink3)
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) { if expanded { Rectangle().fill(PW.border).frame(height: 1) } }
        }
        .buttonStyle(.pressable)
        .accessibilityHint(expanded ? "Folds the finished modules away." : "Shows the finished modules.")
    }
}

/// The waiting node at the foot of a fully-passed level — the exam is done and the
/// member is awaiting a discipler's usher (§1.9). Not tappable; purely reflects the
/// awaitingReview flag — shown with the level's list (inside the fold, once opened).
private struct PWAwaitingRow: View {
    let levelNumber: Int
    var nextPreparing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(PW.gold.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PW.gold.opacity(0.4), lineWidth: 1))
                    .frame(width: 32, height: 32)
                Icon(.flag, size: 14, color: PW.goldDeep)   // a glyph, not a colour emoji (§8.1 rule 7)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Level \(levelNumber) complete")
                    .font(.inter(13, .bold)).foregroundStyle(PW.navy).lineLimit(1)
                Text(UsherWords.line(passed: levelNumber, nextPreparing: nextPreparing))
                    .font(.inter(11, .semibold)).foregroundStyle(PW.goldDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(PW.gold.opacity(0.08))
        .overlay(alignment: .top) { Rectangle().fill(PW.gold.opacity(0.35)).frame(height: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Level \(levelNumber) complete. \(UsherWords.line(passed: levelNumber, nextPreparing: nextPreparing))")
    }
}

/// Refusal shake for locked content — three quick sways, driven by bumping an
/// integer trigger inside `withAnimation` (callers skip it under Reduce Motion).
struct PWLockedShake: GeometryEffect {
    var travel: CGFloat = 5
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 6), y: 0))
    }
}

// MARK: - PathwayHub · milestones (next reward + badge rail)

private struct PathwayMilestones: View {
    let levels: [PathwayLevel]
    let reward: PWReward?
    let openResume: () -> Void
    private var earned: Int { levels.filter(\.walked).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MILESTONES").font(.inter(11, .bold)).kerning(1.62).foregroundStyle(PW.goldDeep)
                Spacer()
                if earned > 0 {   // no "0 earned" (§7.4 #9; the walk's E14)
                    Text("\(earned) earned").font(.inter(11, .semibold)).foregroundStyle(PW.ink3)
                }
            }.padding(.horizontal, 4)
            if let r = reward, r.remaining > 0 { nextRewardCard(r) }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(levels.enumerated()), id: \.element.id) { i, lvl in
                        PWRewardBadge(name: pwShortName(lvl.title), emoji: PW.badgeEmoji[i % PW.badgeEmoji.count], earned: lvl.walked)
                    }
                }.padding(.horizontal, 2)
            }
        }
    }

    private func nextRewardCard(_ r: PWReward) -> some View {
        Button { Haptics.tap(); openResume() } label: {
            HStack(spacing: 12) {
                Text(r.emoji).font(.emoji(22))
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("NEXT REWARD").font(.inter(11, .bold)).kerning(1.28).foregroundStyle(PW.goldLight)
                    Text("The “\(r.name)” badge").font(.inter(13, .bold)).foregroundStyle(.white).lineLimit(1)
                    HStack(spacing: 8) {
                        PWBar(pct: r.pct, height: 6, fill: .linearGradient(colors: [PW.gold, PW.goldLight], startPoint: .leading, endPoint: .trailing), track: Color.white.opacity(0.16))
                        Text("\(r.remaining) to go").font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.7))
                    }
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: .white.opacity(0.5))
            }
            .padding(14)
            .background(LinearGradient(colors: [PW.navy, PW.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: PW.navyDeep.opacity(0.6), radius: 20, y: 12)
        }
        .buttonStyle(.pressable)
    }
}

private struct PWRewardBadge: View {
    let name: String
    let emoji: String
    let earned: Bool
    var body: some View {
        VStack(spacing: 6) {
            Text(emoji).font(.emoji(22)).frame(width: 44, height: 44)
                .background(earned ? Color.white : PW.mutedBg, in: Circle())
                .overlay(Circle().stroke(earned ? PW.gold.opacity(0.33) : PW.border, lineWidth: 1))
                .grayscale(earned ? 0 : 1).opacity(earned ? 1 : 0.7)
            Text(name).font(.inter(11, .semibold)).foregroundStyle(earned ? PW.navy : PW.ink3).lineLimit(1)
            if earned {
                HStack(spacing: 1) {
                    ForEach(0..<3, id: \.self) { _ in Image(systemName: "star.fill").font(.symbol(8)).foregroundStyle(PW.gold) }
                }
            } else {
                Icon(.lock, size: 14, color: PW.ink3)
            }
        }
        .frame(width: 84).padding(.vertical, 12)
        .background(earned
                    ? AnyShapeStyle(LinearGradient(colors: [PW.gold.opacity(0.14), PW.gold.opacity(0.03)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(PW.surface),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(earned ? PW.gold.opacity(0.33) : PW.navy.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: earned ? [] : [4])))
    }
}

// MARK: - PathwayHub · mid-trail "Pause & surrender" figure (fresh Figma)

private struct PWSurrenderFigure: View {
    private let img = "https://images.unsplash.com/photo-1510590337019-5ef8d3d32116?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080"
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Overlay-on-Color.clear: a bare scaledToFill reports the image's
            // own fill width and inflates the whole screen column past the
            // phone's edges (the radio-screen bug, same family).
            if let u = URL(string: img) {
                Color.clear
                    .overlay {
                        CachedAsyncImage(url: u) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                    }
                    .clipped()
            }
            LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.15), Color(hex: 0x081424, alpha: 0.55), Color(hex: 0x081424, alpha: 0.90)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 2) {
                Text("PAUSE & SURRENDER").font(.inter(11, .bold)).kerning(1.54).foregroundStyle(PW.goldLight)
                Text("“Offer yourselves as a living sacrifice, holy and pleasing to God.”")
                    .font(.fraunces(12, .medium)).italic().foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Romans 12:1 · Surrender to His Word").font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.65))
            }
            .padding(14)
        }
        .frame(height: 224).frame(maxWidth: .infinity).clipped()
        .overlay(alignment: .top) { Rectangle().fill(PW.border).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(PW.border).frame(height: 1) }
    }
}

// MARK: - PathwayHub · the summit (redesigned commissioning card — Android parity)

private struct PathwaySummitCard: View {
    /// The journey reached `finished` — the final level's exam is passed
    /// (§3). Never "every published module done": Level 1 finishers were being
    /// commissioned while Levels 2–6 had nothing published yet.
    let reached: Bool
    let levels: [PathwayLevel]
    let firstName: String
    /// Levels still between the member and being sent — at least one until
    /// the summit: every module done at the last level still leaves its exam
    /// (it used to read "0 levels between you and being sent").
    private var levelsLeft: Int { max(1, levels.filter { !$0.walked }.count) }
    // Real sending: a worship gathering, hands raised, JESUS over the stage —
    // visually verified (not picked blind from an ID).
    private let img = "https://images.unsplash.com/photo-1507692049790-de58290a4334?crop=entropy&cs=tinysrgb&fit=max&fm=jpg&q=80&w=1080"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("THE SUMMIT · WHERE THIS ROAD LEADS")
                .font(.inter(11, .bold)).kerning(1.62).foregroundStyle(PW.goldDeep).padding(.horizontal, 4)
            card
        }
        // First time the summit is truly reached → a real celebration (once ever;
        // CelebrationCenter persists fired keys, so replays are no-ops).
        .task(id: reached) {
            guard reached else { return }
            CelebrationCenter.shared.fire(
                key: "commissioned",
                title: "You have been commissioned",
                subtitle: "Sent to make disciples — Matthew 28:19")
        }
    }

    private var card: some View {
        ZStack {
            // Overlay-on-Color.clear so the artwork's fill width can't inflate
            // the card (and with it the whole Pathway column) past the screen.
            if let u = URL(string: img) {
                Color.clear
                    .overlay {
                        CachedAsyncImage(url: u) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                    }
                    .clipped()
            }
            // Navy scrim: 0x26 → 0x73 → 0xF2 of 0A1628, top → bottom.
            LinearGradient(colors: [Color(hex: 0x0A1628, alpha: 0.15), Color(hex: 0x0A1628, alpha: 0.45), Color(hex: 0x0A1628, alpha: 0.95)], startPoint: .top, endPoint: .bottom)
            content
        }
        .frame(height: 300).frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        // Reached earns a gold ceremonial ring; the road there stays quiet.
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(reached ? PW.gold.opacity(0.85) : .clear, lineWidth: 1.5))
        .overlay(alignment: .topTrailing) { statusChip.padding(12) }
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            if reached { Image(systemName: "star.fill").font(.symbol(10)) } else { Icon(.lock, size: 14, color: .white) }
            Text(reached ? "SENT" : "AHEAD OF YOU").font(.inter(11, .bold)).kerning(1)
        }
        .foregroundStyle(reached ? PW.navy : .white)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(reached ? PW.gold : Color.white.opacity(0.18), in: Capsule())
    }

    private var content: some View {
        VStack(spacing: 0) {
            // Ceremonial seal — double gold ring, medal, no emoji.
            ZStack {
                Circle().fill(Color.white.opacity(reached ? 0.14 : 0.07)).frame(width: 58, height: 58)
                    .overlay(Circle().strokeBorder(PW.gold.opacity(reached ? 0.95 : 0.45), lineWidth: 1.5))
                Circle().strokeBorder(PW.goldLight.opacity(reached ? 0.8 : 0.35), lineWidth: 1).frame(width: 46, height: 46)
                Icon(.award, size: 24, color: reached ? PW.goldLight : PW.gold.opacity(0.75))
            }
            .padding(.bottom, 10)
            Text("COMMISSIONED").font(.inter(11, .bold)).kerning(2.4).foregroundStyle(PW.goldLight)
            // The actual charge, not a caption — the words carry the weight.
            Text("“Go therefore and make disciples of all nations…”")
                .font(.fraunces(18, .semibold)).italic().kerning(-0.2)
                .foregroundStyle(.white).multilineTextAlignment(.center).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            Text("MATTHEW 28:19").font(.inter(11, .bold)).kerning(1.8)
                .foregroundStyle(.white.opacity(0.75)).padding(.top, 4)
            // The road itself: one dot per level, gold when walked.
            HStack(spacing: 8) {
                ForEach(levels) { lv in
                    let done = reached || lv.walked
                    Circle()
                        .fill(done ? PW.gold : Color.white.opacity(0.28))
                        .overlay(Circle().strokeBorder(done ? PW.goldLight : .clear, lineWidth: 1))
                        .frame(width: done ? 9 : 7, height: done ? 9 : 7)
                }
            }
            .padding(.top, 14)
            Text(personalLine)
                .font(.inter(11, .bold)).foregroundStyle(PW.goldLight)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .padding(.horizontal, 20).padding(.vertical, 22)
    }

    private var personalLine: String {
        if reached { return "\(firstName), you have been commissioned — go." }
        if levelsLeft == 1 { return "One level between you and being sent." }
        return "\(levelsLeft) levels between you and being sent."
    }
}

// MARK: - Levels map ("Map view") — the calm all-levels overview (LevelsOverview.tsx)

struct LevelsMapView: View {
    @ObservedObject var vm: PathwayViewModel
    let onOpenLevel: (Int) -> Void
    @Environment(\.dismiss) private var dismiss

    /// The member's own level wears the journey's word once its modules are
    /// done ("Exam ready", "Exam passed") — not the server's bare "completed",
    /// which says every module is done, not that the level is passed.
    private func stagePill(for level: PathwayLevel) -> String? {
        guard let j = vm.journey, j.levelNumber == level.levelNumber, j.stage != .learning else { return nil }
        return j.pill
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                if let s = vm.summary {
                    VStack(alignment: .leading, spacing: 0) {
                        if let a = vm.activeLevel {
                            PWContinueCard(level: a, words: LevelsMapWords.continueCard(level: a, journey: vm.journey)) {
                                onOpenLevel(a.levelNumber)
                            }.padding(.bottom, 20)
                        }
                        sectionHeader.padding(.bottom, 12)
                        VStack(spacing: 12) {
                            ForEach(s.levels) { level in
                                PWLevelCard(level: level, stagePill: stagePill(for: level),
                                            lockLine: LevelsMapWords.lockLine(levelNumber: level.levelNumber, journey: vm.journey,
                                                                              preparing: level.lessonCount <= 0)) {
                                    if level.status != .locked { onOpenLevel(level.levelNumber) }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                }
            }
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .ignoresSafeArea(edges: .top)
        .background(PW.bg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    // Fresh Figma LevelsOverview: light cream header, navy text, white stat cards.
    private var header: some View {
        ZStack(alignment: .topTrailing) {
            Circle().fill(PW.gold.opacity(0.14)).frame(width: 288, height: 288).blur(radius: 48).offset(x: 80, y: -96)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Button { Haptics.tap(); dismiss() } label: {
                        Icon(.chevronLeft, size: 22, color: PW.navy).frame(width: 36, height: 36)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().stroke(PW.border, lineWidth: 1))
                            .contentShape(Circle())
                    }.buttonStyle(.pressable)
                    Spacer()
                }
                // A pushed page's kicker names the page (§8.1 rule 2) — the
                // greeting is Home's alone (the walk's E5: "WELCOME BACK, ADA").
                Text("MAP VIEW")
                    .font(.inter(11, .medium)).kerning(1.98).foregroundStyle(Color(hex: 0x9A7A2A)).padding(.top, 14)
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your pathway is unfolding.")
                            .font(.fraunces(28, .medium)).kerning(-1.35).lineSpacing(4).foregroundStyle(PW.navy)
                        Text("A calm view of your discipleship journey, saved progress, and what opens next.")
                            .font(.inter(14)).foregroundStyle(Color(hex: 0x59667C)).lineSpacing(3)
                            .frame(maxWidth: 280, alignment: .leading).padding(.top, 12)
                    }
                    Spacer(minLength: 0)
                    PWProgressRing(pct: vm.journey?.progressPercent ?? 0)
                }.padding(.top, 12)
                HStack(spacing: 8) {
                    PWStatCard(label: "Levels", value: "\(vm.levelsDone)/\(vm.levelCount)")
                    PWStatCard(label: "Modules", value: "\(vm.doneModules)/\(vm.totalModules)")
                    PWStatCard(label: "Offline", value: "Ready")
                }.padding(.top, 24)
            }
            .padding(.horizontal, 20).padding(.top, NuruSafeArea.top + 8).padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .bottom) { Rectangle().fill(PW.border).frame(height: 1) }
        .clipped()
    }

    private var sectionHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("SIX-LEVEL PATHWAY").font(.inter(11, .medium)).kerning(1.54).foregroundStyle(PW.ink2)
                Text("Choose your level").font(.fraunces(22, .medium)).kerning(-0.88).foregroundStyle(PW.ink).padding(.top, 4)
            }
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white).shadow(color: PW.navy.opacity(0.05), radius: 6, y: 2)
                Icon(.map, size: 18, color: PW.navy)
            }.frame(width: 40, height: 40)
        }
    }
}

// MARK: - 74px progress ring

private struct PWProgressRing: View {
    let pct: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        ZStack {
            Circle().stroke(Color(hex: 0x0B1F33, alpha: 0.12), lineWidth: 6)
            Circle().trim(from: 0, to: shown ? CGFloat(max(0, min(100, pct))) / 100 : 0)
                .stroke(PW.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.spring(response: 0.8, dampingFraction: 0.9), value: pct)
            VStack(spacing: 0) {
                Text("\(pct)%").font(.fraunces(18, .medium)).kerning(-0.72).foregroundStyle(PW.navy)
                    .contentTransition(.numericText())
                    .animation(.default, value: pct)
                Text("DONE").font(.inter(11, .medium)).kerning(1.08).foregroundStyle(Color(hex: 0x74808F))
                    .padding(.top, -1)
            }
        }
        .frame(width: 74, height: 74)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true }
            else { withAnimation(.spring(response: 0.8, dampingFraction: 0.9).delay(0.15)) { shown = true } }
        }
    }
}

// MARK: - stat card (white on the cream header, fresh Figma)

private struct PWStatCard: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(.inter(11, .medium)).kerning(1.2).foregroundStyle(Color(hex: 0x74808F))
            Text(value).font(.inter(16, .bold)).kerning(-0.32).foregroundStyle(PW.navy).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PW.border, lineWidth: 1))
    }
}

// MARK: - "Continue your journey" active-level card

private struct PWContinueCard: View {
    let level: PathwayLevel
    /// The journey's words for this level (the walk's E5: "CONTINUE YOUR
    /// JOURNEY · Level 1" over a level whose every module was done).
    let words: LevelsMapWords.Card
    let onTap: () -> Void
    private var pct: Int { level.lessonCount > 0 ? min(100, Int(round(Double(level.lessonsDone) / Double(level.lessonCount) * 100))) : 0 }

    var body: some View {
        Button { Haptics.tap(); onTap() } label: {
            ZStack(alignment: .trailing) {
                // Right tone strip + decorative ring — narrow enough that the
                // words never run under it (the walk's E5: "the navy panel cuts
                // its own words"); the chevron sits on it.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: PW.tone(level.levelNumber), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 56).opacity(0.9)
                        .overlay(alignment: .topTrailing) {
                            Circle().stroke(Color.white.opacity(0.25), lineWidth: 1).frame(width: 44, height: 44).offset(x: 10, y: 14)
                        }
                        .clipped()
                }

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PW.navy.opacity(0.06))
                        Icon(.bookOpen, size: 22, color: PW.navy)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 0) {
                        Text(words.kicker).font(.inter(11, .medium)).kerning(1.54).foregroundStyle(PW.goldDeep)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text(words.title)
                            .font(.nCardTitle).kerning(-0.54).foregroundStyle(PW.ink)
                            .lineLimit(2).multilineTextAlignment(.leading).padding(.top, 4)
                            .fixedSize(horizontal: false, vertical: true)
                        if let line = words.line {
                            Text(line).font(.nCardBody).foregroundStyle(PW.ink2)
                                .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                        }
                        PWBar(pct: words.line == nil ? pct : 100, height: 8, fill: .linearGradient(colors: [Color(hex: 0xB8911F), Color(hex: 0xD8B84D)], startPoint: .leading, endPoint: .trailing), track: PW.navy.opacity(0.10))
                            .padding(.top, 12)
                    }
                    .padding(.trailing, 12)
                    Icon(.chevronRight, size: 18, color: PW.gold)
                }
                .padding(16)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(PW.gold.opacity(0.35), lineWidth: 1))
            .shadow(color: PW.navy.opacity(0.10), radius: 8, y: 3)
        }
        .buttonStyle(.pressableSubtle)
    }
}

// MARK: - level card

private struct PWLevelCard: View {
    let level: PathwayLevel
    /// The journey's word for the member's own level once its modules are
    /// done ("Exam ready", "Exam passed") — nil for every other level.
    var stagePill: String? = nil
    /// What opens this level when it is locked, in the journey's words.
    var lockLine: String = ""
    let onTap: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shakes = 0

    /// Walked: ushered past, or its exam passed and awaiting the usher — an
    /// awaiting level is the member's own, never "locked".
    private var isCompleted: Bool { level.walked }
    private var isActive: Bool { level.status == .active }
    private var isLocked: Bool { level.status == .locked }
    private var pct: Int { level.lessonCount > 0 ? min(100, Int(round(Double(level.lessonsDone) / Double(level.lessonCount) * 100))) : 0 }
    private var subtitle: String { level.theme ?? level.description ?? PW.subtitle[level.levelNumber] ?? "" }

    var body: some View {
        Button(action: handleTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isActive ? PW.navy : isCompleted ? PW.goldTint : PW.mutedBg)
                    if isCompleted {
                        Icon(.check, size: 18, color: PW.goldDeep)
                    } else if isLocked {
                        Icon(.lock, size: 18, color: PW.ink3)
                    } else {
                        CrossMark(size: 18, color: PW.gold)   // Figma's lucide `Cross`
                    }
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("LEVEL \(level.levelNumber)").font(.inter(11, .medium)).kerning(1.4).foregroundStyle(PW.goldDeep)
                        Spacer(minLength: 0)
                        statusPill
                    }
                    Text(level.title).font(.nRowTitle).kerning(-0.3).foregroundStyle(PW.ink)
                        .lineLimit(2).multilineTextAlignment(.leading).padding(.top, 6)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.nCardBody).foregroundStyle(PW.ink2).lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    if isLocked {
                        HStack(spacing: 6) {
                            Icon(.lock, size: 14, color: PW.ink3)
                            Text(lockLine).font(.nCardMeta).foregroundStyle(PW.ink3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.top, 12)
                    } else {
                        VStack(spacing: 8) {
                            HStack {
                                HStack(spacing: 4) {
                                    Icon(.bookOpen, size: 14, color: PW.ink2)
                                    Text("\(min(level.lessonsDone, level.lessonCount))/\(level.lessonCount) modules").font(.nCardMeta).foregroundStyle(PW.ink2)
                                }
                                Spacer(minLength: 0)
                                Text("\(pct)%").font(.inter(11, .medium)).foregroundStyle(PW.navy)
                            }
                            PWBar(pct: pct, height: 6, fill: .color(PW.gold), track: PW.navy.opacity(0.10))
                        }
                        .padding(.top, 12)
                    }
                }

                if !isLocked {
                    Icon(.chevronRight, size: 18, color: PW.chevron).padding(.top, 8)
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isActive ? PW.gold.opacity(0.45) : PW.navy.opacity(0.08), lineWidth: 1))
            .shadow(color: PW.navy.opacity(0.04), radius: 4, y: 1)
            .opacity(isLocked ? 0.6 : 1)
        }
        .buttonStyle(.pressableSubtle)
        .modifier(PWLockedShake(animatableData: CGFloat(shakes)))
        .accessibilityHint(isLocked ? "Locked. \(lockLine)." : "")
    }

    /// Locked levels stay locked (server-authoritative, §1.9) — a tap answers
    /// with a refusal shake; the card already says what unlocks it.
    private func handleTap() {
        guard isLocked else { Haptics.tap(); onTap(); return }
        Haptics.error()
        if !reduceMotion { withAnimation(.linear(duration: 0.35)) { shakes += 1 } }
    }

    private var statusPill: some View {
        let (label, bg, fg): (String, Color, Color) = {
            if let stagePill { return (stagePill, PW.goldTint, Color(hex: 0x8A6B10)) }
            if level.isAwaitingReview { return ("Exam passed", PW.goldTint, Color(hex: 0x8A6B10)) }
            if isCompleted { return ("Complete", PW.goldTint, Color(hex: 0x8A6B10)) }
            if isActive    { return ("Active", Color(hex: 0xDDF4C6), Color(hex: 0x22612A)) }
            return ("Locked", PW.mutedBg, PW.ink3)
        }()
        return Text(label).font(.inter(11, .medium)).foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg, in: Capsule())
    }
}

// MARK: - progress bar (rounded track + fill)

private struct PWBar: View {
    enum Fill { case color(Color); case linearGradient(colors: [Color], startPoint: UnitPoint, endPoint: UnitPoint) }
    let pct: Int
    let height: CGFloat
    let fill: Fill
    let track: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fillShape)
                    .frame(width: geo.size.width * (shown ? CGFloat(max(0, min(100, pct))) / 100 : 0))
                    .animation(.spring(response: 0.8, dampingFraction: 0.9), value: pct)
            }
        }
        .frame(height: height)
        .onAppear {
            guard !shown else { return }
            if reduceMotion { shown = true }
            else { withAnimation(.spring(response: 0.8, dampingFraction: 0.9).delay(0.1)) { shown = true } }
        }
    }

    private var fillShape: AnyShapeStyle {
        switch fill {
        case .color(let c): return AnyShapeStyle(c)
        case .linearGradient(let colors, let s, let e): return AnyShapeStyle(LinearGradient(colors: colors, startPoint: s, endPoint: e))
        }
    }
}

// MARK: - First-load skeleton (mirrors the hub layout so content settles in place)

private struct PathwaySkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Hero placeholder — same parchment gradient and rounded bottom as the real header.
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(PW.mutedBg).frame(width: 170, height: 10)
                    RoundedRectangle(cornerRadius: 7, style: .continuous).fill(PW.mutedBg).frame(width: 230, height: 24)
                    RoundedRectangle(cornerRadius: 5, style: .continuous).fill(PW.mutedBg).frame(width: 190, height: 10)
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PW.navy.opacity(0.10))
                        .frame(height: 68).padding(.top, 8)
                }
                .padding(20)
            }
            .frame(height: 300)
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30, style: .continuous))

            // Journey rail + module list placeholders.
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 20) {
                    ForEach(0..<5, id: \.self) { _ in
                        Circle().fill(PW.mutedBg).frame(width: 48, height: 48)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(0..<4, id: \.self) { i in
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 11, style: .continuous).fill(PW.mutedBg).frame(width: 32, height: 32)
                            VStack(alignment: .leading, spacing: 6) {
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(PW.mutedBg).frame(width: 160, height: 10)
                                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(PW.mutedBg).frame(width: 76, height: 8)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .overlay(alignment: .bottom) { if i < 3 { Rectangle().fill(PW.border).frame(height: 1) } }
                    }
                }
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PW.border, lineWidth: 1))
            }
            .padding(.horizontal, 20)
        }
        .nuruShimmer()
        .accessibilityLabel("Loading your pathway")
    }
}

// Figma's lucide `Cross` — a thick, rounded, equal-arm cross (the Lucide subset
// only ships the thin `plus`, so we draw it to match the active-level tile).
private struct CrossMark: View {
    var size: CGFloat = 18
    var color: Color
    var body: some View {
        let bar = size * 0.32
        ZStack {
            Capsule().frame(width: bar, height: size)
            Capsule().frame(width: size, height: bar)
        }
        .foregroundStyle(color)
        .frame(width: size, height: size)
    }
}


/// The open module's words follow the server's progress (the walk's B3): a
/// module never opened (`progress` 0) is "Up next · tap to start" with
/// "Start" — it read "In progress · tap to continue" with "Resume" beside a
/// hero that said "Start", claiming progress that didn't exist.
enum ModuleRowWords {
    static func openCaption(progress: Double) -> String {
        progress > 0 ? "In progress · tap to continue" : "Up next · tap to start"
    }
    static func openAction(progress: Double) -> String {
        progress > 0 ? "Resume" : "Start"
    }
}

/// Map view speaks the journey's words (the Cycle 3 walk's E5): it said
/// "CONTINUE YOUR JOURNEY · Level 1" and "Complete Level 1 to unlock" while
/// Level 1's every module was done and its exam was next. Pure, so the
/// tests pin it.
enum LevelsMapWords {
    struct Card: Equatable { let kicker: String; let title: String; let line: String? }

    /// The continue card for the member's level: the journey's next step once
    /// the modules are done; "continue" only while there are modules to walk.
    static func continueCard(level: PathwayLevel, journey j: Journey?) -> Card {
        guard let j, j.levelNumber == level.levelNumber, j.stage != .learning else {
            return Card(kicker: "CONTINUE YOUR JOURNEY", title: "Level \(level.levelNumber): \(level.title)", line: nil)
        }
        return Card(kicker: j.kicker.uppercased(), title: j.title, line: j.line)
    }

    /// What opens a locked level: the step before it, in the journey's words.
    /// A level with no lessons yet is being prepared, and says so — nobody is
    /// promised to open it (§9.1 rule 7, §9.2 #7). Android's lockLine.
    static func lockLine(levelNumber n: Int, journey j: Journey?, preparing: Bool = false) -> String {
        let prev = n - 1
        guard let j, j.levelNumber == prev else {
            return preparing ? "Level \(n) is being prepared" : "Complete Level \(prev) to unlock"
        }
        switch j.stage {
        case .learning: return preparing ? "Level \(n) is being prepared" : "Complete Level \(prev) to unlock"
        case .examReady:
            return preparing ? "Pass the Level \(prev) exam — Level \(n) is being prepared"
                : "Pass the Level \(prev) exam — then your leader opens Level \(n)"
        case .examSoon:
            return preparing ? "The Level \(prev) exam opens soon — Level \(n) is being prepared"
                : "The Level \(prev) exam opens soon — then your leader opens Level \(n)"
        case .awaitingUsher, .finished:
            return preparing ? "Level \(n) is being prepared — we'll let you know"
                : "Your leader will open Level \(n) — you'll get a notice"
        }
    }
}
