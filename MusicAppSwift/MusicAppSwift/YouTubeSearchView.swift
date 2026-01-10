//
//  YouTubeSearchView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import SwiftUI

struct YouTubeSearchView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var musicPlayer: MusicPlayer
    var isPresented: Binding<Bool>? = nil
    @State private var searchQuery = ""
    @State private var searchResults: [YouTubeResult] = []
    @State private var isSearching = false
    @State private var downloadingId: String?
    @State private var downloadProgress: String = ""
    @State private var showError = false
    @State private var errorMessage = ""
    
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
                
                if isSearching {
                    ProgressView("Searching...")
                } else if searchResults.isEmpty {
                    ContentUnavailableView(
                        "Search YouTube",
                        systemImage: "magnifyingglass",
                        description: Text("Find and download songs from YouTube")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 12) {
                                ForEach(searchResults) { result in
                                    YouTubeResultRow(
                                        result: result,
                                        isDownloading: downloadingId == result.id,
                                        progress: downloadingId == result.id ? downloadProgress : "",
                                        onDownload: {
                                            downloadSong(result)
                                        }
                                    )
                                }
                            }
                            .padding()
                        }
                    }
                }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchQuery, prompt: "Search YouTube for songs")
            .onSubmit(of: .search) {
                performSearch()
            }
            .alert("Search Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
        }
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        isSearching = true
        searchResults = []
        
        Task {
            await trySearchWithServerFallback()
        }
    }
    
    private func trySearchWithServerFallback() async {
        let query = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        // Try each server host in order with short timeout
        for host in ServerConfig.hosts {
            let urlString = "\(host)/api/search?q=\(query)"
            
            print("🔍 Trying search on: \(host)")
            
            guard let url = URL(string: urlString) else { continue }
            
            var request = URLRequest(url: url)
            request.timeoutInterval = 5.0 // Quick timeout per host
        
            
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    print("❌ Invalid response from \(host)")
                    continue
                }
                
                if httpResponse.statusCode != 200 {
                    print("❌ Server returned \(httpResponse.statusCode) from \(host)")
                    continue
                }
                
                // Success! Parse results
                let results = try JSONDecoder().decode([YouTubeResult].self, from: data)
                print("✅ Found \(results.count) results from \(host)")
                
                await MainActor.run {
                    isSearching = false
                    searchResults = results
                    if results.isEmpty {
                        errorMessage = "No results found for '\(searchQuery)'"
                        showError = true
                    }
                }
                return // Success, stop trying other hosts
                
            } catch {
                print("❌ Failed on \(host): \(error.localizedDescription)")
                continue // Try next host
            }
        }
        
        // All hosts failed
        await MainActor.run {
            isSearching = false
            errorMessage = "Cannot connect to server. Tried: \(ServerConfig.hosts.joined(separator: ", "))"
            showError = true
        }
    }
    
    private func downloadSong(_ result: YouTubeResult) {
        downloadingId = result.id
        downloadProgress = "Starting download..."
        
        Task {
            do {
                // Call the complete Spotify + YouTube pipeline
                let song = try await MusicDownloadManager.shared.downloadAndProcessSong(
                    youtubeURL: "https://youtube.com/watch?v=\(result.videoId)",
                    youtubeTitle: result.title,
                    youtubeDuration: parseDuration(result.duration),
                    progressCallback: { progress in
                        DispatchQueue.main.async {
                            downloadProgress = progress
                            print("📊 Progress: \(progress)")
                        }
                    }
                )
                
                // Add song to player with Spotify metadata
                DispatchQueue.main.async {
                    print("✅ Song created with:")
                    print("   Title: \(song.title)")
                    print("   Artist: \(song.artist)")
                    print("   Artwork Path: \(song.artworkPath ?? "nil")")
                    if let path = song.artworkPath {
                        print("   Artwork exists: \(FileManager.default.fileExists(atPath: path))")
                    }
                    musicPlayer.addSong(song)
                    downloadingId = nil
                    downloadProgress = ""
                    print("✅ Song added to player")
                }
                
            } catch {
                print("❌ Download failed: \(error)")
                DispatchQueue.main.async {
                    downloadingId = nil
                    downloadProgress = "Download failed"
                }
            }
        }
    }
    
    private func parseDuration(_ durationString: String?) -> Double? {
        guard let duration = durationString else { return nil }
        
        // Parse "3:45" format to seconds
        let components = duration.split(separator: ":")
        if components.count == 2,
           let minutes = Double(components[0]),
           let seconds = Double(components[1]) {
            return (minutes * 60) + seconds
        } else if components.count == 3,
                  let hours = Double(components[0]),
                  let minutes = Double(components[1]),
                  let seconds = Double(components[2]) {
            return (hours * 3600) + (minutes * 60) + seconds
        }
        return nil
    }
}

struct YouTubeResultRow: View {
    let result: YouTubeResult
    let isDownloading: Bool
    let progress: String
    let onDownload: () -> Void
    
    var body: some View {
        GlassCard {
            HStack(spacing: 12) {
                // Thumbnail placeholder
                RoundedRectangle(cornerRadius: 6)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [Color(red: 0.478, green: 0.651, blue: 1.0).opacity(0.6), Color(red: 1.0, green: 0.294, blue: 0.698).opacity(0.6)]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(.white)
                            .font(.title3)
                    )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(2)
                    Text(result.displayChannel)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.black.opacity(0.6))
                    Text(result.displayDuration)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.black.opacity(0.6))
                }
                
                Spacer()
                
                if isDownloading {
                    VStack(alignment: .trailing, spacing: 4) {
                        ProgressView()
                        if !progress.isEmpty {
                            Text(progress)
                                .font(.system(size: 10))
                                .foregroundColor(.black.opacity(0.6))
                        }
                    }
                    .padding(.trailing, 8)
                } else {
                    Button(action: onDownload) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

struct YouTubeResult: Identifiable, Codable {
    let id: String
    var videoId: String { return id }
    let title: String
    let channel: String?
    let duration: String?
    let thumbnail: String
    
    var displayChannel: String {
        return channel ?? "Unknown Channel"
    }
    
    var displayDuration: String {
        return duration ?? "Unknown"
    }
}
