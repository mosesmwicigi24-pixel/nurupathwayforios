// The final walk's fix round (pathway docs/EXPERIENCE.md §9.7; the brief
// .nuru-build/briefs/final-fixes-common.md): each rule the walk found broken,
// pinned so it stays fixed. Payloads are decoded as APIClient decodes them:
// snake_case in. Every clock is fixed — Wed 7 Oct 2026, noon in Nairobi —
// so nothing here drifts as the real date moves on.
import XCTest
import SwiftUI
import UIKit
@testable import NuruMember

final class FinalFixesTests: XCTestCase {

    // MARK: Fixtures

    private let nairobi = TimeZone(identifier: "Africa/Nairobi")!
    /// Wed 7 Oct 2026, 12:00 in Nairobi.
    private let wednesday = ISO8601DateFormatter().date(from: "2026-10-07T09:00:00Z")!

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func gift(_ id: String, status: String = "active", frequency: String = "weekly",
                      nextRunAt: String = "2026-10-12T06:00:00.000Z", next: Any = 50_000,
                      failure: String? = nil, pauseReason: String? = nil, resumeOn: String? = nil,
                      pledge: String? = nil) throws -> GivingSchedule {
        var row: [String: Any] = ["schedule_id": id, "fund": "tithe", "amount_minor": 50_000, "currency": "KES",
                                  "method": "mpesa", "frequency": frequency, "status": status,
                                  "next_run_at": nextRunAt, "created_at": "2026-09-01T06:00:00Z",
                                  "next_amount_minor": next]
        if let failure {
            row["last_failure"] = ["code": "insufficient_funds", "reason": failure, "hint": "Top up, then it tries again.",
                                   "retryable": true]
        }
        if let pauseReason { row["pause_reason"] = pauseReason }
        if let resumeOn { row["resume_on"] = resumeOn }
        if let pledge { row["pledge"] = ["pledge_id": pledge, "title": "Missions partner"] }
        return try decode(GivingSchedule.self, row)
    }

    private func standing(pledges: [[String: Any]] = [], due: [[String: Any]] = []) throws -> Partnership {
        try decode(Partnership.self, ["is_partner": true, "pledges": pledges, "due": due])
    }

    private func pledgeJSON(_ id: String = "p-missions", currency: String = "USD", amount: Int = 5_000,
                            pendingClaim: Any? = nil) -> [String: Any] {
        var row: [String: Any] = ["pledge_id": id, "shape": "monthly", "amount_minor": amount, "currency": currency,
                                  "due_day": 15, "title": "Missions partner", "status": "active"]
        if let pendingClaim { row["pending_claim_minor"] = pendingClaim }
        return row
    }

    private func givingRow(_ p: Partnership?, _ s: [GivingSchedule]?) -> HomeWeekRow {
        HomeWeek.givingRow(partnership: p, schedules: s, railsLine: "Tithe & offering · M-Pesa", now: wednesday)
    }

    private func nudge(_ kind: String, route: String, _ params: [String: Any] = [:]) throws -> HomeNudge {
        try decode(HomeNudge.self, ["id": kind, "kind": kind, "title": "Your Sunday letter is waiting", "body": "",
                                    "cta_label": "Read it", "route": route, "params": params, "accent": "navy",
                                    "priority": 75])
    }

    private func segment(_ id: String, kind: String, done: Bool, at: String? = nil, sort: Int = 0) -> PlanSegment {
        PlanSegment(segmentId: id, sort: sort, kind: kind, title: kind.capitalized, reference: nil, content: nil,
                    videoUrl: nil, imageUrl: nil, completed: done, completedAt: at)
    }

    private func source(_ rel: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NuruMember").appendingPathComponent(rel)
        return try String(contentsOf: url, encoding: .utf8)
    }

    // MARK: M1 — Partners never invites a second payment

    func testAPledgeCarriesWhatTheOfficeIsChecking() throws {
        // Eli's dollar pledge: US$ 50 told the office, still being checked.
        let eli = try decode(Pledge.self, pledgeJSON(pendingClaim: 5_000))
        XCTAssertEqual(eli.pendingClaimMinor, 5_000)
        XCTAssertEqual(eli.claimLine, "US$ 50.00 is being checked by the office", "in the pledge's own currency")
        // Ada's Roof sheets, in shillings.
        let ada = try decode(Pledge.self, pledgeJSON("p-roof", currency: "KES", amount: 2_000_000, pendingClaim: 200_000))
        XCTAssertEqual(ada.claimLine, "\(GiveMoney.format(200_000, "KES")) is being checked by the office")
        // Shown, never subtracted: the pledge's own figures stand as the server sent them.
        XCTAssertEqual(ada.remainingMinor, 2_000_000)
        // An older server sends none; nothing odd ever shows.
        XCTAssertEqual(try decode(Pledge.self, pledgeJSON()).pendingClaimMinor, 0)
        XCTAssertNil(try decode(Pledge.self, pledgeJSON()).claimLine)
        XCTAssertNil(try decode(Pledge.self, pledgeJSON(pendingClaim: -3)).claimLine, "a negative is no claim")
        XCTAssertEqual(try decode(Pledge.self, pledgeJSON(pendingClaim: "5000")).pendingClaimMinor, 5_000)
        XCTAssertNotEqual(eli, try decode(Pledge.self, pledgeJSON()), "a new claim redraws the row")
    }

    func testThePageKnowsTheClaimWhicheverReadCarriesIt() throws {
        // The single-pledge read (GET /giving/pledges/:id) carries no
        // pending_claim_minor; the list's copy and the page's own claims do.
        let detail = try decode(Pledge.self, pledgeJSON())
        let listed = try decode(Pledge.self, pledgeJSON(pendingClaim: 5_000))
        XCTAssertEqual(PledgeChecking.minor(rows: [detail, listed, nil], claims: nil, currency: "USD"), 5_000)
        let claims = try decode([PledgeClaim].self, [
            ["claim_id": "c1", "pledge_id": "p-missions", "amount_minor": 5_000, "currency": "USD", "paid_on": "2026-09-30", "status": "pending"],
            ["claim_id": "c2", "pledge_id": "p-missions", "amount_minor": 2_000, "currency": "USD", "paid_on": "2026-09-01", "status": "confirmed"],
            ["claim_id": "c3", "pledge_id": "p-missions", "amount_minor": 900, "currency": "KES", "paid_on": "2026-09-02", "status": "pending"]])
        XCTAssertEqual(PledgeChecking.minor(rows: [detail], claims: claims, currency: "USD"), 5_000,
                       "pending claims in the pledge's own currency; a confirmed one counts already")
        XCTAssertEqual(PledgeChecking.minor(rows: [detail], claims: [], currency: "USD"), 0)
        XCTAssertEqual(PledgeChecking.line(5_000, "USD"), "US$ 50.00 is being checked by the office")
        XCTAssertNil(PledgeChecking.line(0, "USD"))
    }

    func testThePledgePageLeadsWithTheClaimAndPayStepsAside() throws {
        XCTAssertEqual(PledgeClaimLead.counts,
                       "It counts toward this pledge once the office confirms it — no need to pay it again.")
        let page = try source("Features/Give/PartnersView.swift")
        // The lead card comes before the promise card, and Pay is quiet while a claim waits.
        let lead = try XCTUnwrap(page.range(of: "if let claim = PledgeChecking.line(checkingMinor(p), p.currency) { PledgeClaimLead(line: claim) }"))
        let promise = try XCTUnwrap(page.range(of: "Text(pledgeAmountLine(p)).font(.nuruDisplay(22))"))
        XCTAssertLessThan(lead.lowerBound, promise.lowerBound, "the claim leads the pledge's page")
        XCTAssertTrue(page.contains("let quiet = early || checkingMinor(p) > 0"))
        XCTAssertTrue(page.contains(".background(quiet ? Nuru.white : Nuru.gold"), "Pay now is never the gold primary then")
        XCTAssertTrue(page.contains("let quiet = item.action != \"resume\" && item.pendingClaimMinor > 0"),
                      "the DUE row's Pay is the quiet pill while the office checks")
    }

    // MARK: M2 — Home tells a gift the way Give does

    func testAFailedPromptIsNeverCollectedOn() throws {
        // Ben: a weekly gift whose last prompt failed, next prompt Mon 12 Oct.
        let ben = try gift("s-ben", failure: "There wasn't enough in the M-Pesa account.")
        let r = givingRow(try standing(), [ben])
        XCTAssertEqual(r.title, "Giving · Your weekly gift")
        XCTAssertEqual(r.line, "There wasn't enough in the M-Pesa account.", "Give's words — the server's")
        XCTAssertFalse(r.line.hasPrefix("Collected on"))
        XCTAssertTrue(r.urgent, "drawn in Give's amber")
        XCTAssertEqual(r.destination, .schedule("s-ben"), "the gift's sheet")
        XCTAssertNil(r.ask)
        XCTAssertFalse(HomeWeek.asksToGive([r]))
        // A failing gift is the story, even beside a healthy one collecting this week.
        let healthy = try gift("s-ok", frequency: "monthly", nextRunAt: "2026-10-09T06:00:00Z")
        XCTAssertEqual(givingRow(try standing(), [healthy, ben]).destination, .schedule("s-ben"))
        // Without a failure the healthy gift still collects itself.
        XCTAssertEqual(givingRow(try standing(), [healthy]).line, "Collected on Fri 9 Oct")
        XCTAssertFalse(givingRow(try standing(), [healthy]).urgent)
    }

