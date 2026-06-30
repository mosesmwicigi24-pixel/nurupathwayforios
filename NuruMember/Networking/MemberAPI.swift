// Typed endpoint facade over APIClient — the native counterpart of the NuruApi
// object in packages/mobile/src/api/client.ts. Screens call these, never the raw
// client. Only the endpoints needed by the current slice are wired; the rest are
// ported screen-by-screen (see PORT_STATUS.md).
import Foundation

enum MemberAPI {
    // MARK: Auth

    /// POST /auth/login — may yield a 2FA challenge instead of a session.
    static func login(email: String, password: String) async throws -> LoginResult {
        try await APIClient.shared.login(email: email, password: password)
    }

    static func completeMfa(mfaToken: String, code: String) async throws -> Session {
        try await APIClient.shared.completeMfa(mfaToken: mfaToken, code: code)
    }

    // MARK: Profile

    /// GET /me — the signed-in member's profile + enrollment summary.
    static func me() async throws -> MeResponse {
        try await APIClient.shared.get("me", as: MeResponse.self)
    }

    // MARK: Home (server-driven dashboard)

    /// GET /me/rhythm/today — today's three daily rhythms.
    static func rhythmToday() async throws -> RhythmToday {
        try await APIClient.shared.get("me/rhythm/today", as: RhythmToday.self)
    }

    /// GET /me/home/next-action — the next-best-action hero card (may be null).
    static func nextAction() async throws -> NextAction? {
        try await APIClient.shared.get("me/home/next-action", as: NextActionEnvelope.self).action
    }

    /// POST /me/rhythm/complete — mark a rhythm done for today (idempotent).
    static func completeRhythm(_ kind: String) async throws -> RhythmToday {
        struct Body: Encodable { let kind: String }
        return try await APIClient.shared.post("me/rhythm/complete", body: Body(kind: kind), as: RhythmToday.self)
    }
}
