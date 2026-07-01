// Verse Library — the native port of screens/VerseLibraryScreen.tsx. The member's
// saved verses: add a reference (+ optional text/note), and remove. Writes are
// idempotent on saved_verse_id.
import SwiftUI

@MainActor
final class VerseLibraryViewModel: ObservableObject {
    @Published var verses: [SavedVerse] = []
    @Published var loading = true
    @Published var error: String?

    // Offline-first (§1.7): cache-then-network reads; writes apply optimistically
    // and route through the durable mutation queue (idempotent on saved_verse_id).
    private let sync = SyncCoordinator.shared
    private let domain = "saved_verses"

    func load() async {
        error = nil
        let cachedList = await cached()
        if !cachedList.isEmpty { verses = cachedList; loading = false }
        if let fresh = try? await MemberAPI.verses() {
            verses = fresh
            await cacheAll(fresh)
        } else if cachedList.isEmpty {
            error = "You're offline — your verses will load when you reconnect."
        }
        loading = false
    }

    func save(reference: String, version: String, text: String, note: String) async {
        let id = UUID().uuidString
        let ver = version.isEmpty ? "KJV" : version
        let verse = SavedVerse(savedVerseId: id, reference: reference, version: ver,
                               verseText: text.isEmpty ? nil : text, note: note.isEmpty ? nil : note,
                               createdAt: ISO8601DateFormatter().string(from: Date()))
        verses.insert(verse, at: 0)
        await cacheAll(verses)
        await sync.enqueue(domain: domain, op: "save", payload: [
            "saved_verse_id": AnyCodable(id),
            "reference": AnyCodable(reference),
            "version": AnyCodable(ver),
            "verse_text": AnyCodable(text.isEmpty ? nil : text),
            "note": AnyCodable(note.isEmpty ? nil : note),
        ])
    }

    func delete(_ v: SavedVerse) async {
        verses.removeAll { $0.savedVerseId == v.savedVerseId }
        await cacheAll(verses)
        await sync.enqueue(domain: domain, op: "delete", payload: ["saved_verse_id": AnyCodable(v.savedVerseId)])
    }

    private func cacheAll(_ list: [SavedVerse]) async {
        let rows = list.compactMap { v -> (id: String, body: Data)? in
            (try? JSONEncoder().encode(v)).map { (v.savedVerseId, $0) }
        }
        await sync.store.cacheReplace(domain: domain, rows: rows)
    }

    private func cached() async -> [SavedVerse] {
        await sync.store.cachedRows(domain: domain)
            .compactMap { try? JSONDecoder().decode(SavedVerse.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct VerseLibraryView: View {
    @StateObject private var vm = VerseLibraryViewModel()
    @State private var adding = false

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.verses.isEmpty,
                          isEmpty: vm.verses.isEmpty, error: vm.error,
                          emptyText: "No saved verses yet. Tap + to add one.", retry: { Task { await vm.load() } }) {
                ScrollView {
                    VStack(spacing: Nuru.S.md) {
                        ForEach(vm.verses) { v in
                            SavedVerseCard(verse: v) { Task { await vm.delete(v) } }
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("Verse Library")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Icon(.plus, size: 18, color: Nuru.gold) }
            }
        }
        .task { if vm.verses.isEmpty { await vm.load() } }
        .sheet(isPresented: $adding) {
            VerseEditor { reference, version, text, note in
                Task { await vm.save(reference: reference, version: version, text: text, note: note) }
            }
        }
    }
}

private struct SavedVerseCard: View {
    let verse: SavedVerse
    let remove: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                HStack {
                    Text(verse.reference).font(.nHeading).foregroundStyle(Nuru.ink)
                    Spacer()
                    Text(verse.version).font(.nMicro).foregroundStyle(Nuru.faint)
                }
                if let text = verse.verseText, !text.isEmpty {
                    Text(text).font(.nBodyLg).foregroundStyle(Nuru.ink).fixedSize(horizontal: false, vertical: true)
                }
                if let note = verse.note, !note.isEmpty {
                    Text(note).font(.nCaption).foregroundStyle(Nuru.muted)
                }
                HStack {
                    Spacer()
                    Button(role: .destructive, action: remove) {
                        Icon(.trash2, size: 13, color: Nuru.danger)
                    }
                }
            }
        }
    }
}

private struct VerseEditor: View {
    let onSave: (_ reference: String, _ version: String, _ text: String, _ note: String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reference = ""
    @State private var version = ""
    @State private var text = ""
    @State private var note = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Reference") { TextField("e.g. John 3:16", text: $reference) }
                Section("Version (optional)") { TextField("e.g. NIV", text: $version) }
                Section("Verse text (optional)") { TextField("The verse…", text: $text, axis: .vertical).lineLimit(2...8) }
                Section("Note (optional)") { TextField("Why it matters to you", text: $note, axis: .vertical).lineLimit(1...6) }
            }
            .navigationTitle("Save a verse")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(reference, version, text, note); dismiss() }
                        .disabled(reference.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}
