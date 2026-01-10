//
//  Models.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import Foundation

// MARK: - Song Model
struct Song: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let url: String
    
    // ✅ Explicit immutable artwork fields
    let spotifyTrackId: String?  // Real Spotify Track ID (primary key for artwork)
    let artworkURL: String?      // Original Spotify album.images[0].url
    var artworkPath: String?     // Local path: Artwork/<spotifyTrackId>_<hash>.jpg
    
    // Legacy fields
    let spotifyId: String?       // Kept for backward compatibility
    let isrc: String?
    var videoId: String? = nil   // Optional YouTube video identifier
    var audioFingerprint: String?
    
    // ✅ Cache-busted artwork URL with file modification timestamp
    func artworkURLWithCacheBuster() -> String? {
        guard let artworkPath = artworkPath else { return nil }
        
        // Get file modification date for cache busting
        let fileURL = URL(fileURLWithPath: artworkPath)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: artworkPath),
           let modDate = attributes[.modificationDate] as? Date {
            let timestamp = Int(modDate.timeIntervalSince1970)
            return "file://\(artworkPath)?v=\(timestamp)"
        }
        
        return "file://\(artworkPath)"
    }
    
    // ✅ Validate artwork belongs to this song
    func isArtworkValid() -> Bool {
        guard let artworkPath = artworkPath,
              let spotifyTrackId = spotifyTrackId else {
            return false
        }
        
        // Artwork filename must contain the Spotify Track ID
        let filename = URL(fileURLWithPath: artworkPath).lastPathComponent
        let isValid = filename.contains(spotifyTrackId)
        
        if !isValid {
            print("⚠️ ARTWORK MISMATCH: Track '\(title)' (ID: \(spotifyTrackId)) has artwork '\(filename)'")
        }
        
        return isValid
    }
    
    // ✅ Debug log for artwork troubleshooting
    func logArtworkDebug() {
        print("""
        🎵 ARTWORK DEBUG:
           Title: \(title)
           Artist: \(artist)
           Spotify Track ID: \(spotifyTrackId ?? "nil")
           Artwork URL: \(artworkURL ?? "nil")
           Local Path: \(artworkPath ?? "nil")
           Is Valid: \(isArtworkValid())
        """)
    }
    
    static func == (lhs: Song, rhs: Song) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Playlist Model
struct Playlist: Identifiable, Codable, Equatable {
    let id: String
    var name: String
    var songs: [String] // Song IDs
    var color: String
    var coverImageURL: String?
    var createdDate: Date
    var lastModified: Date
    
    init(id: String = UUID().uuidString, 
         name: String, 
         songs: [String] = [], 
         color: String = "#3B82F6",
         coverImageURL: String? = nil,
         createdDate: Date = Date(),
         lastModified: Date = Date()) {
        self.id = id
        self.name = name
        self.songs = songs
        self.color = color
        self.coverImageURL = coverImageURL
        self.createdDate = createdDate
        self.lastModified = lastModified
    }
    
    static func == (lhs: Playlist, rhs: Playlist) -> Bool {
        lhs.id == rhs.id
    }
}
