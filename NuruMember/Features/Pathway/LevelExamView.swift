// Level exam — the ceremonial big sibling of QuizView (the level gate, §1.9
// rule 2). One question at a time under a navy header ("LEVEL N EXAM" overline,
// a gold seal, and a continuous gold progress bar — the paper spans the level's
// WHOLE question pool, so pills would overflow), the same white option cards,
// and a white CTA bar stepping "Next Question" → "Submit Exam".
//
// Server-authoritative throughout: the paper arrives assembled with the
// correct-answer signal stripped (§5.8); every attempt is scored server-side
// against levels.required_exam_pass_mark and the client renders ONLY the
// server's verdict — never grades locally, never reveals answers. Attempts are
// idempotent on a stable client_mutation_id (§2.1/§3.6); "Retry Exam" mints a
// fresh id. If the server says the gate isn't open (GATE_LOCKED — modules
// remaining or a locked level) that answer is surfaced honestly, not hidden.
import SwiftUI

@MainActor
final class LevelExamViewModel: ObservableObject {
    @Published var exam: AssembledExam?
    @Published var levelTitle: String?
    @Published var loading = true
    @Published var notEligible: String?   // the server's own GATE_LOCKED/UNPROCESSABLE explanation
    @Published var error: String?
    @Published var submitting = false
    @Published var result: ExamResult?

    // Per-question answer state (same wire idiom as the module quiz).
    @Published var text: [String: String] = [:]          // single id / scale number / free text
    @Published var checks: [String: Set<String>] = [:]   // checkbox selections

    let levelNumber: Int
    private(set) var clientMutationId = UUID().uuidString   // stable for this attempt
    init(levelNumber: Int) { self.levelNumber = levelNumber }

    func load() async {
        loading = true; error = nil; notEligible = nil
        do { exam = try await MemberAPI.levelExam(levelNumber) }
        catch { classify(error) }
        loading = false
        // Header title — best effort, never blocks the exam itself.
        if levelTitle == nil {
            levelTitle = (try? await MemberAPI.pathway())?.levels.first { $0.levelNumber == levelNumber }?.title
        }
    }

    /// GATE_LOCKED ("finish every module…" / "level is locked") and UNPROCESSABLE
    /// ("no exam questions yet" / "no active enrollment") are honest server states,
    /// not failures — everything else is a genuine load error worth retrying.
    private func classify(_ error: Error) {
        if case let APIError.http(_, code, message) = error,
           code == "GATE_LOCKED" || code == "UNPROCESSABLE" {
            notEligible = message
        } else {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't load the exam."
        }
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
        guard let exam else { return }
        submitting = true; error = nil   // clear a stale submit error before retrying
        defer { submitting = false }
        let answers: [QuizAnswer] = exam.questions.map { q in
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
            result = try await MemberAPI.submitLevelExam(levelNumber, clientMutationId: clientMutationId, answers: answers)
        } catch {
            if case let APIError.http(_, code, message) = error, code == "GATE_LOCKED" {
                notEligible = message   // the gate closed between assemble and submit
            } else {
                self.error = (error as? APIError)?.errorDescription ?? "Couldn't submit. Please try again."
                Haptics.error()
            }
        }
    }

    /// Start a fresh attempt (fail-screen "Retry Exam") — new idempotency key.
    func retry() {
        result = nil; error = nil
        text = [:]; checks = [:]
        clientMutationId = UUID().uuidString
    }
}

// Exam palette — the quiz's exact Figma palette so the exam reads as its sibling.
private enum EX {
    static let navy        = Color(hex: 0x0A1628)   // header / selected radio
    static let navyDeep    = Color(hex: 0x060F1C)   // pass-screen canvas
    static let gold        = Color(hex: 0xC9A227)
    static let goldLight   = Color(hex: 0xE6C068)
    static let bg          = Color(hex: 0xF7F9FC)   // question canvas
    static let ink         = Color(hex: 0x0B0B0C)
    static let kicker      = Color(hex: 0xB0B5BF)   // "QUESTION n OF m"
    static let copy        = Color(hex: 0x5B6472)   // result body copy
    static let radioIdle   = Color(hex: 0xD8DAE0)   // unselected radio ring
    static let cardBorder  = Color.black.opacity(0.08)
    static let selectedBg  = Color(hex: 0x0A2540, alpha: 0.06)
    static let ctaHairline = Color.black.opacity(0.07)
}

