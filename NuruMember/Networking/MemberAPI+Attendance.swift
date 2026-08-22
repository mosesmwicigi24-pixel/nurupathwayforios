// Church service attendance (§3.3) — distinct from the event check-in in
// MemberAPI+Ops.swift. Church services are the weekly cadence the attendance
// streak is measured in, and a service check-in registers the member's contact
// details (name, phone, email) alongside the time they attended.
//
// Wire JSON is snake_case; the shared encoder/decoder converts to/from camelCase.
import Foundation

extension MemberAPI {

    /// GET /services/open — services open for check-in right now, soonest first.
    static func openServices() async throws -> [ChurchService] {
        struct Envelope: Decodable { let data: [ChurchService] }
        return try await APIClient.shared.get("services/open", as: Envelope.self).data
    }

    /// POST /services/{id}/attendance — register attendance by QR scan.
    ///
    /// Contact fields are optional: the server falls back to the member's
    /// profile for anything omitted. Idempotent on `clientScanId` and on
    /// (member, service), so a replay or a second scan comes back with
    /// `duplicate = true` rather than an error — pass the SAME clientScanId when
    /// retrying a failed submit so the retry stays a replay.
    static func checkInToService(serviceId: String,
                                 scanToken: String,
                                 clientScanId: String,
                                 fullName: String?,
                                 phoneNumber: String?,
                                 email: String?) async throws -> ServiceCheckInResult {
        struct Body: Encodable {
            let clientScanId: String
            let scanToken: String
            let fullName: String?
            let phoneNumber: String?
            let email: String?
        }
        return try await APIClient.shared.post(
            "services/\(serviceId)/attendance",
            body: Body(clientScanId: clientScanId,
                       scanToken: scanToken,
                       fullName: fullName,
                       phoneNumber: phoneNumber,
                       email: email),
            as: ServiceCheckInResult.self)
    }

    /// GET /me/attendance/streak — current run, longest, breaks and failures.
    static func attendanceStreak() async throws -> AttendanceStreak {
        try await APIClient.shared.get("me/attendance/streak", as: AttendanceStreak.self)
    }

    /// GET /me/attendance — service-by-service history, newest first, misses included.
    static func attendanceHistory(limit: Int = 30) async throws -> [AttendanceHistoryEntry] {
        struct Envelope: Decodable { let data: [AttendanceHistoryEntry] }
        return try await APIClient.shared.get("me/attendance",
                                              query: ["limit": String(limit)],
                                              as: Envelope.self).data
    }
}

// MARK: - Wire models

/// One church service — the cadence slot members scan into.
struct ChurchService: Decodable, Sendable, Identifiable, Hashable {
    let serviceId: String
    let title: String
    let serviceDate: String
    let startsAt: String
    let checkinOpen: Bool
    /// Whether this member is already checked in.
    let attended: Bool
    let attendedAt: String?

    var id: String { serviceId }

    private enum CodingKeys: String, CodingKey {
        case serviceId, title, serviceDate, startsAt, checkinOpen, attended, attendedAt
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        serviceId = (try? c.decodeIfPresent(String.self, forKey: .serviceId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        serviceDate = (try? c.decodeIfPresent(String.self, forKey: .serviceDate)) ?? ""
        startsAt = (try? c.decodeIfPresent(String.self, forKey: .startsAt)) ?? ""
        checkinOpen = (try? c.decodeIfPresent(Bool.self, forKey: .checkinOpen)) ?? false
        attended = (try? c.decodeIfPresent(Bool.self, forKey: .attended)) ?? false
        attendedAt = try? c.decodeIfPresent(String.self, forKey: .attendedAt)
    }
}

/// How a streak stands. `new` = never attended, `active` = attended the latest
/// service, `at_risk` = missed one, `broken` = missed two or more in a row.
enum AttendanceStreakStatus: String, Decodable, Sendable {
    case new
    case active
    case atRisk = "at_risk"
    case broken
}

/// Attendance measured in SERVICES, not days. The window is anchored at the
/// member's first-ever check-in, so services held before they joined are not
/// counted against them.
struct AttendanceStreak: Decodable, Sendable, Hashable {
    /// Consecutive services attended, counting back from the most recent.
    let currentStreak: Int
    let longestStreak: Int
    let totalAttended: Int
    /// "Failures" — eligible services missed since the first check-in.
    let totalMissed: Int
    /// "Breaks" — one per interruption, so two misses in a row is 1 break, 2 failures.
    let breaks: Int
    /// Consecutive services missed right now; 0 while the streak is alive.
    let currentMissRun: Int
    let lastAttendedAt: String?
    let lastServiceDate: String?
    let status: AttendanceStreakStatus

    private enum CodingKeys: String, CodingKey {
        case currentStreak, longestStreak, totalAttended, totalMissed, breaks
        case currentMissRun, lastAttendedAt, lastServiceDate, status
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        currentStreak = (try? c.decodeIfPresent(Int.self, forKey: .currentStreak)) ?? 0
        longestStreak = (try? c.decodeIfPresent(Int.self, forKey: .longestStreak)) ?? 0
        totalAttended = (try? c.decodeIfPresent(Int.self, forKey: .totalAttended)) ?? 0
        totalMissed = (try? c.decodeIfPresent(Int.self, forKey: .totalMissed)) ?? 0
        breaks = (try? c.decodeIfPresent(Int.self, forKey: .breaks)) ?? 0
        currentMissRun = (try? c.decodeIfPresent(Int.self, forKey: .currentMissRun)) ?? 0
        lastAttendedAt = try? c.decodeIfPresent(String.self, forKey: .lastAttendedAt)
        lastServiceDate = try? c.decodeIfPresent(String.self, forKey: .lastServiceDate)
        status = (try? c.decodeIfPresent(AttendanceStreakStatus.self, forKey: .status)) ?? .new
    }

