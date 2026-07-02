// Quiz — the native port of the Figma QuizScreen. One question at a time under a
// navy header (back circle · "MODULE QUIZ" overline · module title · gold
// progress pills), white option cards on a cool-grey canvas, and a white CTA bar
// whose gold button steps "Next Question" → "Submit Answers". The quiz stays
// server-assembled (answer signal stripped, §5.8) and server-scored (§3.7); the
// client only collects answers and submits. Each answer goes over the wire as a
// string: single-select → the choice id; checkbox → a JSON array of ids; scale →
// the number; short/paragraph → free text. The attempt is idempotent via a
// stable client_mutation_id (§2.1/§3.6); "Retry Quiz" starts a new attempt with
// a fresh id. Pass/fail/review outcomes render the Figma result screens using
// the server's score and pass mark — never client-scored.
import SwiftUI

@MainActor
final class QuizViewModel: ObservableObject {
    @Published var quiz: AssembledQuiz?
    @Published var moduleTitle: String?
    @Published var loading = true
    @Published var error: String?
    @Published var submitting = false
    @Published var result: QuizResult?

    // Per-question answer state.
    @Published var text: [String: String] = [:]          // single id / scale number / free text
    @Published var checks: [String: Set<String>] = [:]   // checkbox selections

    private let moduleId: String
    private(set) var clientMutationId = UUID().uuidString   // stable for this attempt
    init(moduleId: String) { self.moduleId = moduleId }

