// Sign-in — a faithful native port of screens/LoginScreen.tsx. A solid navy
// (#081C36) screen, thirds layout: the gold cross + "Nuru Place" serif wordmark +
// keyline float in the upper region; the login details sit in the lower region.
// Modes: login · register · forgot · reset · mfa (POST /auth/login, /auth/register,
// /auth/password/{forgot,reset}, /auth/login/mfa). Rotated tokens go to the Keychain.
import SwiftUI

private enum LoginMode { case login, register, forgot, reset, mfa }
private enum LoginField: Hashable { case name, email, password, confirm, token, code, newPassword }

/// Horizontal "no" shake for a failed submit — three quick cycles, driven by an
/// incrementing counter so repeat failures re-shake.
private struct ShakeEffect: GeometryEffect {
    var travel: CGFloat = 7
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: travel * sin(animatableData * .pi * 6), y: 0))
    }
}

struct LoginView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var mode: LoginMode = .login
    @State private var busy = false
    @State private var error: String?
    @State private var notice: String?
    @State private var shakes = 0
    @FocusState private var focus: LoginField?

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
            // Dev convenience only on the simulator (seeded local backend). On a
            // real device the build targets prod, where these creds don't exist —
            // so leave the fields empty there.
            #if targetEnvironment(simulator) && DEBUG
            if email.isEmpty { email = "student1@dev.local" }
            if password.isEmpty { password = "pathway123" }
            // Scripted UI verification (simctl launch with SIMCTL_CHILD_NURU_AUTOLOGIN=1)
            // submits the prefilled dev credentials without a tap.
            if ProcessInfo.processInfo.environment["NURU_AUTOLOGIN"] == "1" {
                Task { await submit() }
            }
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
                // The gold cross (exact Figma mark: upright + arm + faded top cap).
                ZStack {
                    RoundedRectangle(cornerRadius: 2).fill(Nuru.gold).frame(width: 4, height: 26)
                    RoundedRectangle(cornerRadius: 2).fill(Nuru.gold).frame(width: 22, height: 4).offset(y: -2)
                    RoundedRectangle(cornerRadius: 2).fill(Nuru.gold.opacity(0.5)).frame(width: 8, height: 4).offset(y: -13)
                }
            }
            Text("Nuru Place")
                .font(.fraunces(36, .semibold)).kerning(-1.08).foregroundStyle(.white)
                .padding(.top, Nuru.S.base)
            HStack(spacing: Nuru.S.sm) {
                LinearGradient(colors: [.clear, Nuru.gold], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28, height: 1).opacity(0.6)
                Circle().fill(Nuru.gold.opacity(0.7)).frame(width: 4, height: 4)
                LinearGradient(colors: [Nuru.gold, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: 28, height: 1).opacity(0.6)
            }
            .padding(.top, 14)
            Text("A MISSIONARY SENDING CHURCH")
                .font(.inter(10, .medium)).kerning(1.8)
                .foregroundStyle(Color.white.opacity(0.45))
                .padding(.top, 12)
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
            .modifier(ShakeEffect(animatableData: CGFloat(shakes)))
            .animation(.easeOut(duration: 0.2), value: error)
            .animation(.easeOut(duration: 0.2), value: notice)
            // Return chains to the next field; on the last field it submits —
            // same path as the gold button, so validation/haptics all apply.
            .onSubmit {
                switch focus {
                case .name: focus = .email
                case .email where mode != .forgot: focus = .password
                case .password where mode == .register: focus = .confirm
                case .token: focus = .newPassword
                default: Task { await submit() }
                }
            }

            footer.padding(.top, Nuru.S.xl)
        }
    }

    private var secondaryHeader: some View {
        VStack(spacing: 0) {
            Button { go(.login) } label: {
                HStack(spacing: 6) {
                    Icon(.arrowLeft, size: 14, color: .white)
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
            field("FULL NAME", icon: .user, id: .name) {
                plainField("Your name", text: $fullName, id: .name, autocap: .words)
            }
        }
        switch mode {
        case .reset:
            field("RESET TOKEN", icon: .lock, id: .token) {
                plainField("Paste the token from your email", text: $token, id: .token)
            }
        case .mfa:
            field("VERIFICATION CODE", icon: .lock, id: .code) {
                plainField("123456", text: $mfaCode, id: .code, keyboard: .numberPad)
            }
        default:
            field("EMAIL ADDRESS", icon: .mail, id: .email) {
                plainField("name@email.com", text: $email, id: .email, keyboard: .emailAddress)
            }
        }

        if mode == .login || mode == .register {
            field("PASSWORD", icon: .lock, id: .password, trailing: eyeToggle) {
                secureField(mode == .register ? "At least 8 characters" : "••••••••", text: $password, id: .password)
            }
        }
        if mode == .register {
            field("CONFIRM PASSWORD", icon: .lock, id: .confirm) {
                secureField("Re-enter password", text: $confirm, id: .confirm)
            }
        }
        if mode == .reset {
            field("NEW PASSWORD", icon: .lock, id: .newPassword, trailing: eyeToggle) {
                secureField("At least 8 characters", text: $newPassword, id: .newPassword)
            }
        }
    }

    private var rememberRow: some View {
        HStack {
            Button {
                Haptics.selection()
                withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { remember.toggle() }
            } label: {
                HStack(spacing: Nuru.S.sm) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(remember ? Nuru.gold : Color.white.opacity(0.30), lineWidth: 1.5)
                            .background(remember ? Nuru.gold : .clear, in: RoundedRectangle(cornerRadius: 6))
                            .frame(width: 20, height: 20)
                        if remember {
                            Icon(.check, size: 11, color: Nuru.navy)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    Text("Remember me").font(.nCaption).foregroundStyle(Nuru.onNavyDim)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.pressableSubtle)
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
            Button {
                Haptics.tap()
                showPw.toggle()
            } label: {
                Icon(showPw ? .eyeOff : .eye, size: 17, color: Color.white.opacity(0.40))
                    // Bigger invisible hit area — the visible glyph stays 17pt.
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        )
    }

    // MARK: Field building blocks

    private func field<Content: View>(_ label: String, icon: Lucide, id: LoginField, trailing: AnyView? = nil,
                                      @ViewBuilder content: () -> Content) -> some View {
        let focused = focus == id
        return VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.inter(11, .semibold)).kerning(1.6).foregroundStyle(Nuru.onNavyDim)
            HStack(spacing: Nuru.S.sm) {
                Icon(icon, size: 17, color: focused ? Nuru.gold.opacity(0.85) : Color.white.opacity(0.40))
                content().frame(maxWidth: .infinity)
                if let trailing { trailing }
            }
            .padding(.horizontal, Nuru.S.base)
            .background(Color.white.opacity(focused ? 0.09 : 0.06), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(focused ? Nuru.gold.opacity(0.55) : Color.white.opacity(0.14), lineWidth: 1))
            .animation(.easeOut(duration: 0.16), value: focused)
        }
    }

    private func plainField(_ placeholder: String, text: Binding<String>, id: LoginField,
                            keyboard: UIKeyboardType = .default,
                            autocap: TextInputAutocapitalization = .never) -> some View {
        TextField("", text: text, prompt: Text(placeholder).foregroundColor(Color.white.opacity(0.40)))
            .keyboardType(keyboard)
            .textInputAutocapitalization(autocap)
            .autocorrectionDisabled()
            .font(.inter(16))
            .foregroundStyle(.white)
            .padding(.vertical, 14)
            .focused($focus, equals: id)
    }

    private func secureField(_ placeholder: String, text: Binding<String>, id: LoginField) -> some View {
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
        .focused($focus, equals: id)
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
        error = nil; notice = nil
        withAnimation(.easeInOut(duration: 0.22)) { mode = next }
    }

    private func enter(_ session: Session) async {
        Haptics.success()
        await auth.onAuthenticated(session)
    }

    /// Failed-submit feedback: error haptic + a quick horizontal shake of the form.
    private func feedbackOnError() {
        Haptics.error()
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 0.4)) { shakes += 1 }
    }

    private func submit() async {
        error = nil; busy = true
        // Runs on EVERY exit path (early validation returns included): any
        // non-nil error at this point is a fresh failure from this attempt.
        defer {
            busy = false
            if error != nil { feedbackOnError() }
        }
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
                    mfaToken = c.mfaToken; mfaCode = ""
                    withAnimation(.easeInOut(duration: 0.22)) { mode = .mfa }
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
                    token = devToken; notice = "Reset link generated (dev). Set your new password below."
                    withAnimation(.easeInOut(duration: 0.22)) { mode = .reset }
                } else {
                    notice = "If an account exists for that email, a reset link is on its way."
                }
            case .reset:
                guard !token.trimmed.isEmpty else { error = "Paste the reset token from your email."; return }
                guard newPassword.count >= 8 else { error = "Password must be at least 8 characters."; return }
                try await MemberAPI.resetPassword(token: token.trimmed, newPassword: newPassword)
                Haptics.success()
                password = ""; notice = "Password reset. Sign in with your new password."
                withAnimation(.easeInOut(duration: 0.22)) { mode = .login }
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
