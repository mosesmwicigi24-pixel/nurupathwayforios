// Home dashboard — the native port of screens/HomeDashboardScreen.tsx (the
// server-driven member home). The vertical slice that proves the end-to-end
// pattern: it loads /me, /me/home/next-action and /me/rhythm/today, renders the
// greeting hero + next-best-action + the daily rhythm row, and writes back a
// completed rhythm via /me/rhythm/complete.
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var nextAction: NextAction?
    @Published var rhythm: RhythmToday?
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true
        error = nil
        async let action = try? MemberAPI.nextAction()
        async let today = try? MemberAPI.rhythmToday()
        nextAction = await action ?? nil
        rhythm = await today
        if rhythm == nil { error = "Couldn't load your day. Pull to refresh." }
        loading = false
    }

    func complete(_ kind: String) async {
        guard let updated = try? await MemberAPI.completeRhythm(kind) else { return }
        rhythm = updated
    }
}

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = HomeViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Nuru.S.base) {
                        hero
                        if vm.loading && vm.rhythm == nil {
                            ProgressView().padding(.top, Nuru.S.xl)
                        } else {
                            if let action = vm.nextAction { nextActionCard(action) }
                            rhythmCard
                        }
                        if let error = vm.error {
                            Text(error).font(.nCaption).foregroundStyle(Nuru.muted)
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { BrandMark(size: 28) } }
        }
        .task { await vm.load() }
    }

    // Greeting hero — warm welcome + current level.
    private var hero: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            Text(greeting)
                .font(.nLabel).foregroundStyle(Nuru.onNavyDim)
            Text(firstName)
                .font(.fraunces(28, .semibold)).foregroundStyle(.white)
            if let level = auth.me?.enrollment?.currentLevel {
                Text("Level \(level) · Pathway")
                    .font(.nCaption).foregroundStyle(Nuru.goldGlow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.lg)
        .background(Nuru.heroGradient, in: RoundedRectangle(cornerRadius: Nuru.R.hero, style: .continuous))
        .nuruShadow()
    }

    private func nextActionCard(_ action: NextAction) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("Next for you")
                    .font(.nOverline).foregroundStyle(Nuru.gold).textCase(.uppercase)
                Text(action.title).font(.nHeading).foregroundStyle(Nuru.ink)
                Text(action.body).font(.nBody).foregroundStyle(Nuru.muted)
                HStack {
                    Text(action.ctaLabel)
                        .font(.inter(13, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.sm)
                        .background(accentColor(action.accent), in: Capsule())
                    Spacer()
                }
            }
        }
    }

    // The three daily rhythms — tap an undone one to mark it complete.
    private var rhythmCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                HStack {
                    Text("Today's rhythm").font(.nHeading).foregroundStyle(Nuru.ink)
                    Spacer()
                    if let r = vm.rhythm {
                        Text("\(r.doneCount)/3").font(.nLabel).foregroundStyle(Nuru.gold)
                    }
                }
                HStack(spacing: Nuru.S.md) {
                    rhythmTile("Prayer", "hands.sparkles.fill", done: vm.rhythm?.prayer ?? false, kind: "prayer")
                    rhythmTile("Word", "book.fill", done: vm.rhythm?.word ?? false, kind: "word")
                    rhythmTile("Reflect", "sparkles", done: vm.rhythm?.reflection ?? false, kind: "reflection")
                }
            }
        }
    }

    private func rhythmTile(_ label: String, _ icon: String, done: Bool, kind: String) -> some View {
        Button {
            if !done { Task { await vm.complete(kind) } }
        } label: {
            VStack(spacing: Nuru.S.xs) {
                Image(systemName: done ? "checkmark.circle.fill" : icon)
                    .font(.system(size: 22))
                    .foregroundStyle(done ? Nuru.success : Nuru.gold)
                Text(label).font(.nMicro).foregroundStyle(done ? Nuru.successText : Nuru.muted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Nuru.S.md)
            .background(done ? Nuru.successBg : Nuru.surface,
                        in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(done)
    }

    // MARK: helpers

    private var firstName: String {
        let name = auth.profile?.fullName ?? "Friend"
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "Good morning"
        case 12..<17: return "Good afternoon"
        default: return "Good evening"
        }
    }

    private func accentColor(_ accent: String) -> Color {
        switch accent {
        case "gold": return Nuru.gold
        case "success": return Nuru.success
        case "steady": return Color(hex: 0x1B5FAE)
        default: return Nuru.navy
        }
    }
}