    func testAPausedGiftIsNeverANewGive() throws {
        // Cara: monthly KSh 2,000, stopped after three missed prompts, no date.
        let cara = try gift("s-cara", status: "paused", frequency: "monthly",
                            failure: "The M-Pesa prompt couldn't reach the phone.", pauseReason: "failures")
        let r = givingRow(try standing(), [cara])
        XCTAssertEqual(r.title, "Paused · Your monthly gift")
        XCTAssertEqual(r.line, "Nothing is owed — it won't prompt again until you resume it", "whether and when it resumes")
        XCTAssertEqual(r.line, PauseCopy.cardLine(for: cara, now: wednesday), "in Give's own words")
        XCTAssertEqual(r.destination, .schedule("s-cara"))
        XCTAssertNotEqual(r.title, "Give")
        XCTAssertFalse(HomeWeek.asksToGive([r]), "no Support God's work over a stopped gift")
        // Paused by the member until a day: it comes back then.
        let until = try gift("s-until", status: "paused", pauseReason: "member", resumeOn: "2026-10-12")
        XCTAssertEqual(givingRow(try standing(), [until]).line, "Resumes Mon 12 Oct")
        // Money owed by hand still asks first.
        let owed = try standing(due: [["kind": "pledge", "id": "p-roof", "title": "Roof sheets", "currency": "KES",
                                       "amount_minor": 300_000, "due_on": "2026-10-08", "action": "pay",
                                       "pending_minor": 0, "overdue_count": 0, "overdue_since": NSNull()]])
        XCTAssertEqual(givingRow(owed, [cara]).title, "Pay · Roof sheets")
    }

    // MARK: M3 — offline is honest and never covers the header

    func testASavedCopySaysSoOnlyOverRealContent() {
        XCTAssertTrue(NuruSavedCopyNotice.shows(online: false, hasContent: true))
        XCTAssertFalse(NuruSavedCopyNotice.shows(online: false, hasContent: false), "never over a skeleton or nothing saved")
        XCTAssertFalse(NuruSavedCopyNotice.shows(online: true, hasContent: true))
        XCTAssertEqual(NuruSavedCopyNotice.copy.title, "You're offline")
        XCTAssertEqual(NuruSavedCopyNotice.copy.line, "Showing what you last saw — we'll refresh when you're back.")
    }

    func testThePillSpeaksOnlyOfChangesWaiting() {
        XCTAssertNil(SyncStatusBanner.message(online: false, pending: 0, syncing: false),
                     "being offline is each tab's own notice, under its header")
        XCTAssertEqual(SyncStatusBanner.message(online: false, pending: 2, syncing: false), "Offline · 2 changes will sync")
        XCTAssertEqual(SyncStatusBanner.message(online: false, pending: 1, syncing: false), "Offline · 1 change will sync")
        XCTAssertEqual(SyncStatusBanner.message(online: true, pending: 3, syncing: true), "Syncing 3 changes…")
        XCTAssertNil(SyncStatusBanner.message(online: true, pending: 0, syncing: false))
        for pending in 0...3 {
            for online in [true, false] {
                let m = SyncStatusBanner.message(online: online, pending: pending, syncing: true) ?? ""
                XCTAssertFalse(m.contains("saved on this device"), "money is never queued — Give is under it too")
            }
        }
    }

    func testEveryTabSaysItsSavedCopyUnderItsHeader() throws {
        let tabs = ["Features/Home/HomeView.swift", "Features/Pathway/PathwayView.swift",
                    "Features/Grow/ReadingPlansView.swift", "Features/Events/EventsView.swift",
                    "Features/Give/GivingView.swift", "Features/Give/PartnersView.swift",
                    "Features/Chat/ChatView.swift", "Features/Departments/DepartmentsView.swift",
                    "Features/Profile/ProfileView.swift"]
        for t in tabs {
            XCTAssertTrue(try source(t).contains("NuruSavedCopyNotice(hasContent:"), t)
        }
        let root = try source("Features/Shell/RootView.swift")
        XCTAssertTrue(root.contains(".overlay(alignment: .bottom) { SyncStatusBanner(sync: sync) }"),
                      "the pill sits above the tab bar, never on a title")
    }

    // MARK: M4 — a failed read is never a fact

    func testAFailedReadSaysSoAndNeverAsks() throws {
        let plans = HomeWeek.plansRow(nil)
        XCTAssertEqual(plans.title, "Your reading plans")
        XCTAssertEqual(plans.line, "Didn't load just now")
        XCTAssertNil(plans.ask)
        XCTAssertTrue(plans.unloaded)
        XCTAssertEqual(HomeWeek.plansRow([]).title, "Start a reading plan", "none is still none")

        let cell = HomeWeek.cellRow(nil, loaded: false, timeZone: nairobi, now: wednesday)
        XCTAssertEqual(cell.title, "Your cell")
        XCTAssertEqual(cell.line, "Didn't load just now")
        XCTAssertNil(cell.ask, "never \"Find your cell · Ask\" for a member who may be in one")
        XCTAssertEqual(cell.destination, .community)
        XCTAssertEqual(HomeWeek.cellRow(nil, timeZone: nairobi, now: wednesday).title, "Find your cell", "no cell is still none")

        let events = HomeWeek.eventsRow(calendar: nil, home: nil, rsvps: nil, now: wednesday, timeZone: nairobi)
        XCTAssertEqual(events.line, "Didn't load just now", "never \"No gatherings this week\" on a failed read")
        XCTAssertEqual(HomeWeek.eventsRow(calendar: [], home: [], rsvps: [], now: wednesday, timeZone: nairobi).line,
                       "No gatherings this week")

        let giving = givingRow(nil, [try gift("s")])
        XCTAssertEqual(giving.title, "Your giving")
        XCTAssertEqual(giving.line, "Didn't load just now")
        XCTAssertFalse(HomeWeek.asksToGive([giving]), "no Support God's work on a guess")
    }

    func testTheServerUnreachableWeekIsHonestAndAsksNothing() {
        // Home with every read failed (the walk's 110): no false step.
        let rows = HomeWeek.rows(journey: nil, enrolledLevel: 1, plans: nil, calendar: nil, homeEvents: nil, rsvps: nil,
                                 partnership: nil, schedules: nil, railsLine: "Tithe & offering", cell: nil,
                                 cellLoaded: false, now: wednesday, timeZone: nairobi)
        XCTAssertEqual(rows.map(\.title), ["Open your pathway", "Your reading plans", "See the church calendar",
                                          "Your giving", "Your cell"])
        XCTAssertNil(HomeWeek.cardOrder(rows).step, "no navy next step built on a failed read")
        XCTAssertFalse(HomeWeek.asksToGive(rows))
    }

    func testAFailedPathwayKeepsItsHeader() throws {
        let page = try source("Features/Pathway/PathwayView.swift")
        XCTAssertTrue(page.contains("PathwayFailedHeader()\n                        errorState"))
        XCTAssertTrue(page.contains("NuruHeaderText(title: \"Your pathway\")"))
    }

    // MARK: M5 — system alerts answer in navy

    func testSystemAlertsAnswerInNavy() throws {
        // iOS 26 tints an alert's and a dialog's answers with SwiftUI's
        // accent — the app's AccentColor. It is navy #0B1F33, not the gold
        // #C89B3C that read about 1.05:1 on the alert's glass.
        let accent = try XCTUnwrap(UIColor(named: "AccentColor"))
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        XCTAssertTrue(accent.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&r, green: &g, blue: &b, alpha: &a))
        XCTAssertEqual(r, 0x0B / 255, accuracy: 0.01)
        XCTAssertEqual(g, 0x1F / 255, accuracy: 0.01)
        XCTAssertEqual(b, 0x33 / 255, accuracy: 0.01)
        // …and SwiftUI's own: the app root's tint, which an alert takes, is navy.
        let app = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("NuruMember/NuruMemberApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains(".nuruDefaultFont()\n            // The system's own chrome"))
        XCTAssertTrue(app.contains("            .tint(Nuru.navy)"))
        XCTAssertFalse(app.contains(".tint(Nuru.gold)"), "a gold root tint is what drew the answers gold")
        // Gold stays where a selected state asks for it: every switch sets it.
        for rel in ["Features/Profile/SettingsView.swift", "Features/Give/GivingView.swift", "Features/Profile/ProfileView.swift"] {
            let text = try source(rel)
            let toggles = text.components(separatedBy: "Toggle(").count - 1
            XCTAssertGreaterThan(toggles, 0, rel)
            XCTAssertGreaterThanOrEqual(text.components(separatedBy: ".tint(Nuru.gold)").count - 1, toggles, "\(rel): a switch's on state is gold")
        }
    }

    // MARK: M6 — "today" means today

