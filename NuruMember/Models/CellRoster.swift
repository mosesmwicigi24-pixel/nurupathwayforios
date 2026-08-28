// The member's own cell roster — GET /me/cell/members. ONE payload carrying
// TWO truths, and the split is the SERVER's (§5.4): everyone receives the
// PEOPLE (name, first name, face, who leads, which row is mine); only the
// cell's shepherd — its leader, a leader_assignment holder, or Admin+ —
// ALSO receives each member's engagement score, risk band, attendance over
// the cell's last ≤8 real gatherings, and last-seen.
//
// For an ordinary member the shepherd fields are ABSENT from the JSON, not
// null-and-hidden, so they decode here as plain optionals and the roster
// screen simply has nothing to draw. `canShepherd` says which view was
// served. A score is NEVER invented client-side: nil stays nil and the row
// prints an em dash. Decoded with the APIClient's `.convertFromSnakeCase`,
// so every property is camelCase; anything the wire may omit is a tolerant
// optional so a sparse payload still decodes.
import Foundation

/// The whole GET /me/cell/members payload. `cell` is null (with an empty
/// list) for a member no leader has placed in a cell yet.
struct CellRoster: Codable, Sendable {
    /// Which cell this roster belongs to.
    struct Cell: Codable, Sendable {
        let cellGroupId: String
        let name: String
    }
    let cell: Cell?
    /// True when the caller shepherds this cell — the ONLY case in which the
    /// members below carry score / band / attendance / last-seen.
    let canShepherd: Bool
    /// Server-ordered leader-first; the shepherd view re-sorts by standing.
    let members: [CellRosterMember]
}

/// One person on the roster. The four shepherd-only facts are optional twice
/// over: absent for an ordinary member, and individually nullable even for a
/// shepherd (a member with no engagement row yet has no score, and a cell
/// that has never met has no attendance).
struct CellRosterMember: Codable, Sendable, Identifiable, Hashable {
    /// Presence at the cell's last `of` real gatherings — counted, never
    /// rendered as a fabricated percentage. Null (not 0-of-0) before the
    /// cell has met at all.
    struct Attendance: Codable, Sendable, Hashable {
        let present: Int
        let of: Int
    }

    let userId: String
    let fullName: String
    let firstName: String
    let avatarUrl: String?
    let isLeader: Bool
    let isMe: Bool

    // MARK: shepherd-only (absent unless CellRoster.canShepherd)

    /// Engagement score 0–100. Nil = not computed yet — show "—", never a 0.
    let score: Int?
    /// thriving | steady | watch | at_risk — nil until engagement is computed.
    let band: String?
    /// Presence over the cell's recent gatherings; nil when it has never met.
    let attendance: Attendance?
    /// Days since this member last did anything; nil = no activity on record.
    let lastSeenDays: Int?

    var id: String { userId }
    static func == (a: CellRosterMember, b: CellRosterMember) -> Bool { a.userId == b.userId }
    func hash(into h: inout Hasher) { h.combine(userId) }
}

// Tolerant decoding lives in extensions so the synthesized memberwise inits
// stay available for the sparse-payload fallbacks and for tests/previews.

extension CellRoster {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cell = try? c.decodeIfPresent(Cell.self, forKey: .cell)
        canShepherd = (try? c.decodeIfPresent(Bool.self, forKey: .canShepherd)) ?? false
        members = (try? c.decodeIfPresent([CellRosterMember].self, forKey: .members)) ?? []
    }
}

extension CellRoster.Cell {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        cellGroupId = (try? c.decodeIfPresent(String.self, forKey: .cellGroupId)) ?? ""
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? ""
    }
}

extension CellRosterMember {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        userId = (try? c.decodeIfPresent(String.self, forKey: .userId)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        // The server always sends first_name; fall back to the first word of
        // the full name rather than leaving a "Message" label with a blank in it.
        firstName = (try? c.decodeIfPresent(String.self, forKey: .firstName))
            ?? fullName.split(separator: " ").first.map(String.init)
            ?? fullName
        avatarUrl = try? c.decodeIfPresent(String.self, forKey: .avatarUrl)
        isLeader = (try? c.decodeIfPresent(Bool.self, forKey: .isLeader)) ?? false
        isMe = (try? c.decodeIfPresent(Bool.self, forKey: .isMe)) ?? false
        score = try? c.decodeIfPresent(Int.self, forKey: .score)
        band = try? c.decodeIfPresent(String.self, forKey: .band)
        attendance = try? c.decodeIfPresent(Attendance.self, forKey: .attendance)
        lastSeenDays = try? c.decodeIfPresent(Int.self, forKey: .lastSeenDays)
    }
}

extension CellRosterMember.Attendance {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        present = (try? c.decodeIfPresent(Int.self, forKey: .present)) ?? 0
        of = (try? c.decodeIfPresent(Int.self, forKey: .of)) ?? 0
    }
}
