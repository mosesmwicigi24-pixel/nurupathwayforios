// Home — the native port of screens/HomeDashboardScreen.tsx. The warm daily
// anchor: navy header (date kicker, bell + unread, progress ring, serif greeting,
// daily line, level status chip), the server-driven next-best-action hero, the
// "Verse for today", today's rhythm with streak, the growth-score snapshot, and
// the "Grow your faith" grid. Styled + iconed (Lucide) to match the RN screen.
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var pathway: PathwaySummary?
    @Published var streak = 0
    @Published var unread = 0
    @Published var greetingLine = "Grace for today's step."
    @Published var nextAction: NextAction?
    @Published var rhythm = RhythmToday(prayer: false, word: false, reflection: false)
    @Published var verse: (text: String, reference: String, version: String)?
    @Published var verseReason: String?
    @Published var reactions: VerseReactions?
    @Published var scores: ScoresSummary?
    @Published var verseSaved = false
    @Published var loading = true
    @Published var error: String?

    func load() async {
        loading = true; error = nil
        async let pathway = try? MemberAPI.pathway()
        async let ach = try? MemberAPI.achievements()
        async let unread = try? MemberAPI.unreadNotifications()
        async let greet = try? MemberAPI.dailyGreeting()
        async let next = try? MemberAPI.nextAction()
        async let rhythm = try? MemberAPI.rhythmToday()
        async let scores = try? MemberAPI.scores()
        async let hv = try? MemberAPI.homeVerse()
        async let vr = try? MemberAPI.verseReactions()

        self.pathway = await pathway
        self.streak = await ach?.streak.current ?? 0
        self.unread = await unread ?? 0
        if let g = await greet, !g.isEmpty { greetingLine = g }
        self.nextAction = await next ?? nil
        if let r = await rhythm { self.rhythm = r }
        self.scores = await scores
        self.reactions = await vr

        if let v = await hv {
            if let t = v.text, !t.isEmpty { verse = (t, v.reference, v.version) }
            else if let passage = try? await MemberAPI.scripture(v.reference) {
                verse = (passage.text, passage.reference, passage.version)
            }
            verseReason = v.reason
        }
        if self.pathway == nil { error = "Couldn't load your dashboard." }
        loading = false
    }

    func markRhythm(_ kind: String) async {
        guard !done(kind) else { return }
        if let next = try? await MemberAPI.completeRhythm(kind) { rhythm = next }
    }
    func done(_ kind: String) -> Bool {
        switch kind { case "prayer": return rhythm.prayer; case "word": return rhythm.word; default: return rhythm.reflection }
    }

    func reactVerse(_ emoji: String) async {
        reactions = try? await MemberAPI.setVerseReaction(emoji)
    }

    func saveVerse() async {
        guard !verseSaved, let v = verse else { return }
        verseSaved = true
        do { try await MemberAPI.saveVerseQuick(reference: v.reference, version: v.version, text: v.text) }
        catch { verseSaved = false }
    }
}

