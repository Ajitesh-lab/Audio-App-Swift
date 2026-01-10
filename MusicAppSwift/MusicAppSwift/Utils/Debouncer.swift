//
//  Debouncer.swift
//  MusicAppSwift
//
//  Debounces frequent async operations to reduce UI churn
//

import Foundation

actor Debouncer {
    private var task: Task<Void, Never>?
    
    func debounce(duration: Duration = .milliseconds(300), operation: @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: duration)
            if !Task.isCancelled {
                await operation()
            }
        }
    }
    
    func cancel() {
        task?.cancel()
        task = nil
    }
}
