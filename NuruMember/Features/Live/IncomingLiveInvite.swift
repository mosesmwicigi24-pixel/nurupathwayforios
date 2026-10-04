// Nuru Live — the RINGING guest invite. The owner asked (2026-09-28) for calls
// to "ring and vibrate"; there is no calling feature, so the Live guest invite
// rings: a broadcaster asking a member onto the stage of their stream.
//
// A `live_guest_invite` push that lands while the app is open (LocalNotifier's
// willPresent), or one the member taps inside its 30 s (RootView), opens this
// full-screen incoming invite OVER everything — in its own window, so a Live
// player, the radio or a sheet already on screen can't hide it. It shows the
// stream's name and the invite's own words, rings (every 4 s) and buzzes
// (every 1.5 s) for up to 30 s, then dismisses itself.
//   • Join — the stream's player, which accepts through its own invite flow
//     (LiveViewerPlayerView.respondToInvite — the invite card's Accept) the
//     moment its pulse shows the invite still open. A player already on that
//     stream accepts in place.
//   • Not now — declines (POST /live/streams/{id}/guests/respond {accept:false}).
//   • No answer in 30 s — it goes away; the invite stays open on the server,
//     and the player's invite card can still answer it.
// An answered invite doesn't ring again when its other copy (the push, the
// inbox's) lands a moment later.
// The ring is the push's own ring, one 1.2 s ring every 4 s (nuru_ring_once.caf
// — a system sound can't be reliably cut off mid-play, so the app rings in
// single rings it simply stops scheduling when the member answers), through
// System Sound Services: the ringer/silent switch and the ringer volume rule
// it, and the app's own audio session (Radio, a Live player, a guest's WebRTC
// call) is never touched. A member who muted Sound and vibration gets the
// same screen, silently — no ring and no buzz.
import AudioToolbox
import os
import SwiftUI
import UIKit

private let inviteLogger = Logger(subsystem: "org.nuruplace.member", category: "IncomingLiveInvite")

/// One ringing invite, read off its push (or its inbox copy).
struct IncomingLiveInvite: Equatable, Identifiable {
    let streamId: String
    /// The stream's name — a ring push's `title`.
    let streamTitle: String
    let heading: String
    let message: String
    /// The 30 s run from here.
    let startedAt: Date
    /// Sound and vibration are off: the same screen, no ring, no buzz.
    let silent: Bool
    /// The inbox row it came from, if any — answering it reads it.
    let notificationId: String?

    var id: String { streamId }

    /// Nil without a stream — there is nothing to join.
    init?(push: NuruPush, now: Date = Date()) {
        guard let streamId = push.streamId else { return nil }
        self.streamId = streamId
        streamTitle = push.title ?? "Nuru Live"
        heading = push.alertTitle ?? LiveInviteCopy.heading
        message = push.alertBody ?? LiveInviteCopy.message(streamTitle: push.title)
        startedAt = push.ringStartedAt ?? now
        silent = !push.soundOn
        notificationId = push.notificationId
    }
}

// MARK: - The ring

/// Rings (one 1.2 s ring every 4 s) and buzzes (every 1.5 s) until `stop()`
/// or the window closes. System sounds obey the ringer/silent switch on
/// their own; after `stop()` at most the ring already sounding finishes.
@MainActor
private final class LiveInviteRinger {
    private var soundId: SystemSoundID = 0
    private var ringTask: Task<Void, Never>?
    private var buzzTask: Task<Void, Never>?

    func start(silent: Bool, remaining: TimeInterval) {
        stop()
        guard !silent, remaining > 0 else { return }
        if let url = Bundle.main.url(forResource: "nuru_ring_once", withExtension: "caf"),
           AudioServicesCreateSystemSoundID(url as CFURL, &soundId) == kAudioServicesNoError {
            let id = soundId
            ringTask = Self.schedule(NuruRing.ringOffsets(remaining: remaining)) { AudioServicesPlaySystemSound(id) }
        } else {
            // The buzz still says it.
            inviteLogger.error("nuru_ring_once.caf missing or unplayable — ringing with vibration only")
        }
        buzzTask = Self.schedule(NuruRing.buzzOffsets(remaining: remaining)) {
            AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
        }
    }

    func stop() {
        ringTask?.cancel()
        ringTask = nil
        buzzTask?.cancel()
        buzzTask = nil
        if soundId != 0 {
            AudioServicesDisposeSystemSoundID(soundId)
            soundId = 0
        }
    }

