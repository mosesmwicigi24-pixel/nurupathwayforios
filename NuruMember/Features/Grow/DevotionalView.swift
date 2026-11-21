// Today's Devotional — the native port of the Figma DevotionalScreen
// (PathwayScreens.tsx). Reads /growth/devotional and lets the member save a
// reflection (which also marks the Reflection rhythm for the day). Body matches
// the Figma anatomy: one white card holding the gold-accented verse block +
// devotional paragraphs, the REFLECTION card (min-length gate, navy submit),
// a Save/Share action row and the gold encouragement strip. The Figma audio/
// video players are mock timers, so they are intentionally not ported.
//
// Read aloud and the night page (member suggestion, 2026-11-21): a Listen
// button and the moon/sun beside Back, the player at the page's foot, and the
// whole page drawn from DevotionalPalette — the day page exactly as it was,
// the night page the readers' sepia (ReadingTheme.swift). Every block below
// takes the palette as an input, so a flip redraws all of it.
import SwiftUI

// MARK: - View model

@MainActor
final class DevotionalViewModel: ObservableObject {
    @Published var devotional: Devotional?
    @Published var loading = true
    @Published var error: String?
    @Published var reflection = ""
    @Published var saving = false
    @Published var saved = false

    func load() async {
        loading = true; error = nil
        do {
            let d = try await MemberAPI.devotional()
            devotional = d
            reflection = d.myReflection ?? ""
        } catch { self.error = NuruStateCopy.failureLine("Couldn't load today's devotional.", error) }
        loading = false
    }

    func saveReflection() async {
        guard let d = devotional,
              !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saving = true; defer { saving = false }
        if (try? await MemberAPI.saveDevotionalReflection(devotionalId: d.devotionalId, body: reflection)) == true {
            // The reading-completion moment: a firm success tick + the
            // "Submitted" check settling in with a small spring.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { saved = true }
            Haptics.success()
        } else {
            Haptics.error()
        }
    }
}

// MARK: - Screen

struct DevotionalView: View {
    @StateObject private var vm = DevotionalViewModel()
    // The reading theme: the member's choice, and the phone's own style for
    // Automatic — either changing redraws the page.
    @AppStorage(ReadingTheme.storageKey) private var readingTheme = ReadingTheme.auto.rawValue
    @ObservedObject private var appearance = ReadingAppearance.shared
    /// Read aloud (ReaderListen.devotional): title, verse, body, the question.
    @State private var listen = ListenReading.empty

    private var night: Bool { ReadingTheme.from(readingTheme).isNight(systemDark: appearance.systemDark) }
    private var pal: DevotionalPalette { DevotionalPalette(night: night) }

