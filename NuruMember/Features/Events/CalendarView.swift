// Calendar — the full-month view reachable from EventsView, matching the
// make's EventsCalendarPage: a cream sub-page header (back button, EVENTS
// eyebrow chip, serif title, gold accent bar), a white month-grid card
// (rounded day cells, multi-category dots, today ring, tap-again-to-clear
// selection) and a photo-forward event list that shows the selected day or
// all upcoming. Bound to the real MemberAPI.calendar window. Pushed onto the
// Events NavigationStack, so NavigationLink(value: occ) resolves to the
// `.navigationDestination(for: CalendarOccurrence.self)` registered there.
import SwiftUI

@MainActor
final class CalendarViewModel: ObservableObject {
    @Published var occurrences: [CalendarOccurrence] = []
    @Published var month: Date            // first day of the displayed month
    @Published var selected: Date?        // selected day; nil = show all upcoming
    @Published var loading = true

    let today: Date
    private let cal = Calendar.current

    init() {
        let c = Calendar.current
        let now = c.startOfDay(for: Date())
        today = now
        selected = nil
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

    /// Tap a day to select it; tap it again to clear back to "all upcoming".
    func toggle(_ day: Date) {
        let d = cal.startOfDay(for: day)
        selected = isSelected(d) ? nil : d
    }

    func isToday(_ d: Date) -> Bool { cal.isDate(d, inSameDayAs: today) }
    func isSelected(_ d: Date) -> Bool {
        guard let selected else { return false }
        return cal.isDate(d, inSameDayAs: selected)
    }

    /// Occurrences that fall on a given day.
    func occurrences(on day: Date) -> [CalendarOccurrence] {
        occurrences.filter { cal.isDate(Ev.date($0.startAt), inSameDayAs: day) }
    }

    /// Up to three distinct category dots for a day (the make shows several).
    func dayDots(_ day: Date) -> [Color] {
        var seen: [String] = []
        for o in occurrences(on: day) {
            let key = (o.category ?? "").lowercased()
            if !seen.contains(key) { seen.append(key) }
            if seen.count == 3 { break }
        }
        return seen.map { Ev.categoryColor($0) }
    }

    /// The list below the grid: the selected day, or every upcoming event.
    var listEvents: [CalendarOccurrence] {
        let rows: [CalendarOccurrence]
        if let selected {
            rows = occurrences(on: selected)
        } else {
            rows = occurrences.filter { Ev.date($0.startAt) >= today }
        }
        return rows.sorted { Ev.date($0.startAt) < Ev.date($1.startAt) }
    }

    /// Distinct categories present in the displayed month (legend row).
    var legendCategories: [String] {
        var seen: [String] = []
        for o in occurrences where cal.isDate(Ev.date(o.startAt), equalTo: month, toGranularity: .month) {
            if let c = o.category, !seen.contains(c) { seen.append(c) }
        }
        return seen
    }

    var upcomingCount: Int {
        occurrences.filter { Ev.date($0.startAt) >= today }.count
    }

    var listTitle: String {
        guard let selected else { return "UPCOMING" }
        return Ev.weekday(iso(selected), "MMM d").uppercased()      // "JUN 15"
    }

    private func iso(_ d: Date) -> String { ISO8601DateFormatter().string(from: d) }
}

struct CalendarView: View {
    @StateObject private var vm = CalendarViewModel()
    @Environment(\.dismiss) private var dismiss

    private let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
    // Sunday-first labels to match the grid math (the make's label row starts
    // on Monday against a Sunday-first grid — an upstream bug we don't copy).
    private let weekdays = ["S", "M", "T", "W", "T", "F", "S"]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                VStack(spacing: Nuru.S.base) {
                    monthCard
                    listHeader
                    daySection
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await vm.load() }
        .task { if vm.occurrences.isEmpty { await vm.load() } }
    }

    // MARK: header — cream sub-page chrome (make's CommunityPage).

    private var header: some View {
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
                Text("EVENTS").font(.inter(9, .bold)).kerning(1.5)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
            }
            Text("All events & calendar")
                .font(.fraunces(27, .semibold)).foregroundStyle(Nuru.navy)
                .padding(.top, Nuru.S.base)
            Text("\(vm.upcomingCount) upcoming · \(vm.headerTitle)")
                .font(.inter(12)).foregroundStyle(Color(hex: 0x59667C))
                .padding(.top, 6)
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

    // MARK: month-grid card

