// The signed-in shell — the native port of navigation/RootNavigator.tsx +
// BottomTabBar.tsx. The Partners programme (pathway docs/PARTNERS_PROGRAMME.md
// §0, owner-approved 2026-09-23) set the bar at SIX destinations: Home ·
// Pathway · Plans · Events · Give · You. Events and Give each own a seat
// again; "You" keeps Community · Departments · Profile · Settings. The old
// broadcaster-only "Live" tab is gone — Go Live / return-to-broadcast / My
// Broadcasts now sit at the top of Events as a "Broadcast" card, still only
// for members holding `live:go` (LiveBroadcastEligibility). A custom cream bar
// draws a navy active icon + label on a gold-tinted pill; the system tab bar
// is hidden so we can match the design exactly.
import Combine
import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case home, pathway, plans, events, give, you

    /// Debug-only: lets a screenshot script open the app on a chosen tab via the
    /// NURU_TAB launch env var (e.g. SIMCTL_CHILD_NURU_TAB=pathway). Defaults home.
    static var initialTab: AppTab {
        #if DEBUG
        switch ProcessInfo.processInfo.environment["NURU_TAB"] {
        case "pathway": return .pathway
        case "plans": return .plans
        case "events": return .events
        case "give": return .give
        case "you": return .you
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
        case .give: return "Give"
        case .you: return "You"
        }
    }
    var icon: Lucide {
        switch self {
        case .home: return .house
        case .pathway: return .bookOpen
        case .plans: return .bookMarked
        case .events: return .calendar
        case .give: return .handHeart
        case .you: return .user
        }
    }
}

/// The four screens folded into the "You" tab (PARTNERS_PROGRAMME §0):
/// Community (the default / "heart" segment — the case stays `.chat` so the
/// "chat" deep link keeps resolving), Departments (§4 — a placeholder until
/// phase 3), Profile, and Settings (the existing screen promoted from behind
/// the Profile gear; the gear route still works). Reached through the same
/// capsule segmented control Chat uses internally, one level up.
enum YouSegment: Hashable, CaseIterable, CapsuleSegment {
    case chat, departments, profile, settings

    var label: String {
        switch self {
        case .chat: return "Community"
        case .departments: return "Departments"
        case .profile: return "Profile"
        case .settings: return "Settings"
        }
    }
    var icon: Lucide {
        switch self {
        case .chat: return .users
        case .departments: return .heartHandshake
        case .profile: return .user
        case .settings: return .settings
        }
    }
}

/// The Give tab's two segments (PARTNERS_PROGRAMME §0): the giving screen
/// itself, and the Partners programme portal (§2).
enum GiveSegment: Hashable, CaseIterable, CapsuleSegment {
    case give, partners

    var label: String {
        switch self {
        case .give: return "Give"
        case .partners: return "Partners"
        }
    }
    var icon: Lucide {
        switch self {
        case .give: return .handHeart
        case .partners: return .heartHandshake
        }
    }
}

/// A gift the Give screen should open pre-filled — Partners' "Pay now" carries
/// the pledge's fund + the amount still due, and the pledge id rides the intent
/// body so the server attributes the gift (§1 "Pledge payment" rule a).
struct GivePreset: Equatable {
    var fund: String?
    var amountMinor: Int?
    var pledgeId: String?
    /// A department need (PARTNERS_PROGRAMME §4) — "Give to this need" sets
    /// it; it rides the intent body as `need_id` so the server attributes
    /// the gift to the need's campaign.
    var needId: String? = nil
    /// The pledge's name (pledge names contract), carried so Give's "PAYING
    /// YOUR PLEDGE" card can say WHICH pledge before the server has answered.
    /// Never sent on the wire.
    var pledgeTitle: String? = nil
    /// The promise in one line ("KSh 1,000 monthly · due on the 25th") for
    /// that card. Display only.
    var pledgeAmountLine: String? = nil
    /// Where the pledge's money goes (`pays_to`) — "Goes to the <name> fund".
    /// Display only: the SERVER routes pledge money, never the client.
    var paysTo: Pledge.FundRef? = nil
    /// A department need's title + one line for Give's "GIVING TO A NEED"
    /// card. Display only.
    var needTitle: String? = nil
    var needLine: String? = nil
    /// The pledge's or need's currency (Giving Cycle 5): it decides the rails
    /// Give offers — a KES promise M-Pesa, a USD one PayPal — and the amount's
    /// money. Nil = shillings.
    var currency: String? = nil
}

