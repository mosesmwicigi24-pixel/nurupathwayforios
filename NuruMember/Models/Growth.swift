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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        devotionalId = try c.decode(String.self, forKey: .devotionalId)
        dayNumber = (try? c.decodeIfPresent(Int.self, forKey: .dayNumber)) ?? 0
        series = try? c.decodeIfPresent(String.self, forKey: .series)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        scriptureRef = try? c.decodeIfPresent(String.self, forKey: .scriptureRef)
        scriptureText = try? c.decodeIfPresent(String.self, forKey: .scriptureText)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        reflectionPrompt = try? c.decodeIfPresent(String.self, forKey: .reflectionPrompt)
        audioUrl = try? c.decodeIfPresent(String.self, forKey: .audioUrl)
        videoUrl = try? c.decodeIfPresent(String.self, forKey: .videoUrl)
        myReflection = try? c.decodeIfPresent(String.self, forKey: .myReflection)
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        memoryVerseId = try c.decode(String.self, forKey: .memoryVerseId)
        reference = (try? c.decodeIfPresent(String.self, forKey: .reference)) ?? ""
        verseText = (try? c.decodeIfPresent(String.self, forKey: .verseText)) ?? ""
        version = (try? c.decodeIfPresent(String.self, forKey: .version)) ?? "WEB"
        weekNumber = try? c.decodeIfPresent(Int.self, forKey: .weekNumber)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "learning"
        bestMatchPct = (try? c.decodeIfPresent(Int.self, forKey: .bestMatchPct)) ?? 0
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        planId = try c.decode(String.self, forKey: .planId)
        code = try? c.decodeIfPresent(String.self, forKey: .code)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        dayCount = (try? c.decodeIfPresent(Int.self, forKey: .dayCount)) ?? 0
        currentDay = try? c.decodeIfPresent(Int.self, forKey: .currentDay)
        completedDays = try? c.decodeIfPresent([Int].self, forKey: .completedDays)
        enrolled = (try? c.decodeIfPresent(Bool.self, forKey: .enrolled)) ?? false
        completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
    }
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

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the hand-built Home rhythm segments.
extension PlanSegment {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        segmentId = try c.decode(String.self, forKey: .segmentId)
        sort = (try? c.decodeIfPresent(Int.self, forKey: .sort)) ?? 0
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "reading"
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        reference = try? c.decodeIfPresent(String.self, forKey: .reference)
        content = try? c.decodeIfPresent(String.self, forKey: .content)
        videoUrl = try? c.decodeIfPresent(String.self, forKey: .videoUrl)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? false
    }
}

struct ReadingPlanDay: Codable, Sendable, Identifiable, Hashable {
    let dayNumber: Int
    let reference: String
    let title: String?
    let content: String?
    let segments: [PlanSegment]?
    let completed: Bool?
    /// Server-decided: true while an earlier day is still unfinished. A locked
    /// day arrives with its shape (title, reference, the kinds of its parts) but
    /// its `content` and `video_url` withheld — there is nothing to render past
    /// the gate even if a client tried.
    let locked: Bool

    var id: Int { dayNumber }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        dayNumber = try c.decode(Int.self, forKey: .dayNumber)
        reference = (try? c.decodeIfPresent(String.self, forKey: .reference)) ?? ""
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        content = try? c.decodeIfPresent(String.self, forKey: .content)
        segments = try? c.decodeIfPresent([PlanSegment].self, forKey: .segments)
        completed = try? c.decodeIfPresent(Bool.self, forKey: .completed)
        // Absent on an older server: nothing is locked, as before.
        locked = (try? c.decodeIfPresent(Bool.self, forKey: .locked)) ?? false
    }
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
    /// The first day not yet finished — the one day to point someone back to.
    /// Null once the whole plan is done.
    let nextDay: Int?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        planId = try c.decode(String.self, forKey: .planId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        subtitle = try? c.decodeIfPresent(String.self, forKey: .subtitle)
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        imageUrl = try? c.decodeIfPresent(String.self, forKey: .imageUrl)
        dayCount = (try? c.decodeIfPresent(Int.self, forKey: .dayCount)) ?? 0
        currentDay = try? c.decodeIfPresent(Int.self, forKey: .currentDay)
        completedDays = try? c.decodeIfPresent([Int].self, forKey: .completedDays)
        enrolled = (try? c.decodeIfPresent(Bool.self, forKey: .enrolled)) ?? false
        days = (try? c.decodeIfPresent([ReadingPlanDay].self, forKey: .days)) ?? []
        nextDay = try? c.decodeIfPresent(Int.self, forKey: .nextDay)
    }
}

