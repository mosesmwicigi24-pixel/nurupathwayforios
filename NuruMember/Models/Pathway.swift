// Pathway DTOs — Swift mirrors of the Level/Module/Quiz contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

// MARK: - Levels

enum LevelStatus: String, Codable, Sendable { case completed, active, locked }

struct PathwayLevel: Codable, Sendable, Identifiable {
    let levelNumber: Int
    let title: String
    let theme: String?
    let description: String?
    let totalModules: Int
    let completedModules: Int
    let minutes: Int
    let status: LevelStatus

    var id: Int { levelNumber }
}

struct PathwaySummary: Codable, Sendable {
    let currentLevel: Int
    let levels: [PathwayLevel]
}

// MARK: - Modules

enum ModuleStatus: String, Codable, Sendable { case completed, next, locked }

struct LevelModule: Codable, Sendable, Identifiable {
    let moduleId: String
    let levelNumber: Int
    let moduleSequenceNumber: Int
    let title: String
    let summary: String?
    let estimatedMinutes: Int?
    let evaluationKind: String
    let quizPassMark: Int
    let completed: Bool
    let status: ModuleStatus
    let progress: Double
    let locked: Bool

    var id: String { moduleId }
}

struct ModuleDetail: Codable, Sendable {
    let moduleId: String
    let levelNumber: Int
    let moduleSequenceNumber: Int
    let title: String
    let lessonContent: String
    let summary: String?
    let keyVerses: [String]?
    let videoUrl: String?
    let evaluationKind: String
    let estimatedMinutes: Int?
    let quizPassMark: Int
    let currentVersion: Int
    let locked: Bool

    /// True when finishing this module requires a graded quiz (vs. mark-complete).
    var requiresQuiz: Bool { evaluationKind.lowercased().contains("quiz") }
}

struct CompleteResult: Codable, Sendable {
    let progressId: String
    let moduleId: String
    let isCompleted: Bool
    let duplicate: Bool
    let nextModuleUnlocked: Bool
}

// MARK: - Quiz (server-assembled, server-scored — §1.3/§3.7)

enum QuestionKind { case single, checkbox, short, paragraph, scale }

struct QuestionChoice: Sendable, Identifiable {
    let id: String
    let text: String
}

struct QuestionScale: Sendable {
    let min: Int
    let max: Int
    let minLabel: String?
    let maxLabel: String?
}

struct QuizQuestion: Decodable, Sendable, Identifiable {
    let questionId: String
    let qType: String
    let questionText: String
    let points: Int?
    let required: Bool?

    // Decoded from the polymorphic answer_options (string[] | {choices} | {scale} | null).
    let choices: [QuestionChoice]
    let scale: QuestionScale?

    var id: String { questionId }

    var kind: QuestionKind {
        switch qType {
        case "checkbox": return .checkbox
        case "short_answer": return .short
        case "paragraph": return .paragraph
        case "linear_scale": return .scale
        // multiple_choice / dropdown / legacy MultipleChoice / unknown → single-select
        default: return .single
        }
    }

    private enum CodingKeys: String, CodingKey {
        case questionId, qType, questionText, points, required, answerOptions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        questionId = try c.decode(String.self, forKey: .questionId)
        qType = try c.decode(String.self, forKey: .qType)
        questionText = try c.decode(String.self, forKey: .questionText)
        points = try c.decodeIfPresent(Int.self, forKey: .points)
        required = try c.decodeIfPresent(Bool.self, forKey: .required)

        // Polymorphic answer_options decoding.
        var decodedChoices: [QuestionChoice] = []
        var decodedScale: QuestionScale?
        if let strings = try? c.decode([String].self, forKey: .answerOptions) {
            decodedChoices = strings.map { QuestionChoice(id: $0, text: $0) }
        } else if let obj = try? c.decode(AnswerOptionsObject.self, forKey: .answerOptions) {
            if let cs = obj.choices { decodedChoices = cs.map { QuestionChoice(id: $0.id, text: $0.text) } }
            if let s = obj.scale {
                decodedScale = QuestionScale(min: s.min, max: s.max, minLabel: s.minLabel, maxLabel: s.maxLabel)
            }
        }
        choices = decodedChoices
        scale = decodedScale
    }

    /// Intermediate decode shape for the object form of answer_options.
    private struct AnswerOptionsObject: Decodable {
        struct Choice: Decodable { let id: String; let text: String }
        struct Scale: Decodable { let min: Int; let max: Int; let minLabel: String?; let maxLabel: String? }
        let choices: [Choice]?
        let scale: Scale?
    }
}

struct AssembledQuiz: Decodable, Sendable {
    let moduleId: String
    let questionCount: Int
    let questions: [QuizQuestion]
}

struct QuizResult: Decodable, Sendable {
    let attemptId: String
    let scoreAchieved: Int
    let isPassed: Bool
    let passMark: Int
    let unlockedNextModuleId: String?
    let requiresManualReview: Bool
    let duplicate: Bool
}
