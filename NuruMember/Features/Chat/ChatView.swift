// Chat — "Nuru Connect" inbox, the native port of the Figma ChatTab. A cream
// header (COMMUNITY kicker, serif title, bell → notifications — §8.1 rule 2), a
// white search bar, the "Quick help from Nuru" AI launcher (a paper card with
// a gold-tint tile), the italic "Verse for today" ribbon, and a capsule segment control
// (#My Space · DM · My Groups with counts). Each segment renders one grouped
// white card of rows: spaces (# avatar, author preview, member dots, Active
// pill), DMs (stories row, real-or-initials avatars, unread badges, read ticks)
// and groups. The pen beside the bell opens the "Start something" compose sheet.
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class ChatInboxViewModel: ObservableObject {
    @Published var inbox: ChatInbox?
    @Published var people: [ChatPerson] = []
    @Published var loading = true
    @Published var error: String?
    /// Why the inbox didn't load — said in the one state language (§4).
    @Published var loadFailure: Error?
    @Published var busyPersonId: String?    // person whose DM is being created
    @Published var joiningSpaceId: String?  // discover space being followed

    // MARK: Connections (Chat Redesign C3a — "no unsolicited DMs")
    @Published var connections: [ConnectionRow] = []
    @Published var incomingRequests: [ConnectionRequestRow] = []
    @Published var outgoingRequests: [ConnectionRequestRow] = []
    @Published var connectingPersonId: String?     // person a request is being sent/cancelled/decided for
    /// Set when POST /chat/dms comes back 403 CONSENT_REQUIRED for someone the
    /// directory hadn't flagged yet (stale cache) — the view auto-offers to
    /// send the request instead of just failing.
    @Published var consentPrompt: ChatPerson?

    // MARK: Four-tab restructure (Chat Redesign C3b)

    /// GET /me/discipleship — the `discipler` field decides whether the
    /// My Discipler tab has a live assignment or shows its empty state.
    @Published var discipleship: Discipleship?
    /// Spaces whose reviewed join request is pending a leader's decision
    /// (session-local; the server notifies on accept/decline).
    @Published var pendingSpaceIds: Set<String> = []
    @Published var openingDiscipler = false
    @Published var openingPastoral = false
    /// Friendly inline notice for the discipler/pastor tabs (open failures).
    @Published var privateThreadNotice: String?
    /// GET /chat/pastoral/eligibility, cached per session (PastorEligibility) —
    /// "have I ever been assigned as a pastor". Shows the "Talk with Your
    /// Pastor" inbox to an assigned pastor, not just a SuperAdmin (Chat
    /// Redesign C4, closing the C3b gap).
    @Published var isPastor = false

    var conversations: [ChatConversation] { inbox?.conversations ?? [] }
    var spaces: [ChatConversation] { conversations.filter { $0.kind == "space" } }
    /// The Chat tab's DM list — with the discipler/pastoral threads kept OUT
    /// (they live in their own tabs). Server-authoritative: a row's `type`
    /// (Chat Redesign C4) says DIRECT/BROADCAST_RESPONSE vs DISCIPLER/PASTORAL.
    /// Only when `type` is absent (an older server) does this fall back to the
    /// client-taught cached-id heuristic — tolerant decode, not the default path.
    var dms: [ChatConversation] {
        conversations.filter {
            guard $0.kind == "dm" else { return false }
            if let type = $0.type { return type != "DISCIPLER" && type != "PASTORAL" }
            return $0.conversationId != PastoralPrefs.pastoralConversationId
                && $0.conversationId != PastoralPrefs.disciplerConversationId
        }
    }
    var groups: [ChatConversation] { conversations.filter { $0.kind == "group" } }
    var discover: [DiscoverSpace] { inbox?.discoverSpaces ?? [] }
    var totalUnread: Int { conversations.reduce(0) { $0 + $1.unread } }

    /// The header's line says what it counts (§7.4 #15): messages — "No new
    /// messages" / "1 new message" / "N new messages". It said "You're all
    /// caught up" beside a bell whose dot counts the inbox's notices, which
    /// read as a contradiction. Nil until the inbox has answered: no count
    /// that isn't true yet (§7.1 rule 5). Pure.
    nonisolated static func headerLine(unread: Int?) -> String? {
        guard let unread else { return nil }
        switch unread {
        case ..<1: return "No new messages"
        case 1: return "1 new message"
        default: return "\(unread) new messages"
        }
    }
    /// Pending asks from someone else — the number the Chat segment badge and
    /// the bell dot both surface prominently.
    var pendingIncomingCount: Int { incomingRequests.count }

    /// Unread on the (known) discipler / pastoral threads — the tab badges.
    var disciplerUnread: Int {
        guard let id = PastoralPrefs.disciplerConversationId else { return 0 }
        return conversations.first { $0.conversationId == id }?.unread ?? 0
    }
    var pastoralUnread: Int {
        guard !PastoralPrefs.muted, let id = PastoralPrefs.pastoralConversationId else { return 0 }
        return conversations.first { $0.conversationId == id }?.unread ?? 0
    }

    func load() async {
        loading = true; error = nil
        async let inboxReq = MemberAPI.chatInbox()
        async let peopleReq = try? MemberAPI.chatPeople()
        async let connectionsReq = try? MemberAPI.listConnections()
        async let incomingReq = try? MemberAPI.listConnectionRequests(direction: "incoming")
        async let outgoingReq = try? MemberAPI.listConnectionRequests(direction: "outgoing")
        async let discipleshipReq = try? MemberAPI.discipleship()

        do { inbox = try await inboxReq; loadFailure = nil }
        catch { self.error = "Couldn't load your chats."; loadFailure = error }
        if let p = await peopleReq { people = p }
        if let c = await connectionsReq { connections = c }
        if let inc = await incomingReq { incomingRequests = inc }
        if let out = await outgoingReq { outgoingRequests = out }
        if let d = await discipleshipReq { discipleship = d }
        isPastor = await PastorEligibility.isPastor()
        // The server is the source of truth for mute now (Chat Redesign C4) —
        // sync the local optimistic flag from whichever row the inbox resolves
        // as the pastoral thread, so a mute set elsewhere (or by this device in
        // an earlier session) is honestly reflected rather than staying stale.
        if let id = PastoralPrefs.pastoralConversationId ?? conversations.first(where: { $0.type == "PASTORAL" })?.conversationId,
           let row = conversations.first(where: { $0.conversationId == id }) {
            PastoralPrefs.muted = row.muted
        }
        loading = false
        publishBadge()
    }

    /// Keeps the You tab's icon badge + segment chip in sync with the SAME
    /// number the Chat segment button already computes inline (L4 restructure
    /// — Chat now lives inside the You tab, so its unread needs to reach
    /// outside this view model; see ChatBadge).
    private func publishBadge() {
        ChatBadge.shared.set(dms.reduce(0) { $0 + $1.unread } + pendingIncomingCount)
    }

    /// My Discipler tab tap → GET /chat/discipler/conversation (lazily creates
    /// the DISCIPLER thread) → the ChatConversation to navigate into. Records
    /// the id so the thread keeps its dressing wherever it's opened from.
    func openDisciplerConversation() async -> ChatConversation? {
        guard !openingDiscipler else { return nil }
        openingDiscipler = true
        defer { openingDiscipler = false }
        do {
            let id = try await MemberAPI.disciplerConversation()
            PastoralPrefs.disciplerConversationId = id
            let d = discipleship?.discipler
            return conversations.first { $0.conversationId == id } ?? ChatConversation(
                conversationId: id, kind: "dm", isPublic: false, title: d?.fullName ?? "My Discipler",
                topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
                lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: d?.avatarUrl)
        } catch let err as APIError {
            if case .http(404, _, _, _) = err {
                // No current assignment (or the discipler's account is gone) —
                // the tab's empty state covers this; refresh so it shows.
                discipleship = try? await MemberAPI.discipleship()
                privateThreadNotice = "A discipler has not yet been assigned to you."
            } else if case .http(403, _, _, _) = err {
                privateThreadNotice = "Direct messages aren't available on this account."
            } else {
                privateThreadNotice = "Couldn't open the conversation — try again."
            }
            return nil
        } catch {
            privateThreadNotice = "Couldn't open the conversation — try again."
            return nil
        }
    }

    /// Talk with My Pastor tap → POST /chat/pastoral (create-or-open). The
    /// pastor's name arrives with the thread itself (GET conversation titles a
    /// DM as the other participant) — the stub title covers the first frame.
    func openPastoralThread() async -> ChatConversation? {
        guard !openingPastoral else { return nil }
        openingPastoral = true
        defer { openingPastoral = false }
        do {
            let t = try await MemberAPI.openPastoralThread()
            PastoralPrefs.pastoralConversationId = t.conversationId
            PastoralPrefs.archived = false   // opening it un-archives by intent
            return conversations.first { $0.conversationId == t.conversationId } ?? ChatConversation(
                conversationId: t.conversationId, kind: "dm", isPublic: false, title: "My Pastor",
                topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
                lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: nil)
        } catch let err as APIError {
            if case .http(404, _, _, _) = err {
                privateThreadNotice = "No pastor is available for your congregation yet — please check back soon."
            } else if case .http(403, _, _, _) = err {
                privateThreadNotice = "Direct messages aren't available on this account."
            } else {
                privateThreadNotice = "Couldn't open the conversation — try again."
            }
            return nil
        } catch {
            privateThreadNotice = "Couldn't open the conversation — try again."
            return nil
        }
    }

    /// Where the caller stands with one directory person right now — derived
    /// client-side from the three lists above, never sent by the server as a
    /// single field.
    func connectionState(for userId: String) -> ConnectionState {
        if connections.contains(where: { $0.userId == userId && $0.status == "accepted" }) { return .connected }
        if connections.contains(where: { $0.userId == userId && $0.status == "blocked" }) { return .blocked }
        if let req = outgoingRequests.first(where: { $0.userId == userId }) { return .requestSent(requestId: req.requestId) }
        if let req = incomingRequests.first(where: { $0.userId == userId }) { return .requestReceived(requestId: req.requestId) }
        return .notConnected
    }

    /// POST /chat/dms then refresh the inbox; returns the conversation to open.
    /// Only ever called for someone already `connected` (or staff) — a
    /// CONSENT_REQUIRED 403 here means the directory's cached state was stale,
    /// so it auto-offers the connection request rather than a dead-end error.
    func startDm(with person: ChatPerson) async -> ChatConversation? {
        guard busyPersonId == nil else { return nil }
        busyPersonId = person.userId
        defer { busyPersonId = nil }
        do {
            let id = try await MemberAPI.createDm(peerUserId: person.userId)
            if let i = try? await MemberAPI.chatInbox() { inbox = i }
            // Prefer the real inbox row (preview, unread); fall back to a stub the
            // thread screen can hydrate from GET /chat/conversations/{id}.
            return conversations.first { $0.conversationId == id } ?? ChatConversation(
                conversationId: id, kind: "dm", isPublic: false, title: person.fullName,
                topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
                lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: person.avatarUrl)
        } catch let err as APIError {
            if case .http(_, "CONSENT_REQUIRED", _, _) = err { consentPrompt = person }
            return nil
        } catch {
            return nil
        }
    }

    /// POST /chat/connections/requests — the new "New DM" for anyone not yet
    /// connected. Refreshes the outgoing list so the row flips to "Request sent".
    func sendConnectionRequest(to person: ChatPerson) async {
        guard connectingPersonId == nil else { return }
        connectingPersonId = person.userId
        defer { connectingPersonId = nil }
        _ = try? await MemberAPI.requestConnection(userId: person.userId)
        if let out = try? await MemberAPI.listConnectionRequests(direction: "outgoing") { outgoingRequests = out }
    }

    /// DELETE /chat/connections/requests/{id} — withdraw a still-pending ask.
    func cancelConnectionRequest(_ req: ConnectionRequestRow) async {
        guard connectingPersonId == nil else { return }
        connectingPersonId = req.userId
        defer { connectingPersonId = nil }
        _ = try? await MemberAPI.cancelConnectionRequest(req.requestId)
        if let out = try? await MemberAPI.listConnectionRequests(direction: "outgoing") { outgoingRequests = out }
    }

    /// POST .../accept — creates the connection; does NOT open a DM (matches
    /// the server: `/chat/dms` still does that, now gated on the connection).
    func acceptConnectionRequest(_ req: ConnectionRequestRow) async {
        guard connectingPersonId == nil else { return }
        connectingPersonId = req.userId
        defer { connectingPersonId = nil }
        _ = try? await MemberAPI.acceptConnectionRequest(req.requestId)
        async let incomingReq = try? MemberAPI.listConnectionRequests(direction: "incoming")
        async let connectionsReq = try? MemberAPI.listConnections()
        if let inc = await incomingReq { incomingRequests = inc }
        if let c = await connectionsReq { connections = c }
        publishBadge()
    }

    /// POST .../decline.
    func declineConnectionRequest(_ req: ConnectionRequestRow) async {
        guard connectingPersonId == nil else { return }
        connectingPersonId = req.userId
        defer { connectingPersonId = nil }
        _ = try? await MemberAPI.declineConnectionRequest(req.requestId)
        if let inc = try? await MemberAPI.listConnectionRequests(direction: "incoming") { incomingRequests = inc }
        publishBadge()
    }

    /// POST /chat/spaces/{id}/join then refresh — the space moves to "your
    /// spaces". C3a/C3b tolerance: where the server refuses the immediate join
    /// (a space that requires leader review), fall back to filing a reviewed
    /// join request (POST /chat/spaces/{id}/join-requests) and show "pending"
    /// instead of a dead-end error.
    func follow(_ space: DiscoverSpace) async {
        guard joiningSpaceId == nil else { return }
        joiningSpaceId = space.conversationId
        defer { joiningSpaceId = nil }
        do {
            try await MemberAPI.joinChatSpace(space.conversationId)
            if let i = try? await MemberAPI.chatInbox() { inbox = i }
        } catch let err as APIError {
            // 403 (review required) / 404 (not visible for immediate join) /
            // 422 — try the reviewed path before giving up.
            guard case .http(let status, _, _, _) = err, [403, 404, 409, 422].contains(status) else { return }
            if let res = try? await MemberAPI.requestSpaceJoin(space.conversationId) {
                if res.status == "already_member" {
                    if let i = try? await MemberAPI.chatInbox() { inbox = i }
                } else {
                    pendingSpaceIds.insert(space.conversationId)
                }
            }
        } catch { /* offline etc. — the button simply stays */ }
    }
}

