// Nuru Live L6c/L7 — composites the ONE outgoing RTMP stream so every
// viewer sees everyone on stage, not just the host's own camera, Zoom-style:
// one full-bleed main tile (whoever's spotlighted) + a rail of thumbnails
// down the right edge for everyone else, tap-to-expand reversible.
//
// L7 REWRITE — root-causing two defects the L6c version had (owner report,
// live-tested):
//
// DEFECT A — "the 1080x1920 portrait seems to be lost a bit" once a guest
// becomes active. PROVEN root cause (read, not guessed, in the checked-out
// HaishinKit 2.2.5 source — Screen.swift, VideoTrackScreenObject.swift):
// `Screen`'s BUILT-IN `videoTrackScreenObject` — the object
// `setVideoMixerSettings(mainTrack:)` retargets — is `internal` to
// HaishinKit, unreachable from this module, so its `videoGravity` is
// PERMANENTLY stuck at the library default `.resizeAspect`. And
// `VideoTrackScreenObject.makeBounds` special-cases `.resizeAspect` to
// ASPECT-FIT the source image inside its bounds (scaling the object's own
// rect down, not the image up) — harmless for the host (their 1080x1920
// camera buffer already matches the canvas exactly: scale=1, no-op), but
// for L6c's guest tracks (960x540 landscape, per the task brief) becoming
// `mainTrack` this fit-scales them into a ~1080×608 band pinned to the
// top-left with the rest of the 1080x1920 canvas showing through
// underneath — a severe, real letterbox, not a metaphor. The CANVAS size
// itself (`Screen.size`, locked once in `activate()`) never moved — this
// was a rendering-gravity bug, not a dimension bug, which is exactly why
// "log the encoder dimensions" alone wouldn't have caught it (they're
// unchanged) and why this rewrite ALSO changes the compositing strategy,
// not just adds logging.
//
// DEFECT B — "the host video is completely replaced by invited guest."
// Root cause: L6c's `setMainTrack` retargeted the SAME built-in object
// away from the host entirely, and BroadcastController auto-drove that
// retarget from a raw audio-level threshold the instant any guest made
// noise — there was no "composite," just a full swap, and no user control
// over it either.
//
// THE FIX for both, in one move: NEVER retarget the built-in object again
// after `activate()` — it stays pinned to the host (track 0) for the
// entire broadcast, so its `.resizeAspect` quirk only ever applies to a
// track that already matches canvas geometry exactly (no letterbox,
// provably, for as long as that pin holds). Spotlighting a GUEST instead
// draws a SEPARATE, fully app-owned `VideoTrackScreenObject` — `mainOverlay`
// — on top of it, full-canvas, with `videoGravity = .resizeAspectFill`
// (which THIS module CAN set, since we own the object). Being added to
// `screen` after the built-in object, it occludes it completely
// (`ScreenObjectContainer.draw` draws children in insertion order, later =
// on top — confirmed by reading `ScreenObjectContainer.swift`), so
// whichever track `mainOverlay.track` points at is rendered full-bleed,
// aspect-filled, zero letterbox — host or guest, no exceptions. Spotlight
// swaps are now a single `@ScreenActor` property write on OUR OWN object
// (`mainOverlay.track = target`) — `mixer.setVideoMixerSettings` is called
// EXACTLY ONCE per broadcast, in `activate()`, and never again: guest
// join/leave/spotlight changes touch zero mixer/encoder state, which is
// what makes "identical geometry and bitrate regardless of guest count" a
// property of the code rather than a hope. `activate()` and every rail
// mutation log `mixer.screen.size` so that invariant is provable from logs,
// not just argued in a comment.
//
// Layout math (rail-tile rects, corner radius) is delegated to
// LiveStageLayout — the SAME file BroadcastController's SwiftUI stage
// (LiveStageView) calls for the host's own local preview, so compositor
// output and host preview can't independently drift.
//
// Every mutation of `screen` (adding/removing/repositioning objects) MUST
// happen on `ScreenActor` — the actor HaishinKit itself uses for every
// `screen.*` touch inside `MediaMixer`. Making this whole type
// `@ScreenActor`-isolated mirrors that convention exactly, rather than
// sprinkling ad hoc `Task { @ScreenActor in }` blocks through
// BroadcastController.
import AVFoundation
import HaishinKit
import UIKit
import os

private let compositorLogger = Logger(subsystem: "org.nuruplace.member", category: "LiveStageCompositor")

