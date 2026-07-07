// Home-dashboard DTOs — Swift mirrors of the home contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

/// GET /me/achievements — badges + streak. Home uses the streak count and
/// diffs the earned badge codes to celebrate newly-awarded badges.
struct Achievements: Codable, Sendable {
    struct Streak: Codable, Sendable { let current: Int; let longest: Int }
    struct Badge: Codable, Sendable { let code: String; let name: String }
    let streak: Streak
    let badges: [Badge]?
}

/// GET /me/home/verse — the tailored "Verse for today".
struct TailoredVerse: Codable, Sendable {
    let reference: String
    let version: String
    let theme: String?
    let reason: String?
    let text: String?
}

/// GET /scripture?ref= — a looked-up passage (used when the tailored verse has no text).
struct ScripturePassage: Codable, Sendable {
    let reference: String
    let version: String
    let text: String
}

/// Verse-of-the-day reactions — community counts for today's shared verse.
struct VerseReactions: Codable, Sendable {
    let counts: [String: Int]
    let mine: String?
    let total: Int
}

/// One growth discipline's score (GET /me/scores).
struct GrowthScore: Codable, Sendable {
    let score: Int
    let band: String?
}

/// The rolling growth trend — this 28-day window vs the previous 28 days.
struct ScoreTrend: Codable, Sendable {
    let windowDays: Int
    let previous: Int
    let delta: Int
    let direction: String        // "up" | "down" | "flat"
    let domains: [String: Int]?  // per-domain delta (habits/curriculum/…)

    var isUp: Bool { direction == "up" }
    var isDown: Bool { direction == "down" }
}

/// GET /me/scores — the five growth scores + a weighted overall + a 28-day trend.
struct ScoresSummary: Codable, Sendable {
    struct Overall: Codable, Sendable { let score: Int; let band: String }
    let overall: Overall
    let habits: GrowthScore
    let curriculum: GrowthScore
    let attendance: GrowthScore
    let word: GrowthScore
    let prayer: GrowthScore
    /// Optional so a pre-trend server response still decodes.
    let trend: ScoreTrend?
}
