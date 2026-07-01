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
}

struct EnrollmentSummary: Codable, Sendable {
    let enrollmentId: String
    let currentLevel: Int
    let state: String
    let startedAt: String
}

struct MeResponse: Codable, Sendable {
    let profile: UserProfile
    let enrollment: EnrollmentSummary?
}

/// POST /auth/mfa/enroll — the TOTP secret the member confirms to turn 2FA on.
struct MfaEnrollment: Codable, Sendable {
    let otpauthUri: String
    let secret: String
}

// MARK: - Home (server-driven dashboard)

/// GET /me/rhythm/today — the three daily rhythms feeding the streak.
struct RhythmToday: Codable, Sendable {
    let prayer: Bool
    let word: Bool
    let reflection: Bool

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
