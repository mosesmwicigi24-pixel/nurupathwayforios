// Prayer Journal — the native port of the UPDATED Figma PrayerJournalScreen.
// A private list of prayers the member can add, edit, mark answered, and delete.
// Entries are user-scoped server-side; writes are idempotent on entry_id.
//
// Data honesty vs the Figma comp: PrayerEntry (/me/prayers) carries only
// title/body/answered/notes/dates, so the comp's social layer (category tag,
// interceding counts, loves, comments, Love/Comment row) has no backing
// fields and is omitted — the card keeps the design's layout language with the
// real actions (mark answered / edit / delete) instead. Share IS real now:
// POST /me/prayers/{id}/share-to-wall copies an entry onto the congregation's
// public prayer wall (idempotent server-side), behind a confirmation. The navy
// "this week" card is driven from real entry created-at days: distinct days
// journaled this week, the current daily journaling streak, and live
// active / this-week / answered counts.
import SwiftUI

@MainActor
final class PrayerJournalViewModel: ObservableObject {
    @Published var entries: [PrayerEntry] = []
    @Published var loading = true
    @Published var error: String?

    // Offline-first (§1.7): reads come from the encrypted cache first (instant,
    // works offline), then refresh from the network; writes apply optimistically
    // and go through the durable mutation queue (idempotent on entry_id).
    private let sync = SyncCoordinator.shared
    private let domain = "prayer_entries"

    func load() async {
        error = nil
        // 1) instant: last-known entries from the encrypted cache
        let cachedList = await cached()
        if !cachedList.isEmpty { entries = cachedList; loading = false }
        // 2) refresh from the server when reachable; mirror into the cache
        if let fresh = try? await MemberAPI.prayers() {
            entries = fresh
            await cacheAll(fresh)
        } else if cachedList.isEmpty {
            error = "You're offline — your journal will load when you reconnect."
        }
        loading = false
    }

