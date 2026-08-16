// A single prayer request on its own page — the native port of
// screens/PrayerWallDetailScreen.tsx: the post, who's praying (🙏 + emoji
// reactions), the author's controls (mark answered / make private), and comments.
import SwiftUI

private let quickReactions = ["🙏", "❤️", "🕊️", "🙌", "✨"]

@MainActor
final class PrayerWallDetailViewModel: ObservableObject {
    @Published var detail: PrayerWallDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var draft = ""
    @Published var sending = false

    let postId: String
    init(postId: String) { self.postId = postId }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.prayerWallGet(postId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't open this request." }
        loading = false
    }

    func react(_ emoji: String) async { _ = try? await MemberAPI.prayerWallReact(postId, emoji: emoji); await load() }

    func comment() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sending = true; defer { sending = false }
        do { try await MemberAPI.prayerWallComment(postId, body: body); draft = ""; await load() }
        catch { Haptics.error() }   // draft is kept so the words aren't lost
    }

    func toggleAnswered() async {
        guard let d = detail else { return }
        try? await MemberAPI.prayerWallAnswered(postId, answered: !d.post.isAnswered); await load()
    }
}

struct PrayerWallDetailView: View {
    @StateObject private var vm: PrayerWallDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(postId: String) { _vm = StateObject(wrappedValue: PrayerWallDetailViewModel(postId: postId)) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.loading && vm.detail == nil {
                Spacer(); ProgressView(); Spacer()
            } else if let d = vm.detail {
                content(d)
                composer(d)
            } else {
                Spacer()
                VStack(spacing: Nuru.S.md) {
                    Text(vm.error ?? "Couldn't open this request.")
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
            Text("Prayer").font(.fraunces(20, .semibold)).foregroundStyle(.white)
            Spacer()
        }
        .padding(.horizontal, Nuru.S.lg).padding(.top, 54).padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
    }

    private func content(_ d: PrayerWallDetail) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                postCard(d.post)
                Text(d.comments.isEmpty ? "BE THE FIRST TO ENCOURAGE"
                     : "\(d.comments.count) \(d.comments.count == 1 ? "REPLY" : "REPLIES")")
                    .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.faint)
                    .padding(.top, Nuru.S.lg).padding(.bottom, Nuru.S.sm)
                ForEach(d.comments) { cm in
                    commentCard(cm).transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: d.comments.count)
        }
        // Drag-to-dismiss the keyboard, same feel as the chat thread.
        .scrollDismissesKeyboard(.interactively)
    }

    private func postCard(_ post: PrayerWallPost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: post.authorAvatar, name: post.authorName, size: 40)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.authorName).font(.nHeading).foregroundStyle(Nuru.ink).lineLimit(1)
                    Text(whenString(post.createdAt)).font(.nCardMeta).foregroundStyle(Nuru.faint)
                }
                Spacer(minLength: 0)
                if post.isAnswered { answeredChip }
            }
            if let title = post.title, !title.isEmpty {
                Text(title).font(.nCardTitle).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.md)
            }
            Text(post.body).font(.nBodyLg).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Reaction bar
            HStack(spacing: Nuru.S.sm) {
                ForEach(quickReactions, id: \.self) { e in
                    let r = post.reactions.first { $0.emoji == e }
                    let mine = r?.mine ?? false
                    Button { Haptics.love(); Task { await vm.react(e) } } label: {
                        HStack(spacing: 4) {
                            Text(e).font(.system(size: 15))
                            if let r, r.count > 0 {
                                Text("\(r.count)").font(.nMicro).foregroundStyle(mine ? Nuru.navyDeep : Nuru.ink600)
                                    .contentTransition(.numericText(value: Double(r.count)))
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(mine ? Nuru.goldChipBg : Nuru.surface, in: Capsule())
                        .overlay(Capsule().stroke(mine ? Nuru.gold : Nuru.border, lineWidth: 1))
                        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: r?.count ?? 0)
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.top, Nuru.S.md)
            if post.mine {
                Button {
                    // Marking a prayer answered is a small celebration; unmarking is quiet.
                    if post.isAnswered { Haptics.tap() } else { Haptics.success() }
                    Task { await vm.toggleAnswered() }
                } label: {
                    HStack(spacing: 6) {
                        Icon(.checkCircle2, size: 14, color: Nuru.successText)
                        Text(post.isAnswered ? "Mark unanswered" : "Mark answered")
                            .font(.inter(12, .bold)).foregroundStyle(Nuru.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Nuru.surface, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .padding(.top, Nuru.S.md)
            }
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func commentCard(_ cm: PrayerWallComment) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: cm.authorAvatar, name: cm.authorName, size: 28)
                Text(cm.authorName).font(.inter(12, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(whenString(cm.createdAt)).font(.nCardMeta).foregroundStyle(Nuru.faint)
            }
            Text(cm.body).font(.nCardBody).foregroundStyle(Nuru.ink)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .padding(.bottom, Nuru.S.sm)
    }

    private func composer(_ d: PrayerWallDetail) -> some View {
        HStack(alignment: .bottom, spacing: Nuru.S.sm) {
            TextField("Write an encouragement…", text: $vm.draft, axis: .vertical)
                .font(.inter(15)).lineLimit(1...5)
                .padding(.horizontal, Nuru.S.base).padding(.vertical, 12)
                .frame(minHeight: 44)
                .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: Nuru.R.control))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.control).stroke(Nuru.border, lineWidth: 1))
            // ✨ Nuru drafting — reads the prayer request + latest comments and
            // proposes an editable encouragement; "Use draft" only fills the field.
            AiDraftButton(recentMessages: draftContext(d)) { vm.draft = $0 }
                .padding(.bottom, 7)
            Button { Haptics.action(); Task { await vm.comment() } } label: {
                Icon(.send, size: 17, color: .white)
                    .frame(width: 44, height: 44).background(Nuru.navyDeep, in: Circle())
            }
            .buttonStyle(.pressable)
            .disabled(vm.sending || vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(vm.sending || vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.2), value: vm.sending || vm.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(Nuru.S.sm)
        .background(Nuru.white)
        .overlay(Rectangle().fill(Nuru.border).frame(height: 1), alignment: .top)
    }

    /// The prayer request (title — body) + the last 4 comments, as the
    /// "[Author]: text" context Nuru drafts from.
    private func draftContext(_ d: PrayerWallDetail) -> [(author: String, text: String)] {
        let p = d.post
        var items: [(author: String, text: String)] = []
        let postText = [p.title ?? "", p.body].filter { !$0.isEmpty }.joined(separator: " — ")
        items.append((p.authorName.isEmpty ? "Member" : p.authorName,
                      postText.isEmpty ? "(voice prayer)" : postText))
        for c in d.comments.suffix(4) {
            items.append((c.authorName.isEmpty ? "Member" : c.authorName,
                          c.body.isEmpty ? "(voice reply)" : c.body))
        }
        return items
    }

    private var answeredChip: some View {
        HStack(spacing: 4) {
            Icon(.checkCircle2, size: 12, color: Nuru.successText)
            Text("Answered").font(.nMicro).foregroundStyle(Nuru.successText)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Nuru.successBg, in: Capsule())
    }

    private func whenString(_ iso: String) -> String {
        guard let date = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        return f.string(from: date)
    }
}
