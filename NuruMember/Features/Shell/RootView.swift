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

/// The selected primary tab, hoisted out of RootView so any screen can switch
/// tabs (e.g. Home's "Give now" banner → the Give tab). Injected app-wide.
@MainActor
final class TabRouter: ObservableObject {
    @Published var selected: AppTab = .initialTab
}

struct RootView: View {
    @EnvironmentObject private var tabs: TabRouter
    // Tabs that have been opened at least once — kept alive so their state (scroll,
    // loaded data) survives switching, without loading all seven on launch.
    @State private var loaded: Set<AppTab> = [AppTab.initialTab]
    @EnvironmentObject private var sync: SyncCoordinator
    @AppStorage(Nuru.textScaleKey) private var textScale: Double = 1.0

    /// Height of the top safe-area inset (status-bar / Dynamic Island band) so the
    /// cream stripe covers exactly that region. Falls back to 59 (Dynamic Island).
    private static var safeAreaTop: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 59
    }

    // A hand-rolled tab container instead of TabView: a stock TabView with 7 tabs
    // collapses tabs 5–7 into a system "More" navigation controller on iPhone, which
    // wrapped Chat/Give/Profile in a nav bar (the stray ‹ + "More" screen) and blocked
    // their full-bleed headers. Rendering the selected tab directly avoids all of it.
    var body: some View {
        ZStack {
            ForEach(AppTab.allCases, id: \.self) { t in
                if loaded.contains(t) {
                    tabView(t)
                        .opacity(t == tabs.selected ? 1 : 0)
                        .allowsHitTesting(t == tabs.selected)
                        .accessibilityHidden(t != tabs.selected)
                }
            }
        }
        .id(textScale)
        // Cream status-bar stripe. The window's status-bar glyphs render DARK (light
        // scheme — reliable across devices, unlike forcing white which came out black
        // on some phones), and we paint the top safe-area band in warm paper so the
        // phone's time/wifi/battery stay legible on cream instead of dark-on-navy.
        // Hidden clear view flips only the status bar; content keeps its own colors.
        .background(Color.clear.preferredColorScheme(.light))
        .overlay(alignment: .top) {
            Nuru.paper
                .frame(maxWidth: .infinity)
                .frame(height: Self.safeAreaTop)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .top) { SyncStatusBanner(sync: sync) }
        .overlay(alignment: .bottom) {
            NuruTabBar(selection: $tabs.selected).ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: tabs.selected) { _, t in loaded.insert(t) }
    }

    // Type-ERASED per tab (AnyView): otherwise RootView.body's type embeds all
    // seven tab view types (HomeView, PathwayView, …) in one _ConditionalContent.
    // That combined type's mangled name is resolved even on the login path (it's a
    // branch of the app's root Group), and it's large enough to overflow the Swift
    // metadata demangler's stack ON DEVICE → EXC_BAD_ACCESS at launch. AnyView
    // keeps RootView's type tiny; each tab's own type is only resolved when it
    // actually renders.
    private func tabView(_ t: AppTab) -> AnyView {
        switch t {
        case .home:    return AnyView(HomeView())
        case .pathway: return AnyView(PathwayView())
        case .plans:   return AnyView(PlansTab())
        case .events:  return AnyView(EventsView())
        case .chat:    return AnyView(ChatView())
        case .give:    return AnyView(GivingView())
        case .profile: return AnyView(ProfileView())
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
        // .nuruDestinations() MUST be inside the stack — applied to the stack from
        // outside, SwiftUI never registers the destinations and plan taps do nothing.
        NavigationStack { ReadingPlansView().nuruDestinations() }
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
