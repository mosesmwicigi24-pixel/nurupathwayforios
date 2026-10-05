// Focused part reader — page 4 of the plan journey (Plan → Days → Day hub →
// THIS). One part of the day at a time (Watch / Listen / Scripture / Devotional /
// Talk it Over / Prayer / Go Deeper) on a warm reading canvas. "Finished" ticks
// the part (server-backed), posts .nuruPlanPartDone so the day hub's row ticks
// the moment the member returns, and pops back — read, tick, back, pick the next.
// The Prayer part carries the day's reflection box at the bottom. Video/audio
// open in a window over the content. Honors the warm night/sepia reader mode.
import SwiftUI
import UIKit

extension Notification.Name {
    /// Posted (object = segmentId) when a part is finished in its reader.
    static let nuruPlanPartDone = Notification.Name("nuruPlanPartDone")
    /// Posted (object = PlanDayUnlockAck) when a segment's ack confirms its
    /// day sealed. Authoritative and same-transaction on the server side —
    /// the day hub trusts it directly instead of waiting for an explicit
    /// "Seal the day" tap, and the plan overview uses it to tell a genuine
    /// lock apart from a completion still catching up to its next fetch.
    static let nuruPlanDayUnlocked = Notification.Name("nuruPlanDayUnlocked")
}

// Scroll metrics (content offset + height → the reading instruments).
private struct PLReadMetrics: Equatable {
    var offset: CGFloat = 0
    var contentHeight: CGFloat = 1
}
private struct PLReadMetricsKey: PreferenceKey {
    static var defaultValue = PLReadMetrics()
    static func reduce(value: inout PLReadMetrics, nextValue: () -> PLReadMetrics) {
        value = nextValue()
    }
}

struct PlanSegmentView: View {
    let ref: PlanSegmentRef
    init(ref: PlanSegmentRef) { self.ref = ref }

    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @AppStorage("readerNight") private var readerNight = false
    /// Three text-size steps, cycled from the header, remembered per device.
    @AppStorage(ReaderTextScale.key) private var readerScale: Double = 1.0
    @State private var done = false
    @State private var saving = false
    /// Why the server didn't record the part — above the button (§7.4 #2).
    @State private var saveError: String?
    /// This part's segments the server has recorded while the page is open:
    /// a retry finishes only the rest.
    @State private var acked: Set<String> = []
    @State private var player: MediaItem?
    // Live scroll fraction → the same reading instruments the Pathway reader
    // shows (top gold hairline + right-rail eye-pacer). Hidden when the part
    // fits on one screen (nothing to pace).
    @State private var readFraction: Double = 0
    @State private var readScrollable = false

    private struct MediaItem: Identifiable { let id = UUID(); let url: URL }

    private var pal: ReaderPalette { ReaderPalette(night: readerNight, textScale: CGFloat(readerScale)) }
    private var segment: PlanSegment { ref.segments[min(max(ref.index, 0), ref.segments.count - 1)] }

    /// The segments this page renders — a combined group ("word" = Scripture +
    /// teaching + Go Deeper; "respond" = Talk + Prayer) or the single segment.
    private var group: [PlanSegment] {
        switch ref.part {
        case "word": return ref.segments.filter { [1, 2, 5].contains(rank($0)) }
        case "respond": return ref.segments.filter { rank($0) == 4 }
        default: return [segment]
        }
    }
    /// The day hub's grouping (PlanDayParts) — one truth for every part.
    private func rank(_ s: PlanSegment) -> Int { PlanDayParts.rank(s) }

