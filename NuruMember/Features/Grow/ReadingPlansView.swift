// Plans tab — rebuilt line-by-line from the UPDATED Figma Make source of truth
// (components/PlansTab.tsx). The fresh design moved to a light-cream header
// (white search field + bell), added a streak/reward strip (flame, week dots,
// badge progress), a shimmering "Plan of the day" badge, a pulsing play ring on
// continue rows, a "Finish & earn" trophy card and highlighted next-day rows in
// the detail slide-over, and a navy day header + confetti on day completion.
// Everything binds to REAL data: the ReadingPlanRow catalogue (MemberAPI.plans),
// plan detail (MemberAPI.plan), enrollment (startPlan), day/segment completion
// (completePlanDay / PlanDayRef navigation), streak (me/achievements) and the
// Word rhythm (me/rhythm/today). Mock-only Figma fields (audio flags, intro
// video/audio players, friends-on-plan avatars) are omitted — no fake data.
// Shared card structs + the PL palette live in ReadingPlanCards.swift.
import SwiftUI
import UserNotifications

// MARK: - Daily plan reminder (local notification)

/// Schedules ONE repeating daily local notification that nudges the member back
/// into their reading plan, deep-specific to the plan + day. Grace-first tone: a
/// warm invitation, never a guilt trip. Re-scheduling replaces the pending one.
enum PlanReminders {
    static let id = "nuru.plan.daily"

    static func schedule(enabled: Bool, hour: Int, minute: Int, planTitle: String?, day: Int?) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard enabled else { return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Time in the Word 🌱"
            if let planTitle, let day {
                content.body = "Day \(day) of \(planTitle) is waiting — a few faithful minutes?"
            } else {
                content.body = "Your reading plan is waiting — a few faithful minutes with God?"
            }
            content.sound = .default
            var comps = DateComponents(); comps.hour = hour; comps.minute = minute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}

// MARK: - Plans list (discovery)

@MainActor
final class ReadingPlansViewModel: ObservableObject {
    @Published var plans: [ReadingPlanRow] = []
    @Published var streak = 0
    @Published var todayWordDone = false
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        async let ach = try? MemberAPI.achievements()
        async let rhythm = try? MemberAPI.rhythmToday()
        do { plans = try await MemberAPI.plans() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load reading plans." }
        streak = (await ach)?.streak.current ?? 0
        todayWordDone = (await rhythm)?.word ?? false
        loading = false
    }
}

struct ReadingPlansView: View {
    @StateObject private var vm = ReadingPlansViewModel()
    @EnvironmentObject private var tabs: TabRouter
    @State private var query = ""
    @State private var category = "all"
    @AppStorage("planReminderOn") private var reminderOn = false
    @AppStorage("planReminderHour") private var reminderHour = 7
    @AppStorage("planReminderMinute") private var reminderMinute = 0
    @AppStorage("streakQuiet") private var streakQuiet = false

    private var q: String { query.trimmingCharacters(in: .whitespaces).lowercased() }
    private var searching: Bool { !q.isEmpty || category != "all" }

    private var filtered: [ReadingPlanRow] {
        vm.plans.filter { p in
            (category == "all" || p.category == category)
                && (q.isEmpty || p.title.lowercased().contains(q) || (p.category ?? "").lowercased().contains(q))
        }
    }
    private var continueReading: [ReadingPlanRow] { vm.plans.filter { $0.enrolled && $0.completedAt == nil } }
    private var planOfDay: ReadingPlanRow? { vm.plans.first { !$0.enrolled } ?? vm.plans.first }
    private var categories: [String] {
        var seen = Set<String>(); var out: [String] = []
        for p in vm.plans { if let c = p.category, !c.isEmpty, !seen.contains(c) { seen.insert(c); out.append(c) } }
        return out
    }
    private var collections: [(id: String, label: String, plans: [ReadingPlanRow])] {
        var out: [(String, String, [ReadingPlanRow])] = []
        if !vm.plans.isEmpty { out.append(("featured", "Featured for you", Array(vm.plans.prefix(8)))) }
        let short = vm.plans.filter { $0.dayCount <= 7 }
        if !short.isEmpty { out.append(("short", "Short reads · 7 days or less", short)) }
        // Mid-length (8–13 days) — most study plans are 10-day, so without this
        // bucket they'd fall between "short" and "long" and never appear in browse.
        let mid = vm.plans.filter { (8...13).contains($0.dayCount) }
        if !mid.isEmpty { out.append(("mid", "Mid-length journeys · about 10 days", mid)) }
        let long = vm.plans.filter { $0.dayCount >= 14 }
        if !long.isEmpty { out.append(("long", "Longer journeys · 2 weeks and up", long)) }
        return out
    }

    var body: some View {
        Group {
            #if DEBUG
            if ProcessInfo.processInfo.environment["NURU_PLAN"] != nil, let pod = planOfDay {
                NavigationStack { PlanDetailView(plan: pod) }
            } else { listBody }
            #else
            listBody
            #endif
        }
        .task { if vm.plans.isEmpty { await vm.load() }; reschedule() }
        // Root of the Plans tab — the bottom bar belongs here (hidden inside a plan).
        .onAppear { tabs.chromeHidden = false }
    }

