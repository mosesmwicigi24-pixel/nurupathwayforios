// Cohort Discussions — the cell's shared board (backend community module, B8).
// Threads the member's cell posts and talks under: list with pinned-first
// ordering, a compose sheet, and a thread page with comments + composer.
// Posting is offline-resilient: writes go through the durable sync queue
// (discussion_threads:create / discussion_comments:create) with client-minted
// ids, appear optimistically, and roll back only if the server rejects them.
// Styled to the Prayer Wall's design language (cream cards, Fraunces, gold).
import SwiftUI

// MARK: - Board (thread list)

@MainActor
final class DiscussionsViewModel: ObservableObject {
    @Published var threads: [DiscussionThread] = []
    /// Optimistic rows queued locally but not yet confirmed by the server.
    @Published var pending: [DiscussionThread] = []
    @Published var loading = true
    @Published var error: String?

    /// What the screen renders: queued posts on top, then the server's board
    /// (pinned first, newest next). Ids compare lowercased so the server echo
    /// of a client-minted uuid dedupes exactly.
    var board: [DiscussionThread] {
        let landed = Set(threads.map { $0.threadId.lowercased() })
        return pending.filter { !landed.contains($0.threadId.lowercased()) } + threads
    }

    func load() async {
        loading = threads.isEmpty && pending.isEmpty
        error = nil
        do {
            threads = try await MemberAPI.discussionThreads()
            prunePending()
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't load your cell's board."
        }
        loading = false
    }

    /// Optimistic + durable: the card appears instantly, the write rides the
    /// offline queue. Returns false (after rolling the card back) only if the
    /// queue refused it or the server rejected the flushed mutation.
    func post(title: String, body: String, authorUserId: String, authorName: String) async -> Bool {
        let tid = UUID().uuidString.lowercased()
        pending.insert(DiscussionThread(
            threadId: tid, title: title, body: body, isPinned: false, isLocked: false,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            authorUserId: authorUserId, authorName: authorName, commentCount: 0), at: 0)
        let queued = await SyncCoordinator.shared.enqueue(domain: "discussion_threads", op: "create", payload: [
            "thread_id": AnyCodable(tid),
            "title": AnyCodable(title),
            "body": AnyCodable(body),
        ])
        guard queued else {
            pending.removeAll { $0.threadId == tid }
            return false
        }
        if SyncCoordinator.shared.isOnline {
            await load()
            // Flushed but never landed and nothing left queued ⇒ rejected. Roll back.
            if !threads.contains(where: { $0.threadId.lowercased() == tid }),
               SyncCoordinator.shared.pendingCount == 0 {
                pending.removeAll { $0.threadId == tid }
                return false
            }
        }
        return true
    }

    private func prunePending() {
        let landed = Set(threads.map { $0.threadId.lowercased() })
        pending.removeAll { landed.contains($0.threadId.lowercased()) }
    }
}

