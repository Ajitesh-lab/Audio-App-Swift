//
//  SongRow.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/01/2026.
//

import SwiftUI

struct SongRow: View {
    let song: Song
    @ObservedObject var musicPlayer: MusicPlayer
    @Binding var songToDelete: Song?
    @Binding var showDeleteConfirmation: Bool
    
    var isPlaying: Bool {
        musicPlayer.currentSong?.id == song.id && musicPlayer.isPlaying
    }
    
    var body: some View {
        Button(action: {
            musicPlayer.play(song)
        }) {
            HStack(spacing: 12) {
                // Artwork
                ArtworkView(
                    artworkPath: song.artworkPath,
                    size: 52,
                    song: song,
                    cornerRadius: 8
                )
                
                // Song Info
                VStack(alignment: .leading, spacing: 4) {
                    Text(song.title)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(isPlaying ? .blue : .black)
                        .lineLimit(1)
                    
                    Text(song.artist)
                        .font(.system(size: 14))
                        .foregroundColor(.black.opacity(0.6))
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Playing indicator or more button
                if isPlaying {
                    Image(systemName: "waveform")
                        .font(.system(size: 18))
                        .foregroundColor(.blue)
                        .symbolEffect(.variableColor.iterative.reversing)
                } else {
                    Menu {
                        Button(action: {
                            musicPlayer.play(song)
                        }) {
                            Label("Play Now", systemImage: "play.fill")
                        }
                        
                        Button(action: {
                            musicPlayer.playNext(song)
                        }) {
                            Label("Play Next", systemImage: "text.insert")
                        }
                        
                        Button(action: {
                            musicPlayer.addToQueue(song)
                        }) {
                            Label("Add to Queue", systemImage: "text.append")
                        }
                        
                        Divider()
                        
                        Button(action: {
                            musicPlayer.toggleLike(song)
                        }) {
                            Label(
                                musicPlayer.likedSongs.contains(song.id) ? "Unlike" : "Like",
                                systemImage: musicPlayer.likedSongs.contains(song.id) ? "heart.fill" : "heart"
                            )
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            songToDelete = song
                            showDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18))
                            .foregroundColor(.black.opacity(0.6))
                            .rotationEffect(.degrees(90))
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .contextMenu {
            Button(action: {
                musicPlayer.play(song)
            }) {
                Label("Play Now", systemImage: "play.fill")
            }
            
            Button(action: {
                musicPlayer.playNext(song)
            }) {
                Label("Play Next", systemImage: "text.insert")
            }
            
            Button(action: {
                musicPlayer.addToQueue(song)
            }) {
                Label("Add to Queue", systemImage: "text.append")
            }
            
            Divider()
            
            Button(action: {
                musicPlayer.toggleLike(song)
            }) {
                Label(
                    musicPlayer.likedSongs.contains(song.id) ? "Unlike" : "Like",
                    systemImage: musicPlayer.likedSongs.contains(song.id) ? "heart.fill" : "heart"
                )
            }
            
            Divider()
            
            Button(role: .destructive) {
                songToDelete = song
                showDeleteConfirmation = true
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}
