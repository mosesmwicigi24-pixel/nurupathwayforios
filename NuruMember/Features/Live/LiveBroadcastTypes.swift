// Nuru Live L3 — small shared broadcaster-only types used by the setup sheet
// and the broadcast screen. Kept separate from Models/Live.swift because
// these aren't wire DTOs — they're local UI/session state.
import Foundation

/// POST /live/streams `kind`.
enum LiveBroadcastKind: String, CaseIterable, Sendable {
    case video
    case audio
}

/// POST /live/streams `scope` — the CHOICE made in the setup sheet (not the
/// server's echoed value, which the create response doesn't even return).
enum LiveBroadcastScopeChoice: String, Sendable {
    case church
    case cell
}

/// Everything the broadcast screen needs once POST /live/streams succeeds.
/// The create response itself carries only stream_id/rtmp_url/stream_key/path
/// — kind and title never round-trip, so the setup sheet threads them through
/// here instead of the broadcast screen re-deriving them.
struct GoLiveSession: Identifiable, Sendable {
    let stream: CreatedLiveStream
    let kind: LiveBroadcastKind
    let title: String
    var id: String { stream.streamId }
}
