// Departments — You → Departments (PARTNERS_PROGRAMME §4, phase 3).
//
// The serving teams of the church, one card each: photo, name, purpose, the
// leader, how many serve, and three quiet verdicts the SERVER makes — "a good
// fit for you" (gift_keys ∩ the member's top gifts, §4), how many needs are
// open for giving, and where the member stands with the team (serving /
// requested). The client never recomputes any of them. Tapping a card pushes
// the department page (DepartmentDetailView) on this segment's own stack.
//
// Ordering is the member's, not the server's: the teams they belong to
// first, then the good fits, then everyone else — so the top of the list
// always answers "where am I / where could I be" before "what exists".
import SwiftUI

/// Pushed pages on the Departments stack.
enum DepartmentRoute: Hashable {
    case department(String)      // a department page, by id
}

@MainActor final class DepartmentsModel: ObservableObject {
    @Published var rows: [DepartmentRow] = []
    @Published var loading = false
    @Published var error: String?

    func load() async {
        loading = rows.isEmpty
        error = nil
        do { rows = try await MemberAPI.departments() }
        catch { if rows.isEmpty { self.error = (error as? APIError)?.errorDescription ?? "We couldn't load the departments just now." } }
        loading = false
    }

    var mine: [DepartmentRow] { rows.filter { $0.isActiveMember || $0.isRequested } }
    var goodFits: [DepartmentRow] { rows.filter { $0.fit && !($0.isActiveMember || $0.isRequested) } }
    var others: [DepartmentRow] { rows.filter { !$0.fit && !($0.isActiveMember || $0.isRequested) } }
}

