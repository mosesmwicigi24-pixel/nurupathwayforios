// Nuru Live — viewer-side wire models (L2). Shapes mirror
// packages/backend/src/modules/live/{index.ts,service.ts} exactly:
//   GET  /live/now                       → { data: [LiveStreamSummary] }
//   POST /live/streams/{id}/heartbeat     → { ok: true } (see MemberAPI+Live.swift)
//   GET  /live/recordings?scope=&cell_id= → { data: [LiveRecordingRow] }
//
// `hls_url` / `recording_url` arrive RELATIVE to the API's ORIGIN (not its
// `/v1` surface) — resolved in MemberAPI+Live.swift, never here.
import Foundation

/// One row of GET /live/now — a stream the caller may watch right now (the
/// server already scopes cell rows to the caller's own cell; no client-side
/// filtering needed beyond picking `scope` apart for Home vs the cell card).
struct LiveStreamSummary: Decodable, Sendable, Identifiable, Hashable {
    let streamId: String
    let scope: String            // "church" | "cell"
    let cellId: String?
    let title: String
    let kind: String              // "video" | "audio"
    let startedAt: String        // ISO 8601
    let hlsUrl: String            // relative — resolve against APIClient.originURL
    let startedByName: String
    let viewerCount: Int

    var id: String { streamId }
    var isChurch: Bool { scope == "church" }
    var isAudio: Bool { kind == "audio" }

    private enum CodingKeys: String, CodingKey {
        case streamId, scope, cellId, title, kind, startedAt, hlsUrl, startedByName, viewerCount
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        streamId = try c.decode(String.self, forKey: .streamId)
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? "church"
        cellId = try? c.decodeIfPresent(String.self, forKey: .cellId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Live now"
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "video"
        startedAt = (try? c.decodeIfPresent(String.self, forKey: .startedAt)) ?? ""
        hlsUrl = (try? c.decodeIfPresent(String.self, forKey: .hlsUrl)) ?? ""
        startedByName = (try? c.decodeIfPresent(String.self, forKey: .startedByName)) ?? ""
        viewerCount = (try? c.decodeIfPresent(Int.self, forKey: .viewerCount)) ?? 0
    }
}

/// One row of GET /live/recordings. No duration field exists server-side —
/// deliberately omitted from every UI that renders this row.
struct LiveRecordingRow: Decodable, Sendable, Identifiable, Hashable {
    let streamId: String
    let scope: String            // "church" | "cell"
    let cellId: String?
    let title: String
    let kind: String              // "video" | "audio"
    let startedAt: String
    let endedAt: String
    let recordingUrl: String      // relative — resolve against APIClient.originURL

    var id: String { streamId }
    var isAudio: Bool { kind == "audio" }

    private enum CodingKeys: String, CodingKey {
        case streamId, scope, cellId, title, kind, startedAt, endedAt, recordingUrl
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        streamId = try c.decode(String.self, forKey: .streamId)
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? "church"
        cellId = try? c.decodeIfPresent(String.self, forKey: .cellId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Replay"
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "video"
        startedAt = (try? c.decodeIfPresent(String.self, forKey: .startedAt)) ?? ""
        endedAt = (try? c.decodeIfPresent(String.self, forKey: .endedAt)) ?? ""
        recordingUrl = (try? c.decodeIfPresent(String.self, forKey: .recordingUrl)) ?? ""
    }
}

/// One row of GET /live/recordings/mine — the caller's OWN ended broadcasts
/// ("My Broadcasts" on the Live tab), or every non-deleted recording for a
/// `live:manage` holder. Distinct shape from `LiveRecordingRow` (server field
/// is `url`, not `recording_url`, and it carries `recording_id` — always
/// `== stream_id`, since a recording is 1:1 with the stream that produced it,
/// but the server names it explicitly so this row is self-describing).
struct LiveMyRecordingRow: Decodable, Sendable, Identifiable, Hashable {
    let recordingId: String
    let streamId: String
    let scope: String            // "church" | "cell"
    let cellId: String?
    let title: String
    let kind: String              // "video" | "audio"
    let startedAt: String
    let endedAt: String
    let url: String               // relative — resolve against APIClient.originURL

    var id: String { recordingId }
    var isAudio: Bool { kind == "audio" }

    private enum CodingKeys: String, CodingKey {
        case recordingId, streamId, scope, cellId, title, kind, startedAt, endedAt, url
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        recordingId = (try? c.decodeIfPresent(String.self, forKey: .recordingId)) ?? ""
        streamId = (try? c.decodeIfPresent(String.self, forKey: .streamId)) ?? ""
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? "church"
        cellId = try? c.decodeIfPresent(String.self, forKey: .cellId)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? "Broadcast"
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "video"
        startedAt = (try? c.decodeIfPresent(String.self, forKey: .startedAt)) ?? ""
        endedAt = (try? c.decodeIfPresent(String.self, forKey: .endedAt)) ?? ""
        url = (try? c.decodeIfPresent(String.self, forKey: .url)) ?? ""
    }
}

// MARK: - Shared date/time formatting (Home banner, cell card, replays list, player chrome)

enum LiveFormat {
    private static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }

    /// "started just now" / "started 12m ago" / "started 2h ago" — nil when the
    /// timestamp doesn't parse (never shows a bogus number).
    static func startedAgo(_ iso: String) -> String? {
        guard let d = parse(iso) else { return nil }
        let mins = max(0, Int(Date().timeIntervalSince(d) / 60))
        if mins < 1 { return "started just now" }
        if mins < 60 { return "started \(mins)m ago" }
        let hrs = mins / 60
        return "started \(hrs)h ago"
    }

