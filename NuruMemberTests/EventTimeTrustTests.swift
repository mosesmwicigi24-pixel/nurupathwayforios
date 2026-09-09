// Event times a member can act on. The wire's `end_at` is not always there and
// not always sane, and `CalendarOccurrence` decodes an absent one to "" — which
// `Ev.date` turns into `.distantPast`. Read straight, that invented a
// small-hours end on the TIME tile AND made every such occurrence compare as
// already finished, which hid its RSVP selector.
//
// Mirrors Android's `evTrustedEnd` (EventsShared.kt) — both platforms must
// refuse the same ends, because a wrong time on a church invitation costs real
// attendance.
import XCTest
@testable import NuruMember

final class EventTimeTrustTests: XCTestCase {

    private let start = "2026-08-30T09:00:00Z"

    // MARK: - trustedEnd refuses what it cannot believe

    func testAbsentEndIsNotTrusted() {
        XCTAssertNil(Ev.trustedEnd(start, ""))
    }

    func testUnparsableEndIsNotTrusted() {
        XCTAssertNil(Ev.trustedEnd(start, "not a date"))
    }

    func testEndBeforeStartIsNotTrusted() {
        XCTAssertNil(Ev.trustedEnd(start, "2026-08-30T08:00:00Z"))
    }

    func testEndEqualToStartIsNotTrusted() {
        XCTAssertNil(Ev.trustedEnd(start, start))
    }

    /// Even a kesha ends: a span past 12h is a data error, not a service.
    func testImplausibleSpanIsNotTrusted() {
        XCTAssertNil(Ev.trustedEnd(start, "2026-08-31T09:00:00Z"))   // 24h
    }

    func testTwelveHourSpanIsStillTrusted() {
        XCTAssertNotNil(Ev.trustedEnd(start, "2026-08-30T21:00:00Z")) // exactly 12h
    }

    func testOrdinaryServiceEndIsTrusted() {
        XCTAssertNotNil(Ev.trustedEnd(start, "2026-08-30T13:00:00Z"))
    }

    func testUnparsableStartIsNotTrusted() {
        XCTAssertNil(Ev.trustedEnd("", "2026-08-30T13:00:00Z"))
    }

    // MARK: - What the member actually reads

    /// The whole point: show the start alone rather than invent an end.
    func testTimeRangeShowsStartAloneWhenEndIsUntrusted() {
        let shown = Ev.timeRange(start, "")
        XCTAssertFalse(shown.contains("–"), "showed a range from an absent end: \(shown)")
        XCTAssertFalse(shown.isEmpty)
        XCTAssertEqual(shown, Ev.timeRange(start, "not a date"))
    }

    func testTimeRangeShowsBothEndsWhenTrusted() {
        XCTAssertTrue(Ev.timeRange(start, "2026-08-30T13:00:00Z").contains("–"))
    }

    func testTimeRangeIsEmptyWithoutAStart() {
        XCTAssertEqual(Ev.timeRange("", "2026-08-30T13:00:00Z"), "")
    }

    // MARK: - An absent end must never finish an event

    /// The RSVP-hiding bug, pinned: a long-past start with no end is NOT over.
    func testAbsentEndNeverMarksAnEventEnded() {
        XCTAssertFalse(Ev.hasEnded("2020-01-01T09:00:00Z", ""))
        XCTAssertFalse(Ev.hasEnded("2020-01-01T09:00:00Z", "not a date"))
    }

    func testTrustedPastEndMarksAnEventEnded() {
        XCTAssertTrue(Ev.hasEnded("2020-01-01T09:00:00Z", "2020-01-01T13:00:00Z"))
    }

    func testFutureEventHasNotEnded() {
        XCTAssertFalse(Ev.hasEnded("2099-01-01T09:00:00Z", "2099-01-01T13:00:00Z"))
    }

    // MARK: - isLive

    func testAbsentEndIsNeverLive() {
        XCTAssertFalse(Ev.isLive("2020-01-01T09:00:00Z", ""))
    }

    func testPastOccurrenceIsNotLive() {
        XCTAssertFalse(Ev.isLive("2020-01-01T09:00:00Z", "2020-01-01T13:00:00Z"))
    }

    func testFutureOccurrenceIsNotLive() {
        XCTAssertFalse(Ev.isLive("2099-01-01T09:00:00Z", "2099-01-01T13:00:00Z"))
    }
}