    func upsert(entryId: String, title: String, body: String, answered: Bool) async {
        let now = ISO8601DateFormatter().string(from: Date())
        let existing = entries.first { $0.entryId == entryId }
        let entry = PrayerEntry(
            entryId: entryId, title: title.isEmpty ? nil : title, body: body, isAnswered: answered,
            answeredNote: existing?.answeredNote, answeredAt: answered ? (existing?.answeredAt ?? now) : nil,
            createdAt: existing?.createdAt ?? now, updatedAt: now)
        // optimistic local apply + cache mirror (animated so cards settle, not snap)
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            if let i = entries.firstIndex(where: { $0.entryId == entryId }) { entries[i] = entry }
            else { entries.insert(entry, at: 0) }
        }
        await cacheAll(entries)
        // durable, idempotent server write (LWW on updated_at)
        await sync.enqueue(domain: domain, op: "upsert", payload: [
            "entry_id": AnyCodable(entryId),
            "title": AnyCodable(title.isEmpty ? nil : title),
            "body": AnyCodable(body),
            "is_answered": AnyCodable(answered),
            "updated_at": AnyCodable(now),
        ])
    }

    func toggleAnswered(_ e: PrayerEntry) async {
        await upsert(entryId: e.entryId, title: e.title ?? "", body: e.body, answered: !e.isAnswered)
    }

    func delete(_ e: PrayerEntry) async {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
            entries.removeAll { $0.entryId == e.entryId }
        }
        await cacheAll(entries)
        await sync.enqueue(domain: domain, op: "delete", payload: ["entry_id": AnyCodable(e.entryId)])
    }

    // MARK: Share to the public prayer wall (online-only — it's a server-side
    // copy into another member-visible surface, so it is NOT queued offline).
    // The server is idempotent: re-sharing returns the existing wall post, so
    // "already shared" simply succeeds.

    /// Entry ids shared during this session — drives the "On the wall 🙏" state.
    @Published var sharedToWall: Set<String> = []
    @Published var shareError: String?

    func shareToWall(_ e: PrayerEntry) async {
        do {
            _ = try await MemberAPI.sharePrayerToWall(e.entryId)
            Haptics.success()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                _ = sharedToWall.insert(e.entryId)
            }
            // Light celebration (no confetti — the wall-compose idiom this
            // mirrors) once the private prayer is confirmed public.
            CelebrationCenter.shared.fire(
                key: "prayer-share-\(e.entryId)",
                title: "Shared to Corporate Prayer",
                subtitle: "Your cell is standing with you 🙏",
                confetti: false)
        } catch {
            Haptics.error()
            let api = error as? APIError
            if case .http(let status, _, _, _)? = api, status == 404 {
                // Offline-created entries live in the mutation queue until the
                // next sync — the server can't share what it hasn't seen yet.
                shareError = "This prayer hasn't finished syncing yet. Give it a moment and try again."
            } else if api?.isNetwork == true {
                shareError = "You're offline — sharing to the wall needs a connection."
            } else {
                shareError = api?.errorDescription ?? "Couldn't share this prayer right now. Try again."
            }
        }
    }

    // MARK: encrypted-cache mirror (round-trips via the DTO's own keys)

    private func cacheAll(_ list: [PrayerEntry]) async {
        let rows = list.compactMap { e -> (id: String, body: Data)? in
            (try? JSONEncoder.nuruSnake.encode(e)).map { (e.entryId, $0) }
        }
        await sync.store.cacheReplace(domain: domain, rows: rows)
    }

    private func cached() async -> [PrayerEntry] {
        await sync.store.cachedRows(domain: domain)
            .compactMap { try? JSONDecoder.nuruSnake.decode(PrayerEntry.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Derived stats — all computed from real entry timestamps (no endpoint).

    var active: [PrayerEntry] { entries.filter { !$0.isAnswered } }
    var answered: [PrayerEntry] { entries.filter(\.isAnswered) }

    /// Start-of-day for every day the member wrote an entry.
    private var journaledDays: Set<Date> {
        let cal = Calendar.current
        return Set(entries.compactMap { prayerDate($0.createdAt).map(cal.startOfDay(for:)) })
    }

    /// Distinct days with at least one entry in the last 7 days (incl. today).
    var daysJournaledThisWeek: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let days = journaledDays
        return (0..<7).reduce(0) { acc, off in
            guard let d = cal.date(byAdding: .day, value: -off, to: today) else { return acc }
            return acc + (days.contains(d) ? 1 : 0)
        }
    }

    /// Entries written in the last 7 days.
    var thisWeekCount: Int {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: Date())) else { return 0 }
        return entries.filter { (prayerDate($0.createdAt) ?? .distantPast) >= cutoff }.count
    }

    /// Consecutive days journaled, ending today (or yesterday if today is still open).
    var streak: Int {
        let cal = Calendar.current
        let days = journaledDays
        var cursor = cal.startOfDay(for: Date())
        if !days.contains(cursor) {
            guard let y = cal.date(byAdding: .day, value: -1, to: cursor), days.contains(y) else { return 0 }
            cursor = y
        }
        var n = 0
        while days.contains(cursor) {
            n += 1
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return n
    }
}

// MARK: - Date helpers (tolerate fractional-second and plain ISO stamps)

private func prayerDate(_ iso: String) -> Date? {
    ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
}

/// "today" / "2 days ago" / "1 week ago" / "Mar 12" — the comp's casual stamp.
private func relativeLabel(_ iso: String) -> String {
    guard let d = prayerDate(iso) else { return "" }
    let cal = Calendar.current
    let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day ?? 0
    switch days {
    case ..<1:  return "today"
    case 1:     return "1 day ago"
    case ..<7:  return "\(days) days ago"
    case ..<14: return "1 week ago"
    case ..<31: return "\(days / 7) weeks ago"
    default:    return shortDate(d)
    }
}

private func shortDate(_ d: Date) -> String {
    let f = DateFormatter(); f.dateFormat = "MMM d"
    return f.string(from: d)
}

// MARK: - Screen

private enum PrayerTab { case active, answered }

