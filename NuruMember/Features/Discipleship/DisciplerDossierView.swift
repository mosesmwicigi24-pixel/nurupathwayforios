// Per-student dossier — the discipler's deep view of one member of their flock,
// fed by GET /disciples/{id}. Top-to-bottom: the member card ("In your care
// since …"), the gold Message CTA (reusing the 1:1 DM the chat module owns),
// the engagement card (e-score circle + band + recency), progression with the
// strong "Awaiting YOUR usher" banner, growth scores, the student's reflections
// INCLUDING what they wrote (plus this leader's feedback), and recent activity.
// Pure reflection of server state (§1.9) — the usher itself happens elsewhere;
// nothing here advances a level or originates gating.
import SwiftUI

@MainActor
final class DisciplerDossierViewModel: ObservableObject {
    @Published var dossier: DiscipleDossier?
    @Published var loading = true
    @Published var error: String?
    /// The existing DM thread with the student — matched by the dossier's
    /// `dmConversationId` against the chat inbox, falling back to a peer-user-id /
    /// title match the way DiscipleshipHubViewModel.findDm does.
    @Published var studentDm: ChatConversation?
    /// True while POST /chat/dms is creating the student DM on the CTA tap.
    @Published var startingDm = false

    let userId: String
    init(userId: String) { self.userId = userId }

