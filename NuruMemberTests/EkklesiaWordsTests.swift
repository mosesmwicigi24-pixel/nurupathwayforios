// Ekklesia's words — the same lines Android says (EkklesiaWordsTest.kt).
import XCTest
@testable import NuruMember

final class EkklesiaWordsTests: XCTestCase {
    func testInvitationIsSteadyWithinADayAndRotatesAcrossDays() {
        XCTAssertEqual(EkklesiaWords.invitation(dayOfYear: 40), EkklesiaWords.invitation(dayOfYear: 40))
        let seen = Set((0..<EkklesiaWords.invitations.count).map { EkklesiaWords.invitation(dayOfYear: $0) })
        XCTAssertEqual(seen.count, EkklesiaWords.invitations.count)
        XCTAssertTrue(EkklesiaWords.invitations.contains(EkklesiaWords.invitation(dayOfYear: 366)))
        XCTAssertTrue(EkklesiaWords.invitations.contains(EkklesiaWords.invitation(dayOfYear: -1)))
    }

    func testNoZeroCountsInTheStandingLine() {
        XCTAssertNil(EkklesiaWords.standing(memberCount: 0))
        XCTAssertEqual(EkklesiaWords.standing(memberCount: 1), "1 intercessor already stands.")
        XCTAssertEqual(EkklesiaWords.standing(memberCount: 34), "34 intercessors already stand.")
    }

    func testMemberLineNamesWhatWaitsTodayUrgencyFirst() {
        XCTAssertEqual(EkklesiaWords.memberLine(needsMeToday: 0, urgent: 0), "You have stood with every need today.")
        XCTAssertEqual(EkklesiaWords.memberLine(needsMeToday: 1, urgent: 0), "1 need waits on you today.")
        XCTAssertEqual(EkklesiaWords.memberLine(needsMeToday: 1, urgent: 1), "1 urgent need waits on you today.")
        XCTAssertEqual(EkklesiaWords.memberLine(needsMeToday: 3, urgent: 1), "3 needs wait on you today, 1 urgent.")
        XCTAssertEqual(EkklesiaWords.memberLine(needsMeToday: 3, urgent: 0), "3 needs wait on you today.")
    }

    func testCountsLineDropsZerosAndRepeats() {
        XCTAssertNil(EkklesiaWords.countsLine(intercessors: 0, prayers: 0, updates: 0))
        XCTAssertEqual(EkklesiaWords.countsLine(intercessors: 1, prayers: 1, updates: 0), "1 interceding")
        XCTAssertEqual(EkklesiaWords.countsLine(intercessors: 12, prayers: 40, updates: 2), "12 interceding · 40 prayers · 2 updates")
        XCTAssertEqual(EkklesiaWords.countsLine(intercessors: 0, prayers: 0, updates: 1), "1 update")
    }

    func testAnEkklesiaPushLandsOnTheWatch() {
        XCTAssertEqual(NoticeRouter.route(NoticeTarget(template: "ekklesia_request")), .ekklesia)
    }
}
