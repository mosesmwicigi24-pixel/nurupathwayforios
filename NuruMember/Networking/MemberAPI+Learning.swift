// Living curriculum (intelligence Phase 3).
//   • GET  modules/{id}/explain?style=simple|swahili|story — the lesson re-rendered
//   • POST modules/{id}/quiz/remediation — "Review with Nuru" after a failed quiz
import Foundation

struct LessonExplanation: Codable, Sendable {
    let style: String
    let body: String
    let cached: Bool
}

struct QuizRemediation: Codable, Sendable {
    let attemptId: String
    let body: String
    let missed: Int
    let cached: Bool
}

extension MemberAPI {
    static func explainLesson(_ moduleId: String, style: String) async throws -> LessonExplanation {
        try await APIClient.shared.get("modules/\(moduleId)/explain?style=\(style)", as: LessonExplanation.self)
    }

    static func quizRemediation(_ moduleId: String) async throws -> QuizRemediation {
        struct Empty: Encodable {}
        return try await APIClient.shared.post("modules/\(moduleId)/quiz/remediation", body: Empty(), as: QuizRemediation.self)
    }
}
