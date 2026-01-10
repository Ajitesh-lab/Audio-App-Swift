//
//  MusicDownloadManager.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import Foundation
import UIKit

class MusicDownloadManager {
    static let shared = MusicDownloadManager()
    
    private let fileManager = FileManager.default
    private let spotifyService = SpotifyService.shared
    
    // Base music directory
    private var musicDirectory: URL {
        let documentsPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documentsPath.appendingPathComponent("Music")
    }
    
    private init() {
        createMusicDirectoryIfNeeded()
    }
    
    // MARK: - Directory Management
    
    private func createMusicDirectoryIfNeeded() {
        if !fileManager.fileExists(atPath: musicDirectory.path) {
            try? fileManager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
        }
    }
    
    private func getSongDirectory(artist: String, album: String, track: String) -> URL {
        let sanitizedArtist = sanitizeFilename(artist)
        let sanitizedAlbum = sanitizeFilename(album)
        let sanitizedTrack = sanitizeFilename(track)
        
        return musicDirectory
            .appendingPathComponent(sanitizedArtist)
            .appendingPathComponent(sanitizedAlbum)
            .appendingPathComponent(sanitizedTrack)
    }
    
    private func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name.components(separatedBy: invalid).joined(separator: "_")
    }
    
    private func extractYouTubeId(from urlString: String) -> String? {
        if let components = URLComponents(string: urlString) {
            if let id = components.queryItems?.first(where: { $0.name == "v" })?.value {
                return id
            }
            if let host = components.host, host.contains("youtu.be") {
                let pathComponents = components.path.split(separator: "/")
                if let idComponent = pathComponents.first {
                    return String(idComponent)
                }
            }
        }
        if let id = urlString.components(separatedBy: "v=").last, id.count == 11 {
            return id
        }
        return nil
    }
    
    private func downloadYouTubeThumbnail(videoId: String) async throws -> Data {
        // Try max resolution first, then fall back to HQ
        let candidates = [
            URL(string: "https://i.ytimg.com/vi/\(videoId)/maxresdefault.jpg"),
            URL(string: "https://i.ytimg.com/vi/\(videoId)/hqdefault.jpg")
        ].compactMap { $0 }
        
        for url in candidates {
            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200, !data.isEmpty {
                    print("   ✅ Downloaded YouTube thumbnail: \(url.absoluteString)")
                    return data
                }
            } catch {
                continue
            }
        }
        throw DownloadError.artworkDownloadFailed
    }
    
    // MARK: - Complete Download Pipeline
    
    func downloadAndProcessSong(
        youtubeURL: String,
        youtubeTitle: String,
        youtubeDuration: Double?,
        progressCallback: @escaping (String) -> Void
    ) async throws -> Song {
        
        let youtubeVideoId = extractYouTubeId(from: youtubeURL)
        // Step 1: Parse YouTube title
        progressCallback("Parsing title...")
        let parsed = TitleParser.parse(youtubeTitle)
        print("📝 Parsed: artist='\(parsed.artist)' track='\(parsed.track)' confidence=\(parsed.confidence)")
        
        // Step 2: Search Spotify
        progressCallback("Searching Spotify...")
        var spotifyTrack: SpotifyTrack?
        
        // Try with artist + track first
        if parsed.confidence != .low {
            print("🔍 Searching Spotify with: artist='\(parsed.artist)' track='\(parsed.track)'")
            do {
                spotifyTrack = try await spotifyService.searchTrack(
                    artist: parsed.artist,
                    track: parsed.track
                )
                if spotifyTrack != nil {
                    print("✅ Found match on first try!")
                }
            } catch {
                print("❌ First search failed: \(error)")
            }
        }
        
        // Fallback: Try swapping artist and track (often reversed in YouTube titles)
        if spotifyTrack == nil && parsed.confidence != .low {
            print("🔄 No results, trying reversed: artist='\(parsed.track)' track='\(parsed.artist)'")
            do {
                spotifyTrack = try await spotifyService.searchTrack(
                    artist: parsed.track,
                    track: parsed.artist
                )
                if spotifyTrack != nil {
                    print("✅ Found match on reversed search!")
                }
            } catch {
                print("❌ Reversed search failed: \(error)")
            }
        }
        
        // Fallback: Try with just the full title
        if spotifyTrack == nil {
            progressCallback("Retrying search...")
            print("🔍 Trying title-only search: '\(youtubeTitle)'")
            do {
                spotifyTrack = try await spotifyService.searchTrackByTitle(youtubeTitle)
                if spotifyTrack != nil {
                    print("✅ Found match on title search!")
                }
            } catch {
                print("❌ Title search failed: \(error)")
            }
        }
        
        // ENFORCE: Spotify as ONLY source of truth - no YouTube metadata allowed
        guard let track = spotifyTrack else {
            // If we can't find a Spotify match, we reject the download
            print("❌ CRITICAL: No Spotify match found. Cannot proceed without verified metadata.")
            throw DownloadError.spotifyMatchRequired
        }
        
        // Validate the match quality
        let matchQuality = validateSpotifyMatch(
            spotifyTrack: track,
            parsedArtist: parsed.artist,
            parsedTrack: parsed.track,
            youtubeDuration: youtubeDuration
        )
        
        print("🎯 Match quality: \(matchQuality.description)")
        
        // REJECT poor matches - they're likely wrong tracks with wrong artwork
        if matchQuality == .poor {
            print("❌ REJECTED: Match quality too low - risk of wrong artwork")
            throw DownloadError.spotifyMatchRequired
        }
        
        // Check if YouTube title suggests remix/cover - warn but allow
        if TitleParser.isRemixOrCover(youtubeTitle) {
            print("⚠️ WARNING: YouTube title suggests remix/cover version")
            print("   Spotify match: \(track.name) by \(track.primaryArtist)")
            print("   Proceeding with official Spotify artwork...")
        }
        
        // ALWAYS use Spotify metadata - it's the source of truth
        let finalArtist = track.primaryArtist
        let finalTrack = track.name
        let finalAlbum = track.album.name
        let finalDuration = track.duration_ms
        let spotifyId = track.id
        let isrc = track.external_ids?.isrc
        
        // Get artwork - must exist from Spotify
        var artworkURL = track.album.highestResImage
        
        // Try fetching album directly for potentially higher resolution
        if artworkURL != nil {
            print("🎨 Trying to fetch higher resolution from album endpoint...")
            if let albumDetails = try? await spotifyService.fetchAlbumDetails(albumId: track.album.id),
               let higherResURL = albumDetails.highestResImage {
                print("   ✅ Got album endpoint images")
                artworkURL = higherResURL
            }
        }
        
        // If still no artwork, try fetching directly from track API
        if artworkURL == nil {
            print("⚠️ No artwork in album data, trying track API...")
            artworkURL = try? await spotifyService.fetchAlbumArtworkURL(for: track.id)
        }
        
        // Artwork is required - fail if we can't get it
        guard let finalArtworkURL = artworkURL else {
            print("❌ CRITICAL: No album artwork available from Spotify")
            throw DownloadError.artworkRequired
        }
        
        print("✅ Using Spotify metadata:")
        print("   🎵 Title: \(finalTrack)")
        print("   🎤 Artist: \(finalArtist)")
        print("   💿 Album: \(finalAlbum)")
        print("   ⏱️ Duration: \(finalDuration)ms")
        print("   🎨 Artwork: \(finalArtworkURL)")
        print("   🆔 Spotify ID: \(spotifyId)")
        if let isrc = isrc {
            print("   📇 ISRC: \(isrc)")
        }
        
        // Step 3: Create song directory
        progressCallback("Creating directories...")
        let songDir = getSongDirectory(
            artist: finalArtist,
            album: finalAlbum,
            track: finalTrack
        )
        try fileManager.createDirectory(at: songDir, withIntermediateDirectories: true)
        
        // Step 4: Download audio from YouTube
        progressCallback("Downloading audio...")
        let audioPath = songDir.appendingPathComponent("\(sanitizeFilename(finalTrack)).mp3")
        try await downloadYouTubeAudio(
            url: youtubeURL,
            outputPath: audioPath.path
        )
        
        // Step 5: Download artwork (REQUIRED - ONLY use Spotify official artwork)
        progressCallback("Downloading artwork...")
        let artworkPath = songDir.appendingPathComponent("cover.jpg")
        
        print("🎨 Downloading official album artwork from Spotify...")
        
        // ONLY use Spotify artwork - guaranteed to be official cover
        let artworkData = try await spotifyService.downloadArtwork(from: finalArtworkURL)
        
        print("   💾 Downloaded \(artworkData.count) bytes from Spotify")
        print("   📦 Artwork resolution: Spotify official (640x640 or higher)")
        print("   💿 Album: \(finalAlbum)")
        print("   Save path: \(artworkPath.path)")
        
        do {
            try artworkData.write(to: artworkPath)
            print("   ✅ Official artwork saved successfully")
            
            // Verify file exists
            guard fileManager.fileExists(atPath: artworkPath.path) else {
                throw DownloadError.artworkSaveFailed
            }
            print("   ✅ Verified: Official album artwork on disk")
        } catch {
            print("   ❌ CRITICAL: Failed to save artwork: \(error)")
            throw DownloadError.artworkDownloadFailed
        }
        
        // Step 6: Save metadata (all from Spotify)
        progressCallback("Saving metadata...")
        let metadata = SongMetadata(
            title: finalTrack,
            artist: finalArtist,
            album: finalAlbum,
            duration: finalDuration,
            spotifyId: spotifyId,
            isrc: isrc,
            artworkLocalPath: artworkPath.lastPathComponent,
            youtubeUrl: youtubeURL,
            downloadDate: Date()
        )
        
        let metadataPath = songDir.appendingPathComponent("metadata.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let metadataData = try encoder.encode(metadata)
        try metadataData.write(to: metadataPath)
        
        print("💾 Metadata saved")
        progressCallback("Complete!")
        print("✅ Download complete: \(finalArtist) - \(finalTrack) from '\(finalAlbum)'")
        
        // Step 7: Create Song object with ALL Spotify metadata
        return Song(
            id: spotifyId,
            title: finalTrack,
            artist: finalArtist,
            album: finalAlbum,
            duration: Double(finalDuration) / 1000.0,
            url: audioPath.absoluteString,
            spotifyTrackId: spotifyId,
            artworkURL: nil,
            artworkPath: artworkPath.path,
            spotifyId: spotifyId,
            isrc: isrc,
            videoId: youtubeVideoId,
            audioFingerprint: nil
        )
    }
    
    // MARK: - YouTube Download via Server with Fallback
    
    private func downloadYouTubeAudio(url: String, outputPath: String) async throws {
        // Extract video ID from URL
        let videoId = url.components(separatedBy: "v=").last ?? url
        
        Logger.log("Starting download with fallback for video: \(videoId)", category: "Download")
        
        // Use fallback service to try multiple APIs
        let tempURL = try await DownloadFallbackService.shared.downloadWithFallback(
            videoId: videoId,
            progressCallback: { progress in
                Logger.log(progress, category: "Download")
            }
        )
        
        // Move the downloaded file to final location
        let outputURL = URL(fileURLWithPath: outputPath)
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // Move temp file to final location
        try FileManager.default.moveItem(at: tempURL, to: outputURL)
        
        Logger.success("Audio saved to: \(outputPath)", category: "Download")
    }
    
    // MARK: - Match Validation
    
    private enum MatchQuality {
        case excellent  // Duration match + string similarity high
        case good       // Duration match OR string similarity high
        case acceptable // Some similarity detected
        case poor       // Weak match but best available
        
        var description: String {
            switch self {
            case .excellent: return "Excellent (high confidence)"
            case .good: return "Good (verified match)"
            case .acceptable: return "Acceptable (likely correct)"
            case .poor: return "Poor (best available)"
            }
        }
    }
    
    private func validateSpotifyMatch(
        spotifyTrack: SpotifyTrack,
        parsedArtist: String,
        parsedTrack: String,
        youtubeDuration: Double?
    ) -> MatchQuality {
        var score = 0
        
        // Check duration match (within 3 seconds)
        if let ytDuration = youtubeDuration {
            let spotifyDuration = Double(spotifyTrack.duration_ms) / 1000.0
            let durationDiff = abs(spotifyDuration - ytDuration)
            
            if durationDiff < 2.0 {
                score += 3  // Strong signal
                print("   ✅ Duration match: \(durationDiff)s difference")
            } else if durationDiff < 5.0 {
                score += 1  // Weak signal
                print("   ⚠️ Duration close: \(durationDiff)s difference")
            } else {
                print("   ⚠️ Duration mismatch: \(durationDiff)s difference")
            }
        }
        
        // Check artist name similarity (stricter matching)
        let artistSimilarity = stringSimilarity(
            normalizeForMatching(parsedArtist),
            normalizeForMatching(spotifyTrack.primaryArtist)
        )
        if artistSimilarity > 0.8 {
            score += 3
            print("   ✅ Artist similarity: \(Int(artistSimilarity * 100))%")
        } else if artistSimilarity > 0.6 {
            score += 1
            print("   ⚠️ Artist similarity: \(Int(artistSimilarity * 100))%")
        } else {
            print("   ❌ Artist mismatch: \(Int(artistSimilarity * 100))%")
        }
        
        // Check track name similarity (stricter matching)
        let trackSimilarity = stringSimilarity(
            normalizeForMatching(parsedTrack),
            normalizeForMatching(spotifyTrack.name)
        )
        if trackSimilarity > 0.8 {
            score += 3
            print("   ✅ Track similarity: \(Int(trackSimilarity * 100))%")
        } else if trackSimilarity > 0.6 {
            score += 1
            print("   ⚠️ Track similarity: \(Int(trackSimilarity * 100))%")
        } else {
            print("   ❌ Track mismatch: \(Int(trackSimilarity * 100))%")
        }
        
        // Determine quality with stricter thresholds
        if score >= 6 {
            return .excellent
        } else if score >= 4 {
            return .good
        } else if score >= 2 {
            return .acceptable
        } else {
            return .poor
        }
    }
    
    // Normalize strings for better matching (remove punctuation, extra spaces)
    private func normalizeForMatching(_ text: String) -> String {
        return text.lowercased()
            .replacingOccurrences(of: "[^a-z0-9\\s]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let longer = s1.count > s2.count ? s1 : s2
        let _ = s1.count > s2.count ? s2 : s1  // shorter not used, but keep for clarity
        
        if longer.isEmpty { return 1.0 }
        
        let distance = levenshteinDistance(s1, s2)
        return Double(longer.count - distance) / Double(longer.count)
    }
    
    private func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1 = Array(s1)
        let s2 = Array(s2)
        var dist = Array(repeating: Array(repeating: 0, count: s2.count + 1), count: s1.count + 1)
        
        for i in 0...s1.count { dist[i][0] = i }
        for j in 0...s2.count { dist[0][j] = j }
        
        for i in 1...s1.count {
            for j in 1...s2.count {
                if s1[i-1] == s2[j-1] {
                    dist[i][j] = dist[i-1][j-1]
                } else {
                    dist[i][j] = min(
                        dist[i-1][j] + 1,
                        dist[i][j-1] + 1,
                        dist[i-1][j-1] + 1
                    )
                }
            }
        }
        
        return dist[s1.count][s2.count]
    }
    
    // MARK: - Placeholder Artwork
    
    private func createPlaceholderArtwork(at directory: URL) -> URL {
        let artworkPath = directory.appendingPathComponent("cover.jpg")
        
        // Create a simple gradient image
        let size = CGSize(width: 500, height: 500)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let image = renderer.image { context in
            let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor(red: 0.48, green: 0.65, blue: 1.0, alpha: 1.0).cgColor,
                    UIColor(red: 1.0, green: 0.29, blue: 0.70, alpha: 1.0).cgColor
                ] as CFArray,
                locations: [0.0, 1.0]
            )!
            
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }
        
        if let data = image.jpegData(compressionQuality: 0.9) {
            try? data.write(to: artworkPath)
        }
        
        return artworkPath
    }
    
    // MARK: - Library Scanning
    
    func scanMusicLibrary() -> [Song] {
        var songs: [Song] = []
        
        guard let artistDirs = try? fileManager.contentsOfDirectory(
            at: musicDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return songs
        }
        
        for artistDir in artistDirs where artistDir.hasDirectoryPath {
            guard let albumDirs = try? fileManager.contentsOfDirectory(
                at: artistDir,
                includingPropertiesForKeys: nil
            ) else { continue }
            
            for albumDir in albumDirs where albumDir.hasDirectoryPath {
                guard let songDirs = try? fileManager.contentsOfDirectory(
                    at: albumDir,
                    includingPropertiesForKeys: nil
                ) else { continue }
                
                for songDir in songDirs where songDir.hasDirectoryPath {
                    if let song = loadSongFromDirectory(songDir) {
                        songs.append(song)
                    }
                }
            }
        }
        
        return songs
    }
    
    private func loadSongFromDirectory(_ directory: URL) -> Song? {
        let metadataPath = directory.appendingPathComponent("metadata.json")
        
        guard let metadataData = try? Data(contentsOf: metadataPath),
              let metadata = try? JSONDecoder().decode(SongMetadata.self, from: metadataData) else {
            return nil
        }
        
        // Find audio file
        let audioPath = directory.appendingPathComponent("\(sanitizeFilename(metadata.title)).mp3")
        
        guard fileManager.fileExists(atPath: audioPath.path) else {
            return nil
        }
        
        // Find artwork
        let artworkPath = directory.appendingPathComponent("cover.jpg")
        let artworkExists = fileManager.fileExists(atPath: artworkPath.path)
        
        // Create Song with ALL Spotify metadata
        return Song(
            id: metadata.spotifyId,
            title: metadata.title,
            artist: metadata.artist,
            album: metadata.album,
            duration: Double(metadata.duration) / 1000.0,
            url: audioPath.absoluteString,
            spotifyTrackId: metadata.spotifyId,
            artworkURL: nil,
            artworkPath: artworkExists ? artworkPath.path : nil,
            spotifyId: metadata.spotifyId,
            isrc: metadata.isrc,
            videoId: nil,
            audioFingerprint: nil
        )
    }
    
    // MARK: - High-Res Artwork Fetching
    
    /// Fetch high-resolution artwork from iTunes Search API (often 1400x1400+)
    private func fetchiTunesArtwork(artist: String, album: String) async throws -> Data? {
        // Clean up search terms
        let searchTerm = "\(artist) \(album)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        let urlString = "https://itunes.apple.com/search?term=\(searchTerm)&entity=album&limit=5"
        guard let url = URL(string: urlString) else {
            throw DownloadError.artworkDownloadFailed
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw DownloadError.artworkDownloadFailed
        }
        
        // Parse iTunes response
        struct iTunesResponse: Codable {
            let results: [iTunesResult]
        }
        
        struct iTunesResult: Codable {
            let artworkUrl100: String?
            let collectionName: String?
            let artistName: String?
        }
        
        let itunesResponse = try JSONDecoder().decode(iTunesResponse.self, from: data)
        
        // Find best match
        guard let firstResult = itunesResponse.results.first,
              var artworkURL = firstResult.artworkUrl100 else {
            print("      No iTunes results found")
            throw DownloadError.artworkDownloadFailed
        }
        
        // iTunes artwork URL hack: replace 100x100 with higher resolution
        // artworkUrl100 → change to 1400x1400 or 3000x3000
        artworkURL = artworkURL
            .replacingOccurrences(of: "100x100", with: "3000x3000")
        
        print("      iTunes URL: \(artworkURL)")
        
        // Download the high-res artwork
        guard let highResURL = URL(string: artworkURL) else {
            throw DownloadError.artworkDownloadFailed
        }
        
        let (artworkData, artworkResponse) = try await URLSession.shared.data(from: highResURL)
        
        guard let httpArtworkResponse = artworkResponse as? HTTPURLResponse,
              httpArtworkResponse.statusCode == 200,
              artworkData.count > 100000 else { // Should be > 100KB for high-res
            print("      iTunes image too small or failed: \(artworkData.count) bytes")
            throw DownloadError.artworkDownloadFailed
        }
        
        print("      ✅ iTunes high-res: \(artworkData.count) bytes (likely 1400x1400+)")
        return artworkData
    }
}