// C3b four-tab restructure: My Space (spaces + the cell/group rooms, merged —
// the backend already unifies both under type=SPACE) · Chat (the consent-gated
// DM segment, renamed) · My Discipler · Talk with My Pastor. SuperAdmin keeps
// Broadcast appended, unchanged.
private enum ChatSegment: Int, CaseIterable { case space, dm, discipler, pastor, broadcast }

// Figma STORY_RING — the warm gold gradient used for rings and badges.
private let storyRing = LinearGradient(
    colors: [Color(hex: 0xE6C068), Color(hex: 0xC89B3C), Color(hex: 0xB07D2E)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

// Per-row tint cycle (backend sends no space colour) — mirrors the mock palette.
// Navy or gold only (§8.1 rule 1) — no indigo, sky, green, pink or teal rows.
// Gold and navy only (§8.1 rule 1; final walk C4: the cell room's tile was
// the hero's mid-blue #315F8C, a hue no role has).
private let rowTints: [UInt32] = [0xC89B3C, 0x143559, 0xA87F2E, 0x0B1F33]
private func rowTint(_ index: Int) -> Color { Color(hex: rowTints[index % rowTints.count]) }

// "9:42 AM" today · "Yesterday" · "Tue" within the week · "4 Jun" beyond.
private func chatTime(_ iso: String?) -> String {
    guard let iso,
          let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    else { return "" }
    let cal = Calendar.current
    let f = DateFormatter()
    if cal.isDateInToday(d) { f.dateFormat = "h:mm a" }
    else if cal.isDateInYesterday(d) { return "Yesterday" }
    else if let days = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day, days < 7 { f.dateFormat = "EEE" }
    else { return NuruDates.day(d) }
    return f.string(from: d)
}

struct ChatView: View {
    /// True when hosted as the "Chat" segment inside the You tab (L4) rather
    /// than as its own top-level tab — the You tab's own segmented-control bar
    /// already clears the status bar, so this header's hero block only needs
    /// a little breathing room, not a second 60pt reservation for it.
    var embeddedInYou: Bool = false

    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @StateObject private var vm = ChatInboxViewModel()
    /// Whether a discipler is paired (GET /growth/mentor) — the My Discipler
    /// chip shows only then (Cycle 4, B1).
    @ObservedObject private var disciplers = DisciplerStore.shared
    @State private var path = NavigationPath()
    @State private var segment: ChatSegment = .space
    @State private var query = ""
    @State private var composeOpen = false
    @State private var showNuru = ProcessInfo.processInfo.environment["NURU_SCREEN"] == "nuru"  // debug screenshot hook

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        VStack(spacing: Nuru.S.screen) {
                            // A saved copy says so (final walk M3) — never
                            // over the skeleton or the failed card.
                            NuruSavedCopyNotice(hasContent: vm.inbox != nil)
                            // Broadcast is a focused composer — drop the AI/verse
                            // cards there so "Send to all" stays above the fold.
                            if segment != .broadcast {
                                aiCard
                                // Pray is a door inside Community (§9.2 #13),
                                // where Home's verse was repeated: the verse is
                                // Home's alone, and the Talk | Pray switch above
                                // is gone — the chips below are the one switcher.
                                if query.isEmpty { prayerRoomRow }
                            }
                            segmentControl
                            segmentBody
                        }
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, Nuru.S.screen)
                        .padding(.bottom, Nuru.tabBarSpace)
                        // Skeleton hands off to real rows with a soft cross-fade.
                        .animation(.easeOut(duration: 0.22), value: vm.loading)
                    }
                    .scrollsToTopOnReselect(.you)   // a re-tap at the root returns to the top (B10)
                }
                .ignoresSafeArea(edges: .top)
                .background(Nuru.paper.ignoresSafeArea())
                .scrollDismissesKeyboard(.interactively)
                if composeOpen { composeSheet }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: composeOpen)
            // A pairing that ends while its chip is open leaves for My Space.
            .onChange(of: disciplers.hasDiscipler) { _, has in
                if !has, segment == .discipler { segment = .space }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showNuru) { NuruAssistantView() }
            .refreshable { await vm.load() }
            .nuruEdgeSwipeBack()   // back by the edge swipe on every pushed page (B9)
            .navigationDestination(for: ChatConversation.self) { ChatThreadView(conversation: $0) }
            // Threads opened WITH a known privacy context (My Discipler /
            // Talk with My Pastor tabs) carry it into the thread screen.
            .navigationDestination(for: ThreadRoute.self) { ChatThreadView(conversation: $0.conversation, context: $0.context) }
            // The bell's inbox, and the announcement a row of it opens.
            .inboxDestinations()
            .navigationDestination(for: Broadcast.self) { BroadcastDetailView(broadcast: $0) }
            // The Prayer Room's own page — the same one Home's "My Prayer
            // Room" tile opens (one way to each thing) — and a prayer in it.
            .navigationDestination(for: CommunityRoute.self) { r in
                switch r {
                case .prayerWall: PrayerRoomView(initialTab: .corporatePrayer)
                case .prayer(let id): PrayerWallDetailView(postId: id)
                case .discussions: DiscussionsView()
                case .discussion(let id): DiscussionThreadView(threadId: id)
                }
            }
        }
        // Coming back from a thread refreshes the inbox, so a conversation just
        // opened stops counting: the thread marked itself read on the server the
        // moment it appeared, and this pulls that truth back into the chips and
        // rows. Without it the numbers only reset on a full tab re-entry.
        .onChange(of: path.count) { old, new in
            if new < old { Task { await vm.load() } }
        }
        // A re-tap on You while Community shows returns to its top (§7.4 #17).
        .popsToRoot(on: .you, path: $path, when: { tabs.youSegmentShown == .chat })
        // Cross-tab deep link (a Home "chat_unread" nudge, the Read-with-a-
        // Friend "Open chat" toast): push THAT thread with the inbox as the
        // back stop. The real inbox row is preferred (title, avatar, unread);
        // before the inbox has loaded a stub carrying only the id still opens
        // — ChatThreadView hydrates from GET /chat/conversations/{id}.
        .onReceive(tabs.$conversationLink) { id in
            guard let id, !id.isEmpty else { return }
            path = NavigationPath()
            path.append(vm.conversations.first { $0.conversationId == id } ?? ChatConversation(
                conversationId: id, kind: "dm", isPublic: false, title: nil,
                topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
                lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: nil))
            DispatchQueue.main.async { tabs.conversationLink = nil }
        }
        // Stale-cache recovery: /chat/dms answered 403 CONSENT_REQUIRED for
        // someone the directory still showed as messageable — offer the
        // connection request instead of a dead-end error.
        // Discipler/pastor tab open failures land here as a friendly alert.
        .alert("Chat", isPresented: Binding(
            get: { vm.privateThreadNotice != nil },
            set: { if !$0 { vm.privateThreadNotice = nil } })
        ) {
            Button("OK", role: .cancel) { vm.privateThreadNotice = nil }
        } message: {
            Text(vm.privateThreadNotice ?? "")
        }
        .alert(item: $vm.consentPrompt) { person in
            Alert(
                title: Text("Not connected yet"),
                message: Text("Send \(person.fullName) a connection request first — you can chat once they accept."),
                primaryButton: .default(Text("Send request")) { Task { await vm.sendConnectionRequest(to: person) } },
                secondaryButton: .cancel())
        }
        .task {
            if vm.inbox == nil { await vm.load() }
            #if DEBUG
            // Screenshot hook: NURU_SCREEN=thread opens the first conversation.
            if ProcessInfo.processInfo.environment["NURU_SCREEN"] == "thread", path.isEmpty,
               let first = vm.spaces.first ?? vm.dms.first ?? vm.groups.first {
                path.append(first)
            }
            #endif
        }
    }

    // MARK: Header

    // Cream Figma header (ChatTab) — navy-on-light "Nuru Connect". Done — keep stable.
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                // One header (EXPERIENCE.md §8.1 rule 2): the kicker names the
                // tab — the greeting belongs to Home alone.
                NuruHeaderText(kicker: "Community", title: "Nuru Connect",
                               line: ChatInboxViewModel.headerLine(unread: vm.inbox == nil ? nil : vm.totalUnread))
                Spacer(minLength: 0)
                // Compose lives in the header, beside the bell (the bell stays
                // rightmost, §8.1 rule 2): as a floating button it always sat on
                // something — the empty state's words, a row's time and unread
                // chip — and a floating button never hides content (rule 9).
                HStack(spacing: Nuru.S.sm) {
                    if segment != .broadcast { composeButton }
                    bellButton
                }
            }
            searchBar.padding(.top, Nuru.S.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, embeddedInYou ? Nuru.S.base : 60)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // The one bell (EXPERIENCE.md §7.2 #4) → the inbox, its gold dot only
    // while the inbox has something unread. It used to light for unread chat
    // messages and pending connection requests too — those are counted where
    // they live (the You tab's badge and the Community chip, ChatBadge); a
    // connection request is also an inbox notice, so the inbox counts it.
    private var bellButton: some View {
        NuruBell()
    }

    private var searchBar: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.search, size: 18, color: Color(hex: 0x74808F))
            TextField("", text: $query, prompt: Text("Search spaces, people, messages").foregroundColor(Color(hex: 0x74808F)))
                .font(.inter(14)).foregroundStyle(Nuru.navy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                // 44pt-tall hit area — the bare 14pt glyph was a fiddly target.
                Button {
                    Haptics.tap()
                    query = ""
                } label: {
                    Icon(.x, size: 14, color: Color(hex: 0x74808F))
                        .frame(width: 32, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Nuru.S.base)
        .frame(height: 46)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: AI card ("Quick help from Nuru")

    // A paper card (owner, 2026-10-08, §8.1 rule 1: navy is the church's
    // voice and each tab's next step — the assistant is neither): white, the
    // hairline, the gold-tint tile, navy words. It was navy (§8.2 #3, which
    // this supersedes), and before that a purple-and-green gradient.
    private var aiCard: some View {
        Button {
            Haptics.tap()
            showNuru = true
        } label: {
            HStack(spacing: 14) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(hex: Nuru.tileTint))
                    .frame(width: 48, height: 48)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
                    .overlay(Icon(.sparkles, size: 22, color: Nuru.navy))
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Quick help from Nuru")
                            .font(.nRowTitle).kerning(-0.16).foregroundStyle(Nuru.navy)
                        Text("AI").font(.inter(11, .heavy)).kerning(1.1).foregroundStyle(Nuru.goldChipText)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Nuru.goldChipBg, in: Capsule())
                    }
                    // Whole, never cut (§8.1 rule 9).
                    // No zero counts (§7.4 #9): "0 updates across 0 spaces" said nothing.
                    Text(ZeroCounts.assistantLine(unread: vm.totalUnread, spaces: vm.spaces.count))
                        .font(.nCardMeta).foregroundStyle(Nuru.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: Nuru.ink300)
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: My Prayer Room (EXPERIENCE.md §9.2 #13) — a door, not a switch

    /// "My Prayer Room · Pray with the family" — Community's prayer, one tap
    /// from its talk, with its own page and tabs. It was a Talk | Pray switch
    /// stacked on You's segment bar and the inbox's chips (three switchers),
    /// and the verse card here repeated Home's verse of the day.
    private var prayerRoomRow: some View {
        NavigationLink(value: CommunityRoute.prayerWall) {
            HStack(spacing: Nuru.S.md) {
                Icon(.handHeart, size: 18, color: Nuru.navy)
                    .frame(width: 36, height: 36)
                    .background(Color(hex: Nuru.tileTint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("My Prayer Room").font(.nRowTitle).foregroundStyle(Nuru.navy)
                    Text("Pray with the family").font(.nCardMeta).foregroundStyle(Nuru.ink600)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: Nuru.ink300)
            }
            .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityHint("Opens My Prayer Room")
    }

    // MARK: Segmented control (capsule pills, navy gradient active)

    // Four (five for SuperAdmin) chips no longer fit a fixed-width capsule row,
    // so the control scrolls horizontally; each chip is icon + label + unread.
    private var segmentControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                // The chips carry what needs the member's attention — messages
                // not yet read — not how many rooms exist. A chip with nothing
                // unread shows no number; opening the conversation clears it.
                segmentButton(.space, "#My Space", icon: nil,
                              (vm.spaces + vm.groups).reduce(0) { $0 + $1.unread })
                // Unread DM messages + pending incoming connection requests —
                // both are "things waiting on you in this tab".
                segmentButton(.dm, "Chat", icon: .messageCircle,
                              vm.dms.reduce(0) { $0 + $1.unread } + vm.pendingIncomingCount)
                // Only for a discipler the server names (Cycle 4, B1): with none it
                // opened onto "A discipler has not yet been assigned to you."
                if disciplers.hasDiscipler {
                    segmentButton(.discipler, "My Discipler", icon: .users, vm.disciplerUnread)
                }
                segmentButton(.pastor, "My Pastor", icon: .heartHandshake, vm.pastoralUnread)
                if isStaff { broadcastSegmentButton }
            }
            .padding(4)
        }
        .background(Color.white.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    /// SuperAdmin gate for the Broadcast segment — mirrors the server's
    /// requireRole("SuperAdmin").
    ///
    /// NOT "any role above Student", which is what this used to be: a cell leader
    /// is a member who is not an admin, and the Broadcast does not exist for them.
    /// The server refuses everyone below SuperAdmin regardless; this keeps the tab
    /// from being offered to people it would only refuse. Compared case-insensitively
    /// because the app has both spellings in the wild, and failing open here would
    /// mean showing a door that never opens.
    private var isStaff: Bool {
        (auth.profile?.role ?? "").lowercased() == "superadmin"
    }

    // Megaphone pill — 4th segment, SuperAdmin only (no count chip; it's a composer).
    private var broadcastSegmentButton: some View {
        let selected = segment == .broadcast
        return Button {
            if !selected { Haptics.selection() }
            withAnimation(.easeInOut(duration: 0.15)) { segment = .broadcast }
        } label: {
            HStack(spacing: 5) {
                Icon(.megaphone, size: 14, color: selected ? Nuru.gold : Color(hex: 0x59667C))
                Text("Broadcast").font(.inter(12, .semibold)).foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.clear),
                in: Capsule())
            .shadow(color: selected ? Color(hex: 0x0B1F33).opacity(0.35) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func segmentButton(_ seg: ChatSegment, _ label: String, icon: Lucide?, _ count: Int) -> some View {
        let selected = segment == seg
        return Button {
            if !selected { Haptics.selection() }
            withAnimation(.easeInOut(duration: 0.15)) { segment = seg }
        } label: {
            HStack(spacing: 5) {
                if let icon { Icon(icon, size: 14, color: selected ? Nuru.gold : Color(hex: 0x59667C)) }
                Text(label).font(.inter(12, .semibold)).foregroundStyle(selected ? Color.white : Color(hex: 0x59667C))
                // Unread only. All read → no number at all; the quiet chip IS the
                // "nothing waiting" signal.
                if count > 0 {
                    Text("\(count)").font(.inter(11, .bold))
                        .foregroundStyle(selected ? Nuru.navy : Color(hex: 0x6A7686))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .frame(minWidth: 18)
                        .background(selected ? Nuru.gold : Nuru.surface, in: Capsule())
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color.clear),
                in: Capsule())
            .shadow(color: selected ? Color(hex: 0x0B1F33).opacity(0.35) : .clear, radius: 8, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: Segment bodies

    @ViewBuilder
    private var segmentBody: some View {
        if vm.loading && vm.inbox == nil {
            inboxSkeleton.transition(.opacity)
        } else if vm.inbox == nil {
            loadFailedCard
        } else {
            switch segment {
            case .space: spaceList
            case .dm: dmList
            case .discipler: disciplerTab
            case .pastor: pastorTab
            case .broadcast:
                // The whole segment sits behind the lock: Face ID (or the
                // password) first, then the composer and the sent broadcasts.
                if isStaff { BroadcastSection() }
            }
        }
    }

    // First-load placeholder — mirrors the grouped row card (52pt squircle +
    // two text lines) so real rows land exactly where the bones were.
    private var inboxSkeleton: some View {
        groupedCard {
            ForEach(0..<4, id: \.self) { i in
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Nuru.surface).frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Nuru.surface).frame(width: 132, height: 10)
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Nuru.surface.opacity(0.7)).frame(height: 8)
                            .padding(.trailing, 56)
                    }
                }
                .padding(.horizontal, Nuru.S.base)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { if i > 0 { Rectangle().fill(Nuru.border).frame(height: 1) } }
            }
        }
        .nuruShimmer()
    }

    // Inbox failed to load — what really happened, in the one state language
    // (§4: offline, our side, an ended session), with a real retry. It said
    // "Couldn't load your chats." whatever the cause.
    private var loadFailedCard: some View {
        NuruStateView(state: .failed(vm.loadFailure.map { NuruStateCopy.failure($0) } ?? .serverSide),
                      retry: { Task { await vm.load() } })
        .frame(maxWidth: .infinity)
    }

    private func matches(_ c: ChatConversation) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return (c.title ?? "").lowercased().contains(q)
            || (c.lastBody ?? "").lowercased().contains(q)
            || (c.lastAuthor ?? "").lowercased().contains(q)
    }

    // My Space — spaces AND the cell/group rooms under one roof (C3b: the
    // backend files both under type=SPACE; two segments were one tab too many).
    private var spaceList: some View {
        let items = vm.spaces.filter(matches)
        let groupItems = vm.groups.filter(matches)
        let discoverable = filteredDiscover
        return VStack(alignment: .leading, spacing: 10) {
            // A Lucide glyph, not a typed "#" (§8.1 rule 7; final walk C4).
            sectionLabel(icon: .messageSquareText, "YOUR SPACES")
            if items.isEmpty {
                emptyCard(icon: query.isEmpty ? .sparkles : .search,
                          query.isEmpty
                    ? SpaceWords.none(canFollow: !discoverable.isEmpty)
                    : "No spaces match your search.")
            } else {
                groupedCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                        NavigationLink(value: c) { SpaceRow(c: c, index: idx, divider: idx > 0) }.buttonStyle(.pressableSubtle)
                    }
                }
            }
            if !groupItems.isEmpty {
                sectionLabel(icon: .users, "CELL & GROUPS").padding(.top, 6)
                groupedCard {
                    ForEach(Array(groupItems.enumerated()), id: \.element.id) { idx, c in
                        NavigationLink(value: c) { ConversationRow(c: c, index: idx, divider: idx > 0) }.buttonStyle(.pressableSubtle)
                    }
                }
            }
            if !discoverable.isEmpty {
                sectionLabel(icon: .messageSquareText, "DISCOVER SPACES").padding(.top, 6)
                groupedCard {
                    ForEach(Array(discoverable.enumerated()), id: \.element.id) { idx, s in
                        DiscoverSpaceRow(space: s, index: idx, divider: idx > 0,
                                         joining: vm.joiningSpaceId == s.conversationId,
                                         pending: vm.pendingSpaceIds.contains(s.conversationId)) {
                            Haptics.tap()
                            Task { await vm.follow(s) }
                        }
                    }
                }
            }
        }
    }

    // MARK: My Discipler tab (C3b)

    @ViewBuilder private var disciplerTab: some View {
        if let discipler = vm.discipleship?.discipler {
            PrivateThreadCard(
                kicker: "MY DISCIPLER",
                title: discipler.fullName,
                subtitle: discipler.roleLabel.isEmpty ? "Walking with you on the pathway" : discipler.roleLabel,
                detail: discipler.cellName,
                avatarUrl: discipler.avatarUrl,
                privacyLine: "Private between you and your assigned discipler.",
                unread: vm.disciplerUnread,
                busy: vm.openingDiscipler,
                cta: "Open conversation",
                locked: false
            ) {
                Haptics.tap()
                Task {
                    if let c = await vm.openDisciplerConversation() {
                        path.append(ThreadRoute(conversation: c, context: .discipler))
                    }
                }
            }
        } else {
            emptyCard(icon: .users, "A discipler has not yet been assigned to you.")
        }
    }

    // MARK: Talk with My Pastor tab (C3b)

    @ViewBuilder private var pastorTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            if PastoralPrefs.archived {
                emptyCard(icon: .messageCircle, "You archived this conversation on this device.")
                Button {
                    Haptics.tap()
                    PastoralPrefs.archived = false
                    vm.objectWillChange.send()
                } label: {
                    Text("Reopen").font(.inter(12, .bold)).foregroundStyle(Nuru.goldChipText)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
            } else {
                PrivateThreadCard(
                    kicker: "TALK WITH MY PASTOR",
                    title: "Your pastor is here for you",
                    subtitle: "A private 1:1 conversation — bring anything.",
                    detail: nil,
                    avatarUrl: nil,
                    privacyLine: "Private pastoral conversation.",
                    unread: vm.pastoralUnread,
                    busy: vm.openingPastoral,
                    cta: "Open conversation",
                    locked: PastoralLock.shared.requiresUnlock,
                    muted: PastoralPrefs.muted
                ) {
                    Haptics.tap()
                    Task {
                        // The local privacy gate first (when enabled), then the
                        // server create-or-open. Cancelled auth = stay put.
                        if PastoralLock.shared.requiresUnlock,
                           !(await PastoralLock.shared.unlock()) { return }
                        if let c = await vm.openPastoralThread() {
                            path.append(ThreadRoute(conversation: c, context: .pastoral))
                        }
                    }
                }
            }
            // Pastor/SuperAdmin side: the "Talk with Your Pastor" inbox, behind
            // the SAME server password step-up (and Face ID fast path) as the
            // Broadcast — reusing that exact machinery. Shown to a SuperAdmin
            // (oversight/fallback reach) OR anyone GET /chat/pastoral/eligibility
            // says has ever been assigned as a pastor — not SuperAdmin-only,
            // which used to hide the inbox from an assigned non-SuperAdmin pastor.
            if isStaff || vm.isPastor {
                PastoralInboxSection { row in
                    path.append(ThreadRoute(
                        conversation: ChatConversation(
                            conversationId: row.conversationId, kind: "dm", isPublic: false,
                            title: row.memberName, topic: nil, category: nil, memberCount: 2,
                            lastBody: row.lastBody, lastType: nil, lastAt: row.lastAt,
                            lastAuthor: nil, unread: 0, avatarUrl: row.memberAvatarUrl),
                        context: .normal))
                }
                .padding(.top, 6)
            }
        }
    }

    // Public spaces the member hasn't joined (inbox `discover_spaces`), searched.
    private var filteredDiscover: [DiscoverSpace] {
        guard !query.isEmpty else { return vm.discover }
        let q = query.lowercased()
        return vm.discover.filter {
            ($0.title ?? "").lowercased().contains(q) || ($0.topic ?? "").lowercased().contains(q)
                || ($0.category ?? "").lowercased().contains(q)
        }
    }

    private var dmList: some View {
        let items = vm.dms.filter(matches)
        let directory = filteredPeople
        return VStack(alignment: .leading, spacing: 10) {
            if query.isEmpty { requestsSection }
            if query.isEmpty && !vm.dms.isEmpty { storiesRow.padding(.bottom, 10) }
            sectionLabel(icon: .users, "DIRECT MESSAGES")
            if items.isEmpty {
                emptyCard(icon: query.isEmpty ? .messageCircle : .search,
                          query.isEmpty
                    ? "Connect with someone before starting a chat."
                    : "No conversations match your search.")
            } else {
                groupedCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                        NavigationLink(value: c) { ConversationRow(c: c, index: idx, divider: idx > 0) }.buttonStyle(.pressableSubtle)
                    }
                }
            }
            if !vm.people.isEmpty {
                sectionLabel(icon: .users, "PEOPLE").padding(.top, 6)
                if directory.isEmpty {
                    emptyCard(icon: .search, "No people match your search.")
                } else {
                    groupedCard {
                        ForEach(Array(directory.enumerated()), id: \.element.id) { idx, p in
                            PersonRow(person: p, index: idx, divider: idx > 0,
                                      state: vm.connectionState(for: p.userId),
                                      busy: vm.busyPersonId == p.userId || vm.connectingPersonId == p.userId,
                                      onMessage: { startDm(p) },
                                      onConnect: { Haptics.tap(); Task { await vm.sendConnectionRequest(to: p) } },
                                      onCancelRequest: {
                                          Haptics.tap()
                                          if case let .requestSent(reqId) = vm.connectionState(for: p.userId) {
                                              Task { await vm.cancelConnectionRequest(
                                                  ConnectionRequestRow(requestId: reqId, status: "pending", message: nil,
                                                                        createdAt: nil, userId: p.userId, fullName: p.fullName,
                                                                        avatarUrl: p.avatarUrl)) }
                                          }
                                      })
                        }
                    }
                }
            }
        }
    }

    // "X wants to connect" (incoming, accept/decline) above "Request sent"
    // (outgoing, cancel) — the incoming list is the one that needs the member's
    // action, so it leads.
    @ViewBuilder private var requestsSection: some View {
        if !vm.incomingRequests.isEmpty || !vm.outgoingRequests.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                sectionLabel(icon: .users, "CONNECTION REQUESTS")
                groupedCard {
                    ForEach(Array(vm.incomingRequests.enumerated()), id: \.element.id) { idx, req in
                        IncomingRequestRow(req: req, divider: idx > 0, busy: vm.connectingPersonId == req.userId,
                                           onAccept: { Haptics.tap(); Task { await vm.acceptConnectionRequest(req) } },
                                           onDecline: { Haptics.tap(); Task { await vm.declineConnectionRequest(req) } })
                    }
                    ForEach(Array(vm.outgoingRequests.enumerated()), id: \.element.id) { idx, req in
                        OutgoingRequestRow(req: req, divider: idx > 0 || !vm.incomingRequests.isEmpty,
                                           busy: vm.connectingPersonId == req.userId,
                                           onCancel: { Haptics.tap(); Task { await vm.cancelConnectionRequest(req) } })
                    }
                }
            }
            .padding(.bottom, 6)
        }
    }

    // The whole registered directory (server-scoped), name/congregation searched.
    private var filteredPeople: [ChatPerson] {
        guard !query.isEmpty else { return vm.people }
        let q = query.lowercased()
        return vm.people.filter {
            $0.fullName.lowercased().contains(q) || ($0.congregation ?? "").lowercased().contains(q)
        }
    }

    // Tap a directory person → POST /chat/dms → open the (existing or new) thread.
    private func startDm(_ person: ChatPerson) {
        Haptics.tap()
        Task {
            if let c = await vm.startDm(with: person) { path.append(c) }
        }
    }

    // MARK: DM stories row (gold gradient rings — presence dots omitted: no data)

    private var storiesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Nuru.S.base) {
                VStack(spacing: 8) {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            Circle().fill(LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1628)],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                            Text(myInitials).font(.inter(14, .semibold)).foregroundStyle(.white)
                        }
                        .frame(width: 58, height: 58)
                        ZStack { Circle().fill(storyRing); Icon(.plus, size: 14, color: .white) }
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Nuru.paper, lineWidth: 3))
                            .shadow(color: Nuru.gold.opacity(0.5), radius: 5, y: 2)
                            .offset(x: 2, y: 2)
                    }
                    Text("Your note").font(.inter(11, .medium)).foregroundStyle(Color(hex: 0x6A7686))
                }
                .frame(width: 60)
                ForEach(vm.dms) { c in
                    NavigationLink(value: c) {
                        VStack(spacing: 8) {
                            Avatar(url: c.avatarUrl, name: c.title ?? "?", size: 52)
                                .padding(2)
                                .background(Circle().fill(Nuru.paper))
                                .padding(2.5)
                                .background(storyRing, in: Circle())
                            Text(firstWord(c.title)).font(.inter(11, .medium)).foregroundStyle(Nuru.navy).lineLimit(1)
                        }
                        .frame(width: 60)
                    }.buttonStyle(.pressable)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: Compose + compose sheet

    /// "Start something" — the bell's tile, with the pen (§8.1 rule 7: 18).
    private var composeButton: some View {
        Button {
            Haptics.tap()
            composeOpen = true
        } label: {
            Icon(.pencil, size: 18, color: Nuru.navy)
                .frame(width: 44, height: 44)
                .background(Color.white, in: Circle())   // the bell's circle beside it
                .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Start something")
    }

    // Figma ComposeSheet — dark scrim, "Start something", three segment shortcuts.
    // "New DM" jumps to the DM segment (PEOPLE directory below the rows) and
    // "Browse spaces" to the space segment (DISCOVER SPACES below your spaces).
    private var composeSheet: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x0B1F33, alpha: 0.45)
                .ignoresSafeArea()
                .onTapGesture { composeOpen = false }
            VStack(spacing: 0) {
                // The title rides in the card: over the scrim it floated on
                // whatever lay behind it and read poorly.
                HStack {
                    Text("Start something").font(.nCardTitle).foregroundStyle(Nuru.navy)
                    Spacer(minLength: 0)
                    Button { composeOpen = false } label: {
                        Icon(.x, size: 14, color: Nuru.navy)
                            .frame(width: 32, height: 32)
                            .background(Nuru.mutedBg, in: Circle())
                            .frame(width: 44, height: 44)     // full-size hit target
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close")
                }
                .padding(.leading, Nuru.S.base).padding(.trailing, Nuru.S.xs).padding(.top, Nuru.S.xs)
                VStack(spacing: 0) {
                    composeAction("New direct message", "Message a person 1:1", divider: true) {
                        Icon(.pencil, size: 18, color: Nuru.gold)
                    } action: { segment = .dm }
                    composeAction("New group", "Your cell & group rooms live in My Space", divider: true) {
                        Icon(.users, size: 18, color: Nuru.gold)
                    } action: { segment = .space }
                    composeAction("Browse spaces", "Find & join a community space", divider: true) {
                        Icon(.compass, size: 18, color: Nuru.gold)
                    } action: { segment = .space }
                }
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
            .padding(.horizontal, Nuru.S.md)
            // Above the tab bar — its last action ("Browse spaces") sat under it
            // (§7.1 rule 3: the last button never sits under the tab bar).
            .padding(.bottom, Nuru.tabBarSpace)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(2)
    }

    private func composeAction(_ title: String, _ sub: String, divider: Bool,
                               @ViewBuilder icon: () -> some View, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
            composeOpen = false
        } label: {
            HStack(spacing: 14) {
                icon()
                    .frame(width: 44, height: 44)
                    .background(Nuru.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.nCardCTA).foregroundStyle(Nuru.navy)
                    Text(sub).font(.nCardMeta).foregroundStyle(Color(hex: 0x9AA3AF))
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: Color(hex: 0xCBD5E1))
            }
            .padding(Nuru.S.base)
            .overlay(alignment: .top) { if divider { Rectangle().fill(Nuru.border).frame(height: 1) } }
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: Shared bits

    private func sectionLabel(hash: Bool = false, icon: Lucide? = nil, _ text: String) -> some View {
        HStack(spacing: 6) {
            if hash { Text("#").font(.inter(12, .bold)).foregroundStyle(Color(hex: 0xB08A1E)) }
            else if let icon { Icon(icon, size: 14, color: Color(hex: 0xB08A1E)) }
            Text(text).font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xB08A1E))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func groupedCard(@ViewBuilder _ content: () -> some View) -> some View {
        VStack(spacing: 0, content: content)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }

    private func emptyCard(icon: Lucide = .messageCircle, _ text: String) -> some View {
        VStack(spacing: Nuru.S.md) {
            Icon(icon, size: 18, color: Nuru.gold.opacity(0.7))
                .frame(width: 40, height: 40)
                .background(Nuru.gold.opacity(0.08), in: Circle())
            Text(text)
                .font(.nCardBody).foregroundStyle(Color(hex: 0x74808F)).lineSpacing(3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28).padding(.horizontal, Nuru.S.base)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Derived

    private var myInitials: String {
        let parts = (auth.profile?.fullName ?? "").split(separator: " ")
        guard let f = parts.first?.first else { return "ME" }
        if parts.count > 1, let l = parts.last?.first { return "\(f)\(l)".uppercased() }
        return String(f).uppercased()
    }
    private func firstWord(_ s: String?) -> String { (s ?? "—").split(separator: " ").first.map(String.init) ?? "—" }
}

// MARK: - Row chrome shared by space/DM/group rows

// WhatsApp-style double tick shown on rows that are fully read.
private struct DoubleCheck: View {
    var body: some View {
        ZStack {
            Icon(.check, size: 14, color: Color(hex: 0xBCC4CE)).offset(x: -3)
            Icon(.check, size: 14, color: Color(hex: 0xBCC4CE)).offset(x: 3)
        }
        .frame(width: 20, height: 14)
    }
}

// Tiny gold-gradient unread pill.
private struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)   // navy on gold (§8.1 rule 4)
            .padding(.horizontal, 5)
            .frame(minWidth: 17, minHeight: 17)
            .background(storyRing, in: Capsule())
            .shadow(color: Nuru.gold.opacity(0.65), radius: 5, y: 3)
    }
}

