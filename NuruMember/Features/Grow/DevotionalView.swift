// Today's Devotional — the native port of the Figma DevotionalScreen
// (PathwayScreens.tsx). Reads /growth/devotional and lets the member save a
// reflection (which also marks the Reflection rhythm for the day). Body matches
// the Figma anatomy: one white card holding the gold-accented verse block +
// devotional paragraphs, the REFLECTION card (min-length gate, navy submit),
// a Save/Share action row and the gold encouragement strip. The Figma audio/
// video players are mock timers, so they are intentionally not ported.
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
        } catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load today's devotional." }
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

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.devotional == nil,
                          isEmpty: vm.devotional == nil, error: vm.error,
                          emptyText: "No devotional today.", retry: { Task { await vm.load() } }) {
                if let d = vm.devotional { content(d) }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.devotional == nil { await vm.load() } }
    }

    private func content(_ d: Devotional) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header(d)
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    // Figma: the verse block and the devotional paragraphs share one white card.
                    Card {
                        VStack(alignment: .leading, spacing: Nuru.S.md) {
                            if let ref = d.scriptureRef {
                                VerseCard(reference: ref, text: d.scriptureText)
                            }
                            BodyParagraphs(text: d.body)
                        }
                    }
                    .gentleEntrance()
                    ReflectionCard(prompt: d.reflectionPrompt,
                                   text: $vm.reflection,
                                   saving: vm.saving,
                                   saved: vm.saved) {
                        Task { await vm.saveReflection() }
                    }
                    .gentleEntrance(delay: 0.06)
                    FooterActions(devotional: d)
                        .gentleEntrance(delay: 0.12)
                    EncouragementStrip()
                        .gentleEntrance(delay: 0.18)
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.lg)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .ignoresSafeArea(edges: .top)
    }

    // Cream Figma ScreenShell header: back button, day overline, serif title, series subtitle.
    private func header(_ d: Devotional) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            BackButton()
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("DAY \(d.dayNumber) · DEVOTIONAL")
                    .font(.inter(11, .bold)).tracking(1.6)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Text(d.title)
                    .font(.fraunces(28, .semibold))
                    .foregroundStyle(Nuru.navy)
                    .fixedSize(horizontal: false, vertical: true)
                if let series = d.series {
                    Text(series)
                        .font(.inter(13, .regular))
                        .foregroundStyle(Color(hex: 0x59667C))
                }
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
                .clipShape(RoundedRectangle(cornerRadius: Nuru.R.hero, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }
}

// MARK: - Back button

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

// MARK: - Verse block (surface tile, gold left accent, inline quote + ref overline)

private struct VerseCard: View {
    let reference: String
    let text: String?

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Nuru.gold)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(spacing: 6) {
                    Icon(.quote, size: 12, color: Nuru.gold)
                    Text(reference.uppercased())
                        .font(.nCardKicker).kerning(1.4)
                        .foregroundStyle(Color(hex: 0xA8861C))
                }
                if let text {
                    Text("\u{201C}\(text)\u{201D}")
                        .font(.fraunces(16, .regular))
                        .foregroundStyle(Nuru.navy)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Nuru.S.md)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Nuru.surface)
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }
}

// MARK: - Body paragraphs (Figma: 14pt ink on 24pt lines, split on blank lines)

private struct BodyParagraphs: View {
    let text: String

    private var paragraphs: [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p)
                    .font(.inter(14, .regular))
                    .foregroundStyle(Nuru.ink)
                    .lineSpacing(7)
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
    let onSave: () -> Void

    /// Figma REFLECT_MIN — a few honest words before submit unlocks.
    private static let minChars = 20

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { trimmed.count >= Self.minChars }
    private var wordCount: Int { trimmed.isEmpty ? 0 : trimmed.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        Card(padding: Nuru.S.base) {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                HStack {
                    Text("REFLECTION")
                        .font(.nCardKicker).kerning(1.4)
                        .foregroundStyle(Color(hex: 0xA8861C))
                    Spacer()
                    if saved {
                        HStack(spacing: 4) {
                            Icon(.check, size: 10, color: Nuru.gold)
                            Text("Submitted").font(.inter(10, .bold)).foregroundStyle(Nuru.gold)
                        }
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                    }
                }
                Text(prompt ?? "What is God saying to you today?")
                    .font(.nCardBody)
                    .foregroundStyle(Nuru.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                field

                Text(hint)
                    .font(.nCardMeta)
                    .foregroundStyle(saved ? Nuru.successText : Nuru.muted)

                submitButton
            }
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
                    .foregroundStyle(Nuru.faint)
                    .padding(.horizontal, Nuru.S.base + 5)
                    .padding(.vertical, Nuru.S.base)
            }
            TextEditor(text: $text)
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
    }

    // Figma: full-width navy submit, dimmed navy while below the minimum.
    private var submitButton: some View {
        Button { Haptics.action(); onSave() } label: {
            ZStack {
                if saving {
                    ProgressView().tint(.white)
                } else {
                    Text(saved ? "Update reflection" : "Submit reflection")
                        .font(.nCardCTA)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(canSubmit ? Color.white : Nuru.navy.opacity(0.55))
            .background(
                canSubmit ? AnyShapeStyle(Nuru.navy) : AnyShapeStyle(Nuru.navy.opacity(0.18)),
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
    @State private var loved = false   // local, like the Figma bookmark state

    var body: some View {
        HStack(spacing: 0) {
            Button {
                loved.toggle()
                Haptics.love()
            } label: {
                column(icon: .heart, label: loved ? "Saved" : "Save",
                       color: loved ? Nuru.gold : Nuru.navy)
            }
            .buttonStyle(.pressable)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: loved)

            ShareLink(item: shareText) {
                column(icon: .share2, label: "Share", color: Nuru.navy)
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Nuru.S.md)
        .padding(.vertical, 3) // the 44pt hit area lives inside each column
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(Nuru.border, lineWidth: 1)
        )
    }

    private func column(icon: Lucide, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Icon(icon, size: 16, color: color)
            Text(label).font(.inter(10, .medium)).foregroundStyle(color)
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
    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(.handHeart, size: 16, color: Nuru.gold)
            Text("Every faithful day adds up. There's no rush — just presence.")
                .font(.nCardBody)
                .foregroundStyle(Nuru.navy)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.md)
        .background(Nuru.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }
}
