// Module (lesson) — the native port of the Figma ModuleLearn content screen,
// rebuilt as an immersive, paged, engagement-tracked reader. Cream canvas under
// a parchment-gradient header (back · "LEVEL n · MODULE m" overline · serif
// title · meta row [read · sections · Watch · Listen] · a tappable section index
// · Read/Reflect/Watch/Listen actions), then the lesson: a real inline video card
// and/or a light audio narration card (each only when that medium exists), a lead
// paragraph, the section's Markdown body (headings render as headings), a
// gold-edged scripture pull-quote, and an inline reflection card that submits
// through completeModule.
//
// A SECTION is ONE author-defined content page: the portal splits the lesson into
// `content_pages` at author-inserted breaks, and each entry is one section (the
// default is a single section = the whole lesson). ONE section renders at a time
// behind the pager + horizontal swipes; the read-completion gate then requires
// reaching the LAST section's end. A 3pt gold bar at the very top
// tracks scroll progress across the whole module, reading/video seconds are
// heartbeat-POSTed to /modules/{id}/engagement (deltas, ≤600s each, fire-and-
// forget), and the reader goes immersive: 7s after open the header, pager, gate
// and app tab bar fade away (tabs.chromeHidden — the mechanism RootView already
// animates); any tap brings them back and re-arms a 3-minute hide. A bottom
// gate keeps the CTA locked until the reader nears the end, then it becomes
// "Start the quiz" or "Mark complete". The server enforces gating + scoring;
// the client only reflects state (§1.9/§3.7).
import SwiftUI
import AVFoundation

@MainActor
final class ModuleViewModel: ObservableObject {
    @Published var detail: ModuleDetail?
    @Published var loading = true
    @Published var error: String?
    @Published var completing = false
    @Published var completed = false
    @Published var completionError: String?

    // Light audio player — the lesson's narration (detail.audioUrl). Published so
    // the Listen control + its thin progress line reflect real playback state.
    @Published var audioPlaying = false
    @Published var audioProgress: Double = 0   // 0…1 of the track (0 until known)
    // Completion signals for the quiz gate: the video embed watched-seconds and
    // the furthest point reached in the audio. The quiz can't start until the
    // read, the watch (≥90%), the listen (≥90%) AND the reflection are satisfied.
    @Published var videoWatchedSec: Double = 0
    @Published var audioMaxProgress: Double = 0

    // Reflection is now a REQUIRED content step BEFORE the quiz — a standalone
    // POST /modules/{id}/reflection, NOT completion. `reflectDone` gates the quiz;
    // `savedReflection` pre-fills the card on open (fetched via GET).
    @Published var reflectDone = false
    @Published var savedReflection: String?
    @Published var submittingReflection = false
    @Published var reflectionError: String?

    private let moduleId: String
    init(moduleId: String) { self.moduleId = moduleId }

    func load() async {
        loading = true; error = nil
        do { detail = try await MemberAPI.module(moduleId) }
        catch { self.error = (error as? APIError)?.errorDescription ?? "Couldn't load this lesson." }
        loading = false
    }

    /// Marks the module complete server-side. Success/failure is surfaced (the
    /// old `try?` swallowed network errors silently, leaving a dead button).
    func markComplete(reflection: String? = nil) async {
        completing = true; completionError = nil
        defer { completing = false }
        let text = (reflection?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        do {
            let res = try await MemberAPI.completeModule(moduleId, reflectionText: text)
            completed = res.isCompleted || res.duplicate
            if completed { Haptics.success() }   // the moment the server confirms
        } catch {
            completionError = (error as? APIError)?.errorDescription ?? "Couldn't save your progress. Please try again."
            Haptics.error()
        }
    }

    // MARK: Engagement (reading/video seconds + resume page — server accumulates)
    //
    // The view feeds this tracker pure OBSERVED signals: reading runs only while
    // the reader is on screen with the scene active; video runs only while the
    // embed is actually open on screen; audio runs only while the narration is
    // actually playing. A 30s heartbeat (plus a flush on disappear/background)
    // drains the accumulators into fire-and-forget POSTs.

    /// Deinit-safe chrome restore: if the reader is ever torn down without a
    /// final onDisappear, the app tab bar must never stay hidden.
    weak var chromeRouter: TabRouter?

    private var readingSince: Date?
    private var videoSince: Date?
    private var audioSince: Date?
    private var pendingReading: TimeInterval = 0
    private var pendingVideo: TimeInterval = 0
    private var pendingAudio: TimeInterval = 0
    private var lastSentPage: Int?       // 1-based page the server already knows
    private var currentPageNumber: Int?  // 1-based page awaiting report
    private var heartbeat: Task<Void, Never>?

    // AVPlayer for the lesson narration + its periodic time observer. Owned here
    // so playback and the counted seconds survive page turns / immersion toggles.
    private var audioPlayer: AVPlayer?
    private var audioObserver: Any?
    private var audioEndObserver: NSObjectProtocol?

    deinit {
        heartbeat?.cancel()
        videoTick?.cancel()
        if let audioObserver { audioPlayer?.removeTimeObserver(audioObserver) }
        if let audioEndObserver { NotificationCenter.default.removeObserver(audioEndObserver) }
        audioPlayer?.pause()
        let router = chromeRouter
        Task { @MainActor in router?.chromeHidden = false }
    }

    /// GET the accumulated totals — silent (`try?`): resume is a nicety, never a blocker.
    func fetchEngagement() async -> ModuleEngagement? {
        try? await MemberAPI.moduleEngagement(moduleId)
    }

    // MARK: Reflection step (standalone, required BEFORE the quiz)

    /// Pre-fill the reflection card and mark the Reflect step done if the member
    /// already wrote one. Silent (`try?`) — a missing/failed fetch just leaves the
    /// step not-yet-done; it never blocks the reader.
    func loadReflection() async {
        // `try?` on an Optional-returning call yields a double Optional — flatten it.
        let fetched = (try? await MemberAPI.moduleReflection(moduleId)) ?? nil
        guard let saved = fetched,
              !saved.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        savedReflection = saved.body
        reflectDone = true
    }

    /// Submit the standalone reflection (optimistic: the Reflect step lights up the
    /// moment the server confirms). This does NOT complete the module — the quiz /
    /// mark-complete path stays server-authoritative (§1.9).
    func submitReflection(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        submittingReflection = true; reflectionError = nil
        defer { submittingReflection = false }
        do {
            _ = try await MemberAPI.submitModuleReflection(moduleId, body: trimmed)
            savedReflection = trimmed
            reflectDone = true
            Haptics.success()
        } catch {
            reflectionError = (error as? APIError)?.errorDescription ?? "Couldn't save your reflection. Please try again."
            Haptics.error()
        }
    }

    /// Seed the page bookkeeping from the server's totals so an unchanged page
    /// is never re-reported.
    func baselinePage(_ pageNumber: Int) {
        lastSentPage = pageNumber
        currentPageNumber = pageNumber
    }

    /// The member turned to a page (1-based); the next heartbeat reports it.
    func pageChanged(to pageNumber: Int) { currentPageNumber = pageNumber }

    func beginReading() { if readingSince == nil { readingSince = Date() } }
    func pauseReading() {
        if let s = readingSince { pendingReading += Date().timeIntervalSince(s) }
        readingSince = nil
    }

    /// "Open" == the video embed is mounted and visible. The embed is a
    /// WKWebView (InlineVideoPlayer) with no play/pause callbacks, so "embed
    /// open on screen" is the best signal we can actually observe — we count
    /// that as video time and nothing more.
    private var videoTick: Task<Void, Never>?
    func setVideoOpen(_ open: Bool) {
        if open {
            if videoSince == nil { videoSince = Date() }
            // Grow the watched-seconds live (1s cadence) so the quiz gate can
            // clear the ≥90% bar the moment the video has genuinely been seen.
            videoTick?.cancel()
            videoTick = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard let self, !Task.isCancelled else { return }
                    self.videoWatchedSec += 1
                }
            }
        } else {
            if let s = videoSince { pendingVideo += Date().timeIntervalSince(s) }
            videoSince = nil
            videoTick?.cancel(); videoTick = nil
        }
    }

    // MARK: Audio narration (light AVPlayer — play/pause + counted seconds)
    //
    // Unlike the video embed (a WKWebView with no callbacks), AVPlayer gives us
    // real play/pause, so audio time is counted only while it's actually playing.
    // The seconds ride the SAME engagement heartbeat as reading/video — no new
    // contract, just the existing `audioSeconds` field.

    /// True once the module carries a usable audio narration URL.
    var hasAudio: Bool {
        guard let raw = detail?.audioUrl?.trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !raw.isEmpty && URL(string: raw) != nil
    }

    func toggleAudio() { audioPlaying ? pauseAudio() : playAudio() }

    /// Start (or resume) the narration. Lazily builds the AVPlayer on first play,
    /// wiring a periodic observer that drives the progress line and a
    /// play-to-end handler that resets to the start.
    func playAudio() {
        guard let raw = detail?.audioUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty, let url = URL(string: raw) else { return }
        // Narration should be heard even with the ring switch on silent.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        if audioPlayer == nil {
            let player = AVPlayer(url: url)
            audioPlayer = player
            let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
            audioObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                Task { @MainActor [weak self] in
                    guard let self, let dur = self.audioPlayer?.currentItem?.duration.seconds,
                          dur.isFinite, dur > 0 else { return }
                    self.audioProgress = min(1, max(0, time.seconds / dur))
                    self.audioMaxProgress = max(self.audioMaxProgress, self.audioProgress)
                }
            }
            audioEndObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main) { [weak self] _ in
                    guard let self else { return }
                    Task { @MainActor in
                        self.audioPlaying = false
                        self.audioProgress = 0
                        self.player_seekToStart()
                        self.pauseAudioClock()
                    }
                }
        }
        audioPlayer?.play()
        audioPlaying = true
        if audioSince == nil { audioSince = Date() }
    }

    func pauseAudio() {
        audioPlayer?.pause()
        audioPlaying = false
        pauseAudioClock()
    }

    /// Drain any in-flight audio interval into the pending accumulator and stop
    /// the clock — called on pause, on end, and when the reader leaves.
    private func pauseAudioClock() {
        if let s = audioSince { pendingAudio += Date().timeIntervalSince(s) }
        audioSince = nil
    }

    /// The reader left the screen / backgrounded: stop hearing (and counting)
    /// audio, but keep the player around so returning can resume mid-track.
    func suspendAudioIfNeeded() {
        guard audioPlaying else { pauseAudioClock(); return }
        pauseAudio()
    }

    private func player_seekToStart() { audioPlayer?.seek(to: .zero) }

    func startHeartbeat() {
        guard heartbeat == nil else { return }
        heartbeat = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { break }
                self?.flushEngagement()
            }
        }
    }

    func stopHeartbeat() {
        heartbeat?.cancel()
        heartbeat = nil
    }

    /// Drain observed time (and a changed page) into ONE fire-and-forget POST.
    /// Deltas are wall-clock capped at 600s each per the wire contract; any
    /// excess carries to the next beat. Never blocks UI, never surfaces errors.
    func flushEngagement() {
        let now = Date()
        if let s = readingSince { pendingReading += now.timeIntervalSince(s); readingSince = now }
        if let s = videoSince { pendingVideo += now.timeIntervalSince(s); videoSince = now }
        if let s = audioSince { pendingAudio += now.timeIntervalSince(s); audioSince = now }
        let reading = min(Int(pendingReading), 600)
        let video = min(Int(pendingVideo), 600)
        let audio = min(Int(pendingAudio), 600)
        let page = currentPageNumber != lastSentPage ? currentPageNumber : nil
        guard reading > 0 || video > 0 || audio > 0 || page != nil else { return }
        pendingReading -= TimeInterval(reading)
        pendingVideo -= TimeInterval(video)
        pendingAudio -= TimeInterval(audio)
        if let page { lastSentPage = page }
        let id = moduleId
        Task.detached {
            try? await MemberAPI.reportModuleEngagement(id,
                                                        readingSeconds: reading > 0 ? reading : nil,
                                                        audioSeconds: audio > 0 ? audio : nil,
                                                        videoSeconds: video > 0 ? video : nil,
                                                        lastPage: page)
        }
    }

    /// AWAIT a final engagement report before starting the quiz, so the server's
    /// content gate sees the latest read/watch/listen seconds (the 30s heartbeat
    /// could otherwise lag the just-finished last chunk and wrongly block).
    func flushEngagementAwaiting() async {
        let now = Date()
        if let s = readingSince { pendingReading += now.timeIntervalSince(s); readingSince = now }
        if let s = videoSince { pendingVideo += now.timeIntervalSince(s); videoSince = now }
        if let s = audioSince { pendingAudio += now.timeIntervalSince(s); audioSince = now }
        let reading = min(Int(pendingReading), 600)
        let video = min(Int(pendingVideo), 600)
        let audio = min(Int(pendingAudio), 600)
        let page = currentPageNumber != lastSentPage ? currentPageNumber : nil
        guard reading > 0 || video > 0 || audio > 0 || page != nil else { return }
        pendingReading -= TimeInterval(reading)
        pendingVideo -= TimeInterval(video)
        pendingAudio -= TimeInterval(audio)
        if let page { lastSentPage = page }
        _ = try? await MemberAPI.reportModuleEngagement(moduleId,
                                                        readingSeconds: reading > 0 ? reading : nil,
                                                        audioSeconds: audio > 0 ? audio : nil,
                                                        videoSeconds: video > 0 ? video : nil,
                                                        lastPage: page)
    }
}

