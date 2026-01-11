//
//  DownloadQueueManager.swift
//  MusicAppSwift
//
//  Download queue system with auto-retry and alternative song matching
//

import Foundation
import Combine

// MARK: - Download Queue Item
struct DownloadQueueItem: Identifiable, Codable {
    let id: String
    let youtubeURL: String
    let videoId: String
    let title: String
    let channel: String?
    let duration: String? // Original duration string from YouTube
    let durationSeconds: Double? // Parsed duration for matching
    var status: DownloadStatus
    var progress: String
    var retryCount: Int
    var failureReason: String?
    var addedDate: Date
    var alternativeResults: [YouTubeResult] // Store search results for fallback
    var currentAlternativeIndex: Int // Which alternative we're trying
    
    enum DownloadStatus: String, Codable {
        case queued
        case downloading
        case completed
        case failed
        case retrying
    }
    
    init(youtubeResult: YouTubeResult, searchResults: [YouTubeResult] = []) {
        self.id = UUID().uuidString
        self.youtubeURL = "https://youtube.com/watch?v=\(youtubeResult.videoId)"
        self.videoId = youtubeResult.videoId
        self.title = youtubeResult.title
        self.channel = youtubeResult.channel
        self.duration = youtubeResult.duration
        self.durationSeconds = DownloadQueueItem.parseDuration(youtubeResult.duration)
        self.status = .queued
        self.progress = ""
        self.retryCount = 0
        self.failureReason = nil
        self.addedDate = Date()
        self.alternativeResults = searchResults
        self.currentAlternativeIndex = 0
    }
    