@ScreenActor
final class LiveStageCompositor {
    private let mixer: MediaMixer

    private var encodeSize: CGSize = .zero
    private(set) var spotlighted: UInt8 = LiveStageSpotlight.host

    /// Insertion order — host (track 0) first, then guests in join order.
    /// Whoever ISN'T `spotlighted` is laid out into the rail in this order
    /// (stable — LiveStageLayout.railRects preserves array order 1:1).
    private var participants: [UInt8] = []
    private var names: [UInt8: String] = [:]
    private var mutedTracks: Set<UInt8> = []
    private var videoObjects: [UInt8: VideoTrackScreenObject] = [:]
    private var labelObjects: [UInt8: TextScreenObject] = [:]

    /// App-owned full-canvas overlay — see header comment. `nil` `.track`
    /// state is never observed after `activate()`; it always mirrors
    /// `spotlighted`.
    private var mainOverlay: VideoTrackScreenObject?

    init(mixer: MediaMixer) {
        self.mixer = mixer
    }

    /// Locks the compositor's output canvas to the session's ALREADY-locked
    /// encode size (`BroadcastController.captureGeometry()`'s result — same
    /// value handed to `stream.setVideoSettings`), switches the mixer into
    /// offscreen rendering with the host (track 0) as the built-in object's
    /// permanent target, and adds `mainOverlay` — the app-owned full-bleed
    /// tile every future spotlight swap actually retargets. Must run BEFORE
    /// `mixer.startRunning()` — `MediaMixer.startRunning()` reads
    /// `videoMixerSettings.mode` once, at call time, to decide whether to
    /// spin up the display-link render loop.
    ///
    /// THIS is the only call, ever, to `mixer.setVideoMixerSettings` for
    /// the lifetime of the broadcast — see header comment. Logs
    /// `mixer.screen.size` so "canvas never moves" is provable from device
    /// logs, not just asserted.
    func activate(encodeSize: CGSize) async {
        self.encodeSize = encodeSize
        mixer.screen.size = encodeSize
        participants = [0]
        names[0] = "You"
        spotlighted = 0
        await mixer.setVideoMixerSettings(VideoMixerSettings(mode: .offscreen, mainTrack: 0))

        let overlay = VideoTrackScreenObject()
        overlay.track = 0
        overlay.videoGravity = .resizeAspectFill
        overlay.cornerRadius = 0
        do {
            try mixer.screen.addChild(overlay)
            mainOverlay = overlay
        } catch {
            compositorLogger.error("activate — addChild(mainOverlay) failed: \(String(describing: error), privacy: .public)")
        }

        addTile(track: 0, name: "You")
        relayout()
        compositorLogger.notice("activate — encodeSize=\(encodeSize.width, privacy: .public)x\(encodeSize.height, privacy: .public) screen.size=\(self.mixer.screen.size.width, privacy: .public)x\(self.mixer.screen.size.height, privacy: .public)")
    }

    /// A newly accepted guest joins the stage — adds their rail tile (video
    /// starts as an empty rounded rect and fills in the moment their first
    /// `mixer.append(_:track:)` frame arrives; see BroadcastController's
    /// `WhepSubscriber.onVideoFrame` wiring) and reflows every other tile's
    /// position to make room. Never touches the mixer/encoder — canvas size
    /// is logged before and after specifically to prove that.
    func addRailTile(track: UInt8, name: String) {
        guard !participants.contains(track) else {
            compositorLogger.notice("addRailTile — track \(track, privacy: .public) already a participant, ignoring")
            return
        }
        let before = mixer.screen.size
        compositorLogger.notice("addRailTile — track \(track, privacy: .public) screen.size(before)=\(before.width, privacy: .public)x\(before.height, privacy: .public)")
        participants.append(track)
        names[track] = name
        addTile(track: track, name: name)
        relayout()
        let after = mixer.screen.size
        compositorLogger.notice("addRailTile — track \(track, privacy: .public) screen.size(after)=\(after.width, privacy: .public)x\(after.height, privacy: .public)")
    }

