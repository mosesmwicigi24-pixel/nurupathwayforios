// Settings — how the APP BEHAVES + account plumbing, split out of ProfileView
// (which keeps the member's identity + spiritual journey). Pushed from the
// Profile header's gear button. Sections: Security & Login (real password
// change + TOTP 2FA), Notifications (server-backed GET/PUT /me/notification-
// preferences with optimistic toggles), Display (global text size), Language
// (PATCH /me locale), Privacy (location consent → /me/location), Help &
// Privacy (FAQs + policy), then Sign out / Delete account and the app version.
// Reuses the shared sectionCard / icon-tile building blocks from ProfileView.
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    // Notification channel prefs — SERVER-BACKED (GET/PUT /me/notification-
    // preferences) with @AppStorage as the offline cache/fallback so the UI
    // never blocks. Toggles are optimistic and roll back on a failed PUT; push
    // additionally requests the real system permission.
    @AppStorage("nuru.notif.push") private var pushOn = true
    @AppStorage("nuru.notif.email") private var emailOn = true
    @AppStorage("nuru.notif.sms") private var smsOn = false
    /// Approximate-location sharing consent (persisted); wired to /me/location.
    @AppStorage("nuru.privacy.shareLocation") private var shareLocation = false
    /// Global text scale (persisted); the font helpers read Nuru.textScale from here.
    @AppStorage(Nuru.textScaleKey) private var textScale: Double = 1.0

    @StateObject private var location = LocationManager()
    @State private var showMfaEnroll = false
    @State private var showMfaDisable = false
    @State private var mfaDisableCode = ""
    @State private var mfaError: String?

    // Sheets
    @State private var showSignOutConfirm = false
    @State private var showPasswordSheet = false
    @State private var helpSheet: SHelpSheet?

    /// Real 2FA state from the server profile — the toggle reflects the truth.
    private var twoFactorOn: Bool { auth.profile?.mfaEnabled ?? false }

    private var p: UserProfile? { auth.profile }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        security
                        notifications
                        display
                        language
                        privacy
                        helpPrivacy
                        actions
                        Text("Nuru Pathway · v1.0").font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                            .padding(.top, Nuru.S.xs)
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await loadServerPrefs() }
        .sheet(isPresented: $showMfaEnroll) {
            MfaEnrollSheet(onEnabled: { Task { await auth.loadProfile() } })
        }
        .sheet(isPresented: $showPasswordSheet) { PasswordChangeSheet() }
        .sheet(item: $helpSheet) { which in
            switch which {
            case .language:
                AppLanguageSheet(current: p?.locale ?? "en", rowVersion: p?.rowVersion ?? 1) {
                    Task { await auth.loadProfile() }
                }
            case .support: HelpSupportSheet()
            case .privacyPolicy: PrivacyPolicySheet()
            }
        }
        .alert("Turn off two-factor?", isPresented: $showMfaDisable) {
            TextField("6-digit code", text: $mfaDisableCode).keyboardType(.numberPad)
            Button("Turn off", role: .destructive) {
                Task {
                    do { try await MemberAPI.disableMfa(code: mfaDisableCode); Haptics.success(); await auth.loadProfile() }
                    catch { Haptics.error(); mfaError = (error as? APIError)?.errorDescription ?? "Couldn't turn off two-factor." }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a current code from your authenticator app to confirm.")
        }
        .alert("Two-factor authentication", isPresented: Binding(get: { mfaError != nil }, set: { if !$0 { mfaError = nil } })) {
            Button("OK") { mfaError = nil }
        } message: { Text(mfaError ?? "") }
        .onChange(of: shareLocation) { _, on in Task { await applyLocationSharing(on) } }
    }

    // MARK: Header (standard pushed-screen idiom: back tile, kicker, Fraunces title)

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back")

            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("PREFERENCES")
                    .font(.nCardKicker).kerning(1.4)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Text("Settings")
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.navy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.25)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Data — server channel prefs

    /// Server is the source of truth for channel prefs; the @AppStorage values
    /// stand in until (and unless) it answers. Direct assignment — the custom
    /// toggle bindings (and their PUT) only run on user interaction.
    private func loadServerPrefs() async {
        if let prefs = try? await MemberAPI.notificationPreferences() {
            pushOn = prefs.pushEnabled
            emailOn = prefs.emailEnabled
            smsOn = prefs.smsEnabled
        }
    }

    // MARK: Settings side-effects

    /// Ask iOS for notification permission when the member turns push on.
    private func requestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Optimistic toggle: flip the local (@AppStorage-cached) value immediately,
    /// PUT all three channels, and roll back + error-haptic if the save fails.
    private func prefBinding(_ value: Binding<Bool>, isPush: Bool = false) -> Binding<Bool> {
        Binding(get: { value.wrappedValue }, set: { on in
            let old = value.wrappedValue
            value.wrappedValue = on
            if isPush, on { requestPushPermission() }
            Task {
                do {
                    try await MemberAPI.updateNotificationPreferences(push: pushOn, email: emailOn, sms: smsOn)
                } catch {
                    Haptics.error()
                    value.wrappedValue = old
                }
            }
        })
    }

    /// Share or stop sharing an approximate location fix (§proximity). If permission
    /// is denied or a fix can't be obtained, revert the toggle so it never lies.
    private func applyLocationSharing(_ on: Bool) async {
        if on {
            if let c = await location.requestCoarseFix() {
                try? await MemberAPI.shareLocation(lat: c.latitude, lng: c.longitude)
            } else {
                shareLocation = false
            }
        } else {
            try? await MemberAPI.stopSharingLocation()
        }
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Security

    private var security: some View {
        sectionCard("SECURITY & LOGIN", icon: .lock) {
            Button { Haptics.tap(); showPasswordSheet = true } label: {
                actionRow(.key, tint: Color(hex: 0xEEF2FF), color: Color(hex: 0x6366F1),
                          "Change password", "Keep your account secure")
            }.buttonStyle(.pressableSubtle)
            Divider()
            HStack(spacing: Nuru.S.md) {
                iconTile(.fingerprint,
                         tint: twoFactorOn ? Color(hex: 0x16A34A).opacity(0.13) : Color(hex: 0xFEF3C7),
                         color: twoFactorOn ? Color(hex: 0x16A34A) : Color(hex: 0xD97706))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Two-factor authentication").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    Text(twoFactorOn ? "Active · Authenticator app" : "Not enabled · recommended")
                        .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { twoFactorOn }, set: { want in
                    Haptics.selection()
                    if want, !twoFactorOn { showMfaEnroll = true }
                    else if !want, twoFactorOn { mfaDisableCode = ""; showMfaDisable = true }
                })).labelsHidden().tint(Nuru.gold)
            }
            .padding(.vertical, 10)
            Divider()
            actionRow(.smartphone, tint: Color(hex: 0xFCE7F3), color: Color(hex: 0xDB2777),
                      "Active sessions", "This device")
        }
    }

    // MARK: Notifications

    private var notifications: some View {
        sectionCard("NOTIFICATIONS", icon: .bell) {
            toggleRow(.bell, "Push notifications", "Devotionals, events, reminders", prefBinding($pushOn, isPush: true)); Divider()
            toggleRow(.mail, "Email", "Weekly summary & receipts", prefBinding($emailOn)); Divider()
            toggleRow(.phone, "SMS", "Critical updates only", prefBinding($smsOn)); Divider()
            Button { Haptics.tap(); openSystemSettings() } label: {
                HStack(spacing: Nuru.S.md) {
                    iconTile(.bell, tint: Nuru.gold.opacity(0.08), color: Color(hex: 0xA8861C))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notification settings").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        Text("Manage sounds & toggles in phone settings").font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 16, color: Color(hex: 0x74808F))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }.buttonStyle(.pressableSubtle)
        }
    }

    // MARK: Display

    /// Text-size options → the global scale the font helpers apply (Nuru.textScale).
    private static let textSizes: [(label: String, scale: Double, preview: CGFloat)] = [
        ("Small", 0.90, 13), ("Default", 1.0, 15), ("Large", 1.15, 18),
    ]

    private var display: some View {
        sectionCard("DISPLAY", icon: .sun) {
            Text("Text size").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
            HStack(spacing: Nuru.S.sm) {
                ForEach(Self.textSizes, id: \.label) { opt in
                    let on = abs(textScale - opt.scale) < 0.001
                    Button {
                        if !on { Haptics.selection() }
                        withAnimation(.easeInOut(duration: 0.15)) { textScale = opt.scale }
                    } label: {
                        Text(opt.label)
                            .font(.inter(opt.preview, on ? .bold : .semibold))
                            .foregroundStyle(on ? Nuru.navy : Color(hex: 0x59667C))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(on ? Nuru.goldChipBg : Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Nuru.gold : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, Nuru.S.xs)
            Text("Adjusts text size across the whole app.").font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F)).padding(.top, Nuru.S.xs)
        }
    }

    // MARK: Language

    private var language: some View {
        sectionCard("LANGUAGE", icon: .languages) {
            Button { Haptics.tap(); helpSheet = .language } label: {
                actionRow(.languages, tint: Color(hex: 0xE0F2FE), color: Color(hex: 0x0EA5E9),
                          "Language", "App language · \(nuruLanguageName(p?.locale))")
            }.buttonStyle(.pressableSubtle)
        }
    }

    // MARK: Privacy

    private var privacy: some View {
        sectionCard("PRIVACY", icon: .mapPin) {
            HStack(spacing: Nuru.S.md) {
                fieldIconTile(.mapPin)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Share my approximate location").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    Text("Helps you connect with believers near you. Approximate only; you can turn this off anytime.")
                        .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Toggle("", isOn: $shareLocation).labelsHidden().tint(Nuru.gold)
            }
        }
    }

    // MARK: Help & privacy

    private var helpPrivacy: some View {
        sectionCard("HELP & PRIVACY", icon: .lifeBuoy) {
            Button { Haptics.tap(); helpSheet = .support } label: {
                actionRow(.lifeBuoy, tint: Nuru.successBg, color: Color(hex: 0x16A34A),
                          "Help & support", "FAQs, contact us")
            }.buttonStyle(.pressableSubtle)
            Divider()
            Button { Haptics.tap(); helpSheet = .privacyPolicy } label: {
                actionRow(.shieldCheck, tint: Color(hex: 0xEEF2FF), color: Color(hex: 0x6366F1),
                          "Privacy policy", "How we handle your data")
            }.buttonStyle(.pressableSubtle)
        }
    }

    // MARK: Danger zone

    private var actions: some View {
        HStack(spacing: Nuru.S.sm) {
            Button { Haptics.tap(); showSignOutConfirm = true } label: {
                HStack(spacing: 6) { Icon(.logOut, size: 15, color: Nuru.navy); Text("Sign out").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy) }
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            // Calm confirm — signing out is reversible, so no destructive red.
            .confirmationDialog("Sign out of Nuru Pathway?", isPresented: $showSignOutConfirm, titleVisibility: .visible) {
                Button("Sign out") {
                    // Revoke the refresh-token family server-side FIRST (the token
                    // is captured synchronously, the call is fire-and-forget), then
                    // clear local state — the sign-out never waits on the network.
                    MemberAPI.revokeSessionBestEffort()
                    auth.signOut()
                }
                Button("Stay signed in", role: .cancel) {}
            } message: {
                Text("Your progress is saved — you can pick up right where you left off.")
            }
            Button { } label: {
                HStack(spacing: 6) { Icon(.trash2, size: 15, color: Color(hex: 0xDC2626)); Text("Delete account").font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0xDC2626)) }
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color(hex: 0xFEF2F2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0xFECACA), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    // MARK: building blocks (rows only used on this screen)

    private func actionRow(_ icon: Lucide, tint: Color, color: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: Nuru.S.md) {
            iconTile(icon, tint: tint, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text(sub).font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 16, color: Color(hex: 0x74808F))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func toggleRow(_ icon: Lucide, _ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: Nuru.S.md) {
            fieldIconTile(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text(sub).font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: Binding(get: { binding.wrappedValue },
                                     set: { binding.wrappedValue = $0; Haptics.selection() }))
                .labelsHidden().tint(Nuru.gold)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Sheet routing

private enum SHelpSheet: String, Identifiable {
    case language, support, privacyPolicy
    var id: String { rawValue }
}

// MARK: - Change password sheet (POST /me/password)

private struct PasswordChangeSheet: View {
    private static let minLength = 8

    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var saving = false
    @State private var error: String?
    @State private var succeeded = false

    var body: some View {
        PSheetShell(title: "Change password") {
            if succeeded {
                successView
            } else {
                formView
            }
        }
        .presentationDetents([.medium])
    }

    // Clear confirmation — the member sees exactly what happened before dismissing.
    private var successView: some View {
        VStack(spacing: Nuru.S.sm) {
            Icon(.checkCircle2, size: 40, color: Nuru.success)
                .padding(.top, Nuru.S.sm)
            Text("Your password has been changed.")
                .font(.fraunces(19, .medium)).foregroundStyle(Nuru.navy)
                .multilineTextAlignment(.center)
            Text("Use your new password next time you sign in.")
                .font(.inter(13)).foregroundStyle(Color(hex: 0x5B6472))
                .multilineTextAlignment(.center)
            GoldSheetButton(title: "Done", busy: false) { dismiss() }
                .padding(.top, Nuru.S.xs)
        }
        .frame(maxWidth: .infinity)
    }

    private var formView: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            secure("Current password", $current)
            secure("New password", $new1)
            secure("Confirm new password", $new2)
            Text("Use at least \(Self.minLength) characters with a mix of letters, numbers and a symbol.")
                .font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                .padding(.top, Nuru.S.xs)
            if let error {
                Text(error).font(.inter(12)).foregroundStyle(Nuru.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
            GoldSheetButton(title: "Change password", busy: saving) { Task { await save() } }
                .padding(.top, Nuru.S.xs)
        }
    }

    private func secure(_ placeholder: String, _ binding: Binding<String>) -> some View {
        PasswordField(placeholder: placeholder, text: binding) { error = nil }
    }

    private func save() async {
        guard !current.isEmpty else { error = "Enter your current password."; return }
        guard new1.count >= Self.minLength else {
            error = "New password must be at least \(Self.minLength) characters."; return
        }
        guard new1 == new2 else { error = "New passwords don't match."; return }
        saving = true; error = nil
        defer { saving = false }
        do {
            try await MemberAPI.changePassword(current: current, new: new1)
            Haptics.success()
            succeeded = true
        } catch {
            Haptics.error()
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't change the password — check your current one."
        }
    }
}

/// Secure text field with a show/hide toggle — matches the sheet's field styling.
private struct PasswordField: View {
    let placeholder: String
    @Binding var text: String
    var onEdit: () -> Void = {}
    @State private var revealed = false

    var body: some View {
        HStack(spacing: Nuru.S.xs) {
            Group {
                if revealed {
                    TextField(placeholder, text: $text)
                } else {
                    SecureField(placeholder, text: $text)
                }
            }
            .font(.inter(14)).foregroundStyle(Nuru.navy)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .onChange(of: text) { _, _ in onEdit() }

            Button {
                revealed.toggle()
            } label: {
                Icon(revealed ? .eyeOff : .eye, size: 18, color: Color(hex: 0x5B6472))
            }
            .accessibilityLabel(revealed ? "Hide password" : "Show password")
        }
        .padding(.horizontal, Nuru.S.base).frame(height: 48)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

// MARK: - App language sheet (PATCH /me locale)

/// PATCH /me body for the locale-only update — snake_cased by the client
/// encoder; `rowVersion` drives the server's optimistic-concurrency check.
private struct UpdateLocaleBody: Encodable {
    let locale: String
    let rowVersion: Int
}

private struct AppLanguageSheet: View {
    let current: String
    let rowVersion: Int
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked = "en"
    @State private var saving = false
    @State private var error: String?

    private let options: [(code: String, name: String, note: String, enabled: Bool)] = [
        ("en", "English", "Available", true),
        ("sw", "Swahili", "Available", true),
        ("fr", "French", "Coming soon", false),
    ]

    var body: some View {
        PSheetShell(title: "App language") {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("Choose the language for the app interface.")
                    .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                VStack(spacing: Nuru.S.sm) {
                    ForEach(options, id: \.code) { o in
                        Button { if o.enabled { Haptics.selection(); picked = o.code } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(o.name).font(.inter(14, .medium)).foregroundStyle(Nuru.navy)
                                    Text(o.note).font(.nCardMeta).foregroundStyle(Color(hex: 0x5B6472))
                                }
                                Spacer()
                                if picked == o.code { Icon(.check, size: 16, color: Nuru.gold) }
                            }
                            .padding(12)
                            .background(picked == o.code ? Nuru.gold.opacity(0.09) : Nuru.surface,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(picked == o.code ? Nuru.gold : Nuru.border, lineWidth: 1))
                            .opacity(o.enabled ? 1 : 0.5)
                        }.buttonStyle(.plain).disabled(!o.enabled)
                    }
                }
                if let error { Text(error).font(.inter(12)).foregroundStyle(Nuru.danger) }
                GoldSheetButton(title: "Save", busy: saving) { Task { await save() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear { picked = String(current.prefix(2)).lowercased() == "sw" ? "sw" : "en" }
    }

    private func save() async {
        saving = true; error = nil
        defer { saving = false }
        do {
            _ = try await APIClient.shared.patch("me", body: UpdateLocaleBody(locale: picked, rowVersion: rowVersion), as: EmptyResponse.self)
            onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't save — please try again."
        }
    }
}

// MARK: - Help & support / privacy policy sheets

private struct HelpSupportSheet: View {
    @State private var open: Int? = 0

    private let faqs: [(q: String, a: String)] = [
        ("How do I track my pathway progress?",
         "Open the Pathway tab to see your current level, completed lessons and upcoming milestones. Progress saves automatically."),
        ("How do reflections work?",
         "After each lesson you can submit a written reflection. Your mentor reviews it and may leave encouragement before you move on."),
        ("How do I give or manage my contributions?",
         "Head to the Give tab to make a one-off gift or set up recurring giving. Receipts appear under Email notifications."),
        ("Can I use the app offline?",
         "Downloaded devotionals and lessons are available offline. Reflections and giving sync once you're back online."),
    ]

    var body: some View {
        PSheetShell(title: "Help & support") {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                ForEach(Array(faqs.enumerated()), id: \.offset) { i, f in
                    VStack(alignment: .leading, spacing: 0) {
                        Button { Haptics.tap(); withAnimation(.easeInOut(duration: 0.2)) { open = open == i ? nil : i } } label: {
                            HStack(spacing: Nuru.S.sm) {
                                Text(f.q).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Icon(.chevronRight, size: 16, color: Color(hex: 0x74808F))
                                    .rotationEffect(.degrees(open == i ? 90 : 0))
                            }
                            .padding(12)
                        }.buttonStyle(.plain)
                        if open == i {
                            Text(f.a).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12).padding(.bottom, 12)
                        }
                    }
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }

                Text("STILL NEED HELP?")
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xA8861C))
                    .padding(.top, Nuru.S.md)
                HStack(spacing: Nuru.S.sm) {
                    Button { openURL("mailto:support@nuru.app") } label: {
                        HStack(spacing: 6) { Icon(.mail, size: 15, color: Nuru.navy); Text("Email us").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy) }
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                    Button { openURL("tel:+254700000000") } label: {
                        HStack(spacing: 6) { Icon(.phone, size: 15, color: Nuru.navy); Text("Call us").font(.inter(13, .bold)).foregroundStyle(Nuru.navy) }
                            .frame(maxWidth: .infinity).frame(height: 46)
                            .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func openURL(_ s: String) {
        guard let url = URL(string: s) else { return }
        UIApplication.shared.open(url)
    }
}

private struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss

    private let sections: [(h: String, p: String)] = [
        ("What we collect",
         "We collect the details you provide — name, contact information, country, languages and pathway activity — to personalise your discipleship journey."),
        ("How we use it",
         "Your data powers progress tracking, reflections, reminders and giving receipts. We never sell your personal information to third parties."),
        ("Who can see it",
         "Your mentor and cell leader can view your pathway progress and reflections. Personal contact details remain private to you and the Nuru team."),
        ("Your choices",
         "You can edit or delete your information at any time from this profile, manage notification preferences, or request full account deletion."),
        ("Data security",
         "Information is encrypted in transit and at rest. Access is restricted to authorised staff bound by confidentiality agreements."),
    ]

    var body: some View {
        PSheetShell(title: "Privacy policy") {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                Text("Last updated 14 June 2026").font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                ForEach(sections, id: \.h) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.h).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        Text(s.p).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Questions about your privacy? Email privacy@nuru.app and we'll respond within 7 days.")
                    .font(.nCardMeta).italic().foregroundStyle(Color(hex: 0x74808F))
                GoldSheetButton(title: "Got it") { dismiss() }
            }
        }
    }
}