// Left gold accent bar + warm tint that mark an unread row.
private struct RowChrome: ViewModifier {
    let unread: Bool
    let divider: Bool
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, Nuru.S.base)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(unread ? Color(hex: 0xFFFDF6) : Color.white)
            .overlay(alignment: .leading) {
                if unread {
                    UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2)
                        .fill(storyRing).frame(width: 3)
                        .padding(.vertical, 10)
                }
            }
            .overlay(alignment: .top) { if divider { Rectangle().fill(Nuru.border).frame(height: 1) } }
    }
}

// Overlapping avatar cascade (the reference MemberStack): identical 20pt
// circles offset by -7pt (~1/3 diameter), each with a 2pt white ring, later
// circles layered ON TOP of earlier ones (zIndex ramps up), finished by the
// white member-count capsule (same 20pt height, thin border, bold navy number)
// overlapping the last circle as the stack's topmost element. The first circle
// shows the space photo (or its initial); the rest are tinted placeholders
// cycling the row palette.
private struct MemberStack: View {
    let avatarUrl: String?
    let title: String?
    let index: Int
    let count: Int

    var body: some View {
        let circles = min(3, max(1, count))
        HStack(spacing: -7) {
            ForEach(0..<circles, id: \.self) { i in
                circle(i).zIndex(Double(i))
            }
            Text(count > 999 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)")
                .font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 7)
                .frame(height: 20)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                .zIndex(Double(circles))
        }
    }

    private func circle(_ i: Int) -> some View {
        let tint = rowTint(index + i)
        return ZStack {
            LinearGradient(colors: [tint, tint.opacity(0.71)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if i == 0 {
                if let avatarUrl, let u = URL(string: avatarUrl) {
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() } else { initial }
                    }
                } else {
                    initial
                }
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.white, lineWidth: 2))
    }

    private var initial: some View {
        Text(String((title ?? "#").trimmingCharacters(in: .whitespaces).prefix(1)).uppercased())
            .font(.inter(11, .bold)).foregroundStyle(.white)
    }
}

