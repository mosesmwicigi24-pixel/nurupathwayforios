// The full announcements list, reachable from Home's "View all" (Android
// parity — Android routes there directly; iOS used to dump into the generic
// notifications inbox). Rows open the existing AnnouncementDetailView.
import SwiftUI

struct AnnouncementsAllView: View {
    @State private var items: [MyAnnouncement] = []
    @State private var loading = true
    /// Why the list didn't load — said in §4's words, never a bare line.
    @State private var failure: Error?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
        // The §8.1 pushed-page header (rule 2: back · kicker · title), not the
        // system's centred title.
        NuruPushedHeader(kicker: "Home", title: "Announcements", line: "From your church")
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                // Loading, empty and failed in §4's one state card (final
                // walk C16's class) — the empty list was a bare line.
                if let state = NuruState.resolve(loading: loading, isEmpty: items.isEmpty, failure: failure,
                                                 empty: .empty(title: "No announcements yet")) {
                    NuruStateView(state: state, retry: { Task { await load() } })
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
        .refreshable { await load() }
        }
        .ignoresSafeArea(edges: .top)
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .nuruEdgeSwipeBack()
        .task { await load() }
    }

    /// A failed refresh keeps the list on screen; with nothing shown, §4 says why.
    private func load() async {
        do { items = try await MemberAPI.myAnnouncements(); failure = nil }
        catch { failure = error }
        loading = false
    }

    private func row(_ a: MyAnnouncement) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Nuru.goldChipBg).frame(width: 40, height: 40)
                Icon(.megaphone, size: 18, color: Nuru.goldChipText)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(a.title)
                    .font(.inter(14, a.opened ? .medium : .bold)).foregroundStyle(Nuru.navy)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(a.body)
                    .font(.inter(12)).foregroundStyle(Nuru.ink600)
                    .lineLimit(2).multilineTextAlignment(.leading)
                // The one date shape (§8.1 rule 8) — it showed "2026-10-05".
                if let at = a.sentAt, let d = NuruDates.parse(at) ?? PauseDates.date(String(at.prefix(10))) {
                    Text(NuruDates.day(d))
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600.opacity(0.7))
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
