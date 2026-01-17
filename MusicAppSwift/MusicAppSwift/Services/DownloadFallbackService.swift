//
//  DownloadFallbackService.swift
//  MusicAppSwift
//
//  Multi-API fallback system for reliable song downloads
//

import Foundation

enum DownloadAPI {
    case primary
    case rapidAPI
    case ytStream
    case invidious
    
    var name: String {
        switch self {
        case .primary: return "Primary Server"
        case .rapidAPI: return "RapidAPI YouTube"
        case .ytStream: return "YTStream API"
        case .invidious: return "Invidious Instance"
        }
    }
}

class DownloadFallbackService {
    static let shared = DownloadFallbackService()
    
    private let primaryServerURL = "https://audio-rough-water-3069.fly.dev"
    
    // Backup API endpoints
    private let invidiousInstances = [
        "https://invidious.fdn.fr",
        "https://inv.riverside.rocks",
        "https://invidious.snopyta.org"
    ]
    
    private init() {}
    
    // MARK: - Main Fallback Logic
    
    func downloadWithFallback(videoId: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        progressCallback("Starting download...")
        
        // Try 1: Primary server (your local Node.js server) - tries all hosts
        do {
            Logger.log("Trying primary servers...", category: "Download")
            let url = try await downloadFromPrimary(videoId: videoId, progressCallback: progressCallback)
            Logger.success("Primary server succeeded!", category: "Download")
            return url
        } catch {
            Logger.error("All primary servers failed: \(error.localizedDescription)", category: "Download")
        }
        
        // Try 2: Invidious instances (public, no API key needed)
        progressCallback("Trying alternative sources...")
        for (index, instance) in invidiousInstances.enumerated() {
            do {
                Logger.log("Trying Invidious instance \(index + 1)/\(invidiousInstances.count): \(instance)", category: "Download")
                let url = try await downloadFromInvidious(videoId: videoId, instance: instance, progressCallback: progressCallback)
                Logger.success("Invidious instance succeeded!", category: "Download")
                return url
            } catch {
                Logger.error("Invidious instance \(index + 1) failed: \(error.localizedDescription)", category: "Download")
                continue
            }
        }
        
        // All methods failed
        progressCallback("Download failed - all sources unavailable")
        throw DownloadError.allMethodsFailed
    }
    
    // MARK: - Primary Server
    
    private func downloadFromPrimary(videoId: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        // Try all configured hosts with fallback
        for host in ServerConfig.hosts {
            do {
                let serverURL = URL(string: "\(host)/api/download-sync/\(videoId)")!
                
                var request = URLRequest(url: serverURL)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.timeoutInterval = 45.0
                
                progressCallback("Downloading from \(host)...")
                Logger.log("Trying primary download from: \(host)", category: "Download")
                
                let (_, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    Logger.error("Primary server \(host) returned status: \((response as? HTTPURLResponse)?.statusCode ?? -1)", category: "Download")
                    continue
                }
                
                Logger.log("Download initiated successfully on \(host), fetching file...", category: "Download")
                
                // Try to fetch the downloaded file
                let formats = ["mp3", "m4a", "webm", "ogg"]
                for format in formats {
                    let testURL = URL(string: "\(host)/downloads/\(videoId).\(format)")!
                    
                    do {
                        let (data, fileResponse) = try await URLSession.shared.data(from: testURL)
                        if let httpFileResponse = fileResponse as? HTTPURLResponse, httpFileResponse.statusCode == 200 {
                            // Save to temp file
                            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(format)")
                            try data.write(to: tempURL)
                            Logger.success("Downloaded \(data.count / 1024) KB as \(format) from \(host)", category: "Download")
                            return tempURL
                        }
                    } catch {
                        continue
                    }
                }
                
                Logger.error("File not found on \(host) after download request", category: "Download")
                
            } catch {
                Logger.error("Failed to download from \(host): \(error.localizedDescription)", category: "Download")
                continue
            }
        }
        
        throw DownloadError.youtubeFailed
    }
    
    // MARK: - Invidious API
    
    private func downloadFromInvidious(videoId: String, instance: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        // Invidious provides direct audio stream URLs
        let apiURL = URL(string: "\(instance)/api/v1/videos/\(videoId)")!
        
        progressCallback("Fetching from Invidious...")
        
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 20.0
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DownloadError.youtubeFailed
        }
        