// One-line preview — voice/photo affordances, author prefix for multi rooms.
private struct RowPreview: View {
    let c: ChatConversation
    let showAuthor: Bool
    /// One line at the everyday sizes; two at the largest, where one cut even
    /// "No messages yet" to "No message…" (§9.6 #4).
    @Environment(\.dynamicTypeSize) private var typeSize
    private var unread: Bool { c.unread > 0 }
    var body: some View {
        HStack(spacing: 4) {
            if c.lastType == "voice" {
                Icon(.mic, size: 14, color: Nuru.gold)
                // Android parity: surface the note's length in the preview.
                Text(c.lastDuration.map { String(format: "Voice message · %d:%02d", $0 / 60, $0 % 60) } ?? "Voice message")
                    .font(.inter(11)).foregroundStyle(bodyColor)
            } else if c.lastType == "image" {
                Icon(.image, size: 14, color: Nuru.gold)
                Text("Photo").font(.inter(11)).foregroundStyle(bodyColor)
            } else {
                (authorText + Text(c.lastBody ?? "No messages yet"))
                    .font(.inter(11)).foregroundStyle(bodyColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
    }
    private var authorText: Text {
        guard showAuthor, let a = c.lastAuthor, !a.isEmpty else { return Text("") }
        return Text("\(a): ").fontWeight(.semibold).foregroundColor(unread ? Nuru.navy : Color(hex: 0x59667C))
    }
    private var bodyColor: Color { unread ? Color(hex: 0x33445A) : Color(hex: 0x6A7686) }
}

// MARK: - Space row (# squircle, author preview, member dots, Active pill)

private struct SpaceRow: View {
    let c: ChatConversation
    let index: Int
    let divider: Bool
    private var tint: Color { rowTint(index) }
    private var unread: Bool { c.unread > 0 }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("#").font(.inter(22, .bold)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(colors: [tint, tint.opacity(0.71)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: tint.opacity(0.35), radius: 7, y: 5)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.title ?? "Space")
                        .font(.inter(12, unread ? .semibold : .medium)).kerning(-0.12)
                        .foregroundStyle(Nuru.navy).lineLimit(1)
                    if c.muted { MutedGlyph() }
                    Spacer(minLength: 4)
                    Text(chatTime(c.lastAt))
                        .font(unread ? .inter(11, .semibold) : .nCardMeta)
                        .foregroundStyle(unread ? Nuru.gold : Color(hex: 0x9AA3AF))
                }
                HStack(spacing: 8) {
                    RowPreview(c: c, showAuthor: true)
                    Spacer(minLength: 4)
                    if unread { UnreadBadge(count: c.unread) } else { DoubleCheck() }
                }
                HStack {
                    MemberStack(avatarUrl: c.avatarUrl, title: c.title, index: index, count: c.memberCount)
                    Spacer(minLength: 0)
                    activePill
                }
                .padding(.top, 6)
            }
        }
        .modifier(RowChrome(unread: unread, divider: divider))
    }

