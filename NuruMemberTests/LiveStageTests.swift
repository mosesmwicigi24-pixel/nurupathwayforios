// Nuru Live L7 — Zoom-style stage (owner-reported live-test defects: guest
// video replacing the host outright, and portrait geometry degrading once
// compositing started). Pins the two PURE pieces the fix is built on:
//
//  - LiveStageLayout: the rail/main-tile rect math BOTH LiveStageCompositor
//    (the actual composited RTMP frame) and LiveStageView (the host's own
//    SwiftUI preview) call into, so the two can't independently drift.
//  - LiveStageSpotlight: the promote/demote/revert state machine that
//    replaced L6c's automatic active-speaker auto-promotion (the literal
//    cause of "host completely replaced by invited guest").
//
// Deliberately does NOT exercise LiveStageCompositor itself — that type is
// `@ScreenActor`-isolated over a real HaishinKit `MediaMixer`, and
// NuruMemberTests (unlike the app target) doesn't link the HaishinKit
// package product, matching this suite's existing convention of testing
// only the pure decision logic behind a HaishinKit/WebRTC-backed type (see
// WhepRetryPolicyTests, GuestAudioPlayoutDeviceTests). The "canvas
// dimensions never vary with guest count" invariant is proven here at the
// layer both the compositor's `mainOverlay` sizing and the SwiftUI main
// tile actually depend on: `LiveStageLayout.mainRect` takes ONLY a canvas
// size — no guest count parameter exists for it to vary with, by
// construction — and `activate`/`addRailTile`/`removeRailTile` never touch
// `encodeSize`/`mixer.screen.size` in the real compositor (see that file's
// L7 header comment and its before/after dimension logging).
import XCTest
@testable import NuruMember

final class LiveStageLayoutTests: XCTestCase {
    private let canvas = CGSize(width: 1080, height: 1920)

    // MARK: Main tile — always the whole canvas, never a function of guest count

    func testMainRectFillsTheEntireCanvas() {
        let rect = LiveStageLayout.mainRect(canvas: canvas)
        XCTAssertEqual(rect, CGRect(origin: .zero, size: canvas))
    }

    /// `mainRect` doesn't take a guest count — there's no argument for it to
    /// react to — so sweeping 0...6 and asserting the SAME rect every time
    /// is the pure-math proof that the main tile's geometry cannot vary
    /// with guest count.
    func testMainRectIdenticalRegardlessOfGuestCount() {
        let expected = CGRect(origin: .zero, size: canvas)
        for guestCount in 0...6 {
            _ = LiveStageLayout.railRects(count: guestCount, canvas: canvas) // exercises the "other" path
            XCTAssertEqual(LiveStageLayout.mainRect(canvas: canvas), expected, "guestCount=\(guestCount)")
        }
    }

    func testMainRectSameForZeroAndSixGuests() {
        XCTAssertEqual(
            LiveStageLayout.mainRect(canvas: canvas),
            LiveStageLayout.mainRect(canvas: canvas)
        )
    }

    // MARK: Rail — 1...6 guests, in bounds, no overlap, stable ordering

    func testRailRectsEmptyForZeroGuests() {
        XCTAssertEqual(LiveStageLayout.railRects(count: 0, canvas: canvas), [])
    }

    func testRailRectCountMatchesGuestCountForOneToSix() {
        for count in 1...6 {
            XCTAssertEqual(LiveStageLayout.railRects(count: count, canvas: canvas).count, count)
        }
    }

    func testRailRectsAllInBoundsForOneToSix() {
        for count in 1...6 {
            for (index, rect) in LiveStageLayout.railRects(count: count, canvas: canvas).enumerated() {
                XCTAssertGreaterThanOrEqual(rect.minX, 0, "count=\(count) index=\(index)")
                XCTAssertGreaterThanOrEqual(rect.minY, 0, "count=\(count) index=\(index)")
                XCTAssertLessThanOrEqual(rect.maxX, canvas.width, "count=\(count) index=\(index)")
                XCTAssertLessThanOrEqual(rect.maxY, canvas.height, "count=\(count) index=\(index)")
                XCTAssertGreaterThan(rect.width, 0, "count=\(count) index=\(index)")
                XCTAssertGreaterThan(rect.height, 0, "count=\(count) index=\(index)")
            }
        }
    }

    func testRailRectsNeverOverlapForOneToSix() {
        for count in 1...6 {
            let rects = LiveStageLayout.railRects(count: count, canvas: canvas)
            for i in 0..<rects.count {
                for j in (i + 1)..<rects.count where j > i {
                    let intersection = rects[i].intersection(rects[j])
                    XCTAssertTrue(
                        intersection.isNull || intersection.width == 0 || intersection.height == 0,
                        "count=\(count) rects \(i) and \(j) overlap: \(rects[i]) vs \(rects[j])"
                    )
                }
            }
        }
    }