// Exact Figma palette (ModuleLearn.tsx) — module-internal (not `private`) so the
// Markdown renderer in LessonMarkdown.swift shares this exact palette.
enum ML {
    static let navy         = Color(hex: 0x0A1628)
    static let cream        = Color(hex: 0xF4F0E8)   // canvas
    static let surface      = Color(hex: 0xFBF8F1)   // inset tiles / scripture
    static let gold         = Color(hex: 0xC9A227)
    static let goldDeep     = Color(hex: 0xB6862F)   // gold gradient tail
    static let border       = Color(hex: 0x0A2540, alpha: 0.08)
    static let track        = Color(hex: 0x0A2540, alpha: 0.10)
    static let overline     = Color(hex: 0x9A7A2A)   // header overline
    static let kicker       = Color(hex: 0xA8861C)   // SECTION / scripture kickers
    static let secondary    = Color(hex: 0x59667C)
    static let lead         = Color(hex: 0x3A4A5F)   // intro paragraph
    static let bodyInk      = Color(hex: 0x1B2733)   // flowing body copy
    static let headerTop    = Color(hex: 0xF6F4EF)
    static let headerBottom = Color(hex: 0xEFE8DA)
    static let goldGradient = LinearGradient(colors: [gold, goldDeep],
                                             startPoint: .topLeading, endPoint: .bottomTrailing)
    static let reflectMinChars = 20   // Figma REFLECT_MIN_MOD
}

// MARK: - Gate step model (the incremental "N of M steps done")

/// One applicable content step. `fraction` (0…1) is the REAL progress toward it —
/// read scroll, watched-seconds vs 90%, audio playhead vs 0.9, or 0/1 for reflect;
/// it drives the partial fill of the in-progress step. `done` is fraction ≥ 1.
enum GateStepKind: String {
    case read, watch, listen, reflect
    var label: String {
        switch self {
        case .read:    return "Read"
        case .watch:   return "Watch"
        case .listen:  return "Listen"
        case .reflect: return "Reflect"
        }
    }
    var icon: Lucide {
        switch self {
        case .read:    return .bookOpen
        case .watch:   return .play
        case .listen:  return .audioLines
        case .reflect: return .quote
        }
    }
}

struct GateStep: Identifiable {
    let kind: GateStepKind
    let fraction: Double
    var id: String { kind.rawValue }
    var done: Bool { fraction >= 1 }
    var clamped: Double { min(1, max(0, fraction)) }
}

struct ModuleView: View {
    let moduleId: String
    @StateObject private var vm: ModuleViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var reflection: String = ""
    @State private var playingVideo = false      // real inline player started
    @State private var reachedEnd = false        // latched at the LAST page's end
    @State private var startingQuiz = false       // flushing engagement before the quiz
    @State private var quizTarget: String?        // pushes QuizView once the flush lands
    @State private var nextModuleTarget: String?  // the server-unlocked next module (post-quiz-pass)

    // Living curriculum — "hear it another way": the same lesson re-rendered by
    // Nuru (simple English / Kiswahili / as a story). Server-gated (§1.9).
    @State private var showExplainMenu = false
    @State private var explainTarget: ExplainTarget?
    // Finished modules fold the reflection to what was written; changing it is
    // an intentional act behind the "Revisit this module" door.
    @State private var editingReflection = false
    @State private var showRevisitDialog = false

    // Paged reading
    @State private var currentPage = 0           // 0-based page index
    @State private var pageFraction: Double = 0  // scroll progress within the page

    // Immersive chrome (header + pager + gate + app tab bar)
    @State private var chromeHidden = false
    @State private var chromeTask: Task<Void, Never>?
    @State private var viewOnScreen = false
    @State private var resumeNote: String?       // "Welcome back — …", fades away
    @State private var lastScrollOffset: CGFloat = 0   // to detect scroll-into-immersion
    @State private var didAutoImmerse = false          // one auto-hide per opening
    // Reading-pace guardrails — a gentle "slow down" when someone blows past the
    // text faster than anyone could read it (real scroll velocity, no camera).
    @State private var lastScrollAt: Date?
    @State private var fastScrollRun: CGFloat = 0      // accumulated blow-through distance
    @State private var lastNudgeAt: Date?
    @State private var showSlowDown = false

    init(moduleId: String) {
        self.moduleId = moduleId
        _vm = StateObject(wrappedValue: ModuleViewModel(moduleId: moduleId))
    }

