// Event detail — the native port of screens/EventDetailScreen.tsx (core): image
// hero, title + date/location, the RSVP control (Going / Maybe / Can't go), the
// "who's going" roster, and the description. The buzz-feed photo wall lands in a
// later pass.
import SwiftUI

@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published var detail: EventDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var rsvpBusy = false

    let occurrence: CalendarOccurrence
    init(occurrence: CalendarOccurrence) { self.occurrence = occurrence }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.event(occurrence.occurrenceId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this event." }
        loading = false
    }

    func setRsvp(_ status: String) async {
        rsvpBusy = true; defer { rsvpBusy = false }
        try? await MemberAPI.rsvp(occurrence.occurrenceId, status: status)
        await load()
    }
}

struct EventDetailView: View {
    @StateObject private var vm: EventDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(occurrence: CalendarOccurrence) {
        _vm = StateObject(wrappedValue: EventDetailViewModel(occurrence: occurrence))
    }

    private var occ: CalendarOccurrence { vm.occurrence }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: Nuru.S.base) {
                hero
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    titleBlock
                    rsvpControl
                    whoIsGoing
                    if let d = vm.detail?.description ?? occ.description, !d.isEmpty {
                        VStack(alignment: .leading, spacing: Nuru.S.sm) {
                            Text("About").font(.nHeading).foregroundStyle(Nuru.ink)
                            Text(d).font(.nBody).foregroundStyle(Nuru.muted).fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Nuru.S.base).cardSurfaceEvD()
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
            if let url = (vm.detail?.primaryImageUrl ?? occ.primaryImageUrl).flatMap(URL.init) {
                AsyncImage(url: url) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                    .frame(height: 280).frame(maxWidth: .infinity).clipped()
            } else {
                LinearGradient(colors: [Nuru.navy700, Nuru.navy, Ev.categoryColor(occ.category)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    .frame(height: 280)
            }
            LinearGradient(colors: [Color.black.opacity(0.35), .clear], startPoint: .top, endPoint: .center)
                .frame(height: 280).allowsHitTesting(false)
            Button { dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: .white)
                    .frame(width: 40, height: 40).background(Color.black.opacity(0.4), in: Circle())
            }
            .padding(.horizontal, Nuru.S.lg).padding(.top, 54)
        }
        .frame(height: 280)
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: Nuru.S.sm) {
            if let c = occ.category { Text(c.uppercased()).font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.goldLo) }
            Text(vm.detail?.title ?? occ.title).font(.fraunces(24, .semibold)).foregroundStyle(Nuru.ink)
            HStack(spacing: Nuru.S.base) {
                meta(.clock, Ev.timeRange(occ.startAt, occ.endAt))
                if let loc = occ.location { meta(.mapPin, loc) }
            }
            Text(Ev.weekday(occ.startAt, "EEEE, MMMM d")).font(.nCaption).foregroundStyle(Nuru.muted)
        }
    }

    private func meta(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) { Icon(icon, size: 13, color: Nuru.ink600); Text(text).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(1) }
    }

    private var rsvpControl: some View {
        let mine = vm.detail?.myRsvp
        return VStack(alignment: .leading, spacing: Nuru.S.sm) {
            Text("Will you be there?").font(.nHeading).foregroundStyle(Nuru.ink)
            HStack(spacing: Nuru.S.sm) {
                rsvpButton("Going", "going", mine == "going", Nuru.success)
                rsvpButton("Maybe", "maybe", mine == "maybe", Nuru.gold)
                rsvpButton("Can't go", "declined", mine == "declined", Nuru.ink600)
            }
        }
        .padding(Nuru.S.base).cardSurfaceEvD()
    }

    private func rsvpButton(_ label: String, _ status: String, _ on: Bool, _ tint: Color) -> some View {
        Button { Task { await vm.setRsvp(status) } } label: {
            Text(label).font(.inter(13, .semibold)).foregroundStyle(on ? .white : Nuru.ink)
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(on ? tint : Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.control).stroke(on ? .clear : Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(vm.rsvpBusy)
    }

    @ViewBuilder
    private var whoIsGoing: some View {
        let people = vm.detail?.attendees ?? occ.attendees ?? []
        let going = vm.detail?.rsvpCounts.going ?? occ.going
        if !people.isEmpty || going > 0 {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("Who's going").font(.nHeading).foregroundStyle(Nuru.ink)
                HStack(spacing: Nuru.S.sm) {
                    HStack(spacing: -8) {
                        ForEach(people.prefix(6)) { a in
                            Avatar(url: a.avatarUrl, name: a.fullName, size: 32)
                                .overlay(Circle().stroke(Nuru.white, lineWidth: 2))
                        }
                    }
                    if going > 0 { Text("\(going) going").font(.nCaption).foregroundStyle(Nuru.muted) }
                    Spacer(minLength: 0)
                }
            }
            .padding(Nuru.S.base).cardSurfaceEvD()
        }
    }
}

private extension View {
    func cardSurfaceEvD() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
