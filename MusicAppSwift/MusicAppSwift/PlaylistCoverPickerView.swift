//
//  PlaylistCoverPickerView.swift
//  MusicAppSwift
//
//  Pick artwork from songs in playlist or library to use as playlist cover
//

import SwiftUI

struct PlaylistCoverPickerView: View {
    let playlist: Playlist
    @EnvironmentObject var musicPlayer: MusicPlayer
    @Environment(\.dismiss) var dismiss
    @State private var selectedFilter: CoverFilter = .playlist
    
    enum CoverFilter {
        case playlist
        case library
    }
    
    // Get songs with artwork
    var availableCovers: [Song] {
        let songsToFilter: [Song]
        switch selectedFilter {
        case .playlist:
            songsToFilter = playlist.songs.compactMap { songId in
                musicPlayer.songs.first(where: { $0.id == songId })
            }
        case .library:
            songsToFilter = musicPlayer.songs
        }
        
        return songsToFilter.filter { $0.artworkPath != nil }
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
                
                if availableCovers.isEmpty {
                    ContentUnavailableView(
                        selectedFilter == .playlist ? "No Artwork in Playlist" : "No Artwork Available",
                        systemImage: "photo",
                        description: Text(selectedFilter == .playlist ? "Add songs with artwork to this playlist" : "Download songs with artwork")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible())
                        ], spacing: 12) {
                            ForEach(availableCovers) { song in
                                Button(action: {
                                    selectCover(song)
                                }) {
                                    VStack(spacing: 8) {
                                        ArtworkView(
                                            artworkPath: song.artworkPath,
                                            size: 100,
                                            song: song,
                                            cornerRadius: 12
                                        )
                                        
                                        VStack(spacing: 2) {
                                            Text(song.title)
                                                .font(.system(size: 12, weight: .medium))
                                                .foregroundColor(.black)
                                                .lineLimit(1)
                                            Text(song.artist)
                                                .font(.system(size: 10))
                                                .foregroundColor(.black.opacity(0.6))
                                                .lineLimit(1)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding()
                        .padding(.bottom, 100)
                    }
                }
            }
            .navigationTitle("Choose Cover")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Picker("Source", selection: $selectedFilter) {
                        Text("Playlist").tag(CoverFilter.playlist)
                        Text("Library").tag(CoverFilter.library)
                    }
                    .pickerStyle(.segmented)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reset") {
                        resetCover()
                    }
                    .foregroundColor(.red)
                }
            }
        }
    }
    
    private func selectCover(_ song: Song) {
        guard let artworkPath = song.artworkPath else { return }
        musicPlayer.updatePlaylistCover(playlistId: playlist.id, coverImageURL: artworkPath)
        dismiss()
    }
    
    private func resetCover() {
        musicPlayer.updatePlaylistCover(playlistId: playlist.id, coverImageURL: nil)
        dismiss()
    }
}
