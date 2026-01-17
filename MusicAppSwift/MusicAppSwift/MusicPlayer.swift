//
//  MusicPlayer.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import Foundation
import AVFoundation
import Combine
import MediaPlayer
import UIKit

#if canImport(ActivityKit)
import ActivityKit
#endif

class MusicPlayer: NSObject, ObservableObject {
    static let shared = MusicPlayer()
    
    @Published var songs: [Song] = []
    @Published var playlists: [Playlist] = []
    @Published var currentSong: Song?
    @Published var isPlaying = false
    @Published var isLoaded = false
    @Published var progress: Double = 0
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    private var lastUpdateTime: Double = 0
    @Published var volume: Float = 1.0
    @Published var playbackSpeed: Float = 1.0
    @Published var isShuffled = false
    @Published var repeatMode: RepeatMode = .off
    @Published var likedSongs: Set<String> = []
    @Published var recentSongs: [String] = []
    
    // Playlist management
    @Published var currentPlaylist: Playlist?
    @Published var queuedSongs: [Song] = []
    
    // Slider drag state - prevents time observer conflicts
    @Published var isDraggingSlider = false
    @Published var draggedTime: Double = 0
    private var allowAutomaticProgressUpdates = false
    
    private var player: AVPlayer?
    private var nextPlayerItem: AVPlayerItem?
    private var timeObserver: Any?
    private var statusObserver: NSKeyValueObservation?
    private var cancellables = Set<AnyCancellable>()
    
    #if canImport(ActivityKit)
    @available(iOS 16.1, *)
    private var currentActivity: Activity<MusicActivityAttributes>?
    #endif
    
    enum RepeatMode {
        case off, one, all
    }
    
    override init() {
        super.init()
        setupAudioSession()
        setupAppLifecycleObservers()
        cleanupStaleLiveActivities() // Clean up any orphaned Dynamic Islands
        
        // Load data asynchronously to avoid blocking UI
        Task {
            await self.loadDataAsync()
        }
    }
    