struct PrayerJournalView: View {
    /// True when hosted as the "Private Prayer" tab of PrayerRoomView, which
    /// supplies its own back button + title + segmented control — so this
    /// view drops its standalone header and offers a floating "+" instead of
    /// the one that normally lives in that header.
    var embedded: Bool = false
    @StateObject private var vm = PrayerJournalViewModel()
    @State private var editing: PrayerDraft?
    @State private var tab: PrayerTab = .active
    @State private var pendingDelete: PrayerEntry?
    @State private var pendingShare: PrayerEntry?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                if !embedded { header }
                // isEmpty gates only the error branch: an empty-but-loaded journal
                // falls through to the designed per-tab empty card below.
                LoadStateView(loading: vm.loading && vm.entries.isEmpty,
                              isEmpty: vm.error != nil && vm.entries.isEmpty,
                              error: vm.error, emptyText: "",
                              retry: { Task { await vm.load() } }) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: Nuru.S.base) {
                            PrayerPulseCard(streak: vm.streak,
                                            daysThisWeek: vm.daysJournaledThisWeek,
                                            activeCount: vm.active.count,
                                            weekCount: vm.thisWeekCount,
                                            answeredCount: vm.answered.count)
                                .gentleEntrance()
                            PrayerTabs(tab: $tab, activeCount: vm.active.count, answeredCount: vm.answered.count)
                                .gentleEntrance(delay: 0.05)
                            let list = tab == .active ? vm.active : vm.answered
                            if list.isEmpty {
                                EmptyPrayers(tab: tab)
                                // No cards yet → the New action still has a home.
                                Button { Haptics.tap(); editing = PrayerDraft() } label: {
                                    HStack(spacing: 6) {
                                        Icon(.plus, size: 14, color: .white)
                                        Text("New prayer").font(.inter(13, .bold)).foregroundStyle(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 13)
                                    .background(
                                        LinearGradient(colors: [Color(hex: 0xE0B85E), Color(hex: 0xC9A227)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: Capsule())
                                }
                                .buttonStyle(.pressable)
                                .padding(.top, Nuru.S.sm)
                            } else {
                                ForEach(Array(list.enumerated()), id: \.element.id) { idx, e in
                                    JournalCard(entry: e,
                                                shared: vm.sharedToWall.contains(e.entryId),
                                                toggle: { Task { await vm.toggleAnswered(e) } },
                                                edit: { Haptics.tap(); editing = PrayerDraft(entry: e) },
                                                share: { pendingShare = e },
                                                remove: { pendingDelete = e },
                                                compose: { editing = PrayerDraft() })
                                        .gentleEntrance(delay: 0.1 + min(Double(idx), 3) * 0.05)
                                }
                            }
                        }
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, embedded ? Nuru.S.lg : Nuru.S.base)
                        .padding(.bottom, Nuru.tabBarSpace)
                    }
                    .refreshable { await vm.load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            // Sharing publishes a private entry to the whole cell — confirm
            // first. (Attached to the inner VStack so it never collides with
            // the delete dialog on the outer ZStack.)
            .confirmationDialog(
                "Share to the prayer wall?",
                isPresented: Binding(get: { pendingShare != nil },
                                     set: { if !$0 { pendingShare = nil } }),
                titleVisibility: .visible
            ) {
                Button("Share to wall") {
                    if let e = pendingShare { Task { await vm.shareToWall(e) } }
                    pendingShare = nil
                }
                Button("Keep it private", role: .cancel) { pendingShare = nil }
            } message: {
                Text("Your cell will see this and pray with you.")
            }
            .alert("Couldn't share",
                   isPresented: Binding(get: { vm.shareError != nil },
                                        set: { if !$0 { vm.shareError = nil } })) {
                Button("OK", role: .cancel) { vm.shareError = nil }
            } message: {
                Text(vm.shareError ?? "")
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.entries.isEmpty { await vm.load() } }
        .sheet(item: $editing) { draft in
            PrayerComposerSheet(draft: draft) { title, body, answered in
                Task { await vm.upsert(entryId: draft.entryId, title: title, body: body, answered: answered) }
            }
        }
        // Deleting a prayer is irreversible — ask before letting it go.
        .confirmationDialog(
            "Delete this prayer?",
            isPresented: Binding(get: { pendingDelete != nil },
                                 set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete prayer", role: .destructive) {
                if let e = pendingDelete { Task { await vm.delete(e) } }
                pendingDelete = nil
            }
            Button("Keep it", role: .cancel) { pendingDelete = nil }
        } message: {
            Text("It will be removed from your journal on every device.")
        }
    }

    // Cream Figma ScreenShell header: back · tracked kicker · gold compose, serif title.
    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack(alignment: .center, spacing: Nuru.S.sm) {
                BackButton()
                Spacer(minLength: 0)
                Text("\(vm.active.count) ACTIVE · \(vm.answered.count) ANSWERED")
                    .font(.inter(11, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                    .lineLimit(1).minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Button { Haptics.tap(); editing = PrayerDraft() } label: {
                    Icon(.plus, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color(hex: 0xC9A227), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("New prayer")
            }
            Text("Prayer journal")
                .font(.fraunces(24, .semibold))
                .foregroundStyle(Nuru.navy)
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
                .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }
}

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Icon(.arrowLeft, size: 18, color: Nuru.navy)
                .frame(width: 40, height: 40)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Navy "this week" stats card (real data: journaled days, streak, counts)

private struct PrayerPulseCard: View {
    let streak: Int
    let daysThisWeek: Int
    let activeCount: Int
    let weekCount: Int
    let answeredCount: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    private let gold = Color(hex: 0xC9A227)

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack(alignment: .top, spacing: Nuru.S.sm) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Nuru.S.sm) {
                        Text("THIS WEEK")
                            .font(.inter(10, .bold)).tracking(2.2)
                            .foregroundStyle(gold)
                        if streak > 0 { streakChip }
                    }
                    Text("Your prayer rhythm")
                        .font(.fraunces(21, .medium))
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(gold.opacity(0.18))
                    .frame(width: 48, height: 48)
                    .overlay(Icon(.handHeart, size: 22, color: gold))
            }

            // Weekly goal bar — days journaled out of 7, honest to created-at data.
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Journaled \(daysThisWeek) of 7 days")
                        .font(.inter(10, .semibold))
                        .foregroundStyle(Color.white.opacity(0.7))
                    Spacer(minLength: Nuru.S.sm)
                    Text(daysThisWeek >= 7 ? "A full week 🙌" : "\(7 - daysThisWeek) to a full week 🙌")
                        .font(.inter(10, .semibold))
                        .foregroundStyle(gold)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.16))
                        Capsule()
                            .fill(LinearGradient(colors: [gold, Color(hex: 0xE6C068)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: grown ? geo.size.width * CGFloat(min(daysThisWeek, 7)) / 7 : 0)
                    }
                }
                .frame(height: 6)
            }

            HStack(spacing: Nuru.S.sm) {
                StatTile(value: activeCount, label: "active")
                StatTile(value: weekCount, label: "this week")
                StatTile(value: answeredCount, label: "answered")
            }
        }
        .padding(Nuru.S.base)
        .background(
            LinearGradient(colors: [Color(hex: 0x060F1C), Color(hex: 0x0A1628), Color(hex: 0x11365A)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x0A2540).opacity(0.35), radius: 14, x: 0, y: 8)
        .onAppear {
            if reduceMotion { grown = true; return }
            withAnimation(.easeOut(duration: 0.9)) { grown = true }
        }
    }

    private var streakChip: some View {
        HStack(spacing: 4) {
            Icon(.flame, size: 9, color: gold)
            Text("\(streak)-day streak").font(.inter(9, .bold)).foregroundStyle(gold)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Color.white.opacity(0.10), in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.15), lineWidth: 1))
    }
}

