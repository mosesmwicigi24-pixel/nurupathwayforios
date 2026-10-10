// Ekklesia — the intercessory watch (pathway packages/backend/src/modules/
// ekklesia). Swift mirrors of the wire shapes, tolerant end-to-end as the
// prayer wall's are (Android parity): a sparse field degrades one row, never
// the watch. Decoded with `.convertFromSnakeCase`.
import Foundation

struct EkklesiaFace: Codable, Sendable, Identifiable, Hashable {
    var userId: String = ""
    var name: String = ""
    var avatar: String? = nil
    var role: String = "intercessor"
    var id: String { userId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        avatar = try? c.decodeIfPresent(String.self, forKey: .avatar)
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "intercessor"
    }
}

/// The watch as the member sees it: counts for everyone, membership for me.
struct EkklesiaGroup: Codable, Sendable {
    var name = "Ekklesia"
    var mission = "Pray for the Body of Christ"
    var memberCount = 0
    var activeCount = 0
    var urgentCount = 0
    var answeredCount = 0
    var prayersToday = 0
    var myPrayersToday = 0
    var myPrayersTotal = 0
    var myDays = 0
    var faces: [EkklesiaFace] = []
    var isMember = false
    var myRole: String? = nil
    var joinedAt: String? = nil
    var isLeader = false
    /// Active needs I have not yet prayed today (0 unless I'm on the watch).
    var needsMeToday = 0
    init() {}
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Ekklesia"
        mission = (try? c.decodeIfPresent(String.self, forKey: .mission)) ?? "Pray for the Body of Christ"
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        activeCount = (try? c.decodeIfPresent(Int.self, forKey: .activeCount)) ?? 0
        urgentCount = (try? c.decodeIfPresent(Int.self, forKey: .urgentCount)) ?? 0
        answeredCount = (try? c.decodeIfPresent(Int.self, forKey: .answeredCount)) ?? 0
        prayersToday = (try? c.decodeIfPresent(Int.self, forKey: .prayersToday)) ?? 0
        myPrayersToday = (try? c.decodeIfPresent(Int.self, forKey: .myPrayersToday)) ?? 0
        myPrayersTotal = (try? c.decodeIfPresent(Int.self, forKey: .myPrayersTotal)) ?? 0
        myDays = (try? c.decodeIfPresent(Int.self, forKey: .myDays)) ?? 0
        faces = (try? c.decodeIfPresent([EkklesiaFace].self, forKey: .faces)) ?? []
        isMember = (try? c.decodeIfPresent(Bool.self, forKey: .isMember)) ?? false
        myRole = try? c.decodeIfPresent(String.self, forKey: .myRole)
        joinedAt = try? c.decodeIfPresent(String.self, forKey: .joinedAt)
        isLeader = (try? c.decodeIfPresent(Bool.self, forKey: .isLeader)) ?? false
        needsMeToday = (try? c.decodeIfPresent(Int.self, forKey: .needsMeToday)) ?? 0
    }
}

struct EkklesiaRequest: Codable, Sendable, Identifiable, Hashable {
    var requestId = ""
    var authorUserId = ""
    var authorName = ""
    var authorAvatar: String? = nil
    var title = ""
    var body = ""
    var forWhom: String? = nil
    var urgency = "normal"          // normal | urgent
    var isAnswered = false
    var answeredAt: String? = nil
    var answeredNote: String? = nil
    var isPinned = false
    var createdAt = ""
    var mine = false
    var intercessorCount = 0        // distinct people who have prayed it
    var prayerCount = 0             // person-days of prayer
    var iPrayedToday = false
    var myPrayerDays = 0
    var updateCount = 0
    var lastUpdateAt: String? = nil
    var id: String { requestId }
    var isUrgent: Bool { urgency == "urgent" }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        requestId = (try? c.decodeIfPresent(String.self, forKey: .requestId)) ?? ""
        authorUserId = (try? c.decodeIfPresent(String.self, forKey: .authorUserId)) ?? ""
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        forWhom = try? c.decodeIfPresent(String.self, forKey: .forWhom)
        urgency = (try? c.decodeIfPresent(String.self, forKey: .urgency)) ?? "normal"
        isAnswered = (try? c.decodeIfPresent(Bool.self, forKey: .isAnswered)) ?? false
        answeredAt = try? c.decodeIfPresent(String.self, forKey: .answeredAt)
        answeredNote = try? c.decodeIfPresent(String.self, forKey: .answeredNote)
        isPinned = (try? c.decodeIfPresent(Bool.self, forKey: .isPinned)) ?? false
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
        intercessorCount = (try? c.decodeIfPresent(Int.self, forKey: .intercessorCount)) ?? 0
        prayerCount = (try? c.decodeIfPresent(Int.self, forKey: .prayerCount)) ?? 0
        iPrayedToday = (try? c.decodeIfPresent(Bool.self, forKey: .iPrayedToday)) ?? false
        myPrayerDays = (try? c.decodeIfPresent(Int.self, forKey: .myPrayerDays)) ?? 0
        updateCount = (try? c.decodeIfPresent(Int.self, forKey: .updateCount)) ?? 0
        lastUpdateAt = try? c.decodeIfPresent(String.self, forKey: .lastUpdateAt)
    }
}