    /// Height of the top safe-area inset (status-bar / Dynamic Island band) —
    /// RootView paints exactly this band in cream, so overlays dock just below
    /// it. Same fallback as RootView (59 = Dynamic Island).
    private static var safeAreaTop: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.top ?? 59
    }

    /// Bottom safe-area inset (home indicator band) — used to pad the immersive
    /// scroll so the last content clears the indicator when the gate is gone.
    private static var safeAreaBottom: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.windows.first(where: { $0.isKeyWindow })?.safeAreaInsets.bottom ?? 34
    }

    private var pageCountNow: Int { vm.detail.map { mlPages($0).count } ?? 1 }

    /// Whole-module reading progress: completed pages + the current page's
    /// scroll fraction, over the page count. Single page → plain scroll fraction.
    private var overallProgress: Double {
        let n = Double(max(pageCountNow, 1))
        return min(1, max(0, (Double(currentPage) + pageFraction) / n))
    }

    // MARK: - Content-completion gate (read + watch ≥90% + listen ≥90% + reflect)
    //
    // The gate is an INCREMENTAL "N of M steps done": the applicable steps are
    // Read (always) + Watch (only with a video) + Listen (only with audio) +
    // Reflect (always). Each carries a live fraction (0…1) so the bottom gate can
    // partially fill the in-progress step; the quiz/mark-complete unlocks ONLY when
    // every applicable step's fraction is 1 (server still re-checks, §1.9).

    /// Video satisfied when there's no video, or it's been watched ~90% (or,
    /// when no duration is set, genuinely opened for a spell).
    private var watchDone: Bool {
        guard let d = vm.detail, d.videoUrl != nil else { return true }
        if let dur = d.videoDurationSec, dur > 0 { return vm.videoWatchedSec >= Double(dur) * 0.9 }
        return vm.videoWatchedSec >= 20
    }
    /// Audio satisfied when there's no audio, or the playhead reached ~90%.
    private var listenDone: Bool { vm.hasAudio ? vm.audioMaxProgress >= 0.9 : true }

    /// Live read fraction — whole-module scroll progress, latched to 1 once the
    /// end sentinel has been reached (so a scroll-back doesn't un-fill Read).
    private var readFraction: Double { reachedEnd ? 1 : min(1, max(0, overallProgress)) }
    /// Live watch fraction — watched-seconds vs the 90% target (or the 20s floor).
    private var watchFraction: Double {
        guard let d = vm.detail, d.videoUrl != nil else { return 1 }
        let target = (d.videoDurationSec.map { Double($0) * 0.9 }).flatMap { $0 > 0 ? $0 : nil } ?? 20
        return min(1, max(0, vm.videoWatchedSec / target))
    }
    /// Live listen fraction — playhead vs the 0.9 target.
    private var listenFraction: Double { vm.hasAudio ? min(1, max(0, vm.audioMaxProgress / 0.9)) : 1 }

    /// The applicable steps, in fixed order, each with its live fraction. Watch is
    /// omitted with no video; Listen is omitted with no audio; Read + Reflect always
    /// show. This is the single source for the "N of M" chips + segmented bar.
    private var gateSteps: [GateStep] {
        var steps: [GateStep] = [GateStep(kind: .read, fraction: readFraction)]
        if let d = vm.detail, d.videoUrl != nil { steps.append(GateStep(kind: .watch, fraction: watchFraction)) }
        if vm.hasAudio { steps.append(GateStep(kind: .listen, fraction: listenFraction)) }
        steps.append(GateStep(kind: .reflect, fraction: vm.reflectDone ? 1 : 0))
        return steps
    }
    private var stepsDone: Int { gateSteps.filter(\.done).count }
    private var stepsTotal: Int { gateSteps.count }
    /// The quiz / mark-complete only unlocks when EVERY applicable step is done.
    private var contentComplete: Bool { reachedEnd && watchDone && listenDone && vm.reflectDone }
    /// The honest reason the gate is still locked — names the FIRST unmet step.
    private func gateLockReason(requiresQuiz: Bool) -> String {
        let tail = requiresQuiz ? "unlock the quiz" : "continue"
        if !reachedEnd     { return "Read to the end to \(tail)" }
        if !watchDone      { return "Finish the video to \(tail)" }
        if !listenDone     { return "Finish the audio to \(tail)" }
        if !vm.reflectDone { return "Add a reflection to \(tail)" }
        return ""
    }

    var body: some View {
        ZStack {
            ML.cream.ignoresSafeArea()
            if vm.loading && vm.detail == nil {
                lessonSkeleton
            } else if let d = vm.detail {
                loaded(d)
            } else {
                VStack(spacing: Nuru.S.md) {
                    Text(vm.error ?? "Couldn't load this lesson.")
                        .font(.inter(14)).foregroundStyle(ML.secondary).multilineTextAlignment(.center)
                    Button {
                        Haptics.tap()
                        Task { await vm.load() }
                    } label: {
                        Text("Try again").font(.inter(13, .semibold)).foregroundStyle(ML.navy)
                            .padding(.horizontal, 20).padding(.vertical, 10)
                            .background(ML.gold, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                }
                .padding(Nuru.S.screen)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .ignoresSafeArea(edges: .top)
        // Reading progress — orientation, not chrome: it survives immersion.
        // Pinned FLUSH to the physical top edge of the screen (the ZStack ignores
        // the top safe area, so `.top` is the true top). A 3pt hairline that
        // never crosses the title or any content.
        .overlay(alignment: .top) {
            if vm.detail != nil {
                NuruReadingBar(progress: overallProgress)
                    .ignoresSafeArea(edges: .top)
            }
        }
        // One-line "Welcome back — picking up on page N" that fades after a beat.
        .overlay(alignment: .top) {
            if let resumeNote {
                MLResumeNote(text: resumeNote)
                    .padding(.top, Self.safeAreaTop + 14)
            }
        }
        // Whisper-small page indicator while the reader is immersed.
        .overlay(alignment: .bottom) {
            if chromeHidden, pageCountNow > 1 {
                MLPageWhisper(page: currentPage + 1, count: pageCountNow)
                    .padding(.bottom, Self.safeAreaBottom + 8)
                    .transition(.opacity)
            }
        }
        // Floating "exit fullscreen" button while immersed — the always-there
        // handle to bring the header + tab bar back (the same toggle as the
        // hero's, just relocated since the hero is gone).
        .overlay(alignment: .topTrailing) {
            if chromeHidden, vm.detail != nil {
                MLImmerseButton(expanded: true, floating: true, action: toggleImmersion)
                    .padding(.trailing, 14)
                    .padding(.top, Self.safeAreaTop + 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        // The eye-pacer: a gold dot on the RIGHT rail whose position is tied to
        // your actual scroll — it moves as you scroll, stops when you stop, and
        // fills the rail behind it to show how far you've read.
        .overlay(alignment: .trailing) {
            if vm.detail != nil {
                // Bind the dot to `overallProgress` — the SAME whole-module signal
                // the top reading bar uses — so the dot and the bar move in lockstep.
                NuruPaceRail(progress: overallProgress)
                    .transition(.opacity)
            }
        }
        // Gentle "slow down and take in the Word" when the scroll blows past
        // the text faster than anyone could read it.
        .overlay(alignment: .top) {
            if showSlowDown {
                MLSlowDownNudge()
                    .padding(.top, chromeHidden ? Self.safeAreaTop + 12 : Self.safeAreaTop + 70)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .task {
            guard vm.detail == nil else { return }
            async let totals = vm.fetchEngagement()   // resume data, in parallel
            async let _reflection: Void = vm.loadReflection()   // pre-fill Reflect step
            await vm.load()
            await _reflection
            // Pre-fill the reflection card with the saved text (only if the member
            // hasn't started typing) so it reads as already-done on return.
            if reflection.isEmpty, let saved = vm.savedReflection { reflection = saved }
            applyResume(await totals)
        }
        .onAppear {
            viewOnScreen = true
            vm.chromeRouter = tabs      // deinit-safe tab-bar restore backstop
            vm.startHeartbeat()
            syncEngagementSignals()
        }
        .onDisappear {
            viewOnScreen = false
            syncEngagementSignals()     // stops the reading/video clocks
            vm.flushEngagement()        // final beat — fire-and-forget
            vm.stopHeartbeat()
            chromeTask?.cancel(); chromeTask = nil
            chromeHidden = false
            tabs.chromeHidden = false   // ALWAYS restore the app chrome
        }
        .onChange(of: scenePhase) { _, phase in
            syncEngagementSignals()
            if phase != .active { vm.flushEngagement() }   // keep the tail on background
        }
        // The quiz opens only after the engagement flush lands (so the server's
        // content gate sees the final read/watch/listen seconds). On a PASS the quiz
        // hands back the server-unlocked next module: pop the quiz and push it, so
        // the member flows straight into the next lesson (§1.9 — the id is the
        // server's; a nil just returns to this module).
        .navigationDestination(item: $quizTarget) { id in
            QuizView(moduleId: id, onPassAdvance: { nextId in
                quizTarget = nil          // pop the quiz
                if let nextId { nextModuleTarget = nextId }
            })
        }
        .navigationDestination(item: $nextModuleTarget) { ModuleView(moduleId: $0) }
        .confirmationDialog("Hear it another way", isPresented: $showExplainMenu, titleVisibility: .visible) {
            Button("In simple English") { explainTarget = ExplainTarget(style: "simple") }
            Button("Kwa Kiswahili") { explainTarget = ExplainTarget(style: "swahili") }
            Button("As a story") { explainTarget = ExplainTarget(style: "story") }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(item: $explainTarget) { t in
            ExplainSheet(moduleId: moduleId, style: t.style)
        }
        .confirmationDialog("You've completed this module", isPresented: $showRevisitDialog, titleVisibility: .visible) {
            Button("Edit my reflection") { Haptics.tap(); editingReflection = true }
            if vm.detail?.requiresQuiz == true {
                Button("Retake the quiz") {
                    Haptics.action()
                    quizTarget = moduleId
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It is sealed — but you can still revisit what you wrote or try the quiz again.")
        }
        .onChange(of: playingVideo) { _, _ in syncEngagementSignals() }
        .onChange(of: currentPage) { _, _ in syncEngagementSignals() }
        // A short beat after the server confirms, so the success haptic and the
        // button's confirmation register before the screen goes away.
        .onChange(of: vm.completed) { _, done in
            guard done else { return }
            Task {
                try? await Task.sleep(nanoseconds: 350_000_000)
                dismiss()
            }
        }
    }

    // MARK: - First-load skeleton (parchment header + text-line placeholders)

    private var lessonSkeleton: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                RoundedRectangle(cornerRadius: 5, style: .continuous).fill(ML.track).frame(width: 140, height: 10)
                RoundedRectangle(cornerRadius: 7, style: .continuous).fill(ML.track).frame(width: 230, height: 22)
                HStack(spacing: 8) {
                    Capsule().fill(ML.track).frame(width: 80, height: 22)
                    Capsule().fill(ML.track).frame(width: 90, height: 22)
                }
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, 110)
            .padding(.bottom, Nuru.S.screen)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(colors: [ML.headerTop, ML.headerBottom],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24, style: .continuous))
                    .ignoresSafeArea(edges: .top)
            )
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<6, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 4, style: .continuous).fill(ML.track)
                        .frame(maxWidth: .infinity).frame(height: 12)
                        .padding(.trailing, i % 3 == 2 ? 80 : 0)
                }
            }
            .padding(.horizontal, Nuru.S.screen)
            .padding(.top, Nuru.S.lg)
            Spacer()
        }
        .nuruShimmer()
        .accessibilityLabel("Loading this lesson")
    }

    // MARK: - Loaded layout (header + paged reader + pager + gate; all fade when immersed)

    private func loaded(_ d: ModuleDetail) -> some View {
        let pages = mlPages(d)
        let pageIndex = min(max(currentPage, 0), pages.count - 1)   // defensive clamp
        // A SECTION is ONE author-defined content page (contentPages entry) — NOT
        // a Markdown heading. Derive each page's title from its FIRST heading (or
        // "Section N"), and parse the heading-stripped BODY so the title never
        // renders twice. The server's page split is untouched — display-only.
        let titledAll = pages.map { pageTitleAndBody($0) }
        // Section titles for the hero's tappable index — one per page.
        let sectionTitles = titledAll.enumerated().map { sectionLabel($0.element.title, $0.offset) }
        // The section's body, rendered as normal Markdown — its headings stay
        // headings (they are NOT relabeled "SECTION n"). The page's title heading
        // was already stripped by pageTitleAndBody, so it never renders twice.
        let bodyBlocks = MLMarkdown.parse(titledAll[pageIndex].body)
        let pageTitle = sectionTitles[pageIndex]
        let video = mlVideo(d)
        return ScrollViewReader { proxy in
            VStack(spacing: 0) {
                if !chromeHidden {
                    MLHeader(levelNumber: d.levelNumber,
                             moduleNumber: d.moduleSequenceNumber,
                             title: d.title,
                             readMinutes: mlReadMinutes(pages),
                             sectionCount: pages.count,
                             sectionTitles: sectionTitles,
                             currentSection: pageIndex,
                             media: headerMedia(d),
                             onSelectSection: { goToPage($0, pageCount: pages.count) },
                             actions: headerActions(hasVideo: video != nil,
                                                    hasAudio: vm.hasAudio,
                                                    pageCount: pages.count, proxy: proxy),
                             onBack: { dismiss() },
                             onToggleImmersion: { toggleImmersion() },
                             onExplain: { Haptics.tap(); showExplainMenu = true },
                             finished: d.isFinished ? MLFinishedSummary(
                                 score: d.bestScore,
                                 when: d.finishedLine,
                                 canRetake: d.requiresQuiz,
                                 onRetake: {
                                     Haptics.action()
                                     quizTarget = d.moduleId
                                 }) : nil)
                        .transition(.opacity)
                }
                reader(d, pages: pages, bodyBlocks: bodyBlocks,
                       sectionTitle: pageTitle, video: video, pageIndex: pageIndex)
                if pages.count > 1 && !chromeHidden {
                    MLPagerBar(pageCount: pages.count, current: pageIndex) {
                        goToPage($0, pageCount: pages.count)
                    }
                    .transition(.opacity)
                }
                if !chromeHidden && !d.isFinished {
                    MLBottomGate(steps: gateSteps,
                                 complete: contentComplete,
                                 lockReason: gateLockReason(requiresQuiz: d.requiresQuiz),
                                 requiresQuiz: d.requiresQuiz,
                                 moduleId: d.moduleId,
                                 busy: vm.completing,
                                 error: vm.completionError,
                                 bottomInset: Nuru.tabBarSpace - 24,
                                 startingQuiz: startingQuiz,
                                 onStartQuiz: {
                                     guard !startingQuiz else { return }
                                     startingQuiz = true
                                     Task {
                                         await vm.flushEngagementAwaiting()   // server gets the latest first
                                         startingQuiz = false
                                         quizTarget = d.moduleId
                                     }
                                 }) {
                        Haptics.action()
                        Task { await vm.markComplete() }
                    }
                    .transition(.opacity)
                }
            }
            // The lesson is on screen: start the reading clock and arm the
            // slide into immersive reading (a scroll gets there sooner).
            .onAppear {
                syncEngagementSignals()
                if !didAutoImmerse { armChromeHide(after: 6) }
            }
        }
    }

    /// One page of the lesson in its own ScrollView. `.id(pageIndex)` recreates
    /// the scroll on every turn — position resets to top — and the `.opacity`
    /// transition crossfades old→new inside the ZStack, so turns feel instant
    /// but never snap.
    private func reader(_ d: ModuleDetail, pages: [String],
                        bodyBlocks: [MLBlock],
                        sectionTitle: String,
                        video: WelcomeVideo?, pageIndex: Int) -> some View {
        GeometryReader { viewport in
            ZStack {
                ScrollView(showsIndicators: false) {
                    lessonBody(d, bodyBlocks: bodyBlocks, sectionTitle: sectionTitle,
                               pageIndex: pageIndex, pageCount: pages.count,
                               video: pageIndex == 0 ? video : nil,
                               isFirstPage: pageIndex == 0,
                               isLastPage: pageIndex == pages.count - 1)
                        .id("top")
                        .padding(.horizontal, Nuru.S.screen)
                        .padding(.top, chromeHidden ? Self.safeAreaTop + 8 : Nuru.S.base)
                        // Clear the home indicator when immersive (no gate below);
                        // a smaller cushion when the gate sits beneath the scroll.
                        .padding(.bottom, chromeHidden ? Self.safeAreaBottom + 40 : Nuru.S.xl + 12)
                        .background(
                            // Scroll metrics for the top progress bar: content
                            // offset + height in the scroll's coordinate space.
                            GeometryReader { g in
                                Color.clear.preference(
                                    key: MLScrollMetricsKey.self,
                                    value: MLScrollMetrics(offset: -g.frame(in: .named("mlScroll")).minY,
                                                           contentHeight: g.size.height))
                            }
                        )
                }
                .coordinateSpace(name: "mlScroll")
                // Taps summon the chrome (simultaneous, so links/buttons still work).
                .simultaneousGesture(TapGesture().onEnded { handleContentTap() })
                // Horizontal swipes turn pages; the dominance check leaves
                // vertical scrolling untouched.
                .simultaneousGesture(
                    DragGesture(minimumDistance: 24).onEnded { v in
                        let dx = v.translation.width
                        guard pages.count > 1, abs(dx) > 60,
                              abs(dx) > abs(v.translation.height) * 1.4 else { return }
                        goToPage(pageIndex + (dx < 0 ? 1 : -1), pageCount: pages.count)
                    }
                )
                .id(pageIndex)
                .transition(.opacity)
            }
            .onPreferenceChange(MLScrollMetricsKey.self) { m in
                updatePageFraction(m, viewport: viewport.size.height)
            }
        }
    }

    private func lessonBody(_ d: ModuleDetail,
                            bodyBlocks: [MLBlock],
                            sectionTitle: String,
                            pageIndex: Int,
                            pageCount: Int,
                            video: WelcomeVideo?,
                            isFirstPage: Bool,
                            isLastPage: Bool) -> some View {
        // Give a genuine opening paragraph the larger "lead" voice; render the
        // rest of the section — headings, lists, quotes, tables — through the
        // real Markdown renderer, where headings stay headings.
        let leadParagraph: String? = {
            if case let .paragraph(text)? = bodyBlocks.first { return text }
            return nil
        }()
        let bodyRest: [MLBlock] = leadParagraph == nil ? bodyBlocks : Array(bodyBlocks.dropFirst())
        let hasLead = !bodyBlocks.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            // Titled SECTION headline — the derived heading (or "Section N"), with
            // an unobtrusive "n of m" for navigation context. The generic
            // "Page N of M" chrome is retired in favour of this title.
            MLSectionHeader(title: sectionTitle,
                            index0: pageIndex, count: pageCount)
                .padding(.bottom, video == nil && !hasLead ? 20 : 16)
            if let video {
                MLVideoCard(video: video, playing: $playingVideo)
                    .id("video")
            }
            // Audio narration — a light play/pause card with a thin progress
            // line; only on the first page and only when the module has audio.
            if isFirstPage, vm.hasAudio {
                MLAudioCard(playing: vm.audioPlaying,
                            progress: vm.audioProgress,
                            minutes: mlMinutes(d.audioDurationSec)) {
                    Haptics.tap()
                    vm.toggleAudio()
                    syncEngagementSignals()
                }
                .id("audio")
                .padding(.top, video == nil ? 0 : 16)
            }
            if let leadParagraph {
                Text(MLMarkdown.inline(leadParagraph))
                    .font(.inter(16, .medium)).foregroundStyle(ML.lead)
                    .lineSpacing(7)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, video == nil ? 0 : 20)
            }
            if !bodyRest.isEmpty {
                MLMarkdownView(blocks: bodyRest)
                    .padding(.top, leadParagraph == nil ? (video == nil ? 0 : 20) : 14)
            }
            if isFirstPage, let verse = d.keyVerses?.first(where: { !$0.isEmpty }) {
                MLScriptureCard(line: verse).padding(.top, 20)
            }
            if isLastPage {
                // Reflection is a REQUIRED content step BEFORE the quiz — it POSTs
                // through /modules/{id}/reflection (NOT completion). On success the
                // Reflect step lights up and the quiz gate can clear.
                Group {
                    if d.isFinished && !editingReflection {
                        VStack(spacing: 14) {
                            MLReflectionFolded(text: vm.savedReflection ?? reflection)
                            // The module is sealed — changing anything is an
                            // intentional act, behind one quiet door.
                            Button {
                                Haptics.tap()
                                showRevisitDialog = true
                            } label: {
                                HStack(spacing: 6) {
                                    Icon(.bookOpen, size: 12, color: ML.secondary)
                                    Text("Revisit this module")
                                        .font(.inter(13, .semibold)).foregroundStyle(ML.secondary)
                                }
                                .padding(.horizontal, 18).padding(.vertical, 10)
                                .background(Color.white, in: Capsule())
                                .overlay(Capsule().stroke(ML.border, lineWidth: 1))
                            }
                            .buttonStyle(.pressable)
                        }
                    } else {
                        MLReflectionCard(text: $reflection,
                                         busy: vm.submittingReflection,
                                         done: vm.reflectDone,
                                         error: vm.reflectionError) {
                            Haptics.action()
                            Task { await vm.submitReflection(reflection) }
                        }
                    }
                }
                .padding(.top, 32)
                .id("reflect")
                // Invisible sentinel — when it scrolls into the lower viewport we
                // latch `reachedEnd`, unlocking the CTA (a whisper of haptic marks
                // it). Lives only on the LAST page, so the gate now requires
                // reaching the last page's end.
                Color.clear.frame(height: 1)
                    .onAppear {
                        guard !reachedEnd else { return }
                        withAnimation(.easeInOut(duration: 0.25)) { reachedEnd = true }
                        Haptics.tap()
                        // The CTA is the next step — if immersed, surface it.
                        if chromeHidden { setChrome(hidden: false); didAutoImmerse = false }
                        armChromeHide(after: 180)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Read / Reflect (+ Watch when a video exists, + Listen when audio exists) —
    // jump to the matching part of the lesson. Behaviour preserved from the old
    // step chips; Listen additionally toggles the narration player.
    private func headerActions(hasVideo: Bool, hasAudio: Bool, pageCount: Int, proxy: ScrollViewProxy) -> MLHeaderActions {
        MLHeaderActions(
            readDone: reachedEnd,
            reflectDone: vm.reflectDone,
            hasVideo: hasVideo,
            watchDone: playingVideo,
            hasAudio: hasAudio,
            audioPlaying: vm.audioPlaying,
            onRead: {
                Haptics.selection()
                goToPage(0, pageCount: pageCount)
                withAnimation { proxy.scrollTo("top", anchor: .top) }
            },
            onReflect: {
                Haptics.selection()
                let last = pageCount - 1
                if currentPage != last {
                    goToPage(last, pageCount: pageCount)
                    // Let the new page mount before scrolling to the card.
                    Task {
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        withAnimation { proxy.scrollTo("reflect", anchor: .center) }
                    }
                } else {
                    withAnimation { proxy.scrollTo("reflect", anchor: .center) }
                }
            },
            onWatch: {
                Haptics.selection()
                playingVideo = true
                goToPage(0, pageCount: pageCount)
                withAnimation { proxy.scrollTo("video", anchor: .top) }
            },
            onListen: {
                Haptics.selection()
                goToPage(0, pageCount: pageCount)
                withAnimation { proxy.scrollTo("audio", anchor: .top) }
                vm.toggleAudio()
                syncEngagementSignals()
            })
    }

    // MARK: - Header media pills (real data only)

    /// The Watch / Listen meta pills. Each is nil unless the module actually
    /// carries that medium; a duration is shown ONLY when the server sent one
    /// (round(sec/60) → "Xm") — never invented.
    private func headerMedia(_ d: ModuleDetail) -> MLHeaderMedia {
        let watch: MLMediaPillModel? = mlVideo(d) != nil
            ? MLMediaPillModel(icon: .play, verb: "Watch", minutes: mlMinutes(d.videoDurationSec))
            : nil
        let listen: MLMediaPillModel? = vm.hasAudio
            ? MLMediaPillModel(icon: .audioLines, verb: "Listen", minutes: mlMinutes(d.audioDurationSec))
            : nil
        return MLHeaderMedia(watch: watch, listen: listen)
    }

    // MARK: - Page turning

    private func goToPage(_ p: Int, pageCount: Int) {
        guard p != currentPage, (0..<pageCount).contains(p) else { return }
        Haptics.selection()
        pageFraction = 0
        if reduceMotion { currentPage = p }
        else { withAnimation(.easeInOut(duration: 0.18)) { currentPage = p } }
        vm.pageChanged(to: p + 1)   // 1-based page number on the wire
        // A page turn is engagement, not idleness — rebuild the pending hide.
        if !chromeHidden { armChromeHide(after: 180) }
    }

    /// Fraction scrolled within the current page (spring-smoothed). A page
    /// shorter than the viewport has nothing to scroll and counts as read.
    /// The first meaningful downward scroll also slides the reader into
    /// immersive mode (before the 7s timer would) — reading IS the signal.
    private func updatePageFraction(_ m: MLScrollMetrics, viewport: CGFloat) {
        let scrollable = m.contentHeight - viewport
        let f = scrollable > 1 ? min(1, max(0, Double(m.offset / scrollable))) : 1
        if reduceMotion { pageFraction = f }
        else { withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { pageFraction = f } }

        // Scroll-triggered immersion: a downward scroll past a small threshold
        // hides the chrome immediately (once). Scrolling back near the top does
        // not force the chrome back — a tap does that.
        let delta = m.offset - lastScrollOffset
        lastScrollOffset = m.offset
        trackReadingPace(delta: delta, viewport: viewport)
        if !chromeHidden, !didAutoImmerse, m.offset > 32, delta > 4 {
            didAutoImmerse = true
            chromeTask?.cancel(); chromeTask = nil
            setChrome(hidden: true)
        }
    }

    // MARK: - Immersive chrome (7s in, tap back, 3-minute re-hide)

    private func setChrome(hidden: Bool) {
        if reduceMotion { chromeHidden = hidden }
        else { withAnimation(.easeInOut(duration: 0.3)) { chromeHidden = hidden } }
        tabs.chromeHidden = hidden   // RootView animates the tab bar itself
    }

    /// One live hide-timer at a time — cancelled and rebuilt on every tap/page
    /// turn so a stale timer can never yank the chrome mid-interaction.
    private func armChromeHide(after seconds: Double) {
        chromeTask?.cancel()
        chromeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            didAutoImmerse = true
            setChrome(hidden: true)
        }
    }

    private func handleContentTap() {
        if chromeHidden {
            setChrome(hidden: false)
            didAutoImmerse = false   // re-arm scroll-into-immersion
        }
        armChromeHide(after: 180)
    }

    // MARK: - Reading-pace guardrail (honest, camera-free)

    /// Watch the real scroll velocity. A downward flick faster than any human
    /// could read (≈1800 pt/s) that sustains past ~2 screens of text is
    /// skimming — we accumulate that blow-through and, once it crosses the bar,
    /// surface a gentle "slow down and take in the Word" nudge (cooldown-limited
    /// so it encourages, never nags). Slowing down decays the accumulator.
    private func trackReadingPace(delta: CGFloat, viewport: CGFloat) {
        let now = Date()
        defer { lastScrollAt = now }
        guard let last = lastScrollAt else { return }
        let dt = now.timeIntervalSince(last)
        guard dt > 0.001, dt < 0.4 else { fastScrollRun = 0; return }   // a pause resets
        let velocity = Double(delta) / dt                              // pt/s, +down
        if velocity > 1800 {
            fastScrollRun += delta
        } else if velocity < 700 {
            fastScrollRun = max(0, fastScrollRun - abs(delta))
        }
        if fastScrollRun > viewport * 2 {
            fastScrollRun = 0
            nudgeSlowDown()
        }
    }

    private func nudgeSlowDown() {
        if let t = lastNudgeAt, Date().timeIntervalSince(t) < 45 { return }   // don't nag
        lastNudgeAt = Date()
        Haptics.tap()
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { showSlowDown = true }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_400_000_000)
            withAnimation(.easeOut(duration: 0.4)) { showSlowDown = false }
        }
    }

    /// The explicit fullscreen toggle (hero + floating button). Manual control
    /// wins: cancel any pending auto-hide, and once the member uses it, hold the
    /// state until they toggle again (don't let scroll re-immerse under them).
    private func toggleImmersion() {
        Haptics.tap()
        chromeTask?.cancel(); chromeTask = nil
        if chromeHidden {
            didAutoImmerse = false
            setChrome(hidden: false)
        } else {
            didAutoImmerse = true      // stop scroll auto-immersion fighting the tap
            setChrome(hidden: true)
        }
    }

    // MARK: - Engagement plumbing

    /// Single choke point for the observed-time signals. Reading counts while
    /// the reader is on screen with the scene active; video counts only while
    /// the embed is open on its page (see setVideoOpen for why that's the
    /// strongest available signal).
    private func syncEngagementSignals() {
        let active = viewOnScreen && scenePhase == .active && vm.detail != nil
        if active { vm.beginReading() } else { vm.pauseReading() }
        vm.setVideoOpen(active && playingVideo && currentPage == 0)
        // Leaving / backgrounding: stop hearing (and counting) the narration.
        if !active { vm.suspendAudioIfNeeded() }
    }

    /// Silent resume: jump straight to the server's last_page and greet the
    /// returning reader with a note that fades on its own.
    private func applyResume(_ totals: ModuleEngagement?) {
        guard let d = vm.detail, let totals else { return }
        let pageCount = mlPages(d).count
        let page = min(max(totals.lastPage, 1), pageCount)
        vm.baselinePage(page)
        guard pageCount > 1, page > 1 else { return }
        currentPage = page - 1      // no animation — the reader opens here
        pageFraction = 0
        showResumeNote("Welcome back — picking up on section \(page)")
    }

    private func showResumeNote(_ text: String) {
        if reduceMotion { resumeNote = text }
        else { withAnimation(.easeInOut(duration: 0.3)) { resumeNote = text } }
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if reduceMotion { resumeNote = nil }
            else { withAnimation(.easeInOut(duration: 0.5)) { resumeNote = nil } }
        }
    }
}

// MARK: - Scroll metrics (content offset + height → the top progress bar)

private struct MLScrollMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 1
}

