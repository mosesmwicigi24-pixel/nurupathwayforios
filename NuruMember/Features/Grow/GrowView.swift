// Shared navigation destinations + small load-state helper for the member app.
// The growth screens (Devotional, Memory Verses, Reading Plans, Prayer Journal,
// Verse Library) are reached from Home's "Grow your faith" grid and the Plans
// tab — exactly like the RN app, which has no separate "Grow" tab.
import SwiftUI

/// App-wide pushable routes (notification center, announcement detail, mentor, cell info).
enum AppRoute: Hashable {
    case notifications
    case announcement(String)
    case announcementsList
    case mentor
    case cell
    /// The cell's people — pushed from CellInfoView's members card.
    case cellRoster
    case discipleshipHub
}

/// Value-routes for the growth screens, pushed from Home / Plans stacks.
enum GrowDestination: Hashable {
    case devotional
    case memoryVerses
    case readingPlans
    case prayerJournal
    case verseLibrary
    case gifts
    case giftsAssessment
    case resources
    /// "Read with a Friend" hub — my active shared-plan groups (spec §3).
    case readWithFriendHub
}

extension View {
    /// Registers every cross-screen navigation destination so any stack (Home,
    /// Plans, Community) can push the same screens with value-based links.
    func nuruDestinations() -> some View {
        self
            .navigationDestination(for: GrowDestination.self) { d in
                switch d {
                case .devotional:    DevotionalView()
                case .memoryVerses:  MemoryVerseView()
                case .readingPlans:  ReadingPlansView()
                // "Prayer journal" is now a tab inside My Prayer Room, not its
                // own screen — both entry points converge on PrayerRoomView.
                case .prayerJournal: PrayerRoomView(initialTab: .privatePrayer)
                case .verseLibrary:  VerseLibraryView()
                case .gifts:         GiftsView()
                case .giftsAssessment: GiftsAssessmentView()
                case .resources:     ResourcesLibraryView()
                case .readWithFriendHub: ReadWithFriendHubView()
                }
            }
            .navigationDestination(for: ReadingPlanRow.self) { PlanDetailView(plan: $0) }
            .navigationDestination(for: PlanDayRef.self) { PlanDayView(ref: $0) }
            .navigationDestination(for: PlanSegmentRef.self) { PlanSegmentView(ref: $0) }
            .navigationDestination(for: TalkRoute.self) { TalkItOverView(route: $0) }
            // Read with a Friend — group detail (by full row or by id alone,
            // e.g. from a notification or a deep link) + the invite preview
            // pushed after a nuru://join/{token} deep link opens the app.
            .navigationDestination(for: ReadingGroupRow.self) { ReadingGroupDetailView(groupId: $0.groupId, preloaded: $0) }
            .navigationDestination(for: ReadingGroupIdRef.self) { ReadingGroupDetailView(groupId: $0.groupId) }
            .navigationDestination(for: ReadingInviteRef.self) { ReadingInvitePreviewView(token: $0.token) }
            .navigationDestination(for: CommunityRoute.self) { r in
                switch r {
                // "Prayer wall" is now the Corporate Prayer tab inside My
                // Prayer Room. A specific post still opens its own detail
                // screen directly — deep links keep working unchanged.
                case .prayerWall: PrayerRoomView(initialTab: .corporatePrayer)
                case .prayer(let id): PrayerWallDetailView(postId: id)
                case .discussions: DiscussionsView()
                case .discussion(let id): DiscussionThreadView(threadId: id)
                }
            }
            .navigationDestination(for: PathwayRoute.self) { r in
                switch r {
                case .level(let n): LevelDetailView(levelNumber: n)
                case .module(let id): ModuleView(moduleId: id)
                case .quiz(let id): QuizView(moduleId: id)
                case .exam(let n): LevelExamView(levelNumber: n)
                case .map: EmptyView()   // only ever pushed from the Pathway tab
                case .walk: YourWalkView()
                }
            }
            .navigationDestination(for: CalendarOccurrence.self) { EventDetailView(occurrence: $0) }
            .navigationDestination(for: AppRoute.self) { r in
                switch r {
                case .notifications: NotificationsView()
                case .announcement(let id): AnnouncementDetailView(announcementId: id)
                case .announcementsList: AnnouncementsAllView()
                case .mentor: MentorView()
                case .cell: CellInfoView()
                case .cellRoster: CellRosterView()
                case .discipleshipHub: DiscipleshipHubView()
                }
            }
    }
}

/// A standard loading / empty / error scaffold so each data screen stays terse.
struct LoadStateView<Content: View>: View {
    let loading: Bool
    let isEmpty: Bool
    let error: String?
    let emptyText: String
    let retry: () -> Void
    @ViewBuilder var content: () -> Content

    var body: some View {
        if loading {
            ProgressView()
        } else if let error, isEmpty {
            VStack(spacing: Nuru.S.md) {
                Text(error).font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                Button { Haptics.tap(); retry() } label: {
                    Text("Try again")
                        .font(.inter(14, .semibold)).foregroundStyle(Nuru.gold)
                        .frame(minWidth: 44, minHeight: 44) // comfortable tap target
                }
                .buttonStyle(.pressable)
            }
            .padding(Nuru.S.xl)
        } else if isEmpty {
            Text(emptyText).font(.nBody).foregroundStyle(Nuru.muted).padding(Nuru.S.xl)
        } else {
            content()
        }
    }
}

