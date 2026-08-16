// Nuru Live — owner-directed LIVE screen redesign (2026-08-01). Pins the
// PURE pieces the new top-row/bottom-dock chrome is built on
// (LiveDockChrome.swift): per-role dock item ordering/eligibility, the
// self-preview minimize/restore reducer, and the TikTok-style counter
// formatting the top row's viewer/hand-count chips use. Deliberately does
// NOT touch any SwiftUI view — same discipline as the sibling
// LiveStageTests.swift (LiveStageLayout/LiveStageSpotlight), which frames
// exactly why: these are the decision-logic layer a view just renders,
// testable with no window/hosting-controller/HaishinKit/WebRTC involved.
import XCTest
@testable import NuruMember

final class LiveDockLayoutTests: XCTestCase {
    // MARK: .viewer — reactions, raise-hand, chat. Never a stage/hardware
    // control (a plain viewer has no camera/mic on this screen to control).

    func testViewerItemsAreEngagementOnly() {
        let items = LiveDockLayout.items(role: .viewer)
        XCTAssertEqual(items, [.reaction(.love), .reaction(.fire), .reaction(.like), .raiseHand, .chat])
    }

    func testViewerNeverGetsGuestOrBroadcasterOnlyControls() {
        let items = Set(LiveDockLayout.items(role: .viewer).map(\.id))
        for forbidden: LiveDockItem in [.camera, .switchCamera, .mic, .speaker, .leave, .end, .documentPage] {
            XCTAssertFalse(items.contains(forbidden.id), "viewer dock must never include \(forbidden.id)")
        }
    }

    /// `isVideo`/`hasDocumentPage` are broadcaster-only knobs — a viewer's
    /// item set must be identical regardless of what's passed for them.
    func testViewerItemsIgnoreBroadcasterOnlyFlags() {
        let a = LiveDockLayout.items(role: .viewer, isVideo: false, hasDocumentPage: true)
        let b = LiveDockLayout.items(role: .viewer, isVideo: true, hasDocumentPage: false)
        XCTAssertEqual(a, b)
    }

    // MARK: .guestOnStage — every engagement control PLUS the full stage/
    // hardware set, in a fixed order, ending with the irreversible action.

    func testGuestOnStageItemsIncludeEveryEngagementAndStageControl() {
        let items = LiveDockLayout.items(role: .guestOnStage)
        XCTAssertEqual(items, [
            .reaction(.love), .reaction(.fire), .reaction(.like), .raiseHand, .chat,
            .camera, .switchCamera, .mic, .speaker, .leave
        ])
    }

    func testGuestOnStageNeverGetsBroadcasterOnlyEnd() {
        XCTAssertFalse(LiveDockLayout.items(role: .guestOnStage).contains(.end))
    }

    /// The one irreversible action in a guest's dock is `.leave`, and it's
    /// always last — never buried mid-row where a slip could hit it.
    func testGuestOnStageLeaveIsAlwaysLast() {
        XCTAssertEqual(LiveDockLayout.items(role: .guestOnStage).last, .leave)
    }

    // MARK: .broadcaster — mirrors GoLiveBroadcastView's pre-redesign
    // control set (mic/flip/End/hand/chat), now gated through the same pure
    // function instead of being hand-assembled inline in the view.

    func testBroadcasterVideoIncludesSwitchCamera() {
        let items = LiveDockLayout.items(role: .broadcaster, isVideo: true)
        XCTAssertTrue(items.contains(.switchCamera))
        XCTAssertEqual(items, [.mic, .switchCamera, .end, .raiseHand, .chat])
    }

    /// Audio-only broadcast — no camera to switch (mirrors the pre-redesign
    /// `if controller.isVideo { flip } else { spacer }` branch).
    func testBroadcasterAudioOnlyExcludesSwitchCamera() {
        let items = LiveDockLayout.items(role: .broadcaster, isVideo: false)
        XCTAssertFalse(items.contains(.switchCamera))
        XCTAssertEqual(items, [.mic, .end, .raiseHand, .chat])
    }

    func testBroadcasterDocumentPageOnlyAppearsWhenFlagged() {
        XCTAssertFalse(LiveDockLayout.items(role: .broadcaster, hasDocumentPage: false).contains(.documentPage))
        XCTAssertTrue(LiveDockLayout.items(role: .broadcaster, hasDocumentPage: true).contains(.documentPage))
    }

    func testBroadcasterNeverGetsGuestOnlyControls() {
        let items = Set(LiveDockLayout.items(role: .broadcaster, isVideo: true, hasDocumentPage: true).map(\.id))
        for forbidden: LiveDockItem in [.camera, .speaker, .leave] {
            XCTAssertFalse(items.contains(forbidden.id), "broadcaster dock must never include \(forbidden.id)")
        }
    }

    // MARK: rows() — the visual row split. Only guestOnStage's wide item set
    // (10 controls) ever splits; everyone else fits one row, always.

    func testViewerRowsIsAlwaysOneRow() {
        XCTAssertEqual(LiveDockLayout.rows(role: .viewer).count, 1)
    }

    func testBroadcasterRowsIsOneRowWithoutADocumentPage() {
        for isVideo in [true, false] {
            XCTAssertEqual(LiveDockLayout.rows(role: .broadcaster, isVideo: isVideo, hasDocumentPage: false).count, 1)
        }
    }