private struct MLScrollMetricsKey: PreferenceKey {
    static var defaultValue = MLScrollMetrics()
    static func reduce(value: inout MLScrollMetrics, nextValue: () -> MLScrollMetrics) {
        value = nextValue()
    }
}

// The reading-progress bar + right-rail eye-pacer are the shared
// NuruReadingBar / NuruPaceRail (NuruTheme.swift) — one visual language
// across the Pathway module reader and the Plan part readers.

// MARK: - Resume note + whisper page indicator (immersive-mode companions)

private struct MLResumeNote: View {
    let text: String
    var body: some View {
        HStack(spacing: 6) {
            Icon(.sparkles, size: 12, color: ML.gold)
            Text(text).font(.inter(12, .medium)).foregroundStyle(ML.navy)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(ML.surface, in: Capsule())
        .overlay(Capsule().stroke(ML.border, lineWidth: 1))
        .shadow(color: Color(hex: 0x0A1628).opacity(0.10), radius: 8, y: 4)
        .transition(.opacity)
        .allowsHitTesting(false)
    }
}

private struct MLPageWhisper: View {
    let page: Int
    let count: Int
    var body: some View {
        Text("\(page) / \(count)")
            .font(.inter(11, .medium)).kerning(0.5)
            .foregroundStyle(ML.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(ML.surface.opacity(0.92), in: Capsule())
            .overlay(Capsule().stroke(ML.border, lineWidth: 1))
            .allowsHitTesting(false)
            .accessibilityLabel("Section \(page) of \(count)")
    }
}

// MARK: - Pager bar (chevrons + number pills, current = gold gradient)

private struct MLPagerBar: View {
    let pageCount: Int
    let current: Int
    let onSelect: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            arrow(.chevronLeft, enabled: current > 0) { onSelect(current - 1) }
            Group {
                if pageCount <= 7 {
                    HStack(spacing: 6) {
                        ForEach(0..<pageCount, id: \.self) { pill($0) }
                    }
                } else {
                    // Too many pills to fit — a compact label keeps orientation.
                    Text("Section \(current + 1) of \(pageCount)")
                        .font(.inter(12, .semibold)).foregroundStyle(ML.navy)
                }
            }
            .frame(maxWidth: .infinity)
            arrow(.chevronRight, enabled: current < pageCount - 1) { onSelect(current + 1) }
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.vertical, 8)
    }

