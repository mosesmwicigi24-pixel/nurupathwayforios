// Typed endpoint facade over APIClient — the native counterpart of the NuruApi
// object in packages/mobile/src/api/client.ts. Screens call these, never the raw
// client. Only the endpoints needed by the current slice are wired; the rest are
// ported screen-by-screen (see PORT_STATUS.md).
import Foundation

enum MemberAPI {
    // MARK: Auth

    /// POST /auth/login — may yield a 2FA challenge instead of a session.
    static func login(email: String, password: String) async throws -> LoginResult {
        try await APIClient.shared.login(email: email, password: password)
    }

    static func completeMfa(mfaToken: String, code: String) async throws -> Session {
        try await APIClient.shared.completeMfa(mfaToken: mfaToken, code: code)
    }

    // MARK: Profile

    /// GET /me — the signed-in member's profile + enrollment summary.
    static func me() async throws -> MeResponse {
        try await APIClient.shared.get("me", as: MeResponse.self)
    }

    // MARK: Home (server-driven dashboard)

    /// GET /me/rhythm/today — today's three daily rhythms.
    static func rhythmToday() async throws -> RhythmToday {
        try await APIClient.shared.get("me/rhythm/today", as: RhythmToday.self)
    }

    /// GET /me/home/next-action — the next-best-action hero card (may be null).
    static func nextAction() async throws -> NextAction? {
        try await APIClient.shared.get("me/home/next-action", as: NextActionEnvelope.self).action
    }

    /// POST /me/rhythm/complete — mark a rhythm done for today (idempotent).
    static func completeRhythm(_ kind: String) async throws -> RhythmToday {
        struct Body: Encodable { let kind: String }
        return try await APIClient.shared.post("me/rhythm/complete", body: Body(kind: kind), as: RhythmToday.self)
    }

    // MARK: Pathway (levels · modules · quiz — server-authoritative gating §1.9)

    /// GET /me/pathway — the member's level trail with per-level progress + status.
    static func pathway() async throws -> PathwaySummary {
        try await APIClient.shared.get("me/pathway", as: PathwaySummary.self)
    }

    /// GET /levels/{n}/modules — the module trail for a level.
    static func levelModules(_ levelNumber: Int) async throws -> [LevelModule] {
        try await APIClient.shared.get("levels/\(levelNumber)/modules", as: Envelope<LevelModule>.self).data
    }

    /// GET /modules/{id} — full lesson + evaluation metadata. Server refuses
    /// content above the member's current level (§1.9); we also honour `locked`.
    static func module(_ moduleId: String) async throws -> ModuleDetail {
        try await APIClient.shared.get("modules/\(moduleId)", as: ModuleDetail.self)
    }

    /// POST /modules/{id}/complete — finish a non-quiz module (optional reflection).
    static func completeModule(_ moduleId: String, reflectionText: String? = nil) async throws -> CompleteResult {
        struct Body: Encodable { let reflectionText: String? }
        return try await APIClient.shared.post("modules/\(moduleId)/complete",
                                               body: Body(reflectionText: reflectionText), as: CompleteResult.self)
    }

    /// GET /modules/{id}/quiz — the server-assembled quiz (answer signal stripped).
    static func quiz(_ moduleId: String) async throws -> AssembledQuiz {
        try await APIClient.shared.get("modules/\(moduleId)/quiz", as: AssembledQuiz.self)
    }

    /// POST /modules/{id}/quiz/attempts — submit answers; scored server-side (§3.7).
    /// `clientMutationId` keeps the attempt idempotent on replay (§2.1/§3.6).
    static func submitQuiz(_ moduleId: String, clientMutationId: String,
                           answers: [QuizAnswer]) async throws -> QuizResult {
        struct Body: Encodable { let clientMutationId: String; let answers: [QuizAnswer] }
        return try await APIClient.shared.post("modules/\(moduleId)/quiz/attempts",
                                               body: Body(clientMutationId: clientMutationId, answers: answers),
                                               as: QuizResult.self)
    }
}

extension MemberAPI {
    // MARK: Growth — daily rhythm & Word
    //
    // NOTE: the writes here (reflection, practice, plan/segment completion, prayer
    // upsert/delete, verse save/delete) currently go online-first. They are
    // retrofitted onto `SyncEngine.writeThrough` (offline queue, §1.7/§3.6) when
    // the offline-engine phase lands — the RN app queued these.

    /// GET /growth/devotional — today's devotional (+ my saved reflection if any).
    static func devotional() async throws -> Devotional {
        try await APIClient.shared.get("growth/devotional", as: Devotional.self)
    }

    /// POST /growth/devotional/reflection — save a reflection; marks the Reflection rhythm.
    @discardableResult
    static func saveDevotionalReflection(devotionalId: String, body: String) async throws -> Bool {
        struct Body: Encodable { let devotionalId: String; let body: String }
        struct Saved: Decodable { let saved: Bool }
        return try await APIClient.shared.post("growth/devotional/reflection",
                                               body: Body(devotionalId: devotionalId, body: body), as: Saved.self).saved
    }

