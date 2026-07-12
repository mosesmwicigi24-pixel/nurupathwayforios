// Spiritual-gifts ("Your Calling") DTOs — Swift mirrors of the contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

struct GiftAssessment: Codable, Sendable {
    let assessmentId: String
    let scores: [String: Double]
    let topGifts: [String]
    let submittedAt: String
    let personaSummary: String?
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        assessmentId = (try? c.decodeIfPresent(String.self, forKey: .assessmentId)) ?? ""
        scores = (try? c.decodeIfPresent([String: Double].self, forKey: .scores)) ?? [:]
        topGifts = (try? c.decodeIfPresent([String].self, forKey: .topGifts)) ?? []
        submittedAt = (try? c.decodeIfPresent(String.self, forKey: .submittedAt)) ?? ""
        personaSummary = try? c.decodeIfPresent(String.self, forKey: .personaSummary)
    }
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
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        giftKey = try c.decode(String.self, forKey: .giftKey)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        personaName = (try? c.decodeIfPresent(String.self, forKey: .personaName)) ?? ""
        tagline = try? c.decodeIfPresent(String.self, forKey: .tagline)
        summary = (try? c.decodeIfPresent(String.self, forKey: .summary)) ?? ""
        strengths = (try? c.decodeIfPresent([String].self, forKey: .strengths)) ?? []
        serving = (try? c.decodeIfPresent([String].self, forKey: .serving)) ?? []
        emoji = try? c.decodeIfPresent(String.self, forKey: .emoji)
        color = try? c.decodeIfPresent(String.self, forKey: .color)
    }
}

struct ServingTrack: Codable, Sendable, Identifiable {
    let trackKey: String
    let title: String
    let description: String
    let giftKeys: [String]
    let matchCount: Int
    var id: String { trackKey }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        trackKey = try c.decode(String.self, forKey: .trackKey)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        description = (try? c.decodeIfPresent(String.self, forKey: .description)) ?? ""
        giftKeys = (try? c.decodeIfPresent([String].self, forKey: .giftKeys)) ?? []
        matchCount = (try? c.decodeIfPresent(Int.self, forKey: .matchCount)) ?? 0
    }
}

struct MyGifts: Codable, Sendable {
    let assessment: GiftAssessment?
    let personas: [GiftPersona]
    let suggestedTracks: [ServingTrack]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        assessment = try? c.decodeIfPresent(GiftAssessment.self, forKey: .assessment)
        personas = (try? c.decodeIfPresent([GiftPersona].self, forKey: .personas)) ?? []
        suggestedTracks = (try? c.decodeIfPresent([ServingTrack].self, forKey: .suggestedTracks)) ?? []
    }
}

/// GET /gifts/questions — one Likert prompt in the (possibly AI-tuned) question set.
struct GiftQuestion: Codable, Sendable, Identifiable, Hashable {
    let questionId: String
    let giftKey: String
    let prompt: String
    var id: String { questionId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        questionId = try c.decode(String.self, forKey: .questionId)
        giftKey = (try? c.decodeIfPresent(String.self, forKey: .giftKey)) ?? ""
        prompt = (try? c.decodeIfPresent(String.self, forKey: .prompt)) ?? ""
    }
}

/// GET /gifts/questions — the served question set for the calling member.
struct GiftQuestionSet: Codable, Sendable {
    let setId: String
    let aiInfluenced: Bool
    let data: [GiftQuestion]
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        setId = (try? c.decodeIfPresent(String.self, forKey: .setId)) ?? ""
        aiInfluenced = (try? c.decodeIfPresent(Bool.self, forKey: .aiInfluenced)) ?? false
        data = (try? c.decodeIfPresent([GiftQuestion].self, forKey: .data)) ?? []
    }
}

/// One answer (1–5 Likert) submitted to POST /gifts/assessments.
struct GiftAnswerInput: Encodable, Sendable {
    let questionId: String
    let value: Int
}