    /// Runs `fire` at each offset (seconds from now) until cancelled. Back
    /// from a suspension, the ones that fell due are skipped, not fired in a burst.
    private static func schedule(_ offsets: [TimeInterval], _ fire: @escaping () -> Void) -> Task<Void, Never> {
        let started = Date()
        return Task {
            for offset in offsets {
                let wait = offset - Date().timeIntervalSince(started)
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
                guard !Task.isCancelled else { return }
                if wait < -0.5 { continue }
                fire()
            }
        }
    }
}

// MARK: - The presenter

@MainActor
final class IncomingLiveInviteCenter: ObservableObject {
    static let shared = IncomingLiveInviteCenter()

    /// Join is opening the stream.
    @Published private(set) var joining = false
    /// One line when Join can't open the stream.
    @Published private(set) var notice: String?
    /// A Join for the stream's player to accept, through its own invite flow,
    /// once its pulse shows the invite still open. Stale after a minute.
    @Published private(set) var acceptRequest: AcceptRequest?
    struct AcceptRequest: Equatable { let streamId: String; let until: Date }

    /// The invite ringing now, if any.
    private(set) var invite: IncomingLiveInvite?
    /// The live stream whose player is on screen, if any — Join there
    /// accepts in place instead of opening a second player.
    private(set) var playerStreamId: String?

    private var window: UIWindow?
    private let ringer = LiveInviteRinger()
    private var timeout: Task<Void, Never>?
    private var backgroundObserver: NSObjectProtocol?
    /// Streams whose invite the member answered (Join or Not now), and when —
    /// so the same invite arriving again doesn't ring twice (NuruRing.isEcho).
    private var answered: [String: Date] = [:]

    private init() {
        // Out of sight, the phone stops ringing; the screen waits out its
        // 30 s in case the member comes straight back.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
        ) { _ in
            Task { @MainActor in IncomingLiveInviteCenter.shared.ringer.stop() }
        }
    }

    /// Ring for `new` — true once it is on screen (or already ringing, or
    /// just answered). False when its 30 s are gone, when the member is
    /// broadcasting (a ring would cover their own stream), or when there is
    /// no window to ring in.
    @discardableResult
    func ring(_ new: IncomingLiveInvite) -> Bool {
        // The same invite twice (its push, then its inbox copy) rings once —
        // and not at all once the member has answered it.
        if invite?.streamId == new.streamId { return true }
        if NuruRing.isEcho(of: new.streamId, answered: answered, now: Date()) { return true }
        let remaining = NuruRing.remaining(since: new.startedAt, now: Date())
        guard remaining > 0, BroadcastCenter.shared.controller == nil else { return false }
        if invite != nil { dismiss() }   // the newest invite is the one ringing
        guard present(new, remaining: remaining) else { return false }
        invite = new
        ringer.start(silent: new.silent, remaining: remaining)
        timeout = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()   // unanswered: the invite stays open for the player's card
        }
        return true
    }

    /// Join: the ring stops at the tap; the stream's player opens and accepts.
    func join() {
        guard let invite, !joining else { return }
        joining = true
        notice = nil
        ringer.stop()
        Task {
            let opened = await openStream(invite.streamId, accept: true)
            guard self.invite?.streamId == invite.streamId else { return }   // dismissed meanwhile
            joining = false
            switch opened {
            case .opened:
                answered[invite.streamId] = Date()
                markRead(invite)
                dismiss()
            case .ended:
                notice = "This Live has ended."
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                if self.invite?.streamId == invite.streamId { dismiss() }
            case .unreachable:
                // Stays up, quietly, for another try until its 30 s run out.
                notice = "Couldn't open the stream — check your connection and try again."
            }
        }
    }

    /// Not now: declines. Best-effort — if it can't reach the server the
    /// invite simply stays open, and the player's invite card still answers it.
    /// Not once Join is opening the stream: the member has answered.
    func notNow() {
        guard let invite, !joining else { return }
        answered[invite.streamId] = Date()
        clearAccept(invite.streamId)
        markRead(invite)
        dismiss()
        Task {
            do {
                try await MemberAPI.respondToLiveGuestInvite(streamId: invite.streamId, accept: false)
            } catch {
                inviteLogger.notice("Declining the Live invite failed — it stays open: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func dismiss() {
        timeout?.cancel()
        timeout = nil
        ringer.stop()
        invite = nil
        joining = false
        notice = nil
        guard let w = window else { return }
        window = nil
        UIView.animate(withDuration: 0.2, animations: { w.alpha = 0 }, completion: { _ in
            w.isHidden = true
            // Hand the keyboard and key status back to the app's own window.
            w.windowScene?.windows.first { $0 !== w && $0.windowLevel == .normal }?.makeKey()
        })
    }

    enum Opened { case opened, ended, unreachable }

    /// Opens the stream's player — or leaves the one already on it — and,
    /// with `accept`, asks it to accept the invite.
    func openStream(_ streamId: String, accept: Bool) async -> Opened {
        if accept { acceptRequest = AcceptRequest(streamId: streamId, until: Date().addingTimeInterval(60)) }
        if playerStreamId == streamId { return .opened }
        let rows: [LiveStreamSummary]
        do {
            rows = try await MemberAPI.fetchLiveNow()
        } catch {
            if accept { acceptRequest = nil }
            return .unreachable
        }
        let discovery = LiveDiscoveryCenter.shared
        discovery.ingest(rows)
        guard let stream = discovery.streams.first(where: { $0.streamId == streamId }) else {
            if accept { acceptRequest = nil }
            return .ended
        }
        discovery.markSeen(streamId)
        discovery.requestedItem = .live(stream)
        return .opened
    }

    // MARK: The player's side (LiveViewerPlayerView)

    func playerAppeared(_ streamId: String) { playerStreamId = streamId }
    func playerDisappeared(_ streamId: String) { if playerStreamId == streamId { playerStreamId = nil } }

    func wantsAccept(_ streamId: String, now: Date = Date()) -> Bool {
        guard let r = acceptRequest, r.streamId == streamId else { return false }
        return r.until > now
    }

    func clearAccept(_ streamId: String) {
        if acceptRequest?.streamId == streamId { acceptRequest = nil }
    }

    // MARK: Window

    /// Its own window over the app's, like a call: nothing presented in the
    /// app (a player, the radio, a sheet) can sit on top of it.
    private func present(_ invite: IncomingLiveInvite, remaining: TimeInterval) -> Bool {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive })
                ?? scenes.first(where: { $0.activationState == .foregroundInactive }) else { return false }
        // A call takes the screen: put the keyboard away.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        let host = UIHostingController(rootView: IncomingLiveInviteView(invite: invite, remaining: remaining, center: self))
        host.view.backgroundColor = .clear
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert
        w.overrideUserInterfaceStyle = .dark
        w.rootViewController = host
        w.alpha = 0
        w.makeKeyAndVisible()
        UIView.animate(withDuration: UIAccessibility.isReduceMotionEnabled ? 0.01 : 0.25) { w.alpha = 1 }
        window = w
        UIAccessibility.post(notification: .screenChanged, argument: nil)
        return true
    }

    private func markRead(_ invite: IncomingLiveInvite) {
        guard let id = invite.notificationId else { return }
        Task { try? await MemberAPI.markNotificationsRead([id]) }
    }
}

