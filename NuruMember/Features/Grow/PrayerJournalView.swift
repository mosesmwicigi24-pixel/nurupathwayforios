// Prayer Journal — the native port of screens/PrayerJournalScreen.tsx. A private
// list of prayers the member can add, edit, mark answered, and delete. Entries
// are user-scoped server-side; writes are idempotent on entry_id. There is no
// prayer-score endpoint, so the score is computed client-side from the entries.
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
        // optimistic local apply + cache mirror
        if let i = entries.firstIndex(where: { $0.entryId == entryId }) { entries[i] = entry }
        else { entries.insert(entry, at: 0) }
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
        entries.removeAll { $0.entryId == e.entryId }
        await cacheAll(entries)
        await sync.enqueue(domain: domain, op: "delete", payload: ["entry_id": AnyCodable(e.entryId)])
    }

    // MARK: encrypted-cache mirror (round-trips via the DTO's own keys)

    private func cacheAll(_ list: [PrayerEntry]) async {
        let rows = list.compactMap { e -> (id: String, body: Data)? in
            (try? JSONEncoder().encode(e)).map { (e.entryId, $0) }
        }
        await sync.store.cacheReplace(domain: domain, rows: rows)
    }

    private func cached() async -> [PrayerEntry] {
        await sync.store.cachedRows(domain: domain)
            .compactMap { try? JSONDecoder().decode(PrayerEntry.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: Computed prayer score (no endpoint) — grows as you pray and journal.
    var answeredCount: Int { entries.filter(\.isAnswered).count }
    var score: Int { min(entries.count * 8 + answeredCount * 6, 100) }
    var band: String {
        switch score {
        case ..<25: return "Just beginning"
        case ..<50: return "Growing"
        case ..<75: return "Faithful"
        default:    return "Devoted"
        }
    }
}

struct PrayerJournalView: View {
    @StateObject private var vm = PrayerJournalViewModel()
    @State private var editing: PrayerDraft?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            Nuru.paper.ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    LoadStateView(loading: vm.loading && vm.entries.isEmpty,
                                  isEmpty: false, error: vm.error,
                                  emptyText: "", retry: { Task { await vm.load() } }) {
                        VStack(spacing: Nuru.S.base) {
                            scoreCard
                            PButton(title: "New prayer", variant: .gold) { editing = PrayerDraft() }
                            if vm.entries.isEmpty {
                                emptyState
                            } else {
                                ForEach(vm.entries) { e in
                                    PrayerCard(entry: e,
                                               toggle: { Task { await vm.toggleAnswered(e) } },
                                               edit: { editing = PrayerDraft(entry: e) },
                                               remove: { Task { await vm.delete(e) } })
                                }
                            }
                        }
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, Nuru.S.base)
                        .padding(.bottom, Nuru.tabBarSpace)
                    }
                }
            }
            .refreshable { await vm.load() }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.entries.isEmpty { await vm.load() } }
        .sheet(item: $editing) { draft in
            PrayerEditor(draft: draft) { title, body, answered in
                Task { await vm.upsert(entryId: draft.entryId, title: title, body: body, answered: answered) }
            }
        }
    }

    // MARK: Navy header

    private var header: some View {
        HStack(alignment: .center, spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.onNavy)
                    .frame(width: 40, height: 40)
                    .background(Nuru.navyDeep, in: Circle())
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Prayer journal")
                    .font(.fraunces(22, .semibold)).foregroundStyle(Nuru.onNavy)
                Text("Only you can read this — always.")
                    .font(.nMicro).foregroundStyle(Nuru.onNavyDim)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 58)
        .padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    // MARK: Prayer score card

    private var scoreCard: some View {
        Card(padding: Nuru.S.base) {
            HStack(alignment: .center, spacing: Nuru.S.base) {
                ScoreRing(score: vm.score)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PRAYER SCORE")
                        .font(.inter(11, .semibold)).kerning(1.2)
                        .foregroundStyle(Nuru.gold)
                    Text(vm.band)
                        .font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                    Text("Grows as you pray and journal — private to you")
                        .font(.nCaption).foregroundStyle(Nuru.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        Card {
            VStack(spacing: Nuru.S.sm) {
                Icon(.handHeart, size: 28, color: Nuru.gold)
                Text("No prayers yet")
                    .font(.nHeading).foregroundStyle(Nuru.ink)
                Text("Tap “New prayer” to write your first one. Only you can read it.")
                    .font(.nCaption).foregroundStyle(Nuru.muted)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Nuru.S.base)
        }
    }
}

/// The gold progress ring on the left of the score card: "{score}/100" stacked.
private struct ScoreRing: View {
    let score: Int
    var body: some View {
        ZStack {
            Circle().stroke(Nuru.goldTint, lineWidth: 4)
            Circle()
                .trim(from: 0, to: CGFloat(score) / 100)
                .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(score)").font(.fraunces(22, .semibold)).foregroundStyle(Nuru.ink)
                Text("/100").font(.inter(9, .medium)).foregroundStyle(Nuru.faint)
            }
        }
        .frame(width: 64, height: 64)
    }
}

/// A new-or-existing prayer being edited in the sheet.
struct PrayerDraft: Identifiable {
    let entryId: String
    var title: String
    var body: String
    var answered: Bool
    var id: String { entryId }

    init() { entryId = UUID().uuidString; title = ""; body = ""; answered = false }
    init(entry: PrayerEntry) {
        entryId = entry.entryId; title = entry.title ?? ""; body = entry.body; answered = entry.isAnswered
    }
}

private struct PrayerCard: View {
    let entry: PrayerEntry
    let toggle: () -> Void
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        Card(padding: Nuru.S.base) {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(alignment: .firstTextBaseline) {
                    Text(entry.title?.isEmpty == false ? entry.title! : "Prayer")
                        .font(.inter(16, .bold)).foregroundStyle(Nuru.ink)
                    Spacer(minLength: Nuru.S.sm)
                    Text(prayerDate)
                        .font(.nMicro).foregroundStyle(Nuru.gold)
                }
                Text(entry.body)
                    .font(.nBody).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.isAnswered, let note = entry.answeredNote, !note.isEmpty {
                    Text(note).font(.nCaption).foregroundStyle(Nuru.successText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: Nuru.S.base) {
                    Button(action: toggle) {
                        HStack(spacing: 4) {
                            if entry.isAnswered {
                                Icon(.checkCircle2, size: 13, color: Nuru.success)
                                Text("Answered").font(.inter(13, .semibold)).foregroundStyle(Nuru.success)
                            } else {
                                Text("Mark answered").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Button(action: edit) {
                        Text("Share to wall ›").font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    Button(role: .destructive, action: remove) {
                        Icon(.trash2, size: 15, color: Nuru.ink300)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
    }

    private var prayerDate: String {
        guard let date = ISO8601DateFormatter.nuru.date(from: entry.createdAt)
                ?? ISO8601DateFormatter().date(from: entry.createdAt) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"
        return f.string(from: date)
    }
}

private struct PrayerEditor: View {
    @State var draft: PrayerDraft
    let onSave: (_ title: String, _ body: String, _ answered: Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Title (optional)") { TextField("Title", text: $draft.title) }
                Section("Prayer") {
                    TextField("What are you praying for?", text: $draft.body, axis: .vertical).lineLimit(3...10)
                }
                Section { Toggle("Answered", isOn: $draft.answered) }
            }
            .navigationTitle(draft.body.isEmpty ? "New prayer" : "Edit prayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(draft.title, draft.body, draft.answered); dismiss()
                    }
                    .disabled(draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
