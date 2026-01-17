//
//  SpotifyImportService.swift
//  MusicAppSwift
//
//  Complete Spotify playlist import pipeline
//

import Foundation
import Combine
import AVFoundation
import CoreMedia
import UIKit
import CryptoKit

enum ImportStatus: String, Codable {
    case pending
    case matching
    case downloading
    case converting
    case done
    case failed
}

struct ImportSong: Identifiable, Codable {
    let id: UUID
    let title: String
    let artist: String
    var status: ImportStatus
    var progress: Double
    var errorMessage: String?
    var playlistId: String? // Track which playlist this song belongs to
    var songId: String? // Track the actual Song ID after it's added to library
    var spotifyTrackId: String? // Spotify track ID for accurate artwork lookup
    var albumArtworkURL: String? // Direct Spotify album artwork URL
    var failureStage: String? // Track where the failure occurred
    var debugInfo: [String: String]? // Store debug information
    
    var searchQuery: String {
        "\(title) - \(artist)"
    }
    
    var youtubeQuery: String {
        "\(title) \(artist) official audio"
    }
}

struct PlaylistInfo {
    let id: String
    let name: String
    var artworkURL: String?
}

class SpotifyImportService: ObservableObject {
    static let shared = SpotifyImportService()
    
    @Published var isImporting = false
    @Published var currentStep = ""
    @Published var importQueue: [ImportSong] = []
    @Published var totalSongs = 0
    @Published var completedSongs = 0
    @Published var failedSongs = 0
    @Published var isAuthenticated = false
    @Published var availablePlaylists: [(id: String, name: String)] = []
    @Published var selectedPlaylistIds: Set<String> = []
    @Published var showPlaylistSelection = false
    
    var spotifyToken: String?
    var playlistsInfo: [String: PlaylistInfo] = [:] // Map playlist ID to info including artwork // Made public for access from SpotifyImportView
    private var cancellables = Set<AnyCancellable>()
    private let artworkService = SpotifyService.shared
    var hasStartedFetchingPlaylists = false // Flag to prevent duplicate fetches
    private var lastDownloadTime: Date?
    private let minimumDownloadInterval: TimeInterval = 5.0 // Rate limit: 5 seconds between downloads
    
    // Performance optimization: Debounce progress updates
    private let progressDebouncer = Debouncer()
    
    private init() {} // Private init for singleton
    
    // MARK: - Validation & Logging Helpers
    
    private func logFailure(song: inout ImportSong, stage: String, error: Error, debugInfo: [String: String] = [:]) {
        song.failureStage = stage
        var fullDebugInfo = debugInfo
        fullDebugInfo["error"] = error.localizedDescription
        fullDebugInfo["spotifyTrackId"] = song.spotifyTrackId ?? "nil"
        fullDebugInfo["albumArtworkURL"] = song.albumArtworkURL ?? "nil"
        song.debugInfo = fullDebugInfo
        
        print("""
        ❌ FAILURE DEBUG LOG
        Song: \(song.title) - \(song.artist)
        Stage: \(stage)
        Spotify Track ID: \(song.spotifyTrackId ?? "nil")
        Album Artwork: \(song.albumArtworkURL ?? "nil")
        Error: \(error.localizedDescription)
        Debug Info: \(fullDebugInfo)
        ========================================
        """)
    }
    
    private func validateAudioFile(at url: URL) async throws -> Bool {
        // Check file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "Validation", code: 1, userInfo: [NSLocalizedDescriptionKey: "File does not exist"])
        }
        
