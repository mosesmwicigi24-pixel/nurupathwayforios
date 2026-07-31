// Nuru Live L6c — the finale: composites the ONE outgoing RTMP stream so
// every viewer sees everyone on stage, not just the host's own camera.
//
// Mechanism (confirmed by reading the checked-out HaishinKit 2.2.5 source —
// DerivedData/.../SourcePackages/checkouts/HaishinKit.swift/HaishinKit/Sources/
// Screen/*, Mixer/MediaMixer.swift, Mixer/VideoMixer.swift — not guessed):
// HaishinKit ships its own offscreen compositor. `MediaMixer.screen` is a
// `Screen` — a `ScreenObjectContainer` that, once
// `mixer.setVideoMixerSettings(.init(mode: .offscreen, mainTrack:))` is set,
// renders every `VideoTrackScreenObject` child on a display-link loop into
// ONE composited `CVPixelBuffer`/`CMSampleBuffer` fed to every output whose
// `videoTrackId == .max` (both `RTMPStream`, the publish path, and — unless
// repinned, see BroadcastController's `selectTrack(0, ...)` call on `mtView`
// — the local camera preview). `VideoMixer.append(track:sampleBuffer:)`
// confirms `.offscreen` mode is a pure "feed the compositor" path — in
// `.passthrough` mode (this app's ENTIRE pre-L6c history) the SAME
// `mixer.append(_:track:)` calls just short-circuit straight to the output
// with no compositing at all, so switching to `.offscreen` here changes
// nothing about how the host camera / Document / Screen sources feed track 0
// — it only adds the ability to layer MORE tracks on top.
//
// `Screen`'s own BUILT-IN `videoTrackScreenObject` (added once, in
// `Screen.init()`) is the "full-frame" object — its `track` is exactly
// `VideoMixerSettings.mainTrack`, reassignable at ANY time via
// `setVideoMixerSettings` without recreating anything. That reassignment IS
// the active-speaker swap: retarget `mainTrack` to a guest's track number and
// their video is instantly full-frame, no new screen object, no dimension
// change (the OUTPUT canvas — `Screen.size`, locked once in `activate(...)`
// to the session's already-locked encode size — never moves).
//
// Everyone who ISN'T currently `mainTrack` gets their own small
// `VideoTrackScreenObject` + `TextScreenObject` name label, positioned in a
// rounded-rectangle rail (bottom in portrait, right edge in landscape) via
// plain top-left `layoutMargin` offsets — `ScreenObject.makeBounds` resolves
// `.left`/`.top` alignment straight to `layoutMargin.left/top`, so the rail
// math below just computes an absolute (x, y, w, h) rect per slot and hands
// it over as a margin pair; no nested containers needed.
//
// Every mutation of `screen` (adding/removing/repositioning objects) MUST
// happen on `ScreenActor` — the actor HaishinKit itself uses for every
// `screen.*` touch inside `MediaMixer` (see e.g. `setVideoMixerSettings`'s
// `Task { @ScreenActor in screen.videoTrackScreenObject.track = ... }`).
// Making this whole type `@ScreenActor`-isolated mirrors that convention
// exactly, rather than sprinkling ad hoc `Task { @ScreenActor in }` blocks
// through BroadcastController.
import AVFoundation
import HaishinKit
import UIKit
import os

private let compositorLogger = Logger(subsystem: "org.nuruplace.member", category: "LiveStageCompositor")

@ScreenActor
final class LiveStageCompositor {
    private let mixer: MediaMixer

    private var encodeSize: CGSize = .zero
    private var isLandscape = false
    private(set) var mainTrack: UInt8 = 0

    /// Insertion order — host (track 0) first, then guests in join order.
    /// Whoever ISN'T `mainTrack` is laid out into the rail in this order.
    private var participants: [UInt8] = []
    private var videoObjects: [UInt8: VideoTrackScreenObject] = [:]
    private var labelObjects: [UInt8: TextScreenObject] = [:]

