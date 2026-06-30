// Verse Library — the native port of screens/VerseLibraryScreen.tsx. The member's
// saved verses: add a reference (+ optional text/note), and remove. Writes are
// idempotent on saved_verse_id.
import SwiftUI

@MainActor
final class VerseLibraryViewModel: ObservableObject {
    @Published var verses: [SavedVerse] = []
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { verses = try await MemberAPI.verses() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your verses." }
        loading = false
    }

    func save(reference: String, version: String, text: String, note: String) async {
        try? await MemberAPI.saveVerse(savedVerseId: UUID().uuidString,
                                       reference: reference,
                                       version: version.isEmpty ? nil : version,
                                       verseText: text.isEmpty ? nil : text,
                                       note: note.isEmpty ? nil : note)
        await load()
    }

    func delete(_ v: SavedVerse) async {
        try? await MemberAPI.deleteVerse(v.savedVerseId)
        await load()
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
                Button { adding = true } label: { Image(systemName: "plus") }
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
                        Image(systemName: "trash").font(.system(size: 13))
                    }.foregroundStyle(Nuru.danger)
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
