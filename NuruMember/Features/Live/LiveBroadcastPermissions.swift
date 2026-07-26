// Nuru Live L3 — camera/mic runtime-permission requests for broadcasting.
// Mirrors two existing, already-shipped idioms exactly rather than inventing
// a third: CheckInScannerView's ScanCameraModel (camera: authorizationStatus
// / requestAccess) and ChatVoice.swift / VoiceNoteCard.swift (mic:
// AVAudioApplication.requestRecordPermission).
//
// Used in TWO places by design: the setup sheet calls `requestForKind` BEFORE
// POST /live/streams so a hard denial never mints an orphaned stream row, and
// BroadcastController re-derives the same states defensively when the
// broadcast screen appears (in case access was revoked in the gap between
// the sheet and the screen), driving a CheckInScannerView-style denied view
// with an "Open Settings" pointer.
import AVFoundation

enum LiveBroadcastPermission: Equatable, Sendable { case unknown, granted, denied }

enum LiveBroadcastPermissions {
    /// Camera authorization, requesting it if not yet determined.
    static func requestCamera() async -> LiveBroadcastPermission {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .granted
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            return ok ? .granted : .denied
        default:
            return .denied
        }
    }

    /// Microphone authorization via AVAudioApplication (iOS 17+ API, already
    /// the house pattern for chat voice notes).
    static func requestMicrophone() async -> LiveBroadcastPermission {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }

    /// Requests whatever a broadcast kind actually needs. `camera` stays
    /// `.unknown` for an audio-only session — it's never asked, so "denied"
    /// would be a lie and "granted" would be a promise we didn't check.
    static func requestForKind(_ kind: LiveBroadcastKind) async -> (camera: LiveBroadcastPermission, mic: LiveBroadcastPermission) {
        let mic = await requestMicrophone()
        guard kind == .video else { return (.unknown, mic) }
        let camera = await requestCamera()
        return (camera, mic)
    }
}
