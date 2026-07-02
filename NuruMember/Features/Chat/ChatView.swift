// Chat — "Nuru Connect" inbox, the native port of the Figma ChatTab. A cream
// header (time-based greeting overline, serif title, bell → notifications), a
// white search bar, the "Quick help from Nuru" AI launcher (gradient ring, orb,
// live dot), the italic "Verse for today" ribbon, and a capsule segment control
// (#My Space · DM · My Groups with counts). Each segment renders one grouped
// white card of rows: spaces (# avatar, author preview, member dots, Active
// pill), DMs (stories row, real-or-initials avatars, unread badges, read ticks)
// and groups. A gold pen FAB opens the "Start something" compose sheet.
import SwiftUI

@MainActor
final class ChatInboxViewModel: ObservableObject {
    @Published var inbox: ChatInbox?
    @Published var people: [ChatPerson] = []
    @Published var verse: (text: String, reference: String, version: String)?
    @Published var loading = true
    @Published var error: String?
    @Published var busyPersonId: String?    // person whose DM is being created
    @Published var joiningSpaceId: String?  // discover space being followed

    var conversations: [ChatConversation] { inbox?.conversations ?? [] }
    var spaces: [ChatConversation] { conversations.filter { $0.kind == "space" } }
    var dms: [ChatConversation] { conversations.filter { $0.kind == "dm" } }
    var groups: [ChatConversation] { conversations.filter { $0.kind == "group" } }
    var discover: [DiscoverSpace] { inbox?.discoverSpaces ?? [] }
    var totalUnread: Int { conversations.reduce(0) { $0 + $1.unread } }

    func load() async {
        loading = true; error = nil
        async let inboxReq = try? MemberAPI.chatInbox()
        async let peopleReq = try? MemberAPI.chatPeople()
        async let verseReq = try? MemberAPI.homeVerse()

        if let i = await inboxReq { inbox = i } else { error = "Couldn't load your chats." }
        if let p = await peopleReq { people = p }
        if let v = await verseReq {
            if let t = v.text, !t.isEmpty { verse = (t, v.reference, v.version) }
            else { verse = (defaultVerseText, v.reference, v.version) }
        }
        loading = false
    }

    /// POST /chat/dms then refresh the inbox; returns the conversation to open.
    func startDm(with person: ChatPerson) async -> ChatConversation? {
        guard busyPersonId == nil else { return nil }
        busyPersonId = person.userId
        defer { busyPersonId = nil }
        guard let id = try? await MemberAPI.createDm(peerUserId: person.userId) else { return nil }
        if let i = try? await MemberAPI.chatInbox() { inbox = i }
        // Prefer the real inbox row (preview, unread); fall back to a stub the
        // thread screen can hydrate from GET /chat/conversations/{id}.
        return conversations.first { $0.conversationId == id } ?? ChatConversation(
            conversationId: id, kind: "dm", isPublic: false, title: person.fullName,
            topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
            lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: person.avatarUrl)
    }

    /// POST /chat/spaces/{id}/join then refresh — the space moves to "your spaces".
    func follow(_ space: DiscoverSpace) async {
        guard joiningSpaceId == nil else { return }
        joiningSpaceId = space.conversationId
        defer { joiningSpaceId = nil }
        guard (try? await MemberAPI.joinChatSpace(space.conversationId)) != nil else { return }
        if let i = try? await MemberAPI.chatInbox() { inbox = i }
    }

    private let defaultVerseText = "“Carry each other’s burdens, and in this way you will fulfill the law of Christ.”"
}

private enum ChatSegment: Int, CaseIterable { case space, dm, group, broadcast }
private enum ChatDest: Hashable { case notifications }

// Figma STORY_RING — the warm gold gradient used for rings, badges and the FAB.
private let storyRing = LinearGradient(
    colors: [Color(hex: 0xE6C068), Color(hex: 0xC89B3C), Color(hex: 0xB07D2E)],
    startPoint: .topLeading, endPoint: .bottomTrailing)

// Per-row tint cycle (backend sends no space colour) — mirrors the mock palette.
private let rowTints: [UInt32] = [0xC89B3C, 0x6366F1, 0x0EA5E9, 0x16A34A, 0xDB2777, 0x0D9488]
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
    else { f.dateFormat = "d MMM" }
    return f.string(from: d)
}