    func testTodaysPartsAreOnlyThoseDoneToday() {
        // Cara's day: the Word read on Mon 5 Oct, nothing since — the walk's
        // "Today: 1 of 3 parts" under "0-day streak".
        let monday = "2026-10-05T07:10:00Z"
        let day = [segment("w", kind: "scripture", done: true, at: monday, sort: 1),
                   segment("p", kind: "prayer", done: false, sort: 2),
                   segment("t", kind: "talk", done: false, sort: 3)]
        XCTAssertNil(PlanDayParts.todayLine(day, now: wednesday, doneToday: { _ in false }),
                     "a part done on Monday is not today's")
        // The same part finished today: it counts.
        let today = [segment("w", kind: "scripture", done: true, at: "2026-10-07T06:00:00Z", sort: 1),
                     segment("p", kind: "prayer", done: false, sort: 2),
                     segment("t", kind: "talk", done: false, sort: 3)]
        XCTAssertEqual(PlanDayParts.todayLine(today, now: wednesday, doneToday: { _ in false }), "Today: 1 of 3 parts")
        // A server without `completed_at`: only this phone's note says today.
        let undated = [segment("w", kind: "scripture", done: true, sort: 1),
                       segment("p", kind: "prayer", done: false, sort: 2),
                       segment("t", kind: "talk", done: false, sort: 3)]
        XCTAssertNil(PlanDayParts.todayLine(undated, now: wednesday, doneToday: { _ in false }))
        XCTAssertEqual(PlanDayParts.todayLine(undated, now: wednesday, doneToday: { $0 == "w" }), "Today: 1 of 3 parts")
        // A day finished is the tick, not a count.
        let all = day.map { segment($0.segmentId, kind: $0.kind, done: true, at: "2026-10-07T06:00:00Z", sort: $0.sort) }
        XCTAssertNil(PlanDayParts.todayLine(all, now: wednesday, doneToday: { _ in true }))
        // Nairobi's day, not UTC's: 23:30 UTC on the 6th is already the 7th there.
        let lateUTC = [segment("w", kind: "scripture", done: true, at: "2026-10-06T22:30:00Z", sort: 1),
                       segment("p", kind: "prayer", done: false, sort: 2)]
        XCTAssertEqual(PlanDayParts.todayLine(lateUTC, now: wednesday, doneToday: { _ in false }), "Today: 1 of 2 parts")
    }

    func testAPlanDayNeverClaimsToday() {
        // Day 4 of a plan paused since Monday read "TODAY'S JOURNEY · 3 PARTS".
        XCTAssertEqual(PlanDayWords.hubKicker(parts: 3), "THIS DAY · 3 PARTS")
        XCTAssertEqual(PlanDayWords.hubKicker(parts: 1), "THIS DAY · 1 PART")
        XCTAssertEqual(PlanDayWords.readingKicker, "THE READING")
        XCTAssertEqual(PlanDayWords.questionKicker(1), "THE QUESTION")
        XCTAssertEqual(PlanDayWords.questionKicker(2), "THE QUESTIONS")
        for w in [PlanDayWords.hubKicker(parts: 3), PlanDayWords.readingKicker, PlanDayWords.questionKicker(2)] {
            XCTAssertFalse(w.contains("TODAY"), w)
        }
    }

