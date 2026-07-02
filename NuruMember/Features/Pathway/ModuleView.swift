// Module (lesson) — the native port of the Figma ModuleLearn content screen.
// Cream canvas under a parchment-gradient header (back · "LEVEL n · MODULE m"
// overline · serif title · meta pills · Read/Watch/Reflect step chips), then one
// flowing lesson page: a real inline video card (only when the module carries a
// videoUrl), a lead paragraph, "SECTION n" blocks with serif headings, a
// gold-edged scripture pull-quote, and an inline reflection card that submits
// through completeModule. A bottom gate keeps the CTA locked until the reader
// nears the end, then it becomes "Start the quiz" or "Mark complete". The server
// enforces gating + scoring; the client only reflects state (§1.9/§3.7).
import SwiftUI

@MainActor
final class ModuleViewModel: ObservableObject {
    @Published var detail: ModuleDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var completing = false
    @Published var completed = false
    @Published var completionError: String?

    private let moduleId: String
    init(moduleId: String) { self.moduleId = moduleId }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.module(moduleId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this lesson." }
        loading = false
    }

    /// Marks the module complete server-side. Success/failure is surfaced (the
    /// old `try?` swallowed network errors silently, leaving a dead button).
    func markComplete(reflection: String? = nil) async {
        completing = true; completionError = nil
        defer { completing = false }
        let text = (reflection?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        do {
            let res = try await MemberAPI.completeModule(moduleId, reflectionText: text)
            completed = res.isCompleted || res.duplicate
            if completed { Haptics.success() }   // the moment the server confirms
        } catch {
            completionError = (error as? APIError)?.errorDescription ?? "Couldn't save your progress. Please try again."
            Haptics.error()
        }
    }
}

// Exact Figma palette (ModuleLearn.tsx) — local so this page is 1:1 with the design.
private enum ML {
    static let navy         = Color(hex: 0x0A1628)
    static let cream        = Color(hex: 0xF4F0E8)   // canvas
    static let surface      = Color(hex: 0xFBF8F1)   // inset tiles / scripture
    static let gold         = Color(hex: 0xC9A227)
    static let goldDeep     = Color(hex: 0xB6862F)   // gold gradient tail
    static let border       = Color(hex: 0x0A2540, alpha: 0.08)
    static let track        = Color(hex: 0x0A2540, alpha: 0.10)
    static let overline     = Color(hex: 0x9A7A2A)   // header overline
    static let kicker       = Color(hex: 0xA8861C)   // SECTION / scripture kickers
    static let secondary    = Color(hex: 0x68758A)
    static let lead         = Color(hex: 0x3A4A5F)   // intro paragraph
    static let bodyInk      = Color(hex: 0x1B2733)   // flowing body copy
    static let headerTop    = Color(hex: 0xF6F4EF)
    static let headerBottom = Color(hex: 0xEFE8DA)
    static let goldGradient = LinearGradient(colors: [gold, goldDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let reflectMinChars = 20   // Figma REFLECT_MIN_MOD
}

struct ModuleView: View {
    let moduleId: String
    @StateObject private var vm: ModuleViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reflection: String = ""
    @State private var playingVideo = false      // real inline player started
    @State private var reachedEnd = false        // latched once the reader nears the end

    init(moduleId: String) {
        self.moduleId = moduleId
        _vm = StateObject(wrappedValue: ModuleViewModel(moduleId: moduleId))
    }

    var body: some View {
        ZStack {
            ML.cream.ignoresSafeArea()
            if vm.loading && vm.detail == nil {
                lessonSkeleton
            } else if let d = vm.detail {
                loaded(d)
            } else {
                VStack(spacing: Nuru.S.md) {
                    Text(vm.error ?? "Couldn't load this lesson.")
                        .font(.inter(14)).foregroundStyle(ML.secondary).multilineTextAlignment(.center)
                    Button {
                        Haptics.tap()
                        Task { await vm.load() }
                    } label: {
                        Text("Try again").font(.inter(13, .semibold)).foregroundStyle(ML.navy)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(ML.gold, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(Nuru.S.screen)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task { if vm.detail == nil { await vm.load() } }
        // A short beat after the server confirms, so the success haptic and the
        // button's confirmation register before the screen goes away.
        .onChange(of: vm.completed) { _, done in
            guard done else { return }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                dismiss()
            }
        }
    }

    // MARK: - First-load skeleton (parchment header + text-line placeholders)

    private var lessonSkeleton: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ML.track).frame(width: 140, height: 10)
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ML.track).frame(width: 230, height: 22)
                HStack(spacing: 8) {
                    Capsule().fill(ML.track).frame(width: 80, height: 22)
                    Capsule().fill(ML.track).frame(width: 90, height: 22)
                }
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, 110)
            .padding(.bottom, Nuru.S.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [ML.headerTop, ML.headerBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
                    .ignoresSafeArea(edges: .top)
            )
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ML.track)
                        .frame(maxWidth: .infinity).frame(height: 12)
                        .padding(.trailing, i % 3 == 2 ? 80 : 0)
                }
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, Nuru.S.lg)
            Spacer()
        }
        .nuruShimmer()
        .accessibilityLabel("Loading this lesson")
    }

