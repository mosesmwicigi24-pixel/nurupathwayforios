// Growth / daily-rhythm DTOs — Swift mirrors of the devotional, memory-verse,
// reading-plan, prayer-journal and saved-verse contracts in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
// Reading-plan types are Hashable so they can drive value-based navigation.
import Foundation

// MARK: - Devotional

struct Devotional: Codable, Sendable {
    let devotionalId: String
    let dayNumber: Int
    let series: String?
    let title: String
    let scriptureRef: String?
    let scriptureText: String?
    let body: String
    let reflectionPrompt: String?
    let audioUrl: String?
    let videoUrl: String?
    let myReflection: String?
}

// MARK: - Memory verses

struct MemoryVerseRow: Codable, Sendable, Identifiable {
    let memoryVerseId: String
    let reference: String
    let verseText: String
    let version: String
    let weekNumber: Int?
    let status: String   // learning | mastered
    let bestMatchPct: Int

    var id: String { memoryVerseId }
    var isMastered: Bool { status == "mastered" }
}

// MARK: - Reading plans

struct ReadingPlanRow: Codable, Sendable, Identifiable, Hashable {
    let planId: String
    let code: String?
    let title: String
    let subtitle: String?
    let description: String?
    let category: String?
    let imageUrl: String?
    let dayCount: Int
    let currentDay: Int?
    let completedDays: [Int]?
    let enrolled: Bool
    let completedAt: String?

    var id: String { planId }
}

struct PlanSegment: Codable, Sendable, Identifiable, Hashable {
    let segmentId: String
    let sort: Int
    let kind: String   // devotional | scripture | video | talk | reading
    let title: String
    let reference: String?
    let content: String?
    let videoUrl: String?
    let imageUrl: String?
    let completed: Bool

    var id: String { segmentId }
}

struct ReadingPlanDay: Codable, Sendable, Identifiable, Hashable {
    let dayNumber: Int
    let reference: String
    let title: String?
    let content: String?
    let segments: [PlanSegment]?
    let completed: Bool?

    var id: Int { dayNumber }
}

/// `/growth/plans/{id}` — the row plus its day-by-day breakdown.
struct ReadingPlanDetail: Codable, Sendable {
    let planId: String
    let title: String
    let subtitle: String?
    let description: String?
    let category: String?
    let imageUrl: String?
    let dayCount: Int
    let currentDay: Int?
    let completedDays: [Int]?
    let enrolled: Bool
    let days: [ReadingPlanDay]
}

struct SegmentCompleteResult: Codable, Sendable {
    struct Progress: Codable, Sendable {
        let planId: String
        let currentDay: Int
        let completedDays: [Int]
        let completedAt: String?
    }
    let segmentId: String
    let dayNumber: Int
    let dayCompleted: Bool
    let progress: Progress?
}

/// Navigation reference for a single plan day (the day + its owning plan id).
struct PlanDayRef: Hashable {
    let planId: String
    let day: ReadingPlanDay
}

// MARK: - Prayer journal

struct PrayerEntry: Codable, Sendable, Identifiable {
    let entryId: String
    let title: String?
    let body: String
    let isAnswered: Bool
    let answeredNote: String?
    let answeredAt: String?
    let createdAt: String
    let updatedAt: String

    var id: String { entryId }
}

// MARK: - Saved verses (Verse Library)

struct SavedVerse: Codable, Sendable, Identifiable {
    let savedVerseId: String
    let reference: String
    let version: String
    let verseText: String?
    let note: String?
    let createdAt: String

    var id: String { savedVerseId }
}
