// Events ("Gathered together" make) — the native port of CommunityTab.tsx.
// Cream header with pulse chips, an optional image-backed LIVE-NOW hero, a
// scrollable 14-day date strip, the navy CALENDAR card, a Today/Upcoming/
// My-RSVPs segment pill, search + colored category chips, photo-forward
// gathering cards with quick-RSVP, a "Series you follow" rail and an
// "Announcements" feed (both with real See-all pages). Bound to the real
// calendar, series, rsvp and announcement endpoints; sections load
// independently and hide when empty.
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
    /// Figma countdown chip: "Today" / "Tomorrow" / "In N days" — nil once past.
    static func dayCountdown(_ iso: String) -> String? {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: Date()),
                                      to: cal.startOfDay(for: date(iso))).day ?? 0
        if days < 0 { return nil }
        if days == 0 { return "Today" }
        if days == 1 { return "Tomorrow" }
        return "In \(days) days"
    }
    /// Category accents — matched to the make (Worship gold, Cell indigo,
    /// Leaders sky #0EA5E9, Youth green #16A34A).
    static func categoryColor(_ c: String?) -> Color {
        switch (c ?? "").lowercased() {
        case "worship": return Color(hex: 0xC89B3C)
        case "youth": return Color(hex: 0x16A34A)
        case "leaders": return Color(hex: 0x0EA5E9)
        case "cell": return Color(hex: 0x6366F1)
        case "marketplace": return Color(hex: 0xE07B39)
        default: return Color(hex: 0x59667C)
        }
    }
    static func weekday(_ iso: String, _ fmt: String) -> String {
        let f = DateFormatter(); f.dateFormat = fmt; return f.string(from: date(iso))
    }
    /// "h:mm a" for an arbitrary date (series cadence subline).
    static func timeOfDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
    /// Short date label, e.g. "Jun 21".
    static func shortDate(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: date(iso))
    }
}

enum EventSegment: String, CaseIterable { case today = "Today", upcoming = "Upcoming", rsvps = "My RSVPs" }

/// Pushable routes within the Events stack.
enum EventsNav: Hashable { case calendar, seriesAll, announcementsAll, attendance }

/// One cell in the scrollable date strip.
struct WeekDay: Identifiable {
    // Identity is the day itself — a UUID here regenerated on every `week`
    // recompute, forcing SwiftUI to tear down and rebuild all 14 pills each
    // time occurrences refreshed.
    var id: Date { date }
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
    @Published var segment: EventSegment = .today
    @Published var selectedDay: Date
    @Published var search = ""
    @Published var category = "All"
    @Published var loading = true
    @Published var error: String?
    /// occurrenceId → "going" / "maybe" / "declined" — seeded from /me/rsvps,
    /// updated optimistically by the quick-RSVP button on each card.
    @Published var quickRsvps: [String: String] = [:]

    let categories = ["All", "Worship", "Cell", "Leaders", "Youth"]

    private let from: String
    private let to: String
    private let todayStart: Date
    private let cal = Calendar.current

    init() {
        let start = Calendar.current.startOfDay(for: Date())
        todayStart = start
        selectedDay = start
        let f = ISO8601DateFormatter()
        from = f.string(from: Calendar.current.date(byAdding: .day, value: -7, to: start) ?? start)
        to = f.string(from: Calendar.current.date(byAdding: .day, value: 60, to: start) ?? start)
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
        quickRsvps = Dictionary((await rs ?? []).map { ($0.eventId, $0.status) },
                                uniquingKeysWith: { a, _ in a })
        if occurrences.isEmpty && series.isEmpty && announcements.isEmpty {
            error = "Couldn't load events."
        }
        loading = false
    }

    /// Cycle the quick RSVP (none → going → maybe → declined) and persist it.
    func quickRsvp(_ occ: CalendarOccurrence) async {
        let prev = quickRsvps[occ.occurrenceId]
        let next: String
        switch prev {
        case "going": next = "maybe"
        case "maybe": next = "declined"
        default: next = "going"
        }
        quickRsvps[occ.occurrenceId] = next
        do { try await MemberAPI.rsvp(occ.occurrenceId, status: next) }
        catch {
            quickRsvps[occ.occurrenceId] = prev
            Haptics.error()   // the optimistic flip was rolled back — say so
        }
    }

    // Summary counts (header pills).
    var thisWeekCount: Int {
        let weekEnd = cal.date(byAdding: .day, value: 7, to: todayStart)!
        return occurrences.filter { let d = Ev.date($0.startAt); return d >= todayStart && d < weekEnd }.count
    }
    var goingCount: Int { quickRsvps.values.filter { $0 == "going" }.count }
    var upcomingCount: Int { occurrences.filter { Ev.date($0.startAt) >= todayStart }.count }

    /// The gathering that is live right now, if any — drives the hero card.
    var liveOccurrence: CalendarOccurrence? {
        occurrences.first { Ev.isLive($0.startAt, $0.endAt) }
    }
    /// True live count for the header chip (was hardcoded "1").
    var liveCount: Int {
        occurrences.filter { Ev.isLive($0.startAt, $0.endAt) }.count
    }

