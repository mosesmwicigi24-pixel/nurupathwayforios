// Nuru Live L6b — the HOST's inbound WebRTC subscribe for ONE accepted
// guest, over WHEP (WebRTC-HTTP Egress Protocol). One instance per guest
// tile, owned by BroadcastController (`guestSubscribers`, keyed by userId),
// created/torn down as `pulse.guests` changes — see
// BroadcastController.syncGuestSubscribers.
//
// WHEP flow mirrors WhipPublisher's WHIP flow exactly, just recvonly and
// with no local tracks to add:
//   1. Build a recvonly RTCPeerConnection (constraints ask to receive both
//      audio and video — MediaMTX auto-creates matching transceivers).
//   2. createOffer → setLocalDescription → wait for ICE gathering.
//   3. POST to the bare `whepURL`, authenticated with an HTTP **Basic**
//      `Authorization` header carrying `user=<streamId>`,
//      `pass=<streamKey>` — the HOST authenticates with the STREAM's own
//      broadcast credentials (the stream owner, not the guest), per the
//      pinned wire contract. Header, not `?user=&pass=` query params — see
//      `WhipBasicAuth` in WebRTCSupport.swift: MediaMTX v1.19.3 silently
//      ignores those query params for WHIP/WHEP (proven against production
//      2026-07-31).
//   4. 201 back: SDP answer + Location (DELETE to unsubscribe).
//   5. setRemoteDescription(answer). The remote video/audio tracks arrive via
//      the `didAdd rtpReceiver:streams:` delegate callback — video is bound
//      to a `WebRTCVideoView` guest tile; audio just needs to exist (WebRTC
//      plays it out automatically over the app's active AVAudioSession route
//      — see WebRTCAudioCoexistence's header comment for how that coexists
//      with HaishinKit's own mic capture on this same device).
//
// RETRY (2026-07-31 production fix — see WhepRetryPolicy's header comment
// for the full production-log evidence): the WHEP subscribe above is no
// longer one-shot. `start()` drives a bounded-exponential-backoff retry loop
// (`runRetryLoop`/`performAttempt`) that treats "no stream is available"
// (404), "deadline exceeded while waiting tracks", and any other
// non-terminal error as "not yet" rather than failure, and keeps the tile in
// `.connecting` while it retries. Once live, a later drop (guest
// backgrounded, network flip, MediaMTX closing the session) is recovered
// automatically by re-entering the SAME retry loop with a fresh window
// (`handleFailedOrClosed`) rather than sticking on an error. `.failed` (with
// a Retry affordance in LiveStageView) is reached ONLY after the retry
// window genuinely expires.
import CoreMedia
import Foundation
import WebRTC
import os

private let whepLogger = Logger(subsystem: "org.nuruplace.member", category: "WhepSubscriber")

@MainActor
final class WhepSubscriber: WebRTCPeerConnectionObserver, ObservableObject {
    enum State: Equatable {
        case connecting
        case live
        case failed(String)
        case ended
    }

    @Published private(set) var state: State = .connecting
    /// Bound by LiveStageView's `WebRTCVideoView`. Audio needs no equivalent
    /// published property — once the remote audio track exists, WebRTC plays
    /// it out on its own; there's nothing for SwiftUI to bind.
    @Published private(set) var videoTrack: RTCVideoTrack?
    /// L6c active-speaker signal — WebRTC's standard "inbound-rtp"/audioLevel
    /// stat (0.0–1.0), polled every second once connected. BroadcastController
    /// compares this across all live guest tiles to decide who goes
    /// full-frame on the composited stage; see `fetchAudioLevel()` below for
    /// why a plain stats poll rather than a raw-buffer RMS meter (the
    /// approach BroadcastController's own header comment rules out for the
    /// LOCAL mic, for a different reason — no equivalent metering API at
    /// all there; here, WebRTC's stats API already reports it).
    @Published private(set) var audioLevel: Double = 0

    /// L6c stage-compositing sink — set by BroadcastController.syncGuestSubscribers
    /// BEFORE `start()`, so it's already in place the moment the remote video
    /// track (and therefore `attachCompositorSink`) arrives. Fires on
    /// WebRTC's decode thread via `RTCFrameToSampleBufferSampler`, so this
    /// must stay `@Sendable` — see that type's header comment.
    var onVideoFrame: (@Sendable (CMSampleBuffer) -> Void)?

