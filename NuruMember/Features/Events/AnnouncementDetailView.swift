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
    @Published var error: String?

    let announcementId: String
    init(announcementId: String) { self.announcementId = announcementId }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.announcement(announcementId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this announcement." }
        await MemberAPI.openAnnouncement(announcementId)
        loading = false
    }
}

struct AnnouncementDetailView: View {
    @StateObject private var vm: AnnouncementDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showVideo = false

    init(announcementId: String) { _vm = StateObject(wrappedValue: AnnouncementDetailViewModel(announcementId: announcementId)) }

    private var images: [String] {
        let d = vm.detail
        let gallery = (d?.images.isEmpty == false ? d?.images : d?.galleryImageUrls) ?? []
        return gallery.filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    if let d = vm.detail {
                        if let url = d.primaryImageUrl.flatMap(URL.init) { heroImage(url) }
                        Text(d.body).font(.nBodyLg).foregroundStyle(Nuru.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let v = d.videoUrl.flatMap(URL.init) { videoTile(v) }
                        if !images.isEmpty { gallery }
                    } else if vm.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else {
                        Text(vm.error ?? "Couldn't load this announcement.")
                            .font(.nBody).foregroundStyle(Nuru.muted)
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
                Text(whenString(sent)).font(.inter(12)).foregroundStyle(Color(hex: 0x68758A))
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
        Button { showVideo = true } label: {
            ZStack {
                Nuru.navyGradient.frame(height: 180)
                Icon(.playCircle, size: 48, color: .white)
            }
            .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        }
        .buttonStyle(.plain)
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