        // Check file size > 200KB
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let fileSize = attributes[.size] as? Int64, fileSize > 200_000 else {
            throw NSError(domain: "Validation", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "File too small (\(attributes[.size] ?? 0) bytes)"
            ])
        }
        
        // Read file header to detect container type
        let fileHandle = try FileHandle(forReadingFrom: url)
        let headerData = fileHandle.readData(ofLength: 16)
        fileHandle.closeFile()
        
        let headerHex = headerData.map { String(format: "%02x", $0) }.joined()
        print("📄 File header: \(headerHex)")
        
        // Check for valid audio headers
        let headerString = String(data: headerData, encoding: .ascii) ?? ""
        let isValidAudio = headerData.count >= 4 && (
            headerString.contains("ftyp") ||  // MP4/M4A
            headerString.hasPrefix("ID3") ||   // MP3 with ID3
            headerData[0] == 0xFF && headerData[1] == 0xFB || // MP3 frame
            headerString.hasPrefix("OggS") ||  // Ogg/Opus
            headerString.hasPrefix("RIFF")     // WAV/WebM
        )
        
        // Reject HTML/JSON/Text files
        if headerString.contains("<html") || headerString.contains("<!DOCTYPE") ||
           headerString.hasPrefix("{") || headerString.hasPrefix("[") {
            throw NSError(domain: "Validation", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "File is not audio (detected HTML/JSON/text content)"
            ])
        }
        
        guard isValidAudio else {
            throw NSError(domain: "Validation", code: 4, userInfo: [
                NSLocalizedDescriptionKey: "Invalid audio file header: \(headerHex)"
            ])
        }
        
        // Try to load with AVAsset to verify it's valid audio
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Check duration > 30 seconds (reject very short files)
        guard durationSeconds > 30 else {
            throw NSError(domain: "Validation", code: 5, userInfo: [
                NSLocalizedDescriptionKey: "Duration too short (\(durationSeconds)s)"
            ])
        }
        
        print("✅ Audio validation passed: \(fileSize / 1024)KB, \(Int(durationSeconds))s, valid header")
        return true
    }
    
    private func rateLimit() async {
        if let lastTime = lastDownloadTime {
            let elapsed = Date().timeIntervalSince(lastTime)
            if elapsed < minimumDownloadInterval {
                let waitTime = minimumDownloadInterval - elapsed
                print("⏱️ Rate limiting: waiting \(String(format: "%.1f", waitTime))s")
                try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
            }
        }
        lastDownloadTime = Date()
    }
    
    // Spotify OAuth Configuration
    private let clientId = "3cd7324b050c4cf4b02c09e38cce2407"
    private let redirectUri = "musicappswift://spotify-callback"
    // Include library scope for liked songs and ensure playlist scopes are requested.
    private let scopes = "playlist-read-private playlist-read-collaborative user-library-read"
    
    // PKCE for secure mobile OAuth
    private var codeVerifier: String = ""
    private var codeChallenge: String = ""
    
    // UI state for OAuth → playlist selection handoff
    @Published var isFetchingPlaylists = false
    
    // MARK: - OAuth Login with PKCE
    
    func getSpotifyAuthURL() -> URL? {
        // Generate PKCE parameters
        codeVerifier = generateCodeVerifier()
        codeChallenge = generateCodeChallenge(from: codeVerifier)
        
        var components = URLComponents(string: "https://accounts.spotify.com/authorize")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectUri),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "show_dialog", value: "true")
        ]
        return components?.url
    }
    
    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return Data(buffer).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    private func generateCodeChallenge(from verifier: String) -> String {
        guard let data = verifier.data(using: .utf8) else { return "" }
        let hash = SHA256.hash(data: data)
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespaces)
    }
    
    func handleAuthCallback(url: URL) async throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw NSError(domain: "SpotifyImport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid callback URL"])
        }
        
        print("✅ Received auth code: \(code.prefix(10))...")
        
        // Exchange code for token via your backend
        let token = try await exchangeCodeForToken(code: code)
        
        print("✅ Got access token: \(token.prefix(20))...")
        
        await MainActor.run {
            self.spotifyToken = token
            self.hasStartedFetchingPlaylists = true
            self.isAuthenticated = true
            self.isFetchingPlaylists = true
            self.currentStep = "Connecting to Spotify..."
            print("🎯 isAuthenticated set to true, starting playlist fetch")
        }
        
        // Immediately fetch playlists to drive the selection sheet
        Task {
            do {
                try await self.fetchPlaylistsForSelection(accessToken: token)
            } catch {
                await MainActor.run {
                    self.hasStartedFetchingPlaylists = false
                    self.isAuthenticated = false
                    self.isFetchingPlaylists = false
                }
                print("❌ Failed to fetch playlists after auth: \(error)")
            }
        }
    }
    
    private func exchangeCodeForToken(code: String) async throws -> String {
        // Call your backend to exchange code for token
        // Your backend should handle client_secret securely
        let serverURL = "https://audio-rough-water-3069.fly.dev/api/spotify/token"
        
        print("🔄 Exchanging code for token...")
        
        guard let url = URL(string: serverURL) else {
            throw NSError(domain: "SpotifyImport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = [
            "code": code,
            "redirect_uri": redirectUri,
            "code_verifier": codeVerifier
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "SpotifyImport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Invalid response from server"])
        }
        
        print("📡 Server response status: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("❌ Server error: \(errorBody)")
            throw NSError(domain: "SpotifyImport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Token exchange failed: \(errorBody)"])
        }
        
        let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
        return tokenResponse.access_token
    }
    
    // MARK: - 1️⃣ Import Spotify Playlists
    
    /// Fetch available playlists and show selection screen
    func fetchPlaylistsForSelection(accessToken: String) async throws {
        await MainActor.run {
            isFetchingPlaylists = true
        }
        await MainActor.run {
            currentStep = "Fetching playlists..."
            // Don't manipulate isAuthenticated here
        }
        
        let playlists = try await fetchAllPlaylists(token: accessToken)
        print("✅ Fetched \(playlists.count) playlists for selection")
        
        await MainActor.run {
            self.availablePlaylists = playlists
            self.showPlaylistSelection = true
            self.isFetchingPlaylists = false
            print("🎯 Setting showPlaylistSelection = true")
        }
    }
    
    func startImport(accessToken: String, selectedPlaylistIds: [String], musicPlayer: MusicPlayer) async throws {
        await MainActor.run {
            isImporting = true
            currentStep = "Fetching playlists..."
            importQueue.removeAll()
            totalSongs = 0
            completedSongs = 0
            failedSongs = 0
        }
        
        spotifyToken = accessToken
        
        // Step A: Fetch all playlists (or use cached ones)
        let allPlaylists = availablePlaylists.isEmpty ? try await fetchAllPlaylists(token: accessToken) : availablePlaylists
        
        // Filter to only selected playlists
        let playlistsToFetch = allPlaylists.filter { selectedPlaylistIds.contains($0.id) }
        print("✅ Importing \(playlistsToFetch.count) selected playlists")
        
        await MainActor.run {
            currentStep = "Fetching tracks from \(playlistsToFetch.count) playlists..."
        }
        
        // Step B: Fetch songs from selected playlists with playlist tracking
        var allImportSongs: [ImportSong] = []
        
        for (index, playlist) in playlistsToFetch.enumerated() {
            await MainActor.run {
                currentStep = "Fetching playlist \(index + 1)/\(playlistsToFetch.count)..."
            }
            
            // Fetch playlist details including artwork
            let playlistDetails = try await fetchPlaylistDetails(playlistId: playlist.id, token: accessToken)
            playlistsInfo[playlist.id] = playlistDetails
            
            let songs = try await fetchPlaylistTracks(playlistId: playlist.id, token: accessToken)
            
            // Create ImportSong objects with playlist tracking and Spotify metadata
            let importSongs = songs.map { track -> ImportSong in
                return ImportSong(
                    id: UUID(),
                    title: track.title,
                    artist: track.artist,
                    status: .pending,
                    progress: 0.0,
                    playlistId: playlist.id,
                    spotifyTrackId: track.trackId,
                    albumArtworkURL: track.artworkURL
                )
            }
            
            allImportSongs.append(contentsOf: importSongs)
            
            print("✅ Fetched \(songs.count) songs from \(playlist.name)")
        }
        
        // Remove duplicates while preserving playlist info and metadata for first occurrence
        var seenSongs = Set<String>()
        var uniqueImportSongs: [ImportSong] = []
        
        for song in allImportSongs {
            let key = "\(song.spotifyTrackId ?? "")"
            if !seenSongs.contains(key) {
                seenSongs.insert(key)
                uniqueImportSongs.append(song)
            }
        }
        
        print("✅ Total unique songs: \(uniqueImportSongs.count) (removed \(allImportSongs.count - uniqueImportSongs.count) duplicates)")
        
        // MARK: - 2️⃣ Build Download Queue
        
        await MainActor.run {
            currentStep = "Building download queue..."
            importQueue = uniqueImportSongs
            totalSongs = importQueue.count
            currentStep = "Ready to download \(totalSongs) songs"
        }
        
        // MARK: - 3️⃣ Process Download Queue
        
        await processDownloadQueue(musicPlayer: musicPlayer)
    }
    
    // MARK: - Spotify API Calls
    
    private func fetchAllPlaylists(token: String) async throws -> [(id: String, name: String)] {
        var allPlaylists: [(id: String, name: String)] = []
        var nextURL: String? = "https://api.spotify.com/v1/me/playlists?limit=50"
        
        while let urlString = nextURL {
            guard let url = URL(string: urlString) else { break }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SpotifyPlaylistsResponse.self, from: data)
            
            allPlaylists.append(contentsOf: response.items.map { ($0.id, $0.name) })
            nextURL = response.next
        }
        
        return allPlaylists
    }
    
    private func fetchPlaylistDetails(playlistId: String, token: String) async throws -> PlaylistInfo {
        let urlString = "https://api.spotify.com/v1/playlists/\(playlistId)"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "SpotifyImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(SpotifyPlaylistDetailsResponse.self, from: data)
        
        // Get largest image URL
        let artworkURL = response.images.first?.url
        
        return PlaylistInfo(id: playlistId, name: response.name, artworkURL: artworkURL)
    }
    
    private func fetchPlaylistTracks(playlistId: String, token: String) async throws -> [(title: String, artist: String, trackId: String, artworkURL: String?)] {
        var allTracks: [(title: String, artist: String, trackId: String, artworkURL: String?)] = []
        var nextURL: String? = "https://api.spotify.com/v1/playlists/\(playlistId)/tracks?limit=100"
        var filteredCount = 0
        
        while let urlString = nextURL {
            guard let url = URL(string: urlString) else { break }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(SpotifyTracksResponse.self, from: data)
            
            let tracks = response.items.compactMap { item -> (title: String, artist: String, trackId: String, artworkURL: String?)? in
                guard let track = item.track else { return nil }
                let title = track.name
                let artist = track.artists.first?.name ?? "Unknown Artist"
                let trackId = track.id
                
                // Get highest resolution album artwork (first image is typically largest)
                guard let artworkURL = track.album.images.first?.url else {
                    filteredCount += 1
                    print("⚠️ Filtered out: '\(title)' - No album artwork available")
                    return nil
                }
                
                // Filter out low-quality or placeholder artwork
                // Spotify provides images in order of quality (largest first)
                // Ensure we have at least a decent resolution image
                if let firstImage = track.album.images.first,
                   let width = firstImage.width, let height = firstImage.height {
                    // Require at least 300x300 for acceptable quality
                    if width < 300 || height < 300 {
                        filteredCount += 1
                        print("⚠️ Filtered out: '\(title)' - Low quality artwork (\(width)x\(height))")
                        return nil
                    }
                }
                
                return (title: title, artist: artist, trackId: trackId, artworkURL: artworkURL)
            }
            
            allTracks.append(contentsOf: tracks)
            nextURL = response.next
        }
        
        if filteredCount > 0 {
            print("📊 Filtered out \(filteredCount) tracks due to missing/low-quality album artwork")
        }
        
        return allTracks
    }
    
    // MARK: - 3️⃣ Process Downloads
    
    private func processDownloadQueue(musicPlayer: MusicPlayer) async {
        await MainActor.run {
            currentStep = "Downloading songs..."
        }
        
        Logger.log("Starting download queue processing...", category: "Import")
        Logger.log("Total songs to process: \(importQueue.count)", category: "Import")
        
        // Process songs in concurrent batches (5 at a time) for 5x speedup
        let batchSize = 5
        
        for batchStart in stride(from: 0, to: importQueue.count, by: batchSize) {
            let batchEnd = min(batchStart + batchSize, importQueue.count)
            let batch = batchStart..<batchEnd
            
            Logger.log("Processing batch \(batchStart/batchSize + 1): songs \(batchStart+1)-\(batchEnd)", category: "Import")
            
            // Process batch concurrently
            await withTaskGroup(of: Void.self) { group in
                for i in batch {
                    group.addTask {
                        await self.processSong(at: i, musicPlayer: musicPlayer)
                    }
                }
            }
        }
        
        Logger.log("Download queue processing finished", category: "Import")
        
        await MainActor.run {
            currentStep = "Creating playlists..."
            Logger.log("Starting playlist creation...", category: "Import")
        }
        
        // Automatically create playlists after all downloads complete
        await MainActor.run {
            Logger.log("About to call createImportedPlaylists", category: "Import")
            createImportedPlaylists(musicPlayer: musicPlayer)
            Logger.success("createImportedPlaylists completed", category: "Import")
        }
        
        await MainActor.run {
            currentStep = "Import complete!"
            isImporting = false
            Logger.success("Import process finished. Total playlists: \(playlistsInfo.count)", category: "Import")
        }
    }
    
    private func processSong(at index: Int, musicPlayer: MusicPlayer) async {
        guard index < importQueue.count else { return }
        
        var song = importQueue[index]
        
        // Rate limiting
        await rateLimit()
        
        // Validate Spotify metadata FIRST
        if song.spotifyTrackId == nil {
            await MainActor.run {
                song.status = .failed
                song.errorMessage = "No Spotify track ID"
                logFailure(song: &song, stage: "spotify_metadata", error: NSError(
                    domain: "Validation",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Missing Spotify track ID"]
                ))
                importQueue[index] = song
                failedSongs += 1
            }
            return
        }
        
        if song.albumArtworkURL == nil {
            print("⚠️ Warning: No album artwork for \(song.title) - will attempt to fetch")
        }
        
        // Update status: Matching
        await MainActor.run {
            song.status = .matching
            importQueue[index] = song
        }
        
        do {
            // Step A: Search YouTube with multiple query variations
            var youtubeResult: String?
            var usedQuery: String = ""
            let searchQueries = [
                "\(song.title) \(song.artist) official audio",
                "\(song.title) \(song.artist) audio",
                "\(song.title) \(song.artist) topic",
                "\(song.artist) \(song.title)"
            ]
            
            print("""
            🎵 ========================================
            Starting isolated download for:
            Track: \(song.title)
            Artist: \(song.artist)
            Spotify ID: \(song.spotifyTrackId ?? "nil")
            ========================================
            """)
            
            for (attemptIndex, query) in searchQueries.enumerated() {
                print("🔍 YouTube search attempt \(attemptIndex + 1)/\(searchQueries.count): \(query)")
                youtubeResult = try await searchYouTube(query: query)
                if youtubeResult != nil {
                    usedQuery = query
                    print("✅ Found match with query: \(query)")
                    print("📹 Video ID: \(youtubeResult!)")
                    break
                }
                // Wait a bit between search attempts
                if attemptIndex < searchQueries.count - 1 {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s
                }
            }
            
            guard let videoId = youtubeResult else {
                throw NSError(domain: "YouTube", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "No YouTube match found after \(searchQueries.count) attempts"
                ])
            }
            
            // Log download context
            print("""
            📥 ========================================
            Downloading audio:
            Track: \(song.title)
            Query Used: \(usedQuery)
            Video ID: \(videoId)
            ========================================
            """)
            
            // Step B: Download
            await MainActor.run {
                song.status = .downloading
                song.debugInfo = [
                    "searchQuery": usedQuery,
                    "videoId": videoId
                ]
                importQueue[index] = song
            }
            
            let downloadedFile = try await downloadAudio(youtubeResult: videoId) { progress in
                // Debounce progress updates to reduce UI churn
                await self.progressDebouncer.debounce(duration: .milliseconds(200)) {
                    await MainActor.run {
                        song.progress = progress
                        self.importQueue[index] = song
                    }
                }
            }
            
            // Step B.5: VALIDATE downloaded file
            print("🔍 Validating downloaded audio file...")
            do {
                _ = try await validateAudioFile(at: downloadedFile)
            } catch {
                // Delete invalid file
                try? FileManager.default.removeItem(at: downloadedFile)
                throw NSError(domain: "Validation", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Downloaded audio file validation failed: \(error.localizedDescription)"
                ])
            }
            
            // Step C: Convert & Tag
            await MainActor.run {
                song.status = .converting
                song.progress = 0.9
                importQueue[index] = song
            }
            
            let finalFile = try await convertAndTag(
                file: downloadedFile,
                title: song.title,
                artist: song.artist
            )
            
            // Step C.5: VALIDATE final file
            print("🔍 Validating final audio file...")
            do {
                _ = try await validateAudioFile(at: finalFile)
            } catch {
                // Delete invalid file
                try? FileManager.default.removeItem(at: finalFile)
                throw NSError(domain: "Validation", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Final audio file validation failed: \(error.localizedDescription)"
                ])
            }
            
            // Step D: Save to library and get the song ID
            let addedSongId = try await saveToLibrary(
                file: finalFile, 
                title: song.title, 
                artist: song.artist, 
                artworkURL: song.albumArtworkURL,
                musicPlayer: musicPlayer
            )
            
            // Mark as complete and track song ID
            await MainActor.run {
                song.status = .done
                song.progress = 1.0
                song.songId = addedSongId
                self.importQueue[index] = song
                self.completedSongs += 1
            }
            
            print("✅ Completed: \(song.title) - \(song.artist)")
            
        } catch {
            // Determine failure stage from error domain
            let stage: String
            if (error as NSError).domain == "YouTube" {
                stage = "youtube_search"
            } else if (error as NSError).domain == "Validation" {
                stage = "audio_validation"
            } else if error.localizedDescription.contains("Download") {
                stage = "download"
            } else if error.localizedDescription.contains("AVFoundation") {
                stage = "avfoundation"
            } else {
                stage = "unknown"
            }
            
            await MainActor.run {
                song.status = .failed
                song.errorMessage = error.localizedDescription
                
                // Enhanced debug info
                var debugInfo = song.debugInfo ?? [:]
                debugInfo["failureStage"] = stage
                debugInfo["error"] = error.localizedDescription
                debugInfo["errorDomain"] = (error as NSError).domain
                debugInfo["errorCode"] = String((error as NSError).code)
                song.debugInfo = debugInfo
                
                logFailure(song: &song, stage: stage, error: error, debugInfo: debugInfo)
                importQueue[index] = song
                failedSongs += 1
            }
            
            print("""
            ❌ FAILURE DEBUG LOG
            Track: \(song.title) - \(song.artist)
            Spotify ID: \(song.spotifyTrackId ?? "nil")
            Search Query: \(song.debugInfo?["searchQuery"] ?? "unknown")
            Video ID: \(song.debugInfo?["videoId"] ?? "unknown")
            Failure Stage: \(stage)
            Error: \(error.localizedDescription)
            Full Debug: \(song.debugInfo ?? [:])
            ========================================
            """)
        }
    }
    
    // MARK: - YouTube Search & Download Integration
    
    private func searchYouTube(query: String) async throws -> String? {
        let serverURL = "https://audio-rough-water-3069.fly.dev/api/search"
        
        guard var components = URLComponents(string: serverURL) else {
            throw NSError(domain: "SpotifyImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"])
        }
        
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        
        guard let url = components.url else {
            throw NSError(domain: "SpotifyImport", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create search URL"])
        }
        
        Logger.debug("Searching YouTube: \(query)", category: "Import")
        let (data, _) = try await URLSession.shared.data(from: url)
        
        // Move JSON parsing to background thread to avoid blocking UI
        let results = try await Task.detached(priority: .userInitiated) {
            try JSONDecoder().decode([YouTubeSearchResult].self, from: data)
        }.value
        
        // Filter results on background thread too
        return await Task.detached {
            let filtered = results.filter { result in
                let titleLower = result.title.lowercased()
                let rejectTerms = ["live", "remix", "cover", "karaoke", "instrumental", "reaction"]
                return !rejectTerms.contains(where: { titleLower.contains($0) })
            }
            
            guard let firstResult = filtered.first else {
                Logger.log("No valid results after filtering", category: "Import")
                return results.first?.id // Fallback to unfiltered if all rejected
            }
            
            Logger.success("Selected: \(firstResult.title)", category: "Import")
            return firstResult.id
        }.value
    }
    
    private func downloadAudio(youtubeResult: String, onProgress: @escaping (Double) async -> Void) async throws -> URL {
        Logger.log("Starting download with fallback for: \(youtubeResult)", category: "Import")
        
        // Use fallback service to try multiple APIs.
        let tempURL = try await DownloadFallbackService.shared.downloadWithFallback(
            videoId: youtubeResult,
            progressCallback: { progress in
                Logger.log(progress, category: "Import")
                Task { await onProgress(0.8) }
            }
        )
        
        Logger.success("Download completed for: \(youtubeResult)", category: "Import")
        
        let workingDir = try ensureWorkingDirectory()
        let fileExtension = tempURL.pathExtension.isEmpty ? "m4a" : tempURL.pathExtension
        let localPath = workingDir.appendingPathComponent("\(UUID().uuidString)_\(youtubeResult).\(fileExtension)")
        
        // Move download into our managed folder (overwrite if needed).
        try? FileManager.default.removeItem(at: localPath)
        try FileManager.default.moveItem(at: tempURL, to: localPath)
        
        await onProgress(1.0)
        
        return localPath
    }
    
    private func convertAndTag(file: URL, title: String, artist: String) async throws -> URL {
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw ImportError.downloadFailed
        }
        
        let appMusicDirectory = try ensureMusicDirectory()
        
        // Create safe filename with proper extension
        let safeFilename = "\(UUID().uuidString).m4a"
        let finalPath = appMusicDirectory.appendingPathComponent(safeFilename)
        
        // Tag metadata using AVFoundation, exporting directly to the final path
        let asset = AVURLAsset(url: file)
        guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ImportError.conversionFailed
        }
        
        exportSession.outputURL = finalPath
        exportSession.outputFileType = .m4a
        
        let titleMetadata = AVMutableMetadataItem()
        titleMetadata.identifier = .commonIdentifierTitle
        titleMetadata.value = title as NSString
        titleMetadata.extendedLanguageTag = "und"
        
        let artistMetadata = AVMutableMetadataItem()
        artistMetadata.identifier = .commonIdentifierArtist
        artistMetadata.value = artist as NSString
        artistMetadata.extendedLanguageTag = "und"
        
        exportSession.metadata = [titleMetadata, artistMetadata]
        
        if #available(iOS 18.0, *) {
            // New API avoids deprecated status/error properties
            try await exportSession.export(to: finalPath, as: .m4a)
        } else {
            // Remove any existing file at destination for legacy export path
            try? FileManager.default.removeItem(at: finalPath)
            await withCheckedContinuation { continuation in
                exportSession.exportAsynchronously {
                    continuation.resume()
                }
            }
        }
        
        guard FileManager.default.fileExists(atPath: finalPath.path) else {
            throw ImportError.conversionFailed
        }
        
        // Clean up original download
        try? FileManager.default.removeItem(at: file)
        
        return finalPath
    }
    
    private func ensureMusicDirectory() throws -> URL {
        // Use Application Support directory (best practice for app-managed media on iOS)
        guard let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "SpotifyImport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not access Application Support directory"])
        }
        
        let musicDirectory = appSupportDirectory.appendingPathComponent("Music", isDirectory: true)
        
        // Create with intermediate directories if needed
        if !FileManager.default.fileExists(atPath: musicDirectory.path) {
            try FileManager.default.createDirectory(at: musicDirectory, withIntermediateDirectories: true, attributes: nil)
        }
        
        return musicDirectory
    }
    
    private func ensureWorkingDirectory() throws -> URL {
        guard let appSupportDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "SpotifyImport", code: 5, userInfo: [NSLocalizedDescriptionKey: "Could not access Application Support directory"])
        }
        
        let downloadsDir = appSupportDirectory.appendingPathComponent("Downloads", isDirectory: true)
        
        // Create with intermediate directories if needed
        if !FileManager.default.fileExists(atPath: downloadsDir.path) {
            try FileManager.default.createDirectory(at: downloadsDir, withIntermediateDirectories: true, attributes: nil)
        }
        
        return downloadsDir
    }
    
    private func fetchArtworkData(artist: String, title: String) async throws -> Data? {
        do {
            if let track = try await artworkService.searchTrack(artist: artist, track: title) {
                var artworkURL = track.album.highestResImage
                
                // Try album details for higher-res art
                if let albumArt = try? await artworkService.fetchAlbumDetails(albumId: track.album.id).highestResImage {
                    artworkURL = albumArt
                }
                
                if let urlString = artworkURL {
                    return try await artworkService.downloadArtwork(from: urlString)
                }
            }
        } catch {
            print("⚠️ Artwork lookup failed for \(title) - \(artist): \(error)")
        }
        return nil
    }
    
    private func saveToLibrary(file: URL, title: String, artist: String, artworkURL: String?, musicPlayer: MusicPlayer) async throws -> String {
        // Get file duration
        let asset = AVURLAsset(url: file)
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Fetch and persist artwork from Spotify URL directly
        let songId = UUID().uuidString
        var artworkPath: String?
        
        if let urlString = artworkURL, let url = URL(string: urlString) {
            do {
                print("📥 Downloading artwork from Spotify: \(urlString)")
                let (data, _) = try await URLSession.shared.data(from: url)
                let artworkFile = file.deletingLastPathComponent().appendingPathComponent("\(songId)_artwork.jpg")
                try data.write(to: artworkFile)
                artworkPath = artworkFile.path
                print("✅ Saved artwork for \(title)")
            } catch {
                print("⚠️ Failed to download/save artwork for \(title): \(error)")
            }
        } else {
            print("⚠️ No artwork URL provided for \(title)")
        }
        
        // Create Song object
        let newSong = Song(
            id: songId,
            title: title,
            artist: artist,
            album: "Spotify Import",
            duration: durationSeconds,
            url: file.absoluteString,
            spotifyTrackId: songId,       // ✅ Use song ID as Spotify track ID
            artworkURL: artworkURL,        // ✅ Original artwork URL
            artworkPath: artworkPath,
            spotifyId: songId,             // Legacy field
            isrc: nil,
            videoId: nil,
            audioFingerprint: nil
        )
        
        // Add to MusicPlayer on main thread
        await MainActor.run {
            musicPlayer.addSong(newSong)
        }
        
        return songId
    }
    
    // MARK: - 4️⃣ Create Playlists (one per Spotify playlist)
    
    func createImportedPlaylists(musicPlayer: MusicPlayer) {
        print("🎵 createImportedPlaylists called")
        print("📊 Current musicPlayer.playlists count: \(musicPlayer.playlists.count)")
        
        let completedSongs = importQueue.filter { $0.status == .done }
        
        guard !completedSongs.isEmpty else {
            print("⚠️ No songs completed successfully")
            return
        }
        
        print("📋 Creating playlists for \(completedSongs.count) completed songs")
        print("📁 playlistsInfo contains \(playlistsInfo.count) playlists")
        
        // Group songs by playlist ID
        var songsByPlaylist: [String: [ImportSong]] = [:]
        for song in completedSongs {
            guard let playlistId = song.playlistId else {
                print("⚠️ Song '\(song.title)' has no playlistId")
                continue
            }
            songsByPlaylist[playlistId, default: []].append(song)
            print("📌 Song '\(song.title)' -> playlist \(playlistId), songId: \(song.songId ?? "nil")")
        }
        
        print("📊 Songs grouped into \(songsByPlaylist.count) playlists")
        
        // Create a playlist for each Spotify playlist
        for (playlistId, songs) in songsByPlaylist {
            guard let playlistInfo = playlistsInfo[playlistId] else {
                print("⚠️ No playlist info found for ID: \(playlistId)")
                continue
            }
            
            let songIds = songs.compactMap { $0.songId }
            
            print("🎵 Playlist '\(playlistInfo.name)': \(songs.count) songs, \(songIds.count) with IDs")
            
            guard !songIds.isEmpty else {
                print("⚠️ No valid song IDs for playlist '\(playlistInfo.name)'")
                continue
            }
            
            // Generate mosaic cover from first 4 songs
            let mosaicCoverPath = generatePlaylistMosaicCover(songIds: songIds, musicPlayer: musicPlayer)
            
            let playlist = Playlist(
                id: UUID().uuidString,
                name: playlistInfo.name, // Use original Spotify playlist name
                songs: songIds,
                color: "7AA6FF",
                coverImageURL: mosaicCoverPath ?? playlistInfo.artworkURL, // Use mosaic or fallback to Spotify artwork
                createdDate: Date()
            )
            
            // Add playlist to music player
            musicPlayer.playlists.append(playlist)
            
            print("✅ Created playlist: \(playlist.name) with \(songIds.count) songs, cover: \(mosaicCoverPath ?? "none")")
            print("📊 musicPlayer now has \(musicPlayer.playlists.count) playlists")
        }
        
        print("🎉 Finished creating \(songsByPlaylist.count) playlists")
        print("📊 Final musicPlayer.playlists count: \(musicPlayer.playlists.count)")
        
        // Trigger save (music player will handle persistence)
        NotificationCenter.default.post(name: NSNotification.Name("PlaylistsChanged"), object: nil)
        print("📢 Posted PlaylistsChanged notification")
    }
    
    // MARK: - Generate Playlist Mosaic Cover
    
    private func generatePlaylistMosaicCover(songIds: [String], musicPlayer: MusicPlayer) -> String? {
        print("🎨 Generating mosaic cover from \(songIds.count) songs")
        print("   Song IDs: \(songIds.prefix(4))")
        
        // Get first 4 songs in order
        let firstFourSongs = Array(songIds.prefix(4)).compactMap { id in
            musicPlayer.songs.first(where: { $0.id == id })
        }
        
        print("   Found \(firstFourSongs.count) songs for mosaic")
        for (index, song) in firstFourSongs.enumerated() {
            print("   [\(index)] \(song.title) - artwork: \(song.artworkPath != nil)")
        }
        
        guard !firstFourSongs.isEmpty else {
            print("⚠️ No songs found for mosaic cover generation")
            return nil
        }
        
        // Load artwork images
        let images = firstFourSongs.compactMap { song -> UIImage? in
            guard let artworkPath = song.artworkPath else {
                print("⚠️ No artwork path for song: \(song.title)")
                return nil
            }
            return UIImage(contentsOfFile: artworkPath)
        }
        
        guard !images.isEmpty else {
            print("⚠️ No artwork images loaded for mosaic")
            return nil
        }
        
        // Create 2x2 mosaic (640x640 total, 320x320 per cell)
        let size = CGSize(width: 640, height: 640)
        let cellSize = CGSize(width: 320, height: 320)
        
        UIGraphicsBeginImageContextWithOptions(size, false, 1.0)
        defer { UIGraphicsEndImageContext() }
        
        for (index, image) in images.enumerated() {
            let row = index / 2
            let col = index % 2
            let x = CGFloat(col) * cellSize.width
            let y = CGFloat(row) * cellSize.height
            
            let rect = CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)
            image.draw(in: rect)
        }
        
        guard let mosaicImage = UIGraphicsGetImageFromCurrentImageContext(),
              let imageData = mosaicImage.jpegData(compressionQuality: 0.9) else {
            print("⚠️ Failed to generate mosaic image")
            return nil
        }
        
        // Save mosaic to disk
        let mosaicId = UUID().uuidString
        guard let workingDir = try? ensureWorkingDirectory() else {
            print("⚠️ Failed to resolve working directory for mosaic cover")
            return nil
        }
        let mosaicPath = workingDir.appendingPathComponent("\(mosaicId)_mosaic.jpg")
        
        do {
            try imageData.write(to: mosaicPath)
            print("✅ Saved mosaic cover to: \(mosaicPath.path)")
            return mosaicPath.path
        } catch {
            print("⚠️ Failed to save mosaic cover: \(error)")
            return nil
        }
    }
}

