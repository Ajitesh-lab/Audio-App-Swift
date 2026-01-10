//
//  MusicLiveActivity.swift
//  MusicAppSwift
//
//  Live Activity for Dynamic Island and Lock Screen
//

import Foundation
import SwiftUI
import AppIntents

#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(WidgetKit)
import WidgetKit
#endif

// MARK: - Widget Bundle (Live Activities don't need @main)
// Live Activities are activated by the app, not launched independently
@available(iOS 16.1, *)
struct MusicWidgetBundle: WidgetBundle {
    var body: some Widget {
        MusicLiveActivity()
    }
}

// MARK: - Live Activity Attributes
@available(iOS 16.1, *)
struct MusicActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var songTitle: String
        var artistName: String
        var isPlaying: Bool
        var progress: Double
        var duration: Double
        var artwork: String?
    }
    
    var albumArtURL: String?
}

// MARK: - Live Activity Widget
@available(iOS 16.1, *)
struct MusicLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MusicActivityAttributes.self) { context in
            // Lock screen/banner UI
            MusicLockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view - ALL regions must return unconditional views
                DynamicIslandExpandedRegion(.leading) {
                    Group {
                        if let artPath = context.state.artwork, !artPath.isEmpty,
                           let image = UIImage(contentsOfFile: artPath) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 70, height: 70)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else {
                            DefaultArtworkView()
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 4) {
                        Text(context.state.songTitle)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)
                            .lineLimit(1)
                        Text(context.state.artistName)
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.6))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if context.state.isPlaying {
                            AnimatedWaveformView()
                                .frame(width: 40, height: 70)
                        } else {
                            Image(systemName: "waveform")
                                .font(.system(size: 32))
                                .foregroundColor(.white.opacity(0.3))
                                .frame(width: 40, height: 70)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 16) {
                        // Progress bar without GeometryReader issues
                        HStack(spacing: 0) {
                            Capsule()
                                .fill(Color.white)
                                .frame(maxWidth: .infinity)
                            Capsule()
                                .fill(Color.white.opacity(0.2))
                                .frame(maxWidth: .infinity)
                        }
                        .frame(height: 3)
                        .padding(.horizontal, 20)
                        
                        HStack {
                            Text(formatTime(context.state.progress))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .monospacedDigit()
                            
                            Spacer()
                            
                            Text("-\(formatTime(context.state.duration - context.state.progress))")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .monospacedDigit()
                        }
                        .padding(.horizontal, 20)
                        
                        HStack(spacing: 50) {
                            Button(intent: PreviousTrackIntent()) {
                                Image(systemName: "backward.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                            
                            Button(intent: PlayPauseIntent()) {
                                Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 50))
                                    .foregroundColor(.white)
                            }
                            
                            Button(intent: NextTrackIntent()) {
                                Image(systemName: "forward.fill")
                                    .font(.system(size: 22))
                                    .foregroundColor(.white)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .padding(.bottom, 12)
                }
            } compactLeading: {
                ZStack {
                    WaveformRingView(isPlaying: context.state.isPlaying, size: 48)
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.9), .purple.opacity(0.9)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                        )
                }
                .frame(width: 52, height: 52)
                .allowsHitTesting(false)
            } compactTrailing: {
                HStack(spacing: 12) {
                    Image(systemName: context.state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                    
                    Image(systemName: "forward.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.8))
                }
                .allowsHitTesting(false)
            } minimal: {
                ZStack {
                    Group {
                        if context.state.isPlaying {
                            WaveformRingView(isPlaying: true, size: 30)
                        } else {
                            Circle()
                                .fill(Color.white.opacity(0.2))
                                .frame(width: 30, height: 30)
                        }
                    }
                    
                    Image(systemName: context.state.isPlaying ? "music.note" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
                .allowsHitTesting(false)
            }
        }
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}


// MARK: - Lock Screen View
@available(iOS 16.1, *)
struct MusicLockScreenView: View {
    let context: ActivityViewContext<MusicActivityAttributes>
    
    var body: some View {
        HStack(spacing: 16) {
            // Album art
            if let artURL = context.attributes.albumArtURL {
                AsyncImage(url: URL(string: artURL)) { image in
                    image.resizable()
                } placeholder: {
                    Color.gray
                }
                .frame(width: 50, height: 50)
                .cornerRadius(8)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(LinearGradient(
                        colors: [.blue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Image(systemName: "music.note")
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.songTitle)
                    .font(.headline)
                    .lineLimit(1)
                
                Text(context.state.artistName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                // Progress bar
                ProgressView(value: context.state.progress, total: context.state.duration)
                    .tint(.blue)
            }
            
            Spacer()
            
            Image(systemName: context.state.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .font(.title)
                .foregroundColor(.blue)
        }
        .padding()
    }
}

// MARK: - Album Art View
@available(iOS 16.1, *)
struct AlbumArtView: View {
    let context: ActivityViewContext<MusicActivityAttributes>
    
    var body: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.8), .purple.opacity(0.8), .pink.opacity(0.6)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 48, height: 48)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 20))
                    .foregroundColor(.white)
            )
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Compact Waveform Animation
@available(iOS 16.1, *)
struct CompactWaveform: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white)
                    .frame(width: 3, height: animating ? heights[index].max : heights[index].min)
                    .animation(
                        .easeInOut(duration: 0.5)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.15),
                        value: animating
                    )
            }
        }
        .frame(width: 14, height: 16)
        .onAppear {
            animating = true
        }
    }
    
    private let heights: [(min: CGFloat, max: CGFloat)] = [
        (6, 14),
        (8, 16),
        (5, 12)
    ]
}

