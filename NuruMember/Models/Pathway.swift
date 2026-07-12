// Pathway DTOs — Swift mirrors of the Level/Module/Quiz contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

// MARK: - Levels

enum LevelStatus: String, Codable, Sendable {
    case completed, active, locked
    // Tolerate any status the server sends that we don't model (prod may use a
    // vocabulary this client predates) — decode unknowns to `locked` rather than
    // throwing, which would fail the whole pathway response and blank the page.
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = LevelStatus(rawValue: raw) ?? .locked
    }
}

struct PathwayLevel: Codable, Sendable, Identifiable {
    let levelNumber: Int
    let title: String
    let theme: String?
    let description: String?
    let totalModules: Int
    let completedModules: Int
    let minutes: Int
    let status: LevelStatus
    /// The member finished this level's exam and is now waiting to be ushered into
    /// the next level by a discipler (§1.9 — advancement is server-authoritative and
    /// no longer auto-advances on an exam pass). Optional + defaulted so payloads
    /// from servers that predate the waiting state still decode; the next level stays
    /// LOCKED while this is true. Cleared (→ false) once the discipler ushers and the
    /// member's current level advances.
    var awaitingReview: Bool = false
    /// The level's final exam is published (admin flipped review→publish). The
    /// exam gate is hidden until this is true. Defaults TRUE so payloads from a
    /// server that predates the gate keep showing the exam (no regression).
    var examPublished: Bool = true

    var id: Int { levelNumber }

    private enum CodingKeys: String, CodingKey {
        case levelNumber, title, theme, description, totalModules
        case completedModules, minutes, status, awaitingReview, examPublished
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        levelNumber = try c.decode(Int.self, forKey: .levelNumber)
        title = try c.decode(String.self, forKey: .title)
        theme = try c.decodeIfPresent(String.self, forKey: .theme)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        totalModules = (try? c.decodeIfPresent(Int.self, forKey: .totalModules)) ?? 0
        completedModules = (try? c.decodeIfPresent(Int.self, forKey: .completedModules)) ?? 0
        minutes = (try? c.decodeIfPresent(Int.self, forKey: .minutes)) ?? 0
        status = (try? c.decodeIfPresent(LevelStatus.self, forKey: .status)) ?? .locked
        awaitingReview = (try? c.decodeIfPresent(Bool.self, forKey: .awaitingReview)) ?? false
        examPublished = (try? c.decodeIfPresent(Bool.self, forKey: .examPublished)) ?? true
    }
}

struct PathwaySummary: Codable, Sendable {
    var currentLevel: Int = 1
    var levels: [PathwayLevel] = []
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        currentLevel = (try? c.decodeIfPresent(Int.self, forKey: .currentLevel)) ?? 1
        levels = (try? c.decodeIfPresent([PathwayLevel].self, forKey: .levels)) ?? []
    }
}

/// A level's mastery out of 100 — the owner's model: exam (50) + module quizzes
/// (30) + app participation (20). Server-computed; the client only renders it.
struct LevelScore: Decodable, Sendable {
    struct Part: Decodable, Sendable { let score: Int; let of: Int; let rawPct: Int }
    struct ExamPart: Decodable, Sendable { let score: Int; let of: Int; let rawPct: Int; let passed: Bool }
    let levelNumber: Int
    let total: Int
    let band: String
    let exam: ExamPart
    let modules: Part
    let participation: Part

    private enum CodingKeys: String, CodingKey {
        case levelNumber, total, band, exam, modules, participation
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        levelNumber = (try? c.decodeIfPresent(Int.self, forKey: .levelNumber)) ?? 0
        total = (try? c.decodeIfPresent(Int.self, forKey: .total)) ?? 0
        band = (try? c.decodeIfPresent(String.self, forKey: .band)) ?? ""
        exam = (try? c.decodeIfPresent(ExamPart.self, forKey: .exam))
            ?? ExamPart(score: 0, of: 0, rawPct: 0, passed: false)
        modules = (try? c.decodeIfPresent(Part.self, forKey: .modules))
            ?? Part(score: 0, of: 0, rawPct: 0)
        participation = (try? c.decodeIfPresent(Part.self, forKey: .participation))
            ?? Part(score: 0, of: 0, rawPct: 0)
    }
}