/// A gift made away from the Give form that Give's result screen should show
/// (Giving Cycle 9: "Collect it automatically at this pace" on a pledge's
/// page) — the same screen as Give's own "give now", watching the same way.
struct GiveWatch: Equatable {
    enum Outcome: Equatable {
        /// The recurring gift's first prompt went out: watch it.
        case firstPrompt(transactionId: String)
        /// 409 GIFT_IN_PROGRESS: nothing was made, a prompt from a moment ago
        /// is still on the phone — watch that one, as Give does.
        case waiting(transactionId: String, message: String)
        /// The gift stands, but today's prompt could not go out: the server's
        /// reason (nil when it gave none) and when the first prompt comes.
        case scheduled(note: String?, nextRunAt: String)
    }
    let outcome: Outcome
    /// What each prompt asks: "KSh 5,000".
    let amountLabel: String
    /// The pledge it collects.
    let pledgeTitle: String
    var frequency: String = "monthly"
}

/// A cross-tab deep link into the Plans tab — the catalogue root, one plan,
/// that plan's day to read (Home's YOUR WEEK — the plan's page is the back
/// stop), or the "Read with a Friend" hub (a plan_group_* notification without
/// a redeemable invite token — the group itself is one tap away from the hub).
enum PlanDeepLink: Hashable { case catalogue; case plan(ReadingPlanRow); case planDay(ReadingPlanRow); case readWithFriendHub }

private struct ScreenVisibleKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    /// False while a screen is mounted but hidden by a keep-alive container —
    /// another tab (RootView), another You segment (YouTabView), another
    /// Community door (CommunityView). They switch by opacity, so onAppear /
    /// onDisappear never fire; a screen that must know whether the member can
    /// SEE it reads this (ChatThreadView: the open conversation, whose
    /// messages land as a light tap instead of a banner). Each container ANDs
    /// its own choice into its parent's. (Give's segments: giveSegmentVisible.)
    var screenVisible: Bool {
        get { self[ScreenVisibleKey.self] }
        set { self[ScreenVisibleKey.self] = newValue }
    }
}

/// The selected primary tab, hoisted out of RootView so any screen can switch
/// tabs (e.g. Home's "Give now" banner → the Give tab). Injected app-wide.
@MainActor
final class TabRouter: ObservableObject {
    @Published var selected: AppTab = .initialTab
    /// Full-screen surfaces (a chat thread, a plan, a module being read) hide
    /// the tab bar so they own the bottom edge — set on appear, cleared on
    /// disappear or by their tab's root. The bar is hidden only where it was
    /// hidden: on the tab (and, on You, the segment) whose screen hid it
    /// (EXPERIENCE.md §7.2 #11). A notice that switches tabs from an open
    /// thread used to land with no bar at all; now the bar is back on the new
    /// tab, and the thread still owns its edge when the member returns.
    var chromeHidden: Bool {
        get { chromeHiddenIn.contains(chromeScope) }
        set {
            let scope = chromeScope
            guard newValue != chromeHiddenIn.contains(scope) else { return }
            if newValue { chromeHiddenIn.insert(scope) } else { chromeHiddenIn.remove(scope) }
        }
    }
    /// Where a full-screen surface has the bar hidden right now.
    @Published private(set) var chromeHiddenIn: Set<ChromeScope> = []
    /// The You tab's visible segment (YouTabView keeps it current) — on You
    /// the bar belongs to the segment, so a notice landing on Profile isn't
    /// left bar-less by a thread open under Community.
    @Published var youSegmentShown: YouSegment = .chat

    /// A tab, and on You its segment.
    struct ChromeScope: Hashable {
        let tab: AppTab
        let segment: YouSegment?
    }
    private var chromeScope: ChromeScope {
        ChromeScope(tab: selected, segment: selected == .you ? youSegmentShown : nil)
    }
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
    /// widget URL, a Home button) should land on. YouTabView consumes this
    /// (pushes its own segment state) and clears it.
    @Published var youSegment: YouSegment?
    /// Which segment of the "Give" tab a cross-tab link should land on —
    /// Give itself, or the Partners portal (a partner invite's "Become a
    /// partner", a `pledge_*` notification, a "partners" nudge). GiveTabView
    /// consumes and clears it exactly like `youSegment`.
    @Published var giveSegment: GiveSegment?
    /// A pre-filled gift for the Give screen (Partners → "Pay now"). GivingView
    /// consumes it (fund, amount, pledge id) and clears it.
    @Published var givePreset: GivePreset?
    /// A gift to open on the Give screen from a giving notification (Giving
    /// Cycle 3: a failed gift's result, with Try again). GivingView consumes
    /// it and clears it.
    @Published var giveLink: GiveLink?
    /// A gift made on a pledge's page to show on Give's result screen (Giving
    /// Cycle 9). GivingView consumes it and clears it.
    @Published var giveWatch: GiveWatch?
    /// A pledge to open on the Partners segment (Giving Cycle 5: a pledge
    /// notice, a gift that collects a pledge). PartnersView pushes it and
    /// clears it.
    @Published var pledgeLink: String?
    /// A conversation to open on the Chat stack (You → Community → Talk) —
    /// set by a Home "chat_unread" nudge or a Read-with-a-Friend "Sent to
    /// <name> in chat · Open chat" toast. ChatView consumes it (pushes the
    /// thread with the inbox as the back stop) and clears it.
    @Published var conversationLink: String?
    /// A department to open on the Departments stack (You → Departments) —
    /// set by a serve_request_* / department_post / department_need_*
    /// notification tap or Profile's "Serving in" row. DepartmentsView
    /// consumes it (pushes the page with the list as the back stop) and
    /// clears it.
    @Published var departmentLink: String?

