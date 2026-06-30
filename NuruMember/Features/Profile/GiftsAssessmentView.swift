// Spiritual Gifts assessment — the native port of the RN gifts questionnaire.
// A server-assembled Likert (1–5) question set (possibly AI-tuned per member,
// §3.x); the client only collects answers and submits. Scoring + persona
// derivation happen server-side; on success we pop back to "Your Calling"
// (GiftsView), which reloads myGifts() and renders the result.
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

    var total: Int { questionSet?.data.count ?? 0 }
    var answered: Int { chosen.values.count }
    var allAnswered: Bool { total > 0 && answered == total }
    var progress: Double { total == 0 ? 0 : Double(answered) / Double(total) }

    func load() async {
        loading = true; error = nil
        do { questionSet = try await MemberAPI.giftQuestions() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load the assessment." }
        loading = false
    }

    /// Builds the answer payload and submits. Returns true on success so the view
    /// can dismiss back to the read screen.
    func submit() async -> Bool {
        guard let questionSet, allAnswered else { return false }
        submitting = true; submitError = nil
        defer { submitting = false }
        let answers = questionSet.data.map { GiftAnswerInput(questionId: $0.questionId, value: chosen[$0.questionId] ?? 0) }
        do {
            _ = try await MemberAPI.submitGifts(setId: questionSet.setId,
                                                clientMutationId: UUID().uuidString,
                                                answers: answers)
            return true
        } catch {
            submitError = (error as? APIError)?.errorDescription ?? "Couldn't submit. Please try again."
            return false
        }
    }
}

// MARK: - Screen

struct GiftsAssessmentView: View {
    @StateObject private var vm = GiftsAssessmentViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Left accent-bar colours, cycled per card by index.
    private let accents: [Color] = [
        Color(hex: 0x7C5CFC),   // purple
        Color(hex: 0x3B82F6),   // blue
        Color(hex: 0x2E9E6B),   // green
        Nuru.gold,              // gold
        Color(hex: 0xE0564B),   // red
    ]

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

    // MARK: header

    private var header: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.onNavy)
                    .frame(width: 38, height: 38)
                    .background(Nuru.navyDeep, in: Circle())
            }
            .buttonStyle(.plain)
            Text("Spiritual gifts")
                .font(.fraunces(22, .semibold))
                .foregroundStyle(Nuru.white)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.base)
        .background(Nuru.navy.ignoresSafeArea(edges: .top))
    }

    // MARK: body states

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.questionSet == nil {
            Spacer(); ProgressView().tint(Nuru.gold); Spacer()
        } else if let qs = vm.questionSet {
            questionnaire(qs)
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

    private func questionnaire(_ qs: GiftQuestionSet) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                heroCard
                ForEach(Array(qs.data.enumerated()), id: \.element.id) { idx, q in
                    questionCard(q, accent: accents[idx % accents.count])
                }
                if let err = vm.submitError {
                    Text(err).font(.nCaption).foregroundStyle(Nuru.danger)
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .safeAreaInset(edge: .bottom) { submitBar }
    }

    // MARK: hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            Icon(.sparkles, size: 22, color: Nuru.onNavy)
            Text("Discover how God wired you")
                .font(.fraunces(22, .semibold))
                .foregroundStyle(Nuru.white)
                .fixedSize(horizontal: false, vertical: true)
            Text("Chosen for you by Nuru, from your journey so far.")
                .font(.nCaption)
                .foregroundStyle(Nuru.onNavyDim)
                .fixedSize(horizontal: false, vertical: true)

            Text("\(vm.answered) of \(vm.total) answered")
                .font(.inter(12, .semibold))
                .foregroundStyle(Nuru.onNavy)
                .padding(.top, Nuru.S.xs)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(Color.white.opacity(0.9))
                        .frame(width: max(0, geo.size.width * vm.progress))
                }
            }
            .frame(height: 4)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Color(hex: 0x8B5CF6), Color(hex: 0x6D3FD6), Color(hex: 0x4C2A9E)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
        )
        .nuruShadow()
    }

    // MARK: question card

    private func questionCard(_ q: GiftQuestion, accent: Color) -> some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(accent)
                .frame(width: 4)
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text(q.prompt)
                    .font(.nBodyLg).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                likertRow(q)
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    private func likertRow(_ q: GiftQuestion) -> some View {
        VStack(spacing: Nuru.S.xs) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(1...5, id: \.self) { n in
                    let selected = vm.chosen[q.questionId] == n
                    Button { vm.chosen[q.questionId] = n } label: {
                        Text("\(n)")
                            .font(.inter(15, .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .foregroundStyle(selected ? Nuru.onNavy : Nuru.muted)
                            .background(
                                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                                    .fill(selected ? Nuru.navy : Nuru.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                                    .stroke(selected ? Color.clear : Nuru.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                Text("Rarely").font(.nMicro).foregroundStyle(Nuru.faint)
                Spacer()
                Text("Strongly agree").font(.nMicro).foregroundStyle(Nuru.faint)
            }
        }
    }

    // MARK: sticky submit

    private var submitBar: some View {
        VStack(spacing: 0) {
            PButton(title: vm.allAnswered ? "See my results" : "Submit",
                    variant: .gold,
                    busy: vm.submitting,
                    disabled: !vm.allAnswered) {
                Task {
                    if await vm.submit() { dismiss() }
                }
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, Nuru.S.md)
            .padding(.bottom, Nuru.S.base)
        }
        .background(Nuru.paper.opacity(0.96).ignoresSafeArea(edges: .bottom))
    }
}
