// Verse Library — the member's saved-verse collection, styled to the Figma
// MemoryVerseScreen library section (PathwayScreens.tsx): a cream ScreenShell
// header (back + kicker + title, with "+ add" in the right slot), then bordered
// white rows — gold bold reference, version chip, quoted 13pt verse text — with
// a gold Practice affordance (type-from-memory sheet) and remove. Writes are
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
            VStack(spacing: 0) {
                header
                LoadStateView(loading: vm.loading && vm.verses.isEmpty,
                              isEmpty: vm.verses.isEmpty, error: vm.error,
                              emptyText: "No saved verses yet. Tap + to add one.", retry: { Task { await vm.load() } }) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: Nuru.S.sm) {
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
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
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

    // Cream Figma ScreenShell header — back on the left, "+ add" in the right slot.
    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                BackButton()
                Spacer()
                Button { adding = true } label: {
                    Icon(.plus, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("YOUR COLLECTION")
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Text("Verse library")
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.navy)
            }
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

/// One saved verse, matching the Figma library-row anatomy: bordered white row,
/// gold bold reference + chip, quoted 13pt navy text — plus the real practice
/// and remove affordances this screen has always had.
private struct SavedVerseCard: View {
    let verse: SavedVerse
    let practice: () -> Void
    let remove: () -> Void

    private var hasText: Bool { verse.verseText?.isEmpty == false }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.xs) {
            HStack(alignment: .top) {
                Text(verse.reference)
                    .font(.inter(12, .bold))
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
                    .font(.inter(13, .regular))
                    .foregroundStyle(Nuru.navy)
                    .lineSpacing(4)
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

/// Type-from-memory practice for a saved verse — the Figma practice sheet
/// (serif title + close, editor, gold match bar, save). Presentation-only:
/// saved verses have no practice endpoint, so "Save practice" simply closes.
private struct VersePracticeSheet: View {
    let verse: SavedVerse
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var matchPct: Int { Self.matchPct(typed: typed, target: verse.verseText ?? "") }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                HStack {
                    Text("Type from memory")
                        .font(.fraunces(18, .medium))
                        .foregroundStyle(Nuru.navy)
                    Spacer()
                    Button { dismiss() } label: {
                        Icon(.x, size: 15, color: Nuru.navy)
                            .frame(width: 32, height: 32)
                            .background(Nuru.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
                Text(verse.reference)
                    .font(.inter(11, .regular))
                    .foregroundStyle(Nuru.muted)
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
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(Nuru.border, lineWidth: 1)
        )
    }

    private var matchBar: some View {
        VStack(alignment: .leading, spacing: Nuru.S.xs) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.track)
                    Capsule().fill(Nuru.gold)
                        .frame(width: Double(matchPct) / 100 * geo.size.width)
                }
            }
            .frame(height: 8)
            Text("\(matchPct)% match")
                .font(.inter(10, .regular))
                .foregroundStyle(Nuru.muted)
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
