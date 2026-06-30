// Quiz — the native port of screens/QuizScreen.tsx. The quiz is server-assembled
// (answer signal stripped, §5.8) and server-scored (§3.7); the client only
// collects answers and submits. Each answer goes over the wire as a string:
// single-select → the choice id; checkbox → a JSON array of ids; scale → the
// number; short/paragraph → free text. The attempt is idempotent via a stable
// client_mutation_id (§2.1/§3.6).
import SwiftUI

@MainActor
final class QuizViewModel: ObservableObject {
    @Published var quiz: AssembledQuiz?
    @Published var loading = true
    @Published var error: String?
    @Published var submitting = false
    @Published var result: QuizResult?

    // Per-question answer state.
    @Published var text: [String: String] = [:]          // single id / scale number / free text
    @Published var checks: [String: Set<String>] = [:]   // checkbox selections

    private let moduleId: String
    private let clientMutationId = UUID().uuidString   // stable for this attempt
    init(moduleId: String) { self.moduleId = moduleId }

    func load() async {
        loading = true; error = nil
        do { quiz = try await MemberAPI.quiz(moduleId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load the quiz." }
        loading = false
    }

    func toggleCheck(_ qid: String, _ choiceId: String) {
        var set = checks[qid] ?? []
        if set.contains(choiceId) { set.remove(choiceId) } else { set.insert(choiceId) }
        checks[qid] = set
    }

    func submit() async {
        guard let quiz else { return }
        submitting = true; defer { submitting = false }
        let answers: [QuizAnswer] = quiz.questions.map { q in
            let given: String
            switch q.kind {
            case .checkbox:
                let ids = Array(checks[q.questionId] ?? [])
                given = (try? String(data: JSONSerialization.data(withJSONObject: ids), encoding: .utf8) ?? "[]") ?? "[]"
            default:
                given = text[q.questionId] ?? ""
            }
            return QuizAnswer(questionId: q.questionId, givenAnswer: given)
        }
        do {
            result = try await MemberAPI.submitQuiz(moduleId, clientMutationId: clientMutationId, answers: answers)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't submit. Please try again."
        }
    }
}

struct QuizView: View {
    let moduleId: String
    @StateObject private var vm: QuizViewModel
    @Environment(\.dismiss) private var dismiss

    init(moduleId: String) {
        self.moduleId = moduleId
        _vm = StateObject(wrappedValue: QuizViewModel(moduleId: moduleId))
    }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            if let result = vm.result {
                ResultView(result: result) { dismiss() }
            } else if vm.loading && vm.quiz == nil {
                ProgressView()
            } else if let quiz = vm.quiz {
                form(quiz)
            } else {
                Text(vm.error ?? "Couldn't load the quiz.").font(.nBody).foregroundStyle(Nuru.muted)
            }
        }
        .navigationTitle("Quiz")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.quiz == nil { await vm.load() } }
    }

    private func form(_ quiz: AssembledQuiz) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                Text("\(quiz.questionCount) question\(quiz.questionCount == 1 ? "" : "s")")
                    .font(.nCaption).foregroundStyle(Nuru.muted)
                ForEach(Array(quiz.questions.enumerated()), id: \.element.id) { idx, q in
                    questionCard(idx + 1, q)
                }
                if let error = vm.error {
                    Text(error).font(.nCaption).foregroundStyle(Nuru.danger)
                }
                PButton(title: "Submit", variant: .gold, busy: vm.submitting) {
                    Task { await vm.submit() }
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    private func questionCard(_ number: Int, _ q: QuizQuestion) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("\(number). \(q.questionText)").font(.nHeading).foregroundStyle(Nuru.ink)
                switch q.kind {
                case .single:   singleSelect(q)
                case .checkbox: checkboxSelect(q)
                case .scale:    scaleSelect(q)
                case .short:    freeText(q, lines: 1)
                case .paragraph: freeText(q, lines: 4)
                }
            }
        }
    }

    // MARK: question renderers

    private func singleSelect(_ q: QuizQuestion) -> some View {
        VStack(spacing: Nuru.S.sm) {
            ForEach(q.choices) { c in
                optionRow(label: c.text, selected: vm.text[q.questionId] == c.id) {
                    vm.text[q.questionId] = c.id
                }
            }
        }
    }

    private func checkboxSelect(_ q: QuizQuestion) -> some View {
        VStack(spacing: Nuru.S.sm) {
            ForEach(q.choices) { c in
                optionRow(label: c.text, selected: vm.checks[q.questionId]?.contains(c.id) ?? false, isCheckbox: true) {
                    vm.toggleCheck(q.questionId, c.id)
                }
            }
        }
    }

    private func scaleSelect(_ q: QuizQuestion) -> some View {
        let scale = q.scale ?? QuestionScale(min: 1, max: 5, minLabel: nil, maxLabel: nil)
        let lo = min(scale.min, scale.max), hi = max(scale.min, scale.max)
        return VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(lo...hi, id: \.self) { n in
                    let sel = vm.text[q.questionId] == String(n)
                    Button { vm.text[q.questionId] = String(n) } label: {
                        Text("\(n)")
                            .font(.inter(15, .semibold))
                            .frame(width: 40, height: 40)
                            .foregroundStyle(sel ? .white : Nuru.ink)
                            .background(sel ? Nuru.gold : Nuru.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if scale.minLabel != nil || scale.maxLabel != nil {
                HStack {
                    Text(scale.minLabel ?? "").font(.nMicro).foregroundStyle(Nuru.faint)
                    Spacer()
                    Text(scale.maxLabel ?? "").font(.nMicro).foregroundStyle(Nuru.faint)
                }
            }
        }
    }

    private func freeText(_ q: QuizQuestion, lines: Int) -> some View {
        TextField("Your answer", text: Binding(
            get: { vm.text[q.questionId] ?? "" },
            set: { vm.text[q.questionId] = $0 }
        ), axis: .vertical)
        .lineLimit(lines...max(lines, 6))
        .font(.nBody)
        .padding(Nuru.S.md)
        .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }

    private func optionRow(label: String, selected: Bool, isCheckbox: Bool = false, tap: @escaping () -> Void) -> some View {
        Button(action: tap) {
            HStack(spacing: Nuru.S.md) {
                Image(systemName: selected
                      ? (isCheckbox ? "checkmark.square.fill" : "largecircle.fill.circle")
                      : (isCheckbox ? "square" : "circle"))
                    .font(.system(size: 18))
                    .foregroundStyle(selected ? Nuru.gold : Nuru.ink300)
                Text(label).font(.nBody).foregroundStyle(Nuru.ink)
                Spacer(minLength: 0)
            }
            .padding(Nuru.S.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Nuru.goldChipBg : Nuru.surface,
                        in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// The graded outcome — server-scored (§3.7). On pass, the next module is unlocked.
private struct ResultView: View {
    let result: QuizResult
    let done: () -> Void

    var body: some View {
        VStack(spacing: Nuru.S.lg) {
            Spacer()
            ZStack {
                Circle().fill(result.isPassed ? Nuru.successBg : Nuru.urgentBg).frame(width: 96, height: 96)
                Image(systemName: result.isPassed ? "checkmark" : (result.requiresManualReview ? "hourglass" : "arrow.counterclockwise"))
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(result.isPassed ? Nuru.success : Nuru.urgentText)
            }
            Text(result.requiresManualReview ? "Submitted for review"
                 : (result.isPassed ? "Passed!" : "Not quite yet"))
                .font(.nTitle).foregroundStyle(Nuru.ink)
            if !result.requiresManualReview {
                Text("You scored \(result.scoreAchieved)% · pass mark \(result.passMark)%")
                    .font(.nBody).foregroundStyle(Nuru.muted)
            } else {
                Text("Your responses were sent to your mentor to review.")
                    .font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            }
            if result.isPassed && result.unlockedNextModuleId != nil {
                Text("The next module is now unlocked.")
                    .font(.nCaption).foregroundStyle(Nuru.success)
            }
            Spacer()
            PButton(title: result.isPassed ? "Continue" : "Back to lesson", variant: .gold, action: done)
        }
        .padding(Nuru.S.screen)
    }
}
