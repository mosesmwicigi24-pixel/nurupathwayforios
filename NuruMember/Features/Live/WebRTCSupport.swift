// Nuru Live L6b — shared WebRTC plumbing used by both WhipPublisher (a
// guest's outbound camera+mic) and WhepSubscriber (the host's inbound feed
// for one accepted guest). Factored out here so those two files stay
// focused on their own state machines instead of repeating peer-connection
// boilerplate.
//
// Package: stasel/WebRTC (https://github.com/stasel/WebRTC) — a binary
// distribution of Google's own WebRTC.framework build for iOS, mirroring the
// upstream ObjC API exactly (verified against the actual libwebrtc ObjC
// headers at googlesource.com/src, not guessed). Added to project.pbxproj
// the same way HaishinKit already is (XCRemoteSwiftPackageReference +
// XCSwiftPackageProductDependency on the NuruMember target).
import AVFoundation
import CoreMedia
import Foundation
import SwiftUI
import WebRTC

// MARK: - Shared factory

/// One `RTCPeerConnectionFactory` for the whole app. Constructing a factory
/// spins up libwebrtc's internal worker/signaling/network threads — there's
/// no reason to pay that more than once, and nothing about a factory is tied
/// to a single peer connection's lifetime. Every WhipPublisher (guest
/// publish) and every WhepSubscriber (one per accepted guest tile on the
/// host) creates its `RTCPeerConnection` from this same instance.
enum WebRTCFactory {
    static let shared: RTCPeerConnectionFactory = {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory)
    }()

    /// A single public STUN server so the client gathers a server-reflexive
    /// (public IP:port) candidate — without one, a device behind NAT would
    /// only ever gather host (LAN-local) candidates, which MediaMTX on the
    /// public VPS could never reach. MediaMTX itself needs no TURN/STUN of
    /// its own here since it's already on a public IP with UDP 8189 open
    /// (per the pinned deployment facts) — it's always reachable directly
    /// once WE have a usable candidate.
    static func configuration() -> RTCConfiguration {
        let config = RTCConfiguration()
        config.iceServers = [RTCIceServer(urlStrings: ["stun:stun.l.google.com:19302"])]
        config.sdpSemantics = .unifiedPlan
        // Gather-then-send (see the L6b task's own pinned guidance): one
        // full gathering pass, no trickle-ICE signaling channel needed for
        // a WHIP/WHEP exchange that's just a single HTTP POST.
        config.continualGatheringPolicy = .gatherOnce
        return config
    }
}

/// Coexistence fix for the HOST device only, where HaishinKit (broadcaster's
/// own outgoing mic) and WebRTC (a guest's incoming audio) are both touching
/// the SAME shared `AVAudioSession` at once.
///
/// WebRTC's `RTCAudioSession` auto-configures/activates `AVAudioSession`
/// itself by default (category `.playAndRecord`, mode `.voiceChat`) the
/// moment a peer connection with an audio track goes live. HaishinKit's own
/// `AVCaptureSession` ALSO auto-configures that same shared session for the
/// broadcaster's outgoing mic
/// (`automaticallyConfiguresApplicationAudioSession = true`, confirmed by
/// reading `VideoCaptureUnit.swift` — see BroadcastController's own header
/// comment on background capture for the precedent of reading HaishinKit's
/// actual source rather than assuming). Two frameworks independently
/// re-activating/re-configuring one shared session is the textbook recipe
/// for a stutter or a dropped mic the instant a guest's audio track goes
/// live mid-broadcast.
///
/// `useManualAudio = true` + `isAudioEnabled = true` tells WebRTC's
/// `RTCAudioSession` to stop calling `setCategory`/`setActive` itself and
/// just run its audio unit against whatever session the app already has
/// active. HaishinKit's `.playAndRecord` category already supports
/// simultaneous playback, so a guest's decoded audio plays out over it
/// without WebRTC ever touching the category or activation state.
///
/// Called once, lazily, the first time BroadcastController spins up a
/// WhepSubscriber. NOT called on the guest/viewer side (LiveViewerPlayerView)
/// — there, WebRTC is the ONLY framework touching audio capture (AVPlayer's
/// own `.playback` category has no recording claim to defend), so leaving
/// WebRTC's automatic session management on is correct there: it needs to
/// promote the session from `.playback` to `.playAndRecord` itself the
/// moment the guest starts publishing.
///
/// Caveat, stated plainly (production reliability doctrine): this is
/// designed from reading both frameworks' documented/source behavior, not
/// verified against a live device with a real second guest — there is no
/// way to exercise "does the broadcaster's mic glitch when a guest joins"
/// from `xcodebuild test`. Flagged in PARITY_AUDIT.md.
enum WebRTCAudioCoexistence {
    private static var configured = false

    static func configureForHostSideGuestAudio() {
        guard !configured else { return }
        configured = true
        let session = RTCAudioSession.sharedInstance()
        session.useManualAudio = true
        session.isAudioEnabled = true
    }
}

// MARK: - No-op RTCPeerConnectionDelegate base

/// `RTCPeerConnectionDelegate` requires ~9 methods; WhipPublisher and
/// WhepSubscriber each only care about 1-2 of them. Subclassing this keeps
/// their own files focused on what they actually handle — every delegate
/// callback fires on WebRTC's own internal thread, so both this base and
/// every override are `nonisolated`; anything touching `@Published` state
/// hops back to the main actor explicitly (see WhipPublisher/WhepSubscriber).
@MainActor
class WebRTCPeerConnectionObserver: NSObject, RTCPeerConnectionDelegate {
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}

// MARK: - SDP negotiation helpers (gather-then-send)