    /// "Jul 20, 2026" — for the Replays list.
    static func dateLabel(_ iso: String) -> String {
        guard let d = parse(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: d)
    }
}

// MARK: - Unified playable item (drives the one full-screen player for both
// a live stream and a recorded replay)

/// Everything `LiveViewerPlayerView` needs, whether the source is a live
/// stream (heartbeat active, "LIVE" chrome) or a finished recording (no
/// heartbeat, plain playback). Built via the two factories below so every
/// call site shares the exact same title/subtitle formatting.
struct LivePlayableItem: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let kind: String              // "video" | "audio"
    let isLive: Bool
    let mediaPath: String         // relative hls_url / recording_url
    let viewerCount: Int?
    /// Non-nil only for a real live stream — its presence is what starts the
    /// 30s heartbeat in the player; a recording never heartbeats.
    let heartbeatStreamId: String?
    /// `LiveStreamSummary.startedByName`, piped through for the viewer
    /// chrome's IG-style broadcaster identity chip — nil for a recording
    /// (no equivalent field on `LiveRecordingRow`, and a finished replay
    /// isn't "someone live" chrome anyway).
    let broadcasterName: String?

    var isAudio: Bool { kind == "audio" }

    static func live(_ s: LiveStreamSummary) -> LivePlayableItem {
        let started = LiveFormat.startedAgo(s.startedAt) ?? "live now"
        return LivePlayableItem(
            id: s.streamId, title: s.title,
            subtitle: "\(started) · \(s.viewerCount) watching",
            kind: s.kind, isLive: true, mediaPath: s.hlsUrl,
            viewerCount: s.viewerCount, heartbeatStreamId: s.streamId,
            broadcasterName: s.startedByName.isEmpty ? nil : s.startedByName)
    }

    static func recording(_ r: LiveRecordingRow, cellName: String? = nil) -> LivePlayableItem {
        let scopeLabel = r.scope == "church" ? "Church" : (cellName ?? "Cell")
        return LivePlayableItem(
            id: r.streamId, title: r.title,
            subtitle: "\(scopeLabel) · \(LiveFormat.dateLabel(r.startedAt))",
            kind: r.kind, isLive: false, mediaPath: r.recordingUrl,
            viewerCount: nil, heartbeatStreamId: nil, broadcasterName: nil)
    }

    /// "My Broadcasts" row → the player — same idiom as `.recording(_:)`,
    /// against the `LiveMyRecordingRow` shape (`url`, not `recording_url`).
    static func myRecording(_ r: LiveMyRecordingRow) -> LivePlayableItem {
        let scopeLabel = r.scope == "church" ? "Church" : "Your cell"
        return LivePlayableItem(
            id: r.streamId, title: r.title,
            subtitle: "\(scopeLabel) · \(LiveFormat.dateLabel(r.startedAt))",
            kind: r.kind, isLive: false, mediaPath: r.url,
            viewerCount: nil, heartbeatStreamId: nil, broadcasterName: nil)
    }
}

// MARK: - Broadcaster-only wire model (L3) — POST /live/streams response.
//
//   POST /live/streams { scope, cell_id?, title, kind } → { stream_id, rtmp_url,
//   stream_key, path }. `rtmp_url` is the bare MediaMTX target with NO stream
//   key or query string on it — BroadcastController combines the two into the
//   real RTMP connect URL (see `publishURL` below).

struct CreatedLiveStream: Decodable, Sendable {
    let streamId: String
    let rtmpUrl: String
    let streamKey: String
    let path: String          // "church" | "cell/{cellId}" — informational only

    private enum CodingKeys: String, CodingKey {
        case streamId, rtmpUrl, streamKey, path
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        streamId = try c.decode(String.self, forKey: .streamId)
        rtmpUrl = (try? c.decodeIfPresent(String.self, forKey: .rtmpUrl)) ?? ""
        streamKey = (try? c.decodeIfPresent(String.self, forKey: .streamKey)) ?? ""
        path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? ""
    }

    /// The actual RTMP connect URL for `RTMPConnection.connect(_:)`.
    ///
    /// MediaMTX's own documented OBS usage is: Server = `rtmp://host/mypath`,
    /// Stream Key = blank. ffmpeg confirms the same thing works when the whole
    /// URL (including query string) is treated as one opaque connect target
    /// with nothing appended as a separate stream name. HaishinKit's
    /// RTMPConnection mirrors that exactly — `makeConnectionMessage()` builds
    /// the RTMP "app" from the connect URL's path PLUS its query string
    /// verbatim (`app = path; if query { app += "?" + query }`), so the
    /// credentials below travel as part of the app/connect target, not as a
    /// stream name. `RTMPStream.publish("")` (empty streamName) is the other
    /// half of this — see BroadcastController.connect(_:).
    var publishURL: String {
        var comps = URLComponents(string: rtmpUrl)
        var items = comps?.queryItems ?? []
        items.append(URLQueryItem(name: "user", value: streamId))
        items.append(URLQueryItem(name: "pass", value: streamKey))
        comps?.queryItems = items
        return comps?.string ?? "\(rtmpUrl)?user=\(streamId)&pass=\(streamKey)"
    }
}
