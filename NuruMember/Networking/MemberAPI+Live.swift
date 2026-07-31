// Nuru Live — viewer endpoints (L2) + broadcaster endpoints (L3). Wire shapes
// mirror packages/backend/src/modules/live/{index.ts,service.ts} exactly; see
// Models/Live.swift for the tolerant DTOs.
import Foundation

extension MemberAPI {
    /// POST /live/streams — mint a new stream + publish key. Gated client-side
    /// (advisory only — see LiveBroadcastEligibility) on `live:go`; the server
    /// re-checks scope eligibility regardless (403 FORBIDDEN_SCOPE) and
    /// enforces "one live stream per scope" (409 CONFLICT).
    static func startLiveStream(scope: String, cellId: String?, title: String, kind: String) async throws -> CreatedLiveStream {
        struct Body: Encodable { let scope: String; let cellId: String?; let title: String; let kind: String }
        return try await APIClient.shared.post("live/streams",
                                               body: Body(scope: scope, cellId: cellId, title: title, kind: kind),
                                               as: CreatedLiveStream.self)
    }

    /// POST /live/streams/{id}/end — idempotent (a second call, e.g. after a
    /// retry timeout, is a no-op that returns the same ended state). We don't
    /// need the response body: the broadcast screen already tracks its own
    /// elapsed time and peak viewer count client-side across its 15s polls.
    static func endLiveStream(streamId: String) async throws {
        _ = try await APIClient.shared.postEmpty("live/streams/\(streamId)/end", as: EmptyResponse.self)
    }

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

    /// GET /live/recordings/mine — the caller's OWN ended broadcasts (or every
    /// non-deleted recording for a `live:manage` holder), owner-managed
    /// keep/delete stewardship. Backs "My Broadcasts" on the Live tab —
    /// distinct from `fetchRecordings`, the read-only list everyone sees.
    static func fetchMyRecordings() async throws -> [LiveMyRecordingRow] {
        try await APIClient.shared.get("live/recordings/mine", as: Envelope<LiveMyRecordingRow>.self).data
    }

    /// DELETE /live/recordings/{id} — soft-deletes (the stream's own owner or
    /// a `live:manage` holder only, enforced server-side; a second call is a
    /// silent no-op). `recording_id == stream_id` always (a recording is 1:1
    /// with the stream that produced it), so any stream_id works here.
    static func deleteLiveRecording(streamId: String) async throws {
        _ = try await APIClient.shared.delete("live/recordings/\(streamId)", as: EmptyResponse.self)
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
