// Level detail — the native port of screens/LevelScreen.tsx: the vertical module
// trail for a level. Completed modules are checked; the next one is open; locked
// modules are dimmed and non-tappable (the server is authoritative, §1.9).
import SwiftUI

@MainActor
final class LevelDetailViewModel: ObservableObject {
    @Published var modules: [LevelModule] = []
    @Published var loading = true
    @Published var error: String?

    private let levelNumber: Int
    init(levelNumber: Int) { self.levelNumber = levelNumber }

    func load() async {
        loading = true; error = nil
        do { modules = try await MemberAPI.levelModules(levelNumber) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load modules." }
        loading = false
    }
}

struct LevelDetailView: View {
    let levelNumber: Int
    @StateObject private var vm: LevelDetailViewModel

    init(levelNumber: Int) {
        self.levelNumber = levelNumber
        _vm = StateObject(wrappedValue: LevelDetailViewModel(levelNumber: levelNumber))
    }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            if vm.loading && vm.modules.isEmpty {
                ProgressView()
            } else if vm.modules.isEmpty {
                Text(vm.error ?? "No modules yet.").font(.nBody).foregroundStyle(Nuru.muted)
            } else {
                ScrollView {
                    VStack(spacing: Nuru.S.md) {
                        header
                        ForEach(Array(vm.modules.enumerated()), id: \.element.id) { _, m in
                            moduleRow(m)
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("Level \(levelNumber)")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.modules.isEmpty { await vm.load() } }
    }

    private var header: some View {
        let completed = vm.modules.filter(\.completed).count
        let minutes = vm.modules.compactMap(\.estimatedMinutes).reduce(0, +)
        return Card {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("\(completed) of \(vm.modules.count) modules")
                    .font(.nHeading).foregroundStyle(Nuru.ink)
                if minutes > 0 {
                    Text("About \(minutes) min total").font(.nCaption).foregroundStyle(Nuru.muted)
                }
                ProgressView(value: vm.modules.isEmpty ? 0 : Double(completed) / Double(vm.modules.count))
                    .tint(Nuru.gold)
            }
        }
    }

    @ViewBuilder
    private func moduleRow(_ m: LevelModule) -> some View {
        let card = ModuleRowCard(module: m)
        if m.locked {
            card   // non-tappable (§1.9)
        } else {
            NavigationLink(value: PathwayRoute.module(m.moduleId)) { card }
                .buttonStyle(.plain)
        }
    }
}

private struct ModuleRowCard: View {
    let module: LevelModule

    var body: some View {
        Card {
            HStack(spacing: Nuru.S.base) {
                ZStack {
                    Circle()
                        .fill(module.completed ? Nuru.success : (module.locked ? Nuru.mutedBg : Nuru.goldTint))
                        .frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(module.completed ? .white : (module.locked ? Nuru.faint : Nuru.gold))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(module.title).font(.nHeading).foregroundStyle(Nuru.ink)
                    if let summary = module.summary, !summary.isEmpty {
                        Text(summary).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2)
                    } else if let mins = module.estimatedMinutes {
                        Text("\(mins) min").font(.nCaption).foregroundStyle(Nuru.muted)
                    }
                }
                Spacer(minLength: 0)
                if !module.locked {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Nuru.ink300)
                }
            }
            .opacity(module.locked ? 0.6 : 1)
        }
    }

    private var icon: String {
        if module.locked { return "lock.fill" }
        if module.completed { return "checkmark" }
        return module.requiresQuiz ? "pencil.and.list.clipboard" : "book.fill"
    }
}

private extension LevelModule {
    var requiresQuiz: Bool { evaluationKind.lowercased().contains("quiz") }
}
