// Module (lesson) — the native port of screens/ModuleScreen.tsx (IMG_1901–1903).
// A navy lesson header (back · "LESSON · MODULE n" overline · serif title · min pill
// · Read/Listen/Watch/Reflect segmented control), a navy "LESSON MEDIA" card with
// two media tiles, an "IN THIS LESSON" verse card, then the Read body as flowing
// paragraphs. A bottom scroll-gate keeps the CTA disabled ("Keep reading…") until
// the reader nears the end, then it becomes "Take the quiz" or "Mark complete".
// The server enforces gating + scoring; the client only reflects state (§1.9/§3.7).
import SwiftUI

@MainActor
final class ModuleViewModel: ObservableObject {
    @Published var detail: ModuleDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var completing = false
    @Published var completed = false

    private let moduleId: String
    init(moduleId: String) { self.moduleId = moduleId }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.module(moduleId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this lesson." }
        loading = false
    }

    func markComplete(reflection: String? = nil) async {
        completing = true; defer { completing = false }
        let text = (reflection?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        if let res = try? await MemberAPI.completeModule(moduleId, reflectionText: text) {
            completed = res.isCompleted || res.duplicate
        }
    }
}

/// The four lesson lenses across the header segmented control.
private enum LessonTab: String, CaseIterable, Identifiable {
    case read, listen, watch, reflect
    var id: String { rawValue }
    var label: String {
        switch self {
        case .read: return "Read"
        case .listen: return "Listen"
        case .watch: return "Watch"
        case .reflect: return "Reflect"
        }
    }
    var icon: Lucide {
        switch self {
        case .read: return .check
        case .listen: return .audioLines
        case .watch: return .play
        case .reflect: return .penLine
        }
    }
}

struct ModuleView: View {
    let moduleId: String
    @StateObject private var vm: ModuleViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var tab: LessonTab = .read
    @State private var reflection: String = ""
    @State private var readProgress: Double = 0      // 0…1 — how far the body has scrolled
    @State private var reachedEnd = false            // latched once the reader nears the end

    init(moduleId: String) {
        self.moduleId = moduleId
        _vm = StateObject(wrappedValue: ModuleViewModel(moduleId: moduleId))
    }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            if vm.loading && vm.detail == nil {
                ProgressView()
            } else if let d = vm.detail {
                loaded(d)
            } else {
                Text(vm.error ?? "Couldn't load this lesson.")
                    .font(.nBody).foregroundStyle(Nuru.muted)
                    .padding(Nuru.S.screen)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        .task { if vm.detail == nil { await vm.load() } }
        .onChange(of: vm.completed) { _, done in if done { dismiss() } }
    }

    // MARK: - Loaded layout (sticky navy header + scrolling content + bottom gate)

