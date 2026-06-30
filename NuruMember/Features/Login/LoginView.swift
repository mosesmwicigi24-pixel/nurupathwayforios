// Sign-in — a faithful native port of screens/LoginScreen.tsx. A solid navy
// (#081C36) screen, thirds layout: the gold cross + "Nuru Place" serif wordmark +
// keyline float in the upper region; the login details sit in the lower region.
// Modes: login · register · forgot · reset · mfa (POST /auth/login, /auth/register,
// /auth/password/{forgot,reset}, /auth/login/mfa). Rotated tokens go to the Keychain.
import SwiftUI

private enum LoginMode { case login, register, forgot, reset, mfa }

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore

    @State private var mode: LoginMode = .login
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?

    @State private var fullName = ""
    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var token = ""
    @State private var newPassword = ""
    @State private var mfaToken = ""
    @State private var mfaCode = ""
    @State private var showPw = false
    @State private var remember = true

    private let rememberKey = "auth.rememberEmail"
    private let connectError = "Can't reach the server. Check your connection and try again."

    var body: some View {
        GeometryReader { geo in
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    brand
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: geo.size.height * 0.42)
                    lower
                        .padding(.bottom, 44)
                }
                .frame(minHeight: geo.size.height)
                .padding(.horizontal, Nuru.S.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Nuru.navyCeremony.ignoresSafeArea())
        .tint(Nuru.gold)
        .onAppear {
            if let saved = UserDefaults.standard.string(forKey: rememberKey), !saved.isEmpty {
                email = saved; remember = true
            }
            #if DEBUG
            if email.isEmpty { email = "student1@dev.local" }
            if password.isEmpty { password = "pathway123" }
            #endif
        }
    }

    // MARK: Upper — brand

    private var brand: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Nuru.gold.opacity(0.10))
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
                    .frame(width: 72, height: 72)
                // The gold cross.
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Nuru.gold).frame(width: 4, height: 26)
                    RoundedRectangle(cornerRadius: 2).fill(Nuru.gold).frame(width: 22, height: 4)
                }
            }
            Text("Nuru Place")
                .font(.fraunces(34, .bold)).foregroundStyle(.white)
                .padding(.top, Nuru.S.base)
            HStack(spacing: Nuru.S.sm) {
                Rectangle().fill(Nuru.gold.opacity(0.6)).frame(width: 28, height: 1)
                Circle().fill(Nuru.gold).frame(width: 4, height: 4)
                Rectangle().fill(Nuru.gold.opacity(0.6)).frame(width: 28, height: 1)
            }
            .padding(.top, Nuru.S.sm)
            Text("A MISSIONARY SENDING CHURCH")
                .font(.inter(11, .semibold)).kerning(2.2)
                .foregroundStyle(Nuru.onNavyDim)
                .padding(.top, Nuru.S.md)
        }
    }

    // MARK: Lower — form

    private var lower: some View {
        VStack(spacing: 0) {
            if mode != .login { secondaryHeader }

            VStack(spacing: Nuru.S.base) {
                fields
                if mode == .login { rememberRow }
                if let error { Text(error).font(.nCaption).foregroundStyle(Nuru.error).frame(maxWidth: .infinity).multilineTextAlignment(.center) }
                if let notice, error == nil { Text(notice).font(.nCaption).foregroundStyle(Nuru.gold).frame(maxWidth: .infinity).multilineTextAlignment(.center) }
                PButton(title: primaryTitle, variant: .gold, busy: busy) { Task { await submit() } }
            }
            .padding(.top, Nuru.S.xl)

            footer.padding(.top, Nuru.S.xl)
        }
    }

    private var secondaryHeader: some View {
        VStack(spacing: 0) {
            Button { go(.login) } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left").font(.system(size: 14, weight: .semibold))
                    Text("Back").font(.nCaption)
                }.foregroundStyle(.white)
            }
            .padding(.bottom, Nuru.S.md)
            Text(heading).font(.fraunces(26, .bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text(subhead).font(.nCaption).foregroundStyle(Nuru.onNavyDim)
                .multilineTextAlignment(.center).padding(.top, 6)
        }
        .padding(.top, Nuru.S.xl)
    }

    @ViewBuilder
    private var fields: some View {
        if mode == .register {
            field("FULL NAME", icon: "person") {
                plainField("Your name", text: $fullName, autocap: .words)
            }
        }
        switch mode {
        case .reset:
            field("RESET TOKEN", icon: "lock") {
                plainField("Paste the token from your email", text: $token)
            }
        case .mfa:
            field("VERIFICATION CODE", icon: "lock") {
                plainField("123456", text: $mfaCode, keyboard: .numberPad)
            }
        default:
            field("EMAIL ADDRESS", icon: "envelope") {
                plainField("name@email.com", text: $email, keyboard: .emailAddress)
            }
        }

        if mode == .login || mode == .register {
            field("PASSWORD", icon: "lock", trailing: eyeToggle) {
                secureField(mode == .register ? "At least 8 characters" : "••••••••", text: $password)
            }
        }
        if mode == .register {
            field("CONFIRM PASSWORD", icon: "lock") {
                secureField("Re-enter password", text: $confirm)
            }
        }
        if mode == .reset {
            field("NEW PASSWORD", icon: "lock", trailing: eyeToggle) {
                secureField("At least 8 characters", text: $newPassword)
            }
        }
    }

    private var rememberRow: some View {
        HStack {
            Button { remember.toggle() } label: {
                HStack(spacing: Nuru.S.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(remember ? Nuru.gold : Color.white.opacity(0.30), lineWidth: 1.5)
                            .background(remember ? Nuru.gold : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .frame(width: 20, height: 20)
                        if remember {
                            Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Nuru.navy)
                        }
                    }
                    Text("Remember me").font(.nCaption).foregroundStyle(Nuru.onNavyDim)
                }
            }
            Spacer()
            Button { go(.forgot) } label: {
                Text("Forgot your password?").font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 4) {
            if mode == .login {
                Text("Don't have an account?").font(.nCaption).foregroundStyle(Nuru.onNavyDim)
                Button { go(.register) } label: { Text("Sign up").font(.inter(12, .bold)).foregroundStyle(Nuru.gold) }
            } else {
                Text("Remembered it?").font(.nCaption).foregroundStyle(Nuru.onNavyDim)
                Button { go(.login) } label: { Text("Log in").font(.inter(12, .bold)).foregroundStyle(Nuru.gold) }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var eyeToggle: AnyView {
        AnyView(
            Button { showPw.toggle() } label: {
                Image(systemName: showPw ? "eye.slash" : "eye")
                    .font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.40))
            }
        )
    }

    // MARK: Field building blocks

    private func field<Content: View>(_ label: String, icon: String, trailing: AnyView? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Nuru.onNavyDim)
            HStack(spacing: Nuru.S.sm) {
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Color.white.opacity(0.40))
                content().frame(maxWidth: .infinity)
                if let trailing { trailing }
            }
            .padding(.horizontal, Nuru.S.base)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1))
        }
    }

    private func plainField(_ placeholder: String, text: Binding<String>,
                            keyboard: UIKeyboardType = .default,
                            autocap: TextInputAutocapitalization = .never) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.40)))
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocap)
            .autocorrectionDisabled()
            .font(.inter(16))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
    }

    private func secureField(_ placeholder: String, text: Binding<String>) -> some View {
        Group {
            if showPw {
                TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.40)))
            } else {
                SecureField("", text: text, prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.40)))
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .font(.inter(16))
        .foregroundStyle(.white)
        .padding(.vertical, 14)
    }

    // MARK: Copy

    private var heading: String {
        switch mode {
        case .register: return "Create account"
        case .forgot: return "Reset password"
        case .reset: return "Set a new password"
        case .mfa: return "Two-factor code"
        case .login: return ""
        }
    }

    private var subhead: String {
        switch mode {
        case .register: return "Begin your discipleship journey on Pathway."
        case .forgot: return "Enter your account email and we'll send you a reset link."
        case .reset: return "Choose a new password for your account."
        case .mfa: return "Enter the 6-digit code from your authenticator app, or a recovery code."
        case .login: return ""
        }
    }

    private var primaryTitle: String {
        switch mode {
        case .login: return busy ? "Signing in…" : "Log in"
        case .register: return busy ? "Creating…" : "Create account"
        case .forgot: return busy ? "Sending…" : "Send reset link"
        case .reset: return busy ? "Saving…" : "Reset password"
        case .mfa: return busy ? "Verifying…" : "Verify & sign in"
        }
    }

    // MARK: Actions

    private func go(_ next: LoginMode) {
        error = nil; notice = nil; mode = next
    }

    private func enter(_ session: Session) async {
        await auth.onAuthenticated(session)
    }

    private func submit() async {
        error = nil; busy = true; defer { busy = false }
        do {
            switch mode {
            case .login:
                guard !email.trimmed.isEmpty, !password.isEmpty else { error = "Enter your email and password."; return }
                switch try await MemberAPI.login(email: email.trimmed, password: password) {
                case .session(let s):
                    if remember { UserDefaults.standard.set(email.trimmed, forKey: rememberKey) }
                    else { UserDefaults.standard.removeObject(forKey: rememberKey) }
                    await enter(s)
                case .mfaChallenge(let c):
                    mfaToken = c.mfaToken; mfaCode = ""; mode = .mfa
                }
            case .mfa:
                guard !mfaCode.trimmed.isEmpty else { error = "Enter your 6-digit code."; return }
                await enter(try await MemberAPI.completeMfa(mfaToken: mfaToken, code: mfaCode.trimmed))
            case .register:
                guard !fullName.trimmed.isEmpty else { error = "Enter your full name."; return }
                guard !email.trimmed.isEmpty else { error = "Enter your email."; return }
                guard password.count >= 8 else { error = "Password must be at least 8 characters."; return }
                guard password == confirm else { error = "Passwords don't match."; return }
                await enter(try await MemberAPI.register(fullName: fullName.trimmed, email: email.trimmed, password: password))
            case .forgot:
                guard !email.trimmed.isEmpty else { error = "Enter your account email."; return }
                if let devToken = try await MemberAPI.forgotPassword(email.trimmed) {
                    token = devToken; notice = "Reset link generated (dev). Set your new password below."; mode = .reset
                } else {
                    notice = "If an account exists for that email, a reset link is on its way."
                }
            case .reset:
                guard !token.trimmed.isEmpty else { error = "Paste the reset token from your email."; return }
                guard newPassword.count >= 8 else { error = "Password must be at least 8 characters."; return }
                try await MemberAPI.resetPassword(token: token.trimmed, newPassword: newPassword)
                password = ""; notice = "Password reset. Sign in with your new password."; mode = .login
            }
        } catch let e as APIError {
            error = errorMessage(for: e)
        } catch {
            self.error = "Something went wrong. Please try again."
        }
    }

    private func errorMessage(for e: APIError) -> String {
        if e.isNetwork { return connectError }
        switch mode {
        case .login: return "Invalid email or password."
        case .mfa: return "That code didn't match. Try again or use a recovery code."
        case .register:
            if case .http(let status, _, _) = e, status == 409 { return "An account with this email already exists." }
            return "Couldn't create your account. Try again."
        case .forgot: return "Couldn't request a reset. Try again."
        case .reset: return "That reset link is invalid or has expired."
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
