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
}

struct ReadingPlansView: View {
    @StateObject private var vm = ReadingPlansViewModel()

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            LoadStateView(loading: vm.loading && vm.plans.isEmpty,
                          isEmpty: vm.plans.isEmpty, error: vm.error,
                          emptyText: "No reading plans yet.", retry: { Task { await vm.load() } }) {
                ScrollView {
                    VStack(spacing: Nuru.S.md) {
                        ForEach(vm.plans) { plan in
                            NavigationLink(value: plan) { PlanRowCard(plan: plan) }.buttonStyle(.plain)
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("Reading Plans")
        .navigationBarTitleDisplayMode(.inline)
        .task { if vm.plans.isEmpty { await vm.load() } }
    }
}

private struct PlanRowCard: View {
    let plan: ReadingPlanRow
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                HStack {
                    Text(plan.title).font(.nHeading).foregroundStyle(Nuru.ink)
                    Spacer()
                    if plan.enrolled {
                        Text(plan.completedAt != nil ? "Done" : "Active")
                            .font(.nMicro).foregroundStyle(Nuru.successText)
                            .padding(.horizontal, Nuru.S.sm).padding(.vertical, 3)
                            .background(Nuru.successBg, in: Capsule())
                    }
                }
                if let subtitle = plan.subtitle ?? plan.description, !subtitle.isEmpty {
                    Text(subtitle).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2)
                }
                Text("\(plan.dayCount) days").font(.nMicro).foregroundStyle(Nuru.faint)
                if plan.enrolled, let done = plan.completedDays?.count {
                    ProgressView(value: plan.dayCount == 0 ? 0 : Double(done) / Double(plan.dayCount)).tint(Nuru.gold)
                }
            }
        }
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
                    if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.white) }
                    else { Text("\(day.dayNumber)").font(.inter(14, .semibold)).foregroundStyle(Nuru.gold) }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(day.title ?? "Day \(day.dayNumber)").font(.nHeading).foregroundStyle(Nuru.ink)
                    Text(day.reference).font(.nCaption).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Nuru.ink300)
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
                    ForEach(ref.day.segments ?? []) { seg in segmentCard(seg) }

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

    private func segmentCard(_ seg: PlanSegment) -> some View {
        let done = vm.completedSegments.contains(seg.segmentId)
        return Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                HStack {
                    Text(seg.title).font(.nHeading).foregroundStyle(Nuru.ink)
                    Spacer()
                    Text(seg.kind.capitalized).font(.nMicro).foregroundStyle(Nuru.faint)
                }
                if let ref = seg.reference { Text(ref).font(.nCaption).foregroundStyle(Nuru.gold) }
                if let content = seg.content, !content.isEmpty {
                    Text(content).font(.nBody).foregroundStyle(Nuru.ink).fixedSize(horizontal: false, vertical: true)
                }
                if let url = seg.videoUrl.flatMap(URL.init) {
                    Link(destination: url) {
                        Label("Watch", systemImage: "play.circle.fill").font(.inter(13, .semibold)).foregroundStyle(Nuru.gold)
                    }
                }
                Button {
                    if !done { Task { await vm.completeSegment(seg.segmentId) } }
                } label: {
                    Label(done ? "Completed" : "Mark complete",
                          systemImage: done ? "checkmark.circle.fill" : "circle")
                        .font(.inter(13, .semibold))
                        .foregroundStyle(done ? Nuru.success : Nuru.gold)
                }
                .buttonStyle(.plain)
                .disabled(done)
            }
        }
    }
}
