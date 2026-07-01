// Account / Profile — native port of the RN Profile screen (IMG_1866–1869). Navy
// header with avatar + gold level coin, then settings cards: Personal Information
// (live /me data), Security & Login, Connected Accounts, Social Links,
// Notifications, Achievements, Milestones, Certificates, Display, Privacy, Help &
// Privacy, and Sign out / Delete account. Profile fields + sign-out are wired to
// the backend. The Security 2FA toggle runs the real TOTP enroll/verify/disable
// flow; Share-location wires to /me/location; notification prefs persist on device
// (+ real push permission). Connected/social links remain visual placeholders.
import SwiftUI
import CoreLocation
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore

    // Notification channel prefs — persisted on device (no backend channel-pref
    // endpoint yet); push additionally requests the real system permission.
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

    /// Real 2FA state from the server profile — the toggle reflects the truth.
    private var twoFactorOn: Bool { auth.profile?.mfaEnabled ?? false }

    private var p: UserProfile? { auth.profile }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.base) {
                header
                personalInfo
                security
                connectedAccounts
                socialLinks
                notifications
                achievements
                milestones
                certificates
                display
                privacy
                helpPrivacy
                actions
                Text("Nuru Pathway · v1.0").font(.nMicro).foregroundStyle(Nuru.faint)
                    .padding(.top, Nuru.S.sm)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .background(Nuru.paper.ignoresSafeArea(edges: .bottom))
        .ignoresSafeArea(edges: .top)
        .sheet(isPresented: $showMfaEnroll) {
            MfaEnrollSheet(onEnabled: { Task { await auth.loadProfile() } })
        }
        .alert("Turn off two-factor?", isPresented: $showMfaDisable) {
            TextField("6-digit code", text: $mfaDisableCode).keyboardType(.numberPad)
            Button("Turn off", role: .destructive) {
                Task {
                    do { try await MemberAPI.disableMfa(code: mfaDisableCode); await auth.loadProfile() }
                    catch { mfaError = (error as? APIError)?.errorDescription ?? "Couldn't turn off two-factor." }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter a current code from your authenticator app to confirm.")
        }
        .alert("Two-factor authentication", isPresented: Binding(get: { mfaError != nil }, set: { if !$0 { mfaError = nil } })) {
            Button("OK") { mfaError = nil }
        } message: { Text(mfaError ?? "") }
        .onChange(of: pushOn) { _, on in if on { requestPushPermission() } }
        .onChange(of: shareLocation) { _, on in Task { await applyLocationSharing(on) } }
    }

    // MARK: Settings side-effects

    /// Ask iOS for notification permission when the member turns push on.
    private func requestPushPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            HStack {
                Text("ACCOUNT").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
                Spacer()
                Icon(.settings, size: 18, color: Nuru.onNavy)
                    .frame(width: 36, height: 36).background(Color.white.opacity(0.12), in: Circle())
            }
            HStack(spacing: Nuru.S.base) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(url: p?.avatarUrl, name: p?.fullName ?? "?", size: 64)
                        .overlay(Circle().stroke(Nuru.gold.opacity(0.6), lineWidth: 2))
                    ZStack {
                        Circle().fill(Nuru.goldGradient).frame(width: 22, height: 22)
                        Text("\(auth.me?.enrollment?.currentLevel ?? 1)").font(.inter(10, .bold)).foregroundStyle(.white)
                    }
                    .overlay(Circle().stroke(Nuru.navy, lineWidth: 2))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p?.fullName ?? "—").font(.fraunces(22, .semibold)).foregroundStyle(.white)
                    if let email = p?.email { Text(email).font(.nCaption).foregroundStyle(Nuru.onNavyDim) }
                    HStack(spacing: 4) {
                        Icon(.award, size: 11, color: Nuru.goldGlow)
                        Text("Level \(auth.me?.enrollment?.currentLevel ?? 1)").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldGlow)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .overlay(Capsule().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Nuru.S.screen).padding(.top, 64).padding(.bottom, Nuru.S.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .padding(.horizontal, -Nuru.S.screen)   // full-bleed inside the padded scroll
    }

    // MARK: Personal information

    private var personalInfo: some View {
        sectionCard("PERSONAL INFORMATION", icon: .user) {
            infoRow(.user, "FULL NAME", p?.fullName ?? "—", editable: true)
            divider
            infoRow(.mail, "EMAIL", p?.email ?? "—", editable: false)
            divider
            infoRow(.bell, "PHONE", p?.phoneNumber ?? "Not set", editable: true)
            divider
            infoRow(.calendar, "DATE OF BIRTH", formattedDOB, editable: true)
            divider
            infoRow(.users, "GENDER", (p?.gender ?? "—").capitalized, editable: true)
            divider
            infoRow(.map, "COUNTRY", countryLabel, editable: true)
            divider
            infoRow(.mapPin, "CITY", p?.city ?? "Not set", editable: true)
            divider
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                rowLabel(.quote, "LANGUAGES SPOKEN")
                HStack(spacing: Nuru.S.sm) {
                    langChip("English", checked: true)
                    langChip("Swahili", checked: false)
                }
            }
            .padding(.vertical, Nuru.S.sm)
        }
    }

    // MARK: Security

    private var security: some View {
        sectionCard("SECURITY & LOGIN", icon: .lock) {
            actionRow(.lock, "Change password", "Keep your account secure")
            divider
            toggleRow(.badgeCheck, "Two-factor authentication",
                      twoFactorOn ? "Enabled" : "Not enabled · recommended",
                      Binding(get: { twoFactorOn }, set: { want in
                          if want, !twoFactorOn { showMfaEnroll = true }
                          else if !want, twoFactorOn { mfaDisableCode = ""; showMfaDisable = true }
                      }))
            divider
            actionRow(.user, "Active sessions", "This device")
        }
    }

    private var connectedAccounts: some View {
        sectionCard("CONNECTED ACCOUNTS", icon: .map) {
            connRow("Google", connected: true); divider
            connRow("Facebook", connected: false); divider
            connRow("Instagram", connected: true); divider
            connRow("X", connected: false); divider
            connRow("LinkedIn", connected: false); divider
            connRow("YouTube", connected: false)
        }
    }

    private var socialLinks: some View {
        sectionCard("SOCIAL LINKS", icon: .map) {
            Text("Add your social links so cell-mates can connect.").font(.nCaption).foregroundStyle(Nuru.muted)
            outlineButton(.pencil, "Edit social links").padding(.top, Nuru.S.sm)
        }
    }

    private var notifications: some View {
        sectionCard("NOTIFICATIONS", icon: .bell) {
            toggleRow(.bell, "Push notifications", "Devotionals, events, reminders", $pushOn); divider
            toggleRow(.mail, "Email", "Weekly summary & receipts", $emailOn); divider
            toggleRow(.messageSquareText, "SMS", "Critical updates only", $smsOn); divider
            actionRow(.bell, "Notification settings", "Manage sounds & toggles in phone settings")
        }
    }

    private var achievements: some View {
        sectionCard("ACHIEVEMENTS", icon: .sparkles) {
            VStack(spacing: Nuru.S.sm) {
                ZStack { Circle().fill(Nuru.goldTint).frame(width: 64, height: 64)
                    .overlay(Circle().stroke(Nuru.gold, lineWidth: 2)); Icon(.badgeCheck, size: 26, color: Nuru.gold) }
                Text("First Steps").font(.inter(12, .semibold)).foregroundStyle(Nuru.ink)
                Text("Badges celebrate your growth — not competition.").font(.nMicro).foregroundStyle(Nuru.faint)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.sm)
        }
    }

    private var milestones: some View {
        sectionCard("MILESTONES", icon: .target) {
            milestoneRow(.heart, "Baptism", "Not yet recorded", active: false); divider
            milestoneRow(.calendar, "Level \(auth.me?.enrollment?.currentLevel ?? 1) · in progress", "Keep going", active: true); divider
            milestoneRow(.heart, "Pathway completion", "Your journey continues", active: false)
        }
    }

    private var certificates: some View {
        sectionCard("CERTIFICATES", icon: .badgeCheck) {
            Text("No certificates yet — complete a level to earn your first.").font(.nCaption).foregroundStyle(Nuru.muted)
        }
    }

    /// Text-size options → the global scale the font helpers apply (Nuru.textScale).
    private static let textSizes: [(label: String, scale: Double)] = [
        ("Small", 0.90), ("Default", 1.0), ("Large", 1.15),
    ]

    private var display: some View {
        sectionCard("DISPLAY", icon: .sun) {
            Text("Text size").font(.nCaption).foregroundStyle(Nuru.muted)
            HStack(spacing: Nuru.S.sm) {
                ForEach(Self.textSizes, id: \.label) { opt in
                    let on = abs(textScale - opt.scale) < 0.001
                    Button { withAnimation(.easeInOut(duration: 0.15)) { textScale = opt.scale } } label: {
                        Text(opt.label).font(.inter(14, on ? .semibold : .regular)).foregroundStyle(Nuru.ink)
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(on ? Nuru.goldChipBg : Nuru.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(on ? Nuru.gold : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, Nuru.S.xs)
            Text("Adjusts text size across the whole app.").font(.nMicro).foregroundStyle(Nuru.faint).padding(.top, Nuru.S.xs)
        }
    }

    private var privacy: some View {
        sectionCard("PRIVACY", icon: .mapPin) {
            toggleRow(.mapPin, "Share my approximate location", "Helps us connect you with believers near you. Approximate only; you can turn this off anytime.", $shareLocation)
        }
    }

    private var helpPrivacy: some View {
        sectionCard("HELP & PRIVACY", icon: .users) {
            actionRow(.quote, "Language", "App language · English"); divider
            actionRow(.messageCircle, "Help & support", "FAQs, contact us"); divider
            actionRow(.lock, "Privacy policy", "How we handle your data")
        }
    }

    private var actions: some View {
        HStack(spacing: Nuru.S.md) {
            Button { auth.signOut() } label: {
                HStack(spacing: 6) { Icon(.arrowRight, size: 14, color: Nuru.ink); Text("Sign out").font(.inter(14, .semibold)).foregroundStyle(Nuru.ink) }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }.buttonStyle(.plain)
            Button { } label: {
                HStack(spacing: 6) { Icon(.trash2, size: 14, color: Nuru.danger); Text("Delete account").font(.inter(14, .semibold)).foregroundStyle(Nuru.danger) }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Nuru.danger.opacity(0.06), in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous).stroke(Nuru.danger.opacity(0.4), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    // MARK: building blocks

    private func sectionCard<C: View>(_ title: String, icon: Lucide, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(spacing: 6) { Icon(icon, size: 13, color: Nuru.gold); Text(title).font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold) }
            content()
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    private var divider: some View { Divider().padding(.leading, 44) }

    private func rowLabel(_ icon: Lucide, _ label: String) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(Nuru.surface).frame(width: 32, height: 32); Icon(icon, size: 15, color: Nuru.ink600) }
            Text(label).font(.inter(10, .semibold)).kerning(0.6).foregroundStyle(Nuru.faint)
        }
    }

    private func infoRow(_ icon: Lucide, _ label: String, _ value: String, editable: Bool) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(Nuru.surface).frame(width: 32, height: 32); Icon(icon, size: 15, color: Nuru.ink600) }
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.inter(10, .semibold)).kerning(0.6).foregroundStyle(Nuru.faint)
                Text(value).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
            }
            Spacer(minLength: 0)
            if editable { Icon(.pencil, size: 14, color: Nuru.ink300) }
        }
        .padding(.vertical, Nuru.S.sm)
    }

    private func actionRow(_ icon: Lucide, _ title: String, _ sub: String) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(Nuru.surface).frame(width: 36, height: 36); Icon(icon, size: 16, color: Nuru.ink600) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                Text(sub).font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 14, color: Nuru.ink300)
        }
        .padding(.vertical, Nuru.S.sm)
    }

    private func toggleRow(_ icon: Lucide, _ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(Nuru.surface).frame(width: 36, height: 36); Icon(icon, size: 16, color: Nuru.ink600) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                Text(sub).font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Spacer(minLength: 0)
            Toggle("", isOn: binding).labelsHidden().tint(Nuru.gold)
        }
        .padding(.vertical, Nuru.S.sm)
    }

    private func connRow(_ name: String, connected: Bool) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { RoundedRectangle(cornerRadius: 10).fill(Nuru.surface).frame(width: 36, height: 36); Icon(.map, size: 16, color: Nuru.ink600) }
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                Text(connected ? "Connected" : "Not connected").font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Spacer(minLength: 0)
            if connected {
                Text("Disconnect").font(.inter(12, .semibold)).foregroundStyle(Nuru.ink)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
            } else {
                Text("Connect").font(.inter(12, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7).background(Nuru.goldGradient, in: Capsule())
            }
        }
        .padding(.vertical, Nuru.S.sm)
    }

    private func milestoneRow(_ icon: Lucide, _ title: String, _ sub: String, active: Bool) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { Circle().fill(active ? Nuru.goldTint : Nuru.surface).frame(width: 32, height: 32)
                .overlay(Circle().stroke(active ? Nuru.gold : .clear, lineWidth: 1.5)); Icon(icon, size: 14, color: active ? Nuru.gold : Nuru.ink400) }
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(14, active ? .semibold : .regular)).foregroundStyle(active ? Nuru.ink : Nuru.muted)
                Text(sub).font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Nuru.S.sm)
    }

    private func outlineButton(_ icon: Lucide, _ title: String) -> some View {
        HStack(spacing: 6) { Icon(icon, size: 14, color: Nuru.ink600); Text(title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink) }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func langChip(_ text: String, checked: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.inter(12, .semibold)).foregroundStyle(checked ? Nuru.successText : Nuru.ink)
            if checked { Icon(.check, size: 11, color: Nuru.successText) }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(checked ? Nuru.successBg : Nuru.surface, in: Capsule())
    }

    // MARK: helpers

    private var formattedDOB: String {
        guard let dob = p?.dateOfBirth, !dob.isEmpty else { return "Not set" }
        let out = DateFormatter(); out.dateFormat = "d MMM yyyy"
        // The field may arrive as "yyyy-MM-dd" or a full ISO timestamp.
        let dayF = DateFormatter(); dayF.dateFormat = "yyyy-MM-dd"
        if let d = dayF.date(from: String(dob.prefix(10))) { return out.string(from: d) }
        if let d = ISO8601DateFormatter.nuru.date(from: dob) ?? ISO8601DateFormatter().date(from: dob) { return out.string(from: d) }
        return String(dob.prefix(10))
    }
    private var countryLabel: String {
        guard let code = p?.countryCode, !code.isEmpty else { return "Not set" }
        let flag = code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
        let names = ["KE": "Kenya", "UG": "Uganda", "TZ": "Tanzania", "NG": "Nigeria", "US": "United States", "GB": "United Kingdom"]
        return "\(flag) \(names[code.uppercased()] ?? code.uppercased())"
    }
}
