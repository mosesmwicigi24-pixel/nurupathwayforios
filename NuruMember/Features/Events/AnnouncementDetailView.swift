// Announcement detail — native port of the RN announcement screen (GET
// /announcements/{id}). Full-bleed hero image, title + date, body, an optional
// video tile, and an image-gallery carousel. Replicates the card/image/video set.
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

    init(announcementId: String) { _vm = StateObject(wrappedValue: AnnouncementDetailViewModel(announcementId: announcementId)) }

    private var images: [String] {
        let d = vm.detail
        let gallery = (d?.images.isEmpty == false ? d?.images : d?.galleryImageUrls) ?? []
        return gallery.filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                hero
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    if let d = vm.detail {
                        if let sent = d.sentAt { Text(whenString(sent)).font(.nCaption).foregroundStyle(Nuru.muted) }
                        Text(d.body).font(.nBodyLg).foregroundStyle(Nuru.ink).fixedSize(horizontal: false, vertical: true)
                        if let v = d.videoUrl.flatMap(URL.init) { videoTile(v) }
                        if !images.isEmpty { gallery }
                    } else if vm.loading {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
                    } else {
                        Text(vm.error ?? "Couldn't load this announcement.").font(.nBody).foregroundStyle(Nuru.muted)
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
    }

    private var hero: some View {
        ZStack(alignment: .topLeading) {
            if let url = vm.detail?.primaryImageUrl.flatMap(URL.init) {
                AsyncImage(url: url) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                    .frame(height: 260).frame(maxWidth: .infinity).clipped()
            } else {
                Nuru.heroGradient.frame(height: 260)
            }
            LinearGradient(colors: [Color.black.opacity(0.35), .clear, Color(hex: 0x081C36, alpha: 0.85)],
                           startPoint: .top, endPoint: .bottom).frame(height: 260).allowsHitTesting(false)
            VStack(alignment: .leading) {
                HStack {
                    Button { dismiss() } label: {
                        Icon(.arrowLeft, size: 18, color: .white).frame(width: 40, height: 40).background(Color.black.opacity(0.4), in: Circle())
                    }
                    Spacer()
                    Icon(.share2, size: 17, color: .white).frame(width: 40, height: 40).background(Color.black.opacity(0.4), in: Circle())
                }
                .padding(.horizontal, Nuru.S.lg).padding(.top, 54)
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("ANNOUNCEMENT").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(Nuru.goldGlow)
                    Text(vm.detail?.title ?? "Announcement").font(.fraunces(24, .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, Nuru.S.lg).padding(.bottom, Nuru.S.lg)
            }
        }
        .frame(height: 260)
    }

    private func videoTile(_ url: URL) -> some View {
        Button { UIApplication.shared.open(url) } label: {
            ZStack {
                Nuru.navyGradient.frame(height: 180)
                Icon(.playCircle, size: 48, color: .white)
            }
            .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        }.buttonStyle(.plain)
    }

    private var gallery: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(images, id: \.self) { s in
                    if let url = URL(string: s) {
                        AsyncImage(url: url) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                            .frame(width: 240, height: 150).clipped()
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
