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
    @Published var verseArt: VerseArt?   // the day's tableau photograph (server-curated)
    /// Seven-bands addition — when present, replaces the "Chosen for your
    /// season" ribbon with a personal encouragement quote + attribution.
    @Published var verseEncouragement: Encouragement?
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
    /// GET /home/events — up to 5 curated, soonest-first rows for the "Upcoming"
    /// section. Server-capped and pre-sorted; rendered exactly as received.
    @Published var homeEvents: [HomeEventRow] = []
    /// The radio broadcast that is live RIGHT NOW (nil = off air). The now-playing
    /// endpoint also returns the next scheduled show — that must stay off Home.
    @Published var onAir: RadioProgram?
    /// The ONE admin-featured event (portal homepage toggle) — nil when unset.
    @Published var featuredEvent: FeaturedEvent?
    /// GET /live/now rows — a live church stream (if any) plus a live stream
    /// for the member's OWN cell (server-scoped; never re-filtered by cell
    /// here). Empty most of the time; the LIVE banner only renders while a
    /// church-scope row is present.
    @Published var liveStreams: [LiveStreamSummary] = []

    @Published var loading = true
    @Published var error: String?
    /// The latest Sunday Letter (intelligence layer) — drives the gold
    /// "A letter for you" knock on Home while unread.
    @Published var letter: PastoralLetter?
    /// Flips true the moment the THIRD rhythm discipline lands DURING this
    /// session — a refresh moving 2→3, never a first load that arrives already
    /// done. Per-session only (nothing persisted): the rhythm card answers with
    /// one soft gold sweep and a "Day sealed" line that stays.
    @Published var daySealed = false
    private var lastRhythmDone: Int?

    func load() async {
        loading = true; error = nil
        async let letter = try? MemberAPI.latestLetter()
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
        async let hev = try? MemberAPI.homeEvents()
        async let fev = try? MemberAPI.featuredEvent()
        async let radio = try? MemberAPI.radioNowPlaying()
        async let live = try? MemberAPI.fetchLiveNow()

        self.letter = (await letter) ?? nil
        self.pathway = await pathway
        let achievements = await ach
        self.streak = achievements?.streak?.current ?? 0
        self.unread = await unread ?? 0
        if let g = await greet, !g.isEmpty { greetingLine = g }
        self.nextAction = await next ?? nil
        if let r = await rhythm { self.rhythm = r }
        // Day sealed — only a WITNESSED completion counts (a count this session
        // below 3 rising to 3). All-done on the very first load stays quiet.
        if let prev = lastRhythmDone, prev < 3, self.rhythm.doneCount == 3 { daySealed = true }
        lastRhythmDone = self.rhythm.doneCount
        self.scores = await scores
        self.reactions = await vr

        if let v = await hv {
            if let t = v.text, !t.isEmpty { verse = (t, v.reference, v.version) }
            else if let passage = try? await MemberAPI.scripture(v.reference) {
                verse = (passage.text, passage.reference, passage.version)
            }
            verseReason = v.reason
            verseArt = (v.art?.url.isEmpty == false) ? v.art : nil
            verseEncouragement = v.encouragement
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
        // Rendered exactly as received — the server caps at 5 and orders
        // soonest-first; the client never caps, sorts, or filters.
        self.homeEvents = await hev ?? []
        self.onAir = Self.liveOnly((await radio) ?? nil)
        self.featuredEvent = (await fev) ?? nil
        self.liveStreams = await live ?? []

        if self.pathway == nil { error = "Couldn't load your dashboard." }
        loading = false

        celebrateMilestones(achievements)
    }

    // MARK: Celebrations — server-truth milestones only (mirrors Android).
    // Every fact below came back from the API this load; the CelebrationCenter
    // keys make each moment once-only across launches.
    private func celebrateMilestones(_ ach: Achievements?) {
        // All three rhythm disciplines done today (server ticks each from real acts).
        if rhythm.doneCount == 3 {
            CelebrationCenter.shared.fire(
                key: "rhythm-\(Self.isoDay(Date()))",
                title: "Today's rhythm complete",
                subtitle: "Prayer, Word and reflection — all three, today. 🎉")
        }
        // Streak milestones — the server's current streak, exact marks only.
        if [3, 7, 14, 21, 30, 50, 100].contains(streak) {
            CelebrationCenter.shared.fire(
                key: "streak-\(streak)",
                title: "\(streak)-day streak!",
                subtitle: "Day by day, grace upon grace. Keep walking.")
        }
        // Newly-awarded badges — diff earned codes against what we've celebrated.
        // The FIRST observation seeds silently so a fresh install doesn't replay
        // the member's whole badge history.
        if let earned = ach?.badges {
            let defaults = UserDefaults.standard
            if let seen = defaults.stringArray(forKey: "seen-badges") {
                for badge in earned where !seen.contains(badge.code) {
                    CelebrationCenter.shared.fire(
                        key: "badge-\(badge.code)",
                        title: "\(badge.name) earned!",
                        subtitle: "A new badge marks real growth — well done.")
                }
            }
            defaults.set(earned.map(\.code), forKey: "seen-badges")
        }
    }

    // Rhythm — read-only on this surface: the server ticks each rhythm from
    // real acts (prayer posted/encouraged, Scripture engaged, reflection written).
    func done(_ kind: String) -> Bool {
        switch kind { case "prayer": return rhythm.prayer; case "word": return rhythm.word; default: return rhythm.reflection }
    }

    // Verse
    /// Toggle my reaction to today's verse. OPTIMISTIC: the tap shows instantly
    /// (one reaction per member/day — tapping my current emoji removes it, a
    /// different one MOVES it), then we reconcile with the server. A dropped or
    /// failed request rolls back to the prior counts instead of blanking them
    /// (the old `try?` swallowed errors into nil, so a slow tap read as "nothing
    /// happened" — the reported bug).
    func reactVerse(_ emoji: String) async {
        let previous = reactions
        var r = reactions ?? VerseReactions()
        func drop(_ e: String) {
            let n = (r.counts[e] ?? 0) - 1
            if n > 0 { r.counts[e] = n } else { r.counts[e] = nil }
        }
        if r.mine == emoji {
            drop(emoji); r.mine = nil                    // tapped my own → remove
        } else {
            if let old = r.mine { drop(old) }            // move off the old one
            r.counts[emoji, default: 0] += 1; r.mine = emoji
        }
        r.total = r.counts.values.reduce(0, +)
        reactions = r                                    // instant feedback
        do { reactions = try await MemberAPI.setVerseReaction(emoji) }
        catch { reactions = previous }                   // server said no → restore
    }
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

    // Radio — lightweight re-check (polled while Home is visible) so the ON AIR
    // card appears/disappears as broadcasts start and end without a full reload.
    func refreshOnAir() async {
        onAir = Self.liveOnly((try? await MemberAPI.radioNowPlaying()) ?? nil)
    }
    private static func liveOnly(_ p: RadioProgram?) -> RadioProgram? {
        guard let p, p.live else { return nil }
        return p
    }

    /// Nuru Live re-check — piggybacks Home's existing refresh cycle (this is
    /// called from a 60s timer that only RUNS while something is confirmed
    /// live; see HomeView's `.task(id: vm.liveStreams.isEmpty)`), so the LIVE
    /// banner's "started Xm ago · N watching" line stays current and the
    /// banner disappears promptly once the stream ends.
    func refreshLiveNow() async {
        liveStreams = (try? await MemberAPI.fetchLiveNow()) ?? []
    }

    // Two-month calendar window around today (drives the Live-now banner; the
    // "Upcoming" section now renders GET /home/events curated rows instead).
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

extension HomeView {
    /// Clearance for a surface docked "above the tab bar" from WITHIN Home's
    /// own view tree (the mini-window pop-up) — the tab bar itself is a
    /// SIBLING overlay one level up in RootView, so this can't rely on
    /// SwiftUI layout and instead mirrors NuruTabBar's own on-screen height
    /// (6pt top padding + 44pt icon row + its bottom clearance) plus the
    /// device's real safe-area inset.
    static var tabBarClearance: CGFloat { NuruSafeArea.bottom + 58 }
}

private let verseReactionEmojis = ["❤️", "🙏", "🔥", "🙌", "👍"]
private let videoReactionEmojis = ["🙏", "🔥", "🎉", "👏"]
private struct GrowTile { let label, sub: String; let icon: Lucide; let tint, fg: UInt32; let dest: AnyHashable }

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @StateObject private var vm = HomeViewModel()
    // (RadioCenter is observed inside HomeOnAirCard / the RootView island pill —
    // observing it here re-rendered the whole feed on every playback tick.)
    @State private var path = NavigationPath()
    /// Featured-carousel position (auto-advances every 6s; swipes respected).
    @State private var featuredPageIndex = 0
    @State private var playingVideo = false
    /// Poster frames cut from videos the server gave no thumbnail for.
    @StateObject private var posters = VideoPosterCache.shared
    @State private var posterTick: UInt8 = 0
    @State private var prayPage = 0   // prayer-wall pager position (drives our gold dots)
    @State private var disciplerPage = 0   // discipler pager position (same gold dots)
    @State private var videoReady = false   // welcome video finished buffering its embed
    @State private var sharePayload: SharePayload?
    @State private var verseShareDialog = false
    @State private var verseShareImage: VerseImagePayload?
    @State private var openedLetter: PastoralLetter?   // Sunday Letter sheet
    // Nuru Live (L2, viewer-only) — the church-scope LIVE banner's player + replays.
    @State private var openLiveItem: LivePlayableItem?
    @State private var openReplays = false
    /// Church service check-in, presented from the header's scan button.
    @State private var showServiceScanner = false
    // Nuru Live discovery — the shared "invite loudly, never hijack" center
    // that also drives the app-wide LIVE bar and notification routing; Home
    // feeds it every /live/now poll and shows its mini-window pop-up.
    @ObservedObject private var liveDiscovery = LiveDiscoveryCenter.shared
    // Nuru Live (L3, broadcaster) — Home's header "Go Live" icon. The
    // controller itself lives in BroadcastCenter (app-wide), not here — see
    // RootView for the single fullScreenCover presentation + floating island.
    @ObservedObject private var broadcast = BroadcastCenter.shared
    @State private var showGoLiveSheet = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // "Day sealed" — one soft gold radial sweep over the rhythm card when the
    // third discipline lands mid-session. Opacity-only, and Reduce Motion never
    // stages it (the haptic + caption still speak).
    @State private var sealGlow: Double = 0
    // One-shot feed entrance — plays ONCE per app session, the first time real
    // content replaces the skeleton. Static, so tab hops, refreshes and even a
    // text-size rebuild (RootView's `.id(textScale)`) can never replay it.
    private static var feedEntranceDone = false
    @State private var feedStaged = false   // rows begin hidden, awaiting the rise
    @State private var feedRisen = false    // the staggered rise has run

    // The five Grow tiles from the fresh Figma GrowGrid (exact tints/labels).
    private var growTiles: [GrowTile] {
        [
            GrowTile(label: "Devotional", sub: "Today's devotional", icon: .sun, tint: 0xFFF4DA, fg: 0x9A7A2A, dest: GrowDestination.devotional),
            GrowTile(label: "Reading plan", sub: "Continue your plan", icon: .bookMarked, tint: 0xEEF2FF, fg: 0x6366F1, dest: GrowDestination.readingPlans),
            GrowTile(label: "Hide His Word", sub: "Memorize Scripture", icon: .quote, tint: 0xFEF3C7, fg: 0xB45309, dest: GrowDestination.memoryVerses),
            GrowTile(label: "Your Calling", sub: "Discover your gifts", icon: .sparkles, tint: 0xF5E8FF, fg: 0xA855F7, dest: GrowDestination.gifts),
            GrowTile(label: "My Prayer Room", sub: "Pray with the family", icon: .handHeart, tint: 0xFEE2E2, fg: 0xDC2626, dest: CommunityRoute.prayerWall),
        ]
    }

    // The Home feed as an ARRAY of individually type-erased views. This is the only
    // form that reliably avoids the on-device type-demangler stack overflow: the
    // enclosing VStack/ForEach type is flat (`ForEach<…, AnyView>`), and each card's
    // (deeply-generic) type is demangled ONE AT A TIME here — in a shallow stack —
    // as its AnyView box is built. `some View` groups and even AnyView-of-6 still
    // forced the runtime to decode several cards' types together and overflowed.
    // Section order mirrors the fresh Figma HomeTab return block exactly (with the
    // radio ON AIR hero pinned first whenever a broadcast is live):
    // Radio ON AIR → LiveNow → Priority → continue hero → rhythm → video → verse → pray →
    // plans/journal → this week → disciplers → announcement → continue level → Priority
    // (repeat) → progress → Grow → Upcoming → encouragement → cohort → give.
    private var feedSections: [(id: String, view: AnyView)] {
        // TRUE first load only (refreshes keep the live content in place) —
        // shimmering placeholders instead of a blank scroll.
        if vm.loading && vm.pathway == nil {
            return [("skeleton", AnyView(HomeFeedSkeleton()))]
        }
        // STABLE ids, not array offsets: when the radio bar arrives late and
        // inserts at the top, every other row must keep its identity — offset
        // keys made SwiftUI tear down and rebuild every card below it.
        var s: [(id: String, view: AnyView)] = []
        // Nuru Live — the church-scope LIVE banner sits at the very TOP of the
        // whole feed, above even the load-error strip: a live broadcast is the
        // most urgent thing on the screen. Hidden entirely when nothing church-
        // scope is live (no fake "off air" chrome on Home).
        if let live = churchLiveStream {
            s.append(("livebanner", AnyView(liveBannerCard(live))))
        }
        // The whole dashboard failed (offline / server down) — a quiet retry
        // strip on top; the sections below degrade gracefully as usual.
        if vm.error != nil && vm.pathway == nil {
            s.append(("loaderror", AnyView(HomeLoadErrorCard { Task { await vm.load() } })))
        }
        if let p = vm.onAir { s.append(("onair", AnyView(onAirCard(p)))) }                         // 0a · Radio ON AIR (pinned first, only while live)
        // Owner's order (2026-08-25, stated exactly): verse for today → featured
        // video → the Sunday Letter → reflection due → the liturgy. Everything
        // else stays where it always was — the ONLY move relative to the
        // original feed is the liturgy stepping BELOW the reflection strip.
        s.append(("verse", AnyView(verseCard)))                                                    // 0 · Verse of the day (leads the feed)
        if let v = vm.welcomeVideo { s.append(("video", AnyView(welcomeVideoCard(v)))) }           // 0a2 · Featured video (start here)
        if let live = liveNowInfo { s.append(("livenow", AnyView(liveNowCard(live)))) }              // 0b · Live now
        if let lt = vm.letter, lt.isUnread {
            s.append(("letter", AnyView(letterKnock(lt))))
        } else if let lt = vm.letter {
            s.append(("letter", AnyView(letterReadRow(lt))))
        } else {
            s.append(("letter", AnyView(letterArrivalCard)))
        }
        if reflectionDue { s.append(("priority", AnyView(priorityStrip))) }                           // 1 · Priority
        s.append(("liturgy", AnyView(HomeLiturgyCard())))                                            // The hour's prayer — below the reflection strip (owner)
        s.append(("echo", AnyView(HomeEchoCard())))                                               // 0e · Today's echo — the app remembers you (Wave 1)
        if let a = vm.nextAction { s.append(("hero", AnyView(heroCard(a)))) }                     // 2
        s.append(("rhythm", AnyView(rhythmCard)))                                                   // 2b · Today's rhythm (right under For-you-today)
        s.append(("selah1", AnyView(SelahDivider())))                                               // — selah: a rest for the eye
        if let rp = resumePlan { s.append(("planresume", AnyView(planResumeBanner(rp)))) }              // 2c · Continue your plan (resume nudge)
        if !vm.prayerPosts.isEmpty { s.append(("prayerwall", AnyView(prayerWallCard))) }                // 5
        s.append(("celebrations", AnyView(CelebrationsRail())))                                           // 5b · Celebrate the family (moments, Phase 4)
        s.append(("minis", AnyView(minisRow)))                                                     // 6
        // A card that shows a CELL opens that CELL (owner, 2026-08-26: tapping it
        // opened an unrelated announcement — the card's own "this week" framing
        // had been wired to the week's first announcement id).
        if let c = vm.featuredCell {                                                    // 7
            s.append(("cell", AnyView(
                NavigationLink(value: AppRoute.cell) { featuredCellCard(c) }
                    .buttonStyle(.pressableSubtle)
            )))
        }
        if !vm.disciplers.isEmpty { s.append(("disciplers", AnyView(disciplersCard))) }                 // 8
        if !featuredPages.isEmpty { s.append(("announcement", AnyView(featuredCarousel))) }             // 9 · carousel: portal-marked announcements + events
        s.append(("continuelevel", AnyView(continueLevelCard)))                                            // 10
        if reflectionDue { s.append(("priority2", AnyView(priorityStrip))) }                           // 12 · Priority (repeat)
        if let sc = vm.scores { s.append(("progress", AnyView(progressCard(sc)))) }                   // 13
        s.append(("selah2", AnyView(SelahDivider())))                                               // — selah: a rest before Grow
        s.append(("grow", AnyView(growSection)))                                                  // 14
        if let fe = vm.featuredEvent { s.append(("event", AnyView(featuredGatheringCard(fe)))) }   // 14b · admin-featured event
        if !vm.homeEvents.isEmpty { s.append(("upcoming", AnyView(upcomingSection))) }                // 15 · curated rows; empty → whole section (header too) hides
        s.append(("encourage", AnyView(oneReflectionBanner)))                                          // 16
        s.append(("cohort", AnyView(cohortSection)))                                                // 17
        s.append(("give", AnyView(giveBanner)))                                                   // 18
        #if targetEnvironment(simulator) && DEBUG
        // Scripted visual verification: NURU_UITEST_TOP=<row id> hoists that row
        // to the top of the feed so a headless screenshot can behold it.
        if let top = ProcessInfo.processInfo.environment["NURU_UITEST_TOP"],
           let idx = s.firstIndex(where: { $0.id == top }), idx > 0 {
            s.insert(s.remove(at: idx), at: 0)
        }
        #endif
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
                    // 20pt between sections — the 16pt grid read congested with
                    // this many cards; each one gets room to breathe (owner ask).
                    // Spacing-by-padding: each row OWNS its 20pt skirt as part
                    // of its layout frame instead of negotiating VStack spacing
                    // with its neighbour. On the owner's device something kept
                    // collapsing inter-row spacing around the radio/liturgy/echo
                    // rows (two fixes survived in the sim, not in the field) —
                    // intrinsic padding is part of the row's own geometry and
                    // cannot be eaten by identity, insertion, or animation.
                    VStack(spacing: 0) {
                        ForEach(Array(feedSections.enumerated()), id: \.element.id) { i, section in
                            // One-shot entrance, OPACITY ONLY. The old 12pt rise
                            // painted rows away from their layout slot, and two
                            // separate races stranded it mid-flight — cards fused
                            // on device (owner screenshots). A card must never be
                            // painted anywhere but where layout puts it: fades
                            // can't move geometry, so stacking is now impossible
                            // by construction.
                            let entering = feedStaged && i < 8
                            section.view
                                .padding(.bottom, 20)
                                .opacity(entering && !feedRisen ? 0 : 1)
                                .animation(entering ? .easeOut(duration: 0.45).delay(Double(i) * 0.04) : nil,
                                           value: feedRisen)
                        }
                    }
                    .padding(.horizontal, Nuru.S.base)
                    .padding(.top, Nuru.S.base)
                    .padding(.bottom, Nuru.tabBarSpace - 20)  // last row brings its own 20pt skirt
                }
            }
            .ignoresSafeArea(edges: .top)
            .background(Nuru.paper.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await vm.load() }
            // Arm the one-shot entrance the moment real content replaces the
            // skeleton — and never again (feedEntranceDone). Reduce Motion
            // skips it entirely: cards simply stand where they belong.
            .onChange(of: vm.loading) { _, isLoading in
                guard !isLoading, vm.pathway != nil, !Self.feedEntranceDone else { return }
                Self.feedEntranceDone = true
                guard !reduceMotion else { return }
                feedStaged = true   // rows render hidden this frame…
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { feedRisen = true }   // …then rise
                // RETIRE the entrance once every stagger has finished (8 × 40ms
                // + 0.5s spring ≈ 0.9s): with feedStaged back to false, every
                // row's offset/opacity become PLAIN zeros — no expression left
                // to linger. Without this, a scheduling race could strand a
                // row 12pt low and visually fuse it into its neighbour
                // (owner-reported "cards mangled together").
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                    var tx = Transaction(); tx.disablesAnimations = true
                    withTransaction(tx) { feedStaged = false }
                }
            }
            // Home root always shows the tab bar (plan screens hide it while inside).
            .onAppear { tabs.chromeHidden = false }
            .nuruDestinations()
        }
        // Tapping one of our iOS notifications lands on the in-app inbox.
        .onReceive(NotificationCenter.default.publisher(for: .nuruOpenNotifications)) { _ in
            tabs.selected = .home
            if !path.isEmpty { path = NavigationPath() }
            path.append(AppRoute.notifications)
        }
        // A tapped announcement notification opens the announcement itself.
        .onReceive(tabs.$announcementLink) { id in
            guard let id else { return }
            if !path.isEmpty { path = NavigationPath() }
            path.append(AppRoute.announcement(id))
            Task { await vm.openAnnouncement(id) }
            DispatchQueue.main.async { tabs.announcementLink = nil }
        }
        .sheet(item: $sharePayload) { ShareToChatSheet(text: $0.text) }
        // Church check-in — presented, not pushed, so the camera is a modal the
        // member dismisses back to exactly where they were.
        .fullScreenCover(isPresented: $showServiceScanner) {
            ServiceCheckInView(memberName: auth.profile?.fullName ?? "",
                               memberPhone: auth.profile?.phoneNumber ?? "",
                               memberEmail: auth.profile?.email)
        }
        // `.id($0.id)` — flicker guard, see LiveViewerPlayerView's header note.
        .fullScreenCover(item: $openLiveItem) { LiveViewerPlayerView(item: $0, replaysScope: "church").id($0.id) }
        .sheet(isPresented: $openReplays) { LiveReplaysView(scope: "church") }
        .sheet(isPresented: $showGoLiveSheet) {
            GoLiveSetupSheet { BroadcastCenter.shared.start(session: $0) }
        }
        .sheet(item: $openedLetter) { lt in
            LetterView(letter: lt) {
                // Read on the server — clear the knock locally too. Every v2
                // field carries over unchanged; only readAt flips.
                if let cur = vm.letter, cur.letterId == lt.letterId {
                    vm.letter = PastoralLetter(letterId: cur.letterId, weekOf: cur.weekOf, title: cur.title,
                                               salutation: cur.salutation, theme: cur.theme, imageKey: cur.imageKey,
                                               body: cur.body, scriptureRef: cur.scriptureRef, highlights: cur.highlights,
                                               nextStep: cur.nextStep, shareLine: cur.shareLine, createdAt: cur.createdAt,
                                               readAt: ISO8601DateFormatter().string(from: Date()))
                }
            }
        }
        // Nuru Live discovery — the mini-window pop-up: a MUTED autoplaying
        // preview docked above the tab bar for the first stream this session
        // hasn't seen yet. "Join live" opens the SAME full player the banner's
        // "Watch live" does (unmuted); ✕ collapses it to the ordinary LIVE
        // banner card above and never re-pops for this stream_id again.
        .overlay(alignment: .bottom) {
            if let id = liveDiscovery.popupStreamId,
               let stream = liveDiscovery.streams.first(where: { $0.streamId == id }) {
                LiveMiniPopup(
                    stream: stream,
                    onJoin: { liveDiscovery.markSeen(stream.streamId); openLiveItem = .live(stream) },
                    onDismiss: { liveDiscovery.dismissPopup(stream.streamId) }
                )
                .padding(.bottom, Self.tabBarClearance)
                .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: liveDiscovery.popupStreamId)
        .task {
            if vm.pathway == nil { await vm.load() }
            liveDiscovery.ingest(vm.liveStreams)
            deepLinkForScreenshots()
        }
        // Radio poll — re-check now-playing every 45s while Home is visible so the
        // ON AIR card appears/disappears as broadcasts start and end. The `.task`
        // is cancelled automatically when Home leaves the screen.
        .task {
            while !Task.isCancelled {
                await vm.refreshOnAir()
                try? await Task.sleep(nanoseconds: 45_000_000_000)
            }
        }
        // The floating radio pill now lives in RootView (island-style, top
        // center, on EVERY tab) — playback still runs through RadioCenter.
        // Nuru Live discovery — an UNCONDITIONAL 60s re-check while Home is
        // visible (this used to gate on `vm.liveStreams.isEmpty` and only poll
        // once something was already known live, but discovering a BRAND NEW
        // stream is the whole point of the mini-window pop-up, so it can't
        // wait for a stream to already be known). Every result is folded into
        // the shared LiveDiscoveryCenter, which decides whether to pop the
        // mini-window (a stream_id this session hasn't surfaced yet).
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                await vm.refreshLiveNow()
                liveDiscovery.ingest(vm.liveStreams)
            }
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
                // The kicker carries a tiny sky: sunrise, sun, sunset or moon
                // matching the hour — the same clock that tints the gradient.
                HStack(spacing: 6) {
                    Image(systemName: skyGlyph).font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Nuru.gold)
                    Text(todayKicker()).font(.inter(11, .semibold)).kerning(2.42).foregroundStyle(Color(hex: 0x9A7A2A))
                        .lineLimit(1).minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // Church check-in. First in the row because it is the most
                // time-critical thing a member does from this screen: they are
                // walking through the door and the QR is already on the wall,
                // so it must not cost a trip through the You tab to reach.
                Button {
                    Haptics.tap()
                    showServiceScanner = true
                } label: {
                    Icon(.qrCode, size: 18, color: Color(hex: 0xA8861C))
                        .frame(width: 40, height: 40)
                        .background(Color(hex: 0xFFF4DA), in: Circle())
                        .overlay(Circle().stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Scan to check in")
                .padding(.trailing, 8)
                NavigationLink(value: AppRoute.notifications) {
                    ZStack(alignment: .topTrailing) {
                        Icon(.bell, size: 18, color: Color(hex: 0xA8861C))
                            .frame(width: 40, height: 40)
                            .background(Color(hex: 0xFFF4DA), in: Circle())
                            .overlay(Circle().stroke(Nuru.gold.opacity(0.35), lineWidth: 1))
                        if vm.unread > 0 {
                            HomeUnreadBadge(count: vm.unread).offset(x: 5, y: -5)
                        }
                    }
                }
                .buttonStyle(.pressable)
                .simultaneousGesture(TapGesture().onEnded { Haptics.tap() })
                // Radio used to sit here. It moved out so the resting header is
                // three buttons (scan · bell · ring) rather than five — it is
                // still reachable from the On Air card below, the Community hub
                // and the radio deep link.
                // Nuru Live header entry (2026-07-31 viewer redesign) — same
                // visual family as the buttons beside it (pulsing red
                // ring, small glyph), shown ONLY while a church-scope stream
                // is actually live (`churchLiveStream`, the same /live/now
                // state that already drives the feed's top banner — no
                // second poll). Tap opens the SAME full player the banner's
                // "Watch live" does.
                if let live = churchLiveStream {
                    Button {
                        Haptics.action()
                        liveDiscovery.markSeen(live.streamId)
                        openLiveItem = .live(live)
                    } label: {
                        ZStack {
                            Circle().fill(Color(hex: 0xFEE2E2))
                            Circle().stroke(Color(hex: 0xDC2626).opacity(0.35), lineWidth: 1)
                            HomeLiveHeaderRing()
                            Image(systemName: "waveform")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color(hex: 0xDC2626))
                        }
                        .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.pressable).padding(.leading, 8)
                    .accessibilityLabel("Live now — \(live.title)")
                }
                // Nuru Live (L3) — gold "Go Live" affordance, visible ONLY when
                // the signed-in profile actually holds the `live:go` grant
                // (client-side advisory gate; the server is the real one).
                if LiveBroadcastEligibility.canGoLive(auth.profile) {
                    Button {
                        Haptics.tap()
                        // Already broadcasting (minimized elsewhere) — reopen
                        // it rather than minting a second stream on top.
                        if broadcast.controller != nil { broadcast.restore() } else { showGoLiveSheet = true }
                    } label: {
                        Image(systemName: "video.fill").font(.system(size: 16))
                            .foregroundStyle(Nuru.navy).frame(width: 40, height: 40)
                            .background(Nuru.gold, in: Circle())
                            .overlay(Circle().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.pressable).padding(.leading, 8)
                    .accessibilityLabel("Go live")
                }
                progressRing.padding(.leading, 8)
            }
            Text("\(greeting), \(firstName).")
                .font(.fraunces(22, .semibold)).kerning(-0.22).foregroundStyle(Nuru.navy)
                .lineLimit(1).minimumScaleFactor(0.8)   // long first names shrink, never wrap
                .padding(.top, 10)
                .gentleEntrance()
            // Nuru's daily word — a blessing written for THIS member (grounded in
            // their streak/level/prayers server-side, cached per day). It deserves
            // more than flat gray: a hanging gold quote and a settled serif voice.
            HomePersonalWord(text: vm.greetingLine)
                .padding(.top, 6)
            if let a = active {
                // The journey jewel — level · modules · streak, ringed in a soft
                // gold gradient with a lit flame when the streak is alive.
                HStack(spacing: 6) {
                    Text("Level \(a.levelNumber)").font(.inter(12, .bold)).foregroundStyle(Nuru.navy)
                    Circle().fill(Nuru.gold.opacity(0.6)).frame(width: 3, height: 3)
                    Text("\(a.completedModules) of \(a.totalModules) modules")
                        .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    Circle().fill(Nuru.gold.opacity(0.6)).frame(width: 3, height: 3)
                    if vm.streak > 0 {
                        HStack(spacing: 3) {
                            Icon(.flame, size: 11, color: Color(hex: 0xDC6B26))
                            Text("\(vm.streak)-day").font(.inter(12, .bold)).foregroundStyle(Color(hex: 0xB4530A))
                                .contentTransition(.numericText())
                                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: vm.streak)
                        }
                    } else {
                        Text("Begin today").font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.white, in: Capsule())
                .overlay(Capsule().stroke(
                    LinearGradient(colors: [Nuru.gold.opacity(0.75), Nuru.gold.opacity(0.25), Nuru.gold.opacity(0.75)],
                                   startPoint: .leading, endPoint: .trailing), lineWidth: 1))
                .shadow(color: Nuru.gold.opacity(0.18), radius: 5, y: 2)
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, NuruSafeArea.top + 8)   // past the paper status stripe on EVERY phone
        .padding(.bottom, 16)
        .background(
            LinearGradient(colors: [headerPalette.top, headerPalette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(alignment: .topTrailing) {
                    Circle().fill(Nuru.gold.opacity(headerPalette.glow)).frame(width: 176, height: 176).blur(radius: 44).offset(x: 40, y: -60)
                }
        )
        .clipShape(.rect(bottomLeadingRadius: 24, bottomTrailingRadius: 24))
        // A gilded edge instead of the flat gray hairline — gold breathing at the
        // center, fading to nothing at the corners — plus a whisper of lift so
        // the header floats over the feed.
        .overlay(alignment: .bottom) {
            LinearGradient(colors: [.clear, Nuru.gold.opacity(0.55), Nuru.gold.opacity(0.55), .clear],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 1.5)
                .padding(.horizontal, 24)
        }
        .shadow(color: Color(hex: 0x0A2540).opacity(0.07), radius: 10, y: 5)
    }

    /// The sky in the kicker — mirrors headerPalette's hour bands.
    private var skyGlyph: String {
        let h = Calendar.current.component(.hour, from: Date())
        return h < 5 ? "moon.stars.fill" : h < 9 ? "sunrise.fill" : h < 16 ? "sun.max.fill"
             : h < 19 ? "sunset.fill" : "moon.stars.fill"
    }

    /// The member's overall GROWTH score (0–100) — the weighted average of the
    /// five domains over the rolling 28 days. Falls back to 0 until scores land.
    private var growthScore: Int { vm.scores?.overall.score ?? 0 }
    /// This-28-days vs previous-28-days movement, for the ▲/▼ badge.
    private var growthTrend: ScoreTrend? { vm.scores?.trend }

    // MiniRing (Figma) — 42px, growth ring, with a ▲/▼ 28-day trend badge.
    // The arc sweeps in once on appear and re-tracks smoothly as data lands.
    private var progressRing: some View {
        ZStack {
            Circle().fill(Color(hex: 0xDCFCE7).opacity(0.6))
            Circle().stroke(Color(hex: 0x16A34A).opacity(0.15), lineWidth: 3)
            HomeRingTrim(
                pct: CGFloat(growthScore) / 100,
                style: AnyShapeStyle(LinearGradient(colors: [Color(hex: 0x16A34A), Color(hex: 0x4ADE80)],
                                                    startPoint: .top, endPoint: .bottom)),
                lineWidth: 3)
            Text("\(growthScore)%").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x166534))
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: growthScore)
        }
        .frame(width: 42, height: 42)
        .overlay(alignment: .bottomTrailing) {
            if let t = growthTrend, t.delta != 0 { trendBadge(t).offset(x: 5, y: 4) }
        }
        .accessibilityLabel("Growth score \(growthScore) percent")
    }

    /// A tiny ▲/▼ badge — points earned or lost vs the previous 28 days.
    private func trendBadge(_ t: ScoreTrend) -> some View {
        HStack(spacing: 0.5) {
            Image(systemName: t.isDown ? "arrow.down" : "arrow.up").font(.system(size: 7, weight: .black))
            Text("\(abs(t.delta))").font(.inter(8, .bold)).contentTransition(.numericText())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 3.5).padding(.vertical, 1.5)
        .background(t.isDown ? Color(hex: 0xDC6B26) : Color(hex: 0x16A34A), in: Capsule())
        .overlay(Capsule().stroke(Color.white, lineWidth: 1))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: t.delta)
    }

    // MARK: 0 — Live now (driven by REAL calendar occurrences; no fake stream data)

    /// A worship-ish gathering that is happening right now (live) or starts within
    /// the hour (soon). No live-stream endpoint exists, so the card routes to the
    /// real event detail and never shows invented viewer counts.
    private var liveNowInfo: (occ: CalendarOccurrence, startsInMin: Int?)? {
        let now = Date()
        for occ in vm.events {
            guard isWorshipish(occ), let start = parseISO(occ.startAt) else { continue }
            let end = parseISO(occ.endAt) ?? start.addingTimeInterval(2 * 3600)
            if start <= now, now <= end { return (occ, nil) }
            let mins = Int(start.timeIntervalSince(now) / 60)
            if mins > 0, mins <= 60 { return (occ, mins) }
        }
        return nil
    }

    private func isWorshipish(_ occ: CalendarOccurrence) -> Bool {
        let hay = "\(occ.category ?? "") \(occ.title)".lowercased()
        return hay.contains("worship") || hay.contains("service") || hay.contains("praise") || hay.contains("church")
    }

    /// 0b — "A letter for you": the gold knock that appears while this week's
    /// Sunday Letter is unread. Tapping opens the stationery sheet (which marks
    /// it read server-side); the knock then rests until next Sunday.
    private func letterKnock(_ lt: PastoralLetter) -> some View {
        Button {
            Haptics.action()
            openedLetter = lt
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0xE8CA6C), Color(hex: 0xB6862F)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Icon(.mail, size: 19, color: Color(hex: 0x1E2A1F))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE SUNDAY LETTER").font(.inter(9, .bold)).kerning(1.6)
                        .foregroundStyle(Color(hex: 0xE8CA6C))
                    Text("A letter was written for you").font(.fraunces(16, .semibold)).foregroundStyle(.white)
                    if let ref = lt.scriptureRef {
                        Text(ref).font(.inter(11)).foregroundStyle(Color(hex: 0xB9C4D4))
                    }
                }
                Spacer(minLength: 0)
                Text("Open").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x1E2A1F))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(Color(hex: 0xE8CA6C), in: Capsule())
            }
            .padding(14)
            .background(
                LinearGradient(colors: [Color(hex: 0x11253F), Color(hex: 0x0A1628)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: 0xC9A227).opacity(0.5), lineWidth: 1))
            .shadow(color: Color(hex: 0xC9A227).opacity(0.18), radius: 10, y: 5)
        }
        .buttonStyle(.pressableSubtle)
    }

    /// 0c (read) — the SAME letter once it's no longer new: a quiet row, not
    /// a knock, so a member can always find their way back to it (and the
    /// archive one tap further) without Home manufacturing false urgency for
    /// something they've already read.
    private func letterReadRow(_ lt: PastoralLetter) -> some View {
        Button {
            Haptics.tap()
            openedLetter = lt
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LetterTheme.resolve(lt.imageKey).accentColor.opacity(0.85))
                        .frame(width: 38, height: 38)
                    Icon(.mail, size: 16, color: Color(hex: 0x1E2A1F))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE SUNDAY LETTER").font(.inter(9, .bold)).kerning(1.6)
                        .foregroundStyle(Color(hex: 0xA8861C))
                    // Ink, not white (owner, 2026-08-24): this quiet row sits
                    // on the bright page — white type simply vanished into it.
                    Text(lt.title).font(.fraunces(14, .semibold)).foregroundStyle(Nuru.navy).lineLimit(1)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 14, color: Color(hex: 0x8A97AA))
            }
            .padding(13)
            .background(Nuru.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Nuru.border, lineWidth: 1))
        }
        .buttonStyle(.pressableSubtle)
    }

    /// 0c (anticipation) — no letter has arrived yet (a brand-new member, or
    /// simply mid-week). Says WHEN rather than showing nothing: the ritual —
    /// knowing something is coming — is the point, not just the payoff.
    private var letterArrivalCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(hex: 0x2C3B52), Color(hex: 0x18213A)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                Icon(.mail, size: 18, color: Color(hex: 0xB9C4D4))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("THE SUNDAY LETTER").font(.inter(9, .bold)).kerning(1.6)
                    .foregroundStyle(Color(hex: 0x8A97AA))
                Text("Your letter arrives Sunday evening").font(.fraunces(15, .semibold)).foregroundStyle(.white)
                Text("A short pastoral note, written from your own week.")
                    .font(.inter(11)).foregroundStyle(Color(hex: 0x8A97AA))
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            LinearGradient(colors: [Color(hex: 0x11253F), Color(hex: 0x0A1628)],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
            .stroke(Color.white.opacity(0.08), lineWidth: 1))
    }

    private func liveNowCard(_ info: (occ: CalendarOccurrence, startsInMin: Int?)) -> some View {
        HomeLiveNowCard(
            title: info.occ.title,
            location: info.occ.location,
            posterUrl: info.occ.primaryImageUrl,
            startsInMin: info.startsInMin
        ) { tabs.openEvent(info.occ) }   // events live on the Events tab
    }

    // MARK: 0d — Nuru Live LIVE banner (church scope; the cell twin lives in
    // CellInfoView, filtered from this SAME /live/now response — no second call)

    /// Defensive guard, belt-and-braces on top of `LiveDiscoveryCenter.
    /// ingest`'s own self-exclusion filter: `vm.liveStreams` is fetched
    /// DIRECTLY (`HomeViewModel.load`/`refreshLiveNow`, not read from
    /// `LiveDiscoveryCenter.streams`), so it needs its own exclusion too — a
    /// broadcaster must never see their OWN stream offered back as "Watch
    /// live" on this banner (parity audit 2026-07-31, Android twin: PR #87's
    /// `HomeScreen.kt` `churchLive` guard — same bypass class: a screen that
    /// fetches `/live/now` itself instead of reading the already-filtered
    /// discovery centre).
    private var churchLiveStream: LiveStreamSummary? {
        let ownStreamId = BroadcastCenter.shared.controller?.session.stream.streamId
        return vm.liveStreams.first { $0.scope == "church" && $0.streamId != ownStreamId }
    }

    private func liveBannerCard(_ stream: LiveStreamSummary) -> some View {
        HomeLiveBannerCard(
            stream: stream,
            onWatch: { Haptics.action(); openLiveItem = .live(stream) },
            onReplays: { openReplays = true }
        )
    }

    // MARK: 1 — Priority strip (reflection due; appears at top AND before progress)

    private var reflectionDue: Bool {
        // The tick this strip tracks is the DAILY RHYTHM's reflection, which
        // exactly one act emits: saving today's devotional reflection
        // (backend growth-content saveDevotionalReflection → interaction
        // kind='reflection'). It has nothing to do with the next module, so
        // the old `nextAction != nil` guard was noise — but never show the
        // strip before the rhythm has actually loaded.
        !vm.loading && !vm.rhythm.reflection
    }

    private var priorityStrip: some View {
        HomePriorityStrip(
            title: "Reflection due today",
            meta: "Write today's devotional reflection",
            cta: "Start reflection"
        ) {
            // Straight to the act that clears this strip: the devotional's
            // reflection composer. (The old link opened the next MODULE —
            // which may have no reflection at all — so the strip nagged
            // forever and the CTA lied about where it went.)
            Haptics.tap()
            path.append(GrowDestination.devotional)
        }
    }

    // MARK: 0a — Nuru Radio ON AIR hero (pinned first, only while actually live)

    /// The bar itself starts/pauses the station through RadioCenter; tapping
    /// elsewhere opens the studio. It also reports its on-screen visibility so
    /// the shell's island pill yields while the bar is in view and slides into
    /// the notch the moment it scrolls away (one radio surface at a time).
    private func onAirCard(_ p: RadioProgram) -> some View {
        HomeOnAirCard(program: p) {
            NotificationCenter.default.post(name: .nuruOpenRadio, object: nil)
        }
            .background(GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.frame(in: .global).minY, initial: true) { _, y in
                        // Visible until (almost) fully scrolled past the top.
                        let visible = y > -40
                        if tabs.onAirBarVisible != visible { tabs.onAirBarVisible = visible }
                    }
            })
            .onDisappear { if tabs.onAirBarVisible { tabs.onAirBarVisible = false } }
    }

    // MARK: 2 — Next-action hero ("For you today" — real pathway numbers)

    private func heroCard(_ a: NextAction) -> some View {
        let done = active?.completedModules ?? 0
        let total = active?.totalModules ?? 0
        let pct = total > 0 ? Int(round(Double(done) / Double(total) * 100)) : 0
        return HomeResumeHero(
            title: a.title,
            meta: total > 0 ? "Level \(active?.levelNumber ?? 1) · \(done) of \(total) modules" : a.body,
            pct: pct,
            note: a.body,
            ctaLabel: a.ctaLabel
        ) {
            // "For you today" continues the pathway — land on the Pathway tab.
            if a.route == "module", let m = a.params?.moduleId {
                tabs.openPathway(.module(m))
            } else if let lvl = active?.levelNumber {
                tabs.openPathway(.level(lvl))
            }
        }
    }

    // MARK: 3 — Featured welcome video

    private func welcomeVideoCard(_ v: WelcomeVideo) -> some View {
        let love = v.loveCount ?? (v.reactions?.first { $0.emoji == "❤️" }?.count ?? 0)
        let liked = v.liked ?? false
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Nuru.S.sm) {
                BrandMark(size: 28)
                Text("Nuru Pathway").font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                Icon(.badgeCheck, size: 14, color: Nuru.gold)
                Spacer(minLength: 0)
                Text("FEATURED").font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.metaGray)
            }
            .padding(Nuru.S.base)

            // Plays inline, pinned to the card's inset 16:9 box — never opens Safari.
            Group {
                if playingVideo {
                    InlineVideoPlayer(video: v, onReady: {
                        withAnimation(.easeOut(duration: 0.25)) { videoReady = true }
                    })
                        .aspectRatio(16.0/9.0, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .background(Color.black)
                        // Buffering cue INSIDE the card — the black box never sits silent.
                        .overlay {
                            if !videoReady {
                                ZStack {
                                    Color.black
                                    ProgressView().tint(Nuru.gold)
                                }
                                .allowsHitTesting(false)
                                .transition(.opacity)
                            }
                        }
                } else {
                    Button { Haptics.tap(); playingVideo = true } label: { videoThumb(v) }
                        .buttonStyle(.pressableSubtle)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, Nuru.S.base)

            VStack(alignment: .leading, spacing: 0) {
                // Caption + fallback sub-line, never the same words twice: when the
                // authored caption IS the fallback copy (or absent), show it once
                // (Android's dedup rule, ported).
                let fallback = "Start here — what the journey looks like"
                // The app's own title face, FOUR points down from the old sans
                // headline (owner, 2026-08-26): it was the one foreign-looking
                // (portal) font on Home. Full width, generous leading, and the
                // sub-line given real air beneath it.
                if let cap = v.caption, !cap.isEmpty {
                    Text(cap)
                        .font(.fraunces(14, .semibold)).foregroundStyle(HomeFig.navy)
                        .nuruLineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if cap != fallback {
                        Text(fallback).font(.nCardBody).foregroundStyle(HomeFig.metaGray)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 7)
                    }
                } else {
                    Text(fallback)
                        .font(.fraunces(14, .semibold)).foregroundStyle(HomeFig.navy)
                        .nuruLineSpacing(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    Button { Haptics.love(); Task { await vm.toggleVideoReaction("❤️") } } label: {
                        HStack(spacing: 5) {
                            Text("❤️").font(.system(size: 15))
                            Text("\(love)").font(.inter(11, .bold)).foregroundStyle(liked ? Nuru.danger : Nuru.ink600)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(liked ? Color(hex: 0xFEE2E2) : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(liked ? Nuru.danger.opacity(0.35) : Nuru.border, lineWidth: 1))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: love)
                    }.buttonStyle(.pressable)
                    ForEach(videoReactionEmojis, id: \.self) { e in
                        let count = v.reactions?.first { $0.emoji == e }?.count ?? 0
                        let mine = v.reactions?.first { $0.emoji == e }?.mine ?? false
                        Button { Haptics.love(); Task { await vm.toggleVideoReaction(e) } } label: {
                            HStack(spacing: 4) {
                                Text(e).font(.system(size: 15))
                                if count > 0 { Text("\(count)").font(.inter(11, .bold)).foregroundStyle(Nuru.ink600) }
                            }
                            .frame(minWidth: 34, minHeight: 34)
                            .padding(.horizontal, count > 0 ? 6 : 0)
                            .background(mine ? Nuru.goldChipBg : Nuru.white, in: Circle())
                            .overlay(Circle().stroke(mine ? Nuru.gold : Nuru.border, lineWidth: 1))
                        }.buttonStyle(.pressable)
                    }
                    Spacer(minLength: 0)
                    Button { Haptics.tap(); sharePayload = SharePayload(text: videoShareText(v)) } label: {
                        HStack(spacing: 5) {
                            Icon(.share2, size: 13, color: Nuru.ink600)
                            Text("Share").font(.inter(11, .semibold)).foregroundStyle(Nuru.ink600)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
                    }.buttonStyle(.pressable)
                }
                .padding(.top, Nuru.S.md)
            }
            .padding(Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: 0xEEF0F3), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func videoThumb(_ v: WelcomeVideo) -> some View {
        ZStack {
            Rectangle().fill(Color(hex: 0xD6DADE))
            // No server thumbnail (uploaded videos carry none — no ffmpeg on the
            // API host): cut a poster frame from the video itself, once, and
            // keep it for the session. See VideoPoster.swift.
            if v.thumbnailUrl == nil || v.thumbnailUrl?.isEmpty == true, let play = v.playUrl {
                Color.clear
                    .overlay {
                        if let img = posters.poster(for: play) {
                            Image(uiImage: img).resizable().scaledToFill().opacity(0.95)
                                .transition(.opacity)
                        }
                    }
                    .clipped()
                    .task(id: play) {
                        await posters.load(play)
                        withAnimation(.easeOut(duration: 0.25)) { posterTick &+= 1 }
                    }
            }
            if let s = v.thumbnailUrl, let u = URL(string: s) {
                // Color.clear owns the layout size; the fill image lives in an
                // overlay so its oversized "fill" size can never inflate the
                // 16:9 thumb ZStack (the radio-screen edge-spill bug family).
                Color.clear
                    .overlay {
                        CachedAsyncImage(url: u) { phase in
                            if let img = phase.image { img.resizable().scaledToFill().opacity(0.95) }
                            else { Rectangle().fill(Color(hex: 0xD6DADE)) }
                        }
                    }
                    .clipped()
            }
            LinearGradient(colors: [Color(hex: 0x0F141E).opacity(0), Color(hex: 0x0F141E).opacity(0.45)],
                           startPoint: .top, endPoint: .bottom)
            // Gold play disc — navy glyph, white inset ring, gold glow (Figma).
            ZStack {
                Circle().fill(Nuru.gold).frame(width: 64, height: 64)
                    .shadow(color: Nuru.gold.opacity(0.5), radius: 14, y: 7)
                Circle().stroke(Color.white.opacity(0.28), lineWidth: 4).frame(width: 58, height: 58)
                Icon(.play, size: 26, color: HomeFig.navy).offset(x: 2)
            }
            if let d = v.durationSec, d > 0 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text(durationLabel(d)).font(.inter(10, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: 0x0F141E).opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
            if let art = vm.verseArt {
                // The tableau: the day's photograph carries the verse (owner ask —
                // "something beautiful to behold" breaking the wall of text).
                VerseTableauHeader(
                    art: art,
                    verseText: vm.verse?.text,
                    reference: "\(vm.verse?.reference ?? "Psalm 119:105") · \(vm.verse?.version ?? "WEB")",
                    version: vm.verse?.version ?? "WEB"
                )
            } else {
                // No art (offline first paint / older backend): the classic cream reading.
                HStack(spacing: 6) {
                    Icon(.bookOpen, size: 13, color: Nuru.goldChipText)
                    Text("VERSE FOR TODAY").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                    Spacer(minLength: 0)
                    Text((vm.verse?.version ?? "WEB").uppercased())
                        .font(.inter(10, .bold)).kerning(1).foregroundStyle(HomeFig.navy)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(Nuru.gold.opacity(0.33), lineWidth: 1))
                }
                .padding([.horizontal, .top], Nuru.S.base)
                VerseQuoteCard(
                    verse: vm.verse?.text ?? "Your word is a lamp to my feet, and a light for my path.",
                    reference: vm.verse?.reference ?? "Psalm 119:105",
                    cardStyle: false
                )
                .padding(.top, Nuru.S.md)
                .padding(.horizontal, Nuru.S.base)
            }
            verseCardBody
        }
        .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.gold.opacity(0.25), lineWidth: 1))
    }

    /// Season ribbon + reactions/save/share — shared by both verse renderings.
    private var verseCardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let enc = vm.verseEncouragement, !enc.text.isEmpty {
                // Seven-bands: a personal encouragement quote replaces the
                // season ribbon when the server provides one.
                VStack(alignment: .leading, spacing: 3) {
                    Text(enc.text)
                        .font(.fraunces(13.5).italic()).foregroundStyle(Nuru.ink)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    if !enc.author.isEmpty {
                        Text("— \(enc.author)")
                            .font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .padding(.top, 8)
            } else if let reason = vm.verseReason, !reason.isEmpty {
                // The season ribbon — Nuru discerned this from THEIR recent
                // prayers and reactions, so it reads as a personal choosing,
                // not an algorithm's footnote.
                HStack(spacing: 6) {
                    Icon(.sparkles, size: 12, color: Nuru.goldChipText)
                    Text("Chosen for your season — \(reason)")
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
                .padding(.top, 8)
            }
            // One row (Figma): reactions left, Save + Share pushed right.
            HStack(spacing: 5) {
                ForEach(verseReactionEmojis, id: \.self) { e in
                    let count = vm.reactions?.counts[e] ?? 0
                    let mine = vm.reactions?.mine == e
                    Button { Haptics.love(); Task { await vm.reactVerse(e) } } label: {
                        HStack(spacing: 3) {
                            Text(e).font(.system(size: 14))
                            if count > 0 {
                                Text("\(count)").font(.inter(10, .bold)).foregroundStyle(mine ? Nuru.goldChipText : Nuru.ink600)
                                    .contentTransition(.numericText())
                            }
                        }
                        .padding(.horizontal, 7).padding(.vertical, 6)
                        .background(mine ? Nuru.goldChipBg : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(mine ? Nuru.gold : Nuru.border, lineWidth: 1))
                        .contentShape(Capsule())   // whole chip is tappable, not just the glyph
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                    }.buttonStyle(.pressable)
                }
                Spacer(minLength: 4)
                Button {
                    if !vm.verseSaved { Haptics.success() }
                    Task { await vm.saveVerse() }
                } label: {
                    pill(icon: .heart, label: vm.verseSaved ? "Saved" : "Save", tint: vm.verseSaved ? Nuru.gold : HomeFig.navy)
                        .animation(.easeInOut(duration: 0.2), value: vm.verseSaved)
                }.buttonStyle(.pressable)
                Button { Haptics.tap(); shareVerseTapped() } label: {
                    pill(icon: .share2, label: "Share", tint: HomeFig.navy)
                }.buttonStyle(.pressable)
            }
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .confirmationDialog("Share today's verse", isPresented: $verseShareDialog, titleVisibility: .visible) {
            Button("Share as a picture") { Task { await shareVerseAsImage() } }
            Button("Send in chat") { sharePayload = SharePayload(text: verseShareText()) }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $verseShareImage) { payload in
            VerseShareSheet(image: payload.image)
                .presentationDetents([.medium, .large])
        }
    }

    /// With a tableau the member chooses picture vs chat; without art the old
    /// text-to-chat share fires directly (nothing to photograph).
    private func shareVerseTapped() {
        if vm.verseArt != nil { verseShareDialog = true }
        else { sharePayload = SharePayload(text: verseShareText()) }
    }

    private func shareVerseAsImage() async {
        guard let art = vm.verseArt else { return }
        let text = vm.verse?.text ?? "Your word is a lamp to my feet, and a light for my path."
        let ref = vm.verse?.reference ?? "Psalm 119:105"
        let ver = vm.verse?.version ?? "WEB"
        if let img = await VerseImageShare.render(art: art, verseText: text, reference: ref, version: ver) {
            verseShareImage = VerseImagePayload(image: img)
        } else {
            // Couldn't fetch/render the picture (offline, CDN hiccup) — share the words.
            sharePayload = SharePayload(text: verseShareText())
        }
    }

    private func pill(icon: Lucide, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 12, color: tint)
            Text(label).font(.inter(11, .semibold)).foregroundStyle(tint)
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Nuru.white, in: Capsule())
        .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    /// A card-header trailing link that reads as a BUTTON — a gold-tinted pill
    /// ("Open wall", "View", "View all") instead of a whisper of bare text that
    /// disappeared into the card (owner ask: make it stand out).
    private func sectionLink(_ label: String) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.inter(11, .bold)).foregroundStyle(Nuru.goldChipText)
            Icon(.chevronRight, size: 11, color: Nuru.goldChipText)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Nuru.goldChipBg, in: Capsule())
        .overlay(Capsule().stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
    }

    // MARK: 5 — Pray for one another (carousel)

    private var prayerWallCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("PRAY FOR ONE ANOTHER").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                Spacer()
                NavigationLink(value: CommunityRoute.prayerWall) {
                    sectionLink("My Prayer Room")
                }.buttonStyle(.plain)
            }
            // A single post hugs its content (no pager, no dead space); multiple
            // posts page in a tight frame with OUR page dots below — the system
            // dots are white (invisible on cream) and forced a tall dead band.
            if vm.prayerPosts.count == 1, let post = vm.prayerPosts.first {
                NavigationLink(value: CommunityRoute.prayer(post.postId)) {
                    prayerPostView(post, inPager: false)
                }.buttonStyle(.pressableSubtle)
                .padding(.top, Nuru.S.sm)
            } else {
                TabView(selection: $prayPage) {
                    // Buttons, NOT NavigationLinks: links hosted inside a paged
                    // TabView can fire with a NEIGHBOR page's value (the pager
                    // forwards taps across hosted pages) — the member tapped
                    // one prayer and landed on another. A button resolves its
                    // own captured post, then navigates programmatically.
                    ForEach(Array(vm.prayerPosts.enumerated()), id: \.element.postId) { i, post in
                        Button {
                            Haptics.tap()
                            path.append(CommunityRoute.prayer(post.postId))
                        } label: {
                            prayerPostView(post, inPager: true)
                        }.buttonStyle(.pressableSubtle)
                        .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 138)
                .padding(.top, Nuru.S.sm)
                HStack(spacing: 5) {
                    ForEach(0..<vm.prayerPosts.count, id: \.self) { i in
                        Capsule().fill(i == prayPage ? Nuru.gold : Nuru.gold.opacity(0.22))
                            .frame(width: i == prayPage ? 16 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: prayPage)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Nuru.S.sm)
            }
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func prayerPostView(_ post: PrayerWallPost, inPager: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Nuru.S.sm) {
                Avatar(url: post.authorAvatar, name: post.authorName, size: 32)
                Text(post.authorName).font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                Spacer(minLength: 0)
            }
            if let t = post.title, !t.isEmpty {
                Text(t).font(.inter(14, .semibold)).foregroundStyle(HomeFig.navy).padding(.top, Nuru.S.sm)
            }
            Text(post.body).font(.nCardBody).foregroundStyle(HomeFig.metaGray).lineLimit(2)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 6)
            // Gold-tinted praying pill (Figma).
            HStack(spacing: 5) {
                Icon(.handHeart, size: 13, color: Nuru.goldChipText)
                Text("\(post.prayCount) praying · \(post.commentCount ?? 0) replies")
                    .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Nuru.gold.opacity(0.10), in: Capsule())
            .padding(.top, Nuru.S.md)
            if inPager { Spacer(minLength: 0) }   // top-align short posts in the pager
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 2c — "Continue your plan" resume banner (a pending-study nudge)

    /// The member's in-progress plan (enrolled, not yet finished), if any.
    private var resumePlan: ReadingPlanRow? {
        guard let p = vm.plan, p.enrolled, p.completedAt == nil else { return nil }
        return p
    }

    private func planResumeBanner(_ p: ReadingPlanRow) -> some View {
        let day = p.currentDay ?? 1
        let done = p.completedDays?.count ?? max(0, day - 1)
        let pct = p.dayCount > 0 ? CGFloat(done) / CGFloat(p.dayCount) : 0
        // Plans live on the Plans tab — switch there and land on this plan.
        return Button { Haptics.tap(); tabs.openPlans(.plan(p)) } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().stroke(Color.white.opacity(0.22), lineWidth: 4)
                    Circle().trim(from: 0, to: pct)
                        .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Icon(.bookMarked, size: 17, color: .white)
                }
                .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("CONTINUE YOUR PLAN").font(.inter(10, .bold)).kerning(1.6).foregroundStyle(Nuru.gold)
                    Text(p.title).font(.fraunces(18, .semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("Day \(day) of \(p.dayCount) · pick up where you left off")
                        .font(.inter(12)).foregroundStyle(.white.opacity(0.72)).lineLimit(1)
                }
                Spacer(minLength: 8)
                Icon(.arrowRight, size: 18, color: Nuru.gold)
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Nuru.navyGradient, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.pressable)
    }

    // MARK: 6 — Reading-plan + Prayer-journal minis

    private var minisRow: some View {
        // Equal fixed heights + explicit contentShape + clipped: each card's
        // tap zone is EXACTLY its visible surface. (The GeometryReader inside
        // the plan card made the row's height ambiguous, letting neighbors'
        // hit areas bleed — a Prayer Room tap could land on the card below.)
        HStack(alignment: .top, spacing: Nuru.S.md) {
            // Resume the plan directly when one is in progress; otherwise open the
            // catalogue — always on the Plans tab (its home), never inside Home.
            Button {
                Haptics.tap()
                tabs.openPlans(resumePlan.map { .plan($0) } ?? .catalogue)
            } label: {
                readingPlanMini
                    .frame(height: 128)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .clipped()
            }
            .buttonStyle(.pressable)
            NavigationLink(value: GrowDestination.prayerJournal) {
                prayerJournalMini
                    .frame(height: 128)
                    .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .clipped()
            }
            .buttonStyle(.pressable)
        }
        .frame(height: 128)
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
                Icon(.bookMarked, size: 17, color: Color(hex: 0x6366F1))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xEEF2FF), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                Text("\(pct)%").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x6366F1))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: 0xEEF2FF), in: Capsule())
            }
            Text("READING PLAN").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0x6366F1)).padding(.top, 10)
            Text(p?.title ?? "Start a plan").font(.inter(14, .semibold)).foregroundStyle(HomeFig.navy).lineLimit(1).padding(.top, 2)
            if let p { Text("Day \(p.currentDay ?? 1) of \(p.dayCount)").font(.nCardMeta).foregroundStyle(HomeFig.faintGray).padding(.top, 2) }
            else { Text("Pick a reading plan").font(.nCardMeta).foregroundStyle(HomeFig.faintGray).padding(.top, 2) }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xEEF0F3)).frame(height: 4)
                    Capsule().fill(Color(hex: 0x6366F1)).frame(width: geo.size.width * CGFloat(pct) / 100, height: 4)
                }
            }.frame(height: 4).padding(.top, Nuru.S.sm)
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
                Icon(.handHeart, size: 17, color: Color(hex: 0xDC2626))
                    .frame(width: 36, height: 36)
                    .background(Color(hex: 0xFEE2E2), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                Spacer()
                // Amber "N answered" chip (Figma).
                Text("\(answered) answered").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x92400E))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color(hex: 0xFEF3C7), in: Capsule())
            }
            Text("MY PRAYER ROOM").font(.nCardKicker).kerning(1.4).foregroundStyle(Color(hex: 0xDC2626)).padding(.top, 10)
            Text(latest?.title ?? "Your prayers").font(.inter(14, .semibold)).foregroundStyle(HomeFig.navy).lineLimit(1).padding(.top, 2)
            Text(latest?.body ?? "Start journaling your prayers").font(.nCardMeta).foregroundStyle(HomeFig.faintGray).lineLimit(1).padding(.top, 2)
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
                ZStack {
                    Rectangle().fill(Nuru.mutedBg)
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image { HomeFadeInImage(image: img) }
                        else { Rectangle().fill(Nuru.mutedBg) }
                    }
                }
                .aspectRatio(16.0/10.0, contentMode: .fill)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay(alignment: .topLeading) {
                    // Anticipation cue — soft gold countdown pill (Figma).
                    HStack(spacing: 4) {
                        Circle().fill(HomeFig.navy).frame(width: 4, height: 4)
                        Text("This week").font(.inter(8, .bold)).foregroundStyle(HomeFig.navy)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(LinearGradient(colors: [Nuru.gold, HomeFig.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing), in: Capsule())
                    .padding(12)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "dot.radiowaves.left.and.right").font(.system(size: 11))
                        .foregroundStyle(HomeFig.eyebrow)
                    Text("THIS WEEK AT NURU").font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.eyebrow)
                    Spacer(minLength: 0)
                }
                Text(c.name).font(.nCardTitle).foregroundStyle(HomeFig.navy).padding(.top, 4)
                if let d = c.disciplerName {
                    Text("\(d)\(c.disciplerRole.map { " · \($0)" } ?? "")").font(.nCardMeta).foregroundStyle(HomeFig.subGray).padding(.top, 1)
                }
                HStack(spacing: 6) {
                    if let f = c.focus { chip(f) }
                    if let l = c.levelLabel { chip(l) }
                }
                .padding(.top, 10)
                if let m = c.meets {
                    HStack(spacing: Nuru.S.sm) {
                        Icon(.calendarDays, size: 15, color: Nuru.gold)
                        (Text(m).font(.inter(11, .semibold)).foregroundStyle(HomeFig.navy)
                         + Text(c.nextSession.map { " · Next: \($0)" } ?? "").font(.nCardMeta).foregroundStyle(HomeFig.faintGray))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 10)
                    .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Nuru.gold.opacity(0.2), lineWidth: 1))
                    .padding(.top, 10)
                }
                HStack {
                    HStack(spacing: 4) {
                        Icon(.mapPin, size: 11, color: HomeFig.faintGray)
                        Text(c.room ?? c.name).font(.nCardMeta).foregroundStyle(HomeFig.faintGray).lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    HStack(spacing: 4) {
                        Icon(.users, size: 11, color: HomeFig.eyebrow)
                        Text(c.members > 0 ? "\(c.members) members" : "Be the first to join 🔥")
                            .font(.inter(10, .bold)).foregroundStyle(HomeFig.eyebrow)
                    }
                }
                .padding(.top, Nuru.S.sm)
            }
            .padding(Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.inter(9, .semibold)).foregroundStyle(Nuru.goldChipText)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Nuru.surface, in: Capsule())
            .overlay(Capsule().stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 8 — Meet your discipler (carousel)

    private var disciplersCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("MEET YOUR DISCIPLER").font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.eyebrow)
                Spacer(minLength: 0)
                // Opens the Discipleship Hub — the fuller student home for the
                // discipleship relationship (backend: GET /me/discipleship).
                NavigationLink(value: AppRoute.discipleshipHub) {
                    sectionLink("View")
                }.buttonStyle(.plain)
            }
            // One discipler hugs its content (no pager, no dead band); several
            // page with OUR gold dots — the system pager dots are WHITE and were
            // invisible on the white card, leaving what read as an empty card.
            if vm.disciplers.count == 1, let d = vm.disciplers.first {
                NavigationLink(value: AppRoute.discipleshipHub) { disciplerView(d) }
                    .buttonStyle(.pressableSubtle)
                    .padding(.top, Nuru.S.md)
            } else {
                TabView(selection: $disciplerPage) {
                    ForEach(Array(vm.disciplers.enumerated()), id: \.element.id) { i, d in
                        NavigationLink(value: AppRoute.discipleshipHub) { disciplerView(d, inPager: true) }
                            .buttonStyle(.pressableSubtle)
                            .tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 190)
                .padding(.top, Nuru.S.md)
                HStack(spacing: 5) {
                    ForEach(0..<vm.disciplers.count, id: \.self) { i in
                        Capsule().fill(i == disciplerPage ? Nuru.gold : Nuru.gold.opacity(0.22))
                            .frame(width: i == disciplerPage ? 16 : 6, height: 6)
                            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: disciplerPage)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, Nuru.S.sm)
            }
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func disciplerView(_ d: Discipler, inPager: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Nuru.S.md) {
                Avatar(url: d.avatarUrl, name: d.fullName, size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.fullName).font(.fraunces(17, .semibold)).foregroundStyle(HomeFig.navy)
                    Text(d.roleLabel.uppercased()).font(.inter(10, .bold)).kerning(1.4).foregroundStyle(Nuru.goldLo)
                }
                Spacer(minLength: 0)
                Icon(.chevronRight, size: 16, color: Nuru.ink300)
            }
            if let m = d.message, !m.isEmpty {
                Text("“\(m)”")
                    .font(.fraunces(14, .regular)).italic()
                    .foregroundStyle(Color(hex: 0x3A4A5F))
                    .lineSpacing(4).lineLimit(inPager ? 3 : nil)
                    .fixedSize(horizontal: false, vertical: !inPager)
                    .padding(.top, Nuru.S.md)
            }
            // The relationship's front door — the hub's hero CTA, previewed here.
            HStack(spacing: 6) {
                Icon(.messageCircle, size: 12, color: Nuru.goldChipText)
                Text("Message · walk together").font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Nuru.gold.opacity(0.10), in: Capsule())
            .padding(.top, Nuru.S.md)
            if inPager { Spacer(minLength: 0) }   // top-align inside the fixed pager
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 9 — Featured announcement

    // MARK: 9 — Featured carousel (owner's revision, 2026-08-24)
    //
    // One sliding rail for everything the portal has marked or scheduled: the
    // featured announcement, the featured gathering, and the next few events.
    // Auto-advances gently; a swipe is always respected. "View all" opens the
    // full events list (You ▸ Events), per the owner's spec.

    private enum FeaturedPage: Identifiable {
        case announcement(FeaturedAnnouncement)
        case event(FeaturedEvent)
        case occurrence(HomeEventRow)
        var id: String {
            switch self {
            case .announcement(let a): return "ann-" + a.announcementId
            case .event(let e): return "fev-" + e.seriesId
            case .occurrence(let o): return "occ-" + o.occurrenceId
            }
        }
    }

    private var featuredPages: [FeaturedPage] {
        var pages: [FeaturedPage] = []
        if let a = vm.featuredAnnouncement { pages.append(.announcement(a)) }
        if let e = vm.featuredEvent { pages.append(.event(e)) }
        let featuredSeries = vm.featuredEvent?.seriesId
        for ev in vm.homeEvents.filter({ $0.seriesId != featuredSeries }).prefix(3) {
            pages.append(.occurrence(ev))
        }
        return pages
    }

    private var featuredCarousel: some View {
        let pages = featuredPages
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FEATURED").font(.inter(11, .bold)).kerning(1.98).foregroundStyle(Nuru.goldChipText)
                Spacer()
                Button { Haptics.selection(); tabs.openYou(.events) } label: {
                    sectionLink("View all")
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            TabView(selection: $featuredPageIndex) {
                ForEach(Array(pages.enumerated()), id: \.element.id) { i, page in
                    featuredPageCard(page).tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 348)
            if pages.count > 1 {
                HStack(spacing: 5) {
                    ForEach(pages.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == featuredPageIndex ? Nuru.gold : Nuru.gold.opacity(0.25))
                            .frame(width: i == featuredPageIndex ? 16 : 5, height: 5)
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.25), value: featuredPageIndex)
            }
        }
        .onReceive(Timer.publish(every: 6, on: .main, in: .common).autoconnect()) { _ in
            guard pages.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.45)) {
                featuredPageIndex = (featuredPageIndex + 1) % pages.count
            }
        }
    }

    @ViewBuilder private func featuredPageCard(_ page: FeaturedPage) -> some View {
        switch page {
        case .announcement(let a):
            Button {
                Haptics.tap()
                path.append(AppRoute.announcement(a.announcementId))
                Task { await vm.openAnnouncement(a.announcementId) }
            } label: {
                featuredPageBody(kicker: "ANNOUNCEMENT", imageUrl: a.primaryImageUrl,
                                 title: a.title, body: a.body,
                                 meta: a.sentAt.map(shortDate), cta: "Read more")
            }
            .buttonStyle(.pressableSubtle)
        case .event(let e):
            Button { Haptics.tap(); tabs.openYou(.events) } label: {
                featuredPageBody(kicker: "FEATURED GATHERING", imageUrl: e.primaryImageUrl,
                                 title: e.title, body: e.description ?? (e.location ?? ""),
                                 meta: e.dtstartLocal.isEmpty ? nil : eventKicker(e.dtstartLocal), cta: "See details")
            }
            .buttonStyle(.pressableSubtle)
        case .occurrence(let o):
            Button { Haptics.tap(); path.append(CalendarOccurrence(homeEvent: o)) } label: {
                featuredPageBody(kicker: "UPCOMING EVENT", imageUrl: o.primaryImageUrl,
                                 title: o.title, body: o.venue ?? "",
                                 meta: eventKicker(o.startsAt), cta: "See details")
            }
            .buttonStyle(.pressableSubtle)
        }
    }

    /// One shared page frame so every slide sits at the same height — image on
    /// top (16:9, gradient fallback), then title, two body lines, and a footer.
    private func featuredPageBody(kicker: String, imageUrl: String?, title: String,
                                  body: String, meta: String?, cta: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                LinearGradient(colors: [Color(hex: 0x16273F), Color(hex: 0x0A1C33)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let s = imageUrl, !s.isEmpty, let u = URL(string: s) {
                    Color.clear.overlay {
                        CachedAsyncImage(url: u) { phase in
                            if let img = phase.image { HomeFadeInImage(image: img) }
                            else { Rectangle().fill(Nuru.mutedBg) }
                        }
                    }
                }
            }
            .aspectRatio(16.0/9.0, contentMode: .fill)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .topLeading) {
                Text(kicker).font(.inter(9, .bold)).kerning(1.3).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.nCardTitle).foregroundStyle(HomeFig.navy)
                    .lineLimit(1)
                Text(body).font(.nCardBody).foregroundStyle(HomeFig.metaGray).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                Spacer(minLength: 0)
                HStack {
                    if let meta { Text(meta).font(.nCardMeta).foregroundStyle(HomeFig.faintGray) }
                    Spacer()
                    HStack(spacing: 3) {
                        Text(cta).font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                        Icon(.chevronRight, size: 13, color: Nuru.gold)
                    }
                }
            }
            .padding(Nuru.S.base)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
        .nuruShadow()
    }


    // MARK: 10 — Continue · Level n

    private var continueLevelCard: some View {
        let a = active
        let done = a?.completedModules ?? 0
        let total = a?.totalModules ?? 0
        let pct = total > 0 ? Int(round(Double(done) / Double(total) * 100)) : 0
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: Nuru.S.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(LinearGradient(colors: [Nuru.gold, HomeFig.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Icon(.play, size: 18, color: HomeFig.navy).offset(x: 1)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("CONTINUE · LEVEL \(a?.levelNumber ?? 1)").font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.eyebrow)
                    Text(a?.title ?? "Foundations of Faith").font(.nRowTitle).foregroundStyle(HomeFig.navy)
                    Text("\(done) of \(total) modules").font(.nCardMeta).foregroundStyle(HomeFig.faintGray)
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: Nuru.S.sm) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(hex: 0xEEF0F3)).frame(height: 6)
                        Capsule()
                            .fill(LinearGradient(colors: [Nuru.gold, HomeFig.goldSoft], startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(pct) / 100, height: 6)
                    }
                }.frame(height: 6)
                Text("\(pct)% complete").font(.inter(10, .bold)).foregroundStyle(HomeFig.eyebrow)
            }
            .padding(.top, Nuru.S.md)
            // Goal-gradient nudge — momentum grows nearer the finish (Figma).
            Text(pct >= 60 ? "Almost there — finish strong 🎉" : "Just \(100 - pct)% to your next badge")
                .font(.inter(11, .semibold)).foregroundStyle(HomeFig.eyebrow)
                .padding(.top, 6)
            Button {
                Haptics.tap()
                if let m = nextModuleId { tabs.openPathway(.module(m)) }
                else { tabs.openPathway(.level(a?.levelNumber ?? 1)) }
            } label: {
                HStack(spacing: 6) {
                    Text("Continue").font(.nCardCTA).foregroundStyle(Nuru.gold)
                    Icon(.chevronRight, size: 15, color: Nuru.gold)
                }
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(HomeFig.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.pressable)
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    // MARK: 11 — Today's rhythm

    private var rhythmCard: some View {
        let complete = vm.rhythm.doneCount == 3
        // Finishing today's rhythm counts today automatically (Figma displayStreak).
        let displayStreak = vm.streak + (complete ? 1 : 0)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(complete ? "Today's rhythm complete 🎉" : "Today's rhythm")
                    .font(.inter(16, .semibold)).foregroundStyle(HomeFig.navy)
                Spacer()
                HStack(spacing: 4) {
                    Icon(.flame, size: 12, color: Nuru.goldChipText)
                    Text(displayStreak > 0 ? "\(displayStreak)-day streak" : "Start today")
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayStreak)
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
            // The seal — appears when the third discipline lands mid-session
            // and stays for the rest of it. A blessing spoken once, not a badge.
            if vm.daySealed {
                Text("Day sealed · well walked")
                    .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Nuru.S.md)
                    .transition(.opacity)
            }
            // Weekly consistency — reflects real completion (today fills when done).
            HomeWeekChain(streakDays: vm.streak, todayDone: complete)
                .padding(.top, 14)
            if !complete {
                Text(vm.rhythm.reflection ? "One more to complete today's rhythm." : "Complete reflection to keep your rhythm.")
                    .font(.nCardBody).foregroundStyle(HomeFig.metaGray).padding(.top, Nuru.S.md)
            }
        }
        .padding(Nuru.S.base)
        .cardSurface()
        // The sweep itself — soft gold breathing out from the card's heart,
        // 0.35 → 0 over 1.2s. Invisible at rest; never intercepts a touch.
        .overlay {
            RadialGradient(colors: [Nuru.gold, .clear], center: .center, startRadius: 0, endRadius: 240)
                .opacity(sealGlow)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: vm.daySealed)
        .onChange(of: vm.daySealed) { _, sealed in
            guard sealed else { return }
            Haptics.success()
            guard !reduceMotion else { return }   // haptic + caption only
            sealGlow = 0.35   // land at full…
            DispatchQueue.main.async {            // …then fade on the next tick
                withAnimation(.easeOut(duration: 1.2)) { sealGlow = 0 }
            }
        }
    }

    // Read-only: each chip is a reflection of real acts (prayer posted/encouraged,
    // Scripture engaged, reflection written) that the server ticks — not a checkbox.
    private func rhythmTile(_ kind: String, _ label: String) -> some View {
        let done = vm.done(kind)
        return VStack(spacing: 4) {
            ZStack {
                Circle().fill(done ? Nuru.successText : Nuru.white).frame(width: 24, height: 24)
                Icon(done ? .check : .clock, size: 12, color: done ? Nuru.white : Nuru.goldLo)
            }
            Text(label).font(.inter(12, .semibold)).foregroundStyle(done ? Nuru.successText : Nuru.goldChipText)
            Text(done ? "DONE" : "PENDING").font(.nMicro).foregroundStyle(done ? Nuru.successText : Nuru.goldChipText).opacity(0.8)
        }
        .frame(maxWidth: .infinity).padding(.vertical, Nuru.S.md)
        .background(done ? Nuru.successBg : Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: done)   // pending → done springs, not snaps
    }

    // MARK: 13 — Your progress (scores)

    private func progressCard(_ s: ScoresSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Your progress").font(.inter(16, .semibold)).foregroundStyle(HomeFig.navy)
                Spacer()
                Button {
                    Haptics.tap(); tabs.openPathway(.level(active?.levelNumber ?? 1))
                } label: {
                    Text("View pathway").font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                }
            }
            HStack(spacing: Nuru.S.base) {
                ZStack {
                    Circle().stroke(Color(hex: 0xEEE7D6), lineWidth: 6)
                    // Sweeps in once when the card scrolls into view.
                    HomeRingTrim(pct: CGFloat(s.overall.score) / 100,
                                 style: AnyShapeStyle(Nuru.gold), lineWidth: 6)
                    VStack(spacing: -2) {
                        Text("\(s.overall.score)").font(.fraunces(18, .semibold)).foregroundStyle(HomeFig.navy)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.4, dampingFraction: 0.8), value: s.overall.score)
                        Text("/100").font(.inter(9, .semibold)).foregroundStyle(HomeFig.faintGray)
                    }
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OVERALL GROWTH").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                    Text(s.overall.band).font(.nCardTitle).foregroundStyle(HomeFig.navy)
                    if let t = s.trend {
                        HStack(spacing: 4) {
                            Image(systemName: t.isDown ? "arrow.down.right" : t.isUp ? "arrow.up.right" : "minus")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(t.isDown ? Color(hex: 0xDC6B26) : t.isUp ? Color(hex: 0x16A34A) : HomeFig.metaGray)
                            Text(trendCaption(t)).font(.nCardBody).foregroundStyle(HomeFig.metaGray)
                        }
                    } else {
                        Text("Your rhythm across the disciplines").font(.nCardBody).foregroundStyle(HomeFig.metaGray)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Nuru.S.base)
            VStack(spacing: 10) {
                scoreBar("Habits", s.habits.score, Nuru.gold, delta: s.trend?.domains?["habits"])
                scoreBar("Word", s.word.score, Color(hex: 0x2F6FB0), delta: s.trend?.domains?["word"])
                scoreBar("Prayer", s.prayer.score, Color(hex: 0xC98A3C), delta: s.trend?.domains?["prayer"])
                scoreBar("Curriculum", s.curriculum.score, HomeFig.navy, delta: s.trend?.domains?["curriculum"])
                scoreBar("Attendance", s.attendance.score, Color(hex: 0x16A34A), delta: s.trend?.domains?["attendance"])
            }
            .padding(.top, Nuru.S.base)
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

    private func scoreBar(_ label: String, _ value: Int, _ fill: Color, delta: Int? = nil) -> some View {
        HStack(spacing: Nuru.S.md) {
            Text(label).font(.inter(12)).foregroundStyle(HomeFig.metaGray).frame(width: 72, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(hex: 0xEEF0F3)).frame(height: 8)
                    Capsule().fill(fill).frame(width: geo.size.width * CGFloat(value) / 100, height: 8)
                }
            }.frame(height: 8)
            // A whisper of movement vs the previous 28 days, next to the score.
            if let d = delta, d != 0 {
                HStack(spacing: 1) {
                    Image(systemName: d < 0 ? "arrow.down" : "arrow.up").font(.system(size: 8, weight: .bold))
                    Text("\(abs(d))").font(.inter(9, .bold))
                }
                .foregroundStyle(d < 0 ? Color(hex: 0xDC6B26) : Color(hex: 0x16A34A))
                .frame(width: 26, alignment: .trailing)
            } else {
                Spacer().frame(width: 26)
            }
            Text("\(value)").font(.inter(12, .semibold)).foregroundStyle(HomeFig.navy).frame(width: 24, alignment: .trailing)
        }
    }

    /// "Up 6 vs last 28 days" / "Down 4 · keep going" / "Holding steady".
    private func trendCaption(_ t: ScoreTrend) -> String {
        if t.delta == 0 { return "Holding steady vs last 28 days" }
        return "\(t.isDown ? "Down" : "Up") \(abs(t.delta)) vs last 28 days"
    }

    // MARK: 14 — Grow your faith

    /// Section label OUTSIDE the card + the grid (fresh Figma layout).
    private var growSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionLabel(text: "Grow your faith")
            growCard
        }
    }

    private var growCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(growTiles.indices, id: \.self) { i in
                    let t = growTiles[i]
                    growTileLink(t)
                        .buttonStyle(.pressable)
                        // "New today" cue on the devotional — a gentle pull to start.
                        // (Decoration only — must never intercept the tile's tap.)
                        .overlay(alignment: .topTrailing) {
                            if i == 0 {
                                HomePulseDot().offset(x: 2, y: -2).allowsHitTesting(false)
                            }
                        }
                }
            }
            NavigationLink(value: AppRoute.mentor) {
                HStack(spacing: Nuru.S.md) {
                    Circle()
                        .fill(LinearGradient(colors: [Nuru.gold, HomeFig.goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 36, height: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("YOUR DISCIPLER").font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.eyebrow)
                        Text("Meet your discipler").font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 16, color: HomeFig.faintGray)
                }
                .padding(Nuru.S.md)
                .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.gold.opacity(0.2), lineWidth: 1))
            }.buttonStyle(.pressable)
        }
        .padding(Nuru.S.md)
        .cardSurface()
    }

    /// `NavigationLink(value:)` must carry a CONCRETE Hashable — pushing the tile's
    /// `AnyHashable` box matches no registered `navigationDestination`, so SwiftUI
    /// silently DISABLES the link (the "dead Grow tiles" bug). Unwrap to the real
    /// route type before building the link.
    @ViewBuilder
    private func growTileLink(_ t: GrowTile) -> some View {
        if let g = t.dest as? GrowDestination {
            if g == .readingPlans {
                // The plan catalogue is the Plans TAB — switch, don't push a copy.
                Button { Haptics.tap(); tabs.openPlans(.catalogue) } label: { growTileView(t) }
            } else {
                NavigationLink(value: g) { growTileView(t) }
            }
        } else if let c = t.dest as? CommunityRoute {
            NavigationLink(value: c) { growTileView(t) }
        } else {
            growTileView(t)   // unreachable with the current tile set
        }
    }

    private func growTileView(_ t: GrowTile) -> some View {
        HStack(spacing: 10) {
            Icon(t.icon, size: 16, color: Color(hex: t.fg))
                .frame(width: 36, height: 36)
                .background(Color(hex: t.tint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 0) {
                Text(t.label).font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy).lineLimit(1)
                Text(t.sub).font(.nCardMeta).foregroundStyle(HomeFig.metaGray).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(Nuru.S.md)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 15 — Upcoming (label outside; up to 5 curated event rows)

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionLabel(text: "Upcoming")
            upcomingCard
        }
    }

    // The ONE admin-featured event (portal "feature on homepage" toggle) —
    // GET /home/featured-event was declared but rendered by no client until now.
    private func featuredGatheringCard(_ fe: FeaturedEvent) -> some View {
        Button {
            Haptics.selection(); tabs.openYou(.events)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let u = fe.primaryImageUrl.flatMap(URL.init) {
                    FitImage(url: u)
                }
                VStack(alignment: .leading, spacing: Nuru.S.sm) {
                    Text("⭐ FEATURED GATHERING").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                    Text(fe.title).font(.fraunces(18, .semibold)).foregroundStyle(Nuru.navy)
                        .multilineTextAlignment(.leading)
                    if let d = fe.description, !d.isEmpty {
                        Text(d).font(.nCaption).foregroundStyle(Nuru.ink600)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                    Text([featuredWhen(fe.dtstartLocal), fe.location].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "  ·  "))
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                }
                .padding(Nuru.S.base)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.pressableSubtle)
    }

    private func featuredWhen(_ dtstartLocal: String) -> String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let d = f.date(from: String(dtstartLocal.prefix(19))) else { return dtstartLocal }
        let out = DateFormatter(); out.dateFormat = "EEE, MMM d · h:mm a"
        return out.string(from: d)
    }

    // The curated rows (GET /home/events): the month grid that used to live here
    // is gone (owner ask) — the Events tab keeps the full calendar. Up to 5 rows,
    // exactly as the server sent them (soonest-first, server-capped): thumb, gold
    // relative-time kicker, title, venue, and the member's RSVP state (or the
    // RSVP call-to-action). Each row pushes the SAME event-detail destination the
    // RSVP/QR flows use (CalendarOccurrence by occurrence_id).
    private var upcomingCard: some View {
        VStack(alignment: .leading, spacing: Nuru.S.md) {
            HStack {
                Text("GATHERINGS").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                Spacer()
                Button { Haptics.selection(); tabs.openYou(.events) } label: {
                    Text("See all").font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                }.buttonStyle(.pressable)
            }
            ForEach(vm.homeEvents) { e in
                Button { Haptics.tap(); path.append(CalendarOccurrence(homeEvent: e)) } label: {
                    HomeUpcomingEventRow(
                        kicker: eventKicker(e.startsAt),
                        soon: eventSoon(e.startsAt),
                        title: e.title,
                        sub: (e.venue?.isEmpty == false ? e.venue! : "Next gathering"),
                        subHighlight: false,
                        imageUrl: e.primaryImageUrl,
                        rsvpStatus: e.myRsvp)
                }.buttonStyle(.pressable)
            }
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func eventKicker(_ startAt: String) -> String {
        guard let d = parseISO(startAt) else { return timeLine(startAt) }
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(d) { day = "Today" }
        else if cal.isDateInTomorrow(d) { day = "Tomorrow" }
        else { let f = DateFormatter(); f.dateFormat = "EEE, MMM d"; day = f.string(from: d) }
        return "\(day) · \(timeLine(startAt))"
    }

    private func eventSoon(_ startAt: String) -> Bool {
        guard let d = parseISO(startAt) else { return false }
        return d.timeIntervalSinceNow < 48 * 3600
    }

    // MARK: 16 — Encouragement ("one reflection away" / "beautifully done")

    private var oneReflectionBanner: some View {
        HomeEncouragementCard(
            firstName: firstName,
            streak: vm.streak,
            rhythmDone: vm.rhythm.doneCount,
            wordDone: vm.rhythm.word,
            prayerDone: vm.rhythm.prayer,
            modulesLeft: active.map { max(0, $0.totalModules - $0.completedModules) },
            levelNumber: active?.levelNumber,
            cellPrayerCount: vm.prayerPosts.count
        )
    }

    // MARK: 17 — Your cohort (label outside; belonging cue when not in a cell)

    private var cohortSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HomeSectionLabel(text: "Your cell")
            cohortCard
        }
    }

    private var cohortCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(vm.cell?.name ?? "Your discipleship cell").font(.nCardMeta).foregroundStyle(HomeFig.faintGray)
            if vm.cell == nil {
                // Cold-start belonging cue — being known is the hook (Figma).
                NavigationLink(value: AppRoute.cell) { HomeCohortColdStart() }
                    .buttonStyle(.pressable)
                    .padding(.top, 10)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                cohortStat(.users, "Leader", vm.cell?.leader?.name ?? "Not assigned")
                cohortStat(.calendarDays, "Next gathering", nextGatheringText)
                cohortStat(.users, "Members", vm.cell.map { "\($0.members)" } ?? "—")
                cohortStat(.target, "Attendance", attendanceText)
            }
            .padding(.top, 10)
            NavigationLink(value: AppRoute.cell) {
                // Says what it opens: this link goes to the CELL, not community.
                Text("Open your cell →").font(.inter(12, .semibold)).foregroundStyle(HomeFig.navy)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .padding(.top, Nuru.S.md)
        }
        .padding(Nuru.S.base)
        .cardSurface()
    }

    private func cohortStat(_ icon: Lucide, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Icon(icon, size: 11, color: Nuru.gold)
                Text(label.uppercased()).font(.inter(9, .semibold)).kerning(0.9).foregroundStyle(HomeFig.faintGray)
            }
            Text(value).font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Nuru.S.md)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var nextGatheringText: String {
        guard let n = vm.cell?.next else { return "TBA" }
        return shortDateTime(n.startAt)
    }
    private var attendanceText: String {
        guard let a = vm.cell?.attendance, a.expected > 0 else { return "—" }
        return "\(a.attended)/\(a.expected)"
    }

    // MARK: 18 — Support God's work (give panel — centered ceremony layout)

    private var giveBanner: some View {
        HomeGiveCard { tabs.openYou(.give) }
    }

    // MARK: derived / helpers

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
    private var firstName: String { (auth.profile?.fullName ?? "Friend").split(separator: " ").first.map(String.init) ?? "Friend" }
    private var isSunday: Bool { Calendar.current.component(.weekday, from: Date()) == 1 }
    private var greeting: String {
        if isSunday { return "Happy Lord's Day" }
        let h = Calendar.current.component(.hour, from: Date())
        return h < 12 ? "Good morning" : h < 17 ? "Good afternoon" : h < 21 ? "Good evening" : "Rest well"
    }
    private func todayKicker() -> String {
        if isSunday {
            let f = DateFormatter(); f.dateFormat = "MMM d"
            return "SUNDAY · THE LORD'S DAY · \(f.string(from: Date()).uppercased())"
        }
        let f = DateFormatter(); f.dateFormat = "EEEE · MMM d"
        return f.string(from: Date()).uppercased() + " · EAT"
    }
    /// The header breathes with the day — dawn rose-gold, plain daylight cream,
    /// a deeper golden hour, and a quieter dusk. Same palette family as the
    /// Figma header, just tilted by the hour; Sundays glow a touch warmer.
    private var headerPalette: (top: Color, bottom: Color, glow: Double) {
        let h = Calendar.current.component(.hour, from: Date())
        let base: (UInt32, UInt32, Double) =
            h < 5  ? (0xEFEDEA, 0xE5E0D6, 0.16) :   // deep night — quiet
            h < 9  ? (0xF9F1E7, 0xF3E3CC, 0.34) :   // dawn — rose-gold
            h < 16 ? (0xF6F4EF, 0xEFE8DA, 0.27) :   // daylight — the Figma cream
            h < 19 ? (0xF7EFDD, 0xEEDFC2, 0.40) :   // golden hour
                     (0xF1EEE8, 0xE7E1D4, 0.20)     // dusk
        return (Color(hex: base.0), Color(hex: base.1), base.2 + (isSunday ? 0.08 : 0))
    }
    private func durationLabel(_ sec: Int) -> String {
        let m = sec / 60, s = sec % 60
        return String(format: "%d:%02d", m, s)
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

// MARK: - First-load skeleton (shimmering card ghosts in the feed's rhythm)

/// Shown ONLY on the true first load (`loading && pathway == nil`) — pull-to-
/// refresh keeps the live content in place. Mirrors the top of the feed:
/// hero → video → verse → minis.
private struct HomeFeedSkeleton: View {
    var body: some View {
        VStack(spacing: Nuru.S.base) {
            ghost(height: 190)
            ghost(height: 240)
            ghost(height: 150)
            HStack(spacing: Nuru.S.sm) {
                ghost(height: 128)
                ghost(height: 128)
            }
        }
    }
    private func ghost(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(Nuru.surface)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Nuru.border, lineWidth: 1))
            .nuruShimmer()
    }
}

