// Departments — PARTNERS_PROGRAMME §4 / §5 (phase 3). Bodies are snake_cased
// by the client encoder; nil optionals are omitted from the body.
import Foundation

extension MemberAPI {
    /// GET /departments — every department in the member's congregation, with
    /// the member's own status/role and the server's "good fit" verdict.
    static func departments() async throws -> [DepartmentRow] {
        try await APIClient.shared.get("departments", as: Envelope<DepartmentRow>.self).data
    }

    /// GET /me/departments — the same rows, only the ones the member belongs
    /// to (requested or active).
    static func myDepartments() async throws -> [DepartmentRow] {
        try await APIClient.shared.get("me/departments", as: Envelope<DepartmentRow>.self).data
    }

    /// GET /departments/{id} — the row plus posts, needs, members, is_leader.
    static func department(_ id: String) async throws -> DepartmentDetail {
        try await APIClient.shared.get("departments/\(id)", as: DepartmentDetail.self)
    }

    /// POST /departments/{id}/serve → `{status}` (201). "I'd like to serve
    /// here" — the leader/admin approves in the portal (§4).
    @discardableResult
    static func requestToServe(_ id: String) async throws -> String {
        struct Body: Encodable {}
        struct Res: Decodable { let status: String? }
        return try await APIClient.shared.post("departments/\(id)/serve", body: Body(), as: Res.self).status ?? "requested"
    }

    /// DELETE /departments/{id}/serve (204) — leave, or withdraw a request.
    static func leaveDepartment(_ id: String) async throws {
        _ = try await APIClient.shared.delete("departments/\(id)/serve", as: EmptyResponse.self)
    }

    // MARK: Leader only

    /// POST /departments/{id}/posts `{body, image_url?}`.
    static func postDepartmentUpdate(_ id: String, body: String, imageUrl: String?) async throws {
        struct Body: Encodable { let body: String; let imageUrl: String? }
        _ = try await APIClient.shared.post("departments/\(id)/posts",
                                            body: Body(body: body, imageUrl: imageUrl), as: EmptyResponse.self)
    }

    /// DELETE /departments/{id}/posts/{postId}.
    static func deleteDepartmentPost(_ id: String, postId: String) async throws {
        _ = try await APIClient.shared.delete("departments/\(id)/posts/\(postId)", as: EmptyResponse.self)
    }

    /// POST /departments/{id}/needs `{title, why, target_minor, currency,
    /// deadline?}` — submitted as pending; the office approves (§4).
    static func submitDepartmentNeed(_ id: String, title: String, why: String,
                                     targetMinor: Int, currency: String, deadline: String?) async throws {
        struct Body: Encodable {
            let title: String; let why: String; let targetMinor: Int
            let currency: String; let deadline: String?
        }
        _ = try await APIClient.shared.post("departments/\(id)/needs",
                                            body: Body(title: title, why: why, targetMinor: targetMinor,
                                                       currency: currency, deadline: deadline),
                                            as: EmptyResponse.self)
    }
}
