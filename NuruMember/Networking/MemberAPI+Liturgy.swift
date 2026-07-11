// The liturgy Home + community intelligence (intelligence Phase 4).
//   • GET  home/liturgy — the prayer line for RIGHT NOW (EAT clock + season)
//   • GET  community/moments — the congregation's recent celebrations
//   • POST community/moments/{id}/bless — one-tap amen / heart / fire
import Foundation

struct HomeLiturgy: Codable, Sendable {
    let part: String        // morning | midday | evening | night
    let season: String      // advent | christmas | lent | easter | ordinary
    let isSunday: Bool
    let line: String
    let scriptureRef: String?
}

struct CommunityMoment: Codable, Sendable, Identifiable {
    let momentId: String
    let userId: String
    let fullName: String
    let avatarUrl: String?
    let kind: String        // module_complete | level_complete | verse_mastered | plan_complete
    let title: String
    let occurredAt: String
    var amenCount: Int
    var heartCount: Int
    var fireCount: Int
    var myBlessing: String?
    var id: String { momentId }
}

struct BlessRes: Codable, Sendable {
    let blessed: Bool
    let kind: String
}

extension MemberAPI {
    static func homeLiturgy() async throws -> HomeLiturgy {
        try await APIClient.shared.get("home/liturgy", as: HomeLiturgy.self)
    }

    static func communityMoments() async throws -> [CommunityMoment] {
        try await APIClient.shared.get("community/moments", as: Envelope<CommunityMoment>.self).data
    }

    static func bless(_ momentId: String, kind: String) async throws -> BlessRes {
        struct Body: Encodable { let kind: String }
        return try await APIClient.shared.post("community/moments/\(momentId)/bless", body: Body(kind: kind), as: BlessRes.self)
    }
}