    private func pill(_ i: Int) -> some View {
        Button { onSelect(i) } label: {
            Text("\(i + 1)")
                .font(.inter(12, .bold))
                .foregroundStyle(i == current ? ML.navy : ML.secondary)
                .frame(width: 30, height: 30)
                .background(i == current ? AnyShapeStyle(ML.goldGradient) : AnyShapeStyle(Color.white),
                            in: Circle())
                .overlay(Circle().stroke(i == current ? Color.clear : ML.border, lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Section \(i + 1) of \(pageCount)")
        .accessibilityAddTraits(i == current ? [.isSelected] : [])
    }

    private func arrow(_ icon: Lucide, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Icon(icon, size: 15, color: enabled ? ML.navy : ML.secondary.opacity(0.4))
                .frame(width: 34, height: 34)
                .background(Color.white, in: Circle())
                .overlay(Circle().stroke(ML.border, lineWidth: 1))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .disabled(!enabled)
    }
}

// MARK: - Header (parchment gradient, rounded bottom, gold glow)
//
// A tidy, centred hero: overline · serif title · a tappable SECTION INDEX (one
// chip per author-defined content page, current = gold) · one meta row (≈ min
// read · N sections · a Watch pill only with a video · a Listen pill only with
// audio — never a pill for media that isn't there) · one action row (a segmented
// Read/Reflect control plus Watch/Listen buttons for whatever media exists).

/// One Watch/Listen meta pill's content. `minutes` is nil unless the server sent
/// a real duration (round(sec/60)); the pill then shows just its verb.
private struct MLMediaPillModel {
    let icon: Lucide
    let verb: String        // "Watch" | "Listen"
    let minutes: Int?       // real duration in minutes, or nil
    var label: String { minutes.map { "\(verb) · \($0)m" } ?? verb }
}

/// The header's media pills — each present only when that medium actually exists.
private struct MLHeaderMedia {
    let watch: MLMediaPillModel?
    let listen: MLMediaPillModel?
}

/// The header's tab actions, tri-stated (done/active shows a check + gold fill).
private struct MLHeaderActions {
    var readDone: Bool
    var reflectDone: Bool
    var hasVideo: Bool
    var watchDone: Bool
    var hasAudio: Bool
    var audioPlaying: Bool
    let onRead: () -> Void
    let onReflect: () -> Void
    let onWatch: () -> Void
    let onListen: () -> Void
}

private struct MLHeader: View {
    let levelNumber: Int
    let moduleNumber: Int
    let title: String
    let readMinutes: Int
    let sectionCount: Int
    let sectionTitles: [String]
    let currentSection: Int
    let media: MLHeaderMedia
    let onSelectSection: (Int) -> Void
    let actions: MLHeaderActions
    let onBack: () -> Void
    let onToggleImmersion: () -> Void
    let onExplain: () -> Void
    var finished: MLFinishedSummary? = nil

    var body: some View {
        VStack(spacing: 0) {
            // Row 1 — back · centred overline · fullscreen · share.
            ZStack {
                Text("LEVEL \(levelNumber) · MODULE \(moduleNumber)")
                    .font(.inter(11, .bold)).kerning(2)
                    .foregroundStyle(ML.overline)
                HStack(spacing: 8) {
                    MLSquareButton(icon: .arrowLeft, action: onBack)
                    Spacer(minLength: 0)
                    // "Hear it another way" — Nuru re-renders this lesson.
                    MLSquareButton(icon: .sparkles, action: onExplain)
                    // Hide the header + tab bar for a full-screen read.
                    MLImmerseButton(expanded: false, action: onToggleImmersion)
                    ShareLink(item: "\(title) — Nuru Pathway") {
                        MLSquareLabel(icon: .share2)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Title — centred serif.
            Text(title)
                .font(.fraunces(24, .medium)).kerning(-0.7)
                .foregroundStyle(ML.navy)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            // Meta row — read · sections · watch · listen, evenly spaced.
            metaRow
                .padding(.top, 12)
            // Section index — one tappable chip per section (only when >1).
            if sectionCount > 1 {
                MLSectionIndex(titles: sectionTitles, current: currentSection, onSelect: onSelectSection)
                    .padding(.top, 12)
            }
            // Action row — balanced, equal-width. Finished modules show the
            // completed ribbon instead: score · finish time · Retake.
            if let f = finished {
                finishedRibbon(f).padding(.top, 14)
            } else {
                actionRow
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, 56)
        .padding(.bottom, Nuru.S.screen)
        .frame(maxWidth: .infinity)
        .background(headerBackground)
        .shadow(color: Color(hex: 0x0A1628).opacity(0.12), radius: 10, y: 6)
    }

    /// ≈ min read · N sections · Watch · Listen. The read + section pills always
    /// show; Watch/Listen appear only for media that's actually present.
    private var metaRow: some View {
        HStack(spacing: 10) {
            MLMetaPill(icon: .clock, label: "≈ \(readMinutes) min read")
            MLMetaPill(icon: .bookOpen,
                       label: "\(sectionCount) section\(sectionCount == 1 ? "" : "s")")
            if let watch = media.watch { MLMetaPill(icon: watch.icon, label: watch.label) }
            if let listen = media.listen { MLMetaPill(icon: listen.icon, label: listen.label) }
        }
        .frame(maxWidth: .infinity)
    }

    /// A segmented Read | Reflect control, and — for whatever media exists — a
    /// matching Watch and/or Listen button beside it. All share equal width.
    private var actionRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                MLSegment(label: "Read", icon: .bookOpen, done: actions.readDone,
                          action: actions.onRead)
                Rectangle().fill(ML.border).frame(width: 1, height: 22)
                MLSegment(label: "Reflect", icon: .quote, done: actions.reflectDone,
                          action: actions.onReflect)
            }
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(ML.border, lineWidth: 1))
            .frame(maxWidth: .infinity)
            if actions.hasVideo {
                MLMediaButton(icon: actions.watchDone ? .check : .play, label: "Watch",
                              active: actions.watchDone, action: actions.onWatch)
                    .frame(maxWidth: .infinity)
            }
            if actions.hasAudio {
                MLMediaButton(icon: .audioLines, label: "Listen",
                              active: actions.audioPlaying, action: actions.onListen)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func finishedRibbon(_ f: MLFinishedSummary) -> some View {
        HStack(spacing: 8) {
            Icon(.check, size: 12, color: ML.navy)
            Text("COMPLETED").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(ML.navy)
            if let s = f.score {
                Text("· \(s)%").font(.inter(11, .bold)).foregroundStyle(ML.gold)
            }
            if let w = f.when {
                Text("· \(w)").font(.inter(10.5)).foregroundStyle(ML.secondary).lineLimit(1)
            }
            Spacer(minLength: 6)
            if f.canRetake {
                Button { f.onRetake() } label: {
                    Text("Retake").font(.inter(11, .bold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(ML.navy, in: Capsule())
                }
                .buttonStyle(.pressable)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(ML.gold.opacity(0.14), in: Capsule())
        .overlay(Capsule().stroke(ML.gold.opacity(0.35), lineWidth: 1))
    }

    private var headerBackground: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [ML.headerTop, ML.headerBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(ML.gold.opacity(0.13))
                .frame(width: 224, height: 224)
                .blur(radius: 44)
                .offset(x: 64, y: -80)
        }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 24, bottomTrailingRadius: 24,
                                          style: .continuous))
        .ignoresSafeArea(edges: .top)
    }
}

/// One segment of the Read | Reflect control. The active/done state fills gold
/// with a check; otherwise a quiet white pill segment.
private struct MLSegment: View {
    let label: String
    let icon: Lucide
    let done: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if done { Icon(.check, size: 11, color: ML.navy) }
                else { Icon(icon, size: 12, color: ML.secondary) }
                Text(label).font(.inter(12, .bold))
            }
            .foregroundStyle(done ? ML.navy : ML.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(done ? AnyShapeStyle(ML.gold.opacity(0.9)) : AnyShapeStyle(Color.clear),
                        in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .animation(.easeInOut(duration: 0.2), value: done)
    }
}

/// A Watch or Listen button — matches the segmented control's height and voice;
/// each only shown when the module carries that medium. `active` fills gold (the
/// video has been opened / the audio is playing).
private struct MLMediaButton: View {
    let icon: Lucide
    let label: String
    let active: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Icon(icon, size: 12, color: active ? ML.navy : ML.secondary)
                Text(label).font(.inter(12, .bold))
            }
            .foregroundStyle(active ? ML.navy : ML.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(active ? AnyShapeStyle(ML.gold.opacity(0.9)) : AnyShapeStyle(Color.white),
                        in: Capsule())
            .overlay(Capsule().stroke(active ? Color.clear : ML.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .animation(.easeInOut(duration: 0.2), value: active)
    }
}

// MARK: - Section index (tappable chips — one per author-defined section)

/// A compact, tappable index of the lesson's sections. One chip per content
/// page, titled from that page's first heading (or "Section N"); the current
/// chip is gold. Tapping jumps the reader to that section. Kept to one clean
/// row that scrolls horizontally when the chips don't all fit, and it keeps the
/// current chip in view as the reader turns pages. Chip text is truncated to one
/// line so a long heading never blows out the row.
private struct MLSectionIndex: View {
    let titles: [String]
    let current: Int
    let onSelect: (Int) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(titles.enumerated()), id: \.offset) { idx, title in
                        chip(idx, title).id(idx)
                    }
                }
                .padding(.horizontal, 2)   // so the gold ring isn't clipped
            }
            // Keep the active chip centred as pages turn (still under Reduce Motion).
            .onChange(of: current) { _, c in
                if reduceMotion { proxy.scrollTo(c, anchor: .center) }
                else { withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(c, anchor: .center) } }
            }
        }
    }

    private func chip(_ idx: Int, _ title: String) -> some View {
        let isCurrent = idx == current
        return Button {
            Haptics.selection()
            onSelect(idx)
        } label: {
            HStack(spacing: 5) {
                Text("\(idx + 1)")
                    .font(.inter(10, .bold))
                    .foregroundStyle(isCurrent ? ML.navy.opacity(0.7) : ML.secondary.opacity(0.7))
                Text(title)
                    .font(.inter(12, .semibold))
                    .lineLimit(1)
                    .foregroundStyle(isCurrent ? ML.navy : ML.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isCurrent ? AnyShapeStyle(ML.gold.opacity(0.9)) : AnyShapeStyle(Color.white),
                        in: Capsule())
            .overlay(Capsule().stroke(isCurrent ? Color.clear : ML.border, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
        .frame(maxWidth: 180, alignment: .leading)
        .accessibilityLabel("Section \(idx + 1): \(title)")
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

private struct MLSquareButton: View {
    let icon: Lucide
    let action: () -> Void
    var body: some View {
        Button(action: action) { MLSquareLabel(icon: icon).contentShape(Rectangle()) }
            .buttonStyle(.pressable)
    }
}

private struct MLSquareLabel: View {
    let icon: Lucide
    var body: some View {
        Icon(icon, size: 17, color: ML.navy)
            .frame(width: 40, height: 40)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ML.border, lineWidth: 1))
    }
}

/// The "slow down" nudge — a soft cream card with a dove, surfaced when the
/// reader blows past the text. Encouragement, not a scold; auto-dismisses.
private struct MLSlowDownNudge: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("🕊️").font(.system(size: 20))
            VStack(alignment: .leading, spacing: 2) {
                Text("Slow down — take in the Word")
                    .font(.inter(13, .semibold)).foregroundStyle(ML.navy)
                Text("Let it speak. Read at the pace of the soul.")
                    .font(.inter(11)).foregroundStyle(ML.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(ML.gold.opacity(0.35), lineWidth: 1))
        .shadow(color: Color(hex: 0x0A1628).opacity(0.16), radius: 12, y: 6)
        .padding(.horizontal, 24)
    }
}

/// Fullscreen toggle — hide/show the header + tab bar for a bigger read area.
/// `expanded == false` (chrome visible) shows the diverging arrows ("go
/// fullscreen"); `expanded == true` (immersed) shows the converging arrows
/// ("exit fullscreen"). The `floating` variant is the frosted round handle
/// that lives in the immersive top-right corner; otherwise it matches the
/// header's square chrome buttons.
private struct MLImmerseButton: View {
    let expanded: Bool
    var floating = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: expanded
                  ? "arrow.down.right.and.arrow.up.left"
                  : "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(floating ? .white : ML.navy)
                .frame(width: 40, height: 40)
                .background {
                    if floating {
                        Circle().fill(ML.navy.opacity(0.82))
                            .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                            .shadow(color: .black.opacity(0.28), radius: 8, y: 4)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white)
                            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ML.border, lineWidth: 1))
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(expanded ? "Exit full-screen reading" : "Full-screen reading")
    }
}

private struct MLMetaPill: View {
    let icon: Lucide
    let label: String
    var body: some View {
        HStack(spacing: 4) {
            Icon(icon, size: 11, color: ML.secondary)
            Text(label).font(.inter(11))
        }
        .foregroundStyle(ML.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.white, in: Capsule())
        .overlay(Capsule().stroke(ML.border, lineWidth: 1))
    }
}

// MARK: - Video card (16:9, real inline player — never a fake transport)

private struct MLVideoCard: View {
    let video: WelcomeVideo
    @Binding var playing: Bool

    var body: some View {
        Group {
            if playing {
                InlineVideoPlayer(video: video)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.black)
            } else {
                Button { Haptics.tap(); playing = true } label: { poster }.buttonStyle(.pressableSubtle)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(playing ? ML.gold : ML.border, lineWidth: 1))
    }

    private var poster: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x123B62), ML.navy],
                           startPoint: .top, endPoint: .bottom)
            Circle().fill(ML.gold.opacity(0.92)).frame(width: 56, height: 56)
            Icon(.play, size: 22, color: ML.navy).offset(x: 2)
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .overlay(alignment: .topLeading) {
            Text("VIDEO")
                .font(.inter(10, .bold)).kerning(1).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(Color.black.opacity(0.55), in: Capsule())
                .padding(12)
        }
    }
}

