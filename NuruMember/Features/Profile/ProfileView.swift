// Account / Profile — native port of the Figma ProfileTab (current make). Cream
// header with avatar + gold level chip, then settings cards: Personal Information
// (Member ID + live /me fields, all editable via PATCH /me except email §5.8),
// Security & Login (real password change + TOTP 2FA), Notifications, Achievements
// (real /me/achievements + /badges catalogue), Milestones (real enrollment +
// baptism flag), Certificates (real GET /certificates + public verify), Display,
// Privacy (location consent → /me/location), Help & Privacy, Sign out / Delete.
// The Figma's Connected-accounts / Social-links sections were removed from the
// current design, so they are gone here too.
import SwiftUI
import UIKit
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

    // Sheets
    @State private var editingField: PField?
    @State private var showPasswordSheet = false
    @State private var helpSheet: PHelpSheet?
    @State private var viewingBadge: PBadgeItem?
    @State private var showAllBadges = false
    @State private var verifyingCert: PCert?

    // Real backend extras (loaded once; tolerate offline with empty state).
    @State private var badges: [PBadgeItem] = []
    @State private var certs: [PCert] = []

    /// Real 2FA state from the server profile — the toggle reflects the truth.
    private var twoFactorOn: Bool { auth.profile?.mfaEnabled ?? false }

    private var p: UserProfile? { auth.profile }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.base) {
                header
                personalInfo
                security
                notifications
                achievements
                milestonesSection
                certificates
                display
                privacy
                helpPrivacy
                actions
                Text("Nuru Pathway · v1.0").font(.inter(10)).foregroundStyle(Color(hex: 0x9CA3AF))
                    .padding(.top, Nuru.S.xs)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .background(Nuru.paper.ignoresSafeArea(edges: .bottom))
        .ignoresSafeArea(edges: .top)
        .task { await loadExtras() }
        .sheet(isPresented: $showMfaEnroll) {
            MfaEnrollSheet(onEnabled: { Task { await auth.loadProfile() } })
        }
        .sheet(item: $editingField) { f in
            EditFieldSheet(field: f, current: currentValue(for: f), rowVersion: p?.rowVersion ?? 1) {
                Task { await auth.loadProfile() }
            }
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
        .sheet(item: $viewingBadge) { b in BadgeDetailSheet(badge: b) }
        .sheet(isPresented: $showAllBadges) { BadgeGallerySheet(badges: badges) }
        .sheet(item: $verifyingCert) { c in VerifyCertificateSheet(cert: c) }
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

    // MARK: Data — real achievements + certificates

    private func loadExtras() async {
        async let catalogue = try? await APIClient.shared.get("badges", as: Envelope<PBadgeCat>.self).data
        async let mine = try? await APIClient.shared.get("me/achievements", as: PMyAchievements.self)
        async let certificates = try? await APIClient.shared.get("certificates", as: Envelope<PCert>.self).data

        let cat = await catalogue ?? []
        let earned = await mine?.badges ?? []
        let earnedByCode = Dictionary(earned.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })
        var merged: [PBadgeItem] = cat.map {
            PBadgeItem(code: $0.code, name: $0.name, description: $0.description,
                       category: $0.category, awardedAt: earnedByCode[$0.code]?.awardedAt ?? earnedByCode[$0.code].map { _ in "" })
        }
        // Earned badges missing from the active catalogue (e.g. retired) still show.
        for e in earned where !merged.contains(where: { $0.code == e.code }) {
            merged.append(PBadgeItem(code: e.code, name: e.name, description: e.description,
                                     category: e.category, awardedAt: e.awardedAt ?? ""))
        }
        badges = merged.sorted { ($0.earned ? 0 : 1, $0.name) < ($1.earned ? 0 : 1, $1.name) }
        certs = await certificates ?? []
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

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    // MARK: Header

    // Cream Figma header (ProfileTab) — navy-on-light "Account", white settings
    // gear, avatar (gold ring + edit pencil), name, email, level chip.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACCOUNT").font(.inter(11, .bold)).kerning(1.98).foregroundStyle(Color(hex: 0x9A7A2A))
                Spacer()
                Icon(.settings, size: 18, color: Nuru.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            HStack(spacing: 16) {
                ZStack(alignment: .bottomTrailing) {
                    Avatar(url: p?.avatarUrl, name: p?.fullName ?? "?", size: 72)
                        .overlay(Circle().stroke(Nuru.gold, lineWidth: 2))
                    ZStack {
                        Circle().fill(Nuru.gold).frame(width: 28, height: 28)
                        Icon(.pencil, size: 11, color: Nuru.navy)
                    }
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .offset(x: 3, y: 3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(p?.fullName ?? "—").font(.fraunces(22, .medium)).kerning(-0.44).foregroundStyle(Nuru.navy)
                    if let email = p?.email { Text(email).font(.inter(13)).foregroundStyle(Color(hex: 0x68758A)) }
                    HStack(spacing: 4) {
                        Icon(.award, size: 11, color: Color(hex: 0x9A7A2A))
                        Text("Level \(auth.me?.enrollment?.currentLevel ?? 1)").font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, Nuru.S.screen).padding(.top, 60).padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
        .padding(.horizontal, -Nuru.S.screen)   // full-bleed inside the padded scroll
    }

    // MARK: Personal information

    /// Editable field definitions — PATCH /me accepts these (email is the login
    /// identity and intentionally NOT writable, §5.8 mass-assignment guard).
    private static let fields: [PField] = [
        PField(id: "name", label: "Full name", icon: .user, kind: .text),
        PField(id: "phone", label: "Phone", icon: .phone, kind: .phone),
        PField(id: "dob", label: "Date of birth", icon: .calendar, kind: .date),
        PField(id: "gender", label: "Gender", icon: .users, kind: .select, options: [
            POption(value: "male", label: "Male"),
            POption(value: "female", label: "Female"),
            POption(value: "prefer_not_to_say", label: "Prefer not to say"),
        ]),
        PField(id: "country", label: "Country", icon: .globe, kind: .select, options: [
            POption(value: "KE", label: "🇰🇪 Kenya"), POption(value: "UG", label: "🇺🇬 Uganda"),
            POption(value: "TZ", label: "🇹🇿 Tanzania"), POption(value: "RW", label: "🇷🇼 Rwanda"),
            POption(value: "ET", label: "🇪🇹 Ethiopia"), POption(value: "NG", label: "🇳🇬 Nigeria"),
        ]),
        PField(id: "city", label: "City", icon: .mapPin, kind: .text),
    ]

    private func currentValue(for f: PField) -> String {
        switch f.id {
        case "name": return p?.fullName ?? ""
        case "phone": return p?.phoneNumber ?? ""
        case "dob": return String((p?.dateOfBirth ?? "").prefix(10))
        case "gender": return p?.gender ?? ""
        case "country": return p?.countryCode?.uppercased() ?? ""
        case "city": return p?.city ?? ""
        default: return ""
        }
    }

    private func displayValue(for f: PField) -> String {
        switch f.id {
        case "name": return p?.fullName ?? "—"
        case "phone": return p?.phoneNumber ?? "Not set"
        case "dob": return formattedDOB
        case "gender":
            guard let g = p?.gender, !g.isEmpty else { return "Not set" }
            return g.replacingOccurrences(of: "_", with: " ").capitalized
        case "country": return countryLabel
        case "city": return p?.city ?? "Not set"
        default: return "—"
        }
    }

    private var personalInfo: some View {
        sectionCard("PERSONAL INFORMATION", icon: .user) {
            memberIdRow
            infoRow(.mail, "EMAIL", p?.email ?? "—")   // login identity — not editable (§5.8)
            Divider()
            ForEach(Self.fields) { f in
                Button { editingField = f } label: {
                    infoRow(f.icon, f.label.uppercased(), displayValue(for: f), editable: true)
                }
                .buttonStyle(.plain)
                if f.id != "city" { Divider() }
            }
            Divider()
            languagesRow
        }
    }

    /// Immutable, server-issued identity — the permanent anchor every interaction,
    /// gift and certificate is tied to (unlike the editable attributes below).
    private var memberIdRow: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.33), lineWidth: 1))
                    .frame(width: 36, height: 36)
                Icon(.fingerprint, size: 16, color: Color(hex: 0xA8861C))
            }
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 3) {
                    Text("MEMBER ID").font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x9CA3AF))
                    Icon(.lock, size: 9, color: Color(hex: 0x9CA3AF))
                }
                Text(memberIdLabel).font(.fraunces(13, .semibold)).foregroundStyle(Nuru.navy)
            }
            Spacer(minLength: 0)
            Text("PERMANENT").font(.inter(9, .semibold)).kerning(0.9).foregroundStyle(Color(hex: 0x9CA3AF))
        }
        .padding(10)
        .background(
            LinearGradient(colors: [Nuru.gold.opacity(0.08), Nuru.surface], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.gold.opacity(0.23), lineWidth: 1))
        .padding(.bottom, Nuru.S.sm)
    }

    /// NRU-<uuid prefix>-<join year> — derived from the real user id + enrollment.
    private var memberIdLabel: String {
        guard let uid = p?.userId, let first = uid.split(separator: "-").first else { return "—" }
        let year = auth.me?.enrollment.map { String($0.startedAt.prefix(4)) }
        return "NRU-\(first.uppercased())" + (year.map { "-\($0)" } ?? "")
    }

    /// Languages spoken — display-only: PATCH /me has no spoken-languages field
    /// (only `locale`), so the default is derived from the member's real locale.
    private var languagesRow: some View {
        HStack(spacing: Nuru.S.md) {
            fieldIconTile(.languages)
            VStack(alignment: .leading, spacing: 3) {
                Text("LANGUAGES SPOKEN").font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x9CA3AF))
                HStack(spacing: 4) { langChip(localeLanguageName, isDefault: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var localeLanguageName: String {
        switch String((p?.locale ?? "en").prefix(2)).lowercased() {
        case "sw": return "Swahili"
        case "fr": return "French"
        default: return "English"
        }
    }

    // MARK: Security

    private var security: some View {
        sectionCard("SECURITY & LOGIN", icon: .lock) {
            Button { showPasswordSheet = true } label: {
                actionRow(.key, tint: Color(hex: 0xEEF2FF), color: Color(hex: 0x6366F1),
                          "Change password", "Keep your account secure")
            }.buttonStyle(.plain)
            Divider()
            HStack(spacing: Nuru.S.md) {
                iconTile(.fingerprint,
                         tint: twoFactorOn ? Color(hex: 0x16A34A).opacity(0.13) : Color(hex: 0xFEF3C7),
                         color: twoFactorOn ? Color(hex: 0x16A34A) : Color(hex: 0xD97706))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Two-factor authentication").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    Text(twoFactorOn ? "Active · Authenticator app" : "Not enabled · recommended")
                        .font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
                }
                Spacer(minLength: 0)
                Toggle("", isOn: Binding(get: { twoFactorOn }, set: { want in
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
            toggleRow(.bell, "Push notifications", "Devotionals, events, reminders", $pushOn); Divider()
            toggleRow(.mail, "Email", "Weekly summary & receipts", $emailOn); Divider()
            toggleRow(.phone, "SMS", "Critical updates only", $smsOn); Divider()
            Button { openSystemSettings() } label: {
                HStack(spacing: Nuru.S.md) {
                    iconTile(.bell, tint: Nuru.gold.opacity(0.08), color: Color(hex: 0xA8861C))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notification settings").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        Text("Manage sounds & toggles in phone settings").font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 16, color: Color(hex: 0x9CA3AF))
                }
                .padding(.vertical, 10)
            }.buttonStyle(.plain)
        }
    }

    // MARK: Achievements (real earned badges + catalogue)

    private var achievements: some View {
        sectionCard("ACHIEVEMENTS", icon: .sparkles,
                    action: badges.isEmpty ? nil : "See all",
                    onAction: { showAllBadges = true }) {
            if badges.isEmpty {
                VStack(spacing: Nuru.S.sm) {
                    ZStack { Circle().fill(Nuru.goldTint).frame(width: 56, height: 56)
                        .overlay(Circle().stroke(Nuru.gold, lineWidth: 1.5)); Icon(.award, size: 22, color: Nuru.gold) }
                    Text("No badges yet").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    Text("Badges appear here as you grow.").font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
                }
                .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(badges) { b in
                            Button { viewingBadge = b } label: { BadgeMedallion(badge: b) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            Text("Badges celebrate your growth — not competition.")
                .font(.inter(10)).italic().foregroundStyle(Color(hex: 0x9CA3AF))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm)
        }
    }

    // MARK: Milestones (real: baptism flag + enrollment level)

    private var milestoneRows: [PMilestone] {
        var rows: [PMilestone] = []
        let baptized = p?.isBaptized ?? false
        rows.append(PMilestone(id: "baptism", label: "Baptism",
                               meta: baptized ? "Recorded — welcome to the family" : "Not yet recorded",
                               status: baptized ? .done : .future))
        let level = max(auth.me?.enrollment?.currentLevel ?? 1, 1)
        for l in 1..<level {
            rows.append(PMilestone(id: "lvl\(l)", label: "Level \(l) completed", meta: "Completed", status: .done))
        }
        rows.append(PMilestone(id: "lvl\(level)", label: "Level \(level) · in progress", meta: "Keep going", status: .active))
        rows.append(PMilestone(id: "completion", label: "Pathway completion", meta: "Your journey continues", status: .future))
        return rows
    }

    private var milestonesSection: some View {
        sectionCard("MILESTONES", icon: .target) {
            let rows = milestoneRows
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, m in
                    MilestoneTimelineRow(milestone: m, isLast: i == rows.count - 1)
                }
            }
        }
    }

    // MARK: Certificates (real GET /certificates)

    private var certificates: some View {
        sectionCard("CERTIFICATES", icon: .badgeCheck) {
            if certs.isEmpty {
                VStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.gold.opacity(0.09))
                            .frame(width: 48, height: 48)
                        Icon(.award, size: 22, color: Nuru.gold)
                    }
                    Text("No certificates yet").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    Text("Complete a level to earn your first.").font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
                }
                .frame(maxWidth: .infinity)
                .padding(20)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            } else {
                VStack(spacing: Nuru.S.sm) {
                    ForEach(certs) { c in
                        CertificateCardView(cert: c) { verifyingCert = c }
                    }
                }
            }
            Text("The name on a certificate is fixed at issuance and won't change if you edit your profile.")
                .font(.inter(10)).italic().foregroundStyle(Color(hex: 0x9CA3AF))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm)
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
                    Button { withAnimation(.easeInOut(duration: 0.15)) { textScale = opt.scale } } label: {
                        Text(opt.label)
                            .font(.inter(opt.preview, on ? .bold : .semibold))
                            .foregroundStyle(on ? Nuru.navy : Color(hex: 0x68758A))
                            .frame(maxWidth: .infinity).frame(height: 48)
                            .background(on ? Nuru.goldChipBg : Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(on ? Nuru.gold : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, Nuru.S.xs)
            Text("Adjusts text size across the whole app.").font(.inter(11)).foregroundStyle(Color(hex: 0x9CA3AF)).padding(.top, Nuru.S.xs)
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
                        .font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
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
            Button { helpSheet = .language } label: {
                actionRow(.languages, tint: Color(hex: 0xE0F2FE), color: Color(hex: 0x0EA5E9),
                          "Language", "App language · \(localeLanguageName)")
            }.buttonStyle(.plain)
            Divider()
            Button { helpSheet = .support } label: {
                actionRow(.lifeBuoy, tint: Nuru.successBg, color: Color(hex: 0x16A34A),
                          "Help & support", "FAQs, contact us")
            }.buttonStyle(.plain)
            Divider()
            Button { helpSheet = .privacyPolicy } label: {
                actionRow(.shieldCheck, tint: Color(hex: 0xEEF2FF), color: Color(hex: 0x6366F1),
                          "Privacy policy", "How we handle your data")
            }.buttonStyle(.plain)
        }
    }

    // MARK: Danger zone

    private var actions: some View {
        HStack(spacing: Nuru.S.sm) {
            Button { auth.signOut() } label: {
                HStack(spacing: 6) { Icon(.logOut, size: 15, color: Nuru.navy); Text("Sign out").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy) }
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }.buttonStyle(.plain)
            Button { } label: {
                HStack(spacing: 6) { Icon(.trash2, size: 15, color: Color(hex: 0xDC2626)); Text("Delete account").font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0xDC2626)) }
                    .frame(maxWidth: .infinity).frame(height: 46)
                    .background(Color(hex: 0xFEF2F2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(hex: 0xFECACA), lineWidth: 1))
            }.buttonStyle(.plain)
        }
    }

    // MARK: building blocks

    private func sectionCard<C: View>(_ title: String, icon: Lucide,
                                      action: String? = nil, onAction: (() -> Void)? = nil,
                                      @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack {
                HStack(spacing: 6) {
                    Icon(icon, size: 12, color: Color(hex: 0xA8861C))
                    Text(title).font(.inter(10, .bold)).kerning(1.8).foregroundStyle(Color(hex: 0xA8861C))
                }
                Spacer()
                if let action, let onAction {
                    Button(action: onAction) {
                        Text(action).font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                    }.buttonStyle(.plain)
                }
            }
            content()
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    /// Neutral 36pt icon tile (personal-info / notification-pref rows).
    private func fieldIconTile(_ icon: Lucide) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.surface)
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                .frame(width: 36, height: 36)
            Icon(icon, size: 15, color: Nuru.navy)
        }
    }

    /// Tinted 36pt icon tile (security / help rows).
    private func iconTile(_ icon: Lucide, tint: Color, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint).frame(width: 36, height: 36)
            Icon(icon, size: 16, color: color)
        }
    }

    private func infoRow(_ icon: Lucide, _ label: String, _ value: String, editable: Bool = false) -> some View {
        HStack(spacing: Nuru.S.md) {
            fieldIconTile(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x9CA3AF))
                Text(value).font(.inter(13, .medium)).foregroundStyle(Nuru.navy)
            }
            Spacer(minLength: 0)
            if editable { Icon(.pencil, size: 14, color: Color(hex: 0x9CA3AF)) }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func actionRow(_ icon: Lucide, tint: Color, color: Color, _ title: String, _ sub: String) -> some View {
        HStack(spacing: Nuru.S.md) {
            iconTile(icon, tint: tint, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text(sub).font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 16, color: Color(hex: 0x9CA3AF))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func toggleRow(_ icon: Lucide, _ title: String, _ sub: String, _ binding: Binding<Bool>) -> some View {
        HStack(spacing: Nuru.S.md) {
            fieldIconTile(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Text(sub).font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
            }
            Spacer(minLength: 0)
            Toggle("", isOn: binding).labelsHidden().tint(Nuru.gold)
        }
        .padding(.vertical, 10)
    }

    private func langChip(_ text: String, isDefault: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text).font(.inter(11, isDefault ? .semibold : .medium))
                .foregroundStyle(isDefault ? Color(hex: 0x8A6D18) : Nuru.navy)
            if isDefault { Icon(.check, size: 10, color: Color(hex: 0x8A6D18)) }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(isDefault ? Nuru.gold.opacity(0.12) : Nuru.surface, in: Capsule())
        .overlay(Capsule().stroke(isDefault ? Nuru.gold.opacity(0.4) : Nuru.border, lineWidth: 1))
    }

    // MARK: helpers

    private var formattedDOB: String {
        guard let dob = p?.dateOfBirth, !dob.isEmpty else { return "Not set" }
        return formatISODay(dob) ?? String(dob.prefix(10))
    }
    private var countryLabel: String {
        guard let code = p?.countryCode, !code.isEmpty else { return "Not set" }
        let flag = code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127397 + $0.value) }.map(String.init).joined()
        let names = ["KE": "Kenya", "UG": "Uganda", "TZ": "Tanzania", "RW": "Rwanda", "ET": "Ethiopia",
                     "NG": "Nigeria", "US": "United States", "GB": "United Kingdom"]
        return "\(flag) \(names[code.uppercased()] ?? code.uppercased())"
    }
}

