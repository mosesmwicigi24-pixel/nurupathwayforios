// "Ask to be connected" to a cell (pathway ed1525d; EXPERIENCE.md §9.2 #12):
// the member says where they live and when they're free, and the request goes
// to their own pastor, in their own pastoral thread. No list of cells or homes
// is shown — the pastor assigns the cell with the tools they already have.
//   GET  /me/cell-connection → { in_cell, request: { requested_at, conversation_id } | null }
//   POST /me/cell-connection   { area 2–80, availability 2–120, note? ≤300, client_mutation_id }
//        → 201 { conversation_id, requested_at }; 409 "You're already in a cell.";
//          422 in the server's own words (a minor; no pastor to receive it).
import Foundation

struct CellConnectionStatus: Decodable, Sendable, Equatable {
    struct Request: Decodable, Sendable, Equatable {
        let requestedAt: String
        let conversationId: String
    }
    let inCell: Bool
    let request: Request?

    private enum CodingKeys: String, CodingKey { case inCell, request }
    init(inCell: Bool, request: Request?) { self.inCell = inCell; self.request = request }
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        inCell = (try? c.decodeIfPresent(Bool.self, forKey: .inCell)) ?? false
        request = try? c.decodeIfPresent(Request.self, forKey: .request)
    }
}

struct CellConnectionResult: Decodable, Sendable, Equatable {
    let conversationId: String
    let requestedAt: String
}

extension MemberAPI {
    static func cellConnection() async throws -> CellConnectionStatus {
        try await APIClient.shared.get("me/cell-connection", as: CellConnectionStatus.self)
    }

    /// One `clientMutationId` per ask, kept across retries, so a retry can't
    /// post twice into the pastor's thread.
    static func askToBeConnected(area: String, availability: String, note: String?,
                                 clientMutationId: String) async throws -> CellConnectionResult {
        struct Body: Encodable {
            let area: String
            let availability: String
            let note: String?
            let clientMutationId: String
        }
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        return try await APIClient.shared.post(
            "me/cell-connection",
            body: Body(area: area.trimmingCharacters(in: .whitespacesAndNewlines),
                       availability: availability.trimmingCharacters(in: .whitespacesAndNewlines),
                       note: (trimmedNote?.isEmpty ?? true) ? nil : trimmedNote,
                       clientMutationId: clientMutationId),
            as: CellConnectionResult.self)
    }
}
