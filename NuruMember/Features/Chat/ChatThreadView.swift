// Chat thread — native port of the Figma "Aurora" ChatThread presentation:
// a warm #E9E6DF canvas with floating light bubbles (no tails), per-sender
// accent colors (stable hash → palette, gold for self), quoted replies on a
// faint navy wash with an accent bar, in-bubble reaction chips + read ticks,
// gradient-hairline day separators, quick replies, and the cream composer
// (plus · message · ✨ Nuru draft assist · smile · navy mic / gold send).
// All data is real (MemberAPI). The make's voice recorder, attachment and
// emoji pickers are mock-only and deliberately not reproduced here.
import Combine
import SwiftUI
import UIKit

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
    /// Pastor mail: a DM that began as a broadcast FROM the other person. The
    /// sender's own copy never dresses (their broadcast messages are `mine`) —
    /// this is the member's side only, which is the whole point: it reads as
    /// "Talk with Pastor", not as one DM among many.
    var isPastorMail: Bool {
        !isSpace && allMessages.contains { $0.broadcastId != nil && !$0.mine }
    }
    // DMs carry an inspiring covenant line instead of a flat "Direct message".
    var subtitle: String {
        if isSpace { return "Public space · \(memberCount) members" }
        return isPastorMail ? "Talk with Pastor" : "Walking together in faith"
    }

    func load() async {
        loading = true; error = nil
        do {
            thread = try await MemberAPI.chatConversation(conversation.conversationId)
            try? await MemberAPI.markChatRead(conversation.conversationId)
        } catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't open this chat." }
        loading = false
    }

    /// Optimistic messages queued locally until the server echoes them back.
    @Published var pending: [ChatMessage] = []

    /// Optimistic edit/delete state — applied on top of whatever the server
    /// last returned so Edit/Delete read instantly, and can be rolled back if
    /// the PATCH/DELETE fails (see editMessage/deleteMessage below).
    @Published var editOverrides: [String: String] = [:]
    @Published var locallyDeletedIds: Set<String> = []

    /// Server thread + any still-in-flight optimistic sends (deduped by id),
    /// with optimistic edits/deletes layered on top.
    /// Ids compare case-insensitively: Postgres normalizes uuid columns to
    /// lowercase, so a client-minted uppercase id comes back lowercased — a
    /// case-sensitive match would keep the optimistic bubble alongside the
    /// server echo forever (the "every send shows twice" bug).
    var allMessages: [ChatMessage] {
        let base = thread?.messages ?? []
        let ids = Set(base.map { $0.messageId.lowercased() })
        let merged = base + pending.filter { !ids.contains($0.messageId.lowercased()) }
        return merged
            .filter { !locallyDeletedIds.contains($0.messageId) }
            .map { m in
                guard let body = editOverrides[m.messageId] else { return m }
                var edited = m
                edited.body = body
                edited.isEdited = true
                return edited
            }
    }

    /// Offline-capable send: the bubble appears instantly and the write goes through
    /// the durable queue as `chat_messages:create` (idempotent on message_id).
    func send(_ text: String? = nil) async {
        let body = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true; defer { sending = false }
        // Lowercased to match the server's canonical uuid form, so the echoed
        // row and this optimistic one dedupe by exact id.
        let mid = UUID().uuidString.lowercased()
        pending.append(ChatMessage(
            messageId: mid, authorUserId: "", authorName: "You", authorAvatar: nil,
            body: body, msgType: "text", attachmentUrl: nil, replyBody: nil, replyAuthor: nil,
            isEdited: false, createdAt: ISO8601DateFormatter().string(from: Date()), mine: true,
            reactions: [], readCount: nil, recipientCount: nil, aiTag: nil))
        if text == nil { draft = "" }
        await SyncCoordinator.shared.enqueue(domain: "chat_messages", op: "create", payload: [
            "conversation_id": AnyCodable(conversation.conversationId),
            "message_id": AnyCodable(mid),
            "body": AnyCodable(body),
            "msg_type": AnyCodable("text"),
        ])
        if SyncCoordinator.shared.isOnline {
            await load()
            // Case-insensitive prune (see allMessages) — also heals bubbles
            // minted uppercase by older builds that are still in `pending`.
            let landed = Set((thread?.messages ?? []).map { $0.messageId.lowercased() })
            pending.removeAll { landed.contains($0.messageId.lowercased()) }
        }
    }

    func react(_ m: ChatMessage, _ emoji: String) async {
        do { _ = try await MemberAPI.toggleChatReaction(m.messageId, emoji: emoji); await load() } catch {}
    }

    /// Author-only edit: reads instantly (optimistic), then reconciles with
    /// the server. A failed PATCH rolls the bubble straight back to what it
    /// said before — never leaves a body on screen the server didn't accept.
    @discardableResult
    func editMessage(_ messageId: String, newBody: String) async -> Bool {
        let body = newBody.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return false }
        let previous = editOverrides[messageId]
        editOverrides[messageId] = body
        do {
            _ = try await MemberAPI.editChatMessage(messageId, body: body)
            await load()
            editOverrides[messageId] = nil
            return true
        } catch {
            editOverrides[messageId] = previous
            return false
        }
    }

    /// Author-only soft delete: the bubble disappears immediately; a failed
    /// DELETE brings it straight back rather than leaving a false "gone" state.
    @discardableResult
    func deleteMessage(_ messageId: String) async -> Bool {
        locallyDeletedIds.insert(messageId)
        do {
            _ = try await MemberAPI.deleteChatMessage(messageId)
            await load()
            return true
        } catch {
            locallyDeletedIds.remove(messageId)
            return false
        }
    }
}

// MARK: - Aurora palette (Figma ChatThread.tsx constants)