// MARK: - Audio narration card (light AVPlayer transport — real playback only)

/// A tasteful play/pause narration tile: a gold-filled round transport, a
/// "Narration" label (with the real "· Xm" duration when the server sent one),
/// and a thin gold progress line bound to actual playback. No scrubber, no fake
/// timecodes — it plays and it counts seconds; that's the whole job here.
private struct MLAudioCard: View {
    let playing: Bool
    let progress: Double        // 0…1 of the track
    let minutes: Int?           // real duration in minutes, or nil
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    transport
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LISTEN")
                            .font(.inter(10, .bold)).kerning(1.8)
                            .foregroundStyle(ML.kicker)
                        Text(minutes.map { "Narration · \($0)m" } ?? "Narration")
                            .font(.inter(13, .semibold)).foregroundStyle(ML.navy)
                    }
                    Spacer(minLength: 0)
                    Icon(.audioLines, size: 18, color: ML.gold.opacity(0.9))
                }
                progressLine
            }
            .padding(Nuru.S.base)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(ML.surface)
            .overlay(alignment: .leading) { Rectangle().fill(ML.gold).frame(width: 3) }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(playing ? ML.gold : ML.border, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressableSubtle)
        .accessibilityLabel(playing ? "Pause narration" : "Play narration")
        .accessibilityValue("\(Int((progress * 100).rounded())) percent")
    }

    private var transport: some View {
        ZStack {
            Circle().fill(ML.goldGradient).frame(width: 44, height: 44)
            // No Lucide "pause" glyph — SF Symbols, as MLImmerseButton already does.
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(ML.navy)
                .offset(x: playing ? 0 : 1)
        }
        .shadow(color: ML.gold.opacity(0.4), radius: 6, y: 3)
    }

    private var progressLine: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(ML.track)
                Capsule().fill(ML.goldGradient)
                    .frame(width: max(0, geo.size.width * min(1, max(0, progress))))
            }
        }
        .frame(height: 3)
    }
}

