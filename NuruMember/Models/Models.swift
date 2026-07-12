// Wire DTOs — Swift mirrors of the shared contract in
// packages/shared/src/types/dto.ts. All decoded with the APIClient's
// `.convertFromSnakeCase` strategy, so snake_case JSON maps to camelCase here.
import Foundation

// MARK: - Auth (§3.3, §5.3)

/// The session token pair returned by /auth/login and /auth/token/refresh.
struct Session: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String?
    let expiresIn: Int?
}

/// Returned by /auth/login when the account has 2FA enabled.
struct MfaChallenge: Decodable, Sendable {
    let mfaRequired: Bool
    let mfaToken: String
}

/// /auth/login can return either a full session or a 2FA challenge.
enum LoginResult: Sendable {
    case session(Session)
    case mfaChallenge(MfaChallenge)
}

// MARK: - Profile (§3.3 /me)

struct UserProfile: Codable, Sendable, Identifiable {
    let userId: String
    let email: String?
    let fullName: String
    let phoneNumber: String?
    let dateOfBirth: String?
    let yearOfSalvation: Int?
    let isBaptized: Bool
    let cellGroupId: String?
    let congregationId: String?
    let role: String
    let timezone: String
    let locale: String
    let isMinor: Bool
    let gender: String?
    let city: String?
    let countryCode: String?
    let avatarUrl: String?
    let mfaEnabled: Bool?
    let rowVersion: Int

    var id: String { userId }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        email = try? c.decodeIfPresent(String.self, forKey: .email)
        fullName = try c.decode(String.self, forKey: .fullName)
        phoneNumber = try? c.decodeIfPresent(String.self, forKey: .phoneNumber)
        dateOfBirth = try? c.decodeIfPresent(String.self, forKey: .dateOfBirth)
        yearOfSalvation = try? c.decodeIfPresent(Int.self, forKey: .yearOfSalvation)
        isBaptized = (try? c.decodeIfPresent(Bool.self, forKey: .isBaptized)) ?? false
        cellGroupId = try? c.decodeIfPresent(String.self, forKey: .cellGroupId)
        congregationId = try? c.decodeIfPresent(String.self, forKey: .congregationId)
        role = (try? c.decodeIfPresent(String.self, forKey: .role)) ?? "Student"
        timezone = (try? c.decodeIfPresent(String.self, forKey: .timezone)) ?? "Africa/Nairobi"
        locale = (try? c.decodeIfPresent(String.self, forKey: .locale)) ?? "en"
        // Defaulting to adult is safe here: minor gating (DMs/chat) is enforced server-side.
        isMinor = (try? c.decodeIfPresent(Bool.self, forKey: .isMinor)) ?? false
        gender = try? c.decodeIfPresent(String.self, forKey: .gender)
        city = try? c.decodeIfPresent(String.self, forKey: .city)
        countryCode = try? c.decodeIfPresent(String.self, forKey: .countryCode)
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        mfaEnabled = try? c.decodeIfPresent(Bool.self, forKey: .mfaEnabled)
        rowVersion = (try? c.decodeIfPresent(Int.self, forKey: .rowVersion)) ?? 0
    }
}

struct EnrollmentSummary: Codable, Sendable {
    let enrollmentId: String
    let currentLevel: Int
    let state: String
    let startedAt: String
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        enrollmentId = try c.decode(String.self, forKey: .enrollmentId)
        currentLevel = try c.decode(Int.self, forKey: .currentLevel)
        state = try c.decode(String.self, forKey: .state)
        startedAt = (try? c.decodeIfPresent(String.self, forKey: .startedAt)) ?? ""
    }
}

struct MeResponse: Codable, Sendable {
    let profile: UserProfile
    let enrollment: EnrollmentSummary?
}

/// POST /auth/mfa/enroll — the TOTP secret the member confirms to turn 2FA on.
struct MfaEnrollment: Codable, Sendable {
    let otpauthUri: String
    let secret: String
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        otpauthUri = (try? c.decodeIfPresent(String.self, forKey: .otpauthUri)) ?? ""
        secret = (try? c.decodeIfPresent(String.self, forKey: .secret)) ?? ""
    }
}

// MARK: - Home (server-driven dashboard)

/// GET /me/rhythm/today — the three daily rhythms feeding the streak.
struct RhythmToday: Codable, Sendable {
    var prayer: Bool = false
    var word: Bool = false
    var reflection: Bool = false
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        prayer = (try? c.decodeIfPresent(Bool.self, forKey: .prayer)) ?? false
        word = (try? c.decodeIfPresent(Bool.self, forKey: .word)) ?? false
        reflection = (try? c.decodeIfPresent(Bool.self, forKey: .reflection)) ?? false
    }
    init(prayer: Bool, word: Bool, reflection: Bool) {
        self.prayer = prayer; self.word = word; self.reflection = reflection
    }

    var doneCount: Int { (prayer ? 1 : 0) + (word ? 1 : 0) + (reflection ? 1 : 0) }
}

/// GET /me/home/next-action — the next-best-action hero card.
struct NextAction: Codable, Sendable, Identifiable {
    let id: String
    let title: String
    let body: String
    let ctaLabel: String
    let route: String
    let accent: String
    let priority: Int
    /// Route parameters — e.g. `{ moduleId }` when `route == "module"`, so the CTA
    /// can deep-link straight to the specific lesson instead of the level.
    let params: NextActionParams?

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id = (try? c.decodeIfPresent(String.self, forKey: .id)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        ctaLabel = (try? c.decodeIfPresent(String.self, forKey: .ctaLabel)) ?? ""
        route = (try? c.decodeIfPresent(String.self, forKey: .route)) ?? ""
        accent = (try? c.decodeIfPresent(String.self, forKey: .accent)) ?? ""
        priority = (try? c.decodeIfPresent(Int.self, forKey: .priority)) ?? 0
        params = try? c.decodeIfPresent(NextActionParams.self, forKey: .params)
    }
}

/// Destination parameters for a NextAction CTA (only the keys we navigate on).
struct NextActionParams: Codable, Sendable, Hashable {
    let moduleId: String?
    let levelNumber: Int?
}

/// Envelope for the next-action endpoint: { "action": NextAction | null }.
struct NextActionEnvelope: Codable, Sendable {
    let action: NextAction?
}
