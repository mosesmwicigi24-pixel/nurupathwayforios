// The liturgy Home + community intelligence (intelligence Phase 4).
//   • GET  home/liturgy — the prayer line for RIGHT NOW (EAT clock + season)
//   • GET  community/moments — the congregation's recent celebrations
//   • POST community/moments/{id}/bless — one-tap amen / heart / fire
import Foundation

struct HomeLiturgy: Codable, Sendable {
    // Tolerant like the Android DTOs: a sparse field degrades one label, it
    // must never blank the whole card (all feed fetches are try?-wrapped).
    var part: String = "morning" // morning | midday | evening | night
    var season: String = "ordinary" // advent | christmas | lent | easter | ordinary
    var isSunday: Bool = false
    var line: String = ""
    var scriptureRef: String? = nil
    var art: VerseArt? = nil   // the hour's tableau photograph (server-curated per part+day)
    // Seven-bands additions — all optional, all tolerant: absent on an older
    // backend response and the card renders exactly as it did before.
    var band: String? = nil        // one of the 7 time-of-day bands (server-only art selection)
    var charge: String? = nil      // a second, subdued exhortation line
    var verseLine: LiturgyVerseLine? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        part = (try? c.decodeIfPresent(String.self, forKey: .part)) ?? "morning"
        season = (try? c.decodeIfPresent(String.self, forKey: .season)) ?? "ordinary"
        isSunday = (try? c.decodeIfPresent(Bool.self, forKey: .isSunday)) ?? false
        line = (try? c.decodeIfPresent(String.self, forKey: .line)) ?? ""
        scriptureRef = try? c.decodeIfPresent(String.self, forKey: .scriptureRef)
        art = try? c.decodeIfPresent(VerseArt.self, forKey: .art)
        band = try? c.decodeIfPresent(String.self, forKey: .band)
        charge = try? c.decodeIfPresent(String.self, forKey: .charge)
        verseLine = try? c.decodeIfPresent(LiturgyVerseLine.self, forKey: .verseLine)
    }
}

/// A short companion verse alongside the liturgy line — italic serif text
/// with a small gold reference caption, e.g. "— Lamentations 3:22-23".
struct LiturgyVerseLine: Codable, Sendable {
    var reference: String = ""
    var text: String = ""
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        reference = (try? c.decodeIfPresent(String.self, forKey: .reference)) ?? ""
        text = (try? c.decodeIfPresent(String.self, forKey: .text)) ?? ""
    }
}

struct CommunityMoment: Codable, Sendable, Identifiable {
    // One odd row must cost ONE card, never the whole rail (Android parity).
    var momentId: String = ""
    var userId: String = ""
    var fullName: String = ""
    var avatarUrl: String? = nil
    var kind: String = "" // module_complete | level_complete | verse_mastered | plan_complete
    var title: String = ""
    var occurredAt: String = ""
    var amenCount: Int = 0
    var heartCount: Int = 0
    var fireCount: Int = 0
    var myBlessing: String? = nil
    var id: String { momentId }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        momentId = (try? c.decodeIfPresent(String.self, forKey: .momentId)) ?? ""
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        occurredAt = (try? c.decodeIfPresent(String.self, forKey: .occurredAt)) ?? ""
        amenCount = (try? c.decodeIfPresent(Int.self, forKey: .amenCount)) ?? 0
        heartCount = (try? c.decodeIfPresent(Int.self, forKey: .heartCount)) ?? 0
        fireCount = (try? c.decodeIfPresent(Int.self, forKey: .fireCount)) ?? 0
        myBlessing = try? c.decodeIfPresent(String.self, forKey: .myBlessing)
    }
}

struct BlessRes: Codable, Sendable {
    let blessed: Bool
    let kind: String
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        blessed = (try? c.decodeIfPresent(Bool.self, forKey: .blessed)) ?? false
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
    }
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

// Wave 1 — echoes: today's companion moment (the member's own history,
// carried back at the right time; null when nothing specific is true).
struct HomeEcho: Codable, Sendable {
    var kind: String = "" // welcome_back | reflection_echo | anniversary
    var body: String = ""
    var quote: String? = nil
    var ref: String? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        quote = try? c.decodeIfPresent(String.self, forKey: .quote)
        ref = try? c.decodeIfPresent(String.self, forKey: .ref)
    }
}

struct HomeEchoEnvelope: Codable, Sendable { let echo: HomeEcho? }

extension MemberAPI {
    static func homeEcho() async throws -> HomeEcho? {
        try await APIClient.shared.get("home/echo", as: HomeEchoEnvelope.self).echo
    }
}