// MARK: - Scripture pull-quote (surface tile with a gold left edge)

private struct MLScriptureCard: View {
    let line: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Icon(.quote, size: 12, color: ML.gold)
                Text("KEY VERSE")
                    .font(.inter(10, .bold)).kerning(1.8)
                    .foregroundStyle(ML.kicker)
            }
            Text("\u{201C}\(line)\u{201D}")
                .font(.fraunces(16.5, .regular)).italic()
                .foregroundStyle(ML.navy)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ML.surface)
        .overlay(alignment: .leading) { Rectangle().fill(ML.gold).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - Section header (the titled headline that replaces "Page N of M")

/// The headline for the current page-as-section: a small "SECTION · n of m"
/// kicker for navigation context, then the derived title as a prominent serif
/// heading. When there are multiple pages the kicker carries the "n of m";
/// a single page shows just "SECTION".
private struct MLSectionHeader: View {
    let title: String
    let index0: Int
    let count: Int

    private var kicker: String {
        count > 1 ? "SECTION · \(index0 + 1) OF \(count)" : "SECTION"
    }
    private var a11y: String {
        count > 1 ? "Section \(index0 + 1) of \(count): \(title)" : title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(.inter(10, .bold)).kerning(1.8)
                .foregroundStyle(ML.kicker)
            Text(title)
                .font(.fraunces(23, .semibold)).kerning(-0.5)
                .foregroundStyle(ML.navy)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel(a11y)
    }
}

// MARK: - Reflection card (inline; submits through completeModule)

/// Header ribbon payload for a finished module.
struct MLFinishedSummary {
    let score: Int?
    let when: String?
    let canRetake: Bool
    let onRetake: () -> Void
}

/// Finished modules show the reflection FOLDED — the words the member wrote,
/// read-only and sealed (edits flow through the "Revisit this module" door).
private struct MLReflectionFolded: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("YOUR REFLECTION").font(.inter(10, .bold)).kerning(1.8).foregroundStyle(ML.kicker)
                Spacer()
                HStack(spacing: 3) {
                    Icon(.check, size: 10, color: Color(hex: 0x15803D))
                    Text("Saved").font(.inter(10, .bold)).foregroundStyle(Color(hex: 0x15803D))
                }
            }
            Text(text.isEmpty ? "\u{2014}" : text)
                .font(.fraunces(15)).foregroundStyle(ML.bodyInk)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(ML.gold.opacity(0.4), lineWidth: 1))
    }
}

private struct MLReflectionCard: View {
    @Binding var text: String
    let busy: Bool
    let done: Bool          // the reflection has been saved server-side
    let error: String?
    let onSubmit: () -> Void

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSubmit: Bool { trimmed.count >= ML.reflectMinChars }
    private var words: Int { trimmed.isEmpty ? 0 : trimmed.split(whereSeparator: \.isWhitespace).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text("REFLECTION · STEP")
                    .font(.inter(10, .bold)).kerning(1.8)
                    .foregroundStyle(ML.kicker)
                Spacer(minLength: 0)
                if done {
                    HStack(spacing: 4) {
                        Icon(.check, size: 10, color: ML.navy)
                        Text("Saved").font(.inter(10, .bold)).foregroundStyle(ML.navy)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(ML.gold.opacity(0.9), in: Capsule())
                    .transition(.opacity)
                }
            }
            Text("What is one thing from this module the Spirit is asking you to practice this week?")
                .font(.fraunces(15, .regular)).foregroundStyle(ML.navy)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
            editor.padding(.top, 12)
            Text(counterLine)
                .font(.inter(11)).foregroundStyle(done ? ML.overline : ML.secondary)
                .contentTransition(.numericText())
                .animation(.default, value: trimmed.count)
                .padding(.top, 6)
            if let error {
                Text(error)
                    .font(.inter(11, .medium)).foregroundStyle(Nuru.danger)
                    .padding(.top, 6)
            }
            submitButton.padding(.top, 12)
        }
        .padding(Nuru.S.base)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(done ? ML.gold.opacity(0.5) : ML.border, lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: done)
    }

    private var counterLine: String {
        if done { return "Reflection saved — you can revise it any time." }
        return canSubmit
            ? "\(words) words · \(trimmed.count) chars"
            : "\(ML.reflectMinChars - trimmed.count) more characters before you can submit"
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("A few honest words…")
                    .font(.inter(13)).foregroundStyle(Nuru.faint)
                    .padding(.horizontal, 14).padding(.vertical, 12)
            }
            TextEditor(text: $text)
                .font(.inter(13)).foregroundStyle(ML.navy)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 110)
                .padding(.horizontal, 10).padding(.vertical, 6)
        }
        .background(ML.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(ML.border, lineWidth: 1))
    }

    private var submitButton: some View {
        Button(action: onSubmit) {
            ZStack {
                if busy { ProgressView().tint(.white) }
                else { Text(done ? "Update reflection" : "Submit reflection").font(.inter(13, .semibold)) }
            }
            .foregroundStyle(canSubmit ? Color.white : Color(hex: 0x0A2540, alpha: 0.55))
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(canSubmit ? AnyShapeStyle(ML.navy) : AnyShapeStyle(Color(hex: 0x0A2540, alpha: 0.18)),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.pressable)
        .disabled(!canSubmit || busy)
        .animation(.easeInOut(duration: 0.2), value: canSubmit)
    }
}

