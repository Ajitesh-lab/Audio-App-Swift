//
//  PlaylistManager.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import Foundation
import SwiftUI
import Combine

class PlaylistManager: ObservableObject {
    @Published var playlists: [Playlist] = []
    
    private let playlistsKey = "savedPlaylists"
    
    init() {
        // Load data asynchronously to avoid blocking UI
        Task {
            await self.loadPlaylistsAsync()
        }
    }
    
    // MARK: - CRUD Operations
    
    func createPlaylist(name: String, color: String = "#3B82F6") -> Playlist {
        let playlist = Playlist(name: name, color: color)
        playlists.append(playlist)
        savePlaylists()
        return playlist
    }
    
    func updatePlaylist(_ playlist: Playlist) {
        if let index = playlists.firstIndex(where: { $0.id == playlist.id }) {
            var updated = playlist
            updated.lastModified = Date()
            playlists[index] = updated
            savePlaylists()
        }
    }
    
    func deletePlaylist(_ playlistId: String) {
        playlists.removeAll { $0.id == playlistId }
        savePlaylists()
    }
    
    func renamePlaylist(_ playlistId: String, newName: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].name = newName
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    func updatePlaylistCover(_ playlistId: String, coverImageURL: String?) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].coverImageURL = coverImageURL
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    func updatePlaylistColor(_ playlistId: String, color: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].color = color
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    // MARK: - Song Management
    
    func addSong(_ songId: String, to playlistId: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            if !playlists[index].songs.contains(songId) {
                playlists[index].songs.append(songId)
                playlists[index].lastModified = Date()
                savePlaylists()
            }
        }
    }
    
    func removeSong(_ songId: String, from playlistId: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].songs.removeAll { $0 == songId }
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    func reorderSongs(in playlistId: String, from source: IndexSet, to destination: Int) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].songs.move(fromOffsets: source, toOffset: destination)
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    func clearPlaylist(_ playlistId: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].songs.removeAll()
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    func moveSong(in playlistId: String, from sourceIndex: Int, to destinationIndex: Int) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            guard sourceIndex != destinationIndex,
                  sourceIndex >= 0, sourceIndex < playlists[index].songs.count,
                  destinationIndex >= 0, destinationIndex <= playlists[index].songs.count else {
                return
            }
            
            let song = playlists[index].songs.remove(at: sourceIndex)
            let adjustedDestination = sourceIndex < destinationIndex ? destinationIndex - 1 : destinationIndex
            playlists[index].songs.insert(song, at: adjustedDestination)
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    // MARK: - Batch Operations
    
    func deleteSongs(songIds: Set<String>, from playlistId: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            playlists[index].songs.removeAll { songIds.contains($0) }
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    func addSongs(_ songIds: [String], to playlistId: String) {
        if let index = playlists.firstIndex(where: { $0.id == playlistId }) {
            for songId in songIds {
                if !playlists[index].songs.contains(songId) {
                    playlists[index].songs.append(songId)
                }
            }
            playlists[index].lastModified = Date()
            savePlaylists()
        }
    }
    
    // MARK: - Persistence
    
    private func savePlaylists() {
        do {
            let data = try JSONEncoder().encode(playlists)
            UserDefaults.standard.set(data, forKey: playlistsKey)
        } catch {
            print("Failed to save playlists: \(error)")
        }
    }
    
    // Async playlist loading on background thread
    @MainActor
    private func loadPlaylistsAsync() async {
        let (data, shouldCreateDefault): (Data?, Bool) = await Task.detached {
            guard let data = UserDefaults.standard.data(forKey: self.playlistsKey) else {
                return (nil, true)
            }
            return (data, false)
        }.value
        
        if shouldCreateDefault {
            createDefaultPlaylists()
            return
        }
        
        // Decode on background thread
        guard let data = data else {
            createDefaultPlaylists()
            return
        }
        
        let decoded = await Task.detached {
            try? JSONDecoder().decode([Playlist].self, from: data)
        }.value
        
        if let playlists = decoded {
            self.playlists = playlists
            Logger.success("Loaded \(playlists.count) playlists", category: "Startup")
        } else {
            Logger.error("Failed to decode playlists", category: "Startup")
            createDefaultPlaylists()
        }
    }
    
    // Keep old function for backward compatibility
    private func loadPlaylists() {
        Task {
            await loadPlaylistsAsync()
        }
    }
    
    private func createDefaultPlaylists() {
        let favorites = Playlist(name: "Favorites", color: "#FF4BB2")
        let recentlyPlayed = Playlist(name: "Recently Played", color: "#7AA6FF")
        playlists = [favorites, recentlyPlayed]
        savePlaylists()
    }
    
    // MARK: - Helper Methods
    
    func getPlaylist(by id: String) -> Playlist? {
        return playlists.first { $0.id == id }
    }
    
    func getTotalDuration(for playlist: Playlist, songs: [Song]) -> Double {
        let playlistSongs = playlist.songs.compactMap { songId in
            songs.first { $0.id == songId }
        }
        return playlistSongs.reduce(0) { $0 + $1.duration }
    }
    
    func formatDuration(_ duration: Double) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours) hr \(minutes) min"
        } else {
            return "\(minutes) min"
        }
    }
}
