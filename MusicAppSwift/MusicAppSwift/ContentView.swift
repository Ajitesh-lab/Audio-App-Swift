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
            
            // Floating Action Button
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    Button(action: {
                        showYouTubeSearch = true
                    }) {
                        Image(systemName: "plus")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundColor(.white)
                            .frame(width: 56, height: 56)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, musicPlayer.currentSong != nil ? 130 : 70)
                }
            }
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
                
                // Play/Pause Button
                Button(action: {
                    musicPlayer.togglePlayPause()
                }) {
                    Image(systemName: musicPlayer.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 48, height: 48)
                        .background(
                            Circle()
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white)
                    .shadow(color: .black.opacity(0.15), radius: 15, x: 0, y: -3)
            )
            .padding(.horizontal, 12)
        }
        .buttonStyle(PlainButtonStyle())
        .fullScreenCover(isPresented: $showExpandedPlayer) {
            ExpandedPlayerView(musicPlayer: musicPlayer)
        }
    }
}