/// "yyyy-MM-dd" (or ISO timestamp) → "18 Apr 1992"-style display date.
func formatISODay(_ iso: String) -> String? {
    let out = DateFormatter(); out.dateFormat = "d MMM yyyy"
    let dayF = DateFormatter(); dayF.dateFormat = "yyyy-MM-dd"
    if let d = dayF.date(from: String(iso.prefix(10))) { return out.string(from: d) }
    if let d = ISO8601DateFormatter().date(from: iso) { return out.string(from: d) }
    return nil
}

// MARK: - Field / sheet models

private struct POption: Hashable { let value: String; let label: String }

private struct PField: Identifiable {
    enum Kind { case text, phone, date, select }
    let id: String
    let label: String
    let icon: Lucide
    let kind: Kind
    var options: [POption] = []
}

private enum PHelpSheet: String, Identifiable {
    case language, support, privacyPolicy
    var id: String { rawValue }
}

/// PATCH /me body — snake_cased by the client encoder; nil fields are omitted.
/// `rowVersion` drives the server's optimistic-concurrency check.
private struct UpdateMeBody: Encodable {
    var fullName: String?
    var phoneNumber: String?
    var gender: String?
    var city: String?
    var countryCode: String?
    var dateOfBirth: String?
    var locale: String?
    let rowVersion: Int
    init(rowVersion: Int) { self.rowVersion = rowVersion }
}

