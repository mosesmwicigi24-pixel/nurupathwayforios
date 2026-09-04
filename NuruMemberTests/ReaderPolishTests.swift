// The pure decisions behind the reader polish: how long a page takes to read,
// how the text-size step cycles, and how a passage splits into verses so a
// long press lands on one of them.
import XCTest
@testable import NuruMember

final class ReaderPolishTests: XCTestCase {
    func testReadTimeRoundsToWholeMinutesAndNeverSaysZero() {
        XCTAssertEqual(ReadTime.minutes(forWords: 0), 1)
        XCTAssertEqual(ReadTime.minutes(forWords: 90), 1)
        XCTAssertEqual(ReadTime.minutes(forWords: 500), 3)   // 2.5 rounds up
        XCTAssertEqual(ReadTime.minutes(forWords: 1200), 6)
    }

    func testWordCountIgnoresBlankRuns() {
        XCTAssertEqual(ReadTime.words(in: "  one two\n\nthree   four "), 4)
        XCTAssertEqual(ReadTime.words(in: nil), 0)
    }

    func testTextScaleCyclesThroughTheThreeSteps() {
        XCTAssertEqual(ReaderTextScale.next(after: 0.9), 1.0)
        XCTAssertEqual(ReaderTextScale.next(after: 1.0), 1.15)
        XCTAssertEqual(ReaderTextScale.next(after: 1.15), 0.9)
        // An off-step value moves on from its nearest step.
        XCTAssertEqual(ReaderTextScale.next(after: 1.02), 1.15)
        XCTAssertEqual(ReaderTextScale.label(0.9), "Small")
        XCTAssertEqual(ReaderTextScale.label(1.15), "Large")
    }

    func testPassageSplitsAtItsVerseNumbers() {
        let v = ScripturePassageText.verses(in: "22 Do not merely listen to the word. 23 Anyone who listens to the word 24 and goes away")
        XCTAssertEqual(v.map(\.number), ["22", "23", "24"])
        XCTAssertEqual(v[1].body, "Anyone who listens to the word")
    }

    func testAnUnnumberedPassageIsOneVerse() {
        let v = ScripturePassageText.verses(in: "A sluggard's appetite is never filled.")
        XCTAssertEqual(v.count, 1)
        XCTAssertNil(v[0].number)
    }
}
