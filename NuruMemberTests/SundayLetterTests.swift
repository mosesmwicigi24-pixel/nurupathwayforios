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
}