// MARK: - The screen

/// Full-screen, Live's navy and gold: the invite's words (`alert_title`
/// over the stream's name, `alert_body` under it), the 30 s running down
/// around the mark, and two big answers.
struct IncomingLiveInviteView: View {
    let invite: IncomingLiveInvite
    /// Seconds left on its clock when it appeared.
    let remaining: TimeInterval
    @ObservedObject var center: IncomingLiveInviteCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swell = false
    @State private var clock: CGFloat = 1

    var body: some View {
        VStack(spacing: 0) {
            liveTag.padding(.top, Nuru.S.lg)
            Spacer(minLength: Nuru.S.lg)
            ringingMark
            words.padding(.top, 28)
            if let notice = center.notice {
                Text(notice)
                    .font(.inter(13, .semibold)).foregroundStyle(Nuru.goldLight)
                    .multilineTextAlignment(.center)
                    .padding(.top, Nuru.S.base)
                    .transition(.opacity)
            }
            Spacer(minLength: Nuru.S.xl)
            answers
        }
        .padding(.horizontal, 28)
        .padding(.bottom, Nuru.S.screen)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // A background, so the wide glow can't widen the layout past the screen.
        .background {
            ZStack {
                LinearGradient(colors: [Nuru.navy, Nuru.navyDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle()
                    .fill(RadialGradient(colors: [Nuru.gold.opacity(0.26), .clear], center: .center, startRadius: 0, endRadius: 240))
                    .frame(width: 440, height: 440)
                    .blur(radius: 30)
                    .offset(y: -110)
            }
            .ignoresSafeArea()
            .accessibilityHidden(true)
        }
        .animation(.easeInOut(duration: 0.2), value: center.notice)
        .accessibilityAddTraits(.isModal)
        .onAppear {
            clock = CGFloat(remaining / NuruRing.window)
            withAnimation(.linear(duration: remaining)) { clock = 0 }
            if !reduceMotion { swell = true }
        }
    }

    private var liveTag: some View {
        HStack(spacing: 6) {
            InviteLiveDot()
            Text("LIVE INVITE").font(.inter(10, .bold)).kerning(1.4).foregroundStyle(.white)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Color(hex: 0xDC2626), in: Capsule())
        .accessibilityHidden(true)
    }

    /// The invite mark, two soft rings swelling out of it while it rings (held
    /// still under Reduce Motion), and the 30 s running down around it.
    private var ringingMark: some View {
        ZStack {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .stroke(Nuru.gold.opacity(0.4), lineWidth: 1.5)
                    .frame(width: 132, height: 132)
                    .scaleEffect(swell ? 1.5 + CGFloat(i) * 0.3 : 1)
                    .opacity(swell ? 0 : (reduceMotion ? 0 : 0.8))
                    .animation(reduceMotion ? nil : .easeOut(duration: 1.5).repeatForever(autoreverses: false).delay(Double(i) * 0.5),
                               value: swell)
            }
            Circle().fill(Nuru.gold.opacity(0.14)).frame(width: 132, height: 132)
            Circle().stroke(Nuru.gold.opacity(0.22), lineWidth: 3).frame(width: 132, height: 132)
            Circle()
                .trim(from: 0, to: clock)
                .stroke(Nuru.gold, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 132, height: 132)
            Icon(.handHeart, size: 46, color: Nuru.gold)
        }
        .frame(width: 200, height: 200)
        .accessibilityHidden(true)
    }

    private var words: some View {
        VStack(spacing: 0) {
            Text(invite.heading.uppercased())
                .font(.nCardKicker).kerning(1.4).foregroundStyle(Nuru.goldLight)
                .multilineTextAlignment(.center)
            Text(invite.streamTitle)
                .font(.fraunces(30, .semibold)).foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .minimumScaleFactor(0.8)
                .padding(.top, Nuru.S.md)
            Text(invite.message)
                .font(.inter(15, .medium)).foregroundStyle(.white.opacity(0.78))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Nuru.S.md)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(invite.heading). \(invite.streamTitle). \(invite.message)")
    }

    private var answers: some View {
        HStack(spacing: 14) {
            Button {
                Haptics.tap()
                center.notNow()
            } label: {
                Text("Not now").font(.inter(16, .semibold)).foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 60)
                    .background(Color.white.opacity(0.14), in: Capsule())
                    .overlay(Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1))
            }
            .buttonStyle(.pressable)
            .disabled(center.joining)
            .opacity(center.joining ? 0.5 : 1)

            Button {
                Haptics.action()
                center.join()
            } label: {
                ZStack {
                    if center.joining {
                        ProgressView().tint(Nuru.navy)
                    } else {
                        Text("Join").font(.inter(16, .bold)).foregroundStyle(Nuru.navy)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 60)
                .background(Nuru.goldGradient, in: Capsule())
                .shadow(color: Nuru.gold.opacity(0.35), radius: 14, y: 6)
            }
            .buttonStyle(.pressable)
            .disabled(center.joining)
            .accessibilityLabel(center.joining ? "Joining" : "Join")
        }
    }
}