    private func loaded(_ d: ModuleDetail) -> some View {
        VStack(spacing: 0) {
            header(d)
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    mediaCard(d)
                    verseCard(d)
                    switch tab {
                    case .read:    readBody(d)
                    case .listen:  listenPane(d)
                    case .watch:   watchPane(d)
                    case .reflect: reflectPane(d)
                    }
                    // Invisible sentinel — when it scrolls into the lower viewport
                    // we latch `reachedEnd`, unlocking the CTA.
                    endSentinel
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.S.lg)
            }
            bottomGate(d)
        }
    }

    // MARK: - Navy header

    private func header(_ d: ModuleDetail) -> some View {
        VStack(spacing: Nuru.S.base) {
            HStack(alignment: .top, spacing: Nuru.S.md) {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 17, color: .white)
                        .frame(width: 40, height: 40)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.14), lineWidth: 1))
                }
                VStack(alignment: .leading, spacing: 5) {
                    Text("LESSON · MODULE \(d.moduleSequenceNumber)")
                        .font(.inter(11, .bold)).kerning(1.4)
                        .foregroundStyle(Nuru.goldGlow)
                    Text(d.title)
                        .font(.fraunces(24, .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: Nuru.S.sm)
                if let mins = d.estimatedMinutes {
                    Text("\(mins) min")
                        .font(.inter(12, .semibold)).foregroundStyle(Nuru.onNavyDim)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.white.opacity(0.08), in: Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
            }
            segmented
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 56)
        .padding(.bottom, Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.navy.ignoresSafeArea(edges: .top))
    }

    private var segmented: some View {
        HStack(spacing: Nuru.S.sm) {
            ForEach(LessonTab.allCases) { t in
                let selected = t == tab
                Button { withAnimation(.easeInOut(duration: 0.18)) { tab = t } } label: {
                    HStack(spacing: 6) {
                        Icon(t.icon, size: 13, color: selected ? Nuru.navyDeep : Nuru.onNavyDim)
                        Text(t.label)
                            .font(.inter(13, .semibold))
                            .foregroundStyle(selected ? Nuru.navyDeep : Nuru.onNavyDim)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 9)
                    .background(
                        selected ? AnyShapeStyle(Nuru.goldGradient) : AnyShapeStyle(Color.white.opacity(0.07)),
                        in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                            .stroke(selected ? Color.clear : Color.white.opacity(0.10), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Lesson media card (navy)

    private func mediaCard(_ d: ModuleDetail) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            Text("LESSON MEDIA")
                .font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldGlow)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white.opacity(0.08), in: Capsule())

            VStack(alignment: .leading, spacing: 6) {
                Text(d.title)
                    .font(.fraunces(22, .semibold)).foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Read, listen, or watch — all available offline after sync.")
                    .font(.inter(13, .regular)).foregroundStyle(Nuru.onNavyDim)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Nuru.S.md) {
                mediaTile(icon: .play, title: "Audio lesson", duration: "6:42",
                          discColor: Nuru.navyDeep, iconColor: Nuru.goldGlow)
                mediaTile(icon: .image, title: "Video teaching", duration: "4:18",
                          discColor: Nuru.navyDeep, iconColor: .white,
                          url: URL(string: d.videoUrl ?? ""))
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.navy, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    @ViewBuilder
    private func mediaTile(icon: Lucide, title: String, duration: String,
                           discColor: Color, iconColor: Color, url: URL? = nil) -> some View {
        let tile = VStack(alignment: .leading, spacing: Nuru.S.md) {
            ZStack {
                Circle().fill(discColor).frame(width: 44, height: 44)
                Icon(icon, size: 18, color: iconColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                Text(duration).font(.inter(12, .regular)).foregroundStyle(Nuru.muted)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

        if let url, !url.absoluteString.isEmpty {
            Link(destination: url) { tile }.buttonStyle(.plain)
        } else {
            tile
        }
    }

    // MARK: - "In this lesson" verse card

    private func verseCard(_ d: ModuleDetail) -> some View {
        let line = d.keyVerses?.first(where: { !$0.isEmpty })
            ?? d.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Group {
            if let line, !line.isEmpty {
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    Text("IN THIS LESSON")
                        .font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                    Text(line)
                        .font(.fraunces(17, .medium)).foregroundStyle(Nuru.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Nuru.S.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
            }
        }
    }

    // MARK: - Read body

    private func readBody(_ d: ModuleDetail) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ForEach(Array(paragraphs(d.lessonContent).enumerated()), id: \.offset) { _, para in
                paragraphView(para)
            }
        }
        .padding(.top, Nuru.S.xs)
    }

    /// One paragraph — numbered headings ("1. Who is God?") get a gold number lead,
    /// bullet lines ("• …") get a filled dot, everything else is flowing body copy.
    @ViewBuilder
    private func paragraphView(_ raw: String) -> some View {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let (number, rest) = numberedHeading(text) {
            HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
                Text("\(number).").font(.inter(14, .bold)).foregroundStyle(Nuru.gold)
                Text(rest).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let bullet = bulletBody(text) {
            HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
                Circle().fill(Nuru.navy).frame(width: 6, height: 6)
                    .offset(y: -2)
                Text(bullet).font(.inter(15, .regular)).foregroundStyle(Nuru.ink)
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(text).font(.inter(15, .regular)).foregroundStyle(Nuru.ink)
                .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Listen / Watch panes

    private func listenPane(_ d: ModuleDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("AUDIO LESSON").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
                HStack(spacing: Nuru.S.md) {
                    ZStack {
                        Circle().fill(Nuru.navyDeep).frame(width: 56, height: 56)
                        Icon(.play, size: 22, color: Nuru.goldGlow)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(d.title).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Audio teaching · 6:42").font(.nCaption).foregroundStyle(Nuru.muted)
                    }
                    Spacer()
                }
                Text("Available offline after sync.").font(.nMicro).foregroundStyle(Nuru.faint)
            }
        }
    }

    private func watchPane(_ d: ModuleDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("VIDEO TEACHING").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Nuru.navy)
                        .frame(height: 168)
                    Circle().fill(Color.white.opacity(0.14)).frame(width: 64, height: 64)
                    Icon(.play, size: 26, color: .white)
                }
                Text(d.title).font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Video teaching · 4:18").font(.nCaption).foregroundStyle(Nuru.muted)
                if let s = d.videoUrl, let url = URL(string: s), !s.isEmpty {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Icon(.play, size: 14, color: Nuru.gold)
                            Text("Open video").font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Reflect pane

    private func reflectPane(_ d: ModuleDetail) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("REFLECT").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.gold)
                Text("What is God saying to you in this lesson?")
                    .font(.fraunces(18, .medium)).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .topLeading) {
                    if reflection.isEmpty {
                        Text("Write your reflection…")
                            .font(.nBody).foregroundStyle(Nuru.faint)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                    }
                    TextEditor(text: $reflection)
                        .font(.nBody).foregroundStyle(Nuru.ink)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 140)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                }
                .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))

                PButton(title: "Save reflection", variant: .gold, busy: vm.completing) {
                    Task { await vm.markComplete(reflection: reflection) }
                }
            }
        }
    }

    // MARK: - Scroll-end sentinel + bottom gate

    // A 1pt marker at the very bottom of the content. In a long ScrollView it only
    // renders once the reader scrolls near the end, which is exactly when we want to
    // unlock the CTA — simple and robust, no scroll-offset math required.
    private var endSentinel: some View {
        Color.clear
            .frame(height: 1)
            .onAppear { reachedEnd = true; readProgress = 1 }
    }

    @ViewBuilder
    private func bottomGate(_ d: ModuleDetail) -> some View {
        // The Reflect tab carries its own "Save reflection" action; the gate is the
        // Read/Listen/Watch completion path.
        if tab != .reflect {
            VStack(spacing: Nuru.S.md) {
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.gold.opacity(0.15)).frame(height: 4)
                    GeometryReader { geo in
                        Capsule().fill(Nuru.gold)
                            .frame(width: max(6, geo.size.width * (reachedEnd ? 1 : readProgress)), height: 4)
                    }
                    .frame(height: 4)
                }

                Text(reachedEnd ? "You've reached the end" : "Read to the end to continue")
                    .font(.inter(12, .semibold))
                    .foregroundStyle(reachedEnd ? Nuru.goldLo : Nuru.muted)

                gateCTA(d)
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, Nuru.S.md)
            .padding(.bottom, Nuru.S.lg)
            .background(
                Nuru.paper
                    .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
                    .ignoresSafeArea(edges: .bottom)
            )
        }
    }

    @ViewBuilder
    private func gateCTA(_ d: ModuleDetail) -> some View {
        if !reachedEnd {
            // Disabled placeholder while the reader hasn't finished.
            Text("Keep reading…")
                .font(.inter(16, .semibold)).foregroundStyle(Nuru.faint)
                .frame(maxWidth: .infinity, minHeight: Nuru.buttonHeightLg)
                .background(Nuru.mutedBg, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
        } else if d.requiresQuiz {
            NavigationLink(value: PathwayRoute.quiz(d.moduleId)) {
                Text("Take the quiz")
                    .font(.inter(16, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: Nuru.buttonHeightLg)
                    .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            PButton(title: "Mark complete", variant: .gold, busy: vm.completing) {
                Task { await vm.markComplete() }
            }
        }
    }

    // MARK: - Text helpers

    /// Split lesson content into display paragraphs (blank-line or single-newline).
    private func paragraphs(_ s: String) -> [String] {
        let byBlank = s.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .flatMap { $0.components(separatedBy: "\n") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return byBlank.isEmpty ? [s] : byBlank
    }

    /// Recognise a leading "1. " / "12) " heading; returns (number, remainder).
    private func numberedHeading(_ s: String) -> (Int, String)? {
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
    private func bulletBody(_ s: String) -> String? {
        for marker in ["• ", "- ", "● ", "* "] where s.hasPrefix(marker) {
            return String(s.dropFirst(marker.count))
        }
        return nil
    }
}
