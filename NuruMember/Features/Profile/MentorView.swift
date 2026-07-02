// Mentorship — the native port of the Figma MentorScreen (PathwayScreens.tsx)
// over the member's real discipler pairing from GET /growth/mentor. Body follows
// the Figma card anatomy: discipler card (avatar real-or-initials), the NEXT
// MEETING card (surface inset row + Message CTA — deep-linked to the discipler's
// DM when the chat inbox has one), the CONVERSATION HISTORY card with divided
// note rows, and a YOUR CELL card that opens the real cell screen. Falls back to
// an invite card when a leader hasn't paired the member with a discipler yet.
import SwiftUI

@MainActor
final class MentorViewModel: ObservableObject {
    @Published var info: MentorInfo?
    @Published var loading = true
    @Published var error: String?
    /// The DM thread with the discipler, when the chat inbox has one — matched
    /// by the row's `peer_user_id` against the mentor's user id where the server
    /// provides it, falling back to matching the DM title (the peer's name)
    /// against the mentor's full name for rows from older servers.
    @Published var mentorDm: ChatConversation?
    /// True while POST /chat/dms is creating the discipler DM.
    @Published var startingDm = false

    func load() async {
        loading = true; error = nil
        do { info = try await MemberAPI.mentor() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your mentorship." }
        loading = false

        if let mentor = info?.mentor,
           let inbox = try? await MemberAPI.chatInbox() {
            mentorDm = Self.findDm(for: mentor, in: inbox.conversations)
        }
    }

    /// Prefer the authoritative peer-user-id match; name match is the fallback.
    static func findDm(for mentor: MentorInfo.Mentor, in conversations: [ChatConversation]) -> ChatConversation? {
        let dms = conversations.filter { $0.kind == "dm" }
        return dms.first { $0.peerUserId == mentor.mentorUserId }
            ?? dms.first {
                $0.title?.compare(mentor.fullName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
    }

    /// No DM yet → create (or fetch — the server dedupes) the 1:1 with the
    /// discipler via POST /chat/dms, then return the conversation to open.
    func startMentorDm() async -> ChatConversation? {
        guard let mentor = info?.mentor, !startingDm else { return nil }
        startingDm = true
        defer { startingDm = false }
        guard let id = try? await MemberAPI.createDm(peerUserId: mentor.mentorUserId) else { return nil }
        // Prefer the real inbox row (preview, unread); fall back to a stub the
        // thread screen hydrates from GET /chat/conversations/{id}.
        let inbox = try? await MemberAPI.chatInbox()
        let dm = inbox?.conversations.first { $0.conversationId == id } ?? ChatConversation(
            conversationId: id, kind: "dm", isPublic: false, title: mentor.fullName,
            topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
            lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: mentor.avatarUrl,
            peerUserId: mentor.mentorUserId)
        mentorDm = dm
        return dm
    }
}

struct MentorView: View {
    @StateObject private var vm = MentorViewModel()
    @Environment(\.dismiss) private var dismiss
    /// Programmatic push of the freshly created discipler DM.
    @State private var openCreatedDm = false
    @State private var dmError = false

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        if vm.loading && vm.info == nil {
                            skeleton
                        } else if let m = vm.info?.mentor {
                            disciplerCard(m).gentleEntrance()
                            meetingCard(m).gentleEntrance(delay: 0.06)
                            historyCard.gentleEntrance(delay: 0.12)
                            if m.cellName != nil { cellCard(m).gentleEntrance(delay: 0.18) }
                        } else if vm.info == nil, let err = vm.error {
                            // A failed load is not "no discipler" — say so and offer a retry.
                            errorCard(err)
                        } else {
                            emptyCard
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Lets the Message CTA push the discipler's DM thread from this stack
        // (only the Chat tab's own stack registers this destination otherwise).
        .navigationDestination(for: ChatConversation.self) { ChatThreadView(conversation: $0) }
        // Programmatic push for the just-created DM (POST /chat/dms on tap).
        .navigationDestination(isPresented: $openCreatedDm) {
            if let dm = vm.mentorDm { ChatThreadView(conversation: dm) }
        }
        .task { if vm.info == nil { await vm.load() } }
    }

    // Cream Figma ScreenShell header (done — keep as is).
    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("YOUR DISCIPLER")
                    .font(.inter(11, .bold)).tracking(1.4)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Text("Mentorship")
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.navy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.25)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: Discipler card (avatar real-or-initials · name · cell · since)

    private func disciplerCard(_ m: MentorInfo.Mentor) -> some View {
        HStack(spacing: Nuru.S.base) {
            Avatar(url: m.avatarUrl, name: m.fullName, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.fullName).font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                if let cell = m.cellName {
                    Text(cell).font(.nCaption).foregroundStyle(Nuru.muted)
                }
                if let since = m.establishedAt.flatMap(Self.monthYear) {
                    Text("Walking with you since \(since)").font(.nMicro).foregroundStyle(Nuru.gold)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: Next meeting (Figma card 1: overline, surface inset row, quick actions)

    private func meetingCard(_ m: MentorInfo.Mentor) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("NEXT MEETING")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))

                HStack(spacing: Nuru.S.md) {
                    ZStack {
                        RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                            .fill(Nuru.goldTint)
                            .frame(width: 44, height: 44)
                        Icon(.calendarClock, size: 18, color: Nuru.gold)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        if let next = vm.info?.nextMeetingAt {
                            Text(Self.longDate(next))
                                .font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
                            Text("With \(m.fullName)")
                                .font(.inter(11, .regular)).foregroundStyle(Nuru.muted)
                        } else {
                            Text("No meeting scheduled yet")
                                .font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
                            Text("Your discipler will set the next one.")
                                .font(.inter(11, .regular)).foregroundStyle(Nuru.muted)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Nuru.S.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))

                messageCTA(m)
            }
        }
    }

    // The Figma Message quick button — a real deep link into the discipler's DM
    // when the inbox has one; otherwise the tap CREATES the 1:1 (POST /chat/dms,
    // server-deduped) and pushes the new thread.
    // (Call / Reschedule from the make are omitted: the mentor contract carries
    // no phone number and there is no rescheduling endpoint.)
    @ViewBuilder private func messageCTA(_ m: MentorInfo.Mentor) -> some View {
        if let dm = vm.mentorDm {
            NavigationLink(value: dm) { messageLabel(busy: false) }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        } else {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Button {
                    Haptics.tap()
                    dmError = false
                    Task {
                        if await vm.startMentorDm() != nil {
                            Haptics.success()
                            openCreatedDm = true
                        } else {
                            Haptics.error()
                            dmError = true
                        }
                    }
                } label: {
                    messageLabel(busy: vm.startingDm)
                }
                .buttonStyle(.pressable)
                .disabled(vm.startingDm)
                if dmError {
                    Text("Couldn't start the chat with \(firstName(m.fullName)) — please try again.")
                        .font(.nMicro).foregroundStyle(Nuru.faint)
                }
            }
        }
    }

