//
//  SongInfoView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import SwiftUI

struct SongInfoView: View {
    let song: Song
    @Environment(\.dismiss) var dismiss
    @State private var isRefreshingArtwork = false
    @State private var showRefreshSuccess = false
    @State private var refreshError: String?
    
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
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Album Art
                        RoundedRectangle(cornerRadius: 24)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        Color(hex: "7AA6FF"),
                                        Color(hex: "FF4BB2")
                                    ]),
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 200, height: 200)
                            .overlay(
                                Image(systemName: "music.note")
                                    .font(.system(size: 60, weight: .medium))
                                    .foregroundColor(.white)
                            )
                            .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: 8)
                        
                        // Song Details
                        VStack(spacing: 16) {
                            InfoRow(label: "Title", value: song.title)
                            InfoRow(label: "Artist", value: song.artist)
                            InfoRow(label: "Album", value: song.album)
                            InfoRow(label: "Duration", value: formatDuration(song.duration))
                            if let spotifyId = song.spotifyId {
                                InfoRow(label: "Spotify ID", value: spotifyId)
                            }
                            if let isrc = song.isrc {
                                InfoRow(label: "ISRC", value: isrc)
                            }
                            InfoRow(label: "File URL", value: song.url, isURL: true)
                            InfoRow(label: "Song ID", value: song.id)
                            
                            // Fix Cover Button
                            Button(action: {
                                Task {
                                    await refreshArtwork()
                                }
                            }) {
                                HStack {
                                    if isRefreshingArtwork {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .tint(.white)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 16, weight: .semibold))
                                    }
                                    Text(isRefreshingArtwork ? "Refreshing..." : "Fix Cover from Spotify")
                                        .font(.system(size: 16, weight: .semibold))
                                }
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.blue)
                                )
                            }
                            .disabled(isRefreshingArtwork || song.spotifyId == nil)
                            .opacity(song.spotifyId == nil ? 0.5 : 1.0)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Song Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 16, weight: .semibold))
                }
            }
            .alert("Artwork Refreshed", isPresented: $showRefreshSuccess) {
                Button("OK") { }
            } message: {
                Text("Album cover has been updated from Spotify")
            }
            .alert("Refresh Failed", isPresented: .constant(refreshError != nil)) {
                Button("OK") { refreshError = nil }
            } message: {
                Text(refreshError ?? "Unknown error")
            }
        }
    }
    
    func refreshArtwork() async {
        guard let spotifyId = song.spotifyId else {
            refreshError = "No Spotify ID available"
            return
        }
        
        isRefreshingArtwork = true
        defer { isRefreshingArtwork = false }
        
        do {
            // Re-fetch artwork from Spotify using track ID
            let spotifyService = SpotifyService.shared
            
            // Get track details directly by ID
            guard let trackDetails = try? await spotifyService.fetchTrackById(trackId: spotifyId),
                  let artworkURL = trackDetails.album.highestResImage else {
                refreshError = "Could not fetch album artwork from Spotify"
                return
            }
            
            // Download the artwork
            let artworkData = try await spotifyService.downloadArtwork(from: artworkURL)
            
            // Save with unique filename based on Spotify Track ID
            let songURL = URL(fileURLWithPath: song.url)
            let songDir = songURL.deletingLastPathComponent()
            let uniqueFilename = "\(spotifyId).jpg"
            let artworkPath = songDir.appendingPathComponent(uniqueFilename)
            
            // Delete old artwork files if they exist
            if let files = try? FileManager.default.contentsOfDirectory(at: songDir, includingPropertiesForKeys: nil) {
                for file in files where file.pathExtension.lowercased() == "jpg" {
                    try? FileManager.default.removeItem(at: file)
                    print("🗑️ Deleted old artwork: \(file.lastPathComponent)")
                }
            }
            
            // Write new artwork
            try artworkData.write(to: artworkPath)
            print("✅ Refreshed artwork: \(uniqueFilename)")
            
            showRefreshSuccess = true
        } catch {
            refreshError = "Failed to refresh artwork: \(error.localizedDescription)"
        }
    }
    
    func formatDuration(_ duration: Double) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    var isURL: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.primary)
                .lineLimit(isURL ? 3 : 2)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(0.7))
        )
    }
}