private struct StatTile: View {
    let value: Int
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)").font(.fraunces(18, .medium)).foregroundStyle(Color(hex: 0xC9A227))
            Text(label).font(.inter(9, .medium)).foregroundStyle(Color.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Nuru.S.sm)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Active / Answered segmented control

private struct PrayerTabs: View {
    @Binding var tab: PrayerTab
    let activeCount: Int
    let answeredCount: Int

    var body: some View {
        HStack(spacing: 4) {
            tabButton(.active, "Active", activeCount)
            tabButton(.answered, "Answered", answeredCount)
        }
        .padding(4)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        .nuruShadow(0.6)
    }

    private func tabButton(_ t: PrayerTab, _ label: String, _ count: Int) -> some View {
        let on = tab == t
        return Button {
            guard tab != t else { return }
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.2)) { tab = t }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.inter(11, .bold))
                    .foregroundStyle(on ? .white : Color(hex: 0x59667C))
                Text("\(count)")
                    .font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 18, minHeight: 16)
                    .background(on ? Color(hex: 0xC9A227) : Nuru.surface, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Nuru.S.sm)
            .background(on ? Nuru.navy : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Empty state (per tab)

private struct EmptyPrayers: View {
    let tab: PrayerTab
    var body: some View {
        Card {
            VStack(spacing: Nuru.S.sm) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Nuru.surface)
                    .frame(width: 48, height: 48)
                    .overlay(Icon(.handHeart, size: 20, color: Nuru.gold))
                Text(tab == .active ? "No active prayers yet" : "No answered prayers yet")
                    .font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                Text("Bring your requests before Him.")
                    .font(.nCardBody).foregroundStyle(Color(hex: 0x59667C))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Nuru.S.lg)
        }
    }
}