    /// Scrollable strip: 14 days starting two days back (Figma week-picker).
    var week: [WeekDay] {
        let letters = DateFormatter()
        letters.dateFormat = "EEEEE"
        let eventDays = Set(occurrences.map { cal.startOfDay(for: Ev.date($0.startAt)) })
        return (-2..<12).map { i in
            let d = cal.date(byAdding: .day, value: i, to: todayStart)!
            return WeekDay(
                date: d,
                letter: letters.string(from: d).uppercased(),
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
    func selectToday() { selectedDay = todayStart }

    /// Occurrence ids with an active RSVP (going or maybe).
    private var rsvpIds: Set<String> {
        Set(quickRsvps.filter { $0.value == "going" || $0.value == "maybe" }.map(\.key))
    }

    /// Segment + selected-day + search + category, in that order.
    var list: [CalendarOccurrence] {
        var rows = occurrences
        switch segment {
        case .today:
            rows = rows.filter { cal.isDate(Ev.date($0.startAt), inSameDayAs: selectedDay) }
        case .upcoming:
            rows = rows.filter { Ev.date($0.startAt) >= todayStart }
        case .rsvps:
            let ids = rsvpIds
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
        case .today: return occurrences.filter { cal.isDate(Ev.date($0.startAt), inSameDayAs: selectedDay) }.count
        case .upcoming: return upcomingCount
        case .rsvps: return rsvpIds.count
        }
    }

    // Section header + empty-state copy, mirroring the make.
    var sectionTitle: String {
        switch segment {
        case .today:
            if cal.isDate(selectedDay, inSameDayAs: todayStart) { return "Today's gatherings" }
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return "Events on \(f.string(from: selectedDay))"
        case .upcoming: return "Coming up"
        case .rsvps: return "Your RSVPs"
        }
    }
    private var hasFilters: Bool {
        category != "All" || !search.trimmingCharacters(in: .whitespaces).isEmpty
    }
    var emptyTitle: String {
        if hasFilters { return "No events match" }
        return segment == .rsvps ? "No RSVPs yet" : "Nothing on this day"
    }
    var emptyCaption: String {
        if hasFilters { return "Try a different search or category." }
        return segment == .rsvps
            ? "Tap an event to say you'll be there."
            : "Browse the full calendar to find a gathering."
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

    func toggleFollow(_ s: EventSeries) async {
        if let result = try? await MemberAPI.toggleSeriesFollow(s.seriesId) {
            applyFollow(result)
        }
    }
}

struct EventsView: View {
    /// True when hosted as the "Events" segment inside the You tab (L4)
    /// rather than as its own top-level tab — the You tab's own segmented
    /// control already clears the status bar, so this header needs only a
    /// little breathing room, not a second 60pt reservation for it.
    var embeddedInYou: Bool = false

    @StateObject private var vm = EventsViewModel()
    @EnvironmentObject private var tabs: TabRouter
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    VStack(spacing: Nuru.S.base) {
                        if let live = vm.liveOccurrence {
                            NavigationLink(value: live) { LiveHeroCard(occ: live) }.buttonStyle(.pressableSubtle)
                        }
                        weekStrip
                        calendarLink
                        attendanceLink
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
            .navigationDestination(for: EventsNav.self) { nav in
                switch nav {
                case .calendar: CalendarView()
                case .seriesAll: SeriesListPage(vm: vm)
                case .announcementsAll: AnnouncementsListPage(vm: vm)
                case .attendance: AttendanceView()
                }
            }
            .nuruDestinations()
        }
        .task { if vm.occurrences.isEmpty && vm.series.isEmpty && vm.announcements.isEmpty { await vm.load() } }
        // Cross-tab deep link (Home's live-now card): open the event detail
        // inside THIS tab, with the Events list as the back stop.
        .onReceive(tabs.$eventLink) { link in
            guard let link else { return }
            path = NavigationPath()
            path.append(link)
            DispatchQueue.main.async { tabs.eventLink = nil }
        }
    }

    // MARK: 1 — cream header

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("📅 EVENTS").font(.inter(11, .bold)).kerning(2).foregroundStyle(Color(hex: 0x9A7A2A))
                    Text("Gathered together").font(.fraunces(28, .semibold)).foregroundStyle(Nuru.navy)
                    Text(vm.headerSubline).font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
                }
                Spacer()
                NavigationLink(value: AppRoute.notifications) {
                    Icon(.bell, size: 19, color: Nuru.navy)
                        .frame(width: 44, height: 44)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
                        .overlay(alignment: .topTrailing) {
                            Circle().fill(Nuru.gold).frame(width: 8, height: 8)
                                .shadow(color: Nuru.gold.opacity(0.8), radius: 4)
                                .padding(8)
                        }
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: Nuru.S.sm) {
                if vm.liveOccurrence != nil { livePulseChip }
                pulseChip("\(vm.thisWeekCount) this week", icon: .calendarDays)
                pulseChip("\(vm.goingCount) you're going", icon: .check)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen).padding(.top, embeddedInYou ? Nuru.S.base : 60).padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    private var livePulseChip: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(hex: 0x22C55E)).frame(width: 6, height: 6)
            Text("\(vm.liveCount) live now").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x15803D))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(hex: 0xDCFCE7), in: Capsule())
    }

    private func pulseChip(_ text: String, icon: Lucide) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 11, color: Nuru.gold)
            Text(text).font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x59667C))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 2 — scrollable date strip

    private var weekStrip: some View {
        VStack(spacing: Nuru.S.sm) {
            HStack {
                Text(vm.monthLabel).font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xA8861C))
                Spacer()
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.selectToday() }
                } label: {
                    Text("TODAY").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.navy)
                        .padding(.vertical, 6).padding(.leading, 12)   // invisible tap-target growth
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(vm.week) { d in dayPill(d) }
                }
            }
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func dayPill(_ d: WeekDay) -> some View {
        let on = vm.isSelected(d.date)
        let bg: Color = on ? Nuru.navy : (d.isToday ? Nuru.gold.opacity(0.12) : .clear)
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.selectedDay = d.date }
        } label: {
            VStack(spacing: 3) {
                Text(d.letter).font(.inter(9, .semibold)).kerning(0.8)
                    .foregroundStyle(on ? Color.white.opacity(0.65) : Color(hex: 0x74808F))
                Text("\(d.day)").font(.fraunces(16, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
                Circle().fill(d.hasEvents ? Nuru.gold : .clear).frame(width: 4, height: 4)
            }
            .frame(width: 44)
            .padding(.vertical, 8)
            .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    // MARK: 3 — calendar card (navy gradient + glow)

    private var calendarLink: some View {
        NavigationLink(value: EventsNav.calendar) {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.goldGradient).frame(width: 48, height: 48)
                    Icon(.calendarDays, size: 22, color: Nuru.navy)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CALENDAR").font(.inter(9, .bold)).kerning(1.5).foregroundStyle(Nuru.goldLight)
                    Text("All events & calendar").font(.nRowTitle).foregroundStyle(Nuru.onNavy)
                    Text("See the whole month at a glance · \(vm.upcomingCount) upcoming")
                        .font(.nCardMeta).foregroundStyle(Nuru.onNavyDim)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: .white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .padding(Nuru.S.base)
            .background {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [Nuru.navy, Color(hex: 0x060F1C)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(Nuru.gold.opacity(0.33)).frame(width: 144, height: 144).blur(radius: 36).offset(x: 40, y: -48)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: 3b — church attendance card

    /// Scan into today's service, and the streak that comes out of showing up.
    /// Same visual weight as CALENDAR: on a Sunday morning this is the reason to
    /// open the app.
    private var attendanceLink: some View {
        NavigationLink(value: EventsNav.attendance) {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.goldGradient).frame(width: 48, height: 48)
                    Icon(.qrCode, size: 22, color: Nuru.navy)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CHURCH ATTENDANCE").font(.inter(9, .bold)).kerning(1.5).foregroundStyle(Nuru.goldLight)
                    Text("Check in to a service").font(.nRowTitle).foregroundStyle(Nuru.onNavy)
                    Text("Scan the QR at church · see your streak")
                        .font(.nCardMeta).foregroundStyle(Nuru.onNavyDim)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: .white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .padding(Nuru.S.base)
            .background {
                ZStack(alignment: .topTrailing) {
                    LinearGradient(colors: [Nuru.navy, Color(hex: 0x060F1C)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(Nuru.gold.opacity(0.33)).frame(width: 144, height: 144).blur(radius: 36).offset(x: 40, y: -48)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: 4 — segment pills (single capsule container)

    private var segmentBar: some View {
        HStack(spacing: 6) {
            ForEach(EventSegment.allCases, id: \.self) { s in segmentPill(s) }
        }
        .padding(4)
        .background(Nuru.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    private func segmentPill(_ s: EventSegment) -> some View {
        let on = vm.segment == s
        return Button {
            guard !on else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.segment = s }
        } label: {
            HStack(spacing: 6) {
                Text(s.rawValue).font(.inter(11, .semibold)).foregroundStyle(on ? .white : Nuru.ink600)
                Text("\(vm.count(s))").font(.inter(9, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(on ? Nuru.gold : Nuru.surface, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(on ? Nuru.navy : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: 5 — search (with clear affordance)

    private var searchBar: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.search, size: 15, color: Color(hex: 0x74808F))
            TextField("Search events by name or place", text: $vm.search)
                .font(.inter(13))
                .foregroundStyle(Nuru.navy)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !vm.search.isEmpty {
                Button {
                    Haptics.tap()
                    vm.search = ""
                } label: {
                    Icon(.x, size: 15, color: Color(hex: 0x74808F))
                        .frame(width: 28, height: 28)          // comfortable tap target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Nuru.S.md).padding(.vertical, 11)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 6 — category chips (active takes the category color)

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Nuru.S.sm) {
                ForEach(vm.categories, id: \.self) { c in
                    let on = vm.category == c
                    let color = c == "All" ? Nuru.navy : Ev.categoryColor(c)
                    Button {
                        guard !on else { return }
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.category = c }
                    } label: {
                        Text(c).font(.inter(12, on ? .semibold : .medium))
                            .foregroundStyle(on ? .white : Nuru.ink600)
                            .padding(.horizontal, Nuru.S.base).padding(.vertical, 9)
                            .background(on ? color : Nuru.white, in: Capsule())
                            .overlay(Capsule().stroke(on ? .clear : Nuru.border, lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: 7 — gatherings list

    private var gatherings: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text(vm.sectionTitle).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
                Spacer()
                NavigationLink(value: EventsNav.calendar) {
                    HStack(spacing: 3) {
                        Text("All & calendar").font(.inter(11, .semibold)).foregroundStyle(Nuru.navy)
                        Icon(.chevronRight, size: 12, color: Nuru.navy)
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
            // Skeleton gathering cards — same silhouette as the real thing, so
            // nothing jumps when content arrives.
            VStack(spacing: Nuru.S.md) {
                skeletonCard
                skeletonCard.opacity(0.55)
            }
        } else if vm.error != nil && vm.occurrences.isEmpty {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("Couldn't load events").font(.nRowTitle).foregroundStyle(Nuru.ink)
                Text("Check your connection, then try again.").font(.nCardBody).foregroundStyle(Nuru.muted)
                Button {
                    Haptics.tap()
                    Task { await vm.load() }
                } label: {
                    Text("Try again").font(.inter(11, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Nuru.navy, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(Nuru.S.base)
            .cardSurfaceEv()
        } else if vm.list.isEmpty {
            emptyGatherings
        } else {
            ForEach(vm.list) { occ in
                NavigationLink(value: occ) {
                    EventCardView(occ: occ,
                                  rsvpStatus: vm.quickRsvps[occ.occurrenceId],
                                  onRsvp: { await vm.quickRsvp(occ) })
                }
                .buttonStyle(.pressableSubtle)
            }
        }
    }

    /// Shimmering placeholder in the shape of a gathering card.
    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(Nuru.surface).frame(height: 150).nuruShimmer()
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(width: 190, height: 14).nuruShimmer()
                RoundedRectangle(cornerRadius: 6).fill(Nuru.surface).frame(width: 130, height: 10).nuruShimmer()
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var emptyGatherings: some View {
        VStack(spacing: Nuru.S.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.surface).frame(width: 48, height: 48)
                Icon(.calendarDays, size: 20, color: Nuru.gold)
            }
            Text(vm.emptyTitle).font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
            Text(vm.emptyCaption).font(.nCardMeta).foregroundStyle(Nuru.faint).multilineTextAlignment(.center)
            NavigationLink(value: EventsNav.calendar) {
                HStack(spacing: 6) {
                    Icon(.calendarDays, size: 13, color: .white)
                    Text("View calendar").font(.inter(11, .semibold)).foregroundStyle(.white)
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                .background(Nuru.navy, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl).padding(.horizontal, Nuru.S.base)
        .cardSurfaceEv()
    }

    // MARK: 8 — series you follow (header inside the card, per the make)

    private var seriesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            railHeader(icon: .sparkles, title: "SERIES YOU FOLLOW", nav: .seriesAll)
            ForEach(Array(vm.series.enumerated()), id: \.element.id) { idx, s in
                SeriesRailRow(series: s) { await vm.toggleFollow(s) }
                if idx < vm.series.count - 1 { Divider().overlay(Nuru.border) }
            }
        }
        .padding(Nuru.S.base)
        .cardSurfaceEv()
    }

    // MARK: 9 — announcements

    private var announcementsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            railHeader(icon: .megaphone, title: "ANNOUNCEMENTS", nav: .announcementsAll)
            ForEach(Array(vm.announcements.enumerated()), id: \.element.id) { idx, a in
                NavigationLink(value: AppRoute.announcement(a.announcementId)) {
                    AnnouncementRow(announcement: a)
                }
                .buttonStyle(.pressable)
                if idx < vm.announcements.count - 1 { Divider().overlay(Nuru.border) }
            }
        }
        .padding(Nuru.S.base)
        .cardSurfaceEv()
    }

    // Shared in-card rail header: gold overline + navy "See all" that navigates.
    private func railHeader(icon: Lucide, title: String, nav: EventsNav) -> some View {
        HStack {
            HStack(spacing: 6) {
                Icon(icon, size: 13, color: Color(hex: 0xA8861C))
                Text(title).font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xA8861C))
            }
            Spacer()
            NavigationLink(value: nav) {
                Text("See all").font(.inter(11, .semibold)).foregroundStyle(Nuru.navy)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, Nuru.S.xs)
    }
}

// MARK: - live-now hero (image-backed, links to the event)

private struct LiveHeroCard: View {
    let occ: CalendarOccurrence

    var body: some View {
        // Media-first hero: the poster keeps its NATURAL aspect (the card grows
        // to fit it — no crop, no letterbox), with the live chrome overlaid;
        // title/meta/footer sit on navy beneath.
        VStack(spacing: 0) {
            media
            content
                .padding(.horizontal, Nuru.S.base)
                .padding(.top, Nuru.S.md)
                .padding(.bottom, Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .topTrailing) {
                LinearGradient(colors: [Color(hex: 0x0B1F33), Color(hex: 0x081424)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Nuru.gold.opacity(0.4)).frame(width: 160, height: 160).blur(radius: 40).offset(x: 40, y: -48)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .nuruShadow()
    }

    private var media: some View {
        FitImage(url: occ.primaryImageUrl.flatMap(URL.init),
                 fallback: LinearGradient(colors: [Color(hex: 0x0B1F33), Nuru.navy, Color(hex: 0x081424)],
                                          startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                LinearGradient(colors: [Color(hex: 0x0B1F33, alpha: 0.15),
                                        Color(hex: 0x0B1F33, alpha: 0.0),
                                        Color(hex: 0x081424, alpha: 0.55)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) {
                HStack(spacing: 8) {
                    livePill
                    Text((occ.category ?? "Gathering").uppercased())
                        .font(.inter(9, .bold)).kerning(1.5).foregroundStyle(Nuru.goldLight)
                }
                .padding(Nuru.S.base)
            }
            .overlay(alignment: .topTrailing) {
                Icon(.qrCode, size: 18, color: .white)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(Nuru.S.base)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(occ.title).font(.fraunces(21, .semibold)).foregroundStyle(.white).lineLimit(2)
            HStack(spacing: Nuru.S.base) {
                heroMeta(.clock, Ev.timeRange(occ.startAt, occ.endAt))
                if let loc = occ.location, !loc.isEmpty { heroMeta(.mapPin, loc) }
            }
            .padding(.top, Nuru.S.sm)
            footer.padding(.top, Nuru.S.md)
        }
    }

    private var footer: some View {
        HStack(spacing: Nuru.S.sm) {
            heroAvatars
            Text("\(occ.going) worshipping").font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.85))
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Icon(.qrCode, size: 14, color: Nuru.navy)
                Text("CHECK IN").font(.inter(10, .bold)).kerning(1).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var livePill: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 5, height: 5)
            Text("LIVE NOW").font(.inter(9, .bold)).kerning(1).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(hex: 0x16A34A), in: Capsule())
    }

    @ViewBuilder private var heroAvatars: some View {
        let list = Array((occ.attendees ?? []).prefix(4))
        if !list.isEmpty {
            HStack(spacing: -8) {
                ForEach(list) { a in
                    Avatar(url: a.avatarUrl, name: a.fullName, size: 24)
                        .overlay(Circle().stroke(Color(hex: 0x081424, alpha: 0.95), lineWidth: 2))
                }
            }
        }
    }

    private func heroMeta(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 13, color: Nuru.goldLight)
            Text(text).font(.nCardMeta).foregroundStyle(.white.opacity(0.8)).lineLimit(1)
        }
    }
}

// MARK: - series rail row

private struct SeriesRailRow: View {
    let series: EventSeries
    let onToggle: () async -> Void

    var body: some View {
        HStack(spacing: Nuru.S.md) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Ev.categoryColor(series.category).opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Ev.categoryColor(series.category).opacity(0.2), lineWidth: 1))
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(series.title).font(.inter(13, .medium)).foregroundStyle(Nuru.navy).lineLimit(1)
                    if series.following && series.newCount > 0 {
                        Text("\(series.newCount) new").font(.inter(8, .bold))
                            .foregroundStyle(Color(hex: 0x8A6D18))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Nuru.gold.opacity(0.15), in: Capsule())
                    }
                }
                Text(series.cadenceLine).font(.nCardMeta).foregroundStyle(Nuru.muted).lineLimit(1)
            }
            Spacer(minLength: Nuru.S.sm)
            FollowButton(following: series.following, onToggle: onToggle)
        }
        .padding(.vertical, Nuru.S.md)
    }
}

// Follow / Following pill — navy when following, ghost otherwise (per the make).
private struct FollowButton: View {
    let following: Bool
    let onToggle: () async -> Void
    @State private var busy = false

    var body: some View {
        Button {
            guard !busy else { return }
            Haptics.action()
            busy = true
            Task { await onToggle(); busy = false }
        } label: {
            HStack(spacing: 4) {
                Icon(following ? .check : .plus, size: 12, color: following ? .white : Nuru.navy)
                Text(following ? "Following" : "Follow")
                    .font(.inter(11, .semibold)).foregroundStyle(following ? .white : Nuru.navy)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(following ? Nuru.navy : .clear, in: Capsule())
            .overlay(Capsule().stroke(following ? .clear : Nuru.border, lineWidth: 1))
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: following)
        }
        .buttonStyle(.pressable)
        .opacity(busy ? 0.5 : 1)
    }
}

// Cadence subline shared by the rail and the See-all page ("Every Sunday · 9:00 AM").
private extension EventSeries {
    var cadenceLine: String {
        let time = nextAt.map { Ev.timeOfDate(Ev.date($0)) }
        let head: String
        let c = cadence.lowercased()
        if c.contains("week") {
            if let next = nextAt { head = "Every \(Ev.weekday(next, "EEEE"))" } else { head = cadence }
        } else if c.contains("one") || c.contains("once") {
            head = "One-off"
        } else {
            head = cadence
        }
        return time.map { "\(head) · \($0)" } ?? head
    }
}

// MARK: - announcement row (icon/image tile + verified badge + unread dot)

private struct AnnouncementRow: View {
    let announcement: MyAnnouncement

    var body: some View {
        HStack(alignment: .top, spacing: Nuru.S.md) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(announcement.title).font(.inter(13, .medium)).foregroundStyle(Nuru.navy).lineLimit(1)
                    Icon(.badgeCheck, size: 12, color: Nuru.gold)
                }
                Text(announcement.body).font(.nCardMeta).foregroundStyle(Nuru.muted).lineLimit(1)
            }
            Spacer(minLength: Nuru.S.sm)
            VStack(alignment: .trailing, spacing: 5) {
                if let sent = announcement.sentAt {
                    Text(timeAgo(sent)).font(.inter(9)).foregroundStyle(Nuru.faint)
                }
                if !announcement.opened {
                    Circle().fill(Nuru.gold).frame(width: 6, height: 6)
                }
            }
        }
        .padding(.vertical, Nuru.S.md)
    }

    @ViewBuilder private var tile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Nuru.gold.opacity(0.12))
            if let url = announcement.primaryImageUrl.flatMap(URL.init) {
                CachedAsyncImage(url: url) { p in
                    if let img = p.image { img.resizable().scaledToFill() }
                    else { Icon(.megaphone, size: 15, color: Nuru.gold) }
                }
            } else {
                Icon(.megaphone, size: 15, color: Nuru.gold)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - gathering card (photo-forward; shared with CalendarView)

struct EventCardView: View {
    let occ: CalendarOccurrence
    var rsvpStatus: String? = nil
    var onRsvp: (() async -> Void)? = nil

    var body: some View {
        let live = Ev.isLive(occ.startAt, occ.endAt)
        let accent = Ev.categoryColor(occ.category)
        VStack(alignment: .leading, spacing: 0) {
            EvCardCover(occ: occ, accent: accent, live: live)
            EvCardBody(occ: occ, rsvpStatus: rsvpStatus, onRsvp: onRsvp)
        }
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

private struct EvCardCover: View {
    let occ: CalendarOccurrence
    let accent: Color
    let live: Bool

    var body: some View {
        // The cover grows to the artwork's natural aspect (16:9 placeholder
        // while loading) — the image fills it exactly, no crop, no letterbox.
        cover
            .overlay {
                LinearGradient(colors: [.clear, .clear, Color(hex: 0x0B1F33, alpha: 0.62)],
                               startPoint: .top, endPoint: .bottom)
            }
            .overlay(alignment: .topLeading) { dateChip.padding(Nuru.S.md) }
            .overlay(alignment: .topTrailing) { statusPill.padding(Nuru.S.md) }
            .overlay(alignment: .bottomLeading) { countdownChip.padding(.horizontal, Nuru.S.md).padding(.bottom, 10) }
            .overlay(alignment: .bottomTrailing) { categoryTag.padding(.horizontal, Nuru.S.md).padding(.bottom, 10) }
    }

    private var cover: some View {
        FitImage(url: occ.primaryImageUrl.flatMap(URL.init), fallback: fallback)
    }

    // Branded fallback — never a blank gray slab.
    private var fallback: LinearGradient {
        LinearGradient(colors: [Nuru.navy700, Nuru.navy, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var dateChip: some View {
        VStack(spacing: 0) {
            Text(Ev.weekday(occ.startAt, "EEE").uppercased())
                .font(.inter(8, .bold)).kerning(0.8).foregroundStyle(accent)
            Text(Ev.weekday(occ.startAt, "d")).font(.fraunces(17, .semibold)).foregroundStyle(Nuru.navy)
        }
        .frame(width: 48, height: 48)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var statusPill: some View {
        if live {
            HStack(spacing: 4) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("LIVE").font(.inter(8, .bold)).kerning(1).foregroundStyle(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(hex: 0x16A34A), in: Capsule())
        } else if occ.rescheduled == true {
            // Wire truth: a moved occurrence arrives with rescheduled=true and the
            // NEW start/end applied — the pill is the member's only cue it changed.
            Text("RESCHEDULED").font(.inter(8, .bold)).kerning(1).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Nuru.goldGradient, in: Capsule())
        } else if occ.going >= 120 {
            Text("🔥 Filling fast").font(.inter(8, .bold)).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Nuru.goldGradient, in: Capsule())
        }
    }

    @ViewBuilder private var countdownChip: some View {
        if !live, let label = Ev.dayCountdown(occ.startAt) {
            let urgent = label == "Today" || label == "Tomorrow"
            HStack(spacing: 4) {
                Icon(.clock, size: 10, color: urgent ? Nuru.navy : Nuru.goldLight)
                Text(label).font(.inter(8, .bold)).foregroundStyle(urgent ? Nuru.navy : .white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(urgent ? AnyShapeStyle(Nuru.goldGradient) : AnyShapeStyle(Color(hex: 0x0B1F33, alpha: 0.5)),
                        in: Capsule())
        }
    }

    @ViewBuilder private var categoryTag: some View {
        if let c = occ.category, !c.isEmpty {
            Text(c.uppercased()).font(.inter(8, .bold)).kerning(1).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(accent.opacity(0.9), in: Capsule())
        }
    }
}

private struct EvCardBody: View {
    let occ: CalendarOccurrence
    let rsvpStatus: String?
    let onRsvp: (() async -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(occ.title).font(.nRowTitle).foregroundStyle(Nuru.ink).lineLimit(1)
            if let d = occ.description, !d.isEmpty {
                Text(d).font(.nCardMeta).foregroundStyle(Nuru.muted).lineLimit(2).padding(.top, 4)
            }
            HStack(spacing: Nuru.S.base) {
                meta(.clock, Ev.timeRange(occ.startAt, occ.endAt))
                if let loc = occ.location, !loc.isEmpty { meta(.mapPin, loc) }
            }
            .padding(.top, Nuru.S.sm)
            Divider().overlay(Nuru.border).padding(.top, Nuru.S.md)
            EvCardFooter(occ: occ, rsvpStatus: rsvpStatus, onRsvp: onRsvp)
                .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
    }

    private func meta(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 12, color: Nuru.ink600)
            Text(text).font(.nCardMeta).foregroundStyle(Nuru.muted).lineLimit(1)
        }
    }
}

// Footer: real attendee avatars + going count + quick-RSVP pill.
private struct EvCardFooter: View {
    let occ: CalendarOccurrence
    let rsvpStatus: String?
    let onRsvp: (() async -> Void)?
    @State private var busy = false

    var body: some View {
        HStack(spacing: Nuru.S.sm) {
            avatars
            Text(occ.going > 0 ? "\(occ.going) going" : "Be the first to RSVP")
                .font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
            Spacer(minLength: 0)
            if onRsvp != nil { rsvpButton }
        }
    }

    @ViewBuilder private var avatars: some View {
        let list = Array((occ.attendees ?? []).prefix(3))
        if !list.isEmpty {
            HStack(spacing: -8) {
                ForEach(list) { a in
                    Avatar(url: a.avatarUrl, name: a.fullName, size: 24)
                        .overlay(Circle().stroke(Nuru.white, lineWidth: 2))
                }
                if list.count == 3 && occ.going > 3 {
                    Text("+\(occ.going - 3)").font(.inter(8, .bold)).foregroundStyle(Nuru.navy)
                        .frame(width: 24, height: 24)
                        .background(Nuru.surface, in: Circle())
                        .overlay(Circle().stroke(Nuru.white, lineWidth: 2))
                }
            }
        } else {
            Icon(.users, size: 13, color: Nuru.ink600)
        }
    }

    private var rsvpButton: some View {
        Button {
            guard !busy, let onRsvp else { return }
            Haptics.action()
            busy = true
            Task { await onRsvp(); busy = false }
        } label: {
            rsvpLabel
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: rsvpStatus)
        }
        .buttonStyle(.pressable)
        .disabled(busy)
        .opacity(busy ? 0.6 : 1)
    }

    @ViewBuilder private var rsvpLabel: some View {
        switch rsvpStatus {
        case "going":
            HStack(spacing: 4) {
                Icon(.check, size: 11, color: Nuru.navy)
                Text("GOING").font(.inter(9, .bold)).kerning(1).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Nuru.goldGradient, in: Capsule())
        case "maybe":
            Text("MAYBE").font(.inter(9, .bold)).kerning(1).foregroundStyle(Color(hex: 0x92400E))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(hex: 0xFEF3C7), in: Capsule())
        default:
            HStack(spacing: 4) {
                Icon(.plus, size: 11, color: Nuru.navy)
                Text("RSVP").font(.inter(9, .bold)).kerning(1).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Nuru.white, in: Capsule())
            .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
        }
    }
}

// MARK: - sub-page header (cream, mirrors the make's CommunityPage chrome)

private struct EvSubHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
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
                Text(eyebrow.uppercased()).font(.inter(9, .bold)).kerning(1.5)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
            }
            Text(title).font(.fraunces(27, .semibold)).foregroundStyle(Nuru.navy).padding(.top, Nuru.S.base)
            if let subtitle {
                Text(subtitle).font(.inter(12)).foregroundStyle(Color(hex: 0x59667C)).padding(.top, 6)
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
}

// MARK: - "See all" announcements page

private struct AnnouncementsListPage: View {
    @ObservedObject var vm: EventsViewModel

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                EvSubHeader(eyebrow: "Announcements", title: "From your church",
                            subtitle: "\(vm.announcements.count) recent")
                VStack(spacing: 0) {
                    ForEach(Array(vm.announcements.enumerated()), id: \.element.id) { idx, a in
                        NavigationLink(value: AppRoute.announcement(a.announcementId)) {
                            AnnouncementRow(announcement: a)
                        }
                        .buttonStyle(.pressable)
                        if idx < vm.announcements.count - 1 { Divider().overlay(Nuru.border) }
                    }
                }
                .padding(.horizontal, Nuru.S.base)
                .cardSurfaceEv()
                .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.base)
                Text("Tap an announcement to read it in full.")
                    .font(.inter(9)).italic().foregroundStyle(Nuru.faint)
                    .padding(.top, Nuru.S.md).padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}

// MARK: - "See all" series page (Following / Discover tabs)

private struct SeriesListPage: View {
    @ObservedObject var vm: EventsViewModel
    @State private var discover = false

    private var shown: [EventSeries] { vm.series.filter { $0.following != discover } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                EvSubHeader(eyebrow: "Series", title: "Series you follow")
                VStack(spacing: Nuru.S.md) {
                    tabs
                    if shown.isEmpty { emptyCard } else { rows }
                    Text("Following a series surfaces its events and sends you reminders.")
                        .font(.inter(9)).italic().foregroundStyle(Nuru.faint)
                }
                .padding(.horizontal, Nuru.S.screen).padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var tabs: some View {
        HStack(spacing: 4) {
            tab("Following", vm.series.filter(\.following).count, on: !discover) { switchTab(false) }
            tab("Discover", vm.series.filter { !$0.following }.count, on: discover) { switchTab(true) }
        }
        .padding(4)
        .background(Nuru.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    private func switchTab(_ toDiscover: Bool) {
        guard discover != toDiscover else { return }
        Haptics.selection()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { discover = toDiscover }
    }

    private func tab(_ label: String, _ count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.inter(11, .semibold)).foregroundStyle(on ? .white : Nuru.ink600)
                Text("\(count)").font(.inter(9, .bold)).foregroundStyle(Nuru.navy)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(on ? Nuru.gold : Nuru.surface, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(on ? Nuru.navy : .clear, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var rows: some View {
        VStack(spacing: Nuru.S.sm) {
            ForEach(shown) { s in SeriesListRow(vm: vm, series: s) }
        }
    }

    private var emptyCard: some View {
        VStack(spacing: Nuru.S.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.surface).frame(width: 48, height: 48)
                Icon(.sparkles, size: 20, color: Nuru.gold)
            }
            Text(discover ? "You follow every series — amen!" : "You're not following any series yet")
                .font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
            Text(discover ? "New series will appear here." : "Browse Discover to follow one.")
                .font(.nCardMeta).foregroundStyle(Nuru.faint)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.xl)
        .cardSurfaceEv()
    }
}

// One series on the See-all page — icon tile, cadence + next, follow toggle.
// Tapping the row opens the next occurrence when it's in the loaded window.
private struct SeriesListRow: View {
    @ObservedObject var vm: EventsViewModel
    let series: EventSeries

    private var nextOccurrence: CalendarOccurrence? {
        guard let id = series.nextOccurrenceId else { return nil }
        return vm.occurrences.first { $0.occurrenceId == id }
    }

    var body: some View {
        HStack(spacing: Nuru.S.md) {
            if let occ = nextOccurrence {
                NavigationLink(value: occ) { info }.buttonStyle(.pressable)
            } else {
                info
            }
            Spacer(minLength: Nuru.S.sm)
            FollowButton(following: series.following) { await vm.toggleFollow(series) }
        }
        .padding(Nuru.S.md)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private var info: some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Ev.categoryColor(series.category).opacity(0.12))
                Icon(.sparkles, size: 16, color: Ev.categoryColor(series.category))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(series.title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
                    if series.following && series.newCount > 0 {
                        Text("\(series.newCount) new").font(.inter(8, .bold))
                            .foregroundStyle(Color(hex: 0x8A6D18))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Nuru.gold.opacity(0.15), in: Capsule())
                    }
                }
                Text(series.cadenceLine).font(.nCardMeta).foregroundStyle(Nuru.muted).lineLimit(1)
                if let next = series.nextAt {
                    HStack(spacing: 4) {
                        Icon(.calendarDays, size: 10, color: Nuru.faint)
                        Text("Next \(Ev.weekday(next, "EEE, MMM d"))").font(.inter(9)).foregroundStyle(Nuru.faint)
                    }
                }
            }
        }
    }
}

extension View {
    func cardSurfaceEv() -> some View {
        background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
