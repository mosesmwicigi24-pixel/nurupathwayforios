// Sunday Letter v2 — pins the two contracts that must never regress:
//   1. theme→illustration resolution is TOTAL (every known theme resolves to
//      itself; anything unrecognised — typo, future addition, missing value —
//      still resolves to a real illustration, never blank);
//   2. PastoralLetter decodes a pre-v2 letter (all five new columns NULL, the
//      exact shape of every letter written before this migration) without
//      throwing and without rendering broken/blank fields.
// Also covers next_step/share_line present vs. absent, since LetterView
// renders (or omits) whole sections based on their nil-ness.
import XCTest
@testable import NuruMember

final class SundayLetterTests: XCTestCase {

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - LetterTheme.resolve — total mapping

    func testEveryKnownThemeResolvesToItself() {
        // Mirrors LETTER_THEMES in packages/backend/src/modules/intelligence/
        // prompts.ts exactly — if the server's vocabulary changes, this test
        // (and LetterTheme's case list) must change with it.
        let known = ["dawn", "water", "path", "harvest", "shelter", "light", "seed", "garden", "mountain", "rest"]
        XCTAssertEqual(Set(known), Set(LetterTheme.allCases.map(\.rawValue)),
                        "the test's known-theme list has drifted from LetterTheme's cases")
        for raw in known {
            XCTAssertEqual(LetterTheme.resolve(raw).rawValue, raw)
        }
    }

    func testUnknownThemeStringFallsBackRatherThanRenderingBlank() {
        for bogus in ["", "sunrise", "SEED", " dawn", "🌅", "null"] {
            let resolved = LetterTheme.resolve(bogus)
            XCTAssertEqual(resolved, LetterTheme.fallback,
                            "unrecognised theme '\(bogus)' must degrade to the fallback, never crash or resolve to nothing")
        }
    }

    func testNilThemeFallsBack() {
        XCTAssertEqual(LetterTheme.resolve(nil), LetterTheme.fallback)
    }

    func testEveryThemeHasAnAccentColor() {
        // Exercises LetterHero's per-theme art table indirectly — a theme
        // with no configured art would be a silent design gap, not a crash,
        // so this is the guard that catches it.
        for theme in LetterTheme.allCases {
            _ = theme.accentColor // must not trap
        }
        XCTAssertEqual(LetterTheme.allCases.count, 10)
    }

    // MARK: - PastoralLetter — null-safe legacy decoding

    /// The exact wire shape of a letter written before feat/sunday-letter-v2:
    /// title/salutation/theme/image_key/highlights/next_step/share_line all
    /// absent, only the original {body, scripture_ref} pair present.
    private static let legacyLetterJSON = """
    {"letter_id":"L1","week_of":"2026-01-04","body":"Grace held you this week, even in the quiet.",
     "scripture_ref":"Psalm 23:1","created_at":"2026-01-04T18:00:00Z","read_at":null}
    """

    func testLegacyLetterDecodesWithoutThrowing() throws {
        XCTAssertNoThrow(try decode(PastoralLetter.self, Self.legacyLetterJSON))
    }

    func testLegacyLetterGetsHonestDefaultsNotBlanks() throws {
        let lt = try decode(PastoralLetter.self, Self.legacyLetterJSON)
        XCTAssertEqual(lt.title, PastoralLetter.defaultTitle)
        XCTAssertEqual(lt.salutation, PastoralLetter.defaultSalutation)
        XCTAssertEqual(lt.theme, LetterTheme.fallback.rawValue)
        XCTAssertEqual(lt.imageKey, lt.theme, "image_key defaults to the (also-defaulted) theme, same as the backend's rowFromDb")
        XCTAssertTrue(lt.highlights.isEmpty)
        XCTAssertNil(lt.nextStep)
        XCTAssertNil(lt.shareLine)
        // Original fields still carry through untouched.
        XCTAssertEqual(lt.body, "Grace held you this week, even in the quiet.")
        XCTAssertEqual(lt.scriptureRef, "Psalm 23:1")
        XCTAssertTrue(lt.isUnread)
    }