    private var activePill: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: 0x16A34A)).frame(width: 6, height: 6)
            Text("Active").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x15803D))
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(hex: 0x16A34A, alpha: 0.09), in: Capsule())
    }
}

// MARK: - DM / group row (real-or-initials squircle avatar, unread badge, read ticks)

private struct ConversationRow: View {
    let c: ChatConversation
    let index: Int
    let divider: Bool
    private var tint: Color { rowTint(index + 3) }
    private var unread: Bool { c.unread > 0 }

    var body: some View {
        HStack(spacing: 14) {
            if c.kind == "dm" {
                SquircleAvatar(url: c.avatarUrl, name: c.title ?? "?", tint: tint)
            } else {
                Icon(.users, size: 22, color: .white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [tint, tint.opacity(0.71)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: tint.opacity(0.35), radius: 7, y: 5)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.shownTitle ?? "Conversation")
                        .font(.inter(12, unread ? .semibold : .medium)).kerning(-0.12)
                        .foregroundStyle(Nuru.navy).lineLimit(1)
                    if c.muted { MutedGlyph() }
                    Spacer(minLength: 4)
                    Text(chatTime(c.lastAt))
                        .font(unread ? .inter(11, .semibold) : .nCardMeta)
                        .foregroundStyle(unread ? Nuru.gold : Color(hex: 0x9AA3AF))
                }
                HStack(spacing: 8) {
                    RowPreview(c: c, showAuthor: c.kind != "dm")
                    Spacer(minLength: 4)
                    // A read mark only beside a message (§8.1 rule 8: "✓✓"
                    // sat beside "No messages yet").
                    if unread { UnreadBadge(count: c.unread) } else if c.lastAt != nil { DoubleCheck() }
                }
            }
        }
        .modifier(RowChrome(unread: unread, divider: divider))
    }
}

