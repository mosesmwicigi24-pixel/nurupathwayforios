// Plans tab — rebuilt line-by-line from the Figma Make source of truth
// (components/PlansTab.tsx). A reading-plan discovery page: navy-gradient header
// with a search field, a "Continue reading" progress list, a "Plan of the day"
// hero, topic pills, horizontal collection carousels (or a filtered grid while
// searching), and a "Read with a friend" invite. Exact Figma palette; bound to
// the real ReadingPlanRow catalogue. The plan-detail day list (PlanDetailView /
// PlanDayView) below is unchanged and reached via the existing navigation.
import SwiftUI

// Exact Figma palette (PlansTab.tsx) — kept local so the page is 1:1 with the design.
private enum PL {
    static let navy      = Color(hex: 0x0A2540)
    static let navyDeep  = Color(hex: 0x081C36)
    static let gold      = Color(hex: 0xC9A227)
    static let goldLight = Color(hex: 0xE6C068)
    static let goldDeep  = Color(hex: 0xA8861C)
    static let cream     = Color(hex: 0xF4F0E8)
    static let creamLo   = Color(hex: 0xF1ECE1)
    static let surface   = Color(hex: 0xFBF8F1)
    static let border    = Color(hex: 0x0A2540, alpha: 0.08)
    static let ink2      = Color(hex: 0x68758A)
    static let ink3      = Color(hex: 0x9CA3AF)
    static let catText   = Color(hex: 0x9A7A2A)
    static let blurb     = Color(hex: 0x3A4A5F)
}

// MARK: - Plans list (discovery)

@MainActor
final class ReadingPlansViewModel: ObservableObject {
    @Published var plans: [ReadingPlanRow] = []
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        do { plans = try await MemberAPI.plans() }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load reading plans." }
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

    // MARK: header (navy gradient + search)

    private var header: some View {
        ZStack(alignment: .topTrailing) {
            RadialGradient(colors: [PL.gold.opacity(0.33), .clear], center: .center, startRadius: 0, endRadius: 120)
                .frame(width: 224, height: 224).blur(radius: 40).offset(x: 40, y: -70)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("PLANS").font(.inter(9, .bold)).kerning(1.8).foregroundStyle(PL.goldLight)
                        Text("Grow in the Word").font(.fraunces(26, .semibold)).kerning(-0.52).foregroundStyle(.white)
                            .padding(.top, 4)
                        Text("A little every day — with the whole family of God.")
                            .font(.inter(12)).foregroundStyle(.white.opacity(0.6)).padding(.top, 4)
                    }
                    Spacer(minLength: 8)
                    ZStack(alignment: .topTrailing) {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.15), lineWidth: 1))
                        Icon(.bell, size: 18, color: .white)
                        Circle().fill(PL.gold).frame(width: 8, height: 8).offset(x: -8, y: 8)
                    }
                    .frame(width: 40, height: 40)
                }
                searchBar.padding(.top, 16)
            }
            .padding(.horizontal, 20)
            .padding(.top, 64)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(.rect(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
        .shadow(color: PL.navyDeep.opacity(0.55), radius: 22, y: 14)
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Icon(.search, size: 16, color: .white.opacity(0.45))
            ZStack(alignment: .leading) {
                if query.isEmpty {
                    Text("Search plans, topics, books…").font(.inter(14)).foregroundStyle(.white.opacity(0.40))
                }
                TextField("", text: $query)
                    .font(.inter(14)).foregroundStyle(.white).tint(PL.gold)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            if !query.isEmpty {
                Button { query = "" } label: { Icon(.x, size: 15, color: .white.opacity(0.45)) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    // MARK: continue reading

    private var continueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            overline("Continue reading")
            ForEach(continueReading) { plan in
                NavigationLink(value: plan) { PLContinueRow(plan: plan) }.buttonStyle(.plain)
            }
        }
    }

    // MARK: plan of the day

    private func planOfDayCard(_ plan: ReadingPlanRow) -> some View {
        NavigationLink(value: plan) {
            ZStack {
                PLCover(plan: plan)
                LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.25), Color(hex: 0x081424, alpha: 0.35), Color(hex: 0x081424, alpha: 0.90)],
                               startPoint: .top, endPoint: .bottom)
            }
            .frame(height: 192).frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .topLeading) {
                Text("PLAN OF THE DAY").font(.inter(9, .bold)).kerning(1.26).foregroundStyle(PL.navy)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(PL.gold, in: Capsule()).padding(14)
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(plan.title).font(.fraunces(22, .semibold)).kerning(-0.22).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 4) {
                        Icon(.clock, size: 12, color: .white.opacity(0.8))
                        Text("\(plan.dayCount) days").font(.inter(11)).foregroundStyle(.white.opacity(0.8))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 14)
            }
            .shadow(color: PL.navyDeep.opacity(0.5), radius: 22, y: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: categories

    private var categoriesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            overline("Browse by topic")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["all"] + categories, id: \.self) { c in
                        let on = category == c
                        Button { category = (category == c ? "all" : c) } label: {
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
                    Button { query = ""; category = "all" } label: {
                        Text("Clear filters").font(.inter(11, .bold)).foregroundStyle(PL.gold)
                    }.buttonStyle(.plain).padding(.top, 2)
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
                Text("Invite your cell to a plan and keep each other going.").font(.inter(11)).foregroundStyle(PL.ink2)
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

// MARK: - plan cover (image with brand-gradient fallback)

private struct PLCover: View {
    let plan: ReadingPlanRow
    var body: some View {
        ZStack {
            LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
            if let u = plan.imageUrl.flatMap(URL.init) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() } else { Color.clear }
                }
            }
        }
        .clipped()
    }
}