/// The pulsing white dot of a LIVE tag (the player's and discovery's own are
/// private to their files).
private struct InviteLiveDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false
    var body: some View {
        Circle().fill(.white).frame(width: 6, height: 6)
            .opacity(dim ? 0.35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

#if DEBUG
extension IncomingLiveInviteCenter {
    /// Scripted verification — a simulator gets no pushes. Launch with
    /// SIMCTL_CHILD_NURU_RING=1 to ring a sample invite shortly after sign-in
    /// (NURU_RING=silent: the muted variant); NURU_RING_STREAM /
    /// NURU_RING_TITLE name the stream. Compiled out of Release.
    func debugRingIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard let mode = env["NURU_RING"], !mode.isEmpty else { return }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let push = NuruPush(template: "live_guest_invite", soundOn: mode != "silent",
                            streamId: env["NURU_RING_STREAM"] ?? "debug-stream",
                            title: env["NURU_RING_TITLE"] ?? "Sunday service")
        if let invite = IncomingLiveInvite(push: push) { ring(invite) }
    }
}

#Preview("Incoming Live invite") {
    IncomingLiveInviteView(
        invite: IncomingLiveInvite(push: NuruPush(template: "live_guest_invite", streamId: "s1", title: "Sunday service"))!,
        remaining: 24, center: .shared)
}
#endif
