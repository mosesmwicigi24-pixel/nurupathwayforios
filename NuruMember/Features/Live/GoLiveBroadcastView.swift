// Nuru Live L3 — the broadcast screen. RootView presents this via ONE
// `fullScreenCover` bound to BroadcastCenter.shared (see BroadcastCenter.swift),
// so this view is a thin "remote control" over a controller it doesn't own —
// exactly like RadioPlayerView is a remote control over RadioCenter.shared.
// Video shows a camera preview (HaishinKit's MTHKView, wrapped via
// MTHKViewRepresentable) OR the Document pager OR the Screen-share
// placeholder, depending on `controller.videoSource`; audio-kind broadcasts
// show the Radio screen's waveform language standing in for a video surface
// that doesn't exist. Both show the same LIVE HUD (pulsing dot, elapsed
// timer, "N watching") and controls (mute, flip camera / back-to-camera,
// source switcher, End, ✋, 💬).
//
// "Broadcast Studio" arc — leave-the-page persistence: the chevron-down
// MINIMIZES (BroadcastCenter.shared.minimize()) rather than ending anything;
// the controller keeps mixing/publishing exactly as before, and RootView's
// floating island becomes the "you're still live" surface on every other
// screen. There is deliberately still NO plain close while `.live` or
// `.reconnecting` beyond minimize — the only way to actually STOP a
// broadcast is the End button's confirmation (here or on the island), so a
// stray tap can never abandon a stream mid-air, and leaving the screen never
// does either.
import AVKit
import HaishinKit
import SwiftUI

struct GoLiveBroadcastView: View {
    @ObservedObject var controller: BroadcastController
    @ObservedObject private var documentSource: DocumentSource
    @ObservedObject private var broadcast = BroadcastCenter.shared
    @StateObject private var reactionQueue = ReactionBurstQueue()
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmEnd = false
    // L5 interactive stage — ✋ hand queue / guests sheet and 💬 live chat,
    // both fed by controller.pulse (the same 3s poll that already tracks
    // viewer count).
    @State private var showHandsSheet = false
    // Taste pass (2026-07-31): the broadcaster now gets the SAME compact,
    // draggable `LiveFloatingChatOverlay` the viewer uses instead of the
    // modal `LiveChatSheet` — chat toggles on/off in place rather than
    // covering the whole stage. `LiveChatSheet.swift` itself is left as-is,
    // just no longer presented from here.
    @State private var chatOverlayVisible = false
    // Broadcast Studio — Camera / Document / Screen source switcher.
    @State private var showSourceSheet = false
    // End-of-broadcast stewardship (Keep in Replays / Delete recording).
    @State private var confirmDeleteRecording = false
    @State private var deletingRecording = false
    @State private var recordingDeleted = false

    init(controller: BroadcastController) {
        self.controller = controller
        self.documentSource = controller.documentSource
    }

    var body: some View {
        ZStack {
            Nuru.navyDeep.ignoresSafeArea()
            content
            hud
        }
        .overlay(alignment: .bottomTrailing) {
            if controller.phase == .live || isReconnecting {
                FloatingReactionsOverlay(queue: reactionQueue)
                    .padding(.bottom, 112).padding(.trailing, 14)
            }
        }
        .overlay {
            // Shared floating chat — full-bleed so it can be dragged anywhere
            // (see LiveFloatingChatOverlay's header comment). Replaces the
            // modal LiveChatSheet on this screen too, matching the viewer.
            if controller.phase == .live || isReconnecting {
                LiveFloatingChatOverlay(
                    streamId: controller.session.stream.streamId, myUserId: auth.profile?.userId,
                    handsRaisedCount: controller.pulse?.hands.count ?? 0,
                    visible: $chatOverlayVisible
                )
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(controller.phase == .live && controller.isVideo)
        // NOTE: no `.task { await controller.start() }` here — BroadcastCenter
        // calls `start()` exactly once, the moment the setup sheet hands back
        // a session (see `BroadcastCenter.start(session:)`), independent of
        // whether this view is even on screen. Re-presenting after a
        // minimize/restore cycle must NOT re-run it.
        //
        // NOTE: no `.onDisappear` teardown either — this view disappears on
        // ordinary minimize (chevron / island round-trip) just as often as on
        // a real End, and the whole point of this arc is that the former
        // must never stop publishing. Every path that actually ends the
        // broadcast calls `controller.end()` (or, before anything started,
        // `BroadcastCenter.shared.clear()`) explicitly — see the End
        // confirmation below, `failedView`'s End button, the island's own End
        // control, and `closeButton`.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.handleBackgrounded() }
            else if phase == .active { controller.handleForegrounded() }
        }
        .onChange(of: controller.freshReactions) { _, fresh in
            guard !fresh.isEmpty else { return }
            for r in fresh { reactionQueue.spawn(emoji: r.emoji, reduceMotion: reduceMotion) }
            controller.clearFreshReactions()
        }
        .confirmationDialog("End this stream?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End stream", role: .destructive) {
                Haptics.action()
                Task { await controller.end() }
            }
            Button("Keep going", role: .cancel) {}
        }
        .sheet(isPresented: $showHandsSheet) {
            LiveHandsGuestsSheet(controller: controller)
        }
        .sheet(isPresented: $showSourceSheet) {
            BroadcastSourceSheet(controller: controller)
        }
    }

