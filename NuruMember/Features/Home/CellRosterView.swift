// The cell roster — the people behind CellInfoView's faces rail. One screen,
// two truths, and the server decides which one you get (GET /me/cell/members):
//
//   • EVERY member sees the PEOPLE — face, name, who leads the cell, which row
//     is theirs, and a "…" menu that opens the conversation.
//   • The cell's SHEPHERD additionally sees each person's standing — score,
//     attendance over the gatherings this cell actually held, and a risk band —
//     because `can_shepherd` came back true and the payload carried those
//     fields. A member's pastoral standing is never shipped to their peers, so
//     an ordinary roster simply has nothing to draw (§5.4).
//
// Nothing here is invented: a member with no engagement row shows "—" rather
// than a zero, and a cell that has never met says so instead of printing 0/0.
import SwiftUI

/// What tapping "…" can honestly offer for one person — derived from the chat
/// module's own connection state (Chat Redesign C1/C2, "no unsolicited DMs"),
/// so the roster never ships a Message button that 403s.
enum CellRosterMessageState: Equatable {
    /// A thread already exists, or the pair are connected — messaging works.
    case message
    /// Not connected yet — the honest action is to ask, exactly as the Chat
    /// tab's people directory does.
    case connect
    case requestSent
    case wantsToConnect
    case blocked
}

@MainActor
final class CellRosterViewModel: ObservableObject {
    @Published var roster: CellRoster?
    @Published var loading = true
    @Published var error: String?

    // The chat module's state, read-only — what makes the "…" menu honest.
    @Published private(set) var conversations: [ChatConversation] = []
    @Published private(set) var connections: [ConnectionRow] = []
    @Published private(set) var outgoingRequests: [ConnectionRequestRow] = []
    @Published private(set) var incomingRequests: [ConnectionRequestRow] = []

    /// The row whose Message/Connect tap is in flight.
    @Published var busyUserId: String?
    /// The freshly opened DM, pushed programmatically.
    @Published var openDm: ChatConversation?
    /// Set when POST /chat/dms answers 403 CONSENT_REQUIRED for someone the
    /// cached connection lists hadn't flagged — offer the request, don't fail.
    @Published var consentPrompt: CellRosterMember?
    /// Quiet inline notice for a failed open.
    @Published var notice: String?

    var canShepherd: Bool { roster?.canShepherd ?? false }
    var cellName: String { roster?.cell?.name ?? "Your cell" }
    var isEmpty: Bool { (roster?.members ?? []).isEmpty }

    /// Member view: the server already ordered leader-first, so leave it alone.
    /// Shepherd view: re-sort by who needs attention — lowest score first, the
    /// scoreless last (a missing score is not a low one), name as tiebreak.
    var people: [CellRosterMember] {
        let m = roster?.members ?? []
        guard canShepherd else { return m }
        return m.sorted { a, b in
            let (x, y) = (a.score, b.score)
            switch (x, y) {
            case let (l?, r?) where l != r: return l < r
            case (nil, _?): return false
            case (_?, nil): return true
            default: return a.fullName.localizedCaseInsensitiveCompare(b.fullName) == .orderedAscending
            }
        }
    }

    /// The gathering count every attendance line is measured against — nil
    /// when this cell has never met (so the screen says so rather than "0 of 0").
    var meetingsCounted: Int? {
        (roster?.members ?? []).compactMap { $0.attendance?.of }.max().flatMap { $0 > 0 ? $0 : nil }
    }

    func load() async {
        loading = true; error = nil
        // The roster is the screen; the four chat reads are best-effort colour
        // for the "…" menu and must never fail the load.
        async let rosterReq = try? MemberAPI.cellRoster()
        async let inboxReq = try? MemberAPI.chatInbox()
        async let connectionsReq = try? MemberAPI.listConnections()
        async let outgoingReq = try? MemberAPI.listConnectionRequests(direction: "outgoing")
        async let incomingReq = try? MemberAPI.listConnectionRequests(direction: "incoming")

        roster = await rosterReq
        conversations = (await inboxReq)?.conversations ?? []
        connections = await connectionsReq ?? []
        outgoingRequests = await outgoingReq ?? []
        incomingRequests = await incomingReq ?? []
        if roster == nil { error = "Couldn't load your cell roster." }
        loading = false
    }

