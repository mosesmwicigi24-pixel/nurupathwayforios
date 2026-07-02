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
    /// Full-screen conversation surfaces (chat threads) hide the tab bar so the
    /// composer owns the bottom edge — set on appear, cleared on disappear.
    @Published var chromeHidden = false
    /// True while Home's ON AIR bar is on screen — the island radio pill yields
    /// to it (one radio surface at a time; scroll the bar away and the pill
    /// slides into the notch, Apple-Music style).
    @Published var onAirBarVisible = false
}

struct RootView: View {
    @EnvironmentObject private var tabs: TabRouter
    // Tabs that have been opened at least once — kept alive so their state (scroll,
    // loaded data) survives switching, without loading all seven on launch.
    @State private var loaded: Set<AppTab> = [AppTab.initialTab]
    @EnvironmentObject private var sync: SyncCoordinator
    @AppStorage(Nuru.textScaleKey) private var textScale: Double = 1.0
    @Environment(\.scenePhase) private var scenePhase
    // The app-wide station — drives the floating island pill on every tab.
    @ObservedObject private var radio = RadioCenter.shared
    @State private var radioOpen = false

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
        // Nuru Radio island — while the station is tuned, the black capsule
        // WRAPS the phone's Dynamic Island (wings around the hardware cutout,
        // Apple-Music style) on every tab. On Home it appears only once the
        // ON AIR bar scrolls out of view — one radio surface at a time. When
        // the app backgrounds/locks, the REAL island takes over via Now Playing.
        .overlay(alignment: .top) {
            if radio.program != nil && !radioOpen
                && !(tabs.selected == .home && tabs.onAirBarVisible) {
                VStack(spacing: 0) {
                    RadioMiniPlayer { radioOpen = true }
                        .padding(.top, RadioMiniPlayer.dockTop)
                    Spacer(minLength: 0)
                }
                .ignoresSafeArea(edges: .top)
                .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: radio.program == nil)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: tabs.onAirBarVisible)
        .fullScreenCover(isPresented: $radioOpen) { RadioPlayerView() }
        .overlay(alignment: .bottom) {
            if !tabs.chromeHidden {
                NuruTabBar(selection: $tabs.selected)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: tabs.chromeHidden)
        .onChange(of: tabs.selected) { _, t in
            loaded.insert(t)
            // Screen telemetry (POST /me/activity/screens) — silent by contract.
            ScreenTracker.record(screen: t.label.lowercased())
        }
        .onAppear { ScreenTracker.record(screen: tabs.selected.label.lowercased()) }
        .onChange(of: scenePhase) { _, p in
            if p == .background { ScreenTracker.appDidEnterBackground() }
        }
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
        // The animation/transition pair lives OUTSIDE the `if let` — attached to
        // the conditional content itself they never ran, so the pill used to pop
        // in/out instead of sliding.
        ZStack(alignment: .top) {
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
            }
        }
        .animation(.easeInOut(duration: 0.25), value: message)
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
    /// The gold indicator is ONE shared capsule that springs between tabs
    /// (matched geometry) instead of blinking out of one slot and into another.
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases, id: \.self) { t in
                let focused = selection == t
                Button {
                    // Re-taps on the current tab are a no-op — no haptic, no bounce.
                    guard selection != t else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = t }
                } label: {
                    VStack(spacing: 2) {
                        Icon(t.icon, size: 21, color: focused ? Nuru.gold : Nuru.onNavyFaint)
                            // One subtle bounce on arrival: each selection change runs
                            // the phase cycle once, and only the newly-focused icon
                            // actually scales (others stay at 1).
                            .phaseAnimator([false, true], trigger: selection) { icon, bouncing in
                                icon.scaleEffect(bouncing && focused && !reduceMotion ? 1.12 : 1)
                            } animation: { _ in .spring(response: 0.26, dampingFraction: 0.55) }
                        Text(t.label).font(.inter(10.5, .medium)).foregroundStyle(focused ? Nuru.gold : Nuru.onNavyFaint)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .overlay(alignment: .top) {
                        if focused {
                            Capsule().fill(Nuru.gold).frame(width: 28, height: 3).offset(y: -3)
                                .matchedGeometryEffect(id: "nuru-tab-indicator", in: indicator)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(focused ? [.isSelected] : [])
            }
        }
        .padding(.top, 6)
        .padding(.bottom, Self.safeBottom)
        .background(Nuru.navy)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.10)).frame(height: 1) }
    }

    /// Bottom clearance: tuck the labels close to the home indicator — the
    /// indicator overlays content harmlessly, so we reclaim most of that inset
    /// instead of stacking a full 34pt of dead navy under the labels.
    static var safeBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let inset = scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
        return inset > 0 ? max(inset - 16, 10) : Nuru.S.md
    }
}

// ProfileView (full Account screen) lives in Features/Profile/ProfileView.swift.
