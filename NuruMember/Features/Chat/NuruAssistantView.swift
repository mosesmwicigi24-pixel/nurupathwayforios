// Nuru Assistant — the AI companion, rebuilt from the Figma NuruAssistant.
// The purple/green gradient header (glows, orb, "Nuru AI", rotating status
// taglines), wrapping suggestion chips, a message transcript (you = ink bubble
// + your initials, Nuru = white bubble + orb, role captions), a typing
// indicator, and a composer. Wired to the real POST /assistant/chat (+ history).
// The mock's attachment tray / voice / stickers / emoji bar and the canned
// CatchUp/Attention cards are omitted — they aren't backed by real data.
// Gracefully surfaces provider outages.
import Combine
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
    static let taglines = [
        "Online · ready when you are",
        "Summarize a conversation ✨",
        "Draft a warm reply 💛",
        "Find prayer requests 🙏",
        "Plan your quiet time 🌅",
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
            Haptics.tap()   // a whisper when the reply lands
        } catch {
            let msg = (error as? APIError)?.errorDescription ?? ""
            let friendly = msg.lowercased().contains("unavailable")
                ? "I'm resting right now and can't reply — please try again in a little while. 🤍"
                : "Something went wrong reaching me. Please try again."
            messages.append(AssistantMessage(role: "assistant", text: friendly))
            Haptics.error()
        }
        typing = false
    }

    func suggest(_ label: String) async { draft = label; await send() }
}

