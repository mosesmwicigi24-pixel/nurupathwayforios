// Notification center — the native port of screens/NotificationsScreen.tsx. White
// top bar with "Mark all read", typed rows (icon tile by template family), gold
// unread dots. Read-state is display-only server state.
import SwiftUI

@MainActor
final class NotificationsViewModel: ObservableObject {
    @Published var rows: [NotificationRow] = []
    @Published var unread = 0
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { let r = try await MemberAPI.notifications(); rows = r.rows; unread = r.unread }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load notifications." }
        loading = false
    }
    func markAll() async { try? await MemberAPI.markNotificationsRead(); await load() }
    func open(_ n: NotificationRow) async {
        if n.isUnread { try? await MemberAPI.markNotificationsRead([n.notificationId]); await load() }
    }
}

struct NotificationsView: View {
    @StateObject private var vm = NotificationsViewModel()
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var detail: NotificationRow?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if vm.loading && vm.rows.isEmpty {
                        ForEach(0..<5, id: \.self) { _ in
                            skeletonRow
                            Divider().padding(.leading, 68)
                        }
                    } else if vm.rows.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.rows) { n in
                            rowLink(n)
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.bottom, Nuru.tabBarSpace)
                .animation(.easeInOut(duration: 0.3), value: vm.unread)
            }
            .refreshable { await vm.load() }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.rows.isEmpty { await vm.load() } }
        // Fallback popup: read the whole notification, then dismiss.
        .sheet(item: $detail) { n in
            NotificationDetailSheet(meta: metaFor(n.template),
                                    reward: Self.isReward(n.template),
                                    template: n.template,
                                    title: titleFor(n),
                                    bodyText: bodyFor(n),
                                    when: ago(n.sentAt ?? n.scheduledFor)) { detail = nil }
        }
    }

    // MARK: tap routing — every notification lands exactly where it points

    /// Wraps a row in the right navigation: a push to the precise in-app target
    /// (announcement, module, level), a tab switch (events / giving / profile /
    /// pathway), or — when there is no target — the read-and-dismiss popup.
    @ViewBuilder private func rowLink(_ n: NotificationRow) -> some View {
        let t = n.template
        if let aid = n.payload?.announcementId, !aid.isEmpty {
            NavigationLink(value: AppRoute.announcement(aid)) { row(n) }
                .buttonStyle(.pressableSubtle)
                .simultaneousGesture(TapGesture().onEnded { markRead(n) })
        } else if let mid = n.payload?.moduleId, !mid.isEmpty {
            // Pathway content opens ON the Pathway tab (the tab bar tells the truth).
            Button {
                markRead(n); Haptics.tap(); dismiss()
                tabs.openPathway(.module(mid))
            } label: { row(n) }.buttonStyle(.pressableSubtle)
        } else if t.hasPrefix("level"), let lvl = n.payload?.levelNumber {
            Button {
                markRead(n); Haptics.tap(); dismiss()
                tabs.openPathway(.level(lvl))
            } label: { row(n) }.buttonStyle(.pressableSubtle)
        } else if let tab = tabDest(t) {
            Button {
                markRead(n)
                Haptics.tap()
                dismiss()
                tabs.selected = tab
            } label: { row(n) }.buttonStyle(.pressableSubtle)
        } else {
            Button {
                markRead(n)
                Haptics.tap()
                detail = n
            } label: { row(n) }.buttonStyle(.pressableSubtle)
        }
    }

    private func markRead(_ n: NotificationRow) {
        if n.isUnread { Task { await vm.open(n) } }
    }

    /// Template families whose home is a whole tab, not one pushed page.
    private func tabDest(_ t: String) -> AppTab? {
        if t.hasPrefix("event") { return .events }
        if t.hasPrefix("giving") || t.hasPrefix("payment") { return .give }
        if t.hasPrefix("badge") || t.hasPrefix("certificate") { return .profile }
        if t.hasPrefix("level") || t.hasPrefix("reflection") { return .pathway }
        return nil
    }

    /// Unread reward rows (badge / certificate / level) get the Figma "gift" cue.
    private var rewardUnread: Int {
        vm.rows.filter { $0.isUnread && Self.isReward($0.template) }.count
    }
    fileprivate static func isReward(_ t: String) -> Bool {
        t.hasPrefix("badge") || t.hasPrefix("certificate") || t.hasPrefix("level")
    }

    private var topBar: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.chevronLeft, size: 20, color: Nuru.navy)
                    .frame(width: 40, height: 40).background(Nuru.mutedBg, in: Circle())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications").font(.nHeading).foregroundStyle(Nuru.ink)
                HStack(spacing: 6) {
                    Text(vm.unread > 0 ? "\(vm.unread) unread" : "All caught up ✨").font(.nMicro).foregroundStyle(Nuru.faint)
                        .contentTransition(.numericText(value: Double(vm.unread)))
                        .animation(.easeInOut(duration: 0.25), value: vm.unread)
                    if rewardUnread > 0 {
                        HStack(spacing: 3) {
                            Icon(.gift, size: 10, color: Color(hex: 0x9A7A2A))
                            Text("\(rewardUnread) \(rewardUnread == 1 ? "gift" : "gifts")")
                                .font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Nuru.gold.opacity(0.12), in: Capsule())
                    }
                }
            }
            Spacer()
            Button { Haptics.action(); Task { await vm.markAll() } } label: {
                HStack(spacing: 4) {
                    // Figma's CheckCheck (double tick) — composed from two check glyphs.
                    ZStack {
                        Icon(.check, size: 13, color: Nuru.gold).offset(x: -3)
                        Icon(.check, size: 13, color: Nuru.gold).offset(x: 3)
                    }
                    .frame(width: 18)
                    Text("Mark all read").font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).background(Nuru.navy, in: Capsule())
            }
            .disabled(vm.unread == 0).opacity(vm.unread == 0 ? 0.4 : 1)
            .animation(.easeInOut(duration: 0.25), value: vm.unread == 0)
        }
        .padding(.horizontal, Nuru.S.base).padding(.top, 54).padding(.bottom, Nuru.S.md)
        .background(Nuru.white)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .bottom)
    }

    private func row(_ n: NotificationRow) -> some View {
        let meta = metaFor(n.template)
        let reward = Self.isReward(n.template)
        return HStack(alignment: .top, spacing: Nuru.S.md) {
            // Reward rows get the celebratory gold-gradient tile + sparkle (Figma "gift" cue).
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(reward
                              ? AnyShapeStyle(LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(meta.bg))
                        .frame(width: 40, height: 40)
                    Icon(meta.icon, size: 18, color: reward ? Nuru.navy : meta.fg)
                }
                if reward {
                    Icon(.sparkles, size: 9, color: Nuru.gold)
                        .frame(width: 16, height: 16)
                        .background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: 4, y: -4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
                    Text(titleFor(n)).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(ago(n.sentAt ?? n.scheduledFor)).font(.nMicro).foregroundStyle(Nuru.faint)
                }
                if let b = bodyFor(n) { Text(b).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2) }
                if reward && n.isUnread {
                    HStack(spacing: 4) {
                        Icon(.gift, size: 10, color: Color(hex: 0x9A7A2A))
                        Text("Tap to open your gift").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Nuru.gold.opacity(0.10), in: Capsule())
                    .padding(.top, 4)
                }
            }
            if n.isUnread { Circle().fill(Nuru.gold).frame(width: 8, height: 8).padding(.top, 6) }
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.md)
        .background(n.isUnread ? Nuru.white : .clear)
        .overlay(alignment: .leading) {
            // Figma: unread rows carry a gold accent bar on the leading edge.
            if n.isUnread {
                UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    .fill(Nuru.gold).frame(width: 4).padding(.vertical, 8)
            }
        }
    }

    /// Shimmering placeholder row matching the notification anatomy (first load).
    private var skeletonRow: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            RoundedRectangle(cornerRadius: 12).fill(Nuru.surface).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 150, height: 11)
                RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(maxWidth: .infinity).frame(height: 9)
            }
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.md)
        .nuruShimmer()
    }

    private var emptyState: some View {
        VStack(spacing: Nuru.S.sm) {
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.10)).frame(width: 56, height: 56)
                Icon(.sparkles, size: 24, color: Nuru.gold)
            }
            Text("You're all caught up").font(.nHeading).foregroundStyle(Nuru.ink)
            Text("New encouragement, reflections, and event reminders will land here.")
                .font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xxl).padding(.horizontal, Nuru.S.xl)
        .gentleEntrance()
    }

    // MARK: template mapping (port of metaFor/titleFor/bodyFor)

    // Figma CATEGORY_TONE — info / success / warning / security. Reward templates
    // (badge/certificate/level) override the tile with the gold gradient above.
    struct Meta { let icon: Lucide; let bg, fg: Color }
    fileprivate func metaFor(_ t: String) -> Meta {
        if t.hasPrefix("reflection") { return Meta(icon: .messageSquareText, bg: Color(hex: 0xFEF3C7), fg: Color(hex: 0xD97706)) }   // warning
        if t.hasPrefix("level") { return Meta(icon: .trendingUp, bg: Color(hex: 0xDCFCE7), fg: Color(hex: 0x16A34A)) }               // success
        if t.hasPrefix("certificate") { return Meta(icon: .award, bg: Color(hex: 0xDCFCE7), fg: Color(hex: 0x16A34A)) }              // success
        if t.hasPrefix("badge") { return Meta(icon: .badgeCheck, bg: Color(hex: 0xDCFCE7), fg: Color(hex: 0x16A34A)) }               // success
        if t.hasPrefix("event") { return Meta(icon: .calendarDays, bg: Color(hex: 0xE0F2FE), fg: Color(hex: 0x0EA5E9)) }             // info
        if t.hasPrefix("announcement") { return Meta(icon: .megaphone, bg: Color(hex: 0xE0F2FE), fg: Color(hex: 0x0EA5E9)) }         // info
        return Meta(icon: .settings, bg: Color(hex: 0xE2E8F0), fg: Color(hex: 0x475569))                                             // security/system
    }

    private let titles: [String: String] = [
        "reengage": "We miss you", "level_completed": "Level complete!", "badge_awarded": "New badge earned",
        "certificate_issued": "Certificate ready", "giving_receipt": "Giving receipt",
        "event_reminder_24h": "Event tomorrow", "event_reminder_1h": "Event starting soon",
        "reflection_approved": "Reflection approved", "reflection_returned": "Reflection returned",
        "reflection_deferred": "Reflection received",
    ]
    private func titleFor(_ n: NotificationRow) -> String {
        if let t = n.payload?.title, !t.isEmpty { return t }
        if let t = titles[n.template] { return t }
        return n.template.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalizingFirst()
    }
    private func bodyFor(_ n: NotificationRow) -> String? {
        if let b = n.payload?.body, !b.isEmpty { return b }
        if let f = n.payload?.feedback, !f.isEmpty { return f }
        let t = n.template
        if t.hasPrefix("reflection_approved") { return "Your discipler approved your reflection — well done." }
        if t.hasPrefix("reflection_returned") { return "Your discipler returned your reflection for another look." }
        if t.hasPrefix("reflection") { return "Your discipler has reviewed your reflection." }
        if t.hasPrefix("level_completed") { return n.payload?.levelNumber.map { "You've completed Level \($0). Keep pressing on!" } ?? "You've completed a level. Keep pressing on!" }
        if t.hasPrefix("badge") { return n.payload?.name.map { "You earned the \"\($0)\" badge." } ?? "You earned a new badge — well done!" }
        if t.hasPrefix("certificate") { return "Your certificate is ready to view and share." }
        if t.hasPrefix("event_reminder_24h") { return "Your event is coming up tomorrow." }
        if t.hasPrefix("event_reminder_1h") { return "Your event starts in about an hour." }
        if t.hasPrefix("event") { return "You have an upcoming gathering." }
        if t.hasPrefix("giving") { return "Thank you for giving — your receipt is ready." }
        if t == "reengage" { return "We've missed you — pick up your journey where you left off." }
        return nil
    }
    private func ago(_ iso: String) -> String { timeAgo(iso) }
}

