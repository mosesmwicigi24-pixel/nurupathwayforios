// Home — the native port of screens/HomeDashboardScreen.tsx, re-ordered by
// EXPERIENCE.md §6.1 (Cycle 2, information hierarchy): each pillar has one
// home and Home points to it once. Top to bottom: the live and on-air banners
// (only while live) → the owner's opening (verse → video → the Sunday letter →
// what needs you today, or the reflection strip → the liturgy) → YOUR WEEK
// (Pathway · Plans · Events · Giving · Cell, HomeWeek) → the day (today's
// rhythm, then today's echo) → the family (prayer wall, celebrations, the
// featured carousel, the featured gathering) → growing (progress, grow your
// faith, encouragement) → "Support God's work", only while the week's giving
// row asks. All sections load concurrently and degrade gracefully (a section
// hides when its data is empty; a week row falls back to its "none" form).
import SwiftUI

@MainActor
final class HomeViewModel: ObservableObject {
    // Core
    @Published var pathway: PathwaySummary?
    @Published var streak = 0
    @Published var greetingLine = "Grace for today's step."
    @Published var rhythm = RhythmToday(prayer: false, word: false, reflection: false)
    /// The rhythm has answered at least once. Until then nothing about today's
    /// prayer, Word or reflection is said — a failed read used to show three
    /// "not yet" tiles and "Reflection due today" (§9.4: no fake facts).
    @Published var rhythmLoaded = false
    @Published var scores: ScoresSummary?
    /// GET /me/home/nudges — "What needs you today". Empty (or a failed
    /// fetch) hands the slot back to the old single reflection strip, so Home
    /// never loses its nudge.
    @Published var nudges: [HomeNudge] = []
    /// Every plan row from GET /growth/plans — a plan nudge opens its detail
    /// with the row the Plans stack expects, and YOUR WEEK names the plan
    /// being read (ReadingPlanRow.active).
    @Published var plans: [ReadingPlanRow] = []

    // Verse
    @Published var verse: (text: String, reference: String, version: String)?
    @Published var verseReason: String?
    @Published var verseArt: VerseArt?   // the day's tableau photograph (server-curated)
    /// Seven-bands addition — when present, replaces the "Chosen for your
    /// season" ribbon with a personal encouragement quote + attribution.
    @Published var verseEncouragement: Encouragement?
    @Published var reactions: VerseReactions?
    @Published var verseSaved = false
    @Published var verseSaving = false
    /// Why the verse didn't save, in words (§4; Cycle 4) — nil otherwise.
    @Published var verseSaveLine: String?

    // Rich home cards
    @Published var welcomeVideo: WelcomeVideo?
    @Published var prayerPosts: [PrayerWallPost] = []
    @Published var featuredAnnouncement: FeaturedAnnouncement?
    @Published var announcements: [MyAnnouncement] = []
    /// The member's OWN cell (GET /me/cell-summary) — YOUR WEEK's cell row.
    @Published var cell: CellSummary.Cell?
    /// When the member asked to be connected to a cell (GET
    /// /me/cell-connection), on any phone — the row says so (§9.2 #12).
    @Published var cellAskedAt: String?
    @Published var events: [CalendarOccurrence] = []
    /// GET /home/events — up to 5 curated, soonest-first rows: the featured
    /// carousel's gatherings and YOUR WEEK's events row. Server-capped and
    /// pre-sorted; never re-capped or re-sorted here.
    @Published var homeEvents: [HomeEventRow] = []
    /// GET /me/rsvps — what the member said yes to ("You're going").
    @Published var rsvps: [MyRsvp]?
    /// GET /giving/partnership (the DUE list, the pledges) and GET
    /// /giving/schedules (the recurring gifts) — YOUR WEEK's giving row, by
    /// the Give code's own rules. Nil when a read failed: the row then asks
    /// ("Give") rather than guess.
    @Published var partnership: Partnership?
    @Published var schedules: [GivingSchedule]?
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
    /// Why the dashboard's pathway didn't load — spoken through the one state
    /// language (NuruStateCopy), never as the server's raw text.
    @Published var failure: Error?
    /// The current level's module trail — read only for the journey's next
    /// step (which module to continue). Nil until it loads.
    @Published var trail: [LevelModule]?
    /// The member's journey (EXPERIENCE.md §3): the header pill, the continue
    /// card and the progress line all read this one derivation.
    @Published var journey: Journey?
    /// GET /giving/methods — the giving card names only the rails that work
    /// here. Nil until the first answer; a failed refresh keeps the last one.
    @Published var givingMethods: GivingMethods?
    /// The latest Sunday Letter (intelligence layer) — drives the gold
    /// "A letter for you" knock on Home while unread.
    @Published var letter: PastoralLetter?
    /// Flips true the moment the THIRD rhythm discipline lands DURING this
    /// session — a refresh moving 2→3, never a first load that arrives already
    /// done. Per-session only (nothing persisted): the rhythm card answers with
    /// one soft gold sweep and a "Day sealed" line that stays.
    @Published var daySealed = false
    private var lastRhythmDone: Int?

