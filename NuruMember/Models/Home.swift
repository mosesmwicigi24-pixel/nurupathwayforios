// Home-dashboard DTOs — Swift mirrors of the home contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

/// GET /me/achievements — badges + streak. Home uses the streak count and
/// diffs the earned badge codes to celebrate newly-awarded badges.
struct Achievements: Codable, Sendable {
    struct Streak: Codable, Sendable {
        var current: Int = 0
        var longest: Int = 0
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            current = (try? c.decodeIfPresent(Int.self, forKey: .current)) ?? 0
            longest = (try? c.decodeIfPresent(Int.self, forKey: .longest)) ?? 0
        }
    }
    struct Badge: Codable, Sendable { let code: String; let name: String }
    // Sparse payloads must degrade to zeros, not sink the card (Android parity).
    var streak: Streak? = nil
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
    var counts: [String: Int] = [:]
    var mine: String? = nil
    var total: Int = 0
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        counts = (try? c.decodeIfPresent([String: Int].self, forKey: .counts)) ?? [:]
        mine = try? c.decodeIfPresent(String.self, forKey: .mine)
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
    }
}

/// One growth discipline's score (GET /me/scores).
struct GrowthScore: Codable, Sendable {
    var score: Int = 0
    var band: String? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        band = try? c.decodeIfPresent(String.self, forKey: .band)
    }
    init(score: Int, band: String?) { self.score = score; self.band = band }
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
    struct Overall: Codable, Sendable {
        var score: Int = 0
        var band: String = "steady"
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
            band = (try? c.decodeIfPresent(String.self, forKey: .band)) ?? "steady"
        }
    }
    let overall: Overall
    let habits: GrowthScore
    let curriculum: GrowthScore
    let attendance: GrowthScore
    let word: GrowthScore
    let prayer: GrowthScore
    /// Optional so a pre-trend server response still decodes.
    let trend: ScoreTrend?
}
