//
//  ProfileView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import SwiftUI

struct ProfileView: View {
    @ObservedObject var musicPlayer: MusicPlayer
    @ObservedObject private var importService = SpotifyImportService.shared
    
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
                    VStack(spacing: 24) {
                        // Profile Header
                        VStack(spacing: 16) {
                            Circle()
                                .fill(Color.gray.opacity(0.15))
                                .frame(width: 120, height: 120)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 50))
                                        .foregroundColor(.gray)
                                )
                            
                            Text("Music Lover")
                                .font(.title)
                                .fontWeight(.bold)
                        }
                        .padding(.top, 40)
                        
                        // Spotify Import Progress (if active)
                        if importService.isImporting || !importService.importQueue.isEmpty {
                            SpotifyDownloadProgress(importService: importService)
                                .padding(.horizontal)
                        }
                        
                        // Stats
                        GlassCard {
                            VStack(spacing: 16) {
                                StatRow(icon: "music.note", title: "Total Songs", value: "\(musicPlayer.songs.count)")
                                Divider()
                                StatRow(icon: "heart.fill", title: "Liked Songs", value: "\(musicPlayer.likedSongs.count)")
                                Divider()
                                StatRow(icon: "music.note.list", title: "Playlists", value: "\(musicPlayer.playlists.count)")
                                Divider()
                                StatRow(icon: "clock.fill", title: "Recently Played", value: "\(musicPlayer.recentSongs.count)")
                            }
                            .padding()
                        }
                        .padding(.horizontal)
                        
                        // Settings Section
                        GlassCard {
                            VStack(spacing: 0) {
                                // Clear Cache Button
                                Button(action: {
                                    clearCache()
                                }) {
                                    HStack {
                                        Image(systemName: "trash")
                                            .font(.body)
                                            .foregroundColor(.red)
                                            .frame(width: 30)
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("Clear Cache")
                                                .fontWeight(.semibold)
                                                .foregroundColor(.primary)
                                            Text("Removes all downloaded songs and metadata")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                        
                                        Spacer()
                                        
                                        if let size = getCacheSizeString() {
                                            Text(size)
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                    }
                                    .padding(.vertical, 8)
                                }
                            }
                            .padding()
                        }
                        .padding(.horizontal)
                        
                        // About
                        GlassCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("About")
                                    .font(.headline)
                                Text("Music App v1.0")
                                    .foregroundColor(.gray)
                                Text("Built with SwiftUI")
                                    .foregroundColor(.gray)
                                Text("© 2025 All rights reserved")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                        }
                        .padding(.horizontal)
                        
                        Spacer(minLength: 100)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    private func clearCache() {
        do {
            try MusicDownloadManager.shared.clearAllCache()
            musicPlayer.songs.removeAll()
            for i in musicPlayer.playlists.indices {
                musicPlayer.playlists[i].songs.removeAll()
            }
        } catch {
            print("❌ Error clearing cache: \(error)")
        }
    }
    
    private func getCacheSizeString() -> String? {
        let bytes = MusicDownloadManager.shared.getCacheSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct StatRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            Text(title)
                .foregroundColor(.black)
            
            Spacer()
            
            Text(value)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
        }
    }
}

struct SettingRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.blue)
                .frame(width: 30)
            
            Text(title)
            
            Spacer()
            
            Text(value)
                .foregroundColor(.gray)
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Spotify Download Progress

struct SpotifyDownloadProgress: View {
    @ObservedObject var importService: SpotifyImportService
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.md) {
                // Header
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.title2)
                        .foregroundColor(DesignSystem.Colors.accent)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Spotify Import")
                            .font(DesignSystem.Typography.title3)
                        Text(importService.currentStep)
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    // Overall stats
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(importService.completedSongs)/\(importService.totalSongs)")
                            .font(DesignSystem.Typography.bodyBold)
                            .foregroundColor(DesignSystem.Colors.primaryText)
                        Text("completed")
                            .font(DesignSystem.Typography.caption)
                            .foregroundColor(DesignSystem.Colors.secondaryText)
                    }
                }
                
                // Progress bar
                ProgressView(value: Double(importService.completedSongs), total: Double(importService.totalSongs))
                    .progressViewStyle(LinearProgressViewStyle(tint: DesignSystem.Colors.accent))
                
                // Status counts
                HStack(spacing: DesignSystem.Spacing.lg) {
                    StatusBadge(
                        icon: "clock.fill",
                        count: importService.importQueue.filter { $0.status == .pending || $0.status == .matching }.count,
                        color: .gray,
                        label: "Pending"
                    )
                    
                    StatusBadge(
                        icon: "arrow.down.circle.fill",
                        count: importService.importQueue.filter { $0.status == .downloading }.count,
                        color: .blue,
                        label: "Downloading"
                    )
                    
                    StatusBadge(
                        icon: "checkmark.circle.fill",
                        count: importService.completedSongs,
                        color: .green,
                        label: "Done"
                    )
                    
                    if importService.failedSongs > 0 {
                        StatusBadge(
                            icon: "xmark.circle.fill",
                            count: importService.failedSongs,
                            color: .red,
                            label: "Failed"
                        )
                    }
                }
                
                // Song list (show first 3)
                if !importService.importQueue.isEmpty {
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(spacing: DesignSystem.Spacing.sm) {
                        ForEach(importService.importQueue.prefix(3)) { song in
                            HStack(spacing: DesignSystem.Spacing.sm) {
                                // Status icon
                                statusIcon(for: song.status)
                                    .font(.caption)
                                    .frame(width: 20)
                                
                                // Song info
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(song.title)
                                        .font(DesignSystem.Typography.callout)
                                        .lineLimit(1)
                                    Text(song.artist)
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(DesignSystem.Colors.secondaryText)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                // Progress/status
                                if song.status == .downloading {
                                    Text("\(Int(song.progress * 100))%")
                                        .font(DesignSystem.Typography.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        
                        if importService.importQueue.count > 3 {
                            Text("+\(importService.importQueue.count - 3) more songs")
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .padding(.top, 4)
                        }
                    }
                }
            }
            .padding(DesignSystem.Spacing.md)
        }
    }
    
    @ViewBuilder
    private func statusIcon(for status: ImportStatus) -> some View {
        switch status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(.gray)
        case .matching:
            ProgressView()
                .scaleEffect(0.7)
        case .downloading:
            Image(systemName: "arrow.down.circle")
                .foregroundColor(.blue)
        case .converting:
            ProgressView()
                .scaleEffect(0.7)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
}

struct StatusBadge: View {
    let icon: String
    let count: Int
    let color: Color
    let label: String
    
    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                Text("\(count)")
                    .font(DesignSystem.Typography.callout)
                    .fontWeight(.semibold)
            }
            .foregroundColor(color)
            
            Text(label)
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }
}