private enum Aurora {
    static let canvas       = Color(hex: 0xE9E6DF)              // CHAT_BG
    static let bubble       = Color(hex: 0xF3F4F3)              // SENDER_BUBBLE / ME_BUBBLE
    static let textDark     = Color(hex: 0x17283D)              // body on light bubbles
    static let meta         = Color(hex: 0x9AA3AF)              // timestamps / ticks
    static let quoteBg      = Color(hex: 0x0B1F33, alpha: 0.05) // QUOTE_BG
    static let quoteBody    = Color(hex: 0x5B6472)
    static let bubbleBorder = Color(hex: 0x0B1F33, alpha: 0.07) // BUBBLE_BORDER
    static let border       = Color(hex: 0x0B1F33, alpha: 0.08) // BORDER
    static let chipBg       = Color(hex: 0x0B1F33, alpha: 0.06) // non-mine reaction chip
    static let hairline     = Color(hex: 0x0B1F33, alpha: 0.12) // day-separator line
    static let shadowInk    = Color(hex: 0x0B1F33)              // SOFT_SHADOW base
    static let navy         = Color(hex: 0x0A1628)              // NAVY
    static let gold         = Color(hex: 0xC89B3C)              // GOLD (= self accent)
    static let goldDeep     = Color(hex: 0xA8761A)              // gold text on light
    static let dayGold      = Color(hex: 0xA8861C)              // day-chip label
    static let confidence   = Color(hex: 0x6A7686)

