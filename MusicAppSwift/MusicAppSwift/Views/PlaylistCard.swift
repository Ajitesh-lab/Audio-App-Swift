//
//  PlaylistCard.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/01/2026.
//

import SwiftUI

struct PlaylistCard: View {
    let playlist: Playlist
    @EnvironmentObject var musicPlayer: MusicPlayer
    @State private var showPlaylist = false
    @State private var showDeleteConfirmation = false
    
    // Get the current playlist data from musicPlayer for live updates
    private var currentPlaylist: Playlist {
        musicPlayer.playlists.first(where: { $0.id == playlist.id }) ?? playlist
    }
    
    var body: some View {
        Button(action: {
            showPlaylist = true
        }) {
            VStack(alignment: .leading, spacing: 8) {
                PlaylistCoverView(playlist: currentPlaylist, size: 140, cornerRadius: 12)
                
                Text(currentPlaylist.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Text("\(currentPlaylist.songs.count) songs")
                    .font(.system(size: 13))
                    .foregroundColor(.black.opacity(0.6))
            }
            .frame(width: 140)
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                Label("Delete Playlist", systemImage: "trash")
            }
        }
        .confirmationDialog("Delete \"\(playlist.name)\"?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                musicPlayer.deletePlaylist(playlist)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will remove the playlist but keep all songs in your library.")
        }
        .sheet(isPresented: $showPlaylist) {
            PlaylistDetailView(playlist: playlist)
                .environmentObject(musicPlayer)
        }
    }
}

struct PlaylistDetailView: View {
    let playlist: Playlist
    @EnvironmentObject var musicPlayer: MusicPlayer
    @Environment(\.dismiss) var dismiss
    @State private var showAddSongs = false
    @State private var showCoverPicker = false
    @State private var refreshID = UUID()
    
    private var currentPlaylist: Playlist? {
        musicPlayer.playlists.first(where: { $0.id == playlist.id })
    }
    
    private var playlistSongs: [Song] {
        currentPlaylist?.songs.compactMap { songId in
            musicPlayer.songs.first(where: { $0.id == songId })
        } ?? []
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.86, green: 0.92, blue: 0.99),
                        Color(red: 0.93, green: 0.96, blue: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header
                        VStack(spacing: 16) {
                            Button(action: {
                                showCoverPicker = true
                            }) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let currentPlaylist = currentPlaylist {
                                        PlaylistCoverView(playlist: currentPlaylist, size: 200, cornerRadius: 20)
                                    }
                                    
                                    Image(systemName: "photo.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.white)
                                        .background(
                                            Circle()
                                                .fill(Color.blue)
                                                .frame(width: 40, height: 40)
                                        )
                                        .offset(x: -10, y: -10)
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            
                            Text(currentPlaylist?.name ?? playlist.name)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("\(playlistSongs.count) songs")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .padding(.top, 20)
                        
                        // Songs List
                        if playlistSongs.isEmpty {
                            ContentUnavailableView(
                                "No Songs",
                                systemImage: "music.note",
                                description: Text("Add songs to this playlist from your library")
                            )
                            .padding(.top, 40)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(playlistSongs) { song in
                                    SongRow(
                                        song: song,
                                        musicPlayer: musicPlayer,
                                        songToDelete: .constant(nil),
                                        showDeleteConfirmation: .constant(false)
                                    )
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: {
                        showAddSongs = true
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "plus.circle.fill")
                            Text("Add Songs")
                        }
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddSongs) {
                if let currentPlaylist = currentPlaylist {
                    AddSongsToPlaylistView(playlist: currentPlaylist)
                        .environmentObject(musicPlayer)
                        .onDisappear {
                            refreshID = UUID()
                        }
                }
            }
            .sheet(isPresented: $showCoverPicker) {
                if let currentPlaylist = currentPlaylist {
                    PlaylistCoverPickerView(playlist: currentPlaylist)
                        .environmentObject(musicPlayer)
                        .onDisappear {
                            refreshID = UUID()
                        }
                }
            }
            .id(refreshID)
        }
    }
}