    var body: some View {
        ZStack {
            pal.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.devotional == nil,
                          isEmpty: vm.devotional == nil, error: vm.error,
                          emptyText: "No devotional today.", retry: { Task { await vm.load() } }) {
                if let d = vm.devotional { content(d) }
            }
        }
        // The Read aloud player floats over the page's foot, clear of the tab bar.
        .overlay(alignment: .bottom) {
            ListenHost(listen) { c in ListenBar(controls: c, colors: pal.listenColors) }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace - 24)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.devotional == nil { await vm.load() } }
        .onAppear { ReadingAppearance.shared.refresh() }
        .onChange(of: vm.devotional?.devotionalId, initial: true) { _, _ in
            let next = vm.devotional.map { ListenReading(pieces: ReaderListen.devotional($0)) } ?? .empty
            if next != listen { listen = next }
        }
        // Leaving the devotional — or its words changing — stops the voice;
        // going to the background does not.
        .onDisappear { ReadAloud.shared.leave(listen.key) }
        .onChange(of: listen.key) { old, _ in ReadAloud.shared.leave(old) }
    }

    private func flipNight() {
        Haptics.tap()
        let next = ReadingTheme.toggled(currentlyNight: night)
        withAnimation(.easeInOut(duration: 0.25)) { readingTheme = next.rawValue }
    }

    private func content(_ d: Devotional) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(d)
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    // Figma: the verse block and the devotional paragraphs share one white card.
                    pageCard {
                        VStack(alignment: .leading, spacing: Nuru.S.md) {
                            if let ref = d.scriptureRef {
                                VerseCard(reference: ref, text: d.scriptureText, pal: pal)
                            }
                            BodyParagraphs(text: d.body, pal: pal)
                        }
                    }
                    .gentleEntrance()
                    ReflectionCard(prompt: d.reflectionPrompt,
                                   text: $vm.reflection,
                                   saving: vm.saving,
                                   saved: vm.saved,
                                   pal: pal) {
                        Task { await vm.saveReflection() }
                    }
                    .gentleEntrance(delay: 0.06)
                    FooterActions(devotional: d, pal: pal)
                        .gentleEntrance(delay: 0.12)
                    EncouragementStrip(pal: pal)
                        .gentleEntrance(delay: 0.18)
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.lg)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    /// The day page's white Card, exactly as before; on the night page the
    /// same shape in the night card colour.
    @ViewBuilder private func pageCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if night {
            content()
                .padding(Nuru.S.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(pal.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(pal.border, lineWidth: 1))
        } else {
            Card { content() }
        }
    }

    // Cream Figma ScreenShell header: back button, day overline, serif title, series subtitle.
    private func header(_ d: Devotional) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            HStack(spacing: 8) {
                BackButton(pal: pal)
                Spacer(minLength: 0)
                // Read aloud: start, pause, resume (the player at the foot does the rest).
                ListenHost(listen) { c in
                    if c.available {
                        Button {
                            Haptics.tap()
                            ReadAloud.shared.toggle(c.reading)
                        } label: {
                            SquareGlyph(icon: c.glyph, pal: pal)
                        }
                        .buttonStyle(.pressable)
                        .accessibilityLabel(c.label)
                    }
                }
                Button { flipNight() } label: {
                    SquareGlyph(icon: night ? .sun : .moon, pal: pal)
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(ReadingTheme.toggleLabel(night: night))
            }
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("DAY \(d.dayNumber) · DEVOTIONAL")
                    .font(.inter(11, .bold)).tracking(1.6)
                    .foregroundStyle(pal.eyebrow)
                Text(d.title)
                    .font(.fraunces(28, .semibold))
                    .foregroundStyle(pal.navy)
                    .fixedSize(horizontal: false, vertical: true)
                if let series = d.series {
                    Text(series)
                        .font(.inter(13, .regular))
                        .foregroundStyle(pal.series)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, NuruSafeArea.top + 8)   // below the status band (rule 9)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [pal.headerTop, pal.headerBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(pal.gold.opacity(pal.night ? 0.12 : 0.25)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(RoundedRectangle(cornerRadius: Nuru.R.hero, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(pal.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }
}

// MARK: - The page's colours (day = the Grow cream as it was; night = the readers' sepia)

/// The devotional's colours on the day page (exactly the tokens it always
/// used) and the night page (ReaderPalette's sepia). `navy` is the page's TEXT
/// navy, so on the night page it is the light ink; the submit button's fill
/// and words have their own pair.
struct DevotionalPalette: Equatable {
    var night: Bool = false
    private var r: ReaderPalette { ReaderPalette(night: true) }

