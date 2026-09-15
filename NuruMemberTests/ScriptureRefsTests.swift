// The reference parser behind "scripture woven into the plans": what counts as
// a citation in prose, how an authored Go Deeper line splits, and the exact
// form handed to GET /scripture. Pure logic — nothing here touches the network.
import XCTest
@testable import NuruMember

final class ScriptureRefsTests: XCTestCase {
    func testDetectsACitationInsideProse() {
        let m = ScriptureRefs.detect(in: #"as Scripture says, "faith without works is dead" (James 2:17), and desire"#)
        XCTAssertEqual(m.map(\.reference), ["James 2:17"])
    }

    func testNumberedBooksWinOverTheirBareNames() {
        XCTAssertEqual(ScriptureRefs.detect(in: "Read 1 John 4:8 and John 3:16 tonight.").map(\.reference),
                       ["1 John 4:8", "John 3:16"])
    }

    func testRangesKeepTheirSpanWithAPlainHyphen() {
        XCTAssertEqual(ScriptureRefs.detect(in: "See James 1:22–25.").map(\.reference), ["James 1:22-25"])
        XCTAssertEqual(ScriptureRefs.normalize(" Ephesians 2:8 – 9 "), "Ephesians 2:8-9")
    }

    func testIgnoresTimesAndOrdinaryNumbers() {
        XCTAssertTrue(ScriptureRefs.detect(in: "It comes at 2:17 in the morning, on March 3.").isEmpty)
    }

    func testSplitsASemicolonListAndNormalisesEachPiece() {
        XCTAssertEqual(ScriptureRefs.split("Proverbs 13:4; James 1:22–25"), ["Proverbs 13:4", "James 1:22-25"])
    }

    func testCommaSplitsOnlyWhenBothSidesNameABook() {
        XCTAssertEqual(ScriptureRefs.split("Matthew 5:3, Luke 6:20"), ["Matthew 5:3", "Luke 6:20"])
        XCTAssertEqual(ScriptureRefs.split("Genesis 1:1, 3"), ["Genesis 1:1, 3"])
    }

    func testAnAuthoredNoteSurvivesTheSplitUntouched() {
        XCTAssertEqual(ScriptureRefs.split("Read the whole chapter slowly\nPsalm 23:1-6"),
                       ["Read the whole chapter slowly", "Psalm 23:1-6"])
        XCTAssertFalse(ScriptureRefs.isReference("Read the whole chapter slowly"))
        XCTAssertTrue(ScriptureRefs.isReference("Psalm 23:1-6"))
    }

    func testVerseCountReadsTheSpanOffTheReference() {
        XCTAssertEqual(ScriptureRefs.verseCount("Proverbs 13:4"), 1)
        XCTAssertEqual(ScriptureRefs.verseCount("James 1:22–25"), 4)
        XCTAssertEqual(ScriptureRefs.verseCount("Psalm 23:1-6"), 6)
        XCTAssertNil(ScriptureRefs.verseCount("John 3:16-4:2"))
        XCTAssertNil(ScriptureRefs.verseCount("Read the whole chapter"))
    }

    func testShortPassagesOpenWithoutATap() {
        XCTAssertTrue(ScriptureRefs.opensByDefault("James 1:22-25"))
        XCTAssertFalse(ScriptureRefs.opensByDefault("Psalm 23:1-6"))
        XCTAssertFalse(ScriptureRefs.opensByDefault("John 3:16-4:2"))
    }

    func testChapterPrefixBuildsASingleVersesReference() {
        XCTAssertEqual(ScriptureRefs.chapterPrefix("James 1:22-25"), "James 1")
        XCTAssertEqual(ScriptureRefs.chapterPrefix("1 Peter 2:9"), "1 Peter 2")
        XCTAssertNil(ScriptureRefs.chapterPrefix("not a reference"))
    }

    func testLinkRoundTripsTheReference() throws {
        let url = try XCTUnwrap(ScriptureRefs.url(for: "1 Peter 2:9-10"))
        XCTAssertEqual(url.scheme, "nuru-scripture")
        XCTAssertEqual(ScriptureRefs.reference(from: url), "1 Peter 2:9-10")
        XCTAssertNil(ScriptureRefs.reference(from: URL(string: "https://example.com/?ref=John%203:16")!))
    }
}
