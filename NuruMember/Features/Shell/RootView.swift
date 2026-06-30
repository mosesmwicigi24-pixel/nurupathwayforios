// The signed-in shell — the native port of navigation/RootNavigator.tsx +
// BottomTabBar.tsx. Seven primary destinations on a custom navy bar with a gold
// active icon + label + top indicator dot (Home · Pathway · Plans · Events ·
// Chat · Give · Profile). The system tab bar is hidden; we draw our own to match
// the RN design exactly.
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, pathway, plans, events, chat, give, profile

    /// Debug-only: lets a screenshot script open the app on a chosen tab via the
    /// NURU_TAB launch env var (e.g. SIMCTL_CHILD_NURU_TAB=pathway). Defaults home.
    static var initialTab: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["NURU_TAB"] {
        case "pathway": return .pathway
        case "plans": return .plans
        case "events": return .events
        case "chat": return .chat
        case "give": return .give
        case "profile": return .profile
        default: return .home
        }
        #else
        return .home
        #endif
    }

    var label: String {
        switch self {
        case .home: return "Home"
        case .pathway: return "Pathway"
        case .plans: return "Plans"
        case .events: return "Events"
        case .chat: return "Chat"
        case .give: return "Give"
        case .profile: return "Profile"
        }
    }
    var icon: Lucide {
        switch self {
        case .home: return .house
        case .pathway: return .bookOpen
        case .plans: return .bookMarked
        case .events: return .calendarDays
        case .chat: return .messageCircle
        case .give: return .handHeart
        case .profile: return .user
        }
    }
}

struct RootView: View {
    @State private var tab: AppTab = .initialTab

    var body: some View {
        TabView(selection: $tab) {
            HomeView().tag(AppTab.home)
            PathwayView().tag(AppTab.pathway)
            PlansTab().tag(AppTab.plans)
            EventsView().tag(AppTab.events)
            ChatView().tag(AppTab.chat)
            GivingView().tag(AppTab.give)
            ProfileView().tag(AppTab.profile)
        }
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .bottom) {
            NuruTabBar(selection: $tab).ignoresSafeArea(edges: .bottom)
        }
    }

    private func placeholderTab(_ title: String, _ blurb: String, _ icon: Lucide) -> some View {
        NavigationStack {
            PlaceholderScreen(title: title, blurb: blurb, icon: icon).navigationTitle(title)
        }
    }
}

/// Plans tab — the reading-plan catalogue with its own navigation stack.
private struct PlansTab: View {
    var body: some View {
        NavigationStack { ReadingPlansView() }.nuruDestinations()
    }
}

/// Custom bottom bar: navy, gold active (icon + label + top dot), dim inactive.
private struct NuruTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                let focused = selection == t
                Button {
                    selection = t
                } label: {
                    VStack(spacing: 3) {
                        Icon(t.icon, size: 21, color: focused ? Nuru.gold : Nuru.onNavyFaint)
                        Text(t.label).font(.inter(11, .medium)).foregroundStyle(focused ? Nuru.gold : Nuru.onNavyFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .overlay(alignment: .top) {
                        if focused {
                            Capsule().fill(Nuru.gold).frame(width: 28, height: 3).offset(y: -2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Self.safeBottom)
        .background(Nuru.navy)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1) }
    }

    /// Bottom safe-area inset (home indicator) so labels never sit under it.
    static var safeBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let inset = scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
        return max(inset, Nuru.S.md)
    }
}

/// Profile tab — identity + sign out (native port of screens/ProfileScreen.tsx
/// header; full profile detail lands in Phase 6).
struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    Text("Profile").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.ink)
                        .padding(.top, Nuru.S.sm)
                    if let p = auth.profile {
                        Card {
                            HStack(spacing: Nuru.S.base) {
                                Avatar(url: p.avatarUrl, name: p.fullName, size: 52)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(p.fullName).font(.nHeading).foregroundStyle(Nuru.ink)
                                    if let email = p.email { Text(email).font(.nCaption).foregroundStyle(Nuru.muted) }
                                    Text(p.role.capitalized).font(.nMicro).foregroundStyle(Nuru.gold)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    VStack(spacing: 0) {
                        menuRow("Notifications", .bell, route: AppRoute.notifications)
                        Divider().padding(.leading, 56)
                        menuRow("Your Calling", .sparkles, route: GrowDestination.gifts)
                        Divider().padding(.leading, 56)
                        menuRow("Memory Verses", .quote, route: GrowDestination.memoryVerses)
                        Divider().padding(.leading, 56)
                        menuRow("Resources", .bookOpen, route: GrowDestination.resources)
                    }
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    .nuruShadow()

                    PButton(title: "Sign out", variant: .navy) { auth.signOut() }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, 60)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .nuruDestinations()
        }
    }

    private func menuRow<R: Hashable>(_ title: String, _ icon: Lucide, route: R) -> some View {
        NavigationLink(value: route) {
            HStack(spacing: Nuru.S.md) {
                Icon(icon, size: 18, color: Nuru.gold).frame(width: 28)
                Text(title).font(.inter(15, .medium)).foregroundStyle(Nuru.ink)
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 14, color: Nuru.ink300)
            }
            .padding(Nuru.S.base)
        }
        .buttonStyle(.plain)
    }
}
