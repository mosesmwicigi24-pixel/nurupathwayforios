// Nuru Live — host-side reaction rendering (2026-07-31 owner report):
// on the HOST's broadcast screen, a reaction was showing as the raw backend
// key ("fire") instead of its emoji glyph, with no count, while the VIEWER
// screen already rendered it correctly.
//
// INVESTIGATED (iOS, no code change made — see WhepSubscriber's sibling fix
// in this same commit series for the retry work; this file is test-only):
// GoLiveBroadcastView (host) and LiveViewerPlayerView (viewer) both feed
// `pulse.recentReactions`/`freshReactions` into the SAME
// `ReactionBurstQueue.spawn(emoji:)` → `LiveReactionKind(emoji:)` →
// SF Symbol glyph pipeline (LiveReactionEffects.swift) — there is no second,
// host-only mapping and no place in the iOS Live feature that prints a raw
// `String` reaction key to the screen. `LiveReactionKind`'s init is already
// total: every unrecognized key falls back to `.like`'s glyph, never raw
// text. So the raw-string bug described for the host does not reproduce on
// iOS as shipped — these tests exist to PIN that invariant so it can never
// regress (e.g. if a future reaction kind is added and someone forgets to
// extend the switch, or the host ever grows a second, divergent mapping).
import XCTest
@testable import NuruMember

final class LiveReactionKindTests: XCTestCase {
    // MARK: Known keys → their correct glyph + tint — the single mapping
    // BOTH host and viewer consume (LiveReactionEffects.swift).

    func testLikeKeyMapsToThumbsUpGlyph() {
        let kind = LiveReactionKind(emoji: "like")
        XCTAssertEqual(kind, .like)
        XCTAssertEqual(kind.systemImage, "hand.thumbsup.fill")
        XCTAssertEqual(kind.emoji, "like")
    }

    func testLoveKeyMapsToHeartGlyph() {
        let kind = LiveReactionKind(emoji: "love")
        XCTAssertEqual(kind, .love)
        XCTAssertEqual(kind.systemImage, "heart.fill")
        XCTAssertEqual(kind.emoji, "love")
    }

    /// "fire" — the third reaction kind the backend added TODAY (widened
    /// CHECK constraint) alongside like/love. This is the exact key from the
    /// owner's bug report.
    func testFireKeyMapsToFlameGlyph() {
        let kind = LiveReactionKind(emoji: "fire")
        XCTAssertEqual(kind, .fire)
        XCTAssertEqual(kind.systemImage, "flame.fill")
        XCTAssertEqual(kind.emoji, "fire")
    }

    // MARK: Unknown key → the fallback glyph, NEVER the raw string. This is
    // precisely how the reported bug would reach the screen if it existed.

    func testUnrecognizedKeyFallsBackToLikeGlyphNeverRawText() {
        for garbage in ["clap", "wow", "", "FIRE", "🔥", "unknown-future-reaction"] {
            let kind = LiveReactionKind(emoji: garbage)
            XCTAssertEqual(kind, .like, "unrecognized key \"\(garbage)\" must fall back to a known kind")
            XCTAssertEqual(kind.systemImage, "hand.thumbsup.fill")
        }
    }

    // MARK: LiveReactionCounts — decodes the new "fire" tally, and stays
    // tolerant (defaults to 0) if a pulse response predates it.

    func testReactionCountsDecodesAllThreeKinds() throws {
        let json = #"{"like": 12, "love": 7, "fire": 3}"#
        let counts = try JSONDecoder().decode(LiveReactionCounts.self, from: Data(json.utf8))
        XCTAssertEqual(counts.like, 12)
        XCTAssertEqual(counts.love, 7)
        XCTAssertEqual(counts.fire, 3)
    }

    func testReactionCountsDefaultsFireToZeroWhenAbsent() throws {
        // A pulse response from before the backend added "fire" — must not
        // crash or drop the other two counts.
        let json = #"{"like": 5, "love": 2}"#
        let counts = try JSONDecoder().decode(LiveReactionCounts.self, from: Data(json.utf8))
        XCTAssertEqual(counts.like, 5)
        XCTAssertEqual(counts.love, 2)
        XCTAssertEqual(counts.fire, 0)
    }

    // MARK: LivePulse — recentReactions carrying a "fire" entry decodes and
    // round-trips through LiveReactionKind exactly like "like"/"love".

    func testRecentReactionWithFireKeyDecodesAndMapsCorrectly() throws {
        let json = #"{"emoji": "fire", "at": "2026-07-31T19:13:05Z"}"#
        let reaction = try JSONDecoder().decode(LiveRecentReaction.self, from: Data(json.utf8))
        XCTAssertEqual(reaction.emoji, "fire")
        XCTAssertEqual(LiveReactionKind(emoji: reaction.emoji), .fire)
    }
}
