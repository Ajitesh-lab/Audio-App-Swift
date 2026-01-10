//
//  Logger.swift
//  MusicAppSwift
//
//  Conditional logging that compiles out in Release builds
//

import Foundation

enum Logger {
    static var isEnabled: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    static func log(_ message: String, category: String = "App") {
        guard isEnabled else { return }
        print("[\(category)] \(message)")
    }
    
    static func error(_ message: String, category: String = "App") {
        guard isEnabled else { return }
        print("❌ [\(category)] \(message)")
    }
    
    static func debug(_ message: String, category: String = "App") {
        guard isEnabled else { return }
        print("🔍 [\(category)] \(message)")
    }
    
    static func success(_ message: String, category: String = "App") {
        guard isEnabled else { return }
        print("✅ [\(category)] \(message)")
    }
}
