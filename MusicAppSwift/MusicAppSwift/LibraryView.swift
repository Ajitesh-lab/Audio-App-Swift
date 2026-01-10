//
//  LibraryView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import SwiftUI

struct LibraryView: View {
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var selectedFilter: FilterType = .all
    @State private var showCreatePlaylist = false
    @State private var showSpotifyImport = false
    @State private var isEditMode = false
    @State private var selectedSongs: Set<String> = []
    @State private var showDeleteConfirmation = false
    @State private var songToDelete: Song?
    @State private var showSingleDeleteConfirmation = false
    @ObservedObject private var importService = SpotifyImportService.shared
    
    enum FilterType: String, CaseIterable {
        case all = "All"
        case liked = "Liked"
        case recent = "Recent"
    }
    
    var filteredSongs: [Song] {
        switch selectedFilter {
        case .all:
            return musicPlayer.songs
        case .liked:
            return musicPlayer.songs.filter { musicPlayer.likedSongs.contains($0.id) }
        case .recent:
            let recentIds = musicPlayer.recentSongs
            return recentIds.compactMap { id in musicPlayer.songs.first(where: { $0.id == id }) }
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
                
                VStack(spacing: DesignSystem.Spacing.md) {
                    if !musicPlayer.playlists.isEmpty {
                        VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                            Text("Playlists")
                                .font(DesignSystem.Typography.title2)
                                .padding(.horizontal, DesignSystem.Spacing.md)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: DesignSystem.Spacing.md) {
                                    ForEach(musicPlayer.playlists) { playlist in
                                        PlaylistCard(playlist: playlist)
                                            .environmentObject(musicPlayer)
                                    }
                                }
                                .padding(.horizontal, DesignSystem.Spacing.md)
                            }
                        }
                    }
                    
                    GlassCard(cornerRadius: DesignSystem.CornerRadius.xxl) {
                        ScrollView {
                            LazyVStack(spacing: DesignSystem.Spacing.xs) {
                                if filteredSongs.isEmpty {
                                    VStack(spacing: DesignSystem.Spacing.md) {
                                        Image(systemName: "music.note")
                                            .font(.system(size: 60))
                                            .foregroundColor(DesignSystem.Colors.secondaryText)
                                        Text(emptyMessage)
                                            .font(DesignSystem.Typography.body)
                                            .foregroundColor(DesignSystem.Colors.secondaryText)
                                            .multilineTextAlignment(.center)
                                    }
                                    .padding(DesignSystem.Spacing.xxl)
                                } else {
                                    ForEach(filteredSongs, id: \.id) { song in
                                        if isEditMode {
                                            HStack {
                                                Button(action: {
                                                    if selectedSongs.contains(song.id) {
                                                        selectedSongs.remove(song.id)
                                                    } else {
                                                        selectedSongs.insert(song.id)
                                                    }
                                                }) {
                                                    Image(systemName: selectedSongs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                                        .foregroundColor(selectedSongs.contains(song.id) ? DesignSystem.Colors.accent : DesignSystem.Colors.secondaryText)
                                                        .font(.system(size: 24))
                                                }
                                                .padding(.leading, DesignSystem.Spacing.sm)
                                                
                                                SongRow(
                                                    song: song,
                                                    musicPlayer: musicPlayer,
                                                    songToDelete: .constant(nil),
                                                    showDeleteConfirmation: .constant(false)
                                                )
                                            }
                                        } else {
                                            SongRow(
                                                song: song,
                                                musicPlayer: musicPlayer,
                                                songToDelete: $songToDelete,
                                                showDeleteConfirmation: $showSingleDeleteConfirmation
                                            )
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.md)
                            .padding(.bottom, 100)
                        }
                        .scrollIndicators(.hidden)
                    }
                    .clipShape(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.xxl, style: .continuous)
                    )
                    .overlay(alignment: .top) {
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.22),
                                Color.white.opacity(0)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 24)
                        .allowsHitTesting(false)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
        .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditMode {
                        Button("Cancel") {
                            isEditMode = false
                            selectedSongs.removeAll()
                        }
                    } else {
                        Button("Edit") {
                            isEditMode = true
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode {
                        Button(action: {
                            if !selectedSongs.isEmpty {
                                showDeleteConfirmation = true
                            }
                        }) {
                            Image(systemName: "trash")
                                .foregroundColor(selectedSongs.isEmpty ? DesignSystem.Colors.secondaryText : .red)
                        }
                        .disabled(selectedSongs.isEmpty)
                    } else {
                        Menu {
                            Button(action: { showCreatePlaylist = true }) {
                                Label("New Playlist", systemImage: "plus.circle")
                            }
                            
                            Button(action: { showSpotifyImport = true }) {
                                Label("Import from Spotify", systemImage: "square.and.arrow.down")
                            }
                        } label: {
                            Image(systemName: "plus.circle.fill")
                        }
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $selectedFilter) {
                        ForEach(FilterType.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .sheet(isPresented: $showCreatePlaylist) {
                CreatePlaylistView(musicPlayer: musicPlayer, isPresented: $showCreatePlaylist)
            }
            .sheet(isPresented: $showSpotifyImport) {
                SpotifyImportView(importService: importService, musicPlayer: musicPlayer)
            }
            .alert("Delete \(selectedSongs.count) song(s)?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    for songId in selectedSongs {
                        if let song = musicPlayer.songs.first(where: { $0.id == songId }) {
                            musicPlayer.deleteSong(song)
                        }
                    }
                    selectedSongs.removeAll()
                    isEditMode = false
                }
            } message: {
                Text("This action cannot be undone.")
            }
            .alert("Delete \"\(songToDelete?.title ?? "")\"?", isPresented: $showSingleDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let song = songToDelete {
                        musicPlayer.deleteSong(song)
                    }
                    songToDelete = nil
                }
            } message: {
                Text("This action cannot be undone.")
            }
        }
    }
    
    var emptyMessage: String {
        switch selectedFilter {
        case .all:
            return "No songs in your library yet.\nSearch for songs to get started!"
        case .liked:
            return "No liked songs yet.\nTap the heart on songs you love!"
        case .recent:
            return "No recently played songs.\nPlay some music to see it here!"
        }
    }
}

struct FilterButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .blue : .gray)
                .padding(.vertical, 8)
                .padding(.horizontal, 16)
                .background(
                    isSelected ? Color.blue.opacity(0.15) : Color.clear
                )
                .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
    }
}
