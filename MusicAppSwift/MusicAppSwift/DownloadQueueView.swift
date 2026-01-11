//
//  DownloadQueueView.swift
//  MusicAppSwift
//
//  Download queue interface with status tracking
//

import SwiftUI

struct DownloadQueueView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var queueManager = DownloadQueueManager.shared
    
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
                
                if queueManager.queue.isEmpty {
                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "tray",
                        description: Text("Your download queue is empty")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            // Active downloads section
                            if queueManager.queue.contains(where: { $0.status == .downloading || $0.status == .queued || $0.status == .retrying }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("Active Downloads")
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(.black)
                                        .padding(.horizontal)
                                    
                                    ForEach(queueManager.queue.filter { 
                                        $0.status == .downloading || $0.status == .queued || $0.status == .retrying 
                                    }) { item in
                                        DownloadQueueItemRow(item: item)
                                    }
                                }
                            }
                            
                            // Failed downloads section
                            if queueManager.queue.contains(where: { $0.status == .failed }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Failed Downloads")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.black)
                                        
                                        Spacer()
                                        
                                        Button("Retry All") {
                                            queueManager.retryFailed()
                                        }
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(queueManager.queue.filter { $0.status == .failed }) { item in
                                        DownloadQueueItemRow(item: item)
                                    }
                                }
                            }
                            
                            // Completed downloads section
                            if queueManager.queue.contains(where: { $0.status == .completed }) {
                                VStack(alignment: .leading, spacing: 12) {
                                    HStack {
                                        Text("Completed")
                                            .font(.system(size: 18, weight: .bold))
                                            .foregroundColor(.black)
                                        
                                        Spacer()
                                        
                                        Button("Clear") {
                                            queueManager.clearCompleted()
                                        }
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.blue)
                                    }
                                    .padding(.horizontal)
                                    
                                    ForEach(queueManager.queue.filter { $0.status == .completed }) { item in
                                        DownloadQueueItemRow(item: item)
                                    }
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                }
            }
            .navigationTitle("Download Queue")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DownloadQueueItemRow: View {
    let item: DownloadQueueItem
    @StateObject private var queueManager = DownloadQueueManager.shared
    
    var statusIcon: String {
        switch item.status {
        case .queued:
            return "clock"
        case .downloading:
            return "arrow.down.circle"
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "exclamationmark.circle.fill"
        case .retrying:
            return "arrow.clockwise.circle"
        }
    }
    
    var statusColor: Color {
        switch item.status {
        case .queued:
            return .orange
        case .downloading:
            return .blue
        case .completed:
            return .green
        case .failed:
            return .red
        case .retrying:
            return .purple
        }
    }
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    // Status icon
                    Image(systemName: statusIcon)
                        .font(.system(size: 24))
                        .foregroundColor(statusColor)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(.black)
                            .lineLimit(2)
                        
                        if let channel = item.channel {
                            Text(channel)
                                .font(.system(size: 13))
                                .foregroundColor(.black.opacity(0.6))
                        }
                        
                        HStack(spacing: 8) {
                            if let duration = item.duration {
                                Text(duration)
                                    .font(.system(size: 12))
                                    .foregroundColor(.black.opacity(0.6))
                            }
                            
                            if item.retryCount > 0 {
                                Text("• Attempt \(item.retryCount + 1)")
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action button
                    if item.status == .failed {
                        Button(action: {
                            queueManager.removeFromQueue(id: item.id)
                        }) {
                            Image(systemName: "trash")
                                .font(.system(size: 18))
                                .foregroundColor(.red)
                        }
                    } else if item.status == .completed {
                        Button(action: {
                            queueManager.removeFromQueue(id: item.id)
                        }) {
                            Image(systemName: "xmark.circle")
                                .font(.system(size: 18))
                                .foregroundColor(.gray)
                        }
                    }
                }
                
                // Progress or error message
                if !item.progress.isEmpty || item.failureReason != nil {
                    HStack {
                        if item.status == .downloading || item.status == .retrying {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Text(item.failureReason ?? item.progress)
                            .font(.system(size: 12))
                            .foregroundColor(item.status == .failed ? .red : .black.opacity(0.7))
                            .lineLimit(2)
                    }
                    .padding(.leading, 52)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .padding(.horizontal)
    }
}

// Preview
#Preview {
    DownloadQueueView()
}
