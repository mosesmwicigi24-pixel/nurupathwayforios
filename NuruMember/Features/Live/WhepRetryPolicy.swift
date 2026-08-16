// Nuru Live — WHEP subscribe retry policy (2026-07-31 production fix).
//
// PROVEN FROM PRODUCTION MediaMTX LOGS: the host's WHEP subscribe used to
// fire once, the moment a guest is accepted — but the guest's WHIP publish
// only starts seconds later (permission prompt, camera warm-up, ICE). Two
// distinct MediaMTX-side symptoms result:
//   1. `no stream is available on path '...'` — a synchronous 404 on the
//      WHEP POST itself, because the guest hasn't started publishing yet.
//      This is "not yet", not failure.
//   2. `peer connection established … closed: deadline exceeded while
//      waiting tracks` — the POST succeeded (MediaMTX answered 201 and the
//      peer connection actually came up) but MediaMTX itself gives up and
//      closes the session because the guest's tracks still never showed.
// Guests also drop and reconnect (backgrounded, network flip) — an
// established subscription that closes needs the exact same recovery, not a
// permanent error.
//
// This type holds ONLY the pure decision logic (bounded exponential
// backoff, retryable-vs-terminal error classification, window expiry) so it
// can be unit-tested without a real WebRTC/MediaMTX round trip. WhepSubscriber
// is the one thing that actually drives a retry loop using it.
import Foundation

enum WhepRetryClassification: Equatable {
    /// Not a failure — try again (e.g. "no stream is available" / 404,
    /// "deadline exceeded while waiting tracks", a transient network error).
    case retryable
    /// Can never succeed by retrying (e.g. a structurally invalid URL) —
    /// surface the error immediately rather than burning the retry window.
    case terminal(String)
    /// The attempt was deliberately torn down (Leave Stage, view teardown,
    /// broadcast end, or a newer `start()` superseding this one) — stop
    /// silently, do not touch UI state.
    case cancelled
}

enum WhepRetryPolicy {
    /// First retry waits ~0.5s, doubling up to an 8s cap — fast enough that
    /// a guest who's ready in a couple seconds isn't stuck watching a long
    /// pause, capped low enough that a still-not-ready guest doesn't wait
    /// forever between checks.
    static let initialBackoff: TimeInterval = 0.5
    static let maxBackoff: TimeInterval = 8.0

    /// Total time the retry loop keeps trying before giving up and showing
    /// an error with a Retry affordance. Generous on purpose — guests on
    /// slow mobile networks (permission prompt, camera warm-up, ICE) are the
    /// NORMAL case here, not the exception; the production gaps observed
    /// were up to ~32s.
    static let window: TimeInterval = 60.0

    /// Safety-net timeout for a single in-flight attempt (POST succeeded,
    /// waiting on the delegate to report `.connected` or a drop). MediaMTX's
    /// own "deadline exceeded while waiting tracks" timeout normally fires
    /// well before this and drives the retry directly — this only protects
    /// against the delegate never firing anything at all.
    static let attemptWatchdog: TimeInterval = 25.0

    /// attempt is 1-based (the delay BEFORE that attempt number, i.e. after
    /// attempt 1 fails, `backoffDelay(forAttempt: 1)` is how long to wait
    /// before attempt 2).
    static func backoffDelay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt >= 1 else { return 0 }
        let scaled = initialBackoff * pow(2.0, Double(attempt - 1))
        return min(scaled, maxBackoff)
    }

    static func isWindowExpired(startedAt: Date, now: Date = Date()) -> Bool {
        now.timeIntervalSince(startedAt) >= window
    }

    /// Classifies an error thrown from the WHIP/WHEP HTTP exchange or SDP
    /// negotiation. Deliberately generous: only a structurally-bad URL
    /// (`WebRTCSDPError.badURL`) and explicit cancellation are non-retryable
    /// — everything else, including every HTTP status (404 "no stream
    /// available", 5xx, or a network hiccup), is treated as "not yet" per
    /// the task's own guidance. The retry WINDOW is what bounds total time
    /// spent, not per-error guessing about which status codes are "real"
    /// failures.
    static func classify(_ error: Error) -> WhepRetryClassification {
        if error is CancellationError { return .cancelled }
        if let urlError = error as? URLError, urlError.code == .cancelled { return .cancelled }
        if let sdpError = error as? WebRTCSDPError, case .badURL = sdpError {
            return .terminal("Bad stage link.")
        }
        return .retryable
    }
}