/// Small bell-slash glyph for a muted conversation row (Chat Redesign C4) —
/// beside the title, same signal the pastoral ⋮ menu's Mute/Unmute reflects.
private struct MutedGlyph: View {
    var body: some View {
        Image(systemName: "bell.slash.fill")
            .font(.symbol(10))
            .foregroundStyle(Color(hex: 0x9AA3AF))
    }
}

// MARK: - Directory person row (PEOPLE section — tap to start/open the DM)

private struct PersonRow: View {
    let person: ChatPerson
    let index: Int
    let divider: Bool
    /// Chat Redesign C3a — "no unsolicited DMs": what tapping this row does
    /// depends entirely on where the pair currently stand.
    let state: ConnectionState
    let busy: Bool
    let onMessage: () -> Void
    let onConnect: () -> Void
    let onCancelRequest: () -> Void
    private var tint: Color { rowTint(index + 1) }

    var body: some View {
        let tappable = { () -> (() -> Void)? in
            switch state {
            case .connected: return onMessage
            case .notConnected: return onConnect
            case .requestSent: return onCancelRequest
            case .requestReceived, .blocked: return nil
            }
        }()
        Group {
            HStack(spacing: 14) {
                SquircleAvatar(url: person.avatarUrl, name: person.fullName, tint: tint)
                    .overlay(alignment: .bottomTrailing) { levelChip }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(person.fullName)
                            .font(.inter(12, .medium)).kerning(-0.12)
                            .foregroundStyle(Nuru.navy).lineLimit(1)
                            .layoutPriority(1)
                        badgeMedallions
                        certSeal
                    }
                    if let subtitle {
                        Text(subtitle)
                            .font(.nCardMeta).foregroundStyle(Color(hex: 0x6A7686)).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                if busy {
                    ProgressView().tint(Nuru.gold).scaleEffect(0.8)
                } else {
                    stateAffordance
                }
            }
            .modifier(RowChrome(unread: false, divider: divider))
        }
        .contentShape(Rectangle())
        .onTapGesture { if !busy { tappable?() } }
        .opacity(busy ? 0.6 : 1)
        .animation(.easeInOut(duration: 0.18), value: busy)
    }

    // Right-edge affordance per connection state — the same real-estate the
    // old always-message-icon used to occupy.
    @ViewBuilder private var stateAffordance: some View {
        switch state {
        case .connected:
            Icon(.messageCircle, size: 14, color: Nuru.gold)
                .frame(width: 32, height: 32)
                .background(Nuru.gold.opacity(0.10), in: Circle())
        case .notConnected:
            HStack(spacing: 4) {
                Image(systemName: "person.badge.plus").font(.symbol(10, weight: .bold))
                Text("Connect").font(.inter(11, .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10).frame(height: 28)
            // A compact in-row action is a navy pill (§8.1 rule 4) — a list of
            // gold "Connect"s was a column of primaries.
            .background(Nuru.navy, in: Capsule())
        case .requestSent:
            HStack(spacing: 4) {
                Text("Request sent").font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x9AA3AF))
                Image(systemName: "xmark.circle.fill").font(.symbol(14)).foregroundStyle(Color(hex: 0xCBD5E1))
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Nuru.surface, in: Capsule())
        case .requestReceived:
            HStack(spacing: 4) {
                Image(systemName: "hand.wave.fill").font(.symbol(10)).foregroundStyle(Nuru.gold)
                Text("Wants to connect").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 10).frame(height: 28)
            .background(Nuru.gold.opacity(0.14), in: Capsule())
        case .blocked:
            Image(systemName: "hand.raised.fill").font(.symbol(13)).foregroundStyle(Color(hex: 0x9AA3AF))
                .frame(width: 32, height: 32)
        }
    }

    private var subtitle: String? {
        PersonWords.subtitle(role: person.role, congregation: person.congregation)
    }

    // MARK: Achievement flair — public aggregates only; every piece disappears
    // gracefully when the server doesn't send it (old servers / no data).

