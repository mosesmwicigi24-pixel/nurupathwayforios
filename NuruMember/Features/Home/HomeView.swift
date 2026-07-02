// Home — the native port of screens/HomeDashboardScreen.tsx, rebuilt to pixel-match
// the member dashboard (IMG_1905–1912 — one long scroll). Every card the screenshots
// show, in order: navy header → continue hero → welcome video → verse of the day →
// prayer-wall carousel → reading-plan/journal minis → this-week cell → disciplers
// carousel → featured announcement → continue level → today's rhythm → reflection
// banner → progress scores → grow grid → upcoming calendar → one-reflection banner →
// your cohort → announcements list → "Support God's Work" give banner. All sections
// load concurrently and degrade gracefully (a section hides when its data is empty).
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    // Core
    @Published var pathway: PathwaySummary?
    @Published var streak = 0
    @Published var unread = 0
    @Published var greetingLine = "Grace for today's step."
    @Published var nextAction: NextAction?
    @Published var rhythm = RhythmToday(prayer: false, word: false, reflection: false)
    @Published var scores: ScoresSummary?

    // Verse
    @Published var verse: (text: String, reference: String, version: String)?
    @Published var verseReason: String?
    @Published var reactions: VerseReactions?
    @Published var verseSaved = false

    // Rich home cards
    @Published var welcomeVideo: WelcomeVideo?
    @Published var prayerPosts: [PrayerWallPost] = []
    @Published var plan: ReadingPlanRow?
    @Published var prayerEntries: [PrayerEntry] = []
    @Published var featuredCell: FeaturedCell?
    @Published var disciplers: [Discipler] = []
    @Published var featuredAnnouncement: FeaturedAnnouncement?
    @Published var announcements: [MyAnnouncement] = []
    @Published var cell: CellSummary.Cell?
    @Published var events: [CalendarOccurrence] = []

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
        async let video = try? MemberAPI.welcomeVideo()
        async let posts = try? MemberAPI.prayerWallHome()
        async let plans = try? MemberAPI.plans()
        async let prayers = try? MemberAPI.prayers()
        async let fcell = try? MemberAPI.featuredCell()
        async let discs = try? MemberAPI.disciplers()
        async let fann = try? MemberAPI.featuredAnnouncement()
        async let anns = try? MemberAPI.myAnnouncements()
        async let summary = try? MemberAPI.cellSummary()
        async let cal = try? MemberAPI.calendar(from: Self.calFrom, to: Self.calTo)

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

        self.welcomeVideo = await video ?? nil
        self.prayerPosts = await posts ?? []
        let allPlans = await plans ?? []
        self.plan = allPlans.first { $0.enrolled } ?? allPlans.first
        self.prayerEntries = await prayers ?? []
        self.featuredCell = await fcell ?? nil
        self.disciplers = await discs ?? []
        self.featuredAnnouncement = await fann ?? nil
        self.announcements = await anns ?? []
        self.cell = (await summary)?.cell
        self.events = (await cal ?? []).sorted { $0.startAt < $1.startAt }

        if self.pathway == nil { error = "Couldn't load your dashboard." }
        loading = false
    }

    // Rhythm
    func markRhythm(_ kind: String) async {
        guard !done(kind) else { return }
        if let next = try? await MemberAPI.completeRhythm(kind) { rhythm = next }
    }
    func done(_ kind: String) -> Bool {
        switch kind { case "prayer": return rhythm.prayer; case "word": return rhythm.word; default: return rhythm.reflection }
    }

    // Verse
    func reactVerse(_ emoji: String) async { reactions = try? await MemberAPI.setVerseReaction(emoji) }
    func saveVerse() async {
        guard !verseSaved, let v = verse else { return }
        verseSaved = true
        do { try await MemberAPI.saveVerseQuick(reference: v.reference, version: v.version, text: v.text) }
        catch { verseSaved = false }
    }

    // Welcome-video reaction toggle
    func toggleVideoReaction(_ emoji: String) async {
        guard let id = welcomeVideo?.mediaAssetId, let v = welcomeVideo else { return }
        guard let r = try? await MemberAPI.toggleMediaReaction(id, emoji: emoji) else { return }
        welcomeVideo = WelcomeVideo(
            mediaAssetId: v.mediaAssetId, videoSource: v.videoSource, caption: v.caption,
            durationSec: v.durationSec, thumbnailUrl: v.thumbnailUrl, reactions: r.reactions,
            loveCount: r.loveCount, liked: r.liked, externalUrl: v.externalUrl,
            externalVideoId: v.externalVideoId, url: v.url, expiresAt: v.expiresAt)
    }

    func openAnnouncement(_ id: String) async { await MemberAPI.openAnnouncement(id) }

    // Two-month calendar window around today (drives section 15's mini month grid).
    private static var calFrom: String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        return isoDay(start)
    }
    private static var calTo: String {
        let cal = Calendar.current
        let start = cal.date(from: cal.dateComponents([.year, .month], from: Date())) ?? Date()
        let end = cal.date(byAdding: DateComponents(month: 2, day: -1), to: start) ?? Date()
        return isoDay(end)
    }
    private static func isoDay(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: d)
    }
}

