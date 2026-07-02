// Level exam + encouragements — the level-gate endpoints (§1.9 rule 2) and the
// trail's motivational content. Mirrors packages/backend/src/modules/assessment
// (exam.ts) and modules/encouragements exactly: the exam paper is assembled
// server-side over the level's whole active question pool with the correct-answer
// signal stripped (§5.8), and every attempt is scored server-side against
// levels.required_exam_pass_mark — the client only collects answers. Attempts are
// idempotent on client_mutation_id (§2.1/§3.6). JSON is snake_case on the wire;
// APIClient decodes with `.convertFromSnakeCase`.
import Foundation

// MARK: - Models

/// GET /levels/{n}/exam → { level_number, question_count, questions }. The rows
/// carry question_id / q_type / question_text / answer_options (stripped), the
/// same wire shape as a module quiz, so they decode as `QuizQuestion`.
struct AssembledExam: Decodable, Sendable {
    let levelNumber: Int
    let questionCount: Int
    let questions: [QuizQuestion]
}

/// POST /levels/{n}/exam/attempts → the ExamResult interface in exam.ts. The
/// verdict is entirely the server's: score over the auto-gradable set, pass mark,
/// whether written answers still need a mentor, and whether this was a replay.
struct ExamResult: Decodable, Sendable {
    let examAttemptId: String
    @FlexInt var scoreAchieved: Int
    let isPassed: Bool
    @FlexInt var passMark: Int
    let requiresManualReview: Bool
    let duplicate: Bool
}

/// GET /levels/{n}/encouragements → { data: [...] } rows from level_encouragements
/// (service.ts SELECT_COLS). Everything textual is nullable — content is authored
/// gradually in the Content Studio, so the client renders whatever exists.
struct LevelEncouragement: Decodable, Sendable, Identifiable {
    let encouragementId: String
    let levelNumber: Int
    let afterModuleSequence: Int
    let kind: String?          // splash | cheer | sticker | note | celebration | nudge | verse
    let title: String?
    let body: String?
    let imageUrl: String?
    let scriptureRef: String?
    let emoji: String?
    let isActive: Bool?
    let sortOrder: Int?

    var id: String { encouragementId }
}

// MARK: - Endpoints

extension MemberAPI {
    /// GET /levels/{n}/exam — the assembled level exam (no answers leaked, §5.8).
    /// The server refuses with GATE_LOCKED until every module in the level is
    /// finished (and the level itself is reachable) — eligibility is its answer.
    static func levelExam(_ levelNumber: Int) async throws -> AssembledExam {
        try await APIClient.shared.get("levels/\(levelNumber)/exam", as: AssembledExam.self)
    }

    /// POST /levels/{n}/exam/attempts — submit answers; scored server-side
    /// against the level's whole active pool (unanswered = wrong, §5.8).
    /// `clientMutationId` keeps the attempt idempotent on replay (§2.1/§3.6).
    static func submitLevelExam(_ levelNumber: Int, clientMutationId: String,
                                answers: [QuizAnswer]) async throws -> ExamResult {
        struct Body: Encodable { let clientMutationId: String; let answers: [QuizAnswer] }
        return try await APIClient.shared.post("levels/\(levelNumber)/exam/attempts",
                                               body: Body(clientMutationId: clientMutationId, answers: answers),
                                               as: ExamResult.self)
    }

    /// GET /levels/{n}/encouragements — a level's active encouragements in trail
    /// order (after_module_sequence, sort_order). Empty until content is authored.
    static func levelEncouragements(_ levelNumber: Int) async throws -> [LevelEncouragement] {
        try await APIClient.shared.get("levels/\(levelNumber)/encouragements",
                                       as: Envelope<LevelEncouragement>.self).data
    }
}
