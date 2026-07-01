// Two-factor (TOTP) enrollment sheet — presented from Profile → Security when
// the member flips "Two-factor authentication" on. It runs the REAL backend
// enroll → verify flow (POST /auth/mfa/enroll then confirm the 6-digit code):
//   1. .task calls MemberAPI.enrollMfa() → an MfaEnrollment { otpauthUri, secret }.
//   2. The member adds the secret to an authenticator app, then types the code.
//   3. MemberAPI.verifyMfa(code:) confirms it server-side; on success we call
//      onEnabled() (so Security can persist the toggle) and dismiss.
// Server-authoritative: the client never decides 2FA is "on" — the verify call does.
import SwiftUI
import UIKit

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
    /// Called after a successful verify, before dismiss — lets Security persist
    /// the "2FA on" state.
    let onEnabled: () -> Void

    @StateObject private var vm = MfaEnrollViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                content
            }
            .navigationTitle("Two-factor authentication")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(.inter(16, .regular))
                        .foregroundStyle(Nuru.muted)
                }
            }
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
                    .font(.nCaption).foregroundStyle(Nuru.muted)
            }
        case .failed:
            failedState
        case .ready:
            enrolledState
        }
    }

    private var failedState: some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.shieldCheck, size: 28, color: Nuru.faint)
            Text(vm.enrollError ?? "Couldn't start two-factor setup.")
                .font(.nBody).foregroundStyle(Nuru.muted)
                .multilineTextAlignment(.center)
            PButton(title: "Try again", variant: .navy) { Task { await vm.enroll() } }
                .frame(maxWidth: 220)
        }
        .padding(Nuru.S.screen)
    }

    // MARK: enrolled — secret + code entry

    private var enrolledState: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                heroCard
                secretCard
                codeCard
                reassurance
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.S.xl)
        }
    }

    private var heroCard: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            Icon(.shieldCheck, size: 22, color: Nuru.onNavy)
                .frame(width: 40, height: 40)
                .background(Color.white.opacity(0.14), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("Add an extra layer")
                    .font(.fraunces(20, .semibold))
                    .foregroundStyle(Nuru.white)
                Text("Add this key to an authenticator app (Google Authenticator, Authy, 1Password), then enter the 6-digit code it shows.")
                    .font(.nCaption)
                    .foregroundStyle(Nuru.onNavyDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.heroGradient, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    private var secretCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                HStack(spacing: Nuru.S.sm) {
                    Icon(.key, size: 16, color: Nuru.gold)
                    Text("Setup key")
                        .font(.nOverline)
                        .foregroundStyle(Nuru.muted)
                        .textCase(.uppercase)
                }

                HStack(alignment: .center, spacing: Nuru.S.md) {
                    Text(vm.groupedSecret)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Nuru.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .padding(Nuru.S.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                        .stroke(Nuru.border, lineWidth: 1)
                )

                Button(action: vm.copySecret) {
                    HStack(spacing: Nuru.S.sm) {
                        Icon(.copy, size: 15, color: Nuru.navyDeep)
                        Text("Copy key")
                            .font(.inter(14, .semibold))
                            .foregroundStyle(Nuru.navyDeep)
                    }
                    .frame(maxWidth: .infinity, minHeight: Nuru.buttonHeightMd)
                    .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var codeCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("Enter the 6-digit code")
                    .font(.nHeading)
                    .foregroundStyle(Nuru.ink)

                TextField("000000", text: Binding(
                    get: { vm.code },
                    set: { vm.sanitize($0) }
                ))
                .keyboardType(.numberPad)
                .textContentType(.oneTimeCode)
                .font(.system(size: 24, weight: .semibold, design: .monospaced))
                .foregroundStyle(Nuru.ink)
                .kerning(4)
                .padding(.horizontal, Nuru.S.base)
                .frame(height: Nuru.buttonHeightMd)
                .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                        .stroke(vm.verifyError == nil ? Nuru.border : Nuru.danger, lineWidth: 1)
                )

                if let err = vm.verifyError {
                    Text(err)
                        .font(.nCaption)
                        .foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                PButton(title: "Verify & enable",
                        variant: .gold,
                        busy: vm.verifying,
                        disabled: !vm.canVerify) {
                    Task {
                        if await vm.verify() {
                            onEnabled()
                            dismiss()
                        }
                    }
                }
            }
        }
    }

    private var reassurance: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(.check, size: 14, color: Nuru.success)
            Text("You'll enter a code from your authenticator each time you sign in on a new device.")
                .font(.nCaption)
                .foregroundStyle(Nuru.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Nuru.S.xs)
    }
}