    // MARK: Main content by phase

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .configuring:
            configuringView
        case .live, .reconnecting:
            liveSurface
        case .failed(let message):
            failedView(message)
        case .ended:
            endedView
        }
    }

    private var configuringView: some View {
        VStack(spacing: 14) {
            ProgressView().tint(Nuru.gold).scaleEffect(1.3)
            Text(controller.isVideo ? "Getting your camera ready…" : "Getting your mic ready…")
                .font(.inter(13)).foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) { closeButton }
    }

    @ViewBuilder private var liveSurface: some View {
        switch controller.videoSource {
        case .camera:
            if controller.isVideo {
                MTHKViewRepresentable(previewSource: controller, videoGravity: .resizeAspectFill)
                    .ignoresSafeArea()
            } else {
                LiveBroadcastAudioBackdrop(title: controller.session.title)
            }
        case .document:
            DocumentPagerView(source: documentSource, pageIndex: $controller.documentPageIndex)
                .ignoresSafeArea()
        case .screen:
            ScreenShareActiveView()
        }
        if documentSource.isLoading {
            ZStack {
                Color.black.opacity(0.55).ignoresSafeArea()
                VStack(spacing: 10) {
                    ProgressView().tint(Nuru.gold)
                    Text("Opening document…").font(.inter(12)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        if case .reconnecting(let attempt) = controller.phase {
            reconnectingOverlay(attempt: attempt)
        }
    }

    private func reconnectingOverlay(attempt: Int) -> some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(Nuru.gold).scaleEffect(1.2)
                Text("Reconnecting… (\(attempt)/3)")
                    .font(.inter(13, .semibold)).foregroundStyle(.white)
                Text("Hold tight — your camera and mic are still on.")
                    .font(.inter(11)).foregroundStyle(.white.opacity(0.6))
            }
        }
    }

    private func failedView(_ message: String) -> some View {
        VStack(spacing: 18) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.system(size: 36)).foregroundStyle(Nuru.gold.opacity(0.85))
            VStack(spacing: 4) {
                Text("Connection lost").font(.fraunces(19, .semibold)).foregroundStyle(.white)
                Text(message).font(.inter(12)).foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
            }
            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    controller.retryFromFailure()
                } label: {
                    Text("Retry").font(.inter(13, .bold)).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Nuru.gold, in: Capsule())
                }
                .buttonStyle(.pressable)
                Button {
                    Haptics.tap()
                    confirmEnd = true
                } label: {
                    Text("End").font(.inter(13, .semibold)).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 22).padding(.vertical, 11)
                        .background(Color.white.opacity(0.1), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                }
                .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
        .overlay(alignment: .topLeading) { minimizeButton }
    }

    @ViewBuilder private var endedView: some View {
        switch controller.endedReason {
        case .summary:
            summaryView
        case .permissionDenied:
            permissionDeniedEndedView
        }
    }

    /// End-of-broadcast stewardship (owner taste pass, 2026-07-31): the
    /// registrar's recording sweep runs in the background (best-effort
    /// inline attempt + a ~2min worker backstop — see the module's own
    /// OPS FOLLOW-UP note), so a recording may not exist yet the instant
    /// this screen appears; deleting one that isn't registered yet is a
    /// harmless no-op (`deleteRecording` best-effort catches the resulting
    /// NOT_FOUND). "Keep in Replays" needs no API call at all — keeping is
    /// simply the default, so dismissing this screen any other way (or not
    /// deleting) already achieves it.
    private var summaryView: some View {
        let duration = (controller.endedAt ?? Date()).timeIntervalSince(controller.startedAt ?? controller.endedAt ?? Date())
        return VStack(spacing: 18) {
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.16)).frame(width: 96, height: 96)
                Icon(recordingDeleted ? .trash2 : .checkCircle2, size: 36, color: Nuru.gold)
            }
            Text("You're offline now").font(.fraunces(22, .semibold)).foregroundStyle(.white)
            Text("You were live for \(formatDuration(duration)) · peak \(controller.peakViewerCount) watching")
                .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            if recordingDeleted {
                Text("Recording deleted").font(.inter(12, .semibold)).foregroundStyle(.white.opacity(0.5))
            }
            Button {
                Haptics.tap()
                BroadcastCenter.shared.clear()
            } label: {
                Text(recordingDeleted ? "Done" : "Keep in Replays").font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, 40)
            if !recordingDeleted {
                Button {
                    Haptics.tap()
                    confirmDeleteRecording = true
                } label: {
                    HStack(spacing: 6) {
                        if deletingRecording {
                            ProgressView().tint(Color(hex: 0xDC2626).opacity(0.8)).scaleEffect(0.7)
                        } else {
                            Icon(.trash2, size: 12, color: Color(hex: 0xDC2626).opacity(0.85))
                        }
                        Text("Delete recording").font(.inter(12.5, .semibold)).foregroundStyle(Color(hex: 0xDC2626).opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .disabled(deletingRecording)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .confirmationDialog("Delete this recording?", isPresented: $confirmDeleteRecording, titleVisibility: .visible) {
            Button("Delete forever", role: .destructive) {
                Haptics.action()
                Task { await deleteRecording() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete '\(controller.session.title)'? The recording will be gone forever.")
        }
    }

    private func deleteRecording() async {
        guard !deletingRecording else { return }
        deletingRecording = true
        defer { deletingRecording = false }
        do {
            try await MemberAPI.deleteLiveRecording(streamId: controller.session.stream.streamId)
            Haptics.success()
            recordingDeleted = true
        } catch {
            Haptics.error()
            // Best-effort: most likely the registrar hasn't attached a
            // recording_url yet (NOT_FOUND) — nothing to steward in that
            // case, and "Keep in Replays" (doing nothing) is already correct.
        }
    }

    /// A defensive re-check of camera/mic access failed once this screen
    /// appeared (access was revoked in the gap since the setup sheet's own
    /// pre-flight check passed) — the stream row was already ended
    /// server-side by BroadcastController; this just explains why.
    private var permissionDeniedEndedView: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Color.white.opacity(0.10)).frame(width: 72, height: 72)
                Icon(controller.isVideo ? .camera : .mic, size: 28, color: Nuru.gold)
            }
            Text(controller.isVideo ? "Camera access needed" : "Microphone access needed")
                .font(.fraunces(21, .medium)).foregroundStyle(.white)
            Text("Access was turned off before this broadcast could start. Turn it on in Settings and go live again.")
                .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button {
                Haptics.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            } label: {
                Text("Open Settings").font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, 40)
            Button { Haptics.tap(); BroadcastCenter.shared.clear() } label: {
                Text("Close").font(.inter(13, .semibold)).foregroundStyle(.white.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: HUD chrome — pulsing dot + elapsed + "N watching", controls

    @ViewBuilder private var hud: some View {
        if controller.phase == .live || isReconnecting {
            VStack {
                topBadges
                if controller.videoPausedInBackground { cameraPausedPill.padding(.top, 6) }
                Spacer()
                if controller.videoSource == .document, !documentSource.pages.isEmpty {
                    documentPageBadge.padding(.bottom, 10)
                }
                controlsRow
            }
        }
    }

    private var isReconnecting: Bool {
        if case .reconnecting = controller.phase { return true }
        return false
    }

    private var topBadges: some View {
        HStack(alignment: .top) {
            minimizeButton
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    PulsingBroadcastDot()
                    Text("LIVE").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(.white)
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color(hex: 0xDC2626), in: Capsule())
                Text(controller.session.title).font(.inter(12, .semibold)).foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color.black.opacity(0.35), in: Capsule())
            }
            Spacer(minLength: 8)
            if controller.isVideo { sourceButton }
            VStack(alignment: .trailing, spacing: 6) {
                if let startedAt = controller.startedAt {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        Text(formatDuration(ctx.date.timeIntervalSince(startedAt)))
                            .font(.inter(11, .semibold)).monospacedDigit().foregroundStyle(.white)
                            .padding(.horizontal, 9).padding(.vertical, 4)
                            .background(Color.black.opacity(0.45), in: Capsule())
                    }
                }
                HStack(spacing: 4) {
                    Icon(.users, size: 10, color: .white.opacity(0.9))
                    Text("\(controller.viewerCount) watching").font(.inter(10, .semibold)).foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Color.black.opacity(0.45), in: Capsule())
            }
        }
        .padding(.horizontal, 16).padding(.top, 10)
        .background(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 140)
        }
    }

    /// Leave-the-page persistence — minimizes to RootView's floating island
    /// WITHOUT touching the controller. See BroadcastCenter.minimize().
    private var minimizeButton: some View {
        Button {
            Haptics.tap()
            broadcast.minimize()
        } label: {
            Icon(.chevronDown, size: 15, color: .white)
                .frame(width: 32, height: 32)
                .background(Color.black.opacity(0.4), in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Minimize — keep broadcasting")
    }

    /// Opens the Camera/Document/Screen picker — tinted gold whenever an
    /// alternate source is active, so it doubles as a "you're not on camera"
    /// indicator at a glance.
    private var sourceButton: some View {
        Button {
            Haptics.tap()
            showSourceSheet = true
        } label: {
            Image(systemName: "rectangle.on.rectangle")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(controller.videoSource == .camera ? .white : Nuru.navy)
                .frame(width: 32, height: 32)
                .background(controller.videoSource == .camera ? Color.black.opacity(0.4) : Nuru.gold, in: Circle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Broadcast source")
        .padding(.trailing, 6)
    }

    private var cameraPausedPill: some View {
        HStack(spacing: 6) {
            Icon(.mic, size: 10, color: Nuru.gold)
            Text("Audio live — camera paused in background")
                .font(.inter(10, .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color.black.opacity(0.55), in: Capsule())
        .frame(maxWidth: .infinity)
    }

    private var documentPageBadge: some View {
        Text("Page \(controller.documentPageIndex + 1) of \(documentSource.pages.count)")
            .font(.inter(11, .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 11).padding(.vertical, 5)
            .background(Color.black.opacity(0.5), in: Capsule())
    }

    private var controlsRow: some View {
        HStack(spacing: 14) {
            controlButton(icon: controller.isMuted ? "mic.slash.fill" : "mic.fill", active: controller.isMuted) {
                Haptics.tap(); controller.toggleMute()
            }
            .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")

            Button {
                Haptics.action()
                confirmEnd = true
            } label: {
                Text("End").font(.inter(14, .bold)).foregroundStyle(.white)
                    .frame(width: 78, height: 48)
                    .background(Color(hex: 0xDC2626), in: Capsule())
            }
            .buttonStyle(.pressable)

            if controller.isVideo {
                if controller.videoSource == .camera {
                    controlButton(icon: "arrow.triangle.2.circlepath.camera.fill", active: false) {
                        Haptics.tap(); controller.flipCamera()
                    }
                    .accessibilityLabel("Flip camera")
                } else {
                    controlButton(icon: "camera.fill", active: false) {
                        Haptics.tap(); Task { await controller.selectCamera() }
                    }
                    .accessibilityLabel("Back to camera")
                }
            } else {
                // Keeps the row visually balanced for audio-only.
                Color.clear.frame(width: 48, height: 48)
            }

            handButton
            controlButton(icon: "message.fill", active: chatOverlayVisible) {
                Haptics.tap(); chatOverlayVisible.toggle()
            }
            .accessibilityLabel(chatOverlayVisible ? "Hide live chat" : "Show live chat")
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 28)
    }

    /// ✋ raised-hand queue — gold badge counts hands from the 3s pulse poll.
    private var handButton: some View {
        let count = controller.pulse?.hands.count ?? 0
        return Button {
            Haptics.tap()
            showHandsSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.white.opacity(0.14), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
                if count > 0 {
                    Text("\(min(count, 99))")
                        .font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, count > 9 ? 5 : 0)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Nuru.gold, in: Circle())
                        .overlay(Circle().stroke(Nuru.navyDeep, lineWidth: 1.5))
                        .offset(x: 5, y: -5)
                }
            }
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Raised hands, \(count)")
    }

    private func controlButton(icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(active ? Nuru.navy : .white)
                .frame(width: 48, height: 48)
                .background(active ? Nuru.gold : Color.white.opacity(0.14), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    /// Only reachable pre-live (`.configuring`) — a hard abort BEFORE
    /// anything started publishing, so it fully clears the broadcast
    /// (`BroadcastCenter.shared.clear()`, not a minimize) rather than
    /// leaving a half-started controller behind.
    private var closeButton: some View {
        Button {
            Haptics.tap()
            Task { await controller.end() }
            BroadcastCenter.shared.clear()
        } label: {
            Icon(.x, size: 18, color: .white)
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.18), in: Circle())
        }
        .buttonStyle(.pressable)
        .padding(.horizontal, 16).padding(.top, 10)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }
}

// MARK: - Small pulsing red dot (broadcaster HUD variant of the viewer chrome's)

private struct PulsingBroadcastDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        Circle().fill(.white).frame(width: 6, height: 6)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

// MARK: - Screen-share placeholder — what's on screen (and therefore what
// ReplayKit captures) if the broadcaster stays on THIS screen instead of
// minimizing to go show something elsewhere in the app. See
// BroadcastController.selectScreen's doc comment: the capture keeps running
// across a minimize/restore round-trip, so this view is only ever a
// starting point, not the whole feature.

private struct ScreenShareActiveView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            VStack(spacing: 16) {
                ZStack {
                    Circle().fill(Nuru.gold.opacity(0.14)).frame(width: 108, height: 108)
                    Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1.5).frame(width: 108, height: 108)
                    Image(systemName: "rectangle.on.rectangle")
                        .font(.system(size: 32, weight: .medium)).foregroundStyle(Nuru.gold)
                }
                Text("Sharing this screen").font(.fraunces(19, .semibold)).foregroundStyle(.white)
                Text("Minimize (the ⌄ up top) and browse Nuru — viewers see whatever you show them, and your mic stays live the whole time.")
                    .font(.inter(12)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
    }
}

// MARK: - Audio-kind backdrop — the Radio screen's navy+gold waveform
// language, standing in for a video surface that doesn't exist for an
// audio-only broadcast. See BroadcastController's header comment: this is a
// tasteful ANIMATED PLACEHOLDER, not a real mic-level meter — HaishinKit's
// public API doesn't expose one to bind to.

private struct LiveBroadcastAudioBackdrop: View {
    let title: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle()
                .fill(RadialGradient(colors: [Nuru.gold.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 220))
                .frame(width: 380, height: 380)
                .blur(radius: 30)
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Nuru.gold.opacity(0.14)).frame(width: 132, height: 132)
                    Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1.5).frame(width: 132, height: 132)
                    Icon(.mic, size: 42, color: Nuru.gold)
                }
                LiveBroadcastWaveform()
                Text("BROADCASTING AUDIO").font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Nuru.gold.opacity(0.85))
                Text(title).font(.fraunces(18, .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center).padding(.horizontal, 40)
            }
        }
        .ignoresSafeArea()
    }
}