struct ChatView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = ChatInboxViewModel()
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
                            aiCard
                            if query.isEmpty { verseCard }
                            segmentControl
                            segmentBody
                        }
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, Nuru.S.screen)
                        .padding(.bottom, Nuru.tabBarSpace)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .background(Nuru.paper.ignoresSafeArea())
                fab
                if composeOpen { composeSheet }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: composeOpen)
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showNuru) { NuruAssistantView() }
            .refreshable { await vm.load() }
            .navigationDestination(for: ChatConversation.self) { ChatThreadView(conversation: $0) }
            .navigationDestination(for: ChatDest.self) { _ in NotificationsView() }
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
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Icon(.sparkle, size: 12, color: Color(hex: 0x9A7A2A))
                        Text("\(greeting.uppercased()) · \(firstName.uppercased())")
                            .font(.inter(11, .semibold)).kerning(2.4).foregroundStyle(Color(hex: 0x9A7A2A))
                    }
                    Text("Nuru Connect")
                        .font(.fraunces(30, .semibold)).kerning(-0.6).foregroundStyle(Nuru.navy)
                        .padding(.top, Nuru.S.md)
                    Text(vm.totalUnread > 0 ? "\(vm.totalUnread) unread · \(vm.spaces.count) spaces" : "You’re all caught up")
                        .font(.inter(13)).foregroundStyle(Color(hex: 0x68758A))
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
                bellButton
            }
            searchBar.padding(.top, Nuru.S.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
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

    // White tile bell → NotificationsView; glowing gold dot when anything is unread.
    private var bellButton: some View {
        Button { path.append(ChatDest.notifications) } label: {
            Icon(.bell, size: 19, color: Nuru.navy)
                .frame(width: 44, height: 44)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if vm.totalUnread > 0 {
                        Circle().fill(Nuru.gold)
                            .frame(width: 8, height: 8)
                            .shadow(color: Nuru.gold.opacity(0.9), radius: 4)
                            .padding(10)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.search, size: 16, color: Color(hex: 0x9CA3AF))
            TextField("", text: $query, prompt: Text("Search spaces, people, messages").foregroundColor(Color(hex: 0x9CA3AF)))
                .font(.inter(14)).foregroundStyle(Nuru.navy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Icon(.x, size: 14, color: Color(hex: 0x9CA3AF)) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Nuru.S.base)
        .frame(height: 46)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: AI card ("Quick help from Nuru" — gradient ring, glows, orb, live dot)

    private var aiCard: some View {
        Button { showNuru = true } label: {
            HStack(spacing: 14) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(RadialGradient(colors: [Color(hex: 0xC4B5FD), Color(hex: 0x7C3AED), Color(hex: 0x2A1259)],
                                             center: UnitPoint(x: 0.32, y: 0.28), startRadius: 2, endRadius: 46))
                        .frame(width: 48, height: 48)
                        .overlay(Icon(.sparkles, size: 20, color: .white))
                        .shadow(color: Color(hex: 0x7C3AED).opacity(0.65), radius: 8, y: 5)
                    Circle().fill(Color(hex: 0x34D399)).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color(hex: 0x0A1628), lineWidth: 2))
                        .shadow(color: Color(hex: 0x34D399).opacity(0.9), radius: 4)
                        .offset(x: 2, y: -2)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("Quick help from Nuru")
                            .font(.fraunces(16, .semibold)).kerning(-0.16).foregroundStyle(.white)
                        Text("AI").font(.inter(8, .heavy)).kerning(1.1).foregroundStyle(Color(hex: 0x0A1628))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(LinearGradient(colors: [Color(hex: 0xA78BFA), Color(hex: 0x34D399)],
                                                       startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                    }
                    Text("The AI assistant · \(vm.totalUnread) updates across \(vm.spaces.count) spaces")
                        .font(.inter(10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: .white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.10), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [Color(hex: 0x2A1259), Color(hex: 0x0A1628), Color(hex: 0x053F30)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(alignment: .topLeading) {
                        Circle().fill(Color(hex: 0x7C3AED).opacity(0.5)).frame(width: 160, height: 160).blur(radius: 40).offset(x: -40, y: -48)
                    }
                    .overlay(alignment: .bottomTrailing) {
                        Circle().fill(Color(hex: 0x10B981).opacity(0.4)).frame(width: 160, height: 160).blur(radius: 40).offset(x: 8, y: 56)
                    }
            )
            .clipShape(RoundedRectangle(cornerRadius: 24.5, style: .continuous))
            .padding(1.5)
            .background(LinearGradient(colors: [Color(hex: 0xA78BFA), Color(hex: 0xC89B3C), Color(hex: 0x34D399)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: 0x4C1D95).opacity(0.45), radius: 18, y: 10)
        }
        .buttonStyle(.plain)
    }

    // MARK: Verse for today (gold ribbon, italic serif verse)

    private var verseCard: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            Icon(.quote, size: 15, color: Nuru.gold)
                .frame(width: 32, height: 32)
                .background(Nuru.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text("VERSE FOR TODAY").font(.inter(9, .bold)).kerning(1.6).foregroundStyle(Color(hex: 0x9A7A2A))
                Text(vm.verse?.text ?? "“Carry each other’s burdens, and in this way you will fulfill the law of Christ.”")
                    .font(.fraunces(13).italic()).foregroundStyle(Nuru.navy).lineSpacing(4)
                Text(vm.verse?.reference ?? "Galatians 6:2")
                    .font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x9A7A2A))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [Nuru.gold.opacity(0.08), Nuru.gold.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.gold.opacity(0.2), lineWidth: 1))
    }

    // MARK: Segmented control (capsule pills, navy gradient active)

    private var segmentControl: some View {
        HStack(spacing: 4) {
            segmentButton(.space, "#My Space", vm.spaces.count)
            segmentButton(.dm, "DM", vm.dms.count)
            segmentButton(.group, "My Groups", vm.groups.count)
            if isStaff { broadcastSegmentButton }
        }
        .padding(4)
        .background(Color.white.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    /// Staff gate for the Broadcast composer — mirrors the server's
    /// requireRole("Instructor"): any role above Student (Instructor, Admin,
    /// SuperAdmin). The server 403s Students regardless; this only hides the UI.
    private var isStaff: Bool {
        guard let role = auth.profile?.role, !role.isEmpty else { return false }
        return role != "Student"
    }

    // Megaphone pill — 4th segment, staff only (no count chip; it's a composer).
    private var broadcastSegmentButton: some View {
        let selected = segment == .broadcast
        return Button { withAnimation(.easeInOut(duration: 0.15)) { segment = .broadcast } } label: {
            HStack(spacing: 5) {
                Icon(.megaphone, size: 12, color: selected ? Nuru.gold : Color(hex: 0x68758A))
                Text("Broadcast").font(.inter(12, .semibold)).foregroundStyle(selected ? Color.white : Color(hex: 0x68758A))
            }
            .frame(maxWidth: .infinity)
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

    private func segmentButton(_ seg: ChatSegment, _ label: String, _ count: Int) -> some View {
        let selected = segment == seg
        return Button { withAnimation(.easeInOut(duration: 0.15)) { segment = seg } } label: {
            HStack(spacing: 5) {
                Text(label).font(.inter(12, .semibold)).foregroundStyle(selected ? Color.white : Color(hex: 0x68758A))
                Text("\(count)").font(.inter(10, .bold))
                    .foregroundStyle(selected ? Nuru.navy : Color(hex: 0x8A93A0))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .frame(minWidth: 18)
                    .background(selected ? Nuru.gold : Nuru.surface, in: Capsule())
            }
            .frame(maxWidth: .infinity)
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
            ProgressView().tint(Nuru.gold).padding(.top, Nuru.S.xl)
        } else if vm.inbox == nil {
            Text(vm.error ?? "Couldn't load your chats.").font(.nBody).foregroundStyle(Nuru.muted).padding(.top, Nuru.S.xl)
        } else {
            switch segment {
            case .space: spaceList
            case .dm: dmList
            case .group: groupList
            case .broadcast:
                if isStaff { BroadcastComposer(peopleCount: vm.people.count) }
            }
        }
    }

    private func matches(_ c: ChatConversation) -> Bool {
        guard !query.isEmpty else { return true }
        let q = query.lowercased()
        return (c.title ?? "").lowercased().contains(q)
            || (c.lastBody ?? "").lowercased().contains(q)
            || (c.lastAuthor ?? "").lowercased().contains(q)
    }

    private var spaceList: some View {
        let items = vm.spaces.filter(matches)
        let discoverable = filteredDiscover
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel(hash: true, "YOUR SPACES")
            if items.isEmpty {
                emptyCard(query.isEmpty
                    ? "No spaces yet — follow one below to get started."
                    : "No spaces match your search.")
            } else {
                groupedCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                        NavigationLink(value: c) { SpaceRow(c: c, index: idx, divider: idx > 0) }.buttonStyle(.plain)
                    }
                }
            }
            if !discoverable.isEmpty {
                sectionLabel(hash: true, "DISCOVER SPACES").padding(.top, 6)
                groupedCard {
                    ForEach(Array(discoverable.enumerated()), id: \.element.id) { idx, s in
                        DiscoverSpaceRow(space: s, index: idx, divider: idx > 0,
                                         joining: vm.joiningSpaceId == s.conversationId) {
                            Task { await vm.follow(s) }
                        }
                    }
                }
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
            if query.isEmpty && !vm.dms.isEmpty { storiesRow.padding(.bottom, 10) }
            sectionLabel(icon: .users, "DIRECT MESSAGES")
            if items.isEmpty {
                emptyCard(query.isEmpty
                    ? "No direct messages yet — start a conversation with someone below."
                    : "No conversations match your search.")
            } else {
                groupedCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                        NavigationLink(value: c) { ConversationRow(c: c, index: idx, divider: idx > 0) }.buttonStyle(.plain)
                    }
                }
            }
            if !vm.people.isEmpty {
                sectionLabel(icon: .users, "PEOPLE").padding(.top, 6)
                if directory.isEmpty {
                    emptyCard("No people match your search.")
                } else {
                    groupedCard {
                        ForEach(Array(directory.enumerated()), id: \.element.id) { idx, p in
                            PersonRow(person: p, index: idx, divider: idx > 0,
                                      busy: vm.busyPersonId == p.userId) { startDm(p) }
                        }
                    }
                }
            }
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
        Task {
            if let c = await vm.startDm(with: person) { path.append(c) }
        }
    }

    private var groupList: some View {
        let items = vm.groups.filter(matches)
        return VStack(alignment: .leading, spacing: 10) {
            sectionLabel(icon: .users, "YOUR GROUPS")
            if items.isEmpty {
                emptyCard(query.isEmpty
                    ? "You’re not in any group rooms yet — they appear when your cell is set up."
                    : "No groups match your search.")
            } else {
                groupedCard {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                        NavigationLink(value: c) { ConversationRow(c: c, index: idx, divider: idx > 0) }.buttonStyle(.plain)
                    }
                }
            }
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
                        ZStack { Circle().fill(storyRing); Icon(.plus, size: 13, color: .white) }
                            .frame(width: 24, height: 24)
                            .overlay(Circle().stroke(Nuru.paper, lineWidth: 3))
                            .shadow(color: Nuru.gold.opacity(0.5), radius: 5, y: 2)
                            .offset(x: 2, y: 2)
                    }
                    Text("Your note").font(.inter(10, .medium)).foregroundStyle(Color(hex: 0x8A93A0))
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
                            Text(firstWord(c.title)).font(.inter(10, .medium)).foregroundStyle(Nuru.navy).lineLimit(1)
                        }
                        .frame(width: 60)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: FAB + compose sheet

    private var fab: some View {
        Button { composeOpen = true } label: {
            Icon(.pencil, size: 22, color: .white)
                .frame(width: 56, height: 56)
                .background(storyRing, in: Circle())
                .shadow(color: Nuru.gold.opacity(0.55), radius: 12, y: 8)
                .shadow(color: Color(hex: 0x0B1F33, alpha: 0.25), radius: 5, y: 3)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Nuru.S.screen)
        .padding(.bottom, Nuru.tabBarSpace - 18)
    }

    // Figma ComposeSheet — dark scrim, "Start something", three segment shortcuts.
    // "New DM" jumps to the DM segment (PEOPLE directory below the rows) and
    // "Browse spaces" to the space segment (DISCOVER SPACES below your spaces).
    private var composeSheet: some View {
        ZStack(alignment: .bottom) {
            Color(hex: 0x0B1F33, alpha: 0.45)
                .ignoresSafeArea()
                .onTapGesture { composeOpen = false }
            VStack(spacing: 8) {
                HStack {
                    Text("Start something").font(.fraunces(17, .semibold)).foregroundStyle(.white)
                    Spacer(minLength: 0)
                    Button { composeOpen = false } label: {
                        Icon(.x, size: 16, color: .white)
                            .frame(width: 32, height: 32)
                            .background(Color.white.opacity(0.15), in: Circle())
                    }.buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
                VStack(spacing: 0) {
                    composeAction("New direct message", "Message a person 1:1", divider: false) {
                        Icon(.pencil, size: 19, color: Nuru.gold)
                    } action: { segment = .dm }
                    composeAction("New group", "Start a private group chat", divider: true) {
                        Icon(.users, size: 19, color: Nuru.gold)
                    } action: { segment = .group }
                    composeAction("Browse spaces", "Find & join a community space", divider: true) {
                        Image(systemName: "safari").font(.system(size: 18)).foregroundStyle(Nuru.gold)
                    } action: { segment = .space }
                }
                .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                .nuruShadow()
            }
            .padding(.horizontal, Nuru.S.md)
            .padding(.bottom, Nuru.S.md)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
        .zIndex(2)
    }

    private func composeAction(_ title: String, _ sub: String, divider: Bool,
                               @ViewBuilder icon: () -> some View, action: @escaping () -> Void) -> some View {
        Button { action(); composeOpen = false } label: {
            HStack(spacing: 14) {
                icon()
                    .frame(width: 44, height: 44)
                    .background(Nuru.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.inter(14, .semibold)).foregroundStyle(Nuru.navy)
                    Text(sub).font(.inter(11.5)).foregroundStyle(Color(hex: 0x9AA3AF))
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 16, color: Color(hex: 0xCBD5E1))
            }
            .padding(Nuru.S.base)
            .overlay(alignment: .top) { if divider { Rectangle().fill(Nuru.border).frame(height: 1) } }
        }
        .buttonStyle(.plain)
    }

    // MARK: Shared bits

    private func sectionLabel(hash: Bool = false, icon: Lucide? = nil, _ text: String) -> some View {
        HStack(spacing: 6) {
            if hash { Text("#").font(.inter(12, .bold)).foregroundStyle(Color(hex: 0xB08A1E)) }
            else if let icon { Icon(icon, size: 12, color: Color(hex: 0xB08A1E)) }
            Text(text).font(.inter(10, .bold)).kerning(2).foregroundStyle(Color(hex: 0xB08A1E))
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

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.inter(12)).foregroundStyle(Color(hex: 0x9CA3AF)).lineSpacing(3)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32).padding(.horizontal, Nuru.S.base)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Derived

    private var firstName: String { (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend" }
    private var myInitials: String {
        let parts = (auth.profile?.fullName ?? "").split(separator: " ")
        guard let f = parts.first?.first else { return "ME" }
        if parts.count > 1, let l = parts.last?.first { return "\(f)\(l)".uppercased() }
        return String(f).uppercased()
    }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }
    private func firstWord(_ s: String?) -> String { (s ?? "—").split(separator: " ").first.map(String.init) ?? "—" }
}

// MARK: - Row chrome shared by space/DM/group rows

// WhatsApp-style double tick shown on rows that are fully read.
private struct DoubleCheck: View {
    var body: some View {
        ZStack {
            Icon(.check, size: 12, color: Color(hex: 0xBCC4CE)).offset(x: -3)
            Icon(.check, size: 12, color: Color(hex: 0xBCC4CE)).offset(x: 3)
        }
        .frame(width: 20, height: 14)
    }
}

// Tiny gold-gradient unread pill.
private struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text("\(count)").font(.inter(9, .bold)).foregroundStyle(.white)
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

// Overlapping member dots + count chip (Figma MemberStack).
private struct MemberStack: View {
    let tint: Color
    let count: Int
    var body: some View {
        HStack(spacing: -8) {
            ForEach(0..<min(3, max(1, count)), id: \.self) { i in
                Circle()
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.6)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 22, height: 22)
                    .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    .zIndex(Double(3 - i))
            }
            Text(count > 999 ? String(format: "%.1fk", Double(count) / 1000) : "\(count)")
                .font(.inter(9, .bold)).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 6)
                .frame(height: 22)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        }
    }
}

