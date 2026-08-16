// "Read with a Friend" — R3 client (spec §3/§6; docs/READING_SOCIAL_PLAN.md
// §4). Reuses the Plans tab's PL palette + card language (ReadingPlanCards.swift)
// and the chat epic's connection graph (MemberAPI+Connections.swift) for the
// friend picker — no second consent model. Wire shapes: Models/ReadingSocial.swift.
import SwiftUI
import UIKit

/// Presents the system share sheet with the given items — the native counterpart
/// used for every "share this link" moment in this feature (mirrors the pattern
/// ProfileView uses for the certificate PDF).
@MainActor
func presentSystemShareSheet(_ items: [Any]) {
    guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
          let root = scene.keyWindow?.rootViewController else { return }
    var top = root
    while let presented = top.presentedViewController { top = presented }
    let avc = UIActivityViewController(activityItems: items, applicationActivities: nil)
    avc.popoverPresentationController?.sourceView = top.view
    avc.popoverPresentationController?.sourceRect = CGRect(
        x: top.view.bounds.midX, y: top.view.bounds.midY, width: 1, height: 1)
    top.present(avc, animated: true)
}

/// The rich invite message shared alongside the /join/{token} link (spec §6:
/// "plan title · N days · 'Join me reading <title> on Nuru Pathway'").
func readingInviteMessage(planTitle: String, dayCount: Int, joinUrl: URL) -> String {
    "Join me reading \"\(planTitle)\" on Nuru Pathway — a \(dayCount)-day plan. \(joinUrl.absoluteString)"
}

// MARK: - Hub: "my active shared groups"

@MainActor
final class ReadWithFriendHubViewModel: ObservableObject {
    @Published var groups: [ReadingGroupRow] = []
    @Published var loading = true
    @Published var error: String?

    var active: [ReadingGroupRow] { groups.filter { !$0.isArchived } }

    func load() async {
        loading = true; error = nil
        do { groups = try await MemberAPI.myReadingGroups() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your shared plans." }
        loading = false
    }
}

struct ReadWithFriendHubView: View {
    @StateObject private var vm = ReadWithFriendHubViewModel()
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss

