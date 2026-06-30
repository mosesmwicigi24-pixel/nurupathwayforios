// Chat thread — the native port of screens/ChatThreadScreen.tsx. Message bubbles
// (mine right/gold, others left/white with author), reply previews, reactions, and
// a send composer. Voice/image bubbles show a tag for now.
import SwiftUI

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var thread: ChatThreadDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var draft = ""
    @Published var sending = false

    let conversation: ChatConversation
    init(conversation: ChatConversation) { self.conversation = conversation }

    func load() async {
        loading = true; error = nil
        do {
            thread = try await MemberAPI.chatConversation(conversation.conversationId)
            try? await MemberAPI.markChatRead(conversation.conversationId)
        } catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't open this chat." }
        loading = false
    }

    func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; defer { sending = false }
        do { try await MemberAPI.sendChatMessage(conversation.conversationId, body: body); draft = ""; await load() } catch {}
    }
}

struct ChatThreadView: View {
    @StateObject private var vm: ChatThreadViewModel
    @Environment(\.dismiss) private var dismiss

    init(conversation: ChatConversation) { _vm = StateObject(wrappedValue: ChatThreadViewModel(conversation: conversation)) }
    private var conv: ChatConversation { vm.conversation }

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.loading && vm.thread == nil {
                Spacer(); ProgressView(); Spacer()
            } else {
                messages
                composer
            }
        }
        .background(Nuru.chatPaper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.thread == nil { await vm.load() } }
    }

    private var header: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: .white).frame(width: 40, height: 40).background(Color.white.opacity(0.10), in: Circle())
            }
            if conv.kind == "dm" { Avatar(url: conv.avatarUrl, name: conv.title ?? "?", size: 34) }
            VStack(alignment: .leading, spacing: 0) {
                Text(conv.title ?? "Conversation").font(.inter(16, .semibold)).foregroundStyle(.white).lineLimit(1)
                if conv.kind != "dm" { Text("\(conv.memberCount) members").font(.nMicro).foregroundStyle(Nuru.onNavyDim) }
            }
            Spacer()
        }
        .padding(.horizontal, Nuru.S.lg).padding(.top, 54).padding(.bottom, Nuru.S.md)
        .background(Nuru.navy)
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Nuru.S.sm) {
                    ForEach(vm.thread?.messages ?? []) { m in MessageBubble(m: m).id(m.id) }
                }
                .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.md)
            }
            .onChange(of: vm.thread?.messages.count ?? 0) { _, _ in
                if let last = vm.thread?.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Nuru.S.sm) {
            TextField("Message…", text: $vm.draft, axis: .vertical)
                .font(.inter(15)).lineLimit(1...5)
                .padding(.horizontal, Nuru.S.base).padding(.vertical, 10).frame(minHeight: 42)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.pill))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.pill).stroke(Nuru.border, lineWidth: 1))
            Button { Task { await vm.send() } } label: {
                Icon(.send, size: 17, color: .white).frame(width: 42, height: 42).background(Nuru.navyDeep, in: Circle())
            }
            .disabled(vm.sending || vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .opacity(vm.sending || vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding(Nuru.S.sm)
        .background(Nuru.paper)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }
}

private struct MessageBubble: View {
    let m: ChatMessage
    var body: some View {
        HStack {
            if m.mine { Spacer(minLength: 40) }
            VStack(alignment: m.mine ? .trailing : .leading, spacing: 2) {
                if !m.mine && m.authorName.isEmpty == false {
                    Text(m.authorName).font(.nMicro).foregroundStyle(Nuru.gold).padding(.leading, 4)
                }
                if let reply = m.replyBody {
                    Text(reply).font(.nMicro).foregroundStyle(Nuru.muted).lineLimit(1)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Color.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                }
                Text(bodyText).font(.nBody).foregroundStyle(Nuru.ink)
                    .padding(.horizontal, Nuru.S.md).padding(.vertical, Nuru.S.sm)
                    .background(m.mine ? Nuru.myBubble : Nuru.white,
                               in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                HStack(spacing: 6) {
                    if m.isEdited { Text("edited").font(.nMicro).foregroundStyle(Nuru.faint) }
                    Text(timeShort(m.createdAt)).font(.nMicro).foregroundStyle(Nuru.faint)
                    if !m.reactions.isEmpty {
                        Text(m.reactions.map { "\($0.emoji)\($0.count)" }.joined(separator: " ")).font(.nMicro)
                    }
                }
                .padding(.horizontal, 4)
            }
            if !m.mine { Spacer(minLength: 40) }
        }
    }

    private var bodyText: String {
        switch m.msgType {
        case "voice": return "🎤 Voice note"
        case "image": return "📷 Photo"
        case "file": return "📎 Attachment"
        default: return m.body
        }
    }
    private func timeShort(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
}
