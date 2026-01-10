//
//  StringCapitalization.swift
//  MusicAppSwift
//
//  Created by Devendra Rawat on 10/12/2025.
//

import Foundation

extension String {
    func titleCased() -> String {
        // Words that should stay lowercase unless they're the first word
        let lowercaseWords = Set([
            "a", "an", "and", "as", "at", "but", "by", "for", "from",
            "in", "into", "like", "of", "on", "or", "the", "to", "with"
        ])
        
        // Words that should stay uppercase
        let uppercaseWords = Set([
            "dj", "mc", "tv", "usa", "uk", "ny", "la", "ac", "dc"
        ])
        
        let words = self.components(separatedBy: " ")
        
        return words.enumerated().map { index, word in
            let lowercased = word.lowercased()
            
            // Always capitalize first word
            if index == 0 {
                return word.prefix(1).uppercased() + word.dropFirst().lowercased()
            }
            
            // Keep certain acronyms uppercase
            if uppercaseWords.contains(lowercased) {
                return word.uppercased()
            }
            
            // Keep small words lowercase
            if lowercaseWords.contains(lowercased) {
                return lowercased
            }
            
            // Special handling for contractions and possessives
            if word.contains("'") {
                let parts = word.components(separatedBy: "'")
                return parts.map { part in
                    guard !part.isEmpty else { return part }
                    return part.prefix(1).uppercased() + part.dropFirst().lowercased()
                }.joined(separator: "'")
            }
            
            // Capitalize first letter of each word
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
