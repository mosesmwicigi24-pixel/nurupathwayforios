// Prayer Wall — the native port of screens/PrayerWallScreen.tsx. A public space
// where members post prayer requests others pray under (🙏 + emoji) and comment.
// Full-bleed worship hero, Latest / Most-prayed sort, request cards, and a
// compose sheet. Styled to match the RN screen exactly.
import SwiftUI

@MainActor
final class PrayerWallViewModel: ObservableObject {
    @Published var posts: [PrayerWallPost] = []
    @Published var sort = "latest"
    @Published var loading = true
    /// Why the wall didn't load — told in the one state card (§4).
    @Published var failure: Error?

    func load() async {
        loading = true; failure = nil
        do { posts = try await MemberAPI.prayerWall(sort: sort) }
        catch { self.failure = error }
        loading = false
    }

    func setSort(_ s: String) async {
        guard s != sort else { return }   // re-tapping the active chip shouldn't refetch
        sort = s; await load()
    }

    func pray(_ p: PrayerWallPost) async {
        _ = try? await MemberAPI.prayerWallReact(p.postId, emoji: "🙏")
        await load()
    }
}

struct PrayerWallView: View {
    /// True when hosted as the "Corporate Prayer" tab of PrayerRoomView, which
    /// supplies its own back button + title + segmented control — so this
    /// view drops its own hero (and the "+" compose button living inside it)
    /// for a gentle prompt at the top of the list.
    var embedded: Bool = false
    @StateObject private var vm = PrayerWallViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var composing = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                if !embedded { hero }
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    if embedded { sharePrompt }
                    sortRow
                    if vm.loading && vm.posts.isEmpty {
                        ForEach(0..<3, id: \.self) { i in
                            SkeletonPrayerCard().gentleEntrance(delay: Double(i) * 0.08)
                        }
                    } else if vm.posts.isEmpty, let f = vm.failure {
                        // The one state card (§8.1 rule 5; final walk #29).
                        NuruStateView(state: .failed(.failure(f)), retry: { Task { await vm.load() } })
                            .padding(.top, Nuru.S.sm)
                    } else if vm.posts.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.posts) { post in
                            NavigationLink(value: CommunityRoute.prayer(post.postId)) {
                                PrayerCardView(post: post) { Task { await vm.pray(post) } }
                            }
                            .buttonStyle(.pressableSubtle)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, embedded ? Nuru.S.lg : Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: vm.posts.map(\.postId))
            }
        }
        // Warm paper, the page every tab stands on (§8.1 rule 1; final walk
        // #29: it was the portal's cool #F7F9FC).
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await vm.load() }
        .task { if vm.posts.isEmpty { await vm.load() } }
        .sheet(isPresented: $composing) {
            PrayerComposeSheet { await vm.load() }
        }
    }

    /// Embedded (My Prayer Room) has no hero to carry "+", so the list opens
    /// with a gentle prompt on gold tint (§8.1 rule 5) — it floated over the
    /// cards instead, and sat under the tab bar on a home-button phone and
    /// under the LIVE bar on every phone (rule 9: a floating button never
    /// hides anything, nor is it hidden).
    private var sharePrompt: some View {
        Button { Haptics.tap(); composing = true } label: {
            HStack(spacing: Nuru.S.md) {
                Icon(.plus, size: 18, color: Nuru.navy)
                    .frame(width: 36, height: 36)
                    .background(Nuru.white, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share a prayer").font(.nRowTitle).foregroundStyle(Nuru.navy)
                    Text("Let the church carry it with you.").font(.nCardMeta).foregroundStyle(Nuru.ink600)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 14, color: Nuru.ink400)
            }
            .padding(Nuru.S.md)
            .background(Nuru.goldTint.opacity(0.55), in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Share a prayer")
    }

    // Full-bleed hero: brand gradient (image removed by design), controls + title overlaid.
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
                    Text("PRAY FOR ONE ANOTHER").font(.inter(11, .medium)).kerning(1.8).foregroundStyle(Nuru.gold)
                    Text("Carry one another").font(.fraunces(26, .semibold)).foregroundStyle(.white)
                    Text("“Carry each other’s burdens, and in this way you will fulfill the law of Christ.” — Galatians 6:2")
                        .font(.nCaption).foregroundStyle(Nuru.onNavyDim).lineLimit(2).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Nuru.S.lg)
            }
        }
        .frame(height: 240)
        .clipShape(.rect(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
    }

    private var sortRow: some View {
        HStack(spacing: Nuru.S.sm) {
            ForEach([("latest", "Latest"), ("prayed", "Most prayed")], id: \.0) { key, label in
                let on = vm.sort == key
                Button {
                    if !on { Haptics.selection() }
                    Task { await vm.setSort(key) }
                } label: {
                    // Selected navy, unselected white with a hairline (§8.1 rule 6).
                    Text(label).font(.inter(12, .bold))
                        .foregroundStyle(on ? .white : Nuru.ink600)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(on ? Color.clear : Nuru.border, lineWidth: 1))
                }
            }
        }
    }

    /// The one state card (§8.1 rule 5), no emoji (rule 7) — and one story
    /// about who sees a shared prayer (final walk M8): the congregation, as
    /// the share prompt says.
    private var emptyState: some View {
        NuruStateView(state: .empty(title: PrayerWallWords.emptyTitle, line: PrayerWallWords.emptyLine))
            .padding(.top, Nuru.S.sm)
            .gentleEntrance()
    }
}