// MARK: - Achievements models (GET /badges + GET /me/achievements)

private struct PBadgeCat: Decodable, Sendable {
    let code: String; let name: String; let description: String; let category: String
}
private struct PEarnedBadge: Decodable, Sendable {
    let code: String; let name: String; let description: String; let category: String
    let awardedAt: String?
}
private struct PMyAchievements: Decodable, Sendable { let badges: [PEarnedBadge] }

private struct PBadgeItem: Identifiable {
    let code: String; let name: String; let description: String; let category: String
    /// Non-nil when earned ("" when the award date is unknown).
    let awardedAt: String?
    var id: String { code }
    var earned: Bool { awardedAt != nil }

    /// Category → medallion icon + colors (mirrors the Figma badge palette).
    var style: (icon: Lucide, color: Color, tint: Color) {
        switch category {
        case "journey": return (.sparkles, Nuru.gold, Color(hex: 0xFFF4DA))
        case "consistency": return (.flame, Color(hex: 0x16A34A), Color(hex: 0xDCFCE7))
        case "community": return (.users, Color(hex: 0x0EA5E9), Color(hex: 0xE0F2FE))
        case "service": return (.handHeart, Color(hex: 0xA855F7), Color(hex: 0xF3E8FF))
        default: return (.award, Nuru.gold, Nuru.goldTint)
        }
    }
}

