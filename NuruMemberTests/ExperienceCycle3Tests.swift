// Experience Cycle 3 — interaction design, pinned (pathway docs/EXPERIENCE.md
// §7): every tap lands where it points, every screen has a way out, and Back
// returns you where you were. The journey's exam rule itself (`exam_available`)
// sits with the other journey tests in ExperienceCycle1Tests; here are the
// rest — the exam row and the exam screen's refusal. Payloads are decoded
// exactly like APIClient's: snake_case in.
import XCTest
@testable import NuruMember

final class ExperienceCycle3Tests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ object: Any) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func module(_ id: String, seq: Int, _ status: String, completed: Bool = false,
                        kind: String = "none", examAvailable: Bool? = nil) throws -> LevelModule {
        var row: [String: Any] = [
            "module_id": id, "level_number": 1, "module_sequence_number": seq, "title": "Module \(id)",
            "summary": NSNull(), "estimated_minutes": 10, "evaluation_kind": kind, "quiz_pass_mark": 70,
            "completed": completed, "status": status, "progress": completed ? 100 : 0, "locked": status == "locked"]
        if let examAvailable { row["exam_available"] = examAvailable }
        return try decode(LevelModule.self, row)
    }

    // MARK: #1 — an exam that can't be taken is never a way in

    func testAnOpenExamRowWithNoQuestionsOpensSoon() throws {
        XCTAssertTrue(try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: false).examOpensSoon)
        XCTAssertFalse(try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: true).examOpensSoon)
        XCTAssertFalse(try module("exam", seq: 11, "next", kind: "exit_exam").examOpensSoon, "absent = available")
        XCTAssertFalse(try module("exam", seq: 11, "locked", kind: "exit_exam", examAvailable: false).examOpensSoon,
                       "still behind the lessons: it reads locked, as before")
        XCTAssertFalse(try module("exam", seq: 11, "completed", completed: true, kind: "exit_exam", examAvailable: false).examOpensSoon,
                       "a passed exam is passed")
        XCTAssertFalse(try module("m1", seq: 1, "next", examAvailable: false).examOpensSoon, "a lesson is never the exam")
    }

    @MainActor
    func testContinueNeverLandsOnAnExamThatOpensSoon() throws {
        let vm = PathwayViewModel()
        vm.modulesByLevel[1] = [try module("m10", seq: 10, "completed", completed: true),
                                try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: false)]
        XCTAssertNil(vm.resumeModule(in: 1), "every lesson done and the exam not open: nothing to continue")
        vm.modulesByLevel[1] = [try module("m10", seq: 10, "completed", completed: true),
                                try module("exam", seq: 11, "next", kind: "exit_exam", examAvailable: true)]
        XCTAssertEqual(vm.resumeModule(in: 1)?.moduleId, "exam", "an open exam is still the next step")
        vm.modulesByLevel[1] = [try module("m9", seq: 9, "next"),
                                try module("exam", seq: 11, "locked", kind: "exit_exam", examAvailable: false)]
        XCTAssertEqual(vm.resumeModule(in: 1)?.moduleId, "m9")
    }

    /// The exam screen's refusal is the server's words with Go back — any
    /// refusal; anything else speaks §4 with Try again.
    func testTheExamsRefusalKeepsTheServersWords() {
        let notReady = APIError.http(status: 422, code: "UNPROCESSABLE",
                                     message: "Your Level 1 exam isn't ready yet — we'll let you know when it opens.")
        XCTAssertEqual(LevelExamViewModel.refusal(notReady, deviceOnline: true),
                       "Your Level 1 exam isn't ready yet — we'll let you know when it opens.")
        let gate = APIError.http(status: 409, code: "GATE_LOCKED", message: "Finish every module in this level before the exam")
        XCTAssertEqual(LevelExamViewModel.refusal(gate, deviceOnline: true), "Finish every module in this level before the exam")
        XCTAssertNil(LevelExamViewModel.refusal(APIError.http(status: 500, code: "INTERNAL", message: "boom"), deviceOnline: true),
                     "ours: Try again, never the raw words")
        XCTAssertNil(LevelExamViewModel.refusal(APIError.offline, deviceOnline: false))
        XCTAssertNil(LevelExamViewModel.refusal(APIError.http(status: 404, code: "NOT_FOUND", message: "Level not found"), deviceOnline: true),
                     "not found is §4's own state")
    }

    // MARK: #2 — the pledge page: collected automatically, paying is a choice

    private func decode<T: Decodable>(_ type: T.Type, json: String) throws -> T {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return try d.decode(T.self, from: Data(json.utf8))
    }

    /// Ada's Kenya trip — `schedule_id` set on an older row.
    private func pledge(_ id: String = "p-kenya", scheduleId: String? = nil) throws -> Pledge {
        let sid = scheduleId.map { #""\#($0)""# } ?? "null"
        return try decode(Pledge.self, json: #"{"pledge_id":"\#(id)","shape":"monthly","amount_minor":500000,"currency":"KES","due_day":5,"title":"Kenya trip","status":"active","schedule_id":\#(sid)}"#)
    }

    /// A recurring gift — bound to `pledge` when given (its collector).
    private func gift(_ id: String, pledge: String? = nil, status: String = "active") throws -> GivingSchedule {
        let bound = pledge.map { #""pledge":{"pledge_id":"\#($0)","title":"Kenya trip"}"# } ?? #""pledge":null"#
        return try decode(GivingSchedule.self, json: #"""
        {"schedule_id":"\#(id)","fund":"mission","amount_minor":500000,"currency":"KES","method":"mpesa",
         "frequency":"monthly","status":"\#(status)","next_run_at":"2026-10-05T06:01:00.000Z",\#(bound),"next_amount_minor":500000}
        """#)
    }

    func testThePledgePagePaysEarlyWhileItsCollectorRuns() throws {
        let kenya = try pledge()
        let collector = try gift("s1", pledge: "p-kenya")
        XCTAssertTrue(PledgePace.paysEarly(kenya, schedules: [collector]), "collected automatically: Pay early + Pause, both quiet")
        guard case .collected(let id, let line) = PledgePace.offer(for: kenya, methods: nil, schedules: [collector]) else {
            return XCTFail("the page's card says the same thing")
        }
        XCTAssertEqual(id, "s1")
        XCTAssertTrue(line.hasPrefix("Collected automatically — next KSh 5,000"), line)

        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: [try gift("s1", pledge: "p-kenya", status: "paused")]),
                       "a paused collector collects nothing: Pay now")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: []), "no collector: Pay now stays the gold primary")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: nil), "the gifts not known yet: never guessed")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: [try gift("s2", pledge: "p-other")]), "another pledge's collector")
        XCTAssertFalse(PledgePace.paysEarly(kenya, schedules: [try gift("s4", status: "cancelled")]))
        XCTAssertTrue(PledgePace.paysEarly(try pledge(scheduleId: "s3"), schedules: [try gift("s3")]),
                      "an older row, bound by the pledge's own schedule_id")
    }

    // MARK: #3 — one router for an inbox row and a tapped banner

    /// A row of GET /me/notifications, verbatim in shape.
    private func notice(_ template: String, _ payload: [String: Any] = [:]) throws -> NotificationRow {
        try decode(NotificationRow.self, ["notification_id": "n1", "template": template, "payload": payload,
                                          "status": "sent", "scheduled_for": "2026-10-04T06:56:24.450Z",
                                          "sent_at": NSNull(), "read_at": NSNull()])
    }

    /// Ada's "Ring check" notices on the local API: they used to open the
    /// greeting sheet from the inbox while a banner opened the player.
    func testALiveNoticeOpensTheLiveFromTheInboxAsFromABanner() throws {
        let started = try notice("live_stream_started", ["scope": "cell", "title": "Ring check", "cell_id": "c1",
                                                          "stream_id": "a34a265b-9f24-4ba1-a474-8cf81db7cd52"])
        let fromInbox = NoticeRouter.route(NoticeTarget(started))
        XCTAssertEqual(fromInbox, .live(streamId: "a34a265b-9f24-4ba1-a474-8cf81db7cd52", title: "Ring check"))
        XCTAssertEqual(NoticeRouter.route(NoticeTarget(userInfo: NoticeTarget(started).userInfo)), fromInbox,
                       "the banner carries the same keys and lands the same")
        let invite = try notice("live_guest_invite", ["title": "Ring check", "stream_id": "a34a265b-9f24-4ba1-a474-8cf81db7cd52"])
        XCTAssertEqual(NoticeRouter.route(NoticeTarget(invite)), fromInbox, "a guest invite opens the same Live")
        XCTAssertEqual(NoticeRouter.route(NoticeTarget(userInfo: ["template": "live_stream_started"])),
                       .live(streamId: nil, title: nil), "an older banner names no stream")
    }

    func testEveryNoticeFamilyLandsTheSameFromBothDoors() throws {
        let cases: [(NotificationRow, NoticeRoute)] = [
            (try notice("pledge_due_soon", ["pledge_id": "p1", "title": "Kenya trip"]), .pledge("p1")),
            (try notice("giving_schedule_covered", ["pledge_id": "p1"]), .pledge("p1")),
            (try notice("giving_gift_failed", ["transaction_id": "t1"]), .gift(.failedGift(transactionId: "t1"))),
            (try notice("giving_schedule_paused", ["schedule_id": "s1"]), .gift(.schedule(scheduleId: "s1"))),
            (try notice("announcement_posted", ["announcement_id": "a1"]), .announcement("a1")),
            (try notice("module_published", ["module_id": "m1"]), .pathway(.module("m1"))),
            (try notice("level_ushered", ["level_number": 2]), .pathway(.level(2))),
            (try notice("level_completed"), .pathwayTab),
            (try notice("reflection_returned", ["feedback": "Look again at verse 3."]), .pathwayTab),
            (try notice("department_post", ["department_id": "d1"]), .department("d1")),
            (try notice("serve_request_approved"), .departments),
            (try notice("event_reminder_24h"), .events),
            (try notice("pledge_overdue"), .partners),
            (try notice("giving_schedule_heads_up", ["frequency": "monthly"]), .give),
            (try notice("badge_awarded", ["name": "Faithful"]), .profile),
            (try notice("plan_group_invite_received", ["invite_token": "tok", "group_id": "g1"]), .readingInvite("tok")),
            (try notice("plan_group_day_completed", ["group_id": "g1"]), .readWithFriend),
            (try notice("sunday_letter", ["title": "A word for the week"]), .itself),
            (try notice("connection_request_received", ["full_name": "Ben"]), .itself),
        ]
        for (n, want) in cases {
            XCTAssertEqual(NoticeRouter.route(NoticeTarget(n)), want, "inbox: \(n.template)")
            XCTAssertEqual(NoticeRouter.route(NoticeTarget(userInfo: NoticeTarget(n).userInfo)), want, "banner: \(n.template)")
        }
    }

    /// The banner carries what routing needs and no more — a notice's title
    /// rides along only for a Live (its stream's name).
    func testABannerCarriesOnlyWhatRoutingNeeds() throws {
        let letter = try notice("sunday_letter", ["title": "A word for the week"])
        XCTAssertEqual(NoticeTarget(letter).userInfo["title"] as? String, "")
        let live = try notice("live_stream_started", ["title": "Ring check", "stream_id": "s1"])
        XCTAssertEqual(NoticeTarget(live).userInfo["title"] as? String, "Ring check")
        XCTAssertEqual(NoticeTarget(live).userInfo["streamId"] as? String, "s1")
    }

    private func liveRow(_ id: String) throws -> LiveStreamSummary {
        try decode(LiveStreamSummary.self, ["stream_id": id, "scope": "church", "title": "Live \(id)", "kind": "video",
                                            "started_at": "2026-10-04T08:00:00Z", "hls_url": "/hls/\(id)/index.m3u8",
                                            "started_by_name": "Pastor", "viewer_count": 3])
    }

    func testALiveNoticeOpensExactlyTheStreamItNames() throws {
        let rows = [try liveRow("s1"), try liveRow("s2")]
        XCTAssertEqual(LiveDiscoveryCenter.noticeTarget(in: rows, named: "s2")?.streamId, "s2")
        XCTAssertNil(LiveDiscoveryCenter.noticeTarget(in: rows, named: "a34a265b"),
                     "over: \"This Live has ended\" — never another stream in its place")
        XCTAssertEqual(LiveDiscoveryCenter.noticeTarget(in: rows, named: nil)?.streamId, "s1",
                       "an older notice naming none: the newest watchable, as before")
        XCTAssertNil(LiveDiscoveryCenter.noticeTarget(in: [], named: nil))
    }

    // MARK: #4 — one bell: its dot means something in the inbox is unread

    func testTheBellsDotMeansSomethingIsUnread() {
        XCTAssertFalse(InboxBadge.showsDot(unread: 0), "Ada, 0 unread: no dot on any bell")
        XCTAssertTrue(InboxBadge.showsDot(unread: 1))
        XCTAssertTrue(InboxBadge.showsDot(unread: 12), "one dot, never a count")
    }

    /// One shared count, refreshed from several places — an answer that left
    /// first and lands last never undoes a fresher one.
    @MainActor
    func testALateReadNeverUndoesAFresherCount() {
        let badge = InboxBadge.shared
        badge.set(0)
        let early = badge.ticket()     // a read that left first…
        let later = badge.ticket()     // …and one that left after it
        badge.land(2, ticket: later)
        XCTAssertEqual(badge.unread, 2)
        badge.land(5, ticket: early)   // the first lands last
        XCTAssertEqual(badge.unread, 2, "an older answer never wins")
        let stale = badge.ticket()
        badge.set(0)                   // the member read everything meanwhile
        badge.land(3, ticket: stale)
        XCTAssertEqual(badge.unread, 0, "a read sent before \"Mark all read\" never brings the dot back")
        badge.land(-1, ticket: badge.ticket())
        XCTAssertEqual(badge.unread, 0)
        badge.reset()
    }

    // MARK: #5 — the M-Pesa wait keeps watching; the way out is there from the start

    func testTheWaitKeepsLookingSoALateAnswerLands() {
        XCTAssertEqual(StkWatch.nextDelay(elapsed: 0), 3)
        XCTAssertEqual(StkWatch.nextDelay(elapsed: 59.9), 3)
        XCTAssertEqual(StkWatch.nextDelay(elapsed: 60), 10)
        XCTAssertEqual(StkWatch.nextDelay(elapsed: 299), 10)
        XCTAssertNil(StkWatch.nextDelay(elapsed: 300), "five minutes, then the stage just waits for Done")
        // Walk the whole watch: the first minute as before, then every 10 s.
        var t: TimeInterval = 0
        var looks: [TimeInterval] = []
        while let d = StkWatch.nextDelay(elapsed: t) { t += d; looks.append(t) }
        XCTAssertEqual(looks.filter { $0 <= 60 }.count, 20, "20 looks in the first minute, 3 s apart")
        XCTAssertTrue(looks.contains(70), "a prompt answered at 70 s is seen at the next look — it used to never land")
        XCTAssertEqual(looks.last, 300)
    }

    func testPastTheMinuteItSaysStillProcessing() {
        XCTAssertFalse(StkWatch.isLate(elapsed: 59), "Waiting up to 60s… is still true")
        XCTAssertTrue(StkWatch.isLate(elapsed: 60), "the line changes and Done leads")
        XCTAssertEqual(StkWatch.lateLine, "Still processing — it will show in Recent giving once it clears.")
    }

    // MARK: #6 — the last tap before money moves names the money

    func testTheNumberSheetsButtonNamesTheMoney() {
        XCTAssertEqual(GiveButton.mobileMoneyLabel(amountLabel: GiveMoney.format(100_000, "KES"), frequency: nil),
                       "Give KSh 1,000")
        XCTAssertEqual(GiveButton.mobileMoneyLabel(amountLabel: GiveMoney.format(101_300, "KES"), frequency: nil),
                       "Give KSh 1,013", "the total sent — a covered fee included")
        XCTAssertEqual(GiveButton.mobileMoneyLabel(amountLabel: "KSh 1,000", frequency: "monthly"), "Start Monthly Gift")
        XCTAssertEqual(GiveButton.mobileMoneyLabel(amountLabel: "KSh 1,000", frequency: "weekly"), "Start Weekly Gift")
        XCTAssertEqual(GiveButton.mobileMoneyLabel(amountLabel: "", frequency: nil), "Give Now", "never a bare \"Give\"")
    }

    // MARK: #7 — leaving a pledge half made asks first

    func testLeavingAPledgeHalfMadeAsksFirst() {
        let opened = NewPledgeDraft(shape: "monthly", amount: 2000, customAmount: "", selectedOptionId: nil,
                                    useCustom: false, customName: "", dueDay: 4,
                                    dueOn: Date(timeIntervalSince1970: 1_800_000_000), autoCharge: false)
        XCTAssertFalse(NewPledgeDraft.asksBeforeLeaving(onFirstStep: true, draft: opened, opening: opened),
                       "step 1 as it opened: ✕ closes at once")
        var total = opened
        total.shape = "total"
        XCTAssertTrue(NewPledgeDraft.asksBeforeLeaving(onFirstStep: true, draft: total, opening: opened), "step 1 changed")
        XCTAssertTrue(NewPledgeDraft.asksBeforeLeaving(onFirstStep: false, draft: opened, opening: opened),
                      "past step 1 — on step 5 ✕ used to throw five steps away silently")
        var named = opened
        named.useCustom = true
        named.customName = "Kenya trip"
        XCTAssertTrue(NewPledgeDraft.asksBeforeLeaving(onFirstStep: true, draft: named, opening: opened),
                      "back on step 1, still holding what later steps chose")
    }
}