    static let storyRing = LinearGradient(
        colors: [Color(hex: 0xE6C068), Color(hex: 0xC89B3C), Color(hex: 0xB07D2E)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let inkBubble = LinearGradient(
        colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let sectionBg = LinearGradient(
        colors: [Color(hex: 0xF6F4EE), Color(hex: 0xF1ECE1)],
        startPoint: .top, endPoint: .bottom)

    /// SENDER_PALETTE `name` colors — stable, harmonious accents (Telegram pattern).
    static let senderPalette: [Color] = [
        Color(hex: 0x4F46E5), // indigo
        Color(hex: 0x0284C7), // sky
        Color(hex: 0x0D9488), // teal
        Color(hex: 0x059669), // emerald
        Color(hex: 0xDB2777), // pink
        Color(hex: 0xC2410C), // burnt orange
        Color(hex: 0x7C3AED), // violet
        Color(hex: 0xB45309), // amber
    ]

    /// Same stable hash as the make: `h = (h * 31 + charCodeAt(i)) >>> 0`.
    static func accent(for id: String) -> Color {
        guard !id.isEmpty else { return gold }
        var h: UInt32 = 0
        for u in id.utf16 { h = h &* 31 &+ UInt32(u) }
        return senderPalette[Int(h % UInt32(senderPalette.count))]
    }
}

// MARK: - Row model (consecutive-run grouping + day separators)

private struct ThreadRow: Identifiable {
    let m: ChatMessage
    let showAuthor: Bool    // colored sender name inside the bubble (groups, run head)
    let showTail: Bool      // last of a consecutive run — avatar + squared corner
    let daySeparator: String?
    var id: String { m.messageId }
}

private func groupKey(_ m: ChatMessage) -> String {
    m.mine ? "me" : (m.authorUserId.isEmpty ? m.authorName : m.authorUserId)
}

private func buildRows(_ messages: [ChatMessage], multi: Bool) -> [ThreadRow] {
    var rows: [ThreadRow] = []
    var lastDay: String?
    for (i, m) in messages.enumerated() {
        let head = i == 0 || groupKey(messages[i - 1]) != groupKey(m)
        let tail = i == messages.count - 1 || groupKey(messages[i + 1]) != groupKey(m)
        let day = dayLabel(m.createdAt)
        let sep = (day != nil && day != lastDay) ? day : nil
        if let day { lastDay = day }
        rows.append(ThreadRow(m: m, showAuthor: multi && !m.mine && head, showTail: tail, daySeparator: sep))
    }
    return rows
}

private func chatDate(_ iso: String) -> Date? {
    ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
}

private func dayLabel(_ iso: String) -> String? {
    guard let d = chatDate(iso) else { return nil }
    let cal = Calendar.current
    if cal.isDateInToday(d) { return "Today" }
    if cal.isDateInYesterday(d) { return "Yesterday" }
    let f = DateFormatter()
    f.dateFormat = cal.isDate(d, equalTo: Date(), toGranularity: .weekOfYear) ? "EEEE" : "MMM d"
    return f.string(from: d)
}

private func timeShort(_ iso: String) -> String {
    guard let d = chatDate(iso) else { return "" }
    let f = DateFormatter(); f.dateFormat = "h:mm a"
    return f.string(from: d)
}

/// Body text with @mentions rendered in gold (the make's `renderBody`).
private func mentionText(_ s: String) -> Text {
    var out = Text(verbatim: "")
    var idx = s.startIndex
    for match in s.matches(of: #/@\w+/#) {
        if match.range.lowerBound > idx {
            out = out + Text(verbatim: String(s[idx..<match.range.lowerBound]))
        }
        out = out + Text(verbatim: String(s[match.range]))
            .foregroundStyle(Aurora.gold)
            .fontWeight(.semibold)
        idx = match.range.upperBound
    }
    if idx < s.endIndex { out = out + Text(verbatim: String(s[idx...])) }
    return out
}

// MARK: - Screen

struct ChatThreadView: View {
    @StateObject private var vm: ChatThreadViewModel
    @EnvironmentObject var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    /// Tracked via keyboardWillShow/Hide so the list can pin to the newest turn.
    @State private var keyboardVisible = false
    /// Edit/Delete — own messages only, offered from the bubble's long-press menu.
    @State private var editingMessage: ChatMessage?
    @State private var pendingDeleteMessage: ChatMessage?
    /// A brief inline banner for a failed edit/delete (the optimistic change
    /// already reverted itself — this just tells the member why).
    @State private var actionError: String?
    @State private var actionErrorDismiss: Task<Void, Never>?

    init(conversation: ChatConversation) { _vm = StateObject(wrappedValue: ChatThreadViewModel(conversation: conversation)) }

    private func flashActionError(_ message: String) {
        Haptics.error()
        actionErrorDismiss?.cancel()
        withAnimation { actionError = message }
        actionErrorDismiss = Task {
            try? await Task.sleep(nanoseconds: 3_500_000_000)
            guard !Task.isCancelled else { return }
            withAnimation { actionError = nil }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ThreadHeader(isSpace: vm.isSpace, title: vm.title, subtitle: vm.subtitle,
                         topic: vm.topic, avatarUrl: vm.avatarUrl) { dismiss() }
            content
        }
        .background(Aurora.sectionBg.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.thread == nil { await vm.load() } }
        // A conversation owns the whole bottom edge: slide the tab bar away while
        // this screen is up so the composer sits on the home indicator / keyboard.
        .onAppear { tabs.chromeHidden = true }
        .onDisappear {
            tabs.chromeHidden = false
            // Silence the thread's shared player on the way out — it's
            // process-wide, and once this screen is gone there is no visible
            // control anywhere to stop a note still talking over Home.
            ChatVoicePlayer.threadShared.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
        .sheet(item: $editingMessage) { message in
            EditMessageSheet(message: message) { newBody in
                await vm.editMessage(message.messageId, newBody: newBody)
            }
        }
        // Deleting is irreversible for everyone in the thread — always confirm.
        .confirmationDialog(
            "Delete this message?",
            isPresented: Binding(get: { pendingDeleteMessage != nil },
                                  set: { if !$0 { pendingDeleteMessage = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                guard let message = pendingDeleteMessage else { return }
                pendingDeleteMessage = nil
                Haptics.action()
                Task {
                    let ok = await vm.deleteMessage(message.messageId)
                    if !ok { flashActionError("Couldn't delete this message — try again.") }
                }
            }
            Button("Cancel", role: .cancel) { pendingDeleteMessage = nil }
        } message: {
            Text("This can't be undone.")
        }
    }

    @ViewBuilder private var content: some View {
        if vm.loading && vm.thread == nil {
            ThreadSkeleton()
        } else if let error = vm.error, vm.thread == nil {
            ThreadErrorState(message: error) { Task { await vm.load() } }
        } else {
            // Quick replies + composer live in the scroll's bottom safe-area
            // inset: keyboard avoidance is automatic (the bar floats directly on
            // top of the keyboard while typing), and when the keyboard is closed
            // we pad past RootView's overlaid navy tab bar so both stay visible.
            MessagesList(rows: buildRows(vm.allMessages, multi: vm.isSpace),
                         keyboardVisible: keyboardVisible,
                         onReact: { m, emoji in Task { await vm.react(m, emoji) } },
                         onEdit: { m in editingMessage = m },
                         onDelete: { m in pendingDeleteMessage = m })
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomBar }
        }
    }

    // With the tab bar hidden for the thread, the safe-area inset alone puts the
    // composer on the home indicator and floats it on the keyboard while typing.
    private var bottomBar: some View {
        VStack(spacing: 0) {
            if let actionError {
                Text(actionError)
                    .font(.inter(11.5, .medium)).foregroundStyle(Nuru.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16).padding(.vertical, 7)
                    .background(Nuru.danger.opacity(0.08))
                    .transition(.opacity)
            }
            // The line that makes a member actually answer. Their fear is not
            // the label — it is "is the whole church about to read this?" So the
            // screen says the true thing, plainly, right where they type. It can
            // be said without lying because the thread genuinely is 1:1: no
            // admin, no leader, nobody else can open it.
            if vm.isPastorMail {
                HStack(spacing: 6) {
                    Icon(.lock, size: 11, color: Nuru.goldChipText)
                    Text("Only \(vm.title) sees your reply")
                        .font(.inter(11, .medium)).foregroundStyle(Nuru.goldChipText)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 7)
                .background(Nuru.goldChipBg)
            }
            QuickReplyRow { reply in
                Haptics.action()
                Task { await vm.send(reply) }
            }
            ComposerBar(draft: $vm.draft, sending: vm.sending,
                        myName: auth.profile?.fullName ?? "You",
                        recentMessages: recentForDraft,
                        conversationId: vm.conversation.conversationId,
                        onSend: {
                            Haptics.action()
                            Task { await vm.send() }
                        },
                        onVoiceSent: { Task { await vm.load() } })
        }
        .background(Aurora.sectionBg)
    }

    /// ✨ Nuru drafting context — the last 5 turns as "[Author]: text", with
    /// placeholders standing in for voice/photo/file bodies.
    private var recentForDraft: [(author: String, text: String)] {
        vm.allMessages
            .filter { $0.msgType != "system" }
            .suffix(5)
            .map { m in
                let author = m.mine ? "You" : (m.authorName.isEmpty ? "Member" : m.authorName)
                let text: String
                switch m.msgType {
                case "voice": text = m.body.isEmpty ? "(voice note)" : m.body
                case "image": text = m.body.isEmpty ? "(photo)" : m.body
                case "video", "file": text = m.body.isEmpty ? "(shared a file)" : m.body
                default: text = m.body
                }
                return (author, text)
            }
    }
}

// MARK: - Header (navy chrome, story-ring avatar)

private struct ThreadHeader: View {
    let isSpace: Bool
    let title: String
    let subtitle: String
    let topic: String?
    let avatarUrl: String?
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Nuru.S.md) {
                backButton
                avatar
                titles
                Spacer(minLength: Nuru.S.sm)
                aiButton
            }
            .padding(.horizontal, Nuru.S.base)
            .padding(.top, 54)
            .padding(.bottom, Nuru.S.md)

            if isSpace, let topic { topicStrip(topic) }
        }
        // Cream Figma header — navy-on-light, gold ambient glow, bottom hairline.
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.22)).frame(width: 176, height: 176).blur(radius: 44).offset(x: 40, y: -60)
                }
        )
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private var backButton: some View {
        Button(action: onBack) {
            Icon(.arrowLeft, size: 18, color: Nuru.navy)
                .frame(width: 38, height: 38)
                .background(Color.white, in: Circle())
                .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
    }

    @ViewBuilder private var avatar: some View {
        if isSpace {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: 0x2E7D6B))
                .frame(width: 38, height: 38)
                .overlay(Text("#").font(.inter(18, .bold)).foregroundStyle(.white))
        } else {
            Avatar(url: avatarUrl, name: title, size: 38)
                .padding(2)
                .overlay(Circle().stroke(Aurora.storyRing, lineWidth: 2))
        }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.fraunces(19, .semibold)).kerning(-0.3).foregroundStyle(Nuru.navy).lineLimit(1)
            if isSpace {
                Text(subtitle).font(.inter(11)).foregroundStyle(Color(hex: 0x59667C)).lineLimit(1)
            } else {
                HStack(spacing: 4) {
                    Text("🕊️").font(.system(size: 10))
                    Text(subtitle).font(.fraunces(12, .medium)).italic()
                        .foregroundStyle(Color(hex: 0x9A7A2A))
                    LinearGradient(colors: [Color(hex: 0x9A7A2A).opacity(0.5), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 26, height: 1).padding(.top, 1)
                }
                .lineLimit(1)
            }
        }
    }

    private var aiButton: some View {
        Button { } label: {
            Icon(.sparkles, size: 18, color: Color(hex: 0x9A7A2A))
                .frame(width: 38, height: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.30), lineWidth: 1))
        }
    }

    private func topicStrip(_ topic: String) -> some View {
        HStack(spacing: 6) {
            Icon(.flag, size: 13, color: Color(hex: 0x59667C))
            Text(topic).font(.inter(12)).foregroundStyle(Color(hex: 0x59667C)).lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, Nuru.S.base)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.55))
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }
}

