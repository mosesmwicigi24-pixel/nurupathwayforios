// Nuru Live — the VIEWER-side floating chat overlay (owner's exact vision,
// 2026-07-31 viewer redesign). REPLACES the modal `LiveChatSheet` on the
// viewer player only: anchored bottom-left, translucent dark material,
// roughly 2/3 screen width and the lower 1/3 of the screen, showing the last
// ~6 messages (gold sender name, white body) with a soft top fade and
// auto-scroll, plus its own translucent composer pill. 💬 in
// `LiveViewerPlayerView`'s rail toggles visibility (opacity/hit-testing only
// — this stays MOUNTED and polling the whole time the player is live, so
// toggling it off and back on never loses the conversation or restarts the
// 3s poll).
//
// The BROADCASTER side is untouched: GoLiveBroadcastView still presents the
// modal `LiveChatSheet.swift` exactly as it did before this pass — that file
// is not modified here.
import SwiftUI

/// Owns the same 3s since-cursor poll `LiveChatSheet` uses, factored out so
/// the floating overlay can keep it running independent of the card's own
/// visibility toggle.
@MainActor
final class LiveFloatingChatController: ObservableObject {
    @Published private(set) var messages: [LiveChatMessage] = []
    @Published private(set) var loading = true
    @Published var draft = ""
    @Published private(set) var sending = false

    /// Only the trailing window is ever RENDERED (owner spec: "last ~6
    /// messages") — the full session history is kept here regardless, so a
    /// future scroll-back affordance wouldn't need to change this layer.
    static let visibleWindow = 6
    private static let maxLength = 500

    private let streamId: String
    private var cursor: String?
    private var pollTask: Task<Void, Never>?

    init(streamId: String) { self.streamId = streamId }

    func start() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.loadInitial()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                guard !Task.isCancelled else { return }
                await self.pollNew()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func clampDraft() {
        if draft.count > Self.maxLength { draft = String(draft.prefix(Self.maxLength)) }
    }

    func send() async {
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
}

struct LiveFloatingChatOverlay: View {
    let streamId: String
    let myUserId: String?
    /// `pulse.hands.count` — a small "✋ N" chip so a viewer can see hands are
    /// up even without opening the broadcaster-only hands sheet (which
    /// viewers don't have access to at all).
    let handsRaisedCount: Int
    @Binding var visible: Bool

    @StateObject private var chat: LiveFloatingChatController
    @FocusState private var composerFocused: Bool

    init(streamId: String, myUserId: String?, handsRaisedCount: Int, visible: Binding<Bool>) {
        self.streamId = streamId
        self.myUserId = myUserId
        self.handsRaisedCount = handsRaisedCount
        _visible = visible
        _chat = StateObject(wrappedValue: LiveFloatingChatController(streamId: streamId))
    }

    private var recent: [LiveChatMessage] {
        Array(chat.messages.suffix(LiveFloatingChatController.visibleWindow))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if handsRaisedCount > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "hand.raised.fill").font(.system(size: 9, weight: .semibold))
                    Text("\(handsRaisedCount) hand\(handsRaisedCount == 1 ? "" : "s") raised")
                        .font(.inter(10, .semibold))
                }
                .foregroundStyle(Nuru.navy)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Nuru.gold, in: Capsule())
            }
            messageColumn
            composerPill
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        // Forces the material to render as its DARK variant regardless of
        // system appearance — this is a video-overlay chrome element, not a
        // themed app surface, and it must read the same in light or dark
        // mode (same call `preferredColorScheme(.dark)` makes for the whole
        // player one level up).
        .environment(\.colorScheme, .dark)
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .task { chat.start() }
        .onDisappear { chat.stop() }
    }

    // MARK: Message list — last ~6, gold name + white body, soft top fade,
    // auto-scrolls to the newest as messages arrive.

    private var messageColumn: some View {
        ScrollViewReader { proxy in
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    if chat.loading && chat.messages.isEmpty {
                        ProgressView().tint(.white).padding(.vertical, 6)
                    } else if recent.isEmpty {
                        Text("Say something — chat is open")
                            .font(.inter(11)).foregroundStyle(.white.opacity(0.55))
                    } else {
                        ForEach(recent) { m in
                            bubble(m).id(m.messageId)
                        }
                    }
                }
                .padding(.top, 14)   // room for the top fade below to sit over content, not blank space
            }
            .onChange(of: chat.messages.count) { _, _ in
                guard let last = recent.last else { return }
                withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.messageId, anchor: .bottom) }
            }
        }
        .frame(maxHeight: .infinity)
        .overlay(alignment: .top) {
            // Decorative top fade-out — messages appear to dissolve into the
            // card's own material rather than hard-clipping at the edge.
            LinearGradient(colors: [Color.black.opacity(0.5), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 22)
                .allowsHitTesting(false)
        }
    }

    private func bubble(_ m: LiveChatMessage) -> some View {
        (Text(m.fullName + "  ").font(.inter(12, .bold)).foregroundStyle(Nuru.gold)
         + Text(m.body).font(.inter(12.5)).foregroundStyle(.white))
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(4)
    }

    // MARK: Composer — translucent input pill + send button

    private var composerPill: some View {
        HStack(spacing: 8) {
            TextField("Say something…", text: $chat.draft)
                .font(.inter(13)).foregroundStyle(.white)
                .tint(.white)
                .focused($composerFocused)
                .onChange(of: chat.draft) { _, _ in chat.clampDraft() }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.white.opacity(0.14), in: Capsule())
                .onSubmit { Task { await chat.send() } }
            Button {
                Haptics.tap()
                Task { await chat.send() }
            } label: {
                Icon(.send, size: 13, color: .white)
                    .frame(width: 32, height: 32)
                    .background(canSend ? Nuru.gold : Color.white.opacity(0.16), in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(!canSend || chat.sending)
        }
    }

    private var canSend: Bool {
        !chat.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