    /// A tap on the tab already shown (§7.4 #17): its stack returns to the
    /// root. A subject, not @Published — a re-tap is a moment, never a value
    /// replayed to a stack that mounts later (it would pop a deep link that
    /// had just landed).
    let reselected = PassthroughSubject<AppTab, Never>()
    /// A tap on the tab already shown while its stack is AT its root: the
    /// root scrolls to its top (§7.4 #17 — the walk's B10).
    let rootReselected = PassthroughSubject<AppTab, Never>()

    func openPathway(_ r: PathwayRoute) { pathwayLink = r; selected = .pathway }
    func openPlans(_ l: PlanDeepLink)   { planLink = l;    selected = .plans }
    func openEvent(_ o: CalendarOccurrence) { eventLink = o; openEvents() }
    func openAnnouncement(_ id: String) { announcementLink = id; selected = .home }
    func openReadingInvite(_ token: String) { readingInviteToken = token; selected = .plans }
    func openYou(_ seg: YouSegment) { youSegment = seg; selected = .you }
    func openConversation(_ id: String) { conversationLink = id; openYou(.chat) }
    /// You → Departments → the department page (PARTNERS_PROGRAMME §4).
    func openDepartment(_ id: String) { departmentLink = id; openYou(.departments) }
    /// Events and Give are top-level tabs again (PARTNERS_PROGRAMME §0) — the
    /// old `openYou(.events)` / `openYou(.give)` call sites now land here.
    func openEvents() { selected = .events }
    func openGive() { giveSegment = .give; selected = .give }
    /// Give, pre-filled (Partners "Pay now" / a due item).
    func openGive(preset: GivePreset) { givePreset = preset; openGive() }
    /// Give, opening one gift (a giving notification's target).
    func openGive(link: GiveLink) { giveLink = link; openGive() }
    /// Give's result screen for a gift made elsewhere (a pledge's page).
    func openGive(watch: GiveWatch) { giveWatch = watch; openGive() }
    /// Partners, opening one pledge.
    func openPledge(_ id: String) { pledgeLink = id; openPartners() }
    func openPartners() { giveSegment = .partners; selected = .give }
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

    /// The six tabs on the bar — the same for every member. The broadcaster-
    /// only surface (Go Live / My Broadcasts) is a card at the top of Events,
    /// gated there by LiveBroadcastEligibility rather than by a tab's existence.
    private var visibleTabs: [AppTab] { AppTab.allCases }

