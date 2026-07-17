// Check-in scanner — the member side of QR event attendance (§3.3). A navy
// full-screen AVFoundation scanner (AVCaptureMetadataOutput) with a gold scan
// frame, torch toggle and cancel ✕. A captured code posts
// POST /events/{id}/attendance with a client-minted lowercase UUID scan id —
// idempotent server-side, so a re-scan of the same event is a friendly no-op —
// then a success ceremony ("You're checked in ✓") or a polite failure state
// with rescan. Camera-permission denial gets a friendly Settings pointer.
import SwiftUI
@preconcurrency import AVFoundation
import UIKit

struct CheckInScannerView: View {
    let eventId: String
    let eventTitle: String
    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ScanCameraModel()
    @State private var phase: ScanPhase = .scanning
    @State private var failureNote = ""

    enum ScanPhase: Equatable { case scanning, submitting, success(duplicate: Bool), failed }

    var body: some View {
        ZStack {
            Nuru.navy.ignoresSafeArea()
            switch camera.permission {
            case .denied:
                deniedView
            default:
                switch phase {
                case .scanning, .submitting:
                    scannerView
                case .success(let duplicate):
                    successView(duplicate: duplicate)
                case .failed:
                    failedView
                }
            }
        }
        .task { await camera.start(onCode: handleCode) }
        .onDisappear { camera.stop() }
    }

    // MARK: Scanning

    private var scannerView: some View {
        ZStack {
            if camera.permission == .granted {
                ScanPreview(session: camera.session).ignoresSafeArea()
            }
            // Dim everything except the (exactly centered) scan window — the
            // cutout and the gold frame are both centered layers so they align.
            Color.black.opacity(0.45)
                .reverseMask { scanWindow }
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // The gold scan frame, centered, with the status caption hung below it.
            scanWindow
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Nuru.gold, lineWidth: 3)
                }
                .overlay {
                    if phase == .submitting {
                        ZStack {
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .fill(Nuru.navy.opacity(0.55))
                            ProgressView().tint(Nuru.gold).scaleEffect(1.4)
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    Text(phase == .submitting ? "Checking you in…" : "Point at the check-in code on the screen")
                        .font(.inter(13)).foregroundStyle(.white.opacity(0.85))
                        .fixedSize()
                        .offset(y: 44)
                }

            VStack(spacing: 0) {
                header
                Spacer()
                footer
            }
            .padding(.horizontal, Nuru.S.screen)
        }
    }

    /// The 260pt square the member aims at — also the dim-mask cutout shape.
    private var scanWindow: some View {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
            .fill(Color.white.opacity(0.001))
            .frame(width: 260, height: 260)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("EVENT CHECK-IN")
                    .font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
                Text(eventTitle)
                    .font(.fraunces(20, .semibold)).kerning(-0.4).foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Nuru.S.md)
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                ZStack {
                    Circle().fill(Color.white.opacity(0.12)).frame(width: 36, height: 36)
                    Icon(.x, size: 17, color: .white)
                }
            }
            .buttonStyle(.pressable)
        }
        .padding(.top, Nuru.S.lg)
    }

    private var footer: some View {
        VStack(spacing: Nuru.S.md) {
            if camera.torchAvailable {
                Button {
                    Haptics.tap()
                    camera.toggleTorch()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: camera.torchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(camera.torchOn ? Nuru.navy : .white)
                        Text(camera.torchOn ? "Torch on" : "Torch")
                            .font(.inter(13, .semibold))
                            .foregroundStyle(camera.torchOn ? Nuru.navy : .white)
                    }
                    .padding(.horizontal, 18).frame(height: 44)
                    .background(camera.torchOn ? Nuru.gold : Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: Outcomes

    private func successView(duplicate: Bool) -> some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.18)).frame(width: 108, height: 108)
                Circle().fill(Nuru.gold).frame(width: 80, height: 80)
                Icon(.check, size: 34, color: Nuru.navy)
            }
            .gentleEntrance()
            Text("You're checked in ✓")
                .font(.fraunces(24, .medium)).kerning(-0.48).foregroundStyle(.white)
                .padding(.top, Nuru.S.lg)
                .gentleEntrance(delay: 0.08)
            Text(duplicate ? "You were already checked in — all set." : eventTitle)
                .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
                .gentleEntrance(delay: 0.16)
            Spacer()
            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text("Done")
                    .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, Nuru.S.xl).padding(.bottom, Nuru.S.xl)
        }
    }

    private var failedView: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color.white.opacity(0.10)).frame(width: 72, height: 72)
                Icon(.qrCode, size: 28, color: Nuru.gold)
            }
            Text("That code didn't work")
                .font(.fraunces(21, .medium)).kerning(-0.42).foregroundStyle(.white)
                .padding(.top, Nuru.S.base)
            Text(failureNote.isEmpty
                 ? "It may be the wrong or an expired code. Grab the latest one on the screen and try again."
                 : failureNote)
                .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
            Spacer()
            VStack(spacing: Nuru.S.sm) {
                Button {
                    Haptics.tap()
                    failureNote = ""
                    phase = .scanning
                    camera.resumeScanning()
                } label: {
                    Text("Scan again")
                        .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.inter(14, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Nuru.S.xl).padding(.bottom, Nuru.S.xl)
        }
    }

    /// Camera denied — a friendly pointer to Settings, never a dead end.
    private var deniedView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.12)).frame(width: 36, height: 36)
                        Icon(.x, size: 17, color: .white)
                    }
                }
                .buttonStyle(.pressable)
            }
            .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.lg)
            Spacer()
            ZStack {
                Circle().fill(Color.white.opacity(0.10)).frame(width: 72, height: 72)
                Icon(.camera, size: 28, color: Nuru.gold)
            }
            Text("Camera access needed")
                .font(.fraunces(21, .medium)).kerning(-0.42).foregroundStyle(.white)
                .padding(.top, Nuru.S.base)
            Text("Nuru uses the camera only to scan the event check-in code. Turn it on in Settings and come back.")
                .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm).padding(.horizontal, Nuru.S.xl)
            Spacer()
            Button {
                Haptics.tap()
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            } label: {
                Text("Open Settings")
                    .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 48)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, Nuru.S.xl).padding(.bottom, Nuru.S.xl)
        }
    }

    // MARK: Submit — one attempt per captured code; server stays authoritative.

    private func handleCode(_ token: String) {
        guard phase == .scanning else { return }
        Haptics.tap()                       // the scanner "tick" — code captured
        camera.pauseScanning()              // no double-fires while we submit
        phase = .submitting
        Task {
            do {
                let result = try await MemberAPI.checkIn(eventId: eventId, scanToken: token)
                phase = .success(duplicate: result.duplicate)
                Haptics.success()
            } catch {
                failureNote = friendlyFailure(error)
                phase = .failed
                Haptics.error()
            }
        }
    }

    private func friendlyFailure(_ error: Error) -> String {
        guard let api = error as? APIError else {
            return "Something went wrong — try scanning again."
        }
        if api.isNetwork {
            return "You're offline — check-in needs a connection. Reconnect and scan again."
        }
        if case .http(_, let code, let message, _) = api {
            switch code ?? "" {
            case "VALIDATION_FAILED":
                return "That code isn't valid for this event — it may have expired. Grab the latest one on the screen and try again."
            case "NOT_FOUND":
                return "We couldn't find this event — pull the event page down to refresh and try again."
            default:
                return message   // e.g. "Check-in has not opened yet for this event"
            }
        }
        return api.errorDescription ?? "Something went wrong — try scanning again."
    }
}