    func testThisPhoneKeepsOnlyTodaysParts() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FinalFixesTests.parts"))
        defaults.removePersistentDomain(forName: "FinalFixesTests.parts")
        let tuesday = wednesday.addingTimeInterval(-86_400)
        PlanPartLog.noteDone("old", now: tuesday, in: defaults)
        XCTAssertTrue(PlanPartLog.doneToday("old", now: tuesday, in: defaults))
        XCTAssertFalse(PlanPartLog.doneToday("old", now: wednesday, in: defaults), "yesterday's part is not today's")
        PlanPartLog.noteDone("new", now: wednesday, in: defaults)
        XCTAssertTrue(PlanPartLog.doneToday("new", now: wednesday, in: defaults))
        XCTAssertNil((defaults.dictionary(forKey: PlanPartLog.key) as? [String: Int])?["old"], "yesterday's falls away")
        PlanPartLog.forget(in: defaults)
        XCTAssertFalse(PlanPartLog.doneToday("new", now: wednesday, in: defaults))
        defaults.removePersistentDomain(forName: "FinalFixesTests.parts")
    }

    // MARK: M7 — nothing animates behind a covered Home

    func testHomeMovesOnlyWhileItIsSeen() {
        XCTAssertTrue(HomeMotion.onScreen(selected: true, atRoot: true, active: true, covered: false))
        XCTAssertFalse(HomeMotion.onScreen(selected: false, atRoot: true, active: true, covered: false), "another tab")
        XCTAssertFalse(HomeMotion.onScreen(selected: true, atRoot: false, active: true, covered: false), "a page pushed over Home")
        XCTAssertFalse(HomeMotion.onScreen(selected: true, atRoot: true, active: false, covered: false), "the app in the background")
        XCTAssertFalse(HomeMotion.onScreen(selected: true, atRoot: true, active: true, covered: true), "a full-screen cover")
        XCTAssertTrue(HomeMotion.turns(onScreen: true, pages: 2))
        XCTAssertFalse(HomeMotion.turns(onScreen: true, pages: 1), "one page never turns")
        XCTAssertFalse(HomeMotion.turns(onScreen: false, pages: 3))
        XCTAssertTrue(NuruPulse.runs(visible: true, reduceMotion: false))
        XCTAssertFalse(NuruPulse.runs(visible: false, reduceMotion: false))
        XCTAssertFalse(NuruPulse.runs(visible: true, reduceMotion: true))
    }

    func testNoTimerOrLoopOnHomeRunsUnguarded() throws {
        let home = try source("Features/Home/HomeView.swift")
        XCTAssertFalse(home.contains("Timer.publish"), "the carousel turns in a task keyed by onScreen")
        XCTAssertEqual(home.components(separatedBy: ".task(id: onScreen) {\n            guard onScreen else { return }").count - 1, 2,
                       "the on-air and live polls stop while Home is covered")
        XCTAssertTrue(home.contains(".environment(\\.screenVisible, onScreen)"))
        for file in ["Features/Home/HomeCards.swift", "Features/Home/HomeView.swift"] {
            let text = try source(file)
            XCTAssertFalse(text.contains("withAnimation(.easeInOut(duration: 1.2).repeatForever")
                           || text.contains(") { pulse = true }") || text.contains(") { expand = true }"),
                           "\(file): a pulse runs through nuruPulse, which stops when Home is covered")
        }
    }

    // MARK: M8 — one story about who sees a shared prayer, one name for the step

    func testTheShareStepHasOneNameAndOneAudience() throws {
        XCTAssertEqual(PrayerWallWords.emptyLine,
                       "Be the first to share a prayer. Everyone in your congregation will see it and can pray with you.")
        XCTAssertFalse(PrayerWallWords.emptyLine.contains("family"))
        XCTAssertFalse(PrayerWallWords.posted.contains("cell"))
        let journal = try source("Features/Grow/PrayerJournalView.swift")
        XCTAssertTrue(journal.contains("Label(\"Share to Corporate\", systemImage: \"megaphone\")"))
        XCTAssertTrue(journal.contains("\"Share to Corporate?\","))
        XCTAssertTrue(journal.contains("Button(\"Share\") {"))
        XCTAssertTrue(journal.contains("Button(\"Keep it private\", role: .cancel)"))
        XCTAssertTrue(journal.contains("Text(\"Everyone in your congregation will see this and can pray with you.\")"))
        for stale in ["Publish to Corporate", "Share to the prayer wall?", "Share to wall", "standing with you 🙏"] {
            XCTAssertFalse(journal.contains(stale), stale)
        }
    }

    // MARK: C1 — the unread letter's nudge never repeats its card

    func testTheLetterNudgeNeverRepeatsTheLetterCard() throws {
        let n = try nudge("letter_unread", route: "letter", ["letterId": "L-4"])
        XCTAssertTrue(HomeWeek.repeats(n, in: [], letterOnHome: "L-4"), "the card above says it")
        XCTAssertTrue(HomeWeek.repeats(try nudge("letter_unread", route: "letter"), in: [], letterOnHome: "L-4"),
                      "no id named: the card's letter")
        XCTAssertTrue(HomeWeek.repeats(try nudge("letter_unread", route: "", ["letter_id": "L-4"]), in: [], letterOnHome: "L-4"),
                      "by kind when the route is absent")
        XCTAssertFalse(HomeWeek.repeats(n, in: [], letterOnHome: nil), "no letter on Home: the nudge is the way to it")
        XCTAssertFalse(HomeWeek.repeats(n, in: [], letterOnHome: "L-3"), "an older letter still sealed is its own ask")
        // Other nudges keep their rule.
        XCTAssertFalse(HomeWeek.repeats(try nudge("reflection_due", route: "devotional"), in: [], letterOnHome: "L-4"))
    }

    // MARK: C2 — rule 8 dates

    func testDatesTakeTheOneShape() throws {
        XCTAssertEqual(PauseCopy.dayLabel("2026-10-12", now: wednesday), "Mon 12 Oct", "no current year")
        XCTAssertEqual(PauseCopy.dayLabel("2027-01-05", now: wednesday), "Tue 5 Jan 2027", "another year says which")
        XCTAssertEqual(PledgeMath.dayLabel("2026-09-27", today: "2026-10-07"), "Sun 27 Sep", "not \"27 September\"")
        XCTAssertEqual(PledgeMath.dayLabel("2026-09-30", today: "2026-10-07"), "Wed 30 Sep")
        XCTAssertEqual(PledgePace.shortDay("2026-12-31", today: "2026-10-07"), "Thu 31 Dec", "as the card's \"by Thu 31 Dec\"")
        XCTAssertEqual(WalkEvent.dateLine("2026-10-05T07:08:00Z", now: wednesday, timeZone: nairobi), "Mon 5 Oct",
                       "Your Walk: not \"5 Oct 2026\"")
        XCTAssertEqual(WalkEvent.dateLine("2025-12-31T07:08:00Z", now: wednesday, timeZone: nairobi), "Wed 31 Dec 2025")
        XCTAssertEqual(WalkEvent.dateLine("2026-10-05 09:12:44.123+03", now: wednesday), "Mon 5 Oct", "a Postgres stamp")
        XCTAssertEqual(ScheduleRhythm.nothingTodayLine(firstPromptISO: "2026-10-12T06:00:00Z", now: wednesday),
                       "Nothing is taken today — the first prompt comes on Mon 12 Oct.")
        XCTAssertEqual(ScheduleRhythm.setUpLine(frequency: "weekly", firstPromptISO: "2026-10-11T06:00:00Z", now: wednesday),
                       "Your weekly gift is set up — the first prompt comes on Sun 11 Oct.")
        XCTAssertEqual(PauseCopy.line(for: try gift("s", status: "paused", pauseReason: "member", resumeOn: "2026-10-12"),
                                      now: wednesday), "Paused until Mon 12 Oct")
    }

    func testAnEventsChipCarriesItsMonthOutsideThisMonth() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = nairobi
        XCTAssertEqual(Ev.otherMonthLabel("2026-11-15T06:00:00.000Z", now: wednesday, calendar: cal), "NOV",
                       "the walk's \"SUN 15\" under \"OCTOBER 2026\"")
        XCTAssertNil(Ev.otherMonthLabel("2026-10-25T06:00:00.000Z", now: wednesday, calendar: cal))
        XCTAssertEqual(Ev.otherMonthLabel("2027-01-03T06:00:00.000Z", now: wednesday, calendar: cal), "JAN")
    }

    // MARK: C3 — rule 9 at the sizes members can choose

    func testWordsBreakOnlyWhereAReaderWould() {
        XCTAssertEqual(NuruText.emailBreaks("student1@dev.local"), "student1@\u{200B}dev.\u{200B}local",
                       "only after \"@\" and \".\"")
        XCTAssertEqual(NuruText.emailBreaks("ada"), "ada")
        XCTAssertEqual(NuruText.keepHyphens("M-Pesa"), "M\u{2011}Pesa")
        XCTAssertEqual(NuruText.badgeLines("Seven-Day Faithful"), "Seven\u{2011}Day\nFaithful",
                       "never \"Seven- / Day Faithful\"")
        XCTAssertEqual(NuruText.badgeLines("Thirty-Day Faithful"), "Thirty\u{2011}Day\nFaithful")
        XCTAssertEqual(NuruText.badgeLines("First Steps"), "First Steps", "a short name keeps one line")
        XCTAssertEqual(NuruText.badgeLines("Faithful"), "Faithful")
        XCTAssertEqual(NuruText.badgeLines("Word Keeper of the Month"), "Word Keeper\nof the Month", "split nearest the middle")
    }

    func testTheYouSwitchAlwaysFitsItsFourSegments() throws {
        let bar = try source("Features/Shell/CapsuleSegmentBar.swift")
        XCTAssertTrue(bar.contains("ViewThatFits(in: .horizontal) {\n            row(.full)\n            row(.words)\n            row(.chosenWords)"))
        XCTAssertFalse(bar.contains("ScrollView(.horizontal"), "a row that scrolls cut \"unity\" and \"Prof\"")
    }

    // MARK: C4 — Community

    func testCommunitySaysItsRoomsPlainly() {
        XCTAssertEqual(ChatConversation.shownTitle("Dev Cell A cell"), "Dev Cell A", "the doubled word goes")
        XCTAssertEqual(ChatConversation.shownTitle("Kilimani Cell cell"), "Kilimani Cell")
        XCTAssertEqual(ChatConversation.shownTitle("Hope cell"), "Hope cell", "a name without it keeps it")
        XCTAssertEqual(ChatConversation.shownTitle("Cellists"), "Cellists")
        XCTAssertFalse(SpaceWords.none(canFollow: false).contains("below"), "nothing below to follow")
        XCTAssertTrue(SpaceWords.none(canFollow: true).contains("follow one below"))
        XCTAssertEqual(CellRhythmWords.noneSet, "No gathering set yet")
    }

    // MARK: C6 — Map view

    func testMapViewCountsTheRealRoad() throws {
        XCTAssertEqual(LevelsMapWords.pathwayKicker(levels: 6), "SIX-LEVEL PATHWAY")
        XCTAssertEqual(LevelsMapWords.pathwayKicker(levels: 7), "SEVEN-LEVEL PATHWAY")
        XCTAssertEqual(LevelsMapWords.pathwayKicker(levels: 12), "12-LEVEL PATHWAY")
        let map = try source("Features/Pathway/PathwayView.swift")
        XCTAssertFalse(map.contains("PWStatCard(label: \"Offline\", value: \"Ready\")"))
    }

    // MARK: C8 — Pathway tells one truth

    func testTheLevelPageNamesTheExamAndAFirstDayStarts() throws {
        XCTAssertEqual(LevelProgressWords.line(completed: 10, total: 10, levelNumber: 1, pct: 91),
                       "10 of 10 modules · the Level 1 exam is next", "the missing 9% said")
        XCTAssertEqual(LevelProgressWords.line(completed: 10, total: 10, levelNumber: 1, pct: 100), "10 of 10 modules")
        XCTAssertEqual(LevelProgressWords.line(completed: 3, total: 10, levelNumber: 1, pct: 27), "3 of 10 modules")
        let nothing = try decode([LevelModule].self, [moduleJSON("m1", seq: 1, "next"), moduleJSON("m2", seq: 2, "locked")])
        XCTAssertEqual(PathwayTrail.resumeVerb(nothing), "Start", "Ben's first day: never \"Continue\"")
        let begun = try decode([LevelModule].self, [moduleJSON("m1", seq: 1, "completed", completed: true),
                                                    moduleJSON("m2", seq: 2, "next")])
        XCTAssertEqual(PathwayTrail.resumeVerb(begun), "Continue")
        let opened = try decode([LevelModule].self, [moduleJSON("m1", seq: 1, "next", progress: 40)])
        XCTAssertEqual(PathwayTrail.resumeVerb(opened), "Continue", "a lesson opened part-way")
        let hub = try source("Features/Pathway/PathwayView.swift")
        XCTAssertTrue(hub.contains("private var activePct: Int { active.map { Journey.levelPercent($0, journey: journey) } ?? 0 }"),
                      "the hub's bar is the level page's and Map's measure")
    }

    private func moduleJSON(_ id: String, seq: Int, _ status: String, completed: Bool = false,
                            progress: Int = 0, kind: String = "none") -> [String: Any] {
        ["module_id": id, "level_number": 1, "module_sequence_number": seq, "title": "Module \(id)",
         "summary": NSNull(), "estimated_minutes": 10, "evaluation_kind": kind, "quiz_pass_mark": 70,
         "completed": completed, "status": status, "progress": completed ? 100 : progress, "locked": status == "locked"]
    }

    // MARK: C11 — Give and Partners

    func testPausedSaysWhetherAndWhenItResumes() throws {
        XCTAssertEqual(PauseCopy.cardLine(for: try gift("s", status: "paused", pauseReason: "failures"), now: wednesday),
                       "Nothing is owed — it won't prompt again until you resume it")
        XCTAssertEqual(PauseCopy.cardLine(for: try gift("s", status: "paused", pauseReason: "member"), now: wednesday),
                       "Nothing is owed — it won't prompt again until you resume it")
        XCTAssertEqual(PauseCopy.cardLine(for: try gift("s", status: "paused", pauseReason: "member", resumeOn: "2026-10-12"),
                                          now: wednesday), "Resumes Mon 12 Oct")
        XCTAssertEqual(PauseCopy.cardLine(for: try gift("s", status: "paused", pauseReason: "pledge"), now: wednesday),
                       "Resumes when you resume its pledge")
    }

    func testNothingPaidIsNeverGreen() {
        XCTAssertFalse(PaidTint.isGreen(0), "\"PAID · KSh 0\" is a plain figure")
        XCTAssertTrue(PaidTint.isGreen(1))
    }

    // MARK: C12 — supporting screens

    func testHideHisWordCountsTheChurchsWeek() {
        // Wed 7 Oct: the fourth day of a week that starts on Sunday — it read "Day 3 of 7".
        XCTAssertEqual(MemoryWeek.day(wednesday, timeZone: nairobi), 4)
        let sunday = ISO8601DateFormatter().date(from: "2026-10-04T09:00:00Z")!
        XCTAssertEqual(MemoryWeek.day(sunday, timeZone: nairobi), 1)
        let saturday = ISO8601DateFormatter().date(from: "2026-10-10T09:00:00Z")!
        XCTAssertEqual(MemoryWeek.day(saturday, timeZone: nairobi), 7)
        // Nairobi's day: 22:30 UTC Saturday is already Sunday there.
        let lateSaturday = ISO8601DateFormatter().date(from: "2026-10-10T22:30:00Z")!
        XCTAssertEqual(MemoryWeek.day(lateSaturday, timeZone: nairobi), 1)
    }

    func testTheCorporateWallIsWarmAndPlain() throws {
        let wall = try source("Features/Community/PrayerWallView.swift")
        XCTAssertFalse(wall.contains("Nuru.coolPaper.ignoresSafeArea()"), "warm paper, not the portal's #F7F9FC")
        XCTAssertFalse(wall.contains("Text(\"🙏\")"), "no emoji (rule 7)")
        XCTAssertTrue(wall.contains("NuruStateView(state: .empty(title: PrayerWallWords.emptyTitle"), "the one state card")
    }

    // MARK: The owner's decisions, 2026-10-08 (EXPERIENCE.md §9.7)

    /// The body of the declaration that starts at `declaration` — brace-matched,
    /// with strings and comments blanked so a bracket in words never counts.
    private func declarationBody(_ declaration: String, in src: String) throws -> String {
        guard let r = src.range(of: declaration) else {
            XCTFail("not found: \(declaration)")
            return ""
        }
        let raw = Array(src.utf8)
        let s = TintScan.strip(raw)
        var i = src.utf8.distance(from: src.startIndex, to: r.upperBound)
        while i < s.count && s[i] != UInt8(ascii: "{") { i += 1 }
        let e = TintScan.matchClose(s, i, UInt8(ascii: "{"), UInt8(ascii: "}"))
        guard e > i else { XCTFail("no body: \(declaration)"); return "" }
        return String(decoding: raw[i...e], as: UTF8.self)
    }

    /// D2: navy is the church's voice and each tab's next step — "Check in to a
    /// service", "Quick help from Nuru" and Home's "Support God's work" are
    /// paper cards with the §8.1 gold-tint tile, not navy fields.
    func testOnlyTheChurchsVoiceAndTheNextStepAreNavy() throws {
        let navyFields = ["colors: [Nuru.navy", "colors: [HomeFig.navy", ".background(Nuru.navy", "Nuru.navyCard", "Nuru.navyGradient"]
        let cards: [(String, String, String)] = [
            ("Features/Events/EventsView.swift", "private var attendanceLink: some View", ".background(Nuru.white"),
            ("Features/Chat/ChatView.swift", "private var aiCard: some View", ".background(Nuru.white"),
            ("Features/Home/HomeCards.swift", "struct HomeGiveCard: View", "Nuru.priorityBg"),
        ]
        for (rel, decl, paper) in cards {
            let body = try declarationBody(decl, in: try source(rel))
            for navy in navyFields { XCTAssertFalse(body.contains(navy), "\(decl): \(navy)") }
            XCTAssertTrue(body.contains(paper), "\(decl) is a paper card")
            XCTAssertTrue(body.contains("Nuru.tileTint") || body.contains("Nuru.goldChipBg"), "\(decl): the gold-tint tile")
        }
        // Home sets the quiet divider only between dark edges: the give card is light now.
        XCTAssertEqual(HomeQuietDivider.edges(of: "give").top, .light)
        XCTAssertEqual(HomeQuietDivider.edges(of: "give").bottom, .light)
        XCTAssertEqual(HomeQuietDivider.edges(of: "letter").top, .dark, "the church's voice stays navy")
    }

    /// D1: the tier's words are the server's ("will carry …" until money lands,
    /// then "carries …"); the app adds none that could contradict them.
    func testTheTierSpeaksOnlyInTheServersWords() throws {
        for rel in ["Features/Give/PartnersView.swift", "Features/Give/PartnersStatementView.swift",
                    "Features/Give/PartnerInviteSheet.swift", "Features/Give/NewPledgeFlow.swift"] {
            let words = literals(try source(rel)).map { $0.lowercased() }
            XCTAssertEqual(words.filter { $0.contains("carries") || $0.contains("will carry") }, [],
                           "\(rel) writes its own tier words")
        }
        XCTAssertEqual(PartnerTierWords.towardKicker, "TOWARD A DISCIPLE")
        XCTAssertEqual(PartnerTierWords.towardCaption, "through a level")
    }

    /// D3: Events' strip rolls from today and never calls itself a week.
    func testEventsStripNeverCallsItselfAWeek() throws {
        XCTAssertEqual(EventsWords.stripCount(2), "2 in the next 7 days", "Android's eventsSoonPill, word for word")
        XCTAssertEqual(EventsWeek.days, 8, "today and the seven days after")
        XCTAssertEqual(EventsWords.nothingPlanned, "Nothing planned yet")
        for words in [EventsWords.stripCount(3), EventsWords.nothingPlanned, EventsWords.quiet] {
            XCTAssertFalse(words.lowercased().contains("week"), words)
        }
        // No string on the tab says "week" (the series' cadence parser reads the bare token;
        // "weekday" and EventsWeek are code inside an interpolation).
        let events = literals(try source("Features/Events/EventsView.swift"))
        XCTAssertEqual(events.filter { $0 != "\"week\"" && $0.range(of: "\\bweek\\b", options: [.regularExpression, .caseInsensitive]) != nil }, [])
    }

    /// The string literals a source writes — comments left out (a comment may
    /// quote the words it replaced).
    private func literals(_ src: String) -> [String] {
        let raw = Array(src.utf8), s = TintScan.strip(raw)
        let quote = UInt8(ascii: "\""), newline = UInt8(ascii: "\n")
        var out: [String] = [], i = 0
        while i < s.count {
            if s[i] == quote {
                var j = i + 1
                while j < s.count && s[j] != quote && s[j] != newline { j += 1 }
                if j < s.count && s[j] == quote {
                    out.append(String(decoding: raw[i...j], as: UTF8.self))
                    i = j + 1
                    continue
                }
            }
            i += 1
        }
        return out
    }

    // MARK: M5's side effect — a text action is gold, never the tint's navy

    /// §8.1 rule 4: a text action is gold text; navy is for chrome. Since M5 the
    /// root tint is navy (menus, toolbars, the caret), so a text action left to
    /// the tint reads navy. Every one colours its own words (TintScan).
    func testNoTextActionReliesOnTheTint() throws {
        var found: [TintScan.Finding] = []
        let root = TypeScan.appRoot
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        XCTAssertGreaterThan(files.count, 100, "the scan reads the app")
        for url in files {
            let rel = String(url.path.dropFirst(root.path.count + 1))
            found += TintScan.findings(file: rel, source: try String(contentsOf: url, encoding: .utf8))
        }
        XCTAssertEqual(found.map(\.description), [], "text actions left to the navy tint")
    }

    /// The scan itself: what it flags, and what it lets be.
    func testTheTintScanFlagsAWordLeftToTheTint() {
        func flags(_ code: String) -> Int { TintScan.findings(file: "Probe.swift", source: code).count }
        XCTAssertEqual(flags("Button(\"See all\") { go() }"), 1, "a string title takes the tint")
        XCTAssertEqual(flags("Button { go() } label: { Text(\"Try again\").font(.inter(12)) }"), 1)
        XCTAssertEqual(flags("NavigationLink(value: r) { Text(\"View calendar\") }"), 1)
        XCTAssertEqual(flags("ShareLink(item: url)"), 1, "the system's Share label")
        XCTAssertEqual(flags("Button { go() } label: { Text(\"Try again\").foregroundStyle(Nuru.gold) }"), 0)
        XCTAssertEqual(flags("Button(\"See all\") { go() }.foregroundStyle(Nuru.gold)"), 0)
        XCTAssertEqual(flags("Button { go() } label: { HStack { Text(\"Give now\") }.foregroundStyle(Nuru.gold) }"), 0)
        XCTAssertEqual(flags("Button { go() } label: { Text(\"Card\") }.buttonStyle(.pressable)"), 0, "a style that draws its own label")
        XCTAssertEqual(flags("Button { go() } label: { Text(\"Card\") }.buttonStyle(.borderless)"), 1, "a tinting style is no style")
        XCTAssertEqual(flags(".alert(\"Leave?\", isPresented: $b) { Button(\"Stay\") { } }"), 0, "an alert's answers are chrome")
        XCTAssertEqual(flags("Menu { Button(\"Copy\") { } } label: { Icon(.more, size: 18, color: Nuru.navy) }"), 0)
        XCTAssertEqual(flags(".toolbar { ToolbarItem { Button(\"Done\") { } } }"), 0)
        XCTAssertEqual(flags("Button { go() } label: { Text(\"🙏\").font(.emoji(18)) }"), 0, "an emoji draws itself")
    }

    /// A link run inside text is a text action too: wherever a link run is
    /// made, that view sets its tint (ScripturePassages, ChatThread, lessons).
    func testALinkRunWearsItsOwnTint() throws {
        let root = TypeScan.appRoot
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        var makers: [String] = []
        for url in files {
            let src = try String(contentsOf: url, encoding: .utf8)
            guard src.contains("].link = ") || src.contains("AttributedString(markdown:") else { continue }
            makers.append(url.lastPathComponent)
            XCTAssertTrue(src.contains(".tint("), "\(url.lastPathComponent) makes link runs without a tint")
        }
        XCTAssertGreaterThanOrEqual(makers.count, 3, "the scan finds the link makers: \(makers)")
    }

    // MARK: Map view — completed levels only (Eli reads the same on both apps)

    @MainActor
    func testMapViewCountsOnlyCompletedLevels() throws {
        func level(_ n: Int, _ status: String, done: Int = 0, of total: Int = 0, awaiting: Bool = false) -> [String: Any] {
            ["level_number": n, "title": "Level \(n)", "theme": NSNull(), "description": NSNull(),
             "total_modules": total, "completed_modules": done, "lessons_total": total, "lessons_completed": done,
             "minutes": 0, "status": status, "awaiting_review": awaiting, "exam_published": true, "exam_available": true]
        }
        let vm = PathwayViewModel()
        // Eli: the exam passed, the leader still to usher — not complete yet.
        vm.summary = try decode(PathwaySummary.self, ["current_level": 1, "levels": [
            level(1, "active", done: 10, of: 10, awaiting: true), level(2, "locked"), level(3, "locked")]])
        XCTAssertEqual(vm.levelsDone, 0, "a passed exam awaiting the leader isn't a completed level")
        vm.summary = try decode(PathwaySummary.self, ["current_level": 2, "levels": [
            level(1, "completed", done: 10, of: 10), level(2, "active"), level(3, "locked")]])
        XCTAssertEqual(vm.levelsDone, 1)
        let map = try source("Features/Pathway/PathwayView.swift")
        XCTAssertTrue(map.contains("var levelsDone: Int { summary?.levels.filter { $0.status == .completed }.count ?? 0 }"))
    }

    // MARK: M4's class — nothing guessed while a read is in flight

    private func eliPathway(awaiting: Bool = false) throws -> PathwaySummary {
        try decode(PathwaySummary.self, ["current_level": 1, "levels": [
            ["level_number": 1, "title": "Foundations", "theme": NSNull(), "description": NSNull(),
             "total_modules": 11, "completed_modules": awaiting ? 11 : 10, "lessons_total": 10, "lessons_completed": 10,
             "minutes": 0, "status": "active", "awaiting_review": awaiting, "exam_published": true, "exam_available": true],
            ["level_number": 2, "title": "Level 2", "theme": NSNull(), "description": NSNull(),
             "total_modules": 0, "completed_modules": 0, "minutes": 0, "status": "locked",
             "awaiting_review": false, "exam_published": false, "exam_available": false]]])
    }

    private func eliTrail(examPassed: Bool = false) throws -> [LevelModule] {
        var rows = (1...10).map { moduleJSON("m\($0)", seq: $0, "completed", completed: true) }
        rows.append(moduleJSON("exam", seq: 11, examPassed ? "completed" : "next", completed: examPassed, kind: "exit_exam"))
        return try decode([LevelModule].self, rows)
    }

    /// Pathway's hero: the summary and its trail land together. Android found
    /// "CONTINUE · Level 1 · Continue" for two seconds before "EXAM READY".
    @MainActor
    func testPathwayTellsNoStepUntilItsTrailAnswers() async throws {
        let vm = PathwayViewModel()
        let first = try eliPathway(), trail = try eliTrail()
        await vm.load(pathway: { first }, trail: { _ in
            // In flight: the page holds its skeleton — nothing is told.
            XCTAssertTrue(vm.loading)
            XCTAssertNil(vm.summary, "no summary on screen without its trail")
            XCTAssertNil(vm.journey)
            return trail
        })
        XCTAssertFalse(vm.loading)
        XCTAssertEqual(vm.journey?.stage, .examReady)
        XCTAssertEqual(vm.journey?.pill, "Exam ready")

        // A refresh keeps the last pair on screen until the new pair is in.
        let passed = try eliPathway(awaiting: true), passedTrail = try eliTrail(examPassed: true)
        await vm.load(pathway: { passed }, trail: { _ in
            XCTAssertEqual(vm.journey?.stage, .examReady, "the last pair, whole — never the new summary beside the old trail")
            XCTAssertEqual(vm.summary?.levels.first?.isAwaitingReview, false)
            return passedTrail
        })
        XCTAssertEqual(vm.journey?.stage, .awaitingUsher)
        XCTAssertEqual(vm.journey?.pill, "Exam passed")

        // A trail that fails reads as none: the journey speaks from the summary.
        struct Down: Error {}
        let again = PathwayViewModel()
        await again.load(pathway: { first }, trail: { _ in throw Down() })
        XCTAssertEqual(again.modulesByLevel[1]?.isEmpty, true)
        XCTAssertEqual(again.journey?.stage, .examReady, "the summary alone, once the trail has answered")
    }

    /// Home: the journey is derived once, from this load's summary AND trail;
    /// YOUR WEEK, the pill, the needs rail and the encouragement hold their
    /// loading shapes until the first load has answered.
    @MainActor
    func testHomeHoldsItsLoadingShapesUntilItsReadsAnswer() throws {
        XCTAssertFalse(HomeViewModel().loadedOnce, "nothing has answered before the first load")
        let home = try source("Features/Home/HomeView.swift")
        XCTAssertEqual(home.components(separatedBy: "self.journey = Journey.derive(").count - 1, 1,
                       "one derivation — never from the summary alone")
        try assertLandsAfterEveryRead("Features/Home/HomeView.swift", anchor: "func load(quiet: Bool = false) async {",
                                      ["journey", "loadedOnce"])
        XCTAssertTrue(home.contains("vm.loadedOnce ? AnyView(HomeWeekCard(rows: week) { openWeek($0) })\n                                        : AnyView(HomeWeekSkeleton())"))
        XCTAssertTrue(home.contains("} else if !vm.loadedOnce {"), "the pill's loading shape")
        XCTAssertTrue(home.contains("HomePillSkeleton()"))
        XCTAssertTrue(home.contains("if vm.loadedOnce { s.append((\"encourage\""))
    }

    /// Every other tab: its reads all answer before any of them shows — a list
    /// never paints with a neighbour's read still in flight (an RSVP shown as
    /// "RSVP", "No badges yet", "A discipler has not yet been assigned").
    func testEachTabsReadsLandTogether() throws {
        try assertLandsAfterEveryRead("Features/Events/EventsView.swift", anchor: "async let rs = try? MemberAPI.myRsvps()",
                                      ["occurrences", "series", "announcements", "quickRsvps", "segment"])
        try assertLandsAfterEveryRead("Features/Give/GivingView.swift", anchor: "async let t = MemberAPI.givingStatements(year: year)",
                                      ["history", "schedules", "methods", "serverYearTotals", "pledgeShapes", "loadFailure"])
        try assertLandsAfterEveryRead("Features/Give/PartnersView.swift", anchor: "async let gifts = try? MemberAPI.schedules()",
                                      ["partnership", "schedules"])
        try assertLandsAfterEveryRead("Features/Grow/ReadingPlansView.swift", anchor: "async let promoList = try? MemberAPI.planPromos()",
                                      ["plans", "todaySealed", "todayLine", "streak", "activeToday", "promos"])
        try assertLandsAfterEveryRead("Features/Pathway/LevelDetailView.swift", anchor: "async let ach = try? MemberAPI.achievements()",
                                      ["level", "journey", "modules", "encouragements", "mentor", "levelScore", "streak"])
        try assertLandsAfterEveryRead("Features/Chat/ChatView.swift", anchor: "async let discipleshipReq",
                                      ["inbox", "people", "connections", "incomingRequests", "outgoingRequests", "discipleship", "isPastor"])
        try assertLandsAfterEveryRead("Features/Profile/ProfileView.swift", anchor: "async let pathway = try? await MemberAPI.pathway()",
                                      ["badges", "certs", "scores", "serving", "journey", "extrasAnswered"])
        let profile = try source("Features/Profile/ProfileView.swift")
        XCTAssertTrue(profile.contains("journey = Journey.derive(summary, trail: trail)"), "You tells the journey with its trail")
        XCTAssertEqual(profile.components(separatedBy: "if !extrasAnswered {").count - 1, 2, "badges and certificates wait")
    }

    /// In the function holding `anchor`, every assignment to `properties`
    /// comes after the function's last `await`: the reads answer first.
    private func assertLandsAfterEveryRead(_ rel: String, anchor: String, _ properties: [String],
                                           file: StaticString = #filePath, line: UInt = #line) throws {
        let src = try source(rel)
        guard let a = src.range(of: anchor) else { return XCTFail("\(rel): \(anchor) not found", file: file, line: line) }
        let s = TintScan.strip(Array(src.utf8))
        let start = src.utf8.distance(from: src.startIndex, to: a.upperBound)
        var depth = 0, end = start
        while end < s.count {
            if s[end] == UInt8(ascii: "{") { depth += 1 }
            if s[end] == UInt8(ascii: "}") { if depth == 0 { break }; depth -= 1 }
            end += 1
        }
        let body = String(decoding: s[start..<end], as: UTF8.self)
        let ns = body as NSString
        let lastAwait = try NSRegularExpression(pattern: "\\bawait\\b").matches(in: body, range: NSRange(location: 0, length: ns.length))
            .last?.range.location ?? -1
        for p in properties {
            let rx = try NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])(?<!let )(?<!var )(?:self\\.)?\(p) = ")
            let sets = rx.matches(in: body, range: NSRange(location: 0, length: ns.length))
            XCTAssertFalse(sets.isEmpty, "\(rel): \(p) is never set here", file: file, line: line)
            for m in sets {
                XCTAssertGreaterThan(m.range.location, lastAwait,
                                     "\(rel): \(p) is shown before every read has answered", file: file, line: line)
            }
        }
    }

    // MARK: C7 — nothing touches the status band (rule 9)

    /// A page whose content runs under the status band (its scroll or its
    /// header ignores the top safe area) pads its header by the band's own
    /// height — NuruSafeArea.top + 8 — never a fixed 60, which sat 2 pt under
    /// a 62 pt band. Checked on the simulator, 2026-10-08.
    func testNoHeaderSitsUnderTheStatusBand() throws {
        for rel in ["Features/Grow/DevotionalView.swift", "Features/Departments/DepartmentDetailView.swift",
                    "Features/Live/NuruLiveTabView.swift", "Features/Give/NewPledgeFlow.swift"] {
            XCTAssertTrue(try source(rel).contains(".padding(.top, NuruSafeArea.top + 8)"), rel)
        }
        let plans = try source("Features/Grow/ReadingPlansView.swift")
        XCTAssertEqual(plans.components(separatedBy: ".padding(.top, NuruSafeArea.top + 8)   // below the status band (rule 9)").count - 1, 2,
                       "a plan's page and its day, over their photographs")
        // Every fixed top inset left in the 50–61 pt range sits BELOW the band:
        // its page keeps the top safe area, so the inset is measured from the
        // band's foot (the giving statement's header stands at 116 pt, the
        // Prayer Room's at 122 pt — seen on the simulator). A new one is
        // checked the same way and listed here.
        let belowTheBand = ["Features/Chat/ChatThreadView.swift": 1, "Features/Community/PrayerWallView.swift": 1,
                            "Features/Community/PrayerWallDetailView.swift": 1, "Features/Community/DiscussionsView.swift": 2,
                            "Features/Give/GivingStatementView.swift": 1, "Features/Grow/MemoryVerseView.swift": 1,
                            "Features/Grow/PrayerJournalView.swift": 1, "Features/Discipleship/DiscipleshipHubView.swift": 1,
                            "Features/Discipleship/DisciplerDossierView.swift": 1, "Features/Discipleship/DisciplerRosterView.swift": 1,
                            "Features/Profile/MentorView.swift": 1, "Features/Grow/VerseLibraryView.swift": 1,
                            "Features/Pathway/YourWalkView.swift": 1,
                            "Features/Give/PartnersView.swift": 1,   // the spinner under Partners' own header
                            "Features/Live/LiveChatSheet.swift": 1]  // inside a sheet, below its grabber
        let rx = try NSRegularExpression(pattern: "\\.padding\\(\\.top, (5[0-9]|6[01])\\)")
        var found: [String: Int] = [:]
        let root = TypeScan.appRoot
        for url in FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap({ $0 as? URL }).filter({ $0.pathExtension == "swift" }) ?? [] {
            let src = try String(contentsOf: url, encoding: .utf8)
            let n = rx.numberOfMatches(in: src, range: NSRange(src.startIndex..., in: src))
            if n > 0 { found[String(url.path.dropFirst(root.path.count + 1)), default: 0] += n }
        }
        XCTAssertEqual(found, belowTheBand)
    }

    // MARK: C16 — the last of the grammar

    func testAnEmptyYearIsTheStateCardNotABareLine() throws {
        XCTAssertEqual(PartnerStatementWords.noPayments(2026), "No pledge payments in 2026")
        for rel in ["Features/Give/PartnersView.swift", "Features/Give/PartnersStatementView.swift"] {
            let src = try source(rel)
            XCTAssertFalse(src.contains("Text(\"No pledge payments in"), "\(rel): a bare line")
            XCTAssertTrue(src.contains("NuruStateView(state: .empty(title: PartnerStatementWords.noPayments(s.year))"), rel)
        }
        let statement = try source("Features/Give/GivingStatementView.swift")
        XCTAssertFalse(statement.contains("Text(\"No gifts \\(periodLabel).\")"), "Give's statement: a bare line")
        XCTAssertTrue(statement.contains("NuruStateView(state: .empty(title: \"No gifts \\(periodLabel)\"))"))
    }

    func testGivesPrimarySitsBelowThePageNotOverIt() throws {
        let give = try source("Features/Give/GivingView.swift")
        XCTAssertTrue(give.contains("VStack(spacing: 0) {\n                ScrollView(showsIndicators: false) {"),
                      "the page, then its bar — the button never covers a fund card")
        XCTAssertFalse(give.contains(".padding(.bottom, Nuru.tabBarSpace + 80)"), "no room left under a floating bar")
    }

    func testEventsOffersSearchOnlyOverSomethingToSearch() {
        XCTAssertFalse(EventsViewModel.showsSearchAndFilters(segmentCount: 0, search: "", category: "All"), "an empty day")
        XCTAssertTrue(EventsViewModel.showsSearchAndFilters(segmentCount: 3, search: "", category: "All"))
        XCTAssertTrue(EventsViewModel.showsSearchAndFilters(segmentCount: 0, search: "youth", category: "All"),
                      "a search in use stays, so it can be cleared")
        XCTAssertTrue(EventsViewModel.showsSearchAndFilters(segmentCount: 0, search: "", category: "Worship"))
        XCTAssertFalse(EventsViewModel.showsSearchAndFilters(segmentCount: 0, search: "  ", category: "All"))
    }

    func testAWeeklyServiceIsOneCardWithItsDatesBeneath() throws {
        func occ(_ id: String, series: String, _ start: String) -> [String: Any] {
            ["occurrence_id": id, "series_id": series, "title": series, "start_at": start, "end_at": start, "going": 0]
        }
        let list = try decode([CalendarOccurrence].self, [
            occ("s11", series: "sunday", "2026-10-11T06:00:00Z"), occ("y14", series: "youth", "2026-10-14T15:00:00Z"),
            occ("s18", series: "sunday", "2026-10-18T06:00:00Z"), occ("s25", series: "sunday", "2026-10-25T06:00:00Z")])
        let groups = EventsGrouping.grouped(list)
        XCTAssertEqual(groups.map(\.first.occurrenceId), ["s11", "y14"], "each series once, by its first date")
        XCTAssertEqual(groups[0].more.map(\.occurrenceId), ["s18", "s25"], "the later Sundays, soonest first")
        XCTAssertEqual(groups[1].more, [])
        XCTAssertEqual(EventsGrouping.grouped([]), [])
    }
}

