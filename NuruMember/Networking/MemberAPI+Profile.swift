// Profile-domain endpoints — server-backed notification preferences, avatar
// upload, real logout, certificate PDF download, and the per-pillar growth-score
// drill-downs. Wire contracts verified against the backend module source:
//   • identity/index.ts   POST /auth/logout { refresh_token } → 204
//   • media/index.ts      POST /me/avatar   multipart field "file" → 201 { avatar_url }
//   • scores/service.ts   GET  /me/scores/{pillar} → ScoreBreakdown
// JSON is snake_case on the wire; APIClient's coders convert to/from camelCase.
import Foundation

// MARK: - Models

/// GET/PUT /me/notification-preferences — all three channels, always together.
struct NotificationPreferences: Codable, Sendable {
    var pushEnabled: Bool
    var emailEnabled: Bool
    var smsEnabled: Bool
}

/// One growth-score pillar (the five member scores of the scores module).
enum ScorePillar: String, CaseIterable, Identifiable, Sendable {
    case word, prayer, habits, curriculum, attendance
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .word: return "Word"
        case .prayer: return "Prayer"
        case .habits: return "Habits"
        case .curriculum: return "Curriculum"
        case .attendance: return "Attendance"
        }
    }

    var icon: Lucide {
        switch self {
        case .word: return .bookOpen
        case .prayer: return .heart
        case .habits: return .flame
        case .curriculum: return .graduationCap
        case .attendance: return .users
        }
    }
}

/// GET /me/scores/{pillar} — the server-authoritative breakdown (§1.1): the 0–100
/// composite, its pastoral band, each weighted component (0–100), and the raw
/// counts behind them ("detail") for transparency. Dictionary keys pass through
/// `.convertFromSnakeCase` too (e.g. `verses_engaged` → `versesEngaged`).
struct ScoreBreakdown: Decodable, Sendable {
    let score: Int
    let band: String
    let components: [String: Double]
    let detail: [String: Double]
}

// MARK: - Endpoints

extension MemberAPI {
    // MARK: Notification preferences (server-backed; @AppStorage is the offline cache)

    /// GET /me/notification-preferences.
    static func notificationPreferences() async throws -> NotificationPreferences {
        try await APIClient.shared.get("me/notification-preferences", as: NotificationPreferences.self)
    }

    /// PUT /me/notification-preferences — all three channels are required.
    static func updateNotificationPreferences(push: Bool, email: Bool, sms: Bool) async throws {
        _ = try await APIClient.shared.put(
            "me/notification-preferences",
            body: NotificationPreferences(pushEnabled: push, emailEnabled: email, smsEnabled: sms),
            as: EmptyResponse.self)
    }

    // MARK: Logout (POST /auth/logout — revokes the refresh-token family)

    /// Best-effort server-side logout. Captures the refresh token SYNCHRONOUSLY
    /// (call this before clearing the local session) and fires the revoke in a
    /// detached task, so local sign-out never blocks on — and never fails
    /// because of — the network. The endpoint needs no bearer auth: it takes
    /// the refresh token itself (identity/index.ts ~line 100).
    static func revokeSessionBestEffort() {
        guard let rt = ProfileEnv.refreshToken else { return }
        Task.detached(priority: .utility) {
            struct Body: Encodable { let refreshToken: String }   // → refresh_token
            _ = try? await APIClient.shared.post("auth/logout", body: Body(refreshToken: rt), as: EmptyResponse.self)
        }
    }

    // MARK: Avatar (POST /me/avatar — multipart, field "file", images only, ≤5 MB)

    /// Upload the member's profile photo. Bytes land on the backend's own disk
    /// (unlike chat attachments, which go straight to Cloudinary), so this is a
    /// bearer-authenticated multipart POST to our API. Returns the new avatar URL.
    static func uploadAvatar(jpeg data: Data, filename: String = "avatar.jpg") async throws -> String {
        var (body, http) = try await postAvatar(data, filename: filename, token: ProfileEnv.accessToken)

        // Expired access token → any authenticated APIClient call runs the
        // single-flight refresh (§5.3) and rewrites the Keychain copy; retry once.
        if http.statusCode == 401 {
            _ = try await MemberAPI.me()
            (body, http) = try await postAvatar(data, filename: filename, token: ProfileEnv.accessToken)
        }

        guard (200..<300).contains(http.statusCode) else {
            struct Env: Decodable {
                struct Inner: Decodable { let code: String?; let message: String? }
                let error: Inner?; let message: String?
            }
            let env = try? JSONDecoder().decode(Env.self, from: body)
            let msg = env?.error?.message ?? env?.message ?? "Couldn't upload the photo."
            throw APIError.http(status: http.statusCode, code: env?.error?.code, message: msg)
        }

        struct Res: Decodable { let avatarUrl: String }           // ← avatar_url
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(Res.self, from: body).avatarUrl
    }

    private static func postAvatar(_ data: Data, filename: String, token: String?) async throws -> (Data, HTTPURLResponse) {
        let boundary = "nuru-\(UUID().uuidString)"
        var req = URLRequest(url: ProfileEnv.baseURL.appendingPathComponent("me/avatar"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var form = Data()
        form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: image/jpeg\r\n\r\n".utf8))
        form.append(data)
        form.append(Data("\r\n--\(boundary)--\r\n".utf8))

        do {
            let (res, resp) = try await URLSession.shared.upload(for: req, from: form)
            guard let http = resp as? HTTPURLResponse else { throw APIError.transport("No HTTP response.") }
            return (res, http)
        } catch let urlErr as URLError {
            if urlErr.code == .notConnectedToInternet || urlErr.code == .timedOut || urlErr.code == .cannotConnectToHost {
                throw APIError.offline
            }
            throw APIError.transport(urlErr.localizedDescription)
        }
    }

    // MARK: Certificate PDF (GET /media/certificates/{code} — streams with auth)

    /// Fetch a certificate's PDF bytes. Rides APIClient's RawJSON passthrough,
    /// so the bearer header + single-flight 401 refresh come for free and the
    /// bytes are returned untouched (no Codable decoding).
    static func downloadCertificatePdf(code: String) async throws -> Data {
        try await APIClient.shared.get("media/certificates/\(code)", as: RawJSON.self).data
    }

    // MARK: Score drill-downs (GET /me/scores/{pillar})

    /// The full breakdown behind one growth score — real data only, rendered as-is.
    static func scoreDetail(_ pillar: ScorePillar) async throws -> ScoreBreakdown {
        try await APIClient.shared.get("me/scores/\(pillar.rawValue)", as: ScoreBreakdown.self)
    }
}

// MARK: - Environment mirror

/// The two things APIClient keeps private that the multipart/logout paths need:
/// the session tokens (same Keychain keys APIClient reads/writes) and the base
/// URL (same resolution order). KEEP IN SYNC with APIClient.swift.
private enum ProfileEnv {
    static var accessToken: String? { Keychain.get("nuru.member.at") }
    static var refreshToken: String? { Keychain.get("nuru.member.rt") }

    static var baseURL: URL {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["NURU_API_URL"]?.trimmingCharacters(in: .whitespaces),
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        #if targetEnvironment(simulator) && DEBUG
        return URL(string: "http://localhost:8080/v1")!
        #else
        return URL(string: "https://pathway.nuruplace.org/v1")!
        #endif
    }
}