    private var monthCard: some View {
        VStack(spacing: Nuru.S.base) {
            // title row + TODAY pill + nav buttons (nav kept for real months —
            // the make is a single-month mock).
            HStack(spacing: Nuru.S.sm) {
                HStack(spacing: 6) {
                    Text(vm.monthTitle).font(.nCardTitle).foregroundStyle(Nuru.navy)
                    Text(vm.yearTitle).font(.fraunces(18, .regular)).foregroundStyle(Color(hex: 0xB8C0CC))
                }
                Spacer(minLength: 0)
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { vm.goToday() }
                } label: {
                    Text("TODAY").font(.inter(9, .bold)).kerning(1)
                        .foregroundStyle(Color(hex: 0xA8861C))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Nuru.gold.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.pressable)
                navButton(.chevronLeft) { stepMonth(-1) }
                navButton(.chevronRight) { stepMonth(1) }
            }

            // weekday header
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { _, d in
                    Text(d).font(.inter(9, .bold)).kerning(0.8).foregroundStyle(Color(hex: 0xB0B8C4))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, 2)

            // day grid
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(vm.gridDays.enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 42) }
                }
            }

            Divider().overlay(Nuru.border)

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
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    /// Month navigation: a light tap plus an eased grid change, so the new
    /// month settles in instead of snapping.
    private func stepMonth(_ delta: Int) {
        Haptics.tap()
        withAnimation(.easeOut(duration: 0.25)) { vm.step(delta) }
    }

    private func navButton(_ glyph: Lucide, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(glyph, size: 14, color: Nuru.ink600)
                .frame(width: 32, height: 32)
                .background(Nuru.surface, in: Circle())
                .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }

    // Rounded-square day cell: navy gradient when selected, gold inset ring on
    // today, and up to three category dots (white while selected).
    private func dayCell(_ day: Date) -> some View {
        let selected = vm.isSelected(day)
        let today = vm.isToday(day)
        let dots = vm.dayDots(day)
        let num = Calendar.current.component(.day, from: day)

        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { vm.toggle(day) }
        } label: {
            VStack(spacing: 3) {
                Text("\(num)")
                    .font(.inter(12, selected || today ? .bold : .semibold))
                    .foregroundStyle(selected ? .white : today ? Color(hex: 0xA8861C) : Nuru.navy)
                HStack(spacing: 2) {
                    if dots.isEmpty {
                        Color.clear.frame(width: 4, height: 4)
                    } else {
                        ForEach(Array(dots.enumerated()), id: \.offset) { _, c in
                            Circle().fill(selected ? Color.white.opacity(0.9) : c).frame(width: 4, height: 4)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background {
                if selected {
                    LinearGradient(colors: [Nuru.navy, Color(hex: 0x060F1C)], startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                if today && !selected {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.gold, lineWidth: 1.5)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
    }

    private func legendItem(_ category: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(Ev.categoryColor(category)).frame(width: 6, height: 6)
            Text(category.capitalized).font(.inter(10, .medium)).foregroundStyle(Nuru.ink600)
        }
    }

    // MARK: selected-day / upcoming list

    private var listHeader: some View {
        HStack {
            Text(vm.listTitle).font(.inter(10, .bold)).kerning(1.5).foregroundStyle(Color(hex: 0xA8861C))
            Spacer(minLength: 0)
            let n = vm.listEvents.count
            Text("\(n) \(n == 1 ? "event" : "events")").font(.inter(10, .semibold)).foregroundStyle(Nuru.faint)
        }
        .padding(.horizontal, 4)
    }

    @ViewBuilder
    private var daySection: some View {
        if vm.loading && vm.occurrences.isEmpty {
            skeletonCard
        } else if vm.listEvents.isEmpty {
            emptyDay
        } else {
            ForEach(vm.listEvents) { occ in
                NavigationLink(value: occ) { EventCardView(occ: occ) }
                    .buttonStyle(.pressableSubtle)
            }
        }
    }

    /// Shimmering placeholder in the shape of an event card.
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

    private var emptyDay: some View {
        VStack(spacing: Nuru.S.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Nuru.gold.opacity(0.08)).frame(width: 48, height: 48)
                Icon(.calendarDays, size: 22, color: Nuru.gold)
            }
            Text(vm.selected == nil ? "Nothing coming up" : "Nothing on this day.")
                .font(.inter(12, .semibold)).foregroundStyle(Nuru.navy)
            if vm.selected != nil {
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { vm.selected = nil }
                } label: {
                    Text("See all upcoming").font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                        .padding(.horizontal, 12).padding(.vertical, 6)   // comfortable tap target
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Text("Check back soon — new gatherings land here.")
                    .font(.nCardMeta).foregroundStyle(Nuru.faint)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Nuru.S.xl)
        .cardSurfaceEv()
    }
}
