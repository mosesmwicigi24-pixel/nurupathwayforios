// Reading Plans — the native port of screens/ReadingPlansScreen.tsx +
// PlanDetailScreen.tsx + PlanDayScreen.tsx. Browse plans, enrol, then work
// through each day's segments. Progress is server-tracked.
import SwiftUI

// MARK: - Plans list

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

    /// Active plan = first enrolled plan (the one in progress at the top of the list).
    var activePlan: ReadingPlanRow? { plans.first { $0.enrolled } }
    /// Everything browsable in the catalogue (the active plan also appears here as in the spec).
    var browsePlans: [ReadingPlanRow] { plans }
}

struct ReadingPlansView: View {
    @StateObject private var vm = ReadingPlansViewModel()

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header
                LoadStateView(loading: vm.loading && vm.plans.isEmpty,
                              isEmpty: vm.plans.isEmpty, error: vm.error,
                              emptyText: "No reading plans yet.", retry: { Task { await vm.load() } }) {
                    VStack(alignment: .leading, spacing: Nuru.S.lg) {
                        if let active = vm.activePlan { activeSection(active) }
                        browseSection
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.lg)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await vm.load() }
        .task { if vm.plans.isEmpty { await vm.load() } }
    }

    // MARK: Navy header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("READ · REFLECT · APPLY")
                .font(.inter(11, .semibold)).kerning(1.5)
                .foregroundStyle(Nuru.gold)
            Text("Plans")
                .font(.fraunces(30, .semibold)).foregroundStyle(Nuru.onNavy)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.lg)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    // MARK: Active plan

    @ViewBuilder
    private func activeSection(_ plan: ReadingPlanRow) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            sectionOverline("ACTIVE PLANS")
            NavigationLink(value: plan) { activeCard(plan) }.buttonStyle(.plain)
        }
    }

    private func activeCard(_ plan: ReadingPlanRow) -> some View {
        let total = max(plan.dayCount, 1)
        let doneDays = plan.completedDays?.count ?? 0
        let currentDay = plan.currentDay ?? (doneDays + 1)
        let progress = min(max(Double(doneDays) / Double(total), 0), 1)
        return HStack(spacing: Nuru.S.base) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Nuru.goldTint)
                Icon(.bookMarked, size: 24, color: Nuru.gold)
            }
            .frame(width: 56, height: 56)
            VStack(alignment: .leading, spacing: 6) {
                Text(plan.title).font(.inter(16, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Text("Day \(currentDay) of \(plan.dayCount)")
                    .font(.nMicro).foregroundStyle(Nuru.faint)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Nuru.gold.opacity(0.18)).frame(height: 4)
                        Capsule().fill(Nuru.gold).frame(width: max(4, geo.size.width * progress), height: 4)
                    }
                }
                .frame(height: 4)
                .padding(.top, 2)
            }
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: Browse plans

    private var browseSection: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            sectionOverline("BROWSE PLANS")
            VStack(spacing: Nuru.S.md) {
                ForEach(vm.browsePlans) { plan in
                    NavigationLink(value: plan) { browseCard(plan) }.buttonStyle(.plain)
                }
            }
        }
    }

    private func browseCard(_ plan: ReadingPlanRow) -> some View {
        HStack(spacing: Nuru.S.base) {
            planThumbnail(plan)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(plan.dayCount) DAYS")
                    .font(.inter(10, .semibold)).kerning(0.8)
                    .foregroundStyle(Nuru.faint)
                Text(plan.title).font(.inter(16, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                if let sub = plan.subtitle ?? plan.description, !sub.isEmpty {
                    Text(sub).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    @ViewBuilder
    private func planThumbnail(_ plan: ReadingPlanRow) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        if let url = plan.imageUrl.flatMap(URL.init) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().scaledToFill()
                } else {
                    fallbackTile
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(shape)
        } else {
            fallbackTile.frame(width: 56, height: 56).clipShape(shape)
        }
    }

    private var fallbackTile: some View {
        ZStack {
            Nuru.goldTint
            Icon(.book, size: 22, color: Nuru.gold)
        }
    }

    private func sectionOverline(_ text: String) -> some View {
        Text(text)
            .font(.inter(11, .semibold)).kerning(1.2)
            .foregroundStyle(Nuru.faint)
    }
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

struct PlanDetailView: View {
    let plan: ReadingPlanRow
    @StateObject private var vm: PlanDetailViewModel

    init(plan: ReadingPlanRow) {
        self.plan = plan
        _vm = StateObject(wrappedValue: PlanDetailViewModel(planId: plan.planId))
    }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.detail == nil,
                          isEmpty: vm.detail == nil, error: vm.error,
                          emptyText: "No days in this plan.", retry: { Task { await vm.load() } }) {
                if let d = vm.detail { content(d) }
            }
        }
        .navigationTitle(plan.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.detail == nil { await vm.load() } }
    }

    private func content(_ d: ReadingPlanDetail) -> some View {
        ScrollView {
            VStack(spacing: Nuru.S.md) {
                if let desc = d.description, !desc.isEmpty {
                    Text(desc).font(.nBody).foregroundStyle(Nuru.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if !d.enrolled {
                    PButton(title: "Start plan", variant: .gold, busy: vm.busy) { Task { await vm.start() } }
                }
                ForEach(d.days) { day in
                    let done = d.completedDays?.contains(day.dayNumber) ?? (day.completed ?? false)
                    NavigationLink(value: PlanDayRef(planId: d.planId, day: day)) {
                        DayRow(day: day, done: done)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Nuru.S.screen)
            .padding(.bottom, Nuru.tabBarSpace)
        }
    }
}

private struct DayRow: View {
    let day: ReadingPlanDay
    let done: Bool
    var body: some View {
        Card {
            HStack(spacing: Nuru.S.base) {
                ZStack {
                    Circle().fill(done ? Nuru.success : Nuru.goldTint).frame(width: 36, height: 36)
                    if done { Icon(.check, size: 13, color: .white) }
                    else { Text("\(day.dayNumber)").font(.inter(14, .semibold)).foregroundStyle(Nuru.gold) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.title ?? "Day \(day.dayNumber)").font(.nHeading).foregroundStyle(Nuru.ink)
                    Text(day.reference).font(.nCaption).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 13, color: Nuru.ink300)
            }
        }
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