struct DiscussionsView: View {
    @StateObject private var vm = DiscussionsViewModel()
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss
    @State private var composing = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    if vm.loading && vm.board.isEmpty {
                        ForEach(0..<3, id: \.self) { i in
                            SkeletonThreadCard().gentleEntrance(delay: Double(i) * 0.08)
                        }
                    } else if vm.board.isEmpty, let err = vm.error {
                        errorState(err)
                    } else if vm.board.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.board) { thread in
                            threadRow(thread)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.board.map(\.threadId))
            }
        }
        .background(Nuru.coolPaper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await vm.load() }
        .task { if vm.threads.isEmpty { await vm.load() } }
        .sheet(isPresented: $composing) {
            DiscussionComposeSheet { title, body_ in
                await vm.post(title: title, body: body_,
                              authorUserId: auth.profile?.userId ?? "",
                              authorName: auth.profile?.fullName ?? "You")
            }
        }
    }

    /// A queued (not-yet-synced) card isn't navigable — its thread page doesn't
    /// exist server-side until the queue flushes.
    @ViewBuilder
    private func threadRow(_ thread: DiscussionThread) -> some View {
        let queued = !vm.threads.contains { $0.threadId.lowercased() == thread.threadId.lowercased() }
        if queued {
            ThreadCardView(thread: thread, queued: true)
        } else {
            NavigationLink(value: CommunityRoute.discussion(thread.threadId)) {
                ThreadCardView(thread: thread, queued: false)
            }
            .buttonStyle(.pressableSubtle)
            .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        }
    }

    // Full-bleed hero — same anatomy as the Prayer Wall's (brand gradient,
    // back + compose controls, kicker/title/verse).
    private var hero: some View {
        ZStack(alignment: .bottom) {
            Nuru.heroGradient
                .frame(maxWidth: .infinity).frame(height: 240).clipped()
            Color(hex: 0x081C36, alpha: 0.55)
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Icon(.arrowLeft, size: 18, color: .white)
                            .frame(width: 40, height: 40).background(Color.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                    Button { Haptics.tap(); composing = true } label: {
                        Icon(.plus, size: 18, color: Nuru.navyDeep)
                            .frame(width: 40, height: 40).background(Nuru.gold, in: Circle())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(.horizontal, Nuru.S.lg).padding(.top, 54)
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("YOUR CELL'S BOARD").font(.inter(11, .medium)).kerning(1.8).foregroundStyle(Nuru.gold)
                    Text("Cohort Discussions").font(.fraunces(24, .semibold)).foregroundStyle(.white)
                    Text("“Let us consider how we may spur one another on toward love and good deeds.” — Hebrews 10:24")
                        .font(.nCaption).foregroundStyle(Nuru.onNavyDim).lineLimit(2).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Nuru.S.lg)
            }
        }
        .frame(height: 240)
        .clipShape(.rect(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
    }

    private var emptyState: some View {
        VStack(spacing: Nuru.S.sm) {
            Icon(.users, size: 32, color: Nuru.gold)
            Text("Nothing here yet").font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
            Text("Start the first conversation in your cell.")
                .font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            Button { Haptics.tap(); composing = true } label: {
                Text("Start a discussion").font(.inter(12, .bold)).foregroundStyle(Nuru.navyDeep)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Nuru.goldChipBg, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.gold, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .padding(.top, Nuru.S.xs)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xxl)
        .gentleEntrance()
    }

    /// Honest failure state — includes the server's 422 "Join a cell group…" case.
    private func errorState(_ message: String) -> some View {
        VStack(spacing: Nuru.S.sm) {
            Text(message).font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            Button { Task { await vm.load() } } label: {
                Text("Try again").font(.inter(12, .bold)).foregroundStyle(Nuru.navyDeep)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Nuru.goldChipBg, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.gold, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xxl)
    }
}

/// Shimmering placeholder matching the thread-card anatomy (first load only).
private struct SkeletonThreadCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 220, height: 14)
            RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(maxWidth: .infinity).frame(height: 10)
            RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 180, height: 10)
            HStack(spacing: Nuru.S.sm) {
                Circle().fill(Nuru.surface).frame(width: 24, height: 24)
                RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 90, height: 9)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 40, height: 9)
            }
            .padding(.top, Nuru.S.xs)
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShimmer()
    }
}

private struct ThreadCardView: View {
    let thread: DiscussionThread
    let queued: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Nuru.S.sm) {
                Text(thread.title).font(.nHeading).foregroundStyle(Nuru.ink)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if thread.isPinned { pinnedChip }
                if queued { queuedChip }
            }
            Text(thread.body).font(.nBody).foregroundStyle(Nuru.muted).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: nil, name: thread.authorName, size: 24)
                Text(thread.authorName).font(.inter(12, .bold)).foregroundStyle(Nuru.ink600).lineLimit(1)
                Text("·").font(.nMicro).foregroundStyle(Nuru.faint)
                Text(timeAgo(thread.createdAt)).font(.nMicro).foregroundStyle(Nuru.faint)
                Spacer(minLength: 0)
                if thread.isLocked {
                    Icon(.lock, size: 13, color: Nuru.faint)
                }
                HStack(spacing: 4) {
                    Icon(.messageCircle, size: 14, color: Nuru.faint)
                    Text("\(thread.commentCount ?? 0)").font(.nCaption).foregroundStyle(Nuru.faint)
                }
            }
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .opacity(queued ? 0.75 : 1)
    }

    private var pinnedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Nuru.gold)
            Text("Pinned").font(.nMicro).foregroundStyle(Nuru.ink600)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Nuru.goldChipBg, in: Capsule())
        .overlay(Capsule().stroke(Nuru.gold, lineWidth: 1))
    }

    private var queuedChip: some View {
        Text("Posting…").font(.nMicro).foregroundStyle(Nuru.faint)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Nuru.mutedBg, in: Capsule())
    }
}

// MARK: - Compose sheet (new thread — title 3…200 chars + body, per the zod schema)