/// What a member who has not joined sees of a need: the title, never the body.
struct EkklesiaPreview: Codable, Sendable, Identifiable {
    var requestId = ""
    var title = ""
    var urgency = "normal"
    var intercessorCount = 0
    var createdAt = ""
    var id: String { requestId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        requestId = (try? c.decodeIfPresent(String.self, forKey: .requestId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        urgency = (try? c.decodeIfPresent(String.self, forKey: .urgency)) ?? "normal"
        intercessorCount = (try? c.decodeIfPresent(Int.self, forKey: .intercessorCount)) ?? 0
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
}

struct EkklesiaOverview: Codable, Sendable {
    var group = EkklesiaGroup()
    var requests: [EkklesiaRequest] = []
    var preview: [EkklesiaPreview] = []
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        group = (try? c.decodeIfPresent(EkklesiaGroup.self, forKey: .group)) ?? EkklesiaGroup()
        requests = (try? c.decodeIfPresent([EkklesiaRequest].self, forKey: .requests)) ?? []
        preview = (try? c.decodeIfPresent([EkklesiaPreview].self, forKey: .preview)) ?? []
    }
}

struct EkklesiaLatest: Codable, Sendable, Identifiable {
    var requestId = ""
    var title = ""
    var forWhom: String? = nil
    var urgency = "normal"
    var intercessorCount = 0
    var createdAt = ""
    var id: String { requestId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        requestId = (try? c.decodeIfPresent(String.self, forKey: .requestId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        forWhom = try? c.decodeIfPresent(String.self, forKey: .forWhom)
        urgency = (try? c.decodeIfPresent(String.self, forKey: .urgency)) ?? "normal"
        intercessorCount = (try? c.decodeIfPresent(Int.self, forKey: .intercessorCount)) ?? 0
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
}

/// GET /ekklesia/summary — the Home card and every invitation read this one shape.
struct EkklesiaSummary: Codable, Sendable {
    var name = "Ekklesia"
    var mission = "Pray for the Body of Christ"
    var isMember = false
    var myRole: String? = nil
    var isLeader = false
    var memberCount = 0
    var activeCount = 0
    var urgentCount = 0
    var answeredCount = 0
    var prayersToday = 0
    var needsMeToday = 0
    var myPrayersToday = 0
    var myDays = 0
    var faces: [EkklesiaFace] = []
    var latest: [EkklesiaLatest] = []
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Ekklesia"
        mission = (try? c.decodeIfPresent(String.self, forKey: .mission)) ?? "Pray for the Body of Christ"
        isMember = (try? c.decodeIfPresent(Bool.self, forKey: .isMember)) ?? false
        myRole = try? c.decodeIfPresent(String.self, forKey: .myRole)
        isLeader = (try? c.decodeIfPresent(Bool.self, forKey: .isLeader)) ?? false
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        activeCount = (try? c.decodeIfPresent(Int.self, forKey: .activeCount)) ?? 0
        urgentCount = (try? c.decodeIfPresent(Int.self, forKey: .urgentCount)) ?? 0
        answeredCount = (try? c.decodeIfPresent(Int.self, forKey: .answeredCount)) ?? 0
        prayersToday = (try? c.decodeIfPresent(Int.self, forKey: .prayersToday)) ?? 0
        needsMeToday = (try? c.decodeIfPresent(Int.self, forKey: .needsMeToday)) ?? 0
        myPrayersToday = (try? c.decodeIfPresent(Int.self, forKey: .myPrayersToday)) ?? 0
        myDays = (try? c.decodeIfPresent(Int.self, forKey: .myDays)) ?? 0
        faces = (try? c.decodeIfPresent([EkklesiaFace].self, forKey: .faces)) ?? []
        latest = (try? c.decodeIfPresent([EkklesiaLatest].self, forKey: .latest)) ?? []
    }
}

struct EkklesiaUpdate: Codable, Sendable, Identifiable {
    var updateId = ""
    var authorUserId = ""
    var authorName = ""
    var authorAvatar: String? = nil
    var kind = "update"             // update | testimony
    var body = ""
    var createdAt = ""
    var mine = false
    var id: String { updateId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        updateId = (try? c.decodeIfPresent(String.self, forKey: .updateId)) ?? ""
        authorUserId = (try? c.decodeIfPresent(String.self, forKey: .authorUserId)) ?? ""
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        authorAvatar = try? c.decodeIfPresent(String.self, forKey: .authorAvatar)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "update"
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        mine = (try? c.decodeIfPresent(Bool.self, forKey: .mine)) ?? false
    }
}

struct EkklesiaIntercessor: Codable, Sendable, Identifiable {
    var userId = ""
    var name = ""
    var avatar: String? = nil
    var days = 0
    var lastPrayedOn: String? = nil
    var me = false
    var id: String { userId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
        avatar = try? c.decodeIfPresent(String.self, forKey: .avatar)
        days = (try? c.decodeIfPresent(Int.self, forKey: .days)) ?? 0
        lastPrayedOn = try? c.decodeIfPresent(String.self, forKey: .lastPrayedOn)
        me = (try? c.decodeIfPresent(Bool.self, forKey: .me)) ?? false
    }
}

struct EkklesiaRequestDetail: Codable, Sendable {
    let request: EkklesiaRequest
    var updates: [EkklesiaUpdate] = []
    var intercessors: [EkklesiaIntercessor] = []
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        request = try c.decode(EkklesiaRequest.self, forKey: .request)
        updates = (try? c.decodeIfPresent([EkklesiaUpdate].self, forKey: .updates)) ?? []
        intercessors = (try? c.decodeIfPresent([EkklesiaIntercessor].self, forKey: .intercessors)) ?? []
    }
}

struct EkklesiaJoinRes: Decodable, Sendable {
    var joined = false; var memberCount = 0; var firstTime = false
    enum CodingKeys: String, CodingKey { case joined, memberCount, firstTime }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        joined = (try? c.decodeIfPresent(Bool.self, forKey: .joined)) ?? false
        memberCount = (try? c.decodeIfPresent(Int.self, forKey: .memberCount)) ?? 0
        firstTime = (try? c.decodeIfPresent(Bool.self, forKey: .firstTime)) ?? false
    }
}

struct EkklesiaIntercedeRes: Decodable, Sendable {
    var prayedToday = false; var firstToday = false; var prayerCount = 0; var intercessorCount = 0; var myPrayerDays = 0
    enum CodingKeys: String, CodingKey { case prayedToday, firstToday, prayerCount, intercessorCount, myPrayerDays }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        prayedToday = (try? c.decodeIfPresent(Bool.self, forKey: .prayedToday)) ?? false
        firstToday = (try? c.decodeIfPresent(Bool.self, forKey: .firstToday)) ?? false
        prayerCount = (try? c.decodeIfPresent(Int.self, forKey: .prayerCount)) ?? 0
        intercessorCount = (try? c.decodeIfPresent(Int.self, forKey: .intercessorCount)) ?? 0
        myPrayerDays = (try? c.decodeIfPresent(Int.self, forKey: .myPrayerDays)) ?? 0
    }
}

/// Ekklesia's words — the lines the invitations and the Home card say, kept
/// pure so a test can read them. Same strings as Android's EkklesiaWords.
enum EkklesiaWords {
    static let invitations: [String] = [
        "Someone is carrying something heavy tonight. Stand with them.",
        "The watch prays the same need again tomorrow. That is what makes it a watch.",
        "Stand in the gap for a few minutes a day. Join Ekklesia.",
        "Before the healing came, somebody prayed. Be that somebody.",
        "Ekklesia is the church on its knees for the church. There is room for you.",
        "A need brought to the watch is never carried alone.",
    ]

