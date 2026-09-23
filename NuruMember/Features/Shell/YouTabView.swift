// The "You" tab — Community · Departments · Profile · Settings
// (PARTNERS_PROGRAMME §0). Community is the default segment (the tab's
// "heart"); Departments is the serving-teams list + pages (§4, phase 3); Profile is
// the account screen; Settings is the existing screen promoted from behind
// the Profile gear (the gear still pushes it, so both doors open the same
// room). Events and Give left this tab for seats of their own on the bar.
//
// All four screens mount PERMANENTLY (opacity-toggled — the same keep-alive
// idiom RootView itself uses across its top-level tabs) so switching segments
// never tears down Chat's inbox scroll position or a half-toggled setting.
// Each screen keeps its OWN NavigationStack untouched; this view only decides
// which one is visible and hit-testable.
import SwiftUI

struct YouTabView: View {
    @EnvironmentObject private var tabs: TabRouter
    @ObservedObject private var chatBadge = ChatBadge.shared
    @State private var segment: YouSegment = .chat
    /// Lazily mounted (like RootView's `loaded`) — Profile/Settings don't pay
    /// their `.task` load cost until the member actually peeks at them, but
    /// once mounted they stay alive for the rest of the session.
    @State private var mounted: Set<YouSegment> = [.chat]

    var body: some View {
        VStack(spacing: 0) {
            CapsuleSegmentBar(selection: segment, counts: [.chat: chatBadge.count]) { select($0, haptic: true) }
            ZStack {
                ForEach(YouSegment.allCases, id: \.self) { seg in
                    if mounted.contains(seg) {
                        segmentContent(seg)
                            .opacity(seg == segment ? 1 : 0)
                            .allowsHitTesting(seg == segment)
                            .accessibilityHidden(seg != segment)
                    }
                }
            }
        }
        .background(Nuru.paper.ignoresSafeArea(edges: .bottom))
        // Cross-tab deep link (a notification tap, a nuru:// widget URL, a Home
        // button) — TabRouter.openYou(_:) sets both the tab AND the segment;
        // consume it once, then clear it so a stale value doesn't replay on
        // the next tab switch.
        .onReceive(tabs.$youSegment) { seg in
            guard let seg else { return }
            select(seg, haptic: false)
            DispatchQueue.main.async { tabs.youSegment = nil }
        }
        .onAppear { ScreenTracker.record(screen: "you.\(segment.label.lowercased())") }
    }

    private func select(_ seg: YouSegment, haptic: Bool) {
        guard segment != seg else { return }
        if haptic { Haptics.selection() }
        withAnimation(.easeInOut(duration: 0.15)) { segment = seg }
        mounted.insert(seg)
        ScreenTracker.record(screen: "you.\(seg.label.lowercased())")
    }

    @ViewBuilder private func segmentContent(_ seg: YouSegment) -> some View {
        switch seg {
        case .chat:        CommunityView(embeddedInYou: true)   // Talk (ChatView) + Pray (PrayerRoomView)
        case .departments: DepartmentsView()
        case .profile:     ProfileView(embeddedInYou: true)
        case .settings:    NavigationStack { SettingsView(embeddedInYou: true) }
        }
    }
}
