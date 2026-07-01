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
    @EnvironmentObject private var sync: SyncCoordinator
    // The member's chosen text size. `tab` lives on RootView (outside the .id'd
    // TabView), so changing the scale rebuilds every tab with the new fonts while
    // keeping the current tab selected.
    @AppStorage(Nuru.textScaleKey) private var textScale: Double = 1.0

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
        .id(textScale)
        .toolbar(.hidden, for: .tabBar)
        .overlay(alignment: .top) { SyncStatusBanner(sync: sync) }
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

/// Thin status pill that appears under the status bar when the member is offline
/// (or a queued write is still catching up). Reassures that nothing was lost —
/// the durable queue will sync on reconnect.
private struct SyncStatusBanner: View {
    @ObservedObject var sync: SyncCoordinator

    private var message: String? {
        if !sync.isOnline {
            return sync.pendingCount > 0
                ? "Offline · \(sync.pendingCount) change\(sync.pendingCount == 1 ? "" : "s") will sync"
                : "You're offline · changes are saved on this device"
        }
        if sync.isSyncing && sync.pendingCount > 0 { return "Syncing \(sync.pendingCount)…" }
        return nil
    }

    var body: some View {
        if let message {
            HStack(spacing: 6) {
                Icon(.clock, size: 12, color: Nuru.onNavy)
                Text(message).font(.inter(12, .semibold)).foregroundStyle(Nuru.onNavy)
            }
            .padding(.horizontal, Nuru.S.base)
            .padding(.vertical, 6)
            .background(Capsule().fill(sync.isOnline ? Nuru.navy : Nuru.ink))
            .nuruShadow()
            .padding(.top, 60)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: message)
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

// ProfileView (full Account screen) lives in Features/Profile/ProfileView.swift.
