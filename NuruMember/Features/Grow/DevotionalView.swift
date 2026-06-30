// Today's Devotional — the native port of screens/DevotionalScreen.tsx. Reads
// /growth/devotional and lets the member save a reflection (which also marks the
// Reflection rhythm for the day).
import SwiftUI

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
        guard let d = devotional, !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        saving = true; defer { saving = false }
        if (try? await MemberAPI.saveDevotionalReflection(devotionalId: d.devotionalId, body: reflection)) == true {
            saved = true
        }
    }
}

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
        .navigationTitle("Devotional")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.devotional == nil { await vm.load() } }
    }

    private func content(_ d: Devotional) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                VStack(alignment: .leading, spacing: Nuru.S.xs) {
                    if let series = d.series {
                        Text(series).font(.nOverline).foregroundStyle(Nuru.gold).textCase(.uppercase)
                    }
                    Text(d.title).font(.nTitle).foregroundStyle(Nuru.ink)
                }
                if let ref = d.scriptureRef {
                    Card(padding: Nuru.S.base) {
                        VStack(alignment: .leading, spacing: Nuru.S.xs) {
                            Text(ref).font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
                            if let text = d.scriptureText {
                                Text(text).font(.nBodyLg).foregroundStyle(Nuru.ink)
                            }
                        }
                    }
                }
                Text(d.body).font(.nBody).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = d.videoUrl.flatMap(URL.init) {
                    Link(destination: url) {
                        Label("Watch", systemImage: "play.circle.fill")
                            .font(.inter(14, .semibold)).foregroundStyle(Nuru.gold)
                    }
                }

                reflectionBlock(d)
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    private func reflectionBlock(_ d: Devotional) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text(d.reflectionPrompt ?? "Your reflection")
                    .font(.nHeading).foregroundStyle(Nuru.ink)
                TextField("Write your reflection…", text: $vm.reflection, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.nBody)
                    .padding(Nuru.S.md)
                    .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                if vm.saved {
                    Label("Saved — reflection rhythm marked", systemImage: "checkmark.circle.fill")
                        .font(.nCaption).foregroundStyle(Nuru.success)
                }
                PButton(title: "Save reflection", variant: .gold, busy: vm.saving) {
                    Task { await vm.saveReflection() }
                }
            }
        }
    }
}
