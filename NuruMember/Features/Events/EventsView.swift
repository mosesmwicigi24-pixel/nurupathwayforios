// Events ("Gathered together" make) — the native port of CommunityTab.tsx.
// Cream header with pulse chips, an optional image-backed LIVE-NOW hero, a
// scrollable 14-day date strip, the navy CALENDAR card, a Today/Upcoming/
// My-RSVPs segment pill, search + colored category chips, photo-forward
// gathering cards with quick-RSVP, a "Series you follow" rail and an
// "Announcements" feed (both with real See-all pages). Bound to the real
// calendar, series, rsvp and announcement endpoints; sections load
// independently and hide when empty. The header's line says what is next
// (EXPERIENCE.md §6.2), and a quiet week is quiet (§6.5): one calm card, the
// calendar and check-in as two compact rows, no tabs, search or filters.
import SwiftUI

// MARK: helpers (port of eventHelpers.ts)

enum Ev {
    static func date(_ iso: String) -> Date {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? .distantPast
    }
    static func timeOf(_ iso: String) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: date(iso))
    }
    /// "9:00 AM – 11:00 AM" — just the start when the end isn't known (it
    /// used to print the end as a midnight that never was).
    static func timeRange(_ s: String, _ e: String) -> String { e.isEmpty ? timeOf(s) : "\(timeOf(s)) – \(timeOf(e))" }
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
    /// A category is a WORD on a pill, never a hue (§8.1 rules 1, 6): one
    /// accent for every category (Cell was indigo, Leaders sky, Youth green).
    static func categoryColor(_ c: String?) -> Color { Nuru.gold }
    static func weekday(_ iso: String, _ fmt: String) -> String {
        let f = DateFormatter(); f.dateFormat = fmt; return f.string(from: date(iso))
    }
    /// "h:mm a" for an arbitrary date (series cadence subline).
    static func timeOfDate(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
    }
    /// Short date label, e.g. "Jun 21".
    static func shortDate(_ iso: String) -> String {
        NuruDates.day(date(iso))
    }
}

/// The Events tab's one header line and its quiet week (EXPERIENCE.md §6.2,
/// §6.5) — pure, so the tests pin them; Android's EventsHeader, the same
/// rules. "In range" is what the tab loads, from today (the church's day) on;
/// a quiet week is one with nothing in it, and the header says so in the
/// same words.
enum EventsHeader {
    /// The gatherings from today on, soonest first — what the tab has to
    /// show, and to filter.
    static func fromToday(_ events: [CalendarOccurrence], now: Date,
                          timeZone: TimeZone = GiveCalendar.nairobi) -> [CalendarOccurrence] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let today = cal.startOfDay(for: now)
        return events.compactMap { o in parse(o.startAt).map { (o, $0) } }
            .filter { cal.startOfDay(for: $0.1) >= today }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// Nothing from today on: the quiet week — the calm card, and no tabs,
    /// search or filters, since there is nothing to filter.
    static func isQuiet(_ events: [CalendarOccurrence], now: Date, timeZone: TimeZone = GiveCalendar.nairobi) -> Bool {
        fromToday(events, now: now, timeZone: timeZone).isEmpty
    }

    /// "Next: Sunday Service · Sun 5 Oct", else "Nothing planned this week".
    static func line(_ events: [CalendarOccurrence], now: Date, timeZone: TimeZone = GiveCalendar.nairobi) -> String {
        guard let next = fromToday(events, now: now, timeZone: timeZone).first, let start = parse(next.startAt) else {
            return "Nothing planned this week"
        }
        return "Next: \(next.title) · \(NuruDates.day(start, timeZone: timeZone))"
    }

    private static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
}

enum EventSegment: String, CaseIterable { case today = "Today", upcoming = "Upcoming", rsvps = "My RSVPs" }

