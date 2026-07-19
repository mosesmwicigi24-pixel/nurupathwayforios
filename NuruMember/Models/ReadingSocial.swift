// Reading & Social R1 — "Read with a Friend" DTOs (spec §3/§6;
// docs/READING_SOCIAL_PLAN.md §4). Mirrors
// packages/backend/src/modules/reading-social/{groups,invites}.ts's wire
// shapes exactly. Every DTO is tolerant (defaulted optionals) — an
// unknown/older server shape must never blank the whole screen.
import Foundation

/// Plan summary embedded in a group or invite preview — the subset of
/// ReadingPlanRow the reading-social endpoints echo back (no `enrolled`/
/// `currentDay`, since those are per-caller and this is shared state).
struct ReadingGroupPlanSummary: Codable, Sendable, Hashable {
    let code: String?
    let title: String
    let subtitle: String?
    let description: String?
    let dayCount: Int
    let imageUrl: String?

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        dayCount = (try? c.decodeIfPresent(Int.self, forKey: .dayCount)) ?? 0
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
    }
}

/// One member's row inside a shared plan group — mirrors GroupMemberRow
/// (groups.ts). `daysDone`/`currentDay` are the progress-visibility
/// exception (docs/READING_SOCIAL_PLAN.md §2.1): exposed ONLY because this
/// caller shares an active group with this person.
struct ReadingGroupMember: Codable, Sendable, Identifiable, Hashable {
    let userId: String
    let fullName: String
    let avatarUrl: String?
    let status: String   // active | left | removed
    let joinedAt: String?
    let leftAt: String?
    let currentDay: Int?
    let completedDays: [Int]?
    let daysDone: Int
    let completedAt: String?

    var id: String { userId }
    var isActive: Bool { status == "active" }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "A friend"
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "active"
        joinedAt = try? c.decodeIfPresent(String.self, forKey: .joinedAt)
        leftAt = try? c.decodeIfPresent(String.self, forKey: .leftAt)
        currentDay = try? c.decodeIfPresent(Int.self, forKey: .currentDay)
        completedDays = try? c.decodeIfPresent([Int].self, forKey: .completedDays)
        daysDone = (try? c.decodeIfPresent(Int.self, forKey: .daysDone)) ?? 0
        completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
    }
}

/// GroupRow — a bounded, invite-only circle walking one plan together
/// (migration 174; groups.ts `GroupRow`). Hashable/Identifiable so it can
/// drive value-based navigation like ReadingPlanRow does.
struct ReadingGroupRow: Codable, Sendable, Identifiable, Hashable {
    let groupId: String
    let planId: String
    let createdBy: String
    let name: String?
    let createdAt: String?
    let archivedAt: String?
    let plan: ReadingGroupPlanSummary
    let members: [ReadingGroupMember]

    var id: String { groupId }
    var isArchived: Bool { archivedAt != nil }
    /// Every OTHER active member — the roster this card shows progress for.
    func otherMembers(excluding userId: String) -> [ReadingGroupMember] {
        members.filter { $0.isActive && $0.userId != userId }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        groupId = try c.decode(String.self, forKey: .groupId)
        planId = (try? c.decodeIfPresent(String.self, forKey: .planId)) ?? ""
        createdBy = (try? c.decodeIfPresent(String.self, forKey: .createdBy)) ?? ""
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        archivedAt = try? c.decodeIfPresent(String.self, forKey: .archivedAt)
        // The server always joins reading_plans (groups.ts `groupRow`, an
        // INNER JOIN — never absent for a live group), so this decodes
        // strictly; a malformed row fails that one array element rather than
        // silently rendering a blank plan card.
        plan = try c.decode(ReadingGroupPlanSummary.self, forKey: .plan)
        members = (try? c.decodeIfPresent([ReadingGroupMember].self, forKey: .members)) ?? []
    }
}

/// InviteRow — a targeted (invitee_user_id set) or open-link invite (invites.ts).
struct ReadingInviteRow: Codable, Sendable, Identifiable, Hashable {
    let inviteId: String
    let groupId: String
    let inviterId: String
    let inviteeUserId: String?
    let token: String
    let status: String   // pending | accepted | declined | revoked | expired
    let message: String?
    let createdAt: String?
    let expiresAt: String?
    let decidedAt: String?
    let acceptedBy: String?

    var id: String { inviteId }
    var isOpenLink: Bool { inviteeUserId == nil }
    var isPending: Bool { status == "pending" }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        inviteId = try c.decode(String.self, forKey: .inviteId)
        groupId = (try? c.decodeIfPresent(String.self, forKey: .groupId)) ?? ""
        inviterId = (try? c.decodeIfPresent(String.self, forKey: .inviterId)) ?? ""
        inviteeUserId = try? c.decodeIfPresent(String.self, forKey: .inviteeUserId)
        token = (try? c.decodeIfPresent(String.self, forKey: .token)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        createdAt = try? c.decodeIfPresent(String.self, forKey: .createdAt)
        expiresAt = try? c.decodeIfPresent(String.self, forKey: .expiresAt)
        decidedAt = try? c.decodeIfPresent(String.self, forKey: .decidedAt)
        acceptedBy = try? c.decodeIfPresent(String.self, forKey: .acceptedBy)
    }
}

/// The inviter's public identity on an invite preview.
struct ReadingInviter: Codable, Sendable, Hashable {
    let userId: String
    let fullName: String
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "A friend"
    }
}

/// GET /reading/invites/{token} — the authenticated in-app preview (invites.ts `InvitePreview`).
struct ReadingInvitePreview: Codable, Sendable {
    let token: String
    let status: String
    let message: String?
    let groupId: String
    let plan: ReadingGroupPlanSummary
    let inviter: ReadingInviter
    let memberCount: Int

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        token = (try? c.decodeIfPresent(String.self, forKey: .token)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        groupId = (try? c.decodeIfPresent(String.self, forKey: .groupId)) ?? ""
        plan = try c.decode(ReadingGroupPlanSummary.self, forKey: .plan)
        inviter = try c.decode(ReadingInviter.self, forKey: .inviter)
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
    }
}

/// POST /reading/invites/{token}/accept response.
struct ReadingInviteAcceptResult: Codable, Sendable {
    let groupId: String
    let status: String
    let joined: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        groupId = (try? c.decodeIfPresent(String.self, forKey: .groupId)) ?? ""
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        joined = (try? c.decodeIfPresent(Bool.self, forKey: .joined)) ?? false
    }
}

/// A value-route: push the invite-preview screen for a given /join/{token}
/// (from a deep link, a pushed "invitations" row, or a share-back).
struct ReadingInviteRef: Hashable, Sendable {
    let token: String
}