    private var listBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                LoadStateView(loading: vm.loading && vm.plans.isEmpty,
                              isEmpty: vm.plans.isEmpty, error: vm.error,
                              emptyText: "No reading plans yet.", retry: { Task { await vm.load() } }) {
                    VStack(alignment: .leading, spacing: 24) {
                        if !searching, !streakQuiet { PLStreakStrip(count: vm.streak, todayDone: vm.todayWordDone) }
                        if !searching, !continueReading.isEmpty { continueSection }
                        if !searching, !continueReading.isEmpty { reminderCard }
                        if !searching, let pod = planOfDay { planOfDayCard(pod) }
                        categoriesSection
                        if searching { filteredResults } else { collectionsSections }
                        if !searching { invitationCard }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, Nuru.tabBarSpace + 20)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(
            LinearGradient(colors: [PL.cream, PL.creamLo], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await vm.load() }
    }

    // MARK: header — light cream (fresh design) with white search + bell

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("PLANS").font(.inter(9, .bold)).kerning(1.8).foregroundStyle(PL.catText)
                    Text("Grow in the Word").font(.fraunces(26, .semibold)).kerning(-0.52).foregroundStyle(PL.navy)
                        .padding(.top, 4)
                    Text("A little every day — with the whole family of God.")
                        .font(.inter(12)).foregroundStyle(PL.ink2).padding(.top, 4)
                }
                Spacer(minLength: 8)
                bellButton
            }
            searchBar.padding(.top, 16)
        }
        .padding(.horizontal, 20)
        .padding(.top, 64)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            RadialGradient(colors: [PL.gold.opacity(0.27), .clear], center: .center, startRadius: 0, endRadius: 112)
                .frame(width: 224, height: 224).blur(radius: 40).opacity(0.4).offset(x: 64, y: -80)
        }
        .background(LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(.rect(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
        .overlay(alignment: .bottom) { Rectangle().fill(PL.border).frame(height: 1) }
        .shadow(color: Color(hex: 0x0A1628).opacity(0.16), radius: 12, y: 7)
    }

    private var bellButton: some View {
        NavigationLink(value: AppRoute.notifications) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
                RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1)
                Icon(.bell, size: 18, color: PL.navy)
            }
            .overlay(alignment: .topTrailing) {
                Circle().fill(PL.gold).frame(width: 8, height: 8).padding(8)
            }
            .frame(width: 40, height: 40)
        }
        .buttonStyle(.plain)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Icon(.search, size: 16, color: PL.ink3)
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search plans, topics, books…").font(.inter(14)).foregroundStyle(PL.ink3)
                }
                TextField("", text: $query)
                    .font(.inter(14)).foregroundStyle(PL.navy).tint(PL.gold)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !query.isEmpty {
                Button { Haptics.tap(); query = "" } label: {
                    Icon(.x, size: 15, color: PL.ink3)
                        // Grow the hit area without growing the field.
                        .contentShape(Rectangle().inset(by: -14))
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    // MARK: continue reading

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            overline("Continue reading")
            if let first = continueReading.first {
                NavigationLink(value: first) { planResumeBanner(first) }.buttonStyle(.pressable)
            }
            ForEach(Array(continueReading.dropFirst())) { plan in
                NavigationLink(value: plan) { PLContinueRow(plan: plan) }.buttonStyle(.pressable)
            }
        }
    }

    /// Prominent navy "Continue · Day N" banner (mirrors the Home resume nudge).
    private func planResumeBanner(_ p: ReadingPlanRow) -> some View {
        let day = p.currentDay ?? 1
        let done = p.completedDays?.count ?? max(0, day - 1)
        let pct = p.dayCount > 0 ? CGFloat(done) / CGFloat(p.dayCount) : 0
        return HStack(spacing: 14) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.22), lineWidth: 4)
                Circle().trim(from: 0, to: pct)
                    .stroke(PL.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Icon(.bookMarked, size: 17, color: .white)
            }
            .frame(width: 48, height: 48)
            VStack(alignment: .leading, spacing: 3) {
                Text("CONTINUE").font(.inter(10, .bold)).kerning(1.6).foregroundStyle(PL.gold)
                Text(p.title).font(.fraunces(18, .semibold)).foregroundStyle(.white).lineLimit(1)
                Text("Day \(day) of \(p.dayCount) · pick up where you left off")
                    .font(.inter(12)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
            }
            Spacer(minLength: 8)
            Icon(.arrowRight, size: 18, color: PL.gold)
        }
        .padding(16).frame(maxWidth: .infinity)
        .background(LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    // MARK: daily reminder card (grace-first nudge)

    private var reminderTime: Binding<Date> {
        Binding(
            get: { Calendar.current.date(from: DateComponents(hour: reminderHour, minute: reminderMinute)) ?? Date() },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                reminderHour = c.hour ?? 7; reminderMinute = c.minute ?? 0
                reschedule()
            }
        )
    }

    private func reschedule() {
        let p = continueReading.first ?? planOfDay
        PlanReminders.schedule(enabled: reminderOn, hour: reminderHour, minute: reminderMinute,
                               planTitle: p?.title, day: p?.currentDay)
    }

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Icon(.bell, size: 16, color: PL.goldDeep)
                    .frame(width: 38, height: 38)
                    .background(PL.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Daily reminder").font(.inter(14, .semibold)).foregroundStyle(PL.navy)
                    Text("A gentle nudge to keep your rhythm").font(.inter(11.5)).foregroundStyle(PL.ink3)
                }
                Spacer(minLength: 8)
                Toggle("", isOn: $reminderOn).labelsHidden().tint(PL.gold)
            }
            if reminderOn {
                Rectangle().fill(PL.border).frame(height: 1)
                DatePicker("Remind me at", selection: reminderTime, displayedComponents: .hourAndMinute)
                    .font(.inter(13)).tint(PL.gold).foregroundStyle(PL.navy)
            }
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PL.border, lineWidth: 1))
        .onChange(of: reminderOn) { _, _ in reschedule() }
    }

    // MARK: plan of the day (shimmering badge + sparkles)

    private func planOfDayCard(_ plan: ReadingPlanRow) -> some View {
        NavigationLink(value: plan) {
            ZStack {
                PLCover(plan: plan)
                LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.25), Color(hex: 0x081424, alpha: 0.35), Color(hex: 0x081424, alpha: 0.90)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 192).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topLeading) { planOfDayBadge.padding(14) }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.fraunces(22, .semibold)).kerning(-0.22).foregroundStyle(.white)
                        .lineLimit(2).truncationMode(.tail).multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Icon(.clock, size: 12, color: .white.opacity(0.8))
                        Text("\(plan.dayCount) days").font(.nCardMeta).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
            .shadow(color: PL.navyDeep.opacity(0.5), radius: 22, y: 12)
        }
        .buttonStyle(.pressableSubtle) // hero-sized card, gentler scale
    }

    private var planOfDayBadge: some View {
        HStack(spacing: 4) {
            Icon(.sparkles, size: 9, color: PL.navy)
            Text("PLAN OF THE DAY").font(.inter(9, .bold)).kerning(1.26).foregroundStyle(PL.navy)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(PL.gold, in: Capsule())
        .overlay(PLShimmer().clipShape(Capsule()))
    }

    // MARK: categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            overline("Browse by topic")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["all"] + categories, id: \.self) { c in
                        let on = category == c
                        Button {
                            Haptics.selection()
                            category = (category == c ? "all" : c)
                        } label: {
                            Text(c == "all" ? "All plans" : c)
                                .font(.inter(12, on ? .bold : .semibold))
                                .foregroundStyle(on ? .white : PL.ink2)
                                .padding(.horizontal, 14).padding(.vertical, 8)
                                .background(on ? AnyShapeStyle(PL.navy) : AnyShapeStyle(Color.white), in: Capsule())
                                .overlay(Capsule().stroke(on ? .clear : PL.border, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.horizontal, -20)
        }
    }

    // MARK: collections (browse) / filtered results (search)

    private var collectionsSections: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(collections, id: \.id) { col in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(col.label).font(.fraunces(13, .semibold)).kerning(-0.13).foregroundStyle(PL.navy)
                        Spacer(minLength: 0)
                        Text("See all").font(.inter(11, .bold)).foregroundStyle(PL.gold)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(col.plans) { plan in PLPlanCard(plan: plan) }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 4)
                    }
                    .padding(.horizontal, -20)
                }
            }
        }
    }

    private var filteredResults: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                overline(category == "all" ? "Results" : category)
                Spacer(minLength: 0)
                Text("\(filtered.count) plan\(filtered.count == 1 ? "" : "s")").font(.inter(10, .semibold)).foregroundStyle(PL.ink3)
            }
            if filtered.isEmpty {
                VStack(spacing: 0) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PL.gold.opacity(0.08))
                        Icon(.bookOpen, size: 22, color: PL.gold)
                    }.frame(width: 48, height: 48)
                    Text("No plans found").font(.inter(13, .semibold)).foregroundStyle(PL.navy).padding(.top, 12)
                    Button { Haptics.tap(); query = ""; category = "all" } label: {
                        Text("Clear filters").font(.inter(11, .bold)).foregroundStyle(PL.gold)
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(Rectangle())
                    }.buttonStyle(.pressable)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 48)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(filtered) { plan in PLPlanTile(plan: plan) }
                }
            }
        }
    }

    // MARK: invitation

    private var invitationCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous).fill(PL.gold.opacity(0.12))
                Icon(.users, size: 19, color: PL.gold)
            }.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text("Read with a friend").font(.inter(13, .bold)).foregroundStyle(PL.navy)
                Text("Invite your cell to a plan and keep each other going.").font(.nCardMeta).foregroundStyle(PL.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 16, color: PL.ink3)
        }
        .padding(16)
        .background(LinearGradient(colors: [PL.gold.opacity(0.08), PL.gold.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PL.gold.opacity(0.2), lineWidth: 1))
    }

    private func overline(_ text: String) -> some View {
        Text(text.uppercased()).font(.inter(9, .bold)).kerning(1.62).foregroundStyle(PL.goldDeep)
    }
}

