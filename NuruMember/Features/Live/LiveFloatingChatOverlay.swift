// Nuru Live — the shared floating chat overlay (2026-07-31 viewer redesign;
// taste pass same day made it draggable/collapsible and extended it to the
// BROADCASTER screen too). REPLACES the modal `LiveChatSheet` on BOTH the
// viewer player and the broadcast screen (`GoLiveBroadcastView`) — chat is
// never a sheet that eats the whole stage anymore, just a small floating
// card. `LiveChatSheet.swift` itself is left in place (unreferenced) rather
// than deleted, in case a future surface still wants a full-screen thread.
//
// TASTE PASS additions (owner feedback: "not movable, occupies too much
// space"):
//   - Draggable from its own header (or the bubble itself when collapsed) —
//     `DragGesture(minimumDistance:)` so a plain tap on the header's ✕/⌄
//     controls, or the bubble, still registers as a tap rather than being
//     eaten by the gesture.
//   - Smaller default footprint: ~55% width × ~26% height (was 66%/32%).
//   - A collapse control shrinks the whole thing to a single round chat
//     bubble (also draggable) — tapping the bubble re-expands the card.
//   - Position is REMEMBERED FOR THE SESSION: `settledOffset` is plain
//     `@State`, so it survives the 💬 visibility toggle and the
//     expand/collapse round-trip (the view stays mounted for as long as the
//     player screen itself is open) — but a fresh stream gets a fresh view
//     identity (`.id(item.id)` at the call site) and starts back at the
//     default corner, which is the right behavior for a new broadcast.
//
// Presentation changed too: this is now a FULL-BLEED `.overlay { }` at the
// call site (no `alignment:`/`.frame` there) so `.position(...)` below can
// place it anywhere on screen — see LiveViewerPlayerView / GoLiveBroadcastView.
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
    /// Owner latency ask (2026-08-01): "render optimistically before the
    /// server confirms". A message id in here is showing on screen ahead of
    /// the server's own confirmation — `bubble(_:)` dims it very slightly so
    /// it never LIES about being confirmed, just feels instant rather than
    /// waiting out a round trip.
    @Published private(set) var pendingMessageIds: Set<String> = []

    /// Only the trailing window is ever RENDERED (owner spec: "last ~6
    /// messages") — the full session history is kept here regardless, so a
    /// future scroll-back affordance wouldn't need to change this layer.
    static let visibleWindow = 6
    private static let maxLength = 500

    private let streamId: String
    /// My own identity — needed to build the optimistic bubble locally,
    /// before the server hands back a real `LiveChatMessage` for it.
    private let myUserId: String?
    private let myFullName: String?
    private let myAvatarUrl: String?
    private var cursor: String?
    private var pollTask: Task<Void, Never>?

    init(streamId: String, myUserId: String? = nil, myFullName: String? = nil, myAvatarUrl: String? = nil) {
        self.streamId = streamId
        self.myUserId = myUserId
        self.myFullName = myFullName
        self.myAvatarUrl = myAvatarUrl
    }

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
        // Optimistic — the member's own message appears in the thread
        // INSTANTLY, before the network round-trip resolves (owner latency
        // ask). Swapped for the server's real row on success; on failure the
        // bubble is left up rather than yanked back (the send may well have
        // landed server-side despite a client-side error — the next poll
        // reconciles either way, same honesty policy as every other
        // optimistic action on this screen).
        let pendingId = "pending-\(UUID().uuidString)"
        let optimistic = LiveChatMessage(
            messageId: pendingId, userId: myUserId ?? "", fullName: myFullName ?? "You",
            avatarUrl: myAvatarUrl, body: text, sentAt: ISO8601DateFormatter().string(from: Date())
        )
        pendingMessageIds.insert(pendingId)
        messages.append(optimistic)
        guard let sent = try? await MemberAPI.sendLiveMessage(streamId: streamId, body: text) else { return }
        pendingMessageIds.remove(pendingId)
        if let idx = messages.firstIndex(where: { $0.messageId == pendingId }) {
            messages[idx] = sent
        } else if !messages.contains(where: { $0.messageId == sent.messageId }) {
            messages.append(sent)
        }
        cursor = sent.sentAt
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Live drag delta (only non-zero mid-gesture) + the settled offset from
    /// the default bottom-leading corner — see the header comment for what
    /// "remembered for the session" means here.
    @GestureState private var dragTranslation: CGSize = .zero
    @State private var settledOffset: CGSize = .zero
    @State private var collapsed = false

    private static let widthFraction: CGFloat = 0.55
    private static let heightFraction: CGFloat = 0.26
    private static let bubbleDiameter: CGFloat = 54
    private static let margin: CGFloat = 12
    /// Clears the bottom dock (owner redesign, 2026-08-01 — see
    /// LiveDockChrome.swift) on either host screen. Sized for the TALLER
    /// two-row guest-on-stage dock so this never overlaps it even though
    /// most of the time (a plain viewer's one-row dock) that leaves a little
    /// unused clearance above the dock — safer than the alternative.
    private static let bottomInset: CGFloat = 210
    /// Clears the new ONE-LINE top row (close ✕ / host chip / title / LIVE /
    /// counters on the viewer; minimize / LIVE pill / timer on the
    /// broadcaster) — much shorter than the old three-row chrome this used
    /// to clear.
    private static let topInset: CGFloat = 76

    init(streamId: String, myUserId: String?, myFullName: String? = nil, myAvatarUrl: String? = nil,
         handsRaisedCount: Int, visible: Binding<Bool>) {
        self.streamId = streamId
        self.myUserId = myUserId
        self.handsRaisedCount = handsRaisedCount
        _visible = visible
        _chat = StateObject(wrappedValue: LiveFloatingChatController(
            streamId: streamId, myUserId: myUserId, myFullName: myFullName, myAvatarUrl: myAvatarUrl))
    }

    private var recent: [LiveChatMessage] {
        Array(chat.messages.suffix(LiveFloatingChatController.visibleWindow))
    }

    private var screen: CGSize { UIScreen.main.bounds.size }
    private var cardSize: CGSize {
        CGSize(width: screen.width * Self.widthFraction, height: screen.height * Self.heightFraction)
    }
    private var currentSize: CGSize {
        collapsed ? CGSize(width: Self.bubbleDiameter, height: Self.bubbleDiameter) : cardSize
    }
    /// Default top-left corner (bottom-leading anchored) before any drag.
    private var defaultOrigin: CGPoint {
        CGPoint(x: Self.margin, y: screen.height - Self.bottomInset - cardSize.height)
    }
    /// Top-left corner after the settled + in-flight drag offset, clamped so
    /// the card/bubble can never drift off-screen or behind the top/bottom HUD.
    private var origin: CGPoint {
        let raw = CGPoint(
            x: defaultOrigin.x + settledOffset.width + dragTranslation.width,
            y: defaultOrigin.y + settledOffset.height + dragTranslation.height)
        let minX = Self.margin
        let maxX = max(minX, screen.width - currentSize.width - Self.margin)
        let minY = Self.topInset
        let maxY = max(minY, screen.height - Self.bottomInset - currentSize.height)
        return CGPoint(x: min(max(raw.x, minX), maxX), y: min(max(raw.y, minY), maxY))
    }

    /// Drag from the header (card) or the bubble itself — a `minimumDistance`
    /// so a plain tap on the header's own collapse button, or a tap on the
    /// bubble, still resolves as a tap rather than being swallowed here.
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragTranslation) { value, state, _ in state = value.translation }
            .onEnded { value in
                settledOffset.width += value.translation.width
                settledOffset.height += value.translation.height
            }
    }

    var body: some View {
        Group {
            if collapsed { bubbleButton } else { card }
        }
        .frame(width: currentSize.width, height: currentSize.height)
        .position(x: origin.x + currentSize.width / 2, y: origin.y + currentSize.height / 2)
        .opacity(visible ? 1 : 0)
        .allowsHitTesting(visible)
        .animation(.easeInOut(duration: 0.2), value: visible)
        .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: collapsed)
        .task { chat.start() }
        .onDisappear { chat.stop() }
    }

    // MARK: Card (expanded) — draggable header + message list + composer

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
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
        .transition(.scale(scale: 0.4, anchor: .topLeading).combined(with: .opacity))
    }

    /// Drag handle + collapse control — the ONLY part of the card the drag
    /// gesture is attached to, so scrolling the message list or typing in
    /// the composer is never fought over with a pan gesture on the card.
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text("LIVE CHAT").font(.inter(9, .bold)).kerning(1).foregroundStyle(.white.opacity(0.6))
            Spacer(minLength: 0)
            Button {
                Haptics.tap()
                collapsed = true
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.14), in: Circle())
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Collapse live chat")
        }
        .contentShape(Rectangle())
        .gesture(dragGesture)
    }

    // MARK: Bubble (collapsed) — single draggable round button, re-expands on tap

    private var bubbleButton: some View {
        Button {
            Haptics.tap()
            collapsed = false
        } label: {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 1)
                Image(systemName: "message.fill").font(.system(size: 17, weight: .semibold)).foregroundStyle(Nuru.gold)
            }
        }
        .environment(\.colorScheme, .dark)
        .buttonStyle(.pressable)
        .simultaneousGesture(dragGesture)
        .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        .accessibilityLabel("Show live chat")
        .transition(.scale(scale: 0.4, anchor: .topLeading).combined(with: .opacity))
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
        // Optimistic bubble, not yet confirmed by the server — dimmed just
        // enough to be honest about that without looking broken.
        .opacity(chat.pendingMessageIds.contains(m.messageId) ? 0.6 : 1)
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
