// Read aloud and the reading theme (member suggestion, 2026-11-21: "dark mode
// would be particularly useful for reading at night" and "listen to the
// teachings and articles instead of having to read everything"). What each
// reader says, where it cuts, how fast, and which page it is drawn on — all
// pure, so nothing here needs a voice or a screen. The engine itself
// (ReadAloud.swift) needs a device. Android's twins: ListenScriptTest,
// ReaderListenTest, ReadingThemeTest.
import XCTest
import SwiftUI
@testable import NuruMember

final class ListenAndNightReadingTests: XCTestCase {
    func testPlanNarrationRejectsUntrustedPathsAndVersions() {
        let id = "4c5fbfa1-d7e7-4d8f-8a89-a2970a95c904"
        let valid = PlanNarration(planId: id, day: 1, part: "word", version: String(repeating: "a", count: 64))
        XCTAssertEqual(valid.audioPath(index: 2), "growth/plans/\(id)/days/1/narration/word/\(String(repeating: "a", count: 64))/2/audio")
        XCTAssertNil(valid.audioPath(index: 100))
        XCTAssertNil(PlanNarration(planId: "../other", day: 1, part: "word").path)
        XCTAssertNil(PlanNarration(planId: id, day: 1, part: "word", version: "../bad").audioPath(index: 0))
    }

    func testPlanPlaybackNamesTheDeviceFallback() {
        let reading = ListenReading(words: ["A reading"], isPlan: true)
        let controls = ListenControls.resolve(reading, loadedKey: reading.key, status: .playing,
                                              index: 0, offered: true, speed: 1, deviceFallback: true)
        XCTAssertEqual(controls.stateLine, "Device voice")
    }

    @MainActor
    func testPlanAudioPlaysEachParagraphOnSimulator() async throws {
        let player = ReadAloud.shared
        guard player.offered else { throw XCTSkip("Spoken feedback or live audio is active") }
        var requests: [String] = []
        player.testAudioLoader = { path in requests.append(path); return Self.silentMp3() }
        defer { player.stop(); player.testAudioLoader = nil }
        let source = PlanNarration(planId: "4c5fbfa1-d7e7-4d8f-8a89-a2970a95c904", day: 1,
                                   part: "word", version: String(repeating: "a", count: 64))
        player.play(ListenReading(words: ["One", "Two"], narration: source, isPlan: true))
        for _ in 0..<100 {
            if requests.count == 2 && player.status == .idle { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(player.status, .idle)
    }

    // Generated silence, encoded as MP3 to exercise the production codec.
    private static func silentMp3() -> Data {
        Data(base64Encoded: "SUQzBAAAAAAAIlRTU0UAAAAOAAADTGF2ZjYzLjEuMTAyAAAAAAAAAAAAAAD/8zTEAAAAA0gAAAAATEFNRTQuMFVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/8zTEOwAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/8zTEdgAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/8zTEsQAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/8zTExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVUxBTUU0LjBVVVVVVVVVVVVVVVX/8zTExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/8zTExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/8zTExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVX/8zTExAAAA0gAAAAAVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVVU=")!
    }
    func testReadingVoicePrefersPremiumThenFallsBackToEnglish() {
        let voices = [
            ListenVoiceCandidate(identifier: "gb-enhanced", language: "en-GB", quality: 1),
            ListenVoiceCandidate(identifier: "us-premium", language: "en-US", quality: 2),
            ListenVoiceCandidate(identifier: "fr-premium", language: "fr-FR", quality: 2)
        ]
        XCTAssertEqual(ListenVoiceSelector.choose(from: voices)?.identifier, "us-premium")
        XCTAssertEqual(ListenVoiceSelector.choose(from: [voices[0]])?.identifier, "gb-enhanced")
        XCTAssertNil(ListenVoiceSelector.choose(from: [voices[2]]))
    }

    private func read(_ pieces: [ListenPiece]) -> [String] { ListenScript.paragraphs(pieces) }

    private func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func segment(_ id: String, _ kind: String, title: String = "", reference: String? = nil,
                         content: String? = nil) -> PlanSegment {
        PlanSegment(segmentId: id, sort: 0, kind: kind, title: title, reference: reference, content: content,
                    videoUrl: nil, imageUrl: nil, completed: false)
    }

    // MARK: - The script: what is said, and where it cuts

    func testAHeadingIsReadOnceWithAPauseAfterIt() {
        XCTAssertEqual(read([.heading("Building Successful")]), ["Building Successful."])
    }

    func testProseSplitsAtBlankLinesAndRunsItsOwnLinesTogether() {
        XCTAssertEqual(read([.prose("God sees you.\nHe knows you.\n\nWalk with Him.")]),
                       ["God sees you. He knows you.", "Walk with Him."])
    }

    func testMarkdownMarksLinksImagesAndRulesAreNotReadOut() {
        let md = "## The **first** step\n\n> Trust *Him* fully\n\n- one thing\n- [another](https://x.org)\n\n---\n\n![photo](a.png)"
        XCTAssertEqual(read([.prose(md)]), ["The first step.", "Trust Him fully", "one thing. another."])
    }

    func testATableReadsRowByRowItsCellsPausedItsRuleSilent() {
        let md = "| Day | Reading |\n|---|:---:|\n| Monday | Psalm 23:1 |"
        XCTAssertEqual(read([.prose(md)]), ["Day, Reading. Monday, Psalm 23, verse 1."])
    }

    func testReferencesInProseAreReadAsWordsAndOnlyRealBooksCount() {
        XCTAssertEqual(ListenScript.speakable("As Romans 8:28 says"), "As Romans 8, verse 28 says")
        XCTAssertEqual(ListenScript.speakable("Read John 15:1-4 today"), "Read John 15, verses 1 to 4 today")
        XCTAssertEqual(ListenScript.speakable("1 John 4:8"), "1 John 4, verse 8")
        XCTAssertEqual(ListenScript.speakable("The service starts at 10:30"), "The service starts at 10:30")
    }

    func testACrossChapterReferenceNamesTheSecondChapter() {
        XCTAssertEqual(ListenScript.naturalReference("John 3:16–4:2"), "John 3, verse 16 to chapter 4, verse 2")
        XCTAssertEqual(ListenScript.naturalReference("Read the whole chapter"), "Read the whole chapter")
    }

    func testAPassageIsItsReferenceThenItsVersesWithoutTheirNumbers() {
        let p = read([.scripture(text: "22 Do not merely listen to the word. 23 Anyone who listens",
                                 reference: "James 1:22-23", startVerse: 22)])
        XCTAssertEqual(p, ["James 1, verses 22 to 23.", "Do not merely listen to the word. Anyone who listens"])
    }

    func testALongParagraphIsCutAtSentenceEndsUnderTheLimit() {
        let sentence = "Grace is enough for today."
        let text = Array(repeating: sentence, count: 10).joined(separator: " ")
        let chunks = ListenScript.chunk(text, maxChars: 60)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 60 }, "\(chunks)")
        XCTAssertEqual(chunks.joined(separator: " "), text)
        XCTAssertEqual(chunks.count, 5)
    }