// MARK: - continue-reading row

private struct PLContinueRow: View {
    let plan: ReadingPlanRow
    private var total: Int { max(plan.dayCount, 1) }
    private var day: Int { plan.currentDay ?? ((plan.completedDays?.count ?? 0) + 1) }
    private var pct: Double { min(max(Double(day) / Double(total), 0), 1) }

    var body: some View {
        HStack(spacing: 12) {
            PLCover(plan: plan).frame(width: 56, height: 56).clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(plan.title).font(.inter(14, .bold)).kerning(-0.14).foregroundStyle(PL.navy).lineLimit(1)
                Text("Today · \(plan.subtitle ?? "Day \(day) of \(total)")").font(.inter(11)).foregroundStyle(PL.ink2).lineLimit(1)
                    .padding(.top, 2)
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(PL.navy.opacity(0.08))
                            Capsule().fill(PL.gold).frame(width: max(6, geo.size.width * pct))
                        }
                    }.frame(height: 6)
                    Text("Day \(day)/\(total)").font(.inter(9, .semibold)).foregroundStyle(PL.ink2)
                }
                .padding(.top, 8)
            }
            ZStack {
                Circle().fill(PL.gold.opacity(0.10))
                Icon(.play, size: 16, color: PL.gold)
            }
            .frame(width: 36, height: 36)
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(PL.border, lineWidth: 1))
        .shadow(color: PL.navy.opacity(0.10), radius: 10, y: 6)
    }
}

// MARK: - portrait plan card (collection carousels)

