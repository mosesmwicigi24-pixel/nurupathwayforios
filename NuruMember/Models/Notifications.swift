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
}