    func load() async {
        loading = true; error = nil
        do { quiz = try await MemberAPI.quiz(moduleId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load the quiz." }
        loading = false
        // Header title — best effort, never blocks the quiz itself.
        if moduleTitle == nil { moduleTitle = try? await MemberAPI.module(moduleId).title }
    }

    func toggleCheck(_ qid: String, _ choiceId: String) {
        var set = checks[qid] ?? []
        if set.contains(choiceId) { set.remove(choiceId) } else { set.insert(choiceId) }
        checks[qid] = set
    }

    /// True once the member has answered enough to move past this question.
    func answered(_ q: QuizQuestion) -> Bool {
        if q.required == false { return true }
        switch q.kind {
        case .checkbox:
            return !(checks[q.questionId] ?? []).isEmpty
        case .short, .paragraph:
            return !(text[q.questionId] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        default:
            return !(text[q.questionId] ?? "").isEmpty
        }
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

    /// Start a fresh attempt (fail-screen "Retry Quiz") — new idempotency key.
    func retry() {
        result = nil; error = nil
        text = [:]; checks = [:]
        clientMutationId = UUID().uuidString
    }
}

// Exact Figma palette (QuizScreen.tsx) — local so this page is 1:1 with the design.
private enum QZ {
    static let navy        = Color(hex: 0x0A1628)   // header / selected radio
    static let navyDeep    = Color(hex: 0x060F1C)   // pass-screen canvas
    static let gold        = Color(hex: 0xC9A227)
    static let bg          = Color(hex: 0xF7F9FC)   // question canvas
    static let ink         = Color(hex: 0x0B0B0C)
    static let kicker      = Color(hex: 0xB0B5BF)   // "QUESTION n OF m"
    static let copy        = Color(hex: 0x6B7280)   // result body copy
    static let radioIdle   = Color(hex: 0xD8DAE0)   // unselected radio ring
    static let cardBorder  = Color.black.opacity(0.08)
    static let selectedBg  = Color(hex: 0x0A2540, alpha: 0.06)
    static let ctaHairline = Color.black.opacity(0.07)
}

struct QuizView: View {
    let moduleId: String
    @StateObject private var vm: QuizViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var idx = 0   // current question

    init(moduleId: String) {
        self.moduleId = moduleId
        _vm = StateObject(wrappedValue: QuizViewModel(moduleId: moduleId))
    }

    var body: some View {
        ZStack {
            QZ.bg.ignoresSafeArea()
            if let result = vm.result {
                QuizResultScreen(result: result,
                                 onDone: { dismiss() },
                                 onRetry: { vm.retry(); idx = 0 })
            } else if vm.loading && vm.quiz == nil {
                ProgressView()
            } else if let quiz = vm.quiz, !quiz.questions.isEmpty {
                flow(quiz)
            } else {
                Text(vm.error ?? "Couldn't load the quiz.")
                    .font(.inter(14)).foregroundStyle(QZ.copy)
                    .padding(Nuru.S.screen)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task { if vm.quiz == nil { await vm.load() } }
    }

    // MARK: - One-question-at-a-time flow

    private func flow(_ quiz: AssembledQuiz) -> some View {
        let count = quiz.questions.count
        let safeIdx = min(idx, count - 1)
        let q = quiz.questions[safeIdx]
        return VStack(spacing: 0) {
            QuizHeader(title: vm.moduleTitle, index: safeIdx, count: count) {
                if safeIdx > 0 { withAnimation(.easeInOut(duration: 0.2)) { idx = safeIdx - 1 } }
                else { dismiss() }
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("QUESTION \(safeIdx + 1) OF \(count)")
                        .font(.inter(12, .semibold)).kerning(1)
                        .foregroundStyle(QZ.kicker)
                    Text(q.questionText)
                        .font(.inter(20, .bold)).kerning(-0.3)
                        .foregroundStyle(QZ.ink)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    answerArea(q)
                        .padding(.top, 28)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.lg)
                .padding(.bottom, Nuru.S.lg)
            }
            QuizCTABar(title: safeIdx < count - 1 ? "Next Question" : "Submit Answers",
                       enabled: vm.answered(q),
                       busy: vm.submitting,
                       error: vm.error) {
                if safeIdx < count - 1 {
                    withAnimation(.easeInOut(duration: 0.2)) { idx = safeIdx + 1 }
                } else {
                    Task { await vm.submit() }
                }
            }
        }
    }

    // MARK: - Answer renderers (Figma shows single-choice; the other server
    // question kinds share the same white-card language)

    @ViewBuilder
    private func answerArea(_ q: QuizQuestion) -> some View {
        switch q.kind {
        case .single:    choiceList(q, isCheckbox: false)
        case .checkbox:  choiceList(q, isCheckbox: true)
        case .scale:     scaleRow(q)
        case .short:     QuizFreeTextCard(text: textBinding(q), lines: 1)
        case .paragraph: QuizFreeTextCard(text: textBinding(q), lines: 4)
        }
    }

    private func choiceList(_ q: QuizQuestion, isCheckbox: Bool) -> some View {
        VStack(spacing: 12) {
            ForEach(q.choices) { c in
                let selected = isCheckbox
                    ? (vm.checks[q.questionId]?.contains(c.id) ?? false)
                    : vm.text[q.questionId] == c.id
                QuizOptionCard(label: c.text, selected: selected, isCheckbox: isCheckbox) {
                    if isCheckbox { vm.toggleCheck(q.questionId, c.id) }
                    else { vm.text[q.questionId] = c.id }
                }
            }
        }
    }

    private func scaleRow(_ q: QuizQuestion) -> some View {
        let scale = q.scale ?? QuestionScale(min: 1, max: 5, minLabel: nil, maxLabel: nil)
        let lo = min(scale.min, scale.max), hi = max(scale.min, scale.max)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ForEach(lo...hi, id: \.self) { n in
                    let sel = vm.text[q.questionId] == String(n)
                    Button { vm.text[q.questionId] = String(n) } label: {
                        Text("\(n)")
                            .font(.inter(16, sel ? .semibold : .regular))
                            .foregroundStyle(sel ? .white : QZ.ink)
                            .frame(width: 44, height: 44)
                            .background(sel ? QZ.navy : Color.white, in: Circle())
                            .overlay(Circle().stroke(sel ? QZ.navy : QZ.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
            }
            if scale.minLabel != nil || scale.maxLabel != nil {
                HStack {
                    Text(scale.minLabel ?? "").font(.inter(12)).foregroundStyle(QZ.kicker)
                    Spacer()
                    Text(scale.maxLabel ?? "").font(.inter(12)).foregroundStyle(QZ.kicker)
                }
            }
        }
    }

    private func textBinding(_ q: QuizQuestion) -> Binding<String> {
        Binding(get: { vm.text[q.questionId] ?? "" },
                set: { vm.text[q.questionId] = $0 })
    }
}

// MARK: - Navy header (back · overline · title · progress pills)

private struct QuizHeader: View {
    let title: String?
    let index: Int
    let count: Int
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button(action: onBack) {
                    Icon(.arrowLeft, size: 17, color: .white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MODULE QUIZ")
                        .font(.inter(11, .semibold)).kerning(0.9)
                        .foregroundStyle(Color.white.opacity(0.38))
                    Text(title ?? "Quiz")
                        .font(.inter(16, .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, 52)

            HStack(spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(i <= index ? QZ.gold : Color.white.opacity(0.18))
                        .frame(width: i == index ? 24 : 8, height: 7)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: index)
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(QZ.navy.ignoresSafeArea(edges: .top))
    }
}

// MARK: - Option card (white, 22px radio/checkbox, navy-selected)

private struct QuizOptionCard: View {
    let label: String
    let selected: Bool
    let isCheckbox: Bool
    let tap: () -> Void

    var body: some View {
        Button(action: tap) {
            HStack(spacing: 14) {
                indicator
                Text(label)
                    .font(.inter(16, selected ? .medium : .regular))
                    .foregroundStyle(QZ.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? QZ.selectedBg : Color.white,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? QZ.navy : QZ.cardBorder, lineWidth: 1.5))
            .shadow(color: selected ? QZ.navy.opacity(0.10) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var indicator: some View {
        if isCheckbox {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(QZ.navy)
                    Icon(.check, size: 13, color: .white)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(QZ.radioIdle, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
        } else {
            ZStack {
                if selected {
                    Circle().fill(QZ.navy)
                    Circle().fill(.white).frame(width: 8, height: 8)
                } else {
                    Circle().stroke(QZ.radioIdle, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
        }
    }
}

// MARK: - Free text (short / paragraph) in the same card language

private struct QuizFreeTextCard: View {
    @Binding var text: String
    let lines: Int

    var body: some View {
        TextField("Type your answer…", text: $text, axis: .vertical)
            .lineLimit(lines...max(lines, 6))
            .font(.inter(16))
            .foregroundStyle(QZ.ink)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(QZ.cardBorder, lineWidth: 1.5))
    }
}

// MARK: - White CTA bar with the gold step button

private struct QuizCTABar: View {
    let title: String
    let enabled: Bool
    let busy: Bool
    let error: String?
    let action: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let error {
                Text(error).font(.inter(12)).foregroundStyle(Nuru.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Button(action: action) {
                ZStack {
                    if busy { ProgressView().tint(QZ.navy) }
                    else { Text(title).font(.inter(16, .bold)).foregroundStyle(QZ.navy) }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(quizGoldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(enabled ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!enabled || busy)
        }
        .padding(.top, 16)
        .padding(.horizontal, Nuru.S.lg)
        .padding(.bottom, Nuru.S.md)
        .background(
            Color.white
                .overlay(Rectangle().fill(QZ.ctaHairline).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private let quizGoldGradient = LinearGradient(
    colors: [Color(hex: 0xC9A227), Color(hex: 0xB6862F)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

// MARK: - Result screens (server-scored, §3.7)

private struct QuizResultScreen: View {
    let result: QuizResult
    let onDone: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if result.requiresManualReview {
            QuizReviewScreen(onDone: onDone)
        } else if result.isPassed {
            QuizPassScreen(score: result.scoreAchieved,
                           unlockedNext: result.unlockedNextModuleId != nil,
                           onContinue: onDone)
        } else {
            QuizFailScreen(score: result.scoreAchieved,
                           passMark: result.passMark,
                           onReview: onDone,
                           onRetry: onRetry)
        }
    }
}

/// Pass — full navy-deep ceremony screen with concentric gold rings + medal.
private struct QuizPassScreen: View {
    let score: Int
    let unlockedNext: Bool
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            QZ.navyDeep.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                rings
                Text("\(score)%")
                    .font(.inter(52, .bold)).foregroundStyle(QZ.gold)
                    .padding(.top, 28)
                Text("Module Passed")
                    .font(.inter(22, .bold)).foregroundStyle(.white)
                    .padding(.top, 6)
                Text(unlockedNext
                     ? "The next module on your pathway is now unlocked."
                     : "You've completed this module's quiz.")
                    .font(.inter(15)).foregroundStyle(Color.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
                    .padding(.horizontal, 44)
                divider.padding(.top, 24)
                Spacer()
                Button(action: onContinue) {
                    Text("Continue Pathway")
                        .font(.inter(16, .bold)).foregroundStyle(QZ.navy)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(quizGoldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Nuru.S.lg)
                .padding(.bottom, Nuru.S.lg)
            }
        }
    }

    // Concentric rings (170/138/110) with the medal, ringed by six gold dots.
    private var rings: some View {
        ZStack {
            Circle().stroke(QZ.gold.opacity(0.15), lineWidth: 1).frame(width: 170, height: 170)
            Circle().stroke(QZ.gold.opacity(0.30), lineWidth: 1).frame(width: 138, height: 138)
            Circle().fill(QZ.gold.opacity(0.09)).frame(width: 110, height: 110)
                .overlay(Circle().stroke(QZ.gold.opacity(0.45), lineWidth: 1))
            Text("🏅").font(.system(size: 44))
            ForEach(0..<6, id: \.self) { i in
                let a = Double(i) * .pi / 3
                Circle().fill(QZ.gold).frame(width: 5, height: 5)
                    .offset(x: 82 * cos(a), y: 82 * sin(a))
            }
        }
        .frame(width: 170, height: 170)
    }

    private var divider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(QZ.gold.opacity(0.35)).frame(height: 1)
            Circle().fill(QZ.gold).frame(width: 4, height: 4)
            Rectangle().fill(QZ.gold.opacity(0.35)).frame(height: 1)
        }
        .frame(width: 200)
    }
}

/// Fail — light screen, 📖 disc, score, "Almost there", review/retry actions.
private struct QuizFailScreen: View {
    let score: Int
    let passMark: Int
    let onReview: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            QZ.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Circle().fill(Color(hex: 0x0A2540, alpha: 0.07))
                    .frame(width: 100, height: 100)
                    .overlay(Text("📖").font(.system(size: 44)))
                Text("\(score)%")
                    .font(.inter(44, .bold)).foregroundStyle(QZ.ink)
                    .padding(.top, 24)
                Text("Almost there")
                    .font(.inter(22, .bold)).foregroundStyle(QZ.ink)
                    .padding(.top, 6)
                Text("You need \(passMark)% to pass. Take a moment to review the lesson — you've got this.")
                    .font(.inter(16)).foregroundStyle(QZ.copy)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.horizontal, 36)
                Spacer()
                VStack(spacing: 10) {
                    Button(action: onReview) {
                        Text("Review Lesson")
                            .font(.inter(16, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(QZ.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    Button(action: onRetry) {
                        Text("Retry Quiz")
                            .font(.inter(16, .semibold)).foregroundStyle(QZ.navy)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(hex: 0x0A2540, alpha: 0.15), lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, Nuru.S.lg)
                .padding(.bottom, Nuru.S.lg)
            }
        }
    }
}

/// Manual review — written answers go to a mentor; no instant pass/fail.
private struct QuizReviewScreen: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            QZ.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Circle().fill(Color(hex: 0x0A2540, alpha: 0.07))
                    .frame(width: 100, height: 100)
                    .overlay(Text("✍️").font(.system(size: 44)))
                Text("Submitted for review")
                    .font(.inter(22, .bold)).foregroundStyle(QZ.ink)
                    .padding(.top, 24)
                Text("Your written answers were sent to your mentor to review. You'll be notified once they're scored.")
                    .font(.inter(16)).foregroundStyle(QZ.copy)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.horizontal, 36)
                Spacer()
                Button(action: onDone) {
                    Text("Back to Lesson")
                        .font(.inter(16, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(QZ.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, Nuru.S.lg)
                .padding(.bottom, Nuru.S.lg)
            }
        }
    }
}
