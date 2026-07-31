
## 2026-07-31 — Nuru Live L6b: real guest video over WHIP/WHEP (branch feat/live-l6b-guest-video, this repo only)
Replaces every "video joins in the next update" placeholder from L6a with
real WebRTC video/audio — guests actually publish, the host actually sees
and hears them. Built against the LIVE, already-deployed MediaMTX WHIP/WHEP
endpoint (`https://pathway.nuruplace.org/webrtc/`) and the pinned wire facts
handed down for this pass; verified those facts against the actual backend
source (`packages/backend/src/modules/live/service.ts` — `guestIngest`,
`authGuestPublish`, `authGuestRead`, `guestPathFor`) before writing a line of
client code, since "PINNED... do not change" is only as good as what's
actually running.

**1. Dependency.** Added SPM package `https://github.com/stasel/WebRTC`
(binary Google WebRTC build, M150/150.0.0 — the current latest release,
confirmed via the GitHub API rather than guessed) to
`NuruMember.xcodeproj/project.pbxproj`, mirroring the existing HaishinKit
`XCRemoteSwiftPackageReference`/`XCSwiftPackageProductDependency` pattern
exactly. `NuruMember/` is a `PBXFileSystemSynchronizedRootGroup` (Xcode 16
file-system-synchronized group), so every new Swift file below needed zero
manual "add to target" pbxproj surgery — only the package itself did.

