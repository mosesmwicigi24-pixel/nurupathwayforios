// Nuru Live L6b — the GUEST's outbound WebRTC publish: camera + mic straight
// to MediaMTX over WHIP (WebRTC-HTTP Ingest Protocol). Owned by
// LiveViewerPlayerView (via GuestStagePiP) for the lifetime of the "I'm an
// accepted guest right now" window — started once `pulse.guests` shows my
// own row as `accepted`, stopped the instant it isn't (host removed me, I
// left, or the stream ended).
//
// WHIP flow (gather-then-send, matching the pinned task guidance — no
// trickle-ICE signaling channel needed for a one-shot HTTP exchange):
//   1. Build a sendonly RTCPeerConnection with a mic (Opus) + front camera
//      (H.264/VP8, whatever the negotiated codec ends up being — MediaMTX
//      handles both) track.
//   2. createOffer → setLocalDescription → wait for ICE gathering to finish.
//   3. POST the complete offer SDP to the bare `whipURL`, authenticated with
//      an HTTP **Basic** `Authorization` header (`user=<myUserId>`,
//      `pass=<token>`) — see `WhipBasicAuth` in WebRTCSupport.swift for why
//      it's a header and not `?user=&pass=` query params (MediaMTX
//      v1.19.3 silently ignores those for WHIP/WHEP; proven against
//      production 2026-07-31 — that's what made guest video unable to ever
//      authenticate).
//   4. 201 back: SDP answer body + `Location` header (the session resource —
//      DELETE it to leave the stage).
//   5. setRemoteDescription(answer). Connection state flips to `.live` once
//      DTLS/ICE finish (delegate callback, hopped to the main actor).
import AVFoundation
import Foundation
import WebRTC
import os

private let whipLogger = Logger(subsystem: "org.nuruplace.member", category: "WhipPublisher")

@MainActor
final class WhipPublisher: WebRTCPeerConnectionObserver, ObservableObject {
    enum State: Equatable {
        case idle
        case connecting
        case live
        case failed(String)
        case ended
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isMuted = false
    /// Bound by GuestStagePiP's self-preview `WebRTCVideoView`.
    @Published private(set) var localVideoTrack: RTCVideoTrack?

    private var peerConnection: RTCPeerConnection?
    private var localAudioTrack: RTCAudioTrack?
    private var capturer: RTCCameraVideoCapturer?
    private var resourceURL: URL?
    /// Stashed from `start()`'s params so `stop()` can re-authenticate the
    /// DELETE the same way (see `WhipHTTP.delete`'s header comment on why
    /// that's sent even though MediaMTX doesn't currently require it there).
    private var credentialUser: String?
    private var credentialPass: String?
    /// Guards against a stale `start()` call (e.g. a fast accepted→removed→
    /// accepted flap) racing a `stop()` and reviving a connection that
    /// should be dead — every awaited step below checks this before touching
    /// shared state.
    private var generation = 0

    /// A failure BEFORE any peer connection exists (e.g. the ingest fetch
    /// itself 403'd) — called by the view instead of `start()`.
    func markFailed(_ message: String) {
        guard state == .idle else { return }
        state = .failed(message)
    }

    /// `whipURLString` is the bare MediaMTX endpoint from `GuestIngest.whipUrl`;
    /// `user`/`pass` (my own userId + the one-time guest token — see
    /// `GuestIngest`'s header comment) are sent as an HTTP Basic
    /// `Authorization` header, never in the URL — see `WhipBasicAuth`.
    func start(whipURLString: String, user: String, pass: String) async {
        guard state == .idle || isTerminal(state) else { return }
        whipLogger.notice("start — generation=\(self.generation + 1, privacy: .public)")
        generation += 1
        let myGeneration = generation
        state = .connecting
        credentialUser = user
        credentialPass = pass

        guard let url = URL(string: whipURLString) else {
            state = .failed("That stage link looks wrong.")
            return
        }

        let config = WebRTCFactory.configuration()
        let pcConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let pc = WebRTCFactory.shared.peerConnection(with: config, constraints: pcConstraints, delegate: self) else {
            state = .failed("Couldn't start the connection.")
            return
        }
        peerConnection = pc

        // Mic (Opus, WebRTC's default audio codec — nothing to configure).
        let audioSource = WebRTCFactory.shared.audioSource(with: RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil))
        let audioTrack = WebRTCFactory.shared.audioTrack(with: audioSource, trackId: "guest-audio-\(user)")
        localAudioTrack = audioTrack
        let audioInit = RTCRtpTransceiverInit()
        audioInit.direction = .sendOnly
        pc.addTransceiver(with: audioTrack, init: audioInit)