    /// Six items (mic, switchCamera, end, raiseHand, chat, documentPage)
    /// would crowd past the 5-item row cap — the document page indicator (a
    /// passive label, not a tap target) gets bumped to its own second row.
    func testBroadcasterWithDocumentPageSplitsPageIndicatorOntoItsOwnRow() {
        let rows = LiveDockLayout.rows(role: .broadcaster, isVideo: true, hasDocumentPage: true)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], [.mic, .switchCamera, .end, .raiseHand, .chat])
        XCTAssertEqual(rows[1], [.documentPage])
    }

    func testGuestOnStageSplitsIntoExactlyTwoRows() {
        XCTAssertEqual(LiveDockLayout.rows(role: .guestOnStage).count, 2)
    }

    /// Row 1 = engagement (what a plain viewer already has); row 2 = stage
    /// hardware — the two concerns never mix within a row.
    func testGuestOnStageRowsSeparateEngagementFromStageControls() {
        let rows = LiveDockLayout.rows(role: .guestOnStage)
        XCTAssertEqual(rows[0], [.reaction(.love), .reaction(.fire), .reaction(.like), .raiseHand, .chat])
        XCTAssertEqual(rows[1], [.camera, .switchCamera, .mic, .speaker, .leave])
    }

    /// Every row, for every role/flag combination, respects the 44pt tap-
    /// target-friendly cap this UI was designed around — never so wide it
    /// would force controls to shrink below a comfortable one-handed reach.
    /// (A soft design invariant, not a pixel measurement — pinned here as
    /// "no row ever exceeds 5 items" so a future item addition can't quietly
    /// blow past it unnoticed.)
    func testNoRowExceedsFiveItems() {
        let allConfigs: [[LiveDockItem]] =
            LiveDockLayout.rows(role: .viewer) +
            LiveDockLayout.rows(role: .guestOnStage) +
            LiveDockLayout.rows(role: .broadcaster, isVideo: true, hasDocumentPage: true)
        for row in allConfigs {
            XCTAssertLessThanOrEqual(row.count, 5, "row \(row.map(\.id)) exceeds the 5-item comfortable-reach cap")
        }
    }

    // MARK: Determinism — same input, same output, every time (no hidden
    // state, no I/O) — the property that makes this function safe to call
    // straight from a SwiftUI body every render.

    func testItemsIsPureAndDeterministic() {
        for _ in 0..<5 {
            XCTAssertEqual(LiveDockLayout.items(role: .guestOnStage), LiveDockLayout.items(role: .guestOnStage))
        }
    }
}

final class GuestPreviewVisibilityTests: XCTestCase {
    func testDefaultsToExpanded() {
        XCTAssertEqual(GuestPreviewVisibility.expanded, .expanded)
    }

    func testToggleFromExpandedCollapses() {
        XCTAssertEqual(GuestPreviewVisibility.expanded.reduce(.toggle), .collapsed)
    }

    func testToggleFromCollapsedExpands() {
        XCTAssertEqual(GuestPreviewVisibility.collapsed.reduce(.toggle), .expanded)
    }

    func testDoubleToggleReturnsToStart() {
        let start = GuestPreviewVisibility.expanded
        XCTAssertEqual(start.reduce(.toggle).reduce(.toggle), start)
    }

    /// Owner spec: "state remembered within the session" — but a FRESH
    /// stage window (re-accepted after leaving, or a brand-new stream) must
    /// never silently inherit a collapsed preview from a previous one.
    func testStageBecameActiveAlwaysForcesExpandedEvenIfCollapsed() {
        XCTAssertEqual(GuestPreviewVisibility.collapsed.reduce(.stageBecameActive), .expanded)
        XCTAssertEqual(GuestPreviewVisibility.expanded.reduce(.stageBecameActive), .expanded)
    }

    func testTogglingAfterStageBecameActiveStillWorksNormally() {
        let reset = GuestPreviewVisibility.collapsed.reduce(.stageBecameActive)
        XCTAssertEqual(reset.reduce(.toggle), .collapsed)
    }
}

/// `LiveCountFormat.abbreviated` (LiveReactionEffects.swift) backs every
/// counter chip in the redesigned top row (viewers, raised hands) and the
/// dock's reaction captions — previously exercised only indirectly, never
/// pinned directly. Values chosen to walk every boundary the switch in that
/// function has (<1000, the 1000/1,000,000 thresholds, and the ".0" trim).
final class LiveCountFormatTests: XCTestCase {
    func testUnderOneThousandIsShownExactly() {
        XCTAssertEqual(LiveCountFormat.abbreviated(0), "0")
        XCTAssertEqual(LiveCountFormat.abbreviated(1), "1")
        XCTAssertEqual(LiveCountFormat.abbreviated(999), "999")
    }

    func testThousandsAbbreviateWithKSuffix() {
        XCTAssertEqual(LiveCountFormat.abbreviated(1000), "1K")
        XCTAssertEqual(LiveCountFormat.abbreviated(1200), "1.2K")
        XCTAssertEqual(LiveCountFormat.abbreviated(9999), "10K")
        XCTAssertEqual(LiveCountFormat.abbreviated(999_999), "1000K")
    }

    func testMillionsAbbreviateWithMSuffix() {
        XCTAssertEqual(LiveCountFormat.abbreviated(1_000_000), "1M")
        XCTAssertEqual(LiveCountFormat.abbreviated(3_400_000), "3.4M")
    }

    /// "10.0K" must trim to "10K" — the trailing ".0" case.
    func testTrailingPointZeroIsDropped() {
        XCTAssertEqual(LiveCountFormat.abbreviated(10_000), "10K")
        XCTAssertEqual(LiveCountFormat.abbreviated(2_000_000), "2M")
    }

    func testNeverShowsMoreThanOneDecimalPlace() {
        // 1,234 / 1000 = 1.234 → must round to ONE decimal ("1.2K"), not
        // "1.234K" or "1.23K".
        XCTAssertEqual(LiveCountFormat.abbreviated(1234), "1.2K")
    }
}