    // MARK: - Loaded layout (sticky header + one flowing lesson page + gate)

    private func loaded(_ d: ModuleDetail) -> some View {
        let parsed = mlParse(d.lessonContent)
        let video = mlVideo(d)
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                MLHeader(levelNumber: d.levelNumber,
                         moduleNumber: d.moduleSequenceNumber,
                         title: d.title,
                         minutes: d.estimatedMinutes,
                         sectionCount: parsed.sections.count,
                         chips: chips(hasVideo: video != nil, proxy: proxy),
                         onBack: { dismiss() })
                ScrollView(showsIndicators: false) {
                    lessonBody(d, parsed: parsed, video: video)
                        .id("top")
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, Nuru.S.base)
                        .padding(.bottom, Nuru.S.lg)
                }
                MLBottomGate(reachedEnd: reachedEnd,
                             requiresQuiz: d.requiresQuiz,
                             moduleId: d.moduleId,
                             busy: vm.completing,
                             error: vm.completionError) {
                    Haptics.action()
                    Task { await vm.markComplete() }
                }
            }
        }
    }

    private func lessonBody(_ d: ModuleDetail,
                            parsed: (lead: String?, sections: [MLSection]),
                            video: WelcomeVideo?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let video {
                MLVideoCard(video: video, playing: $playingVideo)
                    .id("video")
            }
            if let lead = parsed.lead {
                Text(lead)
                    .font(.inter(16, .medium)).foregroundStyle(ML.lead)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, video == nil ? 0 : 20)
            }
            if let verse = d.keyVerses?.first(where: { !$0.isEmpty }) {
                MLScriptureCard(line: verse).padding(.top, 20)
            }
            ForEach(parsed.sections) { s in
                MLSectionBlock(number: s.id + 1, section: s, showDivider: s.id > 0)
                    .padding(.top, 28)
            }
            MLReflectionCard(text: $reflection, busy: vm.completing, error: vm.completionError) {
                Haptics.action()
                Task { await vm.markComplete(reflection: reflection) }
            }
            .padding(.top, 32)
            .id("reflect")
            // Invisible sentinel — when it scrolls into the lower viewport we
            // latch `reachedEnd`, unlocking the CTA (a whisper of haptic marks it).
            Color.clear.frame(height: 1)
                .onAppear {
                    guard !reachedEnd else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { reachedEnd = true }
                    Haptics.tap()
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Read / Watch / Reflect step chips — jump to the matching part of the lesson.
    private func chips(hasVideo: Bool, proxy: ScrollViewProxy) -> [MLChipModel] {
        var out = [MLChipModel(label: "Read", done: reachedEnd) {
            Haptics.selection()
            withAnimation { proxy.scrollTo("top", anchor: .top) }
        }]
        if hasVideo {
            out.append(MLChipModel(label: "Watch", done: playingVideo) {
                Haptics.selection()
                playingVideo = true
                withAnimation { proxy.scrollTo("video", anchor: .top) }
            })
        }
        out.append(MLChipModel(label: "Reflect", done: vm.completed) {
            Haptics.selection()
            withAnimation { proxy.scrollTo("reflect", anchor: .center) }
        })
        return out
    }
}

// MARK: - Header (parchment gradient, rounded bottom, gold glow)

private struct MLChipModel: Identifiable {
    let label: String
    let done: Bool
    let action: () -> Void
    var id: String { label }
}

