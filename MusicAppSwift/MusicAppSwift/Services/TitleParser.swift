//
//  TitleParser.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import Foundation

struct ParsedTitle {
    let artist: String
    let track: String
    let confidence: TitleParserConfidence
}

enum TitleParserConfidence {
    case high      // Clear artist - track pattern
    case medium    // Some separators found
    case low       // No clear pattern
}

class TitleParser {
    
    // MARK: - Noise Words to Remove
    
    private static let noisePatterns = [
        // Version indicators - CRITICAL for preventing remix covers
        "remix",
        "remixed",
        "cover",
        "covered by",
        "nightcore",
        "slowed",
        "slowed + reverb",
        "sped up",
        "speed up",
        "8d audio",
        "8d",
        "bass boosted",
        "reverb",
        "edit",
        "acoustic",
        "piano version",
        "instrumental",
        "karaoke",
        
        // Video types
        "official video",
        "official music video",
        "official audio",
        "music video",
        "official lyric video",
        "lyric video",
        "lyrics video",
        "visualizer",
        "visualiser",
        
        // Quality indicators
        "hd",
        "4k",
        "1080p",
        "720p",
        "high quality",
        "hq",
        
        // Version indicators
        "remastered",
        "remaster",
        "deluxe edition",
        "explicit",
        "clean version",
        "radio edit",
        "extended version",
        "extended mix",
        
        // Generic words
        "full video",
        "full audio",
        "with lyrics",
        "w/ lyrics",
        "lyrics",
        "audio",
        "video",
        "clip",
        "new"
    ]
    
    private static let featuringPatterns = [
        "feat.",
        "feat",
        "ft.",
        "ft",
        "featuring",
        "with"
    ]
    
    // Common separators between artist and track
    private static let separators = [
        " - ",
        " – ",  // en dash
        " — ",  // em dash
        " | ",
        " • "
    ]
    
    // MARK: - Main Parsing Function
    
    static func parse(_ title: String) -> ParsedTitle {
        var cleaned = title
        
        // Step 1: Remove brackets and parentheses content (often noise)
        cleaned = removeBracketsContent(from: cleaned)
        
        // Step 2: Remove noise words
        cleaned = removeNoiseWords(from: cleaned)
        
        // Step 3: Try to split by separator
        if let parsed = trySplitBySeparator(cleaned) {
            return parsed
        }
        
        // Step 4: Try to extract featuring artist
        if let parsed = tryExtractFeaturing(cleaned) {
            return parsed
        }
        
        // Step 5: Low confidence - return as is
        return ParsedTitle(
            artist: "Unknown Artist",
            track: cleaned.trimmingCharacters(in: .whitespacesAndNewlines).titleCased(),
            confidence: .low
        )
    }
    
    // MARK: - Cleaning Functions
    
    private static func removeBracketsContent(from title: String) -> String {
        var result = title
        
        // Remove [...] content
        result = result.replacingOccurrences(
            of: "\\[[^\\]]*\\]",
            with: "",
            options: .regularExpression
        )
        
        // Remove (...) content but keep if it looks like featuring
        let parenPattern = "\\([^)]*\\)"
        if let regex = try? NSRegularExpression(pattern: parenPattern) {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..., in: result))
            