/// Animated gold bars breathing on layered sines — the same Canvas-based
/// idiom as Radio's LiveSweepLine.wave(phase:), sized up for a full-screen
/// HUD centerpiece instead of a thin inline strip.
private struct LiveBroadcastWaveform: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if reduceMotion {
                wave(phase: 1.1)
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    let phase = ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: 2.8) / 2.8 * 2 * .pi
                    wave(phase: phase)
                }
            }
        }
        .frame(width: 180, height: 40)
        .accessibilityHidden(true)
    }

    private func wave(phase: Double) -> some View {
        Canvas { context, size in
            let n = 21
            let slot = size.width / CGFloat(n)
            let barW = min(slot * 0.5, 5)
            let mid = size.height / 2
            for i in 0..<n {
                let x = slot * CGFloat(i) + slot / 2
                let envelope = sin(.pi * Double(i) / Double(n - 1))
                let a = 0.34 + 0.26 * sin(phase + Double(i) * 0.9)
                      + 0.18 * sin(phase * 1.7 + Double(i) * 0.47 + 1.3)
                let h = max(3, size.height * min(0.9, max(0.15, a)) * (0.45 + 0.55 * envelope))
                let rect = CGRect(x: x - barW / 2, y: mid - CGFloat(h) / 2, width: barW, height: CGFloat(h))
                context.fill(Path(roundedRect: rect, cornerRadius: barW / 2),
                             with: .color(Nuru.gold.opacity(0.4 + 0.55 * envelope)))
            }
        }
    }
}
