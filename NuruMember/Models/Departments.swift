// Departments DTOs — PARTNERS_PROGRAMME §4 (phase 3), member contract §5:
// GET /departments, GET /me/departments, GET /departments/{id}. Decoded with
// `.convertFromSnakeCase`. Every field but the id is tolerant, so a server
// that ships a leaner row (or a richer one) still renders the card.
import Foundation

/// One department as the list endpoints return it — the card's whole truth.
/// `fit` / `matchedGifts` are the server's "a good fit for you" verdict
/// (§4: `gift_keys` ∩ the member's top gifts); the client never recomputes it.
struct DepartmentRow: Codable, Sendable, Identifiable, Hashable {
    let departmentId: String
    let name: String
    let purpose: String
    let meets: String?
    let imageUrl: String?
    let giftKeys: [String]
    let isOpenToJoin: Bool
    let leaderName: String?
    let leaderAvatar: String?
    let memberCount: Int
    /// requested | active | declined | left | nil (never asked)
    let myStatus: String?
    /// leader | member | nil
    let myRole: String?
    let openNeeds: Int
    let latestPost: String?
    let latestPostAt: String?
    let fit: Bool
    let matchedGifts: [String]

    var id: String { departmentId }
    static func == (a: DepartmentRow, b: DepartmentRow) -> Bool { a.departmentId == b.departmentId }
    func hash(into h: inout Hasher) { h.combine(departmentId) }

    var isActiveMember: Bool { myStatus == "active" }
    var isRequested: Bool { myStatus == "requested" }
    var isLeaderRole: Bool { myRole == "leader" }

    /// Gift keys → readable names ("teaching_word" → "Teaching word"). The
    /// server may already send names; capitalising a name is harmless.
    var matchedGiftNames: [String] {
        matchedGifts.map { key in
            let words = key.replacingOccurrences(of: "_", with: " ")
            return words.prefix(1).uppercased() + words.dropFirst()
        }
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        departmentId = try c.decode(String.self, forKey: .departmentId)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        purpose = (try? c.decodeIfPresent(String.self, forKey: .purpose)) ?? ""
        meets = try? c.decodeIfPresent(String.self, forKey: .meets)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        giftKeys = (try? c.decodeIfPresent([String].self, forKey: .giftKeys)) ?? []
        isOpenToJoin = (try? c.decodeIfPresent(Bool.self, forKey: .isOpenToJoin)) ?? true
        leaderName = try? c.decodeIfPresent(String.self, forKey: .leaderName)
        leaderAvatar = try? c.decodeIfPresent(String.self, forKey: .leaderAvatar)
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        myStatus = try? c.decodeIfPresent(String.self, forKey: .myStatus)
        myRole = try? c.decodeIfPresent(String.self, forKey: .myRole)
        openNeeds = (try? c.decodeIfPresent(Int.self, forKey: .openNeeds)) ?? 0
        latestPost = try? c.decodeIfPresent(String.self, forKey: .latestPost)
        latestPostAt = try? c.decodeIfPresent(String.self, forKey: .latestPostAt)
        fit = (try? c.decodeIfPresent(Bool.self, forKey: .fit)) ?? false
        matchedGifts = (try? c.decodeIfPresent([String].self, forKey: .matchedGifts)) ?? []
    }
}

/// A leader's (or admin's) post on the department page (§4 `department_posts`).
struct DepartmentPost: Codable, Sendable, Identifiable, Hashable {
    let postId: String
    let body: String
    let imageUrl: String?
    let createdAt: String
    let authorName: String?
    let authorAvatar: String?
    var id: String { postId }
    static func == (a: DepartmentPost, b: DepartmentPost) -> Bool { a.postId == b.postId }
    func hash(into h: inout Hasher) { h.combine(postId) }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        postId = try c.decode(String.self, forKey: .postId)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        authorName = try? c.decodeIfPresent(String.self, forKey: .authorName)
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
    }
}