// MARK: - The text-action scan (§8.1 rule 4; final walk M5's side effect)

/// A text action — a Button, NavigationLink, Link, ShareLink or PhotosPicker
/// whose label is words (a string title, the system's label, or a Text or
/// Label in its label) — colours its words itself: on the action, on the
/// words, or on a container around them; or it wears a button style that
/// draws its own label. The root tint is navy since M5 (menus, toolbars, the
/// caret), so words left to the tint read navy where rule 4 says gold.
/// Chrome — alerts, dialogs, menus, toolbars, swipe actions — takes the tint
/// by design and is let be. (A label drawn by a view of its own is read
/// where that view is written, not here.)
enum TintScan {
    struct Finding: CustomStringConvertible {
        let file: String
        let line: Int
        let what: String
        var description: String { "\(file):\(line): \(what)" }
    }

    static let chrome: Set<String> = ["alert", "confirmationDialog", "Menu", "contextMenu", "toolbar",
                                      "ToolbarItem", "ToolbarItemGroup", "swipeActions"]
    static let tintingStyles = [".buttonStyle(.borderless)", ".buttonStyle(.automatic)",
                                ".buttonStyle(.bordered)", ".buttonStyle(.borderedProminent)"]
    /// Words that are chrome by the way they are shown: a context menu's
    /// items, built apart from the `.contextMenu { menu }` that shows them.
    static let chromeDeclarations: [(file: String, declaration: String)] = [
        ("Features/Chat/ChatThreadView.swift", "@ViewBuilder private var menu: some View"),
    ]