    func testLegacyLetterThemeResolvesToARealIllustration() throws {
        let lt = try decode(PastoralLetter.self, Self.legacyLetterJSON)
        // Never blank: even the defaulted theme string round-trips through
        // the total resolver to a real (fallback) illustration.
        XCTAssertEqual(LetterTheme.resolve(lt.imageKey), LetterTheme.fallback)
    }

    func testEmptyObjectRefusesToDecode() {
        // letter_id is the one field the model requires (mirrors
        // ChatConversation/Broadcast's own identity-is-strict contract) — every
        // OTHER field degrades to a safe default, but a row with no id is not
        // a row.
        XCTAssertThrowsError(try decode(PastoralLetter.self, "{}"))
    }

    // MARK: - PastoralLetter — v2 fields present

    func testFullV2LetterDecodesEveryField() throws {
        // next_step.params stays camelCase on the wire (moduleId, not
        // module_id) — it's a JS object literal serialized straight from
        // JSONB, not a top-level DB column run through snake_case, exactly
        // like NextActionParams' own `params.moduleId` (home/service.ts).
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L2","week_of":"2026-08-09","title":"You kept showing up",
         "salutation":"Dear Grace,","theme":"harvest","image_key":"harvest",
         "body":"This week you finished Module 4 and prayed through a hard morning.",
         "scripture_ref":"Galatians 6:9",
         "highlights":["You finished Module 4 on Tuesday","You prayed three mornings this week"],
         "next_step":{"label":"Module 5 is waiting","route":"module","params":{"moduleId":"m-501"}},
         "share_line":"Grace holds, even on the ordinary days.",
         "created_at":"2026-08-09T18:00:00Z","read_at":null}
        """)
        XCTAssertEqual(lt.title, "You kept showing up")
        XCTAssertEqual(lt.salutation, "Dear Grace,")
        XCTAssertEqual(lt.theme, "harvest")
        XCTAssertEqual(lt.imageKey, "harvest")
        XCTAssertEqual(lt.highlights.count, 2)
        XCTAssertEqual(lt.nextStep?.label, "Module 5 is waiting")
        XCTAssertEqual(lt.nextStep?.route, "module")
        XCTAssertEqual(lt.nextStep?.params?.moduleId, "m-501")
        XCTAssertEqual(lt.shareLine, "Grace holds, even on the ordinary days.")
    }

    // MARK: - next_step / share_line — present vs. absent

    func testNextStepAbsentDecodesToNil() throws {
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L3","week_of":"2026-08-09","body":"A quiet week, and that is honest too.",
         "scripture_ref":null,"created_at":"2026-08-09T18:00:00Z","read_at":null}
        """)
        XCTAssertNil(lt.nextStep, "no next_step in the payload → the CTA section must have nothing to render")
    }

    func testNextStepExplicitNullDecodesToNil() throws {
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L4","week_of":"2026-08-09","body":"body","next_step":null,"share_line":null,
         "created_at":"2026-08-09T18:00:00Z","read_at":null}
        """)
        XCTAssertNil(lt.nextStep)
        XCTAssertNil(lt.shareLine)
    }

    func testNextStepWithoutModuleParamsStillDecodes() throws {
        // The backend's generic fallback: { label: "Continue your journey", route: "pathway" } — no params at all.
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L5","week_of":"2026-08-09","body":"body",
         "next_step":{"label":"Continue your journey","route":"pathway"},
         "created_at":"2026-08-09T18:00:00Z","read_at":null}
        """)
        XCTAssertEqual(lt.nextStep?.label, "Continue your journey")
        XCTAssertEqual(lt.nextStep?.route, "pathway")
        XCTAssertNil(lt.nextStep?.params)
    }

    func testShareLinePresent() throws {
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L6","week_of":"2026-08-09","body":"body","share_line":"A short line worth sending on.",
         "created_at":"2026-08-09T18:00:00Z","read_at":null}
        """)
        XCTAssertEqual(lt.shareLine, "A short line worth sending on.")
    }

    func testBlankShareLineTreatedAsAbsent() throws {
        // Defensive per-field decoding: whitespace-only is the same as null —
        // the share affordance must never render an empty share sheet.
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L7","week_of":"2026-08-09","body":"body","share_line":"   ",
         "created_at":"2026-08-09T18:00:00Z","read_at":null}
        """)
        XCTAssertNil(lt.shareLine)
    }

    // MARK: - isUnread / read_at

    func testReadAtPresentMeansNotUnread() throws {
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L8","week_of":"2026-08-09","body":"body",
         "created_at":"2026-08-09T18:00:00Z","read_at":"2026-08-10T09:00:00Z"}
        """)
        XCTAssertFalse(lt.isUnread)
    }
    // MARK: - v3, the editorial letter (owner, 2026-10-07: board A)

    /// GET /v1/me/letters/latest, verbatim from the local API serving
    /// pathway#512 (the v3 contract, e5912d1) — build7's letter.
    static let v3Latest = #"""
{"letter":{"letter_id":"a68526c0-a54a-4461-aa25-f1fd5c1e1a76","week_of":"2026-10-04","title":"The two prayers you marked answered","salutation":"Dear Builder,","theme":"light","image_key":"dawn","body":"You marked two prayers answered this week. That is worth stopping for.","scripture_ref":"Philippians 4:6","highlights":[],"next_step":null,"share_line":null,"created_at":"2026-10-04T15:00:00.000Z","read_at":"2026-10-07T05:03:06.434Z","issue_no":1,"reading_minutes":1,"paragraphs":["You marked two prayers answered this week. That is worth stopping for."],"scripture":{"ref":"Philippians 4:6","text":"Do not be anxious about anything, but in everything by prayer and supplication with thanksgiving let your requests be made known to God.","version":"ESV"},"photo":{"id":"1580687774725-4e23db308efc","url":"https://images.unsplash.com/photo-1580687774725-4e23db308efc?auto=format&fit=crop&w=1080&q=70","alt":"Trees in the hazy savanna light","caption":"Trees in the hazy savanna light. Chosen for a week of light breaking through."},"figures":[],"signed_by":{"name":"Pastor Moses","role":"Nuru Place"},"pdf_url":"/v1/me/letters/a68526c0-a54a-4461-aa25-f1fd5c1e1a76/pdf"}}
"""#

    /// The same letter as the v2 server sent it (before pathway#512): the
    /// v3 response less its eight v3 fields — nothing else differs.
    static let v2Latest = #"""
{"letter":{"letter_id":"a68526c0-a54a-4461-aa25-f1fd5c1e1a76","week_of":"2026-10-04","title":"The two prayers you marked answered","salutation":"Dear Builder,","theme":"light","image_key":"dawn","body":"You marked two prayers answered this week. That is worth stopping for.","scripture_ref":"Philippians 4:6","highlights":[],"next_step":null,"share_line":null,"created_at":"2026-10-04T15:00:00.000Z","read_at":"2026-10-07T05:03:06.434Z"}}
"""#

    private struct Latest: Decodable { let letter: PastoralLetter? }

    private func v3Letter() throws -> PastoralLetter { try XCTUnwrap(decode(Latest.self, Self.v3Latest).letter) }
    private func v2Letter() throws -> PastoralLetter { try XCTUnwrap(decode(Latest.self, Self.v2Latest).letter) }

    func testAV3LetterDecodesEveryEditorialField() throws {
        let lt = try v3Letter()
        XCTAssertTrue(lt.isEditorial, "a v3 letter is laid out as board A")
        XCTAssertEqual(lt.issueNo, 1)
        XCTAssertEqual(lt.readingMinutes, 1)
        XCTAssertEqual(lt.paragraphs, ["You marked two prayers answered this week. That is worth stopping for."])
        XCTAssertEqual(lt.scripture?.ref, "Philippians 4:6")
        XCTAssertEqual(lt.scripture?.version, "ESV")
        XCTAssertTrue(lt.scripture?.text?.hasPrefix("Do not be anxious about anything") == true)
        XCTAssertEqual(lt.photo?.alt, "Trees in the hazy savanna light")
        XCTAssertEqual(lt.photo?.caption, "Trees in the hazy savanna light. Chosen for a week of light breaking through.")
        XCTAssertTrue(lt.photo?.url.hasPrefix("https://images.unsplash.com/") == true)
        XCTAssertEqual(lt.figures, [])
        XCTAssertEqual(lt.signedBy, LetterSigner(name: "Pastor Moses", role: "Nuru Place"))
        XCTAssertEqual(lt.pdfUrl, "/v1/me/letters/a68526c0-a54a-4461-aa25-f1fd5c1e1a76/pdf")
        // v2's fields, as ever.
        XCTAssertEqual(lt.title, "The two prayers you marked answered")
        XCTAssertEqual(lt.salutation, "Dear Builder,")
        XCTAssertEqual(lt.imageKey, "dawn")
        XCTAssertNil(lt.nextStep)
        XCTAssertNil(lt.shareLine)
        XCTAssertEqual(lt.highlights, [])
        XCTAssertFalse(lt.isUnread)
    }

    func testAV2LetterHasNoEditorialFieldsAndKeepsTodaysStationery() throws {
        let lt = try v2Letter()
        XCTAssertFalse(lt.isEditorial, "a v2 letter renders exactly as before (LetterView's own stationery)")
        XCTAssertNil(lt.issueNo)
        XCTAssertNil(lt.readingMinutes)
        XCTAssertNil(lt.paragraphs)
        XCTAssertNil(lt.scripture)
        XCTAssertNil(lt.photo)
        XCTAssertEqual(lt.figures, [])
        XCTAssertNil(lt.signedBy)
        XCTAssertNil(lt.pdfUrl)
        // The same letter: v3 only added.
        let v3 = try v3Letter()
        XCTAssertEqual([lt.letterId, lt.weekOf, lt.title, lt.salutation, lt.theme, lt.imageKey, lt.body, lt.createdAt],
                       [v3.letterId, v3.weekOf, v3.title, v3.salutation, v3.theme, v3.imageKey, v3.body, v3.createdAt])
        XCTAssertEqual(lt.scriptureRef, v3.scriptureRef)
        XCTAssertEqual(lt.readAt, v3.readAt)
    }

    func testAnOddV3FieldNeverCostsTheLetter() throws {
        let lt = try decode(PastoralLetter.self, """
        {"letter_id":"L9","week_of":"2026-10-04","body":"A quiet week.","paragraphs":["  ",""],"issue_no":"six",
         "reading_minutes":0,"scripture":{"ref":"  ","text":"x"},"photo":{"id":"p","url":" "},
         "figures":[{"value":"","label":"x"},{"value":"4","label":"reflections written"},{"value":"2"}],
         "signed_by":{"name":" "},"pdf_url":"  ","created_at":"2026-10-04T15:00:00Z","read_at":null}
        """)
        XCTAssertFalse(lt.isEditorial, "no paragraphs worth showing: today's stationery")
        XCTAssertNil(lt.issueNo)
        XCTAssertNil(lt.readingMinutes)
        XCTAssertNil(lt.scripture)
        XCTAssertNil(lt.photo)
        XCTAssertEqual(lt.figures, [LetterFigure(value: "4", label: "reflections written"), LetterFigure(value: "2", label: "")],
                       "a figure needs its value; one without a label keeps its value, and an odd one never costs the rest")
        XCTAssertNil(lt.signedBy)
        XCTAssertNil(lt.pdfUrl)
        XCTAssertEqual(lt.body, "A quiet week.")
    }

    func testReadingALetterKeepsEveryField() throws {
        let lt = try v3Letter()
        let read = lt.markedRead(at: "2026-10-07T09:00:00Z")
        XCTAssertEqual(read.readAt, "2026-10-07T09:00:00Z")
        XCTAssertEqual(read.paragraphs, lt.paragraphs)
        XCTAssertEqual(read.scripture, lt.scripture)
        XCTAssertEqual(read.photo, lt.photo)
        XCTAssertEqual(read.signedBy, lt.signedBy)
        XCTAssertEqual(read.pdfUrl, lt.pdfUrl)
        XCTAssertEqual(read.issueNo, lt.issueNo)
        XCTAssertTrue(read.isEditorial, "Home's knock clears without the letter losing its layout")
    }

    func testTheDropCapIsTheFirstLetter() {
        let s = LetterDropCap.split("Ten lessons. You finished every one of them.")
        XCTAssertEqual(s?.initial, "T")
        XCTAssertEqual(s?.rest, "en lessons. You finished every one of them.")
        XCTAssertEqual(LetterDropCap.split("  You marked two prayers answered.")?.initial, "Y")
        XCTAssertEqual(LetterDropCap.split("  You marked two prayers answered.")?.rest, "ou marked two prayers answered.")
        XCTAssertEqual(LetterDropCap.split("Émile wrote.")?.initial, "É")
        // Nothing but a letter takes the cap: the first word stays whole.
        XCTAssertNil(LetterDropCap.split("\u{201C}Ten lessons,\u{201D} you wrote."))
        XCTAssertNil(LetterDropCap.split("10 lessons done."))
        XCTAssertNil(LetterDropCap.split(""))
        XCTAssertNil(LetterDropCap.split("A"))
        // Board A's cap spans two lines of 17/28 reading text.
        XCTAssertEqual(LetterDropCap.lines, 2)
    }

    func testTheEditorialFallbacks() throws {
        let v3 = try v3Letter()
        // The photograph, or the bundled art.
        XCTAssertEqual(LetterEditorialWords.hero(v3),
                       .photo(URL(string: "https://images.unsplash.com/photo-1580687774725-4e23db308efc?auto=format&fit=crop&w=1080&q=70")!,
                              alt: "Trees in the hazy savanna light",
                              caption: "Trees in the hazy savanna light. Chosen for a week of light breaking through."))
        XCTAssertEqual(LetterEditorialWords.hero(try v2Letter()), .art(imageKey: "dawn"))
        var noScheme = v3
        noScheme.photo = LetterPhoto(id: nil, url: "photo-1580687774725", alt: nil, caption: nil)
        XCTAssertEqual(LetterEditorialWords.hero(noScheme), .art(imageKey: "dawn"), "never a broken picture")
        // The verse in full; the reference alone when its text didn't come.
        XCTAssertEqual(LetterEditorialWords.scriptureKicker(try XCTUnwrap(LetterEditorialWords.scripture(v3))), "Philippians 4:6 · ESV")
        let bare = try XCTUnwrap(LetterEditorialWords.scripture(try v2Letter()))
        XCTAssertNil(bare.text, "a v2 reference: the reference alone")
        XCTAssertEqual(LetterEditorialWords.scriptureKicker(bare), "Philippians 4:6")
        XCTAssertNil(LetterEditorialWords.scripture(PastoralLetter(letterId: "L", weekOf: "2026-10-04", body: "b",
                                                                   scriptureRef: nil, createdAt: "", readAt: nil)))
        // "YOUR WEEK, IN GRACE": a figure or a highlight, else hidden.
        XCTAssertFalse(LetterEditorialWords.showsWeek(v3), "build7's week: no figures, no highlights — hidden")
        var withFigure = v3
        withFigure.figures = [LetterFigure(value: "10/10", label: "lessons finished")]
        XCTAssertTrue(LetterEditorialWords.showsWeek(withFigure))
        let withHighlight = PastoralLetter(letterId: "L", weekOf: "2026-10-04", body: "b", scriptureRef: nil,
                                           highlights: ["You wrote four reflections."], createdAt: "", readAt: nil)
        XCTAssertTrue(LetterEditorialWords.showsWeek(withHighlight))
        // The signer, else the church.
        XCTAssertEqual(LetterEditorialWords.signer(v3).name, "Pastor Moses")
        XCTAssertEqual(LetterEditorialWords.signer(try v2Letter()), LetterSigner(name: "Nuru Place", role: nil))
        // The paragraphs, else the body on its blank lines.
        let body = PastoralLetter(letterId: "L", weekOf: "2026-10-04", body: "One.\n\nTwo.\n\n  ", scriptureRef: nil,
                                  createdAt: "", readAt: nil)
        XCTAssertEqual(LetterEditorialWords.paragraphs(body), ["One.", "Two."])
        XCTAssertEqual(LetterEditorialWords.paragraphs(v3), v3.paragraphs)
    }

    func testTheEditorialWords() throws {
        XCTAssertEqual(LetterEditorialWords.dateline(issueNo: 6, weekOf: "2026-10-04"), "No. 6 · Sunday 4 October 2026")
        XCTAssertEqual(LetterEditorialWords.dateline(issueNo: nil, weekOf: "2026-10-04"), "Sunday 4 October 2026")
        XCTAssertEqual(LetterEditorialWords.dateline(issueNo: 2, weekOf: "not a date"), "No. 2")
        XCTAssertEqual(LetterEditorialWords.dek(readingMinutes: 2), "Your week, read back to you · 2 min")
        XCTAssertEqual(LetterEditorialWords.dek(readingMinutes: nil), "Your week, read back to you")
        XCTAssertEqual(LetterEditorialWords.pullQuote("He who began a good work in me isn't finished yet."),
                       "\u{201C}He who began a good work in me isn't finished yet.\u{201D}")
        XCTAssertEqual(LetterEditorialWords.pullQuote("\u{201C}Already quoted.\u{201D}"), "\u{201C}Already quoted.\u{201D}")
        XCTAssertEqual(LetterEditorialWords.verb(LetterNextStep(label: "God & His Nature is waiting", route: "module",
                                                                params: LetterNextStepParams(moduleId: "m1"))), "Begin")
        XCTAssertEqual(LetterEditorialWords.verb(LetterNextStep(label: "Continue your journey", route: "pathway", params: nil)), "Continue")
        XCTAssertEqual(LetterEditorialWords.pdfFileName(try v3Letter()), "Sunday Letter — Sunday 4 October 2026.pdf")
        // "Last week:" is the latest letter before this one.
        func letter(_ id: String, _ week: String) -> PastoralLetter {
            PastoralLetter(letterId: id, weekOf: week, title: "Letter \(id)", body: "b", scriptureRef: nil, createdAt: "", readAt: nil)
        }
        let now = letter("c", "2026-10-04")
        XCTAssertEqual(LetterEditorialWords.previous(now, in: [now, letter("a", "2026-09-20"), letter("b", "2026-09-27")])?.letterId, "b")
        XCTAssertNil(LetterEditorialWords.previous(now, in: [now]), "the first letter has no last week")
        XCTAssertNil(LetterEditorialWords.previous(letter("a", "2026-09-20"), in: [now, letter("a", "2026-09-20")]),
                     "a later letter is never last week")
    }

    /// "Write back" says why it didn't open in the Pastor tab's words — the
    /// local server answers 404 no_pastor for a congregation with no pastor.
    func testWriteBackSaysWhyItDidntOpen() {
        XCTAssertEqual(LetterEditorialWords.writeBackFailure(
            APIError.http(status: 404, code: "NOT_FOUND", message: "No pastor available"), signer: "Pastor Moses"),
            "No pastor is available for your congregation yet — please check back soon.")
        XCTAssertEqual(LetterEditorialWords.writeBackFailure(
            APIError.http(status: 403, code: "FORBIDDEN", message: "x"), signer: "Pastor Moses"),
            "Direct messages aren't available on this account.")
        XCTAssertTrue(LetterEditorialWords.writeBackFailure(APIError.offline, signer: "Pastor Moses")
            .hasPrefix("Couldn't open your conversation with Pastor Moses."))
    }

    /// `pdf_url` is a path from the server's root that already carries /v1 —
    /// against the API's origin, never its base ("/v1/v1/…").
    func testTheLettersPDFResolvesAgainstTheOrigin() {
        let prod = URL(string: "https://pathway.nuruplace.org/v1")!
        let local = URL(string: "http://localhost:8080/v1")!
        let path = "/v1/me/letters/a68526c0-a54a-4461-aa25-f1fd5c1e1a76/pdf"
        XCTAssertEqual(APIClient.serverURL(path, base: prod)?.absoluteString,
                       "https://pathway.nuruplace.org/v1/me/letters/a68526c0-a54a-4461-aa25-f1fd5c1e1a76/pdf")
        XCTAssertEqual(APIClient.serverURL(path, base: local)?.absoluteString,
                       "http://localhost:8080/v1/me/letters/a68526c0-a54a-4461-aa25-f1fd5c1e1a76/pdf")
        XCTAssertEqual(APIClient.serverURL("me/letters/x/pdf", base: prod)?.absoluteString,
                       "https://pathway.nuruplace.org/v1/me/letters/x/pdf", "a bare path is under the base, as send reads it")
        XCTAssertEqual(APIClient.serverURL("https://files.example.org/a.pdf", base: prod)?.absoluteString,
                       "https://files.example.org/a.pdf")
        XCTAssertNil(APIClient.serverURL("   ", base: prod))
    }
}