    /// GET /growth/memory-verses — the member's memory-verse set with status.
    static func memoryVerses() async throws -> [MemoryVerseRow] {
        try await APIClient.shared.get("growth/memory-verses", as: Envelope<MemoryVerseRow>.self).data
    }

    /// POST /growth/memory-verses/practice — log a practice attempt (match %).
    static func practiceVerse(_ memoryVerseId: String, matchPct: Int) async throws {
        struct Body: Encodable { let memoryVerseId: String; let matchPct: Int }
        _ = try await APIClient.shared.post("growth/memory-verses/practice",
                                            body: Body(memoryVerseId: memoryVerseId, matchPct: matchPct), as: EmptyResponse.self)
    }

    /// GET /growth/plans — the reading-plan catalogue with enrolment state.
    static func plans() async throws -> [ReadingPlanRow] {
        try await APIClient.shared.get("growth/plans", as: Envelope<ReadingPlanRow>.self).data
    }

    /// GET /growth/plans/{id} — a plan with its day-by-day breakdown.
    static func plan(_ id: String) async throws -> ReadingPlanDetail {
        try await APIClient.shared.get("growth/plans/\(id)", as: ReadingPlanDetail.self)
    }

    /// POST /growth/plans/{id}/start — enrol in a plan.
    static func startPlan(_ id: String) async throws {
        _ = try await APIClient.shared.postEmpty("growth/plans/\(id)/start", as: EmptyResponse.self)
    }

    /// POST /growth/plans/{id}/complete-day — mark a whole day done.
    static func completePlanDay(_ id: String, dayNumber: Int) async throws {
        struct Body: Encodable { let dayNumber: Int }
        _ = try await APIClient.shared.post("growth/plans/\(id)/complete-day",
                                            body: Body(dayNumber: dayNumber), as: EmptyResponse.self)
    }

    /// POST /growth/segments/{id}/complete — mark one plan-day segment done.
    @discardableResult
    static func completePlanSegment(_ segmentId: String) async throws -> SegmentCompleteResult {
        try await APIClient.shared.postEmpty("growth/segments/\(segmentId)/complete", as: SegmentCompleteResult.self)
    }

    // MARK: Prayer journal

    /// GET /me/prayers — the member's private prayer journal.
    static func prayers() async throws -> [PrayerEntry] {
        try await APIClient.shared.get("me/prayers", as: Envelope<PrayerEntry>.self).data
    }

    /// PUT /me/prayers — create or update an entry (idempotent on entry_id).
    static func upsertPrayer(entryId: String, body: String, title: String? = nil,
                             isAnswered: Bool = false, answeredNote: String? = nil) async throws {
        struct Body: Encodable {
            let entryId: String; let title: String?; let body: String
            let isAnswered: Bool; let answeredNote: String?; let clientMutationId: String
        }
        _ = try await APIClient.shared.put("me/prayers",
            body: Body(entryId: entryId, title: title, body: body, isAnswered: isAnswered,
                       answeredNote: answeredNote, clientMutationId: UUID().uuidString), as: EmptyResponse.self)
    }

    /// DELETE /me/prayers/{id}.
    static func deletePrayer(_ entryId: String) async throws {
        _ = try await APIClient.shared.delete("me/prayers/\(entryId)", as: EmptyResponse.self)
    }

    // MARK: Verse library (saved verses)

    /// GET /me/verses — the member's saved-verse library.
    static func verses() async throws -> [SavedVerse] {
        try await APIClient.shared.get("me/verses", as: Envelope<SavedVerse>.self).data
    }

    /// PUT /me/verses — save/update a verse (idempotent on saved_verse_id).
    static func saveVerse(savedVerseId: String, reference: String, version: String? = nil,
                          verseText: String? = nil, note: String? = nil) async throws {
        struct Body: Encodable {
            let savedVerseId: String; let reference: String; let version: String?
            let verseText: String?; let note: String?; let clientMutationId: String
        }
        _ = try await APIClient.shared.put("me/verses",
            body: Body(savedVerseId: savedVerseId, reference: reference, version: version,
                       verseText: verseText, note: note, clientMutationId: UUID().uuidString), as: EmptyResponse.self)
    }

    /// DELETE /me/verses/{id}.
    static func deleteVerse(_ savedVerseId: String) async throws {
        _ = try await APIClient.shared.delete("me/verses/\(savedVerseId)", as: EmptyResponse.self)
    }
}

/// One submitted answer — `givenAnswer` is always a string per the wire contract
/// (checkbox carries a JSON array of selected ids; scale carries the number).
struct QuizAnswer: Encodable, Sendable {
    let questionId: String
    let givenAnswer: String
}

/// Generic `{ "data": [...] }` list envelope used by several collection endpoints.
struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: [T]
}
