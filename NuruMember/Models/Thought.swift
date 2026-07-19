// Selah — My Thoughts (Prayer Room tab 3, docs: prayer-room-arc). Wire shape
// mirrors packages/backend/src/modules/thoughts/service.ts EXACTLY: `body` is
// the plain-text content, `bodySpans` is the portable rich-text overlay (start/
// end character offsets + the formatting that applies over that range), and
// `drawingUrls` are Cloudinary secure_urls from the existing chat/attachments
// sign→upload flow. There is deliberately no leader/admin read path for this
// domain — "Only you can see it" (owner spec 2026-07-18).
import Foundation

/// One formatting run over `Thought.body[start..<end]` (UTF-16 offsets, matching
/// how NSAttributedString/NSRange already count — no transcoding needed at the
/// boundary). Every field is optional so a span can carry just the one trait
/// that changed at that run.
struct ThoughtSpan: Codable, Sendable, Hashable {
    var start: Int
    var end: Int
    var bold: Bool? = nil
    var italic: Bool? = nil
    /// "#RRGGBB"
    var color: String? = nil
    /// A UIFont name from SelahFonts (e.g. "Fraunces-Regular").
    var font: String? = nil
}

struct Thought: Codable, Sendable, Identifiable {
    var thoughtId: String
    var title: String?
    var body: String
    var bodySpans: [ThoughtSpan]?
    var drawingUrls: [String]
    var createdAt: String
    var updatedAt: String

    var id: String { thoughtId }
}

// Tolerant decoding (server additions must never break an older client build).
extension Thought {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        thoughtId = try c.decode(String.self, forKey: .thoughtId)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        body = (try? c.decodeIfPresent(String.self, forKey: .body)) ?? ""
        bodySpans = (try? c.decodeIfPresent([ThoughtSpan].self, forKey: .bodySpans)) ?? nil
        drawingUrls = (try? c.decodeIfPresent([String].self, forKey: .drawingUrls)) ?? []
        createdAt = (try? c.decodeIfPresent(String.self, forKey: .createdAt)) ?? ""
        updatedAt = (try? c.decodeIfPresent(String.self, forKey: .updatedAt)) ?? ""
    }
}
