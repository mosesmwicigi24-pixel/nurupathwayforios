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
//   3. POST to `whepURL?user=<streamId>&pass=<streamKey>` — the HOST
//      authenticates with the STREAM's own broadcast credentials (the
//      stream owner, not the guest), per the pinned wire contract.
//   4. 201 back: SDP answer + Location (DELETE to unsubscribe).
//   5. setRemoteDescription(answer). The remote video/audio tracks arrive via
//      the `didAdd rtpReceiver:streams:` delegate callback — video is bound
//      to a `WebRTCVideoView` guest tile; audio just needs to exist (WebRTC
//      plays it out automatically over the app's active AVAudioSession route
//      — see WebRTCAudioCoexistence's header comment for how that coexists
//      with HaishinKit's own mic capture on this same device).
import CoreMedia
import Foundation
import WebRTC

@MainActor
final class WhepSubscriber: WebRTCPeerConnectionObserver, ObservableObject {
    enum State: Equatable {
        case connecting
        case live
        case failed(String)
        case ended
    }

    @Published private(set) var state: State = .connecting
    /// Bound by GuestTileRail's `WebRTCVideoView`. Audio needs no equivalent
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
    private var generation = 0
    private var statsTask: Task<Void, Never>?
    private var frameSampler: RTCFrameToSampleBufferSampler?
    private weak var sampledTrack: RTCVideoTrack?

    /// `whepURLString` is `LiveGuestRow.whepUrl`; `user`/`pass` are the
    /// STREAM's own id + stream key (the broadcaster's own publish
    /// credentials double as their WHEP-subscribe credentials — see the
    /// header comment).
    func start(whepURLString: String, user: String, pass: String) async {
        WebRTCAudioCoexistence.configureForHostSideGuestAudio()
        generation += 1
        let myGeneration = generation
        state = .connecting

        guard var comps = URLComponents(string: whepURLString) else {
            state = .failed("Bad stage link.")
            return
        }
        var items = comps.queryItems ?? []
        items.append(URLQueryItem(name: "user", value: user))
        items.append(URLQueryItem(name: "pass", value: pass))
        comps.queryItems = items
        guard let url = comps.url else {
            state = .failed("Bad stage link.")
            return
        }

        let config = WebRTCFactory.configuration()
        let pcConstraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        // L6d — the host-only factory with the custom `RTCAudioDevice`
        // installed (see WebRTCSupport.swift), so this guest's decoded audio
        // lands in `GuestAudioPlayoutDevice` instead of going straight to
        // the speaker via WebRTC's own default session management.
        guard let pc = WebRTCFactory.hostGuestAudio.peerConnection(with: config, constraints: pcConstraints, delegate: self) else {
            state = .failed("Couldn't start the connection.")
            return
        }
        peerConnection = pc

        do {
            let constraints = RTCMediaConstraints(
                mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "true"],
                optionalConstraints: nil)
            let offer = try await WebRTCSDP.createOffer(pc, constraints: constraints)
            try await WebRTCSDP.setLocal(pc, offer)
            guard myGeneration == generation else { return }
            await WebRTCSDP.waitForIceGatheringComplete(pc)
            guard myGeneration == generation else { return }
            let finalOfferSDP = pc.localDescription?.sdp ?? offer.sdp
            let result = try await WhipHTTP.post(sdpOffer: finalOfferSDP, to: url)
            guard myGeneration == generation else { return }
            resourceURL = result.resourceURL
            let answer = RTCSessionDescription(type: .answer, sdp: result.answerSDP)
            try await WebRTCSDP.setRemote(pc, answer)
        } catch {
            guard myGeneration == generation else { return }
            state = .failed("Couldn't connect to this guest's video.")
            teardownPeerConnection()
        }
    }

    func stop() async {
        generation += 1
        let resource = resourceURL
        state = .ended
        if let resource { await WhipHTTP.delete(resource) }
        teardownPeerConnection()
    }

    private func teardownPeerConnection() {
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
    /// GuestTileRail already bound. A no-op if BroadcastController never set
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

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.videoTrack = track
            self.attachCompositorSink(to: track)
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch newState {
            case .connected:
                if self.state == .connecting { self.state = .live }
                self.startStatsPolling()
            case .failed:
                self.state = .failed("Lost connection to this guest's video.")
                self.teardownPeerConnection()
            case .closed, .disconnected, .new, .connecting:
                break
            @unknown default:
                break
            }
        }
    }
}