    private static let space = UInt8(ascii: " "), tab = UInt8(ascii: "\t"), newline = UInt8(ascii: "\n")
    private static let ret = UInt8(ascii: "\r"), quote = UInt8(ascii: "\""), slash = UInt8(ascii: "/")
    private static let star = UInt8(ascii: "*"), backslash = UInt8(ascii: "\\"), colon = UInt8(ascii: ":")
    private static let dot = UInt8(ascii: ".")
    static let lp = UInt8(ascii: "("), rp = UInt8(ascii: ")"), lb = UInt8(ascii: "{"), rb = UInt8(ascii: "}")

    static func isSpace(_ b: UInt8) -> Bool { b == space || b == tab || b == newline || b == ret }
    static func isIdent(_ b: UInt8) -> Bool {
        (b >= 65 && b <= 90) || (b >= 97 && b <= 122) || (b >= 48 && b <= 57) || b == 95
    }

    /// The source with every string literal's contents and every comment
    /// blanked byte for byte (a bracket in words never counts), and ASCII
    /// only, so one byte is one character.
    static func strip(_ raw: [UInt8]) -> [UInt8] {
        var out = raw
        let n = raw.count
        func at(_ i: Int, _ seq: [UInt8]) -> Bool { i + seq.count <= n && Array(raw[i..<(i + seq.count)]) == seq }
        let triple: [UInt8] = [quote, quote, quote]
        var i = 0
        while i < n {
            if at(i, triple) {
                var j = i + 3
                while j < n && !at(j, triple) { j += 1 }
                for k in (i + 3)..<min(j, n) where raw[k] != newline { out[k] = space }
                i = j + 3
                continue
            }
            if raw[i] == quote {
                var j = i + 1
                while j < n && raw[j] != quote && raw[j] != newline {
                    if raw[j] == backslash { j += 2; continue }
                    j += 1
                }
                for k in (i + 1)..<min(max(j, i + 1), n) { out[k] = space }
                i = j + 1
                continue
            }
            if raw[i] == slash && i + 1 < n && raw[i + 1] == slash {
                var j = i
                while j < n && raw[j] != newline { out[j] = space; j += 1 }
                i = j
                continue
            }
            if raw[i] == slash && i + 1 < n && raw[i + 1] == star {
                var j = i
                while j < n && !(raw[j] == star && j + 1 < n && raw[j + 1] == slash) {
                    if raw[j] != newline { out[j] = space }
                    j += 1
                }
                if j < n { out[j] = space }
                if j + 1 < n { out[j + 1] = space }
                i = j + 2
                continue
            }
            i += 1
        }
        for k in 0..<n where out[k] >= 0x80 { out[k] = space }
        return out
    }