    var paper: Color { night ? r.bg : Nuru.paper }
    var white: Color { night ? r.card : Color.white }
    var surface: Color { night ? r.verseBg : Nuru.surface }
    var border: Color { night ? r.border : Nuru.border }
    var navy: Color { night ? r.ink : Nuru.navy }
    var gold: Color { night ? r.gold : Nuru.gold }
    var eyebrow: Color { night ? r.goldDeep : Color(hex: 0x9A7A2A) }
    var kicker: Color { night ? r.goldDeep : Color(hex: 0xA8861C) }
    var series: Color { night ? r.inkDim : Color(hex: 0x59667C) }
    var ink: Color { night ? r.ink : Nuru.ink }
    var muted: Color { night ? r.inkDim : Nuru.muted }
    var faint: Color { night ? Color(hex: 0x6B6455) : Nuru.faint }
    var successText: Color { night ? Color(hex: 0x86EFAC) : Nuru.successText }
    var headerTop: Color { night ? r.card : Color(hex: 0xF6F4EF) }
    var headerBottom: Color { night ? r.bg : Color(hex: 0xEFE8DA) }
    /// The submit button: navy with white words by day; gold with navy words
    /// at night (a navy fill would vanish into the dark page).
    var submitFill: Color { night ? r.gold : Nuru.navy }
    var submitInk: Color { night ? Color(hex: 0x0A1628) : Color.white }
    var submitIdleFill: Color { night ? r.ink.opacity(0.12) : Nuru.navy.opacity(0.18) }
    var submitIdleInk: Color { night ? r.ink.opacity(0.5) : Nuru.navy.opacity(0.55) }

    var listenColors: ListenColors {
        ListenColors(bar: white, ink: navy, inkDim: muted, accent: gold, onAccent: Color(hex: 0x0A1628), border: border)
    }
}

/// The header's square buttons (listen · night page), Back's shape.
private struct SquareGlyph: View {
    let icon: Lucide
    let pal: DevotionalPalette
    var body: some View {
        Icon(icon, size: 18, color: pal.navy)
            .frame(width: 40, height: 40)
            .background(pal.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(pal.border, lineWidth: 1))
    }
}

// MARK: - Back button