// MARK: - Camera model (AVCaptureSession + QR metadata output)

@MainActor
final class ScanCameraModel: NSObject, ObservableObject, AVCaptureMetadataOutputObjectsDelegate {
    enum Permission { case unknown, granted, denied }

    @Published var permission: Permission = .unknown
    @Published var torchOn = false
    @Published var torchAvailable = false

    let session = AVCaptureSession()
    private var device: AVCaptureDevice?
    private var onCode: ((String) -> Void)?
    private var configured = false
    private var scanningPaused = false
    private var lastEmitted: String?
    /// startRunning/stopRunning block — keep them off the main thread.
    private let sessionQueue = DispatchQueue(label: "org.nuruplace.checkin.camera")

    func start(onCode: @escaping (String) -> Void) async {
        self.onCode = onCode
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            permission = .granted
        case .notDetermined:
            let ok = await AVCaptureDevice.requestAccess(for: .video)
            permission = ok ? .granted : .denied
        default:
            permission = .denied
        }
        guard permission == .granted else { return }
        configureIfNeeded()
        let session = self.session
        sessionQueue.async {
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        if torchOn { toggleTorch() }
        let session = self.session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    func pauseScanning() { scanningPaused = true }

    func resumeScanning() {
        lastEmitted = nil
        scanningPaused = false
    }

    func toggleTorch() {
        guard let device, device.hasTorch else { return }
        do {
            try device.lockForConfiguration()
            device.torchMode = torchOn ? .off : .on
            device.unlockForConfiguration()
            torchOn.toggle()
        } catch {
            // Torch is a nicety — never surface an error for it.
        }
    }

    private func configureIfNeeded() {
        guard !configured else { return }
        configured = true
        session.beginConfiguration()
        session.sessionPreset = .high
        if let dev = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: dev),
           session.canAddInput(input) {
            session.addInput(input)
            device = dev
            torchAvailable = dev.hasTorch
        }
        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            if output.availableMetadataObjectTypes.contains(.qr) {
                output.metadataObjectTypes = [.qr]
            }
        }
        session.commitConfiguration()
    }

    /// Delegate runs on the main queue (set above); hop into the actor to emit.
    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput,
                                    didOutput metadataObjects: [AVMetadataObject],
                                    from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr,
              let code = obj.stringValue, !code.isEmpty else { return }
        Task { @MainActor in
            guard !self.scanningPaused, code != self.lastEmitted else { return }
            self.lastEmitted = code
            self.onCode?(code)
        }
    }
}

// MARK: - Preview layer host

private struct ScanPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewHost {
        let v = PreviewHost()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: PreviewHost, context: Context) {}

    final class PreviewHost: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Reverse mask (dim overlay with a see-through scan window)

private extension View {
    /// Masks OUT the given shape — everything except `mask` keeps the modified
    /// view (here: the dim layer), the shape itself stays clear.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                mask().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