private struct MLHeader: View {
    let levelNumber: Int
    let moduleNumber: Int
    let title: String
    let minutes: Int?
    let sectionCount: Int
    let chips: [MLChipModel]
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                MLSquareButton(icon: .arrowLeft, action: onBack)
                Spacer(minLength: 0)
                Text("LEVEL \(levelNumber) · MODULE \(moduleNumber)")
                    .font(.inter(11, .bold)).kerning(2)
                    .foregroundStyle(ML.overline)
                Spacer(minLength: 0)
                ShareLink(item: "\(title) — Nuru Pathway") {
                    MLSquareLabel(icon: .share2)
                }
                .buttonStyle(.plain)
            }
            Text(title)
                .font(.fraunces(24, .medium)).kerning(-0.7)
                .foregroundStyle(ML.navy)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
            HStack(spacing: 8) {
                if let minutes { MLMetaPill(icon: .clock, label: "\(minutes) min read") }
                if sectionCount > 0 {
                    MLMetaPill(icon: .bookOpen,
                               label: "\(sectionCount) section\(sectionCount == 1 ? "" : "s")")
                }
            }
            .padding(.top, 12)
            HStack(spacing: 6) {
                ForEach(chips) { MLChipView(chip: $0) }
            }
            .padding(.top, 12)
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 56)
        .padding(.bottom, Nuru.S.screen)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(headerBackground)
        .shadow(color: Color(hex: 0x0A1628).opacity(0.12), radius: 10, y: 6)
    }

    private var headerBackground: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [ML.headerTop, ML.headerBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(ML.gold.opacity(0.13))
                .frame(width: 224, height: 224)
                .blur(radius: 44)
                .offset(x: 64, y: -80)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24,
                                          style: .continuous))
        .ignoresSafeArea(edges: .top)
    }
}

private struct MLSquareButton: View {
    let icon: Lucide
    let action: () -> Void
    var body: some View {
        Button(action: action) { MLSquareLabel(icon: icon).contentShape(Rectangle()) }
            .buttonStyle(.pressable)
    }
}

private struct MLSquareLabel: View {
    let icon: Lucide
    var body: some View {
        Icon(icon, size: 17, color: ML.navy)
            .frame(width: 40, height: 40)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ML.border, lineWidth: 1))
    }
}

private struct MLMetaPill: View {
    let icon: Lucide
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Icon(icon, size: 11, color: ML.secondary)
            Text(label).font(.inter(11))
        }
        .foregroundStyle(ML.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(ML.border, lineWidth: 1))
    }
}

private struct MLChipView: View {
    let chip: MLChipModel
    var body: some View {
        Button(action: chip.action) {
            HStack(spacing: 4) {
                if chip.done { Icon(.check, size: 10, color: ML.navy) }
                Text(chip.label).font(.inter(10, .bold))
            }
            .foregroundStyle(chip.done ? ML.navy : ML.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(chip.done ? AnyShapeStyle(ML.gold) : AnyShapeStyle(Color.white),
                        in: Capsule())
            .overlay(Capsule().stroke(chip.done ? Color.clear : ML.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .animation(.easeInOut(duration: 0.2), value: chip.done)
    }
}

// MARK: - Video card (16:9, real inline player — never a fake transport)

private struct MLVideoCard: View {
    let video: WelcomeVideo
    @Binding var playing: Bool

    var body: some View {
        Group {
            if playing {
                InlineVideoPlayer(video: video)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
            } else {
                Button { Haptics.tap(); playing = true } label: { poster }.buttonStyle(.pressableSubtle)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(playing ? ML.gold : ML.border, lineWidth: 1))
    }

    private var poster: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x123B62), ML.navy],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(ML.gold.opacity(0.92)).frame(width: 56, height: 56)
            Icon(.play, size: 22, color: ML.navy).offset(x: 2)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            Text("VIDEO")
                .font(.inter(10, .bold)).kerning(1).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(12)
        }
    }
}

// MARK: - Scripture pull-quote (surface tile with a gold left edge)

private struct MLScriptureCard: View {
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Icon(.quote, size: 12, color: ML.gold)
                Text("KEY VERSE")
                    .font(.inter(10, .bold)).kerning(1.8)
                    .foregroundStyle(ML.kicker)
            }
            Text("\u{201C}\(line)\u{201D}")
                .font(.fraunces(16.5, .regular)).italic()
                .foregroundStyle(ML.navy)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ML.surface)
        .overlay(alignment: .leading) { Rectangle().fill(ML.gold).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Sections ("SECTION n" kicker · serif heading · flowing body)

private struct MLSection: Identifiable {
    let id: Int
    let heading: String?
    let lines: [String]
}

private struct MLSectionBlock: View {
    let number: Int
    let section: MLSection
    let showDivider: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showDivider {
                Rectangle().fill(ML.border).frame(height: 1).padding(.bottom, 24)
            }
            if let heading = section.heading {
                Text("SECTION \(number)")
                    .font(.inter(10, .bold)).kerning(1.8)
                    .foregroundStyle(ML.kicker)
                Text(heading)
                    .font(.fraunces(21, .semibold)).kerning(-0.4)
                    .foregroundStyle(ML.navy)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(section.lines.enumerated()), id: \.offset) { _, line in
                    MLBodyLine(line: line)
                }
            }
            .padding(.top, section.heading == nil ? 0 : 14)
        }
    }
}

