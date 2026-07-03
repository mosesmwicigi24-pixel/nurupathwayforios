// Progression endpoints — the standalone module reflection that is now a REQUIRED
// content step BEFORE the quiz (the reader's reflection card no longer submits
// through completeModule; it POSTs here, and the server's content gate counts it
// alongside read + watch(≥90%) + listen(≥90%)). Kept in its own file per the
// coordinated-dev split; everything decodes defensively (optional + defaulted)
// because the wire names may still be refined by the parallel backend agent.
import Foundation

/// A saved standalone reflection for a module. `body` is the text; `createdAt` is
/// when the server recorded it (nil-tolerant — a bare `{ "saved": true }` or a
/// row without a timestamp still decodes). Snake_case on the wire → camelCase.
struct ModuleReflection: Decodable, Sendable {
    let body: String
    let createdAt: String?

    private enum CodingKeys: String, CodingKey { case body, createdAt, text, content }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tolerate `body` | `text` | `content` for the reflection text.
        body = (try? c.decodeIfPresent(String.self, forKey: .body))
            ?? (try? c.decodeIfPresent(String.self, forKey: .text))
            ?? (try? c.decodeIfPresent(String.self, forKey: .content))
            ?? ""
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? nil
    }

    init(body: String, createdAt: String?) {
        self.body = body
        self.createdAt = createdAt
    }
}

extension MemberAPI {
    /// POST /modules/{id}/reflection — save the module's standalone reflection.
    /// Returns the persisted row `{ body, created_at }`. This is a REQUIRED content
    /// step before the quiz; it does NOT complete the module (§1.9 gate — completion
    /// stays server-authoritative via the quiz / mark-complete path).
    @discardableResult
    static func submitModuleReflection(_ moduleId: String, body: String) async throws -> ModuleReflection {
        struct Body: Encodable { let body: String; let clientMutationId: String }
        return try await APIClient.shared.post(
            "modules/\(moduleId)/reflection",
            body: Body(body: body, clientMutationId: UUID().uuidString),
            as: ModuleReflection.self)
    }

    /// GET /modules/{id}/reflection → { data: row | null } — the member's saved
    /// reflection for this module, or nil when they haven't written one yet. Used on
    /// reader open to pre-fill the card and mark the Reflect step already done.
    static func moduleReflection(_ moduleId: String) async throws -> ModuleReflection? {
        struct Env: Decodable { let data: ModuleReflection? }
        return try await APIClient.shared.get("modules/\(moduleId)/reflection", as: Env.self).data
    }
}