// One-line preview — voice/photo affordances, author prefix for multi rooms.
private struct RowPreview: View {
    let c: ChatConversation
    let showAuthor: Bool
    private var unread: Bool { c.unread > 0 }
    var body: some View {
        HStack(spacing: 4) {
            if c.lastType == "voice" {
                Icon(.mic, size: 11, color: Nuru.gold)
                Text("Voice message").font(.inter(10)).foregroundStyle(bodyColor)
            } else if c.lastType == "image" {
                Icon(.image, size: 11, color: Nuru.gold)
                Text("Photo").font(.inter(10)).foregroundStyle(bodyColor)
            } else {
                (authorText + Text(c.lastBody ?? "No messages yet"))
                    .font(.inter(10)).foregroundStyle(bodyColor)
            }
        }
        .lineLimit(1)
    }
    private var authorText: Text {
        guard showAuthor, let a = c.lastAuthor, !a.isEmpty else { return Text("") }
        return Text("\(a): ").fontWeight(.semibold).foregroundColor(unread ? Nuru.navy : Color(hex: 0x68758A))
    }
    private var bodyColor: Color { unread ? Color(hex: 0x33445A) : Color(hex: 0x8A93A0) }
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
                    Spacer(minLength: 4)
                    Text(chatTime(c.lastAt))
                        .font(.inter(10, unread ? .bold : .medium))
                        .foregroundStyle(unread ? Nuru.gold : Color(hex: 0x9AA3AF))
                }
                HStack(spacing: 8) {
                    RowPreview(c: c, showAuthor: true)
                    Spacer(minLength: 4)
                    if unread { UnreadBadge(count: c.unread) } else { DoubleCheck() }
                }
                HStack {
                    MemberStack(tint: tint, count: c.memberCount)
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
            Text("Active").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x15803D))
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
                Icon(.users, size: 21, color: .white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(colors: [tint, tint.opacity(0.71)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .shadow(color: tint.opacity(0.35), radius: 7, y: 5)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(c.title ?? "Conversation")
                        .font(.inter(12, unread ? .semibold : .medium)).kerning(-0.12)
                        .foregroundStyle(Nuru.navy).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(chatTime(c.lastAt))
                        .font(.inter(10, unread ? .bold : .medium))
                        .foregroundStyle(unread ? Nuru.gold : Color(hex: 0x9AA3AF))
                }
                HStack(spacing: 8) {
                    RowPreview(c: c, showAuthor: c.kind != "dm")
                    Spacer(minLength: 4)
                    if unread { UnreadBadge(count: c.unread) } else { DoubleCheck() }
                }
            }
        }
        .modifier(RowChrome(unread: unread, divider: divider))
    }
}

