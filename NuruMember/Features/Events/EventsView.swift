// Events ("Gathered together" make) — the native port of screens/EventsScreen.tsx.
// Navy header with overline + subline + summary pills, a tappable week-strip,
// the navy CALENDAR card, a Today/Upcoming/My-RSVPs segment, search + category
// chips, photo-forward gathering cards, a "Series you follow" list and an
// "Announcements" list. Bound to the real calendar, series and announcement
// endpoints; each section loads independently and hides when empty.
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
    /// "h:mm a" for an arbitrary date (series cadence subline).
    static func timeOfDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
    /// Short relative-ish date label for announcements, e.g. "Jun 21".
    static func shortDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date(iso))
    }
}

enum EventSegment: String, CaseIterable { case today = "Today", upcoming = "Upcoming", rsvps = "My RSVPs" }

/// Pushable routes within the Events stack (the month calendar).
enum EventsNav: Hashable { case calendar }

/// One cell in the 7-day week strip.
struct WeekDay: Identifiable {
    let id = UUID()
    let date: Date
    let letter: String   // S M T W T F S
    let day: Int         // day-of-month number
    let isToday: Bool
    let hasEvents: Bool
}

@MainActor
final class EventsViewModel: ObservableObject {
    @Published var occurrences: [CalendarOccurrence] = []
    @Published var series: [EventSeries] = []
    @Published var announcements: [MyAnnouncement] = []
    @Published var rsvps: [MyRsvp] = []
    @Published var segment: EventSegment = .today
    @Published var selectedDay: Date
    @Published var search = ""
    @Published var category = "All"
    @Published var loading = true
    @Published var error: String?

    let categories = ["All", "Worship", "Cell", "Leaders", "Youth"]

    private let from: String
    private let to: String
    private let todayStart: Date
    private let todayEnd: Date
    private let cal = Calendar.current

    init() {
        let start = Calendar.current.startOfDay(for: Date())
        todayStart = start
        todayEnd = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        selectedDay = start
        let f = ISO8601DateFormatter()
        from = f.string(from: Calendar.current.date(byAdding: .day, value: -7, to: start)!)
        to = f.string(from: Calendar.current.date(byAdding: .day, value: 60, to: start)!)
    }

    func load() async {
        loading = true; error = nil
        async let occ = try? MemberAPI.calendar(from: from, to: to)
        async let ser = try? MemberAPI.eventSeries()
        async let ann = try? MemberAPI.myAnnouncements()
        async let rs = try? MemberAPI.myRsvps()
        occurrences = (await occ ?? []).sorted { Ev.date($0.startAt) < Ev.date($1.startAt) }
        series = await ser ?? []
        announcements = await ann ?? []
        rsvps = await rs ?? []
        if occurrences.isEmpty && series.isEmpty && announcements.isEmpty {
            error = "Couldn't load events."
        }
        loading = false
    }

