// Calendar — the full-month view reachable from EventsView. A navy header with a
// soft warm glow, a custom circular back button, and a serif month title; below
// it a white month-grid card (selectable days, occurrence dots, today ring) and
// a per-day event list. Bound to the real MemberAPI.calendar window. Pushed onto
// the Events NavigationStack, so NavigationLink(value: occ) resolves to the
// `.navigationDestination(for: CalendarOccurrence.self)` registered there.
import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var occurrences: [CalendarOccurrence] = []
    @Published var month: Date          // first day of the displayed month
    @Published var selected: Date       // selected day (start of day)
    @Published var loading = true

    let today: Date
    private let cal = Calendar.current

    init() {
        let c = Calendar.current
        let now = c.startOfDay(for: Date())
        today = now
        selected = now
        month = c.date(from: c.dateComponents([.year, .month], from: now))!
    }

    // ISO window: a few days before the displayed month → +60 days, covers the grid.
    private func window() -> (String, String) {
        let f = ISO8601DateFormatter()
        let start = cal.date(byAdding: .day, value: -6, to: month)!
        let end = cal.date(byAdding: .day, value: 60, to: month)!
        return (f.string(from: start), f.string(from: end))
    }

    func load() async {
        loading = true
        let (from, to) = window()
        let occ = (try? await MemberAPI.calendar(from: from, to: to)) ?? []
        occurrences = occ.sorted { Ev.date($0.startAt) < Ev.date($1.startAt) }
        loading = false
    }

    // MARK: month math

    var monthTitle: String { Ev.weekday(iso(month), "MMMM") }       // "June"
    var yearTitle: String { Ev.weekday(iso(month), "yyyy") }        // "2026"
    var headerTitle: String { "\(monthTitle) \(yearTitle)" }        // "June 2026"

    /// The grid cells: leading blanks (nil) then each day of the month.
    var gridDays: [Date?] {
        let comps = cal.dateComponents([.year, .month], from: month)
        let first = cal.date(from: comps)!
        let range = cal.range(of: .day, in: .month, for: first)!
        let leading = cal.component(.weekday, from: first) - 1   // 0 = Sunday
        var cells: [Date?] = Array(repeating: nil, count: leading)
        for d in range {
            cells.append(cal.date(byAdding: .day, value: d - 1, to: first))
        }
        // pad to a full final week so the grid keeps its rectangular shape
        while cells.count % 7 != 0 { cells.append(nil) }
        return cells
    }

    func step(_ delta: Int) {
        if let m = cal.date(byAdding: .month, value: delta, to: month) {
            month = cal.date(from: cal.dateComponents([.year, .month], from: m))!
        }
        Task { await load() }
    }

    func goToday() {
        month = cal.date(from: cal.dateComponents([.year, .month], from: today))!
        selected = today
        Task { await load() }
    }

    func isToday(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: today) }
    func isSelected(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: selected) }
    func inDisplayedMonth(_ d: Date) -> Bool {
        cal.isDate(d, equalTo: month, toGranularity: .month)
    }

    /// Occurrences that fall on a given day.
    func occurrences(on day: Date) -> [CalendarOccurrence] {
        occurrences.filter { cal.isDate(Ev.date($0.startAt), inSameDayAs: day) }
    }

    /// The dominant category color for a day (for the grid dot) — nil if no events.
    func dayCategory(_ day: Date) -> String? { occurrences(on: day).first?.category }

    /// Events for the currently-selected day, time-sorted.
    var selectedEvents: [CalendarOccurrence] {
        occurrences(on: selected).sorted { Ev.date($0.startAt) < Ev.date($1.startAt) }
    }

    /// Distinct categories present in the displayed month (legend row).
    var legendCategories: [String] {
        var seen: [String] = []
        for o in occurrences where inDisplayedMonth(Ev.date(o.startAt)) {
            if let c = o.category, !seen.contains(c) { seen.append(c) }
        }
        return seen
    }

    var upcomingCount: Int {
        occurrences.filter { Ev.date($0.startAt) >= today }.count
    }

    var selectedDayTitle: String { Ev.weekday(iso(selected), "MMMM d") }   // "June 28"

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}

