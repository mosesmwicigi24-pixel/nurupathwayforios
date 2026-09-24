// The "Give" tab — a two-segment switch, GIVE · PARTNERS (PARTNERS_PROGRAMME
// §0, Partners UI v2). Give is the giving screen; Partners is the programme
// portal (§2). Both mount permanently and toggle by opacity (the You tab's
// keep-alive idiom) so a half-typed amount survives a glance at a pledge and
// back. Each segment keeps its own NavigationStack.
//
// ONE cream band, not two: the tab paints no band of its own. The full-width
// SplitSegmentBar is the first row INSIDE each segment's page header (the
// same band that holds "Sow into the Kingdom" / "Walk with the church"), so
// switching segments swaps the band's title, never stacks a second band.
import SwiftUI

struct GiveTabView: View {
    @EnvironmentObject private var tabs: TabRouter
    @State private var segment: GiveSegment = .give
    @State private var mounted: Set<GiveSegment> = [.give]

    var body: some View {
        ZStack {
            ForEach(GiveSegment.allCases, id: \.self) { seg in
                if mounted.contains(seg) {
                    segmentContent(seg)
                        .opacity(seg == segment ? 1 : 0)
                        .allowsHitTesting(seg == segment)
                        .accessibilityHidden(seg != segment)
                }
            }
        }
        .background(Nuru.paper.ignoresSafeArea(edges: .bottom))
        // TabRouter.openGive() / openPartners() set the tab AND the segment;
        // consume once, then clear so a stale value never replays.
        .onReceive(tabs.$giveSegment) { seg in
            guard let seg else { return }
            select(seg, haptic: false)
            DispatchQueue.main.async { tabs.giveSegment = nil }
        }
        .onAppear { ScreenTracker.record(screen: "give.\(segment.label.lowercased())") }
    }

    private func select(_ seg: GiveSegment, haptic: Bool) {
        guard segment != seg else { return }
        if haptic { Haptics.selection() }
        withAnimation(.easeInOut(duration: 0.15)) { segment = seg }
        mounted.insert(seg)
        ScreenTracker.record(screen: "give.\(seg.label.lowercased())")
    }

    @ViewBuilder private func segmentContent(_ seg: GiveSegment) -> some View {
        switch seg {
        case .give:
            GivingView(embeddedInYou: true, segment: segment) { select($0, haptic: true) }
        case .partners:
            PartnersView(embedded: true, segment: segment) { select($0, haptic: true) }
        }
    }
}
