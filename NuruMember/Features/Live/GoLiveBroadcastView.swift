// Nuru Live L3 — the broadcast screen. Present with `.fullScreenCover(item:)`
// once GoLiveSetupSheet's POST /live/streams succeeds. Video shows a camera
// preview (HaishinKit's MTHKView, wrapped via MTHKViewRepresentable); audio
// shows the Radio screen's waveform language standing in for a video surface
// that doesn't exist. Both show the same LIVE HUD (pulsing dot, elapsed
// timer, "N watching") and controls (mute, flip camera, End).
//
// There is deliberately NO plain close/✕ while `.live` or `.reconnecting` —
// the only way out of an active broadcast is the End button's confirmation,
// so a stray swipe can never abandon a stream mid-air. A close IS offered
// while `.configuring` (before anything is actually publishing) and once
// `.ended` (summary/permission-denied), both of which already call `end()`
// through BroadcastController before the view can be dismissed.
import AVKit
import HaishinKit
import SwiftUI

struct GoLiveBroadcastView: View {
    @StateObject private var controller: BroadcastController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmEnd = false

    init(session: GoLiveSession) {
        _controller = StateObject(wrappedValue: BroadcastController(session: session))
    }

    var body: some View {
        ZStack {
            Nuru.navyDeep.ignoresSafeArea()
            content
            hud
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(controller.phase == .live && controller.isVideo)
        .task { await controller.start() }
        .onDisappear { Task { await controller.end() } }
        // Both kinds end cleanly on background — see BroadcastController.
        // handleBackgrounded's doc comment for the documented tradeoff
        // (iOS suspends camera capture in the background regardless; giving
        // audio the same simple/safe treatment was the deliberate call here
        // rather than wiring a background-audio session category).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { controller.handleBackgrounded() }
        }
        .confirmationDialog("End this stream?", isPresented: $confirmEnd, titleVisibility: .visible) {
            Button("End stream", role: .destructive) {
                Haptics.action()
                Task { await controller.end() }
            }
            Button("Keep going", role: .cancel) {}
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
        if controller.isVideo {
            MTHKViewRepresentable(previewSource: controller, videoGravity: .resizeAspectFill)
                .ignoresSafeArea()
        } else {
            LiveBroadcastAudioBackdrop(title: controller.session.title)
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
    }

    @ViewBuilder private var endedView: some View {
        switch controller.endedReason {
        case .summary:
            summaryView
        case .permissionDenied:
            permissionDeniedEndedView
        }
    }

    private var summaryView: some View {
        let duration = (controller.endedAt ?? Date()).timeIntervalSince(controller.startedAt ?? controller.endedAt ?? Date())
        return VStack(spacing: 18) {
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.16)).frame(width: 96, height: 96)
                Icon(.checkCircle2, size: 36, color: Nuru.gold)
            }
            Text("You're offline now").font(.fraunces(22, .semibold)).foregroundStyle(.white)
            Text("You were live for \(formatDuration(duration)) · peak \(controller.peakViewerCount) watching")
                .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text("Done").font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            Button { Haptics.tap(); dismiss() } label: {
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
                Spacer()
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

    private var controlsRow: some View {
        HStack(spacing: 20) {
            controlButton(icon: controller.isMuted ? "mic.slash.fill" : "mic.fill", active: controller.isMuted) {
                Haptics.tap(); controller.toggleMute()
            }
            .accessibilityLabel(controller.isMuted ? "Unmute" : "Mute")

            Button {
                Haptics.action()
                confirmEnd = true
            } label: {
                Text("End").font(.inter(14, .bold)).foregroundStyle(.white)
                    .frame(width: 92, height: 48)
                    .background(Color(hex: 0xDC2626), in: Capsule())
            }
            .buttonStyle(.pressable)

            if controller.isVideo {
                controlButton(icon: "arrow.triangle.2.circlepath.camera.fill", active: false) {
                    Haptics.tap(); controller.flipCamera()
                }
                .accessibilityLabel("Flip camera")
            } else {
                // Keeps the End button visually centered for audio-only.
                Color.clear.frame(width: 48, height: 48)
            }
        }
        .padding(.bottom, 28)
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

    private var closeButton: some View {
        Button {
            Haptics.tap()
            Task { await controller.end() }
            dismiss()
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
