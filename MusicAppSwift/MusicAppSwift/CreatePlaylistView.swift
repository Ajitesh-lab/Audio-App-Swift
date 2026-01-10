//
//  CreatePlaylistView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 06/12/2025.
//

import SwiftUI

struct CreatePlaylistView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var musicPlayer: MusicPlayer
    @Binding var isPresented: Bool
    @State private var playlistName = ""
    @State private var selectedColor = "#3B82F6"
    
    let colors = ["#3B82F6", "#EF4444", "#10B981", "#F59E0B", "#8B5CF6", "#EC4899", "#14B8A6", "#F97316"]
    
    var body: some View {
        NavigationView {
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
                
                VStack(spacing: 24) {
                    // Preview
                    GlassCard {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(hex: selectedColor))
                            .frame(height: 200)
                            .overlay(
                                VStack {
                                    Image(systemName: "music.note.list")
                                        .font(.system(size: 60))
                                        .foregroundColor(.white)
                                    if !playlistName.isEmpty {
                                        Text(playlistName)
                                            .font(.title3)
                                            .fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.top, 8)
                                    }
                                }
                            )
                    }
                    .padding()
                    
                    // Name Input
                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Playlist Name")
                                .font(.caption)
                                .foregroundColor(.gray)
                            TextField("My Awesome Playlist", text: $playlistName)
                                .textFieldStyle(PlainTextFieldStyle())
                                .font(.title3)
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                    
                    // Color Selection
                    GlassCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Color")
                                .font(.caption)
                                .foregroundColor(.gray)
                            
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                                ForEach(colors, id: \.self) { color in
                                    Circle()
                                        .fill(Color(hex: color))
                                        .frame(width: 50, height: 50)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.white, lineWidth: selectedColor == color ? 3 : 0)
                                        )
                                        .onTapGesture {
                                            selectedColor = color
                                        }
                                }
                            }
                        }
                        .padding()
                    }
                    .padding(.horizontal)
                    
                    // Create Button
                    Button(action: createPlaylist) {
                        Text("Create Playlist")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .disabled(playlistName.isEmpty)
                    .opacity(playlistName.isEmpty ? 0.5 : 1)
                    
                    Spacer()
                }
            }
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func createPlaylist() {
        musicPlayer.createPlaylist(name: playlistName, color: selectedColor)
        dismiss()
    }
}