// Tolerant decoding for the score parts lives in extensions so the memberwise
// inits stay available for the sparse-payload fallbacks above.
extension LevelScore.Part {
    private enum CodingKeys: String, CodingKey { case score, of, rawPct }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        of = (try? c.decodeIfPresent(Int.self, forKey: .of)) ?? 0
        rawPct = (try? c.decodeIfPresent(Int.self, forKey: .rawPct)) ?? 0
    }
}

extension LevelScore.ExamPart {
    private enum CodingKeys: String, CodingKey { case score, of, rawPct, passed }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        score = (try? c.decodeIfPresent(Int.self, forKey: .score)) ?? 0
        of = (try? c.decodeIfPresent(Int.self, forKey: .of)) ?? 0
        rawPct = (try? c.decodeIfPresent(Int.self, forKey: .rawPct)) ?? 0
        passed = (try? c.decodeIfPresent(Bool.self, forKey: .passed)) ?? false
    }
}

// MARK: - Modules

enum ModuleStatus: String, Codable, Sendable {
    case completed, next, locked
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = ModuleStatus(rawValue: raw) ?? .locked
    }
}

/// Int that tolerates Postgres NUMERIC drift: node-pg serializes numerics as
/// strings, so `quiz_pass_mark` arrives as "70.00" from prod but 70 locally.
/// Decodes Int, Double, or numeric String — never crashes a whole screen.
@propertyWrapper
struct FlexInt: Codable, Sendable, Hashable {
    var wrappedValue: Int
    init(wrappedValue: Int) { self.wrappedValue = wrappedValue }
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let i = try? c.decode(Int.self) { wrappedValue = i }
        else if let d = try? c.decode(Double.self) { wrappedValue = Int(d.rounded()) }
        else if let s = try? c.decode(String.self), let d = Double(s) { wrappedValue = Int(d.rounded()) }
        else { wrappedValue = 0 }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer(); try c.encode(wrappedValue)
    }
}

struct LevelModule: Codable, Sendable, Identifiable {
    let moduleId: String
    let levelNumber: Int
    let moduleSequenceNumber: Int
    let title: String
    let summary: String?
    let estimatedMinutes: Int?
    let evaluationKind: String
    @FlexInt var quizPassMark: Int
    let completed: Bool
    let status: ModuleStatus
    let progress: Double
    let locked: Bool

    var id: String { moduleId }

    /// The level's capstone exam container (not a readable lesson). Shown as a
    /// visible, locked-until-ready row at the foot of the trail; tapping it once
    /// unlocked opens the level exam rather than the lesson reader.
    var isExam: Bool { evaluationKind == "exit_exam" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moduleId = try c.decode(String.self, forKey: .moduleId)
        levelNumber = try c.decode(Int.self, forKey: .levelNumber)
        moduleSequenceNumber = try c.decode(Int.self, forKey: .moduleSequenceNumber)
        title = try c.decode(String.self, forKey: .title)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        estimatedMinutes = try? c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        evaluationKind = (try? c.decodeIfPresent(String.self, forKey: .evaluationKind)) ?? "none"
        _quizPassMark = (try? c.decodeIfPresent(FlexInt.self, forKey: .quizPassMark))
            ?? FlexInt(wrappedValue: 0)
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? false
        status = (try? c.decodeIfPresent(ModuleStatus.self, forKey: .status)) ?? .locked
        progress = (try? c.decodeIfPresent(Double.self, forKey: .progress)) ?? 0.0
        // A missing gate must never unlock content (§1.9) — default LOCKED.
        locked = (try? c.decodeIfPresent(Bool.self, forKey: .locked)) ?? true
    }
}

