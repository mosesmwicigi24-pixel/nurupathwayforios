// Chat — "Nuru Connect" inbox, the native port of screens/ChatScreen.tsx. A navy
// gradient header (time-based greeting overline, serif title, bell + unread badge),
// a translucent search bar, the "Quick help from Nuru" AI card, the "Verse for today"
// card, and a three-way segmented control (#My Space · DM · My Groups). Spaces render
// as white cards (# avatar, last-message preview, member dots, Active pill, day); DMs
// lead with a stories row then message rows; Groups show an empty hint when none. A
// gold pencil FAB floats bottom-right. Taps open the thread.
import SwiftUI

@MainActor
final class ChatInboxViewModel: ObservableObject {
    @Published var inbox: ChatInbox?
    @Published var verse: (text: String, reference: String, version: String)?
    @Published var loading = true
    @Published var error: String?

    var conversations: [ChatConversation] { inbox?.conversations ?? [] }
    var spaces: [ChatConversation] { conversations.filter { $0.kind == "space" } }
    var dms: [ChatConversation] { conversations.filter { $0.kind == "dm" } }
    var groups: [ChatConversation] { conversations.filter { $0.kind == "group" } }
    var totalUnread: Int { conversations.reduce(0) { $0 + $1.unread } }

    func load() async {
        loading = true; error = nil
        async let inboxReq = try? MemberAPI.chatInbox()
        async let verseReq = try? MemberAPI.homeVerse()

        if let i = await inboxReq { inbox = i } else { error = "Couldn't load your chats." }
        if let v = await verseReq {
            if let t = v.text, !t.isEmpty { verse = (t, v.reference, v.version) }
            else { verse = (defaultVerseText, v.reference, v.version) }
        }
        loading = false
    }

    private let defaultVerseText = "“Carry each other’s burdens, and in this way you will fulfill the law of Christ.”"
}

private enum ChatSegment: Int, CaseIterable { case space, dm, group }

