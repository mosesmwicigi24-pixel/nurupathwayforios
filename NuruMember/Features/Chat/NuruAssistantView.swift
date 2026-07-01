// Nuru Assistant — the AI companion, rebuilt from the Figma NuruAssistant.
// The purple/green gradient header (orb + "Nuru AI" + status), suggestion chips,
// a message transcript (you = ink bubble, Nuru = white bubble + orb), a typing
// indicator, and a composer. Wired to the real POST /assistant/chat (+ history).
// The decorative attachment tray / voice / stickers from the mock are omitted —
// they aren't backed by real functionality. Gracefully surfaces provider outages.
import SwiftUI

/// One assistant transcript turn — matches the /assistant contract ({role,text}).
struct AssistantMessage: Codable, Sendable, Identifiable, Hashable {
    let role: String   // "user" | "assistant"
    let text: String
    var id: String { "\(role)-\(text.hashValue)" }
    var mine: Bool { role == "user" }
}

private enum NUR {
    static let navy     = Color(hex: 0x0A1628)
    static let purple   = Color(hex: 0x7C3AED)
    static let purpleLt = Color(hex: 0xA78BFA)
    static let green    = Color(hex: 0x10B981)
    static let gold     = Color(hex: 0xC89B3C)
    static let cream    = Color(hex: 0xF6F4EE)
    static let creamLo  = Color(hex: 0xEFEAE0)
    static let border   = Color(hex: 0x0B1F33, alpha: 0.08)
    static let hint     = Color(hex: 0x9AA3AF)

    static let header  = LinearGradient(colors: [Color(hex: 0x2A1259), Color(hex: 0x0A1628), Color(hex: 0x053F30)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let orb     = LinearGradient(colors: [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED), Color(hex: 0x2A1259)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let ink     = LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x163655)], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sendG   = LinearGradient(colors: [Color(hex: 0xA78BFA), Color(hex: 0x34D399)], startPoint: .topLeading, endPoint: .bottomTrailing)

    struct Suggestion { let label: String; let color: Color }
    static let suggestions = [
        Suggestion(label: "Summarize my cohort", color: gold),
        Suggestion(label: "Draft an encouragement", color: purple),
        Suggestion(label: "Find prayer requests", color: green),
        Suggestion(label: "Plan my quiet time", color: Color(hex: 0x0EA5E9)),
    ]
    static let welcome = "Hi, I'm Nuru ✨ your AI companion. I can summarize chats, draft an encouragement, surface prayer requests, or simply talk it through. How can I help today?"
}

@MainActor
final class NuruAssistantViewModel: ObservableObject {
    @Published var messages: [AssistantMessage] = [AssistantMessage(role: "assistant", text: NUR.welcome)]
    @Published var typing = false
    @Published var draft = ""

    func load() async {
        // Replace the welcome greeting with real history when the member has any.
        if let hist = try? await MemberAPI.assistantHistory(), !hist.isEmpty {
            messages = hist
        }
    }

    func send() async {
        let t = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !typing else { return }
        messages.append(AssistantMessage(role: "user", text: t))
        draft = ""
        typing = true
        // Send the running transcript (drop the local welcome so it isn't echoed).
        let transcript = messages.filter { !($0.role == "assistant" && $0.text == NUR.welcome) }
        do {
            let reply = try await MemberAPI.assistantChat(transcript)
            messages.append(AssistantMessage(role: "assistant", text: reply))
        } catch {
            let msg = (error as? APIError)?.errorDescription ?? ""
            let friendly = msg.lowercased().contains("unavailable")
                ? "I'm resting right now and can't reply — please try again in a little while. 🤍"
                : "Something went wrong reaching me. Please try again."
            messages.append(AssistantMessage(role: "assistant", text: friendly))
        }
        typing = false
    }

