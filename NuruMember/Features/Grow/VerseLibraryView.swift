// Verse Library — the native port of screens/VerseLibraryScreen.tsx, with the
// saved-verse cards styled to the Figma make's verse-collection presentation:
// gold serif reference, version chip, quoted serif verse text, and a gold
// Practice affordance (type-from-memory sheet). Add a reference (+ optional
// text/note), practice, and remove. Writes are idempotent on saved_verse_id.
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
            (try? JSONEncoder.nuruSnake.encode(v)).map { (v.savedVerseId, $0) }
        }
        await sync.store.cacheReplace(domain: domain, rows: rows)
    }

    private func cached() async -> [SavedVerse] {
        await sync.store.cachedRows(domain: domain)
            .compactMap { try? JSONDecoder.nuruSnake.decode(SavedVerse.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }
}

struct VerseLibraryView: View {
    @StateObject private var vm = VerseLibraryViewModel()
    @State private var adding = false
    @State private var practicing: SavedVerse?

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.verses.isEmpty,
                          isEmpty: vm.verses.isEmpty, error: vm.error,
                          emptyText: "No saved verses yet. Tap + to add one.", retry: { Task { await vm.load() } }) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Nuru.S.md) {
                        Text("YOUR VERSE LIBRARY")
                            .font(.inter(10, .bold)).tracking(1.8)
                            .foregroundStyle(Nuru.muted)
                            .padding(.horizontal, Nuru.S.xs)
                        ForEach(vm.verses) { v in
                            SavedVerseCard(verse: v,
                                           practice: { practicing = v },
                                           remove: { Task { await vm.delete(v) } })
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
        .sheet(item: $practicing) { verse in
            VersePracticeSheet(verse: verse)
                .presentationDetents([.medium, .large])
        }
    }
}

/// One saved verse, styled to the Figma library card: gold serif reference,
/// version chip, quoted serif verse text, note, then practice + remove.
private struct SavedVerseCard: View {
    let verse: SavedVerse
    let practice: () -> Void
    let remove: () -> Void

    private var hasText: Bool { verse.verseText?.isEmpty == false }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(alignment: .top) {
                    Text(verse.reference)
                        .font(.fraunces(16, .semibold))
                        .foregroundStyle(Nuru.gold)
                    Spacer()
                    Text(verse.version)
                        .font(.inter(10, .semibold))
                        .foregroundStyle(Nuru.muted)
                        .padding(.horizontal, Nuru.S.sm).padding(.vertical, 3)
                        .background(Nuru.surface, in: Capsule())
                }
                if let text = verse.verseText, !text.isEmpty {
                    Text("\u{201C}\(text)\u{201D}")
                        .font(.fraunces(15, .regular))
                        .foregroundStyle(Nuru.navy)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let note = verse.note, !note.isEmpty {
                    Text(note)
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    if hasText {
                        Button(action: practice) {
                            HStack(spacing: 6) {
                                Icon(.penLine, size: 13, color: Nuru.navy)
                                Text("Practice")
                                    .font(.inter(12, .bold))
                                    .foregroundStyle(Nuru.navy)
                            }
                            .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.sm)
                            .background(Nuru.gold, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Button(role: .destructive, action: remove) {
                        Icon(.trash2, size: 14, color: Nuru.danger)
                            .frame(width: 32, height: 32)
                            .background(Nuru.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
        }
    }
}

/// Type-from-memory practice for a saved verse — the Figma practice sheet
/// (verse-tint editor, gold match bar, save). Presentation-only: saved verses
/// have no practice endpoint, so "Save practice" simply closes the sheet.
private struct VersePracticeSheet: View {
    let verse: SavedVerse
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var matchPct: Int { Self.matchPct(typed: typed, target: verse.verseText ?? "") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                VStack(alignment: .leading, spacing: Nuru.S.xs) {
                    Text("TYPE FROM MEMORY")
                        .font(.inter(10, .bold)).tracking(1.2)
                        .foregroundStyle(Nuru.muted)
                    Text(verse.reference)
                        .font(.fraunces(18, .semibold))
                        .foregroundStyle(Nuru.gold)
                }
                editor
                matchBar
                PButton(title: "Save practice", variant: .gold,
                        disabled: typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    dismiss()
                }
            }
            .padding(Nuru.S.screen)
        }
        .background(Nuru.paper)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if typed.isEmpty {
                Text("Begin typing the verse…")
                    .font(.nBody)
                    .foregroundStyle(Nuru.faint)
                    .padding(.horizontal, Nuru.S.base + 5)
                    .padding(.vertical, Nuru.S.base + 8)
            }
            TextEditor(text: $typed)
                .font(.nBody)
                .foregroundStyle(Nuru.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(Nuru.S.sm)
        }
        .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(Nuru.border, lineWidth: 1)
        )
    }

    private var matchBar: some View {
        VStack(alignment: .leading, spacing: Nuru.S.xs) {
            Text("\(matchPct)% match")
                .font(.inter(12, .medium))
                .foregroundStyle(Nuru.muted)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.track)
                    Capsule().fill(Nuru.gold)
                        .frame(width: Double(matchPct) / 100 * geo.size.width)
                }
            }
            .frame(height: 4)
        }
    }

    /// Position-wise word match against the saved text, 0…100 (mirrors the
    /// Figma `matchRatio`).
    static func matchPct(typed: String, target: String) -> Int {
        func words(_ s: String) -> [String] {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        let want = words(target)
        guard !want.isEmpty else { return 0 }
        let got = words(typed)
        var hits = 0
        for i in 0..<min(want.count, got.count) where want[i] == got[i] { hits += 1 }
        return Int((Double(hits) / Double(want.count) * 100).rounded())
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