/// 60pt badge medallion — earned: tinted disc + colored ring; locked: greyed.
private struct BadgeMedallion: View {
    let badge: PBadgeItem
    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(badge.earned ? badge.style.tint : Color(hex: 0xF3F4F6))
                    .overlay(Circle().stroke(badge.earned ? badge.style.color : Nuru.border,
                                             lineWidth: badge.earned ? 1.5 : 1))
                    .frame(width: 54, height: 54)
                Icon(badge.style.icon, size: 20, color: badge.earned ? badge.style.color : Color(hex: 0x9CA3AF))
            }
            Text(badge.name)
                .font(.inter(9, badge.earned ? .semibold : .medium))
                .foregroundStyle(badge.earned ? Nuru.navy : Color(hex: 0x9CA3AF))
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: 66)
    }
}

/// Badge detail — real fields only (name, description, category, awarded date).
private struct BadgeDetailSheet: View {
    let badge: PBadgeItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PSheetShell(title: "") {
            VStack(spacing: Nuru.S.md) {
                ZStack {
                    if badge.earned {
                        Circle().fill(badge.style.color.opacity(0.33)).frame(width: 96, height: 96).blur(radius: 16)
                    }
                    Circle()
                        .fill(badge.earned ? badge.style.tint : Color(hex: 0xF3F4F6))
                        .overlay(Circle().stroke(badge.earned ? badge.style.color : Nuru.border, lineWidth: badge.earned ? 2 : 1))
                        .frame(width: 96, height: 96)
                    Icon(badge.style.icon, size: 42, color: badge.earned ? badge.style.color : Color(hex: 0x9CA3AF))
                }
                HStack(spacing: 6) {
                    if badge.earned {
                        HStack(spacing: 4) {
                            Icon(.check, size: 11, color: Color(hex: 0x16A34A))
                            Text("Earned" + ((badge.awardedAt.flatMap { $0.isEmpty ? nil : formatISODay($0) }).map { " \($0)" } ?? ""))
                                .font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x16A34A))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color(hex: 0x16A34A).opacity(0.09), in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Icon(.lock, size: 10, color: Color(hex: 0x9CA3AF))
                            Text("Locked").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x9CA3AF))
                        }
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color(hex: 0xF3F4F6), in: Capsule())
                    }
                    Text(badge.category.capitalized)
                        .font(.inter(10, .bold)).foregroundStyle(badge.style.color)
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(badge.style.color.opacity(0.10), in: Capsule())
                }
                Text(badge.name).font(.fraunces(26, .semibold)).kerning(-0.5).foregroundStyle(Nuru.navy)
                Text(badge.description).font(.inter(13)).foregroundStyle(Color(hex: 0x6B7280))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                GoldSheetButton(title: badge.earned ? "Keep going" : "Got it") { dismiss() }
                    .padding(.top, Nuru.S.xs)
            }
            .frame(maxWidth: .infinity)
        }
        .presentationDetents([.medium])
    }
}