    // MARK: the "…" menu — only ever offers what actually works

    /// The existing 1:1 with this person, if the inbox has one. Matched on the
    /// authoritative peer id first, then the DM title (older inbox rows) — the
    /// same ladder MentorViewModel.findDm climbs. Discipler threads count: they
    /// are `kind == "dm"` too, and the server returns an existing thread
    /// regardless of consent.
    func existingDm(for m: CellRosterMember) -> ChatConversation? {
        let dms = conversations.filter { $0.kind == "dm" }
        return dms.first { $0.peerUserId == m.userId }
            ?? dms.first {
                $0.title?.compare(m.fullName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
    }

    func messageState(for m: CellRosterMember) -> CellRosterMessageState {
        if existingDm(for: m) != nil { return .message }
        if connections.contains(where: { $0.userId == m.userId && $0.status == "blocked" }) { return .blocked }
        if connections.contains(where: { $0.userId == m.userId && $0.status == "accepted" }) { return .message }
        if outgoingRequests.contains(where: { $0.userId == m.userId }) { return .requestSent }
        if incomingRequests.contains(where: { $0.userId == m.userId }) { return .wantsToConnect }
        return .connect
    }

    /// Open (or create — the server dedupes) the 1:1 and hand it back to push.
    func openMessage(with m: CellRosterMember) async -> ChatConversation? {
        if let dm = existingDm(for: m) { openDm = dm; return dm }
        guard busyUserId == nil else { return nil }
        busyUserId = m.userId
        defer { busyUserId = nil }
        do {
            let id = try await MemberAPI.createDm(peerUserId: m.userId)
            if let inbox = try? await MemberAPI.chatInbox() { conversations = inbox.conversations }
            // Prefer the real inbox row (preview, unread); fall back to a stub
            // the thread screen hydrates from GET /chat/conversations/{id}.
            let dm = conversations.first { $0.conversationId == id } ?? ChatConversation(
                conversationId: id, kind: "dm", isPublic: false, title: m.fullName,
                topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
                lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: m.avatarUrl,
                peerUserId: m.userId)
            openDm = dm
            return dm
        } catch let err as APIError {
            // Stale cache: the lists said connected, the server says otherwise.
            if case .http(_, "CONSENT_REQUIRED", _, _) = err { consentPrompt = m }
            else { notice = "Couldn't open the chat with \(m.firstName) — please try again." }
            return nil
        } catch {
            notice = "Couldn't open the chat with \(m.firstName) — please try again."
            return nil
        }
    }

    /// POST /chat/connections/requests — the roster's honest alternative to a
    /// Message button that would be refused.
    func connect(with m: CellRosterMember) async {
        guard busyUserId == nil else { return }
        busyUserId = m.userId
        defer { busyUserId = nil }
        _ = try? await MemberAPI.requestConnection(userId: m.userId)
        if let out = try? await MemberAPI.listConnectionRequests(direction: "outgoing") { outgoingRequests = out }
    }
}

struct CellRosterView: View {
    @StateObject private var vm = CellRosterViewModel()
    @Environment(\.dismiss) private var dismiss
    /// Programmatic push of a just-created DM (the same idiom MentorView and
    /// DisciplerDossierView use for their Message CTAs).
    @State private var openCreatedDm = false

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        if vm.loading && vm.isEmpty {
                            loadingGhost(height: 68)
                            loadingGhost(height: 68)
                            loadingGhost(height: 68)
                        } else if vm.isEmpty {
                            emptyCard
                        } else {
                            if vm.canShepherd { shepherdNote }
                            rosterCard
                            if let notice = vm.notice {
                                Text(notice).font(.nMicro).foregroundStyle(Nuru.faint)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.roster == nil { await vm.load() } }
        // Lets a Message tap push the thread from THIS stack (only the Chat
        // tab registers this destination otherwise).
        .navigationDestination(for: ChatConversation.self) { ChatThreadView(conversation: $0) }
        .navigationDestination(isPresented: $openCreatedDm) {
            if let dm = vm.openDm { ChatThreadView(conversation: dm) }
        }
        .alert(item: $vm.consentPrompt) { person in
            Alert(
                title: Text("Not connected yet"),
                message: Text("Send \(person.fullName) a connection request first — you can chat once they accept."),
                primaryButton: .default(Text("Send request")) { Task { await vm.connect(with: person) } },
                secondaryButton: .cancel())
        }
    }

    // MARK: header — the navy rounded-bottom idiom CellInfoView established

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.onNavy)
                    .frame(width: 38, height: 38)
                    .background(Nuru.navyDeep, in: Circle())
            }
            .buttonStyle(.pressable)

            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("CELL ROSTER")
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Nuru.gold)
                Text(vm.cellName)
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.nCaption).foregroundStyle(Nuru.onNavyFaint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, Nuru.S.sm)
        .padding(.bottom, Nuru.S.lg)
        .background(
            UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous)
                .fill(Nuru.navy)
                .ignoresSafeArea(edges: .top)
        )
    }

    private var subtitle: String {
        let n = vm.people.count
        guard n > 0 else { return "The people you walk with" }
        let count = n == 1 ? "1 member" : "\(n) members"
        return vm.canShepherd ? "\(count) · sorted by who needs you most" : count
    }

    // MARK: the shepherd's one honest line about what these numbers mean

    private var shepherdNote: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).fill(Nuru.white).frame(width: 40, height: 40)
                Icon(.handHeart, size: 18, color: Nuru.gold)
            }
            Text(shepherdNoteText)
                .font(.nCaption).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.md)
        .background(Nuru.goldTint, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    private var shepherdNoteText: String {
        guard let meetings = vm.meetingsCounted else {
            // Never print 0 of 0 — say the plain thing instead.
            return "This cell hasn't met yet, so there's no attendance to show."
        }
        return meetings == 1
            ? "Attendance counts the one gathering this cell has held. Only you see these numbers."
            : "Attendance counts the last \(meetings) gatherings this cell held. Only you see these numbers."
    }

    // MARK: the people — one card, hairline-divided rows

    private var rosterCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(vm.people.enumerated()), id: \.element.userId) { idx, m in
                if idx > 0 {
                    Rectangle().fill(Nuru.border).frame(height: 1)
                        .padding(.leading, Nuru.S.base + 44 + Nuru.S.md)
                }
                row(m)
            }
        }
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func row(_ m: CellRosterMember) -> some View {
        HStack(spacing: Nuru.S.md) {
            Avatar(url: m.avatarUrl, name: m.fullName, size: 44)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(m.fullName)
                        .font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                        .lineLimit(1).layoutPriority(1)
                    if m.isLeader { leaderChip }
                    if m.isMe { youChip }
                }
                // Standing — shepherd only, and only for what the payload carried.
                if vm.canShepherd { standingLine(m) }
            }
            Spacer(minLength: Nuru.S.sm)
            if !m.isMe { menu(m) }
        }
        .padding(.horizontal, Nuru.S.base)
        .padding(.vertical, Nuru.S.md)
    }

    private var leaderChip: some View {
        Text("LEADER")
            .font(.inter(9, .bold)).kerning(0.7).foregroundStyle(Nuru.goldChipText)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Nuru.goldChipBg, in: Capsule())
            .overlay(Capsule().stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
    }

    private var youChip: some View {
        Text("You")
            .font(.inter(9, .bold)).foregroundStyle(Nuru.navyMid)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Nuru.tintBlue, in: Capsule())
    }

    /// band pill · score with a subtle bar · attendance — one quiet line that
    /// reads at a glance and stays out of the name's way. When the cell has
    /// never met, the attendance slot is dropped entirely rather than printing
    /// a column of dashes: the note above already says why.
    private func standingLine(_ m: CellRosterMember) -> some View {
        HStack(spacing: Nuru.S.sm) {
            if let band = m.band { bandPill(band) }
            scoreMeter(m)
            if vm.meetingsCounted != nil {
                Text(attendanceLabel(m))
                    .font(.nMicro).foregroundStyle(Nuru.faint)
                    .lineLimit(1)
            }
        }
    }

    /// Engagement band → the app's shared band palette (thriving green /
    /// steady blue / watch amber / at-risk red — Nuru.bandColor).
    private func bandPill(_ band: String) -> some View {
        let color = Nuru.bandColor(band)
        return Text(DisciplerRosterView.bandLabel(band))
            .font(.inter(10, .bold)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    /// 0–100 with a hairline bar. A member with no engagement row yet has NO
    /// score — print an em dash, never a fabricated zero.
    @ViewBuilder private func scoreMeter(_ m: CellRosterMember) -> some View {
        if let score = m.score {
            let color = Nuru.bandColor(m.band)
            let width: CGFloat = 34
            HStack(spacing: 5) {
                Text("\(score)").font(.inter(12, .bold)).foregroundStyle(Nuru.ink)
                Capsule().fill(Nuru.track).frame(width: width, height: 4)
                    .overlay(alignment: .leading) {
                        Capsule().fill(color)
                            .frame(width: width * CGFloat(min(max(score, 0), 100)) / 100, height: 4)
                    }
            }
        } else {
            Text("—").font(.inter(12, .bold)).foregroundStyle(Nuru.ink300)
        }
    }

    /// "5 of 8" over the gatherings this cell actually held; "—" before it has
    /// met at all (the shepherd note above says why).
    private func attendanceLabel(_ m: CellRosterMember) -> String {
        guard let a = m.attendance, a.of > 0 else { return "—" }
        return "\(a.present) of \(a.of)"
    }

    // MARK: the "…" — opens the conversation, or asks first when it must

    @ViewBuilder private func menu(_ m: CellRosterMember) -> some View {
        Menu {
            switch vm.messageState(for: m) {
            case .message:
                Button {
                    Haptics.tap()
                    Task { if await vm.openMessage(with: m) != nil { openCreatedDm = true } }
                } label: { Label("Message \(m.firstName)", systemImage: "bubble.left.fill") }
            case .connect:
                Button {
                    Haptics.tap()
                    Task { await vm.connect(with: m) }
                } label: { Label("Connect with \(m.firstName)", systemImage: "person.badge.plus") }
            case .requestSent:
                // Honest dead-ends stay visible but inert — no button that 403s.
                Button {} label: { Label("Request sent — waiting for \(m.firstName)", systemImage: "clock") }
                    .disabled(true)
            case .wantsToConnect:
                Button {} label: { Label("\(m.firstName) asked to connect — answer in Chat", systemImage: "hand.wave") }
                    .disabled(true)
            case .blocked:
                Button {} label: { Label("Blocked", systemImage: "hand.raised.fill") }
                    .disabled(true)
            }
        } label: {
            Group {
                if vm.busyUserId == m.userId {
                    ProgressView().tint(Nuru.navy).scaleEffect(0.7)
                } else {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(Nuru.navy)
                }
            }
            .frame(width: 34, height: 34)
            .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .disabled(vm.busyUserId != nil)
    }

    // MARK: loading / empty

    private func loadingGhost(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
            .fill(Nuru.surface)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .nuruShimmer()
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).fill(Nuru.goldTint).frame(width: 48, height: 48)
                Icon(.users, size: 22, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text(vm.error == nil ? "No one here yet" : "Couldn't load the roster")
                    .font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                Text(vm.error == nil
                     ? "When your leader adds people to this cell, they'll appear here."
                     : "Check your connection and try again.")
                    .font(.nCaption).foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button { Haptics.tap(); Task { await vm.load() } } label: {
                Text("Refresh").font(.nCardCTA).foregroundStyle(Nuru.gold)
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }
}
