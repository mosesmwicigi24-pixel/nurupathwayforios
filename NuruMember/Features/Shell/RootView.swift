// The signed-in shell — the native port of navigation/RootNavigator.tsx +
// BottomTabBar.tsx. Nuru Live L4 (docs/LIVE_STREAMING.md) restructured the bar
// from seven destinations down to Home · Pathway · Plans · You · Live: "You"
// folds Events + Chat + Profile together (the owner's spec), and — since the
// owner's bar has no seat for Give either — Give rides along inside "You" too
// rather than losing its front door. "Live" only appears for members holding
// the `live:go` permission (LiveBroadcastEligibility); everyone else keeps a
// four-tab bar and watches through Home / the cell card as before. A custom
// navy bar draws a gold active icon + label + top indicator dot; the system
// tab bar is hidden so we can match the design exactly (and so a conditional
// 5th/4th tab doesn't fight a stock TabView's own layout).
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, pathway, plans, you, live

    /// Debug-only: lets a screenshot script open the app on a chosen tab via the
    /// NURU_TAB launch env var (e.g. SIMCTL_CHILD_NURU_TAB=pathway). Defaults home.
    static var initialTab: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["NURU_TAB"] {
        case "pathway": return .pathway
        case "plans": return .plans
        case "you": return .you
        case "live": return .live
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
        case .you: return "You"
        case .live: return "Live"
        }
    }
    var icon: Lucide {
        switch self {
        case .home: return .house
        case .pathway: return .bookOpen
        case .plans: return .bookMarked
        case .you: return .user
        case .live: return .camera
        }
    }
}

/// The four screens folded into the "You" tab (L4). Chat is the default/
/// "heart" segment per the owner's spec; Events, Give and Profile are peers
/// reached through the same capsule segmented control Chat already uses
/// internally (My Space / Chat / My Discipler / My Pastor) — just one level up.
enum YouSegment: Hashable, CaseIterable {
    case chat, events, give, profile

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .events: return "Events"
        case .give: return "Give"
        case .profile: return "Profile"
        }
    }
    var icon: Lucide {
        switch self {
        case .chat: return .messageCircle
        case .events: return .calendarDays
        case .give: return .handHeart
        case .profile: return .user
        }
    }
}

/// A cross-tab deep link into the Plans tab — the catalogue root, one plan,
/// or the "Read with a Friend" hub (a plan_group_* notification without a
/// redeemable invite token — the group itself is one tap away from the hub).
enum PlanDeepLink: Hashable { case catalogue; case plan(ReadingPlanRow); case readWithFriendHub }

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
    /// A "Read with a Friend" invite token to open on the Plans stack — set by
    /// a nuru://join/{token} deep link (RootView.onOpenURL) or a
    /// plan_group_invite_received notification tap.
    @Published var readingInviteToken: String?
    /// Which segment of the "You" tab a cross-tab link (notification tap,
    /// widget URL, a Home "See events" / "Give now" button) should land on.
    /// YouTabView consumes this (pushes its own segment state) and clears it.
    @Published var youSegment: YouSegment?

    func openPathway(_ r: PathwayRoute) { pathwayLink = r; selected = .pathway }
    func openPlans(_ l: PlanDeepLink)   { planLink = l;    selected = .plans }
    func openEvent(_ o: CalendarOccurrence) { eventLink = o; openYou(.events) }
    func openAnnouncement(_ id: String) { announcementLink = id; selected = .home }
    func openReadingInvite(_ token: String) { readingInviteToken = token; selected = .plans }
    func openYou(_ seg: YouSegment) { youSegment = seg; selected = .you }
}

struct RootView: View {
    @EnvironmentObject private var tabs: TabRouter
    @EnvironmentObject private var auth: AuthStore
    // Tabs that have been opened at least once — kept alive so their state (scroll,
    // loaded data) survives switching, without loading all five on launch.
    @State private var loaded: Set<AppTab> = [AppTab.initialTab]
    @EnvironmentObject private var sync: SyncCoordinator
    @AppStorage(Nuru.textScaleKey) private var textScale: Double = 1.0
    @Environment(\.scenePhase) private var scenePhase
    // The app-wide station — drives the floating island pill on every tab.
    @ObservedObject private var radio = RadioCenter.shared
    @State private var radioOpen = false
    // Nuru Live "Broadcast Studio" — the app-wide broadcast engine. Leaving
    // the broadcast screen (any tab, any navigation) never stops publishing;
    // RootView owns the ONE full-screen presentation (mirroring the radio
    // player and the live viewer below) plus the floating "still live"
    // island shown everywhere else. See BroadcastCenter.swift.
    @ObservedObject private var broadcast = BroadcastCenter.shared
    // Nuru Live discovery — "invite loudly, never hijack": the app-wide LIVE
    // bar (every tab but Home) and the ONE place a notification tap or bar tap
    // presents the full-screen player from outside Home's own surfaces.
    @ObservedObject private var liveDiscovery = LiveDiscoveryCenter.shared
    // Location-first onboarding: invite ONCE after first login; refresh silently
    // on every open for members already sharing (Profile keeps the off switch).
    @AppStorage("nuru.locationInviteShown") private var locationInviteShown = false
    @AppStorage("nuru.privacy.shareLocation") private var shareLocation = false
    @State private var showLocationInvite = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotionForLiveBar

