// Chat thread — native port of the Figma "Aurora" ChatThread presentation:
// a warm #E9E6DF canvas with floating light bubbles (no tails), per-sender
// accent colors (stable hash → palette, gold for self), quoted replies on a
// faint navy wash with an accent bar, in-bubble reaction chips + read ticks,
// gradient-hairline day separators, quick replies, and the cream composer
// (plus · message · gold sparkle · smile · navy mic / gold send).
// All data is real (MemberAPI). The make's voice recorder, attachment and
// emoji pickers are mock-only and deliberately not reproduced here.
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

    /// Optimistic messages queued locally until the server echoes them back.
    @Published var pending: [ChatMessage] = []

    /// Server thread + any still-in-flight optimistic sends (deduped by id).
    var allMessages: [ChatMessage] {
        let base = thread?.messages ?? []
        let ids = Set(base.map(\.messageId))
        return base + pending.filter { !ids.contains($0.messageId) }
    }

    /// Offline-capable send: the bubble appears instantly and the write goes through
    /// the durable queue as `chat_messages:create` (idempotent on message_id).
    func send(_ text: String? = nil) async {
        let body = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !sending else { return }
        sending = true; defer { sending = false }
        let mid = UUID().uuidString
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
            let landed = Set((thread?.messages ?? []).map(\.messageId))
            pending.removeAll { landed.contains($0.messageId) }
        }
    }

    func react(_ m: ChatMessage, _ emoji: String) async {
        do { _ = try await MemberAPI.toggleChatReaction(m.messageId, emoji: emoji); await load() } catch {}
    }
}

// MARK: - Aurora palette (Figma ChatThread.tsx constants)

private enum Aurora {
    static let canvas       = Color(hex: 0xE9E6DF)              // CHAT_BG
    static let bubble       = Color(hex: 0xF3F4F3)              // SENDER_BUBBLE / ME_BUBBLE
    static let textDark     = Color(hex: 0x17283D)              // body on light bubbles
    static let meta         = Color(hex: 0x9AA3AF)              // timestamps / ticks
    static let quoteBg      = Color(hex: 0x0B1F33, alpha: 0.05) // QUOTE_BG
    static let quoteBody    = Color(hex: 0x6B7280)
    static let bubbleBorder = Color(hex: 0x0B1F33, alpha: 0.07) // BUBBLE_BORDER
    static let border       = Color(hex: 0x0B1F33, alpha: 0.08) // BORDER
    static let chipBg       = Color(hex: 0x0B1F33, alpha: 0.06) // non-mine reaction chip
    static let hairline     = Color(hex: 0x0B1F33, alpha: 0.12) // day-separator line
    static let shadowInk    = Color(hex: 0x0B1F33)              // SOFT_SHADOW base
    static let navy         = Color(hex: 0x0A1628)              // NAVY
    static let gold         = Color(hex: 0xC89B3C)              // GOLD (= self accent)
    static let goldDeep     = Color(hex: 0xA8761A)              // gold text on light
    static let dayGold      = Color(hex: 0xA8861C)              // day-chip label
    static let confidence   = Color(hex: 0x8A93A0)

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
    @Environment(\.dismiss) private var dismiss

