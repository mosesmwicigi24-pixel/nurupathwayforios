// Community routes — shared navigation values for the Prayer Wall and
// Cohort Discussions, pushed from Home/Grow/Cell/Chat stacks. (The old
// Community hub screen was retired when these moved into other tabs.)
import SwiftUI

enum CommunityRoute: Hashable {
    case prayerWall
    case prayer(String)      // postId
    case discussions
    case discussion(String)  // threadId
}
