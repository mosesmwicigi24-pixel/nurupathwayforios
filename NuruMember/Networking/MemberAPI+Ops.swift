// Operational endpoints — PayPal capture (money path, §5.6), QR attendance
// check-in (progress module, §3.3) and the screen-dwell telemetry batcher
// (activity module). Same static-func facade pattern as MemberAPI.swift:
// screens call these, never the raw client. Wire JSON is snake_case; the
// shared encoder/decoder converts to/from camelCase.
import Foundation

extension MemberAPI {
    // MARK: Giving — PayPal capture (settles the ledger server-side, §5.6)

    /// POST /giving/paypal/capture — capture an order the member approved in
    /// the PayPal flow. Idempotent server-side: an already-settled order comes
    /// back as { status: "succeeded" } without touching PayPal again. The
    /// polled transaction stays the source of truth for the UI — this call
    /// only nudges settlement along.
    static func capturePayPal(orderId: String) async throws -> PayPalCaptureResult {
        struct Body: Encodable { let orderId: String }
        return try await APIClient.shared.post("giving/paypal/capture",
                                               body: Body(orderId: orderId),
                                               as: PayPalCaptureResult.self)
    }

    // MARK: Events — QR attendance check-in (idempotent on client_scan_id)

    /// POST /events/{id}/attendance — validate the scanned token and record
    /// attendance. Replays of the same client_scan_id and second scans of the
    /// same event are server-side no-ops that return duplicate = true.
    static func checkIn(eventId: String, scanToken: String,
                        clientScanId: String = UUID().uuidString.lowercased()) async throws -> EventCheckInResult {
        struct Body: Encodable { let clientScanId: String; let scanToken: String }
        return try await APIClient.shared.post("events/\(eventId)/attendance",
                                               body: Body(clientScanId: clientScanId, scanToken: scanToken),
                                               as: EventCheckInResult.self)
    }
}

/// POST /giving/paypal/capture → { status } (succeeded | processing | failed).
struct PayPalCaptureResult: Decodable, Sendable {
    let status: String
}

/// POST /events/{id}/attendance → the recorded (or replayed) check-in.
struct EventCheckInResult: Decodable, Sendable {
    let attendanceId: String
    let duplicate: Bool
}

// MARK: - Screen telemetry (POST /me/activity/screens — best-effort, silent)

/// Tiny app-area dwell tracker. `record(screen:)` closes out the previous
/// screen's dwell (duration = time since it was entered) and starts timing the
/// new one; buffered rows flush fire-and-forget when ~10 accumulate or the app
/// backgrounds. Thread-safe by construction: everything runs on the main
/// actor. Analytics must never surface errors or block UI — flush failures
/// drop the batch silently (the server is best-effort about telemetry too).
@MainActor
enum ScreenTracker {
    /// One dwell row, mirroring the activity module's batch schema
    /// (screen ≤40 chars, duration_ms, occurred_at ISO-8601, client_event_id uuid).
    private struct ScreenEvent: Encodable {
        let screen: String
        let durationMs: Int
        let occurredAt: String
        let clientEventId: String
    }

    private static var current: (screen: String, since: Date)?
    private static var buffer: [ScreenEvent] = []
    private static let flushAt = 10
    private static let maxDwellMs = 86_400_000   // the server clamps at 24h
    private static let iso = ISO8601DateFormatter()

    /// The member is now on `screen` (e.g. a tab name). Closes the previous
    /// dwell into the buffer and starts the new one.
    static func record(screen: String) {
        let now = Date()
        closeCurrent(at: now)
        current = (String(screen.prefix(40)), now)
        if buffer.count >= flushAt { flush() }
    }

    /// Call when the app backgrounds: close the open dwell and flush what we have.
    static func appDidEnterBackground() {
        closeCurrent(at: Date())
        flush()
    }

    private static func closeCurrent(at now: Date) {
        guard let c = current else { return }
        current = nil
        let ms = Int((now.timeIntervalSince(c.since) * 1000).rounded())
        guard ms > 0 else { return }
        buffer.append(ScreenEvent(screen: c.screen,
                                  durationMs: min(ms, maxDwellMs),
                                  occurredAt: iso.string(from: now),
                                  clientEventId: UUID().uuidString.lowercased()))
    }

    /// Fire-and-forget batch post. Silent by contract — no thrown errors, no
    /// retries, no UI. The server accepts up to 200 rows per batch.
    private static func flush() {
        guard !buffer.isEmpty else { return }
        let batch = Array(buffer.prefix(200))
        buffer.removeFirst(batch.count)
        Task {
            struct Body: Encodable { let events: [ScreenEvent] }
            _ = try? await APIClient.shared.post("me/activity/screens",
                                                 body: Body(events: batch), as: EmptyResponse.self)
        }
    }
}
