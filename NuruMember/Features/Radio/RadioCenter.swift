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

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var commandsRegistered = false
    private var artworkTask: Task<Void, Never>?
    private var artwork: MPMediaItemArtwork?

    private init() {
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
        let avPlayer = AVPlayer(playerItem: item)
        player = avPlayer
        observe(item: item, of: avPlayer, live: p.live)
        registerRemoteCommandsIfNeeded()
        UIApplication.shared.beginReceivingRemoteControlEvents()
        avPlayer.play()
        playing = true
        pushNowPlaying()
        loadArtwork(p)
    }

    func togglePlay() { playing ? pause() : play() }

    func play() {
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
        pushNowPlaying()
    }

    func pause() {
        player?.pause()
        playing = false
        pushNowPlaying()
    }

    /// Fully power the station down (mini-player ✕). Clears the Now Playing entry.
    func stop() {
        teardownPlayer()
        program = nil
        playing = false
        artwork = nil
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

    // MARK: - Player observation

    private func observe(item: AVPlayerItem, of avPlayer: AVPlayer, live: Bool) {
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.playing = false
                if self.duration > 0 { self.currentTime = self.duration }
                self.pushNowPlaying()
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
        player?.pause()
        player = nil
        currentTime = 0
        duration = 0
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
