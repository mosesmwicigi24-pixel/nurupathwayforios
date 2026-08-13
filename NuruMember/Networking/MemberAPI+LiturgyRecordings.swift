// Liturgy — pastor's own voice (feat/liturgy-recorded-voice). Admin/SuperAdmin
// only (narrower than the Instructor+ ladder module voice notes use — the
// backend gates these with requireRole("Admin"), not "Instructor+"):
//   • GET    admin/liturgy/recordings        — all 7 bands, clock order,
//     always 7 rows; audioUrl/durationSec/recordedAt null for an
//     unrecorded band (the PERMANENT normal case, not a gap).
//   • POST   admin/liturgy/recordings/{band} — ONE combined multipart
//     request that both uploads the bytes AND attaches them to that band
//     (unlike the two-step me/media/audio → modules/{id}/voice-note flow
//     MemberAPI+Voice.swift uses) — an upsert: calling it again for the
//     same band replaces the recording, server deletes the old file.
//   • DELETE admin/liturgy/recordings/{band} — 200 { deleted: true }, or a
//     404 the caller may treat as "nothing was there to remove".
import Foundation

/// One band's recording status from the admin list — nil fields mean
/// synthesis covers this band right now, never "missing" or an error.
struct LiturgyRecordingStatus: Codable, Sendable {
    var band: String = ""
    var audioUrl: String? = nil
    var durationSec: Int? = nil
    var recordedAt: String? = nil
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        band = (try? c.decodeIfPresent(String.self, forKey: .band)) ?? ""
        audioUrl = try? c.decodeIfPresent(String.self, forKey: .audioUrl)
        durationSec = try? c.decodeIfPresent(Int.self, forKey: .durationSec)
        recordedAt = try? c.decodeIfPresent(String.self, forKey: .recordedAt)
    }
    init(band: String, audioUrl: String? = nil, durationSec: Int? = nil, recordedAt: String? = nil) {
        self.band = band; self.audioUrl = audioUrl; self.durationSec = durationSec; self.recordedAt = recordedAt
    }
}

extension MemberAPI {
    /// GET admin/liturgy/recordings — always 7 rows, clock order
    /// (sunrise…midnight). See LiturgyRecordingRows.build for how the
    /// recorder sheet turns this into a defensive, canonically-ordered list.
    static func liturgyRecordings() async throws -> [LiturgyRecordingStatus] {
        try await APIClient.shared.get("admin/liturgy/recordings", as: Envelope<LiturgyRecordingStatus>.self).data
    }

    /// POST admin/liturgy/recordings/{band} — multipart: `file` (binary
    /// audio) + `duration_sec` (form field, required by the backend). A
    /// SINGLE combined request — never split into an upload-then-attach pair.
    /// Mirrors uploadVoiceAudio's retry-on-401 + Keychain token + VoiceEnv
    /// base-URL resolution exactly, so this diverges from that pattern in
    /// nothing but the endpoint shape.
    static func uploadLiturgyRecording(band: String, m4a data: Data, durationSec: Int) async throws -> (audioUrl: String, durationSec: Int) {
        var (body, http) = try await postLiturgyRecording(band: band, data: data, durationSec: durationSec, token: VoiceEnv.accessToken)

        if http.statusCode == 401 {
            _ = try await MemberAPI.me()
            (body, http) = try await postLiturgyRecording(band: band, data: data, durationSec: durationSec, token: VoiceEnv.accessToken)
        }

        guard (200..<300).contains(http.statusCode) else {
            struct Env: Decodable {
                struct Inner: Decodable { let code: String?; let message: String? }
                let error: Inner?; let message: String?
            }
            let env = try? JSONDecoder().decode(Env.self, from: body)
            let msg = env?.error?.message ?? env?.message ?? "Couldn't save the recording."
            throw APIError.http(status: http.statusCode, code: env?.error?.code, message: msg)
        }

        struct Res: Decodable { let audioUrl: String; let durationSec: Int }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let res = try decoder.decode(Res.self, from: body)
        return (res.audioUrl, res.durationSec)
    }

    /// DELETE admin/liturgy/recordings/{band} — mirrors deleteVoiceNote's
    /// pattern. Propagates a 404 (nothing was recorded for that band) as an
    /// APIError like any other failed delete; the caller decides how to
    /// react (this app never surfaces it as a hard error for an already-
    /// empty band since the UI only offers delete when a recording exists).
    static func deleteLiturgyRecording(band: String) async throws {
        struct Res: Decodable { let deleted: Bool }
        _ = try await APIClient.shared.delete("admin/liturgy/recordings/\(band)", as: Res.self)
    }

    private static func postLiturgyRecording(band: String, data: Data, durationSec: Int, token: String?) async throws -> (Data, HTTPURLResponse) {
        let boundary = "nuru-\(UUID().uuidString)"
        var req = URLRequest(url: VoiceEnv.baseURL.appendingPathComponent("admin/liturgy/recordings/\(band)"))
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var form = Data()
        // duration_sec as a plain form field, ahead of the binary part — same
        // field-then-file ordering uploadChatAttachment uses in MemberAPI.swift.
        form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"duration_sec\"\r\n\r\n\(durationSec)\r\n".utf8))
        form.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"liturgy-\(band).m4a\"\r\nContent-Type: audio/mp4\r\n\r\n".utf8))
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
