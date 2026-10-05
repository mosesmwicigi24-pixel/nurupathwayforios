// Announcement detail — the announcement reader (GET /announcements/{id}),
// presented with the make's cream sub-page chrome: back button, ANNOUNCEMENT
// eyebrow chip, serif title, sent date and a gold accent bar. Below it: the
// primary image (when the announcement has one), the body, an optional video
// tile and an image-gallery carousel — every image slot renders a real URL or
// a branded gradient, never a blank gray.
import SwiftUI

@MainActor
final class AnnouncementDetailViewModel: ObservableObject {
    @Published var detail: AnnouncementDetail?
    @Published var loading = true
    /// Why it didn't load — spoken through §4's one state language (a 404 is
    /// "This isn't here any more · Go back"), never the server's raw words.
    @Published var failure: Error?

    let announcementId: String
    init(announcementId: String) { self.announcementId = announcementId }

    /// Every way in — Home's card, the inbox, a tapped push — lands here, so
    /// this is the one place an announcement is marked opened.
    func load() async {
        loading = true; failure = nil
        do { detail = try await MemberAPI.announcement(announcementId) }
        catch { failure = error }
        loading = false
        guard detail != nil else { return }
        // Reading it reads its notices too (the server marks them, §7.4 #11):
        // the bells re-read the count now, so the dot clears on the way back
        // — not at the next foreground.
        await MemberAPI.openAnnouncement(announcementId)
        await InboxBadge.shared.refresh()
    }
}

struct AnnouncementDetailView: View {
    @StateObject private var vm: AnnouncementDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showVideo = false

    init(announcementId: String) { _vm = StateObject(wrappedValue: AnnouncementDetailViewModel(announcementId: announcementId)) }

    /// The strip under the words — never the cover again (§7.4 #12).
    private var images: [String] {
        guard let d = vm.detail else { return [] }
        return AnnouncementGallery.photos(images: d.images, gallery: d.galleryImageUrls, cover: d.primaryImageUrl)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    if let d = vm.detail {
                        if let url = d.primaryImageUrl.flatMap(URL.init) {
                            heroImage(url).gentleEntrance()
                        }
                        Text(d.body).font(.nBodyLg).foregroundStyle(Nuru.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .gentleEntrance(delay: 0.05)
                        if let v = d.videoUrl.flatMap(URL.init) { videoTile(v).gentleEntrance(delay: 0.1) }
                        if !images.isEmpty { gallery.gentleEntrance(delay: 0.15) }
                    } else if vm.loading {
                        loadingSkeleton
                    } else if let failure = vm.failure {
                        // §4's one state card (§7.4 #12): a 404 reads "This
                        // isn't here any more · It may have been moved or
                        // removed." with Go back — never the raw "Announcement
                        // not found" and a Try again that could not work.
                        NuruStateView(state: .failed(.failure(failure)),
                                      retry: { Task { await vm.load() } },
                                      back: { dismiss() })
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
        // Every video opens the ONE universal full-bleed player page.
        .fullScreenCover(isPresented: $showVideo) {
            if let d = vm.detail, let v = d.videoUrl, !v.isEmpty {
                VideoPlayerPage(
                    urlString: v,
                    title: d.title,
                    summary: d.body,
                    quickNote: d.sentAt.map { "Sent \(whenString($0))" },
                    posterUrl: d.primaryImageUrl)
            }
        }
    }

    // MARK: loading state

    /// Shimmering placeholder in the shape of the announcement — an image
    /// block and a few body lines — so the page doesn't jump when it lands.
    private var loadingSkeleton: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Nuru.surface).frame(height: 180).nuruShimmer()
            RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(height: 12).nuruShimmer()
            RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(width: 250, height: 12).nuruShimmer()
            RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(width: 180, height: 12).nuruShimmer()
        }
        .padding(.top, 2)
    }

    // MARK: cream sub-page header (make's CommunityPage chrome)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.chevronLeft, size: 18, color: Nuru.navy)
                        .frame(width: 40, height: 40)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
                Spacer()
                Text("ANNOUNCEMENT").font(.inter(9, .bold)).kerning(1.5)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
            }
            Text(vm.detail?.title ?? "Announcement")
                .font(.fraunces(27, .semibold)).foregroundStyle(Nuru.navy)
                .padding(.top, Nuru.S.base)
            if let sent = vm.detail?.sentAt {
                Text(whenString(sent)).font(.inter(12)).foregroundStyle(Color(hex: 0x59667C))
                    .padding(.top, 6)
            }
            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [Nuru.gold, Nuru.gold.opacity(0)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 48, height: 3)
                .padding(.top, Nuru.S.md)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen).padding(.top, 60).padding(.bottom, Nuru.S.lg)
        .background {
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        }
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // MARK: media

    // Primary image — grows to the picture's natural aspect (16:9 while it
    // loads, branded gradient on failure) and fills the card edge-to-edge.
    private func heroImage(_ url: URL) -> some View {
        FitImage(url: url)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // Video tile — poster-backed, opens the universal full-bleed player page
    // (never Safari).
    private func videoTile(_ url: URL) -> some View {
        Button {
            Haptics.tap()
            showVideo = true
        } label: {
            ZStack {
                Nuru.navyGradient.frame(height: 180)
                Icon(.playCircle, size: 48, color: .white)
            }
            .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
    }

    // Gallery rail — a fixed-height strip where each photo keeps its own
    // natural width (no crop, no letterbox).
    private var gallery: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(images, id: \.self) { s in
                    if let url = URL(string: s) {
                        FitImage(url: url, fixedHeight: 170)
                            .clipShape(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                    }
                }
            }
        }
    }

    private func whenString(_ iso: String) -> String {
        guard let d = ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }
}

/// The announcement's photo strip (EXPERIENCE.md §7.4 #12: the cover once).
/// The server's `images` is [cover, …gallery] — `gallery_image_urls` when it
/// sends none — and the cover is already the hero above the words, so the
/// strip keeps only the other photos, each once. Pure.
enum AnnouncementGallery {
    static func photos(images: [String], gallery: [String]?, cover: String?) -> [String] {
        let all = images.isEmpty ? (gallery ?? []) : images
        let hero = cover?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var seen = Set<String>()
        return all.compactMap { raw in
            let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty, s != hero, seen.insert(s).inserted else { return nil }
            return s
        }
    }
}