// MARK: - Dashboard-failed strip (quiet retry; the rest degrades gracefully)

private struct HomeLoadErrorCard: View {
    let retry: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(HomeFig.metaGray)
                .frame(width: 36, height: 36)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text("Couldn't load your dashboard").font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                Text("Check your connection and try again.").font(.nCardMeta).foregroundStyle(HomeFig.metaGray)
            }
            Spacer(minLength: 8)
            Button { Haptics.tap(); retry() } label: {
                Text("Retry")
                    .font(.inter(11, .semibold)).foregroundStyle(Nuru.gold)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(HomeFig.navy, in: Capsule())
            }
            .buttonStyle(.pressable)
        }
        .padding(12)
        .background(Nuru.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }
}

// MARK: - Header LIVE entry ring (2026-07-31 viewer redesign) — a slow
// breathing red ring around the header's live glyph, same "something is
// happening right now" language as the LIVE badge's pulsing dot elsewhere
// in this feature, just reshaped for a 40pt circular icon slot.

private struct HomeLiveHeaderRing: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expand = false
    var body: some View {
        Circle()
            .stroke(Color(hex: 0xDC2626), lineWidth: 1.5)
            .scaleEffect(expand ? 1.28 : 1)
            .opacity(expand ? 0 : 0.8)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeOut(duration: 1.3).repeatForever(autoreverses: false)) { expand = true }
            }
    }
}

