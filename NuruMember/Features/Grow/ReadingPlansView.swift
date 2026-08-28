// Plans tab — rebuilt line-by-line from the UPDATED Figma Make source of truth
// (components/PlansTab.tsx). The fresh design moved to a light-cream header
// (white search field + bell), added a streak/reward strip (flame, week dots,
// badge progress), a shimmering "Plan of the day" badge, a pulsing play ring on
// continue rows, a "Finish & earn" trophy card and highlighted next-day rows in
// the detail slide-over, and a navy day header + a fireworks burst on day completion.
// Everything binds to REAL data: the ReadingPlanRow catalogue (MemberAPI.plans),
// plan detail (MemberAPI.plan), enrollment (startPlan), day/segment completion
// (completePlanDay / PlanDayRef navigation), streak (me/achievements) and the
// Word rhythm (me/rhythm/today). Mock-only Figma fields (audio flags, intro
// video/audio players, friends-on-plan avatars) are omitted — no fake data.
// Shared card structs + the PL palette live in ReadingPlanCards.swift.
import SwiftUI
import UserNotifications
import AVFoundation

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

// MARK: - Reader palette (day / warm-night sepia)

/// Colors for the day reader in either light (cream/navy) or a warm night/sepia
/// mode (deep warm paper, cream ink, dimmed gold) for comfortable low-light reading.
struct ReaderPalette {
    var night: Bool = false
    var bg: Color { night ? Color(hex: 0x171411) : PL.cream }
    var ink: Color { night ? Color(hex: 0xEBE3D3) : PL.navy }
    var inkDim: Color { night ? Color(hex: 0x9A9280) : PL.ink3 }
    var card: Color { night ? Color(hex: 0x221E18) : Color.white }
    var gold: Color { night ? Color(hex: 0xD9B65A) : PL.gold }
    var goldDeep: Color { night ? Color(hex: 0xCBA24A) : PL.goldDeep }
    var border: Color { night ? Color.white.opacity(0.09) : PL.border }
    var verseBg: Color { night ? Color(hex: 0x251E13) : PL.highlight }
}
private struct ReaderPaletteKey: EnvironmentKey { static let defaultValue = ReaderPalette() }
extension EnvironmentValues {
    var readerPalette: ReaderPalette {
        get { self[ReaderPaletteKey.self] }
        set { self[ReaderPaletteKey.self] = newValue }
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
        streak = (await ach)?.streak?.current ?? 0
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
    /// Every plan, grouped by length — and every one VISIBLE (owner, 2026-08-26:
    /// "make sure all plans are not hidden"). The old browse put 17 plans in a
    /// sideways rail where 14 of them lived off-screen behind a gesture most
    /// members never make; each plan also appeared twice (once in "Featured",
    /// once in its length bucket). Now: one vertical grid, each plan once, in
    /// the section that describes the commitment it asks for.
    private var collections: [(id: String, label: String, plans: [ReadingPlanRow])] {
        var out: [(String, String, [ReadingPlanRow])] = []
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

    /// A second plan to promote further down the page — never the one already
    /// featured at the top, and never one already being read. Rotates with the
    /// day like the plan of the day, so browsing feels edited, not random.
    private var midPromoPlan: ReadingPlanRow? {
        let pool = vm.plans.filter { !$0.enrolled && $0.planId != planOfDay?.planId && ($0.description?.isEmpty == false) }
        guard !pool.isEmpty else { return nil }
        let day = Int(Date().timeIntervalSince1970 / 86_400)
        return pool[(day / 2) % pool.count]
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
                              emptyText: "Plans are being prepared — check back soon.", retry: { Task { await vm.load() } }) {
                    VStack(alignment: .leading, spacing: 24) {
                        if !searching, !streakQuiet { PLStreakStrip(count: vm.streak, todayDone: vm.todayWordDone) }
                        if !searching, !continueReading.isEmpty { continueSection }
                        if !searching, !continueReading.isEmpty { reminderCard }
                        // The day's invitation, given room to actually invite:
                        // cover + subtitle + the plan's own opening line + a CTA.
                        if !searching, let pod = planOfDay { PLPlanPromo(plan: pod, kicker: "PLAN OF THE DAY") }
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
                    Text("Grow in the Word").font(.fraunces(26, .medium)).kerning(-0.72).foregroundStyle(PL.navy)
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
                Text(p.title).font(.fraunces(18, .medium)).kerning(-0.2).foregroundStyle(.white).lineLimit(1)
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
                    Text(plan.title).font(.fraunces(22, .medium)).kerning(-0.44).foregroundStyle(.white)
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

    /// Browse: every plan on the page, two to a row, grouped by commitment —
    /// nothing behind a sideways swipe. One promo card is woven in after the
    /// first section so the page reads like a magazine rather than a stock list.
    private var collectionsSections: some View {
        VStack(alignment: .leading, spacing: 24) {
            ForEach(Array(collections.enumerated()), id: \.element.id) { i, col in
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(col.label).font(.fraunces(13, .semibold)).kerning(-0.13).foregroundStyle(PL.navy)
                        Spacer(minLength: 0)
                        Text("\(col.plans.count)").font(.inter(11, .bold)).foregroundStyle(PL.ink3)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                        ForEach(col.plans) { plan in PLPlanTile(plan: plan) }
                    }
                }
                if i == 0, let promo = midPromoPlan {
                    PLPlanPromo(plan: promo, kicker: "WORTH YOUR WEEK")
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

    // MARK: invitation — the Read with a Friend hub (spec §3)

    private var invitationCard: some View {
        NavigationLink(value: GrowDestination.readWithFriendHub) {
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
        .buttonStyle(.pressable)
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
    /// A segment ack told us this day number should already be open. Kept
    /// until a fetch actually shows it unlocked, so a day that still comes
    /// back locked (a completion still catching up through the sync path)
    /// reads as "finishing sync" rather than "you're not there yet".
    @Published var awaitingUnlock: Int?

    private let planId: String
    init(planId: String) { self.planId = planId }

    /// Always re-fetches — this screen decides which days are tappable, so it
    /// never trusts a cached "locked" answer from before the member walked
    /// off to finish the previous day. (The offline-sync race: the day
    /// unlocks the moment its last segment lands, which can be after this
    /// screen was last drawn.)
    func load() async {
        loading = true; error = nil
        do {
            detail = try await MemberAPI.plan(planId)
            if let waiting = awaitingUnlock,
               detail?.days.first(where: { $0.dayNumber == waiting })?.locked == false {
                awaitingUnlock = nil
            }
        }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this plan." }
        loading = false
    }

    func start() async {
        busy = true; defer { busy = false }
        try? await MemberAPI.startPlan(planId)
        await load()
    }

    /// A segment's ack (relayed from the day hub) said this plan's next day
    /// is already open server-side.
    func noteUnlockAck(_ ack: PlanDayUnlockAck) {
        guard ack.planId == nil || ack.planId == planId else { return }
        if ack.nextDayUnlocked, let next = ack.nextDayNumber { awaitingUnlock = next }
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
    /// Which locked day the member just reached for — drives the nudge back to
    /// the day they're actually on.
    @State private var lockedNudgeFor: Int?
    /// Read with a Friend (spec §6): create-or-get my group for this plan,
    /// mint an open invite, hand the /join/{token} link to the share sheet.
    @State private var invitingBusy = false
    @State private var inviteError: String?

    init(plan: ReadingPlanRow) {
        self.plan = plan
        _vm = StateObject(wrappedValue: PlanDetailViewModel(planId: plan.planId))
    }

    var body: some View {
        ZStack {
            PL.cream.ignoresSafeArea()
            if let d = vm.detail {
                content(d)
                    .alert("Day \(lockedNudgeFor ?? 0) is still ahead",
                           isPresented: Binding(get: { lockedNudgeFor != nil },
                                                set: { if !$0 { lockedNudgeFor = nil } })) {
                        Button("Stay on Day \(d.nextDay ?? 1)") { lockedNudgeFor = nil }
                    } message: {
                        Text(lockedNudgeMessage(d))
                    }
            } else if vm.loading {
                VStack(spacing: 12) {
                    ProgressView().tint(PL.gold)
                    Text("Preparing your plan…").font(.inter(12, .medium)).foregroundStyle(PL.ink3)
                }
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
        // Always re-fetches on appear (including popping back from the day
        // hub) — see PlanDetailViewModel.load(). vm.detail stays populated
        // meanwhile so this never flashes back to a loading spinner.
        .task { await vm.load() }
        // Hide the bar inside a plan. No onDisappear-restore here: on a PUSH the
        // child's onAppear fires BEFORE this view's onDisappear, so restoring from
        // here re-showed the bar on top of the day hub's footer button. The roots
        // (Plans list, Home) restore the bar on their own onAppear when we pop out.
        .onAppear { tabs.chromeHidden = true }
        .onReceive(NotificationCenter.default.publisher(for: .nuruPlanDayUnlocked)) { note in
            if let ack = note.object as? PlanDayUnlockAck { vm.noteUnlockAck(ack) }
        }
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
                Text(d.title).font(.fraunces(26, .medium)).kerning(-0.72).foregroundStyle(.white)
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
                Text("YOUR JOURNEY · \(d.days.count) DAYS").font(.nCardKicker).kerning(1.4).foregroundStyle(PL.goldDeep)
                Spacer(minLength: 0)
                if done > 0 {
                    Text("\(Int((Double(done) / Double(max(d.days.count, 1)) * 100).rounded()))% done")
                        .font(.inter(10, .bold)).foregroundStyle(PL.catText)
                }
            }
            VStack(spacing: 6) {
                ForEach(visible) { day in
                    if day.locked, vm.awaitingUnlock == day.dayNumber {
                        // A segment ack already told us this day should be
                        // open — this fetch just hasn't caught up yet (the
                        // completion is still landing through the sync path).
                        // An honest brief state, not a dead "you're not there
                        // yet" tap: say so, and let a tap retry the fetch.
                        Button {
                            Haptics.tap()
                            Task { await vm.load() }
                        } label: {
                            PLDetailDayRow(day: day, isNext: false, syncing: true)
                        }
                        .buttonStyle(.pressable)
                    } else if day.locked {
                        // The plan is walked, not skimmed. A locked day doesn't
                        // open — tapping it turns you back to the day you're on,
                        // kindly. (The server withholds its words either way.)
                        Button {
                            Haptics.tap()
                            withAnimation(.easeOut(duration: 0.2)) { lockedNudgeFor = day.dayNumber }
                        } label: {
                            PLDetailDayRow(day: day, isNext: false)
                        }
                        .buttonStyle(.pressable)
                    } else {
                        NavigationLink(value: PlanDayRef(planId: d.planId, day: day, planTitle: d.title)) {
                            PLDetailDayRow(day: day, isNext: !allDone && day.dayNumber == next)
                        }
                        .buttonStyle(.pressable)
                    }
                }
                if !showAllDays, d.days.count > 4 {
                    Button {
                        Haptics.tap()
                        withAnimation(.easeOut(duration: 0.25)) { showAllDays = true }
                    } label: {
                        HStack(spacing: 5) {
                            Text("Show all \(d.days.count) days").font(.inter(12, .bold)).foregroundStyle(PL.goldDeep)
                            Icon(.chevronDown, size: 13, color: PL.goldDeep)
                        }
                        .frame(maxWidth: .infinity, minHeight: 40)
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

    /// Turning someone back from a locked day. Not an error — an invitation:
    /// name the day they're on, name what it holds, and tell them the truth
    /// about why this one is closed. The plan is a walk, and a walk has an order.
    private func lockedNudgeMessage(_ d: ReadingPlanDetail) -> String {
        let n = d.nextDay ?? 1
        let title = d.days.first(where: { $0.dayNumber == n })?.title
        let named = title.map { "Day \(n) — \($0)" } ?? "Day \(n)"
        return "Finish \(named) first, and this one opens.\n\nThese days build on each other, so the plan waits for you rather than running ahead. One day at a time is the whole point."
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
            ? (allDone ? "Read again" : "Continue · Day \(target?.dayNumber ?? 1)")
            : "Begin Day 1"
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
            Button {
                Haptics.tap()
                Task { await startReadWithFriendInvite(d) }
            } label: {
                HStack(spacing: 6) {
                    if invitingBusy { ProgressView().tint(PL.navy) } else { Icon(.share2, size: 15, color: PL.navy) }
                    Text("Invite").font(.inter(13, .semibold)).foregroundStyle(PL.navy)
                }
                .frame(minHeight: 48).padding(.horizontal, 16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .disabled(invitingBusy)
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .padding(.bottom, 8)
        .background(Color.white.overlay(alignment: .top) { Rectangle().fill(PL.border).frame(height: 1) })
        .alert("Couldn't send that invite", isPresented: Binding(get: { inviteError != nil }, set: { if !$0 { inviteError = nil } })) {
            Button("OK") { inviteError = nil }
        } message: {
            Text(inviteError ?? "")
        }
    }

    /// Real Read-with-a-Friend invite (spec §6, replacing the old text-only
    /// ShareLink): create-or-get MY shared group for this plan, mint a fresh
    /// open-link invite, and hand the public /join/{token} URL + a rich
    /// message to the system share sheet (WhatsApp/social/copy — one URL,
    /// every channel).
    private func startReadWithFriendInvite(_ d: ReadingPlanDetail) async {
        guard !invitingBusy else { return }
        invitingBusy = true
        defer { invitingBusy = false }
        do {
            let group = try await MemberAPI.createOrGetReadingGroup(planId: d.planId)
            let invite = try await MemberAPI.createReadingInvite(groupId: group.groupId)
            let url = MemberAPI.readingJoinURL(token: invite.token)
            let message = readingInviteMessage(planTitle: d.title, dayCount: d.dayCount, joinUrl: url)
            Haptics.success()
            presentSystemShareSheet([message])
        } catch {
            Haptics.error()
            inviteError = (error as? APIError)?.errorDescription ?? "Check your connection and try again."
        }
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
// sticky gold "Mark day complete" bar that celebrates with a native rocket-
// and-burst fireworks show. The mock's prev/next-day arrows are still omitted
// (the day ref carries no sibling days).
struct PlanDayView: View {
    let ref: PlanDayRef
    @StateObject private var vm: PlanDayViewModel
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var justDone = false
    @State private var showKeepsake = false
    @AppStorage("readerNight") private var readerNight = false
    private var pal: ReaderPalette { ReaderPalette(night: readerNight) }

    init(ref: PlanDayRef) {
        self.ref = ref
        _vm = StateObject(wrappedValue: PlanDayViewModel(ref: ref))
    }

    /// The day's parts in the STUDY flow: watch/listen first (media sets the
    /// scene), then the Word (Scripture), the teaching (Devotional), the
    /// conversation (Talk it Over), the prayer, and Go Deeper for the hungry.
    /// Stable within ranks (DB sort breaks ties), so authored order is respected.
    private var segments: [PlanSegment] {
        (ref.day.segments ?? []).sorted { rank($0) == rank($1) ? $0.sort < $1.sort : rank($0) < rank($1) }
    }
    private func rank(_ s: PlanSegment) -> Int {
        switch s.kind.lowercased() {
        case "video", "audio": return 0
        case "scripture": return 1
        case "talk": return 3
        case "reading": return 5
        default: return s.title.lowercased().hasPrefix("pray") ? 4 : 2   // Pray after Talk; teaching before
        }
    }
    private var progress: Double {
        if vm.dayCompleted { return 1 }
        guard !segments.isEmpty else { return 0 }
        return Double(vm.completedSegments.count) / Double(segments.count)
    }


    // Open a day -> the DAY HUB: the big day numeral, then the day's parts as
    // tappable rows in the study flow (Watch/Listen -> Scripture -> Devotional ->
    // Talk it Over -> Prayer -> Go Deeper). Each part reads on its own focused
    // page and ticks here on return; "Mark day complete" seals the day.
    var body: some View {
        ZStack {
            pal.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        dayHeader
                        VStack(alignment: .leading, spacing: 10) {
                            Text("TODAY'S JOURNEY · \(hubParts.count) PART\(hubParts.count == 1 ? "" : "S")")
                                .font(.inter(11, .bold)).kerning(1.8).foregroundStyle(pal.goldDeep)
                            ForEach(hubParts) { part in
                                partLink(part) { partRow(part) }
                            }
                            walkStrip
                            reminderRow
                            DayEncouragement().padding(.top, 2)
                        }
                        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 24)
                    }
                }
                footerBar
            }
            if justDone { FireworksCelebration().ignoresSafeArea().allowsHitTesting(false) }
        }
        .ignoresSafeArea(edges: .top)
        .environment(\.readerPalette, pal)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showKeepsake) {
            PlanKeepsakeView(planTitle: ref.planTitle ?? ref.day.title ?? "your plan",
                             days: ref.day.dayNumber) { showKeepsake = false; dismiss() }
        }
        .onAppear { tabs.chromeHidden = true }
        .task { if walkDays == nil { walkDays = (try? await MemberAPI.achievements())?.streak?.current } }
        // A part finished in its reader ticks its row the moment we return.
        .onReceive(NotificationCenter.default.publisher(for: .nuruPlanPartDone)) { note in
            if let id = note.object as? String {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    _ = vm.completedSegments.insert(id)
                }
            }
        }
        // The offline-sync race: the day unlocks server-side the moment the
        // LAST segment's completion lands, but if the member taps straight
        // through, the day hub would otherwise still be waiting on an
        // explicit "Seal the day" tap. Trust the segment's own authoritative
        // ack (computed in the same transaction as the write) directly —
        // "Continue the plan" works immediately, with no extra tap and no
        // race against a re-fetch.
        .onReceive(NotificationCenter.default.publisher(for: .nuruPlanDayUnlocked)) { note in
            guard let ack = note.object as? PlanDayUnlockAck,
                  ack.dayNumber == ref.day.dayNumber,
                  ack.planId == nil || ack.planId == ref.planId else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { vm.dayCompleted = true }
        }
    }

    // MARK: grouped parts — Watch/Listen · The Word · Respond

    struct HubPart: Identifiable {
        let id: String
        let tag: String            // "media" | "word" | "respond"
        let label: String
        let icon: Lucide
        let segs: [PlanSegment]
        let firstIndex: Int
    }

    /// The day distilled into a story arc: media first (when the day has it),
    /// then THE WORD (Scripture woven into the teaching, Go Deeper folded in),
    /// then RESPOND (Talk it Over + Prayer + Reflection together).
    private var hubParts: [HubPart] {
        let segs = segments
        var parts: [HubPart] = []
        for (i, s) in segs.enumerated() where rank(s) == 0 {
            let audio = s.kind.lowercased() == "audio"
            parts.append(HubPart(id: s.segmentId, tag: "media",
                                 label: audio ? "Listen" : "Watch",
                                 icon: .play, segs: [s], firstIndex: i))
        }
        let word = segs.enumerated().filter { [1, 2, 5].contains(rank($0.element)) }
        if let f = word.first {
            parts.append(HubPart(id: "word", tag: "word", label: "The Word",
                                 icon: .bookOpen, segs: word.map(\.element), firstIndex: f.offset))
        }
        let respond = segs.enumerated().filter { rank($0.element) == 4 }
        if let f = respond.first {
            parts.append(HubPart(id: "respond", tag: "respond", label: "Respond",
                                 icon: .handHeart, segs: respond.map(\.element), firstIndex: f.offset))
        }
        // Talk it Over stands alone — the family's shared conversation.
        let talk = segs.enumerated().filter { rank($0.element) == 3 }
        if let f = talk.first {
            parts.append(HubPart(id: "talk", tag: "talk", label: "Talk it Over",
                                 icon: .messageCircle, segs: talk.map(\.element), firstIndex: f.offset))
        }
        return parts
    }

    /// The day's talk questions, joined — seeds the conversation page prompt.
    private var talkPromptFull: String {
        let qs = segments.filter { rank($0) == 3 }.compactMap(\.content).joined(separator: "\n")
        return qs.isEmpty ? "What is God saying to you through today's reading?" : qs
    }

    private func isDone(_ part: HubPart) -> Bool {
        part.segs.allSatisfy { vm.completedSegments.contains($0.segmentId) || $0.completed }
    }
    private var nextPart: HubPart? { hubParts.first(where: { !isDone($0) }) }
    private var nextPartId: String? { nextPart?.id }

    /// The one way into a part — used by both the row and the footer CTA, so the
    /// gold button can only ever carry you INTO the work, never around it.
    @ViewBuilder
    private func partLink<Content: View>(_ part: HubPart, @ViewBuilder label: () -> Content) -> some View {
        if part.tag == "talk" {
            NavigationLink(value: TalkRoute(planId: ref.planId,
                                            dayNumber: ref.day.dayNumber,
                                            planTitle: ref.planTitle ?? ref.day.title ?? "Reading plan",
                                            prompt: talkPromptFull,
                                            talkSegmentId: part.segs.first?.segmentId,
                                            talkDone: isDone(part))) {
                label()
            }
            .buttonStyle(.pressable)
        } else {
            NavigationLink(value: PlanSegmentRef(planTitle: ref.planTitle ?? ref.day.title ?? "Reading plan",
                                                 dayNumber: ref.day.dayNumber,
                                                 segments: segments,
                                                 index: part.firstIndex,
                                                 planId: ref.planId,
                                                 part: part.tag,
                                                 doneIds: Array(vm.completedSegments))) {
                label()
            }
            .buttonStyle(.pressable)
        }
    }

    private func partRow(_ part: HubPart) -> some View {
        let done = isDone(part)
        let isNext = part.id == nextPartId && !done
        return HStack(spacing: 12) {
            Icon(part.icon, size: 16, color: (done || isNext) ? pal.goldDeep : pal.inkDim)
                .frame(width: 42, height: 42)
                .background((done || isNext) ? pal.gold.opacity(0.15) : pal.inkDim.opacity(0.07), in: Circle())
                .overlay(Circle().stroke(done ? pal.gold.opacity(0.5) : (isNext ? pal.gold.opacity(0.4) : pal.border), lineWidth: 1))
            VStack(alignment: .leading, spacing: 2) {
                Text(part.label).font(.inter(14, .semibold)).foregroundStyle(pal.ink)
                Text(partSub(part)).font(.inter(11)).foregroundStyle(done ? pal.goldDeep : pal.inkDim).lineLimit(1)
            }
            Spacer(minLength: 8)
            if done {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(pal.gold)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            } else if isNext {
                Text("Next").font(.inter(10, .bold)).foregroundStyle(PL.navy)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(pal.gold, in: Capsule())
            } else {
                Image(systemName: "circle").font(.system(size: 20)).foregroundStyle(pal.inkDim.opacity(0.35))
            }
        }
        .padding(14)
        .background(pal.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(isNext ? pal.gold.opacity(0.35) : pal.border, lineWidth: 1))
    }

    private func partSub(_ part: HubPart) -> String {
        if isDone(part) { return "Completed" }
        switch part.tag {
        case "media":
            return part.label == "Listen" ? "Today's word + key takeaways" : "Begin with today's video"
        case "word":
            let r = part.segs.first(where: { $0.kind.lowercased() == "scripture" })?.reference
            return r.map { "\($0) · Scripture & teaching" } ?? "Scripture & teaching"
        case "talk":
            return "The family's conversation on today's word"
        default:
            return "Prayer · your reflection"
        }
    }

    // MARK: what we've built, woven in — the walk (streak) + the daily reminder

    @AppStorage("streakQuiet") private var streakQuiet = false
    @AppStorage("planReminderOn") private var reminderOn = false
    @AppStorage("planReminderHour") private var reminderHour = 7
    @AppStorage("planReminderMinute") private var reminderMinute = 0
    @State private var walkDays: Int?

    @ViewBuilder private var walkStrip: some View {
        if !streakQuiet, let days = walkDays, days > 0 {
            HStack(spacing: 8) {
                PLFlame()
                Text(days == 1 ? "1 day with God" : "\(days) days with God")
                    .font(.inter(12, .bold)).foregroundStyle(pal.ink)
                Text("· grace covers missed days").font(.inter(11)).foregroundStyle(pal.inkDim)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(pal.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var reminderRow: some View {
        HStack(spacing: 10) {
            Icon(.bell, size: 14, color: pal.goldDeep)
                .frame(width: 32, height: 32)
                .background(pal.gold.opacity(0.12), in: Circle())
            Text(reminderOn
                 ? String(format: "Daily reminder · %d:%02d", reminderHour, reminderMinute)
                 : "Set a daily reminder")
                .font(.inter(12, .semibold)).foregroundStyle(pal.ink)
            Spacer(minLength: 8)
            Toggle("", isOn: $reminderOn).labelsHidden().tint(pal.gold)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(pal.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(pal.border, lineWidth: 1))
        .onChange(of: reminderOn) { _, _ in
            PlanReminders.schedule(enabled: reminderOn, hour: reminderHour, minute: reminderMinute,
                                   planTitle: ref.planTitle ?? ref.day.title, day: ref.day.dayNumber)
        }
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
                if let pt = ref.planTitle, !pt.isEmpty {
                    Text(pt.uppercased()).font(.inter(10, .bold)).kerning(1.8).foregroundStyle(PL.gold)
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.25)) { readerNight.toggle() }
                } label: {
                    Icon(readerNight ? .sun : .moon, size: 17, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(readerNight ? "Day mode" : "Night mode")
            }
            // The DAY is the hero — a large serif numeral that stays prominent
            // whatever the read-state, beside the day's title + reference.
            HStack(alignment: .center, spacing: 14) {
                VStack(spacing: -4) {
                    Text("DAY").font(.inter(9, .bold)).kerning(1.6).foregroundStyle(PL.gold)
                    Text("\(ref.day.dayNumber)")
                        .font(.fraunces(40, .medium)).kerning(-1.2).foregroundStyle(.white)
                        .monospacedDigit()
                }
                .frame(minWidth: 52)
                Rectangle().fill(PL.gold.opacity(0.5)).frame(width: 1, height: 44)
                VStack(alignment: .leading, spacing: 3) {
                    Text(ref.day.title ?? "Reading & reflection")
                        .font(.fraunces(21, .medium)).kerning(-0.6).foregroundStyle(.white)
                        .lineLimit(2).minimumScaleFactor(0.85)
                    Text(ref.day.reference).font(.inter(11)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
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

    // MARK: sticky footer — mark complete → fireworks → tap to go back

    private var footerBar: some View {
        VStack(spacing: 8) {
            if !vm.dayCompleted && !justDone {
                let read = hubParts.filter(isDone).count
                Text(read >= hubParts.count && !hubParts.isEmpty
                     ? "All parts read — seal the day"
                     : "\(read) of \(hubParts.count) part\(hubParts.count == 1 ? "" : "s") read")
                    .font(.inter(11, .semibold))
                    .foregroundStyle(read >= hubParts.count && !hubParts.isEmpty ? PL.goldDeep : PL.ink3)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
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
            } else if let next = nextPart {
                // A day is finished by DOING it, not by declaring it. While a part
                // is still unread the gold button is the way into that part — it
                // no longer offers to seal a day nobody has walked. (The server
                // refuses that too: 409 CONTENT_INCOMPLETE.)
                partLink(next) {
                    HStack(spacing: 8) {
                        Icon(next.icon, size: 16, color: PL.navy)
                        Text("Continue · \(next.label)").font(.inter(14, .bold)).foregroundStyle(PL.navy)
                        Icon(.arrowRight, size: 15, color: PL.navy)
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: PL.gold.opacity(0.45), radius: 10, y: 8)
                }
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
                        Text("Seal the day").font(.inter(14, .bold)).foregroundStyle(PL.navy)
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

// MARK: - Fireworks celebration ("real fireworks, not paper cuts", ~5s)

/// The day-seal ceremony: 3–4 staggered rockets rise from the bottom third of
/// the screen on a fading streak, then burst into two dozen-plus radial
/// sparks that arc under a light gravity pull and leave their own fading
/// trail behind — one soft "pop" timed to each burst. A single Canvas +
/// TimelineView(.animation) draws every rocket and spark (no per-particle
/// views) so this stays 60fps-friendly. Reduce Motion swaps the whole thing
/// for a static golden glow and skips sound entirely. Purely decorative —
/// never blocks touches.
private struct FireworksCelebration: View {
    var duration: Double = 5.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?

    private let rockets: [Rocket]

    /// A spark's fixed flight plan, resolved against its parent rocket's
    /// burst time + center each frame.
    private struct SparkSeed {
        let angle: Double        // radians, 0...2π around the burst center
        let reach: Double        // radial travel, as a fraction of min(width, height)
        let size: Double         // point diameter at the glowing head
        let color: Color
        let lifeScale: Double    // slight per-spark variance so the burst doesn't die all at once
    }

    private struct Rocket: Identifiable {
        let id: Int
        let x: Double            // 0...1, launch/burst x (kept fixed — real rockets fly straight up)
        let burstY: Double       // 0...1 from the top — where the streak ends and the burst begins
        let t0: Double           // launch time, seconds from celebration start
        let riseDuration: Double
        let color: Color
        let sparks: [SparkSeed]
    }

    // Golds the brand leans on + white + one warm accent — legible on the
    // navy day header and the cream body alike.
    private static let gold = Color(hex: 0xC89B3C)
    private static let goldLight = Color(hex: 0xE0B85E)
    private static let cream = Color(hex: 0xFFF4C7)
    private static let accent = Color(hex: 0xFB7185)   // one accent spark color, used sparingly
    private static let palette: [Color] = [gold, gold, goldLight, goldLight, cream, .white, accent]

    private static let sparkLife = 1.25   // seconds a spark stays visible once it bursts

    init(duration: Double = 5.0) {
        self.duration = duration
        let count = Int.random(in: 3...4)
        var built: [Rocket] = []
        var t0 = 0.0
        for i in 0..<count {
            let riseDuration = Double.random(in: 0.45...0.62)
            let color = Self.palette.randomElement()!
            let sparkCount = Int.random(in: 24...40)
            var seeds: [SparkSeed] = []
            for s in 0..<sparkCount {
                let angle = (Double(s) / Double(sparkCount)) * (2 * .pi) + .random(in: -0.06...0.06)
                seeds.append(SparkSeed(angle: angle,
                                        reach: .random(in: 0.16...0.30),
                                        size: .random(in: 3...6.5),
                                        color: Self.palette.randomElement()!,
                                        lifeScale: .random(in: 0.85...1.15)))
            }
            built.append(Rocket(id: i, x: .random(in: 0.2...0.8), burstY: .random(in: 0.16...0.42),
                                 t0: t0, riseDuration: riseDuration, color: color, sparks: seeds))
            // Stagger the next launch so its burst still has room to fade
            // out before the ~5s ceremony retires (host view tears this down
            // at 5.3s — see PlanDayView.footerButton).
            t0 += Double.random(in: 0.8...1.05)
        }
        rockets = built
    }

    var body: some View {
        Group {
            if reduceMotion {
                staticGlow
            } else {
                fireworks
            }
        }
        .allowsHitTesting(false)
    }

    // Reduce Motion: no rise, no burst, no sound — just a gentle golden
    // presence that confirms "something good just happened".
    private var staticGlow: some View {
        RadialGradient(colors: [Self.cream.opacity(0.5), Self.gold.opacity(0.18), .clear],
                       center: .center, startRadius: 8, endRadius: 280)
            .transition(.opacity)
    }

    private var fireworks: some View {
        TimelineView(.animation) { tl in
            Canvas { ctx, size in
                let t = start.map { tl.date.timeIntervalSince($0) } ?? 0
                ctx.blendMode = .plusLighter   // additive glow — sparks brighten where they overlap
                for rocket in rockets {
                    draw(rocket, into: ctx, size: size, t: t)
                }
            }
        }
        .onAppear {
            start = Date()
            FireworksSound.shared.prepareIfNeeded()
            playPopsTimedToBursts()
        }
    }

    /// One background task walks the rocket list, sleeping only the delta to
    /// each burst moment, and fires a pop right as the sparks appear.
    private func playPopsTimedToBursts() {
        let plan = rockets.map { ($0.id, $0.t0 + $0.riseDuration) }
        Task {
            var elapsed = 0.0
            for (id, burstTime) in plan {
                let delta = burstTime - elapsed
                if delta > 0 {
                    try? await Task.sleep(nanoseconds: UInt64((delta * 1_000_000_000).rounded()))
                }
                elapsed = max(elapsed, burstTime)
                FireworksSound.shared.pop(id)
            }
        }
    }

    private func draw(_ rocket: Rocket, into ctx: GraphicsContext, size: CGSize, t: Double) {
        guard t >= rocket.t0 else { return }
        let burstTime = rocket.t0 + rocket.riseDuration
        let minDim = min(size.width, size.height)

        if t < burstTime {
            drawRisingStreak(rocket, into: ctx, size: size, t: t, burstTime: burstTime)
            return
        }

        let bt = t - burstTime
        guard bt <= Self.sparkLife * 1.3 else { return }   // slowest sparks retire a touch later

        // A quick bright flash at the moment of ignition — the "boom".
        if bt < 0.12 {
            let center = CGPoint(x: rocket.x * size.width, y: rocket.burstY * size.height)
            let flashAlpha = 1 - bt / 0.12
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - 46, y: center.y - 46, width: 92, height: 92)),
                     with: .radialGradient(Gradient(colors: [.white.opacity(0.85 * flashAlpha), rocket.color.opacity(0)]),
                                            center: center, startRadius: 0, endRadius: 46))
        }

        let center = CGPoint(x: rocket.x * size.width, y: rocket.burstY * size.height)
        for seed in rocket.sparks {
            drawSpark(seed, center: center, minDim: minDim, bt: bt, into: ctx)
        }
    }

    /// The rising rocket: a short gradient-stroked streak fading to nothing
    /// at its tail, climbing from just under the screen to the burst point.
    private func drawRisingStreak(_ rocket: Rocket, into ctx: GraphicsContext, size: CGSize, t: Double, burstTime: Double) {
        let p = max(0, min(1, (t - rocket.t0) / rocket.riseDuration))
        let launchY = 1.06
        let headY = launchY + (rocket.burstY - launchY) * p
        let tailP = max(0, p - 0.11)
        let tailY = launchY + (rocket.burstY - launchY) * tailP
        let x = rocket.x * size.width

        let head = CGPoint(x: x, y: headY * size.height)
        let tail = CGPoint(x: x, y: tailY * size.height)
        var path = Path()
        path.move(to: tail)
        path.addLine(to: head)
        ctx.stroke(path, with: .linearGradient(Gradient(colors: [rocket.color.opacity(0), rocket.color.opacity(0.95)]),
                                                startPoint: tail, endPoint: head),
                    style: StrokeStyle(lineWidth: 3, lineCap: .round))
        // A small bright ember at the very tip.
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - 2.5, y: head.y - 2.5, width: 5, height: 5)),
                  with: .color(.white.opacity(0.9)))
    }

    /// One radial spark: outward travel that decelerates, a slight downward
    /// gravity pull that grows with time (so late in life it visibly arcs),
    /// and a short fading trail (gradient stroke) behind the glowing head.
    private func drawSpark(_ seed: SparkSeed, center: CGPoint, minDim: CGFloat, bt: Double, into ctx: GraphicsContext) {
        let life = Self.sparkLife * seed.lifeScale
        guard bt >= 0, bt <= life else { return }
        let lifeT = bt / life

        func position(atLifeT lt: Double) -> CGPoint {
            let clamped = max(0, min(1, lt))
            let outEase = 1 - pow(1 - clamped, 2)          // fast start, decelerating outward push
            let radial = seed.reach * outEase
            let gravity = 0.16 * clamped * clamped          // slight pull, compounding late in life
            let dx = cos(seed.angle) * radial
            let dy = sin(seed.angle) * radial + gravity
            return CGPoint(x: center.x + dx * minDim, y: center.y + dy * minDim)
        }

        let fadeOut = lifeT > 0.7 ? max(0, 1 - (lifeT - 0.7) / 0.3) : 1
        guard fadeOut > 0.02 else { return }

        let head = position(atLifeT: lifeT)
        let tail = position(atLifeT: bt / life - 0.09 / life)

        var trail = Path()
        trail.move(to: tail)
        trail.addLine(to: head)
        ctx.stroke(trail, with: .linearGradient(Gradient(colors: [seed.color.opacity(0), seed.color.opacity(0.8 * fadeOut)]),
                                                 startPoint: tail, endPoint: head),
                   style: StrokeStyle(lineWidth: seed.size * 0.5, lineCap: .round))

        // Glowing head — a soft radial fade reads as an additive spark rather
        // than a flat dot.
        let glowSize = seed.size * 2.2
        ctx.fill(Path(ellipseIn: CGRect(x: head.x - glowSize / 2, y: head.y - glowSize / 2, width: glowSize, height: glowSize)),
                  with: .radialGradient(Gradient(colors: [.white.opacity(0.9 * fadeOut), seed.color.opacity(0.55 * fadeOut), seed.color.opacity(0)]),
                                        center: head, startRadius: 0, endRadius: glowSize / 2))
    }
}

// MARK: - Firework "pop" sound (ambient, silent-switch aware)

/// Three short pop WAVs, played one per burst. AVAudioSession category
/// `.ambient` is the whole point here — it's the one category that RESPECTS
/// the silent switch, so a decorative sound effect never talks over a
/// member who has their phone silenced. Players are loaded off the main
/// thread the first time a celebration appears; nothing here ever blocks UI.
@MainActor
private final class FireworksSound {
    static let shared = FireworksSound()
    private var players: [AVAudioPlayer] = []
    private var preparing = false

    func prepareIfNeeded() {
        guard !preparing, players.isEmpty else { return }
        preparing = true
        Task.detached(priority: .utility) {
            try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            var loaded: [AVAudioPlayer] = []
            for name in ["pop1", "pop2", "pop3"] {
                guard let url = Bundle.main.url(forResource: name, withExtension: "wav"),
                      let player = try? AVAudioPlayer(contentsOf: url) else { continue }
                player.volume = 0.5
                player.prepareToPlay()
                loaded.append(player)
            }
            await MainActor.run { FireworksSound.shared.players = loaded }
        }
    }

    /// Fire the pop for burst `index` (rotates through the three players so
    /// back-to-back bursts don't cut each other's tail off).
    func pop(_ index: Int) {
        guard !players.isEmpty else { return }
        let player = players[index % players.count]
        if player.isPlaying { player.stop(); player.currentTime = 0 }
        player.play()
    }
}

// MARK: - Day reader section components (single-scroll reading)

/// The day's passage/verse — same shared VerseQuoteCard every scripture quote
/// in the app uses, tinted for the reader's day/night palette.
struct DayPullQuote: View {
    let text: String; let caption: String
    @Environment(\.readerPalette) private var pal
    var body: some View {
        VerseQuoteCard(
            verse: text, reference: caption,
            background: pal.verseBg, ink: pal.ink, gold: pal.gold, referenceColor: pal.inkDim
        )
    }
}

/// Serif teaching split into paragraphs on blank lines. Generous size + line
/// height + inter-paragraph gap for comfortable, unhurried reading.
struct DayPassage: View {
    let content: String
    @Environment(\.readerPalette) private var pal
    private var paragraphs: [String] {
        content.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, p in
                Text(p).font(.inter(16, .medium)).foregroundStyle(pal.ink).nuruLineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Talk-it-over questions on a white card.
struct DayTalk: View {
    let prompt: String
    @Environment(\.readerPalette) private var pal
    private var questions: [String] {
        prompt.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .map { $0.hasPrefix("—") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(questions.enumerated()), id: \.offset) { _, q in
                HStack(alignment: .top, spacing: 8) {
                    Icon(.messageCircle, size: 13, color: pal.goldDeep).padding(.top, 3)
                    Text(q).font(.fraunces(16, .regular)).italic().foregroundStyle(pal.ink).nuruLineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.border, lineWidth: 1))
    }
}

/// Prayer on a warm gold tint, with an italic closing blessing (`_…_`).
struct DayPrayer: View {
    let text: String
    @Environment(\.readerPalette) private var pal
    private var lines: [String] { text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
    private var blessing: String? {
        guard let last = lines.last, last.hasPrefix("_"), last.hasSuffix("_"), last.count > 2 else { return nil }
        return String(last.dropFirst().dropLast())
    }
    private var prayer: String { (blessing == nil ? lines : Array(lines.dropLast())).joined(separator: "\n\n") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !prayer.isEmpty {
                Text(prayer).font(.fraunces(16, .regular)).foregroundStyle(pal.ink).nuruLineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let b = blessing {
                Text(b).font(.fraunces(14)).italic().foregroundStyle(pal.goldDeep)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.gold.opacity(0.09), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.gold.opacity(0.22), lineWidth: 1))
    }
}

/// Compact Go Deeper references row.
struct DayGoDeeper: View {
    let refs: String
    @Environment(\.readerPalette) private var pal
    var body: some View {
        HStack(spacing: 10) {
            Icon(.bookOpen, size: 15, color: pal.goldDeep)
            Text(refs).font(.inter(13, .medium)).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.gold.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Sign-off line on a soft gold tint.
struct DayEncouragement: View {
    @Environment(\.readerPalette) private var pal
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Icon(.handHeart, size: 16, color: pal.gold)
            Text("Every faithful day adds up. There's no rush — just presence.")
                .font(.nCardBody).foregroundStyle(pal.ink).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(pal.gold.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// Inline 16:9 video card — tap opens the player window over the day content.
struct DayVideoCard: View {
    let seg: PlanSegment
    var portrait: Bool = false
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
        .aspectRatio(portrait ? 9.0 / 15.0 : 16.0 / 9.0, contentMode: .fit)
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
            FireworksCelebration().ignoresSafeArea().allowsHitTesting(false)
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
                Text(planTitle).font(.fraunces(30, .medium)).kerning(-0.9).foregroundStyle(PL.navy)
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
            Text(planTitle).font(.fraunces(26, .medium)).kerning(-0.52).foregroundStyle(PL.navy).multilineTextAlignment(.center)
            Text("\(days) days walking with God").font(.inter(13, .medium)).foregroundStyle(PL.ink2)
            Text("NURU PATHWAY").font(.inter(11, .bold)).kerning(1.8).foregroundStyle(PL.goldDeep).padding(.top, 8)
        }
        .padding(40)
        .frame(width: 400, height: 400)
        .background(PL.cream)
    }
}
