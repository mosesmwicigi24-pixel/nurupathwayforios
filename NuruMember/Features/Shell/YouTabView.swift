// Nuru Live L4 — the "You" tab (docs/LIVE_STREAMING.md L4 section). The
// owner's tab-bar spec folds Events + Chat + Profile into one tab; the spec's
// bar also has no seat for Give, so — rather than orphaning it — Give rides
// along inside "You" too. Chat is the default segment (the tab's "heart" per
// spec); Events, Give and Profile are peers reached through a top segmented
// control that mirrors the EXACT capsule idiom Chat already uses internally
// for its own rows (My Space / Chat / My Discipler / My Pastor) — navy
// gradient pill when selected, icon + label + unread count chip, one level up.
//
// All four screens mount PERMANENTLY (opacity-toggled — the same keep-alive
// idiom RootView itself uses across its top-level tabs) so switching segments
// never tears down Chat's inbox scroll position, a half-typed Give amount, or
// Events' filters. Each screen keeps its OWN NavigationStack untouched; this
// view only decides which one is visible and hit-testable.
import SwiftUI

struct YouTabView: View {
    @EnvironmentObject private var tabs: TabRouter
    @ObservedObject private var chatBadge = ChatBadge.shared
    @State private var segment: YouSegment = .chat
    /// Lazily mounted (like RootView's `loaded`) — Events/Give/Profile don't
    /// pay their `.task` load cost until the member actually peeks at them,
    /// but once mounted they stay alive for the rest of the session.
    @State private var mounted: Set<YouSegment> = [.chat]

    var body: some View {
        VStack(spacing: 0) {
            segmentBar
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
        // Cross-tab deep link (a notification tap, a nuru:// widget URL, or a
        // Home "See events" / "Give now" button) — TabRouter.openYou(_:) sets
        // both the tab AND the segment; consume it once, then clear it so a
        // stale value doesn't replay on the next tab switch.
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

    // MARK: Segment bar — Chat's own capsule control, one level up. Sits in
    // the same cream gradient band each folded screen used to paint itself
    // (that gradient still shows through — the pill row just now lives ABOVE
    // whichever screen is selected instead of duplicating another one).

    private var segmentBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                segmentButton(.chat, chatBadge.count)
                segmentButton(.events, 0)
                segmentButton(.give, 0)
                segmentButton(.profile, 0)
            }
            .padding(4)
        }
        .background(Color.white.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        .padding(.horizontal, Nuru.S.screen)
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.md)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .ignoresSafeArea(edges: .top)
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private func segmentButton(_ seg: YouSegment, _ count: Int) -> some View {
        let selected = segment == seg
        return Button {
            select(seg, haptic: true)
        } label: {
            HStack(spacing: 5) {
                Icon(seg.icon, size: 12, color: selected ? Nuru.gold : Color(hex: 0x59667C))
                Text(seg.label).font(.inter(12, .semibold)).foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
                // Unread only — a quiet chip (no number) IS "nothing waiting",
                // matching Chat's own segment chips exactly.
                if count > 0 {
                    Text(count > 9 ? "9+" : "\(count)").font(.inter(10, .bold))
                        .foregroundStyle(selected ? Nuru.navy : Color(hex: 0x6A7686))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .frame(minWidth: 18)
                        .background(selected ? Nuru.gold : Nuru.surface, in: Capsule())
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.clear),
                in: Capsule())
            .shadow(color: selected ? Color(hex: 0x0B1F33).opacity(0.35) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func segmentContent(_ seg: YouSegment) -> some View {
        switch seg {
        case .chat:    ChatView(embeddedInYou: true)
        case .events:  EventsView(embeddedInYou: true)
        case .give:    GivingView(embeddedInYou: true)
        case .profile: ProfileView(embeddedInYou: true)
        }
    }
}
