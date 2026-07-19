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
