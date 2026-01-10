//
//  SpotifyService.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import Foundation

// MARK: - Spotify Models
struct SpotifyAuthResponse: Codable {
    let access_token: String
    let token_type: String
    let expires_in: Int
}

struct SpotifySearchResponse: Codable {
    let tracks: SpotifyTracks
}

struct SpotifyTracks: Codable {
    let items: [SpotifyTrack]
}

struct SpotifyTrack: Codable {
    let id: String
    let name: String
    let duration_ms: Int
    let artists: [SpotifyArtist]
    let album: SpotifyAlbum
    let external_ids: SpotifyExternalIds?
    
    var primaryArtist: String {
        artists.first?.name ?? "Unknown Artist"
    }
    
    var allArtists: String {
        artists.map { $0.name }.joined(separator: ", ")
    }
}

struct SpotifyArtist: Codable {
    let id: String
    let name: String
}

struct SpotifyAlbum: Codable {
    let id: String
    let name: String
    let images: [SpotifyAlbumImage]
    let release_date: String?
    
    var highestResImage: String? {
        // Get the LARGEST image available (usually 640x640 or 1000x1000+)
        // Images may not always be sorted, so find max by dimensions
        guard !images.isEmpty else {
            print("   ⚠️ No album images available")
            return nil
        }
        
        print("   📊 Album has \(images.count) images:")
        for (index, img) in images.enumerated() {
            print("      [\(index)] \(img.width ?? 0)x\(img.height ?? 0) - \(img.url)")
        }
        
        // Find image with largest dimensions
        let largestImage = images.max { img1, img2 in
            let size1 = (img1.width ?? 0) * (img1.height ?? 0)
            let size2 = (img2.width ?? 0) * (img2.height ?? 0)
            return size1 < size2
        }
        
        if let largest = largestImage {
            print("   ✅ Selected: \(largest.width ?? 0)x\(largest.height ?? 0)")
        }
        
        return largestImage?.url
    }
}

struct SpotifyAlbumImage: Codable {
    let url: String
    let height: Int?
    let width: Int?
}

struct SpotifyExternalIds: Codable {
    let isrc: String?
}

// MARK: - Song Metadata Model
struct SongMetadata: Codable {
    let title: String
    let artist: String
    let album: String
    let duration: Int // milliseconds
    let spotifyId: String
    let isrc: String?
    let artworkLocalPath: String
    let youtubeUrl: String
    let downloadDate: Date
}

// MARK: - Spotify Service
class SpotifyService {
    static let shared = SpotifyService()
    
    private let clientId = "3cd7324b050c4cf4b02c09e38cce2407"
    private let clientSecret = "653af34f02424a1096d6f4aa14971b16"
    
    private var accessToken: String?
    private var tokenExpiryDate: Date?
    
    private let baseURL = "https://api.spotify.com/v1"
    private let authURL = "https://accounts.spotify.com/api/token"
    
    private init() {}
    
    // MARK: - Authentication
    
    func authenticate() async throws -> String {
        // Check if we have a valid token
        if let token = accessToken,
           let expiryDate = tokenExpiryDate,
           Date() < expiryDate {
            return token
        }
        
        // Request new token
        let credentials = "\(clientId):\(clientSecret)"
        guard let credentialsData = credentials.data(using: .utf8) else {
            throw SpotifyError.invalidCredentials
        }
        let base64Credentials = credentialsData.base64EncodedString()
        
        var request = URLRequest(url: URL(string: authURL)!)
        request.httpMethod = "POST"
        request.setValue("Basic \(base64Credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=client_credentials".data(using: .utf8)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.authenticationFailed
        }
        
        let authResponse = try JSONDecoder().decode(SpotifyAuthResponse.self, from: data)
        
        self.accessToken = authResponse.access_token
        self.tokenExpiryDate = Date().addingTimeInterval(TimeInterval(authResponse.expires_in - 60))
        
        return authResponse.access_token
    }
    
    // MARK: - Search
    
    func searchTrack(artist: String, track: String) async throws -> SpotifyTrack? {
        let token = try await authenticate()
        
        // Clean search terms
        let cleanArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanTrack = track.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Build query
        let query = "track:\(cleanTrack) artist:\(cleanArtist)"
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SpotifyError.invalidQuery
        }
        
