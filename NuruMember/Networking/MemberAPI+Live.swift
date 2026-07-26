// Nuru Live — viewer endpoints (L2, viewer-only; no broadcaster UI). Wire
// shapes mirror packages/backend/src/modules/live/{index.ts,service.ts}
// exactly; see Models/Live.swift for the tolerant DTOs.
import Foundation

extension MemberAPI {
    /// GET /live/now — church stream (if live) plus a cell stream ONLY for the
    /// caller's own cell. The server already scopes this; callers just filter
    /// the returned rows by `scope` (never re-scope by cell client-side).
    static func fetchLiveNow() async throws -> [LiveStreamSummary] {
        try await APIClient.shared.get("live/now", as: Envelope<LiveStreamSummary>.self).data
    }

    /// POST /live/streams/{id}/heartbeat — empty body. Call every ~30s while a
    /// viewer's player is open; best-effort (a dropped heartbeat must never
    /// interrupt playback).
    static func sendHeartbeat(streamId: String) async {
        _ = try? await APIClient.shared.postEmpty("live/streams/\(streamId)/heartbeat", as: EmptyResponse.self)
    }

    /// GET /live/recordings?scope=&cell_id= — both filters optional; omitting
    /// both returns everything visible to the caller (church + their cell).
    static func fetchRecordings(scope: String? = nil, cellId: String? = nil) async throws -> [LiveRecordingRow] {
        var q: [String: String] = [:]
        if let scope, !scope.isEmpty { q["scope"] = scope }
        if let cellId, !cellId.isEmpty { q["cell_id"] = cellId }
        return try await APIClient.shared.get("live/recordings", query: q, as: Envelope<LiveRecordingRow>.self).data
    }

    /// Resolve a server-relative live-media path (`hls_url` / `recording_url`)
    /// against the API's ORIGIN, not its `/v1` surface — these are nginx
    /// routes sitting beside the API (e.g. "/live/church/index.m3u8"), never
    /// under it. The live URL 302-redirects server-side; AVPlayer follows
    /// redirects natively, so the resolved absolute URL is handed straight in.
    static func resolveLiveMediaURL(_ relative: String) async -> URL? {
        let trimmed = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let already = URL(string: trimmed), already.scheme != nil { return already }
        let origin = await APIClient.shared.originURL
        return URL(string: trimmed, relativeTo: origin)?.absoluteURL
    }
}
