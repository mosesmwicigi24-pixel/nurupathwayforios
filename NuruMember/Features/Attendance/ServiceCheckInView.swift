// Church service attendance — the member arrives, opens the app, and scans the
// QR on the sanctuary screen. One scan carries BOTH the service id and its HMAC
// (`nuru-service:<service_id>:<token>`), so there is no "pick your service"
// step: point the camera and you're registered.
//
// After a capture the member confirms the contact details that go on the
// attendance record (name, phone, email — prefilled from their profile, editable
// because the phone on file is often not the one they carry), then submits. The
// server records the time of attending and returns the updated streak, which we
// show as the reward for showing up.
//
// Port parity: Android ServiceCheckInScreen.kt. Camera plumbing is shared with
// CheckInScannerView (ScanCameraModel).
import SwiftUI
import AVFoundation
import UIKit

struct ServiceCheckInView: View {
    let memberName: String
    let memberPhone: String
    let memberEmail: String?
    /// Called when the member wants to see the full attendance record.
    var onSeeAttendance: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @StateObject private var camera = ScanCameraModel()

    @State private var phase: Phase = .scanning
    @State private var scan: ServiceScan?
    @State private var result: ServiceCheckInResult?
    @State private var failureNote = ""

    // The registration form — prefilled so the common case is one tap.
    @State private var name = ""
    @State private var phone = ""
    @State private var email = ""

    /// Minted once per captured code so a retry after a network failure is the
    /// SAME scan to the server — a replay, not a second attendance row (§3.6).
    @State private var scanId = UUID().uuidString.lowercased()

    enum Phase: Equatable { case scanning, registering, submitting, done }

    var body: some View {
        ZStack {
            Nuru.navy.ignoresSafeArea()
            switch camera.permission {
            case .denied where phase == .scanning:
                deniedView
            default:
                switch phase {
                case .scanning:                 scannerView
                case .registering, .submitting: registrationView
                case .done:                     successView
                }
            }
        }
        .task {
            name = memberName
            phone = memberPhone
            email = memberEmail ?? ""
            await camera.start(onCode: handleCode)
        }
        .onDisappear { camera.stop() }
    }

    // MARK: Scanning

    private var scannerView: some View {
        ZStack {
            if camera.permission == .granted {
                ServiceScanPreview(session: camera.session).ignoresSafeArea()
            }
            Color.black.opacity(0.45)
                .punchOut { scanWindow }
                .ignoresSafeArea()
                .allowsHitTesting(false)

            scanWindow
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Nuru.gold, lineWidth: 3)
                }
                .overlay(alignment: .bottom) {
                    Text("Point at the check-in code on the screen")
                        .font(.inter(13)).foregroundStyle(.white.opacity(0.85))
                        .fixedSize()
                        .offset(y: 44)
                }

