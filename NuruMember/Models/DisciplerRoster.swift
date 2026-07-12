// Discipler-side DTOs — the leader's view of the flock, served by
// GET /disciples (roster) and GET /disciples/{id} (per-student dossier).
// Pure reads (no side effects): the roster reflects the server's own
// needs-action-first ordering and the dossier only mirrors server state —
// nothing here advances a level or originates gating (§1.9). Decoded with the
// APIClient's `.convertFromSnakeCase`, so every property is camelCase; anything
// the wire may omit is a tolerant optional so a sparse payload still decodes.
import Foundation

/// The whole GET /disciples payload: the leader's students plus the header
/// summary. The server pre-sorts needs-action first — clients must NOT re-sort.
struct DiscipleRoster: Codable, Sendable {
    let data: [Row]
    let summary: Summary

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        data = (try? c.decodeIfPresent([Row].self, forKey: .data)) ?? []
        summary = (try? c.decodeIfPresent(Summary.self, forKey: .summary))
            ?? Summary(totalStudents: 0, awaitingAction: 0)
    }

    /// "N walking with you · M awaiting action" — computed server-side.
    struct Summary: Codable, Sendable {
        let totalStudents: Int
        let awaitingAction: Int
    }

    /// One student on the roster.
    struct Row: Codable, Sendable, Identifiable, Hashable {
        let userId: String
        let fullName: String
        let avatarUrl: String?
        let cellName: String?
        let cellGroupId: String?
        let currentLevel: Int
        /// thriving | steady | watch | at_risk — nil until engagement is computed.
        let band: String?
        let streakDays: Int
        /// Days since the student last did anything; nil = no activity yet.
        let daysSinceLastActivity: Int?
        /// Reflections waiting on THIS leader's review.
        let pendingReflections: Int
        /// Non-nil when the student awaits the leader's usher into this level.
        let awaitingLevel: Int?

        var id: String { userId }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
            fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
            avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
            cellName = try? c.decodeIfPresent(String.self, forKey: .cellName)
            cellGroupId = try? c.decodeIfPresent(String.self, forKey: .cellGroupId)
            currentLevel = (try? c.decodeIfPresent(Int.self, forKey: .currentLevel)) ?? 1
            band = try? c.decodeIfPresent(String.self, forKey: .band)
            streakDays = (try? c.decodeIfPresent(Int.self, forKey: .streakDays)) ?? 0
            daysSinceLastActivity = try? c.decodeIfPresent(Int.self, forKey: .daysSinceLastActivity)
            pendingReflections = (try? c.decodeIfPresent(Int.self, forKey: .pendingReflections)) ?? 0
            awaitingLevel = try? c.decodeIfPresent(Int.self, forKey: .awaitingLevel)
        }
    }
}

// Tolerant decoding for the nested cards lives in extensions so the memberwise
// inits stay available for the sparse-payload fallbacks above.
extension DiscipleRoster.Summary {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        totalStudents = (try? c.decodeIfPresent(Int.self, forKey: .totalStudents)) ?? 0
        awaitingAction = (try? c.decodeIfPresent(Int.self, forKey: .awaitingAction)) ?? 0
    }
}

