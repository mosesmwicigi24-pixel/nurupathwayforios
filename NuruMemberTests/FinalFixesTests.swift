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
                            progress: Int = 0) -> [String: Any] {
        ["module_id": id, "level_number": 1, "module_sequence_number": seq, "title": "Module \(id)",
         "summary": NSNull(), "estimated_minutes": 10, "evaluation_kind": "none", "quiz_pass_mark": 70,
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
}
