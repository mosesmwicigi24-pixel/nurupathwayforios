// AI reply drafting — a reusable ✨ composer add-on. Tap → Nuru reads the recent
// messages (one summarize-and-draft call through the existing POST /assistant/chat),
// then a sheet shows a one-line summary + an EDITABLE draft the member can send
// ("Use draft" → onUseDraft), tweak in place, or throw away ("Discard").
// Colors mirror the Nuru assistant orb (purple C4B5FD→7C3AED→2A1259 + brand gold).
import SwiftUI

/// ✨ icon button for a composer row. `recentMessages` is (author, text),
/// oldest→newest — callers pass at most 5. `conversationId` (when the surface is
/// a chat thread) lets the server ground on messages the member can access.
/// `onUseDraft` receives the (possibly edited) draft; the caller puts it in its
/// composer so the member still explicitly taps send.
struct AiDraftButton: View {
    let recentMessages: [(author: String, text: String)]
    var conversationId: String? = nil
    let onUseDraft: (String) -> Void

    @State private var busy = false
    @State private var sheetOpen = false
    @State private var failed = false
    @State private var summary: String?
    @State private var draft = ""

    // The NuruAssistant orb palette (NUR.orb) + the brand gold story ring.
    private let orb = LinearGradient(
        colors: [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED), Color(hex: 0x2A1259)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    private let goldGrad = LinearGradient(
        colors: [Color(hex: 0xE6C068), Color(hex: 0xC89B3C), Color(hex: 0xB07D2E)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    var body: some View {
        Button {
            Task { await requestDraft() }
        } label: {
            ZStack {
                Circle().fill(orb)
                if busy {
                    ProgressView().tint(.white).scaleEffect(0.55)
                } else {
                    Icon(.sparkles, size: 15, color: .white)
                }
            }
            .frame(width: 30, height: 30)
            .overlay(Circle().stroke(Nuru.gold.opacity(0.45), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .accessibilityLabel("Draft a reply with Nuru")
        .sheet(isPresented: $sheetOpen) { sheetBody }
    }

    // MARK: Sheet — "NURU SUGGESTS" · summary · editable draft · Use/Discard

    private var sheetBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Circle().fill(orb)
                    .frame(width: 22, height: 22)
                    .overlay(Icon(.sparkles, size: 12, color: .white))
                Text("NURU SUGGESTS")
                    .font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Color(hex: 0x9A7A2A))
            }
            Text(failed
                 ? "Nuru couldn’t reach the assistant just now — you can still write your own reply below."
                 : (summary ?? "Here’s a reply you could send."))
                .font(.inter(12)).foregroundStyle(Color(hex: 0x59667C)).lineSpacing(4)
            TextField("Write your reply…", text: $draft, axis: .vertical)
                .font(.inter(13)).foregroundStyle(Nuru.ink).lineSpacing(4)
                .lineLimit(3...8)
                .padding(Nuru.S.md)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            HStack(spacing: 10) {
                let canUse = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                Button {
                    Haptics.action()
                    onUseDraft(draft.trimmingCharacters(in: .whitespacesAndNewlines))
                    sheetOpen = false
                } label: {
                    Text("Use draft").font(.inter(13, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(goldGrad, in: Capsule())
                        .opacity(canUse ? 1 : 0.5)
                }
                .buttonStyle(.pressable)
                .disabled(!canUse)
                Button {
                    Haptics.tap()
                    sheetOpen = false
                } label: {
                    Text("Discard").font(.inter(13, .semibold)).foregroundStyle(Color(hex: 0x59667C))
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(Color.white, in: Capsule())
                        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.white)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    // MARK: One summarize-and-draft turn through the assistant

    private func requestDraft() async {
        guard !busy else { return }
        busy = true
        Haptics.tap()
        let reply = try? await MemberAPI.assistantChat(
            [AssistantMessage(role: "user", text: Self.buildDraftPrompt(recentMessages))],
            conversationId: conversationId, contextLimit: 5)
        busy = false
        failed = (reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let (s, d) = Self.parseSummaryDraft(reply ?? "")
        summary = s
        draft = d
        sheetOpen = true
    }

    /// One user turn asking Nuru to summarize the recent messages and draft a reply.
    static func buildDraftPrompt(_ recent: [(author: String, text: String)]) -> String {
        let lines = recent.suffix(5).map { author, text in
            "[\(author)]: \(String(text.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces).prefix(400)))"
        }
        let convo = lines.isEmpty ? "(no messages yet — this reply would start the conversation)" : lines.joined(separator: "\n")
        return "Here are the last messages in a church group chat:\n\(convo)\n"
            + "Summarize the conversation in one short sentence, then draft a warm, natural reply I could send "
            + "(2-3 sentences, no emojis unless fitting). Reply in this exact format:\n"
            + "SUMMARY: …\nDRAFT: …"
    }

    /// Defensive SUMMARY:/DRAFT: parse. If the model skipped the format the whole
    /// reply becomes the draft (summary nil).
    static func parseSummaryDraft(_ reply: String) -> (summary: String?, draft: String) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return (nil, "") }
        guard let draftRange = text.range(of: "DRAFT:", options: .caseInsensitive) else { return (nil, text) }
        let draft = String(text[draftRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        var summary: String?
        if let summaryRange = text.range(of: "SUMMARY:", options: .caseInsensitive),
           summaryRange.lowerBound < draftRange.lowerBound {
            let s = String(text[summaryRange.upperBound..<draftRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            summary = s.isEmpty ? nil : s
        }
        return (summary, draft.isEmpty ? text : draft)
    }
}