private let examGoldGradient = LinearGradient(
    colors: [Color(hex: 0xC9A227), Color(hex: 0xB6862F)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

struct LevelExamView: View {
    let levelNumber: Int
    /// Passed from PathwayView — advances into the next module after a pass.
    /// nil (e.g. from the Grow stack) falls back to just dismissing.
    var onPassContinue: (() -> Void)? = nil
    @StateObject private var vm: LevelExamViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var idx = 0   // current question

    init(levelNumber: Int, onPassContinue: (() -> Void)? = nil) {
        self.levelNumber = levelNumber
        self.onPassContinue = onPassContinue
        _vm = StateObject(wrappedValue: LevelExamViewModel(levelNumber: levelNumber))
    }

    var body: some View {
        ZStack {
            EX.bg.ignoresSafeArea()
            if let result = vm.result {
                ExamResultScreen(levelNumber: levelNumber, result: result,
                                 onDone: { dismiss() },
                                 onPassContinue: { (onPassContinue ?? { dismiss() })() },
                                 onRetry: { vm.retry(); idx = 0 })
            } else if vm.loading && vm.exam == nil {
                examSkeleton
            } else if let reason = vm.notEligible {
                ExamNotEligibleScreen(levelNumber: levelNumber, reason: reason) { dismiss() }
            } else if let exam = vm.exam, !exam.questions.isEmpty {
                flow(exam)
            } else {
                loadFailed
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task { if vm.exam == nil { await vm.load() } }
    }

    // MARK: - One-question-at-a-time flow (QuizView's idiom)

    private func flow(_ exam: AssembledExam) -> some View {
        let count = exam.questions.count
        let safeIdx = min(idx, count - 1)
        let q = exam.questions[safeIdx]
        return VStack(spacing: 0) {
            ExamHeader(levelNumber: levelNumber, title: vm.levelTitle, index: safeIdx, count: count) {
                if safeIdx > 0 { withAnimation(.easeInOut(duration: 0.25)) { idx = safeIdx - 1 } }
                else { dismiss() }
            }
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("QUESTION \(safeIdx + 1) OF \(count)")
                        .font(.inter(12, .semibold)).kerning(1)
                        .foregroundStyle(EX.kicker)
                    Text(q.questionText)
                        .font(.inter(20, .bold)).kerning(-0.3)
                        .foregroundStyle(EX.ink)
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
                .id(safeIdx)
                .transition(reduceMotion
                            ? .opacity
                            : .asymmetric(insertion: .opacity.combined(with: .offset(x: 24)),
                                          removal: .opacity.combined(with: .offset(x: -24))))
            }
            ExamCTABar(title: safeIdx < count - 1 ? "Next Question" : "Submit Exam",
                       enabled: vm.answered(q),
                       busy: vm.submitting,
                       error: vm.error) {
                Haptics.action()
                if safeIdx < count - 1 {
                    withAnimation(.easeInOut(duration: 0.25)) { idx = safeIdx + 1 }
                } else {
                    Task { await vm.submit() }
                }
            }
        }
    }

    // MARK: - First-load skeleton (header block + question + option-card placeholders)

    private var examSkeleton: some View {
        VStack(spacing: 0) {
            Rectangle().fill(EX.navy).frame(height: 158)   // where the navy header sits
                .ignoresSafeArea(edges: .top)
            VStack(alignment: .leading, spacing: 0) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: 0x0A2540, alpha: 0.08)).frame(width: 130, height: 10)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(hex: 0x0A2540, alpha: 0.08)).frame(maxWidth: .infinity).frame(height: 18)
                    .padding(.top, 16)
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color(hex: 0x0A2540, alpha: 0.08)).frame(width: 190, height: 18)
                    .padding(.top, 8)
                VStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.white)
                            .frame(height: 56)
                            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(EX.cardBorder, lineWidth: 1.5))
                    }
                }
                .padding(.top, 28)
            }
            .padding(.horizontal, Nuru.S.screen)
            Spacer()
        }
        .nuruShimmer()
        .accessibilityLabel("Loading the exam")
    }

    private var loadFailed: some View {
        VStack(spacing: Nuru.S.md) {
            Text(vm.error ?? "Couldn't load the exam.")
                .font(.inter(14)).foregroundStyle(EX.copy).multilineTextAlignment(.center)
            Button {
                Haptics.tap()
                Task { await vm.load() }
            } label: {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(EX.navy)
                    .padding(.horizontal, 20).padding(.vertical, 10)
                    .background(examGoldGradient, in: Capsule())
            }
            .buttonStyle(.pressable)
            Button { Haptics.tap(); dismiss() } label: {
                Text("Back").font(.inter(13, .semibold)).foregroundStyle(EX.copy)
                    .padding(.horizontal, 20).padding(.vertical, 10)
            }
            .buttonStyle(.pressable)
        }
        .padding(Nuru.S.screen)
    }

    // MARK: - Answer renderers (same white-card language as the quiz)

    @ViewBuilder
    private func answerArea(_ q: QuizQuestion) -> some View {
        switch q.kind {
        case .single:    choiceList(q, isCheckbox: false)
        case .checkbox:  choiceList(q, isCheckbox: true)
        case .scale:     scaleRow(q)
        case .short:     ExamFreeTextCard(text: textBinding(q), lines: 1)
        case .paragraph: ExamFreeTextCard(text: textBinding(q), lines: 4)
        }
    }

    private func choiceList(_ q: QuizQuestion, isCheckbox: Bool) -> some View {
        VStack(spacing: 12) {
            ForEach(q.choices) { c in
                let selected = isCheckbox
                    ? (vm.checks[q.questionId]?.contains(c.id) ?? false)
                    : vm.text[q.questionId] == c.id
                ExamOptionCard(label: c.text, selected: selected, isCheckbox: isCheckbox) {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if isCheckbox { vm.toggleCheck(q.questionId, c.id) }
                        else { vm.text[q.questionId] = c.id }
                    }
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
                    Button {
                        Haptics.selection()
                        withAnimation(.easeInOut(duration: 0.15)) { vm.text[q.questionId] = String(n) }
                    } label: {
                        Text("\(n)")
                            .font(.inter(16, sel ? .semibold : .regular))
                            .foregroundStyle(sel ? .white : EX.ink)
                            .frame(width: 44, height: 44)
                            .background(sel ? EX.navy : Color.white, in: Circle())
                            .overlay(Circle().stroke(sel ? EX.navy : EX.cardBorder, lineWidth: 1.5))
                    }
                    .buttonStyle(.pressable)
                }
            }
            if scale.minLabel != nil || scale.maxLabel != nil {
                HStack {
                    Text(scale.minLabel ?? "").font(.inter(12)).foregroundStyle(EX.kicker)
                    Spacer()
                    Text(scale.maxLabel ?? "").font(.inter(12)).foregroundStyle(EX.kicker)
                }
            }
        }
    }

    private func textBinding(_ q: QuizQuestion) -> Binding<String> {
        Binding(get: { vm.text[q.questionId] ?? "" },
                set: { vm.text[q.questionId] = $0 })
    }
}