    static func parseDuration(_ durationString: String?) -> Double? {
        guard let duration = durationString else { return nil }
        
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

// MARK: - Download Queue Manager
class DownloadQueueManager: ObservableObject {
    static let shared = DownloadQueueManager()
    
    @Published var queue: [DownloadQueueItem] = []
    @Published var isProcessing = false
    
    private let maxRetries = 3
    private let durationMatchTolerance: Double = 30.0 // +/- 30 seconds acceptable
    private var currentDownloadTask: Task<Void, Never>?
    private let queueFilePath: URL
    
    private init() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        queueFilePath = documentsPath.appendingPathComponent("download_queue.json")
        loadQueue()
    }
    
    // MARK: - Queue Persistence
    
    private func saveQueue() {
        do {
            let data = try JSONEncoder().encode(queue)
            try data.write(to: queueFilePath)
            print("💾 Queue saved: \(queue.count) items")
        } catch {
            print("❌ Failed to save queue: \(error)")
        }
    }
    
    private func loadQueue() {
        guard FileManager.default.fileExists(atPath: queueFilePath.path) else { return }
        
        do {
            let data = try Data(contentsOf: queueFilePath)
            let loadedQueue = try JSONDecoder().decode([DownloadQueueItem].self, from: data)
            
            // Filter out completed items, keep failed/queued for retry
            queue = loadedQueue.filter { $0.status != .completed }
            print("📂 Queue loaded: \(queue.count) items")
            
            // Auto-resume processing if there are queued items
            if !queue.isEmpty && !isProcessing {
                Task {
                    await processQueue()
                }
            }
        } catch {
            print("❌ Failed to load queue: \(error)")
        }
    }
    
    // MARK: - Queue Management
    
    func addToQueue(youtubeResult: YouTubeResult, searchResults: [YouTubeResult]) {
        let item = DownloadQueueItem(youtubeResult: youtubeResult, searchResults: searchResults)
        
        DispatchQueue.main.async {
            self.queue.append(item)
            self.saveQueue()
            print("➕ Added to queue: \(item.title)")
            
            // Start processing if not already running
            if !self.isProcessing {
                Task {
                    await self.processQueue()
                }
            }
        }
    }
    
    func removeFromQueue(id: String) {
        DispatchQueue.main.async {
            self.queue.removeAll { $0.id == id }
            self.saveQueue()
        }
    }
    
    func clearCompleted() {
        DispatchQueue.main.async {
            self.queue.removeAll { $0.status == .completed }
            self.saveQueue()
        }
    }
    
    func retryFailed() {
        DispatchQueue.main.async {
            for index in self.queue.indices {
                if self.queue[index].status == .failed {
                    self.queue[index].status = .queued
                    self.queue[index].retryCount = 0
                    self.queue[index].failureReason = nil
                }
            }
            self.saveQueue()
            
            if !self.isProcessing {
                Task {
                    await self.processQueue()
                }
            }
        }
    }
    
    // MARK: - Queue Processing
    
    func processQueue() async {
        guard !isProcessing else { return }
        
        await MainActor.run {
            isProcessing = true
        }
        
        print("🚀 Starting queue processor...")
        
        while true {
            // Find next queued item
            guard let nextIndex = await MainActor.run(body: {
                queue.firstIndex { $0.status == .queued }
            }) else {
                // No more queued items
                break
            }
            
            // Process this item
            await processItem(at: nextIndex)
            
            // Small delay between downloads
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        }
        
        await MainActor.run {
            isProcessing = false
            print("✅ Queue processor finished")
        }
    }
    
    private func processItem(at index: Int) async {
        var item = await MainActor.run { queue[index] }
        
        await MainActor.run {
            queue[index].status = .downloading
            queue[index].progress = "Starting download..."
            saveQueue()
        }
        
        print("⬇️ Processing: \(item.title)")
        
        do {
            // Attempt download
            let song = try await MusicDownloadManager.shared.downloadAndProcessSong(
                youtubeURL: item.youtubeURL,
                youtubeTitle: item.title,
                youtubeDuration: item.durationSeconds,
                progressCallback: { progress in
                    Task { @MainActor in
                        if let idx = self.queue.firstIndex(where: { $0.id == item.id }) {
                            self.queue[idx].progress = progress
                        }
                    }
                }
            )
            
            // Success!
            await MainActor.run {
                if let idx = queue.firstIndex(where: { $0.id == item.id }) {
                    queue[idx].status = .completed
                    queue[idx].progress = "✅ Completed"
                    saveQueue()
                }
                
                // Add to player
                MusicPlayer.shared.addSong(song)
            }
            
            print("✅ Download completed: \(item.title)")
            
        } catch {
            print("❌ Download failed: \(error)")
            await handleDownloadFailure(itemId: item.id, error: error)
        }
    }
    
    private func handleDownloadFailure(itemId: String, error: Error) async {
        guard let index = await MainActor.run(body: { queue.firstIndex { $0.id == itemId } }) else {
            return
        }
        
        var item = await MainActor.run { queue[index] }
        
        // Check if we should try alternatives
        let shouldTryAlternative = item.retryCount < maxRetries && !item.alternativeResults.isEmpty
        
        if shouldTryAlternative {
            // Find next best alternative based on duration
            if let alternative = findNextBestAlternative(for: item) {
                await MainActor.run {
                    queue[index].retryCount += 1
                    queue[index].status = .retrying
                    queue[index].progress = "Trying alternative \(item.retryCount + 1)..."
                    queue[index].youtubeURL = "https://youtube.com/watch?v=\(alternative.videoId)"
                    queue[index].videoId = alternative.videoId
                    queue[index].title = alternative.title
                    queue[index].channel = alternative.channel
                    queue[index].currentAlternativeIndex += 1
                    queue[index].status = .queued // Re-queue for retry
                    saveQueue()
                }
                
                print("🔄 Retrying with alternative: \(alternative.title)")
                
                // Continue processing
                if !isProcessing {
                    Task {
                        await processQueue()
                    }
                }
            } else {
                // No suitable alternatives found
                await markAsFailed(index: index, reason: "No suitable alternatives found")
            }
        } else {
            // Max retries reached or no alternatives
            await markAsFailed(index: index, reason: error.localizedDescription)
        }
    }
    
    private func findNextBestAlternative(for item: DownloadQueueItem) -> YouTubeResult? {
        // Skip already tried alternatives
        let remaining = Array(item.alternativeResults.dropFirst(item.currentAlternativeIndex + 1))
        
        guard !remaining.isEmpty else { return nil }
        guard let targetDuration = item.durationSeconds else {
            // If no duration info, just try next one
            return remaining.first
        }
        
        // Find alternative with closest duration match
        let sorted = remaining.sorted { result1, result2 in
            let duration1 = DownloadQueueItem.parseDuration(result1.duration) ?? 0
            let duration2 = DownloadQueueItem.parseDuration(result2.duration) ?? 0
            
            let diff1 = abs(duration1 - targetDuration)
            let diff2 = abs(duration2 - targetDuration)
            
            return diff1 < diff2
        }
        
        // Return closest match if within tolerance
        if let best = sorted.first,
           let bestDuration = DownloadQueueItem.parseDuration(best.duration) {
            let difference = abs(bestDuration - targetDuration)
            if difference <= durationMatchTolerance {
                print("🎯 Found alternative with duration \(best.duration ?? "?") (target: \(item.duration ?? "?"))")
                return best
            }
        }
        
        // If no good match, still try the next one
        return remaining.first
    }
    
    private func markAsFailed(index: Int, reason: String) async {
        await MainActor.run {
            queue[index].status = .failed
            queue[index].failureReason = reason
            queue[index].progress = "❌ Failed"
            saveQueue()
        }
    }
}
