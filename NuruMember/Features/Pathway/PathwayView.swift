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
}

// Exact Figma palette (LevelsOverview.tsx) — kept local so this page is 1:1 with
// the design rather than the app's near-equivalents.
private enum PW {
    static let navy      = Color(hex: 0x0A2540)
    static let gold      = Color(hex: 0xC9A227)
    static let bg        = Color(hex: 0xF4F0E8)
    static let ink       = Color(hex: 0x0B0B0C)   // primary heading
    static let ink2      = Color(hex: 0x68758A)   // secondary
    static let ink3      = Color(hex: 0x8B95A5)   // tertiary / locked
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
        do {
            summary = try await MemberAPI.pathway()
        } catch {
            summary = nil
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your pathway."
        }
        streak = (try? await MemberAPI.achievements())?.streak.current ?? 0
        if let active = active(in: summary) {
            activeModules = (try? await MemberAPI.levelModules(active.levelNumber)) ?? []
        }
        loading = false
    }

    private func active(in p: PathwaySummary?) -> PathwayLevel? {
        guard let p else { return nil }
        return p.levels.first { $0.status == .active }
            ?? p.levels.first { $0.levelNumber == p.currentLevel }
            ?? p.levels.first
    }
    var activeLevel: PathwayLevel? { active(in: summary) }

    var levelsDone: Int { summary?.levels.filter { $0.status == .completed }.count ?? 0 }
    var doneModules: Int { summary?.levels.reduce(0) { $0 + $1.completedModules } ?? 0 }
    var totalModules: Int { summary?.levels.reduce(0) { $0 + $1.totalModules } ?? 0 }
    var levelCount: Int { summary?.levels.count ?? 6 }
    var overallPct: Int { totalModules > 0 ? Int(round(Double(doneModules) / Double(totalModules) * 100)) : 0 }
}

struct PathwayView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = PathwayViewModel()
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    if vm.loading && vm.summary == nil {
                        ProgressView().tint(PW.gold).padding(.top, Nuru.S.xxl)
                    } else if vm.summary != nil {
                        body(vm.summary!)
                    } else {
                        errorState
                    }
                }
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .ignoresSafeArea(edges: .top)
            .background(PW.bg.ignoresSafeArea())
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
        .task { if vm.summary == nil { await vm.load() } }
    }

    // MARK: header (navy, full-bleed to the top edge)

    private var header: some View {
        ZStack(alignment: .topLeading) {
            // Decorative brand glows (LevelsOverview blur circles).
            Circle().fill(PW.gold.opacity(0.12)).frame(width: 288, height: 288).blur(radius: 60)
                .offset(x: 210, y: -150)
            Circle().fill(Color(hex: 0x5F8FC8).opacity(0.15)).frame(width: 96, height: 96).blur(radius: 40)
                .offset(x: 28, y: 96)

            VStack(alignment: .leading, spacing: 0) {
                Text("Welcome back, \(firstName)".uppercased())
                    .font(.inter(11, .medium)).kerning(1.98).foregroundStyle(PW.gold)
                HStack(alignment: .bottom, spacing: 16) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Your pathway is unfolding.")
                            .font(.fraunces(30, .medium)).kerning(-1.35).lineSpacing(4)
                            .foregroundStyle(.white)
                        Text("A calm view of your discipleship journey, saved progress, and what opens next.")
                            .font(.inter(14)).foregroundStyle(.white.opacity(0.55)).lineSpacing(3)
                            .frame(maxWidth: 280, alignment: .leading)
                            .padding(.top, 12)
                    }
                    Spacer(minLength: 0)
                    PWProgressRing(pct: vm.overallPct)
                }
                .padding(.top, 12)

                HStack(spacing: 8) {
                    PWStatCard(label: "Levels", value: "\(vm.levelsDone)/\(vm.levelCount)")
                    PWStatCard(label: "Modules", value: "\(vm.doneModules)/\(vm.totalModules)")
                    PWStatCard(label: "Offline", value: "Ready")
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)      // clears the status-bar / cream stripe
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(PW.navy)
        .clipped()
    }

    // MARK: body

    private func body(_ summary: PathwaySummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let a = vm.activeLevel {
                PWContinueCard(level: a) { path.append(PathwayRoute.level(a.levelNumber)) }
                    .padding(.bottom, 20)
            }
            sectionHeader.padding(.bottom, 12)
            VStack(spacing: 12) {
                ForEach(summary.levels) { level in
                    PWLevelCard(level: level) {
                        if level.status != .locked { path.append(PathwayRoute.level(level.levelNumber)) }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 24)
    }

    private var sectionHeader: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text("SIX-LEVEL PATHWAY").font(.inter(11, .medium)).kerning(1.54).foregroundStyle(PW.ink2)
                Text("Choose your level").font(.fraunces(22, .medium)).kerning(-0.88).foregroundStyle(PW.ink)
                    .padding(.top, 4)
            }
            Spacer(minLength: 0)
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white)
                    .shadow(color: PW.navy.opacity(0.05), radius: 6, y: 2)
                Icon(.map, size: 19, color: PW.navy)
            }
            .frame(width: 40, height: 40)
        }
    }

    private var errorState: some View {
        VStack(spacing: Nuru.S.md) {
            Text(vm.error ?? "Something went wrong.").font(.nBody).foregroundStyle(PW.ink2)
            Button("Try again") { Task { await vm.load() } }.font(.inter(14, .semibold)).foregroundStyle(PW.gold)
        }.padding(Nuru.S.xl)
    }

    private var firstName: String { (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend" }
}

// MARK: - 74px progress ring

private struct PWProgressRing: View {
    let pct: Int
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 6)
            Circle().trim(from: 0, to: CGFloat(pct) / 100)
                .stroke(PW.gold, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(pct)%").font(.fraunces(18, .medium)).kerning(-0.72).foregroundStyle(.white)
                Text("DONE").font(.inter(9, .medium)).kerning(1.08).foregroundStyle(.white.opacity(0.35))
                    .padding(.top, -1)
            }
        }
        .frame(width: 74, height: 74)
    }
}