    /// Plain-language reading of the streak — the numbers alone don't pastor anyone.
    var note: String {
        switch status {
        case .new:
            return "This is your first check-in. Your streak starts here."
        case .active:
            return currentStreak == 1
                ? "You're on the board — one service in a row."
                : "You've been here \(currentStreak) services in a row."
        case .atRisk:
            return "You missed the last service. Come this week and your streak restarts."
        case .broken:
            return "You've missed \(currentMissRun) services in a row. Today is a good day to come back."
        }
    }
}

/// POST /services/{id}/attendance → the recorded (or replayed) check-in.
struct ServiceCheckInResult: Decodable, Sendable {
    let attendanceId: String
    let duplicate: Bool
    let serviceTitle: String
    let attendedAt: String
    let fullName: String
    let phoneNumber: String
    let email: String?
    let streak: AttendanceStreak

    private enum CodingKeys: String, CodingKey {
        case attendanceId, duplicate, serviceTitle, attendedAt, fullName, phoneNumber, email, streak
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        attendanceId = (try? c.decodeIfPresent(String.self, forKey: .attendanceId)) ?? ""
        duplicate = (try? c.decodeIfPresent(Bool.self, forKey: .duplicate)) ?? false
        serviceTitle = (try? c.decodeIfPresent(String.self, forKey: .serviceTitle)) ?? ""
        attendedAt = (try? c.decodeIfPresent(String.self, forKey: .attendedAt)) ?? ""
        fullName = (try? c.decodeIfPresent(String.self, forKey: .fullName)) ?? ""
        phoneNumber = (try? c.decodeIfPresent(String.self, forKey: .phoneNumber)) ?? ""
        email = try? c.decodeIfPresent(String.self, forKey: .email)
        streak = try c.decode(AttendanceStreak.self, forKey: .streak)
    }
}

/// One service in the member's history — attended, or a visible miss.
struct AttendanceHistoryEntry: Decodable, Sendable, Identifiable, Hashable {
    let serviceId: String
    let title: String
    let serviceDate: String
    let startsAt: String
    let attended: Bool
    let attendedAt: String?

    var id: String { serviceId }

    private enum CodingKeys: String, CodingKey {
        case serviceId, title, serviceDate, startsAt, attended, attendedAt
    }

    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        serviceId = (try? c.decodeIfPresent(String.self, forKey: .serviceId)) ?? ""
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? ""
        serviceDate = (try? c.decodeIfPresent(String.self, forKey: .serviceDate)) ?? ""
        startsAt = (try? c.decodeIfPresent(String.self, forKey: .startsAt)) ?? ""
        attended = (try? c.decodeIfPresent(Bool.self, forKey: .attended)) ?? false
        attendedAt = try? c.decodeIfPresent(String.self, forKey: .attendedAt)
    }
}

// MARK: - QR payload

/// What a scanned church-service QR carries.
struct ServiceScan: Equatable, Sendable {
    let serviceId: String
    let scanToken: String
}

/// What the scanner recognized. The projected sanctuary code and a printed
/// per-service link identify a service directly; the standing door poster
/// (`/jc/<code>`, one code forever per congregation) names only the
/// congregation — the SERVER decides which service it means at scan time,
/// via `resolveStandingCode` below.
enum ScannedServiceCode: Equatable, Sendable {
    case service(ServiceScan)
    case standingCode(String)
}

/// Parse every form a Nuru service QR ships in. Returns nil for any other QR
/// so the scanner ignores unrelated codes instead of posting junk to the
/// server. Mirrors `parseServiceQrPayload` in the backend attendance module —
/// the legacy `nuru-service:` form MUST keep working: it is what the portal
/// still projects on the sanctuary screen.
func parseServiceQR(_ raw: String) -> ScannedServiceCode? {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)

    // Legacy projected form: nuru-service:<service_id>:<token>
    let parts = text.components(separatedBy: ":")
    if parts.count == 3, parts[0] == "nuru-service", !parts[1].isEmpty, !parts[2].isEmpty {
        return .service(ServiceScan(serviceId: parts[1], scanToken: parts[2]))
    }

    // URL forms — accepted from any host so a staging poster scans in a dev
    // build; the payload alone carries everything the flow needs.
    guard let url = URL(string: text),
          let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https"
    else { return nil }
    let seg = url.path.split(separator: "/").map(String.init)

    // Per-service link: /j/<service_id>/<token>
    if seg.count == 3, seg[0] == "j", !seg[1].isEmpty, !seg[2].isEmpty {
        return .service(ServiceScan(serviceId: seg[1], scanToken: seg[2]))
    }
    // Standing poster: /jc/<code> (codes are 64 hex; 16 is the server's floor)
    if seg.count == 2, seg[0] == "jc", seg[1].count >= 16 {
        return .standingCode(seg[1])
    }
    return nil
}

/// What the standing poster means right now (GET /join/congregation/{code},
/// public). Open → the day's service with its scan token, ready for the
/// normal check-in flow. Closed → when to come back.
struct StandingResolution: Decodable, Sendable {
    struct OpenService: Decodable, Sendable {
        let serviceId: String
        let title: String
        let startsAt: String
        let scanToken: String
    }
    struct NextService: Decodable, Sendable {
        let title: String
        let startsAt: String
    }
    let congregation: String
    let open: Bool
    let service: OpenService?
    let next: NextService?
}

extension MemberAPI {
    static func resolveStandingCode(_ code: String) async throws -> StandingResolution {
        try await APIClient.shared.get("join/congregation/\(code)", as: StandingResolution.self)
    }
}
