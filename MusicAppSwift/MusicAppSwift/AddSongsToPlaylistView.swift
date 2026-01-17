//
//  AddSongsToPlaylistView.swift
//  MusicAppSwift
//
//  Add songs from library to a playlist
//

import SwiftUI

struct AddSongsToPlaylistView: View {
    let playlist: Playlist
    @EnvironmentObject var musicPlayer: MusicPlayer
    @Environment(\.dismiss) var dismiss
    @State private var selectedSongs: Set<String> = []
    @State private var searchText = ""
    
    // Songs that aren't already in the playlist
    var availableSongs: [Song] {
        musicPlayer.songs.filter { song in
            !playlist.songs.contains(song.id)
        }
    }
    
    // Filter by search text
    var filteredSongs: [Song] {
        if searchText.isEmpty {
            return availableSongs
        }
        return availableSongs.filter { song in
            song.title.localizedCaseInsensitiveContains(searchText) ||
            song.artist.localizedCaseInsensitiveContains(searchText) ||
            song.album.localizedCaseInsensitiveContains(searchText)
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
                
                if filteredSongs.isEmpty {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Available Songs" : "No Results",
                        systemImage: searchText.isEmpty ? "music.note" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "All songs in your library are already in this playlist" : "No songs match your search")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(filteredSongs) { song in
                                SongSelectionRow(
                                    song: song,
                                    isSelected: selectedSongs.contains(song.id),
                                    onToggle: {
                                        if selectedSongs.contains(song.id) {
                                            selectedSongs.remove(song.id)
                                        } else {
                                            selectedSongs.insert(song.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding()
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Add Songs")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search songs")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add (\(selectedSongs.count))") {
                        addSelectedSongs()
                    }
                    .disabled(selectedSongs.isEmpty)
                    .fontWeight(.semibold)
                }
            }
        }
    }
    
    private func addSelectedSongs() {
        for songId in selectedSongs {
            musicPlayer.addSongToPlaylist(songId: songId, playlistId: playlist.id)
        }
        dismiss()
    }
}

struct SongSelectionRow: View {
    let song: Song
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            GlassCard {
                HStack(spacing: 12) {
                    // Checkbox
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundColor(isSelected ? .blue : .gray)
                    
                    // Artwork
                    ArtworkView(
                        artworkPath: song.artworkPath,
                        size: 48,
                        song: song,
                        cornerRadius: 8
                    )
                    
                    // Song Info
                    VStack(alignment: .leading, spacing: 2) {
                        Text(song.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 13))
                            .foregroundColor(.black.opacity(0.6))
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
