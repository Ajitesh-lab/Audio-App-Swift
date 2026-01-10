//
//  PlaylistPickerView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import SwiftUI

struct PlaylistPickerView: View {
    @ObservedObject var musicPlayer: MusicPlayer
    let song: Song
    @Environment(\.dismiss) var dismiss
    @StateObject private var playlistManager = PlaylistManager()
    @State private var showCreatePlaylist = false
    @State private var newPlaylistName = ""
    
    var availablePlaylists: [Playlist] {
        musicPlayer.playlists.filter { !$0.songs.contains(song.id) }
    }
    
    var body: some View {
        NavigationView {
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
                
                VStack(spacing: 16) {
                    // Song Info
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(hex: "7AA6FF").opacity(0.6),
                                        Color(hex: "FF4BB2").opacity(0.6)
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 50, height: 50)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(song.title)
                                .font(.system(size: 16, weight: .semibold))
                                .lineLimit(1)
                            
                            Text(song.artist)
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.7))
                    )
                    .padding(.horizontal)
                    
                    // Create New Playlist Button
                    Button {
                        showCreatePlaylist = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 24, weight: .medium))
                            Text("Create New Playlist")
                                .font(.system(size: 16, weight: .semibold))
                            Spacer()
                        }
                        .foregroundColor(.blue)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.7))
                        )
                        .padding(.horizontal)
                    }
                    
                    // Existing Playlists
                    if availablePlaylists.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "music.note.list")
                                .font(.system(size: 60))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Song is in all playlists!")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxHeight: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 12) {
                                ForEach(availablePlaylists) { playlist in
                                    Button {
                                        addToPlaylist(playlist)
                                    } label: {
                                        HStack(spacing: 12) {
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color(hex: playlist.color).opacity(0.7))
                                                .frame(width: 50, height: 50)
                                                .overlay(
                                                    Image(systemName: "music.note.list")
                                                        .font(.system(size: 20, weight: .medium))
                                                        .foregroundColor(.white)
                                                )
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(playlist.name)
                                                    .font(.system(size: 16, weight: .semibold))
                                                    .foregroundColor(.black)
                                                
                                                Text("\(playlist.songs.count) songs")
                                                    .font(.system(size: 14))
                                                    .foregroundColor(.black.opacity(0.6))
                                            }
                                            
                                            Spacer()
                                            
                                            Image(systemName: "plus.circle")
                                                .font(.system(size: 24, weight: .medium))
                                                .foregroundColor(.blue)
                                        }
                                        .padding()
                                        .background(
                                            RoundedRectangle(cornerRadius: 12)
                                                .fill(Color.white.opacity(0.7))
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .navigationTitle("Add to Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("New Playlist", isPresented: $showCreatePlaylist) {
            TextField("Playlist name", text: $newPlaylistName)
            Button("Cancel", role: .cancel) {
                newPlaylistName = ""
            }
            Button("Create") {
                createAndAddToPlaylist()
            }
        } message: {
            Text("Enter a name for your new playlist")
        }
    }
    
    func addToPlaylist(_ playlist: Playlist) {
        musicPlayer.addSongToPlaylist(songId: song.id, playlistId: playlist.id)
        playlistManager.addSong(song.id, to: playlist.id)
        dismiss()
    }
    
    func createAndAddToPlaylist() {
        guard !newPlaylistName.isEmpty else { return }
        
        let newPlaylist = playlistManager.createPlaylist(name: newPlaylistName)
        playlistManager.addSong(song.id, to: newPlaylist.id)
        musicPlayer.addSongToPlaylist(songId: song.id, playlistId: newPlaylist.id)
        
        newPlaylistName = ""
        dismiss()
    }
}