    private func cleanupStaleLiveActivities() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            Task {
                let activities = Activity<MusicActivityAttributes>.activities
                if !activities.isEmpty {
                    print("🧹 Found \(activities.count) stale Live Activities from previous session")
                    for activity in activities {
                        await activity.end(nil, dismissalPolicy: .immediate)
                        print("   Removed: \(activity.id)")
                    }
                    print("✅ All stale Live Activities cleaned up")
                }
            }
        }
        #endif
    }
    
    private func setupAppLifecycleObservers() {
        // Observe when app is about to terminate (swiped away from app switcher)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
        
        // Also observe when app enters background (home button pressed)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        
        print("✅ App lifecycle observers set up")
    }
    
    @objc private func appWillTerminate() {
        print("🛑 App is terminating - cleaning up...")
        
        // Stop playback
        player?.pause()
        isPlaying = false
        
        // End Live Activity
        endLiveActivity()
        
        // Clear Now Playing
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        // Deactivate audio session
        _ = try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        
        print("✅ Cleanup complete")
    }
    
    @objc private func appDidEnterBackground() {
        // Don't stop playback in background - music should continue playing
        // Just log for debugging
        print("📱 App entered background - music continues playing")
    }
    
    private func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // CRITICAL: Configure category at launch, but DON'T activate yet
            // Activation happens in activateAudioSessionForPlayback() before each play
            try audioSession.setCategory(
                .playback,
                mode: .default,
                options: [.allowAirPlay, .allowBluetoothA2DP]
            )
            
            print("✅ Audio session configured on app launch")
            print("   Category: \(audioSession.category.rawValue)")
            print("   Mode: \(audioSession.mode.rawValue)")
            
            // CRITICAL: Enable remote control events for lock screen
            UIApplication.shared.beginReceivingRemoteControlEvents()
            print("✅ Remote control events enabled")
            
            // Observe audio interruptions (calls, alarms, etc)
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleAudioInterruption),
                name: AVAudioSession.interruptionNotification,
                object: nil
            )
            
            // Remote commands will be set up after audio session is activated
        } catch {
            print("❌ Failed to set up audio session: \(error)")
        }
    }
    
    private func activateAudioSessionForPlayback() {
        let session = AVAudioSession.sharedInstance()
        do {
            print("🎧 Activating audio session for playback...")
            // Category already set in setupAudioSession() - just activate
            try session.setActive(true)
            UIApplication.shared.beginReceivingRemoteControlEvents()
            print("✅ Audio session ACTIVE with category: \(session.category.rawValue)")
            print("✅ Audio session mode: \(session.mode.rawValue)")
            print("✅ Audio session is active: \(session.isOtherAudioPlaying)")
            
            // Set up remote commands AFTER session is active
            setupRemoteTransportControls()
        } catch {
            print("❌ Failed to activate audio session: \(error)")
        }
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        print("🎮 Setting up remote transport controls...")
        
        // Remove any existing targets first
        commandCenter.playCommand.removeTarget(nil)
        commandCenter.pauseCommand.removeTarget(nil)
        commandCenter.togglePlayPauseCommand.removeTarget(nil)
        commandCenter.nextTrackCommand.removeTarget(nil)
        commandCenter.previousTrackCommand.removeTarget(nil)
        commandCenter.changePlaybackPositionCommand.removeTarget(nil)
        
        print("   🗑️  Removed existing command targets")
        
        // Enable commands
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.togglePlayPauseCommand.isEnabled = true
        commandCenter.nextTrackCommand.isEnabled = true
        commandCenter.previousTrackCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        
        print("   ✅ Commands enabled: play, pause, toggle, next, prev, seek")
        
        // Play command
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("🎵 Remote Command: Play")
            if !self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }
        
        // Pause command
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("🎵 Remote Command: Pause")
            if self.isPlaying {
                self.togglePlayPause()
            }
            return .success
        }
        
        // Toggle play/pause
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("🎵 Remote Command: Toggle Play/Pause")
            self.togglePlayPause()
            return .success
        }
        
        // Next track
        commandCenter.nextTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("🎵 Remote Command: Next Track")
            self.skipForward()
            return .success
        }
        
        // Previous track
        commandCenter.previousTrackCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            print("🎵 Remote Command: Previous Track")
            self.skipBackward()
            return .success
        }
        
        // Seek command
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            print("🎵 Remote Command: Seek to \(positionEvent.positionTime)")
            
            // CRITICAL: Prevent time observer from fighting with remote seek
            self.isDraggingSlider = true
            self.seek(to: positionEvent.positionTime)
            
            // Reset flag after brief delay to allow seek to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.isDraggingSlider = false
            }
            
            return .success
        }
        
        print("   ✅ All 6 command handlers attached (play, pause, toggle, next, prev, seek)")
        print("🎮 Remote Command Center setup COMPLETE")
    }
    
    // MARK: - Playback Control
    func play(_ song: Song) {
        // Reset slider state FIRST to prevent glitches
        isDraggingSlider = false
        draggedTime = 0
        currentTime = 0
        
        // Stop current player if any
        if let currentPlayer = player {
            currentPlayer.pause()
            currentPlayer.replaceCurrentItem(with: nil)
        }
        
        currentSong = song
        
        // CRITICAL: Reactivate and set category before each play (lock screen requires .playback)
        activateAudioSessionForPlayback()
        
        // Support both raw file paths and file:// URLs
        let url: URL
        if let directURL = URL(string: song.url), directURL.scheme != nil {
            url = directURL
        } else {
            url = URL(fileURLWithPath: song.url)
        }
        
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("❌ Audio file missing at path: \(url.path)")
            return
        }
        
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        player?.rate = playbackSpeed
        player?.automaticallyWaitsToMinimizeStalling = false // Reduce buffering delays
        player?.play()
        isPlaying = true
        
        setupTimeObserver()
        addToRecent(song)
        
        // Pre-load next song for gapless playback
        preloadNextSong()
        
        // CRITICAL: Update Now Playing once playback has actually started
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.updateNowPlayingInfo()
        }
        
        // Use modern async API to load duration
        Task { @MainActor in
            do {
                // Modern iOS 16+ API for loading duration
                if #available(iOS 16.0, *) {
                    let duration = try await playerItem.asset.load(.duration)
                    if duration.isNumeric && !duration.isIndefinite {
                        self.duration = CMTimeGetSeconds(duration)
                        print("✅ Duration loaded: \(self.duration)s")
                        
                        // Update again with correct duration
                        self.updateNowPlayingInfo()
                    }
                } else {
                    // Fallback for older iOS
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.updateNowPlayingInfo()
                    }
                }
            } catch {
                print("⚠️ Failed to load duration: \(error)")
                // Still update with what we have
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.updateNowPlayingInfo()
                }
            }
        }
        
        startLiveActivity()
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerDidFinishPlaying),
            name: .AVPlayerItemDidPlayToEndTime,
            object: playerItem
        )
    }
    
    func togglePlayPause() {
        print("🎵 Toggle Play/Pause - Current state: \(isPlaying ? "Playing" : "Paused")")
        
        if isPlaying {
            pause()
        } else {
            // Just resume - audio session already active from initial play()
            play()
            
            // Start Live Activity only if app is in background
            // (App will handle this via scene phase change)
        }
        
        print("🎵 New state: \(isPlaying ? "Playing" : "Paused")")
        
        // CRITICAL: Update Now Playing immediately to reflect new state
        updateNowPlayingInfo()
        updateLiveActivity()
    }

    /// Pause current playback without changing the current song
    func pause() {
        player?.pause()
        isPlaying = false
        endLiveActivity()
        updateNowPlayingInfo()
    }

    /// Resume playback for the current item (if any) without changing the queue
    func play() {
        guard let player = player else { return }
        player.play()
        isPlaying = true
        updateNowPlayingInfo()
    }

    func playNext(_ song: Song) {
        queuedSongs.removeAll { $0.id == song.id }
        queuedSongs.insert(song, at: 0)
        preloadNextSong()
    }

    func addToQueue(_ song: Song) {
        guard !queuedSongs.contains(where: { $0.id == song.id }) else { return }
        queuedSongs.append(song)
        if queuedSongs.count == 1 {
            preloadNextSong()
        }
    }
    
    func skipForward() {
        guard let nextSong = getNextSong() else { return }
        if queuedSongs.first?.id == nextSong.id {
            queuedSongs.removeFirst()
        }
        
        // CRITICAL: Remove time observer first to prevent glitches
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Reset slider state immediately
        isDraggingSlider = false
        draggedTime = 0
        currentTime = 0
        
        // Use preloaded item for instant skip if available
        if let preloadedItem = nextPlayerItem {
            currentSong = nextSong
            player?.replaceCurrentItem(with: preloadedItem)
            player?.play()
            isPlaying = true
            
            setupTimeObserver()
            addToRecent(nextSong)
            updateNowPlayingInfo()
            
            // Preload the next song
            preloadNextSong()
            
            print("⏭️ Skipped forward (gapless): \(nextSong.title)")
        } else {
            // Fallback to regular play
            play(nextSong)
        }
    }
    
    func skipBackward() {
        // CRITICAL: Remove time observer first to prevent glitches
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
        
        // Reset slider state immediately
        isDraggingSlider = false
        draggedTime = 0
        currentTime = 0
        
        // If playing from playlist, go back in playlist
        if let playlist = currentPlaylist {
            let playlistSongs = playlist.songs.compactMap { songId in
                songs.first(where: { $0.id == songId })
            }
            
            if let current = currentSong,
               let currentIndex = playlistSongs.firstIndex(where: { $0.id == current.id }),
               currentIndex > 0 {
                play(playlistSongs[currentIndex - 1])
                return
            }
        }
        
        // Otherwise use main songs list
        guard let current = currentSong,
              let currentIndex = songs.firstIndex(where: { $0.id == current.id }),
              currentIndex > 0 else { return }
        
        play(songs[currentIndex - 1])
    }
    
    func seek(to time: Double) {
        // CRITICAL: Stop automatic updates during seek to prevent glitching
        allowAutomaticProgressUpdates = false
        
        // Track if we set the flag (so we can unset it)
        let wasNotDragging = !isDraggingSlider
        
        // Set flag to block time observer during seek
        if wasNotDragging {
            isDraggingSlider = true
        }
        
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self, finished else { return }
            
            // Update current time immediately after seek completes
            self.currentTime = time
            
            // Update Now Playing with new time
            self.updateNowPlayingElapsedTime()
            
            // Resume automatic updates
            self.allowAutomaticProgressUpdates = true
            
            // Clear the dragging flag if we set it (not from manual drag)
            if wasNotDragging {
                self.isDraggingSlider = false
            }
        }
    }
    
    // MARK: - Slider Drag Management
    
    func startDragging() {
        print("🎚️ Slider drag started - blocking time observer")
        isDraggingSlider = true
        draggedTime = currentTime // Initialize with current position
    }
    
    func updateDragValue(_ time: Double) {
        // Update dragged time but don't seek yet
        draggedTime = time
        // Update UI immediately for smooth feedback
        currentTime = time
    }
    
    func stopDragging(seekTo time: Double) {
        print("🎚️ Slider drag ended - seeking to \(time)s")
        isDraggingSlider = false
        draggedTime = 0 // Reset dragged time
        seek(to: time)
    }
    
    func setSpeed(_ speed: Float) {
        playbackSpeed = speed
        player?.rate = speed
    }
    
    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            songs.shuffle()
        } else {
            songs.sort { $0.title < $1.title }
        }
    }
    
    func toggleRepeat() {
        switch repeatMode {
        case .off:
            repeatMode = .one
        case .one:
            repeatMode = .all
        case .all:
            repeatMode = .off
        }
    }
    
    @objc private func playerDidFinishPlaying() {
        print("🎵 Song finished playing - gapless transition starting...")
        
        switch repeatMode {
        case .one:
            if let current = currentSong {
                play(current)
            }
        case .all:
            skipForwardGapless()
        case .off:
            if !queuedSongs.isEmpty {
                skipForwardGapless()
            } else if let current = currentSong,
                      let currentIndex = songs.firstIndex(where: { $0.id == current.id }),
                      currentIndex < songs.count - 1 {
                skipForwardGapless()
            } else {
                isPlaying = false
            }
        }
    }
    
    // MARK: - Gapless Playback
    private func preloadNextSong() {
        guard let nextSong = getNextSong() else {
            print("ℹ️ No next song to preload")
            return
        }
        
        if let url = URL(string: nextSong.url) {
            nextPlayerItem = AVPlayerItem(url: url)
            
            // Preload asset for instant playback
            Task {
                if let asset = nextPlayerItem?.asset {
                    if #available(iOS 15.0, *) {
                        _ = try? await asset.load(.duration)
                    }
                }
            }
            
            print("✅ Preloaded next song: \(nextSong.title)")
        }
    }
    
    private func skipForwardGapless() {
        guard let nextSong = getNextSong() else { return }
        if queuedSongs.first?.id == nextSong.id {
            queuedSongs.removeFirst()
        }
        
        // Use preloaded item if available
        if let preloadedItem = nextPlayerItem {
            currentSong = nextSong
            player?.replaceCurrentItem(with: preloadedItem)
            player?.play()
            isPlaying = true
            
            setupTimeObserver()
            addToRecent(nextSong)
            updateNowPlayingInfo()
            
            // Preload the next song after this one
            preloadNextSong()
            
            print("✅ Gapless transition to: \(nextSong.title)")
        } else {
            // Fallback to regular play
            play(nextSong)
        }
    }
    
    private func getNextSong() -> Song? {
        if let queued = queuedSongs.first {
            return queued
        }
        if let playlist = currentPlaylist {
            let playlistSongs = playlist.songs.compactMap { songId in
                songs.first(where: { $0.id == songId })
            }
            
            if let current = currentSong,
               let currentIndex = playlistSongs.firstIndex(where: { $0.id == current.id }) {
                let nextIndex = (currentIndex + 1) % playlistSongs.count
                return playlistSongs[nextIndex]
            }
        } else {
            if let current = currentSong,
               let currentIndex = songs.firstIndex(where: { $0.id == current.id }) {
                let nextIndex = currentIndex + 1
                if nextIndex < songs.count {
                    return songs[nextIndex]
                }
            }
        }
        return nil
    }
    
    @objc private func handleAudioInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Interruption began (phone call, alarm, etc)
            print("⚠️ Audio interrupted - pausing")
            if isPlaying {
                player?.pause()
                isPlaying = false
                updateNowPlayingInfo()  // Update to show paused state
            }
            
        case .ended:
            // Interruption ended
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else {
                return
            }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            
            if options.contains(.shouldResume) {
                print("✅ Audio interruption ended - resuming")
                // Reactivate audio session
                do {
                    try AVAudioSession.sharedInstance().setActive(true)
                    player?.play()
                    isPlaying = true
                    updateNowPlayingInfo()  // Update to show playing state
                } catch {
                    print("❌ Failed to resume after interruption: \(error)")
                }
            }
            
        @unknown default:
            break
        }
    }
    
    // MARK: - Time Observer
    private func removeTimeObserver() {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }
    }
    
    private func setupTimeObserver() {
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 1.0, preferredTimescale: 1000),  // Reduced from 0.5s to 1s
            queue: .main
        ) { [weak self] time in
            guard let self = self else { return }
            
            // Don't update if user is dragging slider OR if playback is paused
            guard !self.isDraggingSlider && self.isPlaying else { return }
            
            let newTime = time.seconds
            
            // Only update if changed by > 0.5s (avoid micro-updates that cause UI churn)
            guard abs(newTime - self.currentTime) > 0.5 else { return }
            
            self.currentTime = newTime
            
            if let duration = self.player?.currentItem?.duration.seconds, !duration.isNaN {
                self.duration = duration
                self.progress = self.currentTime / duration
                
                // Update Now Playing and Live Activity only every 5 seconds
                if Int(self.currentTime) % 5 == 0 {
                    self.updateNowPlayingElapsedTime()
                    self.updateLiveActivity()
                }
            }
        }
    }
    
    private func observePlayerStatus(playerItem: AVPlayerItem) {
        statusObserver = playerItem.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch item.status {
                case .readyToPlay:
                    let durationSeconds = item.duration.seconds
                    self.duration = durationSeconds.isFinite && durationSeconds > 0 ? durationSeconds : self.duration
                    
                    print("✅ Player ready! isLoaded=true, duration=\(self.duration)")
                    
                    // Reset progress only after the new track is actually ready
                    self.currentTime = 0
                    self.progress = 0
                    self.lastUpdateTime = 0
                    self.isLoaded = true
                    self.allowAutomaticProgressUpdates = true
                case .failed:
                    if let error = item.error {
                        print("❌ Player FAILED: \(error.localizedDescription)")
                    } else {
                        print("❌ Player FAILED: Unknown error")
                    }
                    self.isLoaded = false
                    self.allowAutomaticProgressUpdates = false
                case .unknown:
                    print("⚠️ Player status UNKNOWN")
                    self.isLoaded = false
                    self.allowAutomaticProgressUpdates = false
                @unknown default:
                    break
                }
            }
        }
    }
    
    // MARK: - Library Management
    func addSong(_ song: Song) {
        songs.append(song)
        saveData()
    }
    
    /// Persist an updated fingerprint for a song and keep the in-memory model in sync
    func updateSongFingerprint(for songId: String, fingerprint: String) {
        if let index = songs.firstIndex(where: { $0.id == songId }) {
            songs[index].audioFingerprint = fingerprint
        }
        if currentSong?.id == songId {
            currentSong?.audioFingerprint = fingerprint
        }
        saveData()
    }
    
    func removeSong(_ song: Song) {
        songs.removeAll { $0.id == song.id }
        saveData()
    }
    
    func deleteSong(_ song: Song) {
        // Stop playback if this song is currently playing
        if currentSong?.id == song.id {
            player?.pause()
            player = nil
            currentSong = nil
            isPlaying = false
            currentTime = 0
            duration = 0
            endLiveActivity()
        }
        
        // Delete the actual audio file
        if let url = URL(string: song.url) {
            do {
                try FileManager.default.removeItem(at: url)
                print("✅ Deleted audio file: \(url.lastPathComponent)")
            } catch {
                print("⚠️ Failed to delete audio file: \(error)")
            }
        }
        
        // Delete artwork file if it exists
        if let artworkPath = song.artworkPath {
            let artworkURL = URL(fileURLWithPath: artworkPath)
            do {
                try FileManager.default.removeItem(at: artworkURL)
                print("✅ Deleted artwork file: \(artworkURL.lastPathComponent)")
            } catch {
                print("⚠️ Failed to delete artwork file: \(error)")
            }
        }
        
        // Remove from library (this triggers UI update)
        songs.removeAll { $0.id == song.id }
        
        // Remove from liked songs
        likedSongs.remove(song.id)
        
        // Remove from recent
        recentSongs.removeAll { $0 == song.id }
        
        // Remove from all playlists
        for i in 0..<playlists.count {
            playlists[i].songs.removeAll { $0 == song.id }
        }
        
        // Clear current playlist if it was playing from one
        if let currentPlaylist = currentPlaylist,
           currentPlaylist.songs.contains(song.id) {
            self.currentPlaylist = nil
        }
        
        // Save and force UI refresh
        saveData()
        
        // Explicitly trigger objectWillChange to ensure all views update
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
        
        print("✅ Song deleted from everywhere: \(song.title)")
    }
    
    func toggleLike(_ song: Song) {
        if likedSongs.contains(song.id) {
            likedSongs.remove(song.id)
        } else {
            likedSongs.insert(song.id)
        }
        saveData()
    }
    
    private func addToRecent(_ song: Song) {
        recentSongs.removeAll { $0 == song.id }
        recentSongs.insert(song.id, at: 0)
        if recentSongs.count > 20 {
            recentSongs.removeLast()
        }
        saveData()
    }
    
    // MARK: - Playlist Management
    func createPlaylist(name: String, color: String) {
        let playlist = Playlist(name: name, color: color)
        playlists.append(playlist)
        saveData()
    }
    
    func deletePlaylist(_ playlist: Playlist) {
        playlists.removeAll { $0.id == playlist.id }
        saveData()
    }
    
    func updatePlaylistCover(_ playlistId: String, coverImageURL: String?) {
        guard let index = playlists.firstIndex(where: { $0.id == playlistId }) else { return }
        
        playlists[index].coverImageURL = coverImageURL
        
        if currentPlaylist?.id == playlistId {
            currentPlaylist?.coverImageURL = coverImageURL
        }
        
        saveData()
    }
    
    func addSongToPlaylist(songId: String, playlistId: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            if !playlists[index].songs.contains(songId) {
                playlists[index].songs.append(songId)
                saveData()
            }
        }
    }
    
    func removeSongFromPlaylist(songId: String, playlistId: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].songs.removeAll { $0 == songId }
            saveData()
        }
    }
    
    func updatePlaylistCover(playlistId: String, coverImageURL: String?) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].coverImageURL = coverImageURL
            saveData()
        }
    }
    
    func playPlaylist(_ playlist: Playlist) {
        // Get all songs from playlist that exist in library
        let playlistSongs = playlist.songs.compactMap { songId in
            songs.first(where: { $0.id == songId })
        }
        
        guard !playlistSongs.isEmpty else { return }
        
        // Set as current playlist
        currentPlaylist = playlist
        
        // Play first song from playlist
        play(playlistSongs[0])
    }
    
    // MARK: - Playlist Playback (Simplified - Queue feature removed)
    
    func playPlaylist(_ playlist: Playlist, songs playlistSongs: [Song], shuffle: Bool = false) {
        guard !playlistSongs.isEmpty else { return }
        
        currentPlaylist = playlist
        
        if shuffle {
            let shuffled = playlistSongs.shuffled()
            play(shuffled[0])
        } else {
            play(playlistSongs[0])
        }
    }
    
    func playSongFromPlaylist(_ song: Song, playlist: Playlist, allSongs: [Song]) {
        currentPlaylist = playlist
        play(song)
    }
    
    // MARK: - Data Persistence
    private func saveData() {
        if let songsData = try? JSONEncoder().encode(songs) {
            UserDefaults.standard.set(songsData, forKey: "songs")
        }
        if let playlistsData = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(playlistsData, forKey: "playlists")
        }
        UserDefaults.standard.set(Array(likedSongs), forKey: "likedSongs")
        UserDefaults.standard.set(recentSongs, forKey: "recentSongs")
    }
    
    // Async data loading on background thread
    @MainActor
    private func loadDataAsync() async {
        // Decode on background thread
        let (loadedSongs, loadedPlaylists, likedData, recentData) = await Task.detached {
            let songsData = UserDefaults.standard.data(forKey: "songs")
            let playlistsData = UserDefaults.standard.data(forKey: "playlists")
            let likedData = UserDefaults.standard.array(forKey: "likedSongs") as? [String]
            let recentData = UserDefaults.standard.array(forKey: "recentSongs") as? [String]
            
            var songs: [Song] = []
            var playlists: [Playlist] = []
            
            if let data = songsData,
               let decoded = try? JSONDecoder().decode([Song].self, from: data) {
                songs = decoded
            }
            
            if let data = playlistsData,
               let decoded = try? JSONDecoder().decode([Playlist].self, from: data) {
                playlists = decoded
            }
            
            return (songs, playlists, likedData, recentData)
        }.value
        
        // Update @Published properties (already on main actor)
        self.songs = loadedSongs
        self.playlists = loadedPlaylists
        if let liked = likedData {
            self.likedSongs = Set(liked)
        }
        if let recent = recentData {
            self.recentSongs = recent
        }
        Logger.success("Data loaded: \(loadedSongs.count) songs, \(loadedPlaylists.count) playlists", category: "Startup")
    }
    
    // Keep old function for backward compatibility
    private func loadData() {
        Task {
            await loadDataAsync()
        }
    }
    
    // MARK: - Now Playing Info
    private func updateNowPlayingInfo() {
        guard let song = currentSong else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            print("⚠️ No current song, clearing Now Playing Info")
            return
        }
        
        print("\n========================================")
        print("🎵 UPDATING NOW PLAYING INFO")
        print("========================================")
        print("📱 Song: \(song.title)")
        print("👤 Artist: \(song.artist)")
        print("💿 Album: \(song.album)")
        print("⏱️  Duration: \(duration)s (song.duration: \(song.duration)s)")
        print("⏰ Current Time: \(currentTime)s")
        print("▶️  Is Playing: \(isPlaying)")
        print("🎨 Artwork Path: \(song.artworkPath ?? "nil")")
        
        var nowPlayingInfo = [String: Any]()
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.title
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.artist
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = song.album
        
        // Use song duration if player duration not available yet
        let effectiveDuration = duration > 0 ? duration : song.duration
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = effectiveDuration
        
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // CRITICAL: Always set playback rate (iOS needs this!)
        let playbackRate: Double = isPlaying ? 1.0 : 0.0
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = playbackRate
        nowPlayingInfo[MPNowPlayingInfoPropertyDefaultPlaybackRate] = 1.0
        nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = MPNowPlayingInfoMediaType.audio.rawValue
        nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = false
        
        print("📊 Playback Rate: \(playbackRate)")
        print("📊 Effective Duration: \(effectiveDuration)")
        
        // Load actual album artwork with dynamic rendering for spatial depth effects
        let artwork = loadArtworkForLockScreen(song: song)
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        
        // CRITICAL: Set this on the default center
        DispatchQueue.main.async {
            let center = MPNowPlayingInfoCenter.default()
            center.nowPlayingInfo = nowPlayingInfo
            
            // Verify it was set
            let verifyInfo = center.nowPlayingInfo
            print("✅ Now Playing Info SET to center")
            print("   - Title in center: \(verifyInfo?[MPMediaItemPropertyTitle] as? String ?? "MISSING")")
            print("   - Artist in center: \(verifyInfo?[MPMediaItemPropertyArtist] as? String ?? "MISSING")")
            print("   - Duration in center: \(verifyInfo?[MPMediaItemPropertyPlaybackDuration] as? Double ?? -1)")
            print("   - Artwork in center: \(verifyInfo?[MPMediaItemPropertyArtwork] != nil ? "YES" : "NO")")
            print("   - Total fields: \(nowPlayingInfo.count)")
            print("========================================\n")
        }
    }
    
    private func updateNowPlayingElapsedTime() {
        guard let song = currentSong else { return }
        
        // Get or create now playing info
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [
            MPMediaItemPropertyTitle: song.title,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: duration > 0 ? duration : song.duration
        ]
        
        // Update time and rate
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func loadArtworkForLockScreen(song: Song) -> MPMediaItemArtwork {
        // Try to load actual album artwork from local path
        if let artworkPath = song.artworkPath,
           let originalImage = UIImage(contentsOfFile: artworkPath),
           originalImage.size.width > 0 && originalImage.size.height > 0 {
            
            print("🎨 Loading album artwork for lock screen: \(artworkPath)")
            print("   📐 Original size: \(originalImage.size.width)x\(originalImage.size.height)")
            
            // Check if resolution is high enough for spatial depth
            let minDimension = min(originalImage.size.width, originalImage.size.height)
            if minDimension >= 1400 {
                print("   ✅ HIGH-RES: Image is \(Int(minDimension))px - SPATIAL DEPTH POSSIBLE")
            } else if minDimension >= 640 {
                print("   ⚠️ MEDIUM-RES: Image is \(Int(minDimension))px - spatial depth unlikely (need 1400+)")
            } else {
                print("   ❌ LOW-RES: Image is \(Int(minDimension))px - NO spatial depth")
            }
            
            // Get file size for verification
            if let fileURL = URL(string: "file://\(artworkPath)"),
               let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let fileSize = attributes[.size] as? Int {
                print("   💾 File size: \(fileSize / 1024)KB")
            }
            
            // CRITICAL: Use dynamic image handler for iOS spatial depth effects
            // Requirements for spatial depth:
            // 1. Image must be 1400x1400 or higher (3000x3000 ideal)
            // 2. Must have clear subject (person/face/object)
            // 3. NEVER crop, round, or filter the image
            // 4. Always return the SAME untouched square image
            return MPMediaItemArtwork(boundsSize: originalImage.size) { requestedSize in
                // CRITICAL: Always return the ORIGINAL untouched image
                // Do NOT resize, crop, or modify in any way
                // iOS needs the full resolution for depth segmentation
                return originalImage
            }
        }
        
        // Fallback: Generate gradient artwork if no album art available
        print("⚠️ No album artwork found, using gradient fallback")
        return self.generateDefaultArtwork()
    }
    
    private func resizeImage(_ image: UIImage, to targetSize: CGSize) -> UIImage {
        // Maintain aspect ratio - fit within target size
        let aspectRatio = image.size.width / image.size.height
        var newSize = targetSize
        
        if targetSize.width / targetSize.height > aspectRatio {
            newSize.width = targetSize.height * aspectRatio
        } else {
            newSize.height = targetSize.width / aspectRatio
        }
        
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
    
    private func generateDefaultArtwork() -> MPMediaItemArtwork {
        return MPMediaItemArtwork(boundsSize: CGSize(width: 512, height: 512)) { size in
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.image { context in
                // Create gradient
                let colors = [
                    UIColor(red: 0.478, green: 0.651, blue: 1.0, alpha: 0.8).cgColor,
                    UIColor(red: 1.0, green: 0.294, blue: 0.698, alpha: 0.8).cgColor
                ]
                let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray,
                                         locations: [0.0, 1.0])!
                
                context.cgContext.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: 0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
                
                // Add music note icon
                let noteSize = size.width * 0.5
                let noteRect = CGRect(
                    x: (size.width - noteSize) / 2,
                    y: (size.height - noteSize) / 2,
                    width: noteSize,
                    height: noteSize
                )
                
                let noteConfig = UIImage.SymbolConfiguration(pointSize: noteSize * 0.6, weight: .regular)
                let noteImage = UIImage(systemName: "music.note", withConfiguration: noteConfig)
                noteImage?.withTintColor(.white.withAlphaComponent(0.9), renderingMode: .alwaysOriginal)
                    .draw(in: noteRect)
            }
        }
    }
    
    // MARK: - Live Activity / Dynamic Island
    func startLiveActivity() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard let song = currentSong else {
                print("❌ Cannot start Live Activity: No current song")
                return
            }
            
            // Check if Live Activities are supported
            guard ActivityAuthorizationInfo().areActivitiesEnabled else {
                print("❌ Live Activities are not enabled on this device")
                return
            }
            
            // CRITICAL: Only start if audio is actually playing
            guard isPlaying else {
                print("⚠️ Not starting Live Activity - audio not playing")
                return
            }
            
            // Cleanup and start in a single atomic operation
            Task { @MainActor in
                // End all existing activities
                for activity in Activity<MusicActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                currentActivity = nil
                
                // Start new activity immediately after cleanup
                print("🎵 Starting Live Activity for: \(song.title)")
                
                let attributes = MusicActivityAttributes(albumArtURL: song.artworkPath)
                let contentState = MusicActivityAttributes.ContentState(
                    songTitle: song.title,
                    artistName: song.artist,
                    isPlaying: self.isPlaying,
                    progress: self.currentTime,
                    duration: self.duration,
                    artwork: song.artworkPath
                )
                
                do {
                    let activity = try Activity<MusicActivityAttributes>.request(
                        attributes: attributes,
                        content: .init(state: contentState, staleDate: nil),
                        pushType: nil
                    )
                    self.currentActivity = activity
                    print("✅ Live Activity started: \(activity.id)")
                } catch {
                    print("❌ Failed to start Live Activity: \(error.localizedDescription)")
                }
            }
        } else {
            print("⚠️ Live Activities require iOS 16.1+")
        }
        #else
        print("⚠️ ActivityKit not available")
        #endif
    }
    
    func updateLiveActivity() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard let activity = currentActivity,
                  let song = currentSong else { return }
            
            let contentState = MusicActivityAttributes.ContentState(
                songTitle: song.title,
                artistName: song.artist,
                isPlaying: isPlaying,
                progress: currentTime,
                duration: duration,
                artwork: nil
            )
            
            Task {
                await activity.update(
                    .init(state: contentState, staleDate: nil)
                )
                // print("🔄 Live Activity updated")
            }
        }
        #endif
    }
    
    func endLiveActivity() {
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            guard let activity = currentActivity else { return }
            
            Task {
                await activity.end(nil, dismissalPolicy: .immediate)
                currentActivity = nil
                print("🛑 Live Activity ended - Dynamic Island removed")
            }
        }
        #endif
    }
    
    // MARK: - App Lifecycle Cleanup
    func handleAppTermination() {
        print("🔴 App terminating - cleaning up Live Activity")
        endLiveActivity()
        
        #if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            // End all activities as a safety measure
            Task {
                for activity in Activity<MusicActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
                print("✅ All Live Activities terminated")
            }
        }
        #endif
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
        statusObserver?.invalidate()
        NotificationCenter.default.removeObserver(self)
        UIApplication.shared.endReceivingRemoteControlEvents()
        endLiveActivity()
    }
}
