//
//  PlayerManager.swift
//  MusicAppSwift
//
//  Created on 11/12/2025.
//

import Foundation
import AVFoundation
import MediaPlayer

final class PlayerManager: NSObject {
    static let shared = PlayerManager()

    private var player: AVPlayer?
    private var timeObserver: Any?

    private override init() {
        super.init()
        setupAudioSession()
        setupRemoteCommands()
    }

    // MARK: - Public

    func play(url: URL,
              title: String,
              artist: String,
              album: String,
              artwork: UIImage) {

        // Clean up old player
        if let player = player {
            player.pause()
            if let obs = timeObserver {
                player.removeTimeObserver(obs)
                timeObserver = nil
            }
        }

        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        self.player = player

        // Observe time to update progress on lock screen
        let interval = CMTime(seconds: 1, preferredTimescale: 1)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval,
                                                      queue: .main) { [weak self] time in
            self?.updateElapsedTime(time: time)
        }

        player.play()
        updateNowPlaying(title: title,
                         artist: artist,
                         album: album,
                         artwork: artwork,
                         isPlaying: true)
    }

    func pause() {
        player?.pause()
        updateNowPlaying(isPlaying: false)
    }

    // MARK: - Audio Session

    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true)
            print("🎧 Audio session configured")
        } catch {
            print("❌ Audio session error:", error)
        }
    }

    // MARK: - Remote Commands

    private func setupRemoteCommands() {
        let cc = MPRemoteCommandCenter.shared()

        cc.playCommand.isEnabled = true
        cc.pauseCommand.isEnabled = true
        cc.nextTrackCommand.isEnabled = false
        cc.previousTrackCommand.isEnabled = false

        cc.playCommand.addTarget { [weak self] _ in
            self?.player?.play()
            self?.updateNowPlaying(isPlaying: true)
            return .success
        }

        cc.pauseCommand.addTarget { [weak self] _ in
            self?.player?.pause()
            self?.updateNowPlaying(isPlaying: false)
            return .success
        }

        print("🎮 Remote commands set up")
    }

    // MARK: - Now Playing

    private func updateNowPlaying(title: String? = nil,
                                  artist: String? = nil,
                                  album: String? = nil,
                                  artwork: UIImage? = nil,
                                  isPlaying: Bool? = nil) {

        var info = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]

        if let title = title {
            info[MPMediaItemPropertyTitle] = title
        }
        if let artist = artist {
            info[MPMediaItemPropertyArtist] = artist
        }
        if let album = album {
            info[MPMediaItemPropertyAlbumTitle] = album
        }
        if let artwork = artwork, artwork.size != .zero {
            let mediaArtwork = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
            info[MPMediaItemPropertyArtwork] = mediaArtwork
        }
        if let isPlaying = isPlaying {
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        }

        // Duration is optional; if you know it, set MPMediaItemPropertyPlaybackDuration

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        print("📱 Now Playing info:", info)
    }

    private func updateElapsedTime(time: CMTime) {
        guard time.isValid else { return }
        let seconds = CMTimeGetSeconds(time)
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
