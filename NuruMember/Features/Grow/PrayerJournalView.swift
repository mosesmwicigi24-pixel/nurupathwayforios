// Prayer Journal — the native port of screens/PrayerJournalScreen.tsx. A private
// list of prayers the member can add, edit, mark answered, and delete. Entries
// are user-scoped server-side; writes are idempotent on entry_id.
import SwiftUI

@MainActor
final class PrayerJournalViewModel: ObservableObject {
    @Published var entries: [PrayerEntry] = []
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { entries = try await MemberAPI.prayers() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your journal." }
        loading = false
    }

    func upsert(entryId: String, title: String, body: String, answered: Bool) async {
        try? await MemberAPI.upsertPrayer(entryId: entryId, body: body,
                                          title: title.isEmpty ? nil : title, isAnswered: answered)
        await load()
    }

    func toggleAnswered(_ e: PrayerEntry) async {
        try? await MemberAPI.upsertPrayer(entryId: e.entryId, body: e.body,
                                          title: e.title, isAnswered: !e.isAnswered)
        await load()
    }

    func delete(_ e: PrayerEntry) async {
        try? await MemberAPI.deletePrayer(e.entryId)
        await load()
    }
}

struct PrayerJournalView: View {
    @StateObject private var vm = PrayerJournalViewModel()
    @State private var editing: PrayerDraft?

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.entries.isEmpty,
                          isEmpty: vm.entries.isEmpty, error: vm.error,
                          emptyText: "No prayers yet. Tap + to add one.", retry: { Task { await vm.load() } }) {
                ScrollView {
                    VStack(spacing: Nuru.S.md) {
                        ForEach(vm.entries) { e in
                            PrayerCard(entry: e,
                                       toggle: { Task { await vm.toggleAnswered(e) } },
                                       edit: { editing = PrayerDraft(entry: e) },
                                       remove: { Task { await vm.delete(e) } })
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("Prayer Journal")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = PrayerDraft() } label: { Image(systemName: "plus") }
            }
        }
        .task { if vm.entries.isEmpty { await vm.load() } }
        .sheet(item: $editing) { draft in
            PrayerEditor(draft: draft) { title, body, answered in
                Task { await vm.upsert(entryId: draft.entryId, title: title, body: body, answered: answered) }
            }
        }
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
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                HStack {
                    if let title = entry.title, !title.isEmpty {
                        Text(title).font(.nHeading).foregroundStyle(Nuru.ink)
                    }
                    Spacer()
                    if entry.isAnswered {
                        Text("Answered").font(.nMicro).foregroundStyle(Nuru.successText)
                            .padding(.horizontal, Nuru.S.sm).padding(.vertical, 3)
                            .background(Nuru.successBg, in: Capsule())
                    }
                }
                Text(entry.body).font(.nBody).foregroundStyle(Nuru.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Nuru.S.base) {
                    Button(entry.isAnswered ? "Mark unanswered" : "Mark answered", action: toggle)
                        .font(.nCaption).foregroundStyle(Nuru.gold)
                    Button("Edit", action: edit).font(.nCaption).foregroundStyle(Nuru.muted)
                    Spacer()
                    Button(role: .destructive, action: remove) {
                        Image(systemName: "trash").font(.system(size: 13))
                    }.foregroundStyle(Nuru.danger)
                }
                .padding(.top, Nuru.S.xs)
            }
        }
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
