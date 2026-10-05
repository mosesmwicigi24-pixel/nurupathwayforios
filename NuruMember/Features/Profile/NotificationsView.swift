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
    /// Optimistic read overrides — the page answers the tap INSTANTLY (the old
    /// flow waited a full network round-trip before anything moved, which read
    /// as "mark all read does nothing"). The server reload then confirms.
    @Published var locallyRead: Set<String> = []

    /// Marks still on their way to the server — the bells re-read the count
    /// only once they have landed.
    private var pendingMarks = 0
    /// The inbox has the server's count (a failed first load knows nothing
    /// to tell the bells).
    private var loaded = false

    func isUnread(_ n: NotificationRow) -> Bool {
        n.isUnread && !locallyRead.contains(n.notificationId)
    }

    func load() async {
        loading = true; error = nil
        let ticket = InboxBadge.shared.ticket()
        do {
            let r = try await MemberAPI.notifications()
            rows = r.rows; unread = r.unread; locallyRead = []; loaded = true
            InboxBadge.shared.land(r.unread, ticket: ticket)   // every bell's dot (§7.2 #4)
        }
        catch { self.error = NuruStateCopy.failureLine("Couldn't load notifications.", error) }
        loading = false
    }
    func markAll() async {
        withAnimation(.easeInOut(duration: 0.45)) {
            locallyRead = Set(rows.map(\.notificationId))
            unread = 0
        }
        InboxBadge.shared.set(0)
        pendingMarks += 1
        try? await MemberAPI.markNotificationsRead()
        pendingMarks -= 1
        await load()
    }
    func open(_ n: NotificationRow) async {
        guard isUnread(n) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            locallyRead.insert(n.notificationId)
            unread = max(0, unread - 1)
        }
        InboxBadge.shared.set(unread)
        pendingMarks += 1
        try? await MemberAPI.markNotificationsRead([n.notificationId])
        pendingMarks -= 1
        await InboxBadge.shared.refresh()   // the server's count, once it's read
    }

    /// The inbox closed (§7.2 #4): the bells take what it knows now, then —
    /// unless a mark is still on its way (it re-reads when it lands) — the
    /// server's own count.
    func closed() {
        if loaded { InboxBadge.shared.set(unread) }
        if pendingMarks == 0 { Task { await InboxBadge.shared.refresh() } }
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
        .onDisappear { vm.closed() }
        // A notice with nowhere to go: the notice itself, then Dismiss.
        .sheet(item: $detail) { n in
            NotificationDetailSheet(meta: metaFor(n.template),
                                    reward: Self.isReward(n.template),
                                    title: titleFor(n),
                                    bodyText: bodyFor(n),
                                    when: ago(n.sentAt ?? n.scheduledFor)) { detail = nil }
        }
    }

    // MARK: tap routing — every notification lands exactly where it points

    /// Wraps a row in its notice's route — the SAME decision a tapped banner
    /// gets (NoticeRouter, EXPERIENCE.md §7.2 #3). An announcement opens on
    /// this stack, so Back returns to the inbox; a Live opens its player (or
    /// "This Live has ended") over the inbox, which stays beneath it; every
    /// other route leaves the inbox for the tab that owns it; a notice with
    /// nowhere to go shows itself.
    @ViewBuilder private func rowLink(_ n: NotificationRow) -> some View {
        let route = NoticeRouter.route(NoticeTarget(n))
        switch route {
        case .announcement(let aid):
            NavigationLink(value: AppRoute.announcement(aid)) { row(n) }
                .buttonStyle(.pressableSubtle)
                .simultaneousGesture(TapGesture().onEnded { markRead(n) })
        case .itself:
            Button {
                markRead(n)
                Haptics.tap()
                detail = n
            } label: { row(n) }.buttonStyle(.pressableSubtle)
        case .live:
            Button {
                markRead(n); Haptics.tap()
                NoticeRouter.open(route, tabs: tabs)
            } label: { row(n) }.buttonStyle(.pressableSubtle)
        default:
            Button {
                markRead(n); Haptics.tap(); dismiss()
                NoticeRouter.open(route, tabs: tabs)
            } label: { row(n) }.buttonStyle(.pressableSubtle)
        }
    }

    private func markRead(_ n: NotificationRow) {
        if n.isUnread { Task { await vm.open(n) } }
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
                Icon(.chevronLeft, size: 22, color: Nuru.navy)
                    .frame(width: 40, height: 40).background(Nuru.mutedBg, in: Circle())
            }
            VStack(alignment: .leading, spacing: 0) {
                // The header as on Android (§8.2 #10): the serif title, one line.
                Text("Notifications").font(.nCardTitle).foregroundStyle(Nuru.ink)
                HStack(spacing: 6) {
                    Text(vm.unread > 0 ? "\(vm.unread) unread" : "All caught up ✨").font(.nCaption).foregroundStyle(Nuru.ink600)
                        .contentTransition(.numericText(value: Double(vm.unread)))
                        .animation(.easeInOut(duration: 0.25), value: vm.unread)
                    if rewardUnread > 0 {
                        HStack(spacing: 3) {
                            Icon(.gift, size: 14, color: Color(hex: 0x9A7A2A))
                            Text("\(rewardUnread) \(rewardUnread == 1 ? "gift" : "gifts")")
                                .font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Nuru.gold.opacity(0.12), in: Capsule())
                    }
                }
            }
            Spacer()
            // Only while something is unread (§7.2 #3, as Android): at zero
            // the line beside the title already says "All caught up", and a
            // disabled "All read" chip was a button that did nothing.
            if vm.unread > 0 {
                Button { Haptics.action(); Task { await vm.markAll() } } label: {
                    HStack(spacing: 4) {
                        // Figma's CheckCheck (double tick) — composed from two check glyphs.
                        ZStack {
                            Icon(.check, size: 14, color: Nuru.goldHi).offset(x: -3)
                            Icon(.check, size: 14, color: Nuru.goldHi).offset(x: 3)
                        }
                        .frame(width: 18)
                        Text("Mark all read")
                            .font(.inter(11, .bold))
                            .foregroundStyle(Nuru.goldHi)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Nuru.navy, in: Capsule())
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.unread == 0)
        // The bar already starts under the status bar (this page keeps the
        // safe area) — the old 54pt top padding counted it a second time and
        // left an empty white band above the header (§8.2 #10).
        .padding(.horizontal, Nuru.S.base).padding(.top, Nuru.S.base).padding(.bottom, Nuru.S.md)
        .background(Nuru.white)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .bottom)
    }

    /// Amber for what still waits, green for what's been received (owner's
    /// design, 2026-08-26): unread rows carry a GLOWING AMBER dot on a warm
    /// wash; read rows a LUMINOUS GREEN dot beside a double tick — the two
    /// states must contrast at a glance, before and after.
    private static let amber = Color(hex: 0xF59E0B)
    private static let lumGreen = Color(hex: 0x22C55E)

    @ViewBuilder private func statusCluster(unread: Bool) -> some View {
        if unread {
            ZStack {
                Circle().fill(Self.amber.opacity(0.22)).frame(width: 20, height: 20)
                Circle().fill(Self.amber).frame(width: 9, height: 9)
                    .shadow(color: Self.amber.opacity(0.9), radius: 4)
                    .shadow(color: Self.amber.opacity(0.45), radius: 9)
            }
        } else {
            HStack(spacing: 4) {
                Circle().fill(Self.lumGreen).frame(width: 7, height: 7)
                    .shadow(color: Self.lumGreen.opacity(0.8), radius: 3)
                ZStack {
                    Icon(.check, size: 14, color: Self.lumGreen).offset(x: -2.5)
                    Icon(.check, size: 14, color: Self.lumGreen).offset(x: 2.5)
                }
                .frame(width: 17)
            }
        }
    }

    private func row(_ n: NotificationRow) -> some View {
        let meta = metaFor(n.template)
        let reward = Self.isReward(n.template)
        let unread = vm.isUnread(n)
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
                    Icon(.sparkles, size: 14, color: Nuru.gold)
                        .frame(width: 16, height: 16)
                        .background(Color.white, in: Circle())
                        .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                        .offset(x: 4, y: -4)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
                    // A notice is a content row (§8.1 rule 3): the serif row
                    // title — semibold while unread, regular once read (as
                    // Android) — wrapping to two lines rather than cut (rule 9).
                    Text(titleFor(n))
                        .font(.fraunces(15, unread ? .semibold : .regular))
                        .foregroundStyle(unread ? Nuru.ink : Nuru.ink600)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Text(ago(n.sentAt ?? n.scheduledFor))
                        .font(.nMicro)
                        .foregroundStyle(unread ? Self.amber : Nuru.faint)
                }
                if let b = bodyFor(n) {
                    Text(b).font(.nCaption)
                        .foregroundStyle(unread ? Nuru.muted : Nuru.faint)
                        .lineLimit(2)
                }
                if reward && unread {
                    HStack(spacing: 4) {
                        Icon(.gift, size: 14, color: Color(hex: 0x9A7A2A))
                        Text("Tap to open your gift").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Nuru.gold.opacity(0.10), in: Capsule())
                    .padding(.top, 4)
                }
            }
            statusCluster(unread: unread).padding(.top, 4)
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.md)
        .background(unread ? Self.amber.opacity(0.07) : .clear)
        .overlay(alignment: .leading) {
            // Unread rows carry the amber accent bar on the leading edge.
            if unread {
                UnevenRoundedRectangle(bottomTrailingRadius: 3, topTrailingRadius: 3, style: .continuous)
                    .fill(Self.amber).frame(width: 4).padding(.vertical, 8)
            }
        }
        .opacity(unread ? 1 : 0.92)
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

    // One icon per notice family (NoticeFamily, §8.2 #14), each on a gold-tint
    // tile (§8.1 rule 7). The tiles used to be blue, green, amber and slate —
    // hues the grammar keeps for state (rule 1) — and a Live notice, or any
    // family the table didn't know, fell to the settings gear. Reward
    // templates (badge/certificate/level) keep the gold-gradient ceremony tile.
    struct Meta { let icon: Lucide; let bg, fg: Color }
    fileprivate func metaFor(_ t: String) -> Meta {
        Meta(icon: NoticeFamily.icon(t), bg: Nuru.goldChipBg, fg: Nuru.goldChipText)
    }

    private let titles: [String: String] = [
        "reengage": "We miss you", "level_completed": "Level complete!", "badge_awarded": "New badge earned",
        "certificate_issued": "Certificate ready", "giving_receipt": "Giving receipt",
        "event_reminder_24h": "Event tomorrow", "event_reminder_1h": "Event starting soon",
        "reflection_approved": "Reflection approved", "reflection_returned": "Reflection returned",
        "reflection_deferred": "Reflection received",
        "serve_request_approved": "You're on the team", "serve_request_declined": "About your request to serve",
        "department_post": "News from your department",
        // department_need_* take the server's words from GivingNotificationCopy.
    ]
    private func titleFor(_ n: NotificationRow) -> String {
        // Giving / Partners words first: on a pledge notice `payload.title`
        // is the pledge's name, not the notice's title.
        if let t = GivingNotificationCopy.title(template: n.template, payload: n.payload) { return t }
        if let t = n.payload?.title, !t.isEmpty { return t }
        if let t = titles[n.template] { return t }
        return n.template.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ").capitalizingFirst()
    }
    private func bodyFor(_ n: NotificationRow) -> String? {
        if let b = n.payload?.body, !b.isEmpty { return b }
        if let f = n.payload?.feedback, !f.isEmpty { return f }
        // A failed gift is not "your receipt is ready" (Giving Cycle 3).
        if let b = GivingNotificationCopy.body(template: n.template, payload: n.payload) { return b }
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

// MARK: - One icon per notice family (EXPERIENCE.md §8.2 #14)

/// A notice's icon says what it is about (§8.1 rule 7) — one Lucide glyph per
/// family of templates, the same table on both apps. Tried in order; the
/// first family that holds is the icon. Pure, so the tests pin it.
enum NoticeFamily {
    static func icon(_ template: String) -> Lucide {
        let t = template.lowercased()
        func any(_ prefixes: String...) -> Bool { prefixes.contains { t.hasPrefix($0) } }
        if any("badge") { return .badgeCheck }
        if any("certificate") { return .award }
        if any("level") { return .trendingUp }
        if any("reflection") { return .messageSquareText }
        if any("serve_request", "department") { return .heartHandshake }
        if any("giving", "pledge", "payment") { return .handHeart }
        if any("event") { return .calendarDays }
        if any("announcement") { return .megaphone }
        if any("live") { return .radio }                 // a Live: the broadcast mark, never a gear
        if any("chat") { return .messageCircle }
        if any("connection") { return .userPlus }
        if any("plan", "reading") { return .bookMarked }
        if any("module", "quiz", "exam") { return .bookOpen }
        if any("prayer", "verse", "devotional") { return .leaf }
        if any("sunday_letter") { return .mail }
        if any("streak") { return .flame }
        if any("cell") { return .users }
        if any("security", "login", "password", "system") { return .shield }
        return .bell
    }
}

// MARK: - The notice itself (a notice with no in-app destination)
// EXPERIENCE.md §7.1 rule 1: a notice with nowhere to go shows only itself —
// its title, its full words, when — and Dismiss. It used to greet the member
// by name, show their journey chips and offer "Continue my journey": a door
// to somewhere the notice never pointed. The sheet is as tall as the notice.

private struct NotificationDetailSheet: View {
    let meta: NotificationsView.Meta
    let reward: Bool
    let title: String
    let bodyText: String?
    let when: String
    let onDismiss: () -> Void

    /// The notice's own height, measured — the sheet fits it (a long notice
    /// scrolls inside a sheet that stops short of the top).
    @State private var contentHeight: CGFloat = 240

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(reward
                                  ? AnyShapeStyle(LinearGradient(colors: [Nuru.gold, Color(hex: 0xB6862F)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(meta.bg))
                            .frame(width: 44, height: 44)
                        Icon(meta.icon, size: 19, color: reward ? Nuru.navy : meta.fg)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(title).font(.nRowTitle).foregroundStyle(Nuru.ink)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 0)
                            Text(when).font(.nMicro).foregroundStyle(Nuru.faint)
                        }
                        if let b = bodyText, !b.isEmpty {
                            Text(b).font(.inter(14)).foregroundStyle(Nuru.muted).lineSpacing(4)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Button {
                    Haptics.tap()
                    onDismiss()
                } label: {
                    Text("Dismiss").font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .padding(.top, 22)
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 16)
            .background(GeometryReader { g in
                Color.clear
                    .onAppear { contentHeight = g.size.height }
                    .onChange(of: g.size.height) { _, h in contentHeight = h }
            })
        }
        .scrollBounceBehavior(.basedOnSize)
        .presentationDetents([.height(min(contentHeight, Self.maxHeight))])
        .presentationDragIndicator(.visible)
        .presentationBackground(Nuru.paper)
    }

    private static var maxHeight: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return (scene?.screen.bounds.height ?? 800) * 0.85
    }
}