    var body: some View {
        ZStack {
            pal.bg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                GeometryReader { viewport in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 20) {
                            content
                            if ref.part == "respond", let pid = ref.planId {
                                PartReflectionBox(planId: pid, dayNumber: ref.dayNumber)
                            }
                            DayEncouragement()
                        }
                        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 24)
                        // Scroll metrics for the reading instruments: content
                        // offset + height in the scroll's coordinate space.
                        .background(GeometryReader { g in
                            Color.clear.preference(
                                key: PLReadMetricsKey.self,
                                value: PLReadMetrics(offset: -g.frame(in: .named("plRead")).minY,
                                                     contentHeight: g.size.height))
                        })
                    }
                    .coordinateSpace(name: "plRead")
                    .scrollDismissesKeyboard(.interactively)
                    .onPreferenceChange(PLReadMetricsKey.self) { m in
                        let span = m.contentHeight - viewport.size.height
                        readScrollable = span > 56
                        readFraction = span > 1 ? min(1, max(0, Double(m.offset / span))) : 1
                    }
                    // The eye-pacer rides the reading canvas — under the navy
                    // header, clear of the bottom CTA (same cue as Pathway).
                    .overlay(alignment: .trailing) {
                        if readScrollable {
                            NuruPaceRail(progress: readFraction, topInset: 16, bottomInset: 116)
                                .transition(.opacity)
                        }
                    }
                    .safeAreaInset(edge: .bottom) { cta }
                }
            }
        }
        .environment(\.readerPalette, pal)
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Whole-part reading progress, flush to the physical top edge — the
        // same gold hairline the Pathway reader pins there.
        .overlay(alignment: .top) {
            if readScrollable {
                NuruReadingBar(progress: readFraction)
                    .ignoresSafeArea(edges: .top)
            }
        }
        .fullScreenCover(item: $player) { it in mediaWindow(it.url) }
        .onAppear {
            tabs.chromeHidden = true
            if group.allSatisfy({ $0.completed || ref.doneIds.contains($0.segmentId) }) { done = true }
        }
    }

    // MARK: header — back · medallion + part name · DAY N kicker · night toggle

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 8)
                Text("DAY \(ref.dayNumber) · \(ref.planTitle.uppercased())")
                    .font(.inter(11, .bold)).kerning(1.6).foregroundStyle(PL.gold)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                // Text size: Small → Regular → Large → Small, one tap each.
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.2)) { readerScale = ReaderTextScale.next(after: readerScale) }
                } label: {
                    Text("Aa").font(.inter(13, .bold)).foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel("Text size: \(ReaderTextScale.label(readerScale))")
                .padding(.trailing, 8)
                Button {
                    Haptics.tap()
                    withAnimation(.easeInOut(duration: 0.25)) { readerNight.toggle() }
                } label: {
                    Icon(readerNight ? .sun : .moon, size: 18, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                .accessibilityLabel(readerNight ? "Day mode" : "Night mode")
            }
            HStack(spacing: 12) {
                Icon(partIcon, size: 18, color: PL.gold)
                    .frame(width: 40, height: 40)
                    .background(PL.gold.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(PL.gold.opacity(0.4), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(partName).font(.fraunces(26, .medium)).kerning(-0.7).foregroundStyle(.white)
                    if let r = headerRef, !r.isEmpty {
                        Text(r).font(.inter(11)).foregroundStyle(.white.opacity(0.65))
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        .background(
            LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(.rect(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
                .ignoresSafeArea(edges: .top)
        )
    }

    private var partName: String {
        switch ref.part {
        case "word": return "The Word"
        case "respond": return "Respond"
        default: return segment.kind.lowercased() == "audio" ? "Listen" : "Watch"
        }
    }

    private var partIcon: Lucide {
        switch ref.part {
        case "word": return .bookOpen
        case "respond": return .handHeart
        default: return .play
        }
    }

    /// The Word page carries teaching after its passage (rank 2 = devotional).
    private var hasTeaching: Bool { group.contains { rank($0) == 2 && !($0.content ?? "").isEmpty } }

    /// Header caption — the scripture reference for The Word page.
    private var headerRef: String? {
        if ref.part == "word" {
            return group.first(where: { $0.kind.lowercased() == "scripture" })?.reference
        }
        return segment.reference
    }

    // MARK: content per part (shared Day* reading components)

    @ViewBuilder private var content: some View {
        switch ref.part {
        case "word":
            // The opening: kicker, the day's title, the reference and an honest
            // read time — a front door before the Word.
            DayOpening(title: ref.dayTitle, reference: headerRef, minutes: ReadTime.minutes(for: group))
            // Scripture woven straight into the teaching — one encouraging read,
            // Go Deeper folded in at the end.
            ForEach(group) { seg in
                switch seg.kind.lowercased() {
                case "scripture":
                    // Authored text wins; a bare reference fetches its passage so
                    // the pull-quote never reads "Proverbs 13:4" and nothing else.
                    if let c = seg.content, !c.isEmpty {
                        DayPullQuote(text: c, caption: seg.reference ?? "Scripture")
                    } else if let r = seg.reference, ScriptureRefs.isReference(r) {
                        DayScriptureQuote(reference: r)
                    } else {
                        DayPullQuote(text: seg.reference ?? seg.title, caption: seg.reference ?? "Scripture")
                    }
                    // Where the Word ends and the teaching begins.
                    if hasTeaching { ReaderOrnament() }
                case "reading":
                    if let c = seg.content, !c.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("GO DEEPER").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                            DayGoDeeperPassages(refs: c)
                        }
                    }
                default:
                    if let c = seg.content, !c.isEmpty { DayPassage(content: c) }
                }
            }
        case "respond":
            // Talk it Over → Prayer → your reflection, one response page.
            ForEach(group) { seg in
                if seg.kind.lowercased() == "talk", let c = seg.content, !c.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TALK IT OVER").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                        DayTalk(prompt: c)
                    }
                } else if let c = seg.content, !c.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("PRAYER").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                        DayPrayer(text: c)
                    }
                }
            }
        default:
            // Media page: a portrait, screen-filling player, then the title and
            // a few scanty keynotes just below.
            DayVideoCard(seg: segment, portrait: true) { url in player = MediaItem(url: url) }
            if !segment.title.isEmpty {
                Text(segment.title).font(.fraunces(18, .medium)).kerning(-0.4).foregroundStyle(pal.ink)
            }
            if let c = segment.content, !c.isEmpty { keynotes(c) }
        }
    }

    /// A few short keynote bullets (capped — scanty by design).
    private func keynotes(_ content: String) -> some View {
        let points = content.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .prefix(4)
        return VStack(alignment: .leading, spacing: 10) {
            Text("KEY POINTS").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                HStack(alignment: .top, spacing: 8) {
                    Circle().fill(pal.gold).frame(width: 5, height: 5).padding(.top, 7)
                    Text(p).font(.inter(pal.fs(14), .medium)).foregroundStyle(pal.ink).lineSpacing(5)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: finish — tick + notify the hub + return, on the server's word

    private var cta: some View {
        VStack(spacing: 8) {
            // Above the button (both apps): clear of the home indicator, read
            // before the retry tap. On its own card: the reading scrolls under
            // this bar, and the words must stay legible over it.
            if let saveError {
                Text(saveError)
                    .font(.inter(12, .medium)).foregroundStyle(pal.danger)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(pal.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(pal.danger.opacity(0.25), lineWidth: 1))
                    .transition(.opacity)
            }
            Button {
                guard !saving else { return }
                if done {
                    Haptics.tap(); dismiss(); return
                }
                saving = true
                withAnimation(.easeOut(duration: 0.2)) { saveError = nil }
                Task { await finish() }
            } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(PL.navy) }
                    else { Icon(.check, size: 14, color: PL.navy) }
                    Text(done ? "Done" : finishLabel)
                        .font(.inter(14, .bold)).foregroundStyle(PL.navy)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: PL.gold.opacity(0.4), radius: 10, y: 6)
            }
            .buttonStyle(.pressable)
            .disabled(saving)
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 14)
        .background(
            LinearGradient(colors: [pal.bg.opacity(0), pal.bg], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    /// Finish the part — every part's gold button (the Word: Scripture,
    /// teaching, Go Deeper; Respond: the prayer; Watch / Listen). No success
    /// before the server says so (§7.4 #2): each segment ticks the hub only
    /// on its own ack; the haptic and the way back come only once all have
    /// landed. A refusal or no answer keeps the member here, with §4's words
    /// for why above the button, and the next tap finishes only the rest.
    private func finish() async {
        var lastAck: SegmentCompleteResult?
        for seg in group where !seg.completed && !acked.contains(seg.segmentId) {
            do {
                let res = try await MemberAPI.completePlanSegment(seg.segmentId)
                acked.insert(seg.segmentId)
                lastAck = res
                NotificationCenter.default.post(name: .nuruPlanPartDone, object: seg.segmentId)
            } catch {
                saving = false
                withAnimation(.easeOut(duration: 0.2)) { saveError = NuruStateCopy.saveFailureLine(error) }
                Haptics.error()
                return
            }
        }
        // The LAST segment's ack is the server's authoritative word on whether
        // this day just sealed and the next one opened — computed in the same
        // transaction as the write. Broadcasting it lets the day hub skip the
        // explicit "Seal the day" tap and the plan overview tell a genuine
        // lock apart from a completion still landing through the sync path.
        // (It also notes the sealed day for the Plans streak card, §7.4 #4.)
        if let ack = lastAck { PlanDayUnlockAck.announce(ack, planId: ref.planId) }
        done = true; saving = false
        Haptics.success()
        dismiss()
    }

    /// Warm, part-specific completion wording.
    private var finishLabel: String {
        switch ref.part {
        case "word": return "I've read today's Word"
        case "respond": return "Amen — finished"
        default: return segment.kind.lowercased() == "audio" ? "Finished listening" : "Finished watching"
        }
    }

    // MARK: media window (over the content)

    private func mediaWindow(_ url: URL) -> some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack {
                HStack {
                    Button { player = nil } label: {
                        Icon(.x, size: 18, color: .white)
                            .frame(width: 38, height: 38).background(Color.white.opacity(0.18), in: Circle())
                    }
                    .buttonStyle(.pressable)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 20).padding(.top, 12)
                Spacer(minLength: 0)
                Button { openURL(url) } label: {
                    HStack(spacing: 8) {
                        Icon(.play, size: 18, color: PL.navy)
                        Text("Start playing").font(.inter(16, .bold)).foregroundStyle(PL.navy)
                    }
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(Color.white, in: Capsule())
                }
                .buttonStyle(.pressable)
                .padding(.horizontal, 20).padding(.bottom, 40)
            }
        }
    }
}

// MARK: - Reflection box (lives at the bottom of the Prayer part)

/// The day's reflection, saved to the plan-day reflection endpoint (upsert).
/// Pre-fills on return visits; the button flips to "Update".
private struct PartReflectionBox: View {
    let planId: String
    let dayNumber: Int

    @Environment(\.readerPalette) private var pal
    @State private var text = ""
    @State private var saved: PlanDayReflection?
    @State private var saving = false
    @State private var justSaved = false
    /// Why the last save did not land — shown under the button, in words.
    /// A silent failure read as "Update does nothing" (owner report,
    /// 2026-09-04); the box now always says what happened.
    @State private var error: String?
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("REFLECTION").font(.inter(11, .bold)).kerning(1.6).foregroundStyle(pal.goldDeep)
                Spacer(minLength: 0)
                if justSaved {
                    HStack(spacing: 4) {
                        Icon(.check, size: 14, color: Color(hex: 0x16A34A))
                        Text("Saved").font(.inter(11, .bold)).foregroundStyle(Color(hex: 0x15803D))
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            Text("What is God showing you today?")
                .font(.fraunces(16, .regular)).italic().foregroundStyle(pal.ink)
                .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("Write it down while it's fresh…").font(.inter(13)).foregroundStyle(pal.inkDim)
                        .padding(.horizontal, 14).padding(.vertical, 12)
                }
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(4...10)
                    .font(.inter(13)).foregroundStyle(pal.ink).tint(pal.gold)
                    .focused($focused)
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            // Save from the keyboard itself: the button below
                            // can sit under the keyboard while typing.
                            Button(saved == nil ? "Save" : "Update") {
                                focused = false
                                Task { await save() }
                            }
                            .font(.inter(14, .bold)).foregroundStyle(pal.goldDeep)
                            .disabled(trimmed.isEmpty || saving)
                            Button("Done") { focused = false }
                                .font(.inter(14, .semibold)).foregroundStyle(pal.goldDeep)
                        }
                    }
            }
            .background(pal.bg, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(pal.border, lineWidth: 1))
            Button {
                Haptics.action()
                Task { await save() }
            } label: {
                HStack(spacing: 6) {
                    if saving { ProgressView().tint(pal.goldDeep) }
                    else if justSaved { Icon(.check, size: 14, color: pal.goldDeep) }
                    else { Icon(.pencil, size: 14, color: pal.goldDeep) }
                    Text(justSaved ? "Saved" : (saved == nil ? "Save reflection" : "Update"))
                        .font(.inter(12, .bold)).foregroundStyle(pal.goldDeep)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(pal.gold.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(pal.gold.opacity(0.3), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .disabled(trimmed.isEmpty || saving)
            .opacity(trimmed.isEmpty ? 0.5 : 1)
            if let error {
                Text(error)
                    .font(.inter(12, .medium)).foregroundStyle(Nuru.danger)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .background(pal.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(pal.border, lineWidth: 1))
        .task {
            guard let row = try? await MemberAPI.planDayReflection(planId: planId, dayNumber: dayNumber) else { return }
            saved = row
            if text.isEmpty { text = row.body }
        }
    }

    private func save() async {
        let body = String(trimmed.prefix(4000))
        guard !body.isEmpty, !saving else { return }
        saving = true
        withAnimation(.easeOut(duration: 0.2)) { error = nil }
        do {
            let row = try await MemberAPI.savePlanDayReflection(planId: planId, dayNumber: dayNumber, body: body)
            saved = row
            // The server's copy is what the next visit will show — mirror it
            // now, so what you see after "Update" is exactly what was kept.
            if !row.body.isEmpty { text = row.body }
            Haptics.success()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { justSaved = true }
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                withAnimation(.easeOut(duration: 0.25)) { justSaved = false }
            }
        } catch {
            Haptics.error()
            withAnimation(.easeOut(duration: 0.2)) {
                // §4's words — offline only when the phone is, never raw text.
                self.error = NuruStateCopy.failureLine("Couldn't save your reflection.", error)
            }
        }
        saving = false
    }
}

// MARK: - Talk it Over — the shared plan-day conversation page

/// The community page for a plan day: the day's question in the serif prompt
/// voice, the family's responses (avatar · name · time · body · encouragement
/// heart), and a pinned composer. Everyone walking the plan meets here.
struct TalkItOverView: View {
    let route: TalkRoute

    @EnvironmentObject private var tabs: TabRouter
    @Environment(\.dismiss) private var dismiss
    @State private var posts: [TalkPost] = []
    @State private var loading = true
    @State private var draft = ""
    @State private var posting = false
    /// Why the last post didn't send — §4's words, with the draft kept.
    @State private var postError: String?
    /// The server has acked Talk it Over's completion on this page.
    @State private var talkSealed = false
    /// The gold button is waiting on the server (§7.4 #2).
    @State private var sealing = false
    /// Why the server didn't record it — above the gold button.
    @State private var sealError: String?
    @State private var aiBusy = false
    @FocusState private var composing: Bool
    /// How far the composer must rise to clear the keyboard, taken from the
    /// keyboard's own frame. On iOS 26 the keyboard no longer reaches this
    /// pushed page's safe area (owner screenshot, 2026-09-04: the composer
    /// sat under the glass keyboard), so the page ignores the keyboard region
    /// entirely and pads by exactly the overlap itself.
    @State private var keyboardInset: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        promptCard
                        if loading && posts.isEmpty {
                            HStack { Spacer(); ProgressView().tint(PL.gold); Spacer() }
                                .padding(.vertical, 40)
                        } else if posts.isEmpty {
                            emptyState
                        } else {
                            ForEach(posts) { post in
                                TalkPostRow(post: post) { toggleLike(post) }
                                    .id(post.postId)
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 16)
                }
                .scrollDismissesKeyboard(.interactively)
                // The composer rides in the scroll's bottom safe-area inset, the
                // same way ChatThreadView pins its own: keyboard avoidance is then
                // automatic and the bar floats directly on top of the keyboard.
                // It must NOT be a plain sibling in a ZStack that also holds a
                // .ignoresSafeArea() background — a ZStack sizes to its LARGEST
                // child, so the keyboard-ignoring Color inflates the stack to the
                // full screen and the composer lays out UNDER the keyboard.
                // (Same ornament lesson as the Home card fusion, ios#72.)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    VStack(spacing: 0) {
                        composer
                        // The same gold "seal it" button every other part ends
                        // with — hidden while typing so the composer gets the room.
                        if !composing { doneBar }
                    }
                    .padding(.bottom, keyboardInset)
                    .background(Color.white)
                }
                .onChange(of: posts.count) { _, _ in
                    if let last = posts.last {
                        withAnimation(.easeOut(duration: 0.3)) { proxy.scrollTo(last.postId, anchor: .bottom) }
                    }
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .background(PL.cream.ignoresSafeArea())
        .animation(.easeInOut(duration: 0.2), value: composing)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { n in
            updateKeyboardInset(n)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) { keyboardInset = 0 }
        }
        // NOT .ignoresSafeArea(.top) — that buried the back-arrow row under the
        // status bar (the header's own background still bleeds navy to the top).
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        // Deliberately NO auto-marking here: the back arrow leaves the day
        // untouched (owner ask — sometimes you just want to look and leave).
        // Posting, or the gold "I've talked it over", seals the part.
        .onAppear { tabs.chromeHidden = true }
        .task { await load() }
        .refreshable { await load() }
    }

    /// The keyboard's end frame → the part of it that overlaps this page,
    /// less the home-indicator inset the safe-area inset already clears.
    private func updateKeyboardInset(_ n: Notification) {
        guard let end = (n.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
        let screen = UIScreen.main.bounds
        let overlap = max(0, screen.maxY - end.minY)
        let bottomSafe = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }
            .first?.safeAreaInsets.bottom ?? 0
        let duration = (n.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double) ?? 0.25
        withAnimation(.easeOut(duration: max(0.1, duration))) {
            keyboardInset = overlap > 0 ? max(0, overlap - bottomSafe) : 0
        }
    }

    private func load() async {
        if let rows = try? await MemberAPI.talkList(planId: route.planId, dayNumber: route.dayNumber) {
            posts = rows
        }
        loading = false
    }

    private func toggleLike(_ post: TalkPost) {
        Haptics.love()
        Task {
            guard let r = try? await MemberAPI.talkLike(post.postId),
                  let i = posts.firstIndex(where: { $0.postId == post.postId }) else { return }
            posts[i] = TalkPost(postId: post.postId, dayNumber: post.dayNumber, body: post.body,
                                createdAt: post.createdAt, userId: post.userId, name: post.name,
                                avatarUrl: post.avatarUrl, likeCount: r.likeCount, liked: r.liked)
        }
    }

    private func send() {
        let body = String(draft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(2000))
        guard !body.isEmpty, !posting else { return }
        posting = true
        Task {
            do {
                let row = try await MemberAPI.talkPost(planId: route.planId, dayNumber: route.dayNumber, body: body)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { posts.append(row) }
                draft = ""
                composing = false
                postError = nil
                Haptics.success()
                // Posting is talking it over: the server completes the part
                // with the post (§7.4 #1). This asks for its ack, so the hub
                // ticks and a sealed day is announced; if it doesn't answer,
                // the gold button finishes it — and says so if it can't.
                Task { await completeTalk() }
            } catch {
                Haptics.error()
                // The draft is kept; say why it's still here (§4's words, as
                // Android: "Couldn't send." and the reason).
                postError = "Couldn't send. " + NuruStateCopy.failure(error).sentence
            }
            posting = false
        }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Icon(.arrowLeft, size: 18, color: .white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.10), in: Circle())
                        .overlay(Circle().stroke(Color.white.opacity(0.15), lineWidth: 1))
                }
                .buttonStyle(.pressable)
                Spacer(minLength: 8)
                Text("DAY \(route.dayNumber) · \(route.planTitle.uppercased())")
                    .font(.inter(11, .bold)).kerning(1.6).foregroundStyle(PL.gold)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Color.clear.frame(width: 36, height: 36)
            }
            HStack(spacing: 12) {
                Icon(.users, size: 18, color: PL.gold)
                    .frame(width: 40, height: 40)
                    .background(PL.gold.opacity(0.16), in: Circle())
                    .overlay(Circle().stroke(PL.gold.opacity(0.4), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Talk it Over").font(.fraunces(26, .medium)).kerning(-0.7).foregroundStyle(.white)
                    Text(posts.isEmpty ? "Be the first to respond" : "\(posts.count) response\(posts.count == 1 ? "" : "s")")
                        .font(.inter(11)).foregroundStyle(.white.opacity(0.65))
                }
                Spacer(minLength: 0)
                participantStack
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 16)
        .background(
            LinearGradient(colors: [PL.navy, PL.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                .clipShape(.rect(bottomLeadingRadius: 22, bottomTrailingRadius: 22))
                .ignoresSafeArea(edges: .top)
        )
    }

    /// Overlapping avatars of the people in today's conversation.
    private var participantStack: some View {
        let people = Array(Dictionary(grouping: posts, by: \.userId).values.compactMap(\.first).prefix(4))
        return HStack(spacing: -8) {
            ForEach(people) { p in
                TalkAvatar(name: p.name, url: p.avatarUrl, size: 26)
                    .overlay(Circle().stroke(PL.navy, lineWidth: 2))
            }
        }
    }

    // MARK: prompt + empty state

    private var promptLines: [String] {
        route.prompt.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("—") ? String($0.dropFirst()).trimmingCharacters(in: .whitespaces) : $0 }
    }

    private var promptCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(promptLines.count == 1 ? "TODAY'S QUESTION" : "TODAY'S QUESTIONS")
                .font(.inter(11, .bold)).kerning(1.6).foregroundStyle(PL.goldDeep)
            ForEach(Array(promptLines.enumerated()), id: \.offset) { _, q in
                Text(q)
                    .font(.fraunces(16, .regular)).italic().foregroundStyle(PL.navy)
                    .nuruLineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(PL.highlight, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.gold.opacity(0.3), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Icon(.messageCircle, size: 24, color: PL.gold)
            Text("No responses yet").font(.inter(13, .semibold)).foregroundStyle(PL.navy)
            Text("Share what God is showing you — your voice encourages the family.")
                .font(.inter(12)).foregroundStyle(PL.ink3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 44)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.border, lineWidth: 1))
    }

    // MARK: composer (pinned)

    private var composer: some View {
        VStack(alignment: .leading, spacing: 6) {
        if let postError {
            Text(postError)
                .font(.inter(11, .medium)).foregroundStyle(Nuru.danger)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        HStack(spacing: 10) {
            ZStack(alignment: .leading) {
                if draft.isEmpty {
                    Text("Write your response…").font(.inter(13)).foregroundStyle(PL.ink3)
                        .padding(.horizontal, 14)
                }
                TextField("", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.inter(13)).foregroundStyle(PL.navy).tint(PL.gold)
                    .focused($composing)
                    .padding(.horizontal, 14)
            }
            .padding(.vertical, 10)
            .background(PL.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(PL.border, lineWidth: 1))
            // AI compose help: empty box → an honest first-person starter from
            // today's questions; with your words → they come back polished, in
            // YOUR voice. Always editable — the member presses send themselves.
            Button {
                guard !aiBusy else { return }
                Haptics.tap()
                aiBusy = true
                Task {
                    let mine = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let s = try? await MemberAPI.talkAssist(planId: route.planId,
                                                               dayNumber: route.dayNumber,
                                                               draft: mine.isEmpty ? nil : mine) {
                        withAnimation(.easeInOut(duration: 0.2)) { draft = s }
                    } else {
                        Haptics.error()
                    }
                    aiBusy = false
                }
            } label: {
                Group {
                    if aiBusy { ProgressView().tint(PL.goldDeep) }
                    else {
                        Image(systemName: "sparkles")
                            .font(.symbol(15, weight: .semibold))
                            .foregroundStyle(PL.goldDeep)
                    }
                }
                .frame(width: 42, height: 42)
                .background(PL.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(PL.gold.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel(draft.isEmpty ? "Compose with AI" : "Polish my words with AI")
            Button { send() } label: {
                Group {
                    if posting { ProgressView().tint(PL.navy) }
                    else { Icon(.send, size: 18, color: PL.navy) }
                }
                .frame(width: 42, height: 42)
                .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.pressable)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || posting)
            .opacity(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
        }
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 8)
        .background(Color.white.overlay(alignment: .top) { Rectangle().fill(PL.border).frame(height: 1) })
    }

    // MARK: done — seal the part and return to the day hub

    /// Talk it Over is a required part of the day (owner, 2026-10-05),
    /// completed by posting in the conversation OR by the gold "I've talked
    /// it over" — nobody is forced to post. Opening the page never completes
    /// it. The server's ack ticks the hub's row and, when this was the day's
    /// last part, seals the day — the same broadcast as every other part's
    /// finish. Returns why it failed, or nil once the part stands.
    @discardableResult
    private func completeTalk() async -> Error? {
        guard let sid = route.talkSegmentId, !route.talkDone, !talkSealed else { return nil }
        do {
            let ack = try await MemberAPI.completePlanSegment(sid)
            talkSealed = true
            NotificationCenter.default.post(name: .nuruPlanPartDone, object: sid)
            PlanDayUnlockAck.announce(ack, planId: route.planId)
            return nil
        } catch {
            return error
        }
    }

    /// The page ends with the SAME gold button every other part has — one
    /// consistent gesture: read/respond, press gold, back at the hub, ticked.
    /// No success before the server says so (§7.4 #2, as Android): the button
    /// shows progress while it waits; on the ack, the haptic and back to the
    /// day; on a refusal or no answer the member stays, told why above it.
    private var doneBar: some View {
        VStack(spacing: 8) {
            if route.talkDone || talkSealed {
                // Already done (the walk's B4): say so, and a quiet way back —
                // no gold "I've talked it over" asking again for a part the day
                // page already shows as completed.
                Text(TalkWords.done).font(.inter(13, .semibold)).foregroundStyle(Nuru.successText)
                Button { Haptics.tap(); dismiss() } label: {
                    Text(TalkWords.back(day: route.dayNumber)).font(.inter(14, .semibold)).foregroundStyle(PL.navy)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: Nuru.R.button, style: .continuous).stroke(PL.border, lineWidth: 1))
                }
                .buttonStyle(.pressable)
            } else {
            // Above the button (both apps): read before the retry tap.
            if let sealError {
                Text(sealError)
                    .font(.inter(12, .medium)).foregroundStyle(Color(hex: 0xB91C1C))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
            Button {
                guard !sealing else { return }
                if route.talkDone || talkSealed {
                    Haptics.tap(); dismiss(); return
                }
                sealing = true
                withAnimation(.easeOut(duration: 0.2)) { sealError = nil }
                Task {
                    let failed = await completeTalk()
                    sealing = false
                    if let failed {
                        withAnimation(.easeOut(duration: 0.2)) { sealError = NuruStateCopy.saveFailureLine(failed) }
                        Haptics.error()
                    } else {
                        Haptics.success()
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if sealing { ProgressView().tint(PL.navy) }
                    else { Icon(.check, size: 14, color: PL.navy) }
                    Text("I've talked it over").font(.inter(14, .bold)).foregroundStyle(PL.navy)
                }
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: PL.gold.opacity(0.4), radius: 10, y: 6)
            }
            .buttonStyle(.pressable)
            .disabled(sealing)
            }
        }
        .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 10)
        .background(Color.white)
    }
}

/// Talk it Over's words once its part is done (the walk's B4).
enum TalkWords {
    static let done = "Completed ✓"
    static func back(day: Int) -> String { "Back to Day \(day)" }
}

/// One response row — avatar, name, time-ago, body, encouragement heart.
private struct TalkPostRow: View {
    let post: TalkPost
    let onLike: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TalkAvatar(name: post.name, url: post.avatarUrl, size: 36)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(post.name).font(.inter(13, .semibold)).foregroundStyle(PL.navy).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(TalkTime.ago(post.createdAt)).font(.inter(11)).foregroundStyle(PL.ink3)
                }
                Text(post.body)
                    .font(.inter(13)).foregroundStyle(PL.bodyInk).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onLike) {
                    HStack(spacing: 5) {
                        Image(systemName: post.liked ? "heart.fill" : "heart")
                            .font(.symbol(13))
                            .foregroundStyle(post.liked ? PL.gold : PL.ink3)
                        if post.likeCount > 0 {
                            Text("\(post.likeCount)").font(.inter(11, .semibold))
                                .foregroundStyle(post.liked ? PL.goldDeep : PL.ink3)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: post.liked)
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(PL.border, lineWidth: 1))
    }
}