    /// `quiet`: the refresh in place (the walk's B5) — no skeleton, no
    /// `loading` flip, and a refresh that can't reach the server changes
    /// nothing, so a dropped connection never blanks what the member sees.
    func load(quiet: Bool = false) async {
        if !quiet { loading = true; failure = nil }
        async let letter = try? MemberAPI.latestLetter()
        async let pathway = Self.attempt { try await MemberAPI.pathway() }
        async let ach = try? MemberAPI.achievements()
        let unreadTicket = InboxBadge.shared.ticket()
        async let unread = try? MemberAPI.unreadNotifications()
        async let greet = try? MemberAPI.dailyGreeting()
        async let nudges = try? MemberAPI.homeNudges()
        async let rhythm = try? MemberAPI.rhythmToday()
        async let scores = try? MemberAPI.scores()
        async let hv = try? MemberAPI.homeVerse()
        async let vr = try? MemberAPI.verseReactions()
        async let video = try? MemberAPI.welcomeVideo()
        async let posts = try? MemberAPI.prayerWallHome()
        async let plans = try? MemberAPI.plans()
        async let fann = try? MemberAPI.featuredAnnouncement()
        async let anns = try? MemberAPI.myAnnouncements()
        async let summary = try? MemberAPI.cellSummary()
        async let cal = try? MemberAPI.calendar(from: Self.calFrom, to: Self.calTo)
        async let hev = try? MemberAPI.homeEvents()
        async let myRsvps = try? MemberAPI.myRsvps()
        async let fev = try? MemberAPI.featuredEvent()
        async let radio = try? MemberAPI.radioNowPlaying()
        async let live = try? MemberAPI.fetchLiveNow()
        async let methods = try? MemberAPI.givingMethods()
        async let standing = try? MemberAPI.partnership()
        async let gifts = try? MemberAPI.schedules()

        let pathwayResult = await pathway
        if quiet, case .failure = pathwayResult { return }
        self.letter = (await letter) ?? nil
        switch pathwayResult {
        case .success(let p): self.pathway = p; failure = nil
        case .failure(let e): self.pathway = nil; failure = e
        }
        // The journey speaks as soon as the summary lands (the pill's words
        // need nothing more); the trail below only names the module to continue.
        self.journey = Journey.derive(self.pathway, trail: self.trail)
        // The current level's trail, started now so it runs beside the rest
        // of the dashboard rather than after it.
        let currentLevel = self.pathway?.currentLevel
        async let trail = Self.levelTrail(currentLevel)
        let achievements = await ach
        self.streak = achievements?.streak?.current ?? 0
        // The inbox's count is the bells' one count (§7.2 #4) — landed with
        // the ticket taken before the read, so a fresher one isn't undone.
        if let n = await unread { InboxBadge.shared.land(n, ticket: unreadTicket) }
        if let g = await greet, !g.isEmpty { greetingLine = g }
        self.nudges = await nudges ?? []
        if let r = await rhythm { self.rhythm = r; rhythmLoaded = true }
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
        self.plans = await plans ?? []
        self.featuredAnnouncement = await fann ?? nil
        self.announcements = await anns ?? []
        self.cell = (await summary)?.cell
        // Asked to be connected? Only worth asking while there's no cell.
        if self.cell == nil, let s = try? await MemberAPI.cellConnection(), !s.inCell {
            self.cellAskedAt = s.request?.requestedAt
        }
        self.events = (await cal ?? []).sorted { $0.startAt < $1.startAt }
        // Rendered exactly as received — the server caps at 5 and orders
        // soonest-first; the client never caps, sorts, or filters.
        self.homeEvents = await hev ?? []
        self.rsvps = await myRsvps
        self.onAir = Self.liveOnly((await radio) ?? nil)
        self.featuredEvent = (await fev) ?? nil
        self.liveStreams = await live ?? []
        if let m = await methods { self.givingMethods = m }
        self.partnership = await standing
        self.schedules = await gifts
        self.trail = await trail
        self.journey = Journey.derive(self.pathway, trail: self.trail)

        if !quiet { loading = false }

        celebrateMilestones(achievements)
    }

    private var lastQuietRefresh = Date.distantPast
    /// Home stayed as first loaded for the whole session (the walk's B5: the
    /// cell read "6 members" for over an hour while the server said 5). It
    /// now refreshes in place when the tab reappears, when its stack returns
    /// to the root, and on foreground — within HomeRefresh's guards.
    func refreshQuietly() async {
        guard HomeRefresh.should(loading: loading, loaded: pathway != nil,
                                 online: SyncCoordinator.devicePathOnline, last: lastQuietRefresh) else { return }
        lastQuietRefresh = Date()
        await load(quiet: true)
    }

    /// A call's answer or its failure — the dashboard keeps WHY the pathway
    /// failed, so its strip can say what really happened.
    private static func attempt<T>(_ op: () async throws -> T) async -> Result<T, Error> {
        do { return .success(try await op()) } catch { return .failure(error) }
    }

    /// The module trail of the member's current level (nil when there is no
    /// level yet, or the read failed — the journey then speaks from the summary).
    private static func levelTrail(_ level: Int?) async -> [LevelModule]? {
        guard let level else { return nil }
        return try? await MemberAPI.levelModules(level)
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
    /// "Saved" only on the server's word (§7.4 #2): the heart fills, with its
    /// haptic, once the verse is kept; a failure is felt and leaves "Save".
    func saveVerse() async {
        guard !verseSaved, !verseSaving, let v = verse else { return }
        verseSaving = true
        verseSaveLine = nil
        defer { verseSaving = false }
        do {
            try await MemberAPI.saveVerseQuick(reference: v.reference, version: v.version, text: v.text)
            verseSaved = true
            Haptics.success()
        } catch {
            // Felt AND said (§4): "Couldn't save that." + why; "Save" stays to retry.
            Haptics.error()
            verseSaveLine = NuruStateCopy.saveFailureLine(error)
        }
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

    /// "Today" / "Tomorrow" / "In N days" until the next Sunday 6 pm in
    /// Africa/Nairobi — the hour the Sunday Letter is written. A Sunday past
    /// six counts toward NEXT Sunday (this week's letter has either arrived —
    /// a different card — or is on its way). Injectable `now` for tests.
    static func sundayLetterCountdown(now: Date = Date()) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Africa/Nairobi") ?? .current
        let weekday = cal.component(.weekday, from: now)   // 1 = Sunday
        let hour = cal.component(.hour, from: now)
        var days = (8 - weekday) % 7                       // 0 = today is Sunday
        if days == 0 && hour >= 18 { days = 7 }
        switch days {
        case 0:  return "Today"
        case 1:  return "Tomorrow"
        default: return "In \(days) days"
        }
    }
}

private let verseReactionEmojis = ["❤️", "🙏", "🔥", "🙌", "👍"]
private let videoReactionEmojis = ["🙏", "🔥", "🎉", "👏"]
private struct GrowTile { let label, sub: String; let icon: Lucide; let tint, fg: UInt32; let dest: AnyHashable }

struct HomeView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vm = HomeViewModel()
    /// Whether a discipler is paired (GET /growth/mentor) — the discipler row
    /// shows only then (Cycle 4, B1).
    @ObservedObject private var disciplers = DisciplerStore.shared
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
    @State private var videoReady = false   // welcome video finished buffering its embed
    /// The partner invitation. Whether it may be shown is decided entirely by
    /// the server; Home's only job is to ask once per appearance and present
    /// whatever comes back. Nil until the server says yes.
    @State private var partnerInvite: PartnerInvite.Campaign?
    @State private var partnerInviteShowing = 1
    @State private var sharePayload: SharePayload?
    @State private var verseShareDialog = false
    @State private var verseShareImage: VerseImagePayload?
    @State private var openedLetter: PastoralLetter?   // Sunday Letter sheet
    @State private var showLetterArchive = false       // "Your Letters" from the arrival card
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

    // Grow your faith — a 2×2 grid (the fresh Figma GrowGrid's tints and
    // labels) and the discipler's row below it (§6.1, growing). The reading-
    // plan tile left with Cycle 2: YOUR WEEK's Plans row and the Plans tab
    // are where a plan lives. Android's order, tile for tile.
    private var growTiles: [GrowTile] {
        [
            // One tile look (§8.1 rules 1, 7): the walk's E17 found a
            // pink-red Prayer Room and a purple Calling.
            GrowTile(label: "Devotional", sub: "Today's devotional", icon: .sun, tint: Nuru.tileTint, fg: Nuru.tileIcon, dest: GrowDestination.devotional),
            GrowTile(label: "Hide His Word", sub: "Memorize Scripture", icon: .quote, tint: Nuru.tileTint, fg: Nuru.tileIcon, dest: GrowDestination.memoryVerses),
            GrowTile(label: "My Prayer Room", sub: "Pray with the family", icon: .handHeart, tint: Nuru.tileTint, fg: Nuru.tileIcon, dest: CommunityRoute.prayerWall),
            GrowTile(label: "Your Calling", sub: "Discover your gifts", icon: .sparkles, tint: Nuru.tileTint, fg: Nuru.tileIcon, dest: GrowDestination.gifts),
        ]
    }