// MARK: - Directory person row (PEOPLE section — tap to start/open the DM)

private struct PersonRow: View {
    let person: ChatPerson
    let index: Int
    let divider: Bool
    let busy: Bool
    let action: () -> Void
    private var tint: Color { rowTint(index + 1) }

    var body: some View {
        Button(action: action) {
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
                    Text(subtitle)
                        .font(.inter(10)).foregroundStyle(Color(hex: 0x8A93A0)).lineLimit(1)
                }
                Spacer(minLength: 4)
                if busy {
                    ProgressView().tint(Nuru.gold).scaleEffect(0.8)
                } else {
                    Icon(.messageCircle, size: 15, color: Nuru.gold)
                        .frame(width: 32, height: 32)
                        .background(Nuru.gold.opacity(0.10), in: Circle())
                }
            }
            .modifier(RowChrome(unread: false, divider: divider))
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private var subtitle: String {
        let role = (person.role?.isEmpty == false) ? person.role! : "Member"
        if let c = person.congregation, !c.isEmpty { return "\(role) · \(c)" }
        return role
    }

    // MARK: Achievement flair — public aggregates only; every piece disappears
    // gracefully when the server doesn't send it (old servers / no data).

    /// Micro game-rank frame docked on the avatar's bottom-trailing corner.
    @ViewBuilder private var levelChip: some View {
        if let lvl = person.level, lvl > 0 {
            Text("L\(lvl)")
                .font(.inter(8, .bold)).foregroundStyle(Nuru.navy)
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
            let icons = Array((person.badgeIcons ?? []).prefix(3))
            HStack(spacing: -4) {
                ForEach(icons.indices, id: \.self) { i in
                    Text(icons[i]).font(.system(size: 10)).lineLimit(1)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(.white))
                        .overlay(Circle().strokeBorder(Nuru.gold.opacity(0.5), lineWidth: 0.5))
                }
                if count > icons.count {
                    Text("+\(count - icons.count)")
                        .font(.inter(7, .semibold)).foregroundStyle(Color(hex: 0xA8761A))
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Nuru.goldTint))
                        .overlay(Circle().strokeBorder(Nuru.gold.opacity(0.5), lineWidth: 0.5))
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
                Icon(.award, size: 9, color: Nuru.gold)
            }
            .fixedSize()
        }
    }
}

