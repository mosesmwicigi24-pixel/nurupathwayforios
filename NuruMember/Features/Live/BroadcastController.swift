// Nuru Live L3 — the broadcaster engine: owns the HaishinKit MediaMixer +
// RTMPConnection + RTMPStream, camera/mic capture, publish, reconnect/backoff,
// and viewer-count polling for GoLiveBroadcastView.
//
// RTMP target / MediaMTX "app" split (load-bearing — see CreatedLiveStream in
// Models/Live.swift for the URL construction):
//   MediaMTX's own documented OBS usage is Server = rtmp://host/mypath,
//   Stream Key = BLANK. ffmpeg confirms the same thing works when the whole
//   URL — including a query string — is one opaque connect target with
//   nothing appended as a separate stream name. HaishinKit's RTMPConnection
//   mirrors this exactly: `RTMPConnection.makeConnectionMessage()` builds the
//   RTMP "app" from the connect URL's path PLUS its raw query string
//   (confirmed by reading RTMPConnection.swift in the resolved 2.2.5
//   checkout), so `CreatedLiveStream.publishURL` (rtmp_url + ?user=&pass=)
//   becomes the WHOLE "app", and `stream.publish("")` (empty streamName) is
//   the other half — there is no separate stream name to give MediaMTX.
//
// HEVC vs H.264: HaishinKit 2.2.x can hardware-encode HEVC for RTMP publish
// (Enhanced RTMP v1), but the docs are explicit that Enhanced RTMP "also
// requires support on the server side" and we have no way to verify from
// this worktree which MediaMTX build/config is actually deployed on the VPS,
// nor how its HLS re-mux path (what every viewer — including older Android
// devices — actually plays) handles an Enhanced-RTMP HEVC ingest. H.264 at
// 1080p30/6Mbps is the well-worn, zero-surprise path: hardware-encoded on
// every iPhone in the fleet, and the exact codec the already-shipped L2
// viewer path (AVPlayer via HLS) was built and tested against. Documented
// here rather than guessed at.
//
// Audio level meter: HaishinKit's public API exposes an `AudioMonitor` for
// LOCAL playback-through-speaker monitoring, not a metering/RMS readout we
// can bind to a level meter. Wiring a real level would mean intercepting raw
// sample buffers via a custom MediaMixerOutput and computing RMS ourselves —
// out of scope for this pass. The audio-kind HUD therefore uses a tasteful
// animated placeholder waveform (LiveBroadcastWaveform, matching the Radio
// screen's Canvas-based sine-wave language) rather than real mic levels —
// documented, not silently faked as "real".
import AVFoundation
import HaishinKit
import RTMPHaishinKit
import UIKit
import VideoToolbox

@MainActor
final class BroadcastController: ObservableObject {
    enum Phase: Equatable {
        case configuring                    // requesting devices, building the mixer
        case live
        case reconnecting(attempt: Int)      // dropped; auto-retry in flight
        case failed(String)                 // retries exhausted — Retry / End choice
        case ended
    }

    enum EndedReason: Equatable { case summary, permissionDenied }

    let session: GoLiveSession
    @Published private(set) var phase: Phase = .configuring
    @Published private(set) var endedReason: EndedReason = .summary
    @Published private(set) var cameraPosition: AVCaptureDevice.Position = .back
    @Published private(set) var isMuted = false
    /// Capture orientation chosen from how the phone is held at go-live and
    /// LOCKED for the session (re-applied after a camera flip). Changing the
    /// encoded dimensions mid-publish would break viewers' players, so we don't
    /// rotate live — same behaviour as every pro broadcast app.
    private(set) var captureOrientation: AVCaptureVideoOrientation = .portrait
    @Published private(set) var startedAt: Date?
    @Published private(set) var endedAt: Date?
    @Published private(set) var viewerCount = 0
    @Published private(set) var peakViewerCount = 0

    // MARK: L5 interactive pulse — folded in alongside viewer-count polling
    // (same start/stop call sites) rather than a second poller: GET
    // /live/streams/{id}/pulse every 3s per docs/LIVE_INTERACTIVE.md, driving
    // the ✋ hand badge, the guests sheet, and the floating reaction overlay.
    @Published private(set) var pulse: LivePulse?
    /// Reactions newly seen since the previous pulse poll — GoLiveBroadcastView
    /// consumes these once (spawns a particle per entry) then calls
    /// `clearFreshReactions()`. The first poll seeds the seen-set without
    /// publishing anything, so going live never floods the HUD with a
    /// stream's entire reaction history at once.
    @Published private(set) var freshReactions: [LiveRecentReaction] = []
    private var seenReactionKeys: Set<String> = []
    private var isFirstPulsePoll = true
    private var pulsePollTask: Task<Void, Never>?