struct SegmentCompleteResult: Codable, Sendable {
    struct Progress: Codable, Sendable {
        let planId: String
        let currentDay: Int
        let completedDays: [Int]
        let completedAt: String?
        init(from d: Decoder) throws {
            let c = try d.container(keyedBy: CodingKeys.self)
            planId = (try? c.decodeIfPresent(String.self, forKey: .planId)) ?? ""
            currentDay = (try? c.decodeIfPresent(Int.self, forKey: .currentDay)) ?? 0
            completedDays = (try? c.decodeIfPresent([Int].self, forKey: .completedDays)) ?? []
            completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
        }
    }
    let segmentId: String
    let dayNumber: Int
    let dayCompleted: Bool
    let progress: Progress?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        segmentId = (try? c.decodeIfPresent(String.self, forKey: .segmentId)) ?? ""
        dayNumber = (try? c.decodeIfPresent(Int.self, forKey: .dayNumber)) ?? 0
        dayCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .dayCompleted)) ?? false
        progress = try? c.decodeIfPresent(Progress.self, forKey: .progress)
    }
}

/// Navigation reference for a single plan day (the day + its owning plan id).
struct PlanDayRef: Hashable {
    let planId: String
    let day: ReadingPlanDay
    var planTitle: String? = nil   // for the completion keepsake ("You completed …")
}

/// Navigation reference for one plan-day segment (Watch / Read / Devotional / Talk),
/// carrying its sibling segments + day so the segment screen can page next/prev.
struct PlanSegmentRef: Hashable {
    let planTitle: String
    let dayNumber: Int
    let segments: [PlanSegment]
    let index: Int
    var planId: String? = nil   // enables the reflection box on the Respond page
    /// Which combined page to open: "media" (one video/audio), "word"
    /// (Scripture + Devotional + Go Deeper) or "respond" (Talk + Prayer +
    /// Reflection). Nil = single-segment fallback.
    var part: String? = nil
    /// Segment ids already completed this session (the day's segment flags can be
    /// stale) — lets a reopened finished part greet with "Done", not a second ask.
    var doneIds: [String] = []
}

/// Navigation to a plan day's shared Talk it Over conversation.
struct TalkRoute: Hashable {
    let planId: String
    let dayNumber: Int
    let planTitle: String
    let prompt: String
    /// The day's talk segment — visiting the conversation marks it read
    /// (presence counts; nobody is forced to post publicly).
    var talkSegmentId: String? = nil
    var talkDone: Bool = false
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

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the optimistic insert in PrayerJournalView.
extension PrayerEntry {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        entryId = try c.decode(String.self, forKey: .entryId)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        isAnswered = (try? c.decodeIfPresent(Bool.self, forKey: .isAnswered)) ?? false
        answeredNote = try? c.decodeIfPresent(String.self, forKey: .answeredNote)
        answeredAt = try? c.decodeIfPresent(String.self, forKey: .answeredAt)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? ""
    }
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

// Tolerant decoding lives in an extension so the synthesized memberwise init
// survives for the optimistic insert in VerseLibraryView.
extension SavedVerse {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        savedVerseId = try c.decode(String.self, forKey: .savedVerseId)
        reference = (try? c.decodeIfPresent(String.self, forKey: .reference)) ?? ""
        version = (try? c.decodeIfPresent(String.self, forKey: .version)) ?? "WEB"
        verseText = try? c.decodeIfPresent(String.self, forKey: .verseText)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
    }
}
