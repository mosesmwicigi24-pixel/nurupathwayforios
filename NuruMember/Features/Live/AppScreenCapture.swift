// Nuru Live "Broadcast Studio" — Document/Screen source capture.
//
// Wraps ReplayKit's IN-APP capture API — `RPScreenRecorder.startCapture(handler:)`
// — NOT `RPBroadcastController`/`startBroadcast`, which needs a separate
// Broadcast Upload Extension target, a system picker, and (for a full
// system-wide screen share) a Broadcast Upload entitlement we don't have and
// don't need. `startCapture(handler:)` requires none of that: it hands this
// PROCESS a live stream of CMSampleBuffers for whatever this app is
// rendering to its own window, no extension, no system broadcast picker —
// exactly "in-app capture" per Apple's ReplayKit docs. First call surfaces
// the standard one-time "NuruMember Would Like to Record This App's Screen"
// system prompt; NSCameraUsageDescription doesn't cover this — ReplayKit's
// prompt is system-owned copy, no Info.plist key required for in-app capture.
//
// Confirmed against MediaMixer.swift in the resolved HaishinKit 2.2.5
// checkout (DerivedData/SourcePackages/checkouts/HaishinKit.swift):
// `MediaMixer.append(_ sampleBuffer: CMSampleBuffer, track: UInt8 = 0)` is a
// PUBLIC, documented manual-append path ("Appends a CMSampleBuffer") that
// routes straight into the same VideoMixer pipeline a physical AVCaptureDevice
// feeds — so a ReplayKit .video buffer for track 0 is indistinguishable, once
// appended, from a camera frame. BroadcastController pairs every append with
// `mixer.attachVideo(nil, track: 0)` first (detaching the camera's AVCaptureSession
// connection — see VideoCaptureUnit.swift's `attachVideo`) so there's exactly
// one producer for track 0 at a time, never two racing.
import AVFoundation
import ReplayKit

@MainActor
final class AppScreenCapture {
    enum CaptureError: Error { case unavailable }

    private(set) var isCapturing = false
    private var onVideoBuffer: (@Sendable (CMSampleBuffer) -> Void)?

    /// Starts in-app screen capture and forwards VIDEO sample buffers only —
    /// ReplayKit also offers `.audioApp`/`.audioMic` buffer types, but those
    /// are deliberately ignored: HaishinKit's own `audioIO` (the mic already
    /// attached in `configureMixer()`) stays the ONE audio pipeline for the
    /// whole broadcast, document/screen source switches included, so muting
    /// or the audio meter never has two competing tracks to reconcile.
    /// `isMicrophoneEnabled = false` stops ReplayKit from even opening a
    /// second mic tap.
    func start(onVideoBuffer: @escaping @Sendable (CMSampleBuffer) -> Void) async throws {
        let recorder = RPScreenRecorder.shared()
        guard recorder.isAvailable else { throw CaptureError.unavailable }
        recorder.isMicrophoneEnabled = false
        recorder.isCameraEnabled = false
        self.onVideoBuffer = onVideoBuffer
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            recorder.startCapture { buffer, type, error in
                guard error == nil, type == .video else { return }
                onVideoBuffer(buffer)
            } completionHandler: { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        isCapturing = true
    }

    func stop() async {
        guard isCapturing else { return }
        isCapturing = false
        onVideoBuffer = nil
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            RPScreenRecorder.shared().stopCapture { _ in continuation.resume() }
        }
    }
}