// MARK: - Messages canvas

private struct MessagesList: View {
    let rows: [ThreadRow]
    let keyboardVisible: Bool
    var onReact: (ChatMessage, String) -> Void
    var onEdit: (ChatMessage) -> Void
    var onDelete: (ChatMessage) -> Void

    /// Insert-animations arm only after the first layout, so opening a thread
    /// never plays a whole screen of entrance transitions at once.
    @State private var settled = false
    /// True while the newest message is scrolled well out of view (the lazy
    /// bottom sentinel has left the viewport).
    @State private var awayFromBottom = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let day = rows.first?.daySeparator { DaySeparator(label: day) }
                    ConfidencePill()
                    if rows.isEmpty { EmptyThread() }
                    ForEach(rows) { row in
                        MessageRow(row: row, hideSeparator: row.id == rows.first?.id,
                                   onReact: { emoji in onReact(row.m, emoji) },
                                   onEdit: { onEdit(row.m) },
                                   onDelete: { onDelete(row.m) })
                        .id(row.id)
                        // New bubbles rise in; the rest of the list never replays.
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .bottom)),
                            removal: .opacity))
                    }
                    Color.clear.frame(height: 1).id("bottom")
                        .onAppear { awayFromBottom = false }
                        .onDisappear { awayFromBottom = true }
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.vertical, Nuru.S.screen)
                .animation(settled ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: rows.count)
            }
            .background(Aurora.canvas)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: rows.count) { _, _ in scrollToEnd(proxy) }
            // Keep the latest messages in view when the keyboard slides up.
            .onChange(of: keyboardVisible) { _, visible in
                if visible { scrollToEnd(proxy) }
            }
            .onAppear {
                scrollToEnd(proxy, animated: false)
                DispatchQueue.main.async { settled = true }
            }
            // Floating "back to now" chevron when the reader is far up-thread.
            .overlay(alignment: .bottomTrailing) {
                if awayFromBottom && !rows.isEmpty {
                    JumpToLatestButton {
                        Haptics.tap()
                        scrollToEnd(proxy)
                    }
                    .padding(.trailing, Nuru.S.base)
                    .padding(.bottom, Nuru.S.md)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: awayFromBottom)
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = rows.last else { return }
        if animated { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
    }
}

/// Small white circle-chevron that drops the reader back to the newest message.
private struct JumpToLatestButton: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Icon(.chevronDown, size: 16, color: Aurora.navy)
                .frame(width: 40, height: 40)
                .background(Color.white, in: Circle())
                .overlay(Circle().stroke(Aurora.border, lineWidth: 1))
                .shadow(color: Aurora.shadowInk.opacity(0.22), radius: 8, y: 5)
        }
        .buttonStyle(.pressable)
    }
}

/// Shimmering bubble bones while the thread loads — real bubble geometry on the
/// Aurora canvas, alternating sides, no invented content.
private struct ThreadSkeleton: View {
    var body: some View {
        VStack(spacing: Nuru.S.base) {
            bone(width: 190, mine: false)
            bone(width: 148, mine: true)
            bone(width: 224, mine: false)
            bone(width: 122, mine: true)
        }
        .padding(.horizontal, Nuru.S.base)
        .padding(.vertical, Nuru.S.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Aurora.canvas)
    }