    init(conversation: ChatConversation) { _vm = StateObject(wrappedValue: ChatThreadViewModel(conversation: conversation)) }

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
    }

    @ViewBuilder private var content: some View {
        if vm.loading && vm.thread == nil {
            Spacer(); ProgressView().tint(Nuru.gold); Spacer()
        } else if let error = vm.error, vm.thread == nil {
            ThreadErrorState(message: error) { Task { await vm.load() } }
        } else {
            MessagesList(rows: buildRows(vm.allMessages, multi: vm.isSpace)) { m, emoji in
                Task { await vm.react(m, emoji) }
            }
            QuickReplyRow { reply in Task { await vm.send(reply) } }
            ComposerBar(draft: $vm.draft, sending: vm.sending,
                        myName: auth.profile?.fullName ?? "You") { Task { await vm.send() } }
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
        }
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
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.fraunces(17, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
            Text(subtitle).font(.inter(11)).foregroundStyle(Color(hex: 0x68758A)).lineLimit(1)
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
            Icon(.flag, size: 13, color: Color(hex: 0x68758A))
            Text(topic).font(.inter(12)).foregroundStyle(Color(hex: 0x68758A)).lineLimit(1)
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
    var onReact: (ChatMessage, String) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if let day = rows.first?.daySeparator { DaySeparator(label: day) }
                    ConfidencePill()
                    if rows.isEmpty { EmptyThread() }
                    ForEach(rows) { row in
                        MessageRow(row: row, hideSeparator: row.id == rows.first?.id) { emoji in
                            onReact(row.m, emoji)
                        }
                        .id(row.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.vertical, Nuru.S.screen)
            }
            .background(Aurora.canvas)
            .onChange(of: rows.count) { _, _ in scrollToEnd(proxy) }
            .onAppear { scrollToEnd(proxy, animated: false) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard let last = rows.last else { return }
        if animated { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
        else { proxy.scrollTo("bottom", anchor: .bottom) }
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
                         showTail: row.showTail, onReact: onReact)
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

    /// A message the room has rallied around gets a soft golden glow.
    private var celebrated: Bool { m.reactions.reduce(0) { $0 + $1.count } >= 8 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if showAuthor { authorLine }
            if let replyBody = m.replyBody { QuotedReply(author: m.replyAuthor, text: replyBody) }
            contentView
            BubbleFooter(m: m, onReact: onReact)
        }
        .padding(.horizontal, Nuru.S.base)
        .padding(.vertical, Nuru.S.md)
        .background(Aurora.bubble, in: shape)
        .overlay(shape.stroke(celebrated ? Aurora.gold.opacity(0.33) : Aurora.bubbleBorder, lineWidth: 1))
        .shadow(color: Aurora.shadowInk.opacity(0.16), radius: 6, x: 0, y: 5)
        .shadow(color: celebrated ? Aurora.gold.opacity(0.35) : .clear, radius: 10, x: 0, y: 7)
        .onTapGesture(count: 2) { onReact("❤️") }
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
            BubbleImage(m: m)
        case "voice":
            VoicePill()
        default:
            mentionText(m.body)
                .font(.inter(13))
                .foregroundStyle(Aurora.textDark)
                .lineSpacing(2.5)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var menu: some View {
        ForEach(["🙏", "❤️", "🔥", "🎉", "👍"], id: \.self) { emoji in
            Button(emoji) { onReact(emoji) }
        }
        if !m.body.isEmpty {
            Divider()
            Button { UIPasteboard.general.string = m.body } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
        }
    }
}

/// Quoted reply on a faint navy wash, tinted by the quoted author's accent.
private struct QuotedReply: View {
    let author: String?
    let text: String

    private var accent: Color {
        guard let author, !author.isEmpty else { return Aurora.gold }
        return author == "You" ? Aurora.gold : Aurora.accent(for: author)
    }

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                if let author, !author.isEmpty {
                    Text(author).font(.inter(11, .bold)).foregroundStyle(accent)
                }
                Text(text).font(.inter(11)).foregroundStyle(Aurora.quoteBody).lineLimit(2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(Aurora.quoteBg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct BubbleImage: View {
    let m: ChatMessage

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            imageView
            if !m.body.isEmpty {
                mentionText(m.body)
                    .font(.inter(13)).foregroundStyle(Aurora.textDark)
                    .lineSpacing(2.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var imageView: some View {
        if let url = m.attachmentUrl, let u = URL(string: url) {
            CachedAsyncImage(url: u) { phase in
                if let img = phase.image { img.resizable().scaledToFill() }
                else if phase.error != nil { placeholder }
                else { ZStack { placeholder; ProgressView().tint(Nuru.gold) } }
            }
            .frame(maxWidth: 240, maxHeight: 220)
            .frame(minHeight: 160)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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

private struct VoicePill: View {
    var body: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.audioLines, size: 16, color: Aurora.gold)
            Text("Voice note").font(.inter(14, .medium)).foregroundStyle(Aurora.textDark)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Aurora.gold.opacity(0.12), in: Capsule())
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

    private var reactionChips: some View {
        HStack(spacing: 4) {
            ForEach(m.reactions, id: \.emoji) { r in
                ReactionChip(r: r) { onReact(r.emoji) }
            }
        }
    }

    private var meta: some View {
        HStack(spacing: 4) {
            if m.isEdited {
                Text("edited").font(.inter(9)).italic().foregroundStyle(Aurora.meta)
            }
            Text(timeShort(m.createdAt)).font(.inter(10)).foregroundStyle(Aurora.meta)
            if m.mine { ReadTicksView(read: (m.readCount ?? 0) > 0) }
        }
    }
}

private struct ReactionChip: View {
    let r: ChatReaction
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 2) {
                Text(r.emoji).font(.system(size: 11))
                Text("\(r.count)").font(.inter(9.5, .bold)).foregroundStyle(Aurora.navy)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(r.mine ? Aurora.gold.opacity(0.14) : Aurora.chipBg, in: Capsule())
            .overlay(Capsule().stroke(r.mine ? Aurora.gold.opacity(0.4) : .clear, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct ReadTicksView: View {
    let read: Bool

    var body: some View {
        Text("✓✓")
            .font(.inter(9.5, .semibold))
            .kerning(-1)
            .foregroundStyle(read ? Aurora.gold : Aurora.meta)
    }
}

/// Amen affordance under prayer requests — toggles a real 🙏 reaction.
private struct PrayerChip: View {
    let m: ChatMessage
    var onReact: (String) -> Void

    private var pray: ChatReaction? { m.reactions.first { $0.emoji == "🙏" } }

    var body: some View {
        let mine = pray?.mine ?? false
        Button { onReact("🙏") } label: {
            Text(label(mine: mine))
                .font(.inter(11, .bold))
                .foregroundStyle(mine ? Aurora.goldDeep : Aurora.navy)
                .padding(.horizontal, Nuru.S.md)
                .padding(.vertical, 6)
                .background(mine ? Aurora.gold.opacity(0.12) : Color.white, in: Capsule())
                .overlay(Capsule().stroke(mine ? Aurora.gold.opacity(0.5) : Aurora.border, lineWidth: 1))
                .shadow(color: mine ? .clear : Aurora.shadowInk.opacity(0.15), radius: 5, x: 0, y: 4)
        }
        .buttonStyle(.plain)
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
        .buttonStyle(.plain)
    }
}

// MARK: - Composer

private struct ComposerBar: View {
    @Binding var draft: String
    let sending: Bool
    let myName: String
    var onSend: () -> Void

    private var hasDraft: Bool { !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        HStack(alignment: .bottom, spacing: Nuru.S.sm) {
            myAvatar
            inputPill
            sendOrMic
        }
        .padding(.horizontal, Nuru.S.md)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(Color.white.opacity(0.92))
        .overlay(Rectangle().fill(Aurora.border).frame(height: 1), alignment: .top)
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
            sparkleChip.padding(.bottom, 5)
            Icon(.smile, size: 19, color: Aurora.meta).padding(.bottom, 9)
        }
        .padding(.horizontal, Nuru.S.md)
        .background(Nuru.paper, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Aurora.border, lineWidth: 1))
    }

    /// Nuru AI assist — decorative parity with the make (drafting is mock-only there).
    private var sparkleChip: some View {
        Circle().fill(Aurora.gold.opacity(0.10))
            .frame(width: 28, height: 28)
            .overlay(Icon(.sparkles, size: 15, color: Aurora.gold))
    }

    /// Gold story-ring send when there's a draft; navy ink mic placeholder otherwise.
    private var sendOrMic: some View {
        Button { if hasDraft { onSend() } } label: {
            Icon(hasDraft ? .send : .mic, size: 18, color: .white)
                .frame(width: 44, height: 44)
                .background(hasDraft ? AnyShapeStyle(Aurora.storyRing) : AnyShapeStyle(Aurora.inkBubble), in: Circle())
                .shadow(color: hasDraft ? Aurora.gold.opacity(0.5) : Aurora.shadowInk.opacity(0.4), radius: 6, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .opacity(sending ? 0.6 : 1)
    }
}