struct ChatView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = ChatInboxViewModel()
    @State private var path = NavigationPath()
    @State private var segment: ChatSegment = .space
    @State private var query = ""

    var body: some View {
        NavigationStack(path: $path) {
            ZStack(alignment: .bottomTrailing) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        header
                        VStack(spacing: Nuru.S.base) {
                            aiCard
                            verseCard
                            segmentControl
                            segmentBody
                        }
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, Nuru.S.base)
                        .padding(.bottom, Nuru.tabBarSpace)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .background(Nuru.paper.ignoresSafeArea())
                fab
            }
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .navigationDestination(for: ChatConversation.self) { ChatThreadView(conversation: $0) }
        }
        .task { if vm.inbox == nil { await vm.load() } }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Icon(.sparkle, size: 12, color: Nuru.gold)
                        Text("\(greeting.uppercased()) · \(firstName.uppercased())")
                            .font(.inter(11, .semibold)).kerning(2.2).foregroundStyle(Nuru.gold)
                    }
                    Text("Nuru Connect")
                        .font(.fraunces(28, .semibold)).foregroundStyle(Nuru.onNavy)
                        .padding(.top, Nuru.S.md)
                    Text("You’re all caught up")
                        .font(.inter(13)).foregroundStyle(Nuru.onNavyDim)
                        .padding(.top, 6)
                }
                Spacer(minLength: 0)
                ZStack(alignment: .topTrailing) {
                    Icon(.bell, size: 20, color: Nuru.onNavy)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    if vm.totalUnread > 0 {
                        Text(vm.totalUnread > 9 ? "9+" : "\(vm.totalUnread)")
                            .font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(Nuru.gold, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                }
            }
            searchBar.padding(.top, Nuru.S.lg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 64)
        .padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    private var searchBar: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.search, size: 16, color: Nuru.onNavyDim)
            TextField("", text: $query, prompt: Text("Search spaces, people, messages").foregroundColor(Nuru.onNavyDim))
                .font(.inter(14)).foregroundStyle(Nuru.onNavy)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: { Icon(.x, size: 14, color: Nuru.onNavyDim) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Nuru.S.base)
        .frame(height: 46)
        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
    }

    // MARK: AI card ("Quick help from Nuru")

    private var aiCard: some View {
        Button { /* AI assistant not wired yet */ } label: {
            HStack(spacing: Nuru.S.md) {
                ZStack(alignment: .topTrailing) {
                    Icon(.sparkles, size: 22, color: .white)
                        .frame(width: 48, height: 48)
                        .background(
                            LinearGradient(colors: [Color(hex: 0x7C3AED), Color(hex: 0x6D28D9)],
                                           startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    Circle().fill(Nuru.online).frame(width: 11, height: 11)
                        .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                        .offset(x: 3, y: -3)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("Quick help from Nuru").font(.inter(15, .semibold)).foregroundStyle(.white)
                        Text("AI").font(.inter(9, .bold)).kerning(0.5).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.white.opacity(0.18), in: Capsule())
                    }
                    Text("The AI assistant · 0 updates across \(vm.spaces.count) spaces")
                        .font(.inter(12)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 16, color: .white.opacity(0.85))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .padding(Nuru.S.base)
            .background(
                LinearGradient(colors: [Color(hex: 0x4C1D95), Color(hex: 0x2A2255), Color(hex: 0x103B3A)],
                               startPoint: .leading, endPoint: .trailing),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .nuruShadow()
        }
        .buttonStyle(.plain)
    }

    // MARK: Verse for today

    private var verseCard: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            Icon(.quote, size: 16, color: Nuru.gold)
                .frame(width: 30, height: 30)
                .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 6) {
                Text("VERSE FOR TODAY").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                Text(vm.verse?.text ?? "“Carry each other’s burdens, and in this way you will fulfill the law of Christ.”")
                    .font(.fraunces(15)).foregroundStyle(Nuru.ink).lineSpacing(3)
                Text(vm.verse?.reference ?? "Galatians 6:2")
                    .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    // MARK: Segmented control

    private var segmentControl: some View {
        HStack(spacing: 4) {
            segmentButton(.space, "#My Space", vm.spaces.count)
            segmentButton(.dm, "DM", vm.dms.count)
            segmentButton(.group, "My Groups", vm.groups.count)
        }
        .padding(5)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func segmentButton(_ seg: ChatSegment, _ label: String, _ count: Int) -> some View {
        let selected = segment == seg
        return Button { withAnimation(.easeInOut(duration: 0.15)) { segment = seg } } label: {
            HStack(spacing: 6) {
                Text(label).font(.inter(13, .semibold)).foregroundStyle(selected ? Nuru.onNavy : Nuru.ink600)
                Text("\(count)").font(.inter(11, .bold))
                    .foregroundStyle(selected ? Nuru.navy : Nuru.ink600)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(selected ? Nuru.gold : Nuru.mutedBg,
                                in: selected ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 7, style: .continuous)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(selected ? Nuru.navy : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        return VStack(alignment: .leading, spacing: Nuru.S.sm) {
            hashOverline("YOUR SPACES")
            if items.isEmpty {
                emptyCard("No spaces yet — they’ll appear as your cell gets set up.")
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, c in
                    NavigationLink(value: c) { SpaceRow(c: c, index: idx) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var dmList: some View {
        let items = vm.dms.filter(matches)
        return VStack(alignment: .leading, spacing: Nuru.S.sm) {
            storiesRow
            overline(.messageCircle, "DIRECT MESSAGES").padding(.top, 6)
            if items.isEmpty {
                emptyCard("No direct messages yet — start a conversation with someone in your space.")
            } else {
                ForEach(items) { c in
                    NavigationLink(value: c) { DMRow(c: c) }.buttonStyle(.plain)
                }
            }
        }
    }

    private var groupList: some View {
        let items = vm.groups.filter(matches)
        return VStack(alignment: .leading, spacing: Nuru.S.sm) {
            overline(.users, "YOUR GROUPS")
            if items.isEmpty {
                emptyCard("You’re not in any group rooms yet — they appear when your cell is set up.")
            } else {
                ForEach(items) { c in
                    NavigationLink(value: c) { DMRow(c: c) }.buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: DM stories row

    private var storiesRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: Nuru.S.base) {
                VStack(spacing: 6) {
                    ZStack(alignment: .bottomTrailing) {
                        ZStack { Circle().fill(Nuru.navy); Text("ME").font(.inter(13, .bold)).foregroundStyle(Nuru.onNavy) }
                            .frame(width: 56, height: 56)
                        ZStack { Circle().fill(Nuru.gold); Icon(.plus, size: 11, color: Nuru.navy) }
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Nuru.paper, lineWidth: 2))
                            .offset(x: 2, y: 2)
                    }
                    Text("Your note").font(.inter(10, .medium)).foregroundStyle(Nuru.muted)
                }
                ForEach(vm.dms) { c in
                    NavigationLink(value: c) {
                        VStack(spacing: 6) {
                            Avatar(url: c.avatarUrl, name: c.title ?? "?", size: 52)
                                .padding(3)
                                .overlay(Circle().stroke(Nuru.gold, lineWidth: 2))
                            Text(firstWord(c.title)).font(.inter(10, .medium)).foregroundStyle(Nuru.muted).lineLimit(1)
                        }
                        .frame(width: 60)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: FAB

    private var fab: some View {
        Button { /* compose not wired yet */ } label: {
            Icon(.pencil, size: 20, color: Nuru.navy)
                .frame(width: 56, height: 56)
                .background(Nuru.goldGradient, in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 1))
                .shadow(color: Nuru.gold.opacity(0.45), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .padding(.trailing, Nuru.S.screen)
        .padding(.bottom, Nuru.tabBarSpace - 18)
    }

    // MARK: Shared bits

    private func overline(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 6) {
            Icon(icon, size: 12, color: Nuru.gold)
            Text(text).font(.inter(10, .bold)).kerning(1.4).foregroundStyle(Nuru.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Nuru.S.xs)
    }

    private func hashOverline(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text("#").font(.inter(12, .bold)).foregroundStyle(Nuru.gold)
            Text(text).font(.inter(10, .bold)).kerning(1.4).foregroundStyle(Nuru.gold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Nuru.S.xs)
    }

    private func emptyCard(_ text: String) -> some View {
        Text(text)
            .font(.nCaption).foregroundStyle(Nuru.muted).lineSpacing(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Derived

    private var firstName: String { (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend" }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }
    private func firstWord(_ s: String?) -> String { (s ?? "—").split(separator: " ").first.map(String.init) ?? "—" }
}

// MARK: - Space row (white card with # avatar, preview, member dots, Active pill, day)

private struct SpaceRow: View {
    let c: ChatConversation
    let index: Int

    private static let tints: [(bg: UInt32, fg: UInt32)] = [
        (0x14B8A6, 0xFFFFFF), // teal
        (0xEC4899, 0xFFFFFF), // pink
        (0xF59E0B, 0xFFFFFF), // amber
        (0x6366F1, 0xFFFFFF), // indigo
        (0x10B981, 0xFFFFFF), // emerald
    ]
    private var tint: (bg: UInt32, fg: UInt32) { Self.tints[index % Self.tints.count] }

    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            Text("#").font(.inter(22, .bold)).foregroundStyle(Color(hex: tint.fg))
                .frame(width: 48, height: 48)
                .background(Color(hex: tint.bg), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.title ?? "Space").font(.inter(15, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(dayLabel).font(.inter(11, .medium)).foregroundStyle(Nuru.faint)
                }
                Text(preview).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(1)
                HStack(spacing: Nuru.S.sm) {
                    memberDots
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        Circle().fill(Nuru.success).frame(width: 6, height: 6)
                        Text("Active").font(.inter(10, .semibold)).foregroundStyle(Nuru.activeBadgeText)
                    }
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Nuru.activeBadgeBg, in: Capsule())
                }
                .padding(.top, 2)
            }
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private static let dotTints: [UInt32] = [0x14B8A6, 0x6366F1, 0xEC4899, 0xF59E0B]
    private var memberDots: some View {
        let n = min(3, max(1, c.memberCount))
        return HStack(spacing: -6) {
            ForEach(0..<n, id: \.self) { i in
                Circle().fill(Color(hex: Self.dotTints[(index + i) % Self.dotTints.count]))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(Nuru.white, lineWidth: 1.5))
            }
            if c.memberCount > 0 {
                Text("\(c.memberCount)").font(.inter(10, .semibold)).foregroundStyle(Nuru.muted).padding(.leading, 10)
            }
        }
    }

    private var preview: String {
        if c.lastType == "voice" { return "🎤 Voice note" }
        if c.lastType == "image" { return "📷 Photo" }
        let prefix = c.lastAuthor.map { "\($0): " } ?? ""
        return prefix + (c.lastBody ?? "No messages yet")
    }

    private var dayLabel: String {
        guard let iso = c.lastAt,
              let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE"
        return f.string(from: d)
    }
}

// MARK: - DM / group row (avatar, name, preview, time, reply count)

private struct DMRow: View {
    let c: ChatConversation
    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            if c.kind == "dm" {
                Avatar(url: c.avatarUrl, name: c.title ?? "?", size: 44)
            } else {
                Icon(.users, size: 18, color: Nuru.gold)
                    .frame(width: 44, height: 44)
                    .background(Nuru.goldChipBg, in: Circle())
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text(c.title ?? "Conversation").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    if let at = c.lastAt { Text(timeAgo(at)).font(.inter(11, .medium)).foregroundStyle(Nuru.faint) }
                }
                Text(preview).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(1)
                HStack(spacing: Nuru.S.md) {
                    HStack(spacing: 4) {
                        Icon(.messageCircle, size: 12, color: Nuru.faint)
                        Text("\(max(0, c.memberCount))").font(.inter(11, .medium)).foregroundStyle(Nuru.faint)
                    }
                    Spacer(minLength: 0)
                    if c.unread > 0 {
                        Text("\(c.unread)").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                            .frame(minWidth: 20, minHeight: 20).background(Nuru.gold, in: Circle())
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private var preview: String {
        if c.lastType == "voice" { return "🎤 Voice note" }
        if c.lastType == "image" { return "📷 Photo" }
        return c.lastBody ?? "No messages yet"
    }
}