// MARK: - Discover space row (public spaces to follow — gold Follow button)

private struct DiscoverSpaceRow: View {
    let space: DiscoverSpace
    let index: Int
    let divider: Bool
    let joining: Bool
    let follow: () -> Void
    private var tint: Color { rowTint(index + 2) }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
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
                    .font(.inter(10)).foregroundStyle(Color(hex: 0x8A93A0)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button(action: follow) {
                Group {
                    if joining {
                        ProgressView().tint(.white).scaleEffect(0.7)
                    } else {
                        HStack(spacing: 4) {
                            Icon(.plus, size: 11, color: .white)
                            Text("Follow").font(.inter(11, .bold)).foregroundStyle(.white)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 30)
                .background(storyRing, in: Capsule())
                .shadow(color: Nuru.gold.opacity(0.45), radius: 5, y: 3)
            }
            .buttonStyle(.plain)
            .disabled(joining)
        }
        .modifier(RowChrome(unread: false, divider: divider))
    }

    private var subtitle: String {
        let members = "\(space.memberCount) member\(space.memberCount == 1 ? "" : "s")"
        if let t = space.topic, !t.isEmpty { return "\(t) · \(members)" }
        if let c = space.category, !c.isEmpty { return "\(c) · \(members)" }
        return "Public space · \(members)"
    }
}

// MARK: - Broadcast composer (staff only — ONE message → every member as a DM)

// The Broadcast segment body: an inspiring composer card. What the admin writes
// here is fanned out server-side (POST /chat/broadcast) as an individual DM to
// every member of the congregation — replies arrive back as normal 1:1 threads.
private struct BroadcastComposer: View {
    let peopleCount: Int
    @State private var text = ""
    @State private var confirming = false
    @State private var sending = false
    @State private var sentTo: Int?
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Icon(.megaphone, size: 19, color: .white)
                    .frame(width: 44, height: 44)
                    .background(storyRing, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Nuru.gold.opacity(0.45), radius: 7, y: 4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reach every member")
                        .font(.fraunces(19, .semibold)).kerning(-0.3).foregroundStyle(Nuru.navy)
                    Text("BROADCAST · STAFF ONLY")
                        .font(.inter(9, .bold)).kerning(1.6).foregroundStyle(Color(hex: 0x9A7A2A))
                }
            }
            TextField("", text: $text,
                      prompt: Text("Write the message every member should receive…").foregroundColor(Color(hex: 0x9CA3AF)),
                      axis: .vertical)
                .font(.inter(14)).foregroundStyle(Nuru.navy)
                .lineLimit(5...10)
                .lineSpacing(4)
                .padding(Nuru.S.md)
                .background(Nuru.paper, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                .disabled(sending)
            Text("Delivers as a personal message to \(peopleCount) member\(peopleCount == 1 ? "" : "s") · replies come back to you individually")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x8A93A0)).lineSpacing(3)
            if let n = sentTo {
                HStack(spacing: 6) {
                    Icon(.checkCircle2, size: 14, color: Color(hex: 0x15803D))
                    Text("Sent to \(n) member\(n == 1 ? "" : "s") ✓")
                        .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x15803D))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: 0x16A34A, alpha: 0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let e = errorText {
                Text(e).font(.inter(11)).foregroundStyle(Color(hex: 0xB91C1C))
            }
            Button { confirming = true } label: {
                Group {
                    if sending {
                        ProgressView().tint(.white)
                    } else {
                        HStack(spacing: 6) {
                            Icon(.send, size: 13, color: .white)
                            Text("Send to all").font(.inter(13, .bold)).foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(storyRing, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: Nuru.gold.opacity(0.5), radius: 9, y: 5)
                .opacity(canSend ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .confirmationDialog("Send to \(peopleCount) member\(peopleCount == 1 ? "" : "s")?",
                                isPresented: $confirming, titleVisibility: .visible) {
                Button("Send to all — this can’t be undone", role: .destructive) { Task { await send() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every member receives this as a personal message from you. There is no way to unsend it.")
            }
        }
        .padding(Nuru.S.base)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !sending
    }

    private func send() async {
        sending = true; errorText = nil; sentTo = nil
        defer { sending = false }
        do {
            let n = try await MemberAPI.broadcast(body: text.trimmingCharacters(in: .whitespacesAndNewlines))
            sentTo = n
            text = ""
        } catch {
            errorText = "Couldn’t send the broadcast — please try again."
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