    /// One invitation for the day; `dayOfYear` keeps it steady all day.
    static func invitation(dayOfYear: Int) -> String {
        let n = invitations.count
        return invitations[((dayOfYear % n) + n) % n]
    }

    /// The line beneath the invitation: who already stands, honestly (no zero counts).
    static func standing(memberCount: Int) -> String? {
        if memberCount <= 0 { return nil }
        return memberCount == 1 ? "1 intercessor already stands." : "\(memberCount) intercessors already stand."
    }

    /// What an intercessor sees instead of an invitation.
    static func memberLine(needsMeToday: Int, urgent: Int) -> String {
        if needsMeToday <= 0 { return "You have stood with every need today." }
        if urgent > 0 && needsMeToday == 1 { return "1 urgent need waits on you today." }
        if urgent > 0 { return "\(needsMeToday) needs wait on you today, \(urgent) urgent." }
        return needsMeToday == 1 ? "1 need waits on you today." : "\(needsMeToday) needs wait on you today."
    }

    /// "12 interceding · 40 prayers · 2 updates" — only the parts that are not zero.
    static func countsLine(intercessors: Int, prayers: Int, updates: Int) -> String? {
        var parts: [String] = []
        if intercessors > 0 { parts.append(intercessors == 1 ? "1 interceding" : "\(intercessors) interceding") }
        if prayers > intercessors { parts.append("\(prayers) prayers") }
        if updates > 0 { parts.append(updates == 1 ? "1 update" : "\(updates) updates") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