/// Pushable routes within the Events stack.
enum EventsNav: Hashable { case calendar, seriesAll, seriesMore, announcementsAll, attendance, broadcasts }

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
    /// The member picked a tab (or a date) — loads stop choosing it for them.
    var segmentChosen = false
    @Published var selectedDay: Date
    @Published var search = ""
    @Published var category = "All"
    @Published var loading = true
    /// Why the gatherings didn't load — spoken through the one state language
    /// (NuruStateCopy): it says "offline" only when it was the connection.
    @Published var failure: Error?
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
        loading = true; failure = nil
        async let occ = MemberAPI.calendar(from: from, to: to)
        async let ser = try? MemberAPI.eventSeries()
        async let ann = try? MemberAPI.myAnnouncements()
        async let rs = try? MemberAPI.myRsvps()
        // The gatherings are the calendar's — keep WHY it failed, so the list
        // can say what really happened (the rest stays best-effort).
        do {
            occurrences = try await occ.sorted { Ev.date($0.startAt) < Ev.date($1.startAt) }
        } catch {
            occurrences = []
            failure = error
        }
        series = await ser ?? []
        announcements = await ann ?? []
        quickRsvps = Dictionary((await rs ?? []).map { ($0.eventId, $0.status) },
                                uniquingKeysWith: { a, _ in a })
        // Open on the first tab that has something (§7.4 #6) — not on an
        // empty "Today (0)" with the gatherings waiting under Upcoming.
        if !segmentChosen {
            segment = Self.openingSegment(today: count(.today), upcoming: count(.upcoming), rsvps: count(.rsvps))
        }
        loading = false
    }

    /// The tab Events opens on: the first that has something — Today, then
    /// Upcoming, then My RSVPs; Today when none has. Pure.
    nonisolated static func openingSegment(today: Int, upcoming: Int, rsvps: Int) -> EventSegment {
        if today > 0 { return .today }
        if upcoming > 0 { return .upcoming }
        if rsvps > 0 { return .rsvps }
        return .today
    }

    /// The member picked a tab.
    func choose(_ s: EventSegment) { segmentChosen = true; segment = s }

    /// The member picked a date on the strip: that date's gatherings, on the
    /// Today tab — the strip filters that tab, so it is brought forward
    /// (a date tap while Upcoming showed would otherwise change nothing).
    func selectDay(_ d: Date) { selectedDay = d; choose(.today) }

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
        let weekEnd = cal.date(byAdding: .day, value: EventsWeek.days, to: todayStart)!
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

    /// The week strip: today through the seventh day after — the same eight
    /// days "N this week" counts (the walk's E21: the strip began two days
    /// back and ran fourteen, so its week and the header's never agreed).
    var week: [WeekDay] {
        let letters = DateFormatter()
        letters.dateFormat = "EEEEE"
        let eventDays = Set(occurrences.map { cal.startOfDay(for: Ev.date($0.startAt)) })
        return (0..<EventsWeek.days).map { i in
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

    /// Something from today on to show and filter (EventsHeader) — the
    /// tabs, search, filters and the header's counts show only then.
    var hasSomethingToFilter: Bool { !EventsHeader.fromToday(occurrences, now: Date()).isEmpty }
    /// The calendar answered and has nothing from today on: the quiet week
    /// (§6.5) — one calm card, and the calendar and check-in as two rows.
    var quiet: Bool { !loading && failure == nil && !hasSomethingToFilter }
    /// The header's one line (§6.2): "Next: «title» · EEE d MMM" or "Nothing
    /// planned this week" once the calendar has answered — today's date
    /// until then (and when it could not answer: never a quiet week it can't see).
    var headerLine: String {
        if occurrences.isEmpty && (loading || failure != nil) { return headerSubline }
        return EventsHeader.line(occurrences, now: Date())
    }
    var headerSubline: String {
        // The one date shape; no zone name — it is the phone's own day.
        return "Today · \(NuruDates.day(todayStart))"
    }

    func isSelected(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: selectedDay) }
    func selectToday() { selectDay(todayStart) }

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
            return "Events on \(NuruDates.day(selectedDay))"
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
    @EnvironmentObject private var auth: AuthStore
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    VStack(spacing: Nuru.S.base) {
                        // Broadcasters only (PARTNERS_PROGRAMME §0): the old
                        // Live tab's Go Live / return-to-broadcast / My
                        // Broadcasts card, gated exactly as that tab was.
                        if LiveBroadcastEligibility.canGoLive(auth.profile) {
                            BroadcastStudioCard { path.append(EventsNav.broadcasts) }
                        }
                        if let live = vm.liveOccurrence {
                            NavigationLink(value: live) { LiveHeroCard(occ: live) }.buttonStyle(.pressableSubtle)
                        }
                        weekStrip
                        if vm.quiet {
                            // A quiet week is quiet (§6.5): one calm card, then
                            // the calendar and check-in as two compact rows.
                            quietCard
                            quietEntries
                        } else {
                            calendarLink
                            attendanceLink
                            // Tabs, search and filters only when there is
                            // something to filter.
                            if vm.hasSomethingToFilter {
                                segmentBar
                                searchBar
                                categoryChips
                            }
                            gatherings
                        }
                        if !vm.series.isEmpty { seriesSection }
                        if !vm.announcements.isEmpty { announcementsSection }
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .scrollsToTopOnReselect(.events)   // a re-tap at the root returns to the top (B10)
            }
            .ignoresSafeArea(edges: .top)
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .nuruEdgeSwipeBack()   // back by the edge swipe on every pushed page (B9)
            .navigationDestination(for: EventsNav.self) { nav in
                switch nav {
                case .calendar: CalendarView()
                case .seriesAll: SeriesListPage(vm: vm)
                case .seriesMore: SeriesListPage(vm: vm, discover: true)
                case .announcementsAll: AnnouncementsListPage(vm: vm)
                case .attendance: AttendanceView()
                case .broadcasts: NuruLiveTabView(pushed: true)
                }
            }
            .nuruDestinations()
        }
        .task { if vm.occurrences.isEmpty && vm.series.isEmpty && vm.announcements.isEmpty { await vm.load() } }
        .popsToRoot(on: .events, path: $path)   // a re-tap returns to the list (§7.4 #17)
        // Cross-tab deep link (Home's live-now card): open the event detail
        // inside THIS tab, with the Events list as the back stop.
        .onReceive(tabs.$eventLink) { link in
            guard let link else { return }
            path = NavigationPath()
            path.append(link)
            DispatchQueue.main.async { tabs.eventLink = nil }
        }
    }

    // MARK: 1 — cream header (one header on every tab, §6.2: the eyebrow,
    // the serif title, one line of what matters now, the bell at the right)

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack(alignment: .top) {
                // The one header's words (§8.1 rules 2–3).
                NuruHeaderText(kicker: "Events", title: "Gathered together", line: vm.headerLine)
                Spacer()
                // The one bell (§7.2 #4): the dot only while the inbox has
                // something unread (it was painted on).
                NuruBell()
            }
            // The counts only when there is something to count — a quiet
            // week's header line already says it.
            if vm.hasSomethingToFilter {
                // No zero chips (§7.4 #9): "0 you're going" said nothing.
                HStack(spacing: Nuru.S.sm) {
                    if vm.liveOccurrence != nil { livePulseChip }
                    if vm.thisWeekCount > 0 { pulseChip("\(vm.thisWeekCount) this week", icon: .calendarDays) }
                    if vm.goingCount > 0 { pulseChip("\(vm.goingCount) you're going", icon: .check) }
                }
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
            Text("\(vm.liveCount) live now").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x15803D))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(hex: 0xDCFCE7), in: Capsule())
    }

    private func pulseChip(_ text: String, icon: Lucide) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 14, color: Nuru.gold)
            Text(text).font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x59667C))
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
                    Text("TODAY").font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.navy)
                        .padding(.vertical, 6).padding(.leading, 12)   // invisible tap-target growth
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            // The eight days fill the card — no scrolling to find this week.
            HStack(spacing: 4) {
                ForEach(vm.week) { d in dayPill(d) }
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
            guard !(on && vm.segment == .today) else { return }
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.selectDay(d.date) }
        } label: {
            VStack(spacing: 3) {
                Text(d.letter).font(.inter(11, .semibold)).kerning(0.8)
                    .foregroundStyle(on ? Color.white.opacity(0.65) : Color(hex: 0x74808F))
                Text("\(d.day)").font(.fraunces(16, .semibold)).foregroundStyle(on ? .white : Nuru.navy)
                Circle().fill(d.hasEvents ? Nuru.gold : .clear).frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 8)
            .background(bg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    // MARK: 2b — a quiet week (§6.5): one calm card, then the calendar and
    // check-in as two compact rows (Android's QuietWeekCard / QuietEntries)

    private var quietCard: some View {
        HStack(spacing: Nuru.S.md) {
            Icon(.calendarDays, size: 18, color: Nuru.gold)
                .frame(width: 40, height: 40)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("The calendar is quiet this week — gatherings the church posts appear here.")
                .font(.inter(12)).foregroundStyle(Color(hex: 0x59667C))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurfaceEv()
    }

    private var quietEntries: some View {
        VStack(spacing: 0) {
            NavigationLink(value: EventsNav.calendar) { quietRow(.calendarDays, "All events & calendar") }
                .buttonStyle(.pressableSubtle)
            Rectangle().fill(Nuru.border).frame(height: 1).padding(.horizontal, Nuru.S.base)
            NavigationLink(value: EventsNav.attendance) { quietRow(.qrCode, "Check in to a service") }
                .buttonStyle(.pressableSubtle)
        }
        .cardSurfaceEv()
    }

    private func quietRow(_ icon: Lucide, _ title: String) -> some View {
        HStack(spacing: Nuru.S.md) {
            Icon(icon, size: 18, color: Nuru.navy)
                .frame(width: 32, height: 32)
                .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 18, color: Color(hex: 0x74808F))
        }
        .padding(.horizontal, Nuru.S.base).padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    // MARK: 3 — calendar card (a white card: the tab's one navy feature card
    // is the church attendance card below — §8.1 rule 1; the walk's E17 found
    // two navy feature cards on Events)

    private var calendarLink: some View {
        NavigationLink(value: EventsNav.calendar) {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(hex: Nuru.tileTint)).frame(width: 48, height: 48)
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
                    Icon(.calendarDays, size: 22, color: Nuru.navy)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CALENDAR").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.eyebrow)
                    Text("All events & calendar").font(.nRowTitle).foregroundStyle(Nuru.navy)
                    Text("See the whole month at a glance · \(vm.upcomingCount) upcoming")
                        .font(.nCardMeta).foregroundStyle(Nuru.ink600)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 18, color: Nuru.ink300)
            }
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
        }
        .buttonStyle(.pressableSubtle)
    }

    // MARK: 3b — church attendance card

    /// Scan into today's service, and the streak that comes out of showing up.
    /// The tab's one navy feature card (§8.1 rule 1): on a Sunday morning
    /// this is the reason to open the app.
    private var attendanceLink: some View {
        NavigationLink(value: EventsNav.attendance) {
            HStack(spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.goldGradient).frame(width: 48, height: 48)
                    Icon(.qrCode, size: 22, color: Nuru.navy)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CHURCH ATTENDANCE").font(.inter(11, .bold)).kerning(1.5).foregroundStyle(Nuru.goldLight)
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
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.choose(s) }
        } label: {
            HStack(spacing: 6) {
                Text(s.rawValue).font(.inter(11, .semibold)).foregroundStyle(on ? .white : Nuru.ink600)
                // No zero counts (§7.4 #9): the quiet pill IS "nothing here".
                if vm.count(s) > 0 {
                    Text("\(vm.count(s))").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(on ? Nuru.gold : Nuru.surface, in: Capsule())
                }
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
            Icon(.search, size: 14, color: Color(hex: 0x74808F))
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
                    Icon(.x, size: 14, color: Color(hex: 0x74808F))
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
                    Button {
                        guard !on else { return }
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.category = c }
                    } label: {
                        Text(c).font(.inter(12, on ? .semibold : .medium))
                            .foregroundStyle(on ? .white : Nuru.ink600)
                            .padding(.horizontal, Nuru.S.base).padding(.vertical, 9)
                            .background(on ? Nuru.navy : Nuru.white, in: Capsule())
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
                        Icon(.chevronRight, size: 14, color: Nuru.navy)
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
        } else if let f = vm.failure, vm.occurrences.isEmpty {
            // What really happened, in the one state language (§4) — not
            // "check your connection" when the session ended or we failed.
            NuruStateView(state: .failed(.failure(f)), retry: { Task { await vm.load() } })
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
                Icon(.calendarDays, size: 22, color: Nuru.gold)
            }
            Text(vm.emptyTitle).font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
            Text(vm.emptyCaption).font(.nCardMeta).foregroundStyle(Nuru.faint).multilineTextAlignment(.center)
            NavigationLink(value: EventsNav.calendar) {
                HStack(spacing: 6) {
                    Icon(.calendarDays, size: 14, color: .white)
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

    // MARK: 8 — series you follow, then more series (header inside the card)

    /// "Series you follow" holds only the series the member follows; the
    /// rest sit under "More series", each with + Follow (§7.4 #7). A follow
    /// moves its row across.
    @ViewBuilder private var seriesSection: some View {
        let split = EventSeries.split(vm.series)
        if !split.following.isEmpty { seriesCard("SERIES YOU FOLLOW", split.following, nav: .seriesAll) }
        if !split.more.isEmpty { seriesCard("MORE SERIES", split.more, nav: .seriesMore) }
    }

    private func seriesCard(_ title: String, _ rows: [EventSeries], nav: EventsNav) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            railHeader(icon: .sparkles, title: title, nav: nav)
            ForEach(Array(rows.enumerated()), id: \.element.id) { idx, s in
                SeriesRailRow(series: s) { await vm.toggleFollow(s) }
                if idx < rows.count - 1 { Divider().overlay(Nuru.border) }
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
                Icon(icon, size: 14, color: Color(hex: 0xA8861C))
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
                        .font(.inter(11, .bold)).kerning(1.5).foregroundStyle(Nuru.goldLight)
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
            Text(occ.title).font(.fraunces(22, .semibold)).foregroundStyle(.white).lineLimit(2)
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
            if occ.going > 0 {   // no zero counts (§7.4 #9)
                Text("\(occ.going) worshipping").font(.inter(11, .semibold)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Icon(.qrCode, size: 14, color: Nuru.navy)
                Text("CHECK IN").font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Nuru.gold, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var livePill: some View {
        HStack(spacing: 5) {
            Circle().fill(.white).frame(width: 5, height: 5)
            Text("LIVE NOW").font(.inter(11, .bold)).kerning(1).foregroundStyle(.white)
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
            Icon(icon, size: 14, color: Nuru.goldLight)
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
            // A series is a repeating gathering (the server lists only those,
            // §9.2 #11): its tile says so — it was drawn empty (the Cycle 4
            // walk's 42; §8.1 rule 7, an icon on a gold-tint tile).
            Icon(.repeat, size: 18, color: Nuru.navy)
                .frame(width: 36, height: 36)
                .background(Color(hex: Nuru.tileTint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    // Titles wrap to two lines (rule 9; the walk's 43: two
                    // "Graduation & Commission…" rows that couldn't be told apart).
                    // A series is a thing: the content row title (§8.1 rule 3).
                    Text(series.title).font(.nRowTitle).foregroundStyle(Nuru.navy)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if series.following && series.newCount > 0 {
                        Text("\(series.newCount) new").font(.inter(11, .bold))
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
                Icon(following ? .check : .plus, size: 14, color: following ? .white : Nuru.navy)
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
extension EventSeries {
    var cadenceLine: String { Self.cadenceLine(cadence, nextAt: nextAt) }

    /// The series line says its time ONCE (§7.4 #8). The server's label
    /// already names it ("Every Sunday · 9:00 AM", "One-off · 3:00 PM",
    /// "Monthly · 3:00 PM") — appending the next gathering's time read
    /// "Every Sunday · 9:00 AM · 9:00 AM". Only a label without a time (an
    /// older server) borrows the next gathering's. Pure.
    static func cadenceLine(_ cadence: String, nextAt: String?) -> String {
        let c = cadence.trimmingCharacters(in: .whitespaces)
        if c.contains("·") { return c }
        let time = nextAt.map { Ev.timeOfDate(Ev.date($0)) }
        let head: String
        let low = c.lowercased()
        if low.contains("week"), let next = nextAt {
            head = "Every \(Ev.weekday(next, "EEEE"))"
        } else if low.contains("one") || low.contains("once") {
            head = "One-off"
        } else {
            head = c
        }
        guard let time else { return head }
        return head.isEmpty ? time : "\(head) · \(time)"
    }

    /// The series the member follows, and the rest — each in the server's
    /// order (§7.4 #7). Pure.
    static func split(_ series: [EventSeries]) -> (following: [EventSeries], more: [EventSeries]) {
        (series.filter(\.following), series.filter { !$0.following })
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
                    Icon(.badgeCheck, size: 14, color: Nuru.gold)
                }
                Text(announcement.body).font(.nCardMeta).foregroundStyle(Nuru.muted).lineLimit(1)
            }
            Spacer(minLength: Nuru.S.sm)
            VStack(alignment: .trailing, spacing: 5) {
                if let sent = announcement.sentAt {
                    Text(timeAgo(sent)).font(.inter(11)).foregroundStyle(Nuru.faint)
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
                    else { Icon(.megaphone, size: 14, color: Nuru.gold) }
                }
            } else {
                Icon(.megaphone, size: 14, color: Nuru.gold)
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
                .font(.inter(11, .bold)).kerning(0.8).foregroundStyle(accent)
            Text(Ev.weekday(occ.startAt, "d")).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.navy)
        }
        .frame(width: 48, height: 48)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder private var statusPill: some View {
        if live {
            HStack(spacing: 4) {
                Circle().fill(.white).frame(width: 5, height: 5)
                Text("LIVE").font(.inter(11, .bold)).kerning(1).foregroundStyle(.white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Color(hex: 0x16A34A), in: Capsule())
        } else if occ.rescheduled == true {
            // Wire truth: a moved occurrence arrives with rescheduled=true and the
            // NEW start/end applied — the pill is the member's only cue it changed.
            Text("RESCHEDULED").font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Nuru.goldGradient, in: Capsule())
        } else if occ.going >= 120 {
            Text("🔥 Filling fast").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Nuru.goldGradient, in: Capsule())
        }
    }

    @ViewBuilder private var countdownChip: some View {
        if !live, let label = Ev.dayCountdown(occ.startAt) {
            let urgent = label == "Today" || label == "Tomorrow"
            HStack(spacing: 4) {
                Icon(.clock, size: 14, color: urgent ? Nuru.navy : Nuru.goldLight)
                Text(label).font(.inter(11, .bold)).foregroundStyle(urgent ? Nuru.navy : .white)
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(urgent ? AnyShapeStyle(Nuru.goldGradient) : AnyShapeStyle(Color(hex: 0x0B1F33, alpha: 0.5)),
                        in: Capsule())
        }
    }

    @ViewBuilder private var categoryTag: some View {
        if let c = occ.category, !c.isEmpty {
            Text(c.uppercased()).font(.inter(11, .bold)).kerning(1).foregroundStyle(.white)
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
            Icon(icon, size: 14, color: Nuru.ink600)
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
                    Text("+\(occ.going - 3)").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                        .frame(width: 24, height: 24)
                        .background(Nuru.surface, in: Circle())
                        .overlay(Circle().stroke(Nuru.white, lineWidth: 2))
                }
            }
        } else {
            Icon(.users, size: 14, color: Nuru.ink600)
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
                Icon(.check, size: 14, color: Nuru.navy)
                Text("GOING").font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.navy)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Nuru.goldGradient, in: Capsule())
        case "maybe":
            Text("MAYBE").font(.inter(11, .bold)).kerning(1).foregroundStyle(Color(hex: 0x92400E))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Color(hex: 0xFEF3C7), in: Capsule())
        default:
            HStack(spacing: 4) {
                Icon(.plus, size: 14, color: Nuru.navy)
                Text("RSVP").font(.inter(11, .bold)).kerning(1).foregroundStyle(Nuru.navy)
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
                Text(eyebrow.uppercased()).font(.inter(11, .bold)).kerning(1.5)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
            }
            Text(title).font(.fraunces(26, .semibold)).foregroundStyle(Nuru.navy).padding(.top, Nuru.S.base)
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
                    .font(.inter(11)).italic().foregroundStyle(Nuru.faint)
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
    /// "More series → See all" opens on Discover (§7.4 #7).
    @State private var discover: Bool

    init(vm: EventsViewModel, discover: Bool = false) {
        self.vm = vm
        _discover = State(initialValue: discover)
    }

    private var shown: [EventSeries] { vm.series.filter { $0.following != discover } }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                EvSubHeader(eyebrow: "Series", title: "Series you follow")
                VStack(spacing: Nuru.S.md) {
                    tabs
                    if shown.isEmpty { emptyCard } else { rows }
                    Text("Following a series surfaces its events and sends you reminders.")
                        .font(.inter(11)).italic().foregroundStyle(Nuru.faint)
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
                if count > 0 {   // no zero counts (§7.4 #9)
                    Text("\(count)").font(.inter(11, .bold)).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(on ? Nuru.gold : Nuru.surface, in: Capsule())
                }
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
                Icon(.sparkles, size: 22, color: Nuru.gold)
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
                    .fill(Color(hex: Nuru.tileTint))
                Icon(.sparkles, size: 18, color: Color(hex: Nuru.tileIcon))
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(series.title).font(.inter(13, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
                    if series.following && series.newCount > 0 {
                        Text("\(series.newCount) new").font(.inter(11, .bold))
                            .foregroundStyle(Color(hex: 0x8A6D18))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Nuru.gold.opacity(0.15), in: Capsule())
                    }
                }
                Text(series.cadenceLine).font(.nCardMeta).foregroundStyle(Nuru.muted).lineLimit(1)
                if let next = series.nextAt {
                    HStack(spacing: 4) {
                        Icon(.calendarDays, size: 14, color: Nuru.faint)
                        Text("Next \(NuruDates.day(Ev.date(next)))").font(.inter(11)).foregroundStyle(Nuru.faint)
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

/// The one "week" on Events (the walk's E21; §6's "this week"): today
/// through the seventh day after — eight days, as Home's week counts on
/// both apps. The strip and the header's "N this week" use the same days.
enum EventsWeek {
    static let days = 8
}
