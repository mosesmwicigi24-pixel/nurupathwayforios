// Event detail — the native port of screens/EventDetailScreen.tsx. A full-bleed
// parallax image hero (category chip + live pill + serif title overlaid), a 2x2
// chip grid of date/time/where/going, add-to-calendar + share actions, the
// "about this gathering" copy, the who's-going roster, the RSVP segmented control,
// and a "who's coming" buzz section with a visual-only hype composer. Bound to the
// real /events/{id} + RSVP endpoints; the buzz feed has no API yet, so it shows a
// tasteful compose-and-be-first state.
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

    private var title: String { vm.detail?.title ?? occ.title }
    private var category: String? { vm.detail?.category ?? occ.category }
    private var location: String? { vm.detail?.location ?? occ.location }
    private var imageUrl: String? { vm.detail?.primaryImageUrl ?? occ.primaryImageUrl }
    private var aboutText: String? { vm.detail?.description ?? occ.description }
    private var going: Int { vm.detail?.rsvpCounts.going ?? occ.going }
    private var attendees: [EventAttendee] { vm.detail?.attendees ?? occ.attendees ?? [] }
    private var isLive: Bool { Ev.isLive(occ.startAt, occ.endAt) }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: Nuru.S.base) {
                hero
                VStack(spacing: Nuru.S.base) {
                    detailsCard
                    actionRow
                    aboutSection
                    whoIsGoing
                    rsvpControl
                    whoIsComing
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.xs)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
    }

    // MARK: Hero — full-bleed parallax image with overlaid chrome + title.

    private var hero: some View {
        GeometryReader { geo in
            let minY = geo.frame(in: .global).minY
            let stretch = max(0, minY)           // parallax overscroll
            let h = heroHeight + stretch
            ZStack(alignment: .bottomLeading) {
                heroImage
                    .frame(width: geo.size.width, height: h)
                    .clipped()
                    .offset(y: -stretch)
                // legibility scrims (top for chrome, bottom for title)
                LinearGradient(colors: [Color.black.opacity(0.34), .clear],
                               startPoint: .top, endPoint: .center)
                    .frame(width: geo.size.width, height: h)
                    .offset(y: -stretch)
                    .allowsHitTesting(false)
                LinearGradient(colors: [.clear, Color(hex: 0x081C36, alpha: 0.78)],
                               startPoint: .center, endPoint: .bottom)
                    .frame(width: geo.size.width, height: h)
                    .offset(y: -stretch)
                    .allowsHitTesting(false)

                heroOverlay
            }
            .frame(width: geo.size.width, height: h, alignment: .bottom)
        }
        .frame(height: heroHeight)
    }

    private var heroHeight: CGFloat { 280 }

    @ViewBuilder
    private var heroImage: some View {
        if let url = imageUrl.flatMap(URL.init) {
            CachedAsyncImage(url: url) { p in
                (p.image ?? Image(systemName: "photo")).resizable().scaledToFill()
            }
        } else {
            LinearGradient(colors: [Nuru.navy700, Nuru.navy, Ev.categoryColor(category)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var heroOverlay: some View {
        VStack(alignment: .leading, spacing: 0) {
            // top chrome — back (left) + share (right)
            HStack {
                circleButton(.arrowLeft) { dismiss() }
                Spacer()
                circleButton(.share2) { }
            }
            .padding(.horizontal, Nuru.S.lg)
            .padding(.top, 54)

            Spacer(minLength: 0)

            // bottom — chips + title
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack(spacing: Nuru.S.sm) {
                    if let c = category {
                        Text(c.uppercased())
                            .font(.inter(10, .bold)).kerning(1.2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.black.opacity(0.40), in: Capsule())
                    }
                    if isLive {
                        HStack(spacing: 4) {
                            Icon(.flame, size: 11, color: Nuru.navy)
                            Text("Happening now!").font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Nuru.goldGradient, in: Capsule())
                    }
                }
                Text(title)
                    .font(.fraunces(28, .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Nuru.S.lg)
            .padding(.bottom, Nuru.S.lg)
        }
    }

    private func circleButton(_ icon: Lucide, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.ultraThinMaterial)
                Circle().fill(Color.black.opacity(0.22))
                Icon(icon, size: 18, color: .white)
            }
            .frame(width: 40, height: 40)
            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: Details — 2x2 chip grid.

    private var detailsCard: some View {
        VStack(spacing: Nuru.S.sm) {
            HStack(spacing: Nuru.S.sm) {
                detailTile(.calendar, "Date", Ev.weekday(occ.startAt, "EEEE, MMMM d"))
                detailTile(.clock, "Time", Ev.timeRange(occ.startAt, occ.endAt))
            }
            HStack(spacing: Nuru.S.sm) {
                detailTile(.mapPin, "Where", location ?? "To be announced")
                detailTile(.users, "Going", going == 1 ? "1 person" : "\(going) people")
            }
        }
        .padding(Nuru.S.base)
        .cardSurfaceEvD()
    }

    private func detailTile(_ icon: Lucide, _ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            Icon(icon, size: 16, color: Nuru.gold)
                .frame(width: 16)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.inter(9, .bold)).kerning(0.8)
                    .foregroundStyle(Nuru.ink400)
                Text(value)
                    .font(.inter(13, .semibold))
                    .foregroundStyle(Nuru.ink)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.md)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Action row — Add to calendar / Share (outline).

    private var actionRow: some View {
        HStack(spacing: Nuru.S.sm) {
            outlineButton(.calendar, "Add to calendar") { }
            outlineButton(.share2, "Share") { }
        }
    }

    private func outlineButton(_ icon: Lucide, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Icon(icon, size: 14, color: Nuru.ink600)
                Text(label).font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 13)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: About this gathering.

    @ViewBuilder
    private var aboutSection: some View {
        if let d = aboutText, !d.isEmpty {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                overline("ABOUT THIS GATHERING")
                Text(d)
                    .font(.nBody).foregroundStyle(Nuru.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Nuru.S.base)
            .cardSurfaceEvD()
        }
    }

    // MARK: Who's going — avatars + count.

    @ViewBuilder
    private var whoIsGoing: some View {
        if !attendees.isEmpty || going > 0 {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                HStack {
                    overline("WHO'S GOING")
                    Spacer(minLength: 0)
                    Text(going == 1 ? "1 going" : "\(going) going")
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
                }
                if attendees.isEmpty {
                    Text("Be the first to RSVP.")
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                } else {
                    HStack(alignment: .top, spacing: Nuru.S.base) {
                        ForEach(attendees.prefix(6)) { a in
                            VStack(spacing: 6) {
                                Avatar(url: a.avatarUrl, name: a.fullName, size: 46)
                                    .overlay(Circle().stroke(Nuru.white, lineWidth: 2))
                                Text(firstName(a.fullName))
                                    .font(.inter(10, .medium)).foregroundStyle(Nuru.ink600)
                                    .lineLimit(1)
                            }
                            .frame(width: 56)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Nuru.S.base)
            .cardSurfaceEvD()
        }
    }

    // MARK: RSVP segmented control.

    private var rsvpControl: some View {
        let mine = vm.detail?.myRsvp
        return VStack(alignment: .leading, spacing: Nuru.S.md) {
            overline("WILL YOU BE THERE?")
            HStack(spacing: Nuru.S.sm) {
                rsvpButton("Going", "going", on: mine == "going", icon: .check, tint: Nuru.success)
                rsvpButton("Maybe", "maybe", on: mine == "maybe", icon: nil, tint: Nuru.gold)
                rsvpButton("Can't", "declined", on: mine == "declined", icon: nil, tint: Nuru.ink400)
            }
            if let mine, !mine.isEmpty {
                HStack(spacing: 5) {
                    Icon(.check, size: 12, color: Nuru.success)
                    Text("Saved · we'll remind you the day before.")
                        .font(.nCaption).foregroundStyle(Nuru.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .cardSurfaceEvD()
    }

    private func rsvpButton(_ label: String, _ status: String, on: Bool, icon: Lucide?, tint: Color) -> some View {
        Button { Task { await vm.setRsvp(status) } } label: {
            HStack(spacing: 5) {
                if on, let icon { Icon(icon, size: 13, color: .white) }
                Text(label).font(.inter(13, .semibold)).foregroundStyle(on ? .white : Nuru.ink)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
            .background(on ? tint : Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(on ? .clear : Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(vm.rsvpBusy)
        .opacity(vm.rsvpBusy ? 0.7 : 1)
    }

    // MARK: Who's coming — buzz header, hype composer (visual), empty state.

    private var whoIsComing: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                HStack(spacing: 5) {
                    overline("WHO'S COMING")
                    Icon(.flame, size: 12, color: Nuru.gold)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Circle().fill(.white).frame(width: 5, height: 5)
                    Text("Buzzing").font(.inter(11, .bold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Nuru.success, in: Capsule())
            }

            hypeComposer

            Text("Be the first to share a moment.")
                .font(.nCaption).foregroundStyle(Nuru.faint)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Nuru.S.md)
        }
    }

    private var hypeComposer: some View {
        VStack(spacing: Nuru.S.md) {
            HStack(spacing: Nuru.S.sm) {
                ZStack {
                    Circle().fill(Nuru.navy).frame(width: 36, height: 36)
                    Text("You").font(.inter(10, .bold)).foregroundStyle(.white)
                }
                Text("Hype the room — say you're coming 🔥")
                    .font(.inter(13)).foregroundStyle(Nuru.ink400)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            HStack(spacing: Nuru.S.sm) {
                composerIcon(.image)
                composerIcon(.camera)
                composerIcon(.smile)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Text("Post").font(.inter(12, .bold)).foregroundStyle(Nuru.navyDeep)
                    Icon(.send, size: 13, color: Nuru.navyDeep)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Nuru.goldChipBg, in: Capsule())
                .overlay(Capsule().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
            }
        }
        .padding(Nuru.S.base)
        .background(Nuru.goldChipBg.opacity(0.45), in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
    }

    private func composerIcon(_ icon: Lucide) -> some View {
        Icon(icon, size: 16, color: Nuru.ink600)
            .frame(width: 36, height: 36)
            .background(Nuru.white, in: Circle())
            .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Bits.

    private func overline(_ text: String) -> some View {
        Text(text)
            .font(.inter(11, .bold)).kerning(1.2)
            .foregroundStyle(Nuru.goldLo)
    }

    private func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
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