    private static let marginFraction: CGFloat = 0.03
    private static let spacingFraction: CGFloat = 0.018
    private static let tileWidthFraction: CGFloat = 0.20
    private static let cornerRadiusFraction: CGFloat = 0.02

    init(mixer: MediaMixer) {
        self.mixer = mixer
    }

    /// Locks the compositor's output canvas to the session's ALREADY-locked
    /// encode size (`BroadcastController.captureGeometry()`'s result — same
    /// value handed to `stream.setVideoSettings`) and switches the mixer into
    /// offscreen rendering with the host's own camera (track 0) as the sole,
    /// full-frame participant. Must run BEFORE `mixer.startRunning()` —
    /// `MediaMixer.startRunning()` reads `videoMixerSettings.mode` once, at
    /// call time, to decide whether to spin up the display-link render loop.
    func activate(encodeSize: CGSize) async {
        self.encodeSize = encodeSize
        isLandscape = encodeSize.width > encodeSize.height
        mixer.screen.size = encodeSize
        // `Screen.videoTrackScreenObject` (the built-in "main" object) is
        // `internal` to HaishinKit — not reachable from this module — so its
        // `videoGravity` stays the library default (`.resizeAspect`). That's
        // a no-op in the common case (the host's own camera buffer is
        // already exactly `encodeSize`, so aspect-fit == aspect-fill with
        // nothing to letterbox); a guest with a different aspect ratio
        // becoming the active speaker will letterbox rather than fill when
        // full-frame. Flagged honestly in PARITY_AUDIT.md rather than
        // reaching for a private-API workaround.
        participants = [0]
        mainTrack = 0
        await mixer.setVideoMixerSettings(VideoMixerSettings(mode: .offscreen, mainTrack: 0))
        addTile(track: 0, name: "You")
        relayout()
    }

    /// A newly accepted guest joins the stage — adds their rail tile (video
    /// starts as an empty rounded rect and fills in the moment their first
    /// `mixer.append(_:track:)` frame arrives; see BroadcastController's
    /// `WhepSubscriber.onVideoFrame` wiring) and reflows every other tile's
    /// position to make room.
    func addRailTile(track: UInt8, name: String) {
        guard !participants.contains(track) else {
            compositorLogger.notice("addRailTile — track \(track, privacy: .public) already a participant, ignoring")
            return
        }
        compositorLogger.notice("addRailTile — track \(track, privacy: .public)")
        participants.append(track)
        addTile(track: track, name: name)
        relayout()
    }

    /// A guest left (declined, removed, or the pulse roster swept them) —
    /// tears down their screen objects and reflows the remaining rail.
    func removeRailTile(track: UInt8) {
        guard participants.contains(track) else {
            compositorLogger.notice("removeRailTile — track \(track, privacy: .public) not a participant, ignoring")
            return
        }
        compositorLogger.notice("removeRailTile — track \(track, privacy: .public)")
        participants.removeAll { $0 == track }
        if let video = videoObjects.removeValue(forKey: track) { mixer.screen.removeChild(video) }
        if let label = labelObjects.removeValue(forKey: track) { mixer.screen.removeChild(label) }
        // The active speaker just left — fall back to the host rather than
        // leaving `mainTrack` pointing at a torn-down object.
        if mainTrack == track { mainTrack = 0 }
        relayout()
    }

    /// Swaps who's full-frame. A no-op if `track` isn't a known participant
    /// (e.g. a guest that already left) or is already main — callers (the
    /// active-speaker loop in BroadcastController) don't need to re-check
    /// membership themselves.
    func setMainTrack(_ track: UInt8) async {
        guard participants.contains(track), track != mainTrack else { return }
        mainTrack = track
        await mixer.setVideoMixerSettings(VideoMixerSettings(mode: .offscreen, mainTrack: track))
        relayout()
    }

