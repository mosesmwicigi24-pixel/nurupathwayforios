// Spiritual-gifts ("Your Calling") DTOs — Swift mirrors of the contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

struct GiftAssessment: Codable, Sendable {
    let assessmentId: String
    let scores: [String: Double]
    let topGifts: [String]
    let submittedAt: String
    let personaSummary: String?
}

struct GiftPersona: Codable, Sendable, Identifiable {
    let giftKey: String
    let title: String
    let personaName: String
    let tagline: String?
    let summary: String
    let strengths: [String]
    let serving: [String]
    let emoji: String?
    let color: String?
    var id: String { giftKey }
}

struct ServingTrack: Codable, Sendable, Identifiable {
    let trackKey: String
    let title: String
    let description: String
    let giftKeys: [String]
    let matchCount: Int
    var id: String { trackKey }
}

struct MyGifts: Codable, Sendable {
    let assessment: GiftAssessment?
    let personas: [GiftPersona]
    let suggestedTracks: [ServingTrack]
}

/// GET /gifts/questions — one Likert prompt in the (possibly AI-tuned) question set.
struct GiftQuestion: Codable, Sendable, Identifiable, Hashable {
    let questionId: String
    let giftKey: String
    let prompt: String
    var id: String { questionId }
}

/// GET /gifts/questions — the served question set for the calling member.
struct GiftQuestionSet: Codable, Sendable {
    let setId: String
    let aiInfluenced: Bool
    let data: [GiftQuestion]
}

/// One answer (1–5 Likert) submitted to POST /gifts/assessments.
struct GiftAnswerInput: Encodable, Sendable {
    let questionId: String
    let value: Int
}
