// Liturgy recorder (feat/liturgy-recorded-voice) — pins the PURE logic in
// LiturgyRecorderLogic.swift: the 7-band clock order, how a possibly sparse/
// scrambled/duplicated server response becomes a complete canonical row
// list, and the small arithmetic (mm:ss formatting, the 1–900s validity
// bound). None of this touches AVAudioRecorder/AVAudioPlayer — see
// LiturgyRecorder.swift for the (untestable-on-CI) recorder model it backs.
import XCTest
@testable import NuruMember

final class LiturgyRecorderLogicTests: XCTestCase {

    // MARK: - LiturgyBand.clockOrder

    func testClockOrderHasAllSevenBandsInOrder() {
        XCTAssertEqual(LiturgyBand.clockOrder,
                        [.sunrise, .morning, .midday, .afternoon, .evening, .night, .midnight])
    }

    func testEveryBandHasAHumanReadableLabel() {
        let labels = LiturgyBand.clockOrder.map(\.label)
        XCTAssertEqual(labels, ["Sunrise", "Morning", "Midday", "Afternoon", "Evening", "Night", "Midnight"])
    }

    // MARK: - LiturgyRecordingRows.build — always 7, always clock order

    func testBuildFromEmptyStatusesYieldsAllSevenBandsUnrecorded() {
        let rows = LiturgyRecordingRows.build(from: [])
        XCTAssertEqual(rows.map(\.band), LiturgyBand.clockOrder)
        XCTAssertTrue(rows.allSatisfy { !$0.hasRecording })
    }

    func testBuildReordersAScrambledResponseIntoClockOrder() {
        // The contract promises clock order already, but the row-builder must
        // not silently trust that — a reordered response still comes out
        // right, the same defensive posture as every other list in this app.
        let statuses = [
            LiturgyRecordingStatus(band: "midnight", audioUrl: "https://a/mid.m4a", durationSec: 40, recordedAt: nil),
            LiturgyRecordingStatus(band: "sunrise", audioUrl: "https://a/sun.m4a", durationSec: 30, recordedAt: nil),
        ]
        let rows = LiturgyRecordingRows.build(from: statuses)
        XCTAssertEqual(rows.map(\.band), LiturgyBand.clockOrder)
        XCTAssertEqual(rows.first { $0.band == .sunrise }?.audioUrl, "https://a/sun.m4a")
        XCTAssertEqual(rows.first { $0.band == .midnight }?.audioUrl, "https://a/mid.m4a")
        // Every band in between stays present and unrecorded, not dropped.
        XCTAssertEqual(rows.count, 7)
        XCTAssertFalse(rows.first { $0.band == .morning }!.hasRecording)
    }

    func testBuildKeepsTheLastEntryOnADuplicateBand() {
        // Mirrors the upsert semantics of the endpoint itself: the newest
        // write for a band is the one that counts.
        let statuses = [
            LiturgyRecordingStatus(band: "evening", audioUrl: "https://a/old.m4a", durationSec: 10, recordedAt: nil),
            LiturgyRecordingStatus(band: "evening", audioUrl: "https://a/new.m4a", durationSec: 20, recordedAt: nil),
        ]
        let rows = LiturgyRecordingRows.build(from: statuses)
        let evening = rows.first { $0.band == .evening }
        XCTAssertEqual(evening?.audioUrl, "https://a/new.m4a")
        XCTAssertEqual(evening?.durationSec, 20)
    }

    func testBuildDropsAnUnrecognizedBandStringRatherThanCrashing() {
        let statuses = [
            LiturgyRecordingStatus(band: "teatime", audioUrl: "https://a/x.m4a", durationSec: 5, recordedAt: nil),
            LiturgyRecordingStatus(band: "morning", audioUrl: "https://a/m.m4a", durationSec: 12, recordedAt: nil),
        ]
        let rows = LiturgyRecordingRows.build(from: statuses)
        XCTAssertEqual(rows.count, 7)   // still exactly the 7 known bands
        XCTAssertEqual(rows.first { $0.band == .morning }?.audioUrl, "https://a/m.m4a")
    }

    // MARK: - LiturgyRecordingRow.hasRecording

    func testHasRecordingIsFalseWhenAudioUrlIsNil() {
        let row = LiturgyRecordingRow(band: .morning, audioUrl: nil, durationSec: nil)
        XCTAssertFalse(row.hasRecording)
    }

    func testHasRecordingIsFalseWhenAudioUrlIsAnEmptyString() {
        let row = LiturgyRecordingRow(band: .morning, audioUrl: "", durationSec: nil)
        XCTAssertFalse(row.hasRecording)
    }

    func testHasRecordingIsTrueWhenAudioUrlIsPresent() {
        let row = LiturgyRecordingRow(band: .morning, audioUrl: "https://a/m.m4a", durationSec: 42)
        XCTAssertTrue(row.hasRecording)
    }

    // MARK: - LiturgyRecorderFormat.timeString

    func testTimeStringFormatsUnderAMinute() {
        XCTAssertEqual(LiturgyRecorderFormat.timeString(0), "0:00")
        XCTAssertEqual(LiturgyRecorderFormat.timeString(5), "0:05")
    }

    func testTimeStringFormatsMinutesAndSecondsWithZeroPadding() {
        XCTAssertEqual(LiturgyRecorderFormat.timeString(65), "1:05")
        XCTAssertEqual(LiturgyRecorderFormat.timeString(605), "10:05")
    }

    func testTimeStringClampsANegativeValueToZeroRatherThanCrashing() {
        XCTAssertEqual(LiturgyRecorderFormat.timeString(-4), "0:00")
    }

    // MARK: - LiturgyRecorderValidation.isValidDuration — mirrors the backend's 1–900s bound

    func testZeroSecondsIsNotAValidDuration() {
        XCTAssertFalse(LiturgyRecorderValidation.isValidDuration(0))
    }

    func testOneSecondIsTheMinimumValidDuration() {
        XCTAssertTrue(LiturgyRecorderValidation.isValidDuration(1))
    }

    func testNineHundredSecondsIsTheMaximumValidDuration() {
        XCTAssertTrue(LiturgyRecorderValidation.isValidDuration(900))
    }

    func testNineHundredOneSecondsExceedsTheBackendBound() {
        XCTAssertFalse(LiturgyRecorderValidation.isValidDuration(901))
    }

    func testANegativeDurationIsNeverValid() {
        XCTAssertFalse(LiturgyRecorderValidation.isValidDuration(-1))
    }
}
