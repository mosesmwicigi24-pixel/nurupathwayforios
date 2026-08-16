// Wave 2 of companion presence — a discipler's voice on the lesson, and the
// quiet knowledge that your cell is studying alongside you.
//   • POST me/media/audio            — multipart m4a upload → { url }
//   • POST modules/{id}/voice-note   — Instructor+ leaves/replaces the note
//   • DELETE modules/{id}/voice-note — author (or Admin+) removes it
//   • GET  community/presence        — cell-mates active this week
import Foundation

struct CommunityPresence: Codable, Sendable {
    let count: Int
    let names: [String]     // up to three first names
    let scope: String       // "cell" | "congregation"
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        count = (try? c.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        names = (try? c.decodeIfPresent([String].self, forKey: .names)) ?? []
        scope = (try? c.decodeIfPresent(String.self, forKey: .scope)) ?? "cell"
    }
}

extension MemberAPI {
    static func communityPresence() async throws -> CommunityPresence {
        try await APIClient.shared.get("community/presence", as: CommunityPresence.self)
    }

    static func setVoiceNote(moduleId: String, audioUrl: String, durationSec: Int) async throws {
        struct Body: Encodable { let audio_url: String; let duration_sec: Int }
        struct Res: Decodable { let noteId: String }
        _ = try await APIClient.shared.post("modules/\(moduleId)/voice-note",
                                            body: Body(audio_url: audioUrl, duration_sec: durationSec),
                                            as: Res.self)
    }

    static func deleteVoiceNote(moduleId: String) async throws {
        struct Res: Decodable { let ok: Bool }
        _ = try await APIClient.shared.delete("modules/\(moduleId)/voice-note", as: Res.self)
    }

    /// Upload a recorded voice note (m4a) to our media store. Mirrors
    /// uploadAvatar — bearer multipart with one 401-refresh retry — and
    /// returns the stored URL to attach via setVoiceNote.
    static func uploadVoiceAudio(m4a data: Data, filename: String = "voice-note.m4a") async throws -> String {
        var (body, http) = try await postAudio(data, filename: filename, token: VoiceEnv.accessToken)

        if http.statusCode == 401 {
            _ = try await MemberAPI.me()
            (body, http) = try await postAudio(data, filename: filename, token: VoiceEnv.accessToken)
        }

        guard (200..<300).contains(http.statusCode) else {
            struct Env: Decodable {
                struct Inner: Decodable { let code: String?; let message: String? }
                let error: Inner?; let message: String?
            }
            let env = try? JSONDecoder().decode(Env.self, from: body)
            let msg = env?.error?.message ?? env?.message ?? "Couldn't upload the voice note."
            throw APIError.http(status: http.statusCode, code: env?.error?.code, message: msg)
        }

        struct Res: Decodable { let url: String }
        return try JSONDecoder().decode(Res.self, from: body).url
    }

    private static func postAudio(_ data: Data, filename: String, token: String?) async throws -> (Data, HTTPURLResponse) {
        let boundary = "nuru-\(UUID().uuidString)"
        var req = URLRequest(url: VoiceEnv.baseURL.appendingPathComponent("me/media/audio"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var form = Data()
        form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
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
}

/// Shared (not fileprivate) so other hand-rolled multipart uploads in this
/// networking layer — e.g. MemberAPI+LiturgyRecordings.swift's admin upload —
/// resolve the base URL and bearer token the exact same way as this one,
/// rather than each hand-rolling its own copy.
enum VoiceEnv {
    static var accessToken: String? { Keychain.get("nuru.member.at") }

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