    // A hand-rolled tab container instead of TabView: a stock TabView with this
    // many tabs collapses the tail into a system "More" navigation controller on
    // iPhone, which wrapped the tail tabs in a nav bar (the stray ‹ + "More"
    // screen) and blocked their full-bleed headers. Rendering the selected tab
    // directly avoids all of it.
    var body: some View {
        ZStack {
            ForEach(visibleTabs, id: \.self) { t in
                if loaded.contains(t) {
                    tabView(t)
                        .environment(\.screenVisible, t == tabs.selected)
                        .opacity(t == tabs.selected ? 1 : 0)
                        .allowsHitTesting(t == tabs.selected)
                        .accessibilityHidden(t != tabs.selected)
                }
            }
        }
        // The default font follows the member's text size (rebuilt with it).
        .nuruDefaultFont()
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
                    NuruTabBar(selection: $tabs.selected, tabs: visibleTabs) { tabs.reselected.send($0) }
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
        // A Live notice tapped once its stream is over — a banner or an inbox
        // row alike (NoticeRouter): "This Live has ended", calm, Go back.
        .fullScreenCover(item: Binding(
            get: { liveDiscovery.endedNotice },
            set: { liveDiscovery.endedNotice = $0 }
        )) { notice in
            LiveEndedView(notice: notice) { liveDiscovery.endedNotice = nil }
        }
        // Celebration layer — server-milestone confetti cards + gold banners
        // (rhythm complete, streak marks, new badges, prayer posted; a gift's
        // one celebration is its own success screen, §7.4 #14). Mounted ONCE
        // here, above every tab and the tab bar.
        .overlay { CelebrationHost() }
        // A tapped iOS notification lands on its EXACT target — the same one
        // its row in the inbox opens (NoticeRouter, EXPERIENCE.md §7.2 #3):
        // a pledge, a gift, an announcement, a module or level, a department,
        // Read with a Friend, the Live player ("This Live has ended" once
        // over). A notice with nowhere to go opens the in-app inbox.
        .onReceive(NotificationCenter.default.publisher(for: .nuruNotificationTap)) { note in
            let info = note.userInfo ?? [:]
            // A Live guest invite RINGS (2026-09-28). Tapped inside its 30 s,
            // it opens the same ringing screen the foreground gets; after
            // that, the router opens ITS stream — and says "This Live has
            // ended" once it's over (§7.3), where the player's own invite
            // card can still answer it.
            if NoticeTarget(userInfo: info).template == "live_guest_invite",
               let invite = IncomingLiveInvite(push: NuruPush(userInfo: info)),
               IncomingLiveInviteCenter.shared.ring(invite) {
                return
            }
            let route = NoticeRouter.route(NoticeTarget(userInfo: info))
            if !NoticeRouter.open(route, tabs: tabs) {
                NotificationCenter.default.post(name: .nuruOpenNotifications, object: nil)
            }
        }
        // Home-screen widgets deep-link with nuru:// URLs — route to the tab
        // (or open the radio player) the widget promises. Also the
        // Read-with-a-Friend deep link: nuru://join/{token} (the SAME scheme
        // the public /join/{token} landing page attempts before falling back
        // to the store — docs/READING_SOCIAL_PLAN.md §5).
        .onOpenURL { url in
            // Read with a Friend — nuru://join/{token} today, and the public
            // https://pathway.nuruplace.org/join/{token} link itself the moment
            // Universal Links exist (harmless until then: no other https URL
            // reaches onOpenURL without an Associated Domain).
            if let token = MemberAPI.readingJoinToken(from: url) {
                tabs.openReadingInvite(token)
                return
            }
            let host = url.host ?? url.absoluteString.replacingOccurrences(of: "nuru://", with: "")
            switch host {
            case "pathway": tabs.selected = .pathway
            case "plans":   tabs.selected = .plans
            // Every existing route name keeps resolving (PARTNERS_PROGRAMME
            // §0): chat → You's Community segment; events / give → their own
            // tabs again; partners → Give's Partners segment.
            case "chat":     tabs.openYou(.chat)
            case "events":   tabs.openEvents()
            case "give":     tabs.openGive()
            case "partners": tabs.openPartners()
            case "departments": tabs.openYou(.departments)
            case "you":      tabs.selected = .you
            // The Live tab folded into Events (its Broadcast card) — an old
            // nuru://live shortcut lands there for everyone.
            case "live":     tabs.openEvents()
            case "radio":   NotificationCenter.default.post(name: .nuruOpenRadio, object: nil)
            // "join" is claimed above by readingJoinToken(from:) — same scheme,
            // now shared with the https shape and the chat bubble's link tap.
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
        #if DEBUG
        // Scripted check of the ringing Live invite (NURU_RING) — a simulator
        // gets no pushes. Compiled out of Release, modifier and all.
        .task { await IncomingLiveInviteCenter.shared.debugRingIfRequested() }
        #endif
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
        case .events:  return AnyView(EventsView())
        case .give:    return AnyView(GiveTabView())
        case .you:     return AnyView(YouTabView())
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
                    Icon(.clock, size: 14, color: Nuru.onNavy)
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
        NavigationStack(path: $path) { ReadingPlansView().nuruDestinations().nuruEdgeSwipeBack() }
            .popsToRoot(on: .plans, path: $path)
            // "Begin Day 1" opens the day it just started on this stack —
            // the plan's page stays beneath it as the way back (§7.4 #2).
            .environment(\.openPlanDay, { ref in path.append(ref) })
            // Cross-tab deep link (Home's resume banner / plan mini / Grow tile):
            // land exactly on the plan with the catalogue as the back stop.
            .onReceive(tabs.$planLink) { link in
                guard let link else { return }
                path = NavigationPath()
                switch link {
                case .plan(let row): path.append(row)
                case .planDay(let row):
                    path.append(row)
                    Task { await openDay(of: row) }
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

    /// Lands on the plan's day — the one its page's Continue opens — once the
    /// plan answers. A failed read, a day still behind its gate, or a member
    /// who has already moved on leaves the plan's page as it is: one tap
    /// from the day.
    private func openDay(of row: ReadingPlanRow) async {
        guard let d = try? await MemberAPI.plan(row.planId), let day = d.continueDay, !day.locked,
              path.count == 1 else { return }
        path.append(PlanDayRef(planId: d.planId, day: day, planTitle: d.title))
    }
}

/// Custom bottom bar: cream, navy active (icon + label on a gold-tinted pill),
/// dim inactive. Six seats: at 375pt (iPhone SE class) each is 62.5pt wide,
/// so the label is 10pt and may shrink a touch ("Pathway" is the widest) and
/// the pill's side inset is 4pt rather than 10.
private struct NuruTabBar: View {
    @Binding var selection: AppTab
    /// The tabs to render, in order.
    let tabs: [AppTab]
    /// A tap on the tab already shown — its stack returns to the root.
    var onReselect: (AppTab) -> Void = { _ in }
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
                    // A re-tap returns the tab to its root (§7.4 #17 — Home kept
                    // a stale "not found" page in its stack); no haptic, no bounce.
                    guard selection != t else { onReselect(t); return }
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { selection = t }
                } label: {
                    VStack(spacing: 3) {
                        ZStack(alignment: .topTrailing) {
                            Icon(t.icon, size: 22, color: focused ? Nuru.navy : Self.inactive)
                                // One subtle bounce on arrival: each selection change runs
                                // the phase cycle once, and only the newly-focused icon
                                // actually scales (others stay at 1).
                                .phaseAnimator([false, true], trigger: selection) { icon, bouncing in
                                    icon.scaleEffect(bouncing && focused && !reduceMotion ? 1.12 : 1)
                                } animation: { _ in .spring(response: 0.26, dampingFraction: 0.55) }
                            if t == .you, chatBadge.count > 0 { badgeDot(chatBadge.count) }
                        }
                        Text(t.label).font(.inter(11, .medium)).foregroundStyle(focused ? Nuru.navy : Self.inactive)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background {
                        // The active tab sits on a warm cream pill (matches the
                        // member app) that slides between tabs.
                        if focused {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(Self.pill)
                                .padding(.horizontal, 4)
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
            .font(.inter(11, .bold)).foregroundStyle(.white)
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

/// A tap on the tab already shown returns that tab's stack to its root
/// (EXPERIENCE.md §7.4 #17). `when` narrows it to the segment on screen (You,
/// Give): a re-tap pops what the member is looking at, never a hidden stack.
private struct PopsToRootOnReselect: ViewModifier {
    let tab: AppTab
    @Binding var path: NavigationPath
    let when: () -> Bool
    @EnvironmentObject private var tabs: TabRouter

    func body(content: Content) -> some View {
        content.onReceive(tabs.reselected) { t in
            guard t == tab, when() else { return }
            // At the root already: its top instead (B10 — it did nothing, and
            // Plans took six swipes back up).
            if path.isEmpty { tabs.rootReselected.send(tab) } else { path = NavigationPath() }
        }
    }
}

/// On a tab root's scroll content: a re-tap on the tab while the stack is
/// at its root scrolls the root to its top (§7.4 #17: "Tapping the current
/// tab returns to its top"; the walk's B10).
private struct ScrollsToTopOnRootReselect: ViewModifier {
    let tab: AppTab
    @EnvironmentObject private var tabs: TabRouter
    private static let anchor = "nuru.tab.root.top"

    func body(content: Content) -> some View {
        ScrollViewReader { proxy in
            content
                .id(Self.anchor)
                .onReceive(tabs.rootReselected) { t in
                    guard t == tab else { return }
                    withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(Self.anchor, anchor: .top) }
                }
        }
    }
}

extension View {
    func popsToRoot(on tab: AppTab, path: Binding<NavigationPath>, when: @escaping () -> Bool = { true }) -> some View {
        modifier(PopsToRootOnReselect(tab: tab, path: path, when: when))
    }
    /// On a tab root's scroll content — see ScrollsToTopOnRootReselect.
    func scrollsToTopOnReselect(_ tab: AppTab) -> some View {
        modifier(ScrollsToTopOnRootReselect(tab: tab))
    }
}