struct DepartmentsView: View {
    @StateObject private var vm = DepartmentsModel()
    @EnvironmentObject private var tabs: TabRouter
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            content
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: DepartmentRoute.self) { route in
                    switch route {
                    case .department(let id):
                        DepartmentDetailView(departmentId: id, seed: vm.rows.first { $0.departmentId == id }) {
                            Task { await vm.load() }
                        }
                    }
                }
        }
        .task { if vm.rows.isEmpty { await vm.load() } }
        // A notification tap (serve_request_* / department_post /
        // department_need_*) or any cross-tab link lands ON the department
        // page, with this list as the back stop. Consumed once, then cleared —
        // a @Published replays the pending value to a freshly mounted segment,
        // so the link survives the You tab mounting this segment lazily.
        .onReceive(tabs.$departmentLink) { id in
            guard let id, !id.isEmpty else { return }
            path = NavigationPath()
            path.append(DepartmentRoute.department(id))
            DispatchQueue.main.async { tabs.departmentLink = nil }
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                VStack(alignment: .leading, spacing: Nuru.S.lg) {
                    if vm.loading && vm.rows.isEmpty {
                        skeleton
                    } else if let e = vm.error, vm.rows.isEmpty {
                        errorState(e)
                    } else if vm.rows.isEmpty {
                        emptyState
                    } else {
                        list
                    }
                }
                .padding(.horizontal, Nuru.S.screen)
                .padding(.top, Nuru.S.base)
                .padding(.bottom, Nuru.tabBarSpace)
            }
        }
        .background(Nuru.paper.ignoresSafeArea())
        .refreshable { await vm.load() }
    }

    // MARK: Header (cream band — the You tab's segment idiom)

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DEPARTMENTS")
                .font(.inter(9, .bold)).kerning(1.62).foregroundStyle(Color(hex: 0x9A7A2A))
            Text("Where to serve")
                .font(.fraunces(24, .semibold)).kerning(-0.48).foregroundStyle(Nuru.navy)
                .padding(.top, 4)
            Text("The teams that carry this church — what they do, what they need, and where you'd fit.")
                .font(.inter(11)).foregroundStyle(Color(hex: 0x59667C))
                .padding(.top, 4)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, Nuru.S.base)
        .padding(.bottom, 20)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 30, bottomTrailingRadius: 30))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // MARK: The list — mine · good fits · everyone else

    private var list: some View {
        let mine = vm.mine, fits = vm.goodFits, others = vm.others
        let sectioned = !mine.isEmpty || !fits.isEmpty
        return Group {
            if !mine.isEmpty { section("YOU SERVE IN", rows: mine) }
            if !fits.isEmpty { section("A GOOD FIT FOR YOU", rows: fits) }
            if !others.isEmpty { section(sectioned ? "MORE DEPARTMENTS" : nil, rows: others) }
        }
    }

    private func section(_ kicker: String?, rows: [DepartmentRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let kicker {
                Text(kicker).font(.nMicro).tracking(1.4).foregroundStyle(Nuru.goldLo)
            }
            VStack(spacing: Nuru.S.md) {
                ForEach(rows) { row in
                    NavigationLink(value: DepartmentRoute.department(row.departmentId)) {
                        DepartmentCard(row: row)
                    }
                    .buttonStyle(.pressable)
                    .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                }
            }
        }
    }

    // MARK: States

    private var skeleton: some View {
        VStack(spacing: Nuru.S.md) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous)
                    .fill(Nuru.white).frame(height: 236).nuruShimmer()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Nuru.S.md) {
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.12)).frame(width: 72, height: 72)
                Icon(.heartHandshake, size: 30, color: Nuru.gold)
            }
            Text("No departments yet")
                .font(.fraunces(22, .semibold)).foregroundStyle(Nuru.navy)
            Text("When the church sets up its serving teams, they'll appear here — what they do, what they need, and how to join one.")
                .font(.nBody).foregroundStyle(Nuru.ink600)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .padding(.horizontal, Nuru.S.lg)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: Nuru.S.sm) {
            Icon(.circleHelp, size: 24, color: Nuru.ink400)
            Text(message).font(.nBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button { Haptics.tap(); Task { await vm.load() } } label: {
                Text("Try again").font(.inter(11, .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Nuru.navy, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity).padding(.top, Nuru.S.xl)
    }
}

// MARK: - The card

struct DepartmentCard: View {
    let row: DepartmentRow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DepartmentPhoto(url: row.imageUrl, name: row.name, height: 132)
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(row.name).font(.nCardTitle).foregroundStyle(Nuru.ink).lineLimit(2)
                        if !row.purpose.isEmpty {
                            Text(row.purpose).font(.nCardBody).foregroundStyle(Nuru.ink600).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    if let chip = DepartmentStatusChip(row: row) { chip }
                }

                HStack(spacing: 8) {
                    if let leader = row.leaderName, !leader.isEmpty {
                        Avatar(url: row.leaderAvatar, name: leader, size: 22)
                        Text(leader).font(.nLabel).foregroundStyle(Nuru.ink).lineLimit(1)
                        Text("·").font(.nCaption).foregroundStyle(Nuru.ink300)
                    }
                    Icon(.users, size: 12, color: Nuru.ink400)
                    Text(row.memberCount == 1 ? "1 serving" : "\(row.memberCount) serving")
                        .font(.nCaption).foregroundStyle(Nuru.ink600)
                }

                if row.fit || row.openNeeds > 0 {
                    DeptChipRow {
                        if row.fit { DepartmentFitChip(gifts: row.matchedGiftNames) }
                        if row.openNeeds > 0 {
                            DeptChip(text: row.openNeeds == 1 ? "1 open need" : "\(row.openNeeds) open needs",
                                     icon: .target, bg: Nuru.tintBlue, fg: Nuru.navyMid)
                        }
                    }
                }

                if let post = row.latestPost, !post.isEmpty {
                    HStack(alignment: .top, spacing: 8) {
                        Icon(.quote, size: 12, color: Nuru.gold)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post).font(.nCardBody).foregroundStyle(Nuru.ink).lineLimit(2)
                            if let at = row.latestPostAt, !at.isEmpty {
                                Text(timeAgo(at)).font(.nCardMeta).foregroundStyle(Nuru.ink400)
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .padding(Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .nuruShadow()
    }
}

// MARK: - Shared pieces (card + department page)

/// The department's photo, or a gold-gradient tableau with the team's initial
/// when there is none — so a department without a photo still has a face.
struct DepartmentPhoto: View {
    let url: String?
    let name: String
    var height: CGFloat = 132

    var body: some View {
        ZStack {
            fallback
            if let url, let u = URL(string: url) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image {
                        img.resizable().scaledToFill()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipped()
    }

    private var fallback: some View {
        ZStack {
            Nuru.goldGradient
            Circle().fill(.white.opacity(0.18)).frame(width: height * 1.4, height: height * 1.4)
                .blur(radius: 30).offset(x: height * 0.6, y: -height * 0.4)
            HStack(spacing: 10) {
                Icon(.heartHandshake, size: 26, color: .white.opacity(0.9))
                Text(Avatar.initials(name)).font(.fraunces(30, .semibold)).foregroundStyle(.white)
            }
        }
    }
}

/// "Serving" / "Requested" — the member's standing with the team, or nothing.
struct DepartmentStatusChip: View {
    let text: String
    let icon: Lucide
    let bg: Color
    let fg: Color

    init?(row: DepartmentRow) {
        if row.isActiveMember {
            text = row.isLeaderRole ? "Leading" : "Serving"
            icon = .circleCheckBig; bg = Nuru.activeBadgeBg; fg = Nuru.activeBadgeText
        } else if row.isRequested {
            text = "Requested"; icon = .clock; bg = Nuru.urgentBg; fg = Nuru.urgentText
        } else {
            return nil
        }
    }

    var body: some View { DeptChip(text: text, icon: icon, bg: bg, fg: fg) }
}

/// The gold "Good fit for you" chip, with the matched gift names when known.
struct DepartmentFitChip: View {
    let gifts: [String]
    var body: some View {
        let detail = gifts.isEmpty ? "" : " · " + gifts.prefix(2).joined(separator: ", ")
        DeptChip(text: "Good fit for you\(detail)", icon: .sparkles, bg: Nuru.goldChipBg, fg: Nuru.goldChipText)
    }
}

struct DeptChip: View {
    let text: String
    var icon: Lucide? = nil
    var bg: Color = Nuru.surface
    var fg: Color = Nuru.ink600
    var body: some View {
        HStack(spacing: 4) {
            if let icon { Icon(icon, size: 10, color: fg) }
            Text(text).font(.inter(11, .semibold)).foregroundStyle(fg).lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(bg, in: Capsule())
    }
}

/// A wrapping row of chips — a Layout so two or three chips never force the
/// card wider than the screen.
struct DeptChipRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        DeptFlowLayout(spacing: 6) { content() }
    }
}

struct DeptFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let size = s.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowH = max(rowH, size.height)
        }
    }
}