    func suggest(_ label: String) async { draft = label; await send() }
}

struct NuruAssistantView: View {
    @StateObject private var vm = NuruAssistantViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        suggestions
                        VStack(spacing: 10) {
                            ForEach(vm.messages) { m in bubble(m) }
                            if vm.typing { typingRow.frame(maxWidth: .infinity, alignment: .leading) }
                        }
                        .id("bottom")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .onChange(of: vm.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: vm.typing) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
            }
            composer
        }
        .background(LinearGradient(colors: [NUR.cream, NUR.creamLo], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: { Icon(.chevronLeft, size: 23, color: .white).frame(width: 40, height: 40) }.buttonStyle(.plain)
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(NUR.orb).frame(width: 44, height: 44)
                    .overlay(Icon(.sparkles, size: 19, color: .white))
                    .shadow(color: NUR.purple.opacity(0.7), radius: 8, y: 4)
                Circle().fill(NUR.green).frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color(hex: 0x0A1628), lineWidth: 2)).offset(x: 3, y: -3)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Nuru").font(.fraunces(20, .semibold)).kerning(-0.2).foregroundStyle(.white)
                    Text("AI").font(.inter(7, .bold)).kerning(0.98).foregroundStyle(NUR.navy)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(NUR.sendG, in: Capsule())
                }
                HStack(spacing: 6) {
                    Circle().fill(NUR.green).frame(width: 6, height: 6)
                    Text("Online · ready when you are").font(.inter(10)).foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Icon(.x, size: 16, color: .white).frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.top, 56).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(NUR.header)
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x2A1259).opacity(0.5), radius: 24, y: 14)
    }

    private var suggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(NUR.suggestions, id: \.label) { s in
                    Button { Task { await vm.suggest(s.label) } } label: {
                        Text(s.label).font(.inter(10, .semibold)).foregroundStyle(NUR.navy)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().stroke(s.color.opacity(0.33), lineWidth: 1))
                    }.buttonStyle(.plain).disabled(vm.typing)
                }
            }.padding(.horizontal, 1)
        }
    }

    private func bubble(_ m: AssistantMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if m.mine { Spacer(minLength: 40) } else { orbAvatar }
            Text(m.text)
                .font(.inter(12)).lineSpacing(3)
                .foregroundStyle(m.mine ? .white : NUR.navy)
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(
                    m.mine ? AnyShapeStyle(NUR.ink) : AnyShapeStyle(Color.white),
                    in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: m.mine ? 18 : 6, bottomTrailingRadius: m.mine ? 6 : 18, topTrailingRadius: 18, style: .continuous)
                )
                .overlay(
                    UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: m.mine ? 18 : 6, bottomTrailingRadius: m.mine ? 6 : 18, topTrailingRadius: 18, style: .continuous)
                        .stroke(m.mine ? Color.clear : NUR.border, lineWidth: 1)
                )
            if m.mine { meAvatar } else { Spacer(minLength: 40) }
        }
    }

    private var orbAvatar: some View {
        Circle().fill(NUR.orb).frame(width: 28, height: 28)
            .overlay(Icon(.sparkles, size: 12, color: .white))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }
    private var meAvatar: some View {
        Circle().fill(NUR.ink).frame(width: 28, height: 28)
            .overlay(Text("ME").font(.inter(8, .bold)).foregroundStyle(.white))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            orbAvatar
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in Circle().fill(NUR.purpleLt).frame(width: 6, height: 6) }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
            .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous).stroke(NUR.border, lineWidth: 1))
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $vm.draft, prompt: Text("Ask Nuru anything…").foregroundColor(NUR.hint), axis: .vertical)
                    .font(.inter(12)).foregroundStyle(NUR.navy).lineLimit(1...4)
                    .onSubmit { Task { await vm.send() } }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(NUR.cream, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(NUR.border, lineWidth: 1))

            Button { Task { await vm.send() } } label: {
                Image(systemName: "paperplane.fill").font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 44, height: 44).background(NUR.sendG, in: Circle())
                    .shadow(color: NUR.purple.opacity(0.5), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.typing)
            .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .top) { Rectangle().fill(NUR.border).frame(height: 1) }
    }
}
