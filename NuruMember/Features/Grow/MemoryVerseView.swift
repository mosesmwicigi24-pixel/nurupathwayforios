// Memory Verses — the native port of screens/MemoryVerseScreen.tsx. Lists the
// member's memory-verse set with a derived WORD SCORE dashboard, a next-milestone
// nudge, and a per-verse practice flow (a .sheet where the member types the verse
// from memory; the server bumps status on a strong match).
import SwiftUI

// MARK: - View model

@MainActor
final class MemoryVerseViewModel: ObservableObject {
    @Published var verses: [MemoryVerseRow] = []
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { verses = try await MemberAPI.memoryVerses() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your verses." }
        loading = false
    }

    func practice(_ id: String, matchPct: Int) async {
        try? await MemberAPI.practiceVerse(id, matchPct: matchPct)
        await load()
    }

    // Derived word-score dashboard (no word-score endpoint exists).
    var total: Int { verses.count }
    var mastered: Int { verses.filter { $0.isMastered }.count }

    var score: Int { total == 0 ? 0 : Int((Double(mastered) / Double(total) * 100).rounded()) }

    var band: String {
        switch score {
        case ..<25: return "Seedling"
        case ..<50: return "Sprouting"
        case ..<75: return "Growing"
        default:    return "Flourishing"
        }
    }

    // Bar values 0…1.
    var consistency: Double { total == 0 ? 0 : Double(mastered) / Double(total) }
    var memorization: Double {
        guard total > 0 else { return 0 }
        let avg = verses.reduce(0) { $0 + $1.bestMatchPct } / total
        return Double(avg) / 100
    }
    var breadth: Double { min(Double(total) / 10, 1) }

    // Next milestone (reach 10 mastered).
    var toNextMilestone: Int { max(0, 10 - mastered) }
}

// MARK: - Screen

struct MemoryVerseView: View {
    @StateObject private var vm = MemoryVerseViewModel()
    @State private var practiceTarget: MemoryVerseRow?

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                LoadStateView(loading: vm.loading && vm.verses.isEmpty,
                              isEmpty: vm.verses.isEmpty, error: vm.error,
                              emptyText: "No memory verses yet.", retry: { Task { await vm.load() } }) {
                    ScrollView {
                        VStack(spacing: Nuru.S.md) {
                            WordScoreCard(score: vm.score, band: vm.band,
                                          consistency: vm.consistency,
                                          memorization: vm.memorization,
                                          breadth: vm.breadth)
                            MilestoneCard(remaining: vm.toNextMilestone)
                            ForEach(vm.verses) { v in
                                VerseCard(verse: v) { practiceTarget = v }
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
        .sheet(item: $practiceTarget) { verse in
            PracticeSheet(verse: verse) { matchPct in
                await vm.practice(verse.memoryVerseId, matchPct: matchPct)
            }
            .presentationDetents([.medium, .large])
        }
    }

    // Navy header with circular back button + titles.
    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            BackButton()
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("HIDE HIS WORD")
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Text("Memory verses")
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

// MARK: - Word score card

private struct WordScoreCard: View {
    let score: Int
    let band: String
    let consistency: Double
    let memorization: Double
    let breadth: Double

    var body: some View {
        Card {
            HStack(alignment: .center, spacing: Nuru.S.base) {
                ScoreRing(score: score, band: band)
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("WORD SCORE")
                            .font(.inter(10, .bold)).tracking(1.2)
                            .foregroundStyle(Nuru.gold)
                        Text(band)
                            .font(.fraunces(18, .semibold))
                            .foregroundStyle(Nuru.ink)
                    }
                    VStack(spacing: 6) {
                        Bar(label: "Consistency", value: consistency)
                        Bar(label: "Memorization", value: memorization)
                        Bar(label: "Breadth", value: breadth)
                    }
                }
            }
        }
    }

    private struct Bar: View {
        let label: String
        let value: Double // 0…1
        var body: some View {
            HStack(spacing: Nuru.S.sm) {
                Text(label)
                    .font(.inter(11, .medium))
                    .foregroundStyle(Nuru.muted)
                    .frame(width: 84, alignment: .leading)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Nuru.track)
                        Capsule().fill(Nuru.gold)
                            .frame(width: max(0, min(1, value)) * geo.size.width)
                    }
                }
                .frame(height: 6)
            }
        }
    }
}