**2. Wire layer.** `Models/LiveInteractions.swift`: `LiveGuestRow` gains
`whepUrl: String?` (owner-only, accepted-only — decodes tolerantly to nil
for everyone else, matching the backend's own `whep_url?` field); new
`GuestIngest` DTO for `GET /live/streams/{id}/guests/me/ingest`.
`Networking/MemberAPI+LiveInteractions.swift`: `fetchLiveGuestIngest`.

**3. `WebRTCSupport.swift`** (new, shared plumbing): one app-wide
`RTCPeerConnectionFactory` (`WebRTCFactory`); `RTCConfiguration` with a
public STUN server (`stun.l.google.com:19302` — needed so a device behind
NAT gathers a usable server-reflexive candidate; MediaMTX itself needs
none, it's already on a public IP with UDP 8189 open) + `.unifiedPlan` +
`.gatherOnce`; a no-op `RTCPeerConnectionDelegate` base class
(`WebRTCPeerConnectionObserver`, `nonisolated` methods hopping to
`@MainActor` — WhipPublisher/WhepSubscriber each only override the 1-2
callbacks they actually care about); `WebRTCSDP` (offer/setLocal/setRemote
wrapped in `withCheckedThrowingContinuation`, deliberately NOT relying on
Swift's auto-bridged async sugar for ObjC completion handlers — couldn't
verify the exact auto-generated signatures without a live compile, and
guessing wrong there is a silent trap); gather-then-send ICE waiting (capped
4s, per the task's own pinned guidance — no trickle-ICE signaling channel
needed for a one-shot WHIP/WHEP POST); `WhipHTTP` (raw `URLSession` POST/
DELETE against MediaMTX directly — not `APIClient`, since this is
`application/sdp` with query-string credentials, not the Nuru API's bearer-
JSON contract); `WebRTCCamera` (front camera, closest-to-640×480 format,
capped fps); `WebRTCVideoView` (`UIViewRepresentable` around
`RTCMTLVideoView`, same idiom as HaishinKit's own `MTHKViewRepresentable`).

**4. `WhipPublisher.swift`** (new) — the GUEST's outbound publish: sendonly
mic (Opus) + front-camera (~640×480@≤24fps, capped 800kbps via
`RTCRtpEncodingParameters.maxBitrateBps`) transceivers, offer → gather →
POST `whipUrl?user=<myUserId>&pass=<token>` → answer, `.idle → .connecting →
.live/.failed` state machine (a `generation` counter guards every awaited
step against a stale start racing a stop — e.g. a fast accepted→removed→
accepted flap). `toggleMute()` flips the local audio track's `isEnabled`.
`stop()` best-effort DELETEs the WHIP session resource before tearing down
the peer connection and capturer.

**5. `WhepSubscriber.swift`** (new) — the HOST's inbound subscribe, one
instance per accepted guest: recvonly (constraint-based
`OfferToReceiveAudio/Video`), same offer/gather/POST/answer dance against
`whepUrl?user=<streamId>&pass=<streamKey>` (the STREAM's own broadcast
credentials — the owner, not the guest). Remote video track arrives via
`didAdd rtpReceiver:streams:`; remote audio needs no explicit handling —
WebRTC plays it out on its own once the track exists.

**6. Host wiring** (`BroadcastController.swift`) — `syncGuestSubscribers`,
called from the existing 3s `pollPulse()` right after `pulse = p`: diffs
`pulse.guests` (accepted + `whepUrl != nil`) against a
`[userId: WhepSubscriber]` dict, starting new ones and stopping/dropping
fallen-off ones; publishes `guestTiles: [GuestTileState]` for the UI.
Cleaned up in `teardown()` alongside everything else. `GuestTileRail.swift`
(new) renders up to 6 rounded 96×128 tiles (camera feed once `.live`,
spinner while `.connecting`, warning glyph if `.failed`) as ONE draggable
unit over the preview — same drag-anywhere idiom as
`LiveFloatingChatOverlay` (`GestureState` translation + settled offset,
clamped on-screen), default top-leading (the one open corner: hands/source
buttons are top-trailing, chat defaults bottom-leading). Wired into
`GoLiveBroadcastView` as a full-bleed `.overlay`.
`LiveHandsGuestsSheet.swift`'s guest row now reads the REAL state
("Connecting…" / "On stage now" / "Video trouble — still on the guest
list") instead of the old static "video in the next update" line.

**7. Guest wiring** (`GuestStageOverlay.swift`, new + `LiveViewerPlayerView.
swift`) — `syncGuestStage`, called from the existing `pulse.guests`
`onChange`: the FIRST time my own row reads `accepted`, fetches
`GuestIngest` and starts `WhipPublisher`; the instant it stops being
`accepted` (removed, declined, left, stream ended), stops it. Replaces the
old static "You're on stage soon — video joins in the next update" gold
banner ENTIRELY with `GuestStagePiP` — a draggable self-preview tile
(spinner while connecting, real `WebRTCVideoView` self-preview once live, a
mic-mute toggle, an honest error+Retry chip on failure) plus a red "Leave
stage" pill (`removeLiveGuest(userId: me)` = self-leave, per the existing
L5 contract). The gold INVITE banner (`status == "invited"`, not yet
accepted) is untouched — same auto-collapse-to-pill taste-pass behavior as
before, just no longer also covering "accepted". HLS playback auto-mutes
(`LiveViewerPlayerController.setSelfEchoMuted`) for the whole "I'm an
accepted guest" window — not just once WHIP goes live — with a small "Muted
while on stage" caption, so my own voice never echoes back over the HLS
pipeline's several-second delay.

**8. AVAudioSession coexistence** (`WebRTCAudioCoexistence`, in
`WebRTCSupport.swift`) — the HOST device runs HaishinKit (own outgoing mic)
and WebRTC (a guest's incoming audio) against the SAME shared
`AVAudioSession` at once. WebRTC's `RTCAudioSession` auto-configures/
activates that session itself by default the moment a peer connection with
audio goes live; HaishinKit's `AVCaptureSession` already does the same for
the broadcaster's own mic
(`automaticallyConfiguresApplicationAudioSession = true`, confirmed by
reading `VideoCaptureUnit.swift` in the resolved HaishinKit checkout — same
precedent as `BroadcastController`'s own background-capture comment).
`useManualAudio = true` + `isAudioEnabled = true`, set once (lazily, the
first time a WhepSubscriber spins up) tells WebRTC to stop touching
`setCategory`/`setActive` itself and just run its audio unit against
whatever session HaishinKit already has active — `.playAndRecord` already
supports simultaneous playback, so a guest's decoded audio should play out
over it without WebRTC ever fighting HaishinKit for the category/activation
state. The GUEST/viewer side deliberately does NOT get this treatment —
there, WebRTC is the only framework touching audio capture at all (AVPlayer's
own `.playback` category has no recording claim to defend), so leaving
WebRTC's automatic session management on is correct: it needs to promote
`.playback` → `.playAndRecord` itself the moment publishing starts.
**Caveat, stated plainly:** this is designed from reading both frameworks'
documented/source behavior, not verified against a live device with a real
second guest — there is no way to exercise "does the broadcaster's mic
glitch when a guest joins" from `xcodebuild test`.

**9. Congregation-hears-guests (the reach goal) — did NOT ship, honestly.**
Read the actual libwebrtc ObjC headers at `webrtc.googlesource.com/src`
(`sdk/objc/api/peerconnection/RTCAudioTrack.h`, `RTCAudioSource.h`) before
attempting anything: there is NO public `RTCAudioRenderer`/audio-sink API on
`RTCAudioTrack` for iOS (unlike `RTCVideoTrack.addRenderer(_:)`, which very
much exists and is what the video tiles use) — only a raw `volume` knob on
`RTCAudioSource`. The one real path is a custom `RTCAudioDeviceModule`
(`sdk/objc/components/audio/RTCAudioDevice.h`): implementing the
`RTCAudioDeviceDelegate` block-pull protocol to intercept the factory's
ALREADY-MIXED playout PCM (every guest's audio pre-mixed together by
libwebrtc, which is actually exactly the shape needed for
`MediaMixer.append(_:AVAudioBuffer, when:track:)`) and feed it into
HaishinKit's mix as an extra audio track. That's a full custom AudioUnit-
level replacement of WebRTC's audio I/O for the whole factory — real scope
(thread-safety, interruption handling, sample-rate negotiation), and with no
live device + real second guest to verify against in this pass, shipping it
unverified risked silently breaking a real broadcast's audio for a feature
that might not even engage right. Implemented the honest fallback instead:
**guests are audible to the HOST only** (over the coexistence fix in §8),
clearly labeled here as L6c work rather than silently declared done.

**Files:** `NuruMember.xcodeproj/project.pbxproj` (WebRTC SPM package),
`Config/NuruMember-Info.plist` + the two `INFOPLIST_KEY_NSMicrophone
UsageDescription` build settings (copy now mentions guests, not just
broadcasters), `Models/LiveInteractions.swift`, `Networking/
MemberAPI+LiveInteractions.swift`, `Features/Live/WebRTCSupport.swift`
(new), `Features/Live/WhipPublisher.swift` (new), `Features/Live/
WhepSubscriber.swift` (new), `Features/Live/GuestStageOverlay.swift` (new),
`Features/Live/GuestTileRail.swift` (new), `Features/Live/
BroadcastController.swift`, `Features/Live/GoLiveBroadcastView.swift`,
`Features/Live/LiveViewerPlayerView.swift`, `Features/Live/
LiveHandsGuestsSheet.swift`.

**Verified:** `xcodebuild -scheme NuruMember -configuration Debug
-destination "id=8265F608-4A98-4E95-9074-7C54BEC4684A" -derivedDataPath
build/dd build` → BUILD SUCCEEDED (SPM resolve included, M150 binary
resolved clean); `... test` → 21/21 green (the existing baseline — no new
unit tests this pass: the entire surface added is live WebRTC/network
negotiation against a real MediaMTX server, which `xcodebuild test` has no
way to exercise without a live signaling peer and camera/mic hardware,
matching the existing precedent set by `BroadcastController.
handleBackgrounded`'s own caveat). Not pushed / no PR opened (per task
instruction — isolated worktree, commit only).

**Android parity pending** — not started this pass; `nuru-android` still
shows whatever L6a scaffolding text it has for an accepted guest.

## 2026-07-31 — Nuru Live taste pass: draggable/collapsible chat, banner auto-collapse, TikTok-style chrome polish, Audience picker, Live hub redesign (branch feat/live-taste, this repo only)
Owner spec: "I like what we have — add good taste, subtle changes that make
this beautiful" (TikTok Live Studio as a reference point, kept in Nuru's own
gold/navy/paper palette, not TikTok's). Built on top of build 93 (Broadcast
Studio). Worked in an isolated worktree (`.worktrees/live-taste`, branch
`feat/live-taste` off `origin/main`); commits are local, not pushed.

**1. Guest banner too big/persistent — fixed.** `LiveViewerPlayerView`'s gold
"invited on stage" / "on stage soon" card now auto-collapses ~3s after
appearing into a small tappable corner pill (`collapsedGuestPill`), reusing
the SAME mechanism whether the status is freshly `invited` or just flipped to
`accepted` after a response (`scheduleGuestBannerAutoCollapse`, keyed off
`pulse.guests` changing) — the banner shows big once per fresh status, then
tucks away; tapping the pill re-expands it. `.animation(reduceMotion ? nil :
.spring(...), value: guestBannerCollapsed)` respects Reduce Motion.

**2/3. Floating chat — draggable, collapsible, shared with the broadcaster.**
`LiveFloatingChatOverlay.swift` rewritten: default size dropped to ~55%
width × ~26% height (was 66%/32%); a new header (drag handle + collapse
chevron) is the ONLY draggable region on the expanded card, so the message
list/composer never fight the pan gesture; `DragGesture(minimumDistance: 8)`
+ `@GestureState` accumulate into a `settledOffset` that survives the 💬
visibility toggle and the collapse/expand round-trip for as long as the
player screen stays mounted ("remembered for the session"); collapsing
shrinks the card to a single round chat-bubble button (also draggable via
`.simultaneousGesture`, so its own tap still resolves). Position is clamped
to on-screen bounds, clear of the top HUD and bottom rail/controls. The call
site changed from an anchored `.overlay(alignment: .bottomLeading) {
.frame(...) }` to a full-bleed `.overlay { }` so `.position(...)` can place
the card/bubble anywhere. `GoLiveBroadcastView` now presents this SAME
component (`chatOverlayVisible`, toggled by the existing 💬 control) instead
of the modal `LiveChatSheet` — `LiveChatSheet.swift` is left in place,
unreferenced, per the owner's "keep the sheet code but stop presenting it."

**4. TikTok-inspired chrome polish.** Host chip: "Host" plain text replaced
with a small gold "HOST" pill next to the name (avatar stays the initials
`Avatar(url: nil, ...)` idiom — confirmed `LiveStreamSummary`/
`LivePlayableItem` carry no `avatarUrl`, only `startedByName`, so there is no
real image to show yet; documented inline). The eye-glyph "N watching" pill
beside LIVE, and the soft translucent circular rail/HUD buttons, were already
in place from build 92/93 and are unchanged. Added a gentle fade + 10pt
slide-down entrance for the whole chrome layer and the interaction rail
(`chromeSettled`, `withAnimation(.spring(...))`), skipped entirely under
Reduce Motion.

**5. Go Live audience picker.** `GoLiveSetupSheet`'s "WHERE" section became
"AUDIENCE": "Everyone — all connected members" vs "A cell / class". The cell
option now lists the broadcaster's OWN cells — reusing the EXISTING
`MemberAPI.disciples()` roster fetch (`GET /disciples`) rather than minting a
new endpoint, per the ask. This is also a genuine correctness fix, not just
UI: the server's actual scope=cell authorization (`service.ts createStream`)
is Admin/SuperAdmin OR the cell in the caller's `leader_assignments` — NOT
`profile.cell_group_id` (personal membership), which is what
`LiveBroadcastEligibility.cellEligible` used as a proxy everywhere else. The
roster is scoped by that same `leader_assignments` set, so every distinct
cell it surfaces is guaranteed to authorize. Falls back to the old
single-"My cell" proxy when the roster call is empty/403s (a non-leader
member) — unchanged behavior for everyone this is new for. Wire contract
unchanged (`scope: church|cell`, `cell_id`).

**6. Banner-on-broadcaster screenshot bug — root cause found and fixed at
the source, not patched at the symptom.** `LiveChatSheet`/guest banner code
never runs on `GoLiveBroadcastView` — grepped for every call site and
confirmed the guest-invite chrome lives ONLY in `LiveViewerPlayerView`. The
real bug: `LiveDiscoveryCenter.ingest(_:)` folded `/live/now` rows into
`streams` with NO filter for "and don't tell me about MY OWN live stream" —
the wire has no such distinction (`startedByName` only, no `startedBy`
user id in `LiveNowRow`/`LiveStreamSummary`). A broadcaster who minimized
their own broadcast could tap the app-wide LIVE bar (or Home's mini-window,
or a routed `live_stream_started` push) for THEIR OWN stream and land in
`LiveViewerPlayerView` — the screenshot's guest chrome rendering over what
should have been their own broadcast surface. Fixed at the source:
`ingest(_:)` now drops `BroadcastCenter.shared.controller?.session.stream
.streamId` from `streams` before anything downstream (bar/mini-window/
notification-tap) ever sees it — a broadcaster can never be offered their
own stream to "watch" from any of the three discovery surfaces. Added a
second, cheap defense-in-depth guard directly in `guestInviteCard` (never
render when `item.id` matches the active `BroadcastCenter` session) in case
some future change reintroduces a path into the viewer for one's own stream;
documented as "should never trigger — the backend also refuses to let a
broadcaster invite themselves as a guest of their own stream."

**7. Live hub redesign (`NuruLiveTabView.swift`) — scope extension mid-task
(owner: "on Android it's bare; bring iOS's to the same elevated design").**
Replaced the plain header/card/list layout with a navy "studio card" hero
(Fraunces "Nuru Live" + caption, large gold Go Live pill with a camera glyph
and a breathing ring — `Reduce Motion` → static; swaps to a "● LIVE now —
watch" row when someone ELSE has the church stream live, since starting a
second one would just 409 anyway). Replaced the embedded read-only Replays
list with "My Broadcasts": `GET /live/recordings/mine` (new
`MemberAPI.fetchMyRecordings()` / `LiveMyRecordingRow` — server field is
`url`, not `recording_url`, since it's a distinct response shape from
`GET /live/recordings`), navy thumbnail tile + kind glyph, Fraunces title,
scope chip + date, and a `Menu` (⋮) per row: Play (existing
`LiveViewerPlayerView` via a new `LivePlayableItem.myRecording(_:)`
factory), Download/Share (`ShareLink` over the ABSOLUTE URL — resolved via
the EXISTING `MemberAPI.resolveLiveMediaURL`, which already prefixes the
API's origin exactly the way the owner's ask described, so no
environment-specific host got hardcoded), and Delete → the SAME confirmation
copy/flow as #8 below → `DELETE /live/recordings/{id}` (new
`MemberAPI.deleteLiveRecording(streamId:)`) then removes the row locally.
Tasteful empty state ("No broadcasts yet…") and an error state with retry,
matching `LiveReplaysView`'s existing idiom. `LiveReplaysView` itself and
its callers (Home, `CellInfoView`) are untouched — "My Broadcasts" is
additive, not a replacement of the read-only Replays surface everyone else
still uses.

**8. End-of-broadcast stewardship (`GoLiveBroadcastView.summaryView`).**
Added "Keep in Replays" (gold, primary — needs no API call; keeping is
simply the default, so it and dismissing any other way both just call
`BroadcastCenter.shared.clear()`) and a quiet red "Delete recording" text
button beneath it, gated behind the same confirmation dialog copy the owner
specified ("Delete '<title>'? The recording will be gone forever." / "Delete
forever" / "Cancel") → `DELETE /live/recordings/{streamId}`. Best-effort: the
recording registrar runs a background sweep (inline attempt + ~2min worker
backstop, per the live module's own OPS FOLLOW-UP note) so a recording may
not be registered yet the instant this screen appears — a delete attempt in
that window 404s server-side and is swallowed silently (nothing to steward
yet, and "keep" — doing nothing — is already correct).

**Honest limits.** No backend is reachable from this sandbox (Home's own
dashboard fails to load with "Couldn't load your dashboard" on a clean
launch) — the Live tab, Go Live flow, guest-invite banner, and My Broadcasts
list could NOT be exercised interactively against a live stream/session in
this pass. Verification is: `xcodebuild … build` → BUILD SUCCEEDED,
`xcodebuild … test` → all 21 baseline tests green, and a plain app-launch
smoke check (no crash, Home renders, session persisted from a prior run).
Every UI change was reasoned through against the existing wire contracts and
this codebase's own idioms (Nuru tokens, `Icon`/`Avatar`/`.pressable`,
`Envelope<T>`/`EmptyResponse`) rather than screenshotted end-to-end. The
`live:go` permission wasn't present on the signed-in profile in this
session, so the Live tab itself didn't even render in the smoke check
(matches existing, unchanged gating in `RootView.visibleTabs`).

## 2026-07-31 — Nuru Live "Broadcast Studio": persistence, honest backgrounding, Document/Screen sources (branch feat/broadcast-studio, this repo only)
Owner spec: richer broadcast stage, screen/document sharing, and the stream
must not die when leaving the broadcast screen. Built on top of build 92
(L5 broadcaster HUD + viewer redesign + orientation fix). Files: new
`BroadcastCenter.swift`, `BroadcastMiniPlayer.swift`, `AppScreenCapture.swift`,
`DocumentPagerView.swift`, `BroadcastSourceSheet.swift`; rewritten
`GoLiveBroadcastView.swift`; extended `BroadcastController.swift`; RootView +
the three "Go Live" entry points (`NuruLiveTabView`, `HomeView`,
`CellInfoView`) repointed at the new app-wide holder.

**1. Stage polish — audited, not changed.** Re-checked the preview/chrome
against the spec (full-bleed, chrome floating, safe-area-respected): the
camera surface already used `MTHKViewRepresentable(...).ignoresSafeArea()`,
`topBadges` already sat inside the system safe-area inset by default (no
letterboxing under the notch/Dynamic Island), and `controlsRow`'s
`.padding(.bottom, 28)` already cleared the home indicator. Nothing to fix;
documented rather than churned.

**2. Leave-the-page persistence — the headline fix.** The bug: `GoLiveBroadcastView`
owned its `BroadcastController` as a `@StateObject` and tore it down (`.onDisappear
{ end() }`) the instant the view left the hierarchy — any navigation away
killed the stream. Fixed by hoisting the controller's lifetime into a new
app-wide singleton, `BroadcastCenter` (mirrors `RadioCenter` exactly):
`BroadcastCenter.shared.start(session:)` mints the controller once (called
from the three Go Live entry points instead of each owning a local
`@State goLiveSession` + its own `.fullScreenCover(item:)`); RootView owns
the ONE `fullScreenCover(isPresented:)` bound to
`broadcast.controller != nil && broadcast.presented`, plus a floating
"● LIVE mm:ss — tap to return" island (`BroadcastMiniPlayer`, docked below
the radio pill's row) shown whenever a broadcast is active and minimized. A
new chevron-down control in the broadcast HUD calls `BroadcastCenter.minimize()`
— sets `presented = false`, dismissing the cover, WITHOUT touching the
controller; the mixer/RTMP keep running untouched. `GoLiveBroadcastView.
onDisappear` is gone entirely — every path that actually ends a broadcast
(the End confirmation, the island's own ✕, `failedView`'s End, a
pre-live abort) calls `controller.end()` or `BroadcastCenter.clear()`
explicitly. Re-tapping "Go live" while already broadcasting restores the
existing session (`broadcast.restore()`) instead of minting a second stream.
`BroadcastCenter` auto-`clear()`s once `phase == .ended` ONLY while
minimized — while the full-screen surface is up, the summary/
permission-denied view still needs to render before anything is cleared.

**3. Backgrounding honesty.** Read `MediaMixer.swift` + `VideoCaptureUnit.swift`
in the resolved HaishinKit 2.2.5 checkout: `mixer.startRunning()` already
registers its OWN `UIApplication.didEnterBackgroundNotification` /
`willEnterForegroundNotification` observers and calls
`VideoCaptureUnit.suspend()`/`.resume()` — `suspend()` detaches ONLY the
camera's `AVCaptureSession` connection (`session.detachCapture(capture)`),
leaving the mic's connection attached and the session running, then
`resume()` re-attaches the camera on foreground. So HaishinKit was already
doing exactly what the spec asked for (pause video, keep audio, auto-resume)
— the only reason a broadcast used to die on backgrounding was
`BroadcastController.handleBackgrounded()` itself calling `end()`
unconditionally. That call is gone; `handleBackgrounded()` now just flags a
`videoPausedInBackground` published bool (drives a small "Audio live —
camera paused" HUD pill), relying on the app's existing `UIBackgroundModes:
audio` entitlement (already shipped for Nuru Radio) plus the
`AVCaptureSession`-managed `AVAudioSession` recording session that attaching
a mic device configures automatically. Audio-only broadcasts were never
touched by this bug in the first place (no camera to lose) but WERE
unconditionally ended by the old code too — also fixed. **Honest limitation:**
there is no way to exercise "does the RTMP socket really survive an hour
backgrounded" from `xcodebuild test`, and this sandbox has no physical
device to background mid-broadcast against a real MediaMTX — this rests on
reading HaishinKit's actual source (cited above) plus the same
well-established AVFoundation pattern Radio already proves works for audio
in this exact app, not an end-to-end device trace.

**4. Source switcher — Camera / Document / Screen.** New `sourceButton` in
the HUD opens `BroadcastSourceSheet`. **Document** (priority item, fully
built): `.fileImporter` PDF pick → `DocumentSource` rasterizes every page to
a `UIImage` via PDFKit (`PDFPage.draw(with:to:)`, off the main thread) →
`DocumentPagerView` (SwiftUI `TabView` + `.page` style) becomes the ENTIRE
on-screen surface. **Screen** ("Share my screen (this app)", also built):
same underlying mechanism. Both route through `AppScreenCapture`, a thin
wrapper over `RPScreenRecorder.startCapture(handler:)` — ReplayKit's
IN-APP capture API (no Broadcast Upload Extension, no system picker,
confirmed this needs neither by reading Apple's ReplayKit docs) — which
hands back live `CMSampleBuffer`s that get fed straight into
`MediaMixer.append(_ sampleBuffer:track:)`, a PUBLIC manual-append entry
point confirmed by reading `MediaMixer.swift` in the resolved checkout
("Appends a CMSampleBuffer" — routes into the SAME `VideoMixer` pipeline a
physical `AVCaptureDevice` feeds). Before appending, the camera is detached
from track 0 (`mixer.attachVideo(nil, track: 0)`) so there's exactly one
producer at a time; a `sourceGeneration` counter guards against a stale
buffer from a just-stopped capture landing on the wrong track during the
async switch. `RPScreenRecorder.isMicrophoneEnabled = false` keeps
HaishinKit's own mic tap the ONE audio pipeline throughout every source
switch. Screen mode deliberately does NOT auto-minimize (kept the scope to
the append pipeline + picker UI, not new island-interaction states); its own
screen explains "minimize (⌄) and browse Nuru" — because `AppScreenCapture`
lives on `BroadcastController`, independent of which view is on screen,
capture genuinely keeps running (and keeps feeding the mixer) across a
minimize/restore round-trip, so free navigation while screen-sharing DOES
work as built, just isn't the state the sheet auto-drives you into.
**Honest limitation:** ReplayKit capture, PDF rendering, and the append path
were verified by reading HaishinKit/ReplayKit's actual APIs and by a clean
`xcodebuild build`/`test` pass — NOT by an on-device screen-record + RTMP
round-trip (no eligible `live:go` test account + no reachable backend in
this sandbox to drive the full flow end-to-end). The first real
`RPScreenRecorder` permission prompt and its interaction with an
already-running `AVCaptureSession` (camera) is the highest-risk untested
edge — worth a manual device pass before this ships to real broadcasters.

**5. L5 HUD across navigation.** ✋/💬 sheets, the reaction overlay, and the
3s pulse poll all live on `BroadcastController` untouched — since the
controller itself never tears down on minimize/restore, all of it keeps
working exactly as build 92 shipped it, verified by inspection (no changes
needed to `LiveHandsGuestsSheet.swift` / `LiveChatSheet.swift` / the pulse
poll in `BroadcastController`).

**Verify:** `xcodebuild build` → BUILD SUCCEEDED (1 pre-existing, unrelated
warning from `appintentsmetadataprocessor`, no compiler warnings in any new
or touched file). `xcodebuild test` → 21/21 green (unchanged baseline —
this arc added no new unit-testable surface; `BroadcastController` needs a
camera/mic/RTMP server to exercise meaningfully). Ran the built app in the
iPhone 17 Pro Max simulator: launches clean, navigates Home/You without
crashing; could NOT reach the Live tab itself (signed-in test profile isn't
`live:go`-eligible and no backend was running against `localhost:8080` in
this sandbox), so the actual broadcast/capture path is unverified beyond
compile + source-reading — flagged above, not hidden.

## 2026-07-31 — Nuru Live viewer redesign: best-in-class chrome + 🔥 reaction (branch feat/live-viewer-polish, this repo only)
Redesigns the VIEWER side of the L5 interactive stage (previous entry below)
into TikTok/IG/YouTube-Live-grade chrome, on top of build 91's shipped API
layer — `LiveViewerPlayerController`, `LivePulseController`, `MemberAPI
+LiveInteractions.swift` are untouched; this pass is UI + one small model
addition. The BROADCASTER side (`GoLiveBroadcastView.swift`,
`LiveChatSheet.swift`, `LiveHandsGuestsSheet.swift`) is untouched too.

**1. 🔥 fire reaction (3rd kind, owner ask).** `LiveReactionCounts` gains a
`fire` field (tolerant default 0 — a pulse response from before the backend
added it still decodes). `LiveReactionKind` (`LiveReactionEffects.swift`)
gains `.fire` (`flame.fill`, orange `0xF97316`) alongside `.love`/`.like`,
plus an `emoji` accessor so the rail can post the right string back to `POST
.../reactions`. Since `ReactionBurstQueue`/`FloatingReactionsOverlay` were
already generic over `LiveReactionKind(emoji:)`, the broadcaster's own
ambient-particle HUD picks up 🔥 automatically with no broadcaster-file
changes.

**2. Full-bleed chrome** (`LiveViewerPlayerView.swift`). Top scrim unchanged;
added a matching bottom scrim (`.ignoresSafeArea` now covers `.top` AND
`.bottom` for the video kind, was top-only) so the new rail/chat never fight
a bright frame. LIVE pill unchanged; the viewer-count chip switched from a
`users` glyph to `eye` (owner spec) and now prefers the live 5s pulse's own
`viewer_count` over the static snapshot `item.viewerCount` was built from,
both abbreviated through a new `LiveCountFormat.abbreviated` (999 / 1.2K /
10K / 3.4M — TikTok-style, tested). New IG-style broadcaster identity chip
(avatar-initials + name + "Host") renders under the top row whenever
`LivePlayableItem.broadcasterName` is set — a new field piped straight from
`LiveStreamSummary.startedByName` in the `.live()` factory (no wire change,
just carrying an already-fetched field through; `.recording()` leaves it
nil, and the chip only ever shows for `item.isLive` anyway).

**3. Right-side vertical action rail** (TikTok idiom, replaces the old
bottom-trailing-ish stack). ❤️ 🔥 👍 each with a TikTok-abbreviated count
underneath sourced from `pulse.reactions`, then ✋ (gold-filled while raised,
unchanged logic) then 💬 (now a VISIBILITY TOGGLE for the floating chat
overlay below, not a sheet presenter). Reaction taps route through one new
shared `fireReaction(emoji:)` — same optimistic particle spawn + haptic +
~900ms cooldown as before, just de-duplicated across three buttons instead of
copy-pasted for two.

**4. Double-tap-the-video = ❤️** — a transparent `SpatialTapGesture(count:
2)` layer, scoped to `item.isLive` (so a replay's native
`AVPlayerViewController` scrub/tap-to-toggle-controls behavior is never
touched), sitting UNDER the chrome/rail/chat overlays so their own buttons
still win the hit-test at their own bounds. Pops a big heart
(`BigHeartBurstView`, spring scale + fade, ~0.9s) at the exact tap point and
calls the same `fireReaction("love")` the rail uses. Reduce Motion: no flying
heart, reaction still fires (matches the rest of L5's Reduce Motion
contract).

**5. Floating chat overlay** (new `LiveFloatingChatOverlay.swift`) —
REPLACES the modal `LiveChatSheet` on the viewer side per the owner's exact
brief: anchored bottom-leading, ~66% width × ~32% height, `.ultraThinMaterial`
forced to its dark variant (`.environment(\.colorScheme, .dark)` — this is
video-overlay chrome, not a themed app surface), last 6 messages (gold name +
white body inline, decorative top fade, auto-scroll on new arrivals), its own
translucent composer pill, and a small gold "✋ N raised" chip when
`pulse.hands` is non-empty (a viewer has no hands-sheet of their own — this
is the only visibility they get into that state). Owns its own 3s
since-cursor poll (`LiveFloatingChatController`, functionally identical to
`LiveChatSheet`'s) and stays MOUNTED for the whole `isLive && .playing`
window regardless of the 💬 toggle — toggling only flips opacity/hit-testing,
so hiding and re-showing chat never drops messages or restarts the poll.

**6. Home header LIVE entry** (`HomeView.swift`) — a 40pt chip in the same
slot family as the radio icon (pulsing red ring `HomeLiveHeaderRing` +
waveform glyph), shown only while `churchLiveStream` (the existing /live/now
state from build 88, already driving the feed's top banner) is non-nil; tap
opens the same full player the banner's "Watch live" does. No new polling —
rides the state Home already has.

**7. FLICKER GUARD — found and fixed a real reuse bug.** Traced how
`LiveViewerPlayerView` is presented at all four call sites
(`HomeView`/`CellInfoView`/`LiveReplaysView`/`RootView`, all
`.fullScreenCover(item:)`) against `LivePlayableItem: Identifiable`.
`fullScreenCover(item:)` does NOT dismiss/re-present when its bound item goes
from one non-nil value straight to a DIFFERENT non-nil value — only a
transition through `nil` does. **RootView's own handler already does exactly
that**: a `live_stream_started` notification tap (and the app-wide
`AppLiveBar` tap) sets `liveDiscovery.requestedItem = .live(stream)`
unconditionally, with no nil-check first. Without an identity break, SwiftUI
would keep the SAME `LiveViewerPlayerView` instance across that call — its
`@StateObject` player/pulse controller would NOT reinitialize, and `.task {
controller.start(...) }` would NOT rerun (plain `.task` only fires on an
identity change) — so a viewer who already had the player open on stream A,
then tapped a push for newly-started stream B, would go on watching STREAM
A's frames under stream B's chrome/title/pulse, until they closed and
reopened the player by hand. Fixed by appending `.id(item.id)` to the
returned view at all four call sites, forcing a fresh view (and fresh
player/pulse controller, freshly fetched against the NEW stream_id) whenever
the stream_id actually changes. The other three call sites only ever go
`nil → item` today so weren't actively hit, but carry the same guard since
nothing stops a future caller from doing what RootView already does.
Separately audited `LiveMiniPopup`'s `MutedPreviewController` (Home's muted
preview) — safe: `LiveDiscoveryCenter.ingest()` only ever sets a NEW
`popupStreamId` while the current one is `nil` (`guard popupStreamId == nil
else { return }`), so that surface always tears down through nil first and
never hits the same reuse class.

**Honest limits:** no live backend/broadcast was available to drive the
built-and-verified UI end-to-end on device this pass (build succeeds, unit
tests cover the new model/format logic, and the app launches clean with the
header change visible in a screenshot) — the interactive chrome itself
(rail, floating chat, double-tap heart, identity chip) is unverified by eye
against a REAL live stream. The broadcaster identity chip shows a generic
"Host" caption rather than a real title/role, since no such field exists on
the pinned wire contract (`LiveStreamSummary` only carries `startedByName`)
and none was invented for it.

Files: `Features/Live/LiveViewerPlayerView.swift`, new `Features/Live/
LiveFloatingChatOverlay.swift`, `Features/Live/LiveReactionEffects.swift`,
`Features/Home/HomeView.swift`, `Features/Home/CellInfoView.swift`,
`Features/Live/LiveReplaysView.swift`, `Features/Shell/RootView.swift`,
`Models/Live.swift`, `Models/LiveInteractions.swift`,
`NuruMemberTests/LiveInteractionsDecodingTests.swift` (+3: fire-count
tolerance, fire emoji mapping, `LiveCountFormat` abbreviation).

**Verified:** `xcodebuild … build` → BUILD SUCCEEDED; `xcodebuild … test` →
21/21 green (18 pre-existing + 3 new). Not pushed / no PR opened (per task
instruction) — built in an isolated worktree (`.worktrees/live-viewer`,
branch `feat/live-viewer-polish`) off `origin/main` at build 91.

**Android parity pending** — not started this pass.

## 2026-07-31 — Nuru Live L5 interactive stage (branch feat/live-interactions, this repo only)
iOS member app builds the interactive layer on top of the shipped L0-L4 live
pipeline, coded exactly to the PINNED wire contract in
`docs/LIVE_INTERACTIVE.md` (backend built to the same doc in parallel — every
DTO decodes tolerantly, optionals + defaults, same discipline as
`Models/Live.swift`).

**1. Wire layer.** `Models/LiveInteractions.swift`: `LiveChatMessage`,
`LiveMessagesEnvelope`, `LivePulse` (+ `LiveReactionCounts`,
`LiveRecentReaction`, `LiveHandRow`, `LiveGuestRow`) — the one poll shape
driving the whole overlay. `Networking/MemberAPI+LiveInteractions.swift`:
`reactToLiveStream`, `setLiveHandRaised`, `fetchLiveMessages`/`sendLiveMessage`,
`fetchLivePulse`, and the L6 guest scaffolding (`inviteLiveGuest`,
`respondToLiveGuestInvite`, `removeLiveGuest`). New Lucide icon case
`thumbsUp` (`\u{E18A}`, confirmed present in the bundled 1784-glyph font).
Covered by `NuruMemberTests/LiveInteractionsDecodingTests.swift` (8 cases:
full-payload + empty-object tolerance for chat messages, the messages
envelope, and the pulse; guest `isActive`; hand-row name default).

**2. Broadcaster** (`Features/Live/GoLiveBroadcastView.swift` +
`BroadcastController.swift`). Controls row grows to
`[mic, End, flip, ✋, 💬]`. The pulse poll (GET `/live/streams/{id}/pulse`,
3s) is folded directly into `BroadcastController` alongside its existing
`startViewerPolling()` — same start/stop call sites (`connectAndPublish`,
`reattemptPublish`, `handleDropped`, `teardown`) rather than a second poller,
since that controller already owns the RTMP lifecycle the poll must track.
✋ carries a gold badge (raised-hand count) → `LiveHandsGuestsSheet.swift`
(medium/large detent): hand rows with "Invite to join" (disabled + "6 guests
max" at the cap) and a "Lower" affordance that is LOCAL-ONLY — the pinned
`POST /hand {raised}` always targets the calling user, so there is no
broadcaster-authority parameter to force someone else's hand down; "Lower"
just clears that row from the sheet's own view for the rest of the stream.
Guests section lists invited/accepted with Remove; accepted rows read
"Joining soon — video in the next update" (L6 video is the next phase — this
never claims more than the plumbing that exists today). 💬 opens
`LiveChatSheet.swift` (shared with the viewer). Floating reactions
(`Features/Live/LiveReactionEffects.swift`, `FloatingReactionsOverlay` +
`ReactionBurstQueue`) rise bottom-right from `pulse.recent_reactions`, capped
at 10 concurrent, Reduce-Motion swaps to a static counter chip; the first
poll after going live seeds the seen-set without spawning anything, so
opening the screen never floods it with a stream's whole reaction history at
once.

**3. Viewer** (`Features/Live/LiveViewerPlayerView.swift` +
new `LivePulseController.swift`, 5s poll, independent instance since the
player's lifecycle is just "on screen" rather than tied to RTMP). ❤️/👍 rail
buttons fire `reactToLiveStream` with instant local optimistic particles
(same `ReactionBurstQueue`) plus ambient particles from others via the pulse,
haptic on tap, ~900ms client-side cooldown mirroring the server's ≥1s/user
rate limit. ✋ toggle: optimistic local flip, reconciled from
`pulse.hands` on the next poll (skipped while a toggle is in flight so it
never fights the user's own tap). 💬 opens the shared `LiveChatSheet`. Guest
invite: if `pulse.guests` contains ME as `invited`, a gold "You're invited on
stage" card offers Accept/Decline (`respondToLiveGuestInvite`); once
`accepted`, it becomes the same honest "joining soon" banner as the
broadcaster's sheet. The whole interactive overlay is gated to a GENUINE
live stream (`item.isLive`) — never shown over a finished replay, since the
pinned contract's endpoints require a live stream anyway and pretending a
recording has a live audience would be dishonest chrome.

**4. Shared.** `LiveChatSheet.swift` — one component, both call sites
(`.presentationDetents([.medium])`): 3s-polled since-cursor message list +
composer, light Aurora-style bubbles (`Nuru.myBubble` for mine, white +
sender name for others), 500-char cap, no read receipts/offline
queue/edit/delete — deliberately lighter than the full 1:1 chat thread.

**Naming note:** `ReactionBurstQueue`'s particle type is
`LiveReactionParticle` (not `ReactionParticle`) — `RadioPlayerView.swift`
already owns that name for its own reaction-bar effect; kept distinct to
avoid a module-wide redeclaration collision.

**Verified:** `xcodebuild … build` → BUILD SUCCEEDED; `xcodebuild … test` →
18/18 green (10 pre-existing + 8 new).

**Android parity pending** — not started this pass; L5 interactions
(raise-hand/reactions/chat) and the L6 guest-invite scaffolding still need a
Kotlin/Compose pass in `nuru-android` against the same pinned contract.

## 2026-07-20 — Reading typography/spacing global pass (branch feat/reading-typography-global, this repo only)
A coordinated 4-part pass making text size AND line spacing genuinely global
(same idiom, same reach) and giving scripture ONE quote-card look everywhere
it appears, plus closing the Selah spacing round-trip the backend just shipped.

**1. Global line-spacing preference (mirrors Text size exactly).**
`Theme/NuruTheme.swift`: added `Nuru.lineSpacingKey = "nuru.lineSpacing"` +
`static var lineSpacing: CGFloat` (UserDefaults-backed, clamped 0.85–1.35 —
same idiom as `Nuru.textScale`), plus the hook SwiftUI actually needs:
`NuruReadingSpacing: ViewModifier` and `View.nuruLineSpacing(_ base: CGFloat =
4)` / `.nuruReading(_:)`, both resolving to `.lineSpacing(base *
Nuru.lineSpacing)`. `Features/Profile/SettingsView.swift`: a new "Line
spacing" segmented control beside Text size — Compact/Default/Relaxed →
0.85/1.0/1.35, `@AppStorage(Nuru.lineSpacingKey)`, each chip's own two
hairlines spaced by the chip's own multiplier so the leading difference is
visible in the picker itself, not just in body text.

**2. Reading surfaces routed through `.nuruLineSpacing(_:)`.** Swapped
`.lineSpacing(n)` → `.nuruLineSpacing(n)` (same base value, now scaled by the
preference) on: `HomeCards.swift` (HomePersonalWord, HomeEncouragementCard),
`VerseTableau.swift` (VerseTableauHeader, VerseShareCard), `EchoCard.swift`
(body + quote), `LetterView.swift` (letter body), `DevotionalView.swift`
(verse card, body paragraphs, reflection prompt), `MemoryVerseView.swift`
(current-verse hero, library row), `LessonMarkdown.swift` (paragraph, bullet,
numbered, quote card), `PlanSegmentView.swift` (Talk it Over prompt),
`ReadingPlansView.swift` (DayPassage, DayTalk, DayPrayer; DayPullQuote now
goes through VerseQuoteCard below). Left tight UI chrome alone (list-preview
snippets with `lineLimit`, banners, buttons, table grids) — text size already
reached all these same surfaces via the font helpers, so the two preferences
now cover identical ground.

**3. Shared `VerseQuoteCard`.** New in `Features/Home/HomeCards.swift`: cream
parchment card (`Nuru.surface`), left gold accent bar, hanging gold ‟ glyph,
Fraunces verse in navy, uppercase letter-spaced gray reference — built by
combining HomeEncouragementCard/HomePersonalWord's card+glyph styling with
EchoCard's accent bar (no new parchment color or quote glyph invented). Takes
optional color overrides + a `cardStyle` flag (full standalone card vs. bar+
text only, for embedding inside a container that already has its own card
chrome) so ONE component serves every context:
- **Home** — `HomeView.swift`'s "classic cream" verse-for-today fallback now
  renders `VerseQuoteCard(cardStyle: false)` inside the existing outer card.
- **Pathway lessons** — `LessonMarkdown.swift`: a blockquote whose attribution
  matches `MLMarkdown.isScriptureReference(_:)` (a conservative "Book
  chapter:verse" regex, ≤40 chars) renders as `VerseQuoteCard`; an ordinary
  blockquote (no attribution, or one that isn't a reference) keeps the plain
  `MLQuoteCard` styling — no hijacking of non-scripture quotes.
- **Plans** — `ReadingPlansView.swift`'s `DayPullQuote` (the day's
  scripture segment in `PlanSegmentView.swift`) now IS a `VerseQuoteCard`,
  tinted via the existing `readerPalette` (day/night reading mode) instead of
  fixed colors — the night-mode reading experience is preserved.

**4. Selah per-span spacing (closes the backend round-trip).**
`Models/Thought.swift`: `ThoughtSpan.spacing: Double?` (0.8–2.5 multiplier,
matches `packages/backend/src/modules/thoughts/service.ts` exactly).
`Features/Community/SelahRichEditor.swift`: `SelahSpacing` now exposes a
`multiplier` (0.85/1.0/1.35 — same 3-tier scale as the new global Settings
control) instead of raw points; `SelahRichText.paragraphStyle(forMultiplier:)`
is the one place points get computed (`anchorPoints(6) * multiplier *
Nuru.lineSpacing` — the global reading preference layers on top of the note's
own choice, exactly as the backend comment on `ThoughtSpan.spacing`
describes). `build()` applies per-span overrides via this helper; `extract()`
reads each run's `NSParagraphStyle.lineSpacing` back, and — mirroring how
bold/italic/color/font already differ-from-baseline and merge adjacent runs —
records `ThoughtSpan.spacing` only when a run's spacing differs from the
note's current document default. `RichEditorController.applySpacing` now
applies to the current **selection** (a true per-span override, like the
other toolbar traits) when there is one, and falls back to the whole note
(preserving the pre-existing "space this whole thought out" gesture) when
there isn't. `SelahEditorView.swift` passes `documentSpacing:` into
`extract()`; `SelahView.swift`'s `spanDict` now serializes `spacing` into the
sync payload the mutation queue sends to the backend — without this the
round-trip was extract-only and never actually reached the server.

**Honest limits:** (a) the Selah toolbar's "document default" spacing is
still a single device-wide `@AppStorage` (pre-existing design, not introduced
here) rather than per-thought — reopening a different note can show a
different doc-default baseline than it was written with, though any EXPLICIT
per-span override always round-trips correctly regardless. (b) `VerseTableauHeader`'s photo-tableau verse (the art-backed "beheld" rendering,
distinct from the "classic cream" fallback) keeps its own bespoke overlay
styling rather than becoming a `VerseQuoteCard`, since it renders over a
photograph with a navy scrim, not a parchment card — it does route through
`.nuruLineSpacing` per item 2 above, but is not visually identical to the
quote card. (c) `MLMarkdown.isScriptureReference` is a regex heuristic — an
attribution shaped exactly like "Book chapter:verse" but that ISN'T actually
scripture (unlikely in lesson content) would render as a verse card; this
trade-off was chosen over a more invasive "explicit scripture field" schema
change, which the lesson content model doesn't currently carry.

**Verify:** `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" build` → BUILD SUCCEEDED; `test` →
10/10 (`ModelDecodingTests`, pre-existing suite, untouched — no new unit tests
added this session for the UI/typography changes, which have no independent
model layer to unit-test beyond what ModelDecodingTests already covers for
`Thought`/`ThoughtSpan`'s tolerant decode).

## 2026-07-20 — Read with a Friend R3 client (branch feat/read-with-friend-ui, this repo only)
Reading & Social R1 backend (pathway#392, `/v1/reading/*` — shared plan
groups, invites, public `/join/{token}` OG page) now has iOS client UI. Read
`pathway/docs/READING_SOCIAL_REDESIGN.md` §3/§6 + `docs/READING_SOCIAL_PLAN.md`
and the backend module (`packages/backend/src/modules/reading-social/{groups,
invites,tokens,publicPage,index}.ts`, read-only) for the exact wire shapes;
built in a dedicated worktree (`.worktrees/rwf`) per the two-agent isolation
instruction — never pushed, commit is local only.

**New:** `Models/ReadingSocial.swift` (tolerant DTOs — `ReadingGroupRow`,
`ReadingGroupMember`, `ReadingInviteRow`, `ReadingInvitePreview`,
`ReadingInviteAcceptResult`); `Networking/MemberAPI+ReadingSocial.swift` (the
11 new calls: create-or-get group, list/get/archive/leave, create/list/revoke
invite, invite preview/accept/decline); `Features/Grow/ReadWithFriendView.swift`
— the hub (`ReadWithFriendHubView`, my active shared groups with per-friend
"Doris · Day 3 of 7" rows), group detail (`ReadingGroupDetailView` — roster +
progress bars, invite-a-friend via a new `FriendPickerSheet` that reuses
`MemberAPI.listConnections()`, share-link, leave/archive, pending-invites
list with revoke, refetches on every appear), and the invite-preview/accept/
decline screen (`ReadingInvitePreviewView`) pushed from a deep link or a
notification tap.

**Wired:** the Plans tab's "Read with a friend" card (`ReadingPlansView.swift`
`invitationCard`) now pushes the hub instead of a static text-only `ShareLink`.
`PlanDetailView`'s "Invite" button (`ctaBar`) now creates-or-gets a real group
for that plan, mints an open invite, and hands the public
`https://pathway.nuruplace.org/join/{token}` link + a rich message ("Join me
reading "<title>" on Nuru Pathway — a N-day plan. <url>") to the system share
sheet (`presentSystemShareSheet`, the same `UIActivityViewController` pattern
`ProfileView`'s certificate share uses) — WhatsApp/social/copy/QR all read the
one URL.

**Incoming:** `nuru://join/{token}` extends the EXISTING custom-scheme
handler in `RootView.onOpenURL` (previously host-only routing for widgets) —
`host == "join"` extracts the token and calls the new
`TabRouter.openReadingInvite(token)`, which lands on Plans → the hub → the
invite-preview screen (accept joins + enrolls + connects; decline is
targeted-invite-only, matching the backend's 403 on open links). A
`plan_group_invite_received` notification tap does the SAME thing — extended
`NotifPayload`/`LocalNotifier` to carry `invite_token`/`group_id` through
`userInfo`; other `plan_group_*` templates (accepted/joined/day-completed,
no redeemable token) land on the hub instead.

**Deep-link limit (honest, not silently deferred):** only the `nuru://`
custom scheme is wired, per `docs/READING_SOCIAL_PLAN.md` §5 tier 2/3 — no
`https://pathway.nuruplace.org/join/{token}` Universal Link. That needs an
`apple-app-site-association` hosted at the domain root (backend/infra work,
out of this client-only session) PLUS an Associated Domains entitlement this
repo has never had (`docs/READING_SOCIAL_PLAN.md` §3: "no `*.entitlements`
file exists anywhere in the tree"). Until AASA ships, the public `/join/{token}`
page's own inline-script fallback (already live server-side) still opens the
app via the custom scheme when installed, or falls through to the App Store
after ~1200ms when not — the three-tier fallback the backend already built;
this client half only had to honor the scheme it defines, which it now does.

**Verify:** `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" build` → BUILD SUCCEEDED; `test` →
10/10 (`ModelDecodingTests`, pre-existing suite, untouched — no reading-social
unit tests added this session; the DTOs are exercised by the tolerant-decode
pattern used throughout, consistent with how `ChatConnections.swift` shipped).

## Session 17c — Trail nodes keep the module number (iOS 46 / Android 2.14.0)
**PRs:** ios#57 · android#22. Field feedback: the ✓ replaced the module number
after completion (and ▶ replaced it on the next module) — members lost their
place. New treatment on BOTH apps: the number NEVER leaves the 36-unit
medallion; state moved to the fill + a 15-unit corner seal (navy check-seal =
done, lock-seal = locked, navy ring = next). iOS installed on Pastor's phone;
Jackline offline (has 45, takes 46 next connect); APK 2.14.0 on Desktop.
- **Hub numbers too (ios#58 build 47 · android#24, code-only):** the 17c fix
  covered LevelDetail but the field screenshot was the HUB — journey-rail
  circles + level-preview rows still swapped numbers for icons. Corner-seal
  treatment extended there on both apps. ALSO: build 46 never actually landed
  on the phone (devicectl said "App installed" but the device stayed on 45 —
  ALWAYS verify with `devicectl device info apps` after install); 47 verified
  on-device. Android change compile-checked only, rides the next requested APK.

## 2026-07-18 — Chat consent UI: connection requests replace unsolicited DMs (branch feat/chat-consent-ui, both member apps, client-only)
Chat Redesign C3a — the backend's C1/C2 "no unsolicited DMs" model
(`docs/CHAT_REDESIGN.md` §4, `docs/CHAT_REDESIGN_PLAN.md` C1 section in the
pathway repo, read-only) now has client UI in both member apps. Contract:
`POST /chat/connections/requests` (+`/:id/accept|/decline`, `DELETE` to
cancel), `GET /chat/connections/requests?direction=incoming|outgoing`, `GET
/chat/connections`, `POST /chat/connections/:user_id/remove|/block|/unblock`,
and `POST /chat/dms` now 403s `CONSENT_REQUIRED` (details.hint = "send a
connection request first") for a brand-new thread between two ordinary
members with no accepted connection — staff and existing threads are
unaffected (grandfathered server-side, verified by reading
`chat/service.ts#createOrGetDm` and `chat/connections.ts`, both untouched).
No backend or portal changes; pathway repo intentionally left untouched
(another agent works there per instruction).

Both apps, same state machine: **not connected** → tapping a directory
person sends a request (was: opened a DM instantly). **request sent** →
shows "Request sent" with a cancel affordance. **request received** →
surfaced in a new "Connection requests" section above Direct Messages
(accept/decline). **connected** → tap opens/creates the DM exactly as
before. A stale-cache 403 `CONSENT_REQUIRED` from `createDm` auto-offers the
connection request via an alert rather than a dead-end error. Existing DM
threads keep working untouched. Empty DM-list state is now "Connect with
someone before starting a chat." The DM segment's unread-count chip now
adds pending incoming requests to the count. Per-connection controls
(Remove connection / Block / Unblock) live in the thread header's ⋮ menu for
DM threads — **no Report**: neither app has a member-facing report/
moderation affordance to reuse (flag/remove/restore are Admin-console-only
server-side), intentionally left out rather than half-built.

This repo's half: new `Models/ChatConnections.swift` (tolerant DTOs:
`ConnectionRequestRow`, `ConnectionRow`, decision/action result shapes) and
`Networking/MemberAPI+Connections.swift` (the 8 new calls). `ChatInbox
ViewModel` (`Features/Chat/ChatView.swift`) grew `connections`/
`incomingRequests`/`outgoingRequests`/`connectionState(for:)`/
`sendConnectionRequest`/`cancelConnectionRequest`/`acceptConnectionRequest`/
`declineConnectionRequest`, and `startDm` now catches `APIError.http(_,
"CONSENT_REQUIRED", _, _)` into a `consentPrompt` alert instead of failing
silently. `PersonRow` branches on the derived `ConnectionState` for its
trailing affordance (Connect / Request sent+cancel / Wants to connect /
message icon); new `IncomingRequestRow`/`OutgoingRequestRow` above the
DIRECT MESSAGES section. `ChatThreadView`'s `ThreadHeader` gains a
`connectionMenu` (SwiftUI `Menu`) replacing the previously non-functional
(empty-action) AI sparkles button for DM threads — the peer id comes from
`ChatConversation.peerUserId`, which the inbox route already returns and the
thread already carried via navigation, so no extra network round-trip was
needed here (Android's equivalent screen needed one — see its own
PARITY_AUDIT.md entry, `GET /chat/conversations/{id}` doesn't carry
`peer_user_id`).

Verified: `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" build` → BUILD SUCCEEDED, `...
test` → 10/10 green. Android side compiled + unit-tested green too (see the
nuru-android repo's own PARITY_AUDIT.md entry, same date). Not pushed / no
PR opened (per task instruction).

## 2026-07-18 — Chat four-tab restructure + My Discipler + Talk with My Pastor (branch feat/chat-four-tabs, this repo only, client-only)
Chat Redesign C3b. Member tabs go from (My Space · Chat · My Groups[· Broadcast])
to **My Space · Chat · My Discipler · Talk with My Pastor**[· Broadcast for
SuperAdmin, unchanged]. Contract — all four routes verified LIVE by reading
`packages/backend/src/modules/{chat,pastoral}/{index,service}.ts` in the
pathway repo (read-only; nothing there touched): `GET
/chat/discipler/conversation` (`{conversation_id}`, 404 `no_discipler`), `POST
/chat/pastoral` (`{conversation_id, pastor_user_id, source}`, 404
`no_pastor`), `GET /chat/pastoral/inbox` (password-step-up gated, same 403
shape as Broadcast), `POST /chat/spaces/:id/join-requests` (+ `GET`/`accept`/
`decline`, all live). No backend/portal changes.

**My Space** merges the old `.space` and `.group` segments (backend's
migration 161 already retypes `kind IN ('space','group')` → `type=SPACE`, so
this is a pure UI merge) into sub-sections "YOUR SPACES" / "CELL & GROUPS" /
"DISCOVER SPACES". Discover's Follow button now tries the immediate `POST
/chat/spaces/:id/join` first (today's behaviour, unchanged) and only falls
back to the reviewed `POST /chat/spaces/:id/join-requests` path (pending pill,
no dead-end error) on a 403/404/409/422 — **honest limit**: `joinSpace()` in
`chat/service.ts` has zero server-side gating today (no
`requires_join_approval` column anywhere in the schema — grepped, confirmed
absent), so every Follow still succeeds immediately exactly as before; the
fallback exists for when the server starts gating some spaces, not because
any space is gated today.

**My Discipler** — tab is live/has-content only when `GET
/me/discipleship.discipler` is non-null (reused, no re-derivation); tapping
opens `GET /chat/discipler/conversation` into `ChatThreadView` with a new
explicit `ChatThreadContext` (`.normal`/`.discipler`/`.pastoral`) threaded
through a new `ThreadRoute` navigation value — the "pass context down
explicitly" approach the task called for, since `GET
/chat/conversations/:id` still doesn't return `type`. Empty state: "A
discipler has not yet been assigned to you." **`DiscipleshipHubView` is
untouched** — its own "Message" CTA still goes through the legacy
`dm_conversation_id`/`POST /chat/dms` path. Verified by reading
`createOrGetDm`: an ordinary (non-Admin/SuperAdmin) discipler with no
accepted C3a connection would hit `CONSENT_REQUIRED` there on a first-ever
message — a pre-existing gap from the C3a work, not introduced or fixed by
this change, left for whoever next touches the Hub.

**Talk with My Pastor** — tapping calls `POST /chat/pastoral`
(create-or-open); thread renders with `ChatThreadContext.pastoral`, the
privacy line "Private pastoral conversation.", and a ⋮ menu (`pastoralMenu`
in `ChatThreadView.swift`): Lock now / Enable-Disable biometric lock / Mute /
Archive (client-side hide, `PastoralPrefs.archived`, no server call — matches
"client-side hide" in the task spec) / Privacy info (honest wording, no false
E2EE claim, matches `CHAT_REDESIGN.md`'s Security section). 404 `no_pastor`
(nothing resolves at all — rare) shows "No pastor is available for your
congregation yet."

**Biometric lock — `PastoralLock.swift`, deliberately NOT `BroadcastLock`'s
shape.** No password anywhere, nothing in the Keychain — `POST
/chat/pastoral` needs no server step-up (that's the pastor/SuperAdmin inbox's
job, not the member's own thread), so there is no password to protect.
`LAContext.evaluatePolicy(.deviceOwnerAuthentication, …)` — the non-biometric
variant, so it falls back to the device passcode when Face ID/Touch ID isn't
enrolled. Remembered-open window is **5 minutes** (Broadcast's is 15) — my
call: this guards a glance-over-the-shoulder privacy risk on the member's own
phone, not broadcast authority over the whole church, so a shorter window
felt right; documented in-code rather than silently copied. Re-locks on
`UIApplication.didEnterBackgroundNotification` (covers device-lock and
app-switch), on sign-out (`AuthStore.signOut()` → `PastoralLock.shared.reset()`,
which also forgets the remembered thread ids and mute/archive flags — the
next account on this phone starts clean), and for free on app relaunch (the
open-window state is `@Published var openUntil: Date?`, in-memory only, never
persisted). The ⋮ toggle just flips a `UserDefaults` bool
(`pastoral.lock.enabled`, **off by default** — opt-in) — enabling it does
**not** enroll a password like `BroadcastLock` does, there is none. A device
with no passcode set at all fails **open** rather than locking the member out
of their own pastoral thread forever — a deliberate judgment call, documented
in-code. The locked state (`PastoralLockedGate`) is a real branch that
**replaces** `content` in `ChatThreadView`'s view tree, not an opaque cover
over live message views — message bodies are never constructed while locked,
not just visually hidden.

**Notification preview suppression — honest finding, not a guess.** Grepped
`chat/service.ts` and `pastoral/service.ts` for every call to the `notify()`
helper: chat message sends (DM, discipler, pastoral, space — all of them)
**never call it**. Only `space_join_requested`/`space_join_accepted`/
`space_join_declined` do (both live, C1/C2), and the pastoral module never
calls `notify()` at all (only `audit()`). This app also has no real APNs push
yet (`MemberAPI.registerDevice()`'s `push_token` stays absent — needs the
paid Apple Developer Program, per existing project notes); its only
notification surface is `Notifications/LocalNotifier.swift`, which polls `GET
/me/notifications` and posts local `UNNotificationRequest`s from whatever
templates come back. **Conclusion: there is currently nothing to leak** — no
chat message of any kind produces a notification, pastoral or otherwise.
`LocalNotifier` was still extended, defensively: any future `pastoral*`
template gets the owner brief's exact locked-copy wording ("You have a new
private pastoral message.") with the body always suppressed, and the newly-
live `space_join_requested`/`space_join_accepted`/`space_join_declined` +
`connection*` templates got real titles instead of falling through to the
generic "Nuru Pathway". This is forward-compatible readiness, not an active
fix to an active leak — stated plainly rather than implied.

**Pastor/SuperAdmin "Talk with Your Pastor" inbox** (`PastoralInboxSection`
in the new `PastoralViews.swift`) reuses `BroadcastLock` + `PasswordConfirmSheet`
exactly as instructed (this is the one place C3b deliberately copies
Broadcast's shape, since `GET /chat/pastoral/inbox` genuinely does require the
same server password step-up) — same Face-ID-releases-password fast path,
same 15-minute window, same sealed-door gate UI. **Judgment call on
placement/visibility**: it lives inside the "Talk with My Pastor" tab body
(appended below the member's own thread card) rather than as a 6th top-level
tab, and is gated on `isStaff` (SuperAdmin) — the exact same bar Broadcast
uses, on the same precedent (Broadcast's own console lives inside the Chat
screen as a role-gated segment, not a separate navigation structure). **Known
gap, stated honestly**: `PastoralService.inbox()` on the server also allows
any user who has *ever* held a `pastor_assignments` row, not just SuperAdmin
— but the route's middleware order is `requirePasswordStepUp()` BEFORE the
"not a pastor" 403 can even fire, so there is no side-effect-free way for the
client to probe "am I a pastor" to decide whether to show the entry point
without first forcing a password prompt on every member. Rather than build
that (bad UX: a password prompt just to find out a menu item shouldn't
exist), this client shows the inbox only to SuperAdmin, matching Broadcast's
existing precedent exactly, as instructed. A non-SuperAdmin pastor assigned
via `POST /admin/pastor-assignments` today has no client-side way to reach
their inbox — real, not hidden.

**Chat tab dedup**: `ChatInboxViewModel.dms` now excludes any conversation id
in `PastoralPrefs` (remembered the first time each dedicated tab resolves its
thread). Since neither `GET /chat/conversations` nor `GET
/chat/conversations/:id` return `type`, this is inherently a client-side,
session/device-taught heuristic, not a real fix — a discipler/pastoral thread
that this device has never opened through its own tab (e.g. a thread created
before this feature shipped, or opened for the first time on a second device)
will still show up as an ordinary row in the Chat tab until the member visits
"My Discipler"/"Talk with My Pastor" once. Documented rather than solved;
fixing it properly needs the backend to start sending `type`, which is out of
scope (backend untouched, per instruction).

Files: `Networking/MemberAPI+Pastoral.swift` (new — DTOs + the 4 calls),
`Features/Chat/PastoralLock.swift` (new — the lock + `PastoralPrefs`),
`Features/Chat/PastoralViews.swift` (new — `PrivateThreadCard`,
`PastoralInboxSection`), `Features/Chat/ChatView.swift` (segment enum grew
`.discipler`/`.pastor`, replaced `.group`; new tab bodies; `follow()`'s
join-request fallback), `Features/Chat/ChatThreadView.swift`
(`ChatThreadContext`, `ThreadRoute`, `pastoralMenu`, `PastoralLockedGate`),
`Auth/AuthStore.swift` (`PastoralLock.shared.reset()` on sign-out),
`Notifications/LocalNotifier.swift` (template copy above).

Verified: `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" -derivedDataPath build/dd build` →
BUILD SUCCEEDED; `... test` → 10/10 green (first attempt hit a transient
simulator-busy `FBSOpenApplicationServiceErrorDomain` launch failure —
unrelated to this change, resolved by rerunning against the same, by-then-
idle simulator). Committed in 4 pieces on `feat/chat-four-tabs`
(`28fa934` API surface, `612eb42` four-tab restructure, `809ba9c`
`PastoralLock`, `ad70f83` thread contexts/menu/gate); this doc update is a
5th. Not pushed / no PR opened (per task instruction).

## 2026-07-20 — Selah (My Thoughts) + AI Prayer Points: Prayer Room tabs 3 & 4 (branch feat/selah-prayer-points, this repo only, client against LIVE backend pathway#391)

Prayer Room grew from three tabs (Private · Corporate · Answered) to four
(Private · Corporate · Selah · Prayer Points). Answered lost its top-level
slot but not its function — `PrayerJournalView`'s own Active/Answered chips
already show whenever it isn't force-pinned, so nothing about Answered was
removed, only relocated (no external call site passed `.answered` as an
`initialTab`, confirmed by grep before the cut).

**Selah — My Thoughts** (`SelahView.swift`, `ThoughtsViewModel`): a private
rich-text + pen journal against the now-live `/me/thoughts` REST surface,
wired through the SAME offline mutation queue as the prayer journal
(`SyncCoordinator.enqueue(domain: "member_thoughts", op: "upsert"/"delete")` —
confirmed server-side in `sync/service.ts:304-316` before wiring). One-time
explainer card (`@AppStorage("nuru.selah.explainerDismissed")`, the
`readerNight` idiom) with the owner's exact copy; empty state "Selah. Pause
here — write your first thought."; list rows show title/preview/relative time
+ a pencil glyph when a thought carries a drawing.

**The editor** (`SelahEditorView.swift` + `SelahRichEditor.swift`) is a
full-screen `UITextView` bridge (`RichTextEditor`/`RichEditorController`) —
Bold, Italic, a 6-swatch color menu, and a 4-face font menu (Inter/Fraunces/
Georgia/Noteworthy — two brand fonts + two free system fonts, deliberately
not bundling new assets) all persist PER SPAN via `ThoughtSpan{start,end,
bold?,italic?,color?,font?}`, extracted by walking the edited
`NSAttributedString`'s runs and merging adjacent identical runs (capped at
the server's 2000-span max). **Line spacing is honestly scoped as a GLOBAL
preference, not per-span** — the backend's `ThoughtSpan` has no spacing
field (confirmed reading `thoughts/service.ts`'s zod schema before building),
so a per-run line-height would silently do nothing for the rest of the note;
spacing is instead `@AppStorage("nuru.selah.lineSpacing")` applied to the
whole `UITextView`, same idiom as `readerNight`. Stated plainly rather than
silently shipping a control that doesn't actually round-trip.

**Pen drawing** (`SelahDrawingSheet.swift`) is real PencilKit (`PKCanvasView`,
`.anyInput` policy, `PKToolPicker`), gated to `UIDevice.current
.userInterfaceIdiom == .pad` — Apple Pencil doesn't exist for iPhone, so the
"Draw" toolbar entry point is hidden there rather than offering a dead end.
A drawing exports to PNG (`PKDrawing.image(from:scale:)`) and uploads through
the EXISTING `chat/attachments/sign` → Cloudinary flow
(`MemberAPI.signChatAttachment(kind: "image")` + `uploadChatAttachment`) —
confirmed the backend's `kind` enum accepts `"image"` before reusing it, no
new upload path invented. Delivered `secure_url`s append to `drawing_urls`;
removable locally before Save (no server-side cleanup of the orphaned
Cloudinary asset — same practice as every other attachment flow in this app).

**Prayer Points** (`PrayerPointsView.swift`) against the intelligence layer's
`PrayerAiService` (`intelligence/prayer.ts`, read before wiring): (a) an
assist composer — seed points → `POST /me/prayer/assist` → an editable draft
in the member's own voice, mirroring `AiDraftButton`'s visual idiom (purple→
gold orb, "Use draft"/"Discard") without reusing the component itself (the
wire shape differs — `assistantChat` summarizes a thread, `/me/prayer/assist`
takes a bare `seed`); (b) "Gather my prayer points" → `POST /me/prayer/points`
→ an editable, removable, copy-all numbered list, the corpus generator. Both
consent-gate on `ai_opt_out` — there is no separate "Sunday Letter consent
prompt" component in this codebase to reuse (checked `LetterView.swift`; the
letter itself just doesn't compose server-side when opted out), so this ships
its own gate card using the exact copy from `ProfileView`'s "Nuru
Intelligence" section, with a one-tap "Turn on AI personalization" CTA that
calls the same `MemberAPI.setAiConsent` the Profile toggle uses.

**Sync plumbing**: `member_thoughts` added to `SyncEngine.pullIdField`
(`"thought_id"`) and `SyncCoordinator.pullDomains`, matching `prayer_entries`
— confirmed `member_thoughts` is in the backend's pull-domain map
(`sync/service.ts:64`) before adding, so background delta pulls now warm the
Selah cache the same way they warm the prayer journal's.

**Honest limits**: (1) line spacing is global, not per-thought (schema
constraint, explained above); (2) drawings are add/remove-locally only — no
in-place re-editing of a saved stroke once uploaded (ships a flattened PNG,
matching the task's "clearly-scoped" fallback for anything beyond a fully-
working rich editor + real pen capture); (3) the rich editor's formatting
menus (color/font) apply to the current UITextView selection or, with an
empty selection, to `typingAttributes` going forward — full parity with how
Notes/Pages behave, no gap here.

Files: `Models/Thought.swift`, `Networking/MemberAPI+Thoughts.swift`,
`Features/Community/SelahRichEditor.swift`, `Features/Community/
SelahDrawingSheet.swift`, `Features/Community/SelahEditorView.swift`,
`Features/Community/SelahView.swift`, `Features/Community/
PrayerPointsView.swift`, `Features/Community/PrayerRoomView.swift` (tabs),
`Offline/SyncCoordinator.swift` + `Offline/OfflineStore.swift`
(`member_thoughts` pull wiring).

Verified: `xcodebuild -scheme NuruMember -configuration Debug -destination
"id=8265F608-4A98-4E95-9074-7C54BEC4684A" -derivedDataPath build/dd build` →
BUILD SUCCEEDED; `... test` → 10/10 green (simulator needed an explicit
`xcrun simctl boot` first — it was Shutdown, same transient-environment class
as the prior session's launch failure, not a code issue). Not pushed / no PR
opened (per task instruction).