// MARK: - OAuth Response Model

struct TokenResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
}

// MARK: - YouTube API Response Model

struct YouTubeSearchResult: Codable {
    let id: String
    let title: String
    let thumbnail: String
    let channel: String?  // Optional - some results don't have this
    let duration: String?  // Optional - some results don't have this
}

// MARK: - Spotify API Response Models

struct SpotifyPlaylistsResponse: Codable {
    let items: [SpotifyPlaylistItem]
    let next: String?
}

struct SpotifyPlaylistItem: Codable {
    let id: String
    let name: String
}

struct SpotifyPlaylistDetailsResponse: Codable {
    let id: String
    let name: String
    let images: [SpotifyPlaylistImage]
}

struct SpotifyPlaylistImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}

struct SpotifyTracksResponse: Codable {
    let items: [SpotifyTrackItemImport]
    let next: String?
}

struct SpotifyTrackItemImport: Codable {
    let track: SpotifyTrackImport?
}

struct SpotifyTrackImport: Codable {
    let id: String
    let name: String
    let artists: [SpotifyArtistImport]
    let album: SpotifyAlbumImport
    let duration_ms: Int
}

struct SpotifyArtistImport: Codable {
    let name: String
}

struct SpotifyAlbumImport: Codable {
    let id: String
    let name: String
    let images: [SpotifyPlaylistImage]
}

// MARK: - Errors

enum ImportError: LocalizedError {
    case noMatch
    case downloadFailed
    case conversionFailed
    
    var errorDescription: String? {
        switch self {
        case .noMatch: return "No YouTube match found"
        case .downloadFailed: return "Download failed"
        case .conversionFailed: return "Conversion failed"
        }
    }
}