// MARK: - Plan detail (slide-over)

@MainActor
final class PlanDetailViewModel: ObservableObject {
    @Published var detail: ReadingPlanDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var busy = false

    private let planId: String
    init(planId: String) { self.planId = planId }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.plan(planId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this plan." }
        loading = false
    }

    func start() async {
        busy = true; defer { busy = false }
        try? await MemberAPI.startPlan(planId)
        await load()
    }
}

// Plan detail — rebuilt from the FRESH Figma PlanDetail: stretchy cover hero
// (back + save), category/title/meta, "About this plan", "What you'll read"
// (first 4 days, next-day highlight + Start pill, % done, expandable "+N more
// days"), the "Finish & earn" trophy card, the consistency nudge, and a sticky
// gold Continue/Start CTA + Invite bar. Intro video/audio players and the
// friends-on-plan avatar row from the mock are omitted (no real fields).
struct PlanDetailView: View {
    let plan: ReadingPlanRow
    @StateObject private var vm: PlanDetailViewModel
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false
    @State private var showAllDays = false

    init(plan: ReadingPlanRow) {
        self.plan = plan
        _vm = StateObject(wrappedValue: PlanDetailViewModel(planId: plan.planId))
    }

    var body: some View {
        ZStack {
            PL.cream.ignoresSafeArea()
            if let d = vm.detail {
                content(d)
            } else if vm.loading {
                ProgressView().tint(PL.gold)
            } else {
                VStack(spacing: 12) {
                    Text(vm.error ?? "Couldn't load this plan.").font(.nBody).foregroundStyle(PL.ink2)
                    Button { Haptics.tap(); Task { await vm.load() } } label: {
                        Text("Try again").font(.inter(14, .semibold)).foregroundStyle(PL.gold)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.pressable)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
        .onAppear { tabs.chromeHidden = true }
        // Restore the bar when this plan is popped (works from the Plans tab AND from
        // the Home resume banner). Pushing the day view keeps this mounted, so this
        // only fires on the real pop back out of the plan.
        .onDisappear { tabs.chromeHidden = false }
    }

    // Real completion state, derived from the day rows the server returns.
    private func completedCount(_ d: ReadingPlanDetail) -> Int { d.days.filter { $0.completed == true }.count }
    private func firstIncomplete(_ d: ReadingPlanDetail) -> ReadingPlanDay? {
        d.days.first { $0.completed != true } ?? d.days.first
    }

    private func content(_ d: ReadingPlanDetail) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    coverHero(d)
                    VStack(spacing: 16) {
                        aboutCard(d)
                        whatYoullRead(d)
                        PLFinishEarnCard(category: d.category, dayCount: d.dayCount)
                        nudge
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)
                }
            }
            ctaBar(d)
        }
    }

    // Cover hero — stretches on pull-down (native stand-in for the mock's
    // scroll parallax translate/scale).
    private func coverHero(_ d: ReadingPlanDetail) -> some View {
        GeometryReader { geo in
            let stretch = max(0, geo.frame(in: .global).minY)
            heroContent(d)
                .frame(width: geo.size.width, height: 256 + stretch)
                .offset(y: -stretch)
        }
        .frame(height: 256)
    }

    private func heroContent(_ d: ReadingPlanDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let u = d.imageUrl.flatMap(URL.init) {
                    // Contained fill image — its oversized ideal size must never
                    // inflate the hero ZStack (would shove the title off-canvas).
                    // Phase-based: while loading/failed the navy gradient shows
                    // (the old `Image(systemName: "photo")` fallback stretched a
                    // giant glyph across the hero), and the real cover fades in.
                    Color.clear.overlay {
                        CachedAsyncImage(url: u) { p in
                            if let img = p.image {
                                img.resizable().scaledToFill()
                                    .transition(.opacity.animation(.easeOut(duration: 0.25)))
                            } else {
                                Color.clear
                            }
                        }
                    }
                }
            }
            .clipped()
            .overlay(LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.40), Color(hex: 0x081424, alpha: 0.10), Color(hex: 0x081424, alpha: 0.92)], startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 6) {
                if let c = d.category, !c.isEmpty {
                    Text(c.uppercased()).font(.inter(9, .bold)).kerning(1.26).foregroundStyle(PL.navy)
                        .lineLimit(1)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(PL.gold, in: Capsule())
                }
                Text(d.title).font(.fraunces(26, .semibold)).kerning(-0.52).foregroundStyle(.white)
                    .lineLimit(3).truncationMode(.tail).multilineTextAlignment(.leading)
                HStack(spacing: 16) {
                    heroMeta(.clock, "\(d.dayCount) days")
                    heroMeta(.bookOpen, "Devotional")
                }
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .clipped()
        .overlay(alignment: .topLeading) {
            HStack {
                circleBtn(.chevronLeft, tint: .white) { dismiss() }
                Spacer()
                saveButton
            }
            .padding(.horizontal, 16).padding(.top, 60)
        }
    }

    private var saveButton: some View {
        Button {
            saved.toggle()
            Haptics.love()
        } label: {
            Group {
                if saved {
                    Image(systemName: "heart.fill").font(.system(size: 15)).foregroundStyle(PL.gold)
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    Icon(.heart, size: 17, color: .white)
                }
            }
            .frame(width: 40, height: 40)
            .background(Color.black.opacity(0.35), in: Circle())
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: saved)
        }
        .buttonStyle(.pressable)
    }

    private func heroMeta(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 13, color: PL.goldLight)
            Text(text).font(.inter(12)).foregroundStyle(.white.opacity(0.8))
        }
    }

    private func circleBtn(_ icon: Lucide, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 20, color: tint)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.pressable)
    }

    private func aboutCard(_ d: ReadingPlanDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ABOUT THIS PLAN").font(.nCardKicker).kerning(1.4).foregroundStyle(PL.goldDeep)
            Text(d.description ?? d.subtitle ?? "A guided plan — Scripture and a short devotional each day.")
                .font(.nCardBody).lineSpacing(4).foregroundStyle(PL.blurb)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private func whatYoullRead(_ d: ReadingPlanDetail) -> some View {
        let done = completedCount(d)
        let next = firstIncomplete(d)?.dayNumber
        let allDone = !d.days.isEmpty && done >= d.days.count
        let visible = showAllDays ? d.days : Array(d.days.prefix(4))
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WHAT YOU'LL READ").font(.nCardKicker).kerning(1.4).foregroundStyle(PL.goldDeep)
                Spacer(minLength: 0)
                if done > 0 {
                    Text("\(Int((Double(done) / Double(max(d.days.count, 1)) * 100).rounded()))% done")
                        .font(.inter(10, .bold)).foregroundStyle(PL.catText)
                }
            }
            VStack(spacing: 6) {
                ForEach(visible) { day in
                    NavigationLink(value: PlanDayRef(planId: d.planId, day: day)) {
                        PLDetailDayRow(day: day, isNext: !allDone && day.dayNumber == next)
                    }
                    .buttonStyle(.pressable)
                }
                if !showAllDays, d.days.count > 4 {
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.25)) { showAllDays = true }
                    } label: {
                        Text("+ \(d.days.count - 4) more days").font(.inter(10)).foregroundStyle(PL.ink3)
                            .frame(maxWidth: .infinity, minHeight: 36) // fingertip-friendly
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private var nudge: some View {
        HStack(spacing: 8) {
            Icon(.sparkles, size: 16, color: PL.gold)
            Text("Consistency over intensity — a few faithful minutes a day.")
                .font(.fraunces(12)).italic().foregroundStyle(PL.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(LinearGradient(colors: [PL.gold.opacity(0.08), PL.gold.opacity(0.02)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.gold.opacity(0.2), lineWidth: 1))
    }

    // Sticky CTA — Start plan (enroll) when not enrolled; once enrolled it
    // deep-links straight into the first incomplete day (or day 1 to review).
    private func ctaBar(_ d: ReadingPlanDetail) -> some View {
        let done = completedCount(d)
        let allDone = !d.days.isEmpty && done >= d.days.count
        let target = allDone ? d.days.first : firstIncomplete(d)
        let label: String = done > 0
            ? (allDone ? "Review plan" : "Continue · Day \(target?.dayNumber ?? 1)")
            : "Start plan"
        return HStack(spacing: 10) {
            Group {
                if d.enrolled, let target {
                    NavigationLink(value: PlanDayRef(planId: d.planId, day: target, planTitle: d.title)) { ctaLabel(label) }
                } else {
                    Button {
                        Haptics.action()
                        Task { await vm.start() }
                    } label: { ctaLabel(label) }
                }
            }
            .buttonStyle(.pressable)
            Button { } label: {
                HStack(spacing: 6) { Icon(.share2, size: 15, color: PL.navy); Text("Invite").font(.inter(13, .semibold)).foregroundStyle(PL.navy) }
                    .frame(minHeight: 48).padding(.horizontal, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white.overlay(alignment: .top) { Rectangle().fill(PL.border).frame(height: 1) })
    }

    private func ctaLabel(_ text: String) -> some View {
        HStack(spacing: 8) {
            if vm.busy { ProgressView().tint(PL.navy) }
            else { Icon(.bookOpen, size: 16, color: PL.navy) }
            Text(text).font(.inter(14, .bold)).foregroundStyle(PL.navy)
        }
        .frame(maxWidth: .infinity, minHeight: 48)
        .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: PL.gold.opacity(0.45), radius: 10, y: 8)
    }
}

// MARK: - Plan day (segments)

@MainActor
final class PlanDayViewModel: ObservableObject {
    @Published var completedSegments: Set<String> = []
    @Published var dayCompleted = false
    @Published var planCompleted = false   // this day finished the WHOLE plan
    @Published var busy = false

    private let planId: String
    private let dayNumber: Int
    init(ref: PlanDayRef) {
        planId = ref.planId
        dayNumber = ref.day.dayNumber
        completedSegments = Set((ref.day.segments ?? []).filter(\.completed).map(\.segmentId))
        dayCompleted = ref.day.completed ?? false
    }

    func completeSegment(_ id: String) async {
        if let res = try? await MemberAPI.completePlanSegment(id) {
            completedSegments.insert(id)
            if res.dayCompleted { dayCompleted = true }
        }
    }

    @Published var completeError: String?

    /// True only when the server actually recorded the completion — the
    /// caller keys the confetti/haptic off this, so a failed save never
    /// celebrates a day that didn't land.
    @discardableResult
    func completeDay() async -> Bool {
        busy = true; completeError = nil
        defer { busy = false }
        do {
            let planDone = try await MemberAPI.completePlanDay(planId, dayNumber: dayNumber)
            dayCompleted = true
            planCompleted = planDone
            return true
        } catch {
            completeError = "Couldn't save today — check your connection and try again."
            return false
        }
    }

    // MARK: Reflection (server-backed; UPSERT on resubmit)

    @Published var reflectionText = ""
    @Published var savedReflection: PlanDayReflection?
    @Published var reflectionSaving = false
    @Published var reflectionJustSaved = false
    @Published var reflectionError: String?

    /// Pre-fill from GET — never clobbers text the member is already typing.
    func loadReflection() async {
        // `try?` flattens the optional-returning throwing call (SE-0230):
        // nil here means "failed OR no reflection yet" — both mean do nothing.
        guard let row = try? await MemberAPI.planDayReflection(planId: planId, dayNumber: dayNumber) else { return }
        savedReflection = row
        if reflectionText.isEmpty { reflectionText = row.body }
    }

    func saveReflection() async {
        let text = String(reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).prefix(4000))
        guard !text.isEmpty, !reflectionSaving else { return }
        reflectionSaving = true; reflectionError = nil
        do {
            savedReflection = try await MemberAPI.savePlanDayReflection(
                planId: planId, dayNumber: dayNumber, body: text)
            Haptics.success()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { reflectionJustSaved = true }
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeOut(duration: 0.25)) { self?.reflectionJustSaved = false }
            }
        } catch {
            Haptics.error()
            let api = error as? APIError
            reflectionError = (api?.isNetwork == true)
                ? "You're offline — your reflection needs a connection to save."
                : (api?.errorDescription ?? "Couldn't save your reflection. Try again.")
        }
        reflectionSaving = false
    }
}

// Day screen — rebuilt from the FRESH Figma DayReader: navy gradient header
// (back, "DAY N", day title, gold progress bar), a scripture-style content
// card, the day's real segments as highlighted rows (they push the existing
// PlanSegmentView), the Figma reflection textarea (now REAL — backed by
// GET/POST /growth/plans/{id}/days/{n}/reflection with upsert semantics, so
// it pre-fills on return visits and the button flips to "Update"), and a
// sticky gold "Mark day complete" bar that celebrates with a native confetti
// burst. The mock's prev/next-day arrows are still omitted (the day ref
// carries no sibling days).
struct PlanDayView: View {
    let ref: PlanDayRef
    @StateObject private var vm: PlanDayViewModel
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var justDone = false
    @State private var showKeepsake = false
    @State private var videoItem: DayVideoItem?

    // Scroll-dwell reading tracker: a part is marked read only after the reader
    // has lingered on it (slow scroll / pause), never on a fast flick-through.
    @State private var sectionFrames: [String: CGRect] = [:]
    @State private var scrollY: CGFloat = 0
    @State private var lastScrollY: CGFloat = 0
    @State private var dwell: [String: Double] = [:]
    @State private var requested = Set<String>()
    @State private var dwellTimer = Timer.publish(every: 0.15, on: .main, in: .common).autoconnect()
    @FocusState private var reflectionFocused: Bool
    @State private var fastTicks = 0   // >0 while the "slow down" nudge shows

    struct DayVideoItem: Identifiable { let id = UUID(); let url: URL }

    init(ref: PlanDayRef) {
        self.ref = ref
        _vm = StateObject(wrappedValue: PlanDayViewModel(ref: ref))
    }

    private var segments: [PlanSegment] { ref.day.segments ?? [] }
    private var progress: Double {
        if vm.dayCompleted { return 1 }
        guard !segments.isEmpty else { return 0 }
        return Double(vm.completedSegments.count) / Double(segments.count)
    }

    // Open the day → the reading itself: one warm scroll of every part, with
    // quick-step chips at the top that jump to a section (same page, one read).
    var body: some View {
        ZStack {
            PL.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            Color.clear.frame(height: 0)
                                .background(GeometryReader { g in
                                    Color.clear.preference(key: ReaderScrollKey.self,
                                                           value: g.frame(in: .named("reader")).minY)
                                })
                            dayHeader
                            quickSteps(proxy)
                            VStack(alignment: .leading, spacing: 30) {
                                ForEach(Array(segments.enumerated()), id: \.element.id) { _, seg in
                                    readerSection(seg).id(seg.segmentId)
                                }
                                reflectionCard
                                DayEncouragement()
                            }
                            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 24)
                        }
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .coordinateSpace(name: "reader")
                    .background(GeometryReader { g in
                        Color.clear.preference(key: ViewportHKey.self, value: g.size.height)
                    })
                }
                footerBar
            }
            if justDone { IntenseCelebration().ignoresSafeArea().allowsHitTesting(false) }
        }
        .overlay(alignment: .top) {
            if fastTicks > 0 { fastScrollNudge.padding(.top, 92) }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: fastTicks > 0)
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.loadReflection() }
        .fullScreenCover(item: $videoItem) { it in videoWindow(it.url) }
        .fullScreenCover(isPresented: $showKeepsake) {
            PlanKeepsakeView(planTitle: ref.planTitle ?? ref.day.title ?? "your plan",
                             days: ref.day.dayNumber) { showKeepsake = false; dismiss() }
        }
        .onAppear { tabs.chromeHidden = true }
        .onPreferenceChange(ReaderScrollKey.self) { scrollY = -$0 }
        .onPreferenceChange(ViewportHKey.self) { viewportH = $0 }
        .onPreferenceChange(SectionFramesKey.self) { sectionFrames = $0 }
        .onReceive(dwellTimer) { _ in tickDwell() }
        .onDisappear { dwellTimer.upstream.connect().cancel() }
    }

    @State private var viewportH: CGFloat = 720

    /// One tick (~0.15s): accrue "reading" credit for the part straddling the
    /// reading line, but ONLY while scrolling slowly — a fast flick earns nothing.
    /// When a part's dwell passes its threshold it marks itself read.
    private func tickDwell() {
        let dt = 0.15
        let velocity = abs(scrollY - lastScrollY) / dt
        lastScrollY = scrollY
        if fastTicks > 0 { fastTicks -= 1 }              // fade the nudge out over time
        if velocity > 2600 { fastTicks = 16 }            // racing past → "slow down" (~2.4s)
        guard velocity < 650 else { return }            // fast scroll → skip, no credit
        let line = viewportH * 0.40                       // reading line: upper-middle
        for seg in segments {
            let id = seg.segmentId
            if vm.completedSegments.contains(id) || seg.completed { continue }
            guard let f = sectionFrames[id], f.minY <= line, line <= f.maxY else { continue }
            let need = min(2.2, max(0.9, f.height / 520))  // longer parts need a bit more dwell
            dwell[id, default: 0] += dt
            if dwell[id, default: 0] >= need, !requested.contains(id) {
                requested.insert(id)
                Task { await vm.completeSegment(id) }
            }
        }
    }

    /// Floating "slow down" nudge — appears when the reader races past the text.
    private var fastScrollNudge: some View {
        HStack(spacing: 8) {
            Image(systemName: "tortoise.fill").font(.system(size: 13)).foregroundStyle(PL.gold)
            Text("Slow down — savour the reading").font(.inter(12.5, .semibold)).foregroundStyle(.white)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(PL.navy, in: Capsule())
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: navy header (fresh DayReader)

    private var dayHeader: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.chevronLeft, size: 18, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                Spacer()
                Text("DAY \(ref.day.dayNumber)").font(.inter(10, .bold)).kerning(1.8).foregroundStyle(PL.gold)
                Spacer()
                Color.clear.frame(width: 36, height: 36)
            }
            Text(ref.day.reference).font(.inter(11)).foregroundStyle(.white.opacity(0.6)).padding(.top, 12)
            Text(ref.day.title ?? "Day \(ref.day.dayNumber)")
                .font(.fraunces(23, .semibold)).kerning(-0.46).foregroundStyle(.white)
                .lineLimit(2).padding(.top, 2)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.2))
                    Capsule()
                        .fill(LinearGradient(colors: [PL.gold, PL.goldLight], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(progress > 0 ? 8 : 0, geo.size.width * progress))
                        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
                }
            }
            .frame(height: 4)
            .padding(.top, 12)
        }
        .padding(.horizontal, 20)
        .padding(.top, 60)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            RadialGradient(colors: [PL.gold.opacity(0.27), .clear], center: .center, startRadius: 0, endRadius: 96)
                .frame(width: 192, height: 192).blur(radius: 40).opacity(0.5).offset(x: 56, y: -64)
        }
        .background(LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    // MARK: quick steps (in-page jump nav under the header)

    private func quickSteps(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { _, seg in
                    let done = vm.completedSegments.contains(seg.segmentId) || seg.completed
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.35)) { proxy.scrollTo(seg.segmentId, anchor: .top) }
                    } label: {
                        HStack(spacing: 5) {
                            if done { Icon(.check, size: 10, color: PL.goldDeep) }
                            Text(chipLabel(seg)).font(.inter(12, .bold)).foregroundStyle(PL.navy)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(PL.gold.opacity(0.14), in: Capsule())
                        .overlay(Capsule().stroke(PL.gold.opacity(0.3), lineWidth: 1))
                    }
                    .buttonStyle(.pressable)
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(PL.cream)
    }

    private func chipLabel(_ seg: PlanSegment) -> String {
        if seg.title.lowercased().hasPrefix("pray") { return "Prayer" }
        switch seg.kind.lowercased() {
        case "scripture": return "Scripture"
        case "devotional": return "Devotional"
        case "talk": return "Talk"
        case "reading": return "Deeper"
        case "video": return "Watch"
        default: return seg.title.isEmpty ? seg.kind.capitalized : seg.title
        }
    }

    // MARK: reader section (overline + completion tick + kind-aware body)

    private func readerSection(_ seg: PlanSegment) -> some View {
        let done = vm.completedSegments.contains(seg.segmentId) || seg.completed
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(overline(seg)).font(.inter(13, .bold)).kerning(2.0).foregroundStyle(PL.goldDeep)
                if seg.kind.lowercased() == "scripture", let r = seg.reference, !r.isEmpty {
                    Text("· \(r)").font(.inter(12, .medium)).foregroundStyle(PL.ink3)
                }
                Spacer(minLength: 0)
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15)).foregroundStyle(done ? PL.gold : PL.ink3.opacity(0.4))
                    .scaleEffect(done ? 1 : 0.9)
                    .animation(.spring(response: 0.3, dampingFraction: 0.65), value: done)
            }
            sectionBody(seg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GeometryReader { g in
            Color.clear.preference(key: SectionFramesKey.self,
                                   value: [seg.segmentId: g.frame(in: .named("reader"))])
        })
    }

    private func overline(_ seg: PlanSegment) -> String {
        if seg.title.lowercased().hasPrefix("pray") { return "PRAYER" }
        if !seg.title.isEmpty { return seg.title.uppercased() }
        switch seg.kind.lowercased() {
        case "scripture": return "TODAY'S READING"
        case "devotional": return "DEVOTIONAL"
        case "talk": return "TALK IT OVER"
        case "reading": return "GO DEEPER"
        case "video": return "WATCH"
        default: return seg.kind.uppercased()
        }
    }

    @ViewBuilder
    private func sectionBody(_ seg: PlanSegment) -> some View {
        switch seg.kind.lowercased() {
        case "video":
            DayVideoCard(seg: seg) { url in videoItem = DayVideoItem(url: url) }
        case "scripture":
            DayPullQuote(text: (seg.content?.isEmpty == false ? seg.content! : (seg.reference ?? seg.title)),
                         caption: seg.reference ?? "Scripture",
                         quoted: seg.content?.isEmpty == false)
        case "talk":
            if let c = seg.content, !c.isEmpty { DayTalk(prompt: c) }
        case "reading":
            if let c = seg.content, !c.isEmpty { DayGoDeeper(refs: c) }
        default:
            if seg.title.lowercased().hasPrefix("pray"), let c = seg.content, !c.isEmpty { DayPrayer(text: c) }
            else if let c = seg.content, !c.isEmpty { DayPassage(content: c) }
        }
    }

    // MARK: video window (opens over the day content)

    private func videoWindow(_ url: URL) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Button { videoItem = nil } label: {
                        Icon(.x, size: 18, color: .white)
                            .frame(width: 38, height: 38).background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 12)
                Spacer(minLength: 0)
                Button { openURL(url) } label: {
                    HStack(spacing: 8) {
                        Icon(.play, size: 16, color: PL.navy)
                        Text("Start watching").font(.inter(16, .bold)).foregroundStyle(PL.navy)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
    }

    private func segmentIcon(_ kind: String) -> Lucide {
        switch kind.lowercased() {
        case "video":      return .play
        case "reading":    return .bookOpen
        case "devotional": return .sun
        case "talk":       return .messageCircle
        case "scripture":  return .quote
        default:           return .book
        }
    }

    // MARK: reflection — the Figma textarea, now backed by the real endpoint.
    // Pre-filled from GET; Submit upserts (the button reads "Update" once a
    // reflection exists) and lands a brief "Saved" check.

    private var reflectionCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("REFLECTION").font(.nCardKicker).kerning(1.4).foregroundStyle(PL.goldDeep)
                Spacer(minLength: 0)
                if vm.reflectionJustSaved {
                    HStack(spacing: 4) {
                        Icon(.check, size: 11, color: Color(hex: 0x16A34A))
                        Text("Saved").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x15803D))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            Text("What is God showing you today?")
                .font(.fraunces(16, .medium)).italic().kerning(-0.16).foregroundStyle(PL.navy)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            ZStack(alignment: .topLeading) {
                if vm.reflectionText.isEmpty {
                    Text("Write it down while it's fresh…").font(.inter(13)).foregroundStyle(PL.ink3)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
                TextField("", text: $vm.reflectionText, axis: .vertical)
                    .lineLimit(4...10)
                    .font(.inter(13.5)).foregroundStyle(PL.navy).tint(PL.gold)
                    .focused($reflectionFocused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { reflectionFocused = false }
                                .font(.inter(14, .semibold)).foregroundStyle(PL.goldDeep)
                        }
                    }
            }
            .background(PL.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1))
            .padding(.top, 10)
            if let err = vm.reflectionError {
                Text(err).font(.inter(11)).foregroundStyle(Color(hex: 0xB42318))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            reflectionSubmit.padding(.top, 10)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private var reflectionSubmit: some View {
        let empty = vm.reflectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return Button {
            Haptics.action()
            Task { await vm.saveReflection() }
        } label: {
            HStack(spacing: 6) {
                if vm.reflectionSaving { ProgressView().tint(PL.refInk) }
                else { Icon(.pencil, size: 13, color: PL.refInk) }
                Text(vm.savedReflection == nil ? "Save reflection" : "Update")
                    .font(.inter(12, .bold)).foregroundStyle(PL.refInk)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(PL.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PL.gold.opacity(0.27), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .disabled(empty || vm.reflectionSaving)
        .opacity(empty ? 0.5 : 1)
        .animation(.easeInOut(duration: 0.2), value: empty)
    }

    // MARK: sticky footer — mark complete → confetti → tap to go back

    private var footerBar: some View {
        VStack(spacing: 8) {
            if let e = vm.completeError {
                Text(e).font(.inter(11)).foregroundStyle(Color(hex: 0xB91C1C))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .transition(.opacity)
            }
            footerButton
        }
        .animation(.easeInOut(duration: 0.2), value: vm.completeError == nil)
        .padding(.horizontal, 20).padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white.overlay(alignment: .top) { Rectangle().fill(PL.border).frame(height: 1) })
    }

    @ViewBuilder private var footerButton: some View {
        HStack {
            if vm.dayCompleted || justDone {
                Button { Haptics.tap(); dismiss() } label: {
                    HStack(spacing: 8) {
                        Text("Continue the plan").font(.inter(14, .bold)).foregroundStyle(PL.navy)
                        Icon(.arrowRight, size: 15, color: PL.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: PL.gold.opacity(0.45), radius: 10, y: 8)
                }
                .buttonStyle(.pressable)
            } else {
                Button {
                    Task {
                        if await vm.completeDay() {
                            Haptics.success() // land the celebration with a felt "done"
                            justDone = true
                            // Finishing the WHOLE plan opens the keepsake after the burst.
                            if vm.planCompleted {
                                try? await Task.sleep(nanoseconds: 700_000_000)
                                showKeepsake = true
                            }
                            // The intense fireworks run ~5s, then retire (the completed
                            // button stays via vm.dayCompleted).
                            try? await Task.sleep(nanoseconds: 5_300_000_000)
                            justDone = false
                        } else {
                            Haptics.error()
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        if vm.busy { ProgressView().tint(PL.navy) }
                        else { Icon(.check, size: 16, color: PL.navy) }
                        Text("Mark day complete").font(.inter(14, .bold)).foregroundStyle(PL.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: PL.gold.opacity(0.45), radius: 10, y: 8)
                }
                .buttonStyle(.pressable)
                .disabled(vm.busy) // double-taps queued a second completion call
            }
        }
    }
}

// MARK: - Intense celebration (fireworks + saturating confetti, ~5s)

/// A big, joyful "boom": staggered firework bursts across the upper screen plus a
/// dense tumbling-confetti rain, drawn in a single Canvas for performance. Runs
/// for ~5s then empties itself. Purely decorative — never blocks touches.
private struct IntenseCelebration: View {
    var duration: Double = 5.0
    @State private var start: Date?

    private let confetti: [Piece]
    private let sparks: [Spark]

    struct Piece { let x, delay, fall, sway, phase, spin, size: Double; let color: Color }
    struct Spark { let cx, cy, t0, angle, speed, size: Double; let color: Color }

    static let palette: [Color] = [
        PL.gold, PL.goldLight, Color(hex: 0xFBBF24), Color(hex: 0xFB7185),
        Color(hex: 0x34D399), Color(hex: 0x60A5FA), Color(hex: 0xFFF3D6),
    ]

    init(duration: Double = 5.0) {
        self.duration = duration
        var conf: [Piece] = []
        for _ in 0..<170 {
            conf.append(Piece(x: .random(in: 0...1), delay: .random(in: 0...2.6),
                              fall: .random(in: 0.9...1.7), sway: .random(in: 12...48),
                              phase: .random(in: 0...6.28), spin: .random(in: -7...7),
                              size: .random(in: 6...13), color: Self.palette.randomElement()!))
        }
        var sp: [Spark] = []
        let bursts = 7
        for b in 0..<bursts {
            let cx = Double.random(in: 0.15...0.85)
            let cy = Double.random(in: 0.14...0.52)
            let t0 = Double(b) * (duration * 0.55 / Double(bursts)) + Double.random(in: 0...0.35)
            let color = Self.palette.randomElement()!
            let count = 46
            for i in 0..<count {
                let ang = Double(i) / Double(count) * 6.2831 + Double.random(in: -0.05...0.05)
                sp.append(Spark(cx: cx, cy: cy, t0: t0, angle: ang,
                                speed: .random(in: 0.15...0.26), size: .random(in: 3...6), color: color))
            }
        }
        confetti = conf; sparks = sp
    }

    var body: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = start.map { tl.date.timeIntervalSince($0) } ?? 0
                for p in confetti {
                    let lt = t - p.delay
                    if lt < 0 { continue }
                    let prog = lt * p.fall / duration
                    if prog > 1.05 { continue }
                    let x = (p.x + sin(lt * 2.2 + p.phase) * (p.sway / size.width)) * size.width
                    let y = (-0.08 + prog * 1.25) * size.height
                    let alpha = min(1, max(0, 1 - (prog - 0.82) / 0.18))
                    var l = ctx
                    l.opacity = alpha
                    l.translateBy(x: x, y: y)
                    l.rotate(by: .radians(lt * p.spin))
                    l.fill(Path(CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * 0.62)),
                           with: .color(p.color))
                }
                for s in sparks {
                    let lt = t - s.t0
                    if lt < 0 || lt > 1.5 { continue }
                    let ease = 1 - pow(1 - min(lt / 1.0, 1), 3)
                    let dist = s.speed * ease
                    let x = (s.cx + cos(s.angle) * dist) * size.width
                    let y = (s.cy + sin(s.angle) * dist + 0.11 * lt * lt) * size.height
                    var l = ctx
                    l.opacity = max(0, 1 - lt / 1.5)
                    l.fill(Path(ellipseIn: CGRect(x: x - s.size / 2, y: y - s.size / 2, width: s.size, height: s.size)),
                           with: .color(s.color))
                }
            }
        }
        .onAppear { start = Date() }
        .allowsHitTesting(false)
    }
}

// MARK: - Reader scroll/dwell preference keys

private struct ReaderScrollKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
private struct ViewportHKey: PreferenceKey {
    static var defaultValue: CGFloat = 720
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { let n = nextValue(); if n > 0 { value = n } }
}
private struct SectionFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

// MARK: - Day reader section components (single-scroll reading)

/// Gold pull-quote. Never double-quotes: verse text already carries curly quotes.
private struct DayPullQuote: View {
    let text: String; let caption: String; var quoted = true
    private var display: String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let already = t.hasPrefix("\u{201C}") || t.hasPrefix("\"")
        return (quoted && !already) ? "\u{201C}\(t)\u{201D}" : t
    }
    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(PL.gold).frame(width: 3)
            VStack(alignment: .leading, spacing: 8) {
                Icon(.quote, size: 16, color: PL.gold)
                Text(display).font(.fraunces(18)).foregroundStyle(PL.navy).lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
                Text(caption.uppercased()).font(.nCardKicker).kerning(1.4).foregroundStyle(PL.ink3)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(PL.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.gold.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Serif teaching split into paragraphs on blank lines. Generous size + line
/// height + inter-paragraph gap for comfortable, unhurried reading.
private struct DayPassage: View {
    let content: String
    private var paragraphs: [String] {
        content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p).font(.fraunces(18)).foregroundStyle(PL.navy).lineSpacing(10)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Talk-it-over questions on a white card.
private struct DayTalk: View {
    let prompt: String
    private var questions: [String] {
        prompt.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map { $0.hasPrefix("—") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                HStack(alignment: .top, spacing: 8) {
                    Icon(.messageCircle, size: 13, color: PL.goldDeep).padding(.top, 3)
                    Text(q).font(.fraunces(15)).foregroundStyle(PL.navy).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.border, lineWidth: 1))
    }
}

/// Prayer on a warm gold tint, with an italic closing blessing (`_…_`).
private struct DayPrayer: View {
    let text: String
    private var lines: [String] { text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var blessing: String? {
        guard let last = lines.last, last.hasPrefix("_"), last.hasSuffix("_"), last.count > 2 else { return nil }
        return String(last.dropFirst().dropLast())
    }
    private var prayer: String { (blessing == nil ? lines : Array(lines.dropLast())).joined(separator: "\n\n") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !prayer.isEmpty {
                Text(prayer).font(.fraunces(15)).foregroundStyle(PL.navy).lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let b = blessing {
                Text(b).font(.fraunces(14)).italic().foregroundStyle(PL.goldDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(PL.gold.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.gold.opacity(0.22), lineWidth: 1))
    }
}

/// Compact Go Deeper references row.
private struct DayGoDeeper: View {
    let refs: String
    var body: some View {
        HStack(spacing: 10) {
            Icon(.bookOpen, size: 15, color: PL.goldDeep)
            Text(refs).font(.fraunces(14)).foregroundStyle(PL.navy).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(PL.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Sign-off line on a soft gold tint.
private struct DayEncouragement: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(.handHeart, size: 16, color: PL.gold)
            Text("Every faithful day adds up. There's no rush — just presence.")
                .font(.nCardBody).foregroundStyle(PL.navy).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(PL.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Inline 16:9 video card — tap opens the player window over the day content.
private struct DayVideoCard: View {
    let seg: PlanSegment
    let onPlay: (URL) -> Void
    var body: some View {
        ZStack {
            Rectangle().fill(LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let u = seg.imageUrl.flatMap(URL.init) {
                Color.clear.overlay {
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() } else { Color.clear }
                    }
                }.clipped()
            }
            Button {
                Haptics.tap()
                if let v = seg.videoUrl.flatMap(URL.init) { onPlay(v) }
            } label: {
                ZStack {
                    Circle().fill(PL.gold).frame(width: 58, height: 58)
                    Icon(.play, size: 20, color: PL.navy).offset(x: 1)
                }
            }.buttonStyle(.pressable)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

// MARK: - Plan completion keepsake (milestone celebration + shareable card)

/// A warm, full-screen "you finished the plan" moment: a ceremonial gold seal,
/// the plan name in serif, days walked, a blessing, fireworks, and a shareable
/// keepsake card. The emotional payoff that makes members start the next plan.
struct PlanKeepsakeView: View {
    let planTitle: String
    let days: Int
    let onDone: () -> Void
    @State private var shareImage: Image?
    @State private var seal = false

    var body: some View {
        ZStack {
            PL.cream.ignoresSafeArea()
            IntenseCelebration().ignoresSafeArea().allowsHitTesting(false)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                ZStack {
                    Circle().stroke(PL.gold.opacity(0.4), lineWidth: 2).frame(width: 132, height: 132)
                    Circle()
                        .fill(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 104, height: 104)
                        .shadow(color: PL.gold.opacity(0.5), radius: 16, y: 8)
                    Icon(.check, size: 40, color: .white)
                }
                .scaleEffect(seal ? 1 : 0.6).opacity(seal ? 1 : 0)
                .padding(.bottom, 24)
                Text("PLAN COMPLETE").font(.inter(12, .bold)).kerning(2.4).foregroundStyle(PL.goldDeep)
                Text(planTitle).font(.fraunces(30, .semibold)).foregroundStyle(PL.navy)
                    .multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 8)
                Text("\(days) days walking with God").font(.inter(14, .medium)).foregroundStyle(PL.ink2).padding(.top, 6)
                Text("“Well done, good and faithful servant.”\nMatthew 25:23")
                    .font(.fraunces(15)).italic().foregroundStyle(PL.goldDeep)
                    .multilineTextAlignment(.center).lineSpacing(4).padding(.horizontal, 40).padding(.top, 18)
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    if let shareImage {
                        ShareLink(item: shareImage, preview: SharePreview("I completed \(planTitle)", image: shareImage)) {
                            HStack(spacing: 8) {
                                Icon(.share2, size: 15, color: .white)
                                Text("Share my finish").font(.inter(15, .bold)).foregroundStyle(.white)
                            }
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(PL.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                    Button { Haptics.tap(); onDone() } label: {
                        Text("Continue your journey").font(.inter(15, .bold)).foregroundStyle(PL.navy)
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }.buttonStyle(.pressable)
                }
                .padding(.horizontal, 24).padding(.bottom, 30)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.15)) { seal = true }
            let renderer = ImageRenderer(content: KeepsakeShareCard(planTitle: planTitle, days: days))
            renderer.scale = 3
            if let ui = renderer.uiImage { shareImage = Image(uiImage: ui) }
        }
    }
}

/// The rendered image shared to WhatsApp / socials — a branded Nuru keepsake.
struct KeepsakeShareCard: View {
    let planTitle: String
    let days: Int
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 84, height: 84)
                Icon(.check, size: 34, color: .white)
            }
            Text("PLAN COMPLETE").font(.inter(11, .bold)).kerning(2).foregroundStyle(PL.goldDeep).padding(.top, 4)
            Text(planTitle).font(.fraunces(26, .semibold)).foregroundStyle(PL.navy).multilineTextAlignment(.center)
            Text("\(days) days walking with God").font(.inter(13, .medium)).foregroundStyle(PL.ink2)
            Text("NURU PATHWAY").font(.inter(11, .bold)).kerning(1.8).foregroundStyle(PL.goldDeep).padding(.top, 8)
        }
        .padding(40)
        .frame(width: 400, height: 400)
        .background(PL.cream)
    }
}