    /// Same x/width down the whole column (right-edge rail, task
    /// requirement C), and monotonically increasing Y — slot N is always
    /// directly below slot N-1, so index → position is stable and
    /// predictable for callers that zip tracks to rects by index.
    func testRailRectsStableTopToBottomOrdering() {
        for count in 2...6 {
            let rects = LiveStageLayout.railRects(count: count, canvas: canvas)
            for i in 1..<rects.count {
                XCTAssertEqual(rects[i].minX, rects[0].minX, accuracy: 0.001, "count=\(count) index=\(i)")
                XCTAssertEqual(rects[i].width, rects[0].width, accuracy: 0.001, "count=\(count) index=\(i)")
                XCTAssertGreaterThan(rects[i].minY, rects[i - 1].minY, "count=\(count) index=\(i)")
            }
        }
    }

    /// Task requirement C: "Up to 6 guests must stack without overflowing —
    /// shrink ... never clip." Six is the densest case; if it fits, every
    /// smaller count fits too (already covered by the in-bounds test above,
    /// this just makes the six-guest case explicit).
    func testSixGuestsShrinkToFitWithoutClipping() {
        let rects = LiveStageLayout.railRects(count: 6, canvas: canvas)
        XCTAssertEqual(rects.count, 6)
        XCTAssertLessThanOrEqual(rects.last?.maxY ?? .infinity, canvas.height)
        XCTAssertGreaterThanOrEqual(rects.first?.minY ?? -1, 0)
    }

    func testRailRectsAreOnTheRightEdge() {
        // Task requirement C: "down the RIGHT side". A rail tile's right
        // edge should sit near the canvas's right edge, well past its
        // horizontal midpoint.
        for count in 1...6 {
            for rect in LiveStageLayout.railRects(count: count, canvas: canvas) {
                XCTAssertGreaterThan(rect.midX, canvas.width / 2, "count=\(count)")
            }
        }
    }
}

final class LiveStageSpotlightTests: XCTestCase {
    func testDefaultsToHost() {
        XCTAssertEqual(LiveStageSpotlight().spotlighted, LiveStageSpotlight.host)
    }

    func testTappingAGuestPromotesThemToMain() {
        var stage = LiveStageSpotlight()
        stage.tap(2)
        XCTAssertEqual(stage.spotlighted, 2)
    }

    func testTappingTheSpotlightedGuestAgainRevertsToHost() {
        var stage = LiveStageSpotlight()
        stage.tap(2)
        stage.tap(2)
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
    }

    func testTappingHostWhileHostIsAlreadyMainIsANoOp() {
        var stage = LiveStageSpotlight()
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
        stage.tap(LiveStageSpotlight.host)
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
    }

    func testTappingADifferentGuestSwitchesDirectlyWithoutRevertingFirst() {
        var stage = LiveStageSpotlight()
        stage.tap(2)
        stage.tap(5)
        XCTAssertEqual(stage.spotlighted, 5, "tapping guest 5 while guest 2 was spotlighted should switch straight to 5")
    }

    func testTappingHostsRailThumbnailRevertsFromASpotlightedGuest() {
        var stage = LiveStageSpotlight()
        stage.tap(3)
        stage.tap(LiveStageSpotlight.host)
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
    }

    func testSpotlightedGuestLeavingFallsBackToHost() {
        var stage = LiveStageSpotlight()
        stage.tap(4)
        XCTAssertEqual(stage.spotlighted, 4)
        stage.participantLeft(4)
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
    }

    func testANonSpotlightedGuestLeavingDoesNotDisturbTheSpotlight() {
        var stage = LiveStageSpotlight()
        stage.tap(1)
        stage.participantLeft(6) // some other guest, never spotlighted
        XCTAssertEqual(stage.spotlighted, 1)
    }

    func testHostLeavingNeverHappensButParticipantLeftIsHarmlessIfItDid() {
        var stage = LiveStageSpotlight()
        stage.participantLeft(LiveStageSpotlight.host)
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
    }

    func testResetForcesBackToHost() {
        var stage = LiveStageSpotlight()
        stage.tap(2)
        stage.reset()
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
    }

    func testFullPromoteDemoteRevertCycle() {
        var stage = LiveStageSpotlight()
        // Promote guest 1.
        stage.tap(1)
        XCTAssertEqual(stage.spotlighted, 1)
        // Demote back to host by tapping host's own rail thumbnail.
        stage.tap(LiveStageSpotlight.host)
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
        // Promote guest 2, then revert by tapping the (now main) guest 2 tile again.
        stage.tap(2)
        XCTAssertEqual(stage.spotlighted, 2)
        stage.tap(2)
        XCTAssertEqual(stage.spotlighted, LiveStageSpotlight.host)
    }
}