        // Parse JSON response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let adaptiveFormats = json["adaptiveFormats"] as? [[String: Any]] else {
            throw DownloadError.youtubeFailed
        }
        
        // Find best audio format
        let audioFormats = adaptiveFormats.filter { format in
            if let type = format["type"] as? String {
                return type.contains("audio")
            }
            return false
        }
        
        guard let bestFormat = audioFormats.first,
              let audioURL = bestFormat["url"] as? String else {
            throw DownloadError.youtubeFailed
        }
        
        Logger.log("Found audio stream URL from Invidious", category: "Download")
        
        // Download the audio stream
        progressCallback("Downloading audio stream...")
        
        guard let streamURL = URL(string: audioURL) else {
            throw DownloadError.youtubeFailed
        }
        
        let (audioData, _) = try await URLSession.shared.data(from: streamURL)
        
        // Save to temp file
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try audioData.write(to: tempURL)
        
        Logger.success("Downloaded \(audioData.count / 1024) KB from Invidious", category: "Download")
        return tempURL
    }
    
    // MARK: - YTStream API
    
    private func downloadFromYTStream(videoId: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        // YTStream.download API - free tier
        let apiURL = URL(string: "https://ytstream-download-youtube-videos.p.rapidapi.com/dl?id=\(videoId)")!
        
        progressCallback("Fetching from YTStream...")
        
        var request = URLRequest(url: apiURL)
        request.timeoutInterval = 30.0
        // Note: Add your RapidAPI key here if you want to use this
        // request.setValue("YOUR_RAPIDAPI_KEY", forHTTPHeaderField: "X-RapidAPI-Key")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw DownloadError.youtubeFailed
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let formats = json["formats"] as? [[String: Any]] else {
            throw DownloadError.youtubeFailed
        }
        
        // Find audio-only format
        let audioFormat = formats.first { format in
            if let formatNote = format["format_note"] as? String {
                return formatNote.lowercased().contains("audio")
            }
            return false
        }
        
        guard let format = audioFormat,
              let audioURL = format["url"] as? String else {
            throw DownloadError.youtubeFailed
        }
        
        Logger.log("Found audio URL from YTStream", category: "Download")
        
        progressCallback("Downloading from YTStream...")
        
        guard let streamURL = URL(string: audioURL) else {
            throw DownloadError.youtubeFailed
        }
        
        let (audioData, _) = try await URLSession.shared.data(from: streamURL)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try audioData.write(to: tempURL)
        
        Logger.success("Downloaded \(audioData.count / 1024) KB from YTStream", category: "Download")
        return tempURL
    }
    
    // MARK: - Direct Extraction (Simplified)
    
    private func downloadDirectExtraction(videoId: String, progressCallback: @escaping (String) -> Void) async throws -> URL {
        // Try to get video info and extract audio stream directly
        // This is a simplified approach - in production you'd need to handle signature decryption
        
        progressCallback("Attempting direct extraction...")
        
        let videoInfoURL = URL(string: "https://www.youtube.com/get_video_info?video_id=\(videoId)")!
        
        var request = URLRequest(url: videoInfoURL)
        request.timeoutInterval = 20.0
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let responseString = String(data: data, encoding: .utf8),
              let urlComponents = URLComponents(string: "?" + responseString),
              let playerResponse = urlComponents.queryItems?.first(where: { $0.name == "player_response" })?.value,
              let playerData = playerResponse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: playerData) as? [String: Any],
              let streamingData = json["streamingData"] as? [String: Any],
              let adaptiveFormats = streamingData["adaptiveFormats"] as? [[String: Any]] else {
            throw DownloadError.youtubeFailed
        }
        
        // Find audio stream
        let audioFormats = adaptiveFormats.filter { format in
            if let mimeType = format["mimeType"] as? String {
                return mimeType.contains("audio")
            }
            return false
        }
        
        guard let bestAudio = audioFormats.first,
              let urlString = bestAudio["url"] as? String,
              let streamURL = URL(string: urlString) else {
            throw DownloadError.youtubeFailed
        }
        
        Logger.log("Found direct audio stream", category: "Download")
        
        progressCallback("Downloading direct stream...")
        
        let (audioData, _) = try await URLSession.shared.data(from: streamURL)
        
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        try audioData.write(to: tempURL)
        
        Logger.success("Downloaded \(audioData.count / 1024) KB directly", category: "Download")
        return tempURL
    }
}

// MARK: - Error Extensions

extension DownloadError {
    static let allMethodsFailed = DownloadError.youtubeFailed
}
