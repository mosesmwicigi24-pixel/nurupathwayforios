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
    @State private var query = ""
    @State private var category = "all"

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
        .task { if vm.plans.isEmpty { await vm.load() } }
    }

    private var listBody: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                LoadStateView(loading: vm.loading && vm.plans.isEmpty,
                              isEmpty: vm.plans.isEmpty, error: vm.error,
                              emptyText: "No reading plans yet.", retry: { Task { await vm.load() } }) {
                    VStack(alignment: .leading, spacing: 24) {
                        if !searching { PLStreakStrip(count: vm.streak, todayDone: vm.todayWordDone) }
                        if !searching, !continueReading.isEmpty { continueSection }
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
        VStack(alignment: .leading, spacing: 10) {
            overline("Continue reading")
            ForEach(continueReading) { plan in
                NavigationLink(value: plan) { PLContinueRow(plan: plan) }.buttonStyle(.pressable)
            }
        }
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
        .ignoresSafeArea(edges: [.top, .bottom])
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
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
                    NavigationLink(value: PlanDayRef(planId: d.planId, day: target)) { ctaLabel(label) }
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
        .padding(.bottom, Nuru.tabBarSpace)
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
            try await MemberAPI.completePlanDay(planId, dayNumber: dayNumber)
            dayCompleted = true
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
    @Environment(\.dismiss) private var dismiss
    @State private var justDone = false

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

    var body: some View {
        ZStack {
            PL.cream.ignoresSafeArea()
            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        dayHeader
                        VStack(alignment: .leading, spacing: 16) {
                            scriptureCard
                            segmentsSection
                            reflectionCard
                        }
                        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 24)
                    }
                }
                footerBar
            }
            if justDone { PLConfettiBurst().ignoresSafeArea() }
        }
        .ignoresSafeArea(edges: [.top, .bottom])
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { await vm.loadReflection() }
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

    // MARK: scripture / day content card

    @ViewBuilder
    private var scriptureCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Icon(.bookOpen, size: 12, color: PL.refInk)
                Text(ref.day.reference.uppercased()).font(.nCardKicker).kerning(1.4).foregroundStyle(PL.refInk)
            }
            if let content = ref.day.content, !content.isEmpty {
                Text(content)
                    .font(.fraunces(17)).italic().foregroundStyle(PL.navy).kerning(-0.17)
                    .lineSpacing(8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(PL.highlight, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.gold.opacity(0.25), lineWidth: 1))
    }

    // MARK: segments (real day flow → PlanSegmentView)

    private var segmentsSection: some View {
        // PlanDayRef carries no plan title, so fall back to the day title.
        let planTitle = ref.day.title ?? "Reading plan"
        let nextId = vm.dayCompleted ? nil : segments.first(where: { !vm.completedSegments.contains($0.segmentId) })?.segmentId
        let startIdx = segments.firstIndex(where: { !vm.completedSegments.contains($0.segmentId) }) ?? 0
        let started = !vm.completedSegments.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Text("WORK THROUGH TODAY").font(.nCardKicker).kerning(1.4).foregroundStyle(PL.goldDeep)
            // One tap into the whole day — the reader now flows every part in a
            // single scroll, so this opens (or resumes) the day's reading.
            NavigationLink(value: PlanSegmentRef(planTitle: planTitle,
                                                 dayNumber: ref.day.dayNumber,
                                                 segments: segments,
                                                 index: startIdx)) {
                HStack(spacing: 8) {
                    Icon(.bookOpen, size: 15, color: PL.navy)
                    Text(started ? "Continue reading" : "Start reading")
                        .font(.inter(14, .bold)).foregroundStyle(PL.navy)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.top, 12)
            VStack(spacing: 6) {
                ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                    NavigationLink(value: PlanSegmentRef(planTitle: planTitle,
                                                         dayNumber: ref.day.dayNumber,
                                                         segments: segments,
                                                         index: idx)) {
                        PLSegmentRow(segment: seg,
                                     icon: segmentIcon(seg.kind),
                                     done: vm.completedSegments.contains(seg.segmentId),
                                     isNext: seg.segmentId == nextId)
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
                    .font(.inter(13)).foregroundStyle(PL.navy).tint(PL.gold)
                    .padding(.horizontal, 14).padding(.vertical, 12)
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
        .padding(.bottom, Nuru.tabBarSpace)
        .background(Color.white.overlay(alignment: .top) { Rectangle().fill(PL.border).frame(height: 1) })
    }

    @ViewBuilder private var footerButton: some View {
        HStack {
            if vm.dayCompleted || justDone {
                Button { dismiss() } label: {
                    Text("Day complete 🎉").font(.inter(14, .bold)).foregroundStyle(PL.navy)
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
                            Haptics.success() // land the confetti with a felt "done"
                            // No withAnimation here — inserting the burst inside a
                            // transaction coalesced its flight to the end state
                            // (confetti never visibly fired). It animates itself.
                            justDone = true
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
        .padding(.horizontal, 20).padding(.top, 12)
        .padding(.bottom, Nuru.tabBarSpace)
        .background(Color.white.overlay(alignment: .top) { Rectangle().fill(PL.border).frame(height: 1) })
    }
}