    /// The app-wide LIVE bar shows on every tab except Home (which has its own
    /// banner + mini-window) while a watchable stream exists and the player it
    /// would open isn't already the thing on screen.
    private var showAppLiveBar: Bool {
        !liveDiscovery.streams.isEmpty && tabs.selected != .home && liveDiscovery.requestedItem == nil
    }

    /// Height of the top safe-area inset (status-bar / Dynamic Island band) so the
    /// cream stripe covers exactly that region. Falls back to 59 (Dynamic Island).
    private static var safeAreaTop: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 59
    }

    /// The tabs actually shown on the bar: "Live" only for a member whose /me
    /// permissions include `live:go` (client-side advisory gate — the server
    /// re-checks on every write regardless, same rule ModuleView/GoLiveSetupSheet
    /// already use). Everyone else gets the four-tab bar the owner's spec shows
    /// for non-broadcasters.
    private var visibleTabs: [AppTab] {
        AppTab.allCases.filter { $0 != .live || LiveBroadcastEligibility.canGoLive(auth.profile) }
    }

    // A hand-rolled tab container instead of TabView: a stock TabView with this
    // many tabs collapses the tail into a system "More" navigation controller on
    // iPhone, which wrapped Chat/Give/Profile in a nav bar (the stray ‹ + "More"
    // screen) and blocked their full-bleed headers. Rendering the selected tab
    // directly avoids all of it (and lets the tab COUNT itself vary by profile).
    var body: some View {
        ZStack {
            ForEach(visibleTabs, id: \.self) { t in
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
        // Nuru Live "Broadcast Studio" — the ONE full-screen broadcast
        // presentation, bound to BroadcastCenter rather than any per-screen
        // `@State`, so minimizing from ANY tab and restoring from the island
        // always reattaches to the SAME controller instead of losing it.
        .fullScreenCover(isPresented: Binding(
            get: { broadcast.controller != nil && broadcast.presented },
            set: { newValue in if !newValue { broadcast.presented = false } }
        )) {
            if let c = broadcast.controller { GoLiveBroadcastView(controller: c) }
        }
        // The floating "you're still live" island — every tab, while a
        // broadcast is active and its full-screen surface is minimized.
        // Docked below the radio pill's row so the rare "listening to Radio
        // while broadcasting" overlap never collides.
        .overlay(alignment: .top) {
            if let c = broadcast.controller, !broadcast.presented {
                BroadcastMiniPlayer(controller: c) { broadcast.restore() }
                    .padding(.top, RadioMiniPlayer.dockTop + RadioMiniPlayer.dockHeight + 10)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.75), value: broadcast.controller != nil)
        .animation(.easeInOut(duration: 0.2), value: broadcast.presented)
        .overlay(alignment: .bottom) {
            if !tabs.chromeHidden {
                VStack(spacing: 0) {
                    // App-wide LIVE bar — every tab EXCEPT Home (which has its
                    // own banner + mini-window), and never while the player
                    // this bar itself would open is already on screen.
                    if showAppLiveBar, let stream = liveDiscovery.newestWatchable {
                        AppLiveBar(stream: stream) {
                            liveDiscovery.markSeen(stream.streamId)
                            liveDiscovery.requestedItem = .live(stream)
                        }
                        .transition(reduceMotionForLiveBar ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    }
                    NuruTabBar(selection: $tabs.selected, tabs: visibleTabs)
                }
                .ignoresSafeArea(edges: .bottom)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.22), value: tabs.chromeHidden)
        .animation(.easeInOut(duration: 0.25), value: showAppLiveBar)
        // The ONE place a discovery surface (the bar above, or a routed
        // `live_stream_started` notification tap below) presents the full
        // player from OUTSIDE Home's own banner/mini-window taps.
        .fullScreenCover(item: Binding(
            get: { liveDiscovery.requestedItem },
            set: { liveDiscovery.requestedItem = $0 }
        )) { item in
            // Replays default to the item's own scope (church → church replays,
            // a cell item → that cell's) — same rule every other player
            // presentation follows (Home banner, cell card, LiveReplaysView).
            let source = liveDiscovery.streams.first { $0.streamId == item.id }
            // `.id(item.id)` — FLICKER GUARD. This is the one call site that
            // actually hits the bug: a second `live_stream_started` push can
            // set `liveDiscovery.requestedItem` to a NEW stream while this
            // cover is already presenting a DIFFERENT one (see the handler
            // below, and the AppLiveBar tap) — the binding goes non-nil to
            // non-nil, never back through nil. `fullScreenCover(item:)` does
            // NOT dismiss/re-present for that transition; it keeps the same
            // presented view and just re-invokes this closure. Without an
            // explicit `.id`, `LiveViewerPlayerView` would keep its existing
            // view identity across that call — its `@StateObject` player and
            // pulse controller would NOT reinitialize, `.task { controller
            // .start(...) }` would NOT rerun (plain `.task` only fires on
            // identity change), and the viewer would silently keep showing
            // the PREVIOUS stream's frames under the new stream's chrome.
            // `.id(item.id)` forces SwiftUI to treat a different stream_id as
            // a brand-new view, tearing down the old player/pulse controller
            // and constructing fresh ones against a freshly-fetched item.
            LiveViewerPlayerView(item: item, replaysScope: source?.scope, replaysCellId: source?.cellId)
                .id(item.id)
        }
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
            let inviteToken = info["inviteToken"] as? String ?? ""
            if !announcementId.isEmpty {
                tabs.openAnnouncement(announcementId)
            } else if !moduleId.isEmpty {
                tabs.openPathway(.module(moduleId))
            } else if template.hasPrefix("level"), level > 0 {
                tabs.openPathway(.level(level))
            } else if template.hasPrefix("event") {
                tabs.openYou(.events)
            } else if template.hasPrefix("giving") || template.hasPrefix("payment") {
                tabs.openYou(.give)
            } else if template.hasPrefix("badge") || template.hasPrefix("certificate") {
                tabs.openYou(.profile)
            } else if template.hasPrefix("reflection") {
                tabs.selected = .pathway
            } else if template == "plan_group_invite_received", !inviteToken.isEmpty {
                // Read with a Friend — same surface a nuru://join/{token} deep
                // link opens (see onOpenURL below).
                tabs.openReadingInvite(inviteToken)
            } else if template.hasPrefix("plan_group") {
                // Progress/joined pings without a token to redeem — land on
                // the hub; the specific group is one tap away from there.
                tabs.openPlans(.readWithFriendHub)
            } else if template.hasPrefix("live") {
                // A tapped `live_stream_started` push must land IN THE PLAYER —
                // re-check /live/now (the stream may have already ended by the
                // time the tap lands) and open the newest watchable stream;
                // fall back to Home (which shows its own banner/mini-window
                // if something else is live) when there's nothing left to join.
                Task {
                    await liveDiscovery.refresh()
                    if let stream = liveDiscovery.newestWatchable {
                        liveDiscovery.markSeen(stream.streamId)
                        liveDiscovery.requestedItem = .live(stream)
                    } else {
                        tabs.selected = .home
                    }
                }
            } else {
                NotificationCenter.default.post(name: .nuruOpenNotifications, object: nil)
            }
        }
        // Home-screen widgets deep-link with nuru:// URLs — route to the tab
        // (or open the radio player) the widget promises. Also the
        // Read-with-a-Friend deep link: nuru://join/{token} (the SAME scheme
        // the public /join/{token} landing page attempts before falling back
        // to the store — docs/READING_SOCIAL_PLAN.md §5).
        .onOpenURL { url in
            let host = url.host ?? url.absoluteString.replacingOccurrences(of: "nuru://", with: "")
            switch host {
            case "pathway": tabs.selected = .pathway
            case "plans":   tabs.selected = .plans
            // Pre-L4 widget/shortcut hosts — still land on the right content,
            // now inside the You tab's matching segment (Give/Events/Chat no
            // longer own a bottom-bar slot).
            case "chat":    tabs.openYou(.chat)
            case "events":  tabs.openYou(.events)
            case "give":    tabs.openYou(.give)
            case "you":     tabs.selected = .you
            case "live":
                // Only navigate if this member actually has a Live tab —
                // otherwise silently fall through to the default (Home) rather
                // than selecting a tab that isn't on the bar.
                if LiveBroadcastEligibility.canGoLive(auth.profile) { tabs.selected = .live }
            case "radio":   NotificationCenter.default.post(name: .nuruOpenRadio, object: nil)
            case "join":
                let token = url.pathComponents.last(where: { $0 != "/" }) ?? url.lastPathComponent
                if !token.isEmpty { tabs.openReadingInvite(token) }
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
        .task {
            if !locationInviteShown && !shareLocation {
                try? await Task.sleep(nanoseconds: 1_200_000_000) // let Home land first
                locationInviteShown = true
                showLocationInvite = true
            } else {
                await LocationOnboarding.refreshIfSharing()
            }
        }
        .sheet(isPresented: $showLocationInvite) { LocationInviteSheet() }
        // The You tab's icon badge (and its Chat segment chip) must be right
        // even for a member who hasn't opened the You tab yet this session —
        // ChatInboxViewModel itself keeps it current once Chat has loaded, but
        // this seeds/refreshes it in the background the same way HomeView
        // polls the radio ON AIR state.
        .task {
            while !Task.isCancelled {
                await ChatBadge.shared.refresh()
                // Nuru Live discovery — piggybacks this same 60s cadence
                // (gentle, foreground-only — this `.task` is cancelled the
                // instant RootView leaves the screen) so the app-wide LIVE bar
                // and a routed notification tap both see fresh /live/now data
                // without a second polling loop.
                await liveDiscovery.refresh()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
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
        case .you:     return AnyView(YouTabView())
        case .live:    return AnyView(NuruLiveTabView())
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
                switch link {
                case .plan(let row): path.append(row)
                case .readWithFriendHub: path.append(GrowDestination.readWithFriendHub)
                case .catalogue: break
                }
                DispatchQueue.main.async { tabs.planLink = nil }
            }
            // A nuru://join/{token} deep link or a plan_group_invite_received
            // notification tap — push the invite preview with the catalogue
            // (and the hub, if already open) as the back stop.
            .onReceive(tabs.$readingInviteToken) { token in
                guard let token else { return }
                path = NavigationPath()
                path.append(GrowDestination.readWithFriendHub)
                path.append(ReadingInviteRef(token: token))
                DispatchQueue.main.async { tabs.readingInviteToken = nil }
            }
    }
}

/// Custom bottom bar: navy, gold active (icon + label + top dot), dim inactive.
private struct NuruTabBar: View {
    @Binding var selection: AppTab
    /// The tabs to render, in order — RootView passes the profile-filtered
    /// list (Live only for a `live:go` holder) so this bar never offers a tab
    /// that doesn't exist for the signed-in member.
    let tabs: [AppTab]
    /// The dms-unread + pending-connection-request count — surfaced on the
    /// You tab's icon exactly like the Chat segment's own chip (ChatBadge is
    /// the one shared source both read from).
    @ObservedObject private var chatBadge = ChatBadge.shared
    /// The gold indicator is ONE shared capsule that springs between tabs
    /// (matched geometry) instead of blinking out of one slot and into another.
    @Namespace private var indicator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { t in
                let focused = selection == t
                Button {
                    // Re-taps on the current tab are a no-op — no haptic, no bounce.
                    guard selection != t else { return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = t }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Icon(t.icon, size: 21, color: focused ? Nuru.navy : Self.inactive)
                                // One subtle bounce on arrival: each selection change runs
                                // the phase cycle once, and only the newly-focused icon
                                // actually scales (others stay at 1).
                                .phaseAnimator([false, true], trigger: selection) { icon, bouncing in
                                    icon.scaleEffect(bouncing && focused && !reduceMotion ? 1.12 : 1)
                                } animation: { _ in .spring(response: 0.26, dampingFraction: 0.55) }
                            if t == .you, chatBadge.count > 0 { badgeDot(chatBadge.count) }
                        }
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

    /// Small red count pill — capped "9+" — top-trailing of the You icon.
    private func badgeDot(_ n: Int) -> some View {
        Text(n > 9 ? "9+" : "\(n)")
            .font(.inter(9, .bold)).foregroundStyle(.white)
            .padding(.horizontal, n > 9 ? 4 : 0)
            .frame(minWidth: 15, minHeight: 15)
            .background(Color(hex: 0xDC2626), in: Capsule())
            .overlay(Capsule().stroke(Nuru.paper, lineWidth: 1.5))
            .offset(x: 11, y: -4)
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
