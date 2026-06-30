// Chat — the native port of screens/ChatScreen.tsx (inbox). The member's Spaces /
// DMs / Groups with last-message previews and unread badges, plus a "Discover
// spaces" section. Taps open the thread. Voice/image attachments are previewed as
// tags for now (the recording/upload subsystem lands later).
import SwiftUI

@MainActor
final class ChatInboxViewModel: ObservableObject {
    @Published var inbox: ChatInbox?
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { inbox = try await MemberAPI.chatInbox() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your chats." }
        loading = false
    }
}

struct ChatView: View {
    @StateObject private var vm = ChatInboxViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    content
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, Nuru.S.base)
                        .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .background(Nuru.paper.ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .navigationDestination(for: ChatConversation.self) { ChatThreadView(conversation: $0) }
        }
        .task { if vm.inbox == nil { await vm.load() } }
    }

    private var header: some View {
        HStack {
            Text("Chat").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.onNavy)
            Spacer()
            Icon(.messageCircle, size: 20, color: Nuru.onNavy)
                .frame(width: 44, height: 44).background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .padding(.horizontal, Nuru.S.screen).padding(.top, 60).padding(.bottom, Nuru.S.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    @ViewBuilder
    private var content: some View {
        if vm.loading && vm.inbox == nil {
            ProgressView().padding(.top, Nuru.S.xl)
        } else if let inbox = vm.inbox {
            VStack(spacing: Nuru.S.sm) {
                if inbox.conversations.isEmpty {
                    Text("No conversations yet.").font(.nBody).foregroundStyle(Nuru.muted).padding(.top, Nuru.S.xl)
                } else {
                    ForEach(inbox.conversations) { c in
                        NavigationLink(value: c) { ConversationRow(c: c) }.buttonStyle(.plain)
                    }
                }
                if !inbox.discoverSpaces.isEmpty {
                    Text("DISCOVER SPACES").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.gold)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Nuru.S.md)
                    ForEach(inbox.discoverSpaces) { s in DiscoverRow(s: s) }
                }
            }
        } else {
            Text(vm.error ?? "Couldn't load your chats.").font(.nBody).foregroundStyle(Nuru.muted).padding(.top, Nuru.S.xl)
        }
    }
}

private struct ConversationRow: View {
    let c: ChatConversation
    var body: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                if c.kind == "dm" {
                    Avatar(url: c.avatarUrl, name: c.title ?? "?", size: 48)
                } else {
                    ZStack { Circle().fill(Nuru.goldTint).frame(width: 48, height: 48); Icon(.messageCircle, size: 20, color: Nuru.gold) }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title ?? "Conversation").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Text(previewText).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 6) {
                if let at = c.lastAt { Text(timeAgo(at)).font(.nMicro).foregroundStyle(Nuru.faint) }
                if c.unread > 0 {
                    Text("\(c.unread)").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                        .frame(minWidth: 20, minHeight: 20).background(Nuru.gold, in: Circle())
                }
            }
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private var previewText: String {
        if c.lastType == "voice" { return "🎤 Voice note" }
        if c.lastType == "image" { return "📷 Photo" }
        let prefix = (c.lastAuthor != nil && c.kind != "dm") ? "\(c.lastAuthor!): " : ""
        return prefix + (c.lastBody ?? "No messages yet")
    }
}

private struct DiscoverRow: View {
    let s: DiscoverSpace
    var body: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { Circle().fill(Nuru.surface).frame(width: 40, height: 40); Icon(.users, size: 18, color: Nuru.ink600) }
            VStack(alignment: .leading, spacing: 1) {
                Text(s.title ?? "Space").font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Text("\(s.memberCount) members").font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Spacer(minLength: 0)
            Text("Join").font(.inter(12, .bold)).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 14).padding(.vertical, 7).background(Nuru.surface, in: Capsule())
                .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}
