// Spiritual Gifts assessment — presented as the Figma make's SpiritualGiftsScreen:
// one Likert question at a time on the cream shell (segmented gold progress,
// serif prompt, five labelled answer rows), auto-submitting after the last
// answer, then a results pane with top-gift bars + serving suggestions.
// The server-assembled question set (possibly AI-tuned per member, §3.x) still
// comes from MemberAPI.giftQuestions, and scoring + persona derivation stay
// server-side — MemberAPI.submitGifts returns the computed profile; the client
// never scores. "Done" pops back to "Your Calling" (GiftsView).
import SwiftUI

// MARK: - View model

@MainActor
final class GiftsAssessmentViewModel: ObservableObject {
    @Published var questionSet: GiftQuestionSet?
    @Published var loading = true
    @Published var error: String?
    @Published var submitting = false
    @Published var submitError: String?

    /// Per-question chosen Likert value (1…5), keyed by questionId.
    @Published var chosen: [String: Int] = [:]
    /// Index of the question on screen (== total once every answer is in).
    @Published var step = 0
    /// The server-computed profile returned by submission.
    @Published var result: MyGifts?

    var total: Int { questionSet?.data.count ?? 0 }
    var answered: Int { chosen.values.count }
    var allAnswered: Bool { total > 0 && answered == total }

    func load() async {
        loading = true; error = nil
        do { questionSet = try await MemberAPI.giftQuestions() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load the assessment." }
        loading = false
    }

    /// Records one answer and advances to the next question.
    func choose(_ value: Int, for question: GiftQuestion) {
        chosen[question.questionId] = value
        step += 1
    }

    /// Submits the full answer set; the server computes scores + personas.
    func submit() async {
        guard let questionSet, allAnswered, !submitting else { return }
        submitting = true; submitError = nil
        defer { submitting = false }
        let answers = questionSet.data.map { GiftAnswerInput(questionId: $0.questionId, value: chosen[$0.questionId] ?? 0) }
        do {
            result = try await MemberAPI.submitGifts(setId: questionSet.setId,
                                                     clientMutationId: UUID().uuidString,
                                                     answers: answers)
            Haptics.success()
        } catch {
            Haptics.error()
            submitError = (error as? APIError)?.errorDescription ?? "Couldn't submit. Please try again."
        }
    }

    /// Clears local answers and fetches a fresh question set.
    func retake() async {
        chosen = [:]; step = 0; result = nil; submitError = nil
        await load()
    }
}

// MARK: - Screen

struct GiftsAssessmentView: View {
    @StateObject private var vm = GiftsAssessmentViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.questionSet == nil { await vm.load() } }
    }

    /// Header kicker: question position while answering, then the result state.
    private var kicker: String {
        if vm.result != nil { return "YOUR GIFTS" }
        if vm.total > 0, vm.step < vm.total { return "QUESTION \(vm.step + 1) OF \(vm.total)" }
        return "SPIRITUAL GIFTS"
    }

    // MARK: Cream shell header (Figma ScreenShell)

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 0)
                Text(kicker)
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Spacer(minLength: 0)
                Color.clear.frame(width: 40, height: 40)
            }
            Text("Spiritual gifts")
                .font(.fraunces(24, .semibold))
                .foregroundStyle(Nuru.navy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.25)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Body states

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.questionSet == nil {
            Spacer(); ProgressView().tint(Nuru.gold); Spacer()
        } else if let g = vm.result {
            ResultsPane(gifts: g, answered: vm.answered,
                        onRetake: { Task { await vm.retake() } },
                        onDone: { dismiss() })
        } else if let qs = vm.questionSet {
            if vm.step < qs.data.count {
                questionPane(qs.data[vm.step], index: vm.step, total: qs.data.count)
                    .id(vm.step)   // each question settles in like a fresh page
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                submitPane
            }
        } else {
            errorState
        }
    }

    private var errorState: some View {
        VStack(spacing: Nuru.S.md) {
            Spacer()
            Text(vm.error ?? "Couldn't load the assessment.")
                .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            PButton(title: "Try again", variant: .navy) { Task { await vm.load() } }
                .frame(maxWidth: 200)
            Spacer()
        }
        .padding(Nuru.S.screen)
    }

    // MARK: One question at a time (Figma Likert card)

    private func questionPane(_ q: GiftQuestion, index: Int, total: Int) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                Card {
                    VStack(alignment: .leading, spacing: Nuru.S.base) {
                        SegmentedProgress(step: index, total: total)
                        Text(q.prompt)
                            .font(.fraunces(20, .medium))
                            .foregroundStyle(Nuru.navy)
                            .lineSpacing(5)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(spacing: Nuru.S.sm) {
                            ForEach(Self.likertOptions) { opt in
                                LikertRow(label: opt.label) {
                                    Haptics.selection()
                                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                        vm.choose(opt.value, for: q)
                                    }
                                    // Last answer in → hand the set to the server.
                                    if vm.allAnswered { Task { await vm.submit() } }
                                }
                            }
                        }
                    }
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    /// One Likert choice (1…5 + its label).
    private struct LikertOption: Identifiable {
        let value: Int
        let label: String
        var id: Int { value }
    }

    /// Likert scale, strongest first — mirrors the Figma option order.
    private static let likertOptions: [LikertOption] = [
        .init(value: 5, label: "Strongly agree"),
        .init(value: 4, label: "Agree"),
        .init(value: 3, label: "Sometimes"),
        .init(value: 2, label: "Rarely"),
        .init(value: 1, label: "Not me"),
    ]

    // MARK: Submission wait / retry (server computes the profile)

    private var submitPane: some View {
        VStack(spacing: Nuru.S.md) {
            Spacer()
            if let err = vm.submitError {
                Text(err)
                    .font(.nBody).foregroundStyle(Nuru.danger).multilineTextAlignment(.center)
                PButton(title: "Try again", variant: .gold, busy: vm.submitting) {
                    Task { await vm.submit() }
                }
                .frame(maxWidth: 220)
            } else {
                ProgressView().tint(Nuru.gold)
                Text("Reading your \(vm.answered) answers…")
                    .font(.nCaption).foregroundStyle(Nuru.muted)
            }
            Spacer()
        }
        .padding(Nuru.S.screen)
    }
}