    func load() async {
        loading = true; error = nil
        do { dossier = try await MemberAPI.disciple(userId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this disciple." }
        loading = false

        // Resolve the DM thread if one exists, so the CTA deep-links instead of
        // create-then-push. Best-effort — mirrors DiscipleshipHubViewModel.load.
        if let d = dossier, let inbox = try? await MemberAPI.chatInbox() {
            studentDm = Self.findDm(dossier: d, in: inbox.conversations)
        }
    }

    /// Prefer the dossier's authoritative conversation id, then a peer-user-id
    /// match, then a name match (older inbox rows) — mirrors the Hub's findDm.
    static func findDm(dossier d: DiscipleDossier, in conversations: [ChatConversation]) -> ChatConversation? {
        if let id = d.dmConversationId,
           let row = conversations.first(where: { $0.conversationId == id }) { return row }
        let dms = conversations.filter { $0.kind == "dm" }
        return dms.first { $0.peerUserId == d.member.userId }
            ?? dms.first {
                $0.title?.compare(d.member.fullName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            }
    }

    /// No DM yet → create (or fetch — the server dedupes) the 1:1 with the
    /// student via POST /chat/dms, then return the conversation to push.
    func startStudentDm() async -> ChatConversation? {
        guard let m = dossier?.member, !startingDm else { return nil }
        startingDm = true
        defer { startingDm = false }
        guard let id = try? await MemberAPI.createDm(peerUserId: m.userId) else { return nil }
        let inbox = try? await MemberAPI.chatInbox()
        let dm = inbox?.conversations.first { $0.conversationId == id } ?? ChatConversation(
            conversationId: id, kind: "dm", isPublic: false, title: m.fullName,
            topic: nil, category: nil, memberCount: 2, lastBody: nil, lastType: nil,
            lastAt: nil, lastAuthor: nil, unread: 0, avatarUrl: m.avatarUrl,
            peerUserId: m.userId)
        studentDm = dm
        return dm
    }
}

struct DisciplerDossierView: View {
    /// The roster row that pushed this dossier — gives the header a name and
    /// avatar before the full dossier loads.
    let row: DiscipleRoster.Row

    @StateObject private var vm: DisciplerDossierViewModel
    @Environment(\.dismiss) private var dismiss
    /// Programmatic push of the freshly created student DM.
    @State private var openCreatedDm = false
    @State private var dmError = false

    init(row: DiscipleRoster.Row) {
        self.row = row
        _vm = StateObject(wrappedValue: DisciplerDossierViewModel(userId: row.userId))
    }

    var body: some View {
        ZStack {
            Nuru.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Nuru.S.base) {
                        if vm.loading && vm.dossier == nil {
                            skeleton
                        } else if let d = vm.dossier {
                            content(d)
                        } else if let err = vm.error {
                            errorCard(err)
                        }
                    }
                    .padding(Nuru.S.screen)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Lets the Message CTA push the student's DM thread from this stack.
        .navigationDestination(for: ChatConversation.self) { ChatThreadView(conversation: $0) }
        // Programmatic push for the just-created DM (POST /chat/dms on tap).
        .navigationDestination(isPresented: $openCreatedDm) {
            if let dm = vm.studentDm { ChatThreadView(conversation: dm) }
        }
        .task { if vm.dossier == nil { await vm.load() } }
    }

    // MARK: content

    @ViewBuilder
    private func content(_ d: DiscipleDossier) -> some View {
        memberCard(d.member).gentleEntrance()
        messageHero(d).gentleEntrance(delay: 0.04)
        engagementCard(d.engagement).gentleEntrance(delay: 0.08)
        progressionCard(d.progression).gentleEntrance(delay: 0.12)
        if d.scores.hasAny { growthCard(d.scores).gentleEntrance(delay: 0.16) }
        if !d.reflections.isEmpty { reflectionsCard(d.reflections).gentleEntrance(delay: 0.20) }
        if !d.recentActivity.isEmpty { activityCard(d.recentActivity).gentleEntrance(delay: 0.24) }
    }

    // MARK: cream header (matches the roster's anatomy)

    private var header: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Button { Haptics.tap(); dismiss() } label: {
                Icon(.arrowLeft, size: 18, color: Nuru.navy)
                    .frame(width: 40, height: 40)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Text("IN YOUR CARE")
                    .font(.nCardKicker).tracking(1.4)
                    .foregroundStyle(Color(hex: 0x9A7A2A))
                Text(row.fullName)
                    .font(.fraunces(26, .semibold))
                    .foregroundStyle(Nuru.navy)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.lg)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.25)).frame(width: 224, height: 224).blur(radius: 48).offset(x: 60, y: -80)
                }
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28, style: .continuous))
                .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
                .ignoresSafeArea(edges: .top)
        )
    }

    // MARK: member card — avatar · name · cell · since

    private func memberCard(_ m: DiscipleDossier.Member) -> some View {
        HStack(spacing: Nuru.S.base) {
            Avatar(url: m.avatarUrl, name: m.fullName, size: 56)
            VStack(alignment: .leading, spacing: 3) {
                Text(m.fullName).font(.inter(17, .bold)).foregroundStyle(Nuru.ink)
                if let cell = m.cellName {
                    Text(cell).font(.nCardMeta).foregroundStyle(Nuru.muted)
                }
                if let since = m.establishedAt.flatMap(Self.monthYear) {
                    Text("In your care since \(since)").font(.nMicro).foregroundStyle(Nuru.goldLo)
                } else if let joined = m.joinedAt.flatMap(Self.monthYear) {
                    Text("Joined \(joined)").font(.nMicro).foregroundStyle(Nuru.goldLo)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: hero — Message {first name} (reuses the 1:1 DM)

    @ViewBuilder
    private func messageHero(_ d: DiscipleDossier) -> some View {
        if let dm = vm.studentDm {
            NavigationLink(value: dm) { messageLabel(d.member, busy: false) }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
        } else {
            VStack(alignment: .leading, spacing: Nuru.S.xs) {
                Button {
                    Haptics.tap()
                    dmError = false
                    Task {
                        if await vm.startStudentDm() != nil {
                            Haptics.success()
                            openCreatedDm = true
                        } else {
                            Haptics.error()
                            dmError = true
                        }
                    }
                } label: {
                    messageLabel(d.member, busy: vm.startingDm)
                }
                .buttonStyle(.pressable)
                .disabled(vm.startingDm)
                if dmError {
                    Text("Couldn't start the chat with \(Self.firstName(d.member.fullName)) — please try again.")
                        .font(.nMicro).foregroundStyle(Nuru.faint)
                }
            }
        }
    }

    /// The gold hero button label — "Message {first name}".
    private func messageLabel(_ m: DiscipleDossier.Member, busy: Bool) -> some View {
        HStack(spacing: Nuru.S.sm) {
            if busy {
                ProgressView().tint(Nuru.navy).scaleEffect(0.85)
            } else {
                Icon(.messageCircle, size: 17, color: Nuru.navy)
            }
            Text("Message \(Self.firstName(m.fullName))")
                .font(.inter(15, .semibold)).foregroundStyle(Nuru.navy)
        }
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
        .shadow(color: Nuru.gold.opacity(0.35), radius: 12, y: 6)
    }

    // MARK: engagement — e-score circle · band pill · recency

    private func engagementCard(_ e: DiscipleDossier.Engagement) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("ENGAGEMENT")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))

                HStack(spacing: Nuru.S.md) {
                    let color = e.band.map(Nuru.bandColor) ?? Nuru.ink600
                    ZStack {
                        Circle().fill(color.opacity(0.10)).frame(width: 52, height: 52)
                            .overlay(Circle().stroke(color.opacity(0.4), lineWidth: 1.5))
                        Text(e.eScore.map(String.init) ?? "—")
                            .font(.fraunces(18, .semibold)).foregroundStyle(color)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        if let band = e.band {
                            Text(DisciplerRosterView.bandLabel(band))
                                .font(.inter(11, .bold)).foregroundStyle(Nuru.bandColor(band))
                                .padding(.horizontal, 9).padding(.vertical, 3)
                                .background(Nuru.bandColor(band).opacity(0.12), in: Capsule())
                                .overlay(Capsule().stroke(Nuru.bandColor(band).opacity(0.25), lineWidth: 1))
                        } else {
                            Text("Not yet computed").font(.nCardMeta).foregroundStyle(Nuru.faint)
                        }
                        Text(lastActiveLine(e.daysSinceLastActivity))
                            .font(.nCardMeta)
                            .foregroundStyle(e.daysSinceLastActivity.map { $0 >= 7 } == true ? Nuru.danger : Nuru.muted)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func lastActiveLine(_ days: Int?) -> String {
        guard let days else { return "No activity yet" }
        return days == 0 ? "Active today" : "Last active \(days) day\(days == 1 ? "" : "s") ago"
    }

    // MARK: progression — level · streak · modules bar · usher banner

    private func progressionCard(_ p: DiscipleDossier.Progression) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("WHERE THEY ARE")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))

                HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
                    Text("Level \(p.currentLevel)")
                        .font(.fraunces(20, .semibold)).foregroundStyle(Nuru.ink)
                    Text(p.levelTitle)
                        .font(.nCardBody).foregroundStyle(Nuru.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    if p.streakDays > 0 {
                        HStack(spacing: 4) {
                            Icon(.flame, size: 13, color: Nuru.gold)
                            Text("\(p.streakDays)-day")
                                .font(.inter(11, .bold)).foregroundStyle(Nuru.goldLo)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Nuru.goldTint.opacity(0.6), in: Capsule())
                    }
                }

                // Modules progress bar.
                VStack(alignment: .leading, spacing: 6) {
                    GeometryReader { geo in
                        let pct = p.modulesTotal > 0 ? Double(p.modulesCompleted) / Double(p.modulesTotal) : 0
                        ZStack(alignment: .leading) {
                            Capsule().fill(Nuru.track)
                            Capsule().fill(Nuru.goldGradient)
                                .frame(width: max(0, geo.size.width * pct))
                        }
                    }
                    .frame(height: 8)
                    Text("\(p.modulesCompleted) of \(p.modulesTotal) modules complete")
                        .font(.nCardMeta).foregroundStyle(Nuru.faint)
                }

                if let level = p.awaitingLevel {
                    usherBanner(level: level)
                }
            }
        }
    }

    /// The strong gold "this student is waiting on YOU" banner.
    private func usherBanner(level: Int) -> some View {
        HStack(spacing: Nuru.S.md) {
            ZStack {
                Circle().fill(Nuru.gold.opacity(0.16))
                    .overlay(Circle().stroke(Nuru.gold.opacity(0.4), lineWidth: 1))
                Text("🌿").font(.system(size: 20))
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text("Awaiting YOUR usher into Level \(level)")
                    .font(.inter(14, .bold)).foregroundStyle(Nuru.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(Self.firstName(row.fullName)) has finished the work — walk them forward.")
                    .font(.inter(11)).foregroundStyle(Nuru.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.goldTint.opacity(0.5), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    // MARK: growth — overall big + five band-colored stat chips

    private func growthCard(_ s: DiscipleDossier.Scores) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.md) {
                Text("THEIR GROWTH")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))

                if let overall = s.overall {
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        Text("\(overall)")
                            .font(.fraunces(34, .semibold)).foregroundStyle(Self.scoreColor(overall))
                        Text("overall")
                            .font(.nCardBody).foregroundStyle(Nuru.muted)
                        Spacer(minLength: 0)
                    }
                }

                // Five sub-scores as band-colored chips — nil ones skipped gracefully.
                let chips: [(String, Int?)] = [
                    ("Word", s.word), ("Prayer", s.prayer), ("Habits", s.habits),
                    ("Curriculum", s.curriculum), ("Attendance", s.attendance),
                ]
                let present = chips.compactMap { label, v in v.map { (label, $0) } }
                if !present.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Nuru.S.sm),
                                        GridItem(.flexible(), spacing: Nuru.S.sm)],
                              spacing: Nuru.S.sm) {
                        ForEach(present, id: \.0) { label, value in
                            scoreChip(label: label, value: value)
                        }
                    }
                }
            }
        }
    }

    private func scoreChip(label: String, value: Int) -> some View {
        let color = Self.scoreColor(value)
        return HStack(spacing: Nuru.S.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(.inter(9, .bold)).kerning(0.8).foregroundStyle(Nuru.faint)
                Text("\(value)")
                    .font(.inter(18, .bold)).foregroundStyle(color)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Nuru.S.md).padding(.vertical, Nuru.S.sm)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(color.opacity(0.22), lineWidth: 1))
    }

    // MARK: reflections — module · level · state pill · body · your feedback

    private func reflectionsCard(_ reflections: [DiscipleDossier.Reflection]) -> some View {
        Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("THEIR REFLECTIONS")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(reflections.enumerated()), id: \.element.id) { i, r in
                        reflectionRow(r)
                        if i < reflections.count - 1 { Divider().overlay(Nuru.border) }
                    }
                }
            }
        }
    }

    private func reflectionRow(_ r: DiscipleDossier.Reflection) -> some View {
        VStack(alignment: .leading, spacing: Nuru.S.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.moduleTitle)
                        .font(.inter(13, .semibold)).foregroundStyle(Nuru.ink).lineLimit(2)
                    Text("Level \(r.levelNumber) · \(Self.shortDate(r.submittedAt) ?? "")")
                        .font(.nMicro).foregroundStyle(Nuru.faint)
                }
                Spacer(minLength: Nuru.S.sm)
                statePill(r.state)
            }
            // What the student wrote — quoted block (the leader reads it here).
            if let body = r.body, !body.isEmpty {
                HStack(alignment: .top, spacing: Nuru.S.sm) {
                    RoundedRectangle(cornerRadius: 1.5).fill(Nuru.gold.opacity(0.5)).frame(width: 3)
                    Text(body)
                        .font(.inter(12)).italic().foregroundStyle(Nuru.ink)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Nuru.S.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            // This leader's own feedback, when given.
            if let notes = r.feedbackNotes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 3) {
                    Text("YOUR FEEDBACK")
                        .font(.inter(9, .bold)).kerning(0.8).foregroundStyle(Nuru.goldLo)
                    Text(notes)
                        .font(.inter(12)).foregroundStyle(Nuru.muted)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Nuru.S.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.goldTint.opacity(0.35), in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
            }
        }
        .padding(.vertical, Nuru.S.md)
    }

    /// Reflection state → a small pill (approved green, pending blue, returned
    /// amber, deferred grey — the app's shared status palette).
    private func statePill(_ state: String) -> some View {
        let (label, color): (String, Color) = {
            switch state.lowercased() {
            case "approved": return ("Approved", Nuru.success)
            case "pending":  return ("Pending", Color(hex: 0x1B5FAE))
            case "returned": return ("Returned", Nuru.warning)
            case "deferred": return ("Deferred", Nuru.ink600)
            default:         return (state.capitalized, Nuru.ink600)
            }
        }()
        return Text(label)
            .font(.inter(10, .bold)).foregroundStyle(color)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 1))
    }

    // MARK: recent activity — kind rows, capped at 10 + "+N more"

    private func activityCard(_ activity: [DiscipleDossier.Activity]) -> some View {
        let shown = Array(activity.prefix(10))
        let extra = activity.count - shown.count
        return Card {
            VStack(alignment: .leading, spacing: Nuru.S.sm) {
                Text("RECENT ACTIVITY")
                    .font(.inter(10, .bold)).tracking(1.8)
                    .foregroundStyle(Color(hex: 0xA8861C))
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { i, a in
                        activityRow(a)
                        if i < shown.count - 1 { Divider().overlay(Nuru.border) }
                    }
                }
                if extra > 0 {
                    Text("+\(extra) more")
                        .font(.nMicro).foregroundStyle(Nuru.faint)
                }
            }
        }
    }

    private func activityRow(_ a: DiscipleDossier.Activity) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Nuru.S.sm) {
            Circle().fill(Nuru.gold.opacity(0.5)).frame(width: 5, height: 5)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 3 }
            Text(Self.kindLabel(a.kind))
                .font(.inter(12, .medium)).foregroundStyle(Nuru.ink)
            Spacer(minLength: Nuru.S.sm)
            Text(timeAgo(a.occurredAt))
                .font(.nMicro).foregroundStyle(Nuru.faint)
        }
        .padding(.vertical, Nuru.S.sm)
    }

    /// "kind_words" → "Kind words" — snake_case wire kind to a sentence label.
    static func kindLabel(_ kind: String) -> String {
        let words = kind.replacingOccurrences(of: "_", with: " ")
        guard let first = words.first else { return kind }
        return String(first).uppercased() + words.dropFirst()
    }

    // MARK: loading skeleton (mirrors member card + hero + one card)

    private var skeleton: some View {
        VStack(spacing: Nuru.S.base) {
            HStack(spacing: Nuru.S.base) {
                Circle().fill(Nuru.surface).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 140, height: 12)
                    RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 90, height: 9)
                }
                Spacer(minLength: 0)
            }
            .padding(Nuru.S.base)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShimmer()

            RoundedRectangle(cornerRadius: Nuru.R.button).fill(Nuru.surface)
                .frame(maxWidth: .infinity).frame(height: 52)
                .nuruShimmer()

            VStack(alignment: .leading, spacing: Nuru.S.md) {
                RoundedRectangle(cornerRadius: 4).fill(Nuru.surface).frame(width: 90, height: 8)
                RoundedRectangle(cornerRadius: Nuru.R.control).fill(Nuru.surface)
                    .frame(maxWidth: .infinity).frame(height: 68)
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShimmer()
        }
    }

    // MARK: error state (load failed — offer retry)

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: Nuru.S.md) {
            Text(message).font(.nCardBody).foregroundStyle(Nuru.muted).multilineTextAlignment(.center)
            Button { Haptics.tap(); Task { await vm.load() } } label: {
                Text("Try again").font(.inter(13, .semibold)).foregroundStyle(Nuru.navy)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Nuru.R.control, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
        }
        .frame(maxWidth: .infinity)
        .padding(Nuru.S.base)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    // MARK: helpers

    private static func firstName(_ full: String) -> String {
        full.split(separator: " ").first.map(String.init) ?? full
    }

    /// Score → band color (the shared engagement palette).
    private static func scoreColor(_ v: Int) -> Color {
        switch v {
        case 75...:   return Nuru.bandColor("thriving")
        case 50..<75: return Nuru.bandColor("steady")
        case 30..<50: return Nuru.bandColor("watch")
        default:      return Nuru.bandColor("at_risk")
        }
    }

    // MARK: date helpers (match DiscipleshipHubView's formatting)

    private static func parse(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
    private static func monthYear(_ iso: String) -> String? {
        guard let d = parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"; return f.string(from: d)
    }
    private static func shortDate(_ iso: String) -> String? {
        guard let d = parse(iso) else { return nil }
        let f = DateFormatter(); f.dateFormat = "MMM d, yyyy"; return f.string(from: d)
    }
}

private extension DiscipleDossier.Scores {
    /// True when at least one score is computed — drives whether the growth card shows.
    var hasAny: Bool {
        overall != nil || word != nil || prayer != nil || habits != nil || curriculum != nil || attendance != nil
    }
}