// MARK: - Circular Waveform Ring
@available(iOS 16.1, *)
struct WaveformRingView: View {
    var isPlaying: Bool
    var size: CGFloat = 46
    
    private var radius: CGFloat { size / 2 - 6 }
    
    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.2), lineWidth: 2.4)
                
                ForEach(0..<16) { index in
                    let angle = Double(index) / 16 * .pi * 2
                    let wobble = isPlaying ? (sin(t * 2.0 + angle * 1.8) + 1) / 2 : 0
                    let height = 7.0 + wobble * 10.0
                    
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.65)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: 3, height: height)
                        .offset(y: -(radius))
                        .rotationEffect(.radians(angle))
                        .opacity(isPlaying ? 1.0 : 0.55)
                }
            }
        }
        .frame(width: size, height: size)
        .opacity(isPlaying ? 1 : 0.85)
        .animation(.easeInOut(duration: 0.6), value: isPlaying)
    }
}

// MARK: - Animated Waveform View for Expanded State
@available(iOS 16.1, *)
struct AnimatedWaveformView: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { timeline in
            Canvas { context, size in
                let barCount = 4
                let barWidth: CGFloat = 3
                let spacing: CGFloat = 4
                let totalWidth = CGFloat(barCount) * (barWidth + spacing) - spacing
                let startX = (size.width - totalWidth) / 2
                
                for i in 0..<barCount {
                    let x = startX + CGFloat(i) * (barWidth + spacing)
                    let phase = timeline.date.timeIntervalSinceReferenceDate
                    let offset = sin(phase * 3 + Double(i) * 0.5) * 15 + 15
                    let height = min(max(offset, 8), size.height - 10)
                    let y = (size.height - height) / 2
                    
                    let rect = CGRect(x: x, y: y, width: barWidth, height: height)
                    let path = RoundedRectangle(cornerRadius: 1.5).path(in: rect)
                    context.fill(path, with: .color(.white))
                }
            }
        }
    }
}

// MARK: - Default Artwork View
@available(iOS 16.1, *)
struct DefaultArtworkView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(
                LinearGradient(
                    colors: [.blue.opacity(0.7), .purple.opacity(0.8)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 70, height: 70)
            .overlay(
                Image(systemName: "music.note")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            )
    }
}

// MARK: - App Intents for Dynamic Island Controls
@available(iOS 16.0, *)
struct PlayPauseIntent: AppIntent {
    static var title: LocalizedStringResource = "Play/Pause"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        MusicPlayer.shared.togglePlayPause()
        return .result()
    }
}

@available(iOS 16.0, *)
struct NextTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Next Track"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        MusicPlayer.shared.skipForward()
        return .result()
    }
}

@available(iOS 16.0, *)
struct PreviousTrackIntent: AppIntent {
    static var title: LocalizedStringResource = "Previous Track"
    
    @MainActor
    func perform() async throws -> some IntentResult {
        MusicPlayer.shared.skipBackward()
        return .result()
    }
}