// MARK: - Unread bell badge (pops in once, counts roll numerically)

private struct HomeUnreadBadge: View {
    let count: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        Text(count > 9 ? "9+" : "\(count)")
            .font(.inter(9, .bold)).foregroundStyle(Nuru.navy)
            .frame(minWidth: 16, minHeight: 16).padding(.horizontal, 2)
            .background(Nuru.gold, in: Capsule())
            .contentTransition(.numericText())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
            .scaleEffect(shown || reduceMotion ? 1 : 0.4)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                guard !shown else { return }
                // One springy arrival beat — attention without a looping pulse.
                withAnimation(.spring(response: 0.35, dampingFraction: 0.6).delay(0.35)) { shown = true }
            }
    }
}

// MARK: - Progress-ring arc that sweeps in once and re-tracks data changes

private struct HomeRingTrim: View {
    let pct: CGFloat            // 0…1
    let style: AnyShapeStyle
    let lineWidth: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    var body: some View {
        Circle()
            .trim(from: 0, to: shown ? min(max(pct, 0), 1) : 0)
            .stroke(style, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(reduceMotion ? nil : .spring(response: 0.8, dampingFraction: 0.85), value: pct)
            .onAppear {
                guard !shown else { return }
                if reduceMotion { shown = true }
                else { withAnimation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.2)) { shown = true } }
            }
    }
}