// MARK: - Bottom gate (progress strip + locked / quiz / mark-complete CTA)

private struct MLBottomGate: View {
    let steps: [GateStep]       // the applicable steps, in order, each with a live fraction
    let complete: Bool          // every applicable step done
    let lockReason: String      // why it's still locked (names the first unmet step)
    let requiresQuiz: Bool
    let moduleId: String
    let busy: Bool
    let error: String?
    /// Extra bottom clearance so the CTA is never hidden behind the app tab bar
    /// (which RootView overlays on top of this view while chrome is visible).
    let bottomInset: CGFloat
    let startingQuiz: Bool
    let onStartQuiz: () -> Void
    let onComplete: () -> Void

    private var doneCount: Int { steps.filter(\.done).count }

    var body: some View {
        VStack(spacing: complete ? 8 : 10) {
            if complete {
                // Done state collapses to one slim celebratory line — the bar and
                // chips would only repeat it, and the reclaimed height keeps the
                // reflection card visible above the gate.
                HStack(spacing: 10) {
                    Text("All steps done 🎉")
                        .font(.inter(11, .bold)).foregroundStyle(ML.overline)
                    Spacer(minLength: 0)
                }
            } else {
                // Header — the live "N of M steps done" tally.
                HStack(spacing: 10) {
                    Text("\(doneCount) of \(steps.count) steps done")
                        .font(.inter(11, .bold))
                        .foregroundStyle(ML.navy)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.25), value: doneCount)
                    Spacer(minLength: 0)
                }
                // The compact chip row — check when done, a partial ring while in
                // progress. (The old segmented bar duplicated these rings and cost
                // a full row of reading space; the chips alone tell the story.)
                chipRow
            }
            if let error {
                Text(error)
                    .font(.inter(11, .medium)).foregroundStyle(Nuru.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            cta
        }
        .padding(.horizontal, Nuru.S.screen)
        .padding(.top, complete ? Nuru.S.sm : Nuru.S.md)
        .padding(.bottom, bottomInset)
        .background(
            ML.cream
                .overlay(alignment: .top) { Rectangle().fill(ML.border).frame(height: 1) }
                .ignoresSafeArea(edges: .bottom)
        )
        .animation(.easeInOut(duration: 0.25), value: complete)
    }

    /// One filling segment per applicable step. A done segment is solid gold; the
    /// in-progress segment fills gold to its real fraction; not-yet steps stay track.
    private var segmentedBar: some View {
        HStack(spacing: 5) {
            ForEach(steps) { step in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(ML.track)
                        Capsule().fill(step.done ? AnyShapeStyle(ML.goldGradient) : AnyShapeStyle(ML.gold.opacity(0.85)))
                            .frame(width: max(0, geo.size.width * step.clamped))
                    }
                }
                .frame(height: 6)
                .animation(.easeOut(duration: 0.35), value: step.clamped)
            }
        }
    }

    /// A compact row of labelled step chips.
    private var chipRow: some View {
        HStack(spacing: 6) {
            ForEach(steps) { MLStepChip(step: $0) }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var cta: some View {
        if !complete {
            HStack(spacing: 8) {
                Icon(.lock, size: 13, color: ML.secondary)
                Text(lockReason)
                    .font(.inter(14, .bold))
            }
            .foregroundStyle(ML.secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(ML.border, lineWidth: 1))
        } else if requiresQuiz {
            // Flush the latest read/watch/listen seconds before navigating, so
            // the server's content gate never wrongly blocks a real finisher.
            Button {
                Haptics.action()
                onStartQuiz()
            } label: {
                ZStack {
                    if startingQuiz { ProgressView().tint(ML.navy) }
                    else {
                        HStack(spacing: 8) {
                            Text("Start the quiz").font(.inter(14, .bold))
                            Icon(.arrowRight, size: 15, color: ML.navy)
                        }
                    }
                }
                .foregroundStyle(ML.navy)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(ML.goldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: ML.gold.opacity(0.45), radius: 12, y: 8)
            }
            .buttonStyle(.pressable)
            .disabled(startingQuiz)
        } else {
            Button(action: onComplete) {
                ZStack {
                    if busy { ProgressView().tint(ML.navy) }
                    else { Text("Mark complete").font(.inter(14, .bold)) }
                }
                .foregroundStyle(ML.navy)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(ML.goldGradient, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: ML.gold.opacity(0.45), radius: 12, y: 8)
            }
            .buttonStyle(.pressable)
            .disabled(busy)
        }
    }
}

// MARK: - Gate step chip (labelled; check when done, partial ring in progress)

/// One step in the bottom gate's chip row. Done → gold fill + check. In progress
/// (0 < fraction < 1) → a subtle gold partial ring around the icon. Not started →
/// a quiet white chip. The ring reads the step's REAL fraction so it grows live.
private struct MLStepChip: View {
    let step: GateStep

    private var inProgress: Bool { step.clamped > 0.001 && !step.done }

    var body: some View {
        HStack(spacing: 5) {
            ZStack {
                if step.done {
                    Icon(.check, size: 10, color: ML.navy)
                } else {
                    // A partial ring that fills to the live fraction while in progress.
                    Circle().stroke(ML.track, lineWidth: 1.5).frame(width: 14, height: 14)
                    if inProgress {
                        Circle().trim(from: 0, to: step.clamped)
                            .stroke(ML.gold, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .frame(width: 14, height: 14)
                            .animation(.easeOut(duration: 0.35), value: step.clamped)
                    }
                    Icon(step.kind.icon, size: 8, color: inProgress ? ML.overline : ML.secondary)
                }
            }
            .frame(width: 16, height: 16)
            Text(step.kind.label)
                .font(.inter(11, .bold))
                .foregroundStyle(step.done ? ML.navy : (inProgress ? ML.navy : ML.secondary))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(step.done ? AnyShapeStyle(ML.gold.opacity(0.9)) : AnyShapeStyle(Color.white),
                    in: Capsule())
        .overlay(Capsule().stroke(step.done ? Color.clear : (inProgress ? ML.gold.opacity(0.5) : ML.border), lineWidth: 1))
        .animation(.easeInOut(duration: 0.2), value: step.done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(step.kind.label) step")
        .accessibilityValue(step.done ? "done" : "\(Int((step.clamped * 100).rounded())) percent")
    }
}

// MARK: - Lesson pages + read-time (real data only)

/// The reader's pages: the server's author-inserted splits when present,
/// otherwise the whole lesson as one page.
private func mlPages(_ d: ModuleDetail) -> [String] {
    let pages = (d.contentPages ?? [])
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    return pages.isEmpty ? [d.lessonContent] : pages
}

/// ≈ read time from the REAL word count of what's actually rendered, at a
/// standard 200 wpm — a computation, never an invented number.
private func mlReadMinutes(_ pages: [String]) -> Int {
    let words = pages.joined(separator: " ").split(whereSeparator: \.isWhitespace).count
    return max(1, Int((Double(words) / 200.0).rounded()))
}

/// A media duration in whole minutes for a "Xm" pill suffix — REAL data only:
/// nil (server sent none) → nil (the pill shows just its verb, no duration).
/// A sub-30s clip rounds up to "1m" so a present duration never reads "0m".
private func mlMinutes(_ seconds: Int?) -> Int? {
    guard let seconds, seconds > 0 else { return nil }
    return max(1, Int((Double(seconds) / 60.0).rounded()))
}

// MARK: - Section titles (client-derived — each page is a titled SECTION)

/// A page's first line is treated as its section title when it's a Markdown ATX
/// heading (`#`…`######` + space(s) + text). That heading line — and one blank
/// line immediately after it — is stripped from the returned body, so the title
/// isn't rendered twice. Otherwise `title == nil` and the body is the page
/// verbatim (internal spacing preserved). Display-only; the server's page split
/// is untouched.
private let mlHeadingRegex = try! NSRegularExpression(pattern: "^#{1,6}[ \\t]+(.+?)[ \\t]*$")

private func pageTitleAndBody(_ page: String) -> (title: String?, body: String) {
    let trimmed = page.trimmingCharacters(in: .whitespacesAndNewlines)
    // Isolate the first non-empty line without disturbing the rest of the page.
    let lines = trimmed.components(separatedBy: "\n")
    guard let firstIdx = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) else {
        return (nil, page)
    }
    let firstLine = lines[firstIdx].trimmingCharacters(in: .whitespaces)
    let range = NSRange(firstLine.startIndex..<firstLine.endIndex, in: firstLine)
    guard let match = mlHeadingRegex.firstMatch(in: firstLine, range: range),
          let capture = Range(match.range(at: 1), in: firstLine) else {
        return (nil, page)
    }
    let title = String(firstLine[capture])
    // Drop the heading line, then one immediately-following blank line.
    var rest = Array(lines[(firstIdx + 1)...])
    if let first = rest.first, first.trimmingCharacters(in: .whitespaces).isEmpty {
        rest.removeFirst()
    }
    return (title, rest.joined(separator: "\n"))
}

/// The section's headline for page `index0` (0-based) — the derived title, or a
/// numbered fallback when the page carries no heading.
private func sectionLabel(_ title: String?, _ index0: Int) -> String {
    title ?? "Section \(index0 + 1)"
}

/// Wrap the module's real videoUrl for the shared inline player (source inferred
/// from the host — YouTube/Vimeo embed, anything else plays as HTML5 video).
private func mlVideo(_ d: ModuleDetail) -> WelcomeVideo? {
    guard let raw = d.videoUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
          !raw.isEmpty else { return nil }
    let lower = raw.lowercased()
    let source = lower.contains("youtu") ? "youtube" : (lower.contains("vimeo") ? "vimeo" : "direct")
    return WelcomeVideo(mediaAssetId: d.moduleId, videoSource: source, caption: nil,
                        durationSec: nil, thumbnailUrl: nil, reactions: nil, loveCount: nil,
                        liked: nil, externalUrl: raw, externalVideoId: nil, url: nil,
                        expiresAt: nil)
}