/// An active member of the department (§4 `department_members`, status active).
struct DepartmentMember: Codable, Sendable, Identifiable, Hashable {
    let userId: String
    let fullName: String
    let avatarUrl: String?
    /// leader | member
    let role: String
    var id: String { userId }
    var isLeader: Bool { role == "leader" }
    static func == (a: DepartmentMember, b: DepartmentMember) -> Bool { a.userId == b.userId }
    func hash(into h: inout Hasher) { h.combine(userId) }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "member"
    }
}

/// A department need (§4 `department_needs`). Progress (`raisedMinor`,
/// `percent`, `reached`) is the server's — it comes from the campaign the
/// office created on approval, never from anything the client adds up.
struct DepartmentNeed: Codable, Sendable, Identifiable, Hashable {
    let needId: String
    let title: String
    let why: String
    let targetMinor: Int
    let currency: String
    let deadline: String?
    /// draft | pending | approved | closed
    let status: String
    let createdAt: String
    let submittedName: String?
    let raisedMinor: Int
    let percent: Int
    let reached: Bool
    var id: String { needId }
    static func == (a: DepartmentNeed, b: DepartmentNeed) -> Bool { a.needId == b.needId }
    func hash(into h: inout Hasher) { h.combine(needId) }

    /// Approved = open for giving. Only these show to members; leaders also
    /// see pending (awaiting the office) and closed.
    var isOpen: Bool { status == "approved" }
    var isPending: Bool { status == "pending" || status == "draft" }
    var isClosed: Bool { status == "closed" }
    /// Progress toward the target, clamped for the bar.
    var fraction: Double { min(1, max(0, Double(percent) / 100)) }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        needId = try c.decode(String.self, forKey: .needId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        why = (try? c.decodeIfPresent(String.self, forKey: .why)) ?? ""
        targetMinor = (try? c.decodeIfPresent(Int.self, forKey: .targetMinor)) ?? 0
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "KES"
        deadline = try? c.decodeIfPresent(String.self, forKey: .deadline)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "pending"
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        submittedName = try? c.decodeIfPresent(String.self, forKey: .submittedName)
        raisedMinor = (try? c.decodeIfPresent(Int.self, forKey: .raisedMinor)) ?? 0
        percent = (try? c.decodeIfPresent(Int.self, forKey: .percent)) ?? 0
        reached = (try? c.decodeIfPresent(Bool.self, forKey: .reached)) ?? false
    }
}

/// GET /departments/{id} — the list row plus the page's three sections and
/// `is_leader` (the caller's authority on this department: compose posts,
/// delete posts, submit needs).
struct DepartmentDetail: Codable, Sendable {
    let summary: DepartmentRow
    let isLeader: Bool
    let posts: [DepartmentPost]
    let members: [DepartmentMember]
    let needs: [DepartmentNeed]

    private enum ExtraKeys: String, CodingKey { case isLeader, posts, members, needs }

    init(from d: Decoder) throws {
        // The row fields sit at the top level beside the extras, so the same
        // decoder feeds both.
        summary = try DepartmentRow(from: d)
        let c = try d.container(keyedBy: ExtraKeys.self)
        isLeader = (try? c.decodeIfPresent(Bool.self, forKey: .isLeader)) ?? false
        posts = (try? c.decodeIfPresent([DepartmentPost].self, forKey: .posts)) ?? []
        members = (try? c.decodeIfPresent([DepartmentMember].self, forKey: .members)) ?? []
        needs = (try? c.decodeIfPresent([DepartmentNeed].self, forKey: .needs)) ?? []
    }

    func encode(to e: Encoder) throws {
        try summary.encode(to: e)
        var c = e.container(keyedBy: ExtraKeys.self)
        try c.encode(isLeader, forKey: .isLeader)
        try c.encode(posts, forKey: .posts)
        try c.encode(members, forKey: .members)
        try c.encode(needs, forKey: .needs)
    }
}