/// Shimmering placeholder matching the request-card anatomy (first load only).
private struct SkeletonPrayerCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            HStack(spacing: Nuru.S.sm) {
                Circle().fill(Nuru.surface).frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 4) {
                    RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 110, height: 10)
                    RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 64, height: 8)
                }
                Spacer(minLength: 0)
            }
            RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(maxWidth: .infinity).frame(height: 12)
            RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 200, height: 12)
            Capsule().fill(Nuru.surface).frame(width: 88, height: 30).padding(.top, Nuru.S.xs)
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShimmer()
    }
}

private struct PrayerCardView: View {
    let post: PrayerWallPost
    let pray: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: post.authorAvatar, name: post.authorName, size: 36)
                VStack(alignment: .leading, spacing: 0) {
                    Text(post.authorName).font(.inter(12, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    Text(timeAgo(post.createdAt)).font(.nCardMeta).foregroundStyle(Nuru.faint)
                }
                Spacer(minLength: 0)
                if post.isAnswered { answeredChip }
            }
            if let title = post.title, !title.isEmpty {
                Text(title).font(.nHeading).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.sm)
            }
            Text(post.body).font(.nCardBody).foregroundStyle(Nuru.muted).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            if post.audioUrl != nil { voiceTag.padding(.top, Nuru.S.sm) }
            HStack(spacing: Nuru.S.base) {
                Button { Haptics.love(); pray() } label: {
                    HStack(spacing: 6) {
                        // A Lucide glyph, not an emoji (§8.1 rule 7).
                        Icon(.handHeart, size: 14, color: post.iPrayed ? Nuru.navyDeep : Nuru.ink600)
                        Text(post.prayCount > 0 ? "\(post.prayCount) praying" : "Pray")
                            .font(.inter(12, .bold)).foregroundStyle(post.iPrayed ? Nuru.navyDeep : Nuru.ink600)
                            .contentTransition(.numericText(value: Double(post.prayCount)))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(post.iPrayed ? Nuru.goldChipBg : Nuru.surface, in: Capsule())
                    .overlay(Capsule().stroke(post.iPrayed ? Nuru.gold : Nuru.border, lineWidth: 1))
                    .animation(.spring(response: 0.35, dampingFraction: 0.7), value: post.prayCount)
                }
                .buttonStyle(.pressable)
                HStack(spacing: 4) {
                    Icon(.messageCircle, size: 14, color: Nuru.faint)
                    Text("\(post.commentCount ?? 0)").font(.nCardMeta).foregroundStyle(Nuru.faint)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private var answeredChip: some View {
        HStack(spacing: 4) {
            Icon(.checkCircle2, size: 14, color: Nuru.successText)
            Text("Answered").font(.nMicro).foregroundStyle(Nuru.successText)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Nuru.successBg, in: Capsule())
    }

    private var voiceTag: some View {
        HStack(spacing: 6) {
            Icon(.audioLines, size: 14, color: Nuru.gold)
            Text("Voice prayer").font(.nCaption).foregroundStyle(Nuru.muted)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Nuru.surface, in: Capsule())
    }
}

private struct PrayerComposeSheet: View {
    let onPosted: () async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var body_ = ""
    @State private var busy = false
    @State private var err: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    Text("The family in your congregation can pray with you.")
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                    TextField("Title (optional)", text: $title)
                        .font(.inter(15)).padding(.horizontal, Nuru.S.base).frame(height: 44)
                        .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: Nuru.R.control))
                        .overlay(RoundedRectangle(cornerRadius: Nuru.R.control).stroke(Nuru.border, lineWidth: 1))
                        .padding(.top, Nuru.S.base)
                    TextField("What would you like prayer for?", text: $body_, axis: .vertical)
                        .font(.inter(15)).lineLimit(5...10).padding(Nuru.S.base)
                        .frame(minHeight: 110, alignment: .topLeading)
                        .background(Nuru.coolPaper, in: RoundedRectangle(cornerRadius: Nuru.R.control))
                        .overlay(RoundedRectangle(cornerRadius: Nuru.R.control).stroke(Nuru.border, lineWidth: 1))
                    if let err { Text(err).font(.nCaption).foregroundStyle(Nuru.error) }
                    // The sheet's one gold primary (§8.1 rule 4) — it was a
                    // navy block with white words.
                    PButton(title: "Post to wall", variant: .gold, busy: busy, disabled: body_.trimmed.isEmpty) {
                        Task { await post() }
                    }
                    .animation(.easeInOut(duration: 0.2), value: busy || body_.trimmed.isEmpty)
                    .padding(.top, Nuru.S.base)
                }
                .padding(Nuru.S.lg)
            }
            .background(Nuru.white.ignoresSafeArea())
            .navigationTitle("Share a prayer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }

    private func post() async {
        let text = body_.trimmed
        guard !text.isEmpty else { return }
        Haptics.action()
        busy = true; err = nil
        do {
            try await MemberAPI.createPrayerWallPost(title: title.trimmed.isEmpty ? nil : title.trimmed, body: text)
            Haptics.success()
            await onPosted(); dismiss()
            // Quiet gold banner (no confetti) once the server accepted the post —
            // unique key per post so every prayer gets its moment.
            CelebrationCenter.shared.fire(
                key: "prayer-\(UUID().uuidString)",
                title: "Your prayer is on the wall",
                subtitle: PrayerWallWords.posted,
                confetti: false)
        } catch {
            Haptics.error()
            err = NuruStateCopy.failureLine("Couldn't post. Try again.", error); busy = false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// The wall's words, one story about who sees a shared prayer (final walk
/// M8): everyone in the member's congregation — the share prompt's words.
/// Android says the same.
enum PrayerWallWords {
    static let emptyTitle = "No requests yet"
    static let emptyLine = "Be the first to share a prayer. Everyone in your congregation will see it and can pray with you."
    static let posted = "Everyone in your congregation can pray with you."
}
