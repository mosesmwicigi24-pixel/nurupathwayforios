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
import CoreImage
import CoreMedia
import CoreVideo
import Foundation
import SwiftUI
import WebRTC
import os

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

    /// L6d — HOST-ONLY factory for `WhepSubscriber`'s guest-audio
    /// subscriptions, built with a custom `RTCAudioDevice`
    /// (`GuestAudioPlayoutDevice.shared`) so every accepted guest's decoded
    /// audio — pre-mixed by native ADM, since every `WhepSubscriber` peer
    /// connection on the host shares this ONE factory → ONE ADM → ONE
    /// `getPlayoutData` stream (confirmed against `RTCAudioDevice.h`, not
    /// guessed) — lands in our hands instead of going straight to the
    /// speaker via WebRTC's own session management. See
    /// GuestAudioPlayoutDevice.swift for the full mechanism and the
    /// deliberate scope limit (playout only). `WhipPublisher` (a guest's own
    /// outbound mic+camera) keeps using `shared` above, completely
    /// untouched, with WebRTC's normal default ADM.
    static let hostGuestAudio: RTCPeerConnectionFactory = {
        let encoderFactory = RTCDefaultVideoEncoderFactory()
        let decoderFactory = RTCDefaultVideoDecoderFactory()
        return RTCPeerConnectionFactory(encoderFactory: encoderFactory, decoderFactory: decoderFactory, audioDevice: GuestAudioPlayoutDevice.shared)
    }()

    /// One Metal-backed `CIContext` shared by every guest's
    /// `RTCFrameToSampleBufferSampler` (L6c stage compositing) — building a
    /// `CIContext` spins up its own Metal command queue/shader cache, so
    /// there's no reason to pay that per guest, only once for the app.
    static let compositingContext = CIContext(options: [.useSoftwareRenderer: false])

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
// directly, not the Nuru API. Auth is HTTP Basic, NOT query-string
// credentials — see `WhipBasicAuth`'s header comment for why.)

struct WhipExchangeResult { let answerSDP: String; let resourceURL: URL? }

/// MediaMTX (confirmed against the deployed v1.19.3) ignores `?user=&pass=`
/// query parameters on the WHIP/WHEP POST entirely — a controlled experiment
/// against production (2026-07-31: real guest device, empty user reached our
/// `/v1/live/auth` webhook even with the query string present) proved it.
/// The SAME request with an HTTP **Basic** `Authorization` header DID carry
/// the real username through. This type is the one place that builds that
/// header, so `WhipPublisher`/`WhepSubscriber` never touch credentials
/// directly and can't regress back to the query-string form.
///
/// Query-string credentials are also a plain leak risk (URLs land in proxy
/// logs, `os_log`, crash reports) that a header doesn't have — another
/// reason to prefer Basic even where it happens to also work.
enum WhipBasicAuth {
    static func headerValue(user: String, pass: String) -> String {
        let raw = "\(user):\(pass)"
        let encoded = Data(raw.utf8).base64EncodedString()
        return "Basic \(encoded)"
    }

    static func apply(user: String, pass: String, to request: inout URLRequest) {
        request.setValue(headerValue(user: user, pass: pass), forHTTPHeaderField: "Authorization")
    }
}

