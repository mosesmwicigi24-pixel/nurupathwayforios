// Memory Verses — the native port of the Figma MemoryVerseScreen
// (PathwayScreens.tsx): a "This week" hero card for the current verse (quoted
// serif text, week-day goal, gold Practice CTA), then the "YOUR VERSE LIBRARY"
// section with mastered/week chips. Kept on top: the derived WORD SCORE
// dashboard and milestone nudge (shipped scoring feature, not in the make).
// Practicing opens a type-from-memory sheet; the server bumps status on a
// strong match.
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

    // The Figma "This week" hero — first verse still being learned.
    var currentVerse: MemoryVerseRow? {
        verses.first(where: { !$0.isMastered }) ?? verses.first
    }
    var libraryVerses: [MemoryVerseRow] {
        verses.filter { $0.memoryVerseId != currentVerse?.memoryVerseId }
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
                        VStack(alignment: .leading, spacing: Nuru.S.md) {
                            WordScoreCard(score: vm.score, band: vm.band,
                                          consistency: vm.consistency,
                                          memorization: vm.memorization,
                                          breadth: vm.breadth)
                            MilestoneCard(remaining: vm.toNextMilestone, mastered: vm.mastered)
                            if let current = vm.currentVerse {
                                CurrentVerseCard(verse: current) { practiceTarget = current }
                            }
                            if !vm.libraryVerses.isEmpty {
                                Text("YOUR VERSE LIBRARY")
                                    .font(.inter(10, .semibold)).tracking(1.8)
                                    .foregroundStyle(Nuru.muted)
                                    .padding(.horizontal, Nuru.S.xs)
                                    .padding(.top, Nuru.S.sm)
                                ForEach(vm.libraryVerses) { v in
                                    LibraryVerseRow(verse: v) { practiceTarget = v }
                                }
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

    // Cream Figma ScreenShell header (done — keep as is).
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
        .buttonStyle(.pressable)
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
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var grown = false
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
                            .frame(width: (grown ? max(0, min(1, value)) : 0) * geo.size.width)
                    }
                }
                .frame(height: 6)
            }
            .onAppear {
                guard !grown else { return }
                if reduceMotion { grown = true; return }
                withAnimation(.easeOut(duration: 0.7).delay(0.2)) { grown = true }
            }
        }
    }
}

private struct ScoreRing: View {
    let score: Int
    let band: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false
    var body: some View {
        ZStack {
            Circle().stroke(Nuru.goldGlow, lineWidth: 4)
            Circle()
                .trim(from: 0, to: grown ? max(0.02, min(1, Double(score) / 100)) : 0.02)
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
        .onAppear {
            guard !grown else { return }
            if reduceMotion { grown = true; return }
            withAnimation(.easeOut(duration: 0.9).delay(0.15)) { grown = true }
        }
    }
}

// MARK: - Milestone nudge

private struct MilestoneCard: View {
    let remaining: Int
    let mastered: Int

    // "1 verses" read wrong, and "0 verses to go" undersold a reached milestone.
    private var title: String {
        remaining == 0
            ? "Milestone reached — \(mastered) verses mastered"
            : "\(remaining) verse\(remaining == 1 ? "" : "s") to your next milestone"
    }
    private var subtitle: String {
        remaining == 0
            ? "Beautiful work. Keep hiding His Word in your heart."
            : "Master \(remaining) more to reach 10. Keep hiding His Word in your heart."
    }

    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(.sparkles, size: 18, color: Nuru.gold)
                .frame(width: 34, height: 34)
                .background(Nuru.goldGlow, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.inter(13, .semibold))
                    .foregroundStyle(Nuru.ink)
                Text(subtitle)
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

// MARK: - "This week" hero card (Figma: overline + day goal, quoted serif verse, gold Practice)

private struct CurrentVerseCard: View {
    let verse: MemoryVerseRow
    let practice: () -> Void

    /// Monday-based day of the week, the Figma "Day 4 of 7" goal.
    private var dayOfWeek: Int {
        let wd = Calendar.current.component(.weekday, from: Date())  // 1 = Sunday
        return wd == 1 ? 7 : wd - 1
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack {
                    Text("THIS WEEK")
                        .font(.inter(10, .semibold)).tracking(1.8)
                        .foregroundStyle(Color(hex: 0xA8861C))
                    Spacer()
                    Text("Day \(dayOfWeek) of 7")
                        .font(.inter(10, .regular))
                        .foregroundStyle(Nuru.muted)
                }
                Text("\u{201C}\(verse.verseText)\u{201D}")
                    .font(.fraunces(20, .medium))
                    .foregroundStyle(Nuru.navy)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Text(verse.reference)
                    .font(.inter(12, .bold))
                    .foregroundStyle(Nuru.gold)
                    .lineLimit(1)
                practiceButton
                    .padding(.top, Nuru.S.xs)
            }
        }
    }

    // Figma "Listen" twin button is a mock (no verse audio) — Practice goes full width.
    private var practiceButton: some View {
        Button { Haptics.tap(); practice() } label: {
            HStack(spacing: Nuru.S.sm) {
                Icon(.penLine, size: 14, color: Nuru.navy)
                Text("Practice").font(.inter(13, .bold)).foregroundStyle(Nuru.navy)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Nuru.gold, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Library row (Figma: bordered white row, gold ref, status chip, quoted text)

private struct LibraryVerseRow: View {
    let verse: MemoryVerseRow
    let practice: () -> Void

    var body: some View {
        Button { Haptics.tap(); practice() } label: {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                HStack(alignment: .top) {
                    Text(verse.reference)
                        .font(.inter(12, .bold))
                        .foregroundStyle(Nuru.gold)
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: Nuru.S.sm)
                    chip.layoutPriority(1)
                }
                Text("\u{201C}\(verse.verseText)\u{201D}")
                    .font(.inter(13, .regular))
                    .foregroundStyle(Nuru.navy)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Nuru.S.md)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private var chip: some View {
        if verse.isMastered {
            chipView("Mastered", bg: Nuru.successBg, fg: Nuru.successText)
        } else if let w = verse.weekNumber {
            chipView("Week \(w)", bg: Nuru.surface, fg: Nuru.muted)
        } else {
            chipView("Learning", bg: Nuru.surface, fg: Nuru.muted)
        }
    }

    private func chipView(_ label: String, bg: Color, fg: Color) -> some View {
        Text(label)
            .font(.inter(10, .semibold))
            .foregroundStyle(fg)
            .padding(.horizontal, Nuru.S.sm).padding(.vertical, 3)
            .background(bg, in: Capsule())
    }
}

// MARK: - Practice sheet (Figma: serif title + close, ref caption, editor, gold match bar)

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

                VStack(alignment: .leading, spacing: Nuru.S.xs) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Nuru.track)
                            Capsule().fill(Nuru.gold)
                                .frame(width: Double(matchPct) / 100 * geo.size.width)
                                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: matchPct)
                        }
                    }
                    .frame(height: 8)
                    Text("\(matchPct)% match")
                        .font(.inter(10, .regular))
                        .foregroundStyle(Nuru.muted)
                        .contentTransition(.numericText())
                        .animation(.default, value: matchPct)
                }
                // A quiet tick each time the match crosses a quarter — progress you can feel.
                .onChange(of: matchPct) { old, new in
                    if new / 25 != old / 25, new > old { Haptics.selection() }
                }

                PButton(title: "Save practice", variant: .gold, busy: saving,
                        disabled: typed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
                    Task {
                        Haptics.action()
                        saving = true
                        await onSave(matchPct)
                        saving = false
                        Haptics.success()
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
