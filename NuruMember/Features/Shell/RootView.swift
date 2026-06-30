// The signed-in tab shell — the native port of navigation/RootNavigator.tsx +
// BottomTabBar.tsx. Five primary tabs (Home · Pathway · Give · Community ·
// Profile); the full seven-destination map from the RN app is reintroduced as
// each feature screen is ported (see PORT_STATUS.md). Home is fully wired; the
// others are placeholders for the next porting phases.
import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }

            ComingSoon(title: "Pathway", icon: "map.fill",
                       blurb: "Levels, modules, quizzes and the learning path.")
                .tabItem { Label("Pathway", systemImage: "map.fill") }

            ComingSoon(title: "Give", icon: "heart.fill",
                       blurb: "Giving, schedules and statements (online-only, §5.6).")
                .tabItem { Label("Give", systemImage: "heart.fill") }

            ComingSoon(title: "Community", icon: "bubble.left.and.bubble.right.fill",
                       blurb: "Chat, prayer wall and cohort discussions.")
                .tabItem { Label("Community", systemImage: "bubble.left.and.bubble.right.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
        .tint(Nuru.gold)
    }
}

/// Placeholder destination for screens not yet ported.
struct ComingSoon: View {
    var title: String
    var icon: String
    var blurb: String

    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                VStack(spacing: Nuru.S.base) {
                    Image(systemName: icon)
                        .font(.system(size: 40))
                        .foregroundStyle(Nuru.gold)
                    Text(title).font(.nTitle).foregroundStyle(Nuru.ink)
                    Text(blurb)
                        .font(.nBody).foregroundStyle(Nuru.muted)
                        .multilineTextAlignment(.center)
                    Text("Porting in progress")
                        .font(.nMicro).foregroundStyle(Nuru.faint)
                        .padding(.top, Nuru.S.sm)
                }
                .padding(Nuru.S.xl)
            }
            .navigationTitle(title)
        }
    }
}

/// Minimal Profile tab — shows the signed-in member and a sign-out control.
struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Nuru.S.base) {
                        if let p = auth.profile {
                            Card {
                                VStack(alignment: .leading, spacing: Nuru.S.xs) {
                                    Text(p.fullName).font(.nHeading).foregroundStyle(Nuru.ink)
                                    if let email = p.email {
                                        Text(email).font(.nCaption).foregroundStyle(Nuru.muted)
                                    }
                                    Text(p.role.capitalized).font(.nMicro).foregroundStyle(Nuru.gold)
                                }
                            }
                        }
                        PButton(title: "Sign out", variant: .navy) { auth.signOut() }
                    }
                    .padding(Nuru.S.screen)
                }
            }
            .navigationTitle("Profile")
        }
    }
}
