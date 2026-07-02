// Two-factor (TOTP) enrollment sheet — presented from Profile → Security when
// the member flips "Two-factor authentication" on. Styled after the Figma
// TwoFASheet (bottom sheet, scan → verify steps) but runs the REAL backend
// enroll → verify flow (POST /auth/mfa/enroll then confirm the 6-digit code):
//   1. .task calls MemberAPI.enrollMfa() → an MfaEnrollment { otpauthUri, secret }.
//   2. Scan step: a real QR is rendered from otpauthUri (CoreImage), with the
//      setup key below it for manual entry, then "I've scanned it".
//   3. Verify step: MemberAPI.verifyMfa(code:) confirms it server-side; on
//      success we call onEnabled() (so Profile refreshes /me) and dismiss.
// Server-authoritative: the client never decides 2FA is "on" — the verify call does.
import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// MARK: - View model

@MainActor
final class MfaEnrollViewModel: ObservableObject {
    enum Phase { case loading, ready, failed }

    @Published var phase: Phase = .loading
    @Published var enrollment: MfaEnrollment?
    @Published var enrollError: String?     // failure loading the secret

    @Published var code: String = ""
    @Published var verifying = false
    @Published var verifyError: String?     // wrong / rejected code

    /// True once the code is long enough to attempt a verify (6 digits).
    var canVerify: Bool { code.count >= 6 && !verifying }

    /// The shared secret, chunked into groups of 4 for readability.
    var groupedSecret: String {
        guard let s = enrollment?.secret, !s.isEmpty else { return "" }
        var out = ""
        for (i, ch) in s.enumerated() {
            if i > 0 && i % 4 == 0 { out.append(" ") }
            out.append(ch)
        }
        return out
    }

    /// The REAL provisioning QR — generated locally from the server's otpauth URI
    /// so Google Authenticator / Authy / 1Password can scan straight into setup.
    var qrImage: UIImage? {
        guard let uri = enrollment?.otpauthUri, !uri.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(uri.utf8)
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }

    func enroll() async {
        phase = .loading; enrollError = nil
        do {
            let e = try await MemberAPI.enrollMfa()
            enrollment = e
            phase = .ready
        } catch {
            enrollError = (error as? APIError)?.errorDescription ?? "Couldn't start two-factor setup."
            phase = .failed
        }
    }

    /// Keeps only digits and caps the length (some authenticators emit up to
    /// 8-digit codes; 10 is a safe ceiling).
    func sanitize(_ raw: String) {
        let digits = raw.filter(\.isNumber)
        code = String(digits.prefix(10))
    }

    func copySecret() {
        UIPasteboard.general.string = enrollment?.secret
    }

    /// Confirms the code with the server. Returns true on success so the view can
    /// call onEnabled() and dismiss.
    func verify() async -> Bool {
        guard canVerify else { return false }
        verifying = true; verifyError = nil
        defer { verifying = false }
        do {
            try await MemberAPI.verifyMfa(code: code)
            return true
        } catch {
            verifyError = "That code didn't match — check your app and try again."
            code = ""
            return false
        }
    }
}

// MARK: - Sheet

struct MfaEnrollSheet: View {
    /// Called after a successful verify, before dismiss — lets Profile refresh /me.
    let onEnabled: () -> Void

    @StateObject private var vm = MfaEnrollViewModel()
    @State private var step: Step = .scan
    @State private var copied = false
    @Environment(\.dismiss) private var dismiss

    private enum Step { case scan, verify }

    var body: some View {
        PSheetShell(title: "Enable 2-factor authentication") {
            content
        }
        .task { if vm.enrollment == nil { await vm.enroll() } }
    }

    // MARK: body states

    @ViewBuilder
    private var content: some View {
        switch vm.phase {
        case .loading:
            VStack(spacing: Nuru.S.md) {
                ProgressView().tint(Nuru.gold)
                Text("Setting up two-factor…")
                    .font(.inter(12)).foregroundStyle(Nuru.muted)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xxl)
        case .failed:
            failedState
        case .ready:
            switch step {
            case .scan: scanStep
            case .verify: verifyStep
            }
        }
    }

    private var failedState: some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.shieldCheck, size: 28, color: Nuru.faint)
            Text(vm.enrollError ?? "Couldn't start two-factor setup.")
                .font(.inter(13)).foregroundStyle(Nuru.muted)
                .multilineTextAlignment(.center)
            GoldSheetButton(title: "Try again") { Task { await vm.enroll() } }
                .frame(maxWidth: 220)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Nuru.S.xl)
    }

    // MARK: scan step — real QR + setup key

    private var scanStep: some View {
        VStack(spacing: Nuru.S.md) {
            Text("Scan this QR code with Google Authenticator, Authy or 1Password.")
                .font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
                .multilineTextAlignment(.center)

            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    .frame(width: 176, height: 176)
                if let qr = vm.qrImage {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: 140, height: 140)
                } else {
                    Icon(.qrCode, size: 140, color: Nuru.navy)
                }
            }

            // Setup key for manual entry — tap to copy.
            Button {
                vm.copySecret()
                copied = true
                Task { try? await Task.sleep(nanoseconds: 1_600_000_000); copied = false }
            } label: {
                HStack(spacing: 6) {
                    Text(vm.groupedSecret)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .kerning(1.5).foregroundStyle(Nuru.navy)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Icon(copied ? .check : .copy, size: 12, color: copied ? Nuru.success : Nuru.faint)
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            GoldSheetButton(title: "I've scanned it") { step = .verify }
                .padding(.top, Nuru.S.xs)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: verify step — confirm the 6-digit code server-side

    private var verifyStep: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Text("Enter the 6-digit code from your authenticator app.")
                .font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))

            TextField("123456", text: Binding(
                get: { vm.code },
                set: { vm.sanitize($0) }
            ))
            .keyboardType(.numberPad)
            .textContentType(.oneTimeCode)
            .font(.system(size: 20, weight: .semibold, design: .monospaced))
            .foregroundStyle(Nuru.navy)
            .kerning(8)
            .multilineTextAlignment(.center)
            .frame(height: 52)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(vm.verifyError == nil ? Nuru.border : Nuru.danger, lineWidth: 1)
            )

            if let err = vm.verifyError {
                Text(err)
                    .font(.inter(12)).foregroundStyle(Nuru.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            GoldSheetButton(title: "Enable 2FA", busy: vm.verifying, disabled: !vm.canVerify) {
                Task {
                    if await vm.verify() {
                        onEnabled()
                        dismiss()
                    }
                }
            }

            HStack(alignment: .top, spacing: Nuru.S.sm) {
                Icon(.check, size: 14, color: Nuru.success)
                Text("You'll enter a code from your authenticator each time you sign in on a new device.")
                    .font(.inter(12)).foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