private extension String {
    func capitalizingFirst() -> String { isEmpty ? self : prefix(1).uppercased() + dropFirst() }
}

// MARK: - Read-and-dismiss popup (notifications with no in-app destination)
// Not a flat message box: it greets the member BY NAME, carries the
// notification, shows their live quick stats (streak · level · plan), and ends
// with a word of encouragement + a gold door back onto the journey.

private struct NotificationDetailSheet: View {
    let meta: NotificationsView.Meta
    let reward: Bool
    let template: String
    let title: String
    let bodyText: String?
    let when: String
    let onDismiss: () -> Void

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @State private var streak: Int?
    @State private var activeLevel: PathwayLevel?
    @State private var plan: ReadingPlanRow?

    private var firstName: String {
        (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend"
    }
    private var greeting: String {
        if Calendar.current.component(.weekday, from: Date()) == 1 { return "Happy Lord's Day" }
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }
    /// The keep-going word, tuned to what the notification is about.
    private var nudge: String {
        if template.hasPrefix("nudge") || template.contains("miss") {
            return "The road is still yours, \(firstName). One small step today — a verse, a prayer, a page — and you're walking again."
        }
        if reward { return "God is faithful — and so were you. Keep walking; there's more ahead." }
        return "Every step counts, \(firstName). Keep going — God isn't finished with you."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Personal greeting first — this popup speaks TO the member.
            Text("\(greeting), \(firstName).")
                .font(.fraunces(22, .medium)).kerning(-0.4).foregroundStyle(Nuru.navy)

            // The notification itself.
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(reward
                              ? AnyShapeStyle(LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(meta.bg))
                        .frame(width: 44, height: 44)
                    Icon(meta.icon, size: 19, color: reward ? Nuru.navy : meta.fg)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Text(when).font(.nMicro).foregroundStyle(Nuru.faint)
                    }
                    if let b = bodyText, !b.isEmpty {
                        Text(b).font(.inter(13)).foregroundStyle(Nuru.muted).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(14)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .padding(.top, 14)

            // Quick stats — where the member actually stands, live from the server.
            if streak != nil || activeLevel != nil || plan != nil {
                HStack(spacing: 8) {
                    if let s = streak {
                        statChip(icon: .flame, tint: Color(hex: 0xB4530A), bg: Color(hex: 0xFFF4DA),
                                 label: s > 0 ? "\(s) days with God" : "Begin today")
                    }
                    if let a = activeLevel {
                        statChip(icon: .bookOpen, tint: Nuru.navy, bg: Nuru.tintBlue,
                                 label: "Level \(a.levelNumber) · \(a.completedModules)/\(a.totalModules)")
                    }
                    if let p = plan {
                        statChip(icon: .bookMarked, tint: Color(hex: 0x6366F1), bg: Color(hex: 0xEEF2FF),
                                 label: "Day \(p.currentDay ?? 1) of \(p.dayCount)")
                    }
                }
                .padding(.top, 14)
                .transition(.opacity)
            }

            // The word that sends them on.
            Text(nudge)
                .font(.fraunces(14.5, .regular)).italic()
                .foregroundStyle(Color(hex: 0x3A4A5F)).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)

            Spacer(minLength: 16)
            Button {
                Haptics.tap()
                onDismiss()
                if let a = activeLevel { tabs.openPathway(.level(a.levelNumber)) }
                else { tabs.selected = .pathway }
            } label: {
                HStack(spacing: 8) {
                    Icon(.arrowRight, size: 15, color: Nuru.navy)
                    Text("Continue my journey").font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            Button {
                Haptics.tap()
                onDismiss()
            } label: {
                Text("Dismiss").font(.inter(13, .semibold)).foregroundStyle(Nuru.muted)
                    .frame(maxWidth: .infinity, minHeight: 40)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(20)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Nuru.paper)
        .animation(.easeInOut(duration: 0.25), value: streak == nil)
        // Live stats — best-effort, in parallel; chips appear as data lands.
        .task {
            async let ach = try? MemberAPI.achievements()
            async let pw = try? MemberAPI.pathway()
            async let pl = try? MemberAPI.plans()
            streak = (await ach)?.streak.current
            if let p = await pw {
                activeLevel = p.levels.first { $0.status == .active }
                    ?? p.levels.first { $0.levelNumber == p.currentLevel }
                    ?? p.levels.first
            }
            plan = (await pl)?.first { $0.enrolled && $0.completedAt == nil }
        }
    }

    private func statChip(icon: Lucide, tint: Color, bg: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 12, color: tint)
            Text(label).font(.inter(11, .bold)).foregroundStyle(tint)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(bg, in: Capsule())
    }
}