    var isVideo: Bool { session.kind == .video }

    private let connection: RTMPConnection
    private let stream: RTMPStream
    private let mixer = MediaMixer()
    private var mtView: MediaMixerOutput?
    private var isMixerReady = false

    private var connectionStatusTask: Task<Void, Never>?
    private var streamStatusTask: Task<Void, Never>?
    private var viewerPollTask: Task<Void, Never>?
    private var retryTask: Task<Void, Never>?
    private var retryAttempt = 0
    private var intentionallyStopped = false
    private var endInFlight = false

    /// Backoff schedule for auto-retry after a dropped connection — 3
    /// attempts, escalating, then a manual Retry/End choice.
    private static let backoffSeconds: [UInt64] = [2, 5, 10]

    init(session: GoLiveSession) {
        self.session = session
        let conn = RTMPConnection()
        connection = conn
        stream = RTMPStream(connection: conn)
    }

    // MARK: Start

    /// Requests devices, wires the mixer → stream pipeline, connects and
    /// publishes. Camera/mic permission was ALREADY granted in
    /// GoLiveSetupSheet before POST /live/streams ever fired — this is a
    /// defensive RE-check for the (rare) case access was revoked in the gap
    /// between the sheet and this screen. If it fails here, the stream row
    /// already exists server-side, so we must call /end ourselves rather
    /// than leaving it orphaned.
    func start() async {
        // Start the accelerometer feed early so UIDevice.current.orientation is
        // valid by the time configureMixer() reads it (the permission awaits
        // below give it time to settle).
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        if isVideo {
            guard await LiveBroadcastPermissions.requestCamera() == .granted else {
                await endOrphanedStream(reason: .permissionDenied)
                return
            }
        }
        guard await LiveBroadcastPermissions.requestMicrophone() == .granted else {
            await endOrphanedStream(reason: .permissionDenied)
            return
        }

        await configureMixer()
        observeStatus()
        await connectAndPublish()
    }

