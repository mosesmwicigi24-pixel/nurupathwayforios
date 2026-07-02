// Cohort Discussions — typed facade over the backend community module
// (packages/backend/src/modules/community). The board is CELL-scoped: the
// server resolves the caller's cell_group_id and answers 422 ("Join a cell
// group to use Community") for members without one; threads outside the cell
// 404 (no existence leak).
//
// Reads live here. WRITES go through the durable offline queue instead
// (SyncCoordinator.enqueue → sync/push as `discussion_threads:create` /
// `discussion_comments:create`): ids are client-minted and the server dedupes
// replays, so a post "succeeds" the moment it is queued (§1.7/§3.6).
import Foundation

/// One row of GET /community/threads — pinned first, then newest.
struct DiscussionThread: Codable, Sendable, Identifiable {
    let threadId: String
    let title: String
    let body: String
    let isPinned: Bool
    let isLocked: Bool
    let createdAt: String
    let authorUserId: String
    let authorName: String
    /// Visible-comment count — present on the list select only; the detail
    /// endpoint omits it, so decode defensively.
    let commentCount: Int?

    var id: String { threadId }
}

/// One visible comment under a thread (oldest first).
struct DiscussionComment: Codable, Sendable, Identifiable {
    let commentId: String
    let body: String
    let createdAt: String
    let authorUserId: String
    let authorName: String

    var id: String { commentId }
}

/// GET /community/threads/{id} — the thread's own fields flattened at the top
/// level with its comments alongside (the server spreads `{ ...thread, comments }`).
struct DiscussionThreadDetail: Codable, Sendable {
    let threadId: String
    let title: String
    let body: String
    let isPinned: Bool
    let isLocked: Bool
    let createdAt: String
    let authorUserId: String
    let authorName: String
    let comments: [DiscussionComment]
}

extension MemberAPI {
    // MARK: Community — Cohort Discussions (my cell's board)

    /// GET /community/threads — the caller's cell board (≤100 rows).
    static func discussionThreads() async throws -> [DiscussionThread] {
        try await APIClient.shared.get("community/threads", as: Envelope<DiscussionThread>.self).data
    }

    /// GET /community/threads/{id} — one thread with its visible comments.
    static func discussionThread(_ threadId: String) async throws -> DiscussionThreadDetail {
        try await APIClient.shared.get("community/threads/\(threadId)", as: DiscussionThreadDetail.self)
    }
}