private struct MLBodyLine: View {
    let line: String
    var body: some View {
        if let bullet = mlBullet(line) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(ML.navy).frame(width: 5, height: 5).offset(y: -2)
                Text(bullet)
                    .font(.inter(15)).foregroundStyle(ML.bodyInk)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(line)
                .font(.inter(15)).foregroundStyle(ML.bodyInk)
                .lineSpacing(6)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Reflection card (inline; submits through completeModule)

private struct MLReflectionCard: View {
    @Binding var text: String
    let busy: Bool
    let error: String?
    let onSubmit: () -> Void

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { trimmed.count >= ML.reflectMinChars }
    private var words: Int { trimmed.isEmpty ? 0 : trimmed.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("REFLECTION")
                .font(.inter(10, .bold)).kerning(1.8)
                .foregroundStyle(ML.kicker)
            Text("What is one thing from this module the Spirit is asking you to practice this week?")
                .font(.fraunces(15, .regular)).foregroundStyle(ML.navy)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            editor.padding(.top, 12)
            Text(counterLine)
                .font(.inter(11)).foregroundStyle(ML.secondary)
                .contentTransition(.numericText())
                .animation(.default, value: trimmed.count)
                .padding(.top, 6)
            if let error {
                Text(error)
                    .font(.inter(11, .medium)).foregroundStyle(Nuru.danger)
                    .padding(.top, 6)
            }
            submitButton.padding(.top, 12)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(ML.border, lineWidth: 1))
    }

    private var counterLine: String {
        canSubmit
            ? "\(words) words · \(trimmed.count) chars"
            : "\(ML.reflectMinChars - trimmed.count) more characters before you can submit"
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("A few honest words…")
                    .font(.inter(13)).foregroundStyle(Nuru.faint)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
            TextEditor(text: $text)
                .font(.inter(13)).foregroundStyle(ML.navy)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(ML.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(ML.border, lineWidth: 1))
    }

    private var submitButton: some View {
        Button(action: onSubmit) {
            ZStack {
                if busy { ProgressView().tint(.white) }
                else { Text("Submit reflection").font(.inter(13, .semibold)) }
            }
            .foregroundStyle(canSubmit ? Color.white : Color(hex: 0x0A2540, alpha: 0.55))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(canSubmit ? AnyShapeStyle(ML.navy) : AnyShapeStyle(Color(hex: 0x0A2540, alpha: 0.18)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(!canSubmit || busy)
        .animation(.easeInOut(duration: 0.2), value: canSubmit)
    }
}

// MARK: - Bottom gate (progress strip + locked / quiz / mark-complete CTA)

private struct MLBottomGate: View {
    let reachedEnd: Bool
    let requiresQuiz: Bool
    let moduleId: String
    let busy: Bool
    let error: String?
    let onComplete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                progressBar
                Text(reachedEnd ? "All steps done 🎉" : "Keep reading")
                    .font(.inter(10, .bold))
                    .foregroundStyle(reachedEnd ? ML.overline : ML.secondary)
            }
            if let error {
                Text(error)
                    .font(.inter(11, .medium)).foregroundStyle(Nuru.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            cta
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.md)
        .padding(.bottom, Nuru.S.screen)
        .background(ML.cream.ignoresSafeArea(edges: .bottom))
        .animation(.easeInOut(duration: 0.25), value: reachedEnd)
    }

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ML.track)
                Capsule().fill(ML.gold)
                    .frame(width: max(8, geo.size.width * (reachedEnd ? 1 : 0.12)))
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.4), value: reachedEnd)
    }

    @ViewBuilder
    private var cta: some View {
        if !reachedEnd {
            HStack(spacing: 8) {
                Icon(.lock, size: 13, color: ML.secondary)
                Text(requiresQuiz ? "Read to the end to unlock the quiz" : "Read to the end to continue")
                    .font(.inter(14, .bold))
            }
            .foregroundStyle(ML.secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ML.border, lineWidth: 1))
        } else if requiresQuiz {
            NavigationLink(value: PathwayRoute.quiz(moduleId)) {
                HStack(spacing: 8) {
                    Text("Start the quiz").font(.inter(14, .bold))
                    Icon(.arrowRight, size: 15, color: ML.navy)
                }
                .foregroundStyle(ML.navy)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(ML.goldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: ML.gold.opacity(0.45), radius: 12, y: 8)
            }
            .buttonStyle(.pressable)
            .simultaneousGesture(TapGesture().onEnded { Haptics.action() })
        } else {
            Button(action: onComplete) {
                ZStack {
                    if busy { ProgressView().tint(ML.navy) }
                    else { Text("Mark complete").font(.inter(14, .bold)) }
                }
                .foregroundStyle(ML.navy)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(ML.goldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: ML.gold.opacity(0.45), radius: 12, y: 8)
            }
            .buttonStyle(.pressable)
            .disabled(busy)
        }
    }
}

