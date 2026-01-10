//
//  ArtworkView.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import SwiftUI

struct ArtworkView: View {
    let artworkPath: String?
    let size: CGFloat
    let song: Song?   // Optional Song for enhanced validation
    let cornerRadius: CGFloat?
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = true
    
    init(artworkPath: String?, size: CGFloat, song: Song? = nil, cornerRadius: CGFloat? = nil) {
        self.artworkPath = artworkPath
        self.size = size
        self.song = song
        self.cornerRadius = cornerRadius
    }
    
    private var resolvedCornerRadius: CGFloat {
        cornerRadius ?? (size * 0.1)
    }
    
    var body: some View {
        Group {
            if let image = loadedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Fallback to gradient with music note
                RoundedRectangle(cornerRadius: resolvedCornerRadius)
                    .fill(LinearGradient(
                        gradient: Gradient(colors: [
                            Color(red: 0.478, green: 0.651, blue: 1.0),
                            Color(red: 1.0, green: 0.294, blue: 0.698)
                        ]),
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.4, weight: .light))
                            .foregroundColor(.white.opacity(0.9))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: resolvedCornerRadius))
        .task(id: artworkPath) {
            await loadImageAsync()
        }
    }
    
    private func loadImageAsync() async {
        guard let path = artworkPath else {
            isLoading = false
            return
        }
        
        await MainActor.run {
            // Load image async with caching (prevents main thread blocking)
            ImageCache.shared.loadImage(from: path, targetSize: CGSize(width: size * 2, height: size * 2)) { image in
                self.loadedImage = image
                self.isLoading = false
            }
        }
    }
}
