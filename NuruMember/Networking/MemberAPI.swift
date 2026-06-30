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

    // MARK: Pathway (levels · modules · quiz — server-authoritative gating §1.9)

    /// GET /me/pathway — the member's level trail with per-level progress + status.
    static func pathway() async throws -> PathwaySummary {
        try await APIClient.shared.get("me/pathway", as: PathwaySummary.self)
    }

    /// GET /levels/{n}/modules — the module trail for a level.
    static func levelModules(_ levelNumber: Int) async throws -> [LevelModule] {
        try await APIClient.shared.get("levels/\(levelNumber)/modules", as: Envelope<LevelModule>.self).data
    }

    /// GET /modules/{id} — full lesson + evaluation metadata. Server refuses
    /// content above the member's current level (§1.9); we also honour `locked`.
    static func module(_ moduleId: String) async throws -> ModuleDetail {
        try await APIClient.shared.get("modules/\(moduleId)", as: ModuleDetail.self)
    }

    /// POST /modules/{id}/complete — finish a non-quiz module (optional reflection).
    static func completeModule(_ moduleId: String, reflectionText: String? = nil) async throws -> CompleteResult {
        struct Body: Encodable { let reflectionText: String? }
        return try await APIClient.shared.post("modules/\(moduleId)/complete",
                                               body: Body(reflectionText: reflectionText), as: CompleteResult.self)
    }

    /// GET /modules/{id}/quiz — the server-assembled quiz (answer signal stripped).
    static func quiz(_ moduleId: String) async throws -> AssembledQuiz {
        try await APIClient.shared.get("modules/\(moduleId)/quiz", as: AssembledQuiz.self)
    }

    /// POST /modules/{id}/quiz/attempts — submit answers; scored server-side (§3.7).
    /// `clientMutationId` keeps the attempt idempotent on replay (§2.1/§3.6).
    static func submitQuiz(_ moduleId: String, clientMutationId: String,
                           answers: [QuizAnswer]) async throws -> QuizResult {
        struct Body: Encodable { let clientMutationId: String; let answers: [QuizAnswer] }
        return try await APIClient.shared.post("modules/\(moduleId)/quiz/attempts",
                                               body: Body(clientMutationId: clientMutationId, answers: answers),
                                               as: QuizResult.self)
    }
}

/// One submitted answer — `givenAnswer` is always a string per the wire contract
/// (checkbox carries a JSON array of selected ids; scale carries the number).
struct QuizAnswer: Encodable, Sendable {
    let questionId: String
    let givenAnswer: String
}

/// Generic `{ "data": [...] }` list envelope used by several collection endpoints.
struct Envelope<T: Decodable & Sendable>: Decodable, Sendable {
    let data: [T]
}
