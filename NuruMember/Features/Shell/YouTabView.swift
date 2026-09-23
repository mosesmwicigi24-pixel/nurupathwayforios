// The "You" tab — Community · Departments · Profile · Settings
// (PARTNERS_PROGRAMME §0). Community is the default segment (the tab's
// "heart"); Departments is a placeholder until phase 3 (§4, §6); Profile is
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
        case .departments: DepartmentsPlaceholderView()
        case .profile:     ProfileView(embeddedInYou: true)
        case .settings:    NavigationStack { SettingsView(embeddedInYou: true) }
        }
    }
}

/// Departments (PARTNERS_PROGRAMME §4) ship in phase 3. Until then the
/// segment says so honestly rather than showing an empty list that looks
/// like a bug.
struct DepartmentsPlaceholderView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.md) {
                ZStack {
                    Circle().fill(Nuru.gold.opacity(0.12)).frame(width: 72, height: 72)
                    Icon(.heartHandshake, size: 30, color: Nuru.gold)
                }
                Text("Departments are coming")
                    .font(.fraunces(22, .semibold)).foregroundStyle(Nuru.navy)
                Text("You'll be able to see where to serve — the teams, what they need, and how to join one.")
                    .font(.nBody).foregroundStyle(Nuru.ink600)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
            .padding(.horizontal, Nuru.S.lg)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, Nuru.S.lg)
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .background(Nuru.paper.ignoresSafeArea())
    }
}