struct CalendarView: View {
    @StateObject private var vm = CalendarViewModel()
    @Environment(\.dismiss) private var dismiss

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                VStack(spacing: Nuru.S.lg) {
                    monthCard
                    daySection
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.lg)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await vm.load() }
        .task { if vm.occurrences.isEmpty { await vm.load() } }
    }

    // MARK: header — navy, rounded bottom, warm glow top-right, back + overline.
    private var header: some View {
        ZStack(alignment: .topTrailing) {
            // soft warm glow, upper-right
            RadialGradient(
                colors: [Nuru.goldGlow.opacity(0.55), Nuru.gold.opacity(0.18), .clear],
                center: .topTrailing, startRadius: 4, endRadius: 220
            )
            .frame(width: 320, height: 260)
            .offset(x: 70, y: -70)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Button { dismiss() } label: {
                        Icon(.arrowLeft, size: 18, color: Nuru.navy)
                            .frame(width: 40, height: 40)
                            .background(Nuru.white, in: Circle())
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text("EVENTS")
                        .font(.inter(11, .semibold)).kerning(2)
                        .foregroundStyle(Nuru.gold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.white.opacity(0.06), in: Capsule())
                        .padding(.top, 2)
                }
                Text(vm.headerTitle)
                    .font(.fraunces(30, .semibold))
                    .foregroundStyle(Nuru.onNavy)
                    .padding(.top, Nuru.S.lg)
                Text("\(vm.upcomingCount) upcoming · \(vm.monthTitle) \(vm.yearTitle)")
                    .font(.inter(12))
                    .foregroundStyle(Nuru.onNavyDim)
                    .padding(.top, 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(Nuru.gold)
                    .frame(width: 44, height: 3)
                    .padding(.top, Nuru.S.md)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, 56)
            .padding(.bottom, Nuru.S.lg)
        }
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    // MARK: month-grid card
    private var monthCard: some View {
        VStack(spacing: Nuru.S.base) {
            // title row + TODAY pill + nav buttons
            HStack(spacing: Nuru.S.sm) {
                HStack(spacing: 6) {
                    Text(vm.monthTitle).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
                    Text(vm.yearTitle).font(.fraunces(18, .regular)).foregroundStyle(Nuru.ink300)
                }
                Spacer(minLength: 0)
                Button { vm.goToday() } label: {
                    Text("TODAY").font(.inter(10, .bold)).kerning(0.8)
                        .foregroundStyle(Nuru.goldChipText)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Nuru.goldChipBg, in: Capsule())
                }
                .buttonStyle(.plain)
                navButton(.chevronLeft) { vm.step(-1) }
                navButton(.chevronRight) { vm.step(1) }
            }

            // weekday header
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, d in
                    Text(d).font(.inter(11, .semibold)).foregroundStyle(Nuru.ink400)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)

            // day grid
            LazyVGrid(columns: cols, spacing: Nuru.S.sm) {
                ForEach(Array(vm.gridDays.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 40) }
                }
            }

            Divider().background(Nuru.border)

            // legend
            HStack(spacing: Nuru.S.base) {
                if vm.legendCategories.isEmpty {
                    legendItem("worship")
                } else {
                    ForEach(vm.legendCategories, id: \.self) { legendItem($0) }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }

    private func navButton(_ glyph: Lucide, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(glyph, size: 14, color: Nuru.ink600)
                .frame(width: 32, height: 32)
                .background(Nuru.surface, in: Circle())
                .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func dayCell(_ day: Date) -> some View {
        let inMonth = vm.inDisplayedMonth(day)
        let selected = vm.isSelected(day)
        let today = vm.isToday(day)
        let cat = vm.dayCategory(day)
        let num = Ev.weekday(ISO8601DateFormatter().string(from: day), "d")

        return Button {
            vm.selected = Calendar.current.startOfDay(for: day)
        } label: {
            ZStack {
                if selected {
                    Circle().fill(Nuru.navy).frame(width: 40, height: 40)
                } else if today {
                    Circle().stroke(Nuru.gold, lineWidth: 1.5).frame(width: 40, height: 40)
                }
                VStack(spacing: 2) {
                    Text(num)
                        .font(.inter(13, selected || today ? .bold : .medium))
                        .foregroundStyle(
                            selected ? Nuru.onNavy
                            : today ? Nuru.gold
                            : inMonth ? Nuru.ink : Nuru.ink300
                        )
                    if let cat, !selected {
                        Circle().fill(Ev.categoryColor(cat)).frame(width: 5, height: 5)
                    } else {
                        Color.clear.frame(width: 5, height: 5)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func legendItem(_ category: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(Ev.categoryColor(category)).frame(width: 7, height: 7)
            Text(category).font(.inter(11, .medium)).foregroundStyle(Nuru.ink600)
        }
    }

    // MARK: selected-day section
    private var daySection: some View {
        VStack(spacing: Nuru.S.md) {
            HStack {
                Text(vm.selectedDayTitle)
                    .font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
                Spacer(minLength: 0)
                let n = vm.selectedEvents.count
                Text("\(n) \(n == 1 ? "event" : "events")")
                    .font(.inter(11, .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Nuru.navy, in: Capsule())
            }

            if vm.loading && vm.occurrences.isEmpty {
                ProgressView().padding(.top, Nuru.S.lg)
            } else if vm.selectedEvents.isEmpty {
                emptyDay
            } else {
                ForEach(vm.selectedEvents) { occ in
                    NavigationLink(value: occ) { dayEventCard(occ) }
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyDay: some View {
        VStack(spacing: 6) {
            Text("Nothing scheduled").font(.nHeading).foregroundStyle(Nuru.ink)
            Text("Pick another day, or check back soon.")
                .font(.nCaption).foregroundStyle(Nuru.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Nuru.S.xl)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // Compact event row: left accent bar + icon tile + title/time/place + going.
    private func dayEventCard(_ occ: CalendarOccurrence) -> some View {
        let accent = Ev.categoryColor(occ.category)
        return HStack(spacing: 0) {
            Rectangle().fill(accent).frame(width: 4)
            HStack(alignment: .top, spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Icon(.calendar, size: 20, color: accent)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(occ.title)
                        .font(.fraunces(16, .semibold)).foregroundStyle(Nuru.ink).lineLimit(1)
                    HStack(spacing: 6) {
                        Icon(.clock, size: 13, color: Nuru.ink600)
                        Text(Ev.timeOf(occ.startAt)).font(.inter(12)).foregroundStyle(Nuru.muted)
                    }
                    if let loc = occ.location, !loc.isEmpty {
                        HStack(spacing: 6) {
                            Icon(.mapPin, size: 13, color: Nuru.ink600)
                            Text(loc).font(.inter(12)).foregroundStyle(Nuru.muted).lineLimit(1)
                        }
                    }
                    attendeeRow(occ)
                        .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(Nuru.S.base)
        }
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
    }

    private func attendeeRow(_ occ: CalendarOccurrence) -> some View {
        let avatars = Array((occ.attendees ?? []).prefix(3))
        return HStack(spacing: Nuru.S.sm) {
            if !avatars.isEmpty {
                HStack(spacing: -8) {
                    ForEach(avatars) { a in
                        Avatar(url: a.avatarUrl, name: a.fullName, size: 24)
                            .overlay(Circle().stroke(Nuru.white, lineWidth: 2))
                    }
                }
            } else {
                Icon(.users, size: 13, color: Nuru.ink600)
            }
            Text(occ.going > 0 ? "\(occ.going) going" : "Be the first")
                .font(.inter(12)).foregroundStyle(Nuru.muted)
        }
    }
}