    func testOneSentenceLongerThanTheLimitIsCutAtASpace() {
        let long = Array(repeating: "a", count: 50).joined(separator: " ")
        let chunks = ListenScript.chunk(long, maxChars: 20)
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 20 && !$0.hasPrefix(" ") }, "\(chunks)")
        XCTAssertEqual(chunks.joined(separator: " "), long)
    }

    func testNothingSpeakableMeansNoParagraphs() {
        XCTAssertTrue(read([.prose("---\n\n![x](y)"), .heading("  ")]).isEmpty)
        XCTAssertNil(ListenScript.speakable("***"))
    }

    func testTheSameWordsGiveTheSameKey() {
        XCTAssertEqual(ListenScript.key(["a", "b"]), ListenScript.key(["a", "b"]))
        XCTAssertNotEqual(ListenScript.key(["a", "b"]), ListenScript.key(["ab"]))
        XCTAssertEqual(ListenReading(words: ["a"]), ListenReading(words: ["a"]))
    }

    func testSpeedsCycleAndReadAsMultipliers() {
        XCTAssertEqual(ListenSpeed.next(after: 1.0), 1.25)
        XCTAssertEqual(ListenSpeed.next(after: 1.5), 0.8)
        XCTAssertEqual(ListenSpeed.next(after: 0.9), 1.0, "an odd value moves on from its nearest step")
        XCTAssertEqual(ListenSpeed.label(1.0), "1×")
        XCTAssertEqual(ListenSpeed.label(1.25), "1.25×")
        XCTAssertEqual(ListenSpeed.label(0.8), "0.8×")
        XCTAssertEqual(ListenSpeed.label(1.5), "1.5×")
    }

    func testOneTimesIsALittleSlowerThanTheEnginesDefaultAndEveryRateStaysInRange() {
        XCTAssertEqual(ListenSpeed.rate(for: 1.0, defaultRate: 0.5, minimum: 0, maximum: 1), 0.46, accuracy: 0.0001)
        XCTAssertEqual(ListenSpeed.rate(for: 1.5, defaultRate: 0.5, minimum: 0, maximum: 1), 0.69, accuracy: 0.0001)
        XCTAssertEqual(ListenSpeed.rate(for: 4, defaultRate: 0.5, minimum: 0, maximum: 1), 1, "clamped to the engine's maximum")
        XCTAssertEqual(ListenSpeed.rate(for: 1, defaultRate: 0.5, minimum: 0.6, maximum: 1), 0.6, "and to its minimum")
    }

    // MARK: - Each reader, in the order its page shows it

    func testAPlansWordPartReadsTheTitleThePassageAndTheTeaching() {
        let group = [
            segment("s1", "scripture", reference: "Proverbs 13:4", content: "4 A sluggard’s appetite is never filled"),
            segment("s2", "devotional", content: "Diligence is faith at work.\n\nStart small."),
            segment("s3", "reading", content: "James 1:22-25; Romans 12:11"),
        ]
        XCTAssertEqual(read(ReaderListen.planPart(part: "word", group: group, dayTitle: "Building well", passages: [:])), [
            "Building well.",
            "Proverbs 13, verse 4.",
            "A sluggard’s appetite is never filled",
            "Diligence is faith at work.",
            "Start small.",
            "Go deeper.",
            "James 1, verses 22 to 25",
            "Romans 12, verse 11",
        ])
    }

    func testABareReferenceReadsItsFetchedPassageOrJustTheReferenceUntilItLands() {
        let group = [segment("s1", "scripture", reference: "John 3:16")]
        XCTAssertEqual(ReaderListen.passagesToFetch(part: "word", group: group), ["John 3:16"])
        XCTAssertEqual(read(ReaderListen.planPart(part: "word", group: group, dayTitle: nil, passages: [:])),
                       ["John 3, verse 16."])
        XCTAssertEqual(read(ReaderListen.planPart(part: "word", group: group, dayTitle: nil,
                                                  passages: ["John 3:16": "16 For God so loved the world"])),
                       ["John 3, verse 16.", "For God so loved the world"])
    }

    func testTheRespondPartReadsItsPrayersAndAFilmPartReadsNothingOverTheFilm() {
        let prayer = [segment("p", "devotional", title: "Pray", content: "Lord, make me faithful.")]
        XCTAssertEqual(read(ReaderListen.planPart(part: "respond", group: prayer, dayTitle: nil, passages: [:])),
                       ["Lord, make me faithful."])
        let film = [segment("v", "video", title: "Talk", content: "Keynotes")]
        XCTAssertTrue(read(ReaderListen.planPart(part: "media", group: film, dayTitle: nil, passages: [:])).isEmpty)
        XCTAssertTrue(read(ReaderListen.planPart(part: nil, group: film, dayTitle: nil, passages: [:])).isEmpty)
        XCTAssertTrue(ReaderListen.passagesToFetch(part: "media", group: film).isEmpty)
    }

    func testTheDevotionalEndsOnItsQuestion() throws {
        let d = try decode(Devotional.self, [
            "devotional_id": "d", "day_number": 3, "title": "Planted", "scripture_ref": "Psalm 1:3",
            "scripture_text": "3 He is like a tree planted by streams", "body": "Roots first.",
            "reflection_prompt": "Where are you planted?",
        ])
        XCTAssertEqual(read(ReaderListen.devotional(d)),
                       ["Planted.", "Psalm 1, verse 3.", "He is like a tree planted by streams", "Roots first.",
                        "Reflection.", "Where are you planted?"])
    }

    func testTheLetterReadsItsTitleSalutationBodyVerseAndSignature() {
        var l = PastoralLetter(letterId: "L", weekOf: "2026-11-22", title: "A week of grace", salutation: "Dear Wanjiru,",
                               body: "", scriptureRef: nil, createdAt: "", readAt: nil)
        l.paragraphs = ["You came back.", "God noticed."]
        l.scripture = LetterScripture(ref: "Philippians 4:6", text: "Do not be anxious about anything", version: "ESV")
        l.signedBy = LetterSigner(name: "Moses", role: "Senior Pastor")
        XCTAssertEqual(read(ReaderListen.letter(l)), [
            "A week of grace.", "Dear Wanjiru,", "You came back.", "God noticed.",
            "Philippians 4, verse 6.", "Do not be anxious about anything", "With grace, Moses, Senior Pastor.",
        ])
    }

    func testALetterWithoutASignerIsSignedByTheChurchAndABareVerseIsNamed() {
        var l = PastoralLetter(letterId: "L", weekOf: "2026-11-22", body: "One.", scriptureRef: "Psalm 23:1",
                               createdAt: "", readAt: nil)
        l.paragraphs = ["One."]
        XCTAssertEqual(read(ReaderListen.letter(l)),
                       ["Your Sunday Letter.", "Dear friend,", "One.", "Scripture: Psalm 23, verse 1", "With grace, Nuru Place."])
        XCTAssertEqual(ReaderListen.signature(LetterSigner(name: "Pastor Moses", role: nil)), "With grace, Pastor Moses.")
    }

    func testAClassicLetterReadsItsReferenceBeforeTheLetterAndItsWeek() {
        let l = PastoralLetter(letterId: "L", weekOf: "2026-11-22", title: "Two prayers", salutation: "Dear Grace,",
                               body: "First.\n\nSecond.", scriptureRef: "Psalm 23:1",
                               highlights: ["You prayed twice."], createdAt: "", readAt: nil)
        XCTAssertEqual(read(ReaderListen.classicLetter(l)), [
            "Two prayers.", "Dear Grace,", "Scripture: Psalm 23, verse 1", "First.", "Second.",
            "This week.", "You prayed twice.", "With grace, Nuru Place.",
        ])
    }

    func testALessonNumbersItsSectionsOnlyWhenItHasMoreThanOne() throws {
        let base: [String: Any] = ["module_id": "m", "level_number": 1, "module_sequence_number": 1, "title": "Prayer",
                                   "lesson_content": "## Why pray\n\nBecause He listens."]
        XCTAssertEqual(read(ReaderListen.module(try decode(ModuleDetail.self, base))),
                       ["Prayer.", "Why pray.", "Because He listens."])
        var two = base
        two["content_pages"] = ["Part one.", "Part two."]
        two["key_verses"] = ["“Pray continually.” — 1 Thessalonians 5:17"]
        // The key verse where this phone shows it: after the first section's words.
        XCTAssertEqual(read(ReaderListen.module(try decode(ModuleDetail.self, two))), [
            "Prayer.", "Section 1.", "Part one.", "Key verse.", "“Pray continually.” — 1 Thessalonians 5, verse 17",
            "Section 2.", "Part two.",
        ])
    }

    // MARK: - The controls: offered, loaded, and the bar's words

    func testListenIsOfferedOnlyWithWordsAndNothingInTheWay() {
        let reading = ListenReading(words: ["One.", "Two."])
        let idle = ListenControls.resolve(reading, loadedKey: nil, status: .idle, index: 0, offered: true, speed: 1)
        XCTAssertTrue(idle.available)
        XCTAssertFalse(idle.active)
        XCTAssertEqual(idle.glyph, .headphones)
        XCTAssertEqual(idle.label, "Listen — read this aloud")
        XCTAssertEqual(idle.pillWord, "Listen")
        XCTAssertFalse(ListenControls.resolve(reading, loadedKey: nil, status: .idle, index: 0, offered: false, speed: 1).available,
                       "VoiceOver on, or the church live: no Listen")
        XCTAssertFalse(ListenControls.resolve(.empty, loadedKey: nil, status: .idle, index: 0, offered: true, speed: 1).available,
                       "nothing to read: no Listen")
    }

    func testALoadedReadingKeepsItsControlsAndSaysWhereItIs() {
        let reading = ListenReading(words: ["One.", "Two.", "Three."])
        let playing = ListenControls.resolve(reading, loadedKey: reading.key, status: .playing, index: 1,
                                             offered: false, speed: 1.25)
        XCTAssertTrue(playing.available, "a reading already playing keeps its controls when the church goes live")
        XCTAssertTrue(playing.active)
        XCTAssertTrue(playing.playing)
        XCTAssertEqual(playing.glyph, .pause)
        XCTAssertEqual(playing.label, "Pause reading aloud")
        XCTAssertEqual(playing.stateLine, "Reading aloud")
        XCTAssertEqual(playing.placeLine, "2 of 3")
        XCTAssertEqual(playing.progress, 2.0 / 3.0, accuracy: 0.0001)
        let paused = ListenControls.resolve(reading, loadedKey: reading.key, status: .paused, index: 2, offered: true, speed: 1)
        XCTAssertEqual(paused.glyph, .play)
        XCTAssertEqual(paused.stateLine, "Paused")
        XCTAssertEqual(paused.pillWord, "Resume")
        let other = ListenControls.resolve(reading, loadedKey: "another", status: .playing, index: 2, offered: true, speed: 1)
        XCTAssertFalse(other.active, "another reader's reading is not this one's")
        XCTAssertEqual(other.index, 0)
    }

    // MARK: - The reading theme

    func testAutomaticFollowsThePhoneDayAndNightDoNot() {
        XCTAssertTrue(ReadingTheme.auto.isNight(systemDark: true))
        XCTAssertFalse(ReadingTheme.auto.isNight(systemDark: false))
        XCTAssertFalse(ReadingTheme.day.isNight(systemDark: true))
        XCTAssertTrue(ReadingTheme.night.isNight(systemDark: false))
    }

    func testAnUnknownOrMissingKeyIsAutomaticAndTheWordsAreAndroids() {
        XCTAssertEqual(ReadingTheme.from(nil), .auto)
        XCTAssertEqual(ReadingTheme.from("sepia"), .auto)
        XCTAssertEqual(ReadingTheme.from("night"), .night)
        XCTAssertEqual(ReadingTheme.storageKey, "nuru.readingTheme")
        XCTAssertEqual(ListenSpeed.storageKey, "nuru.listen.speed")
        XCTAssertEqual(ReadingTheme.allCases.map(\.rawValue), ["auto", "day", "night"])
        XCTAssertEqual(ReadingTheme.allCases.map(\.label), ["Automatic", "Day", "Night"])
        XCTAssertEqual(ReadingThemeWords.caption,
                       "Plans, the devotional, the Sunday letter and lessons. Automatic follows your phone's dark mode. Each reader has a listen button too.")
    }

    func testTheReadersButtonChoosesTheOtherPageExplicitly() {
        XCTAssertEqual(ReadingTheme.toggled(currentlyNight: true), .day)
        XCTAssertEqual(ReadingTheme.toggled(currentlyNight: false), .night)
        XCTAssertEqual(ReadingTheme.toggleLabel(night: true), "Day page")
        XCTAssertEqual(ReadingTheme.toggleLabel(night: false), "Night page")
    }

    func testTheOldNightSwitchCarriesOverOnceAndNeverOverAChoice() throws {
        XCTAssertEqual(ReadingTheme.migratedValue(stored: nil, legacyNight: true), "night")
        XCTAssertNil(ReadingTheme.migratedValue(stored: nil, legacyNight: false), "no night: Automatic")
        XCTAssertNil(ReadingTheme.migratedValue(stored: "day", legacyNight: true), "a choice already made stands")

        let suite = "ReadingTheme.\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set(true, forKey: ReadingTheme.legacyNightKey)
        ReadingTheme.migrateLegacySetting(in: d)
        XCTAssertEqual(d.string(forKey: ReadingTheme.storageKey), "night")
        d.set("day", forKey: ReadingTheme.storageKey)
        ReadingTheme.migrateLegacySetting(in: d)
        XCTAssertEqual(d.string(forKey: ReadingTheme.storageKey), "day", "it runs at every launch and changes nothing after")
    }

    // MARK: - The day pages stay exactly as they were

    func testTheDayPagesAreTheirOwnColoursAndTheNightPageIsTheSepia() {
        let day = MLPalette()
        XCTAssertEqual(day.navy, ML.navy)
        XCTAssertEqual(day.cream, ML.cream)
        XCTAssertEqual(day.surface, ML.surface)
        XCTAssertEqual(day.card, Color.white)
        XCTAssertEqual(day.bodyInk, ML.bodyInk)
        let night = MLPalette(night: true)
        XCTAssertNotEqual(night.cream, ML.cream)
        XCTAssertEqual(night.navyFill, ML.navy, "a navy fill stays dark on the night page")

        XCTAssertEqual(DevotionalPalette().paper, Nuru.paper)
        XCTAssertEqual(DevotionalPalette().navy, Nuru.navy)
        XCTAssertEqual(DevotionalPalette().submitFill, Nuru.navy)
        XCTAssertNotEqual(DevotionalPalette(night: true).paper, Nuru.paper)

        XCTAssertEqual(LetterInk().body, LetterInk.dayBody)
        XCTAssertEqual(LetterInk(night: true).body, LetterInk.nightBody)
        XCTAssertEqual(LetterInk().card, Color.white)

        XCTAssertFalse(ReaderPalette().night)
        XCTAssertNotEqual(ReaderPalette(night: true), ReaderPalette(), "the page turns when the theme does")
    }
}
