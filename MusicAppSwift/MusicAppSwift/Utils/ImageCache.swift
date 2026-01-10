//
//  ImageCache.swift
//  MusicAppSwift
//
//  High-performance image cache using NSCache
//

import UIKit

/// High-performance image cache using NSCache
class ImageCache {
    static let shared = ImageCache()
    
    private let cache = NSCache<NSString, UIImage>()
    private let ioQueue = DispatchQueue(label: "com.musicapp.imagecache", qos: .userInitiated)
    
    private init() {
        cache.countLimit = 200 // Cache up to 200 images
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }
    
    func image(forKey key: String) -> UIImage? {
        return cache.object(forKey: key as NSString)
    }
    
    func loadImage(from path: String, targetSize: CGSize, completion: @escaping (UIImage?) -> Void) {
        let cacheKey = "\(path)-\(Int(targetSize.width))" as NSString
        
        // Check cache first (fast path)
        if let cached = cache.object(forKey: cacheKey) {
            completion(cached)
            return
        }
        
        // Load and decode off main thread
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            
            guard FileManager.default.fileExists(atPath: path),
                  let original = UIImage(contentsOfFile: path) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            
            // Resize to target size (reduces memory footprint)
            let resized = self.resize(image: original, to: targetSize)
            
            // Cache the result
            self.cache.setObject(resized, forKey: cacheKey)
            
            DispatchQueue.main.async {
                completion(resized)
            }
        }
    }
    
    private func resize(image: UIImage, to targetSize: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
    
    func clearCache() {
        cache.removeAllObjects()
    }
}