private struct BackButton: View {
    let pal: DevotionalPalette
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Button { dismiss() } label: {
            Icon(.arrowLeft, size: 18, color: pal.navy)
                .frame(width: 40, height: 40)
                .background(pal.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(pal.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Verse block (surface tile, gold left accent, inline quote + ref overline)

private struct VerseCard: View {
    let reference: String
    let text: String?
    let pal: DevotionalPalette

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(pal.gold)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(spacing: 6) {
                    Icon(.quote, size: 14, color: pal.gold)
                    Text(reference.uppercased())
                        .font(.nCardKicker).kerning(1.4)
                        .foregroundStyle(pal.kicker)
                }
                if let text {
                    Text("\u{201C}\(text)\u{201D}")
                        .font(.fraunces(16, .regular))
                        .foregroundStyle(pal.navy)
                        .nuruLineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Nuru.S.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(pal.surface)
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }
}

// MARK: - Body paragraphs (the one 16 pt reading body, §8.2 #21; split on blank lines)

private struct BodyParagraphs: View {
    let text: String
    let pal: DevotionalPalette

    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p)
                    .font(.nBodyLg)   // long reading: the one 16 pt body
                    .foregroundStyle(pal.ink)
                    .nuruLineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Reflection card

private struct ReflectionCard: View {
    let prompt: String?
    @Binding var text: String
    let saving: Bool
    let saved: Bool
    let pal: DevotionalPalette
    let onSave: () -> Void

    /// Figma REFLECT_MIN — a few honest words before submit unlocks.
    private static let minChars = 20

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { trimmed.count >= Self.minChars }
    private var wordCount: Int { trimmed.isEmpty ? 0 : trimmed.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        if pal.night {
            inner
                .padding(Nuru.S.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(pal.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(pal.border, lineWidth: 1))
        } else {
            Card(padding: Nuru.S.base) { inner }
        }
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text("REFLECTION")
                    .font(.nCardKicker).kerning(1.4)
                    .foregroundStyle(pal.kicker)
                Spacer()
                if saved {
                    HStack(spacing: 4) {
                        Icon(.check, size: 14, color: pal.gold)
                        Text("Submitted").font(.inter(11, .bold)).foregroundStyle(pal.gold)
                    }
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            Text(prompt ?? "What is God saying to you today?")
                .font(.nCardBody)
                .foregroundStyle(pal.muted)
                .nuruLineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            field

            Text(hint)
                .font(.nCardMeta)
                .foregroundStyle(saved ? pal.successText : pal.muted)

            submitButton
        }
    }

    private var hint: String {
        if saved { return "\(wordCount) words · saved to your journal" }
        if canSubmit { return "\(wordCount) words · \(trimmed.count) chars" }
        return "\(Self.minChars - trimmed.count) more characters before you can submit"
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if trimmed.isEmpty && text.isEmpty {
                Text("Write your reflection…")
                    .font(.nBody)
                    .foregroundStyle(pal.faint)
                    .padding(.horizontal, Nuru.S.base + 5)
                    .padding(.vertical, Nuru.S.base)
            }
            TextEditor(text: $text)
                .font(.nBody)
                .foregroundStyle(pal.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(Nuru.S.sm)
        }
        .background(pal.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(pal.border, lineWidth: 1)
        )
    }

    // Figma: full-width navy submit, dimmed navy while below the minimum.
    private var submitButton: some View {
        Button { Haptics.action(); onSave() } label: {
            ZStack {
                if saving {
                    ProgressView().tint(pal.submitInk)
                } else {
                    Text(saved ? "Update reflection" : "Submit reflection")
                        .font(.nCardCTA)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(canSubmit ? pal.submitInk : pal.submitIdleInk)
            .background(
                canSubmit ? AnyShapeStyle(pal.submitFill) : AnyShapeStyle(pal.submitIdleFill),
                in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
            )
        }
        .buttonStyle(.pressable)
        .disabled(!canSubmit || saving)
    }
}

// MARK: - Footer actions (Figma Save · Share row; Discuss has no chat target yet)

private struct FooterActions: View {
    let devotional: Devotional
    let pal: DevotionalPalette
    /// A quiet like, on this screen only — nothing is saved anywhere, so the
    /// heart never says "Saved" (owner decision, EXPERIENCE.md §7.4) until
    /// real saving exists as its own feature.
    @State private var loved = false

    var body: some View {
        HStack(spacing: 0) {
            Button {
                loved.toggle()
                Haptics.love()
            } label: {
                column(icon: .heart, label: HeartWords.label, color: loved ? pal.gold : pal.navy)
            }
            .buttonStyle(.pressable)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: loved)
            .accessibilityValue(loved ? "Liked" : "")

            ShareLink(item: shareText) {
                column(icon: .share2, label: "Share", color: pal.navy)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Nuru.S.md)
        .padding(.vertical, 3) // the 44pt hit area lives inside each column
        .background(pal.white, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(pal.border, lineWidth: 1)
        )
    }

    private func column(icon: Lucide, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Icon(icon, size: 18, color: color)
            Text(label).font(.inter(11, .medium)).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }

    private var shareText: String {
        var parts: [String] = [devotional.title]
        if let t = devotional.scriptureText, let r = devotional.scriptureRef {
            parts.append("\u{201C}\(t)\u{201D} — \(r)")
        } else if let r = devotional.scriptureRef {
            parts.append(r)
        }
        return parts.joined(separator: "\n\n")
    }
}

// MARK: - Encouragement strip (gold tint + HandHeart, straight from the Figma)

private struct EncouragementStrip: View {
    let pal: DevotionalPalette
    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(.handHeart, size: 18, color: pal.gold)
            Text("Every faithful day adds up. There's no rush — just presence.")
                .font(.nCardBody)
                .foregroundStyle(pal.navy)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.md)
        .background(pal.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }
}

/// The heart's one word (owner decision, §7.4): "Like" — never "Save" or
/// "Saved", because a heart on these pages keeps nothing anywhere.
enum HeartWords {
    static let label = "Like"
}