    // Summary counts (header pills).
    var thisWeekCount: Int {
        let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart)!
        return occurrences.filter { let d = Ev.date($0.startAt); return d >= todayStart && d < weekEnd }.count
    }
    var goingCount: Int { rsvps.filter { $0.status == "going" }.count }
    var upcomingCount: Int { occurrences.filter { Ev.date($0.startAt) >= todayStart }.count }

    /// The current week, Sunday → Saturday, with event-dot + today markers.
    var week: [WeekDay] {
        let weekday = cal.component(.weekday, from: todayStart) // 1 = Sunday
        let sunday = cal.date(byAdding: .day, value: -(weekday - 1), to: todayStart)!
        let eventDays = Set(occurrences.map { cal.startOfDay(for: Ev.date($0.startAt)) })
        let letters = ["S", "M", "T", "W", "T", "F", "S"]
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i, to: sunday)!
            return WeekDay(
                date: d,
                letter: letters[i],
                day: cal.component(.day, from: d),
                isToday: cal.isDate(d, inSameDayAs: todayStart),
                hasEvents: eventDays.contains(cal.startOfDay(for: d))
            )
        }
    }

    var monthLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: todayStart).uppercased()
    }
    var headerSubline: String {
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"
        return "Today · \(f.string(from: todayStart)) · East Africa Time"
    }

    func isSelected(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: selectedDay) }

    /// Segment + selected-day + search + category, in that order.
    var list: [CalendarOccurrence] {
        var rows = occurrences
        switch segment {
        case .today:
            rows = rows.filter { cal.isDate(Ev.date($0.startAt), inSameDayAs: selectedDay) }
        case .upcoming:
            rows = rows.filter { Ev.date($0.startAt) >= todayStart }
        case .rsvps:
            let ids = Set(rsvps.map(\.eventId))
            rows = rows.filter { ids.contains($0.occurrenceId) }
        }
        if category != "All" {
            rows = rows.filter { ($0.category ?? "").lowercased() == category.lowercased() }
        }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            rows = rows.filter {
                $0.title.lowercased().contains(q) || ($0.location ?? "").lowercased().contains(q)
            }
        }
        return rows
    }

    func count(_ s: EventSegment) -> Int {
        switch s {
        case .today: return occurrences.filter { cal.isDate(Ev.date($0.startAt), inSameDayAs: todayStart) }.count
        case .upcoming: return upcomingCount
        case .rsvps: return rsvps.count
        }
    }

    /// Optimistically flip a series' follow state after the server confirms.
    func applyFollow(_ result: SeriesFollowResult) {
        guard let i = series.firstIndex(where: { $0.seriesId == result.seriesId }) else { return }
        let s = series[i]
        series[i] = EventSeries(
            seriesId: s.seriesId, title: s.title, category: s.category, cadence: s.cadence,
            nextAt: s.nextAt, nextOccurrenceId: s.nextOccurrenceId, nextEndAt: s.nextEndAt,
            location: s.location, following: result.following, newCount: s.newCount
        )
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
                        weekStrip
                        calendarLink
                        segmentBar
                        searchBar
                        categoryChips
                        gatherings
                        if !vm.series.isEmpty { seriesSection }
                        if !vm.announcements.isEmpty { announcementsSection }
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .navigationDestination(for: EventsNav.self) { _ in CalendarView() }
            .nuruDestinations()
        }
        .background(Color.clear.preferredColorScheme(.dark))   // full-bleed navy header → white status bar
        .task { if vm.occurrences.isEmpty && vm.series.isEmpty && vm.announcements.isEmpty { await vm.load() } }
    }

    // MARK: 1 — navy header

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("EVENTS").font(.inter(11, .bold)).kerning(2).foregroundStyle(Color(hex: 0x9A7A2A))
                    Text("Gathered together").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.navy)
                    Text(vm.headerSubline).font(.inter(11)).foregroundStyle(Color(hex: 0x68758A))
                }
                Spacer()
                Icon(.bell, size: 19, color: Nuru.navy)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            HStack(spacing: Nuru.S.sm) {
                pulseChip("\(vm.thisWeekCount) this week", icon: .calendarDays)
                pulseChip("\(vm.goingCount) you're going", icon: .check)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen).padding(.top, 60).padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private func pulseChip(_ text: String, icon: Lucide) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 11, color: Nuru.gold)
            Text(text).font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x68758A))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 2 — week strip

    private var weekStrip: some View {
        VStack(spacing: Nuru.S.md) {
            HStack {
                Text(vm.monthLabel).font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.muted)
                Spacer()
                Text("TODAY").font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.gold)
            }
            HStack(spacing: 0) {
                ForEach(vm.week) { d in
                    let on = vm.isSelected(d.date)
                    Button { vm.selectedDay = d.date } label: {
                        VStack(spacing: 5) {
                            Text(d.letter).font(.inter(10, .semibold)).foregroundStyle(on ? Nuru.onNavyDim : Nuru.faint)
                            Text("\(d.day)").font(.fraunces(16, .semibold)).foregroundStyle(on ? .white : Nuru.ink)
                            Circle()
                                .fill(d.hasEvents ? (on ? Nuru.gold : Nuru.gold) : .clear)
                                .frame(width: 5, height: 5)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(on ? Nuru.navy : .clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(alignment: .top) {
                            if d.isToday && !on {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Nuru.gold.opacity(0.5), lineWidth: 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: 3 — calendar card

    private var calendarLink: some View {
        NavigationLink(value: EventsNav.calendar) {
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
        .buttonStyle(.plain)
    }

    // MARK: 4 — segment

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

    // MARK: 5 — search

    private var searchBar: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.search, size: 16, color: Nuru.muted)
            TextField("Search events by name or place", text: $vm.search)
                .font(.inter(13))
                .foregroundStyle(Nuru.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, 13)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.pill, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.pill, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 6 — category chips

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(vm.categories, id: \.self) { c in
                    let on = vm.category == c
                    Button { vm.category = c } label: {
                        Text(c).font(.inter(12, on ? .semibold : .medium))
                            .foregroundStyle(on ? .white : Nuru.ink600)
                            .padding(.horizontal, Nuru.S.base).padding(.vertical, 9)
                            .background(on ? Nuru.navy : Nuru.white, in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: 7 — today's gatherings

    private var gatherings: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text("Today's gatherings").font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
                Spacer()
                NavigationLink(value: EventsNav.calendar) {
                    HStack(spacing: 3) {
                        Text("All & calendar").font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                        Icon(.chevronRight, size: 12, color: Nuru.gold)
                    }
                }
                .buttonStyle(.plain)
            }
            gatheringBody
        }
    }

    @ViewBuilder
    private var gatheringBody: some View {
        if vm.loading && vm.occurrences.isEmpty {
            ProgressView().frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl)
        } else if vm.error != nil && vm.occurrences.isEmpty {
            VStack(spacing: Nuru.S.xs) {
                Text("Couldn't load events").font(.fraunces(16, .semibold)).foregroundStyle(Nuru.ink)
                Text("Too many requests; slow down.").font(.nCaption).foregroundStyle(Nuru.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(Nuru.S.base)
            .cardSurfaceEv()
        } else if vm.list.isEmpty {
            VStack(spacing: Nuru.S.sm) {
                ZStack { Circle().fill(Nuru.goldTint).frame(width: 48, height: 48); Icon(.calendarDays, size: 21, color: Nuru.gold) }
                Text("Nothing today").font(.nHeading).foregroundStyle(Nuru.ink)
                Text("New gatherings appear here as they're scheduled.")
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

    // MARK: 8 — series you follow

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: .calendarClock, title: "SERIES YOU FOLLOW")
            VStack(spacing: 0) {
                ForEach(Array(vm.series.enumerated()), id: \.element.id) { idx, s in
                    SeriesRow(series: s) { await follow(s) }
                    if idx < vm.series.count - 1 { Divider().overlay(Nuru.border) }
                }
            }
            .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.xs)
            .cardSurfaceEv()
        }
    }

    private func follow(_ s: EventSeries) async {
        if let result = try? await MemberAPI.toggleSeriesFollow(s.seriesId) {
            vm.applyFollow(result)
        }
    }

    // MARK: 9 — announcements

    private var announcementsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader(icon: .megaphone, title: "ANNOUNCEMENTS")
            VStack(spacing: 0) {
                ForEach(Array(vm.announcements.enumerated()), id: \.element.id) { idx, a in
                    NavigationLink(value: AppRoute.announcement(a.announcementId)) {
                        AnnouncementRow(announcement: a)
                    }
                    .buttonStyle(.plain)
                    if idx < vm.announcements.count - 1 { Divider().overlay(Nuru.border) }
                }
            }
            .padding(.horizontal, Nuru.S.base).padding(.vertical, Nuru.S.xs)
            .cardSurfaceEv()
        }
    }

    // Shared section header: gold overline + "See all".
    private func sectionHeader(icon: Lucide, title: String) -> some View {
        HStack {
            HStack(spacing: 6) {
                Icon(icon, size: 13, color: Nuru.gold)
                Text(title).font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.muted)
            }
            Spacer()
            Text("See all").font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
        }
        .padding(.bottom, Nuru.S.sm)
    }
}

// MARK: series row

private struct SeriesRow: View {
    let series: EventSeries
    let onToggle: () async -> Void
    @State private var busy = false

    var body: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Ev.categoryColor(series.category).opacity(0.16))
                    .frame(width: 44, height: 44)
                Icon(.calendarDays, size: 20, color: Ev.categoryColor(series.category))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(series.title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    if series.newCount > 0 {
                        Text("\(series.newCount) new").font(.inter(9, .bold))
                            .foregroundStyle(Nuru.goldChipText)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Nuru.goldChipBg, in: Capsule())
                    }
                }
                Text(cadenceLine).font(.inter(11)).foregroundStyle(Nuru.muted).lineLimit(1)
            }
            Spacer(minLength: Nuru.S.sm)
            Button {
                guard !busy else { return }
                busy = true
                Task { await onToggle(); busy = false }
            } label: {
                if series.following {
                    HStack(spacing: 4) {
                        Icon(.check, size: 12, color: .white)
                        Text("Following").font(.inter(11, .semibold)).foregroundStyle(.white)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Nuru.navy, in: Capsule())
                } else {
                    HStack(spacing: 4) {
                        Icon(.plus, size: 12, color: Nuru.ink)
                        Text("Follow").font(.inter(11, .semibold)).foregroundStyle(Nuru.ink)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Nuru.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                }
            }
            .buttonStyle(.plain)
            .opacity(busy ? 0.5 : 1)
        }
        .padding(.vertical, Nuru.S.md)
    }

    private var cadenceLine: String {
        let time = series.nextAt.map { Ev.timeOfDate(Ev.date($0)) }
        let head: String
        let c = series.cadence.lowercased()
        if c.contains("week") {
            // "Every Sunday" from the next occurrence weekday, else from cadence text.
            if let next = series.nextAt {
                head = "Every \(Ev.weekday(next, "EEEE"))"
            } else {
                head = series.cadence
            }
        } else if c.contains("one") || c.contains("once") {
            head = "One-off"
        } else {
            head = series.cadence
        }
        return time.map { "\(head) · \($0)" } ?? head
    }
}

