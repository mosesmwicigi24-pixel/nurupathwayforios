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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    if vm.loading && vm.rows.isEmpty {
                        ProgressView().padding(.top, Nuru.S.xl)
                    } else if vm.rows.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.rows) { n in
                            Button { Task { await vm.open(n) } } label: { row(n) }.buttonStyle(.plain)
                            Divider().padding(.leading, 68)
                        }
                    }
                }
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .refreshable { await vm.load() }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.rows.isEmpty { await vm.load() } }
    }

    private var topBar: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.chevronLeft, size: 20, color: Nuru.navy)
                    .frame(width: 40, height: 40).background(Nuru.mutedBg, in: Circle())
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Notifications").font(.nHeading).foregroundStyle(Nuru.ink)
                Text(vm.unread > 0 ? "\(vm.unread) unread" : "All caught up").font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Spacer()
            Button { Task { await vm.markAll() } } label: {
                HStack(spacing: 4) {
                    Icon(.check, size: 14, color: Nuru.gold)
                    Text("Mark all read").font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                }
                .padding(.horizontal, 12).padding(.vertical, 7).background(Nuru.navy, in: Capsule())
            }
            .disabled(vm.unread == 0).opacity(vm.unread == 0 ? 0.4 : 1)
        }
        .padding(.horizontal, Nuru.S.base).padding(.top, 54).padding(.bottom, Nuru.S.md)
        .background(Nuru.white)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .bottom)
    }

    private func row(_ n: NotificationRow) -> some View {
        let meta = metaFor(n.template)
        return HStack(alignment: .top, spacing: Nuru.S.md) {
            ZStack { RoundedRectangle(cornerRadius: 12).fill(meta.bg).frame(width: 40, height: 40); Icon(meta.icon, size: 18, color: meta.fg) }
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
                    Text(titleFor(n)).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    Spacer(minLength: 0)
                    Text(ago(n.sentAt ?? n.scheduledFor)).font(.nMicro).foregroundStyle(Nuru.faint)
                }
                if let b = bodyFor(n) { Text(b).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2) }
            }
            if n.isUnread { Circle().fill(Nuru.gold).frame(width: 8, height: 8).padding(.top, 6) }
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.md)
        .background(n.isUnread ? Nuru.white : .clear)
    }

    private var emptyState: some View {
        VStack(spacing: Nuru.S.sm) {
            Icon(.sparkles, size: 24, color: Nuru.gold)
            Text("You're all caught up").font(.nHeading).foregroundStyle(Nuru.ink)
            Text("New encouragement, reflections, and event reminders will land here.")
                .font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xxl).padding(.horizontal, Nuru.S.xl)
    }

    // MARK: template mapping (port of metaFor/titleFor/bodyFor)

    private struct Meta { let icon: Lucide; let bg, fg: Color }
    private func metaFor(_ t: String) -> Meta {
        if t.hasPrefix("reflection") { return Meta(icon: .messageSquareText, bg: Color(hex: 0xFEF3C7), fg: Color(hex: 0x92400E)) }
        if t.hasPrefix("level") { return Meta(icon: .sparkles, bg: Nuru.successBg, fg: Nuru.successText) }
        if t.hasPrefix("certificate") { return Meta(icon: .badgeCheck, bg: Color(hex: 0xFFF8DD), fg: Nuru.goldLo) }
        if t.hasPrefix("badge") { return Meta(icon: .badgeCheck, bg: Color(hex: 0xE0E7FF), fg: Color(hex: 0x4338CA)) }
        if t.hasPrefix("event") { return Meta(icon: .calendarDays, bg: Nuru.tintBlue, fg: Nuru.navy) }
        if t.hasPrefix("announcement") { return Meta(icon: .megaphone, bg: Nuru.tintBlue, fg: Nuru.navy) }
        return Meta(icon: .bell, bg: Nuru.mutedBg, fg: Nuru.ink600)
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
