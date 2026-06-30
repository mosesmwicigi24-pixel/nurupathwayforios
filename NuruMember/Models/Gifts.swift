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