    private var myUserId: String { auth.me?.profile.userId ?? "" }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                header
                LoadStateView(loading: vm.loading && vm.groups.isEmpty,
                              isEmpty: vm.active.isEmpty, error: vm.error,
                              emptyText: "", retry: { Task { await vm.load() } }) {
                    if vm.active.isEmpty {
                        emptyState
                    } else {
                        VStack(spacing: 14) {
                            ForEach(vm.active) { g in
                                NavigationLink(value: g) {
                                    ReadingGroupCard(group: g, myUserId: myUserId)
                                }
                                .buttonStyle(.pressable)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, Nuru.tabBarSpace + 20)
        }
        .background(LinearGradient(colors: [PL.cream, PL.creamLo], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .refreshable { await vm.load() }
        .onAppear { tabs.chromeHidden = true }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.chevronLeft, size: 18, color: PL.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(PL.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            VStack(alignment: .leading, spacing: 2) {
                Text("READ WITH A FRIEND").font(.inter(9, .bold)).kerning(1.6).foregroundStyle(PL.catText)
                Text("Your shared plans").font(.fraunces(22, .medium)).kerning(-0.4).foregroundStyle(PL.navy)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 44)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(PL.gold.opacity(0.1))
                Icon(.users, size: 26, color: PL.gold)
            }
            .frame(width: 64, height: 64)
            Text("Read together").font(.fraunces(18, .medium)).foregroundStyle(PL.navy)
            Text("Invite a friend to any plan and keep each other going — see how far they've come and cheer them on.")
                .font(.inter(13)).foregroundStyle(PL.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { Haptics.tap(); dismiss() } label: {
                Text("Browse plans").font(.inter(13, .bold)).foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(PL.navy, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48).padding(.horizontal, 24)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }
}

/// Group card — plan cover + title, the OTHER active members' avatars, and a
/// per-friend progress row ("Doris · Day 3 of 7") for up to three of them.
struct ReadingGroupCard: View {
    let group: ReadingGroupRow
    let myUserId: String

    private var others: [ReadingGroupMember] { group.otherMembers(excluding: myUserId) }
    private func firstName(_ s: String) -> String { s.split(separator: " ").first.map(String.init) ?? s }
    private func dayLabel(_ m: ReadingGroupMember) -> String {
        "Day \(max(m.currentDay ?? 1, 1)) of \(group.plan.dayCount)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                cover
                VStack(alignment: .leading, spacing: 5) {
                    Text(group.plan.title).font(.fraunces(15, .medium)).kerning(-0.15)
                        .foregroundStyle(PL.navy).lineLimit(1)
                    HStack(spacing: -8) {
                        ForEach(others.prefix(5)) { m in
                            Avatar(url: m.avatarUrl, name: m.fullName, size: 24)
                                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                        }
                        if others.isEmpty {
                            Text("Just you so far").font(.inter(11)).foregroundStyle(PL.ink3)
                        }
                    }
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 15, color: PL.ink3)
            }
            if !others.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(others.prefix(3)) { m in
                        HStack(spacing: 6) {
                            Text(firstName(m.fullName)).font(.inter(12, .semibold)).foregroundStyle(PL.blurb)
                            Text("· \(dayLabel(m))").font(.inter(12)).foregroundStyle(PL.ink3)
                            Spacer(minLength: 0)
                        }
                    }
                    if others.count > 3 {
                        Text("+ \(others.count - 3) more").font(.inter(11, .semibold)).foregroundStyle(PL.goldDeep)
                    }
                }
                .padding(.top, 2)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private var cover: some View {
        ZStack {
            LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let u = group.plan.imageUrl.flatMap(URL.init) {
                Color.clear.overlay {
                    CachedAsyncImage(url: u) { p in
                        if let img = p.image { img.resizable().scaledToFill() } else { Color.clear }
                    }
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - Group detail: roster + progress, invite, leave/archive

@MainActor
final class ReadingGroupDetailViewModel: ObservableObject {
    @Published var group: ReadingGroupRow?
    @Published var pendingInvites: [ReadingInviteRow] = []
    @Published var loading = true
    @Published var error: String?
    @Published var busy = false
    @Published var toast: String?

    let groupId: String
    init(groupId: String, preloaded: ReadingGroupRow?) {
        self.groupId = groupId
        self.group = preloaded
    }

    /// Always re-fetches — the roster + per-friend progress must reflect the
    /// LATEST reads, not a cached snapshot from when the hub last loaded.
    func load() async {
        loading = (group == nil)
        error = nil
        do {
            group = try await MemberAPI.readingGroup(groupId)
            pendingInvites = (try? await MemberAPI.listReadingInvites(groupId: groupId))?.filter(\.isPending) ?? []
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this shared plan."
        }
        loading = false
    }

    func inviteFriend(userId: String) async {
        do {
            _ = try await MemberAPI.createReadingInvite(groupId: groupId, userId: userId)
            Haptics.success()
            toast = "Invite sent"
            await load()
        } catch {
            Haptics.error()
            toast = (error as? APIError)?.errorDescription ?? "Couldn't send that invite."
        }
    }

    /// Mint (or reuse) an open share-link and hand the join URL + rich
    /// message to the system share sheet.
    func shareOpenLink() async {
        guard let plan = group?.plan else { return }
        do {
            let invite = try await MemberAPI.createReadingInvite(groupId: groupId)
            let url = MemberAPI.readingJoinURL(token: invite.token)
            let message = readingInviteMessage(planTitle: plan.title, dayCount: plan.dayCount, joinUrl: url)
            Haptics.success()
            presentSystemShareSheet([message])
        } catch {
            Haptics.error()
            toast = (error as? APIError)?.errorDescription ?? "Couldn't create a share link."
        }
    }

    func revoke(_ invite: ReadingInviteRow) async {
        do { try await MemberAPI.revokeReadingInvite(groupId: groupId, inviteId: invite.inviteId); await load() }
        catch { toast = (error as? APIError)?.errorDescription ?? "Couldn't revoke that invite." }
    }

    @discardableResult
    func leave() async -> Bool {
        busy = true; defer { busy = false }
        do { try await MemberAPI.leaveReadingGroup(groupId); return true }
        catch { toast = (error as? APIError)?.errorDescription ?? "Couldn't leave — try again."; return false }
    }

    func archive() async {
        busy = true; defer { busy = false }
        do { try await MemberAPI.archiveReadingGroup(groupId); await load() }
        catch { toast = (error as? APIError)?.errorDescription ?? "Couldn't end this shared plan." }
    }
}

struct ReadingGroupDetailView: View {
    let groupId: String
    var preloaded: ReadingGroupRow?
    @StateObject private var vm: ReadingGroupDetailViewModel
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var showFriendPicker = false
    @State private var showLeaveConfirm = false

    init(groupId: String, preloaded: ReadingGroupRow? = nil) {
        self.groupId = groupId
        self.preloaded = preloaded
        _vm = StateObject(wrappedValue: ReadingGroupDetailViewModel(groupId: groupId, preloaded: preloaded))
    }

    private var myUserId: String { auth.me?.profile.userId ?? "" }
    private var isCreator: Bool { vm.group?.createdBy == myUserId && !myUserId.isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            PL.cream.ignoresSafeArea()
            if let g = vm.group {
                content(g)
            } else if vm.loading {
                VStack(spacing: 12) {
                    ProgressView().tint(PL.gold)
                    Text("Loading your shared plan…").font(.inter(12, .medium)).foregroundStyle(PL.ink3)
                }
            } else {
                VStack(spacing: 12) {
                    Text(vm.error ?? "Couldn't load this shared plan.").font(.nBody).foregroundStyle(PL.ink2)
                    Button { Haptics.tap(); Task { await vm.load() } } label: {
                        Text("Try again").font(.inter(14, .semibold)).foregroundStyle(PL.gold)
                    }
                    .buttonStyle(.pressable)
                }
            }
            if let toast = vm.toast { toastView(toast) }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // "refreshing on appear" — the roster's progress is a moving target.
        .task { await vm.load() }
        .onAppear { tabs.chromeHidden = true }
        .sheet(isPresented: $showFriendPicker) {
            FriendPickerSheet(alreadyIn: Set((vm.group?.members ?? []).filter(\.isActive).map(\.userId))) { userId in
                Task { await vm.inviteFriend(userId: userId) }
            }
        }
        .confirmationDialog("Leave this shared plan?", isPresented: $showLeaveConfirm, titleVisibility: .visible) {
            Button("Leave", role: .destructive) {
                Task { if await vm.leave() { dismiss() } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can rejoin later with a fresh invite.")
        }
        .onChange(of: vm.toast) { _, t in
            guard t != nil else { return }
            Task {
                try? await Task.sleep(nanoseconds: 2_400_000_000)
                withAnimation { vm.toast = nil }
            }
        }
    }

    private func content(_ g: ReadingGroupRow) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 16) {
                headerBar
                heroCard(g)
                rosterCard(g)
                if isCreator, !vm.pendingInvites.isEmpty { pendingInvitesCard }
                actionsCard(g)
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, Nuru.tabBarSpace + 32)
        }
    }

    private var headerBar: some View {
        HStack {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.chevronLeft, size: 18, color: PL.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: Circle())
                    .overlay(Circle().stroke(PL.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            Spacer(minLength: 0)
        }
        .padding(.top, 24)
    }

    private func heroCard(_ g: ReadingGroupRow) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let u = g.plan.imageUrl.flatMap(URL.init) {
                    Color.clear.overlay {
                        CachedAsyncImage(url: u) { p in
                            if let img = p.image { img.resizable().scaledToFill() } else { Color.clear }
                        }
                    }
                }
            }
            .frame(height: 140).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text("READING TOGETHER").font(.inter(9, .bold)).kerning(1.5).foregroundStyle(PL.goldDeep)
                Text(g.plan.title).font(.fraunces(20, .medium)).kerning(-0.4).foregroundStyle(PL.navy)
                Text("\(g.plan.dayCount)-day plan · \(g.members.filter(\.isActive).count) reading together")
                    .font(.inter(12)).foregroundStyle(PL.ink3)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private func rosterCard(_ g: ReadingGroupRow) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHO'S READING").font(.nCardKicker).kerning(1.4).foregroundStyle(PL.goldDeep)
            VStack(spacing: 0) {
                ForEach(g.members.filter(\.isActive)) { m in
                    memberRow(m, dayCount: g.plan.dayCount, isMe: m.userId == myUserId)
                    if m.id != g.members.filter(\.isActive).last?.id {
                        Rectangle().fill(PL.border).frame(height: 1).padding(.leading, 52)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private func memberRow(_ m: ReadingGroupMember, dayCount: Int, isMe: Bool) -> some View {
        let done = max(m.daysDone, 0)
        let pct = dayCount > 0 ? min(1, Double(done) / Double(dayCount)) : 0
        return HStack(spacing: 12) {
            Avatar(url: m.avatarUrl, name: m.fullName, size: 38)
            VStack(alignment: .leading, spacing: 4) {
                Text(isMe ? "\(m.fullName) (you)" : m.fullName)
                    .font(.inter(13, .semibold)).foregroundStyle(PL.navy)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(PL.border).frame(height: 5)
                        Capsule().fill(PL.gold).frame(width: geo.size.width * pct, height: 5)
                    }
                }
                .frame(height: 5)
            }
            Text("Day \(max(m.currentDay ?? 1, 1)) of \(dayCount)")
                .font(.inter(11, .bold)).foregroundStyle(PL.catText)
                .lineLimit(1).fixedSize()
        }
        .padding(.vertical, 10)
    }

    private var pendingInvitesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PENDING INVITES").font(.nCardKicker).kerning(1.4).foregroundStyle(PL.goldDeep)
            ForEach(vm.pendingInvites) { invite in
                HStack {
                    Icon(.clock, size: 14, color: PL.ink3)
                    Text(invite.isOpenLink ? "Open link" : "Invite sent").font(.inter(12)).foregroundStyle(PL.ink2)
                    Spacer(minLength: 0)
                    Button { Haptics.tap(); Task { await vm.revoke(invite) } } label: {
                        Text("Revoke").font(.inter(11, .bold)).foregroundStyle(.red)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private func actionsCard(_ g: ReadingGroupRow) -> some View {
        VStack(spacing: 10) {
            Button { Haptics.tap(); showFriendPicker = true } label: {
                actionRow(.users, "Invite a friend", tint: PL.navy)
            }.buttonStyle(.pressable)
            Button { Haptics.tap(); Task { await vm.shareOpenLink() } } label: {
                actionRow(.share2, "Share join link", tint: PL.navy)
            }.buttonStyle(.pressable)
            if isCreator {
                Button { Haptics.tap(); Task { await vm.archive() } } label: {
                    actionRow(.flag, "End this shared plan", tint: PL.ink2)
                }.buttonStyle(.pressable)
            }
            Button { Haptics.tap(); showLeaveConfirm = true } label: {
                actionRow(.logOut, "Leave", tint: .red)
            }.buttonStyle(.pressable)
        }
    }

    private func actionRow(_ icon: Lucide, _ label: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Icon(icon, size: 16, color: tint)
            Text(label).font(.inter(13, .semibold)).foregroundStyle(tint)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private func toastView(_ text: String) -> some View {
        Text(text).font(.inter(12, .semibold)).foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(PL.navy, in: Capsule())
            .padding(.bottom, Nuru.tabBarSpace + 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A value-route for pushing group detail from a group_id alone (a
/// notification tap or a deep link that only carries the group, not the
/// full row) — the destination fetches fresh either way.
struct ReadingGroupIdRef: Hashable, Sendable { let groupId: String }

// MARK: - Friend picker (targeted invite) — reuses the chat connection graph

struct FriendPickerSheet: View {
    var alreadyIn: Set<String> = []
    let onPick: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var connections: [ConnectionRow] = []
    @State private var loading = true
    @State private var query = ""

    private var filtered: [ConnectionRow] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let candidates = connections.filter { $0.status == "accepted" && !alreadyIn.contains($0.userId) }
        return q.isEmpty ? candidates : candidates.filter { $0.fullName.lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if loading {
                    ProgressView()
                } else if filtered.isEmpty {
                    emptyState
                } else {
                    List(filtered) { c in
                        Button { Haptics.tap(); onPick(c.userId); dismiss() } label: {
                            HStack(spacing: 12) {
                                Avatar(url: c.avatarUrl, name: c.fullName, size: 36)
                                Text(c.fullName).font(.inter(14, .medium)).foregroundStyle(PL.navy)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $query, prompt: "Search your connections")
            .navigationTitle("Invite a friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                connections = (try? await MemberAPI.listConnections()) ?? []
                loading = false
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon(.users, size: 28, color: PL.ink3)
            Text("No connections yet").font(.inter(14, .semibold)).foregroundStyle(PL.navy)
            Text("Connect with someone in Chat first, then invite them to read together.")
                .font(.inter(12)).foregroundStyle(PL.ink2).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

// MARK: - Invite preview (deep link / pushed) — accept or decline

@MainActor
final class ReadingInvitePreviewViewModel: ObservableObject {
    @Published var preview: ReadingInvitePreview?
    @Published var loading = true
    @Published var error: String?
    @Published var busy = false
    @Published var result: ReadingInviteAcceptResult?
    @Published var declined = false

    let token: String
    init(token: String) { self.token = token }

    func load() async {
        loading = true; error = nil
        do { preview = try await MemberAPI.readingInvitePreview(token) }
        catch let err { error = (err as? APIError)?.errorDescription ?? "This invite link isn't available." }
        loading = false
    }

    func accept() async {
        busy = true; defer { busy = false }
        do { result = try await MemberAPI.acceptReadingInvite(token); Haptics.success() }
        catch let err { Haptics.error(); error = (err as? APIError)?.errorDescription ?? "Couldn't join — try again." }
    }

    func decline() async {
        busy = true; defer { busy = false }
        do { try await MemberAPI.declineReadingInvite(token); declined = true }
        catch let err { error = (err as? APIError)?.errorDescription ?? "Couldn't decline — try again." }
    }
}

struct ReadingInvitePreviewView: View {
    let token: String
    @StateObject private var vm: ReadingInvitePreviewViewModel
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss

    init(token: String) {
        self.token = token
        _vm = StateObject(wrappedValue: ReadingInvitePreviewViewModel(token: token))
    }

    var body: some View {
        ZStack {
            PL.cream.ignoresSafeArea()
            if let result = vm.result {
                joinedState(result)
            } else if vm.declined {
                declinedState
            } else if let p = vm.preview {
                previewState(p)
            } else if vm.loading {
                VStack(spacing: 12) {
                    ProgressView().tint(PL.gold)
                    Text("Opening your invite…").font(.inter(12, .medium)).foregroundStyle(PL.ink3)
                }
            } else {
                unavailableState
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.load() }
        .onAppear { tabs.chromeHidden = true }
    }

    private func previewState(_ p: ReadingInvitePreview) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button { Haptics.tap(); dismiss() } label: {
                    Icon(.x, size: 18, color: PL.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(PL.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20).padding(.top, 24)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    ZStack {
                        LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                        if let u = p.plan.imageUrl.flatMap(URL.init) {
                            Color.clear.overlay {
                                CachedAsyncImage(url: u) { ph in
                                    if let img = ph.image { img.resizable().scaledToFill() } else { Color.clear }
                                }
                            }
                        }
                    }
                    .frame(height: 200).frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: PL.navyDeep.opacity(0.35), radius: 18, y: 10)

                    VStack(spacing: 6) {
                        Text("\(p.inviter.fullName.split(separator: " ").first.map(String.init) ?? p.inviter.fullName) invited you to read")
                            .font(.inter(13, .semibold)).foregroundStyle(PL.ink2)
                        Text(p.plan.title).font(.fraunces(24, .medium)).kerning(-0.5)
                            .foregroundStyle(PL.navy).multilineTextAlignment(.center)
                        HStack(spacing: 16) {
                            metaChip(.clock, "\(p.plan.dayCount) days")
                            metaChip(.users, "\(p.memberCount) reading")
                        }
                        .padding(.top, 4)
                    }

                    if let msg = p.message, !msg.isEmpty {
                        Text("\u{201C}\(msg)\u{201D}").font(.fraunces(14)).italic()
                            .foregroundStyle(PL.blurb).multilineTextAlignment(.center)
                            .padding(16)
                            .background(PL.highlight, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let error = vm.error {
                        Text(error).font(.inter(12)).foregroundStyle(.red).multilineTextAlignment(.center)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 24)
            }

            VStack(spacing: 10) {
                Button {
                    Haptics.action(); Task { await vm.accept() }
                } label: {
                    HStack(spacing: 8) {
                        if vm.busy { ProgressView().tint(PL.navy) } else { Icon(.bookOpen, size: 16, color: PL.navy) }
                        Text("Join & start reading").font(.inter(14, .bold)).foregroundStyle(PL.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.pressable)
                .disabled(vm.busy)

                Button { Haptics.tap(); Task { await vm.decline() } } label: {
                    Text("Not now").font(.inter(13, .semibold)).foregroundStyle(PL.ink2)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.pressable)
                .disabled(vm.busy)
            }
            .padding(.horizontal, 20).padding(.bottom, 20)
        }
    }

    private func metaChip(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 12, color: PL.goldDeep)
            Text(text).font(.inter(11, .semibold)).foregroundStyle(PL.ink2)
        }
    }

    private func joinedState(_ result: ReadingInviteAcceptResult) -> some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(PL.gold.opacity(0.12))
                Icon(.check, size: 30, color: PL.goldDeep)
            }
            .frame(width: 72, height: 72)
            Text("You're in!").font(.fraunces(22, .medium)).foregroundStyle(PL.navy)
            Text("You've joined the plan — go see who's reading with you.")
                .font(.inter(13)).foregroundStyle(PL.ink2).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink(value: ReadingGroupIdRef(groupId: result.groupId)) {
                Text("Go to shared plan").font(.inter(14, .bold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(PL.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
        }
        .padding(32)
    }

    private var declinedState: some View {
        VStack(spacing: 14) {
            Icon(.x, size: 28, color: PL.ink3)
            Text("Invite declined").font(.fraunces(18, .medium)).foregroundStyle(PL.navy)
            Button { Haptics.tap(); dismiss() } label: {
                Text("Close").font(.inter(13, .bold)).foregroundStyle(PL.gold)
            }
            .buttonStyle(.pressable)
        }
        .padding(32)
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Icon(.bookOpen, size: 28, color: PL.ink3)
            Text(vm.error ?? "This invite link isn't available.")
                .font(.inter(14)).foregroundStyle(PL.ink2).multilineTextAlignment(.center)
            Button { Haptics.tap(); dismiss() } label: {
                Text("Close").font(.inter(13, .bold)).foregroundStyle(PL.gold)
            }
            .buttonStyle(.pressable)
        }
        .padding(32)
    }
}
