// RadioCenter — the app-wide Nuru Radio engine.
//
// OWNS the AVPlayer and the currently-tuned program, so playback survives
// leaving the player page (the studio view is just a remote control over this
// singleton). Because the app declares UIBackgroundModes: audio and the session
// category is .playback, the stream keeps going when the phone locks or the app
// backgrounds — and the MPNowPlayingInfoCenter + MPRemoteCommandCenter wiring
// below is what surfaces it in the iPhone's Dynamic Island / Lock Screen with
// working play–pause controls.
import AVFoundation
import Foundation
import MediaPlayer
import SwiftUI
import UIKit

@MainActor
final class RadioCenter: ObservableObject {
    static let shared = RadioCenter()

    /// The tuned program (nil = radio idle: no player, no Now Playing entry).
    @Published private(set) var program: RadioProgram?
    @Published private(set) var playing = false
    /// Scrubber state for RECORDED shows (seconds). Live streams keep these 0.
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var duration: Double = 0
    /// Soft-mute (the studio's volume glass button) — audio keeps flowing so the
    /// live edge stays current; only the output is silenced.
    @Published private(set) var muted = false
    /// Sleep timer — when set, playback pauses at this moment (studio moon button).
    @Published private(set) var sleepAt: Date?
    /// When the current LIVE tune-in began — drives the studio's elapsed clock.
    @Published private(set) var tunedAt: Date?

    private var sleepTask: Task<Void, Never>?
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    // Live-stream auto-reconnect: engine restarts / network blips kill the HTTP
    // stream and AVPlayer just sits there "playing" silence. We re-tune with
    // backoff; user actions (play/stop/tune) reset the attempt counter.
    private var failObserver: NSObjectProtocol?
    private var stallObserver: NSObjectProtocol?
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private var commandsRegistered = false
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?
    // Adaptive live-stream buffer (AIMD): +3s on every underrun (cap 15s),
    // −1s per clean 4-minute stretch (floor 4s). Persisted so each device
    // converges on the smallest buffer that plays clean on ITS network.
    private static let adaptiveBufferKey = "radio.adaptiveBuffer"
    private var adaptiveBuffer: Double {
        didSet { UserDefaults.standard.set(adaptiveBuffer, forKey: Self.adaptiveBufferKey) }
    }
    /// Shared debounce across all underrun paths (stall/fail/end/buffer-empty)
    /// and the yardstick for the stability task's "clean window" check.
    private var lastUnderrunAt: Date?
    private var bufferEmptyObservation: NSKeyValueObservation?
    private var stabilityTask: Task<Void, Never>?

