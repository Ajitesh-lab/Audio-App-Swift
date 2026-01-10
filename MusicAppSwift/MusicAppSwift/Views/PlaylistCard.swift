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
    
    var body: some View {
        Button(action: {
            showPlaylist = true
        }) {
            VStack(alignment: .leading, spacing: 8) {
                PlaylistCoverView(playlist: playlist, size: 140, cornerRadius: 12)
                
                Text(playlist.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.black)
                    .lineLimit(1)
                
                Text("\(playlist.songs.count) songs")
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
    
    private var playlistSongs: [Song] {
        playlist.songs.compactMap { songId in
            musicPlayer.songs.first(where: { $0.id == songId })
        }
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
                            PlaylistCoverView(playlist: playlist, size: 200, cornerRadius: 20)
                            
                            Text(playlist.name)
                                .font(.title)
                                .fontWeight(.bold)
                            
                            Text("\(playlist.songs.count) songs")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