/// "See all" gallery — the full real catalogue with earned state.
private struct BadgeGallerySheet: View {
    let badges: [PBadgeItem]
    @State private var viewing: PBadgeItem?

    private var earnedCount: Int { badges.filter(\.earned).count }

    var body: some View {
        PSheetShell(title: "Badge gallery") {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("\(earnedCount) of \(badges.count) badges earned")
                    .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0xA8861C))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(badges) { b in
                        Button { viewing = b } label: {
                            VStack(spacing: 6) {
                                BadgeMedallion(badge: b)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                            .opacity(b.earned ? 1 : 0.6)
                        }.buttonStyle(.plain)
                    }
                }
                Text("Locked badges unlock as you grow. Keep going.")
                    .font(.inter(10)).italic().foregroundStyle(Color(hex: 0x9CA3AF))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .sheet(item: $viewing) { b in BadgeDetailSheet(badge: b) }
    }
}

// MARK: - Milestones

private struct PMilestone: Identifiable {
    enum Status { case done, active, future }
    let id: String
    let label: String
    let meta: String
    let status: Status
}

/// Timeline row — 28pt node + connector line down to the next milestone.
private struct MilestoneTimelineRow: View {
    let milestone: PMilestone
    let isLast: Bool

    private var isDone: Bool { milestone.status == .done }
    private var isActive: Bool { milestone.status == .active }

    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(isDone ? Nuru.gold : isActive ? Color.white : Color(hex: 0xF3F4F6))
                        .overlay(Circle().stroke(isActive ? Nuru.gold : isDone ? .clear : Nuru.border,
                                                 lineWidth: isActive ? 2 : 1))
                        .frame(width: 28, height: 28)
                    Icon(isDone ? .check : isActive ? .calendar : .heart,
                         size: isDone ? 14 : isActive ? 13 : 12,
                         color: isDone ? Nuru.navy : isActive ? Nuru.gold : Color(hex: 0x9CA3AF))
                }
                if !isLast {
                    Rectangle()
                        .fill(isDone ? Nuru.gold : Color(hex: 0x0B1F33).opacity(0.12))
                        .frame(width: 1)
                        .frame(minHeight: 16, maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(milestone.label)
                    .font(.inter(13, .semibold))
                    .foregroundStyle(isDone || isActive ? Nuru.navy : Color(hex: 0x9CA3AF))
                Text(milestone.meta).font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
            }
            .padding(.bottom, isLast ? 0 : 12)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Certificates (GET /certificates · public GET /verify/{code})

private struct PCert: Decodable, Sendable, Identifiable {
    let certificateId: String
    let levelNumber: Int?
    let verificationCode: String
    let issuedAt: String
    let downloadUrl: String?
    var id: String { certificateId }
    var title: String { levelNumber.map { "Pathway Level \($0)" } ?? "Pathway certificate" }
}

private struct CertificateCardView: View {
    let cert: PCert
    let onVerify: () -> Void
    @State private var copied = false

    var body: some View {
        VStack(spacing: Nuru.S.sm) {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(LinearGradient(colors: [Nuru.gold.opacity(0.20), Nuru.gold.opacity(0.09)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.33), lineWidth: 1))
                        .frame(width: 44, height: 44)
                    Icon(.award, size: 20, color: Nuru.gold)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(cert.title).font(.inter(14, .semibold)).kerning(-0.14).foregroundStyle(Nuru.navy)
                    Text("Level \(cert.levelNumber ?? 1) · Issued \(formatISODay(cert.issuedAt) ?? String(cert.issuedAt.prefix(10)))")
                        .font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
                }
                Spacer(minLength: 0)
            }

            // Verification code — tap to copy (public proof at /verify/{code}).
            Button {
                UIPasteboard.general.string = cert.verificationCode
                copied = true
                Task { try? await Task.sleep(nanoseconds: 1_600_000_000); copied = false }
            } label: {
                HStack(spacing: 8) {
                    Icon(.fingerprint, size: 13, color: Color(hex: 0x9CA3AF))
                    Text(cert.verificationCode)
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .kerning(0.5).foregroundStyle(Nuru.navy)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Icon(copied ? .check : .copy, size: 11, color: copied ? Color(hex: 0x16A34A) : Nuru.gold)
                        Text(copied ? "Copied" : "Copy")
                            .font(.inter(10, .bold)).foregroundStyle(copied ? Color(hex: 0x16A34A) : Nuru.gold)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }.buttonStyle(.plain)

            // Trust chip → live verification against the public endpoint.
            Button(action: onVerify) {
                HStack(spacing: 4) {
                    Icon(.shieldCheck, size: 13, color: Color(hex: 0x8A6D18))
                    Text("Signed · Verify").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x8A6D18))
                }
                .frame(maxWidth: .infinity).frame(height: 36)
                .background(Nuru.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.33), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(12)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

/// GET /verify/{code} — recomputes hash + signature server-side (§5.5).
private struct PVerifyResult: Decodable, Sendable {
    let valid: Bool
    let revoked: Bool
    let recipientName: String?
    let levelNumber: Int?
    let issuedAt: String?
    let verificationCode: String
}

private struct VerifyCertificateSheet: View {
    let cert: PCert
    @State private var result: PVerifyResult?
    @State private var failed = false

    var body: some View {
        PSheetShell(title: "Verify certificate") {
            if let r = result {
                let color = r.valid ? Color(hex: 0x16A34A) : Color(hex: 0xDC2626)
                VStack(spacing: Nuru.S.md) {
                    VStack(spacing: 6) {
                        ZStack {
                            Circle().fill(color.opacity(0.12)).frame(width: 56, height: 56)
                            Icon(r.valid ? .shieldCheck : .shield, size: 28, color: color)
                        }
                        Text(r.valid ? "Valid · cryptographically signed" : r.revoked ? "Revoked" : "Invalid")
                            .font(.inter(15, .bold)).foregroundStyle(color)
                        Text(r.valid ? "This certificate is authentic and was issued by Nuru Place."
                                     : "This certificate is no longer valid.")
                            .font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Nuru.S.base)
                    .background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(color.opacity(0.25), lineWidth: 1))

                    VStack(spacing: 0) {
                        verifyRow("Recipient", r.recipientName ?? "—"); Divider()
                        verifyRow("Certificate", cert.title); Divider()
                        verifyRow("Issued", r.issuedAt.flatMap(formatISODay) ?? formatISODay(cert.issuedAt) ?? "—"); Divider()
                        verifyRow("Verification code", r.verificationCode, mono: true)
                    }

                    HStack(spacing: 4) {
                        Icon(.lock, size: 11, color: Color(hex: 0x9CA3AF))
                        Text("Anyone can confirm this at pathway.nuruplace.org/v1/verify/\(cert.verificationCode)")
                            .font(.inter(10)).foregroundStyle(Color(hex: 0x9CA3AF))
                    }
                }
            } else if failed {
                VStack(spacing: Nuru.S.sm) {
                    Icon(.shield, size: 26, color: Nuru.faint)
                    Text("Couldn't reach the verification service.").font(.inter(13)).foregroundStyle(Nuru.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl)
            } else {
                VStack(spacing: Nuru.S.sm) {
                    ProgressView().tint(Nuru.gold)
                    Text("Verifying signature…").font(.inter(12)).foregroundStyle(Nuru.muted)
                }
                .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl)
            }
        }
        .presentationDetents([.medium])
        .task {
            do { result = try await APIClient.shared.get("verify/\(cert.verificationCode)", as: PVerifyResult.self) }
            catch { failed = true }
        }
    }

    private func verifyRow(_ label: String, _ value: String, mono: Bool = false) -> some View {
        HStack {
            Text(label).font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
            Spacer(minLength: Nuru.S.md)
            Text(value)
                .font(mono ? .system(size: 12, weight: .semibold, design: .monospaced) : .inter(12, .semibold))
                .foregroundStyle(Nuru.navy)
                .lineLimit(1)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - Edit field sheet (PATCH /me, optimistic-concurrency row_version)

private struct EditFieldSheet: View {
    let field: PField
    let current: String
    let rowVersion: Int
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var selected = ""
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        PSheetShell(title: "Edit \(field.label.lowercased())") {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                switch field.kind {
                case .select:
                    VStack(spacing: Nuru.S.sm) {
                        ForEach(field.options, id: \.value) { opt in
                            Button { selected = opt.value } label: {
                                HStack {
                                    Text(opt.label).font(.inter(14, .medium)).foregroundStyle(Nuru.navy)
                                    Spacer()
                                    if selected == opt.value { Icon(.check, size: 16, color: Nuru.gold) }
                                }
                                .padding(12)
                                .background(selected == opt.value ? Nuru.gold.opacity(0.09) : Nuru.surface,
                                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .stroke(selected == opt.value ? Nuru.gold : Nuru.border, lineWidth: 1))
                            }.buttonStyle(.plain)
                        }
                    }
                case .date:
                    DatePicker("", selection: $date, in: ...Date(), displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                case .text, .phone:
                    TextField(field.label, text: $text)
                        .keyboardType(field.kind == .phone ? .phonePad : .default)
                        .font(.inter(14)).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, Nuru.S.base).frame(height: 48)
                        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }

                if let error {
                    Text(error).font(.inter(12)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }

                GoldSheetButton(title: "Save changes", busy: saving) { Task { await save() } }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            text = current
            selected = current
            if field.kind == .date, !current.isEmpty {
                let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                if let d = f.date(from: current) { date = d }
            }
        }
    }

    private var newValue: String {
        switch field.kind {
        case .select: return selected
        case .date:
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: date)
        case .text, .phone: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    private func save() async {
        let value = newValue
        guard !value.isEmpty else { error = "Please enter a value."; return }
        saving = true; error = nil
        defer { saving = false }
        var body = UpdateMeBody(rowVersion: rowVersion)
        switch field.id {
        case "name": body.fullName = value
        case "phone": body.phoneNumber = value
        case "dob": body.dateOfBirth = value
        case "gender": body.gender = value
        case "country": body.countryCode = value
        case "city": body.city = value
        default: return
        }
        do {
            _ = try await APIClient.shared.patch("me", body: body, as: EmptyResponse.self)
            onSaved()
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't save — please try again."
        }
    }
}

// MARK: - Change password sheet (POST /me/password)

private struct PasswordChangeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        PSheetShell(title: "Change password") {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                secure("Current password", $current)
                secure("New password", $new1)
                secure("Confirm new password", $new2)
                Text("Use at least 8 characters with a mix of letters, numbers and a symbol.")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
                    .padding(.top, Nuru.S.xs)
                if let error {
                    Text(error).font(.inter(12)).foregroundStyle(Nuru.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
                GoldSheetButton(title: "Update password", busy: saving) { Task { await save() } }
                    .padding(.top, Nuru.S.xs)
            }
        }
        .presentationDetents([.medium])
    }

    private func secure(_ placeholder: String, _ binding: Binding<String>) -> some View {
        SecureField(placeholder, text: binding)
            .font(.inter(14)).foregroundStyle(Nuru.navy)
            .padding(.horizontal, Nuru.S.base).frame(height: 48)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func save() async {
        guard !current.isEmpty else { error = "Enter your current password."; return }
        guard new1.count >= 8 else { error = "New password must be at least 8 characters."; return }
        guard new1 == new2 else { error = "New passwords don't match."; return }
        saving = true; error = nil
        defer { saving = false }
        struct Body: Encodable { let currentPassword: String; let newPassword: String }
        do {
            _ = try await APIClient.shared.post("me/password",
                                                body: Body(currentPassword: current, newPassword: new1),
                                                as: EmptyResponse.self)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't change the password — check your current one."
        }
    }
}

// MARK: - App language sheet (PATCH /me locale)

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
                    .font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
                VStack(spacing: Nuru.S.sm) {
                    ForEach(options, id: \.code) { o in
                        Button { if o.enabled { picked = o.code } } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(o.name).font(.inter(14, .medium)).foregroundStyle(Nuru.navy)
                                    Text(o.note).font(.inter(11)).foregroundStyle(Color(hex: 0x6B7280))
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
        var body = UpdateMeBody(rowVersion: rowVersion)
        body.locale = picked
        do {
            _ = try await APIClient.shared.patch("me", body: body, as: EmptyResponse.self)
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
                        Button { withAnimation(.easeInOut(duration: 0.2)) { open = open == i ? nil : i } } label: {
                            HStack(spacing: Nuru.S.sm) {
                                Text(f.q).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                                Icon(.chevronRight, size: 16, color: Color(hex: 0x9CA3AF))
                                    .rotationEffect(.degrees(open == i ? 90 : 0))
                            }
                            .padding(12)
                        }.buttonStyle(.plain)
                        if open == i {
                            Text(f.a).font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12).padding(.bottom, 12)
                        }
                    }
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }

                Text("STILL NEED HELP?")
                    .font(.inter(10, .semibold)).kerning(1.8).foregroundStyle(Color(hex: 0xA8861C))
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
                Text("Last updated 14 June 2026").font(.inter(11)).foregroundStyle(Color(hex: 0x9CA3AF))
                ForEach(sections, id: \.h) { s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(s.h).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        Text(s.p).font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Questions about your privacy? Email privacy@nuru.app and we'll respond within 7 days.")
                    .font(.inter(11)).italic().foregroundStyle(Color(hex: 0x9CA3AF))
                GoldSheetButton(title: "Got it") { dismiss() }
            }
        }
    }
}

// MARK: - Shared sheet chrome (native port of the Figma SheetShell)

/// Bottom-sheet chrome: grab handle, Fraunces title, X close, scrollable content.
struct PSheetShell<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(Color(hex: 0x0B1F33).opacity(0.15))
                .frame(width: 40, height: 4)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
            HStack {
                Text(title).font(.fraunces(20, .medium)).kerning(-0.4).foregroundStyle(Nuru.navy)
                Spacer()
                Button { dismiss() } label: {
                    ZStack {
                        Circle().fill(Nuru.surface).frame(width: 32, height: 32)
                        Icon(.x, size: 16, color: Nuru.navy)
                    }
                }.buttonStyle(.plain)
            }
            .padding(.top, 12)
            ScrollView(showsIndicators: false) {
                content().padding(.top, Nuru.S.base).padding(.bottom, Nuru.S.xl)
            }
        }
        .padding(.horizontal, Nuru.S.screen)
        .background(Color.white.ignoresSafeArea())
        .presentationCornerRadius(28)
        .presentationDragIndicator(.hidden)
    }
}

/// Flat gold sheet CTA — GOLD background, navy 700-weight label (Figma buttons).
struct GoldSheetButton: View {
    let title: String
    var busy: Bool = false
    var disabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if busy { ProgressView().tint(Nuru.navy) }
                else { Text(title).font(.inter(14, .bold)).foregroundStyle(Nuru.navy) }
            }
            .frame(maxWidth: .infinity).frame(height: 48)
            .background(disabled ? Nuru.gold.opacity(0.4) : Nuru.gold,
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled || busy)
    }
}
