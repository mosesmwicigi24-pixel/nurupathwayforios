// Sign-in — the native port of screens/LoginScreen.tsx. A navy ceremony screen
// with the "Nuru Place" wordmark and gold keyline. Email + password is the
// working path (POST /auth/login); a 2FA challenge collects the code next.
import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var email = ""
    @State private var password = ""
    @State private var mfaToken: String?
    @State private var mfaCode = ""
    @State private var busy = false
    @State private var error: String?

    private var isMfa: Bool { mfaToken != nil }

    var body: some View {
        ZStack {
            Nuru.ceremonyGradient.ignoresSafeArea()

            VStack(spacing: Nuru.S.lg) {
                Spacer()

                // Wordmark
                VStack(spacing: Nuru.S.base) {
                    BrandMark(size: 64)
                    Text("Nuru Place")
                        .font(.fraunces(34, .semibold))
                        .foregroundStyle(.white)
                    Rectangle().fill(Nuru.gold).frame(width: 48, height: 2)
                    Text("Discipleship Pathway")
                        .font(.nLabel)
                        .foregroundStyle(Nuru.onNavyDim)
                }

                Spacer()

                // Form
                VStack(spacing: Nuru.S.md) {
                    if isMfa {
                        Text("Two-factor code")
                            .font(.nHeading).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        darkField("6-digit code", text: $mfaCode, secure: false, keyboard: .numberPad)
                    } else {
                        darkField("Email", text: $email, secure: false, keyboard: .emailAddress)
                        darkField("Password", text: $password, secure: true)
                    }

                    if let error {
                        Text(error)
                            .font(.nCaption)
                            .foregroundStyle(Nuru.goldGlow)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    PButton(title: isMfa ? "Verify" : "Sign in", variant: .gold, busy: busy) {
                        Task { await submit() }
                    }

                    if isMfa {
                        Button("Back") { mfaToken = nil; mfaCode = ""; error = nil }
                            .font(.nCaption).foregroundStyle(Nuru.onNavyDim)
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.bottom, Nuru.S.xxl)
            }
        }
    }

    @ViewBuilder
    private func darkField(_ placeholder: String, text: Binding<String>, secure: Bool, keyboard: UIKeyboardType = .default) -> some View {
        Group {
            if secure {
                SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Nuru.onNavyFaint))
            } else {
                TextField("", text: text, prompt: Text(placeholder).foregroundColor(Nuru.onNavyFaint))
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .font(.nBody)
        .foregroundStyle(.white)
        .padding(.horizontal, Nuru.S.base)
        .frame(height: Nuru.buttonHeightMd)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(.white.opacity(0.15), lineWidth: 1)
        )
    }

    private func submit() async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            if let token = mfaToken {
                let session = try await MemberAPI.completeMfa(mfaToken: token, code: mfaCode.trimmingCharacters(in: .whitespaces))
                await auth.onAuthenticated(session)
                return
            }
            guard !email.trimmingCharacters(in: .whitespaces).isEmpty, !password.isEmpty else {
                error = "Enter your email and password."
                return
            }
            switch try await MemberAPI.login(email: email.trimmingCharacters(in: .whitespaces), password: password) {
            case .session(let session):
                await auth.onAuthenticated(session)
            case .mfaChallenge(let challenge):
                mfaToken = challenge.mfaToken
            }
        } catch let e as APIError {
            error = e.isNetwork ? "Can't reach the server. Check your connection." : "Invalid email or password."
        } catch {
            self.error = "Something went wrong. Please try again."
        }
    }
}
