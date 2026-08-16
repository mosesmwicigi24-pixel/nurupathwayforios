// Nuru Live L4 tab restructure (docs/LIVE_STREAMING.md) — Chat now lives one
// level inside the "You" tab, so its unread count needs to reach TWO places
// outside ChatView itself: the You tab's segmented-control chip and the You
// tab's bottom-bar icon badge. ChatInboxViewModel is still owned privately by
// ChatView (kept alive in the You tab's ZStack so switching segments never
// tears down the inbox), so this tiny shared store is the one thing both the
// tab bar (RootView) and the segment bar (YouTabView) can read without either
// of them needing a ChatInboxViewModel of their own.
import Foundation

@MainActor
final class ChatBadge: ObservableObject {
    static let shared = ChatBadge()
    private init() {}

    /// Unread DMs (discipler/pastoral threads excluded — they have their own
    /// tabs inside Chat) + pending incoming connection requests. Exactly the
    /// same formula as ChatView's own "Chat" segment chip, so the two never
    /// disagree.
    @Published private(set) var count = 0

    /// Called by ChatInboxViewModel whenever the inbox (or the connection
    /// request lists) reloads.
    func set(_ n: Int) { count = max(0, n) }

    /// Background refresh so the badge is right even before the member has
    /// ever opened the You tab this session — RootView polls this the same
    /// way HomeView polls the radio ON AIR state. Duplicates
    /// ChatInboxViewModel's `dms` filter (kind == "dm", discipler/pastoral
    /// excluded) because it runs independently of any mounted ChatView.
    func refresh() async {
        async let inboxReq = try? MemberAPI.chatInbox()
        async let incomingReq = try? MemberAPI.listConnectionRequests(direction: "incoming")
        guard let inbox = await inboxReq else { return }
        let incoming = await incomingReq ?? []
        let dmUnread = inbox.conversations.filter {
            guard $0.kind == "dm" else { return false }
            if let type = $0.type { return type != "DISCIPLER" && type != "PASTORAL" }
            return $0.conversationId != PastoralPrefs.pastoralConversationId
                && $0.conversationId != PastoralPrefs.disciplerConversationId
        }.reduce(0) { $0 + $1.unread }
        set(dmUnread + incoming.count)
    }
}
