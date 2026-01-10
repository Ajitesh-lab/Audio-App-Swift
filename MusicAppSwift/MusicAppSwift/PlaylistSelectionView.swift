//
//  PlaylistSelectionView.swift
//  MusicAppSwift
//

import SwiftUI

struct PlaylistSelectionView: View {
    @ObservedObject var importService: SpotifyImportService
    @ObservedObject var musicPlayer: MusicPlayer
    @Environment(\.dismiss) var dismiss
    
    @State private var showError = false
    @State private var errorMessage = ""
    
    var allSelected: Bool {
        importService.selectedPlaylistIds.count == importService.availablePlaylists.count
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: [
                        DesignSystem.Colors.background,
                        DesignSystem.Colors.background.opacity(0.8)
                    ]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header section
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        Image(systemName: "music.note.list")
                            .font(.system(size: 50))
                            .foregroundColor(DesignSystem.Colors.accent)
                            .padding(.top, DesignSystem.Spacing.lg)
                        
                        Text("Select Playlists to Import")
                            .font(DesignSystem.Typography.title)
                            .foregroundColor(DesignSystem.Colors.primaryText)
                        
                        Text("\(importService.selectedPlaylistIds.count) of \(importService.availablePlaylists.count) selected")
                            .font(DesignSystem.Typography.body)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    .padding(.bottom, DesignSystem.Spacing.md)
                    
                    // Select All / Deselect All
                    HStack {
                        Button(action: {
                            if allSelected {
                                importService.selectedPlaylistIds.removeAll()
                            } else {
                                importService.selectedPlaylistIds = Set(importService.availablePlaylists.map { $0.id })
                            }
                        }) {
                            HStack {
                                Image(systemName: allSelected ? "checkmark.square.fill" : "square")
                                    .foregroundColor(DesignSystem.Colors.accent)
                                Text(allSelected ? "Deselect All" : "Select All")
                                    .font(DesignSystem.Typography.bodyMedium)
                                    .foregroundColor(DesignSystem.Colors.primaryText)
                            }
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.vertical, DesignSystem.Spacing.sm)
                            .background(DesignSystem.Colors.secondaryBackground.opacity(0.3))
                            .cornerRadius(DesignSystem.CornerRadius.md)
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, DesignSystem.Spacing.lg)
                    .padding(.bottom, DesignSystem.Spacing.sm)
                    
                    // Playlist list
                    ScrollView {
                        LazyVStack(spacing: DesignSystem.Spacing.sm) {
                            ForEach(importService.availablePlaylists, id: \.id) { playlist in
                                PlaylistRow(
                                    playlist: playlist,
                                    isSelected: importService.selectedPlaylistIds.contains(playlist.id),
                                    onToggle: {
                                        if importService.selectedPlaylistIds.contains(playlist.id) {
                                            importService.selectedPlaylistIds.remove(playlist.id)
                                        } else {
                                            importService.selectedPlaylistIds.insert(playlist.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, DesignSystem.Spacing.lg)
                        .padding(.bottom, DesignSystem.Spacing.xl)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        guard !importService.selectedPlaylistIds.isEmpty else { return }
                        
                        Task {
                            do {
                                guard let token = importService.spotifyToken else {
                                    errorMessage = "No access token available"
                                    showError = true
                                    return
                                }
                                
                                let selectedIds = Array(importService.selectedPlaylistIds)
                                
                                // Dismiss playlist selection first
                                await MainActor.run {
                                    importService.showPlaylistSelection = false
                                    dismiss()
                                }
                                
                                // Small delay to ensure UI updates
                                try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                
                                // Start the import
                                try await importService.startImport(
                                    accessToken: token,
                                    selectedPlaylistIds: selectedIds,
                                    musicPlayer: musicPlayer
                                )
                            } catch {
                                await MainActor.run {
                                    errorMessage = error.localizedDescription
                                    showError = true
                                }
                            }
                        }
                    }) {
                        Text("Import")
                            .fontWeight(.bold)
                            .foregroundColor(importService.selectedPlaylistIds.isEmpty ? .gray : .white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(importService.selectedPlaylistIds.isEmpty ? Color.gray.opacity(0.3) : DesignSystem.Colors.accent)
                            )
                    }
                    .disabled(importService.selectedPlaylistIds.isEmpty)
                }
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
        }
    }
}

struct PlaylistRow: View {
    let playlist: (id: String, name: String)
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: DesignSystem.Spacing.md) {
                // Checkbox
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundColor(isSelected ? DesignSystem.Colors.accent : DesignSystem.Colors.secondaryText)
                
                // Playlist icon
                Image(systemName: "music.note.list")
                    .font(.system(size: 20))
                    .foregroundColor(DesignSystem.Colors.accent)
                    .frame(width: 40, height: 40)
                    .background(DesignSystem.Colors.secondaryBackground.opacity(0.3))
                    .cornerRadius(DesignSystem.CornerRadius.sm)
                
                // Playlist name
                Text(playlist.name)
                    .font(DesignSystem.Typography.body)
                    .foregroundColor(DesignSystem.Colors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
            }
            .padding(DesignSystem.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .fill(isSelected ? DesignSystem.Colors.accent.opacity(0.1) : DesignSystem.Colors.secondaryBackground.opacity(0.3))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.md)
                    .stroke(isSelected ? DesignSystem.Colors.accent.opacity(0.5) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    PlaylistSelectionView(
        importService: SpotifyImportService.shared,
        musicPlayer: MusicPlayer()
    )
}
