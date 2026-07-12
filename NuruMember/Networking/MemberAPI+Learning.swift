// Living curriculum (intelligence Phase 3).
//   • GET  modules/{id}/explain?style=simple|swahili|story — the lesson re-rendered
//   • POST modules/{id}/quiz/remediation — "Review with Nuru" after a failed quiz
import Foundation

struct LessonExplanation: Codable, Sendable {
    let style: String
    let body: String
    let cached: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        style = (try? c.decodeIfPresent(String.self, forKey: .style)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        cached = (try? c.decodeIfPresent(Bool.self, forKey: .cached)) ?? false
    }
}

struct QuizRemediation: Codable, Sendable {
    let attemptId: String
    let body: String
    let missed: Int
    let cached: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        attemptId = (try? c.decodeIfPresent(String.self, forKey: .attemptId)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        missed = (try? c.decodeIfPresent(Int.self, forKey: .missed)) ?? 0
        cached = (try? c.decodeIfPresent(Bool.self, forKey: .cached)) ?? false
    }
}

extension MemberAPI {
    static func explainLesson(_ moduleId: String, style: String) async throws -> LessonExplanation {
        try await APIClient.shared.get("modules/\(moduleId)/explain", query: ["style": style], as: LessonExplanation.self)
    }

    static func quizRemediation(_ moduleId: String) async throws -> QuizRemediation {
        struct Empty: Encodable {}
        return try await APIClient.shared.post("modules/\(moduleId)/quiz/remediation", body: Empty(), as: QuizRemediation.self)
    }
}