        // Front camera, ~640×480@24fps, capped ~800kbps — a tile-sized feed,
        // not a broadcast-quality one (see the L6b task's own guidance).
        guard let device = WebRTCCamera.device(position: .front) else {
            state = .failed("No camera available on this device.")
            teardownPeerConnection()
            return
        }
        guard let format = WebRTCCamera.format(for: device) else {
            state = .failed("Couldn't find a usable camera format.")
            teardownPeerConnection()
            return
        }
        let fps = WebRTCCamera.fps(for: format)
        let videoSource = WebRTCFactory.shared.videoSource()
        let camCapturer = RTCCameraVideoCapturer(delegate: videoSource)
        capturer = camCapturer
        do {
            try await startCapture(camCapturer, device: device, format: format, fps: fps)
        } catch {
            state = .failed("Couldn't start the camera.")
            teardownPeerConnection()
            return
        }
        guard myGeneration == generation else { return }

        let videoTrack = WebRTCFactory.shared.videoTrack(with: videoSource, trackId: "guest-video-\(user)")
        localVideoTrack = videoTrack
        let videoInit = RTCRtpTransceiverInit()
        videoInit.direction = .sendOnly
        let videoTransceiver = pc.addTransceiver(with: videoTrack, init: videoInit)
        WebRTCSDP.capVideoBitrate(videoTransceiver?.sender, toBps: 800_000)

        do {
            let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
            let offer = try await WebRTCSDP.createOffer(pc, constraints: constraints)
            try await WebRTCSDP.setLocal(pc, offer)
            guard myGeneration == generation else { return }
            await WebRTCSDP.waitForIceGatheringComplete(pc)
            guard myGeneration == generation else { return }
            let finalOfferSDP = pc.localDescription?.sdp ?? offer.sdp
            let result = try await WhipHTTP.post(sdpOffer: finalOfferSDP, to: url, user: user, pass: pass)
            guard myGeneration == generation else { return }
            resourceURL = result.resourceURL
            let answer = RTCSessionDescription(type: .answer, sdp: result.answerSDP)
            try await WebRTCSDP.setRemote(pc, answer)
            // `.live` itself is set from the peerConnection(_:didChange
            // newState:) delegate callback below, once ICE/DTLS actually
            // finish connecting — this is just "negotiated OK so far".
        } catch {
            guard myGeneration == generation else { return }
            state = .failed("Couldn't connect to the stage. Check your connection and try again.")
            teardownPeerConnection()
        }
    }

    /// The self-preview PiP's Retry tap — clears a terminal `.failed` state
    /// so a fresh `start()` (with newly re-fetched ingest credentials) is
    /// free to run again.
    func resetToIdle() {
        guard isTerminal(state) else { return }
        state = .idle
    }

    func toggleMute() {
        guard let track = localAudioTrack else { return }
        track.isEnabled.toggle()
        isMuted = !track.isEnabled
    }

    func stop() async {
        guard state != .idle else { return }
        whipLogger.notice("stop — generation=\(self.generation + 1, privacy: .public)")
        generation += 1
        let resource = resourceURL
        let user = credentialUser
        let pass = credentialPass
        state = .ended
        if let resource, let user, let pass { await WhipHTTP.delete(resource, user: user, pass: pass) }
        teardownPeerConnection()
        // Reset to `.idle` AFTER teardown so a fresh `start()` (re-accepted
        // after a re-invite) is free to run again.
        state = .idle
    }

    /// Lifetime-ordering, same discipline as `WhepSubscriber.teardownPeerConnection`:
    /// stop the camera capturer BEFORE closing the peer connection it feeds,
    /// then nil every reference so nothing downstream can touch a
    /// native WebRTC object after this returns.
    private func teardownPeerConnection() {
        whipLogger.notice("teardownPeerConnection")
        capturer?.stopCapture()
        capturer = nil
        peerConnection?.close()
        peerConnection = nil
        localVideoTrack = nil
        localAudioTrack = nil
        resourceURL = nil
        credentialUser = nil
        credentialPass = nil
    }

    private func isTerminal(_ state: State) -> Bool {
        switch state {
        case .failed, .ended: return true
        default: return false
        }
    }

    private func startCapture(_ capturer: RTCCameraVideoCapturer, device: AVCaptureDevice, format: AVCaptureDevice.Format, fps: Int) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            capturer.startCapture(with: device, format: format, fps: fps) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    // MARK: RTCPeerConnectionDelegate (optional callbacks we actually use)

    /// Identity-checked against `self.peerConnection` before touching any
    /// state — see `WhepSubscriber`'s identical guard (same file family,
    /// same reasoning) for why: this `Task` hop doesn't run synchronously
    /// with the WebRTC thread that triggered it, so a fast leave→rejoin
    /// (`stop()` then `start()` again) could otherwise let a stale callback
    /// from the OLD, already-closed connection mutate state that now belongs
    /// to a brand-new one.
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, self.peerConnection === peerConnection else { return }
            switch newState {
            case .connected:
                if self.state == .connecting { self.state = .live }
            case .failed:
                self.state = .failed("Lost connection to the stage.")
                self.teardownPeerConnection()
            case .closed, .disconnected, .new, .connecting:
                break
            @unknown default:
                break
            }
        }
    }
}