enum WebRTCSDPError: Error { case noAnswer, noDescription, badURL, httpStatus(Int) }

enum WebRTCSDP {
    static func createOffer(_ pc: RTCPeerConnection, constraints: RTCMediaConstraints) async throws -> RTCSessionDescription {
        try await withCheckedThrowingContinuation { cont in
            pc.offer(for: constraints) { sdp, error in
                if let sdp { cont.resume(returning: sdp) } else { cont.resume(throwing: error ?? WebRTCSDPError.noDescription) }
            }
        }
    }

    static func setLocal(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setLocalDescription(sdp) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    static func setRemote(_ pc: RTCPeerConnection, _ sdp: RTCSessionDescription) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            pc.setRemoteDescription(sdp) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    /// Gather-then-send: block (briefly) until ICE gathering completes so the
    /// offer POSTed to MediaMTX carries every candidate at once — no trickle
    /// signaling channel needed for a one-shot WHIP/WHEP HTTP exchange. Capped
    /// at 4s so a network that never reports `.complete` (rare, but possible)
    /// can't hang the join/subscribe flow forever; whatever candidates
    /// gathered by then are used as-is.
    static func waitForIceGatheringComplete(_ pc: RTCPeerConnection, timeout: TimeInterval = 4) async {
        let deadline = Date().addingTimeInterval(timeout)
        while pc.iceGatheringState != .complete, Date() < deadline {
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    /// Caps the video sender's outgoing bitrate — guests render as small
    /// tiles (host rail / self-preview PiP), so there's no reason to spend
    /// more than ~800kbps on one. A no-op if the sender has no encodings yet
    /// (never crashes a publish over a cosmetic bitrate cap).
    static func capVideoBitrate(_ sender: RTCRtpSender?, toBps bps: Int) {
        guard let sender, !sender.parameters.encodings.isEmpty else { return }
        let params = sender.parameters
        for encoding in params.encodings { encoding.maxBitrateBps = NSNumber(value: bps) }
        sender.parameters = params
    }
}

// MARK: - WHIP/WHEP HTTP exchange (raw — not APIClient; this hits MediaMTX
// directly, not the Nuru API, and auth is query-string credentials per the
// pinned wire contract, not a bearer token)

struct WhipExchangeResult { let answerSDP: String; let resourceURL: URL? }

enum WhipHTTP {
    /// POST the local SDP offer to a WHIP/WHEP URL (already carrying
    /// `?user=&pass=` — see `WhipPublisher`/`WhepSubscriber`). MediaMTX
    /// answers 201 with the SDP answer as the body and a `Location` header
    /// pointing at the session resource (DELETE it to leave/stop).
    static func post(sdpOffer: String, to url: URL) async throws -> WhipExchangeResult {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(sdpOffer.utf8)
        req.timeoutInterval = 15
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WebRTCSDPError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let answer = String(data: data, encoding: .utf8) ?? ""
        var resourceURL: URL?
        if let location = http.value(forHTTPHeaderField: "Location") {
            resourceURL = URL(string: location, relativeTo: url)?.absoluteURL
        }
        return WhipExchangeResult(answerSDP: answer, resourceURL: resourceURL)
    }

    /// Best-effort session teardown — a failed DELETE (network blip, session
    /// already reaped server-side) must never block the local peer connection
    /// from closing.
    static func delete(_ url: URL) async {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.timeoutInterval = 8
        _ = try? await URLSession.shared.data(for: req)
    }
}

// MARK: - Camera format selection (guest publish only)

enum WebRTCCamera {
    static func device(position: AVCaptureDevice.Position = .front) -> AVCaptureDevice? {
        let devices = RTCCameraVideoCapturer.captureDevices()
        return devices.first { $0.position == position } ?? devices.first
    }

    /// Closest supported format to the target width — guests are small
    /// tiles, so 640×480 (falling back to whatever's closest) is plenty and
    /// keeps encode cost/bandwidth low, per the task's own guidance.
    static func format(for device: AVCaptureDevice, targetWidth: Int32 = 640) -> AVCaptureDevice.Format? {
        let formats = RTCCameraVideoCapturer.supportedFormats(for: device)
        return formats.min { a, b in
            let da = abs(CMVideoFormatDescriptionGetDimensions(a.formatDescription).width - targetWidth)
            let db = abs(CMVideoFormatDescriptionGetDimensions(b.formatDescription).width - targetWidth)
            return da < db
        }
    }

    static func fps(for format: AVCaptureDevice.Format, target: Int32 = 24) -> Int {
        let maxSupported = format.videoSupportedFrameRateRanges.map { Int32($0.maxFrameRate) }.max() ?? target
        return Int(min(target, maxSupported))
    }
}

// MARK: - SwiftUI video surface (self-preview PiP + host guest tiles)

/// Thin `UIViewRepresentable` around `RTCMTLVideoView` — WebRTC's own
/// Metal-backed renderer, the same idiom as HaishinKit's `MTHKViewRepresentable`
/// already used for the broadcaster's own camera preview. Rebinds cleanly
/// when `track` changes (e.g. a tile's subscriber reconnects) or goes nil
/// (renders empty rather than holding a stale frame).
struct WebRTCVideoView: UIViewRepresentable {
    let track: RTCVideoTrack?
    var contentMode: UIView.ContentMode = .scaleAspectFill

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView()
        view.videoContentMode = contentMode
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        context.coordinator.bind(track: track, to: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private weak var boundTrack: RTCVideoTrack?
        func bind(track: RTCVideoTrack?, to view: RTCMTLVideoView) {
            guard track !== boundTrack else { return }
            if let boundTrack { boundTrack.remove(view) }
            boundTrack = track
            track?.add(view)
        }
    }
}
