// URLSession-based API client for the native member app. The native counterpart
// of packages/mobile/src/api/client.ts: it injects the gateway JWT (§1.3),
// targets the versioned API surface (§3.1), and silently rotates the access
// token once on a 401 via the stored refresh token.
//
// SINGLE-FLIGHT refresh (§5.3): the Home screen fires many requests at once, so
// an expired access token produces a burst of simultaneous 401s. Refresh tokens
// are one-time-use + rotated; reusing a burned token trips the backend's
// reuse-detection and revokes the WHOLE family. So every concurrent 401 must
// share ONE refresh — the first 401 spends the token, the rest await it.
import Foundation

enum APIError: LocalizedError {
    case http(status: Int, code: String?, message: String, details: ErrorDetails? = nil)
    case decoding(String)
    case transport(String)
    case offline
    case unauthorized

    /// The server is ASKING for the password, not refusing (§5.3 step-up). A
    /// FORBIDDEN_SCOPE alone cannot say this — only details.password_required —
    /// so the answerable case gets a name of its own rather than a string test
    /// scattered across call sites.
    var needsPasswordConfirm: Bool {
        if case let .http(_, _, _, details) = self { return details?.passwordRequired == true }
        return false
    }

    var errorDescription: String? {
        switch self {
        case .http(_, _, let m, _): return m
        case .decoding(let m): return "Couldn't read the server response. \(m)"
        case .transport(let m): return m
        case .offline: return "You appear to be offline."
        case .unauthorized: return "Your session has expired. Please sign in again."
        }
    }

    /// True when the request never reached a server answer (offline / unreachable),
    /// as opposed to a 4xx/5xx the server actually returned. Mirrors
    /// offlineWrite.ts `isNetworkError` — drives the write-through offline queue.
    var isNetwork: Bool {
        switch self {
        case .offline, .transport: return true
        default: return false
        }
    }
}

/// Backend error envelope: { "error": { "code", "message", "details" } } or
/// { "message" }.
///
/// `details` matters because the code alone is not always enough to know what to
/// do: a step-up demand and an ordinary "you may not" are BOTH FORBIDDEN_SCOPE.
/// Only `details.password_required` tells them apart — one is answerable, the
/// other is a wall.
private struct ErrorEnvelope: Decodable {
    struct Inner: Decodable {
        let code: String?
        let message: String?
        let details: ErrorDetails?
    }
    let error: Inner?
    let message: String?
    var code: String? { error?.code }
    var text: String? { error?.message ?? message }
    var details: ErrorDetails? { error?.details }
}

/// The bits of an error's `details` the app acts on. Everything is optional —
/// an unknown detail must never fail the decode of the error itself.
struct ErrorDetails: Decodable, Sendable {
    /// The server is asking the person to confirm their password (§5.3 step-up),
    /// not refusing them. Answerable — prompt, then retry.
    let passwordRequired: Bool?
    /// The server is asking for a second factor.
    let mfaRequired: Bool?
    /// How fresh a confirmation must be, in seconds.
    let maxAgeSeconds: Int?
}

