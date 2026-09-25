// A department's page — pushed from the Departments list, or landed on
// directly by a serve_request_* / department_post / department_need_*
// notification (PARTNERS_PROGRAMME §4, phase 3).
//
// Hero (photo, name, purpose, when it meets, who leads it), the member's
// standing with the team and the one door in ("I'd like to serve here" —
// the leader approves in the PORTAL, never here), then three segments:
// Posts (the leader's updates), Needs (what the team is raising for; "Give to
// this need" opens Give with the need riding the intent so the server
// attributes the gift), and Members.
//
// Leaders get the compose sheet, delete on posts, and "Submit a need" (the
// office approves — approval is what creates the campaign behind the
// progress bar, §4). Nothing here computes money or progress: `raised`,
// `percent`, `reached` are the server's.
import SwiftUI

@MainActor final class DepartmentDetailModel: ObservableObject {
    let departmentId: String
    @Published var detail: DepartmentDetail?
    @Published var loading = true
    @Published var error: String?
    /// True while serve / leave / post / need is in flight — one at a time.
    @Published var busy = false
    /// A failed action, surfaced once in an alert and cleared. Never silent.
    @Published var actionError: String?

    init(departmentId: String) { self.departmentId = departmentId }

    func load() async {
        loading = detail == nil
        error = nil
        do { detail = try await MemberAPI.department(departmentId) }
        catch { if detail == nil { self.error = (error as? APIError)?.errorDescription ?? "We couldn't load this department." } }
        loading = false
    }

    /// POST /serve — then reload so the standing shown is the server's.
    @discardableResult
    func requestToServe() async -> Bool {
        await run("That didn't go through. Nothing has changed.") {
            try await MemberAPI.requestToServe(self.departmentId)
        }
    }

    /// DELETE /serve — leave the team, or withdraw a pending request.
    @discardableResult
    func leave() async -> Bool {
        await run("That didn't go through. You're still on the team.") {
            try await MemberAPI.leaveDepartment(self.departmentId)
        }
    }

    @discardableResult
    func post(body: String, imageUrl: String?) async -> Bool {
        await run("Your post didn't go through. Nothing was posted.") {
            try await MemberAPI.postDepartmentUpdate(self.departmentId, body: body, imageUrl: imageUrl)
        }
    }

    @discardableResult
    func deletePost(_ postId: String) async -> Bool {
        await run("The post couldn't be removed.") {
            try await MemberAPI.deleteDepartmentPost(self.departmentId, postId: postId)
        }
    }

    @discardableResult
    func submitNeed(title: String, why: String, targetMinor: Int, currency: String, deadline: String?) async -> Bool {
        await run("The need wasn't submitted. Nothing has changed.") {
            try await MemberAPI.submitDepartmentNeed(self.departmentId, title: title, why: why,
                                                     targetMinor: targetMinor, currency: currency, deadline: deadline)
        }
    }

    private func run(_ failure: String, _ op: @escaping () async throws -> Void) async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            try await op()
            Haptics.success()
            await load()
            return true
        } catch {
            Haptics.error()
            actionError = (error as? APIError)?.errorDescription ?? failure
            return false
        }
    }
}

private enum DeptSegment: String, CaseIterable {
    case posts = "Posts", needs = "Needs", members = "Members"
    var icon: Lucide {
        switch self { case .posts: return .megaphone; case .needs: return .target; case .members: return .users }
    }
}

struct DepartmentDetailView: View {
    let departmentId: String
    /// The list's copy of the row, so the hero renders before the fetch.
    var seed: DepartmentRow? = nil
    /// Called after a serve / leave succeeded so the list's status chips catch up.
    var onChanged: (() -> Void)? = nil

    @StateObject private var vm: DepartmentDetailModel
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var segment: DeptSegment = .posts
    @State private var showComposer = false
    @State private var showNeedForm = false
    @State private var confirmLeave = false
    @State private var deletingPost: DepartmentPost?

    init(departmentId: String, seed: DepartmentRow? = nil, onChanged: (() -> Void)? = nil) {
        self.departmentId = departmentId
        self.seed = seed
        self.onChanged = onChanged
        _vm = StateObject(wrappedValue: DepartmentDetailModel(departmentId: departmentId))
    }

