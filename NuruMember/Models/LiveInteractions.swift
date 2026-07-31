// Nuru Live L5 — interactive-stage wire models (raise-hand, reactions, live
// chat) + L6 guest scaffolding. Shapes mirror the PINNED contract in
// docs/LIVE_INTERACTIVE.md exactly (backend built to it in parallel):
//   POST /live/streams/{id}/reactions        {emoji} → 204
//   POST /live/streams/{id}/hand             {raised} → 204
//   GET  /live/streams/{id}/messages?since=  → {messages:[LiveChatMessage]}
//   POST /live/streams/{id}/messages         {body} → 201 the message
//   GET  /live/streams/{id}/pulse            → LivePulse (below)
//   POST /live/streams/{id}/guests/{userId}         (invite, broadcaster)
//   POST /live/streams/{id}/guests/respond   {accept} (invitee)
//   DELETE /live/streams/{id}/guests/{userId}       (broadcaster or self)
//
// Every DTO decodes tolerantly (optionals + defaults) — same discipline as
// Models/Live.swift — since the backend is still being built against this
// same pinned doc and a field arriving late (or renamed) must never crash
// the interactive overlay.
import Foundation

// MARK: - Live chat (L5)

struct LiveChatMessage: Decodable, Sendable, Identifiable, Equatable {
    let messageId: String
    let userId: String
    let fullName: String
    let avatarUrl: String?
    let body: String
    let sentAt: String

    var id: String { messageId }

    private enum CodingKeys: String, CodingKey {
        case messageId, userId, fullName, avatarUrl, body, sentAt
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        messageId = (try? c.decodeIfPresent(String.self, forKey: .messageId)) ?? UUID().uuidString
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "Member"
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        sentAt = (try? c.decodeIfPresent(String.self, forKey: .sentAt)) ?? ""
    }
}

/// GET /live/streams/{id}/messages envelope — `{messages: [...]}`, ascending,
/// capped at 200/poll server-side.
struct LiveMessagesEnvelope: Decodable, Sendable {
    let messages: [LiveChatMessage]

    private enum CodingKeys: String, CodingKey { case messages }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        messages = (try? c.decodeIfPresent([LiveChatMessage].self, forKey: .messages)) ?? []
    }
}

// MARK: - Pulse (L5) — the one poll for the whole interactive overlay

/// One entry of `pulse.recent_reactions` — a recent like/love, timestamped so
/// the client can tell which ones it hasn't animated yet.
struct LiveRecentReaction: Decodable, Sendable, Equatable {
    let emoji: String   // "like" | "love"
    let at: String       // ISO 8601

    private enum CodingKeys: String, CodingKey { case emoji, at }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        emoji = (try? c.decodeIfPresent(String.self, forKey: .emoji)) ?? "like"
        at = (try? c.decodeIfPresent(String.self, forKey: .at)) ?? ""
    }
}

struct LiveReactionCounts: Decodable, Sendable, Equatable {
    let like: Int
    let love: Int
    /// Third reaction kind, added alongside like/love (owner ask, 2026-07-31)
    /// — decodes tolerantly to 0 so this client keeps working against a
    /// pulse response from before the backend added it.
    let fire: Int

    private enum CodingKeys: String, CodingKey { case like, love, fire }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        like = (try? c.decodeIfPresent(Int.self, forKey: .like)) ?? 0
        love = (try? c.decodeIfPresent(Int.self, forKey: .love)) ?? 0
        fire = (try? c.decodeIfPresent(Int.self, forKey: .fire)) ?? 0
    }
    init(like: Int = 0, love: Int = 0, fire: Int = 0) { self.like = like; self.love = love; self.fire = fire }
}

/// One raised hand — `pulse.hands`.
struct LiveHandRow: Decodable, Sendable, Identifiable, Equatable {
    let userId: String
    let fullName: String
    let avatarUrl: String?
    let raisedAt: String

    var id: String { userId }

    private enum CodingKeys: String, CodingKey { case userId, fullName, avatarUrl, raisedAt }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "Member"
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        raisedAt = (try? c.decodeIfPresent(String.self, forKey: .raisedAt)) ?? ""
    }
}

/// One guest slot — `pulse.guests`. `status`: invited → accepted|declined →
/// removed|ended (a stream end sweeps every row to `ended` server-side).
struct LiveGuestRow: Decodable, Sendable, Identifiable, Equatable {
    let userId: String
    let fullName: String
    let avatarUrl: String?
    let status: String
    /// L6b — the MediaMTX WHEP URL the STREAM'S OWN OWNER subscribes to for
    /// this guest's real WebRTC video (`.../webrtc/guest/<streamId>/<userId>/whep`).
    /// Present only for the broadcaster's own pulse poll and only once the
    /// guest is `accepted` — absent for every other caller (viewers, the
    /// guest themselves) and absent for `invited`/`declined`/`removed`/`ended`
    /// rows, so decodes tolerantly to nil rather than erroring.
    let whepUrl: String?

    var id: String { userId }
    var isActive: Bool { status == "invited" || status == "accepted" }

    private enum CodingKeys: String, CodingKey { case userId, fullName, avatarUrl, status, whepUrl }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? "Member"
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? "invited"
        whepUrl = try? c.decodeIfPresent(String.self, forKey: .whepUrl)
    }
}

/// GET /live/streams/{id}/guests/me/ingest — the CALLING user's own WHIP
/// publish credentials, valid only while their `pulse.guests` row is
/// `accepted` on a LIVE stream (403 FORBIDDEN_SCOPE otherwise). `whipUrl` is
/// the bare MediaMTX WHIP endpoint
/// (`.../webrtc/guest/<streamId>/<userId>/whip`); WhipPublisher appends
/// `?user=<userId>&pass=<token>` itself (MediaMTX's credential-based
/// WHIP/WHEP auth — see docs/LIVE_INTERACTIVE.md and BroadcastController's
/// header comment on the RTMP equivalent).
struct GuestIngest: Decodable, Sendable {
    let whipUrl: String
    let token: String
    let path: String

    private enum CodingKeys: String, CodingKey { case whipUrl, token, path }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        whipUrl = (try? c.decodeIfPresent(String.self, forKey: .whipUrl)) ?? ""
        token = (try? c.decodeIfPresent(String.self, forKey: .token)) ?? ""
        path = (try? c.decodeIfPresent(String.self, forKey: .path)) ?? ""
    }
}

/// GET /live/streams/{id}/pulse — the ONE poll driving the whole interactive
/// overlay (broadcaster every 3s, viewer every 5s): viewer count, reaction
/// tallies + a recent-events tail (for the floating particle overlay), who
/// has a hand up, and the guest roster.
struct LivePulse: Decodable, Sendable {
    let viewerCount: Int
    let reactions: LiveReactionCounts
    let recentReactions: [LiveRecentReaction]
    let hands: [LiveHandRow]
    let guests: [LiveGuestRow]

    private enum CodingKeys: String, CodingKey {
        case viewerCount, reactions, recentReactions, hands, guests
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        viewerCount = (try? c.decodeIfPresent(Int.self, forKey: .viewerCount)) ?? 0
        reactions = (try? c.decodeIfPresent(LiveReactionCounts.self, forKey: .reactions)) ?? LiveReactionCounts()
        recentReactions = (try? c.decodeIfPresent([LiveRecentReaction].self, forKey: .recentReactions)) ?? []
        hands = (try? c.decodeIfPresent([LiveHandRow].self, forKey: .hands)) ?? []
        guests = (try? c.decodeIfPresent([LiveGuestRow].self, forKey: .guests)) ?? []
    }
}
