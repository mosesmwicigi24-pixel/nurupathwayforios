// Prayer Wall — the native port of screens/PrayerWallScreen.tsx. A public space
// where members post prayer requests others pray under (🙏 + emoji) and comment.
// Full-bleed worship hero, Latest / Most-prayed sort, request cards, and a
// compose sheet. Styled to match the RN screen exactly.
import SwiftUI

private let prayerHero = "https://images.unsplash.com/photo-1529070538774-1843cb3265df?w=1200&q=80"

@MainActor
final class PrayerWallViewModel: ObservableObject {
    @Published var posts: [PrayerWallPost] = []
    @Published var sort = "latest"
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { posts = try await MemberAPI.prayerWall(sort: sort) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load the prayer wall." }
        loading = false
    }

    func setSort(_ s: String) async { sort = s; await load() }

    func pray(_ p: PrayerWallPost) async {
        try? await MemberAPI.prayerWallReact(p.postId, emoji: "🙏")
        await load()
    }
}

struct PrayerWallView: View {
    @StateObject private var vm = PrayerWallViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var composing = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                hero
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    sortRow
                    if vm.loading && vm.posts.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else if vm.posts.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.posts) { post in
                            NavigationLink(value: CommunityRoute.prayer(post.postId)) {
                                PrayerCardView(post: post) { Task { await vm.pray(post) } }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.coolPaper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await vm.load() }
        .task { if vm.posts.isEmpty { await vm.load() } }
        .sheet(isPresented: $composing) {
            PrayerComposeSheet { await vm.load() }
        }
    }

    // Full-bleed hero: edge-to-edge image, controls + title overlaid.
    private var hero: some View {
        ZStack(alignment: .bottom) {
            CachedAsyncImage(url: URL(string: prayerHero)) { phase in
                (phase.image ?? Image(systemName: "photo")).resizable().scaledToFill()
            }
            .frame(maxWidth: .infinity).frame(height: 240).clipped()
            Color(hex: 0x081C36, alpha: 0.55)
            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Icon(.arrowLeft, size: 18, color: .white)
                            .frame(width: 40, height: 40).background(Color.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                    Button { composing = true } label: {
                        Icon(.plus, size: 18, color: Nuru.navyDeep)
                            .frame(width: 40, height: 40).background(Nuru.gold, in: Circle())
                    }
                }
                .padding(.horizontal, Nuru.S.lg).padding(.top, 54)
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("PRAY FOR ONE ANOTHER").font(.inter(11, .medium)).kerning(1.8).foregroundStyle(Nuru.gold)
                    Text("Carry one another").font(.fraunces(24, .semibold)).foregroundStyle(.white)
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
                Button { Task { await vm.setSort(key) } } label: {
                    Text(label).font(.inter(12, .bold))
                        .foregroundStyle(on ? Nuru.navyDeep : Nuru.ink600)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(on ? Nuru.goldChipBg : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(on ? Nuru.gold : Nuru.border, lineWidth: 1))
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Text("No requests yet").font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
            Text("Be the first to share a prayer for the family to stand with you.")
                .font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xxl)
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
                    Text(timeAgo(post.createdAt)).font(.nMicro).foregroundStyle(Nuru.faint)
                }
                Spacer(minLength: 0)
                if post.isAnswered { answeredChip }
            }
            if let title = post.title, !title.isEmpty {
                Text(title).font(.nHeading).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.sm)
            }
            Text(post.body).font(.nBody).foregroundStyle(Nuru.muted).lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
            if post.audioUrl != nil { voiceTag.padding(.top, Nuru.S.sm) }
            HStack(spacing: Nuru.S.base) {
                Button(action: pray) {
                    HStack(spacing: 6) {
                        Text("🙏").font(.system(size: 15))
                        Text(post.prayCount > 0 ? "\(post.prayCount) praying" : "Pray")
                            .font(.inter(12, .bold)).foregroundStyle(post.iPrayed ? Nuru.navyDeep : Nuru.ink600)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(post.iPrayed ? Nuru.goldChipBg : Nuru.surface, in: Capsule())
                    .overlay(Capsule().stroke(post.iPrayed ? Nuru.gold : Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                HStack(spacing: 4) {
                    Icon(.messageCircle, size: 14, color: Nuru.faint)
                    Text("\(post.commentCount)").font(.nCaption).foregroundStyle(Nuru.faint)
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
            Icon(.checkCircle2, size: 11, color: Nuru.successText)
            Text("Answered").font(.nMicro).foregroundStyle(Nuru.successText)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Nuru.successBg, in: Capsule())
    }

    private var voiceTag: some View {
        HStack(spacing: 6) {
            Icon(.audioLines, size: 13, color: Nuru.gold)
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
                    Button { Task { await post() } } label: {
                        Text(busy ? "Posting…" : "Post to wall")
                            .font(.nHeading).foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: Nuru.R.button))
                    }
                    .disabled(busy || body_.trimmed.isEmpty)
                    .opacity(busy || body_.trimmed.isEmpty ? 0.5 : 1)
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
        busy = true; err = nil
        do {
            try await MemberAPI.createPrayerWallPost(title: title.trimmed.isEmpty ? nil : title.trimmed, body: text)
            await onPosted(); dismiss()
        } catch {
            err = (error as? APIError)?.errorDescription ?? "Couldn't post. Try again."; busy = false
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