private struct ScoreRing: View {
    let score: Int
    let band: String
    var body: some View {
        ZStack {
            Circle().stroke(Nuru.goldGlow, lineWidth: 4)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, Double(score) / 100)))
                .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.fraunces(24, .semibold))
                    .foregroundStyle(Nuru.ink)
                Text("/100")
                    .font(.inter(10, .medium))
                    .foregroundStyle(Nuru.muted)
            }
        }
        .frame(width: 84, height: 84)
    }
}

// MARK: - Milestone nudge

private struct MilestoneCard: View {
    let remaining: Int
    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(.sparkles, size: 18, color: Nuru.gold)
                .frame(width: 34, height: 34)
                .background(Nuru.goldGlow, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text("\(remaining) verses to your next milestone")
                    .font(.inter(13, .semibold))
                    .foregroundStyle(Nuru.ink)
                Text("Master \(remaining) more to reach 10. Keep hiding His Word in your heart.")
                    .font(.inter(12, .regular))
                    .foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.base)
        .background(Nuru.goldTint, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
                .stroke(Nuru.goldLo, lineWidth: 1)
        )
    }
}

// MARK: - Verse card

private struct VerseCard: View {
    let verse: MemoryVerseRow
    let practice: () -> Void

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(alignment: .top) {
                    Text(verse.reference)
                        .font(.fraunces(16, .semibold))
                        .foregroundStyle(Nuru.gold)
                    Spacer()
                    if verse.isMastered { masteredBadge }
                }
                Text(verse.verseText)
                    .font(.nBody)
                    .foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if verse.isMastered {
                    outlineButton
                } else {
                    PButton(title: "Practice", variant: .gold, action: practice)
                }
            }
        }
    }

    // No outline variant exists in PButton, so the "Practice again" CTA is built
    // inline: a bordered, paper-filled, full-width button matching the screenshot.
    private var outlineButton: some View {
        Button(action: practice) {
            Text("Practice again")
                .font(.inter(16, .semibold))
                .foregroundStyle(Nuru.ink)
                .frame(maxWidth: .infinity, minHeight: Nuru.buttonHeightLg)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous)
                        .stroke(Nuru.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var masteredBadge: some View {
        HStack(spacing: 4) {
            Icon(.check, size: 11, color: Nuru.successText)
            Text("Mastered")
                .font(.inter(11, .semibold))
                .foregroundStyle(Nuru.successText)
        }
        .padding(.horizontal, Nuru.S.sm).padding(.vertical, 4)
        .background(Nuru.successBg, in: Capsule())
    }
}

// MARK: - Practice sheet

private struct PracticeSheet: View {
    let verse: MemoryVerseRow
    let onSave: (Int) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var saving = false

    private var matchPct: Int { Self.matchPct(typed: typed, target: verse.verseText) }

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

                PButton(title: "Save practice", variant: .gold, busy: saving,
                        disabled: typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task {
                        saving = true
                        await onSave(matchPct)
                        saving = false
                        dismiss()
                    }
                }
            }
            .padding(Nuru.S.screen)
        }
        .background(Nuru.paper)
    }

    // Normalized word-overlap ratio between typed text and the target verse, 0…100.
    static func matchPct(typed: String, target: String) -> Int {
        func words(_ s: String) -> [String] {
            s.lowercased()
                .components(separatedBy: CharacterSet.alphanumerics.inverted)
                .filter { !$0.isEmpty }
        }
        let want = words(target)
        guard !want.isEmpty else { return 0 }
        let got = words(typed)
        guard !got.isEmpty else { return 0 }

        // Longest common prefix of the word sequences, the closest signal to
        // "recited from the start" — plus credit for overall word overlap.
        var prefix = 0
        while prefix < want.count, prefix < got.count, want[prefix] == got[prefix] { prefix += 1 }
        let prefixRatio = Double(prefix) / Double(want.count)

        var pool = want
        var hits = 0
        for w in got {
            if let i = pool.firstIndex(of: w) { pool.remove(at: i); hits += 1 }
        }
        let overlapRatio = Double(hits) / Double(want.count)

        let combined = max(prefixRatio, overlapRatio * 0.9)
        return min(100, Int((combined * 100).rounded()))
    }
}
