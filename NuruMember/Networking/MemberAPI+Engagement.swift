// Module engagement — server-accumulated reading/audio/video time + resume page
// for the immersive module reader. The client POSTs small observed DELTAS (each
// ≤600s by contract — wall-clock capped client-side too) on a 30s heartbeat and
// on disappear; the server accumulates and returns the running totals. All
// writes are fire-and-forget at the call sites (`try?`) — engagement telemetry
// must never block or break the reading experience.
import Foundation

/// Totals row for one member × module, returned by both engagement endpoints.
/// `lastPage` is the 1-based page number the member last had open (0 when the
/// server has never been told a page). @FlexInt tolerates node-pg NUMERIC
/// strings, same as quiz marks.
struct ModuleEngagement: Codable, Sendable {
    @FlexInt var readingSeconds: Int
    @FlexInt var audioSeconds: Int
    @FlexInt var videoSeconds: Int
    @FlexInt var lastPage: Int
}

extension MemberAPI {
    /// GET /modules/{id}/engagement — this member's accumulated totals (used to
    /// resume on the last-read page when reopening a module).
    static func moduleEngagement(_ moduleId: String) async throws -> ModuleEngagement {
        try await APIClient.shared.get("modules/\(moduleId)/engagement", as: ModuleEngagement.self)
    }

    /// POST /modules/{id}/engagement — report observed deltas (seconds actually
    /// on screen / actually playing, each ≤600) and/or the current page. Nil
    /// fields are omitted from the wire body (synthesized Encodable drops nil
    /// optionals). Returns the new server totals.
    @discardableResult
    static func reportModuleEngagement(_ moduleId: String,
                                       readingSeconds: Int? = nil,
                                       audioSeconds: Int? = nil,
                                       videoSeconds: Int? = nil,
                                       lastPage: Int? = nil) async throws -> ModuleEngagement {
        struct Body: Encodable {
            let readingSeconds: Int?
            let audioSeconds: Int?
            let videoSeconds: Int?
            let lastPage: Int?
        }
        return try await APIClient.shared.post("modules/\(moduleId)/engagement",
            body: Body(readingSeconds: readingSeconds, audioSeconds: audioSeconds,
                       videoSeconds: videoSeconds, lastPage: lastPage),
            as: ModuleEngagement.self)
    }
}