            VStack(spacing: 0) {
                header(kicker: "CHURCH ATTENDANCE", title: "Check in to the service")
                Spacer()
                if camera.torchAvailable { torchButton }
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

    private var torchButton: some View {
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
        .padding(.bottom, 40)
    }

    // MARK: Registration — what goes on the attendance record

    private var registrationView: some View {
        VStack(spacing: 0) {
            header(kicker: "YOUR DETAILS", title: "Confirm and register")
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.md) {
                    Text("These go on today's attendance record.")
                        .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                        .padding(.bottom, Nuru.S.sm)

                    field("Full name", text: $name, keyboard: .default, content: .name)
                    field("Phone number", text: $phone, keyboard: .phonePad, content: .telephoneNumber)
                    field("Email (optional)", text: $email, keyboard: .emailAddress, content: .emailAddress)

                    if !failureNote.isEmpty {
                        Text(failureNote)
                            .font(.inter(13)).foregroundStyle(Nuru.goldLight)
                            .padding(.top, Nuru.S.sm)
                    }
                }
                .padding(.top, Nuru.S.lg)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: Nuru.S.sm) {
                Button {
                    Haptics.tap()
                    submit()
                } label: {
                    Text(phase == .submitting ? "Checking you in…" : "Check in")
                        .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .background(canSubmit ? Nuru.gold : Nuru.gold.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(!canSubmit)

                Button {
                    failureNote = ""
                    scan = nil
                    phase = .scanning
                    camera.resumeScanning()
                } label: {
                    Text("Scan a different code")
                        .font(.inter(14, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(Color.white.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(phase == .submitting)
            }
            .padding(.bottom, Nuru.S.xl)
        }
        .padding(.horizontal, Nuru.S.screen)
    }

    private var canSubmit: Bool {
        phase == .registering
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func field(_ label: String,
                       text: Binding<String>,
                       keyboard: UIKeyboardType,
                       content: UITextContentType) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.inter(10, .bold)).kerning(1.4).foregroundStyle(Nuru.gold)
            TextField("", text: text)
                .font(.inter(15)).foregroundStyle(.white)
                .keyboardType(keyboard)
                .textContentType(content)
                .autocorrectionDisabled()
                .textInputAutocapitalization(keyboard == .emailAddress ? .never : .words)
                .padding(.horizontal, 14).frame(height: 48)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
    }

    // MARK: Success

    private var successView: some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(Nuru.gold.opacity(0.18)).frame(width: 108, height: 108)
                    Circle().fill(Nuru.gold).frame(width: 80, height: 80)
                    Icon(.check, size: 34, color: Nuru.navy)
                }
                .gentleEntrance()
                .padding(.top, Nuru.S.xl)

                Text(result?.duplicate == true ? "Already checked in ✓" : "You're checked in ✓")
                    .font(.fraunces(24, .medium)).kerning(-0.48).foregroundStyle(.white)
                    .padding(.top, Nuru.S.lg)
                    .gentleEntrance(delay: 0.08)

                Text(result?.serviceTitle ?? "")
                    .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.sm)
                    .gentleEntrance(delay: 0.16)

                if let at = result?.attendedAt {
                    Text(shortTime(at))
                        .font(.inter(12)).foregroundStyle(.white.opacity(0.5))
                        .padding(.top, 2)
                }

                if let streak = result?.streak {
                    StreakSummary(streak: streak)
                        .padding(.top, Nuru.S.xl)
                        .gentleEntrance(delay: 0.24)
                }

                VStack(spacing: Nuru.S.sm) {
                    if onSeeAttendance != nil {
                        Button {
                            Haptics.tap()
                            dismiss()
                            onSeeAttendance?()
                        } label: {
                            Text("See my attendance")
                                .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                    }
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Text("Done")
                            .font(.inter(14, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, Nuru.S.xl)
                .padding(.bottom, Nuru.S.xl)
            }
            .padding(.horizontal, Nuru.S.screen)
        }
    }

    /// Camera denied — a friendly pointer to Settings, never a dead end.
    private var deniedView: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                closeButton
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
            Text("Nuru uses the camera only to scan the service check-in code. Turn it on in Settings and come back.")
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

    // MARK: Chrome

    private func header(kicker: String, title: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(kicker)
                    .font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
                Text(title)
                    .font(.fraunces(20, .semibold)).kerning(-0.4).foregroundStyle(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: Nuru.S.md)
            closeButton
        }
        .padding(.top, Nuru.S.lg)
    }

    private var closeButton: some View {
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

    // MARK: Capture + submit

    private func handleCode(_ raw: String) {
        guard phase == .scanning else { return }
        // Not one of ours — keep scanning rather than posting junk to the server.
        guard let parsed = parseServiceQR(raw) else { return }
        Haptics.tap()                    // the scanner "tick" — code captured
        camera.pauseScanning()
        scan = parsed
        scanId = UUID().uuidString.lowercased()
        phase = .registering
    }

    private func submit() {
        guard let s = scan else { return }
        phase = .submitting
        failureNote = ""
        Task {
            do {
                let r = try await MemberAPI.checkInToService(
                    serviceId: s.serviceId,
                    scanToken: s.scanToken,
                    clientScanId: scanId,          // unchanged on retry → a replay
                    fullName: blankToNil(name),
                    phoneNumber: blankToNil(phone),
                    email: blankToNil(email))
                result = r
                phase = .done
                Haptics.success()
            } catch {
                failureNote = friendlyFailure(error)
                phase = .registering
                Haptics.error()
            }
        }
    }

    private func blankToNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    private func friendlyFailure(_ error: Error) -> String {
        guard let api = error as? APIError else {
            return "Something went wrong — try again."
        }
        if api.isNetwork {
            return "You're offline — check-in needs a connection. Reconnect and try again."
        }
        if case .http(_, let code, let message) = api {
            switch code ?? "" {
            case "VALIDATION_FAILED":
                return "That code isn't valid — it may have expired. Grab the latest one on the screen and scan again."
            case "NOT_FOUND":
                return "We couldn't find that service. Scan the code on the screen again."
            case "FORBIDDEN_SCOPE":
                return "That code belongs to another congregation."
            default:
                return message   // e.g. "Check-in has closed for this service"
            }
        }
        return api.errorDescription ?? "Something went wrong — try again."
    }
}

// MARK: - Streak summary (shared with AttendanceView)

/// Current run · longest · breaks · failures — the four numbers, one row of tiles.
struct StreakSummary: View {
    let streak: AttendanceStreak

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Text("YOUR ATTENDANCE")
                .font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
            HStack(spacing: 8) {
                tile("Streak", streak.currentStreak)
                tile("Longest", streak.longestStreak)
                tile("Breaks", streak.breaks)
                tile("Missed", streak.totalMissed)
            }
            Text(streak.note)
                .font(.inter(13)).foregroundStyle(.white.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tile(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.fraunces(22, .medium)).foregroundStyle(Nuru.gold)
            Text(label)
                .font(.inter(11, .medium)).foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Nuru.S.md)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(Color.white.opacity(0.18), lineWidth: 1))
    }
}

/// "09:14" out of an ISO-8601 instant, without pulling in a date formatter.
func shortTime(_ iso: String) -> String {
    guard let t = iso.split(separator: "T").dropFirst().first, t.count >= 5 else { return iso }
    return String(t.prefix(5))
}

// MARK: - Preview layer host

private struct ServiceScanPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> Host {
        let v = Host()
        v.previewLayer.session = session
        v.previewLayer.videoGravity = .resizeAspectFill
        return v
    }

    func updateUIView(_ uiView: Host, context: Context) {}

    final class Host: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}

// MARK: - Punch-out mask (dim overlay with a see-through scan window)

private extension View {
    /// Masks OUT the given shape — everything except `shape` keeps the modified
    /// view (here: the dim layer), the shape itself stays clear.
    func punchOut<S: View>(@ViewBuilder _ shape: () -> S) -> some View {
        self.mask {
            ZStack {
                Rectangle()
                shape().blendMode(.destinationOut)
            }
            .compositingGroup()
        }
    }
}