enum WhipHTTP {
    /// POST the local SDP offer to a bare WHIP/WHEP URL (no credentials in
    /// the URL — see `WhipBasicAuth`). MediaMTX answers 201 with the SDP
    /// answer as the body and a `Location` header pointing at the session
    /// resource (DELETE it to leave/stop).
    static func post(sdpOffer: String, to url: URL, user: String, pass: String) async throws -> WhipExchangeResult {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        WhipBasicAuth.apply(user: user, pass: pass, to: &req)
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
    ///
    /// MediaMTX's own WHIP/WHEP DELETE (and PATCH/trickle-ICE, unused here
    /// since we gather-then-send) handlers are keyed purely by the opaque
    /// session-secret UUID already embedded in the `Location` resource URL —
    /// verified against the mediamtx source (`onWHIPDelete`/`onWHIPPatch`
    /// parse+validate that UUID and never consult the authHTTP webhook), so
    /// this endpoint does NOT require the Basic header the POST needs. We
    /// send it anyway (harmless, and the caller already has the credentials
    /// in scope) as cheap defense-in-depth against a future MediaMTX version
    /// tightening that.
    static func delete(_ url: URL, user: String, pass: String) async {
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        WhipBasicAuth.apply(user: user, pass: pass, to: &req)
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

// MARK: - Guest video → CMSampleBuffer bridge (L6c stage compositing)

/// Converts one guest's incoming WebRTC video frames into `CMSampleBuffer`s
/// HaishinKit's `MediaMixer` can `append(_:track:)` — see
/// `LiveStageCompositor` for the compositing side and BroadcastController's
/// `syncGuestSubscribers` for where this gets wired to a `WhepSubscriber`.
///
/// `renderFrame(_:)` fires on WebRTC's own decode thread — exactly like the
/// existing `WebRTCVideoView.Coordinator` binding (`track.add(view)`). WebRTC
/// supports multiple simultaneous renderers per track, so this is a SECOND
/// sink added to the same track alongside the host's local guest-tile
/// preview (`LiveStageView`, unchanged) — one decode, two consumers, not two
/// decodes.
///
/// Always normalizes through `buffer.toI420()` — the one representation
/// EVERY `RTCVideoFrameBuffer` can produce (hardware `RTCCVPixelBuffer`
/// decode OR software `RTCI420Buffer`, per `RTCVideoFrameBuffer.h`'s
/// `toI420()` requirement) — rather than special-casing the CVPixelBuffer
/// path, so guests negotiating either H.264 (hardware decode) or VP8/VP9
/// (software) composite through the identical code path. Guests are already
/// capped to small, low-bitrate tiles (`WebRTCCamera.format` targets 640px,
/// `WebRTCSDP.capVideoBitrate` caps ~800kbps), so the extra conversion is
/// cheap against the compositor's 30fps budget.
///
/// Also un-rotates: `RTCVideoFrame.rotation` is metadata WebRTC's own
/// renderers apply at DISPLAY time — since this bypasses that and feeds
/// HaishinKit's compositor directly, rotation is baked into the pixel buffer
/// here via `CIImage.oriented(_:)` so guest video isn't sideways on stage.
final class RTCFrameToSampleBufferSampler: NSObject, RTCVideoRenderer {
    private static let logger = Logger(subsystem: "org.nuruplace.member", category: "RTCFrameToSampleBufferSampler")

    private let ciContext: CIContext
    private let onSampleBuffer: (CMSampleBuffer) -> Void
    private var pixelBufferPool: CVPixelBufferPool?
    private var pooledSize: CGSize = .zero
    private var hasLoggedFirstFrame = false

    init(ciContext: CIContext, onSampleBuffer: @escaping (CMSampleBuffer) -> Void) {
        self.ciContext = ciContext
        self.onSampleBuffer = onSampleBuffer
    }

    func setSize(_ size: CGSize) {
        // No-op — the output pixel buffer pool is (re)created lazily in
        // `renderFrame` from the frame's own already-rotated dimensions, so a
        // separate pre-rotation size callback would only race it.
    }

    /// Fires on WebRTC's decode thread (not hard-realtime like
    /// `GuestAudioPlayoutDevice`'s CoreAudio callback, but still a busy
    /// worker thread) at guest frame rate (~24-30fps) — so this logs only
    /// the FIRST frame as a one-time breadcrumb, never per-frame.
    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        guard let sampleBuffer = makeSampleBuffer(from: frame) else {
            Self.logger.error("renderFrame — makeSampleBuffer returned nil, dropping this frame")
            return
        }
        if !hasLoggedFirstFrame {
            hasLoggedFirstFrame = true
            Self.logger.notice("first guest video frame sampled — \(frame.width, privacy: .public)x\(frame.height, privacy: .public)")
        }
        onSampleBuffer(sampleBuffer)
    }

    private func makeSampleBuffer(from frame: RTCVideoFrame) -> CMSampleBuffer? {
        guard let image = uprightImage(from: frame) else { return nil }
        let size = image.extent.size
        guard size.width > 0, size.height > 0 else { return nil }
        if pixelBufferPool == nil || pooledSize != size {
            pixelBufferPool = Self.makePool(size: size)
            pooledSize = size
            if pixelBufferPool == nil {
                Self.logger.fault("makeSampleBuffer — CVPixelBufferPoolCreate failed for size \(size.width, privacy: .public)x\(size.height, privacy: .public)")
            }
        }
        guard let pool = pixelBufferPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let outBuffer = pixelBuffer else { return nil }
        ciContext.render(image, to: outBuffer)

        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: outBuffer, formatDescriptionOut: &formatDescription)
        guard let formatDescription else { return nil }

        let pts = CMTime(value: frame.timeStampNs, timescale: 1_000_000_000)
        var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: pts, decodeTimeStamp: .invalid)
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: outBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    /// Builds an upright `CIImage` from the I420 planes every
    /// `RTCVideoFrameBuffer` can produce — see this type's header comment for
    /// why this is the one path for both HW- and SW-decoded guests.
    private func uprightImage(from frame: RTCVideoFrame) -> CIImage? {
        let i420 = frame.buffer.toI420()
        guard let planar = Self.makePlanarPixelBuffer(from: i420) else { return nil }
        var image = CIImage(cvPixelBuffer: planar)
        // RTCVideoRotation's raw values (0/90/180/270) are stable — reading
        // `.rawValue` sidesteps any ambiguity in how the ObjC NS_ENUM case
        // names import into Swift.
        switch frame.rotation.rawValue {
        case 90: image = image.oriented(CGImagePropertyOrientation.right)
        case 180: image = image.oriented(CGImagePropertyOrientation.down)
        case 270: image = image.oriented(CGImagePropertyOrientation.left)
        default: break
        }
        // `.oriented` can report an extent with a non-zero origin — normalize
        // back to (0,0) so the pixel buffer render below isn't offset.
        let origin = image.extent.origin
        if origin != .zero {
            image = image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        }
        return image
    }

    private static func makePlanarPixelBuffer(from i420: any RTCI420BufferProtocol) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [kCVPixelBufferIOSurfacePropertiesKey: [:]]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(i420.width),
            Int(i420.height),
            kCVPixelFormatType_420YpCbCr8PlanarFullRange,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        copyPlane(src: i420.dataY, srcStride: Int(i420.strideY), dst: buffer, plane: 0, height: Int(i420.height))
        copyPlane(src: i420.dataU, srcStride: Int(i420.strideU), dst: buffer, plane: 1, height: Int(i420.chromaHeight))
        copyPlane(src: i420.dataV, srcStride: Int(i420.strideV), dst: buffer, plane: 2, height: Int(i420.chromaHeight))
        return buffer
    }

    private static func copyPlane(src: UnsafePointer<UInt8>, srcStride: Int, dst: CVPixelBuffer, plane: Int, height: Int) {
        guard let dstBase = CVPixelBufferGetBaseAddressOfPlane(dst, plane) else { return }
        let dstStride = CVPixelBufferGetBytesPerRowOfPlane(dst, plane)
        let rowBytes = min(srcStride, dstStride)
        for row in 0..<height {
            memcpy(dstBase.advanced(by: row * dstStride), src.advanced(by: row * srcStride), rowBytes)
        }
    }

    private static func makePool(size: CGSize) -> CVPixelBufferPool? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: Int(size.width),
            kCVPixelBufferHeightKey: Int(size.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, nil, attrs as CFDictionary, &pool)
        return pool
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