// MARK: - Errors
enum DownloadError: LocalizedError {
    case youtubeFailed
    case spotifyMatchRequired
    case artworkRequired
    case artworkDownloadFailed
    case artworkSaveFailed
    case notImplemented
    case invalidPath
    case metadataSaveFailed
    
    var errorDescription: String? {
        switch self {
        case .youtubeFailed:
            return "Failed to download from YouTube"
        case .spotifyMatchRequired:
            return "No Spotify match found. Cannot download without verified metadata."
        case .artworkRequired:
            return "Album artwork not available from Spotify"
        case .artworkDownloadFailed:
            return "Failed to download album artwork from Spotify"
        case .artworkSaveFailed:
            return "Failed to save album artwork to disk"
        case .notImplemented:
            return "YouTube download not yet implemented - needs server integration"
        case .invalidPath:
            return "Invalid file path"
        case .metadataSaveFailed:
            return "Failed to save metadata"
        }
    }
}

// MARK: - Cache Management
extension MusicDownloadManager {
    /// Returns the total size (in bytes) of the on-disk music cache.
    func getCacheSize() -> Int64 {
        var totalSize: Int64 = 0
        
        guard fileManager.fileExists(atPath: musicDirectory.path) else {
            return 0
        }
        
        if let enumerator = fileManager.enumerator(
            at: musicDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let fileURL as URL in enumerator {
                if let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey]),
                   let fileSize = resourceValues.fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
    
    /// Clears all downloaded songs and recreates the music directory.
    func clearAllCache() throws {
        guard fileManager.fileExists(atPath: musicDirectory.path) else {
            return
        }
        
        try fileManager.removeItem(at: musicDirectory)
        createMusicDirectoryIfNeeded()
    }
}
