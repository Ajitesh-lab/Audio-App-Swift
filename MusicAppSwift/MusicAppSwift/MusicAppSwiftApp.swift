//
//  MusicAppSwiftApp.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import SwiftUI
import AVFoundation

@main
struct MusicAppSwiftApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var musicPlayer = MusicPlayer.shared
    @StateObject private var playlistManager = PlaylistManager()
    @StateObject private var authService = AuthService()
    
    init() {
        // Configure audio session on app launch for lock screen support
        configureAudioSessionForLockScreen()
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                if authService.isAuthenticated {
                    ContentView()
                        .environmentObject(musicPlayer)
                        .environmentObject(playlistManager)
                        .environmentObject(authService)
                } else {
                    LoginView()
                        .environmentObject(authService)
                }
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            handleScenePhaseChange(from: oldPhase, to: newPhase)
        }
    }
    
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            // App came to foreground - end Live Activity immediately
            print("📱 App became active - ending Live Activity")
            musicPlayer.endLiveActivity()
            
        case .background:
            // App went to background - start Live Activity if audio playing
            print("📱 App entered background")
            if musicPlayer.isPlaying && musicPlayer.currentSong != nil {
                print("🎵 Starting Live Activity (audio playing)")
                musicPlayer.startLiveActivity()
            }
            
        case .inactive:
            // Transition state - do nothing
            break
            
        @unknown default:
            break
        }
    }
    
    private func configureAudioSessionForLockScreen() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
            print("✅ Audio session configured on app launch")
        } catch {
            print("❌ Failed to configure audio session: \(error)")
        }
    }
}