// MARK: - glass stat card

private struct PWStatCard: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(.inter(10, .medium)).kerning(1.2).foregroundStyle(.white.opacity(0.38))
            Text(value).font(.inter(16, .bold)).kerning(-0.32).foregroundStyle(.white).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }
}

// MARK: - "Continue your journey" active-level card

private struct PWContinueCard: View {
    let level: PathwayLevel
    let onTap: () -> Void
    private var pct: Int { level.totalModules > 0 ? Int(round(Double(level.completedModules) / Double(level.totalModules) * 100)) : 0 }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .trailing) {
                // Right tone strip (w-32, opacity 90) + decorative ring.
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LinearGradient(colors: PW.tone(level.levelNumber), startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(width: 128).opacity(0.9)
                        .overlay(alignment: .topTrailing) {
                            Circle().stroke(Color.white.opacity(0.25), lineWidth: 1).frame(width: 80, height: 80).offset(x: -8, y: 24)
                        }
                }

                HStack(spacing: 16) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PW.navy.opacity(0.06))
                        Icon(.bookOpen, size: 20, color: PW.navy)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 0) {
                        Text("CONTINUE YOUR JOURNEY").font(.inter(11, .medium)).kerning(1.54).foregroundStyle(PW.goldDeep)
                        Text("Level \(level.levelNumber): \(level.title)")
                            .font(.fraunces(18, .medium)).kerning(-0.54).foregroundStyle(PW.ink)
                            .lineLimit(2).multilineTextAlignment(.leading).padding(.top, 4)
                        PWBar(pct: pct, height: 8, fill: .linearGradient(colors: [Color(hex: 0xB8911F), Color(hex: 0xD8B84D)], startPoint: .leading, endPoint: .trailing), track: PW.navy.opacity(0.10))
                            .padding(.top, 12)
                    }
                    .padding(.trailing, 8)
                    Icon(.chevronRight, size: 20, color: PW.gold)
                }
                .padding(16)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(PW.gold.opacity(0.35), lineWidth: 1))
            .shadow(color: PW.navy.opacity(0.10), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - level card

private struct PWLevelCard: View {
    let level: PathwayLevel
    let onTap: () -> Void

    private var isCompleted: Bool { level.status == .completed }
    private var isActive: Bool { level.status == .active }
    private var isLocked: Bool { level.status == .locked }
    private var pct: Int { level.totalModules > 0 ? Int(round(Double(level.completedModules) / Double(level.totalModules) * 100)) : 0 }
    private var subtitle: String { level.theme ?? level.description ?? PW.subtitle[level.levelNumber] ?? "" }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(isActive ? PW.navy : isCompleted ? PW.goldTint : PW.mutedBg)
                    Icon(isCompleted ? .check : isLocked ? .lock : .plus,
                         size: isCompleted ? 19 : isLocked ? 17 : 18,
                         color: isActive ? PW.gold : isCompleted ? PW.goldDeep : PW.ink3)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center) {
                        Text("LEVEL \(level.levelNumber)").font(.inter(10, .medium)).kerning(1.4).foregroundStyle(PW.goldDeep)
                        Spacer(minLength: 0)
                        statusPill
                    }
                    Text(level.title).font(.fraunces(15, .medium)).kerning(-0.3).foregroundStyle(PW.ink)
                        .lineLimit(2).multilineTextAlignment(.leading).padding(.top, 6)
                    if !subtitle.isEmpty {
                        Text(subtitle).font(.inter(12)).foregroundStyle(PW.ink2).lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
                    }
                    if isLocked {
                        HStack(spacing: 6) {
                            Icon(.lock, size: 12, color: PW.ink3)
                            Text("Complete Level \(level.levelNumber - 1) to unlock").font(.inter(12)).foregroundStyle(PW.ink3)
                        }
                        .padding(.top, 12)
                    } else {
                        VStack(spacing: 8) {
                            HStack {
                                HStack(spacing: 4) {
                                    Icon(.bookOpen, size: 12, color: PW.ink2)
                                    Text("\(level.completedModules)/\(level.totalModules) modules").font(.inter(11)).foregroundStyle(PW.ink2)
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
                    Icon(.chevronRight, size: 17, color: PW.chevron).padding(.top, 8)
                }
            }
            .padding(16)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(isActive ? PW.gold.opacity(0.45) : PW.navy.opacity(0.08), lineWidth: 1))
            .shadow(color: PW.navy.opacity(0.04), radius: 4, y: 1)
            .opacity(isLocked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private var statusPill: some View {
        let (label, bg, fg): (String, Color, Color) = {
            if isCompleted { return ("Complete", PW.goldTint, Color(hex: 0x8A6B10)) }
            if isActive    { return ("Active", Color(hex: 0xDDF4C6), Color(hex: 0x22612A)) }
            return ("Locked", PW.mutedBg, PW.ink3)
        }()
        return Text(label).font(.inter(10, .medium)).foregroundStyle(fg)
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

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(fillShape).frame(width: geo.size.width * CGFloat(max(0, min(100, pct))) / 100)
            }
        }
        .frame(height: height)
    }

    private var fillShape: AnyShapeStyle {
        switch fill {
        case .color(let c): return AnyShapeStyle(c)
        case .linearGradient(let colors, let s, let e): return AnyShapeStyle(LinearGradient(colors: colors, startPoint: s, endPoint: e))
        }
    }
}