    static func matchClose(_ s: [UInt8], _ i: Int, _ o: UInt8, _ c: UInt8) -> Int {
        var d = 0, j = i
        while j < s.count {
            if s[j] == o { d += 1 } else if s[j] == c { d -= 1; if d == 0 { return j } }
            j += 1
        }
        return -1
    }

    static func matchOpen(_ s: [UInt8], _ i: Int, _ o: UInt8, _ c: UInt8) -> Int {
        var d = 0, j = i
        while j >= 0 {
            if s[j] == c { d += 1 } else if s[j] == o { d -= 1; if d == 0 { return j } }
            j -= 1
        }
        return -1
    }

    private static func text(_ s: [UInt8], _ a: Int, _ b: Int) -> String {
        guard a < b else { return "" }
        return String(decoding: s[max(0, a)..<min(b, s.count)], as: UTF8.self)
    }

    /// The name of the call a `{` closure belongs to: `.alert(…) {` → alert,
    /// `Menu {` → Menu, a `label: {` → the call before it.
    static func ownerName(_ s: [UInt8], _ brace: Int) -> String {
        var j = brace - 1
        while j >= 0 && isSpace(s[j]) { j -= 1 }
        if j >= 0 && s[j] == colon {
            var k = j - 1
            while k >= 0 && isIdent(s[k]) { k -= 1 }
            if k < j - 1 {
                j = k
                while j >= 0 && isSpace(s[j]) { j -= 1 }
                if j >= 0 && s[j] == rb {
                    let o = matchOpen(s, j, lb, rb)
                    if o >= 0 { return ownerName(s, o) }
                }
            }
        }
        if j >= 0 && s[j] == rp {
            let o = matchOpen(s, j, lp, rp)
            j = o - 1
            while j >= 0 && isSpace(s[j]) { j -= 1 }
        }
        var k = j
        while k >= 0 && isIdent(s[k]) { k -= 1 }
        return text(s, k + 1, j + 1)
    }