    /// A guest left (declined, removed, or the pulse roster swept them) —
    /// tears down their screen objects and reflows the remaining rail. If
    /// they were spotlighted, `BroadcastController` will already have
    /// called `spotlight(track: 0)` (via `LiveStageSpotlight.participantLeft`)
    /// before this runs, so `mainOverlay` never dangles on a torn-down
    /// track.
    func removeRailTile(track: UInt8) {
        guard participants.contains(track) else {
            compositorLogger.notice("removeRailTile — track \(track, privacy: .public) not a participant, ignoring")
            return
        }
        let before = mixer.screen.size
        compositorLogger.notice("removeRailTile — track \(track, privacy: .public) screen.size(before)=\(before.width, privacy: .public)x\(before.height, privacy: .public)")
        participants.removeAll { $0 == track }
        names.removeValue(forKey: track)
        mutedTracks.remove(track)
        if let video = videoObjects.removeValue(forKey: track) { mixer.screen.removeChild(video) }
        if let label = labelObjects.removeValue(forKey: track) { mixer.screen.removeChild(label) }
        relayout()
        let after = mixer.screen.size
        compositorLogger.notice("removeRailTile — track \(track, privacy: .public) screen.size(after)=\(after.width, privacy: .public)x\(after.height, privacy: .public)")
    }

    /// Swaps who's full-frame by retargeting ONLY `mainOverlay` — never the
    /// mixer/encoder. A no-op if `track` isn't a known participant (e.g. a
    /// guest that already left) or is already spotlighted — callers (the
    /// stage-tap handler in BroadcastController) don't need to re-check
    /// membership themselves.
    func spotlight(track: UInt8) {
        guard participants.contains(track), track != spotlighted else { return }
        spotlighted = track
        mainOverlay?.track = track
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
        if let overlay = mainOverlay { mixer.screen.removeChild(overlay) }
        mainOverlay = nil
        participants.removeAll()
        names.removeAll()
        mutedTracks.removeAll()
        spotlighted = LiveStageSpotlight.host
        await mixer.setVideoMixerSettings(.default)
    }

    /// Best-effort mic-muted indicator on a guest's rail tile — see
    /// BroadcastController's header comment on `guestMuteHeuristic` for the
    /// honest limitation: WebRTC's `MediaStreamTrack.enabled` is a
    /// LOCAL-only flag (not synced to the remote peer) and no server field
    /// carries a guest's own mute state today, so this is driven by a
    /// sustained-silence heuristic, not a definitive "they tapped mute"
    /// signal. Folded into the name label (◦ prefix) since HaishinKit's
    /// screen-object toolkit has no icon/glyph primitive — plain text is
    /// the only thing `TextScreenObject` can render.
    func setMuted(track: UInt8, isMuted: Bool) {
        guard participants.contains(track) else { return }
        if isMuted { mutedTracks.insert(track) } else { mutedTracks.remove(track) }
        guard let label = labelObjects[track] else { return }
        let name = names[track] ?? ""
        label.string = isMuted ? "\u{1F507} \(name)" : name
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
        LiveStageLayout.railRects(count: 1, canvas: encodeSize).first?.size ?? .zero
    }

    private var cornerRadius: CGFloat {
        LiveStageLayout.cornerRadius(canvas: encodeSize)
    }

    /// Recomputes from scratch every time (add/remove/spotlight-swap) rather
    /// than incrementally — simpler to reason about and cheap: at most 6
    /// guests + the host, once per event, never per-frame.
    private func relayout() {
        guard encodeSize != .zero else { return }
        let railTracks = participants.filter { $0 != spotlighted }
        let rects = LiveStageLayout.railRects(count: railTracks.count, canvas: encodeSize)
        let radius = cornerRadius

        for (index, track) in railTracks.enumerated() {
            guard index < rects.count else { continue }
            let rect = rects[index]
            if let video = videoObjects[track] {
                video.isVisible = true
                video.size = rect.size
                video.horizontalAlignment = .left
                video.verticalAlignment = .top
                video.layoutMargin = UIEdgeInsets(top: rect.minY, left: rect.minX, bottom: 0, right: 0)
                video.cornerRadius = radius
            }
            if let label = labelObjects[track] {
                label.isVisible = true
                label.size = CGSize(width: max(0, rect.width - 12), height: 0)
                label.horizontalAlignment = .left
                label.verticalAlignment = .top
                let labelY = max(rect.minY, rect.maxY - rect.height * 0.22)
                label.layoutMargin = UIEdgeInsets(top: labelY, left: rect.minX + 6, bottom: 0, right: 0)
            }
        }

        // The spotlighted participant's own rail tile+label are hidden —
        // they're already shown full-frame via `mainOverlay`, so never
        // double them up.
        videoObjects[spotlighted]?.isVisible = false
        labelObjects[spotlighted]?.isVisible = false
    }
}
