// "Why this score?" — the drill-down sheet behind the five growth scores.
// Renders GET /me/scores/{pillar} exactly as the server computes it (§1.1
// server-authoritative): the 0–100 composite + pastoral band, each weighted
// component as a gold bar, and the raw counts ("The numbers behind it") for
// transparency. A pillar picker at the top swaps between the five disciplines.
// REAL DATA ONLY — every number on this sheet comes off the wire.
import SwiftUI

struct ScoreDetailView: View {
    @State private var pillar: ScorePillar
    @State private var breakdown: ScoreBreakdown?
    @State private var failed = false

    init(pillar: ScorePillar) {
        _pillar = State(initialValue: pillar)
    }

    var body: some View {
        PSheetShell(title: "Why this score?") {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                pillarPicker

                if let b = breakdown {
                    hero(b).gentleEntrance()
                    componentsCard(b).gentleEntrance(delay: 0.05)
                    if !b.detail.isEmpty { detailCard(b).gentleEntrance(delay: 0.1) }
                    Text("Scores are formative, never a leaderboard — they decay gently when you lapse and grow as you do.")
                        .font(.inter(10)).italic().foregroundStyle(Color(hex: 0x9CA3AF))
                        .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                } else if failed {
                    errorCard
                } else {
                    skeleton
                }
            }
        }
        .presentationDetents([.large])
        .task(id: pillar) { await load() }
    }

    private func load() async {
        breakdown = nil; failed = false
        do { breakdown = try await MemberAPI.scoreDetail(pillar) }
        catch { failed = true }
    }

    // MARK: Pillar picker

    private var pillarPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(ScorePillar.allCases) { p in
                    let on = p == pillar
                    Button {
                        if !on { Haptics.selection(); pillar = p }
                    } label: {
                        HStack(spacing: 5) {
                            Icon(p.icon, size: 12, color: on ? Nuru.navy : Color(hex: 0x68758A))
                            Text(p.displayName)
                                .font(.inter(12, on ? .bold : .semibold))
                                .foregroundStyle(on ? Nuru.navy : Color(hex: 0x68758A))
                        }
                        .padding(.horizontal, 12).frame(height: 36)
                        .background(on ? Nuru.gold.opacity(0.16) : Nuru.surface, in: Capsule())
                        .overlay(Capsule().stroke(on ? Nuru.gold : Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
    }

    // MARK: Hero — the composite + band + what this pillar measures

    private func hero(_ b: ScoreBreakdown) -> some View {
        VStack(spacing: Nuru.S.sm) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(b.score)")
                    .font(.fraunces(52, .semibold)).kerning(-1)
                    .foregroundStyle(Nuru.navy)
                    .contentTransition(.numericText())
                Text("/ 100").font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0x9CA3AF))
            }
            HStack(spacing: 4) {
                Icon(.sparkles, size: 11, color: Color(hex: 0x8A6D18))
                Text(b.band).font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x8A6D18))
            }
            .padding(.horizontal, 12).padding(.vertical, 5)
            .background(Nuru.gold.opacity(0.14), in: Capsule())
            .overlay(Capsule().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))

            Text(pillar.blurb)
                .font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(Nuru.S.base)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 22, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
    }

    // MARK: Components — the weighted parts, as bars

    private func componentsCard(_ b: ScoreBreakdown) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            sectionHeading("WHAT MAKES IT UP")
            ForEach(sortedKeys(b.components), id: \.self) { key in
                componentBar(label: Self.label(for: key), value: b.components[key] ?? 0)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func componentBar(label: String, value: Double) -> some View {
        let clamped = min(max(value, 0), 100)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(label).font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                Spacer(minLength: Nuru.S.sm)
                Text("\(Int(value.rounded()))")
                    .font(.inter(12, .bold)).foregroundStyle(Color(hex: 0xA8861C))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.surface)
                        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                    if clamped > 0 {
                        Capsule().fill(Nuru.gold)
                            .frame(width: max(8, geo.size.width * CGFloat(clamped) / 100))
                    }
                }
            }
            .frame(height: 8)
        }
    }

    // MARK: Detail — the raw counts behind the components

    private func detailCard(_ b: ScoreBreakdown) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeading("THE NUMBERS BEHIND IT")
                .padding(.bottom, Nuru.S.xs)
            ForEach(Array(sortedKeys(b.detail).enumerated()), id: \.element) { i, key in
                if i > 0 { Divider() }
                HStack {
                    Text(Self.label(for: key)).font(.inter(12)).foregroundStyle(Color(hex: 0x6B7280))
                    Spacer(minLength: Nuru.S.md)
                    Text(Self.format(b.detail[key] ?? 0, key: key))
                        .font(.inter(13, .bold)).foregroundStyle(Nuru.navy)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func sectionHeading(_ text: String) -> some View {
        Text(text).font(.inter(10, .bold)).kerning(1.8).foregroundStyle(Color(hex: 0xA8861C))
    }

    // MARK: Loading / error

    private var skeleton: some View {
        VStack(spacing: Nuru.S.base) {
            RoundedRectangle(cornerRadius: 22).fill(Nuru.surface).frame(height: 150)
            RoundedRectangle(cornerRadius: 22).fill(Nuru.surface).frame(height: 130)
        }
        .nuruShimmer()
    }

    private var errorCard: some View {
        VStack(spacing: Nuru.S.md) {
            Icon(.circleHelp, size: 24, color: Nuru.faint)
            Text("Couldn't load this score right now.")
                .font(.inter(13)).foregroundStyle(Nuru.muted)
            Button { Task { await load() } } label: {
                Text("Try again").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(Nuru.S.lg)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Key labels & ordering
    //
    // Dictionary keys come through the client decoder's `.convertFromSnakeCase`
    // (e.g. `verses_engaged` → `versesEngaged`). Known keys get a warm label;
    // anything the server adds later falls back to a generic humanization so a
    // new field is never dropped.

    private static let knownLabels: [String: String] = [
        // components
        "consistency": "Consistency",
        "memorization": "Memorization",
        "breadth": "Breadth",
        "depth": "Depth",
        "completeness": "Completeness",
        "completion": "Completion",
        "mastery": "Mastery",
        "attendance": "Showing up",
        // detail — word
        "versesEngaged": "Verses engaged",
        "versesMastered": "Verses mastered",
        "avgMatchPct": "Average best match",
        "activeDays14": "Active days (last 14)",
        // detail — prayer
        "prayersLogged": "Prayers journaled",
        "answered": "Marked answered",
        "prayerDays14": "Prayer days (last 14)",
        // detail — habits
        "rhythmWeekPct": "This week's rhythm",
        // detail — curriculum
        "modulesCompleted": "Modules completed",
        "modulesPublished": "Modules available",
        "quizzesPassed": "Quizzes passed",
        // detail — attendance
        "presentDays30d": "Present days (last 30)",
        "target": "Monthly target",
    ]

    /// Preferred order — consistency first (it leads every formula), then depth-ish
    /// components, then everything else alphabetically.
    private static let preferredOrder = [
        "consistency", "memorization", "depth", "completeness", "completion", "mastery", "breadth", "attendance",
        "activeDays14", "prayerDays14", "rhythmWeekPct",
        "versesEngaged", "versesMastered", "avgMatchPct",
        "prayersLogged", "answered",
        "modulesCompleted", "modulesPublished", "quizzesPassed",
        "presentDays30d", "target",
    ]

    private func sortedKeys(_ dict: [String: Double]) -> [String] {
        dict.keys.sorted { a, b in
            let ia = Self.preferredOrder.firstIndex(of: a) ?? .max
            let ib = Self.preferredOrder.firstIndex(of: b) ?? .max
            return ia == ib ? a < b : ia < ib
        }
    }

    static func label(for key: String) -> String {
        if let known = knownLabels[key] { return known }
        // Generic camelCase → "Sentence case" fallback for future server fields.
        var words: [String] = []
        var current = ""
        for ch in key {
            if ch.isUppercase, !current.isEmpty { words.append(current); current = String(ch).lowercased() }
            else { current.append(ch) }
        }
        if !current.isEmpty { words.append(current) }
        let sentence = words.joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }

    /// Percent-flavoured keys read as %, everything else as a plain count.
    private static func format(_ value: Double, key: String) -> String {
        let isPct = key.lowercased().contains("pct")
        let n = Int(value.rounded())
        return isPct ? "\(n)%" : "\(n)"
    }
}

private extension ScorePillar {
    /// What feeds this score — mirrors the formulas in scores/service.ts.
    var blurb: String {
        switch self {
        case .word:
            return "How the Word is taking root in you — how often you've engaged Scripture in the last 14 days, how deeply you're memorizing, and how many verses you've taken on."
        case .prayer:
            return "How your prayer life is growing — how consistently you've prayed in the last 14 days, and the depth of your journal, including the answers you've seen."
        case .habits:
            return "How steady your daily rhythm is — the days you showed up for at least one discipline in the last 14, and how many of the daily prayer, Word and reflection ticks you hit."
        case .curriculum:
            return "How your learning is going — the pathway modules you've completed, deepened by how well you scored on the quizzes you passed."
        case .attendance:
            return "How you're gathering with the body — the days you were present in the community or checked in at a gathering over the last 30."
        }
    }
}