struct NuruAssistantView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = NuruAssistantViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var taglineIndex = 0
    /// Turn-entrance animations arm only after the transcript's first layout,
    /// so restored history never plays a wall of transitions.
    @State private var settled = false
    private let taglineTimer = Timer.publish(every: 3.2, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        suggestions.gentleEntrance(delay: 0.05)
                        VStack(spacing: 10) {
                            // Keyed by position, not text-hash: two identical turns
                            // (e.g. asking the same thing twice) must not collide.
                            ForEach(Array(vm.messages.enumerated()), id: \.offset) { _, m in
                                bubble(m)
                                    .transition(.asymmetric(
                                        insertion: .opacity.combined(with: .move(edge: .bottom)),
                                        removal: .opacity))
                            }
                            if vm.typing {
                                typingRow
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .bottomLeading)))
                            }
                        }
                        .id("bottom")
                        .animation(settled ? .spring(response: 0.4, dampingFraction: 0.85) : nil, value: vm.messages.count)
                        .animation(settled ? .spring(response: 0.4, dampingFraction: 0.85) : nil, value: vm.typing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: vm.messages.count) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                .onChange(of: vm.typing) { _, _ in withAnimation { proxy.scrollTo("bottom", anchor: .bottom) } }
                // Keep the latest turns visible when the keyboard slides up
                // (the composer itself already rides the keyboard: it sits at
                // the bottom of the screen VStack and nothing disables SwiftUI's
                // keyboard safe-area avoidance on this fullScreenCover).
                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                    withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
            composer
        }
        .background(LinearGradient(colors: [NUR.cream, NUR.creamLo], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            await vm.load()
            settled = true
        }
    }

    // MARK: header

    private var header: some View {
        HStack(spacing: 12) {
            Button { dismiss() } label: {
                Icon(.chevronLeft, size: 23, color: .white)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }.buttonStyle(.pressable)
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
                statusTicker
            }
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Icon(.x, size: 16, color: .white).frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                    .frame(width: 44, height: 44)     // full-size hit target
                    .contentShape(Rectangle())
            }.buttonStyle(.pressable)
        }
        .padding(.horizontal, 12).padding(.top, 56).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background(
            NUR.header
                .overlay(alignment: .topLeading) {
                    Circle().fill(NUR.purple.opacity(0.55)).frame(width: 176, height: 176).blur(radius: 44).offset(x: -40, y: -40)
                }
                .overlay(alignment: .bottomTrailing) {
                    Circle().fill(NUR.green.opacity(0.45)).frame(width: 176, height: 176).blur(radius: 44).offset(x: 20, y: 64)
                }
        )
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
        .shadow(color: Color(hex: 0x2A1259).opacity(0.5), radius: 24, y: 14)
    }

    // Live, rotating status line under the title (Figma NuruStatus).
    private var statusTicker: some View {
        HStack(spacing: 6) {
            Circle().fill(NUR.green).frame(width: 6, height: 6)
                .shadow(color: NUR.green.opacity(0.9), radius: 3)
            Text(NUR.taglines[taglineIndex])
                .font(.inter(10)).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                .id(taglineIndex)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)))
        }
        .frame(height: 13, alignment: .leading)
        .clipped()
        .onReceive(taglineTimer) { _ in
            withAnimation(.easeOut(duration: 0.32)) { taglineIndex = (taglineIndex + 1) % NUR.taglines.count }
        }
    }

    private var suggestions: some View {
        ChipFlow(spacing: 6) {
            ForEach(NUR.suggestions, id: \.label) { s in
                Button {
                    Haptics.tap()
                    Task { await vm.suggest(s.label) }
                } label: {
                    Text(s.label).font(.inter(10, .semibold)).foregroundStyle(NUR.navy)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(s.color.opacity(0.33), lineWidth: 1))
                        .shadow(color: s.color.opacity(0.35), radius: 6, y: 4)
                }
                .buttonStyle(.pressable)
                .disabled(vm.typing)
                .opacity(vm.typing ? 0.55 : 1)
            }
        }
    }

    private func bubble(_ m: AssistantMessage) -> some View {
        HStack(alignment: .bottom, spacing: 6) {
            if m.mine { Spacer(minLength: 48) } else { orbAvatar }
            VStack(alignment: m.mine ? .trailing : .leading, spacing: 2) {
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
                    .shadow(color: m.mine ? Color(hex: 0x0B1F33).opacity(0.25) : NUR.purple.opacity(0.12), radius: 8, y: 5)
                Text(m.mine ? "You" : "Nuru")
                    .font(.inter(8)).foregroundStyle(NUR.hint)
            }
            if m.mine { meAvatar } else { Spacer(minLength: 48) }
        }
    }

    private var orbAvatar: some View {
        Circle().fill(NUR.orb).frame(width: 28, height: 28)
            .overlay(Icon(.sparkles, size: 12, color: .white))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }
    private var meAvatar: some View {
        Circle().fill(NUR.ink).frame(width: 28, height: 28)
            .overlay(Text(myInitials).font(.inter(8, .bold)).foregroundStyle(.white))
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }
    private var myInitials: String {
        let parts = (auth.profile?.fullName ?? "").split(separator: " ")
        guard let f = parts.first?.first else { return "ME" }
        if parts.count > 1, let l = parts.last?.first { return "\(f)\(l)".uppercased() }
        return String(f).uppercased()
    }

    private var typingRow: some View {
        HStack(alignment: .bottom, spacing: 6) {
            orbAvatar
            TypingDots()
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(Color.white, in: UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous))
                .overlay(UnevenRoundedRectangle(topLeadingRadius: 18, bottomLeadingRadius: 6, bottomTrailingRadius: 18, topTrailingRadius: 18, style: .continuous).stroke(NUR.border, lineWidth: 1))
        }
    }

    private var composer: some View {
        let sendable = !vm.draft.trimmingCharacters(in: .whitespaces).isEmpty && !vm.typing
        return HStack(alignment: .bottom, spacing: 8) {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("", text: $vm.draft, prompt: Text("Ask Nuru anything…").foregroundColor(NUR.hint), axis: .vertical)
                    .font(.inter(12)).foregroundStyle(NUR.navy).lineLimit(1...4)
                    .onSubmit {
                        if sendable { Haptics.action() }
                        Task { await vm.send() }
                    }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(NUR.cream, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(NUR.border, lineWidth: 1))

            Button {
                Haptics.action()
                Task { await vm.send() }
            } label: {
                Icon(.send, size: 17, color: .white)
                    .frame(width: 44, height: 44).background(NUR.sendG, in: Circle())
                    .shadow(color: NUR.purple.opacity(0.5), radius: 8, y: 4)
            }
            .buttonStyle(.pressable)
            .disabled(!sendable)
            // Dim whenever the button can't fire — it used to sit at full
            // strength while Nuru was still typing.
            .opacity(sendable ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.18), value: sendable)
        }
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .top) { Rectangle().fill(NUR.border).frame(height: 1) }
    }
}

// MARK: - Typing dots (the classic staggered pulse — still under Reduce Motion)

private struct TypingDots: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(NUR.purpleLt)
                    .frame(width: 6, height: 6)
                    .opacity(pulsing ? 1 : 0.35)
                    .scaleEffect(pulsing ? 1 : 0.75)
                    .animation(
                        reduceMotion ? nil :
                            .easeInOut(duration: 0.5)
                            .repeatForever(autoreverses: true)
                            .delay(Double(i) * 0.16),
                        value: pulsing)
            }
        }
        .onAppear { pulsing = true }
    }
}

// MARK: - ChipFlow (wrapping chip layout, mirrors Figma flex-wrap)

private struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? max(0, x - spacing) : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
    }
}
