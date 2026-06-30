// Pathway hub — the native port of screens/LevelsScreen.tsx. The journey reads as
// a vertical trail of levels (completed / active / locked) on a gold rail. The
// §1.9 hard-lock is enforced here AND server-side: a level above current_level is
// never tappable. Hosts the Level → Module → Quiz navigation stack.
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
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { summary = try await MemberAPI.pathway() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your pathway." }
        loading = false
    }
}

struct PathwayView: View {
    @StateObject private var vm = PathwayViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                Group {
                    if vm.loading && vm.summary == nil {
                        ProgressView()
                    } else if let summary = vm.summary {
                        trail(summary)
                    } else {
                        errorState
                    }
                }
            }
            .navigationTitle("Pathway")
            .navigationDestination(for: PathwayRoute.self) { route in
                switch route {
                case .level(let n): LevelDetailView(levelNumber: n)
                case .module(let id): ModuleView(moduleId: id)
                case .quiz(let id): QuizView(moduleId: id)
                }
            }
        }
        .task { if vm.summary == nil { await vm.load() } }
    }

    private func trail(_ summary: PathwaySummary) -> some View {
        ScrollView {
            VStack(spacing: Nuru.S.md) {
                ForEach(summary.levels) { level in
                    levelRow(level, currentLevel: summary.currentLevel)
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private func levelRow(_ level: PathwayLevel, currentLevel: Int) -> some View {
        let locked = LevelGating.isLevelLocked(level.levelNumber, currentLevel: currentLevel, serverStatus: level.status)
        let content = LevelCard(level: level, locked: locked, currentLevel: currentLevel)
        if locked {
            content   // non-tappable (§1.9)
        } else {
            NavigationLink(value: PathwayRoute.level(level.levelNumber)) { content }
                .buttonStyle(.plain)
        }
    }

    private var errorState: some View {
        VStack(spacing: Nuru.S.md) {
            Text(vm.error ?? "Something went wrong.").font(.nBody).foregroundStyle(Nuru.muted)
            Button("Try again") { Task { await vm.load() } }
                .font(.inter(14, .semibold)).foregroundStyle(Nuru.gold)
        }
        .padding(Nuru.S.xl)
    }
}

/// One station on the level trail.
private struct LevelCard: View {
    let level: PathwayLevel
    let locked: Bool
    let currentLevel: Int

    var body: some View {
        Card {
            HStack(spacing: Nuru.S.base) {
                badge
                VStack(alignment: .leading, spacing: Nuru.S.xs) {
                    Text("Level \(level.levelNumber)")
                        .font(.nOverline).foregroundStyle(Nuru.gold).textCase(.uppercase)
                    Text(level.title).font(.nHeading).foregroundStyle(Nuru.ink)
                    if locked {
                        Text(LevelGating.lockedLevelLabel(currentLevel: currentLevel))
                            .font(.nCaption).foregroundStyle(Nuru.muted)
                    } else {
                        Text("\(level.completedModules) of \(level.totalModules) modules")
                            .font(.nCaption).foregroundStyle(Nuru.muted)
                        ProgressView(value: progress)
                            .tint(Nuru.gold)
                    }
                }
                Spacer(minLength: 0)
                if !locked {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Nuru.ink300)
                }
            }
            .opacity(locked ? 0.6 : 1)
        }
    }

    private var progress: Double {
        level.totalModules == 0 ? 0 : Double(level.completedModules) / Double(level.totalModules)
    }

    private var badge: some View {
        ZStack {
            Circle()
                .fill(level.status == .completed ? Nuru.success : (locked ? Nuru.mutedBg : Nuru.goldTint))
                .frame(width: 44, height: 44)
            Image(systemName: locked ? "lock.fill" : (level.status == .completed ? "checkmark" : "book.fill"))
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(level.status == .completed ? .white : (locked ? Nuru.faint : Nuru.gold))
        }
    }
}