struct ModuleDetail: Codable, Sendable {
    let moduleId: String
    let levelNumber: Int
    let moduleSequenceNumber: Int
    let title: String
    let lessonContent: String
    /// Lesson content pre-split into pages by author-inserted breaks; a
    /// single-element array when unpaginated. Optional + defaulted so payloads
    /// from servers that predate pagination still decode.
    var contentPages: [String]? = nil
    let summary: String?
    let keyVerses: [String]?
    let videoUrl: String?
    /// Media durations + the lesson's audio narration. All optional + defaulted
    /// so payloads from servers that predate this contract still decode. Durations
    /// drive the "Watch · Xm" / "Listen · Ym" pill labels (omitted → no duration
    /// shown); `audioUrl` is what gates the Listen pill/player existing at all.
    var videoDurationSec: Int? = nil
    var audioUrl: String? = nil
    var audioDurationSec: Int? = nil
    let evaluationKind: String
    let estimatedMinutes: Int?
    @FlexInt var quizPassMark: Int
    let currentVersion: Int
    let locked: Bool
    /// Per-member completion summary (defaulted — older servers omit them).
    /// When `completed`, the reader collapses into a clean reading room.
    var completed: Bool? = nil
    var completedAt: String? = nil
    var bestScore: Int? = nil
    /// A discipler's voice note on this lesson — one per congregation
    /// (companion Wave 2). Defaulted so older servers still decode.
    var voiceNote: ModuleVoiceNote? = nil

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        moduleId = try c.decode(String.self, forKey: .moduleId)
        levelNumber = try c.decode(Int.self, forKey: .levelNumber)
        moduleSequenceNumber = try c.decode(Int.self, forKey: .moduleSequenceNumber)
        title = try c.decode(String.self, forKey: .title)
        lessonContent = (try? c.decodeIfPresent(String.self, forKey: .lessonContent)) ?? ""
        contentPages = try? c.decodeIfPresent([String].self, forKey: .contentPages)
        summary = try? c.decodeIfPresent(String.self, forKey: .summary)
        keyVerses = try? c.decodeIfPresent([String].self, forKey: .keyVerses)
        videoUrl = try? c.decodeIfPresent(String.self, forKey: .videoUrl)
        videoDurationSec = try? c.decodeIfPresent(Int.self, forKey: .videoDurationSec)
        audioUrl = try? c.decodeIfPresent(String.self, forKey: .audioUrl)
        audioDurationSec = try? c.decodeIfPresent(Int.self, forKey: .audioDurationSec)
        evaluationKind = (try? c.decodeIfPresent(String.self, forKey: .evaluationKind)) ?? "none"
        estimatedMinutes = try? c.decodeIfPresent(Int.self, forKey: .estimatedMinutes)
        _quizPassMark = (try? c.decodeIfPresent(FlexInt.self, forKey: .quizPassMark))
            ?? FlexInt(wrappedValue: 0)
        currentVersion = (try? c.decodeIfPresent(Int.self, forKey: .currentVersion)) ?? 1
        // A missing gate must never unlock content (§1.9) — default LOCKED.
        locked = (try? c.decodeIfPresent(Bool.self, forKey: .locked)) ?? true
        completed = try? c.decodeIfPresent(Bool.self, forKey: .completed)
        completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
        bestScore = try? c.decodeIfPresent(Int.self, forKey: .bestScore)
        voiceNote = try? c.decodeIfPresent(ModuleVoiceNote.self, forKey: .voiceNote)
    }

    /// True when finishing this module requires a graded quiz (vs. mark-complete).
    var requiresQuiz: Bool { evaluationKind.lowercased().contains("quiz") }

    var isFinished: Bool { completed == true }

    /// "11 Jul 2026 · 20:14" from the ISO completed_at, in the member's locale.
    var finishedLine: String? {
        guard let completedAt else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let alt = ISO8601DateFormatter()
        var date = iso.date(from: completedAt) ?? alt.date(from: completedAt)
        if date == nil {
            // Postgres ::text form "2026-07-11 17:14:09.123+00"
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSxx"
            date = f.date(from: completedAt)
            if date == nil { f.dateFormat = "yyyy-MM-dd HH:mm:ssxx"; date = f.date(from: completedAt) }
        }
        guard let date else { return nil }
        let out = DateFormatter()
        out.dateFormat = "d MMM yyyy · HH:mm"
        return out.string(from: date)
    }
}