actor APIClient {
    static let shared = APIClient()

    private let baseURL: URL
    private let atKey = "nuru.member.at"
    private let rtKey = "nuru.member.rt"

    private var accessToken: String?
    private var refreshToken: String?

    /// In-flight refresh, shared by every concurrent 401 (single-flight).
    private var refreshTask: Task<Bool, Never>?

    /// Called when the refresh token itself is dead — the app returns to /login.
    private var onSessionExpired: (@Sendable () -> Void)?

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    /// Dedicated session (not `URLSession.shared`): bounded timeouts, fail-fast
    /// when offline (the app must fall through to its cache immediately, §1.7),
    /// and no cookie/credential persistence — auth is bearer-JWT only (§1.3).
    private static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30    // Argon2id endpoints can take seconds (§5.5)
        c.timeoutIntervalForResource = 120  // hard ceiling for one whole transfer
        c.waitsForConnectivity = false      // offline-first: surface .offline now, don't wait
        c.httpShouldSetCookies = false      // bearer tokens only — never send cookies
        c.httpCookieAcceptPolicy = .never   // …and never store any the server sets
        c.httpCookieStorage = nil
        c.urlCredentialStorage = nil        // no URL-auth credentials to persist
        c.urlCache = URLCache.shared        // the disk cache sized by configureNuruCaches()
        return URLSession(configuration: c)
    }()

    init() {
        baseURL = Self.resolveBaseURL()
        accessToken = Keychain.get(atKey)
        refreshToken = Keychain.get(rtKey)
    }

    /// API base-URL resolution mirroring config.ts:
    ///   1. NURU_API_URL env override (used by smoke-test scripts / device dev).
    ///   2. Debug builds ON THE SIMULATOR → the dev machine on localhost.
    ///   3. Everything else (a physical device, any Release build) → production.
    ///
    /// A physical device can't reach the Mac's `localhost`, and there is no Metro
    /// packager host to borrow (unlike the RN app), so device builds default to
    /// prod over HTTPS — point at a LAN backend with the NURU_API_URL scheme env
    /// var if you need local dev on a real phone.
    private static let prodBase = URL(string: "https://pathway.nuruplace.org/v1")!

    private static func resolveBaseURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["NURU_API_URL"]?.trimmingCharacters(in: .whitespaces),
           !raw.isEmpty, let url = URL(string: raw) {
            return url
        }
        #if targetEnvironment(simulator) && DEBUG
        return URL(string: "http://localhost:8080/v1")!
        #else
        return prodBase
        #endif
    }

    // MARK: Session

    var hasSession: Bool { accessToken != nil }

    func setOnSessionExpired(_ fn: @escaping @Sendable () -> Void) { onSessionExpired = fn }

    func setSession(access: String?, refresh: String?) {
        accessToken = access
        refreshToken = refresh
        Keychain.set(access, for: atKey)
        Keychain.set(refresh, for: rtKey)
    }

    /// Swap ONLY the access token, keeping the refresh token exactly where it is.
    ///
    /// For /auth/confirm-password, which re-mints the access token with a fresh
    /// pwd_at and returns no refresh token of its own (§5.3 step-up). Going
    /// through setSession(access:refresh:nil) would wipe the refresh token and
    /// silently end the session at the next expiry — the same rotation that trips
    /// reuse-detection. Hence a method rather than a call site remembering.
    func setAccessToken(_ access: String) {
        accessToken = access
        Keychain.set(access, for: atKey)
    }

    func clearSession() { setSession(access: nil, refresh: nil) }

    // MARK: Requests

    func get<T: Decodable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T {
        try await send(path, method: "GET", query: query, body: Optional<Int>.none, as: T.self)
    }

    func post<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await send(path, method: "POST", body: body, as: T.self)
    }

    func put<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await send(path, method: "PUT", body: body, as: T.self)
    }

    func patch<B: Encodable, T: Decodable>(_ path: String, body: B, as type: T.Type) async throws -> T {
        try await send(path, method: "PATCH", body: body, as: T.self)
    }

    func delete<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await send(path, method: "DELETE", body: Optional<Int>.none, as: T.self)
    }

    /// POST with no request body (action endpoints).
    func postEmpty<T: Decodable>(_ path: String, as type: T.Type) async throws -> T {
        try await send(path, method: "POST", body: Optional<Int>.none, as: T.self)
    }

    /// Raw JSON data for a path (used where the response shape is decoded by the caller).
    func send<B: Encodable, T: Decodable>(
        _ path: String, method: String, query: [String: String] = [:],
        body: B?, as type: T.Type, isRetry: Bool = false
    ) async throws -> T {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(trimmed), resolvingAgainstBaseURL: false) else {
            throw APIError.transport("Couldn't form the request URL.")
        }
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError.transport("Couldn't form the request URL.") }
        var req = URLRequest(url: url)
        req.httpMethod = method
        // 30s, not 15s: password endpoints run Argon2id, which can take several
        // seconds on a small/cold server (mirrors client.ts).
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: req)
        } catch let urlErr as URLError {
            if urlErr.code == .notConnectedToInternet || urlErr.code == .timedOut || urlErr.code == .cannotConnectToHost {
                throw APIError.offline
            }
            throw APIError.transport(urlErr.localizedDescription)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response.")
        }

        if http.statusCode == 401, !isRetry, refreshToken != nil {
            if await refreshSession() {
                return try await send(path, method: method, query: query, body: body, as: T.self, isRetry: true)
            } else {
                onSessionExpired?()
                throw APIError.unauthorized
            }
        }

        guard (200..<300).contains(http.statusCode) else {
            let env = try? decoder.decode(ErrorEnvelope.self, from: data)
            let msg = env?.text ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode)
            throw APIError.http(status: http.statusCode, code: env?.code, message: msg, details: env?.details)
        }

        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        // Raw passthrough: the caller decodes the bytes itself (used by the sync
        // engine, which must read pull rows WITHOUT snake_case key conversion).
        if T.self == RawJSON.self { return RawJSON(data: data) as! T }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// POST returning the raw response bytes (no Codable key conversion).
    func postRaw<B: Encodable>(_ path: String, body: B) async throws -> Data {
        try await send(path, method: "POST", body: body, as: RawJSON.self).data
    }

    // MARK: Login (single endpoint that may return a 2FA challenge)

    /// POST /auth/login → either a full Session or a 2FA challenge.
    func login(email: String, password: String) async throws -> LoginResult {
        struct Body: Encodable { let email: String; let password: String }
        let trimmed = "auth/login"
        var req = URLRequest(url: baseURL.appendingPathComponent(trimmed))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try encoder.encode(Body(email: email, password: password))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: req)
        } catch let urlErr as URLError {
            if urlErr.code == .notConnectedToInternet || urlErr.code == .timedOut || urlErr.code == .cannotConnectToHost {
                throw APIError.offline
            }
            throw APIError.transport(urlErr.localizedDescription)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            let env = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw APIError.http(status: http.statusCode, code: env?.code,
                                message: env?.text ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode))
        }
        if let challenge = try? decoder.decode(MfaChallenge.self, from: data), challenge.mfaRequired {
            return .mfaChallenge(challenge)
        }
        let session = try decoder.decode(Session.self, from: data)
        setSession(access: session.accessToken, refresh: session.refreshToken)
        return .session(session)
    }

    /// POST /auth/confirm-password → re-mint MY access token with a fresh pwd_at
    /// (§5.3 step-up), so the routes that guard the church's private words will
    /// open for the next 15 minutes.
    ///
    /// Deliberately bespoke rather than going through send(), for one reason: a
    /// wrong password answers 401, and send() treats a 401 as an expired session
    /// — it would refresh and REPLAY the wrong password, spending two attempts of
    /// the login lockout for one typo. This must reach the caller untouched.
    ///
    /// Only the access token is replaced; the refresh token stays exactly as it
    /// is (this endpoint returns none).
    func confirmPassword(_ password: String) async throws {
        struct Body: Encodable { let password: String }
        struct Res: Decodable { let accessToken: String }
        var req = URLRequest(url: baseURL.appendingPathComponent("auth/confirm-password"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = accessToken { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = try encoder.encode(Body(password: password))

        let data: Data, response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: req)
        } catch let urlErr as URLError {
            if urlErr.code == .notConnectedToInternet || urlErr.code == .timedOut || urlErr.code == .cannotConnectToHost {
                throw APIError.offline
            }
            throw APIError.transport(urlErr.localizedDescription)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.transport("No HTTP response.") }
        guard (200..<300).contains(http.statusCode) else {
            let env = try? decoder.decode(ErrorEnvelope.self, from: data)
            throw APIError.http(status: http.statusCode, code: env?.code,
                                message: env?.text ?? HTTPURLResponse.localizedString(forStatusCode: http.statusCode),
                                details: env?.details)
        }
        setAccessToken(try decoder.decode(Res.self, from: data).accessToken)
    }

    /// POST /auth/register → a new account + session.
    func register(fullName: String, email: String, password: String) async throws -> Session {
        struct Body: Encodable { let fullName: String; let email: String; let password: String }
        let session = try await send("auth/register", method: "POST",
                                     body: Body(fullName: fullName, email: email, password: password), as: Session.self)
        setSession(access: session.accessToken, refresh: session.refreshToken)
        return session
    }

    /// Second step of a 2FA login: exchange the challenge token + code for a session.
    func completeMfa(mfaToken: String, code: String) async throws -> Session {
        struct Body: Encodable { let mfaToken: String; let code: String }
        let session = try await send("auth/login/mfa", method: "POST", body: Body(mfaToken: mfaToken, code: code), as: Session.self)
        setSession(access: session.accessToken, refresh: session.refreshToken)
        return session
    }

    // MARK: Refresh

    /// Single-flight refresh: the first caller starts the rotation; concurrent
    /// callers await the same Task and never spend a second (burned) token.
    private func refreshSession() async -> Bool {
        if let task = refreshTask { return await task.value }
        let task = Task<Bool, Never> { [self] in await self.performRefresh() }
        refreshTask = task
        let ok = await task.value
        refreshTask = nil
        return ok
    }

    private func performRefresh() async -> Bool {
        guard let rt = refreshToken else { return false }
        struct Body: Encodable { let refreshToken: String }
        var req = URLRequest(url: baseURL.appendingPathComponent("auth/token/refresh"))
        req.httpMethod = "POST"
        req.timeoutInterval = 30   // bound the boot refresh so it can't stall the app
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? encoder.encode(Body(refreshToken: rt))
        guard let (data, resp) = try? await Self.session.data(for: req),
              let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let session = try? decoder.decode(Session.self, from: data) else {
            clearSession()
            return false
        }
        setSession(access: session.accessToken, refresh: session.refreshToken)
        return true
    }
}

/// Sentinel for endpoints with no/ignored response body (204 actions).
struct EmptyResponse: Decodable {}

/// Marker for a raw-bytes response; `APIClient.send` special-cases it and skips
/// Codable decoding, so `data` holds the untouched server JSON.
struct RawJSON: Decodable {
    let data: Data
    init(data: Data) { self.data = data }
    init(from decoder: Decoder) throws { self.data = Data() } // unused; send() special-cases
}