// MARK: - Small pieces (private structs keep the body's type metadata light)

/// Segmented per-question progress — gold up to the current step.
private struct SegmentedProgress: View {
    let step: Int
    let total: Int
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<max(total, 1), id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Nuru.gold : Nuru.track)
                    .frame(height: 4)
                    .frame(maxWidth: .infinity)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: step)
    }
}

/// One Likert answer row — surface tile, label + chevron (the Figma option list).
private struct LikertRow: View {
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(.inter(13, .medium))
                    .foregroundStyle(Nuru.navy)
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 14, color: Nuru.faint)
            }
            .padding(Nuru.S.md)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

/// Results — top-gift bars + serving suggestions from the profile the server
/// returned (no client-side scoring).
private struct ResultsPane: View {
    let gifts: MyGifts
    let answered: Int
    let onRetake: () -> Void
    let onDone: () -> Void

    /// Figma's result-bar palette, cycled across the top gifts.
    private static let barColors: [Color] = [Color(hex: 0x6366F1), Color(hex: 0xDC2626), Nuru.gold]

    /// One resolved result row (gift key → persona title + normalised %).
    private struct TopGift: Identifiable {
        let key: String
        let title: String
        let pct: Int
        let color: Color
        var id: String { key }
    }

    private var topGifts: [TopGift] {
        guard let a = gifts.assessment else { return [] }
        return a.topGifts.prefix(3).enumerated().map { idx, key in
            TopGift(key: key,
                    title: gifts.personas.first { $0.giftKey == key }?.title ?? key.capitalized,
                    pct: Self.pct(a.scores[key]),
                    color: Self.barColors[idx % Self.barColors.count])
        }
    }

    /// Scores may arrive as 0…1 fractions or 0…100 percentages — normalise.
    private static func pct(_ v: Double?) -> Int {
        guard let v else { return 0 }
        let scaled = v <= 1 ? v * 100 : v
        return max(0, min(100, Int(scaled.rounded())))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                topGiftsCard.gentleEntrance()
                if !gifts.suggestedTracks.isEmpty { servingCard.gentleEntrance(delay: 0.12) }
                retakeButton.gentleEntrance(delay: 0.2)
                PButton(title: "Done", variant: .gold, action: onDone).gentleEntrance(delay: 0.2)
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    private var topGiftsCard: some View {
        Card {
            VStack(spacing: Nuru.S.base) {
                VStack(spacing: Nuru.S.xs) {
                    Icon(.sparkles, size: 22, color: Nuru.gold)
                        .frame(width: 56, height: 56)
                        .background(Nuru.gold.opacity(0.13), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Text("YOUR TOP GIFTS")
                        .font(.inter(10, .bold)).tracking(1.8)
                        .foregroundStyle(Nuru.goldLo)
                        .padding(.top, Nuru.S.sm)
                    Text("Based on \(answered) reflections")
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                }
                .frame(maxWidth: .infinity)
                VStack(spacing: Nuru.S.md) {
                    ForEach(topGifts) { g in
                        GiftBar(title: g.title, pct: g.pct, color: g.color)
                    }
                }
            }
        }
    }

    private var servingCard: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("WHERE TO SERVE")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Nuru.goldLo)
                ForEach(gifts.suggestedTracks.prefix(3)) { t in
                    HStack(spacing: Nuru.S.sm) {
                        Icon(.check, size: 13, color: Nuru.navy)
                            .frame(width: 28, height: 28)
                            .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        Text(t.title)
                            .font(.inter(12, .medium))
                            .foregroundStyle(Nuru.navy)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(Nuru.S.sm + 2)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var retakeButton: some View {
        Button { Haptics.tap(); onRetake() } label: {
            Text("Retake assessment")
                .font(.inter(13, .semibold))
                .foregroundStyle(Nuru.navy)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

/// One result row: gift name + % + tinted progress bar (the Figma result bars).
private struct GiftBar: View {
    let title: String
    let pct: Int
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: Nuru.S.xs) {
            HStack {
                Text(title)
                    .font(.inter(13, .semibold))
                    .foregroundStyle(Nuru.navy)
                Spacer()
                Text("\(pct)%")
                    .font(.inter(11, .regular))
                    .foregroundStyle(Nuru.muted)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.track)
                    Capsule().fill(color)
                        .frame(width: (revealed ? Double(pct) / 100 : 0) * geo.size.width)
                }
            }
            .frame(height: 8)
        }
        .onAppear {
            guard !revealed else { return }
            if reduceMotion { revealed = true; return }
            withAnimation(.spring(response: 0.7, dampingFraction: 0.85).delay(0.2)) { revealed = true }
        }
    }
}
