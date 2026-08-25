// The liturgy Home + celebrations rail (intelligence Phase 4).
//   • HomeLiturgyCard — Home breathes with the hours: the current part's prayer
//     line (morning/midday/evening/night), coloured by the church season.
//     Self-loading; collapses to nothing until the line arrives. Gives the
//     hour a VOICE (feat/liturgy-audio) — a tap-only listen control reads the
//     line + Scripture aloud on-device (LiturgyVoice.swift); never auto-plays.
//   • CelebrationsRail — the congregation's recent milestones (server-detected,
//     Phase 4 moments) with one-tap blessings (🙌 ❤️ 🔥), optimistic updates.
import SwiftUI

struct HomeLiturgyCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject private var tabs: TabRouter
    @EnvironmentObject private var auth: AuthStore
    @State private var lit: HomeLiturgy?
    @StateObject private var voice = LiturgyVoiceEngine()
    @State private var showRecordingsManager = false

    /// Admin/SuperAdmin only — narrower than the Instructor+ ladder used for
    /// module voice notes elsewhere (ModuleView.swift's `canLeaveVoiceNote`);
    /// the backend gates admin/liturgy/recordings with requireRole("Admin").
    private var canManageRecordings: Bool {
        ["Admin", "SuperAdmin"].contains(auth.profile?.role ?? "")
    }

    private func partLabel(_ p: String) -> String {
        switch p {
        case "morning": return "MORNING"
        case "midday": return "MIDDAY"
        case "evening": return "EVENING"
        default: return "NIGHT"
        }
    }

    private func partEmoji(_ p: String) -> String {
        switch p {
        case "morning": return "🌅"
        case "midday": return "☀️"
        case "evening": return "🌆"
        default: return "🌙"
        }
    }

    var body: some View {
        Group {
            if lit == nil {
                // Zero-height anchor: keeps this view INSTALLED while empty so
                // .task actually runs (a bare empty Group never appears, so its
                // task never fires — the card would stay dead forever).
                Color.clear.frame(height: 0)
            }
            if let lit {
                // Scripture First (owner's pick, 2026-08-25 — option 4 of the
                // five-way design board): the Word is the headline, set large
                // under a hanging gold quotation mark. The composed statement
                // becomes the small golden line that frames it, and the
                // explanation lands the verse beneath a hairline. The hour's
                // photograph retired from this card — the verse carries it.
                // One layout for every state; `scriptureRef == nil` marks a
                // PERSONAL composition (the server nulls it then), which earns
                // the "Why this word today" preface.
                VStack(alignment: .leading, spacing: 0) {
                    litKicker(lit, onPhoto: false)
                    Text(lit.line)
                        .font(.inter(11.5, .semibold)).foregroundStyle(Color(hex: 0xA8861C))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                    if let vl = lit.verseLine, !vl.text.isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("“")
                                .font(.fraunces(44, .semibold)).foregroundStyle(Nuru.gold)
                                .offset(y: 2)
                                .accessibilityHidden(true)
                            Text(vl.text)
                                .font(.fraunces(19.5)).foregroundStyle(Nuru.navyDeep)
                                .lineSpacing(5)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.top, 7)
                        }
                        .padding(.top, 4)
                        Text(vl.reference.uppercased())
                            .font(.inter(9.5, .bold)).kerning(1.4)
                            .foregroundStyle(Color(hex: 0xA8861C))
                            .padding(.top, 10)
                    } else if let ref = lit.scriptureRef {
                        Text(ref.uppercased())
                            .font(.inter(9.5, .bold)).kerning(1.4)
                            .foregroundStyle(Color(hex: 0xA8861C))
                            .padding(.top, 10)
                    }
                    if let charge = lit.charge, !charge.isEmpty {
                        Rectangle().fill(Nuru.border)
                            .frame(height: 1)
                            .padding(.top, 14)
                        Group {
                            if lit.scriptureRef == nil {
                                Text("Why this word today: ")
                                    .font(.inter(12.5, .semibold)).foregroundColor(Nuru.navyDeep)
                                + Text(charge)
                                    .font(.inter(12.5)).foregroundColor(Nuru.ink600)
                            } else {
                                Text(charge)
                                    .font(.inter(12.5)).foregroundColor(Nuru.ink600)
                            }
                        }
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 12)
                    }
                    pastorVoiceButton(lit)
                        .padding(.top, 12)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Nuru.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Nuru.border, lineWidth: 1)
                )
                .nuruShadow()
            }
        }
        // A decline toast (VoiceOver running / currently broadcasting / a
        // session hiccup) — floats over the card without touching its
        // caption-grown height, auto-dismisses itself.
        .overlay(alignment: .top) {
            if let reason = voice.declineReason {
                Text(reason)
                    .font(.inter(11, .semibold)).foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.black.opacity(0.8), in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: reason) {
                        try? await Task.sleep(nanoseconds: 3_500_000_000)
                        guard !Task.isCancelled else { return }
                        withAnimation { voice.declineReason = nil }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: voice.declineReason)
        .onChange(of: voice.declineReason) { _, reason in if reason != nil { Haptics.error() } }
        .task {
            voice.stop()   // a fresh fetch replaces the text — never keep reading the old one
            lit = try? await MemberAPI.homeLiturgy()
        }
        .onChange(of: scenePhase) { _, phase in
            // The tab shell keeps Home alive for the whole session — without
            // this an overnight-resident app shows yesterday's card forever.
            if phase == .active {
                Task { voice.stop(); lit = try? await MemberAPI.homeLiturgy() }
            } else {
                voice.stop()   // backgrounding/locking — never keep talking off-screen
            }
        }
        // Switching tabs never removes this view (RootView keeps every
        // loaded tab mounted at opacity 0 — see RootView.body) so
        // `.onDisappear` alone would NOT catch "the member left Home for
        // Pathway/Plans/You/Live". This is the signal that does.
        .onChange(of: tabs.selected) { _, selected in
            if selected != .home { voice.stop() }
        }
        // Belt-and-suspenders for any OTHER way this view genuinely leaves
        // the hierarchy (it normally won't, per the note above).
        .onDisappear { voice.stop() }
        .sheet(isPresented: $showRecordingsManager) {
            LiturgyRecordingsSheet()
        }
    }

    /// The hour + brand row — shared by the tableau (top overlay) and the
    /// classic offline card. Gold hour label, then the Nuru Pathway lockup.
    @ViewBuilder
    private func litKicker(_ lit: HomeLiturgy, onPhoto: Bool = true) -> some View {
        HStack(spacing: 7) {
            Text(partEmoji(lit.part)).font(.system(size: 15))
            Text(lit.isSunday ? "SUNDAY · \(partLabel(lit.part))" : "\(partLabel(lit.part)) · \(lit.season.uppercased())")
                .font(.inter(10.5, .bold)).kerning(1.6)
                .foregroundStyle(onPhoto ? Color(hex: 0xF2DDA0) : Color(hex: 0xA8861C))
                .shadow(color: .black.opacity(onPhoto ? 0.4 : 0), radius: 2, y: 1)
                .lineLimit(1)
            BrandMark(size: 14)
            Text("Nuru Pathway")
                .font(.inter(10.5, .semibold)).foregroundStyle(onPhoto ? .white : Nuru.navy)
                .shadow(color: .black.opacity(onPhoto ? 0.45 : 0), radius: 2, y: 1)
                .lineLimit(1)
            Icon(.badgeCheck, size: 11, color: onPhoto ? Color(hex: 0xF2DDA0) : Color(hex: 0xA8861C))
            Spacer(minLength: 0)
            if canManageRecordings { recordManageButton }
            listenButton(lit)
        }
    }

    // MARK: - Record-your-voice affordance (Admin/SuperAdmin only)

    /// A small, unobtrusive control next to the listen button — opens the
    /// full 7-band recorder list (LiturgyRecorder.swift). Never shown to a
    /// member; never a badge/counter (see that file's header for why).
    private var recordManageButton: some View {
        Button {
            Haptics.tap()
            showRecordingsManager = true
        } label: {
            Icon(.mic, size: 12, color: Color(hex: 0xF2DDA0))
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.3), in: Circle())
                .overlay(Circle().stroke(Color(hex: 0xF2DDA0).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel("Manage your recorded liturgy readings")
    }

    // MARK: - Listen control (feat/liturgy-audio)

    /// What the voice engine should say for this liturgy — mirrors exactly
    /// what the card SHOWS (line → charge → verse-line-or-scriptureRef).
    /// `recordedUrlString: lit.recordedAudioUrl` — the pastor's own voice for
    /// this band when he's recorded one; null (most bands, most of the time —
    /// mixed coverage is permanent, not a gap) falls back to synthesis via
    /// `LiturgyAudioSource.preferred` (see LiturgyVoiceLogic.swift).
    private func spokenSource(for lit: HomeLiturgy) -> LiturgyAudioSource {
        // Deliberately NOT `.preferred(recordedUrlString:…)`. Listen always
        // synthesises TODAY'S TEXT, because the liturgy is recomposed daily
        // (new spine, new memory) while a recording is a STANDING per-band
        // asset the pastor replaces occasionally. Letting the recording
        // silently take over this button meant a member read one thing on the
        // card and heard the pastor say something else — which reads as a bug,
        // not a blessing. His voice now has its own control below.
        .synthesized(LiturgySpeechText.segments(
            line: lit.line, charge: lit.charge,
            verseLineText: lit.verseLine?.text, verseLineReference: lit.verseLine?.reference,
            scriptureRef: lit.scriptureRef))
    }

    /// The pastor's own standing word for THIS hour — a separate thing from
    /// the day's liturgy, and labelled as such. Absent for most bands most of
    /// the time; mixed coverage is permanent and normal, so there is no empty
    /// state, no "not yet recorded", nothing to complete.
    @ViewBuilder
    private func pastorVoiceButton(_ lit: HomeLiturgy) -> some View {
        if let raw = lit.recordedAudioUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty, let url = URL(string: raw) {
            Button {
                Haptics.tap()
                voice.toggle(.recorded(url))
            } label: {
                HStack(spacing: 6) {
                    Icon(.volume2, size: 11, color: Color(hex: 0xF2DDA0))
                    Text("A word for this hour — Pastor Moses")
                        .font(.inter(11, .semibold))
                        .foregroundStyle(Color(hex: 0xF2DDA0))
                    if let secs = lit.recordedAudioDurationSec, secs > 0 {
                        Text("\(secs)s")
                            .font(.inter(10))
                            .foregroundStyle(Color(hex: 0xF2DDA0).opacity(0.7))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.3), in: Capsule())
                .overlay(Capsule().stroke(Color(hex: 0xF2DDA0).opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .accessibilityLabel("Play Pastor Moses's own word for this hour")
            .accessibilityHint("His recorded blessing for this time of day. Separate from the written liturgy above.")
        }
    }

    private var listenAccessibilityLabel: String {
        switch voice.state {
        case .idle: return "Listen to today's liturgy read aloud"
        case .playing: return "Pause the liturgy reading"
        case .paused: return "Resume the liturgy reading"
        }
    }

    /// Speaker = "tap to listen" (idle); pause/play mirror VoiceMessageBubble's
    /// own convention elsewhere in the app once playback is actually underway,
    /// so a mid-reading pause reads as resumable rather than as a reset.
    private var listenIcon: Lucide {
        switch voice.state {
        case .idle: return .volume2
        case .playing: return .pause
        case .paused: return .play
        }
    }

    /// A small gold-on-navy circular toggle — never auto-plays, tap only.
    private func listenButton(_ lit: HomeLiturgy) -> some View {
        Button {
            Haptics.tap()
            voice.toggle(spokenSource(for: lit))
        } label: {
            Icon(listenIcon, size: 12, color: Color(hex: 0xF2DDA0))
                .frame(width: 24, height: 24)
                .background(Color.black.opacity(0.3), in: Circle())
                .overlay(Circle().stroke(Color(hex: 0xF2DDA0).opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.pressable)
        .accessibilityLabel(listenAccessibilityLabel)
        .accessibilityHint("Reads the words shown above aloud, on this device.")
    }
}

struct CelebrationsRail: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var moments: [CommunityMoment] = []

    var body: some View {
        Group {
            if moments.isEmpty {
                Color.clear.frame(height: 0) // install-anchor — see HomeLiturgyCard
            }
            if !moments.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    // No internal horizontal padding: the Home feed already
                    // pads every section 16pt — the rail's extra S.screen inset
                    // double-padded it 20pt deeper than its neighbours (owner
                    // screenshot, 2026-08-25: "these cards are not aligned").
                    HStack(spacing: 6) {
                        Text("🎉").font(.system(size: 13))
                        Text("CELEBRATE THE FAMILY")
                            .font(.inter(10.5, .bold)).kerning(1.6)
                            .foregroundStyle(Nuru.muted)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(moments) { m in
                                MomentCard(moment: m) { kind in
                                    bless(m, kind: kind)
                                }
                            }
                        }
                    }
                }
            }
        }
        .task { moments = (try? await MemberAPI.communityMoments()) ?? [] }
        .onChange(of: scenePhase) { _, phase in
            // The tab shell keeps Home alive for the whole session — without
            // this an overnight-resident app shows yesterday's card forever.
            if phase == .active { Task { moments = (try? await MemberAPI.communityMoments()) ?? [] } }
        }
    }

    private func bless(_ m: CommunityMoment, kind: String) {
        guard let idx = moments.firstIndex(where: { $0.momentId == m.momentId }) else { return }
        Haptics.action()
        var updated = moments[idx]
        // Optimistic: move my blessing to the tapped kind.
        if let prev = updated.myBlessing {
            if prev == "amen" { updated.amenCount -= 1 }
            if prev == "heart" { updated.heartCount -= 1 }
            if prev == "fire" { updated.fireCount -= 1 }
        }
        if kind == "amen" { updated.amenCount += 1 }
        if kind == "heart" { updated.heartCount += 1 }
        if kind == "fire" { updated.fireCount += 1 }
        updated.myBlessing = kind
        moments[idx] = updated
        Task { _ = try? await MemberAPI.bless(m.momentId, kind: kind) }
    }
}

private struct MomentCard: View {
    let moment: CommunityMoment
    let onBless: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Avatar(url: moment.avatarUrl, name: moment.fullName, size: 30)
                Text(moment.fullName.split(separator: " ").first.map(String.init) ?? moment.fullName)
                    .font(.inter(13, .bold)).foregroundStyle(Nuru.ink)
                    .lineLimit(1)
            }
            Text(moment.title)
                .font(.fraunces(15)).foregroundStyle(Nuru.navyMid)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .topLeading)
            HStack(spacing: 6) {
                blessChip("🙌", "amen", moment.amenCount)
                blessChip("❤️", "heart", moment.heartCount)
                blessChip("🔥", "fire", moment.fireCount)
            }
        }
        .padding(14)
        .frame(width: 210, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(Nuru.border, lineWidth: 1))
    }

    private func blessChip(_ emoji: String, _ kind: String, _ count: Int) -> some View {
        let mine = moment.myBlessing == kind
        return Button { onBless(kind) } label: {
            HStack(spacing: 4) {
                Text(emoji).font(.system(size: 12))
                if count > 0 {
                    Text("\(count)").font(.inter(11, .bold))
                        .foregroundStyle(mine ? Nuru.navy : Nuru.muted)
                        .contentTransition(.numericText())   // ticks up, never snaps
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: count)
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(mine ? Color(hex: 0xE8CA6C).opacity(0.35) : Nuru.tintBlue, in: Capsule())
            .overlay(Capsule().stroke(mine ? Color(hex: 0xC9A227).opacity(0.6) : Color.clear, lineWidth: 1))
        }
        .buttonStyle(.pressable)
    }
}
