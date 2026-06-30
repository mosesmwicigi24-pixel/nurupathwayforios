// Chat thread — the native port of screens/ChatThreadScreen.tsx. A warm-paper
// thread over a navy header: navy bubbles (mine, right) with read receipts, white
// bubbles (others, left) with an avatar + gold author name, reply previews,
// reactions, image/voice bubbles, a quick-reply chip row, and the composer
// (attach · message field · AI sparkle · emoji · gold mic).
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

    var isSpace: Bool {
        let k = thread?.kind ?? conversation.kind
        return k != "dm"
    }
    var title: String { thread?.title ?? conversation.title ?? "Conversation" }
    var topic: String? {
        let t = thread?.topic ?? conversation.topic
        return (t?.isEmpty == false) ? t : nil
    }
    var memberCount: Int { thread?.memberCount ?? conversation.memberCount }
    var avatarUrl: String? { conversation.avatarUrl }
    var subtitle: String {
        isSpace ? "Public space · \(memberCount) members" : "Direct message"
    }

    func load() async {
        loading = true; error = nil
        do {
            thread = try await MemberAPI.chatConversation(conversation.conversationId)
            try? await MemberAPI.markChatRead(conversation.conversationId)
        } catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't open this chat." }
        loading = false
    }

    func send(_ text: String? = nil) async {
        let body = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true; defer { sending = false }
        do {
            try await MemberAPI.sendChatMessage(conversation.conversationId, body: body)
            if text == nil { draft = "" }
            await load()
        } catch {}
    }

    func react(_ m: ChatMessage, _ emoji: String) async {
        do { _ = try await MemberAPI.toggleChatReaction(m.messageId, emoji: emoji); await load() } catch {}
    }
}

struct ChatThreadView: View {
    @StateObject private var vm: ChatThreadViewModel
    @EnvironmentObject var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    private let quickReplies = ["Amen 🙏", "Praying for you 💛", "On my way 🏃", "Thank you 🙏"]