    /// Micro game-rank frame docked on the avatar's bottom-trailing corner.
    @ViewBuilder private var levelChip: some View {
        if let lvl = person.level, lvl > 0 {
            Text("L\(lvl)")
                .font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 4.5).padding(.vertical, 1.5)
                .background(
                    LinearGradient(colors: [Nuru.goldHi, Nuru.goldLo],
                                   startPoint: .top, endPoint: .bottom),
                    in: Capsule()
                )
                .overlay(Capsule().strokeBorder(.white, lineWidth: 1.5))
                .offset(x: 4, y: 4)
        }
    }

    /// Up to 3 overlapping badge medallions + a "+N" mini chip for the rest.
    @ViewBuilder private var badgeMedallions: some View {
        if let count = person.badgeCount, count > 0 {
            let emojis = Array((person.badgeIcons ?? []).prefix(3))
            HStack(spacing: -4) {
                ForEach(emojis.indices, id: \.self) { i in
                    Text(emojis[i]).font(.emoji(11)).lineLimit(1)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white))
                        .overlay(Circle().strokeBorder(Nuru.gold.opacity(0.5), lineWidth: 0.5))
                }
                if count > emojis.count {
                    // At the 11 pt floor "+12" is wider than the medallions, so
                    // the chip grows into a capsule rather than cutting it.
                    Text("+\(count - emojis.count)")
                        .font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0xA8761A))
                        .fixedSize()
                        .padding(.horizontal, 3)
                        .frame(minWidth: 16, minHeight: 16)
                        .background(Capsule().fill(Nuru.goldTint))
                        .overlay(Capsule().strokeBorder(Nuru.gold.opacity(0.5), lineWidth: 0.5))
                }
            }
            .fixedSize()
        }
    }

    /// The "certified" mark — a tiny gold rosette seal.
    @ViewBuilder private var certSeal: some View {
        if let certs = person.certCount, certs > 0 {
            ZStack {
                Circle().fill(Nuru.goldTint).frame(width: 16, height: 16)
                Icon(.award, size: 14, color: Nuru.gold)
            }
            .fixedSize()
        }
    }
}

// MARK: - Connection request rows (incoming = accept/decline, outgoing = cancel)

private struct IncomingRequestRow: View {
    let req: ConnectionRequestRow
    let divider: Bool
    let busy: Bool
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SquircleAvatar(url: req.avatarUrl, name: req.fullName, tint: Nuru.gold)
            VStack(alignment: .leading, spacing: 3) {
                Text(req.fullName).font(.inter(12, .medium)).kerning(-0.12).foregroundStyle(Nuru.navy).lineLimit(1)
                Text("Wants to connect").font(.nCardMeta).foregroundStyle(Color(hex: 0x6A7686))
            }
            Spacer(minLength: 4)
            if busy {
                ProgressView().tint(Nuru.gold).scaleEffect(0.8)
            } else {
                HStack(spacing: 8) {
                    Button(action: onDecline) {
                        Icon(.x, size: 14, color: Color(hex: 0x59667C))
                            .frame(width: 30, height: 30)
                            .background(Nuru.surface, in: Circle())
                    }.buttonStyle(.pressable)
                    Button(action: onAccept) {
                        Icon(.check, size: 14, color: .white)
                            .frame(width: 30, height: 30)
                            .background(storyRing, in: Circle())
                    }.buttonStyle(.pressable)
                }
            }
        }
        .modifier(RowChrome(unread: true, divider: divider))
    }
}

private struct OutgoingRequestRow: View {
    let req: ConnectionRequestRow
    let divider: Bool
    let busy: Bool
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            SquircleAvatar(url: req.avatarUrl, name: req.fullName, tint: Color(hex: 0x9AA3AF))
            VStack(alignment: .leading, spacing: 3) {
                Text(req.fullName).font(.inter(12, .medium)).kerning(-0.12).foregroundStyle(Nuru.navy).lineLimit(1)
                Text("Request sent — waiting to be accepted").font(.nCardMeta).foregroundStyle(Color(hex: 0x6A7686))
            }
            Spacer(minLength: 4)
            if busy {
                ProgressView().tint(Nuru.gold).scaleEffect(0.8)
            } else {
                Button(action: onCancel) {
                    Text("Cancel").font(.inter(11, .semibold)).foregroundStyle(Color(hex: 0x59667C))
                        .padding(.horizontal, 12).frame(height: 28)
                        .background(Nuru.surface, in: Capsule())
                }.buttonStyle(.pressable)
            }
        }
        .modifier(RowChrome(unread: false, divider: divider))
    }
}

// MARK: - Discover space row (public spaces to follow — gold Follow button)