private struct DiscussionComposeSheet: View {
    /// Posts through the offline queue; false means the card was rolled back.
    let onPost: (_ title: String, _ body: String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var busy = false
    @State private var err: String?

    private var invalid: Bool { title.trimmed.count < 3 || body_.trimmed.isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    Text("Everyone in your cell can read and reply.")
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                    TextField("What's this about?", text: $title)
                        .font(.inter(15)).padding(.horizontal, Nuru.S.base).frame(height: 44)
                        .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: Nuru.R.control))
                        .overlay(RoundedRectangle(cornerRadius: Nuru.R.control).stroke(Nuru.border, lineWidth: 1))
                        .padding(.top, Nuru.S.base)
                    TextField("Share a thought, a question, a word…", text: $body_, axis: .vertical)
                        .font(.inter(15)).lineLimit(5...10).padding(Nuru.S.base)
                        .frame(minHeight: 110, alignment: .topLeading)
                        .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: Nuru.R.control))
                        .overlay(RoundedRectangle(cornerRadius: Nuru.R.control).stroke(Nuru.border, lineWidth: 1))
                    if let err { Text(err).font(.nCaption).foregroundStyle(Nuru.error) }
                    Button { Task { await post() } } label: {
                        Text(busy ? "Posting…" : "Post to your cell")
                            .font(.nHeading).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: Nuru.R.button))
                    }
                    .buttonStyle(.pressable)
                    .disabled(busy || invalid)
                    .opacity(busy || invalid ? 0.5 : 1)
                    .animation(.easeInOut(duration: 0.2), value: busy || invalid)
                    .padding(.top, Nuru.S.base)
                }
                .padding(Nuru.S.lg)
            }
            .background(Nuru.white.ignoresSafeArea())
            .navigationTitle("Start a discussion")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func post() async {
        guard !invalid else { return }
        Haptics.action()
        busy = true; err = nil
        if await onPost(title.trimmed, body_.trimmed) {
            Haptics.success()
            dismiss()
        } else {
            Haptics.error()
            err = "Couldn't post to your cell. Try again."
            busy = false
        }
    }
}

// MARK: - Thread page (post + comments + composer)

@MainActor
final class DiscussionThreadViewModel: ObservableObject {
    @Published var detail: DiscussionThreadDetail?
    /// Optimistic comments queued locally but not yet echoed by the server.
    @Published var pendingComments: [DiscussionComment] = []
    @Published var loading = true
    @Published var error: String?
    @Published var draft = ""
    @Published var sending = false

    let threadId: String
    init(threadId: String) { self.threadId = threadId }

    var comments: [DiscussionComment] {
        let landed = Set((detail?.comments ?? []).map { $0.commentId.lowercased() })
        return (detail?.comments ?? []) + pendingComments.filter { !landed.contains($0.commentId.lowercased()) }
    }

    func load() async {
        loading = detail == nil
        error = nil
        do {
            detail = try await MemberAPI.discussionThread(threadId)
            let landed = Set((detail?.comments ?? []).map { $0.commentId.lowercased() })
            pendingComments.removeAll { landed.contains($0.commentId.lowercased()) }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? "Couldn't open this discussion."
        }
        loading = false
    }

    /// Optimistic + durable send through the offline queue; on a server
    /// rejection the bubble rolls back and the words return to the draft.
    func send(authorUserId: String, authorName: String) async {
        let body = draft.trimmed
        guard !body.isEmpty, !sending else { return }
        sending = true; defer { sending = false }
        let cid = UUID().uuidString.lowercased()
        pendingComments.append(DiscussionComment(
            commentId: cid, body: body, createdAt: ISO8601DateFormatter().string(from: Date()),
            authorUserId: authorUserId, authorName: authorName))
        draft = ""
        let queued = await SyncCoordinator.shared.enqueue(domain: "discussion_comments", op: "create", payload: [
            "comment_id": AnyCodable(cid),
            "thread_id": AnyCodable(threadId),
            "body": AnyCodable(body),
        ])
        guard queued else { rollback(cid, body: body); return }
        if SyncCoordinator.shared.isOnline {
            await load()
            // Flushed but never echoed and nothing left queued ⇒ rejected
            // (e.g. the thread was locked or hidden meanwhile).
            if !(detail?.comments ?? []).contains(where: { $0.commentId.lowercased() == cid }),
               SyncCoordinator.shared.pendingCount == 0 {
                rollback(cid, body: body)
            }
        }
    }

    private func rollback(_ commentId: String, body: String) {
        pendingComments.removeAll { $0.commentId == commentId }
        if draft.trimmed.isEmpty { draft = body }   // the words aren't lost
        Haptics.error()
    }
}