    init(conversation: ChatConversation) { _vm = StateObject(wrappedValue: ChatThreadViewModel(conversation: conversation)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.loading && vm.thread == nil {
                Spacer(); ProgressView().tint(Nuru.gold); Spacer()
            } else {
                messages
                quickReplyRow
                composer
            }
        }
        .background(Nuru.chatPaper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.thread == nil { await vm.load() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: Nuru.S.md) {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: .white)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.10), in: Circle())
                }

                if vm.isSpace {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(hex: 0x2E7D6B))
                        .frame(width: 38, height: 38)
                        .overlay(Text("#").font(.inter(18, .bold)).foregroundStyle(.white))
                } else {
                    Avatar(url: vm.avatarUrl, name: vm.title, size: 38)
                        .overlay(Circle().stroke(Nuru.gold.opacity(0.6), lineWidth: 1.5))
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.title).font(.inter(16, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text(vm.subtitle).font(.inter(11)).foregroundStyle(Nuru.onNavyDim).lineLimit(1)
                }

                Spacer(minLength: Nuru.S.sm)

                Button { } label: {
                    Icon(.sparkles, size: 18, color: Nuru.goldGlow)
                        .frame(width: 38, height: 38)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.30), lineWidth: 1))
                }
            }
            .padding(.horizontal, Nuru.S.base)
            .padding(.top, 54)
            .padding(.bottom, Nuru.S.md)

            if vm.isSpace, let topic = vm.topic {
                HStack(spacing: 6) {
                    Icon(.flag, size: 13, color: Nuru.onNavyDim)
                    Text(topic).font(.inter(12)).foregroundStyle(Nuru.onNavyDim).lineLimit(1)
                    Spacer()
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.vertical, 10)
                .background(Color.white.opacity(0.05))
                .overlay(Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1), alignment: .top)
            }
        }
        .background(Nuru.navy)
    }

    // MARK: Messages

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: Nuru.S.md) {
                    confidenceBanner
                    if let group = dateLabel { dateChip(group) }
                    ForEach(vm.thread?.messages ?? []) { m in
                        MessageBubble(m: m) { emoji in Task { await vm.react(m, emoji) } }
                            .id(m.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.vertical, Nuru.S.md)
            }
            .onChange(of: vm.thread?.messages.count ?? 0) { _, _ in scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy, animated: false) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = vm.thread?.messages.last else { return }
        if animated { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }

    private var confidenceBanner: some View {
        HStack(spacing: 6) {
            Icon(.lock, size: 11, color: Nuru.faint)
            Text("Held in confidence — speak life here")
                .font(.inter(11)).foregroundStyle(Nuru.faint)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    private var dateLabel: String? {
        guard let first = vm.thread?.messages.first,
              let d = ISO8601DateFormatter.nuru.date(from: first.createdAt) ?? ISO8601DateFormatter().date(from: first.createdAt)
        else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "Today" }
        if cal.isDateInYesterday(d) { return "Yesterday" }
        let f = DateFormatter()
        f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .weekOfYear) ? "EEEE" : "MMM d"
        return f.string(from: d)
    }

    private func dateChip(_ text: String) -> some View {
        Text(text)
            .font(.inter(12, .semibold))
            .foregroundStyle(Nuru.goldLo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
    }

    // MARK: Quick replies

    private var quickReplyRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(quickReplies, id: \.self) { reply in
                    Button { Task { await vm.send(reply) } } label: {
                        Text(reply)
                            .font(.inter(13, .medium))
                            .foregroundStyle(Nuru.ink)
                            .padding(.horizontal, Nuru.S.base)
                            .padding(.vertical, 9)
                            .background(Nuru.white, in: Capsule())
                            .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, Nuru.S.base)
            .padding(.vertical, Nuru.S.sm)
        }
    }

    // MARK: Composer

    private var composer: some View {
        HStack(alignment: .center, spacing: Nuru.S.sm) {
            Circle()
                .fill(Nuru.navyDeep)
                .frame(width: 34, height: 34)
                .overlay(
                    Text(Avatar.initials(auth.profile?.fullName ?? "You"))
                        .font(.inter(12, .semibold)).foregroundStyle(.white)
                )

            Button { } label: {
                Icon(.plus, size: 20, color: Nuru.ink600)
            }
            .buttonStyle(.plain)

            HStack(alignment: .center, spacing: 6) {
                TextField("Message", text: $vm.draft, axis: .vertical)
                    .font(.inter(15))
                    .lineLimit(1...5)
                Button { Task { await vm.send() } } label: {
                    Icon(.sparkle, size: 16, color: Nuru.goldLo)
                        .frame(width: 26, height: 26)
                        .background(Nuru.goldChipBg, in: Circle())
                }
                .buttonStyle(.plain)
                Button { } label: {
                    Icon(.smile, size: 18, color: Nuru.ink400)
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, Nuru.S.base)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(Nuru.surface, in: Capsule())
            .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))

            Button {
                let trimmed = vm.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // mic placeholder
                } else {
                    Task { await vm.send() }
                }
            } label: {
                Icon(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? .mic : .send, size: 18, color: .white)
                    .frame(width: 42, height: 42)
                    .background(Nuru.goldGradient, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(vm.sending)
            .opacity(vm.sending ? 0.6 : 1)
        }
        .padding(.horizontal, Nuru.S.md)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.base)
        .background(Nuru.paper)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let m: ChatMessage
    var onReact: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            if m.mine {
                Spacer(minLength: 48)
                bubbleColumn
            } else {
                Avatar(url: m.authorAvatar, name: m.authorName, size: 28)
                bubbleColumn
                Spacer(minLength: 48)
            }
        }
    }

    private var bubbleColumn: some View {
        VStack(alignment: m.mine ? .trailing : .leading, spacing: 3) {
            if !m.mine && !m.authorName.isEmpty {
                Text(m.authorName)
                    .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
                    .padding(.leading, 4)
            }

            bubble

            if !m.reactions.isEmpty { reactionChips }
        }
    }

    @ViewBuilder private var bubble: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let replyBody = m.replyBody {
                replyPreview(replyBody)
            }

            switch m.msgType {
            case "image":
                imageContent
            case "voice":
                voicePill
            default:
                Text(m.body)
                    .font(.inter(15))
                    .foregroundStyle(m.mine ? .white : Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            footer
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(m.mine ? AnyShapeStyle(Nuru.navyDeep) : AnyShapeStyle(Nuru.white))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(m.mine ? Color.clear : Nuru.border, lineWidth: 1)
        )
        .nuruShadow(m.mine ? 0 : 0.5)
    }

    private func replyPreview(_ body: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let author = m.replyAuthor {
                Text(author).font(.inter(11, .semibold))
                    .foregroundStyle(m.mine ? Nuru.goldGlow : Nuru.goldLo)
            }
            Text(body).font(.inter(12))
                .foregroundStyle(m.mine ? Nuru.onNavyDim : Nuru.muted)
                .lineLimit(2)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background((m.mine ? Color.white.opacity(0.10) : Color.black.opacity(0.04)),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            Rectangle().fill(m.mine ? Nuru.goldGlow : Nuru.goldLo).frame(width: 3),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var imageContent: some View {
        if let url = m.attachmentUrl, let u = URL(string: url) {
            CachedAsyncImage(url: u) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else if phase.error != nil {
                    placeholderTile
                } else {
                    ZStack { placeholderTile; ProgressView().tint(Nuru.gold) }
                }
            }
            .frame(maxWidth: 240, maxHeight: 280)
            .frame(minHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !m.body.isEmpty {
                Text(m.body).font(.inter(15)).foregroundStyle(m.mine ? .white : Nuru.ink)
            }
        } else {
            placeholderTile.frame(width: 200, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var placeholderTile: some View {
        Rectangle().fill(Nuru.mutedBg)
            .overlay(Icon(.image, size: 28, color: Nuru.faint))
    }

    private var voicePill: some View {
        HStack(spacing: 8) {
            Icon(.audioLines, size: 16, color: m.mine ? Nuru.goldGlow : Nuru.goldLo)
            Text("Voice note").font(.inter(14, .medium))
                .foregroundStyle(m.mine ? .white : Nuru.ink)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background((m.mine ? Color.white.opacity(0.10) : Nuru.goldChipBg),
                    in: Capsule())
    }

    private var footer: some View {
        HStack(spacing: 5) {
            if m.isEdited {
                Text("edited").font(.inter(10))
                    .foregroundStyle(m.mine ? Nuru.onNavyDim : Nuru.faint)
            }
            Text(timeShort(m.createdAt)).font(.inter(10))
                .foregroundStyle(m.mine ? Nuru.onNavyDim : Nuru.faint)
            if m.mine { readReceipt }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder private var readReceipt: some View {
        let read = (m.readCount ?? 0) > 0
        if read {
            Text("✓✓").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldGlow)
        } else {
            HStack(spacing: 4) {
                Text("✓✓").font(.inter(11, .semibold)).foregroundStyle(Nuru.onNavyDim)
            }
        }
    }

    private var reactionChips: some View {
        HStack(spacing: 5) {
            ForEach(m.reactions.indices, id: \.self) { i in
                let r = m.reactions[i]
                Button { onReact(r.emoji) } label: {
                    HStack(spacing: 3) {
                        Text(r.emoji).font(.inter(12))
                        if r.count > 1 {
                            Text("\(r.count)").font(.inter(11, .semibold))
                                .foregroundStyle(r.mine ? Nuru.goldChipText : Nuru.muted)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(r.mine ? Nuru.goldChipBg : Nuru.white, in: Capsule())
                    .overlay(Capsule().stroke(r.mine ? Nuru.gold.opacity(0.4) : Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 2)
    }

    private func timeShort(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
}