private let verseReactionEmojis = ["❤️", "🙏", "🔥", "🙌", "👍"]
private let videoReactionEmojis = ["🙏", "🔥", "🎉", "👏"]
private struct GrowTile { let label, sub: String; let icon: Lucide; let tint, fg: UInt32; let dest: AnyHashable }

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @StateObject private var vm = HomeViewModel()
    @State private var path = NavigationPath()
    @State private var playingVideo = false
    @State private var sharePayload: SharePayload?

    private var growTiles: [GrowTile] {
        [
            GrowTile(label: "Devotional", sub: "Today's devotional", icon: .sun, tint: 0xFFF4DA, fg: 0xA87F2E, dest: GrowDestination.devotional),
            GrowTile(label: "Reading plan", sub: "Continue your plan", icon: .bookMarked, tint: 0xEEF2FF, fg: 0x6366F1, dest: GrowDestination.readingPlans),
            GrowTile(label: "Hide His Word", sub: "Memorize Scripture", icon: .quote, tint: 0xFFF4DA, fg: 0xA87F2E, dest: GrowDestination.memoryVerses),
            GrowTile(label: "Your Calling", sub: "Discover your gifts", icon: .sparkles, tint: 0xF3E8FF, fg: 0xA855F7, dest: GrowDestination.gifts),
            GrowTile(label: "Resources", sub: "Books, audio & teaching", icon: .bookOpen, tint: 0xE8EDFB, fg: 0x4F63C4, dest: GrowDestination.resources),
            GrowTile(label: "Prayer Wall", sub: "Pray with the family", icon: .handHeart, tint: 0xFEE2E2, fg: 0xB91C1C, dest: CommunityRoute.prayerWall),
        ]
    }

    // The Home feed as an ARRAY of individually type-erased views. This is the only
    // form that reliably avoids the on-device type-demangler stack overflow: the
    // enclosing VStack/ForEach type is flat (`ForEach<…, AnyView>`), and each card's
    // (deeply-generic) type is demangled ONE AT A TIME here — in a shallow stack —
    // as its AnyView box is built. `some View` groups and even AnyView-of-6 still
    // forced the runtime to decode several cards' types together and overflowed.
    private var feedSections: [AnyView] {
        var s: [AnyView] = []
        if let a = vm.nextAction { s.append(AnyView(heroCard(a))) }                     // 2
        if let v = vm.welcomeVideo { s.append(AnyView(welcomeVideoCard(v))) }           // 3
        s.append(AnyView(verseCard))                                                    // 4
        if !vm.prayerPosts.isEmpty { s.append(AnyView(prayerWallCard)) }                // 5
        s.append(AnyView(minisRow))                                                     // 6
        if let c = vm.featuredCell {                                                    // 7
            if let aid = weekAnnouncementId {
                s.append(AnyView(Button {
                    path.append(AppRoute.announcement(aid))
                    Task { await vm.openAnnouncement(aid) }
                } label: { featuredCellCard(c) }.buttonStyle(.plain)))
            } else {
                s.append(AnyView(featuredCellCard(c)))
            }
        }
        if !vm.disciplers.isEmpty { s.append(AnyView(disciplersCard)) }                 // 8
        if let a = vm.featuredAnnouncement { s.append(AnyView(featuredAnnouncementCard(a))) } // 9
        s.append(AnyView(continueLevelCard))                                            // 10
        s.append(AnyView(rhythmCard))                                                   // 11
        if !vm.rhythm.reflection, let a = active { s.append(AnyView(reflectionBanner(a))) } // 12
        if let sc = vm.scores { s.append(AnyView(progressCard(sc))) }                   // 13
        s.append(AnyView(growCard))                                                     // 14
        s.append(AnyView(upcomingCard))                                                 // 15
        s.append(AnyView(oneReflectionBanner))                                          // 16
        s.append(AnyView(cohortCard))                                                   // 17
        if !vm.announcements.isEmpty { s.append(AnyView(announcementsCard)) }           // 18
        s.append(AnyView(giveBanner))                                                   // 19
        return s
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                    // Split into opaque `some View` groups. A single VStack with all
                    // ~18 sections compiles to one enormous parameter-pack TupleView
                    // whose mangled type name overflows the Swift metadata demangler
                    // (swift_getTypeByMangledNameImpl) at launch on-device → EXC_BAD_ACCESS.
                    // Each group boundary erases the tuple, keeping every type small.
                    VStack(spacing: Nuru.S.base) {
                        ForEach(Array(feedSections.enumerated()), id: \.offset) { _, section in
                            section
                        }
                    }
                    .padding(.horizontal, Nuru.S.base)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace)
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            .nuruDestinations()
        }
        .sheet(item: $sharePayload) { ShareToChatSheet(text: $0.text) }
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
        case "prayerDetail": path.append(CommunityRoute.prayer("de300000-0000-0000-0000-000000000500"))
        case "gifts": path.append(GrowDestination.gifts)
        case "giftsAssessment": path.append(GrowDestination.giftsAssessment)
        case "resources": path.append(GrowDestination.resources)
        case "notifications": path.append(AppRoute.notifications)
        case "mentor": path.append(AppRoute.mentor)
        case "cell": path.append(AppRoute.cell)
        case "planSegment":
            let segs = [
                PlanSegment(segmentId: "s1", sort: 0, kind: "video", title: "Watch",
                            reference: nil, content: "A short reflection to begin the day.",
                            videoUrl: "https://example.com/v.mp4", imageUrl: nil, completed: false),
                PlanSegment(segmentId: "s2", sort: 1, kind: "reading", title: "Today's Reading",
                            reference: "Psalm 1", content: "Blessed is the one who does not walk in step with the wicked…",
                            videoUrl: nil, imageUrl: nil, completed: false),
            ]
            path.append(PlanSegmentRef(planTitle: "Rooted: 10 Days in the Psalms", dayNumber: 2, segments: segs, index: 0))
        case "level": path.append(PathwayRoute.level(1))
        case "notifications": path.append(AppRoute.notifications)
        default: break
        }
        #endif
    }

    // MARK: 1 — Navy header

    // Cream, navy-on-light header — exact Figma HomeTab (HEADER_BG cream gradient,
    // Bell + Radio + MiniRing, greeting, subtitle, level chip).
    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                Text(todayKicker()).font(.inter(11, .semibold)).kerning(2.42).foregroundStyle(Color(hex: 0x9A7A2A))
                    .frame(maxWidth: .infinity, alignment: .leading)
                NavigationLink(value: AppRoute.notifications) {
                    ZStack(alignment: .topTrailing) {
                        Icon(.bell, size: 18, color: Nuru.navy)
                            .frame(width: 40, height: 40)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                        if vm.unread > 0 {
                            Text(vm.unread > 9 ? "9+" : "\(vm.unread)")
                                .font(.inter(9, .bold)).foregroundStyle(Nuru.navy)
                                .frame(minWidth: 16, minHeight: 16).padding(.horizontal, 2)
                                .background(Nuru.gold, in: Capsule())
                                .offset(x: 5, y: -5)
                        }
                    }
                }
                .buttonStyle(.plain)
                Button { } label: {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 17))
                        .foregroundStyle(Nuru.navy).frame(width: 40, height: 40)
                        .background(Color.white, in: Circle())
                        .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.plain).padding(.leading, 8)
                progressRing.padding(.leading, 8)
            }
            Text("\(greeting), \(firstName).")
                .font(.fraunces(22, .semibold)).kerning(-0.22).foregroundStyle(Nuru.navy)
                .padding(.top, 10)
            Text(vm.greetingLine).font(.inter(13)).foregroundStyle(Color(hex: 0x68758A))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            if let a = active {
                Text("Level \(a.levelNumber) · \(a.completedModules) of \(a.totalModules) modules · \(vm.streak > 0 ? "\(vm.streak)d streak" : "Begin today")")
                    .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white, in: Capsule())
                    .overlay(Capsule().stroke(Nuru.gold.opacity(0.53), lineWidth: 1))
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 60)   // clears the status bar / Dynamic Island (header is full-bleed)
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [Color(hex: 0xF6F4EF), Color(hex: 0xEFE8DA)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(0.27)).frame(width: 176, height: 176).blur(radius: 44).offset(x: 40, y: -60)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        .overlay(alignment: .bottom) { Rectangle().fill(Nuru.border).frame(height: 1) }
    }

    // MiniRing (Figma) — 42px, navy track, gold progress, navy pct.
    private var progressRing: some View {
        ZStack {
            Circle().stroke(Nuru.navy.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(overallPct) / 100)
                .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(overallPct)%").font(.inter(10, .bold)).foregroundStyle(Nuru.navy)
        }
        .frame(width: 42, height: 42)
    }

    // MARK: 2 — Next-action hero

    private func heroCard(_ a: NextAction) -> some View {
        Button {
            if a.route == "module", let m = a.params?.moduleId {
                path.append(PathwayRoute.module(m))
            } else if let lvl = active?.levelNumber {
                path.append(PathwayRoute.level(lvl))
            }
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

    // MARK: 3 — Featured welcome video

    private func welcomeVideoCard(_ v: WelcomeVideo) -> some View {
        let love = v.loveCount ?? (v.reactions?.first { $0.emoji == "❤️" }?.count ?? 0)
        let liked = v.liked ?? false
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Nuru.S.sm) {
                BrandMark(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Nuru Pathway").font(.inter(13, .bold)).foregroundStyle(Nuru.ink)
                    Text("Welcome").font(.nMicro).foregroundStyle(Nuru.faint)
                }
                Spacer(minLength: 0)
                Text("FEATURED").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.faint)
            }
            .padding(Nuru.S.base)

            // Plays inline, pinned to the card's 16:9 box — never opens Safari.
            Group {
                if playingVideo {
                    InlineVideoPlayer(video: v)
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                } else {
                    Button { playingVideo = true } label: { videoThumb(v) }.buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                if let cap = v.caption, !cap.isEmpty {
                    Text(cap).font(.fraunces(17, .semibold)).foregroundStyle(Nuru.ink)
                }
                Text("Start here — what the journey looks like")
                    .font(.nCaption).foregroundStyle(Nuru.muted).padding(.top, 2)
                HStack(spacing: 6) {
                    Button { Task { await vm.toggleVideoReaction("❤️") } } label: {
                        HStack(spacing: 5) {
                            Text("❤️").font(.system(size: 15))
                            Text("\(love)").font(.inter(11, .bold)).foregroundStyle(liked ? Nuru.danger : Nuru.ink600)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(liked ? Color(hex: 0xFEE2E2) : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(liked ? Nuru.danger.opacity(0.35) : Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                    ForEach(videoReactionEmojis, id: \.self) { e in
                        let count = v.reactions?.first { $0.emoji == e }?.count ?? 0
                        let mine = v.reactions?.first { $0.emoji == e }?.mine ?? false
                        Button { Task { await vm.toggleVideoReaction(e) } } label: {
                            HStack(spacing: 4) {
                                Text(e).font(.system(size: 15))
                                if count > 0 { Text("\(count)").font(.inter(11, .bold)).foregroundStyle(Nuru.ink600) }
                            }
                            .frame(minWidth: 34, minHeight: 34)
                            .padding(.horizontal, count > 0 ? 6 : 0)
                            .background(mine ? Nuru.goldChipBg : Nuru.white, in: Circle())
                            .overlay(Circle().stroke(mine ? Nuru.gold : Nuru.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    Spacer(minLength: 0)
                    Button { sharePayload = SharePayload(text: videoShareText(v)) } label: {
                        HStack(spacing: 5) {
                            Icon(.share2, size: 13, color: Nuru.ink600)
                            Text("Share").font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
                .padding(.top, Nuru.S.md)
            }
            .padding(Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func videoThumb(_ v: WelcomeVideo) -> some View {
        ZStack {
            Rectangle().fill(Nuru.mutedBg)
            if let s = v.thumbnailUrl, let u = URL(string: s) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { Rectangle().fill(Nuru.mutedBg) }
                }
            }
            ZStack {
                Circle().fill(Color.black.opacity(0.45)).frame(width: 60, height: 60)
                Icon(.play, size: 24, color: .white)
            }
            if let d = v.durationSec, d > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(durationLabel(d)).font(.inter(10, .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color.black.opacity(0.6), in: Capsule())
                            .padding(8)
                    }
                }
            }
        }
        .aspectRatio(16.0/9.0, contentMode: .fill)
        .frame(maxWidth: .infinity)
        .clipped()
    }

    // MARK: 4 — Verse for today

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
                Button { sharePayload = SharePayload(text: verseShareText()) } label: {
                    pill(icon: .share2, label: "Share", tint: Nuru.ink600)
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

    // MARK: 5 — Pray for one another (carousel)

    private var prayerWallCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PRAY FOR ONE ANOTHER").font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                Spacer()
                NavigationLink(value: CommunityRoute.prayerWall) {
                    Text("Open wall ›").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
                }.buttonStyle(.plain)
            }
            TabView {
                ForEach(vm.prayerPosts) { post in
                    NavigationLink(value: CommunityRoute.prayer(post.postId)) {
                        prayerPostView(post)
                    }.buttonStyle(.plain)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 188)
            .padding(.top, Nuru.S.sm)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func prayerPostView(_ post: PrayerWallPost) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: post.authorAvatar, name: post.authorName, size: 36)
                Text(post.authorName).font(.inter(13, .bold)).foregroundStyle(Nuru.ink)
                Spacer(minLength: 0)
            }
            if let t = post.title, !t.isEmpty {
                Text(t).font(.fraunces(17, .semibold)).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.sm)
            }
            Text(post.body).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            HStack(spacing: 4) {
                Icon(.handHeart, size: 13, color: Nuru.goldChipText)
                Text("\(post.prayCount) praying · \(post.commentCount ?? 0) reply")
                    .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
            }
            .padding(.top, Nuru.S.sm)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Nuru.S.lg)   // clear the page dots
    }

    // MARK: 6 — Reading-plan + Prayer-journal minis

    private var minisRow: some View {
        HStack(spacing: Nuru.S.sm) {
            NavigationLink(value: GrowDestination.readingPlans) { readingPlanMini }.buttonStyle(.plain)
            NavigationLink(value: GrowDestination.prayerJournal) { prayerJournalMini }.buttonStyle(.plain)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var readingPlanMini: some View {
        let p = vm.plan
        let pct: Int = {
            guard let p, p.dayCount > 0 else { return 0 }
            let done = p.completedDays?.count ?? max(0, (p.currentDay ?? 1) - 1)
            return Int(round(Double(done) / Double(p.dayCount) * 100))
        }()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Icon(.book, size: 16, color: Color(hex: 0x6366F1))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0xEEF2FF), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Text("\(pct)%").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x6366F1))
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Color(hex: 0xEEF2FF), in: Capsule())
            }
            Text("READING PLAN").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Color(hex: 0x6366F1)).padding(.top, Nuru.S.md)
            Text(p?.title ?? "Start a plan").font(.inter(14, .bold)).foregroundStyle(Nuru.ink).lineLimit(1).padding(.top, 3)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Nuru.track).frame(height: 6)
                    Capsule().fill(Color(hex: 0x6366F1)).frame(width: geo.size.width * CGFloat(pct) / 100, height: 6)
                }
            }.frame(height: 6).padding(.top, Nuru.S.sm)
            if let p { Text("Day \(p.currentDay ?? 1) of \(p.dayCount)").font(.nMicro).foregroundStyle(Nuru.faint).padding(.top, 6) }
            else { Text("Pick a reading plan").font(.nMicro).foregroundStyle(Nuru.faint).padding(.top, 6) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private var prayerJournalMini: some View {
        let answered = vm.prayerEntries.filter { $0.isAnswered }.count
        let latest = vm.prayerEntries.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Icon(.handHeart, size: 16, color: Color(hex: 0xB91C1C))
                    .frame(width: 34, height: 34)
                    .background(Color(hex: 0xFEE2E2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Text(answered > 0 ? "\(answered) answered" : "Private").font(.inter(11, .bold)).foregroundStyle(Nuru.successText)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Nuru.successBg, in: Capsule())
            }
            Text("PRAYER JOURNAL").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Color(hex: 0xB91C1C)).padding(.top, Nuru.S.md)
            Text(latest?.title ?? "Your prayers").font(.inter(14, .bold)).foregroundStyle(Nuru.ink).lineLimit(1).padding(.top, 3)
            Text(latest?.body ?? "Start journaling your prayers").font(.nMicro).foregroundStyle(Nuru.faint).lineLimit(2).padding(.top, 6)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.base)
        .cardSurface()
    }

    // MARK: 7 — This week at Nuru (featured cell)

    private func featuredCellCard(_ c: FeaturedCell) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let s = c.imageUrl, let u = URL(string: s) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { Rectangle().fill(Nuru.mutedBg) }
                }
                .frame(height: 168).frame(maxWidth: .infinity).clipped()
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Icon(.users, size: 12, color: Nuru.goldChipText)
                    Text("THIS WEEK AT NURU").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText)
                    Spacer(minLength: 0)
                    Text("Read more").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
                    Icon(.chevronRight, size: 12, color: Nuru.goldLo)
                }
                Text(c.name).font(.fraunces(20, .semibold)).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.sm)
                if let d = c.disciplerName {
                    Text("\(d)\(c.disciplerRole.map { " · \($0)" } ?? "")").font(.nCaption).foregroundStyle(Nuru.muted).padding(.top, 2)
                }
                HStack(spacing: Nuru.S.sm) {
                    if let f = c.focus { chip(.target, f) }
                    if let l = c.levelLabel { chip(.award, l) }
                }
                .padding(.top, Nuru.S.md)
                if let m = c.meets {
                    HStack(spacing: Nuru.S.sm) {
                        Icon(.calendarClock, size: 14, color: Nuru.goldChipText)
                            .frame(width: 30, height: 30)
                            .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(m).font(.inter(13, .semibold)).foregroundStyle(Nuru.ink)
                            if let n = c.nextSession { Text("Next: \(n)").font(.nMicro).foregroundStyle(Nuru.faint) }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Nuru.S.sm)
                    .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.top, Nuru.S.md)
                }
                HStack(spacing: Nuru.S.sm) {
                    if let r = c.room { chip(.mapPin, r) }
                    chip(.users, "\(c.members) members")
                }
                .padding(.top, Nuru.S.md)
            }
            .padding(Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func chip(_ icon: Lucide, _ text: String) -> some View {
        HStack(spacing: 5) {
            Icon(icon, size: 12, color: Nuru.goldChipText)
            Text(text).font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Nuru.surface, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 8 — Meet your discipler (carousel)

    private var disciplersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Icon(.users, size: 12, color: Nuru.goldChipText)
                Text("MEET YOUR DISCIPLER").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText)
                Spacer(minLength: 0)
                NavigationLink(value: AppRoute.mentor) {
                    HStack(spacing: 3) {
                        Text("View").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
                        Icon(.chevronRight, size: 12, color: Nuru.goldLo)
                    }
                }.buttonStyle(.plain)
            }
            TabView {
                ForEach(vm.disciplers) { d in disciplerView(d) }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .frame(height: 150)
            .padding(.top, Nuru.S.sm)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func disciplerView(_ d: Discipler) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Nuru.S.md) {
                Avatar(url: d.avatarUrl, name: d.fullName, size: 52)
                VStack(alignment: .leading, spacing: 2) {
                    Text(d.fullName).font(.inter(15, .bold)).foregroundStyle(Nuru.ink)
                    Text(d.roleLabel).font(.inter(12, .semibold)).foregroundStyle(Nuru.goldChipText)
                    if let m = d.message, !m.isEmpty {
                        Text("“\(m)”").font(.fraunces(13)).italic().foregroundStyle(Nuru.muted).lineLimit(3).padding(.top, 4)
                    }
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Nuru.S.lg)
    }

    // MARK: 9 — Featured announcement

    private func featuredAnnouncementCard(_ a: FeaturedAnnouncement) -> some View {
        Button {
            path.append(AppRoute.announcement(a.announcementId))
            Task { await vm.openAnnouncement(a.announcementId) }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let s = a.primaryImageUrl, let u = URL(string: s) {
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { Rectangle().fill(Nuru.mutedBg) }
                    }
                    .frame(height: 168).frame(maxWidth: .infinity).clipped()
                }
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Icon(.megaphone, size: 12, color: Nuru.goldChipText)
                        Text("FEATURED ANNOUNCEMENT").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText)
                    }
                    Text(a.title).font(.fraunces(20, .semibold)).foregroundStyle(Nuru.ink).padding(.top, Nuru.S.sm)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(a.body).font(.nCaption).foregroundStyle(Nuru.muted).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, Nuru.S.sm)
                    HStack {
                        if let s = a.sentAt { Text(shortDate(s)).font(.nMicro).foregroundStyle(Nuru.faint) }
                        Spacer()
                        Text("Read more ›").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
                    }
                    .padding(.top, Nuru.S.md)
                }
                .padding(Nuru.S.base)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShadow()
        }
        .buttonStyle(.plain)
    }

    // MARK: 10 — Continue · Level n

    private var continueLevelCard: some View {
        let a = active
        let done = a?.completedModules ?? 0
        let total = a?.totalModules ?? 0
        let pct = total > 0 ? Int(round(Double(done) / Double(total) * 100)) : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Nuru.goldChipBg).frame(width: 52, height: 52)
                    Icon(.play, size: 22, color: Nuru.gold)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("CONTINUE · LEVEL \(a?.levelNumber ?? 1)").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText)
                    Text(a?.title ?? "Foundations of Faith").font(.fraunces(20, .semibold)).foregroundStyle(Nuru.ink)
                    Text("\(done) of \(total) modules").font(.nCaption).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Nuru.S.sm) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Nuru.track).frame(height: 6)
                        Capsule().fill(Nuru.gold).frame(width: geo.size.width * CGFloat(pct) / 100, height: 6)
                    }
                }.frame(height: 6)
                Text("\(pct)% complete").font(.inter(11, .bold)).foregroundStyle(Nuru.goldLo)
            }
            .padding(.top, Nuru.S.base)
            Button {
                if let m = nextModuleId { path.append(PathwayRoute.module(m)) }
                else { path.append(PathwayRoute.level(a?.levelNumber ?? 1)) }
            } label: {
                HStack(spacing: 6) {
                    Text("Continue").font(.inter(15, .bold)).foregroundStyle(Nuru.gold)
                    Icon(.chevronRight, size: 15, color: Nuru.gold)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, Nuru.S.base)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    // MARK: 11 — Today's rhythm

    private var rhythmCard: some View {
        let done = vm.rhythm.doneCount
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

    // MARK: 12 — Reflection due today

    private func reflectionBanner(_ a: PathwayLevel) -> some View {
        Button { path.append(PathwayRoute.level(a.levelNumber)) } label: {
            HStack(spacing: Nuru.S.md) {
                Icon(.messageSquareText, size: 18, color: Nuru.goldChipText)
                    .frame(width: 40, height: 40)
                    .background(Nuru.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Reflection due today").font(.inter(14, .bold)).foregroundStyle(Nuru.ink)
                    Text(a.title).font(.nCaption).foregroundStyle(Nuru.muted)
                }
                Spacer(minLength: 0)
                Text("Start reflection").font(.inter(12, .bold)).foregroundStyle(Nuru.gold)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Nuru.navyDeep, in: Capsule())
            }
            .padding(Nuru.S.md)
            .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: 13 — Your progress (scores)

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
                ZStack {
                    Circle().stroke(Nuru.track, lineWidth: 3)
                    Circle().trim(from: 0, to: CGFloat(s.overall.score) / 100)
                        .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: -3) {
                        Text("\(s.overall.score)").font(.fraunces(22, .semibold)).foregroundStyle(Nuru.navyDeep)
                        Text("/100").font(.nMicro).foregroundStyle(Nuru.ink600)
                    }
                }
                .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OVERALL GROWTH").font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldLo)
                    Text(s.overall.band).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.ink)
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
            if let a = active {
                let left = max(0, a.totalModules - a.completedModules)
                HStack(spacing: Nuru.S.sm) {
                    Icon(.target, size: 16, color: Nuru.goldChipText)
                        .frame(width: 30, height: 30)
                        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    (Text("\(left) modules ").font(.inter(12, .bold)).foregroundStyle(Nuru.ink)
                     + Text("left before Level \(a.levelNumber + 1)").font(.inter(12)).foregroundStyle(Nuru.muted))
                    Spacer(minLength: 0)
                }
                .padding(Nuru.S.sm)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(.top, Nuru.S.md)
            }
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

    // MARK: 14 — Grow your faith

    private var growCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            Text("Grow your faith").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: Nuru.S.sm), GridItem(.flexible(), spacing: Nuru.S.sm)], spacing: Nuru.S.sm) {
                ForEach(growTiles.indices, id: \.self) { i in
                    let t = growTiles[i]
                    NavigationLink(value: t.dest) { growTileView(t) }.buttonStyle(.plain)
                }
            }
            NavigationLink(value: AppRoute.mentor) {
                HStack(spacing: Nuru.S.md) {
                    Icon(.users, size: 18, color: Nuru.gold)
                        .frame(width: 36, height: 36)
                        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 1) {
                        Text("YOUR DISCIPLER").font(.inter(10, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText)
                        Text("Meet your discipler").font(.inter(14, .bold)).foregroundStyle(Nuru.ink)
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 16, color: Nuru.ink300)
                }
                .padding(Nuru.S.md)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
            }.buttonStyle(.plain)
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

    // MARK: 15 — Upcoming (mini month + next event)

    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.base) {
            HStack {
                Text("Upcoming").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                Spacer()
                Text("See all ›").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
            }
            HStack(alignment: .top, spacing: Nuru.S.base) {
                miniMonth.frame(maxWidth: .infinity)
                nextEventColumn.frame(width: 132)
            }
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private var miniMonth: some View {
        let cal = Calendar.current
        let today = Date()
        let monthStart = cal.date(from: cal.dateComponents([.year, .month], from: today)) ?? today
        let daysInMonth = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        // Monday-first leading offset
        let firstWeekday = cal.component(.weekday, from: monthStart) // 1=Sun…7=Sat
        let lead = (firstWeekday + 5) % 7
        let cells: [Int?] = Array(repeating: nil, count: lead) + (1...daysInMonth).map { Optional($0) }
        let eventDays: Set<Int> = Set(vm.events.compactMap { occ -> Int? in
            guard let d = ISO8601DateFormatter.nuru.date(from: occ.startAt) ?? ISO8601DateFormatter().date(from: occ.startAt) else { return nil }
            guard cal.isDate(d, equalTo: monthStart, toGranularity: .month) else { return nil }
            return cal.component(.day, from: d)
        })
        let todayNum = cal.isDate(today, equalTo: monthStart, toGranularity: .month) ? cal.component(.day, from: today) : -1
        let mf = DateFormatter(); mf.dateFormat = "MMMM"
        let cols = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)

        return VStack(spacing: 6) {
            Text(mf.string(from: monthStart).uppercased()).font(.inter(11, .bold)).kerning(1.2).foregroundStyle(Nuru.goldChipText)
            LazyVGrid(columns: cols, spacing: 2) {
                ForEach(Array(["M","T","W","T","F","S","S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.inter(9, .semibold)).foregroundStyle(Nuru.ink400).frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: cols, spacing: 4) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let isToday = day == todayNum
                        ZStack {
                            if isToday { Circle().fill(Nuru.navy).frame(width: 24, height: 24) }
                            VStack(spacing: 1) {
                                Text("\(day)")
                                    .font(.inter(11, isToday ? .bold : .medium))
                                    .foregroundStyle(isToday ? Nuru.onNavy : Nuru.ink)
                                if eventDays.contains(day) && !isToday {
                                    Circle().fill(Nuru.gold).frame(width: 4, height: 4)
                                } else {
                                    Color.clear.frame(width: 4, height: 4)
                                }
                            }
                        }
                        .frame(height: 26)
                    } else {
                        Color.clear.frame(height: 26)
                    }
                }
            }
        }
    }

    private var nextEventColumn: some View {
        Group {
            if let occ = vm.events.first(where: { (ISO8601DateFormatter.nuru.date(from: $0.startAt) ?? ISO8601DateFormatter().date(from: $0.startAt) ?? .distantPast) >= Calendar.current.startOfDay(for: Date()) }) ?? vm.events.first {
                Button { path.append(occ) } label: {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(weekdayLine(occ.startAt)).font(.inter(10, .bold)).kerning(0.8).foregroundStyle(Nuru.goldChipText)
                        if let s = occ.primaryImageUrl, let u = URL(string: s) {
                            CachedAsyncImage(url: u) { phase in
                                if let img = phase.image { img.resizable().scaledToFill() }
                                else { Rectangle().fill(Nuru.mutedBg) }
                            }
                            .frame(width: 132, height: 100).clipped()
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .padding(.top, 6)
                        }
                        Text(timeLine(occ.startAt)).font(.inter(11, .bold)).foregroundStyle(Nuru.goldLo).padding(.top, 6)
                        Text(occ.title).font(.inter(13, .bold)).foregroundStyle(Nuru.ink).lineLimit(2).padding(.top, 1)
                        if let loc = occ.location { Text(loc).font(.nMicro).foregroundStyle(Nuru.faint).lineLimit(1).padding(.top, 1) }
                        Text("Next gathering").font(.nMicro).foregroundStyle(Nuru.faint).padding(.top, 1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No upcoming").font(.inter(12, .bold)).foregroundStyle(Nuru.ink)
                    Text("Nothing scheduled yet").font(.nMicro).foregroundStyle(Nuru.faint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: 16 — One-reflection-away banner

    private var oneReflectionBanner: some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(.sparkle, size: 16, color: Nuru.goldChipText)
                .frame(width: 32, height: 32)
                .background(Nuru.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text("You're one reflection away from completing this week's rhythm.")
                .font(.inter(12, .medium)).foregroundStyle(Nuru.goldChipText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.md)
        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: 17 — Your cohort

    private var cohortCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: AppRoute.cell) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Nuru.S.sm) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Your cell").font(.inter(15, .semibold)).foregroundStyle(Nuru.ink)
                            Text(vm.cell?.name ?? "Your discipleship cell").font(.nCaption).foregroundStyle(Nuru.muted)
                        }
                        Spacer(minLength: 0)
                        Text("Details").font(.inter(12, .semibold)).foregroundStyle(Nuru.goldLo)
                        Icon(.chevronRight, size: 12, color: Nuru.goldLo)
                    }
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Nuru.S.sm), GridItem(.flexible(), spacing: Nuru.S.sm)], spacing: Nuru.S.sm) {
                        cohortStat(.users, "Leader", vm.cell?.leader?.name ?? "Not assigned")
                        cohortStat(.calendarDays, "Next gathering", nextGatheringText)
                        cohortStat(.handHeart, "Members", vm.cell.map { "\($0.members)" } ?? "—")
                        cohortStat(.percent, "Attendance", attendanceText)
                    }
                    .padding(.top, Nuru.S.md)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            NavigationLink(value: CommunityRoute.prayerWall) {
                HStack {
                    Spacer()
                    Text("Open community ›").font(.inter(13, .bold)).foregroundStyle(Nuru.gold)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(Nuru.navyDeep, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func cohortStat(_ icon: Lucide, _ label: String, _ value: String) -> some View {
        HStack(spacing: Nuru.S.sm) {
            Icon(icon, size: 14, color: Nuru.goldChipText)
                .frame(width: 30, height: 30)
                .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.nMicro).foregroundStyle(Nuru.faint)
                Text(value).font(.inter(13, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.sm)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var nextGatheringText: String {
        guard let n = vm.cell?.next else { return "TBA" }
        return shortDateTime(n.startAt)
    }
    private var attendanceText: String {
        guard let a = vm.cell?.attendance, a.expected > 0 else { return "—" }
        return "\(a.attended)/\(a.expected)"
    }

    // MARK: 18 — Announcements list

    private var announcementsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ANNOUNCEMENTS").font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                Spacer()
                Text("View all ›").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldLo)
            }
            VStack(spacing: Nuru.S.md) {
                ForEach(vm.announcements.prefix(4)) { a in
                    Button {
                        path.append(AppRoute.announcement(a.announcementId))
                        Task { await vm.openAnnouncement(a.announcementId) }
                    } label: {
                        announcementRow(a)
                    }.buttonStyle(.plain)
                }
            }
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func announcementRow(_ a: MyAnnouncement) -> some View {
        HStack(alignment: .top, spacing: Nuru.S.sm) {
            if let s = a.primaryImageUrl, let u = URL(string: s) {
                CachedAsyncImage(url: u) { phase in
                    if let img = phase.image { img.resizable().scaledToFill() }
                    else { Rectangle().fill(Nuru.mutedBg) }
                }
                .frame(width: 56, height: 56).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Icon(.megaphone, size: 18, color: Nuru.goldChipText)
                    .frame(width: 56, height: 56)
                    .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(a.title).font(.inter(13, .bold)).foregroundStyle(Nuru.ink).lineLimit(1)
                Text(a.body).font(.nMicro).foregroundStyle(Nuru.muted).lineLimit(2)
                if let s = a.sentAt { Text(shortDate(s)).font(.nMicro).foregroundStyle(Nuru.faint) }
            }
            Spacer(minLength: 0)
            if !a.opened { Circle().fill(Nuru.gold).frame(width: 8, height: 8).padding(.top, 4) }
        }
    }

    // MARK: 19 — Support God's work (give banner)

    private var giveBanner: some View {
        ZStack {
            Nuru.ceremonyGradient
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Icon(.heart, size: 12, color: Nuru.goldGlow)
                    Text("SUPPORT GOD'S WORK").font(.inter(11, .bold)).kerning(1.4).foregroundStyle(Nuru.goldGlow)
                }
                Text("Sow into something eternal").font(.fraunces(22, .semibold)).foregroundStyle(Nuru.onNavy).padding(.top, Nuru.S.sm)
                Text("Every gift carries the gospel further — raising disciples, sustaining the mission, and lighting the way for the next person to find Christ. Give cheerfully, as the Lord leads.")
                    .font(.nCaption).foregroundStyle(Nuru.onNavyDim).padding(.top, Nuru.S.sm)
                    .fixedSize(horizontal: false, vertical: true)
                Button { tabs.selected = .give } label: {
                    HStack(spacing: 6) {
                        Icon(.gift, size: 15, color: Nuru.navyDeep)
                        Text("Give now").font(.inter(15, .bold)).foregroundStyle(Nuru.navyDeep)
                        Icon(.arrowRight, size: 14, color: Nuru.navyDeep)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Nuru.goldGradient, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, Nuru.S.base)
                Text("Tithe & offering · M-Pesa, card and more").font(.nMicro).foregroundStyle(Nuru.onNavyFaint)
                    .frame(maxWidth: .infinity).padding(.top, Nuru.S.sm)
            }
            .padding(Nuru.S.lg)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .nuruShadow()
    }

    // MARK: derived / helpers

    /// The announcement the "This week at Nuru" card opens — the featured one, or
    /// the most recent announcement as a fallback.
    private var weekAnnouncementId: String? {
        vm.featuredAnnouncement?.announcementId ?? vm.announcements.first?.announcementId
    }

    /// The specific next lesson to resume, when the next-action CTA is a module.
    private var nextModuleId: String? {
        guard let a = vm.nextAction, a.route == "module" else { return nil }
        return a.params?.moduleId
    }

    private func verseShareText() -> String {
        let text = vm.verse?.text ?? "“Your word is a lamp to my feet, and a light for my path.”"
        let ref = vm.verse?.reference ?? "Psalm 119:105"
        let ver = vm.verse?.version ?? "WEB"
        return "\(text)\n— \(ref) (\(ver))"
    }

    private func videoShareText(_ v: WelcomeVideo) -> String {
        let cap = v.caption ?? "A word for your week"
        return v.playUrl.map { "\(cap)\n\($0)" } ?? cap
    }

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
        let f = DateFormatter(); f.dateFormat = "EEEE · MMM d"
        return f.string(from: Date()).uppercased() + " · EAT"
    }
    private func durationLabel(_ sec: Int) -> String {
        let m = sec / 60, s = sec % 60
        return String(format: "%d:%02d", m, s)
    }
    private func openURL(_ s: String?) {
        guard let s, let u = URL(string: s) else { return }
        UIApplication.shared.open(u)
    }
    /// Parse an ISO timestamp tolerantly.
    private func parseISO(_ iso: String) -> Date? {
        ISO8601DateFormatter.nuru.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
    }
    private func shortDate(_ iso: String) -> String {
        guard let d = parseISO(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "MMM d"; return f.string(from: d)
    }
    private func shortDateTime(_ iso: String) -> String {
        guard let d = parseISO(iso) else { return "TBA" }
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"; return f.string(from: d)
    }
    private func weekdayLine(_ iso: String) -> String {
        guard let d = parseISO(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; return f.string(from: d).uppercased()
    }
    private func timeLine(_ iso: String) -> String {
        guard let d = parseISO(iso) else { return "" }
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f.string(from: d)
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