/// The whole `{ data: … }` payload for one student's dossier —
/// GET /disciples/{id}.
struct DiscipleDossier: Codable, Sendable {
    let member: Member
    let progression: Progression
    let scores: Scores
    let engagement: Engagement
    /// Most-recent first (server-capped).
    let reflections: [Reflection]
    let recentActivity: [Activity]
    /// Present only when a 1:1 DM already exists (a GET never creates one); the
    /// Message CTA opens it directly. When nil the CTA creates it via POST /chat/dms.
    let dmConversationId: String?

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        member = (try? c.decodeIfPresent(Member.self, forKey: .member))
            ?? Member(userId: "", fullName: "", avatarUrl: nil, cellName: nil,
                      establishedAt: nil, joinedAt: nil)
        progression = (try? c.decodeIfPresent(Progression.self, forKey: .progression))
            ?? Progression(currentLevel: 1, levelTitle: "", streakDays: 0,
                           modulesCompleted: 0, modulesTotal: 0, awaitingLevel: nil)
        scores = (try? c.decodeIfPresent(Scores.self, forKey: .scores))
            ?? Scores(overall: nil, word: nil, prayer: nil, habits: nil,
                      curriculum: nil, attendance: nil)
        engagement = (try? c.decodeIfPresent(Engagement.self, forKey: .engagement))
            ?? Engagement(eScore: nil, band: nil, daysSinceLastActivity: nil)
        reflections = (try? c.decodeIfPresent([Reflection].self, forKey: .reflections)) ?? []
        recentActivity = (try? c.decodeIfPresent([Activity].self, forKey: .recentActivity)) ?? []
        dmConversationId = try? c.decodeIfPresent(String.self, forKey: .dmConversationId)
    }

    /// Who the student is.
    struct Member: Codable, Sendable {
        let userId: String
        let fullName: String
        let avatarUrl: String?
        let cellName: String?
        /// When the discipleship relationship was established — "In your care since …".
        let establishedAt: String?
        let joinedAt: String?
    }

    /// Where the student is on the pathway (server-authoritative, §1.9).
    struct Progression: Codable, Sendable {
        let currentLevel: Int
        let levelTitle: String
        let streakDays: Int
        let modulesCompleted: Int
        let modulesTotal: Int
        /// Non-nil when the student awaits the leader's usher into this level.
        let awaitingLevel: Int?
    }

    /// The six growth scores (0..100), each nil until computed.
    struct Scores: Codable, Sendable {
        let overall: Int?
        let word: Int?
        let prayer: Int?
        let habits: Int?
        let curriculum: Int?
        let attendance: Int?
    }

    /// Engagement health — e-score, band and recency.
    struct Engagement: Codable, Sendable {
        let eScore: Int?
        /// thriving | steady | watch | at_risk.
        let band: String?
        let daysSinceLastActivity: Int?
    }

    /// One of the student's reflections, INCLUDING the body (the leader reads
    /// what the student wrote) plus the leader's own feedback when given.
    struct Reflection: Codable, Sendable, Identifiable {
        let reflectionId: String
        let moduleId: String
        let moduleTitle: String
        let levelNumber: Int
        /// approved | pending | returned | deferred.
        let state: String
        let submittedAt: String
        let body: String?
        let feedbackNotes: String?

        var id: String { reflectionId }
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            reflectionId = (try? c.decodeIfPresent(String.self, forKey: .reflectionId)) ?? ""
            moduleId = (try? c.decodeIfPresent(String.self, forKey: .moduleId)) ?? ""
            moduleTitle = (try? c.decodeIfPresent(String.self, forKey: .moduleTitle)) ?? ""
            levelNumber = (try? c.decodeIfPresent(Int.self, forKey: .levelNumber)) ?? 0
            state = (try? c.decodeIfPresent(String.self, forKey: .state)) ?? ""
            submittedAt = (try? c.decodeIfPresent(String.self, forKey: .submittedAt)) ?? ""
            body = try? c.decodeIfPresent(String.self, forKey: .body)
            feedbackNotes = try? c.decodeIfPresent(String.self, forKey: .feedbackNotes)
        }
    }

    /// One recent-activity event ("module_completed" → "Module completed").
    struct Activity: Codable, Sendable {
        let kind: String
        let occurredAt: String
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
            occurredAt = (try? c.decodeIfPresent(String.self, forKey: .occurredAt)) ?? ""
        }
    }
}

extension DiscipleDossier.Member {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        cellName = try? c.decodeIfPresent(String.self, forKey: .cellName)
        establishedAt = try? c.decodeIfPresent(String.self, forKey: .establishedAt)
        joinedAt = try? c.decodeIfPresent(String.self, forKey: .joinedAt)
    }
}

extension DiscipleDossier.Progression {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        currentLevel = (try? c.decodeIfPresent(Int.self, forKey: .currentLevel)) ?? 1
        levelTitle = (try? c.decodeIfPresent(String.self, forKey: .levelTitle)) ?? ""
        streakDays = (try? c.decodeIfPresent(Int.self, forKey: .streakDays)) ?? 0
        modulesCompleted = (try? c.decodeIfPresent(Int.self, forKey: .modulesCompleted)) ?? 0
        modulesTotal = (try? c.decodeIfPresent(Int.self, forKey: .modulesTotal)) ?? 0
        awaitingLevel = try? c.decodeIfPresent(Int.self, forKey: .awaitingLevel)
    }
}
