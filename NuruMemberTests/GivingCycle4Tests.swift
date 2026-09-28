// Giving Cycle 4 — a recurring gift the member controls, pinned: the rhythm
// row says when it falls on the church's (Nairobi) calendar — a monthly gift
// on the 31st says so in a short month — "Start with a gift now" and "Nothing
// is taken today" say exactly what the server will do, a change sends only
// what changed and only what the server would accept, a pause runs from
// tomorrow to a year ahead, and a paused gift says why (and only offers Resume
// when it is the member's to resume). The decoder is configured exactly like
// APIClient's: snake_case in, camelCase out.
import XCTest
@testable import NuruMember

final class GivingCycle4Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    private func schedule(_ fields: String) throws -> GivingSchedule {
        try decode(GivingSchedule.self, #"{"schedule_id":"s1","fund":"tithe","amount_minor":50000,"currency":"KES","method":"mpesa",\#(fields)}"#)
    }

    private func date(_ iso: String) -> Date { ISO8601DateFormatter().date(from: iso)! }

    private func grouped(_ n: Int) -> String { n.formatted(.number.grouping(.automatic)) }

    // MARK: Rhythm row — weekly and monthly

    func testWeeklyRhythmRow() throws {
        let s = try schedule(#""frequency":"weekly","status":"active","next_run_at":"2026-10-04T06:00:00Z""#)
        XCTAssertEqual(ScheduleRhythm.day(of: s), 0, "Sunday is 0, as the server numbers it")
        XCTAssertEqual(ScheduleRhythm.rowText(for: s), "KSh 500 every Sunday · next Sun 4 Oct")
    }

    func testWeeklyDayIsNairobisNotUTCs() throws {
        // 22:30 UTC on Saturday is 01:30 on Sunday in Nairobi.
        let s = try schedule(#""frequency":"weekly","status":"active","next_run_at":"2026-10-03T22:30:00Z""#)
        XCTAssertEqual(ScheduleRhythm.rowText(for: s), "KSh 500 every Sunday · next Sun 4 Oct")
    }

    func testMonthlyRhythmRowUsesItsOwnDay() throws {
        let s = try schedule(#""frequency":"monthly","status":"active","anchor_day":28,"next_run_at":"2026-10-28T06:00:00Z""#)
        XCTAssertEqual(ScheduleRhythm.rowText(for: s), "KSh 500 every month on the 28th · next Wed 28 Oct")
    }

    func testMonthlyOnThe31stInShortMonths() throws {
        let nov = try schedule(#""frequency":"monthly","status":"active","anchor_day":31,"next_run_at":"2026-11-30T06:00:00Z""#)
        XCTAssertEqual(ScheduleRhythm.rowText(for: nov),
                       "KSh 500 every month on the 31st · next Mon 30 Nov, the last day of November",
                       "its own day stays the 31st; the month's last day is when it comes")
        let feb = try schedule(#""frequency":"monthly","status":"active","anchor_day":31,"next_run_at":"2027-02-28T06:00:00Z""#)
        XCTAssertEqual(ScheduleRhythm.rowText(for: feb),
                       "KSh 500 every month on the 31st · next Sun 28 Feb, the last day of February")
        let noAnchor = try schedule(#""frequency":"monthly","status":"active","next_run_at":"2026-11-30T06:00:00Z""#)
        XCTAssertEqual(ScheduleRhythm.rowText(for: noAnchor), "KSh 500 every month on the 30th · next Mon 30 Nov",
                       "an older server's gift reads its next prompt's day")
    }

    func testTheRhythmRowIsTheSoonestRunningGift() throws {
        let all = try decode([GivingSchedule].self, """
        [{"schedule_id":"late","status":"active","frequency":"monthly","next_run_at":"2026-11-01T06:00:00Z"},
         {"schedule_id":"paused","status":"paused","frequency":"weekly","next_run_at":"2026-09-30T06:00:00Z"},
         {"schedule_id":"soon","status":"active","frequency":"weekly","next_run_at":"2026-10-04T06:00:00Z"},
         {"schedule_id":"gone","status":"cancelled","frequency":"weekly","next_run_at":"2026-09-29T06:00:00Z"}]
        """)
        XCTAssertEqual(ScheduleRhythm.soonestActive(all)?.scheduleId, "soon", "paused and cancelled gifts are not a rhythm")
        XCTAssertNil(ScheduleRhythm.soonestActive(Array(all.dropFirst(3))), "no running gift → no row")
        XCTAssertEqual(ScheduleRhythm.ordinal(1), "1st"); XCTAssertEqual(ScheduleRhythm.ordinal(2), "2nd")
        XCTAssertEqual(ScheduleRhythm.ordinal(3), "3rd"); XCTAssertEqual(ScheduleRhythm.ordinal(11), "11th")
        XCTAssertEqual(ScheduleRhythm.ordinal(12), "12th"); XCTAssertEqual(ScheduleRhythm.ordinal(13), "13th")
        XCTAssertEqual(ScheduleRhythm.ordinal(21), "21st"); XCTAssertEqual(ScheduleRhythm.ordinal(22), "22nd")
        XCTAssertEqual(ScheduleRhythm.ordinal(23), "23rd"); XCTAssertEqual(ScheduleRhythm.ordinal(31), "31st")
    }

    // MARK: Start with a gift now / nothing today

    func testStartNowAndNothingTodayLines() {
        let saturday31 = date("2026-10-31T09:00:00Z")   // Sat 31 Oct, noon in Nairobi
        let amount = "KSh \(grouped(1000))"
        XCTAssertEqual(ScheduleRhythm.startNowLine(amountLabel: amount, frequency: "weekly", now: saturday31),
                       "\(amount) now, then every Saturday")
        XCTAssertEqual(ScheduleRhythm.startNowLine(amountLabel: amount, frequency: "monthly", now: saturday31),
                       "\(amount) now, then every month on the 31st")
        XCTAssertEqual(ScheduleRhythm.nothingTodayLine(frequency: "weekly", now: saturday31),
                       "Nothing is taken today — the first prompt comes on 7 Nov 2026.")
        XCTAssertEqual(ScheduleRhythm.nothingTodayLine(frequency: "monthly", now: saturday31),
                       "Nothing is taken today — the first prompt comes on 30 Nov 2026.", "the 31st clamps into November")
        XCTAssertEqual(ScheduleRhythm.nothingTodayLine(firstPromptISO: "2026-11-30T06:00:00Z"),
                       "Nothing is taken today — the first prompt comes on 30 Nov 2026.")
        XCTAssertEqual(ScheduleRhythm.setUpLine(frequency: "weekly", firstPromptISO: "2026-10-11T06:00:00Z"),
                       "Your weekly gift is set up — the first prompt comes on 11 Oct 2026.")
        XCTAssertEqual(ScheduleRhythm.setUpLine(frequency: "monthly", firstPromptISO: ""), "Your monthly gift is set up.")
    }

    func testScheduleCreatedWithAFirstGiftOrAReason() throws {
        let now = try decode(ScheduleCreated.self, """
        {"schedule_id":"s1","status":"active","next_run_at":"2026-11-04T06:00:00Z","reused":false,
         "first_charge":{"transaction_id":"t1","status":"processing","provider":"mpesa","provider_ref":"ws_CO_1","reused":false}}
        """)
        XCTAssertEqual(now.firstCharge?.transactionId, "t1", "the first prompt's gift — the ceremony watches it")
        XCTAssertNil(now.firstChargeError)
        let failed = try decode(ScheduleCreated.self,
            #"{"schedule_id":"s1","status":"active","next_run_at":"2026-11-04T06:00:00Z","reused":false,"first_charge":null,"first_charge_error":"M-Pesa is unavailable right now"}"#)
        XCTAssertNil(failed.firstCharge)
        XCTAssertEqual(failed.firstChargeError, "M-Pesa is unavailable right now", "the schedule stands; today's prompt did not go")
        let next = try decode(ScheduleCreated.self, #"{"schedule_id":"s1","status":"active","next_run_at":"2026-11-04T06:00:00Z","reused":true}"#)
        XCTAssertNil(next.firstCharge); XCTAssertNil(next.firstChargeError)
        XCTAssertTrue(next.reused)
    }

    // MARK: Schedule edit validation

    private let mpesa = GivingMethods.fallback().method("mpesa")

    func testAnUnchangedFormSendsNothing() throws {
        let s = try schedule(#""frequency":"weekly","status":"active","next_run_at":"2026-10-04T06:00:00Z","phone_number":"+254712345678""#)
        let d = ScheduleEdit.draft(of: s)
        XCTAssertEqual(d, ScheduleDraft(amountText: "500", day: 0, phoneText: "+254712345678", useProfileNumber: false))
        XCTAssertEqual(ScheduleEdit.plan(d, for: s, rail: mpesa), ScheduleEdit.Plan(patch: nil, problem: nil))
    }

    func testAmountMustBeWholeShillingsInsideTheLimits() throws {
        let s = try schedule(#""frequency":"monthly","status":"active","anchor_day":5,"next_run_at":"2026-10-05T06:00:00Z""#)
        var d = ScheduleEdit.draft(of: s)
        d.amountText = "1,500"
        XCTAssertEqual(ScheduleEdit.plan(d, for: s, rail: mpesa).patch, SchedulePatch(amountMinor: 150_000), "only the amount changed")
        d.amountText = "1500.50"
        XCTAssertEqual(ScheduleEdit.plan(d, for: s, rail: mpesa).problem, "Enter whole shillings — no cents.")
        d.amountText = "300000"
        XCTAssertEqual(ScheduleEdit.plan(d, for: s, rail: mpesa).problem, "M-Pesa gifts are from KSh 1 to KSh \(grouped(250_000)).")
        d.amountText = ""
        XCTAssertEqual(ScheduleEdit.plan(d, for: s, rail: mpesa).problem, "Enter an amount.")
        d.amountText = "0"
        XCTAssertEqual(ScheduleEdit.plan(d, for: s, rail: mpesa).problem, "Enter an amount.")
        XCTAssertNil(ScheduleEdit.plan(d, for: s, rail: mpesa).patch, "nothing is sent while something is wrong")
    }

    func testDayMustBeARealDay() throws {
        let weekly = try schedule(#""frequency":"weekly","status":"active","next_run_at":"2026-10-04T06:00:00Z""#)
        var d = ScheduleEdit.draft(of: weekly)
        d.day = 3
        XCTAssertEqual(ScheduleEdit.plan(d, for: weekly, rail: mpesa).patch, SchedulePatch(day: 3), "Wednesday")
        d.day = 7
        XCTAssertEqual(ScheduleEdit.plan(d, for: weekly, rail: mpesa).problem, "Choose a day.")
        let monthly = try schedule(#""frequency":"monthly","status":"active","anchor_day":5,"next_run_at":"2026-10-05T06:00:00Z""#)
        var m = ScheduleEdit.draft(of: monthly)
        m.day = 31
        XCTAssertEqual(ScheduleEdit.plan(m, for: monthly, rail: mpesa).patch, SchedulePatch(day: 31))
        m.day = 0
        XCTAssertEqual(ScheduleEdit.plan(m, for: monthly, rail: mpesa).problem, "Choose a day.", "a month has no day 0")
    }

    func testNumberChangesAreKenyanOrBackToTheProfile() throws {
        let own = try schedule(#""frequency":"weekly","status":"active","next_run_at":"2026-10-04T06:00:00Z","phone_number":"+254712345678""#)
        var d = ScheduleEdit.draft(of: own)
        d.phoneText = "0712 345 678"
        XCTAssertNil(ScheduleEdit.plan(d, for: own, rail: mpesa).patch, "the same number, typed another way, is no change")
        d.phoneText = "0110 123 456"
        XCTAssertEqual(ScheduleEdit.plan(d, for: own, rail: mpesa).patch, SchedulePatch(phone: .number("+254110123456")))
        d.phoneText = "12345"
        XCTAssertEqual(ScheduleEdit.plan(d, for: own, rail: mpesa).problem, KenyanPhone.invalidMessage)
        d.phoneText = ""
        XCTAssertEqual(ScheduleEdit.plan(d, for: own, rail: mpesa).problem, "Add the number to prompt, or use your profile number.")
        d.useProfileNumber = true
        XCTAssertEqual(ScheduleEdit.plan(d, for: own, rail: mpesa).patch, SchedulePatch(phone: .profile), "back to the profile number")

        let profile = try schedule(#""frequency":"weekly","status":"active","next_run_at":"2026-10-04T06:00:00Z""#)
        let p = ScheduleEdit.draft(of: profile)
        XCTAssertTrue(p.useProfileNumber)
        XCTAssertNil(ScheduleEdit.plan(p, for: profile, rail: mpesa).patch, "already on the profile number")
    }

    func testThePatchSendsOnlyWhatChangedAndNullForTheProfile() throws {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.outputFormatting = .sortedKeys
        func json(_ p: SchedulePatch) throws -> String { String(decoding: try e.encode(p), as: UTF8.self) }
        XCTAssertEqual(try json(SchedulePatch(amountMinor: 150_000)), #"{"amount_minor":150000}"#)
        XCTAssertEqual(try json(SchedulePatch(phone: .profile)), #"{"phone_number":null}"#, "null = back to the profile number")
        XCTAssertEqual(try json(SchedulePatch(phone: .number("+254712345678"))), #"{"phone_number":"+254712345678"}"#)
        XCTAssertEqual(try json(SchedulePatch(day: 0, headsUp: false)), #"{"day":0,"heads_up":false}"#)
        XCTAssertEqual(try json(SchedulePatch()), "{}")
        XCTAssertTrue(SchedulePatch().isEmpty)
    }

    // MARK: Pause-date bounds

    func testPauseRunsFromTomorrowToAYearAhead() {
        let now = date("2026-09-28T20:30:00Z")   // Mon 28 Sep, 23:30 in Nairobi
        let r = PauseDates.range(now: now)
        XCTAssertEqual(PauseDates.wire(r.lowerBound), "2026-09-29", "tomorrow")
        XCTAssertEqual(PauseDates.wire(r.upperBound), "2027-09-28", "a year from today")
        XCTAssertFalse(PauseDates.isAllowed(PauseDates.date("2026-09-28")!, now: now), "not today")
        XCTAssertTrue(PauseDates.isAllowed(PauseDates.date("2026-09-29")!, now: now))
        XCTAssertTrue(PauseDates.isAllowed(PauseDates.date("2027-09-28")!, now: now))
        XCTAssertFalse(PauseDates.isAllowed(PauseDates.date("2027-09-29")!, now: now), "not past a year")
    }

    func testPauseBoundsFollowNairobisDayNotUTCs() {
        let now = date("2026-09-28T21:30:00Z")   // already Tue 29 Sep, 00:30 in Nairobi
        XCTAssertEqual(PauseDates.wire(PauseDates.range(now: now).lowerBound), "2026-09-30")
        XCTAssertEqual(PauseDates.wire(PauseDates.date("2026-10-05")!), "2026-10-05", "a date survives the wire")
    }

    // MARK: Pause-reason copy

    func testWhyAGiftIsPaused() throws {
        let failures = try schedule(#""frequency":"weekly","status":"paused","pause_reason":"failures""#)
        XCTAssertEqual(PauseCopy.line(for: failures), "Paused after 3 prompts didn't go through")
        XCTAssertTrue(PauseCopy.canResume(failures))
        XCTAssertEqual(PauseCopy.cardLine(for: failures), "Nothing is owed")

        let until = try schedule(#""frequency":"weekly","status":"paused","pause_reason":"member","resume_on":"2026-10-05""#)
        XCTAssertEqual(PauseCopy.line(for: until), "Paused until 5 Oct 2026")
        XCTAssertTrue(PauseCopy.canResume(until))
        XCTAssertEqual(PauseCopy.cardLine(for: until), "Resumes 5 Oct")

        let member = try schedule(#""frequency":"weekly","status":"paused","pause_reason":"member","resume_on":null"#)
        XCTAssertEqual(PauseCopy.line(for: member), "Paused")
        XCTAssertTrue(PauseCopy.canResume(member))

        let pledge = try schedule(#""frequency":"monthly","status":"paused","pause_reason":"pledge""#)
        XCTAssertEqual(PauseCopy.line(for: pledge), "Paused with its pledge — resume the pledge in Partners")
        XCTAssertFalse(PauseCopy.canResume(pledge), "no Resume — the server refuses; the pledge brings it back")

        let legacy = try schedule(#""frequency":"weekly","status":"paused""#)
        XCTAssertEqual(PauseCopy.line(for: legacy), "Paused")
        XCTAssertTrue(PauseCopy.canResume(legacy))

        let running = try schedule(#""frequency":"weekly","status":"active""#)
        XCTAssertNil(PauseCopy.line(for: running))
        XCTAssertFalse(PauseCopy.canResume(running))
    }

    func testScheduleRowsCarryTheCycle4Fields() throws {
        let s = try schedule(#""frequency":"monthly","status":"paused","pause_reason":"member","resume_on":"2026-10-05","heads_up":false,"anchor_day":31"#)
        XCTAssertEqual(s.pauseReason, "member")
        XCTAssertEqual(s.resumeOn, "2026-10-05")
        XCTAssertFalse(s.headsUp)
        XCTAssertEqual(s.anchorDay, 31)
        let old = try schedule(#""frequency":"weekly","status":"active""#)
        XCTAssertNil(old.pauseReason); XCTAssertNil(old.resumeOn); XCTAssertNil(old.anchorDay)
        XCTAssertTrue(old.headsUp, "an older server's gift keeps the heads-up on")
    }

    // MARK: Schedule notifications

    func testScheduleNoticesOpenTheirSheetAndSayWhy() throws {
        let failed = try decode(NotificationRow.self, """
        {"notification_id":"n1","template":"giving_schedule_failed","status":"sent",
         "payload":{"schedule_id":"s1","frequency":"weekly","reason":"The M-Pesa prompt couldn't reach the phone.",
                    "hint":"Check the phone is on and has signal, then try again.","retry_at":"2026-09-28T14:00:00Z"}}
        """)
        XCTAssertEqual(GiveLink.from(template: failed.template, transactionId: nil, scheduleId: failed.payload?.scheduleId),
                       .schedule(scheduleId: "s1"))
        XCTAssertEqual(GivingNotificationCopy.title(template: failed.template, payload: failed.payload), "Your weekly gift didn't go through")
        XCTAssertEqual(GivingNotificationCopy.body(template: failed.template, payload: failed.payload),
                       "The M-Pesa prompt couldn't reach the phone. We'll send the prompt once more later today.")

        let paused = try decode(NotificationRow.self,
            #"{"notification_id":"n2","template":"giving_schedule_paused","payload":{"schedule_id":"s2","reason":"There wasn't enough in the M-Pesa account."}}"#)
        XCTAssertEqual(GiveLink.from(template: paused.template, transactionId: nil, scheduleId: paused.payload?.scheduleId),
                       .schedule(scheduleId: "s2"))
        XCTAssertEqual(GivingNotificationCopy.title(template: paused.template, payload: paused.payload), "Your recurring gift is paused")
        XCTAssertEqual(GivingNotificationCopy.body(template: paused.template, payload: paused.payload),
                       "There wasn't enough in the M-Pesa account. We've stopped sending prompts for now. Open Give to resume it whenever you're ready.")
    }

    func testTheHeadsUpOpensGiveAndSaysWhatIsComing() throws {
        let n = try decode(NotificationRow.self, """
        {"notification_id":"n3","template":"giving_schedule_heads_up",
         "payload":{"schedule_id":"s1","amount_minor":50000,"currency":"KES","frequency":"monthly","fund_name":"Tithe","prompt_at":"2026-10-05T06:00:00Z"}}
        """)
        XCTAssertNil(GiveLink.from(template: n.template, transactionId: nil, scheduleId: n.payload?.scheduleId),
                     "the heads-up opens Give itself, not a sheet")
        XCTAssertEqual(GivingNotificationCopy.title(template: n.template, payload: n.payload), "Your monthly gift is ready")
        XCTAssertEqual(GivingNotificationCopy.body(template: n.template, payload: n.payload),
                       "An M-Pesa prompt for KSh 500 to Tithe is coming to your phone in a few minutes. Enter your PIN to give.")
    }

    /// Giving Cycle 7's notice when the office changes a gift at the member's
    /// request — the server's words (workers/dispatch.ts), which the inbox
    /// used to show without any (found comparing the apps, Cycle 10).
    func testTheOfficesChangeSaysWhatItDidAndOpensTheGift() throws {
        let paused = try decode(NotificationRow.self, """
        {"notification_id":"n4","template":"giving_schedule_office_change","status":"sent",
         "payload":{"schedule_id":"s1","action":"pause","resume_on":"2026-10-12","amount_minor":100000,"currency":"KES","frequency":"weekly","fund_name":"Tithe"}}
        """)
        XCTAssertEqual(GiveLink.from(template: paused.template, transactionId: nil, scheduleId: paused.payload?.scheduleId),
                       .schedule(scheduleId: "s1"))
        XCTAssertEqual(GivingNotificationCopy.title(template: paused.template, payload: paused.payload), "Your recurring gift is paused")
        XCTAssertEqual(GivingNotificationCopy.body(template: paused.template, payload: paused.payload),
                       "The church office paused your weekly gift of KSh 1,000 to Tithe, as you asked — it starts again on 12 October.")

        let resumed = try decode(NotificationRow.self,
            #"{"notification_id":"n5","template":"giving_schedule_office_change","payload":{"schedule_id":"s1","action":"resume","amount_minor":500000,"currency":"KES","frequency":"monthly"}}"#)
        XCTAssertEqual(GivingNotificationCopy.title(template: resumed.template, payload: resumed.payload), "Your recurring gift is back on")
        XCTAssertEqual(GivingNotificationCopy.body(template: resumed.template, payload: resumed.payload),
                       "The church office resumed your monthly gift of KSh 5,000, as you asked.")

        let cancelled = try decode(NotificationRow.self,
            #"{"notification_id":"n6","template":"giving_schedule_office_change","payload":{"schedule_id":"s1","action":"cancel","amount_minor":100000,"currency":"KES","frequency":"weekly","fund_name":"Tithe"}}"#)
        XCTAssertEqual(GivingNotificationCopy.title(template: cancelled.template, payload: cancelled.payload), "Your recurring gift was cancelled")
        XCTAssertEqual(GivingNotificationCopy.body(template: cancelled.template, payload: cancelled.payload),
                       "The church office cancelled your weekly gift of KSh 1,000 to Tithe, as you asked. Nothing more will be prompted.")
    }
}
