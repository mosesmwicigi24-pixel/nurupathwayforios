// Module (lesson) — the native port of screens/ModuleScreen.tsx. Renders the
// lesson content + key verses, then the completion CTA: a graded quiz when the
// module's evaluation requires one, otherwise a "Mark complete" action. The
// server enforces gating + scoring; the client only reflects state (§1.9/§3.7).
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

    func markComplete() async {
        completing = true; defer { completing = false }
        if let res = try? await MemberAPI.completeModule(moduleId) {
            completed = res.isCompleted || res.duplicate
        }
    }
}

struct ModuleView: View {
    let moduleId: String
    @StateObject private var vm: ModuleViewModel
    @Environment(\.dismiss) private var dismiss

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
                content(d)
            } else {
                Text(vm.error ?? "Couldn't load this lesson.").font(.nBody).foregroundStyle(Nuru.muted)
            }
        }
        .navigationTitle(vm.detail?.title ?? "Lesson")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.detail == nil { await vm.load() } }
        .onChange(of: vm.completed) { _, done in
            if done { dismiss() }
        }
    }

    private func content(_ d: ModuleDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                if let summary = d.summary, !summary.isEmpty {
                    Text(summary).font(.nBodyLg).foregroundStyle(Nuru.ink)
                }
                if let verses = d.keyVerses, !verses.isEmpty {
                    Card(padding: Nuru.S.base) {
                        VStack(alignment: .leading, spacing: Nuru.S.xs) {
                            Text("Key verses").font(.nOverline).foregroundStyle(Nuru.gold).textCase(.uppercase)
                            ForEach(verses, id: \.self) { v in
                                Text(v).font(.nBody).foregroundStyle(Nuru.ink)
                            }
                        }
                    }
                }
                Text(d.lessonContent)
                    .font(.nBody).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let urlString = d.videoUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("Watch the teaching", systemImage: "play.circle.fill")
                            .font(.inter(14, .semibold)).foregroundStyle(Nuru.gold)
                    }
                }

                cta(d).padding(.top, Nuru.S.sm)
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }

    @ViewBuilder
    private func cta(_ d: ModuleDetail) -> some View {
        if d.requiresQuiz {
            NavigationLink(value: PathwayRoute.quiz(d.moduleId)) {
                Text("Take the quiz")
                    .font(.inter(16, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: Nuru.buttonHeightLg)
                    .background(Nuru.primaryButton, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
            }
            .buttonStyle(.plain)
        } else {
            PButton(title: "Mark complete", variant: .gold, busy: vm.completing) {
                Task { await vm.markComplete() }
            }
        }
    }
}