    private var row: DepartmentRow? { vm.detail?.summary ?? seed }
    private var isLeader: Bool { vm.detail?.isLeader ?? (seed?.isLeaderRole ?? false) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    if let r = row {
                        hero(r)
                        standing(r)
                    }
                    if vm.loading && vm.detail == nil {
                        ProgressView().tint(Nuru.gold).frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let e = vm.error, vm.detail == nil {
                        errorState(e)
                    } else if let d = vm.detail {
                        segmentRow
                        switch segment {
                        case .posts:   posts(d)
                        case .needs:   needs(d)
                        case .members: members(d)
                        }
                    }
                }
                .padding(Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
            .refreshable { await vm.load() }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .onAppear { ScreenTracker.record(screen: "you.departments.page") }
        .sheet(isPresented: $showComposer) {
            DepartmentPostComposer { body, imageUrl in await vm.post(body: body, imageUrl: imageUrl) }
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showNeedForm) {
            DepartmentNeedForm(currency: vm.detail?.needs.first?.currency ?? "KES") { title, why, target, currency, deadline in
                await vm.submitNeed(title: title, why: why, targetMinor: target, currency: currency, deadline: deadline)
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            row?.isRequested == true ? "Withdraw your request?" : "Leave this department?",
            isPresented: $confirmLeave, titleVisibility: .visible
        ) {
            Button(row?.isRequested == true ? "Withdraw request" : "Leave the department", role: .destructive) {
                Haptics.action()
                Task { if await vm.leave() { onChanged?() } }
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text(row?.isRequested == true
                 ? "The leader won't see your request any more. You can ask again any time."
                 : "You'll stop appearing on the team. You can ask to serve again any time.")
        }
        .confirmationDialog(
            "Remove this post?",
            isPresented: Binding(get: { deletingPost != nil }, set: { if !$0 { deletingPost = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove the post", role: .destructive) {
                if let p = deletingPost { Haptics.action(); Task { await vm.deletePost(p.postId) } }
                deletingPost = nil
            }
            Button("Keep it", role: .cancel) { deletingPost = nil }
        } message: {
            Text("Members won't see it any more. This can't be undone.")
        }
        .alert("That didn't go through", isPresented: Binding(get: { vm.actionError != nil }, set: { if !$0 { vm.actionError = nil } })) {
            Button("OK") { vm.actionError = nil }
        } message: { Text(vm.actionError ?? "") }
    }

    // MARK: Header (cream band, back + overflow)

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Button { Haptics.tap(); dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                if let r = row, r.isActiveMember || r.isRequested {
                    Menu {
                        Button(role: .destructive) { confirmLeave = true } label: {
                            Label(r.isRequested ? "Withdraw request" : "Leave department", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "ellipsis").font(.system(size: 16, weight: .bold)).foregroundStyle(Nuru.navy)
                            .frame(width: 40, height: 40)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                    }
                    .accessibilityLabel("More")
                }
            }
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("DEPARTMENT").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0x9A7A2A))
                Text(row?.name ?? "Department").font(.fraunces(26, .semibold)).foregroundStyle(Nuru.navy)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
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
        .ignoresSafeArea(edges: .top)
    }

    // MARK: Hero

    private func hero(_ r: DepartmentRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DepartmentPhoto(url: r.imageUrl, name: r.name, height: 176)
            VStack(alignment: .leading, spacing: 12) {
                if !r.purpose.isEmpty {
                    Text(r.purpose).font(.nBodyLg).foregroundStyle(Nuru.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let meets = r.meets, !meets.isEmpty {
                    HStack(spacing: 8) {
                        Icon(.calendarClock, size: 14, color: Nuru.gold)
                        Text(meets).font(.nBody).foregroundStyle(Nuru.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    if let leader = r.leaderName, !leader.isEmpty {
                        Avatar(url: r.leaderAvatar, name: leader, size: 28)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(leader).font(.nLabel).foregroundStyle(Nuru.ink).lineLimit(1)
                            Text("Leader").font(.nCardMeta).foregroundStyle(Nuru.ink400)
                        }
                        Spacer(minLength: 8)
                    }
                    HStack(spacing: 4) {
                        Icon(.users, size: 12, color: Nuru.ink400)
                        Text(r.memberCount == 1 ? "1 serving" : "\(r.memberCount) serving")
                            .font(.nCaption).foregroundStyle(Nuru.ink600)
                    }
                }
                if r.fit || r.isActiveMember || r.isRequested {
                    DeptChipRow {
                        if let chip = DepartmentStatusChip(row: r) { chip }
                        if r.fit { DepartmentFitChip(gifts: r.matchedGiftNames) }
                    }
                }
            }
            .padding(Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    // MARK: Standing — the one door in, or where the member already stands

    @ViewBuilder private func standing(_ r: DepartmentRow) -> some View {
        if r.isActiveMember {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Icon(.circleCheckBig, size: 15, color: Nuru.success)
                    Text(isLeader ? "You lead this team." : "You serve here.")
                        .font(.inter(13, .semibold)).foregroundStyle(Nuru.successText)
                }
                if isLeader {
                    Text("Requests to serve are approved in the portal — new members appear here once you've said yes there.")
                        .font(.nCaption).foregroundStyle(Nuru.ink600)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.successBg.opacity(0.6), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if r.isRequested {
            HStack(spacing: 8) {
                Icon(.clock, size: 15, color: Nuru.urgentText)
                Text("Requested — waiting for the leader")
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.urgentText)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.urgentBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: 8) {
                PButton(title: "I'd like to serve here", variant: .gold, busy: vm.busy, disabled: !r.isOpenToJoin) {
                    Haptics.action()
                    Task { if await vm.requestToServe() { onChanged?() } }
                }
                if !r.isOpenToJoin {
                    Text("This team isn't taking new members right now.")
                        .font(.nCaption).foregroundStyle(Nuru.ink600)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else if r.myStatus == "declined" {
                    Text("Your earlier request wasn't approved. You're welcome to ask again.")
                        .font(.nCaption).foregroundStyle(Nuru.ink600)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("The leader approves requests in the portal.")
                        .font(.nCaption).foregroundStyle(Nuru.ink400)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
    }

    // MARK: Segments

    private var segmentRow: some View {
        HStack(spacing: 4) {
            ForEach(DeptSegment.allCases, id: \.self) { seg in
                let on = seg == segment
                Button {
                    guard segment != seg else { return }
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.15)) { segment = seg }
                } label: {
                    HStack(spacing: 5) {
                        Icon(seg.icon, size: 12, color: on ? Nuru.gold : Color(hex: 0x59667C))
                        Text(seg.rawValue).font(.inter(12, .semibold)).foregroundStyle(on ? Color.white : Color(hex: 0x59667C))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        on ? AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x0A1628), Color(hex: 0x16273F)],
                                                          startPoint: .topLeading, endPoint: .bottomTrailing))
                           : AnyShapeStyle(Color.clear),
                        in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.7), in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Posts

    private func posts(_ d: DepartmentDetail) -> some View {
        let sorted = d.posts.sorted { $0.createdAt > $1.createdAt }
        return VStack(alignment: .leading, spacing: Nuru.S.md) {
            if d.isLeader {
                Button { Haptics.tap(); showComposer = true } label: {
                    HStack(spacing: 6) {
                        Icon(.penLine, size: 13, color: Nuru.navy)
                        Text("Write a post").font(.inter(13, .bold))
                    }
                    .foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
            if sorted.isEmpty {
                quietNote(d.isLeader ? "Nothing posted yet — write the first update for the team."
                                     : "Nothing posted yet. The leader's updates will appear here.")
            } else {
                ForEach(sorted) { p in postCard(p, canDelete: d.isLeader) }
            }
        }
    }

    private func postCard(_ p: DepartmentPost, canDelete: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Avatar(url: p.authorAvatar, name: p.authorName ?? "", size: 30)
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.authorName ?? "Department").font(.nLabel).foregroundStyle(Nuru.ink).lineLimit(1)
                    Text(timeAgo(p.createdAt)).font(.nCardMeta).foregroundStyle(Nuru.ink400)
                }
                Spacer(minLength: 8)
                if canDelete {
                    Button { Haptics.tap(); deletingPost = p } label: {
                        Icon(.trash2, size: 14, color: Nuru.ink400)
                            .frame(width: 32, height: 32)
                            .background(Nuru.surface, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove post")
                }
            }
            Text(p.body).font(.nBody).foregroundStyle(Nuru.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let url = p.imageUrl, let u = URL(string: url) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                            .frame(maxWidth: .infinity).frame(height: 180).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    } else if phase.error == nil {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Nuru.surface)
                            .frame(height: 180).nuruShimmer()
                    }
                }
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Needs

    private func needs(_ d: DepartmentDetail) -> some View {
        // Members see what is open for giving; the leader also sees what is
        // still with the office and what has closed.
        let open = d.needs.filter(\.isOpen)
        let pending = d.isLeader ? d.needs.filter(\.isPending) : []
        let closed = d.isLeader ? d.needs.filter(\.isClosed) : []
        return VStack(alignment: .leading, spacing: Nuru.S.md) {
            if d.isLeader {
                Button { Haptics.tap(); showNeedForm = true } label: {
                    HStack(spacing: 6) {
                        Icon(.plus, size: 13, color: Nuru.navy)
                        Text("Submit a need").font(.inter(13, .bold))
                    }
                    .foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.pressable)
                Text("The office approves a need before it opens for giving.")
                    .font(.nCaption).foregroundStyle(Nuru.ink400)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            if open.isEmpty && pending.isEmpty && closed.isEmpty {
                quietNote("No open needs right now.")
            }
            if !open.isEmpty {
                if d.isLeader { kicker("OPEN FOR GIVING") }
                ForEach(open) { n in needCard(n) }
            }
            if !pending.isEmpty {
                kicker("WITH THE OFFICE")
                ForEach(pending) { n in needCard(n) }
            }
            if !closed.isEmpty {
                kicker("CLOSED")
                ForEach(closed) { n in needCard(n) }
            }
        }
    }

    private func needCard(_ n: DepartmentNeed) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(n.title).font(.nRowTitle).foregroundStyle(Nuru.ink).lineLimit(2)
                    if !n.why.isEmpty {
                        Text(n.why).font(.nCardBody).foregroundStyle(Nuru.ink600)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                needChip(n)
            }

            if n.isOpen || n.isClosed {
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Nuru.navy.opacity(0.10))
                            Capsule().fill(n.reached ? Nuru.success : Nuru.gold)
                                .frame(width: max(4, geo.size.width * n.fraction))
                        }
                    }
                    .frame(height: 7)
                    HStack(spacing: 6) {
                        Text(money(n.raisedMinor, n.currency)).font(.nLabel).foregroundStyle(Nuru.ink)
                        Text("of \(money(n.targetMinor, n.currency))").font(.nCaption).foregroundStyle(Nuru.ink600)
                        Spacer(minLength: 8)
                        Text("\(n.percent)%").font(.nCaption).foregroundStyle(Nuru.ink600)
                    }
                }
            } else {
                Text("Target \(money(n.targetMinor, n.currency))").font(.nCaption).foregroundStyle(Nuru.ink600)
            }

            HStack(spacing: 6) {
                if let dl = n.deadline, !dl.isEmpty {
                    Icon(.calendar, size: 11, color: Nuru.ink400)
                    Text("by \(formatISODay(dl) ?? String(dl.prefix(10)))").font(.nCaption).foregroundStyle(Nuru.ink600)
                }
                if let who = n.submittedName, !who.isEmpty, n.isPending {
                    if n.deadline != nil { Text("·").font(.nCaption).foregroundStyle(Nuru.ink300) }
                    Text("Submitted by \(who)").font(.nCaption).foregroundStyle(Nuru.ink600).lineLimit(1)
                }
            }

            if n.isOpen && !n.reached {
                Button {
                    Haptics.action()
                    // Give opens with the need attached — the intent carries
                    // `need_id` and the SERVER routes the gift to the
                    // department's fund (§4), so Give shows a GIVING TO A NEED
                    // card instead of its fund chooser.
                    tabs.openGive(preset: GivePreset(fund: nil, amountMinor: nil, pledgeId: nil, needId: n.needId,
                                                     needTitle: n.title.isEmpty ? nil : n.title,
                                                     needLine: "\(n.percent)% of \(money(n.targetMinor, n.currency)) raised"))
                } label: {
                    HStack(spacing: 6) {
                        Icon(.handHeart, size: 13, color: Nuru.navy)
                        Text("Give to this need").font(.inter(13, .bold))
                    }
                    .foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    @ViewBuilder private func needChip(_ n: DepartmentNeed) -> some View {
        if n.reached {
            DeptChip(text: "Target reached", icon: .circleCheckBig, bg: Nuru.activeBadgeBg, fg: Nuru.activeBadgeText)
        } else if n.isOpen {
            DeptChip(text: "Open", icon: .handHeart, bg: Nuru.goldChipBg, fg: Nuru.goldChipText)
        } else if n.isPending {
            DeptChip(text: "Awaiting approval", icon: .clock, bg: Nuru.urgentBg, fg: Nuru.urgentText)
        } else {
            DeptChip(text: "Closed", bg: Nuru.surface, fg: Nuru.ink600)
        }
    }

    // MARK: Members

    private func members(_ d: DepartmentDetail) -> some View {
        let sorted = d.members.sorted { ($0.isLeader ? 0 : 1, $0.fullName) < ($1.isLeader ? 0 : 1, $1.fullName) }
        return VStack(alignment: .leading, spacing: Nuru.S.md) {
            if sorted.isEmpty {
                quietNote("No one on the team yet.")
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 14) {
                    ForEach(sorted) { m in
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottomTrailing) {
                                Avatar(url: m.avatarUrl, name: m.fullName, size: 54)
                                    .overlay(Circle().stroke(m.isLeader ? Nuru.gold : Color.clear, lineWidth: 2))
                                if m.isLeader {
                                    ZStack {
                                        Circle().fill(Nuru.gold).frame(width: 18, height: 18)
                                        Icon(.badgeCheck, size: 10, color: .white)
                                    }
                                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
                                    .offset(x: 2, y: 2)
                                }
                            }
                            Text(m.fullName).font(.nMicro).foregroundStyle(Nuru.ink)
                                .multilineTextAlignment(.center).lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            if m.isLeader {
                                Text("Leader").font(.inter(9, .bold)).kerning(0.8).foregroundStyle(Nuru.goldLo)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .top)
                    }
                }
                .padding(Nuru.S.base)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
        }
    }

    // MARK: Bits

    private func kicker(_ t: String) -> some View {
        Text(t).font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo).padding(.top, 4)
    }

    private func quietNote(_ t: String) -> some View {
        Text(t).font(.nCardBody).foregroundStyle(Color(hex: 0x5B6472))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 22).padding(.horizontal, Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Nuru.S.sm) {
            Text(message).font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { Haptics.tap(); Task { await vm.load() } } label: {
                Text("Try again").font(.inter(11, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Nuru.navy, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
    }
}

// MARK: - Leader: compose a post

private struct DepartmentPostComposer: View {
    /// Returns true when the server accepted the post — the sheet then closes.
    let onPost: (String, String?) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var body_ = ""
    @State private var imageUrl = ""
    @State private var busy = false
    @FocusState private var focused: Bool

    private var trimmedBody: String { body_.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedUrl: String { imageUrl.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var urlOk: Bool {
        trimmedUrl.isEmpty || (URL(string: trimmedUrl).map { $0.scheme == "https" || $0.scheme == "http" } ?? false)
    }

    var body: some View {
        PSheetShell(title: "Write a post") {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("An update for everyone on the team — what's coming up, what went well, what you need hands for.")
                    .font(.nCaption).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)
                ZStack(alignment: .topLeading) {
                    if body_.isEmpty {
                        Text("What's happening in the team?")
                            .font(.nBody).foregroundStyle(Nuru.ink400)
                            .padding(.horizontal, 17).padding(.vertical, 18)
                    }
                    TextEditor(text: $body_)
                        .font(.nBody).foregroundStyle(Nuru.ink)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .frame(minHeight: 150)
                        .focused($focused)
                }
                .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                VStack(alignment: .leading, spacing: 6) {
                    Text("IMAGE LINK (OPTIONAL)").font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x74808F))
                    NuruField(placeholder: "https://…", text: $imageUrl, keyboard: .URL)
                    if !urlOk {
                        Text("That doesn't look like a web link.").font(.nCaption).foregroundStyle(Nuru.danger)
                    }
                }
                GoldSheetButton(title: "Post to the team", busy: busy, disabled: trimmedBody.isEmpty || !urlOk) {
                    Haptics.action()
                    busy = true
                    Task {
                        let ok = await onPost(trimmedBody, trimmedUrl.isEmpty ? nil : trimmedUrl)
                        busy = false
                        if ok { dismiss() }
                    }
                }
            }
        }
        .onAppear { focused = true }
    }
}

// MARK: - Leader: submit a need (the office approves → a campaign is born, §4)

private struct DepartmentNeedForm: View {
    var currency: String = "KES"
    /// (title, why, target_minor, currency, deadline yyyy-MM-dd?) → accepted?
    let onSubmit: (String, String, Int, String, String?) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var why = ""
    @State private var amount = ""
    @State private var hasDeadline = false
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var busy = false

    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedWhy: String { why.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var amountMajor: Int? {
        let digits = amount.filter(\.isNumber)
        guard let v = Int(digits), v > 0 else { return nil }
        return v
    }
    private var canSubmit: Bool { !trimmedTitle.isEmpty && !trimmedWhy.isEmpty && amountMajor != nil }

    var body: some View {
        PSheetShell(title: "Submit a need") {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                Text("Tell the office what the team needs and why. Once approved, it opens for giving on this page.")
                    .font(.nCaption).foregroundStyle(Nuru.ink600)
                    .fixedSize(horizontal: false, vertical: true)

                labelled("WHAT IS NEEDED") {
                    sentenceField("e.g. Two wireless microphones", text: $title)
                }
                labelled("WHY IT MATTERS") {
                    ZStack(alignment: .topLeading) {
                        if why.isEmpty {
                            Text("A sentence or two the office can read.")
                                .font(.nBody).foregroundStyle(Nuru.ink400)
                                .padding(.horizontal, 17).padding(.vertical, 18)
                        }
                        TextEditor(text: $why)
                            .font(.nBody).foregroundStyle(Nuru.ink)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 12).padding(.vertical, 10)
                            .frame(minHeight: 110)
                    }
                    .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                }
                labelled("AMOUNT (\(currency))") {
                    NuruField(placeholder: "e.g. 20000", text: $amount, keyboard: .numberPad)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $hasDeadline.animation(.easeInOut(duration: 0.2))) {
                        Text("Needed by a date").font(.nBody).foregroundStyle(Nuru.ink)
                    }
                    .tint(Nuru.gold)
                    if hasDeadline {
                        DatePicker("Deadline", selection: $deadline, in: Date()..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .font(.nBody)
                            .tint(Nuru.navy)
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))

                GoldSheetButton(title: "Submit for approval", busy: busy, disabled: !canSubmit) {
                    guard let major = amountMajor else { return }
                    Haptics.action()
                    busy = true
                    let dl: String? = hasDeadline ? Self.dayString(deadline) : nil
                    Task {
                        let ok = await onSubmit(trimmedTitle, trimmedWhy, major * 100, currency, dl)
                        busy = false
                        if ok { dismiss() }
                    }
                }
            }
        }
    }

    private func labelled<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.inter(10, .semibold)).kerning(1.2).foregroundStyle(Color(hex: 0x74808F))
            content()
        }
    }

    /// A text field with sentence capitalisation (NuruField turns it off — right for emails, wrong here).
    private func sentenceField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .textInputAutocapitalization(.sentences)
            .font(.nBody)
            .padding(.horizontal, Nuru.S.base)
            .frame(height: Nuru.buttonHeightMd)
            .background(Nuru.inputBg, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
    }

    private static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