    private func messageLabel(busy: Bool) -> some View {
        HStack(spacing: Nuru.S.sm) {
            if busy {
                ProgressView().tint(Nuru.navy).scaleEffect(0.8)
            } else {
                Icon(.messageCircle, size: 15, color: Nuru.navy)
            }
            Text("Message").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
        }
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
    }

    // MARK: Conversation history (Figma card 2: one card, divided note rows)

    private var historyCard: some View {
        let notes = vm.info?.notes ?? []
        return Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("CONVERSATION HISTORY")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))
                if notes.isEmpty {
                    Text("Your discipler's meeting notes will appear here after your first session.")
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                        .padding(.top, Nuru.S.xs)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(notes.enumerated()), id: \.element.noteId) { i, note in
                            noteRow(note)
                            if i < notes.count - 1 { Divider().overlay(Nuru.border) }
                        }
                    }
                }
            }
        }
    }

    private func noteRow(_ note: MentorInfo.Note) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.topic?.isEmpty == false ? note.topic! : "Session")
                    .font(.inter(12, .semibold)).foregroundStyle(Nuru.ink)
                Spacer(minLength: Nuru.S.sm)
                if let met = note.metAt.flatMap(Self.shortDate) {
                    Text(met).font(.inter(10, .regular)).foregroundStyle(Nuru.faint)
                }
            }
            Text(note.note)
                .font(.inter(12, .regular)).foregroundStyle(Nuru.muted)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
            if let next = note.nextMeetingAt.flatMap(Self.shortDate) {
                HStack(spacing: 4) {
                    Icon(.calendar, size: 11, color: Nuru.faint)
                    Text("Next: \(next)").font(.nMicro).foregroundStyle(Nuru.faint)
                }
            }
        }
        .padding(.vertical, Nuru.S.md)
    }

    // MARK: Your cell (Figma card 3 — opens the real cell screen)

    private func cellCard(_ m: MentorInfo.Mentor) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("YOUR CELL")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))
                Text(m.cellName ?? "")
                    .font(.inter(14, .semibold)).foregroundStyle(Nuru.ink)
                NavigationLink(value: AppRoute.cell) {
                    HStack(spacing: Nuru.S.sm) {
                        Icon(.users, size: 15, color: Nuru.navy)
                        Text("Open community").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
            }
        }
    }

    // MARK: Loading skeleton (mirrors the discipler + meeting card anatomy)

    private var skeleton: some View {
        VStack(spacing: Nuru.S.base) {
            HStack(spacing: Nuru.S.base) {
                Circle().fill(Nuru.surface).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 140, height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 90, height: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShimmer()

            VStack(alignment: .leading, spacing: Nuru.S.md) {
                RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 90, height: 8)
                RoundedRectangle(cornerRadius: Nuru.R.control).fill(Nuru.surface)
                    .frame(maxWidth: .infinity).frame(height: 68)
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShimmer()
        }
    }

    // MARK: Error state (load failed — distinct from "no discipler yet")

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: Nuru.S.md) {
            Text(message).font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            Button { Task { await vm.load() } } label: {
                Text("Try again").font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: Empty state (no pairing yet)

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous)
                    .fill(Nuru.goldTint)
                    .frame(width: 48, height: 48)
                Icon(.heartHandshake, size: 22, color: Nuru.gold)
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("No discipler yet")
                    .font(.inter(17, .bold))
                    .foregroundStyle(Nuru.ink)
                Text("When your leader pairs you with a discipler, you'll see your meetings and notes here.")
                    .font(.nCaption)
                    .foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
                .stroke(Nuru.border, lineWidth: 1)
        )
        .nuruShadow()
    }

    // MARK: date helpers

    private static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
    private static func monthYear(_ iso: String) -> String? {
        guard let d = parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: d)
    }
    private static func longDate(_ iso: String) -> String {
        guard let d = parse(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d · h:mm a"; return f.string(from: d)
    }
    private static func shortDate(_ iso: String) -> String? {
        guard let d = parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }
}