    private var peerConnection: RTCPeerConnection?
    private var resourceURL: URL?
    /// Session identity — stashed from `start()`'s params. Unlike the
    /// connection-scoped fields `teardownPeerConnection()` clears on every
    /// attempt, these survive across retries AND across an automatic
    /// reconnect after a drop (`handleFailedOrClosed`), since both need the
    /// SAME WHEP URL/credentials to try again. Only `stop()` clears them.
    private var savedWhepURL: String?
    private var credentialUser: String?
    private var credentialPass: String?
    private var generation = 0
    private var statsTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var attemptWatchdogTask: Task<Void, Never>?
    private var connectContinuation: CheckedContinuation<AttemptOutcome, Never>?
    private var frameSampler: RTCFrameToSampleBufferSampler?
    private weak var sampledTrack: RTCVideoTrack?

    private enum AttemptOutcome { case connected, retry, terminal(String), cancelled }

    /// `whepURLString` is `LiveGuestRow.whepUrl`; `user`/`pass` are the
    /// STREAM's own id + stream key (the broadcaster's own publish
    /// credentials double as their WHEP-subscribe credentials — see the
    /// header comment). Sent as an HTTP Basic `Authorization` header, never
    /// in the URL — see `WhipBasicAuth`.
    ///
    /// Kicks off the retry loop and awaits its FIRST resolution (connected,
    /// terminal, or window-expired) — matching the original one-shot
    /// signature callers already use (`Task { await sub.start(...) }`).
    /// Recovery from a LATER drop happens independently, off this call, via
    /// `handleFailedOrClosed`.
    func start(whepURLString: String, user: String, pass: String) async {
        generation += 1
        let myGeneration = generation
        whepLogger.notice("start — generation=\(myGeneration, privacy: .public)")
        WebRTCAudioCoexistence.configureForHostSideGuestAudio()
        savedWhepURL = whepURLString
        credentialUser = user
        credentialPass = pass
        state = .connecting
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runRetryLoop(generation: myGeneration, startedAt: Date())
        }
        retryTask = task
        await task.value
    }

    func stop() async {
        whepLogger.notice("stop — generation=\(self.generation + 1, privacy: .public)")
        generation += 1
        retryTask?.cancel()
        retryTask = nil
        attemptWatchdogTask?.cancel()
        attemptWatchdogTask = nil
        if let continuation = connectContinuation {
            connectContinuation = nil
            continuation.resume(returning: .cancelled)
        }
        let resource = resourceURL
        let user = credentialUser
        let pass = credentialPass
        state = .ended
        if let resource, let user, let pass { await WhipHTTP.delete(resource, user: user, pass: pass) }
        teardownPeerConnection()
        savedWhepURL = nil
        credentialUser = nil
        credentialPass = nil
    }

    /// The Retry affordance in LiveStageView — only reachable from `.failed`,
    /// i.e. after the retry window already expired once. Reuses the same
    /// WHEP URL/credentials from the original `start()` (still held, since
    /// only `stop()` clears them) rather than requiring the guest to fully
    /// leave and rejoin the stage.
    func retry() async {
        guard case .failed = state else { return }
        guard let whepURLString = savedWhepURL, let user = credentialUser, let pass = credentialPass else { return }
        await start(whepURLString: whepURLString, user: user, pass: pass)
    }

    // MARK: - Retry loop

    /// Bounded-exponential-backoff attempts (`WhepRetryPolicy`) until
    /// connected, a terminal error, cancellation, or the retry window
    /// expires. Re-entered with a FRESH window both from `start()` and from
    /// `handleFailedOrClosed` (an established subscription dropping is a new
    /// problem, not a continuation of the original join attempt).
    private func runRetryLoop(generation myGeneration: Int, startedAt: Date) async {
        guard let whepURLString = savedWhepURL, let user = credentialUser, let pass = credentialPass else { return }
        guard let url = URL(string: whepURLString) else {
            guard myGeneration == generation else { return }
            state = .failed("Bad stage link.")
            return
        }
        var attempt = 0
        while myGeneration == generation, !Task.isCancelled {
            attempt += 1
            let outcome = await performAttempt(url: url, user: user, pass: pass, generation: myGeneration)
            guard myGeneration == generation, !Task.isCancelled else { return }
            switch outcome {
            case .connected, .cancelled:
                return
            case .terminal(let message):
                whepLogger.notice("attempt \(attempt, privacy: .public) terminal — \(message, privacy: .public)")
                state = .failed(message)
                teardownPeerConnection()
                return
            case .retry:
                if WhepRetryPolicy.isWindowExpired(startedAt: startedAt) {
                    whepLogger.notice("retry window expired after \(attempt, privacy: .public) attempt(s)")
                    state = .failed("Couldn't connect to this guest's video.")
                    teardownPeerConnection()
                    return
                }
                state = .connecting
                let delay = WhepRetryPolicy.backoffDelay(forAttempt: attempt)
                whepLogger.notice("attempt \(attempt, privacy: .public) not ready — retrying in \(delay, privacy: .public)s")
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
        }
    }

    /// One full WHIP/WHEP HTTP exchange, then — if it succeeds — waits
    /// (bounded by `WhepRetryPolicy.attemptWatchdog`) for the delegate to
    /// report either `.connected` or a drop (`.failed`/`.closed`, e.g.
    /// MediaMTX's "deadline exceeded while waiting tracks"). Always tears
    /// down whatever peer connection existed from a PRIOR attempt first —
    /// each attempt starts from a clean slate.
    private func performAttempt(url: URL, user: String, pass: String, generation myGeneration: Int) async -> AttemptOutcome {
        teardownPeerConnection()
        guard myGeneration == generation else { return .cancelled }

        let config = WebRTCFactory.configuration()
        let pcConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        // L6d — the host-only factory with the custom `RTCAudioDevice`
        // installed (see WebRTCSupport.swift), so this guest's decoded audio
        // lands in `GuestAudioPlayoutDevice` instead of going straight to
        // the speaker via WebRTC's own default session management.
        guard let pc = WebRTCFactory.hostGuestAudio.peerConnection(with: config, constraints: pcConstraints, delegate: self) else {
            return .terminal("Couldn't start the connection.")
        }
        peerConnection = pc

        do {
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
                optionalConstraints: nil)
            let offer = try await WebRTCSDP.createOffer(pc, constraints: constraints)
            try await WebRTCSDP.setLocal(pc, offer)
            guard myGeneration == generation, peerConnection === pc else { return .cancelled }
            await WebRTCSDP.waitForIceGatheringComplete(pc)
            guard myGeneration == generation, peerConnection === pc else { return .cancelled }
            let finalOfferSDP = pc.localDescription?.sdp ?? offer.sdp
            let result = try await WhipHTTP.post(sdpOffer: finalOfferSDP, to: url, user: user, pass: pass)
            guard myGeneration == generation, peerConnection === pc else { return .cancelled }
            resourceURL = result.resourceURL
            let answer = RTCSessionDescription(type: .answer, sdp: result.answerSDP)
            try await WebRTCSDP.setRemote(pc, answer)
            guard myGeneration == generation, peerConnection === pc else { return .cancelled }
        } catch {
            guard myGeneration == generation, peerConnection === pc else { return .cancelled }
            switch WhepRetryPolicy.classify(error) {
            case .retryable: return .retry
            case .terminal(let message): return .terminal(message)
            case .cancelled: return .cancelled
            }
        }

        // Remote description accepted — the exchange itself succeeded. Now
        // wait for the delegate to report the ACTUAL connection outcome:
        // `.connected` resolves this attempt as success; `.failed`/`.closed`
        // (MediaMTX's own "deadline exceeded while waiting tracks" surfaces
        // here) resolves it as retryable. The watchdog is only a safety net
        // in case neither ever fires.
        return await withCheckedContinuation { (continuation: CheckedContinuation<AttemptOutcome, Never>) in
            guard myGeneration == generation, peerConnection === pc else {
                continuation.resume(returning: .cancelled)
                return
            }
            connectContinuation = continuation
            attemptWatchdogTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(WhepRetryPolicy.attemptWatchdog * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                self.resolvePendingAttempt(.retry, pc: pc)
            }
        }
    }

    /// Resumes the in-flight attempt's continuation exactly once — called
    /// from the delegate (`.connected`/`.failed`/`.closed`) or the attempt
    /// watchdog, whichever fires first. Guarded on `peerConnection === pc`
    /// so a stale resolution (from an already-superseded attempt) is a
    /// silent no-op instead of resolving the WRONG attempt's continuation.
    private func resolvePendingAttempt(_ outcome: AttemptOutcome, pc: RTCPeerConnection) {
        guard peerConnection === pc, let continuation = connectContinuation else { return }
        connectContinuation = nil
        attemptWatchdogTask?.cancel()
        attemptWatchdogTask = nil
        continuation.resume(returning: outcome)
    }

    /// Lifetime-ordering is load-bearing here: the video renderer sink is
    /// detached from the track BEFORE the peer connection (and therefore the
    /// track itself) is closed — a native WebRTC object must never be
    /// touched after teardown starts. `frameSampler`/`sampledTrack` are
    /// nilled out immediately after so any late-arriving delegate callback
    /// (e.g. a straggler `didAdd rtpReceiver` racing a fast accept→remove)
    /// has nothing left to attach to.
    ///
    /// Connection-scoped only — deliberately does NOT clear
    /// `savedWhepURL`/`credentialUser`/`credentialPass`, which must survive
    /// across retries and automatic reconnects. Only `stop()` clears those.
    private func teardownPeerConnection() {
        whepLogger.notice("teardownPeerConnection")
        statsTask?.cancel()
        statsTask = nil
        if let sampledTrack, let frameSampler { sampledTrack.remove(frameSampler) }
        frameSampler = nil
        sampledTrack = nil
        peerConnection?.close()
        peerConnection = nil
        videoTrack = nil
        resourceURL = nil
        audioLevel = 0
    }

    /// L6c — adds a SECOND renderer to the just-arrived remote video track
    /// (WebRTC supports multiple sinks per track) that converts frames to
    /// CMSampleBuffers for `onVideoFrame`, alongside whatever `WebRTCVideoView`
    /// LiveStageView already bound. A no-op if BroadcastController never set
    /// `onVideoFrame` (e.g. an audio-only session has no compositor).
    private func attachCompositorSink(to track: RTCVideoTrack) {
        guard let onVideoFrame else { return }
        let sampler = RTCFrameToSampleBufferSampler(ciContext: WebRTCFactory.compositingContext, onSampleBuffer: onVideoFrame)
        frameSampler = sampler
        sampledTrack = track
        track.add(sampler)
    }

    /// Polls WebRTC's standard stats API for this guest's inbound audio
    /// level once a second — the same signal browsers use for "active
    /// speaker" highlighting. `statistics(completionHandler:)` isn't
    /// async-native, so it's bridged via a continuation; the completion fires
    /// on WebRTC's own signaling thread, which is fine — continuations are
    /// thread-safe, and the result hop back onto `self` (MainActor, since
    /// this whole type is) happens naturally via `await` below.
    private func startStatsPolling() {
        guard statsTask == nil else { return }
        statsTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                let level = await self.fetchAudioLevel()
                guard !Task.isCancelled else { return }
                self.audioLevel = level
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    private func fetchAudioLevel() async -> Double {
        guard let pc = peerConnection else { return 0 }
        return await withCheckedContinuation { continuation in
            pc.statistics { report in
                var level: Double = 0
                for stat in report.statistics.values where stat.type == "inbound-rtp" {
                    guard let kind = stat.values["kind"] as? String, kind == "audio" else { continue }
                    if let value = stat.values["audioLevel"] as? NSNumber {
                        level = value.doubleValue
                    }
                }
                continuation.resume(returning: level)
            }
        }
    }

    // MARK: RTCPeerConnectionDelegate (optional callbacks we actually use)

    /// Both delegate callbacks below hop onto MainActor via a fresh `Task`,
    /// which does not run synchronously with the WebRTC thread that
    /// triggered it — by the time it actually executes, `stop()` (called
    /// from a fast accept→remove→re-accept, or the drop-watchdog tearing
    /// every guest down) may have ALREADY closed and replaced
    /// `self.peerConnection`. Comparing identity against the `peerConnection`
    /// param each callback receives (WebRTC always passes the SPECIFIC
    /// instance that fired it) is what stops a stale callback from a
    /// torn-down connection from resurrecting state — or worse, calling
    /// `teardownPeerConnection()` — against a DIFFERENT, currently-live
    /// connection that happens to share this same `WhepSubscriber` instance.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else { return }
            self.videoTrack = track
            self.attachCompositorSink(to: track)
        }
    }

    /// `.connected` resolves a pending in-flight attempt as success (if
    /// there is one) and marks the tile live. `.failed`/`.closed` either
    /// resolves a pending attempt as retryable (still mid-handshake — see
    /// `performAttempt`'s continuation), or, if there was no pending
    /// attempt, means an already-LIVE subscription just dropped (guest
    /// backgrounded, network flip, or MediaMTX itself closing the session —
    /// "deadline exceeded while waiting tracks" is exactly this case when it
    /// arrives late). That drop is recovered automatically by re-entering
    /// the retry loop with a fresh window, never left stuck on an error.
    /// `.disconnected` is deliberately left alone — WebRTC's own ICE layer
    /// routinely self-heals a brief `.disconnected` back to `.connected`
    /// without our help; only `.failed`/`.closed` are treated as a real drop.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else { return }
            switch newState {
            case .connected:
                self.handleConnected(pc: peerConnection)
            case .failed, .closed:
                self.handleFailedOrClosed(pc: peerConnection)
            case .disconnected, .new, .connecting:
                break
            @unknown default:
                break
            }
        }
    }

    private func handleConnected(pc: RTCPeerConnection) {
        resolvePendingAttempt(.connected, pc: pc)
        state = .live
        startStatsPolling()
    }

    private func handleFailedOrClosed(pc: RTCPeerConnection) {
        if connectContinuation != nil {
            resolvePendingAttempt(.retry, pc: pc)
            return
        }
        guard state == .live else { return }
        whepLogger.notice("established subscription dropped — reconnecting")
        generation += 1
        let myGeneration = generation
        teardownPeerConnection()
        state = .connecting
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            guard let self else { return }
            await self.runRetryLoop(generation: myGeneration, startedAt: Date())
        }
    }
}
