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

/// A cross-tab deep link into the Plans tab — the catalogue root or one plan.
enum PlanDeepLink: Hashable { case catalogue; case plan(ReadingPlanRow) }

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

    // Cross-tab deep links. Content always opens INSIDE the tab that owns it —
    // a Pathway module from a Home nudge lands on the Pathway tab, a plan from
    // the resume banner lands on Plans, an event card lands on Events — so the
    // bottom bar always tells the truth about where the member is. The owning
    // tab's root consumes its link (pushes it on its own stack) and clears it;
    // links survive the tab being lazily created (a @Published replays the
    // pending value to a fresh subscriber).
    @Published var pathwayLink: PathwayRoute?
    @Published var planLink: PlanDeepLink?
    @Published var eventLink: CalendarOccurrence?
    /// Announcement to open on the Home stack (from a tapped iOS notification).
    @Published var announcementLink: String?

    func openPathway(_ r: PathwayRoute) { pathwayLink = r; selected = .pathway }
    func openPlans(_ l: PlanDeepLink)   { planLink = l;    selected = .plans }
    func openEvent(_ o: CalendarOccurrence) { eventLink = o; selected = .events }
    func openAnnouncement(_ id: String) { announcementLink = id; selected = .home }
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
        // The ONE radio presentation source — Home's radio button and the ON AIR
        // bar post this instead of presenting their own cover (two covers over
        // the same window fought and produced a mis-sized, shifted player).
        .onReceive(NotificationCenter.default.publisher(for: .nuruOpenRadio)) { _ in
            radioOpen = true
        }
        .overlay(alignment: .bottom) {
            if !tabs.chromeHidden {
                NuruTabBar(selection: $tabs.selected)
                    .ignoresSafeArea(edges: .bottom)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: tabs.chromeHidden)
        // Celebration layer — server-milestone confetti cards + gold banners
        // (rhythm complete, streak marks, new badges, prayer posted, gift
        // confirmed). Mounted ONCE here, above every tab and the tab bar.
        .overlay { CelebrationHost() }
        // A tapped iOS notification lands on its EXACT target: module/level →
        // Pathway tab, announcement → Home stack, event/giving/badge families →
        // their tab. Anything unroutable opens the in-app inbox as before.
        .onReceive(NotificationCenter.default.publisher(for: .nuruNotificationTap)) { note in
            let info = note.userInfo ?? [:]
            let template = info["template"] as? String ?? ""
            let announcementId = info["announcementId"] as? String ?? ""
            let moduleId = info["moduleId"] as? String ?? ""
            let level = info["levelNumber"] as? Int ?? 0
            if !announcementId.isEmpty {
                tabs.openAnnouncement(announcementId)
            } else if !moduleId.isEmpty {
                tabs.openPathway(.module(moduleId))
            } else if template.hasPrefix("level"), level > 0 {
                tabs.openPathway(.level(level))
            } else if template.hasPrefix("event") {
                tabs.selected = .events
            } else if template.hasPrefix("giving") || template.hasPrefix("payment") {
                tabs.selected = .give
            } else if template.hasPrefix("badge") || template.hasPrefix("certificate") {
                tabs.selected = .profile
            } else if template.hasPrefix("reflection") {
                tabs.selected = .pathway
            } else {
                NotificationCenter.default.post(name: .nuruOpenNotifications, object: nil)
            }
        }
        // Home-screen widgets deep-link with nuru:// URLs — route to the tab
        // (or open the radio player) the widget promises.
        .onOpenURL { url in
            switch url.host ?? url.absoluteString.replacingOccurrences(of: "nuru://", with: "") {
            case "pathway": tabs.selected = .pathway
            case "plans":   tabs.selected = .plans
            case "chat":    tabs.selected = .chat
            case "events":  tabs.selected = .events
            case "give":    tabs.selected = .give
            case "radio":   NotificationCenter.default.post(name: .nuruOpenRadio, object: nil)
            default:        tabs.selected = .home
            }
        }
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
    @EnvironmentObject private var tabs: TabRouter
    @State private var path = NavigationPath()

    var body: some View {
        // .nuruDestinations() MUST be inside the stack — applied to the stack from
        // outside, SwiftUI never registers the destinations and plan taps do nothing.
        NavigationStack(path: $path) { ReadingPlansView().nuruDestinations() }
            // Cross-tab deep link (Home's resume banner / plan mini / Grow tile):
            // land exactly on the plan with the catalogue as the back stop.
            .onReceive(tabs.$planLink) { link in
                guard let link else { return }
                path = NavigationPath()
                if case .plan(let row) = link { path.append(row) }
                DispatchQueue.main.async { tabs.planLink = nil }
            }
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
                    VStack(spacing: 3) {
                        Icon(t.icon, size: 21, color: focused ? Nuru.navy : Self.inactive)
                            // One subtle bounce on arrival: each selection change runs
                            // the phase cycle once, and only the newly-focused icon
                            // actually scales (others stay at 1).
                            .phaseAnimator([false, true], trigger: selection) { icon, bouncing in
                                icon.scaleEffect(bouncing && focused && !reduceMotion ? 1.12 : 1)
                            } animation: { _ in .spring(response: 0.26, dampingFraction: 0.55) }
                        Text(t.label).font(.inter(10.5, .medium)).foregroundStyle(focused ? Nuru.navy : Self.inactive)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        // The active tab sits on a warm cream pill (matches the
                        // member app) that slides between tabs.
                        if focused {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Self.pill)
                                .padding(.horizontal, 10)
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
        .background(Nuru.paper)
        .overlay(alignment: .top) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // Cream tab-bar palette (member-app look): navy active, muted-gray inactive,
    // warm gold-tinted cream pill behind the selected tab.
    private static let inactive = Color(hex: 0x7E8894)
    private static let pill = Nuru.gold.opacity(0.16)

    /// Bottom clearance: labels sit flush against the home indicator — it
    /// overlays content harmlessly, so we reclaim essentially the whole inset
    /// and leave no dead navy under the names.
    static var safeBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        let inset = scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
        return inset > 0 ? 2 : Nuru.S.xs
    }
}

// ProfileView (full Account screen) lives in Features/Profile/ProfileView.swift.