/// Avatar with warm-initials fallback.
private struct TalkAvatar: View {
    let name: String
    let url: String?
    let size: CGFloat
    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let s = parts.compactMap { $0.first.map(String.init) }.joined().uppercased()
        return s.isEmpty ? "?" : s
    }
    var body: some View {
        Group {
            if let u = url.flatMap(URL.init), !(url ?? "").isEmpty {
                Color.clear.overlay {
                    CachedAsyncImage(url: u) { phase in
                        if let img = phase.image { img.resizable().scaledToFill() }
                        else { fallback }
                    }
                }
                .clipShape(Circle())
            } else {
                fallback.clipShape(Circle())
            }
        }
        .frame(width: size, height: size)
    }
    private var fallback: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [PL.gold, PL.ctaDeep], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text(initials).font(.inter(NuruType.snap(size * 0.34), .bold)).foregroundStyle(.white)
        }
    }
}

/// Compact relative time for talk rows ("2h", "3d", "1w").
private enum TalkTime {
    static func ago(_ iso: String) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) ?? Date()
        let s = max(0, Date().timeIntervalSince(date))
        if s < 60 { return "now" }
        if s < 3600 { return "\(Int(s / 60))m" }
        if s < 86400 { return "\(Int(s / 3600))h" }
        if s < 604800 { return "\(Int(s / 86400))d" }
        return "\(Int(s / 604800))w"
    }
}
