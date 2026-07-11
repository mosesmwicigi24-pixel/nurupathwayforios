// Living-curriculum sheets (intelligence Phase 3).
//   • NuruCoachSheet — "Review with Nuru" after a failed quiz: a short review
//     of exactly what tripped this attempt, then straight back to the retry.
//   • ExplainSheet — the SAME lesson re-rendered (simple / Kiswahili / story).
// Both are warm stationery over navy, matching the Sunday Letter voice.
import SwiftUI

/// Sheet routing token for the reader's "hear it another way" menu.
struct ExplainTarget: Identifiable {
    let style: String
    var id: String { style }
}

struct NuruCoachSheet: View {
    let moduleId: String
    var onRetry: () -> Void = {}
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var error: String?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x081020)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 8) {
                        Icon(.sparkles, size: 15, color: Color(hex: 0xE8CA6C))
                        Text("REVIEW WITH NURU").font(.inter(11, .bold)).kerning(1.8).foregroundStyle(Color(hex: 0xE8CA6C))
                        Spacer()
                    }
                    if let text {
                        Text(text)
                            .font(.fraunces(17)).foregroundStyle(Color(hex: 0x2A3441)).lineSpacing(6)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: 0xFFFDF6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Button {
                            Haptics.action(); dismiss(); onRetry()
                        } label: {
                            Text("I'm ready — retry the quiz")
                                .font(.inter(15, .semibold)).foregroundStyle(Color(hex: 0x1E2A1F))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(LinearGradient(colors: [Color(hex: 0xE8CA6C), Color(hex: 0xB6862F)],
                                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.pressable)
                    } else if let error {
                        Text(error).font(.inter(14)).foregroundStyle(.white.opacity(0.85))
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().tint(Color(hex: 0xE8CA6C))
                            Text("Nuru is looking at what tripped you…").font(.inter(14)).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(22).padding(.top, 16)
            }
        }
        .presentationDetents([.large])
        .task {
            do { text = try await MemberAPI.quizRemediation(moduleId).body }
            catch { self.error = "Couldn't prepare your review — the lesson itself is still the best coach." }
        }
    }
}

struct ExplainSheet: View {
    let moduleId: String
    @State var style: String
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var loading = true

    private let styles: [(key: String, label: String)] = [
        ("simple", "Simple"), ("swahili", "Kiswahili"), ("story", "As a story"),
    ]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x081020)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    ForEach(styles, id: \.key) { s in
                        Button {
                            Haptics.tap(); style = s.key
                            Task { await load() }
                        } label: {
                            Text(s.label).font(.inter(12, .bold))
                                .foregroundStyle(style == s.key ? Color(hex: 0x1E2A1F) : .white.opacity(0.85))
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(style == s.key ? Color(hex: 0xE8CA6C) : Color.white.opacity(0.10), in: Capsule())
                        }
                        .buttonStyle(.pressable)
                    }
                    Spacer()
                    Button { dismiss() } label: {
                        Icon(.x, size: 14, color: .white).frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.14), in: Circle())
                    }
                }
                .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 12)
                ScrollView(showsIndicators: false) {
                    if let text {
                        Text(text)
                            .font(.fraunces(17)).foregroundStyle(Color(hex: 0x2A3441)).lineSpacing(6)
                            .padding(20)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(hex: 0xFFFDF6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .padding(.horizontal, 20).padding(.bottom, 26)
                    } else {
                        HStack(spacing: 10) {
                            ProgressView().tint(Color(hex: 0xE8CA6C))
                            Text(loading ? "Rendering the lesson…" : "Couldn't render this lesson right now.")
                                .font(.inter(14)).foregroundStyle(.white.opacity(0.85))
                        }
                        .padding(.top, 30)
                    }
                }
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true; text = nil
        text = try? await MemberAPI.explainLesson(moduleId, style: style).body
        loading = false
    }
}
