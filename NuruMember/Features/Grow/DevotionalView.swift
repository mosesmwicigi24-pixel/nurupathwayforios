// Today's Devotional — the native port of screens/DevotionalScreen.tsx. Reads
// /growth/devotional and lets the member save a reflection (which also marks the
// Reflection rhythm for the day). Pixel-matched to the iOS member screenshot:
// a navy rounded-bottom header, a gold-accented verse card, the devotional body,
// and a white REFLECTION card with a private save action.
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
            saved = true
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
                VStack(alignment: .leading, spacing: Nuru.S.lg) {
                    if let ref = d.scriptureRef {
                        VerseCard(reference: ref, text: d.scriptureText)
                    }
                    Text(d.body)
                        .font(.inter(15, .regular))
                        .foregroundStyle(Nuru.muted)
                        .lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                    ReflectionCard(prompt: d.reflectionPrompt,
                                   text: $vm.reflection,
                                   saving: vm.saving,
                                   saved: vm.saved) {
                        Task { await vm.saveReflection() }
                    }
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
                        .foregroundStyle(Color(hex: 0x68758A))
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
        .buttonStyle(.plain)
    }
}

// MARK: - Verse card (gold left accent)

private struct VerseCard: View {
    let reference: String
    let text: String?

    var body: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(Nuru.gold)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Icon(.quote, size: 18, color: Nuru.gold)
                Text(reference.uppercased())
                    .font(.inter(11, .bold)).tracking(1.2)
                    .foregroundStyle(Nuru.gold)
                if let text {
                    Text(text)
                        .font(.fraunces(17, .regular))
                        .foregroundStyle(Nuru.ink)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Nuru.verseBg)
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }
}

// MARK: - Reflection card

private struct ReflectionCard: View {
    let prompt: String?
    @Binding var text: String
    let saving: Bool
    let saved: Bool
    let onSave: () -> Void

    private var isEmpty: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Card(padding: Nuru.S.lg) {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("REFLECTION")
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Nuru.gold)
                Text(prompt ?? "What is God saying to you today?")
                    .font(.inter(15, .semibold))
                    .foregroundStyle(Nuru.ink)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)

                field

                HStack(spacing: Nuru.S.md) {
                    saveButton
                    Text(saved ? "Saved — stays private to you." : "Stays private to you.")
                        .font(.inter(12, .regular))
                        .foregroundStyle(saved ? Nuru.successText : Nuru.faint)
                }
            }
        }
    }

    private var field: some View {
        ZStack(alignment: .topLeading) {
            if isEmpty {
                Text("A few honest words…")
                    .font(.nBody)
                    .foregroundStyle(Nuru.faint)
                    .padding(.horizontal, Nuru.S.base + 5)
                    .padding(.vertical, Nuru.S.base)
            }
            TextEditor(text: $text)
                .font(.nBody)
                .foregroundStyle(Nuru.ink)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 96)
                .padding(Nuru.S.sm)
        }
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                .stroke(Nuru.border, lineWidth: 1)
        )
    }

    private var saveButton: some View {
        Button(action: onSave) {
            HStack(spacing: Nuru.S.sm) {
                if saving {
                    ProgressView().tint(.white)
                } else {
                    Icon(.check, size: 15, color: Nuru.white)
                }
                Text("Save reflection")
                    .font(.inter(14, .semibold))
                    .foregroundStyle(Nuru.white)
            }
            .padding(.horizontal, Nuru.S.base)
            .frame(height: 40)
            .background(
                (isEmpty ? AnyShapeStyle(Nuru.faint) : AnyShapeStyle(Nuru.goldGradient)),
                in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous)
            )
            .opacity(saving ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isEmpty || saving)
    }
}