    private func configureMixer() async {
        try? await mixer.attachAudio(AVCaptureDevice.default(for: .audio))
        if isVideo {
            let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: cameraPosition)
            try? await mixer.attachVideo(device, track: 0)
            // Follow the phone: portrait → 1080×1920, landscape → 1920×1080.
            // Orientation is read once, here, and locked for the whole session.
            let geo = captureGeometry()
            captureOrientation = geo.orientation
            await mixer.setVideoOrientation(geo.orientation)
            try? await stream.setVideoSettings(VideoCodecSettings(
                videoSize: geo.size,
                bitRate: 6_000_000,
                profileLevel: kVTProfileLevel_H264_High_AutoLevel as String,
                scalingMode: .trim,
                bitRateMode: .average,
                maxKeyFrameIntervalDuration: 2
            ))
        }
        try? await stream.setAudioSettings(AudioCodecSettings(bitRate: 128_000))
        await mixer.addOutput(stream)
        try? await mixer.setFrameRate(30)
        await mixer.startRunning()
        isMixerReady = true
        if let mtView { await mixer.addOutput(mtView) }
    }

    /// The capture orientation + encode size for how the phone is PHYSICALLY held.
    /// The app UI is portrait-locked, so `interfaceOrientation` is useless here —
    /// we read the device's accelerometer orientation directly so the broadcaster
    /// can frame portrait OR landscape just by turning the phone at go-live.
    /// UIDeviceOrientation.landscapeLeft/Right are INVERTED relative to
    /// AVCaptureVideoOrientation (a long-standing AVFoundation quirk), hence the
    /// crossed mapping. faceUp/faceDown/unknown default to portrait.
    private func captureGeometry() -> (orientation: AVCaptureVideoOrientation, size: CGSize) {
        let landscape = CGSize(width: 1920, height: 1080)
        let portrait = CGSize(width: 1080, height: 1920)
        switch UIDevice.current.orientation {
        case .landscapeLeft: return (.landscapeRight, landscape)
        case .landscapeRight: return (.landscapeLeft, landscape)
        case .portraitUpsideDown: return (.portraitUpsideDown, portrait)
        default: return (.portrait, portrait)   // portrait, faceUp/Down, unknown
        }
    }

    private func connectAndPublish() async {
        do {
            _ = try await connection.connect(session.stream.publishURL)
            _ = try await stream.publish("")
            startedAt = startedAt ?? Date()
            retryAttempt = 0
            phase = .live
            UIApplication.shared.isIdleTimerDisabled = true
            startViewerPolling()
            startPulsePolling()
        } catch {
            await handleDropped()
        }
    }

    // MARK: Connection-drop handling — auto-retry with backoff, then a
    // manual Retry/End choice. Never spins forever silently.

    private func observeStatus() {
        connectionStatusTask?.cancel()
        connectionStatusTask = Task { [weak self] in
            guard let self else { return }
            for await status in await self.connection.status {
                guard !Task.isCancelled else { return }
                await self.handle(status)
            }
        }
        streamStatusTask?.cancel()
        streamStatusTask = Task { [weak self] in
            guard let self else { return }
            for await status in await self.stream.status {
                guard !Task.isCancelled else { return }
                await self.handle(status)
            }
        }
    }

    private func handle(_ status: RTMPStatus) async {
        guard !intentionallyStopped, phase == .live else { return }
        let dropCodes: Set<String> = [
            RTMPConnection.Code.connectClosed.rawValue,
            RTMPConnection.Code.connectFailed.rawValue,
            RTMPStream.Code.connectClosed.rawValue,
            RTMPStream.Code.connectFailed.rawValue,
            RTMPStream.Code.failed.rawValue,
        ]
        guard dropCodes.contains(status.code) else { return }
        await handleDropped()
    }

    private func handleDropped() async {
        guard !intentionallyStopped else { return }
        stopViewerPolling()
        stopPulsePolling()
        guard retryAttempt < Self.backoffSeconds.count else {
            phase = .failed("Lost connection to the stream after several tries.")
            return
        }
        let delay = Self.backoffSeconds[retryAttempt]
        retryAttempt += 1
        phase = .reconnecting(attempt: retryAttempt)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard let self, !Task.isCancelled, !self.intentionallyStopped else { return }
            await self.reattemptPublish()
        }
    }

    private func reattemptPublish() async {
        try? await connection.close()
        do {
            _ = try await connection.connect(session.stream.publishURL)
            _ = try await stream.publish("")
            phase = .live
            retryAttempt = 0
            startViewerPolling()
            startPulsePolling()
        } catch {
            await handleDropped()
        }
    }

    /// The manual "Retry" button from the failed state — a fresh 3-attempt run.
    func retryFromFailure() {
        guard case .failed = phase else { return }
        retryAttempt = 0
        phase = .reconnecting(attempt: 1)
        Task { await reattemptPublish() }
    }

    // MARK: Viewer count — poll GET /live/now every 15s, filter to our own id

    private func startViewerPolling() {
        viewerPollTask?.cancel()
        viewerPollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollViewers()
                try? await Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    private func stopViewerPolling() {
        viewerPollTask?.cancel()
        viewerPollTask = nil
    }

    private func pollViewers() async {
        guard let rows = try? await MemberAPI.fetchLiveNow(),
              let mine = rows.first(where: { $0.streamId == session.stream.streamId }) else { return }
        viewerCount = mine.viewerCount
        peakViewerCount = max(peakViewerCount, mine.viewerCount)
    }

    // MARK: L5 pulse — hand queue + guests roster + reaction feed, one GET
    // every 3s (see the header comment above `pulse`'s declaration).

    private func startPulsePolling() {
        pulsePollTask?.cancel()
        pulsePollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.pollPulse()
                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopPulsePolling() {
        pulsePollTask?.cancel()
        pulsePollTask = nil
    }

    /// Out-of-cadence refresh — called by LiveHandsGuestsSheet right after an
    /// invite/remove so the sheet reflects the change immediately rather than
    /// waiting out the rest of the 3s window.
    func pollPulseNow() async { await pollPulse() }

    func clearFreshReactions() { freshReactions = [] }

    private func pollPulse() async {
        guard let p = try? await MemberAPI.fetchLivePulse(streamId: session.stream.streamId) else { return }
        var newOnes: [LiveRecentReaction] = []
        for r in p.recentReactions {
            let key = "\(r.emoji)|\(r.at)"
            guard !seenReactionKeys.contains(key) else { continue }
            seenReactionKeys.insert(key)
            if !isFirstPulsePoll { newOnes.append(r) }
        }
        isFirstPulsePoll = false
        if seenReactionKeys.count > 500 { seenReactionKeys.removeAll() }
        pulse = p
        if !newOnes.isEmpty { freshReactions = newOnes }
    }

    // MARK: Controls

    func toggleMute() {
        Task {
            var settings = await mixer.audioMixerSettings
            settings.isMuted.toggle()
            await mixer.setAudioMixerSettings(settings)
            isMuted = settings.isMuted
        }
    }

    func flipCamera() {
        guard isVideo else { return }
        Task {
            let newPosition: AVCaptureDevice.Position = cameraPosition == .back ? .front : .back
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newPosition) else { return }
            try? await mixer.attachVideo(device, track: 0) { unit in
                unit.isVideoMirrored = (newPosition == .front)
            }
            await mixer.setVideoOrientation(captureOrientation)   // re-attach resets it — keep the locked orientation
            cameraPosition = newPosition
        }
    }

    // MARK: End / teardown

    /// User-confirmed End, a background-triggered end, a give-up-after-
    /// retries End, or the view's own `.onDisappear` (belt-and-suspenders
    /// teardown so the idle timer / stream can never be left dangling on an
    /// abnormal dismiss) — all funnel through here. `endInFlight` is set
    /// synchronously before the first `await`, so two concurrent callers
    /// (e.g. a manual End racing the view's onDisappear) can never both pass
    /// the guard — MainActor reentrancy only happens at suspension points.
    func end() async {
        guard phase != .ended, !endInFlight else { return }
        endInFlight = true
        await teardown()
        try? await MemberAPI.endLiveStream(streamId: session.stream.streamId)
        endedReason = .summary
        endedAt = Date()
        phase = .ended
        endInFlight = false
    }

    /// The stream row was already minted server-side (the setup sheet's POST
    /// succeeded) but we never actually attached/connected/published here —
    /// a defensive permission re-check failed. End it server-side so nothing
    /// is left "live" with no publisher, but skip the mixer/RTMP teardown
    /// (nothing was ever started) and mark this a permission-denied ending
    /// so the terminal view doesn't claim a broadcast happened.
    private func endOrphanedStream(reason: EndedReason) async {
        intentionallyStopped = true
        try? await MemberAPI.endLiveStream(streamId: session.stream.streamId)
        endedReason = reason
        phase = .ended
    }

    /// App backgrounded while live (video kind — see GoLiveBroadcastView's
    /// scenePhase handler for the documented video/audio tradeoff): iOS
    /// aggressively suspends camera capture in the background regardless of
    /// anything we do, so "try to keep publishing" would just silently die.
    /// Ending cleanly here is the honest choice — the summary screen still
    /// shows real elapsed/peak numbers.
    func handleBackgrounded() {
        guard phase == .live || isReconnectingOrConfiguring else { return }
        Task { await end() }
    }

    private var isReconnectingOrConfiguring: Bool {
        if case .reconnecting = phase { return true }
        return phase == .configuring
    }

    private func teardown() async {
        intentionallyStopped = true
        connectionStatusTask?.cancel(); connectionStatusTask = nil
        streamStatusTask?.cancel(); streamStatusTask = nil
        retryTask?.cancel(); retryTask = nil
        stopViewerPolling()
        stopPulsePolling()
        _ = try? await stream.close()
        try? await connection.close()
        await mixer.stopRunning()
        try? await mixer.attachAudio(nil)
        if isVideo { try? await mixer.attachVideo(nil, track: 0) }
        UIApplication.shared.isIdleTimerDisabled = false
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }
}

// MARK: - Camera preview source (MTHKViewRepresentable's connection point)

extension BroadcastController: MTHKViewRepresentable.PreviewSource {
    nonisolated func connect(to view: MTHKView) {
        Task { @MainActor in
            self.mtView = view
            if self.isMixerReady { await self.mixer.addOutput(view) }
        }
    }
}
