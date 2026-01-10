//
//  TestPlayerView.swift
//  MusicAppSwift
//
//  Test view for minimal lock screen player
//

import SwiftUI

struct TestPlayerView: View {
    @State private var isPlaying = false
    
    var body: some View {
        VStack(spacing: 30) {
            Text("Minimal Lock Screen Test")
                .font(.headline)
            
            Text("This uses a simplified PlayerManager to test lock screen controls")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            
            Button(action: playTestTrack) {
                HStack {
                    Image(systemName: "play.circle.fill")
                        .font(.title)
                    Text("Play Test Track")
                        .font(.headline)
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            Button(action: pauseTestTrack) {
                HStack {
                    Image(systemName: "pause.circle.fill")
                        .font(.title)
                    Text("Pause")
                        .font(.headline)
                }
                .padding()
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            Spacer()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions:")
                    .font(.caption)
                    .bold()
                Text("1. Tap 'Play Test Track'")
                Text("2. Lock your device")
                Text("3. Check if lock screen shows artwork + controls")
                Text("4. Try play/pause from lock screen")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            .padding()
            .background(Color.secondary.opacity(0.1))
            .cornerRadius(8)
        }
        .padding()
    }
    
    private func playTestTrack() {
        // Try to use one of the downloaded songs
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let musicPath = documentsPath.appendingPathComponent("Music")
        
        // Generate a default cover image
        let coverImage = generateDefaultCoverImage()
        
        // Try to find any downloaded song
        if let firstSong = findFirstDownloadedSong(in: musicPath) {
            print("🎵 Found downloaded song: \(firstSong.title)")
            PlayerManager.shared.play(
                url: firstSong.url,
                title: firstSong.title,
                artist: firstSong.artist,
                album: firstSong.album,
                artwork: firstSong.artwork ?? coverImage
            )
            isPlaying = true
        } else {
            print("⚠️ No downloaded songs found, using placeholder")
            // Fallback: use a remote URL for testing
            if let testURL = URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3") {
                PlayerManager.shared.play(
                    url: testURL,
                    title: "Test Song",
                    artist: "Test Artist",
                    album: "Test Album",
                    artwork: coverImage
                )
                isPlaying = true
            }
        }
    }
    
    private func pauseTestTrack() {
        PlayerManager.shared.pause()
        isPlaying = false
    }
    
    private func generateDefaultCoverImage() -> UIImage {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { context in
            // Gradient background
            let colors = [
                UIColor.systemBlue.cgColor,
                UIColor.systemPurple.cgColor
            ]
            let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors as CFArray,
                                     locations: [0.0, 1.0])!
            context.cgContext.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
            
            // Music note icon
            let noteSize: CGFloat = 256
            let noteRect = CGRect(
                x: (size.width - noteSize) / 2,
                y: (size.height - noteSize) / 2,
                width: noteSize,
                height: noteSize
            )
            
            let notePath = UIBezierPath()
            notePath.move(to: CGPoint(x: noteRect.midX, y: noteRect.minY))
            notePath.addLine(to: CGPoint(x: noteRect.midX, y: noteRect.maxY - 50))
            notePath.addArc(withCenter: CGPoint(x: noteRect.midX, y: noteRect.maxY - 25),
                           radius: 25,
                           startAngle: .pi,
                           endAngle: 0,
                           clockwise: true)
            
            UIColor.white.withAlphaComponent(0.8).setStroke()
            notePath.lineWidth = 12
            notePath.stroke()
        }
    }
    
    private func findFirstDownloadedSong(in musicPath: URL) -> (url: URL, title: String, artist: String, album: String, artwork: UIImage?)? {
        let fileManager = FileManager.default
        
        guard let enumerator = fileManager.enumerator(at: musicPath,
                                                       includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [.skipsHiddenFiles]) else {
            return nil
        }
        
        for case let fileURL as URL in enumerator {
            if fileURL.pathExtension.lowercased() == "mp3" {
                // Get parent directories for artist/album
                let components = fileURL.pathComponents
                let title = fileURL.deletingPathExtension().lastPathComponent
                let album = components.count > 2 ? components[components.count - 2] : "Unknown Album"
                let artist = components.count > 3 ? components[components.count - 3] : "Unknown Artist"
                
                // Try to find cover.jpg in same directory
                let artworkURL = fileURL.deletingLastPathComponent().appendingPathComponent("cover.jpg")
                let artwork = UIImage(contentsOfFile: artworkURL.path)
                
                return (url: fileURL, title: title, artist: artist, album: album, artwork: artwork)
            }
        }
        
        return nil
    }
}

#Preview {
    TestPlayerView()
}
