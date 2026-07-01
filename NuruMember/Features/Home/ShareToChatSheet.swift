// Share a snippet (the verse of the day, the welcome video) into an existing
// chat conversation — a space, a group, or a direct message — by posting it as a
// message (POST /chat/conversations/{id}/messages). Reached from Home's Share
// buttons via `.sheet(item:)`.
import SwiftUI

/// Identifiable payload so Home can drive the sheet with `.sheet(item:)`.
struct SharePayload: Identifiable {
    let id = UUID()
    let text: String
}

struct ShareToChatSheet: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    @State private var conversations: [ChatConversation] = []
    @State private var loading = true
    @State private var error: String?
    @State private var sendingId: String?
    @State private var sentTitle: String?

    private var spaces: [ChatConversation] { conversations.filter { $0.kind == "space" } }
    private var groups: [ChatConversation] { conversations.filter { $0.kind == "group" } }
    private var directs: [ChatConversation] { conversations.filter { $0.kind == "dm" } }

    var body: some View {
        NavigationStack {
            ZStack {
                Nuru.paper.ignoresSafeArea()
                content
            }
            .navigationTitle("Share to chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Nuru.gold)
                }
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var content: some View {
        if let sent = sentTitle {
            VStack(spacing: Nuru.S.md) {
                Icon(.circleCheckBig, size: 40, color: Nuru.gold)
                Text("Shared to \(sent)").font(.inter(16, .bold)).foregroundStyle(Nuru.ink)
            }
        } else if loading {
            ProgressView().tint(Nuru.gold)
        } else if let e = error {
            VStack(spacing: Nuru.S.md) {
                Text(e).font(.nCaption).foregroundStyle(Nuru.muted)
                Button("Try again") { Task { await load() } }.foregroundStyle(Nuru.gold)
            }.padding(Nuru.S.screen)
        } else if conversations.isEmpty {
            Text("You're not in any conversations yet.")
                .font(.nCaption).foregroundStyle(Nuru.muted).padding(Nuru.S.screen)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.lg) {
                    previewCard
                    section("SPACES", spaces)
                    section("GROUPS", groups)
                    section("INDIVIDUALS", directs)
                }
                .padding(Nuru.S.screen)
            }
        }
    }

    private var previewCard: some View {
        Text(text)
            .font(.fraunces(14)).foregroundStyle(Nuru.ink).lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    @ViewBuilder private func section(_ title: String, _ items: [ChatConversation]) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text(title).font(.inter(11, .bold)).tracking(1.2).foregroundStyle(Nuru.muted)
                ForEach(items) { row($0) }
            }
        }
    }

    private func row(_ c: ChatConversation) -> some View {
        Button { Task { await send(to: c) } } label: {
            HStack(spacing: Nuru.S.md) {
                Avatar(url: c.avatarUrl, name: c.title ?? "Chat", size: 40)
                VStack(alignment: .leading, spacing: 1) {
                    Text(c.title ?? (c.kind == "dm" ? "Direct message" : "Conversation"))
                        .font(.inter(15, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    if c.kind != "dm" {
                        Text("\(c.memberCount) member\(c.memberCount == 1 ? "" : "s")")
                            .font(.nMicro).foregroundStyle(Nuru.faint)
                    }
                }
                Spacer(minLength: 0)
                if sendingId == c.conversationId {
                    ProgressView().tint(Nuru.gold)
                } else {
                    Icon(.send, size: 16, color: Nuru.gold)
                }
            }
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(sendingId != nil)
    }

    private func load() async {
        loading = true; error = nil
        do { conversations = try await MemberAPI.chatInbox().conversations }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your chats." }
        loading = false
    }

    private func send(to c: ChatConversation) async {
        guard sendingId == nil else { return }
        sendingId = c.conversationId
        do {
            try await MemberAPI.sendChatMessage(c.conversationId, body: text)
            sentTitle = c.title ?? "chat"
            try? await Task.sleep(nanoseconds: 900_000_000)
            dismiss()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't send. Try again."
        }
        sendingId = nil
    }
}
