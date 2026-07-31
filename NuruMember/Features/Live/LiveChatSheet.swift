// Nuru Live L5 — the lightweight live-chat sheet, shared verbatim by the
// broadcaster screen and the viewer player (present with
// `.presentationDetents([.medium])` at the call site). Deliberately NOT the
// full Aurora chat thread: no read receipts, no offline queue, no edit/
// delete, no reactions-on-messages — just a 3s-polled (since-cursor) message
// list + composer, dressed in the same light-bubble language as 1:1 threads
// so it still feels like "this app's chat", not a bolted-on widget.
import SwiftUI

struct LiveChatSheet: View {
    let streamId: String
    let myUserId: String?

    @Environment(\.dismiss) private var dismiss
    @State private var messages: [LiveChatMessage] = []
    @State private var loading = true
    @State private var draft = ""
    @State private var sending = false
    @State private var pollTask: Task<Void, Never>?
    @State private var cursor: String?

    private static let maxLength = 500

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                messageList
                Divider().overlay(Nuru.border)
                composer
            }
            .background(Nuru.chatPaper.ignoresSafeArea())
            .navigationTitle("Live chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Haptics.tap()
                        dismiss()
                    } label: {
                        Icon(.x, size: 15, color: Nuru.ink600)
                            .frame(width: 30, height: 30)
                            .background(Nuru.white, in: Circle())
                    }
                }
            }
        }
        .task { await start() }
        .onDisappear { pollTask?.cancel() }
    }

    // MARK: List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if loading {
                        ProgressView().tint(Nuru.gold).padding(.top, 40)
                            .frame(maxWidth: .infinity)
                    } else if messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(messages) { m in
                            LiveChatBubble(message: m, mine: myUserId != nil && m.userId == myUserId)
                                .id(m.messageId)
                        }
                    }
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.S.sm)
            }
            .onChange(of: messages.count) { _, _ in
                guard let last = messages.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.messageId, anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Icon(.messageCircle, size: 26, color: Nuru.ink300)
            Text("No messages yet — say something!")
                .font(.inter(12)).foregroundStyle(Nuru.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 50)
    }

    // MARK: Composer

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Say something…", text: $draft, axis: .vertical)
                .font(.inter(14))
                .lineLimit(1...4)
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Nuru.white, in: Capsule())
                .onChange(of: draft) { _, v in
                    if v.count > Self.maxLength { draft = String(v.prefix(Self.maxLength)) }
                }
            Button {
                Haptics.tap()
                Task { await send() }
            } label: {
                Icon(.send, size: 15, color: .white)
                    .frame(width: 38, height: 38)
                    .background(canSend ? Nuru.gold : Nuru.gold.opacity(0.4), in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(!canSend || sending)
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, 10)
        .background(Nuru.paper)
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Poll lifecycle

    private func start() async {
        await loadInitial()
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await pollNew()
            }
        }
    }

    private func loadInitial() async {
        loading = true
        defer { loading = false }
        guard let rows = try? await MemberAPI.fetchLiveMessages(streamId: streamId) else { return }
        messages = rows
        cursor = rows.last?.sentAt
    }

    private func pollNew() async {
        guard let rows = try? await MemberAPI.fetchLiveMessages(streamId: streamId, since: cursor),
              !rows.isEmpty else { return }
        let existing = Set(messages.map(\.messageId))
        let fresh = rows.filter { !existing.contains($0.messageId) }
        if let last = rows.last { cursor = last.sentAt }
        guard !fresh.isEmpty else { return }
        messages.append(contentsOf: fresh)
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending else { return }
        sending = true
        defer { sending = false }
        draft = ""
        guard let sent = try? await MemberAPI.sendLiveMessage(streamId: streamId, body: text) else { return }
        if !messages.contains(where: { $0.messageId == sent.messageId }) {
            messages.append(sent)
            cursor = sent.sentAt
        }
    }
}

// MARK: - One bubble — light card on the chat-paper canvas, gold-green for
// mine (matches Nuru.myBubble), plain white for everyone else + their name.

private struct LiveChatBubble: View {
    let message: LiveChatMessage
    let mine: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if mine { Spacer(minLength: 50) }
            if !mine { Avatar(url: message.avatarUrl, name: message.fullName, size: 26) }
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine {
                    Text(message.fullName).font(.inter(10, .semibold)).foregroundStyle(Nuru.ink600)
                }
                Text(message.body).font(.inter(13.5)).foregroundStyle(Nuru.ink)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(mine ? Nuru.myBubble : Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !mine { Spacer(minLength: 50) }
        }
    }
}
