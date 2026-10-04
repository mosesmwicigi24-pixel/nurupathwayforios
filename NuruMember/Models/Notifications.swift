// Notification-center DTOs — Swift mirrors of the contract in
// packages/mobile/src/api/types.ts. Decoded with `.convertFromSnakeCase`.
import Foundation

/// The subset of a notification's `payload` the UI reads for its title/body and
/// deep-link routing (extra keys are ignored).
struct NotifPayload: Codable, Sendable {
    let title: String?
    let body: String?
    let feedback: String?
    let levelNumber: Int?
    let name: String?
    let moduleId: String?
    let announcementId: String?
    /// Read with a Friend (reading-social groups.ts `notify()` calls) —
    /// `plan_group_invite_received` carries `invite_token` so a notification
    /// tap can open the SAME invite-preview screen a nuru://join/{token} deep
    /// link opens; the other plan_group_* templates carry only `group_id`.
    let inviteToken: String?
    let groupId: String?
    /// Departments (PARTNERS_PROGRAMME §4): serve_request_* / department_post /
    /// department_need_* carry `department_id` so a tap opens the page.
    let departmentId: String?
    /// Giving (Giving Cycle 3): `giving_gift_failed` carries the gift's
    /// `transaction_id` (a tap opens its result, with Try again), its amount,
    /// currency and fund, and the server's `reason` + `hint` for the banner.
    var transactionId: String? = nil
    var amountMinor: Int? = nil
    var currency: String? = nil
    var fund: String? = nil
    var reason: String? = nil
    var hint: String? = nil
    /// Recurring gifts (Giving Cycle 4): `giving_schedule_failed` / `_paused`
    /// carry the `schedule_id` (a tap opens its sheet), its frequency and when
    /// it will be tried again; the heads-up carries the fund's name.
    var scheduleId: String? = nil
    var frequency: String? = nil
    var fundName: String? = nil
    var retryAt: String? = nil
    /// Partners (Giving Cycle 5): pledge_* notices and the pledge collector's
    /// (giving_schedule_covered / _stopped) carry the `pledge_id` a tap opens
    /// — their `title` is the PLEDGE's name, not a push title — plus what
    /// their words need: covered through / ended on (YYYY-MM-DD), whether a
    /// fulfilled pledge's prompts stopped, the heads-up's pledge and whether
    /// it asks only the rest, the due-soon day count, the office's message.
    var pledgeId: String? = nil
    var coveredThrough: String? = nil
    var untilOn: String? = nil
    var scheduleStopped: Bool? = nil
    var pledgeTitle: String? = nil
    var partial: Bool? = nil
    var daysAway: Int? = nil
    var dueOn: String? = nil
    var message: String? = nil
    /// The office changed a recurring gift at the member's request (Giving
    /// Cycle 7, `giving_schedule_office_change`): pause · resume · cancel,
    /// and the day a pause ends (YYYY-MM-DD) when it has one.
    var action: String? = nil
    var resumeOn: String? = nil
    /// A department need's notices (department_need_*): the office's note
    /// when it was not approved. Their `title` is the NEED's name.
    var note: String? = nil
    /// Nuru Live (`live_stream_started`, `live_guest_invite`): the stream a
    /// tap opens — or says has ended (EXPERIENCE.md §7.2 #3).
    var streamId: String? = nil

    private enum CodingKeys: String, CodingKey {
        case title, body, feedback, levelNumber, name, moduleId, announcementId, inviteToken, groupId, departmentId
        case transactionId, amountMinor, currency, fund, reason, hint
        case scheduleId, frequency, fundName, retryAt
        case pledgeId, coveredThrough, untilOn, scheduleStopped, pledgeTitle, partial, daysAway, dueOn, message
        case action, resumeOn, note
        case streamId
    }

    /// Field by field: one field of an unexpected type (a template this app
    /// has never seen) reads as absent instead of blanking the whole payload
    /// — and with it the banner's words and the tap's destination.
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        body = try? c.decodeIfPresent(String.self, forKey: .body)
        feedback = try? c.decodeIfPresent(String.self, forKey: .feedback)
        levelNumber = try? c.decodeIfPresent(Int.self, forKey: .levelNumber)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        moduleId = try? c.decodeIfPresent(String.self, forKey: .moduleId)
        announcementId = try? c.decodeIfPresent(String.self, forKey: .announcementId)
        inviteToken = try? c.decodeIfPresent(String.self, forKey: .inviteToken)
        groupId = try? c.decodeIfPresent(String.self, forKey: .groupId)
        departmentId = try? c.decodeIfPresent(String.self, forKey: .departmentId)
        transactionId = try? c.decodeIfPresent(String.self, forKey: .transactionId)
        amountMinor = try? c.decodeIfPresent(Int.self, forKey: .amountMinor)
        currency = try? c.decodeIfPresent(String.self, forKey: .currency)
        fund = try? c.decodeIfPresent(String.self, forKey: .fund)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
        hint = try? c.decodeIfPresent(String.self, forKey: .hint)
        scheduleId = try? c.decodeIfPresent(String.self, forKey: .scheduleId)
        frequency = try? c.decodeIfPresent(String.self, forKey: .frequency)
        fundName = try? c.decodeIfPresent(String.self, forKey: .fundName)
        retryAt = try? c.decodeIfPresent(String.self, forKey: .retryAt)
        pledgeId = try? c.decodeIfPresent(String.self, forKey: .pledgeId)
        coveredThrough = try? c.decodeIfPresent(String.self, forKey: .coveredThrough)
        untilOn = try? c.decodeIfPresent(String.self, forKey: .untilOn)
        scheduleStopped = try? c.decodeIfPresent(Bool.self, forKey: .scheduleStopped)
        pledgeTitle = try? c.decodeIfPresent(String.self, forKey: .pledgeTitle)
        partial = try? c.decodeIfPresent(Bool.self, forKey: .partial)
        daysAway = try? c.decodeIfPresent(Int.self, forKey: .daysAway)
        dueOn = try? c.decodeIfPresent(String.self, forKey: .dueOn)
        message = try? c.decodeIfPresent(String.self, forKey: .message)
        action = try? c.decodeIfPresent(String.self, forKey: .action)
        resumeOn = try? c.decodeIfPresent(String.self, forKey: .resumeOn)
        note = try? c.decodeIfPresent(String.self, forKey: .note)
        streamId = try? c.decodeIfPresent(String.self, forKey: .streamId)
    }
}

struct NotificationRow: Codable, Sendable, Identifiable {
    let notificationId: String
    let template: String
    let payload: NotifPayload?
    let status: String
    let scheduledFor: String
    let sentAt: String?
    let readAt: String?

    var id: String { notificationId }
    var isUnread: Bool { readAt == nil && status == "sent" }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        notificationId = try c.decode(String.self, forKey: .notificationId)
        template = (try? c.decodeIfPresent(String.self, forKey: .template)) ?? ""
        payload = try? c.decodeIfPresent(NotifPayload.self, forKey: .payload)
        status = (try? c.decodeIfPresent(String.self, forKey: .status)) ?? ""
        scheduledFor = (try? c.decodeIfPresent(String.self, forKey: .scheduledFor)) ?? ""
        sentAt = try? c.decodeIfPresent(String.self, forKey: .sentAt)
        readAt = try? c.decodeIfPresent(String.self, forKey: .readAt)
    }
}