// MARK: - Prayer card

private struct JournalCard: View {
    let entry: PrayerEntry
    let shared: Bool
    let toggle: () -> Void
    let edit: () -> Void
    let share: () -> Void
    let remove: () -> Void
    let compose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: avatar disc + "You · 2 days ago"
            HStack(alignment: .center, spacing: Nuru.S.md) {
                Circle()
                    .fill(LinearGradient(colors: [Nuru.gold, Nuru.goldLo],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .overlay(Text("ME").font(.inter(12, .bold)).foregroundStyle(.white))
                    .shadow(color: Nuru.gold.opacity(0.4), radius: 6, x: 0, y: 4)
                HStack(spacing: 6) {
                    Text("You").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                    Text("·").font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                    Text(relativeLabel(entry.isAnswered ? (entry.answeredAt ?? entry.createdAt) : entry.createdAt))
                        .font(.nCardMeta).foregroundStyle(Color(hex: 0x74808F))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Nuru.S.base)
            .padding(.top, Nuru.S.base)

            // Serif title + body
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.title?.isEmpty == false ? entry.title! : "Prayer")
                    .font(.nRowTitle).foregroundStyle(Nuru.navy)
                Text(entry.body)
                    .font(.nCardBody).foregroundStyle(Color(hex: 0x3A4A5F))
                    .lineSpacing(4)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Nuru.S.base)
            .padding(.top, Nuru.S.md)

            if entry.isAnswered {
                answeredBanner
                    .padding(.horizontal, Nuru.S.base)
                    .padding(.top, Nuru.S.md)
                shareToCorporateButton
                    .padding(.horizontal, Nuru.S.base)
                    .padding(.top, Nuru.S.sm)
            } else {
                // One row, two halves: the quiet toggle and the gold bridge to
                // Corporate Prayer side by side — the card stays compact.
                HStack(spacing: Nuru.S.sm) {
                    markAnsweredButton
                    shareToCorporateButton
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.top, Nuru.S.md)
            }

            // Hairline + remaining row actions (design slot for Love/Comment).
            Rectangle().fill(Nuru.border).frame(height: 1).padding(.top, Nuru.S.md)
            // ONE home for every action: Edit · (Reopen) · Delete on the left,
            // and the standout gold "New prayer" on the same row — nothing
            // floats, nothing hides behind the tab bar.
            HStack(spacing: 0) {
                RowAction(icon: .pencil, label: "Edit", action: edit)
                if entry.isAnswered { RowAction(icon: .repeat, label: "Reopen", action: toggle) }
                RowAction(icon: .trash2, label: "Delete", action: remove)
                Spacer(minLength: 0)
                Button { Haptics.tap(); compose() } label: {
                    HStack(spacing: 5) {
                        Icon(.plus, size: 13, color: .white)
                        Text("New prayer").font(.inter(12, .bold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(
                        LinearGradient(colors: [Color(hex: 0xE0B85E), Color(hex: 0xC9A227)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: Capsule())
                    .shadow(color: Color(hex: 0xC9A227).opacity(0.35), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.pressable)
                .padding(.trailing, Nuru.S.sm)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    /// Green celebration banner for answered prayers (real: is_answered + answered_at/_note).
    private var answeredBanner: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Circle().fill(Color(hex: 0x16A34A))
                .frame(width: 28, height: 28)
                .overlay(Icon(.check, size: 13, color: .white))
            VStack(alignment: .leading, spacing: 1) {
                Text("Answered prayer 🎉")
                    .font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x15803D))
                Text(answeredSub)
                    .font(.inter(9, .medium)).foregroundStyle(Color(hex: 0x16A34A))
                if let note = entry.answeredNote, !note.isEmpty {
                    Text(note)
                        .font(.nCardMeta).foregroundStyle(Color(hex: 0x166534))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            LinearGradient(colors: [Color(hex: 0xDCFCE7), Color(hex: 0xBBF7D0)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var answeredSub: String {
        if let at = entry.answeredAt, let d = prayerDate(at) { return "He is faithful · \(shortDate(d))" }
        return "He is faithful"
    }

    /// Full-width gold-outline action (the comp's "I'm praying" slot → real toggle).
    private var markAnsweredButton: some View {
        Button {
            Haptics.success() // an answered prayer is the journal's best moment
            toggle()
        } label: {
            HStack(spacing: 6) {
                Icon(.checkCircle2, size: 13, color: Color(hex: 0x7A5A14))
                Text("Mark answered").font(.inter(12, .bold)).foregroundStyle(Color(hex: 0x7A5A14))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(hex: 0xC9A227).opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(hex: 0xC9A227).opacity(0.27), lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    /// Solid-gold "Share to Corporate Prayer" CTA, or the settled "On the
    /// wall" state once the server confirms the copy landed.
    private var shareToCorporateButton: some View {
        Group {
            if shared {
                HStack(spacing: 6) {
                    Icon(.handHeart, size: 15, color: Color(hex: 0x16A34A))
                    Text("On the wall 🙏").font(.inter(12, .bold)).foregroundStyle(Color(hex: 0x15803D))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    LinearGradient(colors: [Color(hex: 0xDCFCE7), Color(hex: 0xBBF7D0)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .scale(scale: 0.95)))
            } else {
                Button { Haptics.tap(); share() } label: {
                    HStack(spacing: 6) {
                        Icon(.share2, size: 14, color: Nuru.navyDeep)
                        Text("Share to Corporate").font(.inter(12, .bold)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(Nuru.navyDeep)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(hex: 0xC9A227), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: shared)
    }
}

private struct RowAction: View {
    let icon: Lucide
    let label: String
    let action: () -> Void
    var body: some View {
        Button { Haptics.tap(); action() } label: {
            HStack(spacing: 6) {
                Icon(icon, size: 15, color: Color(hex: 0x59667C))
                Text(label).font(.inter(10, .semibold)).foregroundStyle(Color(hex: 0x59667C))
            }
            .frame(maxWidth: .infinity, minHeight: 44) // proper thumb-sized target
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Compose / edit sheet

/// A new-or-existing prayer being edited in the sheet.
struct PrayerDraft: Identifiable {
    let entryId: String
    let isNew: Bool
    var title: String
    var body: String
    var answered: Bool
    var id: String { entryId }

    init() { entryId = UUID().uuidString; isNew = true; title = ""; body = ""; answered = false }
    init(entry: PrayerEntry) {
        entryId = entry.entryId; isNew = false
        title = entry.title ?? ""; body = entry.body; answered = entry.isAnswered
    }
}

private struct PrayerComposerSheet: View {
    @State var draft: PrayerDraft
    let onSave: (_ title: String, _ body: String, _ answered: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    private var bodyEmpty: Bool { draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text(draft.isNew ? "New prayer" : "Edit prayer")
                    .font(.fraunces(18, .medium)).foregroundStyle(Nuru.navy)
                Spacer(minLength: 0)
                Button { dismiss() } label: {
                    Circle().fill(Nuru.surface)
                        .frame(width: 32, height: 32)
                        .overlay(Icon(.x, size: 15, color: Nuru.navy))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            TextField("Title (e.g. Wisdom for the new role)", text: $draft.title)
                .font(.inter(14, .regular)).foregroundStyle(Nuru.navy)
                .padding(Nuru.S.md)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            TextField("What are you asking for?", text: $draft.body, axis: .vertical)
                .lineLimit(4...10)
                .font(.inter(14, .regular)).foregroundStyle(Nuru.navy)
                .padding(Nuru.S.md)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            HStack {
                Text("Answered").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                Spacer(minLength: 0)
                Toggle("", isOn: $draft.answered).labelsHidden().tint(Color(hex: 0xC9A227))
            }
            .padding(Nuru.S.md)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            Button {
                Haptics.action() // the "saved" confirmation you can feel
                onSave(draft.title, draft.body, draft.answered)
                dismiss()
            } label: {
                Text(draft.isNew ? "Save prayer" : "Save changes")
                    .font(.inter(14, .bold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(hex: 0xC9A227), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(bodyEmpty)
            .opacity(bodyEmpty ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.2), value: bodyEmpty)
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .background(Color.white)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
