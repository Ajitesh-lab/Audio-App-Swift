import Foundation
import Combine
import UIKit

class AuthService: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authToken: String?
    
    private let baseURL = ServerConfig.hosts.first ?? "https://audio-rough-water-3069.fly.dev"
    
    // Get unique device ID
    private var deviceId: String {
        if let uuid = UIDevice.current.identifierForVendor?.uuidString {
            return uuid
        }
        // Fallback to saved UUID
        if let saved = UserDefaults.standard.string(forKey: "deviceId") {
            return saved
        }
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: "deviceId")
        return newUUID
    }
    
    private var deviceName: String {
        return UIDevice.current.name
    }
    
    init() {
        // Load saved token if exists
        if let token = UserDefaults.standard.string(forKey: "authToken") {
            self.authToken = token
            Task {
                await fetchCurrentUser()
            }
        }
    }
    
    // Register new user
    func register(email: String, password: String, name: String?, licenseKey: String) async throws -> User {
        guard let url = URL(string: "\(baseURL)/api/auth/register") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = RegisterRequest(
            email: email,
            password: password,
            name: name,
            licenseKey: licenseKey,
            deviceId: deviceId,
            deviceName: deviceName
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 201 {
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run {
                self.authToken = authResponse.token
                self.currentUser = authResponse.user
                self.isAuthenticated = true
            }
            UserDefaults.standard.set(authResponse.token, forKey: "authToken")
            return authResponse.user
        } else {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse?.error ?? "Registration failed")
        }
    }
    
    // Login existing user
    func login(email: String, password: String) async throws -> User {
        guard let url = URL(string: "\(baseURL)/api/auth/login") else {
            throw AuthError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = LoginRequest(
            email: email,
            password: password,
            deviceId: deviceId,
            deviceName: deviceName
        )
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }
        
        if httpResponse.statusCode == 200 {
            let authResponse = try JSONDecoder().decode(AuthResponse.self, from: data)
            await MainActor.run {
                self.authToken = authResponse.token
                self.currentUser = authResponse.user
                self.isAuthenticated = true
            }
            UserDefaults.standard.set(authResponse.token, forKey: "authToken")
            return authResponse.user
        } else {
            let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data)
            throw AuthError.serverError(errorResponse?.error ?? "Login failed")
        }
    }
    
    // Fetch current user profile
    func fetchCurrentUser() async {
        guard let token = authToken,
              let url = URL(string: "\(baseURL)/api/auth/me") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else { return }
            
            if httpResponse.statusCode == 200 {
                let userResponse = try JSONDecoder().decode(UserResponse.self, from: data)
                await MainActor.run {
                    self.currentUser = userResponse.user
                    self.isAuthenticated = true
                }
            } else {
                await logout()
            }
        } catch {
            await logout()
        }
    }
    
    // Logout
    func logout() async {
        await MainActor.run {
            self.authToken = nil
            self.currentUser = nil
            self.isAuthenticated = false
        }
        UserDefaults.standard.removeObject(forKey: "authToken")
    }
    
    // Get authorization header for API requests
    func getAuthHeader() -> [String: String] {
        if let token = authToken {
            return ["Authorization": "Bearer \(token)"]
        }
        return [:]
    }
}

// MARK: - Models
struct User: Codable, Identifiable {
    let id: Int
    let email: String
    let name: String?
    let createdAt: String?
    
    enum CodingKeys: String, CodingKey {
        case id, email, name
        case createdAt = "created_at"
    }
}

struct RegisterRequest: Codable {
    let email: String
    let password: String
    let name: String?
    let licenseKey: String
    let deviceId: String
    let deviceName: String
}

struct LoginRequest: Codable {
    let email: String
    let password: String
    let deviceId: String
    let deviceName: String
}

struct AuthResponse: Codable {
    let message: String
    let token: String
    let user: User
}

struct UserResponse: Codable {
    let user: User
}

struct ErrorResponse: Codable {
    let error: String
}

enum AuthError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case serverError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .invalidResponse:
            return "Invalid server response"
        case .serverError(let message):
            return message
        }
    }
}
