//
//  ExpandedPlayerView.swift
//  MusicAppSwift
//
//  Simplified premium player with consistent design system
//

import SwiftUI

struct ExpandedPlayerView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var musicPlayer: MusicPlayer
    @State private var isScrubbing = false
    @State private var scrubTime: Double = 0
    
    var song: Song? {
        return musicPlayer.currentSong
    }
    
    var body: some View {
        ZStack {
            // Clean gradient background
            LinearGradient(
                gradient: Gradient(colors: [
                    Color(red: 0.86, green: 0.92, blue: 0.99),
                    Color(red: 0.93, green: 0.96, blue: 1.0)
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Swipe indicator
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(DesignSystem.Colors.secondaryText)
                    .frame(width: 36, height: 5)
                    .padding(.top, DesignSystem.Spacing.xs)
                    .padding(.bottom, DesignSystem.Spacing.md)
                
                VStack(spacing: DesignSystem.Spacing.lg) {
                    Spacer()
                    
                    // Album Artwork - Large and centered
                    ArtworkView(
                        artworkPath: song?.artworkPath,
                        size: 300,
                        song: song
                    )
                        .shadow(
                            color: DesignSystem.Shadow.large.color,
                            radius: DesignSystem.Shadow.large.radius,
                            x: DesignSystem.Shadow.large.x,
                            y: DesignSystem.Shadow.large.y
                        )
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .animation(.easeInOut(duration: DesignSystem.Animation.normal), value: song?.id)
                    
                    // Song Info - Clean hierarchy
                    if let song = song {
                        VStack(spacing: DesignSystem.Spacing.xs) {
                            Text(song.title)
                                .font(DesignSystem.Typography.title2)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                            Text(song.artist)
                                .font(DesignSystem.Typography.body)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                        }
                        .padding(.horizontal, DesignSystem.Spacing.xl)
                        .padding(.top, DesignSystem.Spacing.md)
                    }
                    
                    // Progress Slider
                    VStack(spacing: DesignSystem.Spacing.xs) {
                        Slider(
                            value: $scrubTime,
                            in: 0...max(musicPlayer.duration, 1),
                            onEditingChanged: { isEditing in
                                isScrubbing = isEditing
                                if isEditing {
                                    musicPlayer.startDragging()
                                    scrubTime = musicPlayer.currentTime
                                } else {
                                    musicPlayer.stopDragging(seekTo: scrubTime)
                                }
                            }
                        )
                        .tint(DesignSystem.Colors.accent)
                        
                        HStack {
                            Text(formatTime(isScrubbing ? scrubTime : musicPlayer.currentTime))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .monospacedDigit()
                            Spacer()
                            Text(formatTime(musicPlayer.duration))
                                .font(DesignSystem.Typography.caption)
                                .foregroundColor(DesignSystem.Colors.secondaryText)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.xl)
                    .padding(.top, DesignSystem.Spacing.md)
                    .onChange(of: musicPlayer.currentTime) { _, newValue in
                        if !isScrubbing {
                            scrubTime = newValue
                        }
                    }
                    
                    // Playback Controls - Simplified
                    HStack(spacing: DesignSystem.Spacing.xxl) {
                        Button(action: { 
                            withAnimation(.easeInOut(duration: DesignSystem.Animation.quick)) {
                                musicPlayer.skipBackward()
                            }
                        }) {
                            Image(systemName: "backward.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        
                        Button(action: { 
                            withAnimation(.easeInOut(duration: DesignSystem.Animation.quick)) {
                                musicPlayer.togglePlayPause()
                            }
                        }) {
                            Image(systemName: musicPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                .font(.system(size: 72, weight: .semibold))
                                .foregroundColor(.black)
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: musicPlayer.isPlaying)
                        
                        Button(action: { 
                            withAnimation(.easeInOut(duration: DesignSystem.Animation.quick)) {
                                musicPlayer.skipForward()
                            }
                        }) {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 34, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .padding(.top, DesignSystem.Spacing.md)
                    
                    Spacer()
                }
            }
        }
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height > 100 {
                        withAnimation(.easeOut(duration: DesignSystem.Animation.normal)) {
                            dismiss()
                        }
                    }
                }
        )
    }
    
    private func formatTime(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