struct DiscussionThreadView: View {
    @StateObject private var vm: DiscussionThreadViewModel
    @EnvironmentObject private var auth: AuthStore
    @Environment(\.dismiss) private var dismiss

    init(threadId: String) { _vm = StateObject(wrappedValue: DiscussionThreadViewModel(threadId: threadId)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.loading && vm.detail == nil {
                Spacer(); ProgressView(); Spacer()
            } else if let d = vm.detail {
                content(d)
                if d.isLocked { lockedNotice } else { composer }
            } else {
                Spacer()
                VStack(spacing: Nuru.S.md) {
                    Text(vm.error ?? "Couldn't open this discussion.")
                        .font(.nBody).foregroundStyle(Nuru.muted)
                        .multilineTextAlignment(.center).padding(.horizontal, Nuru.S.xl)
                    Button { Task { await vm.load() } } label: {
                        Text("Try again").font(.inter(12, .bold)).foregroundStyle(Nuru.navyDeep)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Nuru.goldChipBg, in: Capsule())
                            .overlay(Capsule().stroke(Nuru.gold, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
                Spacer()
            }
        }
        .background(Nuru.coolPaper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
    }

    private var header: some View {
        HStack(spacing: Nuru.S.md) {
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: .white)
                    .frame(width: 40, height: 40).background(Color.white.opacity(0.10), in: Circle())
            }
            Text("Discussion").font(.fraunces(20, .semibold)).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, Nuru.S.lg).padding(.top, 54).padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
    }

    private func content(_ d: DiscussionThreadDetail) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                threadCard(d)
                Text(vm.comments.isEmpty ? "BE THE FIRST TO REPLY"
                     : "\(vm.comments.count) \(vm.comments.count == 1 ? "REPLY" : "REPLIES")")
                    .font(.nMicro).kerning(0.6).foregroundStyle(Nuru.faint)
                    .padding(.top, Nuru.S.lg).padding(.bottom, Nuru.S.sm)
                ForEach(vm.comments) { cm in
                    commentCard(cm).transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.comments.count)
        }
        .refreshable { await vm.load() }
    }

    private func threadCard(_ d: DiscussionThreadDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: nil, name: d.authorName, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(d.authorName).font(.nHeading).foregroundStyle(Nuru.ink).lineLimit(1)
                    Text(whenString(d.createdAt)).font(.nMicro).foregroundStyle(Nuru.faint)
                }
                Spacer(minLength: 0)
                if d.isPinned {
                    HStack(spacing: 4) {
                        Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(Nuru.gold)
                        Text("Pinned").font(.nMicro).foregroundStyle(Nuru.ink600)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Nuru.goldChipBg, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.gold, lineWidth: 1))
                }
            }
            Text(d.title).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.md)
            Text(d.body).font(.nBodyLg).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func commentCard(_ cm: DiscussionComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: nil, name: cm.authorName, size: 28)
                Text(cm.authorName).font(.inter(12, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(whenString(cm.createdAt)).font(.nMicro).foregroundStyle(Nuru.faint)
            }
            Text(cm.body).font(.nBody).foregroundStyle(Nuru.ink)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .padding(.bottom, Nuru.S.sm)
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Nuru.S.sm) {
            TextField("Add to the conversation…", text: $vm.draft, axis: .vertical)
                .font(.inter(15)).lineLimit(1...5)
                .padding(.horizontal, Nuru.S.base).padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: Nuru.R.control))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.control).stroke(Nuru.border, lineWidth: 1))
            Button {
                Haptics.action()
                Task {
                    await vm.send(authorUserId: auth.profile?.userId ?? "",
                                  authorName: auth.profile?.fullName ?? "You")
                }
            } label: {
                Icon(.send, size: 17, color: .white)
                    .frame(width: 44, height: 44).background(Nuru.navyDeep, in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(vm.sending || vm.draft.trimmed.isEmpty)
            .opacity(vm.sending || vm.draft.trimmed.isEmpty ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.2), value: vm.sending || vm.draft.trimmed.isEmpty)
        }
        .padding(Nuru.S.sm)
        .background(Nuru.white)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }

    private var lockedNotice: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.lock, size: 14, color: Nuru.faint)
            Text("This discussion has been locked by a leader.")
                .font(.nCaption).foregroundStyle(Nuru.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(Nuru.S.base)
        .background(Nuru.white)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }

    private func whenString(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
