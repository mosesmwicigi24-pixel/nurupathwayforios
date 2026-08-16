// Liturgy voice (feat/liturgy-audio, feat/liturgy-recorded-voice) — pins the
// PURE logic in LiturgyVoiceLogic.swift: how a Scripture reference becomes
// spoken words, how a HomeLiturgy's fields become an ordered reading, the
// playback state machine, voice-selection fallback, and the recorded-vs-
// synthesized audio-source selection. None of this touches
// AVSpeechSynthesizer/AVAudioSession — see LiturgyVoice.swift for the
// (untestable-on-CI) engine that drives it.
import XCTest
@testable import NuruMember

final class LiturgyVoiceTests: XCTestCase {

    // MARK: - spokenReference — the one genuinely fiddly conversion

    func testSimpleVerseReference() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("Psalm 23:1"), "Psalm twenty-three, verse one")
    }

    func testVerseRangeReference() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("John 15:1-4"), "John fifteen, verses one to four")
    }

    func testFirstNumeralBookOrdinal() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("1 Corinthians 13:4-7"),
                        "First Corinthians thirteen, verses four to seven")
    }

    func testSecondNumeralBookOrdinal() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("2 Timothy 1:7"), "Second Timothy one, verse seven")
    }

    func testThirdNumeralBookOrdinal() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("3 John 1:2"), "Third John one, verse two")
    }

    func testChapterOnlyReferenceHasNoVerseWord() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("Genesis 1"), "Genesis one")
    }

    func testMultiWordBookNameSplitsOnTheLastSpace() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("Song of Solomon 2:1"), "Song of Solomon two, verse one")
    }

    func testLargeChapterAndVerseNumbersSpellOutInFull() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("Psalm 119:105"), "Psalm one hundred nineteen, verse one hundred five")
    }

    func testEmptyReferenceReturnsEmpty() {
        XCTAssertEqual(LiturgySpeechText.spokenReference(""), "")
    }

    func testWhitespaceOnlyReferenceReturnsEmpty() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("   \n  "), "")
    }

    /// Never crash, never go silent on a real (if odd) string — best-effort
    /// pass-through when the shape doesn't match "book chapter[:verse(s)]".
    func testUnparseableReferenceFallsBackToTheOriginalRatherThanCrashing() {
        XCTAssertEqual(LiturgySpeechText.spokenReference("TBD"), "TBD")
        XCTAssertEqual(LiturgySpeechText.spokenReference("Selected Readings"), "Selected Readings")
    }

    func testCrossChapterRangeDoesNotCrashAndMentionsBothChapters() {
        // Rare ("Matthew 26:69-27:26") — no exact wording contract, just:
        // never crash, and don't silently drop either chapter number.
        let spoken = LiturgySpeechText.spokenReference("Matthew 26:69-27:26")
        XCTAssertTrue(spoken.contains("twenty-six"))
        XCTAssertTrue(spoken.contains("twenty-seven"))
    }

    // MARK: - spokenBookName

    func testNonNumeralBookNamePassesThroughUnchanged() {
        XCTAssertEqual(LiturgySpeechText.spokenBookName("Psalm"), "Psalm")
        XCTAssertEqual(LiturgySpeechText.spokenBookName("Song of Solomon"), "Song of Solomon")
    }

    // MARK: - segments(...) — what actually gets queued to speak, in order

    func testSegmentsIncludeOnlyTheLineWhenNothingElsePresent() {
        let segs = LiturgySpeechText.segments(line: "Grace meets you here.", charge: nil,
                                               verseLineText: nil, verseLineReference: nil, scriptureRef: nil)
        XCTAssertEqual(segs.map(\.text), ["Grace meets you here."])
    }

    func testSegmentsIncludeChargeWhenPresent() {
        let segs = LiturgySpeechText.segments(line: "Grace meets you here.", charge: "Walk in it today.",
                                               verseLineText: nil, verseLineReference: nil, scriptureRef: nil)
        XCTAssertEqual(segs.map(\.text), ["Grace meets you here.", "Walk in it today."])
    }

    /// Mirrors HomeLiturgyCard's own visual rule exactly (LiturgyCards.swift):
    /// `if let vl = lit.verseLine … else if let ref = lit.scriptureRef` — the
    /// voice must never say MORE than what's on screen (both references).
    func testSegmentsPreferVerseLineOverScriptureRefWhenBothPresent() {
        let segs = LiturgySpeechText.segments(
            line: "Grace meets you here.", charge: nil,
            verseLineText: "His mercies are new every morning.", verseLineReference: "Lamentations 3:23",
            scriptureRef: "Psalm 23:1")
        XCTAssertEqual(segs.map(\.text), [
            "Grace meets you here.",
            "His mercies are new every morning.",
            "Lamentations three, verse twenty-three",
        ])
    }

    func testSegmentsFallBackToScriptureRefWhenNoVerseLine() {
        let segs = LiturgySpeechText.segments(line: "Grace meets you here.", charge: nil,
                                               verseLineText: nil, verseLineReference: nil, scriptureRef: "Psalm 23:1")
        XCTAssertEqual(segs.map(\.text), ["Grace meets you here.", "Psalm twenty-three, verse one"])
    }

    func testBlankFieldsAreTreatedAsAbsentNotAsEmptyUtterances() {
        let segs = LiturgySpeechText.segments(line: "Grace meets you here.", charge: "   ",
                                               verseLineText: "  ", verseLineReference: "Psalm 23:1",
                                               scriptureRef: "John 3:16")
        // charge blank -> skipped; verseLineText blank -> falls through to scriptureRef
        XCTAssertEqual(segs.map(\.text), ["Grace meets you here.", "John three, verse sixteen"])
    }

    func testEmptyLiturgyProducesNoSegments() {
        let segs = LiturgySpeechText.segments(line: "", charge: nil, verseLineText: nil,
                                               verseLineReference: nil, scriptureRef: nil)
        XCTAssertTrue(segs.isEmpty)
    }

    func testFinalSegmentHasNoTrailingPause() {
        let segs = LiturgySpeechText.segments(line: "Grace meets you here.", charge: nil,
                                               verseLineText: nil, verseLineReference: nil, scriptureRef: "Psalm 23:1")
        XCTAssertEqual(segs.last?.pauseAfter, 0)
    }

    // MARK: - LiturgyVoiceState.applying — the TOTAL playback state machine

    func testStartFromIdleGoesToPlaying() {
        XCTAssertEqual(LiturgyVoiceState.idle.applying(.start), .playing)
    }

    func testPauseFromPlayingGoesToPaused() {
        XCTAssertEqual(LiturgyVoiceState.playing.applying(.pause), .paused)
    }

    func testResumeFromPausedGoesToPlaying() {
        XCTAssertEqual(LiturgyVoiceState.paused.applying(.resume), .playing)
    }

    func testStopAlwaysLandsOnIdleFromAnyState() {
        XCTAssertEqual(LiturgyVoiceState.idle.applying(.stop), .idle)
        XCTAssertEqual(LiturgyVoiceState.playing.applying(.stop), .idle)
        XCTAssertEqual(LiturgyVoiceState.paused.applying(.stop), .idle)
    }

    func testFinishAlwaysLandsOnIdleFromAnyState() {
        XCTAssertEqual(LiturgyVoiceState.idle.applying(.finish), .idle)
        XCTAssertEqual(LiturgyVoiceState.playing.applying(.finish), .idle)
        XCTAssertEqual(LiturgyVoiceState.paused.applying(.finish), .idle)
    }

    func testRedundantStartWhileAlreadyActiveIsANoOp() {
        XCTAssertEqual(LiturgyVoiceState.playing.applying(.start), .playing)
        XCTAssertEqual(LiturgyVoiceState.paused.applying(.start), .paused)
    }

    func testPauseWhileNotPlayingIsANoOp() {
        XCTAssertEqual(LiturgyVoiceState.idle.applying(.pause), .idle)
        XCTAssertEqual(LiturgyVoiceState.paused.applying(.pause), .paused)
    }

    func testResumeWhileNotPausedIsANoOp() {
        XCTAssertEqual(LiturgyVoiceState.idle.applying(.resume), .idle)
        XCTAssertEqual(LiturgyVoiceState.playing.applying(.resume), .playing)
    }

    // MARK: - LiturgyVoiceSelector.choose — voice-selection fallback

    func testPrefersEnhancedVoiceInTheMostPreferredLocale() {
        let candidates = [
            LiturgyVoiceCandidate(identifier: "us-default", language: "en-US", isEnhancedOrPremium: false),
            LiturgyVoiceCandidate(identifier: "gb-enhanced", language: "en-GB", isEnhancedOrPremium: true),
            LiturgyVoiceCandidate(identifier: "us-enhanced", language: "en-US", isEnhancedOrPremium: true),
        ]
        // en-GB outranks en-US within the enhanced tier (preferredLocales order).
        XCTAssertEqual(LiturgyVoiceSelector.choose(from: candidates)?.identifier, "gb-enhanced")
    }

    func testEnhancedQualityWinsOverLocalePreference() {
        // An enhanced en-US voice beats a default-quality en-GB voice — audio
        // quality is the FIRST-order preference, locale is the tie-breaker.
        let candidates = [
            LiturgyVoiceCandidate(identifier: "us-enhanced", language: "en-US", isEnhancedOrPremium: true),
            LiturgyVoiceCandidate(identifier: "gb-default", language: "en-GB", isEnhancedOrPremium: false),
        ]
        XCTAssertEqual(LiturgyVoiceSelector.choose(from: candidates)?.identifier, "us-enhanced")
    }

    func testFallsBackToDefaultQualityWhenNoEnhancedVoiceExists() {
        let candidates = [LiturgyVoiceCandidate(identifier: "us-default", language: "en-US", isEnhancedOrPremium: false)]
        XCTAssertEqual(LiturgyVoiceSelector.choose(from: candidates)?.identifier, "us-default")
    }

    func testFallsBackToAnyEnglishLocaleWhenNoneAreInThePreferredList() {
        // en-IN isn't in `preferredLocales` at all — still picked over nothing.
        let candidates = [LiturgyVoiceCandidate(identifier: "in-default", language: "en-IN", isEnhancedOrPremium: false)]
        XCTAssertEqual(LiturgyVoiceSelector.choose(from: candidates)?.identifier, "in-default")
    }

    func testReturnsNilWhenNoEnglishVoiceIsInstalled() {
        let candidates = [
            LiturgyVoiceCandidate(identifier: "fr", language: "fr-FR", isEnhancedOrPremium: true),
            LiturgyVoiceCandidate(identifier: "sw", language: "sw-KE", isEnhancedOrPremium: false),
        ]
        XCTAssertNil(LiturgyVoiceSelector.choose(from: candidates))
    }

    func testReturnsNilForAnEmptyCandidateList() {
        XCTAssertNil(LiturgyVoiceSelector.choose(from: []))
    }

    // MARK: - LiturgyAudioSource.preferred — the Phase 2 seam

    func testPrefersRecordedAudioWhenAURLIsPresent() {
        let source = LiturgyAudioSource.preferred(recordedUrlString: "https://media.nuru.app/liturgy/morning.m4a",
                                                    segments: [.init(text: "fallback", pauseAfter: 0)])
        XCTAssertEqual(source, .recorded(URL(string: "https://media.nuru.app/liturgy/morning.m4a")!))
    }

    func testFallsBackToSynthesisWhenNoURLIsGiven() {
        let segments = [LiturgySpeechSegment(text: "Grace meets you here.", pauseAfter: 0)]
        XCTAssertEqual(LiturgyAudioSource.preferred(recordedUrlString: nil, segments: segments), .synthesized(segments))
    }

    func testFallsBackToSynthesisWhenTheURLStringIsBlank() {
        let segments = [LiturgySpeechSegment(text: "Grace meets you here.", pauseAfter: 0)]
        XCTAssertEqual(LiturgyAudioSource.preferred(recordedUrlString: "   ", segments: segments), .synthesized(segments))
    }

    /// A malformed URL string (one `URL(string:)` itself fails to parse) must
    /// fall back exactly like nil/blank — never crash, never go silent. This
    /// is distinct from the blank-string case above: the string is non-empty
    /// but still unusable as a URL. NOTE: a raw space in the PATH is not
    /// enough to trip this on modern Foundation — it auto-percent-encodes
    /// path/query characters (`"…/morning file.m4a"` parses fine as
    /// `…/morning%20file.m4a`). A space inside the HOST component, though,
    /// is genuinely unparseable — that's what actually exercises this branch.
    func testFallsBackToSynthesisWhenTheURLStringIsMalformed() {
        let segments = [LiturgySpeechSegment(text: "Grace meets you here.", pauseAfter: 0)]
        XCTAssertNil(URL(string: "https://media nuru.app/liturgy/morning.m4a"),
                      "This fixture must itself be unparseable — otherwise this test proves nothing.")
        XCTAssertEqual(
            LiturgyAudioSource.preferred(recordedUrlString: "https://media nuru.app/liturgy/morning.m4a",
                                          segments: segments),
            .synthesized(segments))
    }

    /// A band with no recording — the PERMANENT normal case (mixed coverage
    /// by design, not a gap to fill; see LiturgyVoiceLogic.swift's header).
    /// The recorded-audio field exists on the wire now, but most bands, most
    /// of the time, will still carry no URL, and must still speak synthesized.
    func testTodaysDefaultIsAlwaysSynthesizedWithNoRecordedUrlField() {
        let segments = LiturgySpeechText.segments(line: "Grace meets you here.", charge: nil,
                                                    verseLineText: nil, verseLineReference: nil, scriptureRef: "Psalm 23:1")
        XCTAssertEqual(LiturgyAudioSource.preferred(recordedUrlString: nil, segments: segments), .synthesized(segments))
    }
}