private struct PLPlanCard: View {
    let plan: ReadingPlanRow
    var body: some View {
        NavigationLink(value: plan) {
            ZStack(alignment: .bottomLeading) {
                PLCover(plan: plan)
                LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.05), Color(hex: 0x081424, alpha: 0.85)],
                               startPoint: .init(x: 0.5, y: 0.4), endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title).font(.fraunces(13, .semibold)).foregroundStyle(.white)
                        .lineLimit(2).multilineTextAlignment(.leading)
                    if let c = plan.category, !c.isEmpty {
                        Text(c.uppercased()).font(.inter(9, .bold)).kerning(0.9).foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(10)
            }
            .overlay(alignment: .topLeading) { daysBadge(plan.dayCount) }
            .frame(width: 150, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: PL.navy.opacity(0.5), radius: 14, y: 10)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - grid tile (search results)

private struct PLPlanTile: View {
    let plan: ReadingPlanRow
    var body: some View {
        NavigationLink(value: plan) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topLeading) {
                    PLCover(plan: plan).aspectRatio(16.0 / 10.0, contentMode: .fill).frame(maxWidth: .infinity).clipped()
                    daysBadge(plan.dayCount)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(plan.title).font(.inter(12, .bold)).foregroundStyle(PL.navy).lineLimit(2).multilineTextAlignment(.leading)
                    if let c = plan.category, !c.isEmpty {
                        Text(c.uppercased()).font(.inter(9, .bold)).kerning(0.9).foregroundStyle(PL.catText)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

@ViewBuilder
private func daysBadge(_ days: Int) -> some View {
    Text("\(days) DAYS").font(.inter(8, .bold)).kerning(0.96).foregroundStyle(PL.navy)
        .padding(.horizontal, 8).padding(.vertical, 2)
        .background(Color.white.opacity(0.9), in: Capsule())
        .padding(8)
}

// MARK: - Plan detail (days)

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

// Plan detail — rebuilt from the Figma PlanDetail slide-over: cover hero (back +
// save), category/title/meta, "About this plan", "What you'll read" day rows, a
// consistency nudge, and a sticky Start-plan / Invite bar.
struct PlanDetailView: View {
    let plan: ReadingPlanRow
    @StateObject private var vm: PlanDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var saved = false

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
                    Button("Try again") { Task { await vm.load() } }.foregroundStyle(PL.gold)
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task { if vm.detail == nil { await vm.load() } }
    }

    private func content(_ d: ReadingPlanDetail) -> some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    coverHero(d)
                    VStack(spacing: 16) {
                        aboutCard(d)
                        whatYoullRead(d)
                        nudge
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 20)
                }
            }
            ctaBar(d)
        }
    }

    private func coverHero(_ d: ReadingPlanDetail) -> some View {
        ZStack(alignment: .bottomLeading) {
            ZStack {
                LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let u = d.imageUrl.flatMap(URL.init) {
                    CachedAsyncImage(url: u) { p in (p.image ?? Image(systemName: "photo")).resizable().scaledToFill() }
                }
            }
            .frame(height: 264).frame(maxWidth: .infinity).clipped()
            .overlay(LinearGradient(colors: [Color(hex: 0x081424, alpha: 0.40), Color(hex: 0x081424, alpha: 0.10), Color(hex: 0x081424, alpha: 0.92)], startPoint: .top, endPoint: .bottom))

            VStack(alignment: .leading, spacing: 6) {
                if let c = d.category, !c.isEmpty {
                    Text(c.uppercased()).font(.inter(9, .bold)).kerning(1.26).foregroundStyle(PL.navy)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(PL.gold, in: Capsule())
                }
                Text(d.title).font(.fraunces(26, .semibold)).kerning(-0.52).foregroundStyle(.white)
                    .lineLimit(3).multilineTextAlignment(.leading)
                HStack(spacing: 16) {
                    heroMeta(.clock, "\(d.dayCount) days")
                    heroMeta(.bookOpen, "Devotional")
                }
                .padding(.top, 2)
            }
            .padding(.horizontal, 20).padding(.bottom, 16)
        }
        .frame(height: 264)
        .overlay(alignment: .topLeading) {
            HStack {
                circleBtn(.chevronLeft, tint: .white) { dismiss() }
                Spacer()
                circleBtn(.heart, tint: saved ? PL.gold : .white) { saved.toggle() }
            }
            .padding(.horizontal, 16).padding(.top, 60)
        }
    }

    private func heroMeta(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 13, color: PL.goldLight)
            Text(text).font(.inter(12)).foregroundStyle(.white.opacity(0.8))
        }
    }

    private func circleBtn(_ icon: Lucide, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: icon == .heart ? 17 : 20, color: tint)
                .frame(width: 40, height: 40)
                .background(Color.black.opacity(0.35), in: Circle())
        }
        .buttonStyle(.plain)
    }

    private func aboutCard(_ d: ReadingPlanDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ABOUT THIS PLAN").font(.inter(10, .bold)).kerning(1.8).foregroundStyle(PL.goldDeep)
            Text(d.description ?? d.subtitle ?? "A guided plan — Scripture and a short devotional each day.")
                .font(.inter(13)).lineSpacing(4).foregroundStyle(PL.blurb)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private func whatYoullRead(_ d: ReadingPlanDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("WHAT YOU'LL READ").font(.inter(10, .bold)).kerning(1.8).foregroundStyle(PL.goldDeep)
            VStack(spacing: 6) {
                ForEach(d.days) { day in
                    NavigationLink(value: PlanDayRef(planId: d.planId, day: day)) { dayRow(day) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)
        }
        .padding(16)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    private func dayRow(_ day: ReadingPlanDay) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text("DAY").font(.inter(7, .bold)).foregroundStyle(PL.gold)
                Text("\(day.dayNumber)").font(.fraunces(14, .semibold)).foregroundStyle(PL.navy)
            }
            .frame(width: 36, height: 36)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(PL.border, lineWidth: 1))
            VStack(alignment: .leading, spacing: 1) {
                Text(day.title ?? "Reading & reflection").font(.inter(12, .semibold)).foregroundStyle(PL.navy).lineLimit(1)
                Text(day.reference).font(.inter(10)).foregroundStyle(PL.ink3).lineLimit(1)
            }
            Spacer(minLength: 0)
            Icon(.chevronRight, size: 14, color: Color(hex: 0xCBD5E1))
        }
        .padding(10)
        .background(PL.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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

    private func ctaBar(_ d: ReadingPlanDetail) -> some View {
        HStack(spacing: 10) {
            Button { Task { await vm.start() } } label: {
                HStack(spacing: 8) {
                    if vm.busy { ProgressView().tint(PL.navy) }
                    else { Icon(.check, size: 16, color: PL.navy) }
                    Text(d.enrolled ? "Continue reading" : "Start plan").font(.inter(14, .bold)).foregroundStyle(PL.navy)
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(LinearGradient(colors: [PL.gold, Color(hex: 0xB6862F)], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            Button { } label: {
                HStack(spacing: 6) { Icon(.share2, size: 15, color: PL.navy); Text("Invite").font(.inter(13, .semibold)).foregroundStyle(PL.navy) }
                    .frame(minHeight: 48).padding(.horizontal, 16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 12)
        .padding(.bottom, Self.safeBottom + 12)
        .background(Color.white.overlay(alignment: .top) { Rectangle().fill(PL.border).frame(height: 1) })
    }

    private static var safeBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 0
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

    func completeDay() async {
        busy = true; defer { busy = false }
        try? await MemberAPI.completePlanDay(planId, dayNumber: dayNumber)
        dayCompleted = true
    }
}

struct PlanDayView: View {
    let ref: PlanDayRef
    @StateObject private var vm: PlanDayViewModel
    @Environment(\.dismiss) private var dismiss

    init(ref: PlanDayRef) {
        self.ref = ref
        _vm = StateObject(wrappedValue: PlanDayViewModel(ref: ref))
    }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: Nuru.S.base) {
                    Text(ref.day.reference).font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
                    if let content = ref.day.content, !content.isEmpty {
                        Text(content).font(.nBody).foregroundStyle(Nuru.ink).fixedSize(horizontal: false, vertical: true)
                    }
                    let segments = ref.day.segments ?? []
                    // PlanDayRef carries no plan title, so fall back to the day title.
                    let planTitle = ref.day.title ?? "Reading plan"
                    ForEach(Array(segments.enumerated()), id: \.element.id) { idx, seg in
                        NavigationLink(value: PlanSegmentRef(planTitle: planTitle,
                                                             dayNumber: ref.day.dayNumber,
                                                             segments: segments,
                                                             index: idx)) {
                            segmentCard(seg)
                        }
                        .buttonStyle(.plain)
                    }

                    if vm.dayCompleted {
                        Label("Day complete", systemImage: "checkmark.circle.fill")
                            .font(.nHeading).foregroundStyle(Nuru.success)
                    } else {
                        PButton(title: "Mark day complete", variant: .gold, busy: vm.busy) {
                            Task { await vm.completeDay(); dismiss() }
                        }
                    }
                }
                .padding(Nuru.S.screen)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .navigationTitle(ref.day.title ?? "Day \(ref.day.dayNumber)")
        .navigationBarTitleDisplayMode(.inline)
    }

    // A tappable row that pushes the full-screen PlanSegmentView (watch / read /
    // devotional / talk). Completion + watching now live on that screen.
    private func segmentCard(_ seg: PlanSegment) -> some View {
        let done = vm.completedSegments.contains(seg.segmentId)
        return Card {
            HStack(spacing: Nuru.S.base) {
                ZStack {
                    Circle().fill(done ? Nuru.success : Nuru.goldTint).frame(width: 36, height: 36)
                    Icon(segmentIcon(seg.kind), size: 15, color: done ? .white : Nuru.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(seg.title).font(.nHeading).foregroundStyle(Nuru.ink)
                    Text(seg.kind.capitalized).font(.nCaption).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 13, color: Nuru.ink300)
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
}
