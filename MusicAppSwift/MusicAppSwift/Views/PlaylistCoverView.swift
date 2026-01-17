//
//  PlaylistCoverView.swift
//  MusicAppSwift
//
//  Created by OpenAI on 20/02/2025.
//

import SwiftUI

struct PlaylistCoverView: View {
    let playlist: Playlist
    var size: CGFloat = 160
    var cornerRadius: CGFloat = DesignSystem.CornerRadius.lg
    
    private var shadow: (color: Color, radius: CGFloat, x: CGFloat, y: CGFloat) {
        size >= 200 ? DesignSystem.Shadow.large : DesignSystem.Shadow.medium
    }
    
    var body: some View {
        Group {
            if let image = resolvedImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let remoteURL = remoteCoverURL {
                AsyncImage(url: remoteURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
    
    private var resolvedImage: UIImage? {
        guard let cover = playlist.coverImageURL else { return nil }
        
        // Handle both raw file paths and file:// URLs
        let normalizedPath: String
        if cover.hasPrefix("file://"), let url = URL(string: cover) {
            normalizedPath = url.path
        } else {
            normalizedPath = cover
        }
        
        // Resolve relative paths to documents directory
        let fullPath: String
        if normalizedPath.hasPrefix("/") {
            // Already an absolute path
            fullPath = normalizedPath
        } else {
            // Relative path - resolve to documents directory
            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            fullPath = documentsPath.appendingPathComponent(normalizedPath).path
        }
        
        guard FileManager.default.fileExists(atPath: fullPath) else { return nil }
        return UIImage(contentsOfFile: fullPath)
    }
    
    private var remoteCoverURL: URL? {
        guard let cover = playlist.coverImageURL,
              let url = URL(string: cover),
              let scheme = url.scheme,
              scheme != "file" else {
            return nil
        }
        return url
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(hex: playlist.color),
                        Color(hex: playlist.color).opacity(0.7)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "music.note.list")
                    .font(.system(size: size * 0.28, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            )
    }
}
