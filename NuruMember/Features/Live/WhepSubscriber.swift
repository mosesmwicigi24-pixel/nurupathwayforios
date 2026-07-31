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

    private var peerConnection: RTCPeerConnection?
    private var resourceURL: URL?
    private var generation = 0

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
        guard let pc = WebRTCFactory.shared.peerConnection(with: config, constraints: pcConstraints, delegate: self) else {
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
        peerConnection?.close()
        peerConnection = nil
        videoTrack = nil
        resourceURL = nil
    }

    // MARK: RTCPeerConnectionDelegate (optional callbacks we actually use)

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        guard let track = rtpReceiver.track as? RTCVideoTrack else { return }
        Task { @MainActor [weak self] in
            self?.videoTrack = track
        }
    }

    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCPeerConnectionState) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            switch newState {
            case .connected:
                if self.state == .connecting { self.state = .live }
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