    private func bone(width: CGFloat, mine: Bool) -> some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(mine ? Color(hex: 0x0B1F33, alpha: 0.10) : Color.white.opacity(0.8))
            .frame(width: width, height: 44)
            .nuruShimmer()
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
    }
}

/// "TODAY" between two soft gradient hairlines.
private struct DaySeparator: View {
    let label: String

    var body: some View {
        HStack(spacing: Nuru.S.md) {
            LinearGradient(colors: [.clear, Aurora.hairline], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
            Text(label.uppercased())
                .font(.inter(10, .bold)).tracking(2.2)
                .foregroundStyle(Aurora.dayGold)
                .fixedSize()
            LinearGradient(colors: [Aurora.hairline, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(height: 1)
        }
        .padding(.bottom, Nuru.S.base)
    }
}

/// A gentle confidentiality blessing.
private struct ConfidencePill: View {
    var body: some View {
        Text("🕊️ Held in confidence — speak life here")
            .font(.inter(9, .semibold))
            .foregroundStyle(Aurora.confidence)
            .padding(.horizontal, Nuru.S.md)
            .padding(.vertical, 4)
            .background(Color(hex: 0x0B1F33, alpha: 0.045), in: Capsule())
            .frame(maxWidth: .infinity)
            .padding(.bottom, Nuru.S.base)
    }
}

private struct EmptyThread: View {
    var body: some View {
        VStack(spacing: 6) {
            Icon(.sparkles, size: 18, color: Aurora.gold)
            Text("No messages yet — say hello")
                .font(.inter(10)).foregroundStyle(Aurora.meta)
        }
        .padding(.horizontal, Nuru.S.base)
        .padding(.vertical, Nuru.S.screen)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Aurora.border, lineWidth: 1))
        .padding(.top, Nuru.S.xl)
    }
}

private struct ThreadErrorState: View {
    let message: String
    var onRetry: () -> Void

