// The full announcements list, reachable from Home's "View all" (Android
// parity — Android routes there directly; iOS used to dump into the generic
// notifications inbox). Rows open the existing AnnouncementDetailView.
import SwiftUI

struct AnnouncementsAllView: View {
    @State private var items: [MyAnnouncement] = []
    @State private var loading = true
    @State private var failed = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                if loading {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
                } else if items.isEmpty {
                    VStack(spacing: 8) {
                        Icon(.megaphone, size: 24, color: Nuru.gold)
                        Text(failed ? "Couldn't load announcements — pull to try again." : "No announcements yet.")
                            .font(.inter(14)).foregroundStyle(Nuru.ink)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 60)
                } else {
                    ForEach(items) { a in
                        NavigationLink(value: AppRoute.announcement(a.announcementId)) {
                            row(a)
                        }
                        .buttonStyle(.pressableSubtle)
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 12)
            .padding(.bottom, Nuru.tabBarSpace)
        }
        .background(Color(hex: 0xFAF7F0).ignoresSafeArea())
        .refreshable {
            do { items = try await MemberAPI.myAnnouncements(); failed = false } catch { failed = true }
        }
        .navigationTitle("Announcements")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do { items = try await MemberAPI.myAnnouncements(); failed = false }
            catch { failed = true }
            loading = false
        }
    }

    private func row(_ a: MyAnnouncement) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Nuru.goldChipBg).frame(width: 40, height: 40)
                Icon(.megaphone, size: 17, color: Nuru.goldChipText)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(a.title)
                    .font(.inter(14, a.opened ? .medium : .bold)).foregroundStyle(Nuru.navy)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(a.body)
                    .font(.inter(12)).foregroundStyle(Nuru.ink600)
                    .lineLimit(2).multilineTextAlignment(.leading)
                if let at = a.sentAt {
                    Text(String(at.prefix(10)))
                        .font(.inter(10.5, .semibold)).foregroundStyle(Nuru.ink600.opacity(0.7))
                }
            }
            Spacer(minLength: 0)
            if !a.opened { Circle().fill(Nuru.gold).frame(width: 8, height: 8).padding(.top, 6) }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}
