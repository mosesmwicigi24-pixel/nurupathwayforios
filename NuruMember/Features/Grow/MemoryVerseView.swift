// Memory Verses — the native port of screens/MemoryVerseScreen.tsx. Lists the
// member's memory-verse set with mastery status, and offers a simple recite/
// practice flow that logs an attempt (the server bumps status on a strong match).
import SwiftUI

@MainActor
final class MemoryVerseViewModel: ObservableObject {
    @Published var verses: [MemoryVerseRow] = []
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { verses = try await MemoryVerseRow.fetch() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your verses." }
        loading = false
    }

    func markPracticed(_ verse: MemoryVerseRow) async {
        try? await MemberAPI.practiceVerse(verse.memoryVerseId, matchPct: 100)
        await load()
    }
}

private extension MemoryVerseRow {
    static func fetch() async throws -> [MemoryVerseRow] { try await MemberAPI.memoryVerses() }
}

struct MemoryVerseView: View {
    @StateObject private var vm = MemoryVerseViewModel()

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.verses.isEmpty,
                          isEmpty: vm.verses.isEmpty, error: vm.error,
                          emptyText: "No memory verses yet.", retry: { Task { await vm.load() } }) {
                ScrollView {
                    VStack(spacing: Nuru.S.md) {
                        ForEach(vm.verses) { v in VerseCard(verse: v) { Task { await vm.markPracticed(v) } } }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("Memory Verses")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.verses.isEmpty { await vm.load() } }
    }
}

private struct VerseCard: View {
    let verse: MemoryVerseRow
    let practiced: () -> Void
    @State private var revealed = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack {
                    Text(verse.reference).font(.nHeading).foregroundStyle(Nuru.ink)
                    Spacer()
                    statusChip
                }
                if revealed {
                    Text(verse.verseText).font(.nBodyLg).foregroundStyle(Nuru.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tap reveal to test your recall.").font(.nCaption).foregroundStyle(Nuru.faint)
                }
                HStack(spacing: Nuru.S.md) {
                    Button(revealed ? "Hide" : "Reveal") { withAnimation { revealed.toggle() } }
                        .font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
                    Spacer()
                    if !verse.isMastered {
                        Button("I knew it", action: practiced)
                            .font(.inter(13, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.sm)
                            .background(Nuru.success, in: Capsule())
                    }
                }
            }
        }
    }

    private var statusChip: some View {
        Text(verse.isMastered ? "Mastered" : "Learning")
            .font(.nMicro)
            .foregroundStyle(verse.isMastered ? Nuru.successText : Nuru.goldChipText)
            .padding(.horizontal, Nuru.S.sm).padding(.vertical, 3)
            .background(verse.isMastered ? Nuru.successBg : Nuru.goldChipBg, in: Capsule())
    }
}