        let urlString = "\(baseURL)/search?type=track&q=\(encodedQuery)&limit=10"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            // Token expired, retry once
            self.accessToken = nil
            return try await searchTrack(artist: artist, track: track)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SpotifyError.searchFailed(statusCode: httpResponse.statusCode)
        }
        
        let searchResponse = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
        
        print("🎵 Spotify search results: \(searchResponse.tracks.items.count) tracks found")
        
        // Use all tracks - no filtering
        let tracksToSearch = searchResponse.tracks.items
        
        // Find best match by comparing artist and track names
        var bestMatch: SpotifyTrack?
        var bestScore = 0.0
        
        for spotifyTrack in tracksToSearch.prefix(10) {
            let artistScore = stringSimilarity(cleanArtist.lowercased(), spotifyTrack.primaryArtist.lowercased())
            let trackScore = stringSimilarity(cleanTrack.lowercased(), spotifyTrack.name.lowercased())
            let combinedScore = (artistScore * 0.6) + (trackScore * 0.4) // Weight artist match more
            
            print("   Candidate: \(spotifyTrack.primaryArtist) - \(spotifyTrack.name) (score: \(String(format: "%.2f", combinedScore)))")
            
            if combinedScore > bestScore {
                bestScore = combinedScore
                bestMatch = spotifyTrack
            }
        }
        
        // No filtering - accept the best match found
        if let match = bestMatch {
            print("✅ Selected: \(match.primaryArtist) - \(match.name) (score: \(String(format: "%.2f", bestScore)))")
            print("   Album: \(match.album.name)")
            print("   Images: \(match.album.images.count) available")
            if let artworkURL = match.album.highestResImage {
                print("   Artwork URL: \(artworkURL)")
            }
        }
        
        return bestMatch
    }
    
    // Simple string similarity using Levenshtein distance
    private func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let distance = levenshteinDistance(s1, s2)
        let maxLength = max(s1.count, s2.count)
        guard maxLength > 0 else { return 1.0 }
        return 1.0 - (Double(distance) / Double(maxLength))
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
                        dist[i-1][j] + 1,    // deletion
                        dist[i][j-1] + 1,    // insertion
                        dist[i-1][j-1] + 1   // substitution
                    )
                }
            }
        }
        
        return dist[s1.count][s2.count]
    }
    
    func searchTrackByTitle(_ title: String) async throws -> SpotifyTrack? {
        let token = try await authenticate()
        
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let encodedQuery = cleanTitle.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw SpotifyError.invalidQuery
        }
        
        let urlString = "\(baseURL)/search?type=track&q=\(encodedQuery)&limit=10"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.searchFailed(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        
        let searchResponse = try JSONDecoder().decode(SpotifySearchResponse.self, from: data)
        
        print("🎵 Title-only search results: \(searchResponse.tracks.items.count) tracks")
        
        // Find best match by title similarity
        var bestMatch: SpotifyTrack?
        var bestScore = 0.0
        
        for spotifyTrack in searchResponse.tracks.items.prefix(10) {
            let titleScore = stringSimilarity(cleanTitle.lowercased(), spotifyTrack.name.lowercased())
            print("   Candidate: \(spotifyTrack.primaryArtist) - \(spotifyTrack.name) (score: \(String(format: "%.2f", titleScore)))")
            
            if titleScore > bestScore {
                bestScore = titleScore
                bestMatch = spotifyTrack
            }
        }
        
        // No threshold - accept the best title match
        if let match = bestMatch {
            print("✅ Title search selected: \(match.primaryArtist) - \(match.name) (score: \(String(format: "%.2f", bestScore)))")
        }
        
        return bestMatch
    }
    
    // MARK: - Image Download
    
    /// Fetch album details directly - sometimes has higher resolution images
    func fetchAlbumDetails(albumId: String) async throws -> SpotifyAlbum {
        let token = try await authenticate()
        let urlString = "\(baseURL)/albums/\(albumId)"
        guard let url = URL(string: urlString) else { throw SpotifyError.invalidURL }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            self.accessToken = nil
            return try await fetchAlbumDetails(albumId: albumId)
        }
        guard httpResponse.statusCode == 200 else {
            throw SpotifyError.searchFailed(statusCode: httpResponse.statusCode)
        }
        
        let album = try JSONDecoder().decode(SpotifyAlbum.self, from: data)
        return album
    }
    
    /// Fetch album artwork URL from the track endpoint (helpful if search payload lacks images).
    func fetchAlbumArtworkURL(for trackId: String) async throws -> String? {
        let token = try await authenticate()
        let urlString = "\(baseURL)/tracks/\(trackId)"
        guard let url = URL(string: urlString) else { throw SpotifyError.invalidURL }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            self.accessToken = nil
            return try await fetchAlbumArtworkURL(for: trackId)
        }
        guard httpResponse.statusCode == 200 else {
            throw SpotifyError.searchFailed(statusCode: httpResponse.statusCode)
        }
        
        struct TrackResponse: Codable {
            let album: SpotifyAlbum
        }
        
        let trackResponse = try JSONDecoder().decode(TrackResponse.self, from: data)
        return trackResponse.album.highestResImage
    }
    
    /// Fetch track details by Spotify Track ID
    func fetchTrackById(trackId: String) async throws -> SpotifyTrack {
        let token = try await authenticate()
        
        let urlString = "\(baseURL)/tracks/\(trackId)"
        guard let url = URL(string: urlString) else {
            throw SpotifyError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SpotifyError.invalidResponse
        }
        
        if httpResponse.statusCode == 401 {
            // Token expired, retry once
            self.accessToken = nil
            return try await fetchTrackById(trackId: trackId)
        }
        
        guard httpResponse.statusCode == 200 else {
            throw SpotifyError.searchFailed(statusCode: httpResponse.statusCode)
        }
        
        let track = try JSONDecoder().decode(SpotifyTrack.self, from: data)
        return track
    }
    
    func downloadArtwork(from url: String) async throws -> Data {
        guard let imageURL = URL(string: url) else {
            throw SpotifyError.invalidURL
        }
        
        let (data, response) = try await URLSession.shared.data(from: imageURL)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SpotifyError.artworkDownloadFailed
        }
        
        return data
    }
}

// MARK: - Errors
enum SpotifyError: LocalizedError {
    case invalidCredentials
    case authenticationFailed
    case invalidQuery
    case invalidURL
    case invalidResponse
    case searchFailed(statusCode: Int)
    case artworkDownloadFailed
    case noResults
    
    var errorDescription: String? {
        switch self {
        case .invalidCredentials:
            return "Invalid Spotify API credentials"
        case .authenticationFailed:
            return "Failed to authenticate with Spotify"
        case .invalidQuery:
            return "Invalid search query"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid response from Spotify"
        case .searchFailed(let code):
            return "Search failed with status code: \(code)"
        case .artworkDownloadFailed:
            return "Failed to download artwork"
        case .noResults:
            return "No results found"
        }
    }
}