// MARK: announcement row

private struct AnnouncementRow: View {
    let announcement: MyAnnouncement

    var body: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                if let url = announcement.primaryImageUrl.flatMap(URL.init) {
                    CachedAsyncImage(url: url) { p in
                        (p.image ?? Image(systemName: "photo")).resizable().scaledToFill()
                    }
                    .frame(width: 48, height: 48).clipped()
                } else {
                    Nuru.goldGradient.frame(width: 48, height: 48)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(announcement.title).font(.inter(14, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    Spacer(minLength: Nuru.S.sm)
                    if let sent = announcement.sentAt {
                        Text(Ev.shortDate(sent)).font(.inter(10)).foregroundStyle(Nuru.faint)
                    }
                }
                Text(announcement.body).font(.inter(11)).foregroundStyle(Nuru.muted).lineLimit(1)
            }
            Icon(.chevronRight, size: 16, color: Nuru.ink300)
        }
        .padding(.vertical, Nuru.S.md)
    }
}

// MARK: gathering card

struct EventCardView: View {
    let occ: CalendarOccurrence

    var body: some View {
        let live = Ev.isLive(occ.startAt, occ.endAt)
        let accent = Ev.categoryColor(occ.category)
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .top) {
                if let url = occ.primaryImageUrl.flatMap(URL.init) {
                    CachedAsyncImage(url: url) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
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
