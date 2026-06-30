// Events ("Gathered together" make) — the native port of screens/EventsScreen.tsx.
// Navy header with a live-pulse summary row, an image-backed LIVE/FEATURED hero,
// a Today/Upcoming/My-RSVPs segment, and photo-forward event cards. Bound to the
// real calendar, featured-event and RSVP endpoints.
import SwiftUI

// MARK: helpers (port of eventHelpers.ts)

enum Ev {
    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? .distantPast
    }
    static func timeOf(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date(iso))
    }
    static func timeRange(_ s: String, _ e: String) -> String { "\(timeOf(s)) – \(timeOf(e))" }
    static func isLive(_ s: String, _ e: String) -> Bool {
        let now = Date(); return date(s) <= now && now <= date(e)
    }
    static func countdown(_ iso: String) -> String {
        let ms = date(iso).timeIntervalSinceNow
        if ms <= 0 { return "Happening now" }
        let mins = Int(ms / 60)
        if mins < 60 { return "\(max(1, mins)) min to go" }
        let hours = mins / 60
        if hours < 24 { return "\(hours) \(hours == 1 ? "hour" : "hours") to go" }
        let days = hours / 24
        return "\(days) \(days == 1 ? "day" : "days") to go"
    }
    static func categoryColor(_ c: String?) -> Color {
        switch (c ?? "").lowercased() {
        case "worship": return Color(hex: 0xC89B3C)
        case "youth": return Color(hex: 0x22B07D)
        case "leaders": return Color(hex: 0x3FA9F5)
        case "cell": return Color(hex: 0x6366F1)
        case "marketplace": return Color(hex: 0xE07B39)
        default: return Color(hex: 0x68758A)
        }
    }
    static func weekday(_ iso: String, _ fmt: String) -> String {
        let f = DateFormatter(); f.dateFormat = fmt; return f.string(from: date(iso))
    }
}

enum EventSegment: String, CaseIterable { case today = "Today", upcoming = "Upcoming", rsvps = "My RSVPs" }

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var occurrences: [CalendarOccurrence] = []
    @Published var featured: FeaturedEvent?
    @Published var rsvps: [MyRsvp] = []
    @Published var segment: EventSegment = .today
    @Published var loading = true
    @Published var error: String?

    private let from: String
    private let to: String
    private let todayStart: Date
    private let todayEnd: Date

    init() {
        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        todayStart = start
        todayEnd = cal.date(byAdding: .day, value: 1, to: start)!
        let f = ISO8601DateFormatter()
        from = f.string(from: cal.date(byAdding: .day, value: -7, to: start)!)
        to = f.string(from: cal.date(byAdding: .day, value: 45, to: start)!)
    }

    func load() async {
        loading = true; error = nil
        async let occ = try? MemberAPI.calendar(from: from, to: to)
        async let feat = try? MemberAPI.featuredEvent()
        async let rs = try? MemberAPI.myRsvps()
        occurrences = (await occ ?? []).sorted { Ev.date($0.startAt) < Ev.date($1.startAt) }
        featured = await feat ?? nil
        rsvps = await rs ?? []
        if occurrences.isEmpty && featured == nil { error = "Couldn't load events." }
        loading = false
    }

    var liveCount: Int { occurrences.filter { Ev.isLive($0.startAt, $0.endAt) }.count }
    var thisWeekCount: Int {
        let weekEnd = Calendar.current.date(byAdding: .day, value: 7, to: todayStart)!
        return occurrences.filter { let d = Ev.date($0.startAt); return d >= todayStart && d < weekEnd }.count
    }
    var goingCount: Int { rsvps.filter { $0.status == "going" }.count }
    var upcomingCount: Int { occurrences.filter { Ev.date($0.startAt) >= todayStart }.count }

    /// The hero occurrence: a live one, else the soonest upcoming.
    var heroOccurrence: CalendarOccurrence? {
        occurrences.first { Ev.isLive($0.startAt, $0.endAt) }
            ?? occurrences.first { Ev.date($0.startAt) >= Date() }
    }

    var list: [CalendarOccurrence] {
        switch segment {
        case .today:
            return occurrences.filter { let d = Ev.date($0.startAt); return d >= todayStart && d < todayEnd }
        case .upcoming:
            return occurrences.filter { Ev.date($0.startAt) >= todayStart }
        case .rsvps:
            let ids = Set(rsvps.map(\.eventId))
            return occurrences.filter { ids.contains($0.occurrenceId) }
        }
    }

    func count(_ s: EventSegment) -> Int {
        switch s {
        case .today: return occurrences.filter { let d = Ev.date($0.startAt); return d >= todayStart && d < todayEnd }.count
        case .upcoming: return upcomingCount
        case .rsvps: return rsvps.count
        }
    }
}