// MARK: - Lesson parsing (lead paragraph · numbered headings → sections · bullets)

/// Split lesson content into display paragraphs (blank-line or single-newline).
private func mlParagraphs(_ s: String) -> [String] {
    let lines = s.replacingOccurrences(of: "\r\n", with: "\n")
        .components(separatedBy: "\n\n")
        .flatMap { $0.components(separatedBy: "\n") }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    return lines.isEmpty ? [s] : lines
}

/// Recognise a leading "1. " / "12) " heading; returns (number, remainder).
private func mlNumberedHeading(_ s: String) -> (Int, String)? {
    var idx = s.startIndex
    var digits = ""
    while idx < s.endIndex, s[idx].isNumber { digits.append(s[idx]); idx = s.index(after: idx) }
    guard !digits.isEmpty, let n = Int(digits), idx < s.endIndex else { return nil }
    let sep = s[idx]
    guard sep == "." || sep == ")" else { return nil }
    let rest = s[s.index(after: idx)...].trimmingCharacters(in: .whitespaces)
    // Treat as a heading only when it's a short title line, not a sentence.
    guard !rest.isEmpty, rest.count <= 60 else { return nil }
    return (n, rest)
}

/// Recognise a bullet line ("• …" or "- …"); returns the body without the marker.
private func mlBullet(_ s: String) -> String? {
    for marker in ["• ", "- ", "● ", "* "] where s.hasPrefix(marker) {
        return String(s.dropFirst(marker.count))
    }
    return nil
}

/// Group the flat paragraphs into a lead paragraph + numbered sections.
private func mlParse(_ content: String) -> (lead: String?, sections: [MLSection]) {
    let paras = mlParagraphs(content)
    var lead: String?
    var sections: [MLSection] = []
    var heading: String?
    var lines: [String] = []
    var open = false

    func flush() {
        if open, heading != nil || !lines.isEmpty {
            sections.append(MLSection(id: sections.count, heading: heading, lines: lines))
        }
        heading = nil; lines = []; open = false
    }

    for (i, p) in paras.enumerated() {
        if let (_, rest) = mlNumberedHeading(p) {
            flush()
            heading = rest; open = true
        } else if i == 0 {
            lead = p
        } else {
            open = true
            lines.append(p)
        }
    }
    flush()
    return (lead, sections)
}

/// Wrap the module's real videoUrl for the shared inline player (source inferred
/// from the host — YouTube/Vimeo embed, anything else plays as HTML5 video).
private func mlVideo(_ d: ModuleDetail) -> WelcomeVideo? {
    guard let raw = d.videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else { return nil }
    let lower = raw.lowercased()
    let source = lower.contains("youtu") ? "youtube" : (lower.contains("vimeo") ? "vimeo" : "direct")
    return WelcomeVideo(mediaAssetId: d.moduleId, videoSource: source, caption: nil,
                        durationSec: nil, thumbnailUrl: nil, reactions: nil, loveCount: nil,
                        liked: nil, externalUrl: raw, externalVideoId: nil, url: nil,
                        expiresAt: nil)
}