    // The Home feed as an ARRAY of individually type-erased views. This is the only
    // form that reliably avoids the on-device type-demangler stack overflow: the
    // enclosing VStack/ForEach type is flat (`ForEach<…, AnyView>`), and each card's
    // (deeply-generic) type is demangled ONE AT A TIME here — in a shallow stack —
    // as its AnyView box is built. `some View` groups and even AnyView-of-6 still
    // forced the runtime to decode several cards' types together and overflowed.
    // Section order is EXPERIENCE.md §6.1's (Cycle 2): the live and on-air
    // banners (only while live) → the owner's opening → YOUR WEEK → the day →
    // the family → growing → "Support God's work" only while the week asks.
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
        // YOUR WEEK's rows, read first: "What needs you today" (above them)
        // never repeats one (§9.1 rule 3).
        let week = weekRows
        // A first day leads with the path's first step, not a side task
        // (§9.1 rule 4): the reflection waits; a person waiting never does.
        let firstDay = vm.journey?.isFirstDay == true
        let needs = vm.nudges.filter { !HomeWeek.repeats($0, in: week) && !(firstDay && $0.kind == "reflection_due") }
        // Nuru Live — the church-scope LIVE banner sits at the very TOP of the
        // whole feed, above even the load-error strip: a live broadcast is the
        // most urgent thing on the screen. Hidden entirely when nothing church-
        // scope is live (no fake "off air" chrome on Home).
        if let live = churchLiveStream {
            s.append(("livebanner", AnyView(liveBannerCard(live))))
        }
        // The whole dashboard failed — a quiet strip on top, saying what really
        // happened (offline, the session ended, our server) in the one state
        // language; the sections below degrade gracefully as usual.
        if let f = vm.failure, vm.pathway == nil {
            s.append(("loaderror", AnyView(NuruStateView(state: .failed(.failure(f)),
                                                          retry: { Task { await vm.load() } }, compact: true))))
        }
        if let p = vm.onAir { s.append(("onair", AnyView(onAirCard(p)))) }                         // 1 · Radio ON AIR (only while live)
        // 2 · Owner's order (2026-08-25, stated exactly): verse for today →
        // featured video → the Sunday Letter → reflection due → the liturgy.
        // Unchanged by Cycle 2 — the live-gathering card keeps its old slot
        // after the video, and only while a service is on or about to start.
        // Verse of the day (leads the feed) — once it loaded: a stand-in verse
        // under "VERSE FOR TODAY" was not today's verse (§9.4).
        if vm.verse != nil { s.append(("verse", AnyView(verseCard))) }
        if let v = vm.welcomeVideo { s.append(("video", AnyView(welcomeVideoCard(v)))) }           // Featured video (start here)
        if let live = liveNowInfo { s.append(("livenow", AnyView(liveNowCard(live)))) }              // Live now
        if let lt = vm.letter, lt.isUnread {
            s.append(("letter", AnyView(letterKnock(lt))))
        } else if let lt = vm.letter {
            s.append(("letter", AnyView(letterReadRow(lt))))
        } else {
            s.append(("letter", AnyView(letterArrivalCard)))
        }
        // "What needs you today" — the server-ranked rail takes the priority
        // slot, less any nudge a YOUR WEEK row already asks (§9.1 rule 3: the
        // row keeps it). An empty (or failed) fetch falls back to the old
        // single reflection strip so Home never loses its nudge (one place,
        // one ask); a rail whose every nudge is a row's shows nothing.
        if !needs.isEmpty { s.append(("needsyou", AnyView(HomeNeedsYouRail(nudges: needs) { openNudge($0) }))) }
        else if vm.nudges.isEmpty, reflectionDue, !firstDay { s.append(("priority", AnyView(priorityStrip))) }
        s.append(("liturgy", AnyView(HomeLiturgyCard())))                                            // The hour's prayer — below the reflection strip (owner)
        // 3 · YOUR WEEK — one row per pillar, each pointing to its home once.
        // It replaced the "For you today" hero, the continue-level card, the
        // reading-plan/journal minis, the plan banner, both cell cards and the
        // upcoming list: each told one of these five stories again.
        s.append(("week", AnyView(HomeWeekCard(rows: week) { openWeek($0) })))
        // 4 · The day: today's rhythm, then today's echo.
        if vm.rhythmLoaded { s.append(("rhythm", AnyView(rhythmCard))) }                          // Today's rhythm — once it is known
        s.append(("echo", AnyView(HomeEchoCard())))                                               // Today's echo — the app remembers you (Wave 1)
        s.append(("selah1", AnyView(SelahDivider())))                                               // — selah: a rest for the eye
        // 5 · The family. (The disciplers carousel left with Cycle 2: the
        // discipler's one door on Home is grow's "Your discipler" row.)
        if !vm.prayerPosts.isEmpty { s.append(("prayerwall", AnyView(prayerWallCard))) }
        s.append(("celebrations", AnyView(CelebrationsRail())))                                           // Celebrate the family (moments, Phase 4)
        if !featuredPages.isEmpty { s.append(("announcement", AnyView(featuredCarousel))) }             // carousel: portal-marked announcements + events
        if let fe = vm.featuredEvent, let next = fe.nextStart() {                                   // admin-featured event,
            s.append(("event", AnyView(featuredGatheringCard(fe, next: next))))                     // only while it meets again (B6)
        }
        // 6 · Growing.
        if let sc = vm.scores { s.append(("progress", AnyView(progressCard(sc)))) }
        s.append(("selah2", AnyView(SelahDivider())))                                               // — selah: a rest before Grow
        s.append(("grow", AnyView(growSection)))
        s.append(("encourage", AnyView(oneReflectionBanner)))
        // 7 · Support God's work — only while the week's giving row is "Give":
        // a member already giving isn't asked twice.
        if HomeWeek.asksToGive(week) { s.append(("give", AnyView(giveBanner))) }
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
                .scrollsToTopOnReselect(.home)   // a re-tap at the root returns to the top (B10)
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
            .nuruEdgeSwipeBack()   // back by the edge swipe on every pushed page (B9)
            .nuruDestinations()
        }
        // A re-tap on Home returns to Home's top (§7.4 #17 — a stale "not
        // found" page stayed in this stack).
        .popsToRoot(on: .home, path: $path)
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
        // The partner invitation. Presented only when the server said to, and
        // reported back either way — a dismissal is data too.
        .sheet(item: $partnerInvite) { c in
            PartnerInviteSheet(
                campaign: c,
                showing: partnerInviteShowing,
                onBecomePartner: {
                    Task { try? await MemberAPI.inviteOutcome(c.campaignId, outcome: "opened") }
                    // Opens the Partners portal (Give tab → Partners segment).
                    // NOT a payment sheet.
                    tabs.openPartners()
                },
                onDismiss: { permanent in
                    Task {
                        try? await MemberAPI.inviteOutcome(
                            c.campaignId, outcome: permanent ? "declined" : "dismissed")
                    }
                })
        }
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
        .sheet(isPresented: $showLetterArchive) { LetterArchiveView() }
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
            // Ask once per appearance. Every rule about WHEN is the server's;
            // a failure here is silence, never a retry loop and never a guess.
            guard partnerInvite == nil,
                  let d = try? await MemberAPI.partnerInvite(),
                  d.show, let c = d.campaign else { return }
            partnerInviteShowing = d.showing ?? 1
            partnerInvite = c
            // Rendered, not merely decided — this is what the cap counts.
            try? await MemberAPI.inviteShown(c.campaignId)
        }
        .task {
            if vm.pathway == nil { await vm.load() }
            liveDiscovery.ingest(vm.liveStreams)
            deepLinkForScreenshots()
        }
        // In place, never a skeleton (the walk's B5): when Home's tab comes
        // back, when its stack returns to the root (a plan day finished, an
        // RSVP, a passed exam), and on foreground while Home is shown.
        .onChange(of: tabs.selected) { _, t in
            if t == .home { Task { await vm.refreshQuietly() } }
        }
        .onChange(of: path.isEmpty) { _, atRoot in
            if atRoot { Task { await vm.refreshQuietly() } }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, tabs.selected == .home { Task { await vm.refreshQuietly() } }
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
        case "cellRoster": path.append(AppRoute.cellRoster)
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
        // The exam screen as the server answers it — its refusal, its way out.
        case "exam": path.append(PathwayRoute.exam(1))
        // One announcement by id, as the server answers it — e.g. a removed
        // one's state card (§7.4 #12): NURU_SCREEN=announcement:<uuid>.
        case let s? where s.hasPrefix("announcement:"):
            path.append(AppRoute.announcement(String(s.dropFirst("announcement:".count))))
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
                    Image(systemName: skyGlyph).font(.symbol(11, weight: .semibold))
                        .foregroundStyle(Nuru.gold)
                    // The kicker role (§8.1 rule 3) — at the old 2.4 tracking
                    // Sunday's "THE LORD'S DAY" kicker was cut short.
                    Text(todayKicker()).font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.eyebrow)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
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
                    // The bell's look and size beside it (§8.1 rule 7).
                    Icon(.qrCode, size: 18, color: Nuru.navy)
                        .frame(width: 44, height: 44)
                        .background(Nuru.white, in: Circle())
                        .overlay(Circle().stroke(Nuru.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Scan to check in")
                .padding(.trailing, 8)
                // The one bell (§7.2 #4): the inbox, and a gold dot only while
                // something in it is unread (it used to carry a count here).
                NuruBell()
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
                                .font(.symbol(13, weight: .semibold))
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
                        Image(systemName: "video.fill").font(.symbol(16))
                            .foregroundStyle(Nuru.navy).frame(width: 40, height: 40)
                            .background(Nuru.gold, in: Circle())
                            .overlay(Circle().stroke(Nuru.gold.opacity(0.5), lineWidth: 1))
                    }
                    .buttonStyle(.pressable).padding(.leading, 8)
                    .accessibilityLabel("Go live")
                }
                // The score once there is one (the Android walk's A3: no
                // fact before it loads; §7.4 #9: no "0" ring).
                if HomeHeaderWords.showsScore(vm.scores?.overall.score) {
                    progressRing.padding(.leading, 8)
                }
            }
            Text(HomeHeaderWords.greeting(greeting, fullName: auth.profile?.fullName))
                .font(.fraunces(22, .semibold)).kerning(-0.22).foregroundStyle(Nuru.navy)
                .lineLimit(1).minimumScaleFactor(0.8)   // long first names shrink, never wrap
                .padding(.top, 10)
                .gentleEntrance()
            // Nuru's daily word — a blessing written for THIS member (grounded in
            // their streak/level/prayers server-side, cached per day). It deserves
            // more than flat gray: a hanging gold quote and a settled serif voice.
            HomePersonalWord(text: vm.greetingLine)
                .padding(.top, 6)
            if let j = vm.journey {
                // The journey jewel — the level · where the member stands on it
                // (the journey's pill: "3 of 10 modules", "Exam ready"…) · the
                // streak while it is alive, ringed in a soft gold gradient. No
                // "Begin today" beside a finished level: the pill says the truth.
                HStack(spacing: 6) {
                    Text("Level \(j.levelNumber)").font(.inter(12, .bold)).foregroundStyle(Nuru.navy)
                    Circle().fill(Nuru.gold.opacity(0.6)).frame(width: 3, height: 3)
                    Text(j.pill)
                        .font(.inter(12, .semibold)).foregroundStyle(Color(hex: 0x9A7A2A))
                    // (The streak is named once on Home — on the rhythm card,
                    // §9.2 #3; it was "🔥 3-day" here too.)
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

    /// The sky in the kicker — the liturgy card's part of the day, on the
    /// church's clock (§9.3 rule 3), as the greeting and the header's light.
    private var skyGlyph: String {
        switch ChurchClock.part() {
        case .morning: return "sunrise.fill"
        case .midday: return "sun.max.fill"
        case .evening: return "sunset.fill"
        case .night: return "moon.stars.fill"
        }
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
            // A score is progress, and progress is gold (§8.1 rule 1).
            Circle().fill(Color(hex: Nuru.tileTint).opacity(0.8))
            Circle().stroke(Nuru.gold.opacity(0.18), lineWidth: 3)
            HomeRingTrim(
                pct: CGFloat(growthScore) / 100,
                style: AnyShapeStyle(LinearGradient(colors: [Nuru.goldLo, Nuru.goldHi],
                                                    startPoint: .top, endPoint: .bottom)),
                lineWidth: 3)
            // A score out of 100 (the growth score), not a percent of anything.
            Text("\(growthScore)").font(.inter(11, .bold)).foregroundStyle(Nuru.goldChipText)
                .contentTransition(.numericText())
                .animation(.spring(response: 0.4, dampingFraction: 0.8), value: growthScore)
        }
        .frame(width: 42, height: 42)
        .overlay(alignment: .bottomTrailing) {
            if let t = growthTrend, t.delta != 0 { trendBadge(t).offset(x: 5, y: 4) }
        }
        .accessibilityLabel("Growth score \(growthScore) out of 100")
    }

    /// A tiny ▲/▼ badge — points earned or lost vs the previous 28 days.
    private func trendBadge(_ t: ScoreTrend) -> some View {
        HStack(spacing: 0.5) {
            Image(systemName: t.isDown ? "arrow.down" : "arrow.up").font(.symbol(7, weight: .black))
            Text("\(abs(t.delta))").font(.inter(11, .bold)).contentTransition(.numericText())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 3.5).padding(.vertical, 1.5)
        .background(t.isDown ? Nuru.warning : Nuru.success, in: Capsule())
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
                    Icon(.mail, size: 18, color: Color(hex: 0x1E2A1F))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE SUNDAY LETTER").font(.inter(11, .bold)).kerning(1.6)
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
                    Icon(.mail, size: 18, color: Color(hex: 0x1E2A1F))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE SUNDAY LETTER").font(.inter(11, .bold)).kerning(1.6)
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
    /// Tapping opens "Your Letters" (the archive sheet LetterView also
    /// reaches) — usually empty for the member this card addresses, but it
    /// says so kindly and it is where the letters will live. The gold pill
    /// counts down to Sunday 6 pm Nairobi, the hour the letter is written.
    private var letterArrivalCard: some View {
        Button {
            Haptics.tap()
            showLetterArchive = true
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Color(hex: 0xE8CA6C), Color(hex: 0xB6862F)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Icon(.mail, size: 18, color: .white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("THE SUNDAY LETTER").font(.inter(11, .bold)).kerning(1.6)
                        .foregroundStyle(Color(hex: 0xE8CA6C))
                    Text("Your letter arrives Sunday evening").font(.fraunces(15, .semibold)).foregroundStyle(.white)
                    Text("Written for your week")
                        .font(.inter(11)).foregroundStyle(Color(hex: 0xC7D0DC))
                }
                Spacer(minLength: 8)
                Text(Self.sundayLetterCountdown())
                    .font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x0A1628))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Color(hex: 0xC9A227), in: Capsule())
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
        .buttonStyle(.pressableSubtle)
        .accessibilityHint("Opens your letters.")
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
        !vm.loading && vm.rhythmLoaded && !vm.rhythm.reflection
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

    // MARK: 1 — "What needs you today" (server-ranked nudges; replaces the strip)

    /// Routes a nudge to the surface that clears it. Content opens INSIDE the
    /// tab that owns it (the TabRouter contract): Pathway for a quiz or a level
    /// exam, Plans for a plan or a reading invite, You → Community for a
    /// thread; the devotional, the cell and the letter are Home's own. `route`
    /// is authoritative; an unknown one falls back to the kind's default.
    private func openNudge(_ n: HomeNudge) {
        let route = Self.nudgeRoutes.contains(n.route) ? n.route : Self.defaultNudgeRoute(forKind: n.kind)
        switch route {
        case "devotional":
            path.append(GrowDestination.devotional)
        case "quiz":
            if let m = n.params?.moduleId, !m.isEmpty { tabs.openPathway(.quiz(m)) } else { tabs.selected = .pathway }
        case "level_exam":
            if let l = n.params?.levelNumber { tabs.openPathway(.exam(l)) } else { tabs.selected = .pathway }
        case "letter":
            openLetter(id: n.params?.letterId)
        case "cell":
            path.append(AppRoute.cell)
        case "plan":
            if let id = n.params?.planId, let row = vm.plans.first(where: { $0.planId == id }) {
                tabs.openPlans(.plan(row))
            } else {
                tabs.openPlans(.catalogue)
            }
        case "reading_invite":
            if let t = n.params?.token, !t.isEmpty { tabs.openReadingInvite(t) } else { tabs.openPlans(.readWithFriendHub) }
        case "chat":
            if let c = n.params?.conversationId, !c.isEmpty { tabs.openConversation(c) } else { tabs.openYou(.chat) }
        case "partners":
            // A pledge due / behind (PARTNERS_PROGRAMME §3) — the pledge card
            // with its Pay now lives in the Partners portal.
            tabs.openPartners()
        default:
            break   // an unroutable nudge is a server bug — never a crash, never a wrong screen
        }
    }

    private static let nudgeRoutes: Set<String> =
        ["devotional", "quiz", "level_exam", "letter", "cell", "plan", "reading_invite", "chat", "partners"]

    private static func defaultNudgeRoute(forKind kind: String) -> String {
        switch kind {
        case "reflection_due":   return "devotional"
        case "quiz_in_progress": return "quiz"
        case "level_review":     return "level_exam"
        case "letter_unread":    return "letter"
        case "cell_gathering":   return "cell"
        case "plan_day_due":     return "plan"
        case "reading_invite":   return "reading_invite"
        case "chat_unread":      return "chat"
        default:                 return ""
        }
    }

    /// Opens a Sunday Letter the way the knock does (the `openedLetter`
    /// sheet): the one already on Home when it matches, else the exact
    /// letter from the archive, else the latest.
    private func openLetter(id: String?) {
        if let cur = vm.letter, id == nil || id == cur.letterId {
            openedLetter = cur
            return
        }
        Task {
            if let id, let lt = (try? await MemberAPI.letters())?.first(where: { $0.letterId == id }) {
                openedLetter = lt
                return
            }
            if let lt = (try? await MemberAPI.latestLetter()) ?? nil {
                vm.letter = lt
                openedLetter = lt
            }
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

    // MARK: YOUR WEEK (EXPERIENCE.md §6.1) — one row per pillar

    /// The five rows from what Home already loaded; HomeWeek decides the
    /// words (and each row's "none" form when its data didn't come).
    private var weekRows: [HomeWeekRow] {
        HomeWeek.rows(journey: vm.journey, enrolledLevel: auth.me?.enrollment?.currentLevel, plans: vm.plans,
                      calendar: vm.events, homeEvents: vm.homeEvents, rsvps: vm.rsvps,
                      partnership: vm.partnership, schedules: vm.schedules,
                      railsLine: GivingMethods.homeGiveLine(vm.givingMethods), cell: vm.cell,
                      cellAskedAt: vm.cellAskedAt,
                      planSealedHere: PlanDayLog.sealedToday())
    }

    /// A row lands where its pillar lives (the TabRouter contract): the
    /// journey's step inside Pathway, the plan's day inside Plans, the
    /// gathering inside Events, the pledge or the gift on Give, the cell page
    /// here, Community on You.
    private func openWeek(_ row: HomeWeekRow) {
        switch row.destination {
        case .journey(let d):
            if let d { tabs.openPathway(d.route) } else { tabs.selected = .pathway }
        case .planDay(let p): tabs.openPlans(.planDay(p))
        case .plans: tabs.openPlans(.catalogue)
        case .event(let occ): tabs.openEvent(occ)
        case .events: tabs.openEvents()
        case .pledge(let id): tabs.openPledge(id)
        case .schedule(let id): tabs.openGive(link: .schedule(scheduleId: id))
        case .partners: tabs.openPartners()
        case .give: tabs.openGive()
        case .cell: path.append(AppRoute.cell)
        case .cellConnect: path.append(AppRoute.cellConnect)
        case .community: tabs.openYou(.chat)
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
                            Text("❤️").font(.emoji(15))
                            Text("\(love)").font(.inter(11, .bold)).foregroundStyle(liked ? Nuru.danger : Nuru.ink600)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(liked ? Color(hex: 0xFEE2E2) : Nuru.white, in: Capsule())
                        .overlay(Capsule().stroke(liked ? Nuru.danger.opacity(0.35) : Nuru.border, lineWidth: 1))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: love)
                    }.buttonStyle(.pressable)
                    ForEach(videoReactionEmojis, id: \.self) { emoji in
                        let count = v.reactions?.first { $0.emoji == emoji }?.count ?? 0
                        let mine = v.reactions?.first { $0.emoji == emoji }?.mine ?? false
                        Button { Haptics.love(); Task { await vm.toggleVideoReaction(emoji) } } label: {
                            HStack(spacing: 4) {
                                Text(emoji).font(.emoji(15))
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
                            Icon(.share2, size: 14, color: Nuru.ink600)
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
                        Text(durationLabel(d)).font(.inter(11, .semibold)).foregroundStyle(.white)
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
                    Icon(.bookOpen, size: 14, color: Nuru.goldChipText)
                    Text("VERSE FOR TODAY").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldChipText)
                    Spacer(minLength: 0)
                    Text((vm.verse?.version ?? "WEB").uppercased())
                        .font(.inter(11, .bold)).kerning(1).foregroundStyle(HomeFig.navy)
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
                        .font(.fraunces(14).italic()).foregroundStyle(Nuru.ink)
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
                    Icon(.sparkles, size: 14, color: Nuru.goldChipText)
                    Text("Chosen for your season — \(reason)")
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                        .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Nuru.gold.opacity(0.3), lineWidth: 1))
                .padding(.top, 8)
            }
            // A save that failed says why, above the buttons (§4, §7.4 #2).
            if let line = vm.verseSaveLine {
                Text(line).font(.nCardMeta).foregroundStyle(Nuru.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Nuru.S.md)
            }
            // One row (Figma): reactions left, Save + Share pushed right — or,
            // when they don't fit, two rows, so no label is ever cut ("Shar/e",
            // the walk's E15; §8.1 rule 9).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 5) {
                    verseReactionChips
                    Spacer(minLength: 4)
                    verseSaveShare
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 5) { verseReactionChips }
                    HStack(spacing: 8) { verseSaveShare }
                }
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

    @ViewBuilder private var verseReactionChips: some View {
        ForEach(verseReactionEmojis, id: \.self) { emoji in
            let count = vm.reactions?.counts[emoji] ?? 0
            let mine = vm.reactions?.mine == emoji
            Button { Haptics.love(); Task { await vm.reactVerse(emoji) } } label: {
                HStack(spacing: 3) {
                    Text(emoji).font(.emoji(14))
                    if count > 0 {
                        Text("\(count)").font(.inter(11, .bold)).foregroundStyle(mine ? Nuru.goldChipText : Nuru.ink600)
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
    }

    @ViewBuilder private var verseSaveShare: some View {
        Button {
            Task { await vm.saveVerse() }
        } label: {
            pill(icon: .heart, label: vm.verseSaved ? "Saved" : "Save", tint: vm.verseSaved ? Nuru.gold : HomeFig.navy)
                .animation(.easeInOut(duration: 0.2), value: vm.verseSaved)
        }.buttonStyle(.pressable)
        Button { Haptics.tap(); shareVerseTapped() } label: {
            pill(icon: .share2, label: "Share", tint: HomeFig.navy)
        }.buttonStyle(.pressable)
    }

    private func pill(icon: Lucide, label: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Icon(icon, size: 14, color: tint)
            Text(label).font(.inter(11, .semibold)).foregroundStyle(tint)
        }
        .lineLimit(1)
        .fixedSize()
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
            Icon(.chevronRight, size: 14, color: Nuru.goldChipText)
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
            // Gold-tinted praying pill (Figma) — only once someone has prayed
            // or replied: no zero counts (§7.4 #9).
            if let counts = ZeroCounts.prayerLine(praying: post.prayCount, replies: post.commentCount ?? 0) {
                HStack(spacing: 5) {
                    Icon(.handHeart, size: 14, color: Nuru.goldChipText)
                    Text(counts)
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Nuru.gold.opacity(0.10), in: Capsule())
                .padding(.top, Nuru.S.md)
            }
            if inPager { Spacer(minLength: 0) }   // top-align short posts in the pager
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 9 — Featured announcement

    // MARK: 9 — Featured carousel (owner's revision, 2026-08-24)
    //
    // One sliding rail for what the portal has marked or scheduled: the
    // featured announcement and the next few events. Auto-advances gently; a
    // swipe is always respected. "View all" opens the full events list (You ▸
    // Events), per the owner's spec. The featured gathering is NOT a page here
    // (EXPERIENCE.md §7.2 #9): it has its own card further down Home, and the
    // carousel showed it beside that card — never twice on one screen.

    private enum FeaturedPage: Identifiable {
        case announcement(FeaturedAnnouncement)
        case occurrence(HomeEventRow)
        var id: String {
            switch self {
            case .announcement(let a): return "ann-" + a.announcementId
            case .occurrence(let o): return "occ-" + o.occurrenceId
            }
        }
    }

    private var featuredPages: [FeaturedPage] {
        var pages: [FeaturedPage] = []
        if let a = vm.featuredAnnouncement { pages.append(.announcement(a)) }
        let shownFeatured = vm.featuredEvent.flatMap { $0.nextStart() == nil ? nil : $0.seriesId }
        let events = HomeFeatured.carouselEvents(vm.homeEvents, featuredSeriesId: shownFeatured,
                                                 onNowOccurrenceId: liveNowInfo?.occ.occurrenceId)
        pages += events.map { .occurrence($0) }
        return pages
    }

    private var featuredCarousel: some View {
        let pages = featuredPages
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FEATURED").font(.inter(11, .bold)).kerning(1.98).foregroundStyle(Nuru.goldChipText)
                Spacer()
                Button { Haptics.selection(); tabs.openEvents() } label: {
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
                                 meta: a.sentAt.flatMap(NuruDates.parse).map { NuruDates.day($0) }, cta: "Read more")
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
                Text(kicker).font(.inter(11, .bold)).kerning(1.3).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.45), in: Capsule())
                    .padding(10)
            }
            VStack(alignment: .leading, spacing: 0) {
                // A title wraps to two lines (rule 9; the walk's "Experie…");
                // the body yields its second line when the title needs it.
                Text(title).font(.nCardTitle).foregroundStyle(HomeFig.navy)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(body).font(.nCardBody).foregroundStyle(HomeFig.metaGray).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    .layoutPriority(-1)
                Spacer(minLength: 0)
                HStack {
                    if let meta { Text(meta).font(.nCardMeta).foregroundStyle(HomeFig.faintGray) }
                    Spacer()
                    HStack(spacing: 3) {
                        Text(cta).font(.inter(12, .semibold)).foregroundStyle(Nuru.gold)
                        Icon(.chevronRight, size: 14, color: Nuru.gold)
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


    // MARK: 11 — Today's rhythm

    private var rhythmCard: some View {
        let complete = vm.rhythm.doneCount == 3
        // The one streak (§9.2 #3), counted as Plans counts it: today counts
        // once anything of today's rhythm is done. It read "Start today"
        // beside a done Word, while Plans said "1-day streak". Named here
        // alone on Home (the header pill no longer repeats it).
        let active = vm.rhythm.doneCount > 0
        let days = StreakWords.days(vm.streak, activeToday: active)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                // A card title (§8.1 rule 3): Fraunces 18.
                Text(complete ? "Today's rhythm complete 🎉" : "Today's rhythm")
                    .font(.nCardTitle).foregroundStyle(HomeFig.navy)
                Spacer()
                if days > 0 {
                    HStack(spacing: 4) {
                        Icon(.flame, size: 14, color: Nuru.goldChipText)
                        Text(StreakWords.title(days))
                            .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: days)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Nuru.goldChipBg, in: Capsule())
                }
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
            // The streak's week — today fills once today counts.
            HomeWeekChain(streakDays: days, todayDone: active)
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
                Icon(done ? .check : .clock, size: 14, color: done ? Nuru.white : Nuru.goldLo)
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
                Text("Your progress").font(.nCardTitle).foregroundStyle(HomeFig.navy)   // a card title (§8.1 rule 3)
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
                        Text("/100").font(.inter(11, .semibold)).foregroundStyle(HomeFig.faintGray)
                    }
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 1) {
                    Text("OVERALL GROWTH").font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.gold)
                    Text(s.overall.band).font(.nCardTitle).foregroundStyle(HomeFig.navy)
                    if let t = s.trend {
                        HStack(spacing: 4) {
                            Image(systemName: t.isDown ? "arrow.down.right" : t.isUp ? "arrow.up.right" : "minus")
                                .font(.symbol(10, weight: .bold))
                                .foregroundStyle(t.isDown ? Nuru.warning : t.isUp ? Nuru.success : HomeFig.metaGray)
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
                // Every bar is progress — gold (§8.1 rule 1; Word was blue,
                // Attendance green).
                scoreBar("Word", s.word.score, Nuru.gold, delta: s.trend?.domains?["word"])
                scoreBar("Prayer", s.prayer.score, Nuru.gold, delta: s.trend?.domains?["prayer"])
                scoreBar("Curriculum", s.curriculum.score, Nuru.gold, delta: s.trend?.domains?["curriculum"])
                scoreBar("Attendance", s.attendance.score, Nuru.gold, delta: s.trend?.domains?["attendance"])
            }
            .padding(.top, Nuru.S.base)
            if let j = vm.journey {
                // The journey's next step in one line ("3 of 10 modules in
                // Level 2", "Take the Level 1 exam") — never "0 modules left".
                let line = j.progressLine
                HStack(spacing: Nuru.S.sm) {
                    Icon(.target, size: 18, color: Nuru.goldChipText)
                        .frame(width: 30, height: 30)
                        .background(Nuru.goldChipBg, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    // The next step is a thing: the content row title, Fraunces
                    // 15 (§8.1 rule 3), the rest of the line in body type.
                    (Text(line.bold).font(.nRowTitle).foregroundStyle(Nuru.ink)
                     + Text(line.rest).font(.nCardBody).foregroundStyle(Nuru.muted))
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
                    Image(systemName: d < 0 ? "arrow.down" : "arrow.up").font(.symbol(8, weight: .bold))
                    Text("\(abs(d))").font(.inter(11, .bold))
                }
                .foregroundStyle(d < 0 ? Nuru.warning : Nuru.success)
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
            // Only for a discipler the server names (Cycle 4, B1): "Meet your
            // discipler" opened onto "No discipler yet" for members with none.
            if let mentor = disciplers.mentor {
            NavigationLink(value: AppRoute.mentor) {
                HStack(spacing: Nuru.S.md) {
                    Avatar(url: mentor.avatarUrl, name: mentor.fullName, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("YOUR DISCIPLER").font(.nCardKicker).kerning(1.4).foregroundStyle(HomeFig.eyebrow)
                        Text(mentor.fullName.isEmpty ? "Your discipler" : mentor.fullName)
                            .font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Icon(.chevronRight, size: 18, color: HomeFig.faintGray)
                }
                .padding(Nuru.S.md)
                .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.gold.opacity(0.2), lineWidth: 1))
            }.buttonStyle(.pressable)
            } else if disciplers.known {
                // With none, it's said once, here (§9.2 #8) — nothing to tap,
                // no door onto an empty page. Only once the server has
                // answered: never a fact before it is true.
                HStack(spacing: Nuru.S.md) {
                    Icon(.heartHandshake, size: 18, color: Nuru.navy)
                        .frame(width: 36, height: 36)
                        .background(Color(hex: Nuru.tileTint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    Text(DisciplerStore.noneLine)
                        .font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(Nuru.S.md)
                .background(Nuru.verseBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.gold.opacity(0.2), lineWidth: 1))
                .accessibilityElement(children: .combine)
            }
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
            NavigationLink(value: g) { growTileView(t) }
        } else if let c = t.dest as? CommunityRoute {
            NavigationLink(value: c) { growTileView(t) }
        } else {
            growTileView(t)   // unreachable with the current tile set
        }
    }

    private func growTileView(_ t: GrowTile) -> some View {
        HStack(spacing: 10) {
            Icon(t.icon, size: 18, color: Color(hex: t.fg))
                .frame(width: 36, height: 36)
                .background(Color(hex: t.tint), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            // Words wrap to two lines, never cut (§8.1 rule 9; the walk's E15:
            // "Hide His W…", "My Prayer R…", "Discover your…").
            VStack(alignment: .leading, spacing: 0) {
                Text(t.label).font(.inter(13, .semibold)).foregroundStyle(HomeFig.navy)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Text(t.sub).font(.nCardMeta).foregroundStyle(HomeFig.metaGray)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .padding(Nuru.S.md)
        .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    // MARK: 15 — Featured gathering (the family)

    // The ONE admin-featured event (portal "feature on homepage" toggle) —
    // GET /home/featured-event was declared but rendered by no client until now.
    private func featuredGatheringCard(_ fe: FeaturedEvent, next: Date) -> some View {
        Button {
            Haptics.selection(); tabs.openEvents()
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
                    Text([NuruDates.dayTime(next), fe.location].compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: "  ·  "))
                        .font(.inter(11, .semibold)).foregroundStyle(Nuru.goldChipText)
                }
                .padding(Nuru.S.base)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.pressableSubtle)
    }

    private func eventKicker(_ startAt: String) -> String {
        guard let d = parseISO(startAt) else { return "" }
        let cal = Calendar.current
        let day: String
        if cal.isDateInToday(d) { day = "Today" }
        else if cal.isDateInTomorrow(d) { day = "Tomorrow" }
        else { day = NuruDates.day(d) }
        return "\(day) · \(NuruDates.time(d))"
    }

    // MARK: 16 — Encouragement ("one reflection away" / "beautifully done")

    private var oneReflectionBanner: some View {
        HomeEncouragementCard(
            firstName: firstName,
            streak: vm.streak,
            rhythmDone: vm.rhythm.doneCount,
            wordDone: vm.rhythm.word,
            prayerDone: vm.rhythm.prayer,
            // Modules still to walk — only while the member is walking them
            // (the journey's learning stage); an exam left is not "a module".
            modulesLeft: vm.journey.flatMap { $0.stage == .learning ? max(0, $0.totalModules - $0.completedModules) : nil },
            levelNumber: vm.journey?.levelNumber,
            cellPrayerCount: vm.prayerPosts.count
        )
    }

    // MARK: 18 — Support God's work (give panel — centered ceremony layout)

    private var giveBanner: some View {
        HomeGiveCard(railsLine: GivingMethods.homeGiveLine(vm.givingMethods)) { tabs.openGive() }
    }

    // MARK: derived / helpers

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
    /// On the church's clock — the one the liturgy card keeps — so the two
    /// say the same part of the day (§9.3 rule 3): Ben read "Good afternoon"
    /// over an "EVENING" card at 16:32, and "Good morning" over "NIGHT" after
    /// midnight. Android's HomeGreeting, the same bands.
    private var greeting: String {
        HomeHeaderWords.timeGreeting(hour: ChurchClock.hour(), sunday: ChurchClock.isSunday())
    }
    private func todayKicker() -> String {
        // The one date shape (§8.1 rule 8), and no "EAT" — it is the phone's
        // own day, wherever the member is.
        if isSunday { return "THE LORD'S DAY · \(NuruDates.day(Date()).uppercased())" }
        return NuruDates.day(Date()).uppercased()
    }
    /// The header breathes with the day — dawn rose-gold, plain daylight cream,
    /// a deeper golden hour, and a quieter dusk. Same palette family as the
    /// Figma header, just tilted by the hour; Sundays glow a touch warmer.
    /// The header's light by the same part of the day (§9.3 rule 3).
    private var headerPalette: (top: Color, bottom: Color, glow: Double) {
        let base: (UInt32, UInt32, Double)
        switch ChurchClock.part() {
        case .morning: base = (0xF9F1E7, 0xF3E3CC, 0.34)   // dawn — rose-gold
        case .midday:  base = (0xF6F4EF, 0xEFE8DA, 0.27)   // daylight — the Figma cream
        case .evening: base = (0xF7EFDD, 0xEEDFC2, 0.40)   // golden hour
        case .night:   base = (0xF1EEE8, 0xE7E1D4, 0.20)   // dusk into night — quiet
        }
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
/// verse → video → letter → the week.
private struct HomeFeedSkeleton: View {
    var body: some View {
        VStack(spacing: Nuru.S.base) {
            ghost(height: 240)
            ghost(height: 190)
            ghost(height: 72)
            ghost(height: 290)
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

// MARK: - The featured carousel's events (EXPERIENCE.md §7.2 #9)

/// Never twice on one screen: the carousel's upcoming events skip any that has
/// its own card on Home — the featured gathering's series (its card stands
/// below the carousel; the carousel used to show it again beside it) and the
/// gathering happening now (the live-now card). Up to three, in the server's
/// order. Pure — pinned by tests.
enum HomeFeatured {
    /// One card per series, at its next date (the walk's E10: "Welcome to
    /// Ablaze" three times — 25 Oct, 25 Nov, 25 Dec; §7.2 #9, never twice on
    /// one screen). Rows arrive soonest first, so the first of a series is its
    /// next meeting. A row without a series stands for itself.
    static func carouselEvents(_ rows: [HomeEventRow], featuredSeriesId: String?,
                               onNowOccurrenceId: String?) -> [HomeEventRow] {
        let featured = featuredSeriesId.flatMap { $0.isEmpty ? nil : $0 }
        var seen = Set<String>()
        return Array(rows.filter { row in
            guard !(featured != nil && row.seriesId == featured), row.occurrenceId != onNowOccurrenceId else { return false }
            return seen.insert(row.seriesId.isEmpty ? "occ:" + row.occurrenceId : row.seriesId).inserted
        }.prefix(3))
    }
}


/// When Home refreshes in place (the walk's B5; §7.1 rule 5: a refresh
/// updates in place). Pure, so the tests pin it.
enum HomeRefresh {
    static let minimumGap: TimeInterval = 30
    static func should(loading: Bool, loaded: Bool, online: Bool?, last: Date, now: Date = Date()) -> Bool {
        loaded && !loading && online != false && now.timeIntervalSince(last) >= minimumGap
    }
}

/// What Home's header says before it knows (the Android walk's A3: a fact
/// shown while loading is a fact made up). No name until the profile names
/// the member — "Good evening." not "Good evening, Friend." — and no growth
/// ring until a score has come back above zero.
/// The church's clock (Nairobi) — the one the liturgy card is chosen by
/// (the server's partOf): morning from 4, midday from 11, evening from 16,
/// night from 21 until 4. Home's greeting, its sky and its light read it, so
/// the greeting, the liturgy card and the header say the same part of the
/// day (EXPERIENCE.md §9.3 rule 3).
enum ChurchClock {
    enum Part: Equatable { case morning, midday, evening, night }

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = GiveCalendar.nairobi
        return cal
    }
    static func hour(_ now: Date = Date()) -> Int { calendar.component(.hour, from: now) }
    static func isSunday(_ now: Date = Date()) -> Bool { calendar.component(.weekday, from: now) == 1 }
    static func part(_ now: Date = Date()) -> Part { part(hour: hour(now)) }
    static func part(hour h: Int) -> Part {
        switch h {
        case 4..<11: return .morning
        case 11..<16: return .midday
        case 16..<21: return .evening
        default: return .night
        }
    }
}

enum HomeHeaderWords {
    /// "Happy Lord's Day" on a Sunday; otherwise by the church's hour, in the
    /// liturgy's bands: "Good afternoon" ends at 16, when the card turns to
    /// EVENING; "Rest well" from 21 until 4, when it is NIGHT.
    static func timeGreeting(hour h: Int, sunday: Bool) -> String {
        if sunday { return "Happy Lord's Day" }
        switch h {
        case 0..<4: return "Rest well"
        case 4..<12: return "Good morning"
        case 12..<16: return "Good afternoon"
        case 16..<21: return "Good evening"
        default: return "Rest well"
        }
    }

    static func greeting(_ greeting: String, fullName: String?) -> String {
        guard let first = fullName?.split(separator: " ").first, !first.isEmpty else { return "\(greeting)." }
        return "\(greeting), \(first)."
    }
    static func showsScore(_ score: Int?) -> Bool { (score ?? 0) > 0 }
}