            for match in matches.reversed() {
                if let range = Range(match.range, in: result) {
                    let content = String(result[range]).lowercased()
                    // Keep if it contains featuring info
                    let keepParens = featuringPatterns.contains { content.contains($0) }
                    if !keepParens {
                        result.removeSubrange(range)
                    }
                }
            }
        }
        
        return result
    }
    
    private static func removeNoiseWords(from title: String) -> String {
        var result = title.lowercased()
        
        // Remove all noise patterns
        for pattern in noisePatterns {
            result = result.replacingOccurrences(of: pattern, with: "", options: .caseInsensitive)
        }
        
        // Clean up extra spaces
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        
        return result
    }
    
    // MARK: - Version Detection
    
    static func isRemixOrCover(_ title: String) -> Bool {
        let lowercased = title.lowercased()
        let remixIndicators = [
            "remix", "remixed", "cover", "nightcore", "slowed",
            "sped up", "speed up", "8d", "bass boosted",
            "reverb", "edit", "acoustic version", "piano version",
            "instrumental", "karaoke"
        ]
        
        for indicator in remixIndicators {
            if lowercased.contains(indicator) {
                print("⚠️ Detected non-original version: contains '\(indicator)'")
                return true
            }
        }
        return false
    }
    
    // MARK: - Pattern Recognition
    
    private static func trySplitBySeparator(_ title: String) -> ParsedTitle? {
        for separator in separators {
            if title.contains(separator) {
                let parts = title.components(separatedBy: separator)
                guard parts.count >= 2 else { continue }
                
                let first = parts[0].trimmingCharacters(in: .whitespacesAndNewlines).titleCased()
                let second = parts[1].trimmingCharacters(in: .whitespacesAndNewlines).titleCased()
                
                print("🔍 TitleParser: Separator '\(separator)' found")
                print("   Part 1: '\(first)' (length: \(first.count))")
                print("   Part 2: '\(second)' (length: \(second.count))")
                
                // Standard format is "Artist - Song Title"
                // Artist names are typically shorter than song titles
                // High confidence if first part is 2-30 chars (typical artist name length)
                let firstIsArtistLength = first.count >= 2 && first.count <= 30
                let secondIsTrackLength = second.count >= 2 && second.count <= 80
                
                if firstIsArtistLength && secondIsTrackLength {
                    print("   ✅ Standard format: '\(first)' - '\(second)'")
                    return ParsedTitle(
                        artist: first,
                        track: second,
                        confidence: .high
                    )
                }
                
                // If first part is very long (>40 chars), might be reversed
                if first.count > 40 && second.count < 40 {
                    print("   🔄 Reversed format detected: '\(second)' - '\(first)'")
                    return ParsedTitle(
                        artist: second,
                        track: first,
                        confidence: .medium
                    )
                }
                
                // Default: assume standard format
                print("   ⚠️ Ambiguous, using standard format")
                return ParsedTitle(
                    artist: first,
                    track: second,
                    confidence: .medium
                )
            }
        }
        
        return nil
    }
    
    private static func tryExtractFeaturing(_ title: String) -> ParsedTitle? {
        let lowercased = title.lowercased()
        
        for pattern in featuringPatterns {
            if let range = lowercased.range(of: pattern) {
                let mainPart = String(title[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines).titleCased()
                
                // Try to split main part
                if let parsed = trySplitBySeparator(mainPart) {
                    return parsed
                }
                
                return ParsedTitle(
                    artist: "Unknown Artist",
                    track: mainPart,
                    confidence: .medium
                )
            }
        }
        
        return nil
    }
    
    // MARK: - Validation
    
    static func validateMatch(
        parsedArtist: String,
        parsedTrack: String,
        spotifyTrack: SpotifyTrack,
        youtubeDuration: Double?
    ) -> Bool {
        // Check title similarity
        let trackScore = stringSimilarity(
            parsedTrack.lowercased(),
            spotifyTrack.name.lowercased()
        )
        
        // Check artist similarity
        let artistScore = stringSimilarity(
            parsedArtist.lowercased(),
            spotifyTrack.primaryArtist.lowercased()
        )
        
        // Check duration if available (within 2 seconds)
        var durationMatch = true
        if let ytDuration = youtubeDuration {
            let spotifyDurationSec = Double(spotifyTrack.duration_ms) / 1000.0
            let difference = abs(ytDuration - spotifyDurationSec)
            durationMatch = difference <= 2.0
        }
        
        // Need good track match, reasonable artist match, and duration match
        return trackScore > 0.6 && artistScore > 0.4 && durationMatch
    }
    
    // Simple Levenshtein-based similarity
    private static func stringSimilarity(_ s1: String, _ s2: String) -> Double {
        let longer = s1.count > s2.count ? s1 : s2
        let shorter = s1.count > s2.count ? s2 : s1
        
        if longer.count == 0 {
            return 1.0
        }
        
        let distance = levenshteinDistance(shorter, longer)
        return (Double(longer.count) - Double(distance)) / Double(longer.count)
    }
    
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)
        var matrix = [[Int]](repeating: [Int](repeating: 0, count: s2Array.count + 1), count: s1Array.count + 1)
        
        for i in 0...s1Array.count {
            matrix[i][0] = i
        }
        
        for j in 0...s2Array.count {
            matrix[0][j] = j
        }
        
        for i in 1...s1Array.count {
            for j in 1...s2Array.count {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i - 1][j] + 1,
                    matrix[i][j - 1] + 1,
                    matrix[i - 1][j - 1] + cost
                )
            }
        }
        
        return matrix[s1Array.count][s2Array.count]
    }
}