    var body: some View {
        VStack(spacing: Nuru.S.md) {
            Spacer()
            Text(message)
                .font(.inter(13)).foregroundStyle(Nuru.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Nuru.S.xl)
            Button(action: onRetry) {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, Nuru.S.lg).padding(.vertical, 10)
                    .background(Aurora.storyRing, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Message row (avatar slot + bubble column)

private struct MessageRow: View {
    let row: ThreadRow
    let hideSeparator: Bool
    var onReact: (String) -> Void
    var onEdit: () -> Void
    var onDelete: () -> Void

    private var m: ChatMessage { row.m }
    private var accent: Color {
        m.mine ? Aurora.gold : Aurora.accent(for: m.authorUserId.isEmpty ? m.authorName : m.authorUserId)
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hideSeparator, let day = row.daySeparator { DaySeparator(label: day) }
            HStack(alignment: .bottom, spacing: Nuru.S.sm) {
                if m.mine {
                    Spacer(minLength: 48)
                    column
                } else {
                    avatarSlot
                    column
                    Spacer(minLength: 48)
                }
            }
            .padding(.bottom, row.showTail ? Nuru.S.base : 6)
        }
    }

    /// Width is always reserved so runs stay aligned; the thumb shows on the tail only.
    private var avatarSlot: some View {
        Group {
            if row.showTail { SenderThumb(m: m, accent: accent) }
            else { Color.clear }
        }
        .frame(width: 28, height: 28)
    }

    private var column: some View {
        VStack(alignment: m.mine ? .trailing : .leading, spacing: 6) {
            AuroraBubble(m: m, accent: accent, showAuthor: row.showAuthor,
                         showTail: row.showTail, onReact: onReact,
                         onEdit: onEdit, onDelete: onDelete)
            if m.aiTag == "prayer" && !m.mine { PrayerChip(m: m, onReact: onReact) }
        }
    }
}

/// Small round avatar beside the last message of a run (photo, or accent-tinted initials).
private struct SenderThumb: View {
    let m: ChatMessage
    let accent: Color

    var body: some View {
        Group {
            if let url = m.authorAvatar, !url.isEmpty {
                Avatar(url: url, name: m.authorName, size: 28)
            } else {
                Circle()
                    .fill(LinearGradient(colors: [accent, accent.opacity(0.71)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                    .overlay(Text(Avatar.initials(m.authorName))
                        .font(.inter(9, .bold)).foregroundStyle(.white))
            }
        }
        .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}

// MARK: - Bubble

private struct AuroraBubble: View {
    let m: ChatMessage
    let accent: Color
    let showAuthor: Bool
    let showTail: Bool
    var onReact: (String) -> Void
    var onEdit: () -> Void = {}
    var onDelete: () -> Void = {}

    /// A message the room has rallied around gets a soft golden glow.
    private var celebrated: Bool { m.reactions.reduce(0) { $0 + $1.count } >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showAuthor { authorLine }
            if let replyBody = m.replyBody { QuotedReply(author: m.replyAuthor, text: replyBody, dark: m.mine) }
            contentView
            BubbleFooter(m: m, onReact: onReact)
        }
        .padding(.horizontal, Nuru.S.base)
        .padding(.vertical, Nuru.S.md)
        // Your own messages ride the navy ink card; incoming stays light Aurora.
        .background(m.mine ? AnyShapeStyle(Aurora.inkBubble) : AnyShapeStyle(Aurora.bubble), in: shape)
        .overlay(shape.stroke(celebrated ? Aurora.gold.opacity(0.33)
                              : (m.mine ? Color.white.opacity(0.08) : Aurora.bubbleBorder), lineWidth: 1))
        .shadow(color: Aurora.shadowInk.opacity(m.mine ? 0.35 : 0.16), radius: 6, x: 0, y: 5)
        .shadow(color: celebrated ? Aurora.gold.opacity(0.35) : .clear, radius: 10, x: 0, y: 7)
        .onTapGesture(count: 2) {
            Haptics.love()
            onReact("❤️")
        }
        .contextMenu { menu }
    }

    /// Floating bubble, no tails — the tail-side bottom corner squares to 8 on the run's last message.
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 22,
            bottomLeadingRadius: (!m.mine && showTail) ? 8 : 22,
            bottomTrailingRadius: (m.mine && showTail) ? 8 : 22,
            topTrailingRadius: 22,
            style: .continuous)
    }

    private var authorLine: some View {
        HStack(spacing: 6) {
            Circle().fill(accent).frame(width: 6, height: 6)
            Text(m.authorName).font(.inter(11.5, .bold)).foregroundStyle(accent)
        }
    }

    @ViewBuilder private var contentView: some View {
        switch m.msgType {
        case "image":
            BubbleImage(m: m, onReact: onReact)
        case "voice":
            VoiceMessageBubble(message: m, player: ChatVoicePlayer.threadShared, onDark: m.mine)
        default:
            mentionText(m.body)
                .font(.inter(13))
                .foregroundStyle(m.mine ? Color.white : Aurora.textDark)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var menu: some View {
        ForEach(["🙏", "❤️", "🔥", "🎉", "👍"], id: \.self) { emoji in
            Button(emoji) {
                Haptics.love()
                onReact(emoji)
            }
        }
        if !m.body.isEmpty {
            Divider()
            Button { UIPasteboard.general.string = m.body } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
        // Author-only — never offered on someone else's message, a system row,
        // or a broadcast copy the member didn't write themselves.
        if m.mine {
            Divider()
            if m.msgType != "voice" && m.msgType != "image" {
                Button {
                    Haptics.tap()
                    onEdit()
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
            }
            Button(role: .destructive) {
                Haptics.tap()
                onDelete()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Quoted reply on a faint wash, tinted by the quoted author's accent.
/// `dark` = rendered inside the navy outgoing bubble.
private struct QuotedReply: View {
    let author: String?
    let text: String
    var dark = false

    private var accent: Color {
        guard let author, !author.isEmpty else { return Aurora.gold }
        return author == "You" ? Aurora.gold : Aurora.accent(for: author)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(dark ? Aurora.gold : accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if let author, !author.isEmpty {
                    Text(author).font(.inter(11, .bold)).foregroundStyle(dark ? Aurora.gold : accent)
                }
                Text(text).font(.inter(11))
                    .foregroundStyle(dark ? Color.white.opacity(0.75) : Aurora.quoteBody).lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(dark ? Color.white.opacity(0.10) : Aurora.quoteBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BubbleImage: View {
    let m: ChatMessage
    var onReact: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageView
            if !m.body.isEmpty {
                mentionText(m.body)
                    .font(.inter(13)).foregroundStyle(m.mine ? Color.white : Aurora.textDark)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// WhatsApp-style thumb: rendered at the image's own aspect (width ≤ 240,
    /// aspect clamped 0.5…2.0), tap → full-screen lightbox. The double-tap ❤️
    /// is re-declared on the thumb itself so it keeps working over the image
    /// (the bubble-level recognizer can't see through the thumb's single tap).
    @ViewBuilder private var imageView: some View {
        if let url = m.attachmentUrl, let u = URL(string: url) {
            NaturalImageThumb(url: u, maxWidth: 240, maxHeight: 480,
                              onDoubleTap: {
                                  Haptics.love()
                                  onReact("❤️")
                              })
        } else {
            placeholder
                .frame(width: 200, height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var placeholder: some View {
        Rectangle().fill(Aurora.quoteBg)
            .overlay(Icon(.image, size: 28, color: Aurora.meta))
    }
}



/// In-bubble footer: reaction chips left, edited · time · read ticks right.
private struct BubbleFooter: View {
    let m: ChatMessage
    var onReact: (String) -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: Nuru.S.sm) {
            if !m.reactions.isEmpty {
                reactionChips
                Spacer(minLength: Nuru.S.sm)
            }
            meta
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    /// Inside the navy outgoing card, the footer furniture flips to light inks.
    private var dark: Bool { m.mine }

    private var reactionChips: some View {
        HStack(spacing: 4) {
            ForEach(m.reactions, id: \.emoji) { r in
                ReactionChip(r: r, dark: dark) { onReact(r.emoji) }
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 4) {
            if m.isEdited {
                Text("edited").font(.inter(9)).italic()
                    .foregroundStyle(dark ? Color.white.opacity(0.55) : Aurora.meta)
            }
            Text(timeShort(m.createdAt)).font(.inter(10))
                .foregroundStyle(dark ? Color.white.opacity(0.6) : Aurora.meta)
            if m.mine { ReadTicksView(read: (m.readCount ?? 0) > 0, dark: dark) }
        }
    }
}

private struct ReactionChip: View {
    let r: ChatReaction
    var dark = false
    var onTap: () -> Void

    var body: some View {
        Button {
            Haptics.tap()
            onTap()
        } label: {
            HStack(spacing: 2) {
                Text(r.emoji).font(.system(size: 11))
                Text("\(r.count)").font(.inter(9.5, .bold))
                    .foregroundStyle(dark ? Color.white : Aurora.navy)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(r.mine ? Aurora.gold.opacity(dark ? 0.28 : 0.14)
                        : (dark ? Color.white.opacity(0.12) : Aurora.chipBg), in: Capsule())
            .overlay(Capsule().stroke(r.mine ? Aurora.gold.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ReadTicksView: View {
    let read: Bool
    var dark = false

    var body: some View {
        Text("✓✓")
            .font(.inter(9.5, .semibold))
            .kerning(-1)
            .foregroundStyle(read ? Aurora.gold : (dark ? Color.white.opacity(0.55) : Aurora.meta))
    }
}

/// Amen affordance under prayer requests — toggles a real 🙏 reaction.
private struct PrayerChip: View {
    let m: ChatMessage
    var onReact: (String) -> Void

    private var pray: ChatReaction? { m.reactions.first { $0.emoji == "🙏" } }

    var body: some View {
        let mine = pray?.mine ?? false
        Button {
            Haptics.love()
            onReact("🙏")
        } label: {
            Text(label(mine: mine))
                .font(.inter(11, .bold))
                .foregroundStyle(mine ? Aurora.goldDeep : Aurora.navy)
                .padding(.horizontal, Nuru.S.md)
                .padding(.vertical, 6)
                .background(mine ? Aurora.gold.opacity(0.12) : Color.white, in: Capsule())
                .overlay(Capsule().stroke(mine ? Aurora.gold.opacity(0.5) : Aurora.border, lineWidth: 1))
                .shadow(color: mine ? .clear : Aurora.shadowInk.opacity(0.15), radius: 5, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
    }

    private func label(mine: Bool) -> String {
        let base = mine ? "🙏 Praying" : "🙏 I'm praying"
        let count = pray?.count ?? 0
        return count > 0 ? "\(base) · \(count)" : base
    }
}

// MARK: - Quick replies

private struct QuickReplyRow: View {
    var onSend: (String) -> Void

    private let replies = ["Amen 🙏", "Praying for you 💛", "On my way 🚶", "Thank you 🤍"]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(replies, id: \.self) { reply in chip(reply) }
            }
            .padding(.horizontal, Nuru.S.base)
            .padding(.vertical, Nuru.S.sm)
        }
    }

    private func chip(_ reply: String) -> some View {
        Button { onSend(reply) } label: {
            Text(reply)
                .font(.inter(12.5, .medium))
                .foregroundStyle(Aurora.navy)
                .padding(.horizontal, 14)
                .padding(.vertical, Nuru.S.sm)
                .background(Color.white.opacity(0.9), in: Capsule())
                .overlay(Capsule().stroke(Aurora.border, lineWidth: 1))
                .shadow(color: Aurora.shadowInk.opacity(0.16), radius: 4, x: 0, y: 4)
        }
        .buttonStyle(.pressable)
    }
}

// MARK: - Composer

private struct ComposerBar: View {
    @Binding var draft: String
    let sending: Bool
    let myName: String
    let recentMessages: [(author: String, text: String)]
    let conversationId: String
    var onSend: () -> Void
    var onVoiceSent: () -> Void = {}

    @StateObject private var recorder = ChatVoiceRecorder()
    @State private var sendingVoice = false
    @State private var voiceSendFailed = false
    @State private var micHint = false
    @State private var micHintDismiss: Task<Void, Never>?

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// The strip owns the bar while capturing, after an autostop (the take is
    /// finished and waiting), mid-upload, and after a failed send (retry).
    private var stripUp: Bool {
        recorder.isRecording || recorder.finishedFile != nil || sendingVoice || voiceSendFailed
    }

    var body: some View {
        VStack(spacing: 0) {
            if micHint {
                Text("Allow microphone in Settings to send voice messages.")
                    .font(.inter(11.5)).foregroundStyle(Aurora.meta)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 8)
                    .transition(.opacity)
                    .onTapGesture { withAnimation { micHint = false } }
            }
            HStack(alignment: .bottom, spacing: Nuru.S.sm) {
                if stripUp {
                    recordingStrip
                } else {
                    myAvatar
                    inputPill
                    sendOrMic
                }
            }
        }
        .padding(.horizontal, Nuru.S.md)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(Rectangle().fill(Aurora.border).frame(height: 1), alignment: .top)
        .onDisappear { recorder.cancel() }
        // Mic denied → a brief hint (~4 s, or the next tap) instead of a dead button.
        .onChange(of: recorder.denied) { _, denied in
            guard denied else { return }
            recorder.denied = false
            withAnimation { micHint = true }
            micHintDismiss?.cancel()
            micHintDismiss = Task {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { return }
                withAnimation { micHint = false }
            }
        }
    }

    /// While capturing: pulsing red dot · live wave · clock · cancel · send.
    /// After the 5-minute cap (or a call/Siri) the strip stays — wave frozen,
    /// clock stopped, send live — and a failed send flips it to tap-to-retry.
    private var recordingStrip: some View {
        HStack(spacing: 12) {
            Button {
                Haptics.tap()
                recorder.cancel()
                voiceSendFailed = false
            } label: {
                Icon(.x, size: 17, color: Aurora.meta)
                    .frame(width: 36, height: 36)
                    .background(Nuru.paper, in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(sendingVoice)
            if recorder.isRecording {
                RecordingDot()
            } else {
                Circle().fill(voiceSendFailed ? Color(hex: 0xE0342C) : Aurora.gold)
                    .frame(width: 10, height: 10)
            }
            if voiceSendFailed {
                Text("Couldn't send — tap to retry")
                    .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0xE0342C))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LiveWaveView(levels: recorder.levels, tint: Aurora.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(String(format: "%d:%02d", recorder.elapsedSec / 60, recorder.elapsedSec % 60))
                .font(.inter(12, .semibold)).monospacedDigit().foregroundStyle(Aurora.navy)
            Button { sendVoice() } label: {
                if sendingVoice {
                    ProgressView().tint(.white)
                        .frame(width: 44, height: 44)
                        .background(AnyShapeStyle(Aurora.storyRing), in: Circle())
                } else {
                    Icon(.send, size: 18, color: .white)
                        .frame(width: 44, height: 44)
                        .background(AnyShapeStyle(Aurora.storyRing), in: Circle())
                        .shadow(color: Aurora.gold.opacity(0.5), radius: 6, x: 0, y: 5)
                }
            }
            .buttonStyle(.pressable)
            .disabled(sendingVoice)
        }
        .frame(minHeight: 44)
    }

    private func sendVoice() {
        guard !sendingVoice else { return }
        Haptics.action()
        let waveform = recorder.waveformFor()
        guard let file = recorder.stop() else { return }
        // Duration after stop(): stop() finalizes it from the recorder's clock.
        let duration = max(1, recorder.elapsedSec)
        // Read the bytes NOW (≤ ~2.4 MB, local disk): onDisappear's cancel()
        // deletes the tmp file, and a deferred read inside the Task could lose
        // that race and silently drop the message.
        guard let data = try? Data(contentsOf: file) else {
            voiceSendFailed = true
            return
        }
        voiceSendFailed = false
        sendingVoice = true
        Task {
            defer { sendingVoice = false }
            do {
                let url = try await MemberAPI.uploadVoiceAudio(m4a: data, filename: "chat-voice.m4a")
                try await MemberAPI.sendChatVoice(conversationId, audioUrl: url, durationSec: duration, waveform: waveform)
                Haptics.success()
                recorder.discardFile()   // the send landed — the tmp copy can go
                onVoiceSent()
            } catch {
                // Keep the take: the strip stays up with a retry until the
                // member sends it or cancels it themselves.
                Haptics.tap()
                voiceSendFailed = true
            }
        }
    }

    private var myAvatar: some View {
        Circle().fill(Aurora.inkBubble)
            .frame(width: 36, height: 36)
            .overlay(Text(Avatar.initials(myName)).font(.inter(10, .bold)).foregroundStyle(.white))
            .overlay(Circle().stroke(.white, lineWidth: 2))
            .shadow(color: Aurora.shadowInk.opacity(0.30), radius: 5, x: 0, y: 4)
            .padding(.bottom, 2)
    }

    private var inputPill: some View {
        HStack(alignment: .bottom, spacing: Nuru.S.sm) {
            Icon(.plus, size: 19, color: Aurora.meta).padding(.bottom, 9)
            TextField("Message", text: $draft, axis: .vertical)
                .font(.inter(12))
                .foregroundStyle(Aurora.navy)
                .lineLimit(1...6)
                .padding(.vertical, 8)
            // ✨ Nuru drafting — summarizes the last messages and proposes an
            // editable reply; "Use draft" only fills the composer (member sends).
            AiDraftButton(recentMessages: recentMessages, conversationId: conversationId) { text in
                draft = text
            }
            .padding(.bottom, 5)
            Icon(.smile, size: 19, color: Aurora.meta).padding(.bottom, 9)
        }
        .padding(.horizontal, Nuru.S.md)
        .background(Nuru.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Aurora.border, lineWidth: 1))
    }

    /// Gold story-ring send when there's a draft; hold-free tap-to-record mic
    /// otherwise (Android parity — was a dead placeholder).
    private var sendOrMic: some View {
        Button {
            if hasDraft { onSend() } else { Haptics.action(); micHint = false; recorder.start() }
        } label: {
            Icon(hasDraft ? .send : .mic, size: 18, color: .white)
                .frame(width: 44, height: 44)
                .background(hasDraft ? AnyShapeStyle(Aurora.storyRing) : AnyShapeStyle(Aurora.inkBubble), in: Circle())
                .shadow(color: hasDraft ? Aurora.gold.opacity(0.5) : Aurora.shadowInk.opacity(0.4), radius: 6, x: 0, y: 5)
        }
        .buttonStyle(.pressable)
        .disabled(sending)
        .opacity(sending ? 0.6 : 1)
        // Mic ↔ gold send swap eases instead of snapping per keystroke.
        .animation(.easeInOut(duration: 0.18), value: hasDraft)
    }
}


// MARK: - Edit message (own text messages only)

/// Small sheet, prefilled with the current body — PATCH /chat/messages/{id}.
/// `onSave` returns whether the server accepted it; a `false` keeps the sheet
/// open with an inline error instead of dismissing on a change that didn't land.
private struct EditMessageSheet: View {
    let message: ChatMessage
    var onSave: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text: String
    @State private var saving = false
    @State private var error: String?

    init(message: ChatMessage, onSave: @escaping (String) async -> Bool) {
        self.message = message
        self.onSave = onSave
        _text = State(initialValue: message.body)
    }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        PSheetShell(title: "Edit message") {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                TextField("Message", text: $text, axis: .vertical)
                    .font(.inter(14)).foregroundStyle(Nuru.navy)
                    .lineLimit(3...8)
                    .padding(.horizontal, Nuru.S.base).padding(.vertical, 12)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))

                if let error {
                    Text(error).font(.inter(12)).foregroundStyle(Nuru.danger)
                }

                GoldSheetButton(title: "Save", busy: saving, disabled: trimmed.isEmpty) {
                    Task { await save() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() async {
        guard !trimmed.isEmpty else { return }
        // Nothing actually changed — no need to round-trip the server.
        if trimmed == message.body { dismiss(); return }
        saving = true; error = nil
        defer { saving = false }
        let ok = await onSave(trimmed)
        if ok {
            Haptics.success()
            dismiss()
        } else {
            Haptics.error()
            error = "Couldn't save — please try again."
        }
    }
}

/// The classic recording pulse — a red dot breathing at ~1 Hz.
private struct RecordingDot: View {
    @State private var on = false
    var body: some View {
        Circle().fill(Color(hex: 0xE0342C))
            .frame(width: 10, height: 10)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}
