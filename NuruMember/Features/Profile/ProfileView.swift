// Account / Profile — native port of the Figma ProfileTab (current make): who
// the member IS. Cream header with avatar + gold level chip, then the journey
// cards: Personal Information (Member ID + live /me fields, all editable via
// PATCH /me except email §5.8), Achievements (real /me/achievements + /badges
// catalogue), Growth Scores, Milestones (real enrollment + baptism flag) and
// Certificates (real GET /certificates + public verify). How the APP BEHAVES
// (security, notifications, display, language, privacy, help, sign out) moved
// to SettingsView, pushed from the header's gear button.
// The Figma's Connected-accounts / Social-links sections were removed from the
// current design, so they are gone here too.
import SwiftUI
import UIKit
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var auth: AuthStore

    /// Pushes SettingsView. @SceneStorage (not @State): RootView re-`.id`s the
    /// whole tab tree when the text scale changes, and Settings owns the text-
    /// size control — plain @State would pop the member out of Settings the
    /// moment they tapped a size. SceneStorage survives that reconstruction.
    @SceneStorage("nuru.profile.showSettings") private var showSettings = false

    // Sheets
    @State private var editingField: PField?
    @State private var viewingBadge: PBadgeItem?
    @State private var showAllBadges = false
    @State private var verifyingCert: PCert?

    // Real backend extras (loaded once; tolerate offline with empty state).
    @State private var badges: [PBadgeItem] = []
    @State private var certs: [PCert] = []
    @State private var scores: ScoresSummary?
    @State private var scoreDetailPillar: ScorePillar?

    // Avatar upload (PhotosPicker → downscaled JPEG → POST /me/avatar).
    @State private var avatarPick: PhotosPickerItem?
    @State private var avatarUploading = false
    @State private var avatarError: String?

    private var p: UserProfile? { auth.profile }

    var body: some View {
        // The Profile tab owns its own stack (RootView renders tabs bare) so the
        // gear can PUSH SettingsView like every other drill-down in the app.
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: Nuru.S.base) {
                    header
                    personalInfo
                    achievements
                    growthScores
                    milestonesSection
                    certificates
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .background(Nuru.paper.ignoresSafeArea(edges: .bottom))
            .ignoresSafeArea(edges: .top)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(isPresented: $showSettings) { SettingsView() }
            .task { await loadExtras() }
            .sheet(item: $editingField) { f in
                EditFieldSheet(field: f, current: currentValue(for: f), rowVersion: p?.rowVersion ?? 1) {
                    Task { await auth.loadProfile() }
                }
            }
            .sheet(item: $viewingBadge) { b in BadgeDetailSheet(badge: b) }
            .sheet(isPresented: $showAllBadges) { BadgeGallerySheet(badges: badges) }
            .sheet(item: $verifyingCert) { c in VerifyCertificateSheet(cert: c) }
            .sheet(item: $scoreDetailPillar) { p in ScoreDetailView(pillar: p) }
            .alert("Profile photo", isPresented: Binding(get: { avatarError != nil }, set: { if !$0 { avatarError = nil } })) {
                Button("OK") { avatarError = nil }
            } message: { Text(avatarError ?? "") }
            .onChange(of: avatarPick) { _, item in if let item { Task { await uploadAvatar(item) } } }
        }
    }

    // MARK: Data — real achievements + certificates

    private func loadExtras() async {
        async let catalogue = try? await APIClient.shared.get("badges", as: Envelope<PBadgeCat>.self).data
        async let mine = try? await APIClient.shared.get("me/achievements", as: PMyAchievements.self)
        async let certificates = try? await APIClient.shared.get("certificates", as: Envelope<PCert>.self).data
        async let scoresSummary = try? await MemberAPI.scores()

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
        scores = await scoresSummary
    }

    // MARK: Avatar upload (PhotosPicker → ~512px JPEG → POST /me/avatar)

    private func uploadAvatar(_ item: PhotosPickerItem) async {
        defer { avatarPick = nil }
        guard !avatarUploading else { return }
        avatarUploading = true
        defer { avatarUploading = false }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self),
                  let jpeg = Self.downscaledJPEG(raw) else {
                Haptics.error()
                avatarError = "Couldn't read that photo — please pick another."
                return
            }
            _ = try await MemberAPI.uploadAvatar(jpeg: jpeg)
            Haptics.success()
            await auth.loadProfile()   // the header re-renders with the new avatar_url
        } catch {
            Haptics.error()
            avatarError = (error as? APIError)?.errorDescription ?? "Couldn't upload your photo — please try again."
        }
    }

    /// Downscale to a sane avatar size (longest edge ≤512px) and JPEG-encode —
    /// well inside the server's 5 MB limit and quick even on poor connections.
    private static func downscaledJPEG(_ data: Data, maxDimension: CGFloat = 512) -> Data? {
        guard let img = UIImage(data: data), img.size.width > 0, img.size.height > 0 else { return nil }
        let pixelW = img.size.width * img.scale
        let pixelH = img.size.height * img.scale
        let scale = min(1, maxDimension / max(pixelW, pixelH))
        let size = CGSize(width: floor(pixelW * scale), height: floor(pixelH * scale))
        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: fmt).image { _ in
            img.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.85)
    }

    // MARK: Header

    // Cream Figma header (ProfileTab) — navy-on-light "Account", white settings
    // gear (→ pushes SettingsView), avatar (gold ring + edit pencil), name,
    // email, level chip.
    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("ACCOUNT").font(.inter(11, .bold)).kerning(1.98).foregroundStyle(Color(hex: 0x9A7A2A))
                Spacer()
                Button { Haptics.tap(); showSettings = true } label: {
                    Icon(.settings, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Settings")
            }
            HStack(spacing: 16) {
                // Tap anywhere on the avatar (incl. the pencil) to pick a new photo.
                PhotosPicker(selection: $avatarPick, matching: .images, photoLibrary: .shared()) {
                    ZStack(alignment: .bottomTrailing) {
                        Avatar(url: p?.avatarUrl, name: p?.fullName ?? "?", size: 72)
                            .overlay(Circle().stroke(Nuru.gold, lineWidth: 2))
                            .overlay {
                                if avatarUploading {
                                    ZStack {
                                        Circle().fill(Nuru.navy.opacity(0.45))
                                        ProgressView().tint(.white)
                                    }
                                }
                            }
                        ZStack {
                            Circle().fill(Nuru.gold).frame(width: 28, height: 28)
                            Icon(.pencil, size: 11, color: Nuru.navy)
                        }
                        .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        .offset(x: 3, y: 3)
                    }
                }
                .buttonStyle(.pressable)
                .disabled(avatarUploading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(p?.fullName ?? "—").font(.fraunces(22, .medium)).kerning(-0.44).foregroundStyle(Nuru.navy)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if let email = p?.email {
                        Text(email).font(.inter(13)).foregroundStyle(Color(hex: 0x59667C))
                            .lineLimit(1).truncationMode(.middle)
                    }
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
            .gentleEntrance()
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
                Button { Haptics.tap(); editingField = f } label: {
                    infoRow(f.icon, f.label.uppercased(), displayValue(for: f), editable: true)
                }
                .buttonStyle(.pressableSubtle)
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
                    Text("MEMBER ID").font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x74808F))
                    Icon(.lock, size: 9, color: Color(hex: 0x74808F))
                }
                Text(memberIdLabel).font(.fraunces(13, .semibold)).foregroundStyle(Nuru.navy)
            }
            Spacer(minLength: 0)
            Text("PERMANENT").font(.inter(9, .semibold)).kerning(0.9).foregroundStyle(Color(hex: 0x74808F))
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
                Text("LANGUAGES SPOKEN").font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x74808F))
                HStack(spacing: 4) { langChip(localeLanguageName, isDefault: true) }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var localeLanguageName: String { nuruLanguageName(p?.locale) }

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
                    Text("Badges appear here as you grow.").font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                }
                .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.sm)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(badges) { b in
                            Button { Haptics.tap(); viewingBadge = b } label: { BadgeMedallion(badge: b) }
                                .buttonStyle(.pressable)
                        }
                    }
                }
            }
            Text("Badges celebrate your growth — not competition.")
                .font(.nCardMeta).italic().foregroundStyle(Color(hex: 0x74808F))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm)
        }
    }

    // MARK: Growth scores (real GET /me/scores → "Why this score?" drill-downs)

    private func pillarScore(_ s: ScoresSummary, _ p: ScorePillar) -> GrowthScore {
        switch p {
        case .word: return s.word
        case .prayer: return s.prayer
        case .habits: return s.habits
        case .curriculum: return s.curriculum
        case .attendance: return s.attendance
        }
    }

    private var growthScores: some View {
        sectionCard("GROWTH SCORES", icon: .trendingUp) {
            if let s = scores {
                // Overall — the weighted composite the server computes.
                HStack(spacing: Nuru.S.md) {
                    ZStack {
                        Circle().fill(Nuru.goldTint).frame(width: 44, height: 44)
                            .overlay(Circle().stroke(Nuru.gold.opacity(0.5), lineWidth: 1.5))
                        Text("\(s.overall.score)").font(.fraunces(16, .semibold)).foregroundStyle(Nuru.navy)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Overall").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                        Text(s.overall.band).font(.inter(11)).foregroundStyle(Color(hex: 0x8A6D18))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
                Divider()
                ForEach(ScorePillar.allCases) { pillar in
                    let g = pillarScore(s, pillar)
                    Button { Haptics.tap(); scoreDetailPillar = pillar } label: {
                        HStack(spacing: Nuru.S.md) {
                            fieldIconTile(pillar.icon)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(pillar.displayName).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                                    Spacer(minLength: Nuru.S.sm)
                                    Text("\(g.score)").font(.inter(13, .bold)).foregroundStyle(Color(hex: 0xA8861C))
                                }
                                GeometryReader { geo in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Nuru.surface)
                                        if g.score > 0 {
                                            Capsule().fill(Nuru.gold)
                                                .frame(width: max(6, geo.size.width * CGFloat(min(g.score, 100)) / 100))
                                        }
                                    }
                                }
                                .frame(height: 5)
                            }
                            Icon(.chevronRight, size: 16, color: Color(hex: 0x74808F))
                        }
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressableSubtle)
                    if pillar != ScorePillar.allCases.last { Divider() }
                }
                Text("Tap a score to see why — scores are formative, never a leaderboard.")
                    .font(.nCardMeta).italic().foregroundStyle(Color(hex: 0x74808F))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.xs)
            } else {
                // Real data only: offline / not loaded yet — no invented numbers.
                HStack(spacing: Nuru.S.md) {
                    fieldIconTile(.trendingUp)
                    Text("Your growth scores appear here once we can reach the server.")
                        .font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 6)
            }
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
                    Text("Complete a level to earn your first.").font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
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
                .font(.nCardMeta).italic().foregroundStyle(Color(hex: 0x74808F))
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                .padding(.top, Nuru.S.sm)
        }
    }

    // MARK: building blocks

    private func infoRow(_ icon: Lucide, _ label: String, _ value: String, editable: Bool = false) -> some View {
        HStack(spacing: Nuru.S.md) {
            fieldIconTile(icon)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x74808F))
                Text(value).font(.inter(13, .medium)).foregroundStyle(Nuru.navy)
            }
            Spacer(minLength: 0)
            if editable { Icon(.pencil, size: 14, color: Color(hex: 0x74808F)) }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
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