    /// Where the modifier chain starting at `j` ends: ".a(…) .b { … } …".
    static func modifiersEnd(_ s: [UInt8], _ from: Int) -> Int {
        var j = from
        while true {
            var t = j
            while t < s.count && isSpace(s[t]) { t += 1 }
            guard t < s.count, s[t] == dot, t + 1 < s.count, isIdent(s[t + 1]) else { break }
            var u = t + 1
            while u < s.count && isIdent(s[u]) { u += 1 }
            if u < s.count && s[u] == lp { u = matchClose(s, u, lp, rp) + 1 }
            var v = u
            while v < s.count && (s[v] == space || s[v] == tab) { v += 1 }
            if v < s.count && s[v] == lb { u = matchClose(s, v, lb, rb) + 1 }
            guard u > t else { break }
            j = u
        }
        return j
    }

    static func ownStyle(_ mods: String) -> Bool {
        mods.contains(".buttonStyle(") && !tintingStyles.contains { mods.contains($0) }
    }
    static func colored(_ mods: String) -> Bool {
        mods.contains(".foregroundStyle(") || mods.contains(".foregroundColor(") || mods.contains(".tint(")
    }

    /// Whether a container around `pos` (out to `stop`) draws its own label or colours its words.
    static func enclosing(_ s: [UInt8], _ pos: Int, _ stop: Int) -> (styled: Bool, colored: Bool) {
        var d = 0, styled = false, col = false
        var j = pos - 1
        while j >= stop {
            if s[j] == rb { d += 1 } else if s[j] == lb {
                if d == 0 {
                    let e = matchClose(s, j, lb, rb)
                    if e > 0 {
                        let mods = text(s, e + 1, modifiersEnd(s, e + 1))
                        if ownStyle(mods) { styled = true }
                        if colored(mods) { col = true }
                    }
                } else { d -= 1 }
            }
            j -= 1
        }
        return (styled, col)
    }

    static func findings(file: String, source: String) -> [Finding] {
        let raw = Array(source.utf8)
        let s = strip(raw)
        let str = String(decoding: s, as: UTF8.self)
        let ns = str as NSString
        // Chrome by the way it is shown (a context menu built apart).
        var skip: [Range<Int>] = []
        for c in chromeDeclarations where c.file == file {
            if let r = source.range(of: c.declaration) {
                var i = source.utf8.distance(from: source.startIndex, to: r.upperBound)
                while i < s.count && s[i] != lb { i += 1 }
                let e = matchClose(s, i, lb, rb)
                if e > i { skip.append(i..<e) }
            }
        }
        guard let sites = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])(Button|NavigationLink|Link|ShareLink|PhotosPicker)\\s*[({]"),
              let words = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])(Text|Label)\\s*\\("),
              let stringFirst = try? NSRegularExpression(pattern: "^\\(\\s*\""),
              let identFirst = try? NSRegularExpression(pattern: "^\\(\\s*[A-Za-z_][A-Za-z0-9_.]*\\s*[,)]")
        else { return [] }
        var out: [Finding] = []
        for m in sites.matches(in: str, range: NSRange(location: 0, length: ns.length)) {
            let start = m.range.location
            if skip.contains(where: { $0.contains(start) }) { continue }
            let kind = ns.substring(with: m.range(at: 1))
            var j = start + kind.utf8.count
            while j < s.count && (s[j] == space || s[j] == tab) { j += 1 }
            var args = ""
            if j < s.count && s[j] == lp {
                let e = matchClose(s, j, lp, rp)
                guard e > j else { continue }
                args = text(s, j, e + 1)
                j = e + 1
            }
            // Its closures: `{ … }` and `label: { … }`, in order.
            var closures: [(name: String, open: Int, close: Int)] = []
            while true {
                var t = j
                while t < s.count && isSpace(s[t]) { t += 1 }
                if t < s.count && s[t] == lb {
                    let e = matchClose(s, t, lb, rb)
                    guard e > t else { break }
                    closures.append(("", t, e)); j = e + 1
                    continue
                }
                var u = t
                while u < s.count && isIdent(s[u]) { u += 1 }
                if u > t, u < s.count, s[u] == colon {
                    var v = u + 1
                    while v < s.count && isSpace(s[v]) { v += 1 }
                    if v < s.count && s[v] == lb {
                        let e = matchClose(s, v, lb, rb)
                        guard e > v else { break }
                        closures.append((text(s, t, u), v, e)); j = e + 1
                        continue
                    }
                }
                break
            }
            let mods = text(s, j, modifiersEnd(s, j))
            // Chrome, by its owners.
            var owners: [String] = []
            var d = 0, q = start - 1
            while q >= 0 {
                if s[q] == rb { d += 1 } else if s[q] == lb { if d == 0 { owners.append(ownerName(s, q)) } else { d -= 1 } }
                q -= 1
            }
            if owners.contains(where: { chrome.contains($0) }) { continue }
            if ownStyle(mods) || colored(mods) { continue }
            let around = enclosing(s, start, 0)
            if around.styled { continue }

            let argRange = NSRange(location: 0, length: (args as NSString).length)
            var stringLabel = stringFirst.firstMatch(in: args, range: argRange) != nil
            if kind == "Button", identFirst.firstMatch(in: args, range: argRange) != nil { stringLabel = true }
            var label: (open: Int, close: Int)?
            if kind == "Button" {
                if let l = closures.first(where: { $0.name == "label" }) { label = (l.open, l.close) }
                else if args.contains("action:"), let f = closures.first { label = (f.open, f.close) }
            } else if let l = closures.last {
                label = (l.open, l.close)
            }
            let line = raw[0..<start].filter { $0 == newline }.count + 1
            if label == nil {
                if stringLabel {
                    if !around.colored { out.append(Finding(file: file, line: line, what: "\(kind)'s title is left to the tint")) }
                } else if kind == "ShareLink" || kind == "PhotosPicker" {
                    if !around.colored { out.append(Finding(file: file, line: line, what: "\(kind)'s system label is left to the tint")) }
                }
                continue
            }
            guard let l = label else { continue }
            let inside = NSRange(location: l.open, length: l.close - l.open)
            for w in words.matches(in: str, range: inside) {
                let ts = w.range.location
                var tp = ts + ns.substring(with: w.range(at: 1)).utf8.count
                while tp < s.count && (s[tp] == space || s[tp] == tab) { tp += 1 }
                let te = matchClose(s, tp, lp, rp)
                guard te > tp else { continue }
                let tmods = text(s, te + 1, modifiersEnd(s, te + 1))
                if colored(tmods) || tmods.contains(".font(.emoji(") { continue }
                if around.colored || enclosing(s, ts, l.open).colored { continue }
                let wline = raw[0..<ts].filter { $0 == newline }.count + 1
                out.append(Finding(file: file, line: wline, what: "\(kind)'s words are left to the tint"))
            }
        }
        return out
    }
}