private let verseReactionEmojis = ["❤️", "🙏", "🔥", "🙌", "👍"]
private struct GrowTile { let label, sub: String; let icon: Lucide; let tint, fg: UInt32; let dest: AnyHashable }

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @StateObject private var vm = HomeViewModel()
    @State private var path = NavigationPath()

    private var growTiles: [GrowTile] {
        [
            GrowTile(label: "Devotional", sub: "Today's devotional", icon: .sun, tint: 0xFFF4DA, fg: 0xA87F2E, dest: GrowDestination.devotional),
            GrowTile(label: "Reading plan", sub: "Continue your plan", icon: .bookMarked, tint: 0xEEF2FF, fg: 0x6366F1, dest: GrowDestination.readingPlans),
            GrowTile(label: "Hide His Word", sub: "Memorize Scripture", icon: .quote, tint: 0xFFF4DA, fg: 0xA87F2E, dest: GrowDestination.memoryVerses),
            GrowTile(label: "Your Calling", sub: "Discover your gifts", icon: .sparkles, tint: 0xF3E8FF, fg: 0xA855F7, dest: GrowDestination.gifts),
            GrowTile(label: "Prayer Wall", sub: "Pray with the family", icon: .handHeart, tint: 0xFEE2E2, fg: 0xB91C1C, dest: CommunityRoute.prayerWall),
        ]
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    VStack(spacing: Nuru.S.base) {
                        if let a = vm.nextAction { heroCard(a) }
                        verseCard
                        rhythmCard
                        if let s = vm.scores { progressCard(s) }
                        growCard
                    }
                    .padding(.horizontal, Nuru.S.screen)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .nuruDestinations()
        }
        .task {
            if vm.pathway == nil { await vm.load() }
            deepLinkForScreenshots()
        }
    }

    /// DEBUG-only: deep-link into a pushed screen for screenshot verification
    /// (e.g. SIMCTL_CHILD_NURU_SCREEN=devotional). No-op in Release / when unset.
    private func deepLinkForScreenshots() {
        #if DEBUG
        guard path.isEmpty else { return }
        switch ProcessInfo.processInfo.environment["NURU_SCREEN"] {
        case "devotional": path.append(GrowDestination.devotional)
        case "memoryVerses": path.append(GrowDestination.memoryVerses)
        case "readingPlans": path.append(GrowDestination.readingPlans)
        case "prayerJournal": path.append(GrowDestination.prayerJournal)
        case "verseLibrary": path.append(GrowDestination.verseLibrary)
        case "prayerWall": path.append(CommunityRoute.prayerWall)
        case "notifications": path.append(AppRoute.notifications)
        default: break
        }
        #endif
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(todayKicker()).font(.inter(11, .semibold)).kerning(2.4).foregroundStyle(Nuru.gold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                NavigationLink(value: AppRoute.notifications) {
                    ZStack(alignment: .topTrailing) {
                        Icon(.bell, size: 20, color: Nuru.onNavy)
                            .frame(width: 44, height: 44)
                            .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if vm.unread > 0 {
                            Text(vm.unread > 9 ? "9+" : "\(vm.unread)")
                                .font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
                                .frame(minWidth: 18, minHeight: 18)
                                .background(Nuru.gold, in: Circle())
                                .offset(x: 4, y: -4)
                        }
                    }
                }
                .buttonStyle(.plain)
                Text("\(overallPct)%").font(.fraunces(14, .semibold)).foregroundStyle(Nuru.onNavy)
                    .frame(width: 48, height: 48)
                    .background(Nuru.gold.opacity(0.08), in: Circle())
                    .overlay(Circle().stroke(Nuru.gold, lineWidth: 4))
                    .padding(.leading, Nuru.S.sm)
            }
            Text("\(greeting), \(firstName).")
                .font(.fraunces(28, .semibold)).foregroundStyle(Nuru.onNavy)
                .padding(.top, Nuru.S.xl)
            Text(vm.greetingLine).font(.inter(16)).foregroundStyle(Nuru.onNavyDim)
                .padding(.top, Nuru.S.sm)
            if let a = active {
                Text("Level \(a.levelNumber) · \(a.completedModules) of \(a.totalModules) modules · \(vm.streak)d streak")
                    .font(.inter(12, .semibold)).foregroundStyle(Nuru.goldGlow)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .overlay(Capsule().stroke(Nuru.gold.opacity(0.55), lineWidth: 1))
                    .padding(.top, Nuru.S.lg)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 60)
        .padding(.bottom, Nuru.S.xl)
        .background(Nuru.navy)
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
    }

    // MARK: Next-action hero

    private func heroCard(_ a: NextAction) -> some View {
        Button {
            if a.route == "module" { /* moduleId param not modelled; open pathway */ }
        } label: {
            HStack(spacing: Nuru.S.md) {
                RoundedRectangle(cornerRadius: 2).fill(heroAccent(a.accent)).frame(width: 4)
                VStack(alignment: .leading, spacing: 0) {
                    Text("FOR YOU TODAY").font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.goldGlow)
                    Text(a.title).font(.fraunces(19, .semibold)).foregroundStyle(Nuru.onNavy).padding(.top, 4)
                    Text(a.body).font(.nCaption).foregroundStyle(Nuru.onNavyDim).padding(.top, 4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: 4) {
                        Text(a.ctaLabel).font(.inter(12, .bold)).foregroundStyle(Nuru.navyDeep)
                        Icon(.chevronRight, size: 14, color: Nuru.navyDeep)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Nuru.gold, in: Capsule())
                    .padding(.top, Nuru.S.md)
                }
                Spacer(minLength: 0)
            }
            .padding(Nuru.S.base)
            .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: Nuru.R.card, style: .continuous))
            .nuruShadow()
        }
        .buttonStyle(.plain)
    }

    // MARK: Verse for today

    private var verseCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Icon(.bookOpen, size: 13, color: Nuru.goldChipText)
                Text("VERSE FOR TODAY").font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                Spacer(minLength: 0)
                Text(vm.verse?.version ?? "WEB").font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(Nuru.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
            }
            Text(vm.verse?.text ?? "“Your word is a lamp to my feet, and a light for my path.”")
                .font(.fraunces(18)).foregroundStyle(Nuru.ink).lineSpacing(5).padding(.top, Nuru.S.md)
            Text("\(vm.verse?.reference ?? "Psalm 119:105") · \(vm.verse?.version ?? "WEB")")
                .font(.inter(12, .medium)).foregroundStyle(Nuru.ink600).padding(.top, Nuru.S.sm)
            if let reason = vm.verseReason, !reason.isEmpty {
                HStack(spacing: 5) {
                    Icon(.sparkles, size: 12, color: Nuru.goldChipText)
                    Text("Chosen for you · \(reason)").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                }.padding(.top, 6)
            }
            // Reactions
            HStack(spacing: 6) {
                ForEach(verseReactionEmojis, id: \.self) { e in
                    let count = vm.reactions?.counts[e] ?? 0
                    let mine = vm.reactions?.mine == e
                    Button { Task { await vm.reactVerse(e) } } label: {
                        HStack(spacing: 4) {
                            Text(e).font(.system(size: 15))
                            if count > 0 { Text("\(count)").font(.inter(11, .bold)).foregroundStyle(mine ? Nuru.goldChipText : Nuru.ink600) }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(mine ? Nuru.verseBg : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(mine ? Nuru.gold : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, Nuru.S.md)
            HStack(spacing: Nuru.S.sm) {
                Button { Task { await vm.saveVerse() } } label: {
                    pill(icon: .heart, label: vm.verseSaved ? "Saved" : "Save", tint: vm.verseSaved ? Nuru.gold : Nuru.ink600)
                }.buttonStyle(.plain)
            }
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
    }

    private func pill(icon: Lucide, label: String, tint: Color) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 13, color: tint)
            Text(label).font(.inter(11, .semibold)).foregroundStyle(tint)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Nuru.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: Rhythm

    private var rhythmCard: some View {
        let done = (vm.rhythm.prayer ? 1 : 0) + (vm.rhythm.word ? 1 : 0) + (vm.rhythm.reflection ? 1 : 0)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(done == 3 ? "Today's rhythm complete 🎉" : "Today's rhythm")
                    .font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                Spacer()
                HStack(spacing: 4) {
                    Icon(.flame, size: 12, color: Nuru.goldChipText)
                    Text("\(vm.streak)-day streak").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Nuru.goldChipBg, in: Capsule())
            }
            HStack(spacing: Nuru.S.sm) {
                rhythmTile("prayer", "Prayer")
                rhythmTile("word", "Word")
                rhythmTile("reflection", "Reflection")
            }
            .padding(.top, Nuru.S.md)
            if !vm.rhythm.reflection {
                Text("Complete reflection to keep your rhythm.").font(.nMicro).foregroundStyle(Nuru.faint).padding(.top, Nuru.S.sm)
            }
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func rhythmTile(_ kind: String, _ label: String) -> some View {
        let done = vm.done(kind)
        return Button { Task { await vm.markRhythm(kind) } } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle().fill(done ? Nuru.successText : Nuru.white).frame(width: 24, height: 24)
                    Icon(done ? .check : .clock, size: 12, color: done ? Nuru.white : Nuru.goldLo)
                }
                Text(label).font(.inter(12, .semibold)).foregroundStyle(done ? Nuru.successText : Nuru.goldChipText)
                Text(done ? "DONE" : "PENDING").font(.nMicro).foregroundStyle(done ? Nuru.successText : Nuru.goldChipText).opacity(0.8)
            }
            .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.md)
            .background(done ? Nuru.successBg : Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }.buttonStyle(.plain)
    }

    // MARK: Progress (scores)

    private func progressCard(_ s: ScoresSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your progress").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                Spacer()
                NavigationLink(value: PathwayRoute.level(active?.levelNumber ?? 1)) {
                    Text("View pathway ›").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
                }
            }
            HStack(spacing: Nuru.S.base) {
                VStack(spacing: -3) {
                    Text("\(s.overall.score)").font(.fraunces(24, .semibold)).foregroundStyle(Nuru.navyDeep)
                    Text("/100").font(.nMicro).foregroundStyle(Nuru.ink600)
                }
                .frame(width: 68, height: 68)
                .background(Nuru.verseBg, in: Circle())
                .overlay(Circle().stroke(Nuru.gold, lineWidth: 3))
                VStack(alignment: .leading, spacing: 1) {
                    Text("OVERALL GROWTH").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldLo)
                    Text(s.overall.band).font(.nHeading).foregroundStyle(Nuru.ink)
                    Text("Your rhythm across the disciplines").font(.nCaption).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Nuru.S.md)
            VStack(spacing: Nuru.S.sm) {
                scoreBar("Habits", s.habits.score, Nuru.gold)
                scoreBar("Word", s.word.score, Color(hex: 0x1B5FAE))
                scoreBar("Prayer", s.prayer.score, Nuru.goldLo)
                scoreBar("Curriculum", s.curriculum.score, Nuru.navy)
                scoreBar("Attendance", s.attendance.score, Nuru.success)
            }
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func scoreBar(_ label: String, _ value: Int, _ fill: Color) -> some View {
        HStack(spacing: Nuru.S.sm) {
            Text(label).font(.nCaption).foregroundStyle(Nuru.ink600).frame(width: 86, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.track).frame(height: 8)
                    Capsule().fill(fill).frame(width: geo.size.width * CGFloat(value) / 100, height: 8)
                }
            }.frame(height: 8)
            Text("\(value)").font(.nCaption).foregroundStyle(Nuru.ink).fontWeight(.bold).frame(width: 30, alignment: .trailing)
        }
    }

    // MARK: Grow grid

    private var growCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Text("Grow your faith").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Nuru.S.sm), GridItem(.flexible(), spacing: Nuru.S.sm)], spacing: Nuru.S.sm) {
                ForEach(growTiles.indices, id: \.self) { i in
                    let t = growTiles[i]
                    NavigationLink(value: t.dest) { growTileView(t) }.buttonStyle(.plain)
                }
            }
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func growTileView(_ t: GrowTile) -> some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(t.icon, size: 16, color: Color(hex: t.fg))
                .frame(width: 32, height: 32)
                .background(Color(hex: t.tint), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(t.label).font(.inter(12, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Text(t.sub).font(.nMicro).foregroundStyle(Nuru.faint).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.md)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: derived

    private var active: PathwayLevel? {
        guard let p = vm.pathway else { return nil }
        return p.levels.first { $0.status == .active }
            ?? p.levels.first { $0.levelNumber == p.currentLevel }
            ?? p.levels.first
    }
    private var overallPct: Int {
        guard let p = vm.pathway else { return 0 }
        let total = p.levels.reduce(0) { $0 + $1.totalModules }
        let done = p.levels.reduce(0) { $0 + $1.completedModules }
        return total > 0 ? Int(round(Double(done) / Double(total) * 100)) : 0
    }
    private var firstName: String { (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend" }
    private var greeting: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : "Good evening"
    }
    private func heroAccent(_ a: String) -> Color {
        switch a { case "success": return Nuru.success; case "steady": return Color(hex: 0x1B5FAE); case "navy": return Nuru.goldGlow; default: return Nuru.gold }
    }
    private func todayKicker() -> String {
        let f = DateFormatter(); f.dateFormat = "EEEE, MMM d"
        return f.string(from: Date()).uppercased() + " · EAT"
    }
}

private extension View {
    /// White card surface with one soft shadow + hairline border (RN `st.card`).
    func cardSurface() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
    }
}