// MARK: - Shared card building blocks (ProfileView + SettingsView)

/// The account surfaces' card: white rounded card with a gold kicker header
/// (and optional trailing action). File-scope so SettingsView shares the exact
/// same visual language.
func sectionCard<C: View>(_ title: String, icon: Lucide,
                          action: String? = nil, onAction: (() -> Void)? = nil,
                          @ViewBuilder content: () -> C) -> some View {
    VStack(alignment: .leading, spacing: Nuru.S.sm) {
        HStack {
            HStack(spacing: 6) {
                Icon(icon, size: 12, color: Color(hex: 0xA8861C))
                Text(title).font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xA8861C))
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

/// Neutral 36pt icon tile (personal-info / notification-pref / privacy rows).
func fieldIconTile(_ icon: Lucide) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.surface)
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .frame(width: 36, height: 36)
        Icon(icon, size: 15, color: Nuru.navy)
    }
}

/// Tinted 36pt icon tile (security / help rows).
func iconTile(_ icon: Lucide, tint: Color, color: Color) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint).frame(width: 36, height: 36)
        Icon(icon, size: 16, color: color)
    }
}

/// Locale code → display language name (Profile's languages row + Settings' language row).
func nuruLanguageName(_ locale: String?) -> String {
    switch String((locale ?? "en").prefix(2)).lowercased() {
    case "sw": return "Swahili"
    case "fr": return "French"
    default: return "English"
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

/// PATCH /me body — snake_cased by the client encoder; nil fields are omitted.
/// `rowVersion` drives the server's optimistic-concurrency check.
private struct UpdateMeBody: Encodable {
    var fullName: String?
    var phoneNumber: String?
    var gender: String?
    var city: String?
    var countryCode: String?
    var dateOfBirth: String?
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
                Icon(badge.style.icon, size: 20, color: badge.earned ? badge.style.color : Color(hex: 0x74808F))
            }
            Text(badge.name)
                .font(.inter(9, badge.earned ? .semibold : .medium))
                .foregroundStyle(badge.earned ? Nuru.navy : Color(hex: 0x74808F))
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
                    Icon(badge.style.icon, size: 42, color: badge.earned ? badge.style.color : Color(hex: 0x74808F))
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
                            Icon(.lock, size: 10, color: Color(hex: 0x74808F))
                            Text("Locked").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x74808F))
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
                Text(badge.description).font(.inter(13)).foregroundStyle(Color(hex: 0x5B6472))
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
                        Button { Haptics.tap(); viewing = b } label: {
                            VStack(spacing: 6) {
                                BadgeMedallion(badge: b)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                            .opacity(b.earned ? 1 : 0.6)
                        }.buttonStyle(.pressable)
                    }
                }
                Text("Locked badges unlock as you grow. Keep going.")
                    .font(.inter(10)).italic().foregroundStyle(Color(hex: 0x74808F))
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
                         color: isDone ? Nuru.navy : isActive ? Nuru.gold : Color(hex: 0x74808F))
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
                    .foregroundStyle(isDone || isActive ? Nuru.navy : Color(hex: 0x74808F))
                Text(milestone.meta).font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
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

    // PDF download (GET /media/certificates/{code} — authed stream → temp file).
    @State private var downloading = false
    @State private var savedPdfURL: URL?
    @State private var downloadError: String?

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
                        .font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
                }
                Spacer(minLength: 0)
            }

            // Verification code — tap to copy (public proof at /verify/{code}).
            Button {
                UIPasteboard.general.string = cert.verificationCode
                Haptics.success()
                withAnimation(.easeInOut(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_600_000_000)
                    withAnimation(.easeInOut(duration: 0.25)) { copied = false }
                }
            } label: {
                HStack(spacing: 8) {
                    Icon(.fingerprint, size: 13, color: Color(hex: 0x74808F))
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

            HStack(spacing: Nuru.S.sm) {
                // Trust chip → live verification against the public endpoint.
                Button { Haptics.tap(); onVerify() } label: {
                    HStack(spacing: 4) {
                        Icon(.shieldCheck, size: 13, color: Color(hex: 0x8A6D18))
                        Text("Signed · Verify").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x8A6D18))
                    }
                    .frame(maxWidth: .infinity).frame(height: 36)
                    .background(Nuru.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.33), lineWidth: 1))
                }.buttonStyle(.plain)

                // Download → save the authed PDF to a temp file, then share.
                // After the first fetch the button becomes a ShareLink re-share.
                if let saved = savedPdfURL {
                    ShareLink(item: saved) {
                        downloadLabel(icon: .check, text: "Share PDF")
                    }.buttonStyle(.plain)
                } else {
                    Button { downloadPdf() } label: {
                        if downloading {
                            HStack(spacing: 5) {
                                ProgressView().tint(Nuru.navy).scaleEffect(0.7)
                                Text("Downloading…").font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                            }
                            .frame(maxWidth: .infinity).frame(height: 36)
                            .background(Nuru.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.33), lineWidth: 1))
                        } else {
                            downloadLabel(icon: .download, text: "Download PDF")
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(downloading)
                }
            }

            if let downloadError {
                Text(downloadError)
                    .font(.inter(10)).foregroundStyle(Color(hex: 0xDC2626))
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }
        }
        .padding(12)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func downloadLabel(icon: Lucide, text: String) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 13, color: Nuru.navy)
            Text(text).font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
        }
        .frame(maxWidth: .infinity).frame(height: 36)
        .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func downloadPdf() {
        guard !downloading else { return }
        Haptics.tap()
        downloading = true
        downloadError = nil
        Task {
            defer { downloading = false }
            do {
                let data = try await MemberAPI.downloadCertificatePdf(code: cert.verificationCode)
                let name = "Nuru-\(cert.title.replacingOccurrences(of: " ", with: "-"))-\(cert.verificationCode).pdf"
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
                try data.write(to: url, options: .atomic)
                savedPdfURL = url
                Haptics.success()
                presentShare(url)
            } catch {
                Haptics.error()
                if case APIError.http(let status, _, _) = error, status == 404 {
                    downloadError = "The PDF isn't ready yet — check back soon."
                } else {
                    downloadError = (error as? APIError)?.errorDescription ?? "Couldn't download the certificate."
                }
            }
        }
    }

    /// Present the saved PDF in the system share sheet right after download
    /// (the ShareLink the button becomes covers re-shares).
    private func presentShare(_ url: URL) {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive }),
              let root = scene.keyWindow?.rootViewController else { return }
        var top = root
        while let presented = top.presentedViewController { top = presented }
        let avc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad needs an anchor for the popover presentation.
        avc.popoverPresentationController?.sourceView = top.view
        avc.popoverPresentationController?.sourceRect = CGRect(
            x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
        top.present(avc, animated: true)
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
                            .font(.inter(11)).foregroundStyle(Color(hex: 0x5B6472))
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
                        Icon(.lock, size: 11, color: Color(hex: 0x74808F))
                        Text("Anyone can confirm this at pathway.nuruplace.org/v1/verify/\(cert.verificationCode)")
                            .font(.inter(10)).foregroundStyle(Color(hex: 0x74808F))
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
            Text(label).font(.inter(12)).foregroundStyle(Color(hex: 0x5B6472))
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
                            Button { Haptics.selection(); selected = opt.value } label: {
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
            Haptics.success()
            onSaved()
            dismiss()
        } catch {
            Haptics.error()
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't save — please try again."
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
        .buttonStyle(.pressable)
        .disabled(disabled || busy)
        .animation(.easeInOut(duration: 0.2), value: disabled || busy)
    }
}
