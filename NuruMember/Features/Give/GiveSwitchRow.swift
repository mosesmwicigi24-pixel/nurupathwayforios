// The Give tab band's first row (EXPERIENCE.md §6.2 — one header on every
// tab, the bell always at the far right): the GIVE · PARTNERS switch with the
// tab's bell at its right, opening the same notifications inbox as every
// other bell. Both segments paint it (each in its own header band), and each
// segment's stack learns the inbox's routes (`inboxDestinations`) — a bell
// that opened nothing would be worse than none. Android's GiveBell, the same
// look: white, a hairline, the other bells' gold dot, the switch's height.
import SwiftUI

struct GiveSwitchRow: View {
    let selection: GiveSegment
    let onSelect: (GiveSegment) -> Void

    var body: some View {
        HStack(spacing: 10) {
            SplitSegmentBar(selection: selection, onSelect: onSelect)
            NavigationLink(value: AppRoute.notifications) {
                Icon(.bell, size: 18, color: Nuru.navy)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        Circle().fill(Nuru.gold).frame(width: 8, height: 8).padding(9)
                    }
            }
            .buttonStyle(.pressable)
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            .accessibilityLabel("Notifications")
        }
    }
}

extension View {
    /// What a bell opens, for a stack that doesn't register every app route
    /// (`nuruDestinations`): the inbox, and the announcement a row of it
    /// opens. Every other inbox row switches tabs itself.
    func inboxDestinations() -> some View {
        navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .notifications: NotificationsView()
            case .announcement(let id): AnnouncementDetailView(announcementId: id)
            case .announcementsList: AnnouncementsAllView()
            default: EmptyView()
            }
        }
    }
}