    private init() {
        let stored = UserDefaults.standard.object(forKey: Self.adaptiveBufferKey) as? Double
        adaptiveBuffer = min(15, max(4, stored ?? 5.0))
        // Keep `playing` honest across phone calls / Siri / other-app takeovers.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(), queue: .main
        ) { [weak self] note in
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                .map(AVAudioSession.InterruptionOptions.init(rawValue:)) ?? []
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch type {
                case .began:
                    self.playing = false
                    self.pushNowPlaying()
                case .ended where options.contains(.shouldResume):
                    self.play()
                default:
                    break
                }
            }
        }
    }

    // MARK: - Transport

    /// Tune the station to a program: live → HLS, otherwise the hosted recording.
    /// Re-tuning the same program just resumes; a different one swaps the stream.
    func tune(_ p: RadioProgram) {
        guard let url = p.streamUrl else { return }
        if program?.id == p.id, player != nil {
            if !playing { play() }
            return
        }
        teardownPlayer()
        program = p
        artwork = nil
        // Radio must be heard even with the ring switch on silent, and .playback
        // (+ UIBackgroundModes: audio) keeps it alive when the app backgrounds.
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        let item = AVPlayerItem(url: url)
        if p.live {
            // Live radio: hug the live edge. AVPlayer's default anti-stall
            // buffering is VOD-tuned and parks listeners 5-15s behind the
            // broadcast. The forward buffer ADAPTS per device (AIMD): every
            // underrun adds 3s (cap 15s), every clean 4-minute stretch shaves
            // 1s (floor 4s), so each device converges on the smallest buffer
            // that plays dropout-free on its own network. A reconnect's
            // rebuilt item lands here and inherits the grown buffer.
            // NOTE: automaticallyWaitsToMinimizeStalling must stay ON for an
            // Icecast HTTP stream — disabling it made playback start against
            // an empty buffer and render silence (field-reported).
            item.preferredForwardBufferDuration = adaptiveBuffer
        }
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer
        observe(item: item, of: avPlayer, live: p.live)
        registerRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        avPlayer.isMuted = muted
        avPlayer.play()
        playing = true
        if p.live { startStabilityTask() }
        tunedAt = p.live ? Date() : nil
        pushNowPlaying()
        loadArtwork(p)
    }

    /// Soft mute — silences output without stopping the stream.
    func toggleMute() {
        muted.toggle()
        player?.isMuted = muted
    }

    /// Sleep timer: pause after `minutes` (nil cancels). One timer at a time.
    func setSleepTimer(minutes: Int?) {
        sleepTask?.cancel()
        sleepTask = nil
        guard let minutes else { sleepAt = nil; return }
        let target = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepAt = target
        sleepTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.sleepAt != nil else { return }
                self.pause()
                self.sleepAt = nil
            }
        }
    }

    func togglePlay() { playing ? pause() : play() }

    func play() {
        reconnectAttempts = 0
        guard let player else {
            if let program { tune(program) }   // stream was torn down — rebuild
            return
        }
        try? AVAudioSession.sharedInstance().setActive(true)
        // Pressing play at the end of a recording restarts it.
        if duration > 0, currentTime >= duration - 0.5 {
            player.seek(to: .zero)
            currentTime = 0
        }
        player.play()
        playing = true
        if program?.live == true { startStabilityTask() }
        pushNowPlaying()
    }

    func pause() {
        reconnectTask?.cancel()
        reconnectTask = nil
        stabilityTask?.cancel()
        stabilityTask = nil
        player?.pause()
        playing = false
        pushNowPlaying()
    }

    /// Fully power the station down (mini-player ✕). Clears the Now Playing entry.
    func stop() {
        reconnectTask?.cancel()
        reconnectTask = nil
        reconnectAttempts = 0
        teardownPlayer()
        program = nil
        playing = false
        artwork = nil
        tunedAt = nil
        sleepTask?.cancel()
        sleepTask = nil
        sleepAt = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Recorded shows only (live streams have no timeline to seek).
    func seek(to seconds: Double) {
        guard let player, duration > 0 else { return }
        let clamped = min(max(0, seconds), duration)
        currentTime = clamped
        player.seek(to: CMTime(seconds: clamped, preferredTimescale: 600)) { [weak self] _ in
            Task { @MainActor [weak self] in self?.pushNowPlaying() }
        }
    }

    // MARK: - Ducking (feat/liturgy-audio — the liturgy voice needs to be
    // heard over the station without silently cutting worship music off)

    /// Remembers the pre-duck volume so `unduck()` restores it exactly.
    private var duckedVolume: Float?

    /// Lower the station's output so another in-app voice (the liturgy
    /// reader) can be heard clearly over it. A no-op if the station isn't
    /// tuned or is already ducked — safe to call unconditionally.
    func duck(to level: Float = 0.12) {
        guard let player, duckedVolume == nil else { return }
        duckedVolume = player.volume
        player.volume = level
    }

    /// Restore the station's normal volume after a duck.
    func unduck() {
        guard let player, let prev = duckedVolume else { return }
        player.volume = prev
        duckedVolume = nil
    }

    // MARK: - Player observation

    private func observe(item: AVPlayerItem, of avPlayer: AVPlayer, live: Bool) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if live {
                    // A live Icecast stream "ending" = the server dropped us
                    // (engine restart, network blip). Count it as an underrun
                    // (the rebuilt item then starts with the grown buffer),
                    // then reconnect — don't stop.
                    self.recordUnderrun()
                    self.scheduleLiveReconnect()
                } else {
                    self.playing = false
                    if self.duration > 0 { self.currentTime = self.duration }
                    self.pushNowPlaying()
                }
            }
        }
        if live {
            failObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordUnderrun()
                    self?.scheduleLiveReconnect()
                }
            }
            stallObserver = NotificationCenter.default.addObserver(
                forName: AVPlayerItem.playbackStalledNotification, object: item, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.recordUnderrun()
                    self?.scheduleLiveReconnect()
                }
            }
            // Soft underruns: the forward buffer draining mid-play is trouble
            // even when no stall notification fires — count it too (the shared
            // 5s debounce in recordUnderrun stops double-counting when both fire).
            bufferEmptyObservation = item.observe(\.isPlaybackBufferEmpty, options: [.new]) { [weak self] _, change in
                guard change.newValue == true else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.playing else { return }
                    self.recordUnderrun()
                }
            }
        }
        guard !live else { return }
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self, let current = self.player?.currentItem else { return }
                self.currentTime = max(0, time.seconds.isFinite ? time.seconds : 0)
                let d = current.duration.seconds
                if d.isFinite, d > 0, abs(self.duration - d) > 0.5 {
                    self.duration = d
                    self.pushNowPlaying()   // duration just became known — refresh the island
                }
            }
        }
    }

    private func teardownPlayer() {
        artworkTask?.cancel()
        artworkTask = nil
        if let timeObserver { player?.removeTimeObserver(timeObserver) }
        timeObserver = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
        if let failObserver { NotificationCenter.default.removeObserver(failObserver) }
        failObserver = nil
        if let stallObserver { NotificationCenter.default.removeObserver(stallObserver) }
        stallObserver = nil
        bufferEmptyObservation?.invalidate()
        bufferEmptyObservation = nil
        stabilityTask?.cancel()
        stabilityTask = nil
        player?.pause()
        player = nil
        currentTime = 0
        duration = 0
        duckedVolume = nil   // the old AVPlayer instance is gone — nothing left to restore
    }

    /// Rebuild the live player after the stream drops. Backoff 2/3/5/8s, up to
    /// 8 tries; any explicit user action (tune/play/stop) resets the counter.
    private func scheduleLiveReconnect() {
        guard let p = program, p.live, playing else { return }
        guard reconnectTask == nil, reconnectAttempts < 8 else { return }
        reconnectAttempts += 1
        let delays: [Double] = [2, 3, 5, 8]
        let delay = delays[min(reconnectAttempts - 1, delays.count - 1)]
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard let self, !Task.isCancelled else { return }
            self.reconnectTask = nil
            guard let current = self.program, current.id == p.id, self.playing else { return }
            self.teardownPlayer()
            self.tune(current)   // player == nil → tune rebuilds fresh
        }
    }

    // MARK: - Adaptive buffer (AIMD)

    /// Additive increase: any live-stream trouble (stall, failure, dropout,
    /// buffer drain) grows the forward buffer +3s toward the 15s cap and
    /// applies it to the current item immediately. One real dropout tends to
    /// fire several of those signals back-to-back, so a shared 5s debounce
    /// makes them count once.
    private func recordUnderrun() {
        let now = Date()
        if let last = lastUnderrunAt, now.timeIntervalSince(last) < 5 { return }
        lastUnderrunAt = now
        adaptiveBuffer = min(15, adaptiveBuffer + 3)
        player?.currentItem?.preferredForwardBufferDuration = adaptiveBuffer
    }

    /// Decrease when stable: while live audio plays, every 4-minute window
    /// with zero underruns shaves 1s off the buffer (floor 4s), so devices on
    /// good networks drift back toward the live edge. Cancelled by
    /// pause/stop/teardown; tune/play restart it for live programs.
    private func startStabilityTask() {
        stabilityTask?.cancel()
        stabilityTask = Task { [weak self] in
            while !Task.isCancelled {
                let windowStart = Date()
                try? await Task.sleep(nanoseconds: 240 * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.playing, self.program?.live == true else { return }
                if let last = self.lastUnderrunAt, last >= windowStart { continue }
                self.adaptiveBuffer = max(4, self.adaptiveBuffer - 1)
                self.player?.currentItem?.preferredForwardBufferDuration = self.adaptiveBuffer
            }
        }
    }

    // MARK: - Now Playing (Dynamic Island / Lock Screen)

    private func pushNowPlaying() {
        guard let p = program else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: p.title,
            MPMediaItemPropertyArtist: p.speaker ?? "Nuru Radio",
            MPMediaItemPropertyAlbumTitle: "Nuru Radio",
            MPNowPlayingInfoPropertyIsLiveStream: p.live,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
        ]
        if !p.live, duration > 0 {
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        }
        if let artwork { info[MPMediaItemPropertyArtwork] = artwork }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Registered once for the app's lifetime — handlers route back into the
    /// singleton, so the island / lock-screen buttons keep working no matter
    /// which screen (if any) is showing.
    private func registerRemoteCommandsIfNeeded() {
        guard !commandsRegistered else { return }
        commandsRegistered = true
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.play() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.pause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor [weak self] in self?.togglePlay() }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let e = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor [weak self] in self?.seek(to: e.positionTime) }
            return .success
        }
    }

    /// Best-effort artwork for the island / lock screen. Reuses the app's decoded
    /// image cache; every failure path just leaves the text-only Now Playing card.
    private func loadArtwork(_ p: RadioProgram) {
        artworkTask?.cancel()
        guard let s = p.artworkUrl, let url = URL(string: s) else { return }
        artworkTask = Task { [weak self] in
            var image = NuruImageCache.shared.image(for: url)
            if image == nil {
                guard let (data, response) = try? await URLSession.shared.data(from: url) else { return }
                if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return }
                guard let decoded = UIImage(data: data) else { return }
                NuruImageCache.shared.insert(decoded, for: url)
                image = decoded
            }
            guard let image, !Task.isCancelled else { return }
            guard let self, self.program?.id == p.id else { return }
            self.artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            self.pushNowPlaying()
        }
    }
}
