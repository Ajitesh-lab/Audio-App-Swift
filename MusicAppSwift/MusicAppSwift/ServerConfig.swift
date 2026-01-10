import Foundation

enum ServerConfig {
    /// Ordered list of server base URLs to try (overrideable via UserDefaults key `ServerBaseURL`)
    static var hosts: [String] {
        var defaults = [
            "http://192.168.1.133:3001",
            "http://localhost:3001",
            "http://127.0.0.1:3001"
        ]
        
        if let override = UserDefaults.standard.string(forKey: "ServerBaseURL"),
           !override.isEmpty,
           let overrideURL = URL(string: override),
           overrideURL.scheme != nil {
            defaults.insert(override, at: 0)
        }
        
        return defaults
    }
}