    /// Broadcast ending — removes every screen object and reverts the mixer
    /// to plain passthrough (harmless either way since the mixer is about to
    /// stop running entirely, but leaves no dangling `.offscreen` state
    /// behind for anything inspecting `mixer.videoMixerSettings` during
    /// teardown).
    func teardown() async {
        for track in participants {
            if let video = videoObjects.removeValue(forKey: track) { mixer.screen.removeChild(video) }
            if let label = labelObjects.removeValue(forKey: track) { mixer.screen.removeChild(label) }
        }
        participants.removeAll()
        mainTrack = 0
        await mixer.setVideoMixerSettings(.default)
    }

    // MARK: - Internal

    private func addTile(track: UInt8, name: String) {
        let video = VideoTrackScreenObject()
        video.track = track
        video.videoGravity = .resizeAspectFill
        video.cornerRadius = cornerRadius
        do {
            try mixer.screen.addChild(video)
        } catch {
            // Never propagate — a failed screen-object add must degrade to
            // "this guest's tile stays a blank rounded rect" (their WHEP
            // subscriber is still live and unaffected), never take down the
            // compositor or the host's own publish.
            compositorLogger.error("addTile — addChild(video) failed for track \(track, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        videoObjects[track] = video

        let label = TextScreenObject()
        label.string = name
        label.attributes = [
            .font: UIFont.boldSystemFont(ofSize: max(12, tileSize.height * 0.14)),
            .foregroundColor: UIColor.white,
            .strokeColor: UIColor.black,
            .strokeWidth: -2
        ]
        try? mixer.screen.addChild(label)
        labelObjects[track] = label
    }

    private var tileSize: CGSize {
        let short = min(encodeSize.width, encodeSize.height)
        let width = short * Self.tileWidthFraction
        return CGSize(width: width, height: width * 4 / 3)
    }

    private var cornerRadius: CGFloat {
        min(encodeSize.width, encodeSize.height) * Self.cornerRadiusFraction
    }

    /// Recomputes from scratch every time (add/remove/main-swap) rather than
    /// incrementally — simpler to reason about and cheap: at most 6 guests +
    /// the host, once per event, never per-frame.
    private func relayout() {
        guard encodeSize != .zero else { return }
        let short = min(encodeSize.width, encodeSize.height)
        let margin = short * Self.marginFraction
        let spacing = short * Self.spacingFraction
        let size = tileSize
        let railTracks = participants.filter { $0 != mainTrack }

        for (index, track) in railTracks.enumerated() {
            let rect = railRect(index: index, size: size, margin: margin, spacing: spacing)
            if let video = videoObjects[track] {
                video.isVisible = true
                video.size = rect.size
                video.horizontalAlignment = .left
                video.verticalAlignment = .top
                video.layoutMargin = UIEdgeInsets(top: rect.minY, left: rect.minX, bottom: 0, right: 0)
                video.cornerRadius = cornerRadius
            }
            if let label = labelObjects[track] {
                label.isVisible = true
                label.size = CGSize(width: max(0, rect.width - 12), height: 0)
                label.horizontalAlignment = .left
                label.verticalAlignment = .top
                let labelY = max(rect.minY, rect.maxY - size.height * 0.22)
                label.layoutMargin = UIEdgeInsets(top: labelY, left: rect.minX + 6, bottom: 0, right: 0)
            }
        }

        // The active speaker's own rail tile+label are hidden — they're
        // already shown full-frame via the built-in
        // `screen.videoTrackScreenObject` (its `track` == `mainTrack`), so
        // never double them up.
        videoObjects[mainTrack]?.isVisible = false
        labelObjects[mainTrack]?.isVisible = false
    }

    private func railRect(index: Int, size: CGSize, margin: CGFloat, spacing: CGFloat) -> CGRect {
        if isLandscape {
            let x = encodeSize.width - margin - size.width
            let y = margin + CGFloat(index) * (size.height + spacing)
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        } else {
            let x = margin + CGFloat(index) * (size.width + spacing)
            let y = encodeSize.height - margin - size.height
            return CGRect(x: x, y: y, width: size.width, height: size.height)
        }
    }
}