struct EventsView: View {
    @StateObject private var vm = EventsViewModel()

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    VStack(spacing: Nuru.S.base) {
                        if let hero = vm.heroOccurrence { heroCard(hero) }
                        calendarLink
                        segmentBar
                        cards
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .navigationDestination(for: CalendarOccurrence.self) { EventDetailView(occurrence: $0) }
        }
        .task { if vm.occurrences.isEmpty { await vm.load() } }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text("Events").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.onNavy)
                Spacer()
                ZStack {
                    Icon(.bell, size: 20, color: Nuru.onNavy)
                        .frame(width: 44, height: 44)
                        .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
            HStack(spacing: Nuru.S.sm) {
                if vm.liveCount > 0 {
                    pulseChip("\(vm.liveCount) live now", icon: nil, dot: true, fg: Color(hex: 0x7FE0A0))
                }
                pulseChip("\(vm.thisWeekCount) this week", icon: .calendarDays, dot: false, fg: Nuru.onNavyDim)
                pulseChip("\(vm.goingCount) you're going", icon: .check, dot: false, fg: Nuru.onNavyDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen).padding(.top, 60).padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    private func pulseChip(_ text: String, icon: Lucide?, dot: Bool, fg: Color) -> some View {
        HStack(spacing: 5) {
            if dot { Circle().fill(Color(hex: 0x22C55E)).frame(width: 6, height: 6) }
            if let icon { Icon(icon, size: 11, color: Nuru.gold) }
            Text(text).font(.inter(10, .bold)).foregroundStyle(fg)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.06), in: Capsule())
    }

    // Live / featured immersive hero.
    private func heroCard(_ occ: CalendarOccurrence) -> some View {
        let live = Ev.isLive(occ.startAt, occ.endAt)
        return NavigationLink(value: occ) {
            ZStack(alignment: .bottomLeading) {
                if let url = occ.primaryImageUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                        .frame(height: 200).frame(maxWidth: .infinity).clipped()
                } else {
                    Ev.categoryColor(occ.category).frame(height: 200).frame(maxWidth: .infinity)
                }
                LinearGradient(colors: [.clear, Color(hex: 0x081C36, alpha: 0.85)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    HStack(spacing: Nuru.S.sm) {
                        if live {
                            HStack(spacing: 4) { Circle().fill(.white).frame(width: 6, height: 6); Text("LIVE NOW").font(.inter(9, .bold)).kerning(1).foregroundStyle(.white) }
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Nuru.danger, in: Capsule())
                        } else {
                            HStack(spacing: 4) { Icon(.sparkles, size: 10, color: Nuru.navy); Text("FEATURED").font(.inter(9, .bold)).kerning(1).foregroundStyle(Nuru.navy) }
                                .padding(.horizontal, 8).padding(.vertical, 4).background(Nuru.gold, in: Capsule())
                        }
                        if let c = occ.category { Text(c.uppercased()).font(.inter(9, .bold)).kerning(1).foregroundStyle(Nuru.goldLight) }
                    }
                    Text(occ.title).font(.fraunces(21, .semibold)).foregroundStyle(.white)
                    HStack(spacing: Nuru.S.base) {
                        heroMeta(.clock, Ev.timeRange(occ.startAt, occ.endAt))
                        if let loc = occ.location { heroMeta(.mapPin, loc) }
                    }
                    Text(occ.going > 0 ? "\(occ.going) \(live ? "worshipping" : "going")" : "Join the gathering")
                        .font(.inter(10, .bold)).foregroundStyle(.white.opacity(0.85))
                }
                .padding(Nuru.S.base)
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .nuruShadow()
        }
        .buttonStyle(.plain)
    }

    private func heroMeta(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) { Icon(icon, size: 13, color: Nuru.goldLight); Text(text).font(.inter(10)).foregroundStyle(Nuru.onNavyDim).lineLimit(1) }
    }

    private var calendarLink: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack { RoundedRectangle(cornerRadius: 16).fill(Nuru.goldGradient).frame(width: 44, height: 44); Icon(.calendarDays, size: 22, color: Nuru.navy) }
            VStack(alignment: .leading, spacing: 1) {
                Text("CALENDAR").font(.inter(9, .bold)).kerning(1).foregroundStyle(Nuru.goldLight)
                Text("All events & calendar").font(.fraunces(15, .semibold)).foregroundStyle(Nuru.onNavy)
                Text("See the whole month · \(vm.upcomingCount) upcoming").font(.inter(10)).foregroundStyle(Nuru.onNavyDim)
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 18, color: .white)
        }
        .padding(Nuru.S.base)
        .background(Nuru.navy, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
    }

    private var segmentBar: some View {
        HStack(spacing: Nuru.S.sm) {
            ForEach(EventSegment.allCases, id: \.self) { s in
                let on = vm.segment == s
                Button { vm.segment = s } label: {
                    HStack(spacing: 6) {
                        Text(s.rawValue).font(.inter(11, on ? .bold : .regular)).foregroundStyle(on ? .white : Nuru.ink600)
                        Text("\(vm.count(s))").font(.inter(10, .bold)).foregroundStyle(on ? Nuru.navy : Nuru.ink600)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(on ? Nuru.gold : Nuru.surface, in: Capsule())
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 9)
                    .background(on ? Nuru.navy : Nuru.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(on ? .clear : Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var cards: some View {
        if vm.loading && vm.occurrences.isEmpty {
            ProgressView().padding(.top, Nuru.S.xl)
        } else if vm.list.isEmpty {
            VStack(spacing: Nuru.S.sm) {
                ZStack { Circle().fill(Nuru.goldTint).frame(width: 48, height: 48); Icon(.calendarDays, size: 21, color: Nuru.gold) }
                Text(vm.segment == .today ? "Nothing today" : vm.segment == .upcoming ? "Nothing coming up" : "No RSVPs yet")
                    .font(.nHeading).foregroundStyle(Nuru.ink)
                Text(vm.segment == .rsvps ? "Tap an event to say you'll be there." : "New gatherings appear here as they're scheduled.")
                    .font(.nCaption).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl)
            .cardSurfaceEv()
        } else {
            ForEach(vm.list) { occ in
                NavigationLink(value: occ) { EventCardView(occ: occ) }.buttonStyle(.plain)
            }
        }
    }
}

struct EventCardView: View {
    let occ: CalendarOccurrence

    var body: some View {
        let live = Ev.isLive(occ.startAt, occ.endAt)
        let accent = Ev.categoryColor(occ.category)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if let url = occ.primaryImageUrl.flatMap(URL.init) {
                    AsyncImage(url: url) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                        .frame(height: 150).frame(maxWidth: .infinity).clipped()
                } else {
                    LinearGradient(colors: [Nuru.navy700, Nuru.navy, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .frame(height: 150)
                }
                HStack(alignment: .top) {
                    VStack(spacing: 0) {
                        Text(Ev.weekday(occ.startAt, "EEE").uppercased()).font(.inter(9, .bold)).foregroundStyle(accent)
                        Text(Ev.weekday(occ.startAt, "d")).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.navy)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Spacer()
                    if live {
                        HStack(spacing: 4) { Circle().fill(.white).frame(width: 5, height: 5); Text("LIVE").font(.inter(9, .bold)).foregroundStyle(.white) }
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Nuru.danger, in: Capsule())
                    } else if occ.going >= 120 {
                        Text("🔥 Popular").font(.inter(9, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 4).background(Color.black.opacity(0.35), in: Capsule())
                    }
                }
                .padding(Nuru.S.sm)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(occ.title).font(.fraunces(17, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                if let d = occ.description, !d.isEmpty {
                    Text(d).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2).padding(.top, 4)
                }
                HStack(spacing: Nuru.S.base) {
                    metaRow(.clock, Ev.timeRange(occ.startAt, occ.endAt))
                    if let loc = occ.location { metaRow(.mapPin, loc) }
                }
                .padding(.top, Nuru.S.sm)
                HStack(spacing: Nuru.S.sm) {
                    Icon(.users, size: 13, color: Nuru.ink600)
                    Text(occ.going > 0 ? "\(occ.going) going" : "Be the first to RSVP").font(.nCaption).foregroundStyle(Nuru.muted)
                    Spacer(minLength: 0)
                    if !live { Text(Ev.countdown(occ.startAt)).font(.inter(10, .semibold)).foregroundStyle(accent) }
                }
                .padding(.top, Nuru.S.md)
            }
            .padding(Nuru.S.base)
        }
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
    }

    private func metaRow(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) { Icon(icon, size: 12, color: Nuru.ink600); Text(text).font(.inter(10)).foregroundStyle(Nuru.muted).lineLimit(1) }
    }
}

private extension View {
    func cardSurfaceEv() -> some View {
        background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