// MARK: - Navy header (back · gold seal · overline · title · continuous progress)
// The exam spans the level's whole pool (often 15–30 questions), so the quiz's
// per-question pills would overflow — a single gold bar carries the progress.

private struct ExamHeader: View {
    let levelNumber: Int
    let title: String?
    let index: Int
    let count: Int
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                Button { Haptics.tap(); onBack() } label: {
                    Icon(.arrowLeft, size: 17, color: .white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.pressable)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Icon(.award, size: 11, color: EX.gold)
                        Text("LEVEL \(levelNumber) EXAM")
                            .font(.inter(11, .semibold)).kerning(0.9)
                            .foregroundStyle(EX.goldLight.opacity(0.85))
                    }
                    Text(title ?? "Level \(levelNumber)")
                        .font(.inter(16, .semibold)).foregroundStyle(.white)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, 52)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule().fill(examGoldGradient)
                        .frame(width: geo.size.width * CGFloat(index + 1) / CGFloat(max(count, 1)))
                        .animation(.easeInOut(duration: 0.25), value: index)
                }
            }
            .frame(height: 7)
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, 18)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EX.navy.ignoresSafeArea(edges: .top))
        .overlay(alignment: .bottom) { Rectangle().fill(EX.gold.opacity(0.45)).frame(height: 1) }
    }
}

