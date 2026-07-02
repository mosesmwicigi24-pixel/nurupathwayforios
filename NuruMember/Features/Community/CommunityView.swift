// Community tab — hosts the congregation's shared spaces. The Prayer Wall and
// Cohort Discussions (the cell's board) are fully ported; Chat (DMs + spaces)
// is the next screen in this phase (see PORT_STATUS.md). Owns the navigation
// stack for the area.
import SwiftUI

enum CommunityRoute: Hashable {
    case prayerWall
    case prayer(String)      // postId
    case discussions
    case discussion(String)  // threadId
}

struct CommunityView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: Nuru.S.md) {
                        NavigationLink(value: CommunityRoute.prayerWall) {
                            hubRow("Prayer Wall", "Pray with the family", "hands.sparkles.fill", live: true)
                        }
                        .buttonStyle(.pressableSubtle)
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                        .gentleEntrance()
                        hubRow("Chat", "Direct messages & spaces", "bubble.left.and.bubble.right.fill", live: false)
                            .gentleEntrance(delay: 0.06)
                        NavigationLink(value: CommunityRoute.discussions) {
                            hubRow("Cohort Discussions", "Your cell's board", "person.3.fill", live: true)
                        }
                        .buttonStyle(.pressableSubtle)
                        .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                        .gentleEntrance(delay: 0.12)
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .navigationTitle("Community")
            .navigationDestination(for: CommunityRoute.self) { route in
                switch route {
                case .prayerWall: PrayerWallView()
                case .prayer(let id): PrayerWallDetailView(postId: id)
                case .discussions: DiscussionsView()
                case .discussion(let id): DiscussionThreadView(threadId: id)
                }
            }
        }
    }

    private func hubRow(_ title: String, _ subtitle: String, _ icon: String, live: Bool) -> some View {
        Card {
            HStack(spacing: Nuru.S.base) {
                ZStack {
                    Circle().fill(Nuru.goldTint).frame(width: 44, height: 44)
                    Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Nuru.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.nHeading).foregroundStyle(Nuru.ink)
                    Text(subtitle).font(.nCardBody).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
                if live {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Nuru.ink300)
                } else {
                    Text("Soon").font(.nMicro).foregroundStyle(Nuru.faint)
                        .padding(.horizontal, Nuru.S.sm).padding(.vertical, 3)
                        .background(Nuru.mutedBg, in: Capsule())
                }
            }
            .opacity(live ? 1 : 0.6)
        }
    }
}
