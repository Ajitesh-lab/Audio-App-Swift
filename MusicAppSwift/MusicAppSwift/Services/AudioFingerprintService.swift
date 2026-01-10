//
//  AudioFingerprintService.swift
//  MusicAppSwift
//
//  Generates deterministic audio fingerprints for version identification
//

import Foundation
import AVFoundation
import Accelerate

class AudioFingerprintService {
    static let shared = AudioFingerprintService()
    
    private init() {}
    
    /// Generate audio fingerprint from first 30-45 seconds of track
    func generateFingerprint(for audioUrl: String) async throws -> String {
        guard let url = URL(string: audioUrl) else {
            throw FingerprintError.invalidURL
        }
        
        print("🔍 Generating fingerprint for: \(url.lastPathComponent)")
        
        let asset = AVURLAsset(url: url)
        
        // Read first 30-45 seconds of audio
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        let sampleDuration = min(45.0, durationSeconds)
        
        let timeRange = CMTimeRange(
            start: .zero,
            duration: CMTime(seconds: sampleDuration, preferredTimescale: 600)
        )
        
        // Extract audio data
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else {
            throw FingerprintError.noAudioTrack
        }
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(output)
        reader.timeRange = timeRange
        
        guard reader.startReading() else {
            throw FingerprintError.readFailed
        }
        
        var audioData = Data()
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            
            let length = CMBlockBufferGetDataLength(blockBuffer)
            var data = Data(count: length)
            _ = data.withUnsafeMutableBytes { buffer in
                CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: buffer.baseAddress!)
            }
            audioData.append(data)
        }
        
        // Generate fingerprint from audio data
        let fingerprint = computeFingerprint(from: audioData)
        
        print("✅ Generated fingerprint: \(fingerprint)")
        return fingerprint
    }
    
    private func computeFingerprint(from audioData: Data) -> String {
        // Use SHA-256 for deterministic fingerprint
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        audioData.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(audioData.count), &hash)
        }
        
        // Take first 12 bytes and encode as hex for compact representation
        let fingerprintBytes = hash.prefix(12)
        let fingerprint = "fp_" + fingerprintBytes.map { String(format: "%02x", $0) }.joined()
        
        return fingerprint
    }
}

enum FingerprintError: Error {
    case invalidURL
    case noAudioTrack
    case readFailed
}

// Import CommonCrypto for SHA-256
import CommonCrypto
