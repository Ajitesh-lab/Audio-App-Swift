import SwiftUI

/// Debug-only view to surface the last few download log lines from disk.
/// Not linked in production UI; present manually when needed.
struct DownloadLogDebugView: View {
    @State private var logs: [String] = []
    
    var body: some View {
        NavigationView {
            List(logs, id: \.self) { line in
                Text(line)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
            }
            .navigationTitle("Download Logs")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Refresh") { loadLogs() }
                }
            }
            .onAppear { loadLogs() }
        }
    }
    
    private func loadLogs() {
        logs = [] // MusicDownloadManager.shared.recentLogs()
    }
}
