// Wave 3 — footprints on the trail + Your Walk.
//   • GET modules/{id}/footprints — cell-mates who already completed this
//     module (faces + when), so nobody reads alone.
//   • GET me/walk — the member's whole journey as one descending thread of
//     real events (began, modules, reflections, levels, certificates,
//     verses, plans, badges). Counted server-side, never guessed.
import Foundation

struct Footprint: Codable, Sendable {
    let firstName: String
    let avatarUrl: String?
    let completedAt: String
}

struct FootprintsRes: Codable, Sendable {
    let count: Int
    let scope: String            // "cell" | "congregation"
    let footprints: [Footprint]
}

struct WalkEvent: Codable, Sendable, Identifiable {
    let kind: String             // began|module|reflection|level|certificate|verse|plan|badge
    let title: String
    let detail: String?
    let quote: String?
    let occurredAt: String

    var id: String { "\(kind)-\(title)-\(occurredAt)" }

    /// "2 Jul 2026" from the ISO/Postgres timestamp.
    var dateLine: String {
        let m = occurredAt.prefix(10).split(separator: "-")
        guard m.count == 3, let mo = Int(m[1]), let d = Int(m[2]), (1...12).contains(mo) else { return "" }
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(d) \(months[mo - 1]) \(m[0])"
    }
}

struct WalkRes: Codable, Sendable { let data: [WalkEvent] }

extension MemberAPI {
    static func footprints(moduleId: String) async throws -> FootprintsRes {
        try await APIClient.shared.get("modules/\(moduleId)/footprints", as: FootprintsRes.self)
    }

    static func myWalk() async throws -> [WalkEvent] {
        try await APIClient.shared.get("me/walk", as: WalkRes.self).data
    }
}
