//
//  ContentView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var musicPlayer: MusicPlayer
    @State private var selectedTab = 0
    @State private var showYouTubeSearch = false
    @State private var fabPosition = CGPoint(x: UIScreen.main.bounds.width - 50, y: UIScreen.main.bounds.height - 150)
    
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selectedTab) {
                LibraryView(musicPlayer: musicPlayer)
                    .tabItem {
                        Label("Library", systemImage: "music.note.list")
                    }
                    .tag(0)
                
                ProfileView(musicPlayer: musicPlayer)
                    .tabItem {
                        Label("Profile", systemImage: "person.fill")
                    }
                    .tag(1)
            }
            .accentColor(.blue)
            
            // Mini Player
            if musicPlayer.currentSong != nil {
                VStack(spacing: 0) {
                    Spacer()
                    MiniPlayer(musicPlayer: musicPlayer)
                        .padding(.bottom, 60)
                        .padding(.top, 8)
                }
                .ignoresSafeArea(.keyboard)
            }
            
            // Floating Action Button (Draggable)
            Button(action: {
                showYouTubeSearch = true
            }) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 48, height: 48)
                    .background(Color.blue)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .position(fabPosition)
            .highPriorityGesture(
                DragGesture()
                    .onChanged { value in
                        fabPosition = value.location
                    }
            )
        }
        .sheet(isPresented: $showYouTubeSearch) {
            YouTubeSearchView(musicPlayer: musicPlayer, isPresented: $showYouTubeSearch)
        }
    }
}

struct MiniPlayer: View {
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var showExpandedPlayer = false
    
    var body: some View {
        Button(action: {
            showExpandedPlayer = true
        }) {
            HStack(spacing: 12) {
                // Artwork
                if let song = musicPlayer.currentSong {
                    ArtworkView(
                        artworkPath: song.artworkPath,
                        size: 48,
                        song: song,
                        cornerRadius: 8
                    )
                }
                
                // Song Info
                VStack(alignment: .leading, spacing: 2) {
                    if let song = musicPlayer.currentSong {
                        Text(song.title)
                            .font(.system(size: 15, weight: .semibold))
                            .lineLimit(1)
                            .foregroundColor(.black)
                        Text(song.artist)
                            .font(.system(size: 13))
                            .lineLimit(1)
                            .foregroundColor(.black.opacity(0.6))
                    }
                }
                
                Spacer()
                
                // Skip Back Button
                Button(action: {
                    musicPlayer.skipBackward()
                }) {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(PlainButtonStyle())
                
                // Play/Pause Button
                Button(action: {
                    musicPlayer.togglePlayPause()
                }) {
                    Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle()
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Skip Forward Button
                Button(action: {
                    musicPlayer.skipForward()
                }) {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.black.opacity(0.7))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: -3)
            )
            .padding(.horizontal, 12)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showExpandedPlayer) {
            ExpandedPlayerView(musicPlayer: musicPlayer)
        }
    }
}