/// "A word from your discipler" — a short voice note a leader leaves on a
/// module for their whole congregation (Wave 2).
struct ModuleVoiceNote: Codable, Sendable {
    let authorName: String
    let avatarUrl: String?
    let audioUrl: String
    let durationSec: Int
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        authorName = (try? c.decodeIfPresent(String.self, forKey: .authorName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        audioUrl = (try? c.decodeIfPresent(String.self, forKey: .audioUrl)) ?? ""
        durationSec = (try? c.decodeIfPresent(Int.self, forKey: .durationSec)) ?? 0
    }
}

struct CompleteResult: Codable, Sendable {
    let progressId: String
    let moduleId: String
    let isCompleted: Bool
    let duplicate: Bool
    let nextModuleUnlocked: Bool
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        progressId = try c.decode(String.self, forKey: .progressId)
        moduleId = try c.decode(String.self, forKey: .moduleId)
        // Safe-conservative defaults: never claim completion/unlocks by omission.
        isCompleted = (try? c.decodeIfPresent(Bool.self, forKey: .isCompleted)) ?? false
        duplicate = (try? c.decodeIfPresent(Bool.self, forKey: .duplicate)) ?? false
        nextModuleUnlocked = (try? c.decodeIfPresent(Bool.self, forKey: .nextModuleUnlocked)) ?? false
    }
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
        qType = (try? c.decodeIfPresent(String.self, forKey: .qType)) ?? ""
        questionText = (try? c.decodeIfPresent(String.self, forKey: .questionText)) ?? ""
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

    private enum CodingKeys: String, CodingKey { case moduleId, questionCount, questions }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        moduleId = (try? c.decodeIfPresent(String.self, forKey: .moduleId)) ?? ""
        questionCount = (try? c.decodeIfPresent(Int.self, forKey: .questionCount)) ?? 0
        questions = (try? c.decodeIfPresent([QuizQuestion].self, forKey: .questions)) ?? []
    }
}

struct QuizResult: Decodable, Sendable {
    let attemptId: String
    @FlexInt var scoreAchieved: Int
    let isPassed: Bool
    @FlexInt var passMark: Int
    let unlockedNextModuleId: String?
    let requiresManualReview: Bool
    let duplicate: Bool

    private enum CodingKeys: String, CodingKey {
        case attemptId, scoreAchieved, isPassed, passMark
        case unlockedNextModuleId, requiresManualReview, duplicate
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        attemptId = (try? c.decodeIfPresent(String.self, forKey: .attemptId)) ?? ""
        _scoreAchieved = (try? c.decodeIfPresent(FlexInt.self, forKey: .scoreAchieved))
            ?? FlexInt(wrappedValue: 0)
        // Safe-conservative: never claim a pass by omission.
        isPassed = (try? c.decodeIfPresent(Bool.self, forKey: .isPassed)) ?? false
        _passMark = (try? c.decodeIfPresent(FlexInt.self, forKey: .passMark))
            ?? FlexInt(wrappedValue: 0)
        unlockedNextModuleId = try? c.decodeIfPresent(String.self, forKey: .unlockedNextModuleId)
        requiresManualReview = (try? c.decodeIfPresent(Bool.self, forKey: .requiresManualReview)) ?? false
        duplicate = (try? c.decodeIfPresent(Bool.self, forKey: .duplicate)) ?? false
    }
}