// MARK: - Option card (white, 22px radio/checkbox, navy-selected)

private struct ExamOptionCard: View {
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
                    .foregroundStyle(EX.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .background(selected ? EX.selectedBg : Color.white,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(selected ? EX.navy : EX.cardBorder, lineWidth: 1.5))
            .shadow(color: selected ? EX.navy.opacity(0.10) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder
    private var indicator: some View {
        if isCheckbox {
            ZStack {
                if selected {
                    RoundedRectangle(cornerRadius: 6, style: .continuous).fill(EX.navy)
                    Icon(.check, size: 13, color: .white)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(EX.radioIdle, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
        } else {
            ZStack {
                if selected {
                    Circle().fill(EX.navy)
                    Circle().fill(.white).frame(width: 8, height: 8)
                } else {
                    Circle().stroke(EX.radioIdle, lineWidth: 2)
                }
            }
            .frame(width: 22, height: 22)
        }
    }
}

// MARK: - Free text (short / paragraph) in the same card language

private struct ExamFreeTextCard: View {
    @Binding var text: String
    let lines: Int

    var body: some View {
        TextField("Type your answer…", text: $text, axis: .vertical)
            .lineLimit(lines...max(lines, 6))
            .font(.inter(16))
            .foregroundStyle(EX.ink)
            .padding(.vertical, 16)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(EX.cardBorder, lineWidth: 1.5))
    }
}

// MARK: - White CTA bar with the gold step button

private struct ExamCTABar: View {
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
                    .transition(.opacity)
            }
            Button(action: action) {
                ZStack {
                    if busy { ProgressView().tint(EX.navy) }
                    else { Text(title).font(.inter(16, .bold)).foregroundStyle(EX.navy) }
                }
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(examGoldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .opacity(enabled ? 1 : 0.45)
            }
            .buttonStyle(.pressable)
            .disabled(!enabled || busy)
            .animation(.easeInOut(duration: 0.2), value: enabled)
        }
        .animation(.easeInOut(duration: 0.2), value: error != nil)
        .padding(.top, 16)
        .padding(.horizontal, Nuru.S.lg)
        .padding(.bottom, Nuru.S.md)
        .background(
            Color.white
                .overlay(Rectangle().fill(EX.ctaHairline).frame(height: 1), alignment: .top)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Not eligible (the server said the gate isn't open — honest, kind)

private struct ExamNotEligibleScreen: View {
    let levelNumber: Int
    let reason: String
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Circle().fill(Color(hex: 0x0A2540, alpha: 0.07))
                .frame(width: 100, height: 100)
                .overlay(Icon(.lock, size: 36, color: EX.copy))
            Text("The gate isn't open yet")
                .font(.inter(22, .bold)).foregroundStyle(EX.ink)
                .padding(.top, 24)
            Text(reason)
                .font(.inter(16)).foregroundStyle(EX.copy)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .padding(.top, 10)
                .padding(.horizontal, 36)
            Text("Finish every module in Level \(levelNumber), then come back — the exam will be waiting.")
                .font(.inter(13)).foregroundStyle(EX.kicker)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 12)
                .padding(.horizontal, 44)
            Spacer()
            Button { Haptics.tap(); onBack() } label: {
                Text("Back to Level")
                    .font(.inter(16, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(EX.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.horizontal, Nuru.S.lg)
            .padding(.bottom, Nuru.S.lg)
        }
        .gentleEntrance()
    }
}

// MARK: - Result screens (server-scored — the verdict is rendered, never computed)

private struct ExamResultScreen: View {
    let levelNumber: Int
    let result: ExamResult
    let onDone: () -> Void
    let onPassContinue: () -> Void
    let onRetry: () -> Void

    var body: some View {
        if result.isPassed {
            ExamPassScreen(levelNumber: levelNumber,
                           score: result.scoreAchieved,
                           mentorReview: result.requiresManualReview,
                           onContinue: onPassContinue)
        } else if result.requiresManualReview {
            ExamReviewScreen(onDone: onDone)
        } else {
            ExamFailScreen(levelNumber: levelNumber,
                           score: result.scoreAchieved,
                           passMark: result.passMark,
                           onReview: onDone,
                           onRetry: onRetry)
        }
    }
}

/// Pass — the full gold ceremony. Deeper navy, larger concentric rings and a
/// laurel of gold dots that bloom in a stagger; a success haptic lands on
/// arrival. This is the level gate, so it celebrates a touch harder than the
/// module quiz — the score and verdict shown are the server's, untouched.
private struct ExamPassScreen: View {
    let levelNumber: Int
    let score: Int
    let mentorReview: Bool
    let onContinue: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bloomed = false
    @State private var advancing = false   // Continue tapped — loading the next module

    var body: some View {
        ZStack {
            EX.navyDeep.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                rings
                    .scaleEffect(bloomed ? 1 : 0.82)
                    .opacity(bloomed ? 1 : 0)
                // The verdict number — labelled so it reads plainly as the score.
                Text("MARKS SCORED")
                    .font(.inter(12, .bold)).kerning(2)
                    .foregroundStyle(EX.gold.opacity(0.7))
                    .padding(.top, 26)
                    .gentleEntrance(delay: 0.06)
                Text("\(score)%")
                    .font(.inter(56, .bold)).foregroundStyle(EX.gold)
                    .padding(.top, 4)
                    .gentleEntrance(delay: 0.1)
                Text("Level \(levelNumber) Complete")
                    .font(.fraunces(24, .semibold)).foregroundStyle(.white)
                    .padding(.top, 6)
                    .gentleEntrance(delay: 0.18)
                // §1.9 (new): passing no longer auto-advances — the member now waits
                // to be ushered by a discipler. The copy is a dignified handoff.
                Text(mentorReview
                     ? "A true milestone. Some written answers went to your mentor to read — and your discipler will usher you onward. 🌿"
                     : "A true milestone. Awaiting your discipler's blessing to continue to the next level. 🌿")
                    .font(.inter(15)).foregroundStyle(Color.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.horizontal, 40)
                    .gentleEntrance(delay: 0.26)
                divider.padding(.top, 24)
                Spacer()
                Button {
                    guard !advancing else { return }
                    advancing = true
                    Haptics.tap()
                    onContinue()   // refresh the pathway + return to the hub (no jump)
                } label: {
                    Group {
                        if advancing {
                            HStack(spacing: 8) {
                                ProgressView().tint(EX.navy)
                                Text("Returning to your pathway…").font(.inter(16, .bold)).foregroundStyle(EX.navy)
                            }
                        } else {
                            Text("Back to your pathway").font(.inter(16, .bold)).foregroundStyle(EX.navy)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(examGoldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, Nuru.S.lg)
                .padding(.bottom, Nuru.S.lg)
            }
            // Confetti over the whole ceremony — fires on arrival, once.
            CelebrationConfetti().allowsHitTesting(false)
        }
        .onAppear {
            Haptics.success()
            guard !bloomed else { return }
            if reduceMotion { bloomed = true }
            else { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { bloomed = true } }
        }
    }

    // Concentric rings (190/154/122) with the trophy, laurelled by eight gold
    // dots that arrive one after another — the exam's bigger bloom.
    private var rings: some View {
        ZStack {
            Circle().stroke(EX.gold.opacity(0.15), lineWidth: 1).frame(width: 190, height: 190)
            Circle().stroke(EX.gold.opacity(0.30), lineWidth: 1).frame(width: 154, height: 154)
            Circle().fill(EX.gold.opacity(0.09)).frame(width: 122, height: 122)
                .overlay(Circle().stroke(EX.gold.opacity(0.45), lineWidth: 1))
            Text("🏆").font(.system(size: 50))
            ForEach(0..<8, id: \.self) { i in
                let a = Double(i) * .pi / 4
                Circle().fill(EX.gold).frame(width: 5, height: 5)
                    .offset(x: 92 * cos(a), y: 92 * sin(a))
                    .gentleEntrance(delay: 0.3 + Double(i) * 0.06)
            }
        }
        .frame(width: 190, height: 190)
    }

    private var divider: some View {
        HStack(spacing: 8) {
            Rectangle().fill(EX.gold.opacity(0.35)).frame(height: 1)
            Circle().fill(EX.gold).frame(width: 4, height: 4)
            Rectangle().fill(EX.gold.opacity(0.35)).frame(height: 1)
        }
        .frame(width: 200)
    }
}

/// Fail — light screen, kind copy, the server's score and pass mark, retry.
private struct ExamFailScreen: View {
    let levelNumber: Int
    let score: Int
    let passMark: Int
    let onReview: () -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            EX.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Circle().fill(Color(hex: 0x0A2540, alpha: 0.07))
                    .frame(width: 100, height: 100)
                    .overlay(Text("📖").font(.system(size: 44)))
                Text("MARKS SCORED")
                    .font(.inter(11, .bold)).kerning(2)
                    .foregroundStyle(EX.copy)
                    .padding(.top, 22)
                Text("\(score)%")
                    .font(.inter(44, .bold)).foregroundStyle(EX.ink)
                    .padding(.top, 4)
                Text("Not yet — and that's okay")
                    .font(.inter(22, .bold)).foregroundStyle(EX.ink)
                    .padding(.top, 6)
                Text("You need \(passMark)% to pass the Level \(levelNumber) exam. It draws from the whole level, so revisit the modules and come back when you're ready — you can retake it.")
                    .font(.inter(16)).foregroundStyle(EX.copy)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.horizontal, 36)
                Spacer()
                VStack(spacing: 10) {
                    Button { Haptics.tap(); onReview() } label: {
                        Text("Review Modules")
                            .font(.inter(16, .semibold)).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .background(EX.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.pressable)
                    Button { Haptics.action(); onRetry() } label: {
                        Text("Retry Exam")
                            .font(.inter(16, .semibold)).foregroundStyle(EX.navy)
                            .frame(maxWidth: .infinity, minHeight: 56)
                            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(Color(hex: 0x0A2540, alpha: 0.15), lineWidth: 1.5))
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, Nuru.S.lg)
                .padding(.bottom, Nuru.S.lg)
            }
        }
        .onAppear { Haptics.error() }   // kind copy stays; the hand hears "not yet"
    }
}

/// Manual review — written answers went to a mentor; no instant pass/fail.
private struct ExamReviewScreen: View {
    let onDone: () -> Void

    var body: some View {
        ZStack {
            EX.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer()
                Circle().fill(Color(hex: 0x0A2540, alpha: 0.07))
                    .frame(width: 100, height: 100)
                    .overlay(Text("✍️").font(.system(size: 44)))
                Text("Submitted for review")
                    .font(.inter(22, .bold)).foregroundStyle(EX.ink)
                    .padding(.top, 24)
                Text("Your exam has written answers that need a mentor's eyes. You'll be notified once it's scored.")
                    .font(.inter(16)).foregroundStyle(EX.copy)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .padding(.top, 10)
                    .padding(.horizontal, 36)
                Spacer()
                Button { Haptics.tap(); onDone() } label: {
                    Text("Back to Level")
                        .font(.inter(16, .semibold)).foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background(EX.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, Nuru.S.lg)
                .padding(.bottom, Nuru.S.lg)
            }
        }
        .onAppear { Haptics.success() }   // the submission itself landed safely
    }
}

// (Confetti: the pass ceremony reuses the ONE shared emitter —
// CelebrationConfetti in Features/Shared/CelebrationCenter.swift.)