private struct DiscoverSpaceRow: View {
    let space: DiscoverSpace
    let index: Int
    let divider: Bool
    let joining: Bool
    /// A reviewed join request is filed and awaiting the leader (C3b) — the
    /// Follow button gives way to a quiet "Requested" pill.
    let pending: Bool
    let follow: () -> Void
    private var tint: Color { rowTint(index + 2) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("#").font(.inter(22, .bold)).foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(colors: [tint, tint.opacity(0.71)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: tint.opacity(0.35), radius: 7, y: 5)
            VStack(alignment: .leading, spacing: 3) {
                Text(space.title ?? "Space")
                    .font(.inter(12, .medium)).kerning(-0.12)
                    .foregroundStyle(Nuru.navy).lineLimit(1)
                Text(subtitle)
                    .font(.nCardMeta).foregroundStyle(Color(hex: 0x6A7686)).lineLimit(1)
                // Member cascade — the count lives in the stack's pill, not the text.
                MemberStack(avatarUrl: nil, title: space.title, index: index + 2, count: space.memberCount)
                    .padding(.top, 5)
            }
            Spacer(minLength: 4)
            if pending {
                HStack(spacing: 4) {
                    Image(systemName: "hourglass").font(.symbol(10, weight: .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    Text("Requested").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(Nuru.gold.opacity(0.12), in: Capsule())
            } else {
                Button(action: follow) {
                    Group {
                        if joining {
                            ProgressView().tint(.white).scaleEffect(0.7)
                        } else {
                            HStack(spacing: 4) {
                                Icon(.plus, size: 14, color: .white)
                                Text("Follow").font(.inter(11, .bold)).foregroundStyle(.white)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .frame(minWidth: 44)   // spinner state stays a comfortable target
                    .background(Nuru.navy, in: Capsule())   // a compact in-row action (§8.1 rule 4)
                }
                .buttonStyle(.pressable)
                .disabled(joining)
                .animation(.easeInOut(duration: 0.18), value: joining)
            }
        }
        .modifier(RowChrome(unread: false, divider: divider))
    }

    private var subtitle: String {
        if let t = space.topic, !t.isEmpty { return t }
        if let c = space.category, !c.isEmpty { return c }
        return "Public space"
    }
}

// MARK: - Broadcast composer (staff only — ONE message → every member as a DM)

// The Broadcast segment body: an inspiring composer card. What the admin writes
// here is fanned out server-side (POST /chat/broadcast) as an individual DM to
// every member of the congregation — replies arrive back as normal 1:1 threads.
/// The message you just sent, shown as the sent thing — its own words in the
/// serif the app reserves for what is being said, and the count it actually
/// reached. Built from the send's own reply; nothing is refetched to draw it.
struct BroadcastSentCard: View {
    let sent: Broadcast

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Icon(.megaphone, size: 14, color: Nuru.goldChipText)
                Text("SENT TO EVERYONE").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                Spacer(minLength: 0)
                Text(reach).font(.nCardMeta).foregroundStyle(Nuru.ink600)
            }
            Text(sent.body)
                .font(.fraunces(15)).foregroundStyle(Nuru.navy).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.md)
        .background(Nuru.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
    }

    private var reach: String {
        let n = sent.recipientCount
        return "\(n) member" + (n == 1 ? "" : "s")
    }
}

struct BroadcastComposer: View {
    @State private var text = ""
    @State private var confirming = false
    @State private var sending = false
    @State private var sentTo: Int?
    @State private var errorText: String?
    /// The server asked us to confirm the password (§5.3). The draft survives it.
    @State private var askingPassword = false
    /// The message as it went out — shown at once from the send's own reply,
    /// with no refetch to find out what we just said.
    @State private var justSent: Broadcast?
    /// Held across a password prompt so confirm-then-retry resumes THIS send
    /// rather than starting a second one. A new id is minted only after a send
    /// actually lands.
    @State private var mutationId = UUID().uuidString
    // ✨ AI drafting + 🖼️ image attachment (sign → Cloudinary → secure_url)
    @State private var aiDrafting = false
    @State private var photoItem: PhotosPickerItem?
    @State private var uploading = false
    @State private var attachmentUrl: String?
    @State private var attachmentImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Navy explainer card — sets expectations before the composer.
            HStack(alignment: .top, spacing: 14) {
                Icon(.megaphone, size: 22, color: Color(hex: 0xE6C068))
                    .frame(width: 40, height: 40)
                    .background(Nuru.gold.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Message every member")
                        .font(.nRowTitle).kerning(-0.16).foregroundStyle(.white)
                    Text("Reaches every member as a personal message from you. Replies come back to you one-on-one.")
                        .font(.inter(11)).foregroundStyle(.white.opacity(0.7)).lineSpacing(3)
                }
                Spacer(minLength: 0)
            }
            .padding(Nuru.S.base)
            .background(
                LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            if uploading || attachmentImage != nil {
                BroadcastAttachmentThumb(image: attachmentImage, uploading: uploading) {
                    photoItem = nil; attachmentUrl = nil; attachmentImage = nil
                }
            }
            HStack(alignment: .bottom, spacing: 10) {
                TextField("", text: $text,
                          prompt: Text("Write the message every member should receive…").foregroundColor(Color(hex: 0x74808F)),
                          axis: .vertical)
                    .font(.inter(14)).foregroundStyle(Nuru.navy)
                    .lineLimit(5...10)
                    .lineSpacing(4)
                    .padding(Nuru.S.md)
                    .background(Nuru.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    .disabled(sending)
                VStack(spacing: 8) {
                    // ✨ Ask Nuru to polish (or write) the draft.
                    Button { Task { await aiAssist() } } label: {
                        Group {
                            if aiDrafting { ProgressView().tint(Nuru.navy).scaleEffect(0.7) }
                            else { Icon(.sparkles, size: 14, color: Nuru.navy) }
                        }
                        .frame(width: 38, height: 38)
                        .background(Color(hex: Nuru.tileTint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(aiDrafting || sending)
                    // 🖼️ Attach a photo — uploaded straight to Cloudinary.
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Icon(.image, size: 14, color: Color(hex: 0x9A7A2A))
                            .frame(width: 38, height: 38)
                            .background(Nuru.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
                    }
                    .disabled(uploading || sending)
                }
            }
            .onChange(of: photoItem) { _, item in
                guard item != nil else { return }
                Task { await uploadPicked() }
            }
            // The message, as sent — drawn from the send's own reply, so it
            // appears the instant it lands rather than after a refetch.
            if let sent = justSent {
                BroadcastSentCard(sent: sent)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let n = sentTo {
                HStack(spacing: 6) {
                    Icon(.checkCircle2, size: 14, color: Color(hex: 0x15803D))
                    Text("Delivered to \(n) member\(n == 1 ? "" : "s") 🎉")
                        .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x15803D))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x16A34A, alpha: 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            if let e = errorText {
                Text(e).font(.nCardMeta).foregroundStyle(Color(hex: 0xB91C1C))
                    .transition(.opacity)
            }
            Button {
                Haptics.action()
                confirming = true
            } label: {
                Group {
                    if sending {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 6) {
                            Icon(.send, size: 14, color: .white)
                            Text("Send to everyone").font(.nCardCTA).foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(storyRing, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Nuru.gold.opacity(0.5), radius: 9, y: 5)
                .opacity(canSend ? 1 : 0.45)
            }
            .buttonStyle(.pressable)
            .disabled(!canSend)
            .alert("Broadcast to all members?", isPresented: $confirming) {
                Button("Send") { Task { await send() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every member receives this as a personal message from you.")
            }
        }
        .padding(Nuru.S.base)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        // Success banner, inline errors and the attachment thumb settle in
        // rather than snapping the card's layout.
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: sentTo)
        .animation(.easeInOut(duration: 0.2), value: errorText)
        .animation(.easeInOut(duration: 0.2), value: attachmentImage == nil)
        // The server asked who is holding the phone. Confirm, then finish the
        // send that was already in flight — the draft never left the field.
        .sheet(isPresented: $askingPassword) {
            PasswordConfirmSheet(reason: "This message goes to every member in your name. Confirm your password to send it.") {
                Task { await send() }
            }
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending && !uploading && !aiDrafting
    }

    private func send() async {
        sending = true; errorText = nil; sentTo = nil
        defer { sending = false }
        do {
            // audience is deliberately NOT passed: unasked means the whole
            // church. Sending "congregation" by default is what made a broadcast
            // reach 40 of 60 — the other 19 have no congregation to be scoped to.
            let sent = try await MemberAPI.broadcast(
                body: text.trimmingCharacters(in: .whitespacesAndNewlines),
                attachmentUrl: attachmentUrl,
                msgType: attachmentUrl == nil ? "text" : "image",
                clientMutationId: mutationId)
            sentTo = sent.sent
            justSent = sent.asBroadcast   // show it as THE MESSAGE SENT, at once
            text = ""
            photoItem = nil; attachmentUrl = nil; attachmentImage = nil
            mutationId = UUID().uuidString  // the next send is a new thing to say
            Haptics.success()
        } catch let e as APIError where e.needsPasswordConfirm {
            // Not a refusal — the server is asking who is holding the phone.
            // Keep the draft and the mutation id: confirming and retrying must
            // resume THIS send, not make them write it again, and the same id
            // means a half-delivered attempt cannot double-send.
            Haptics.tap()
            askingPassword = true
        } catch {
            // The draft and photo stay; the line says why (§4).
            errorText = NuruStateCopy.sendFailureLine(error)
            Haptics.error()
        }
    }

    /// ✨ Polish the current draft with Nuru — or, when the field is empty, ask
    /// for a fresh broadcast. Fills the field with the reply; the provider being
    /// offline degrades to a friendly inline error.
    private func aiAssist() async {
        aiDrafting = true; errorText = nil
        defer { aiDrafting = false }
        let draft = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let ask = draft.isEmpty
            ? "Write a warm broadcast message from a pastor to the whole congregation (2-4 sentences). Reply with the message only."
            : "Polish this as a warm broadcast message from a pastor to all members (2-4 sentences). Reply with the message only: \(draft)"
        do {
            let reply = try await MemberAPI.assistantChat([AssistantMessage(role: "user", text: ask)])
            let polished = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            if !polished.isEmpty {
                text = polished
                Haptics.tap()
            }
        } catch {
            errorText = "Nuru couldn’t draft right now — please try again in a moment."
            Haptics.error()
        }
    }

    /// 🖼️ Load the picked photo and push its bytes straight to Cloudinary via the
    /// server-signed params (sign → multipart POST → secure_url, §4.5).
    private func uploadPicked() async {
        guard let item = photoItem else { return }
        uploading = true; errorText = nil
        defer { uploading = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else {
                throw APIError.transport("Unreadable photo.")
            }
            attachmentImage = image
            let type = item.supportedContentTypes.first
            let mime = type?.preferredMIMEType ?? "image/jpeg"
            let ext = type?.preferredFilenameExtension ?? "jpg"
            let sign = try await MemberAPI.signChatAttachment(contentType: mime)
            attachmentUrl = try await MemberAPI.uploadChatAttachment(
                sign: sign, data: data, filename: "broadcast.\(ext)", contentType: mime)
        } catch {
            photoItem = nil; attachmentUrl = nil; attachmentImage = nil
            errorText = "Couldn’t attach the photo — please try again."
            Haptics.error()
        }
    }
}

/// The removable attachment preview above the broadcast field: the picked photo
/// as a small rounded thumbnail, a spinner veil while it uploads, and an ✕ to
/// drop it before sending.
private struct BroadcastAttachmentThumb: View {
    let image: UIImage?
    let uploading: Bool
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Nuru.paper
                }
                if uploading {
                    Color.black.opacity(0.25)
                    ProgressView().tint(.white).scaleEffect(0.8)
                }
            }
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            Text(uploading ? "Uploading photo…" : "Photo attached · sent with your message")
                .font(.nCardMeta).foregroundStyle(Color(hex: 0x6A7686))
            Spacer(minLength: 0)
            if !uploading {
                Button {
                    Haptics.tap()
                    onRemove()
                } label: {
                    Icon(.x, size: 14, color: Color(hex: 0x64748B))
                        .frame(width: 26, height: 26)
                        .background(Color(hex: 0x0B1F33, alpha: 0.06), in: Circle())
                        .frame(width: 44, height: 44)     // full-size hit target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// Rounded-square avatar: real photo when available, tinted-gradient initials otherwise.
private struct SquircleAvatar: View {
    let url: String?
    let name: String
    let tint: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [tint, tint.opacity(0.71)], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let url, let u = URL(string: url) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { initialsText }
                }
            } else {
                initialsText
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: tint.opacity(0.35), radius: 7, y: 5)
    }

    private var initialsText: some View {
        Text(initials).font(.inter(15, .semibold)).foregroundStyle(.white)
    }
    private var initials: String {
        let parts = name.split(separator: " ").filter { $0.first?.isLetter == true }
        guard let f = parts.first?.first else { return "?" }
        if parts.count > 1, let l = parts.last?.first { return "\(f)\(l)".uppercased() }
        return String(name.prefix(2)).uppercased()
    }
}

/// A person's line in the people list (§8.1 rule 8): never a raw role
/// ("Student · …" read like data). A member's line is their congregation,
/// or nothing — never the word "Member" (Android's round 2 settled it; the
/// level is already on the avatar's badge). The church's staff read as
/// what they are to a member, with the congregation when there is one.
enum PersonWords {
    static func subtitle(role: String?, congregation: String?) -> String? {
        let c = congregation.flatMap { $0.isEmpty ? nil : $0 }
        let who: String?
        switch (role ?? "").lowercased() {
        case "instructor": who = "Teacher"
        case "admin", "superadmin": who = "Church staff"
        default: who = nil
        }
        switch (who, c) {
        case let (w?, c?): return "\(w) · \(c)"
        case let (w?, nil): return w
        case let (nil, c?): return c
        default: return nil
        }
    }
}

/// Your spaces' words when there are none (final walk C4): "follow one
/// below" only while there is one below to follow.
enum SpaceWords {
    static func none(canFollow: Bool) -> String {
        canFollow ? "No spaces yet — follow one below to get started."
                  : "No spaces yet. When the church opens one, you can follow it here."
    }
}

extension ChatConversation {
    /// The room's name as a member reads it (§8.1 rule 8; final walk C4): the
    /// server names a cell's room "<cell> cell", which read "Dev Cell A cell"
    /// for a cell already called a Cell. The doubled word goes.
    var shownTitle: String? { title.map(Self.shownTitle) }

    static func shownTitle(_ raw: String) -> String {
        let t = raw.trimmingCharacters(in: .whitespaces)
        guard t.lowercased().hasSuffix(" cell") else { return t }
        let head = String(t.dropLast(5))
        let words = head.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        return words.contains("cell") ? head : t
    }
}
