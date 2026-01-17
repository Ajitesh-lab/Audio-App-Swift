import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @State private var email = ""
    @State private var isLoading = false
    @State private var successMessage: String?
    @State private var errorMessage: String?
    
    // Custom colors
    private let primaryPurple = Color(red: 88/255, green: 86/255, blue: 214/255)
    private let textFieldBorder = Color.gray.opacity(0.3)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Close Button
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.black)
                            .font(.system(size: 18))
                    }
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                
                // App Title
                Text("Sotre")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.top, 40)
                
                // Icon
                Image(systemName: "lock.rotation")
                    .font(.system(size: 60))
                    .foregroundColor(primaryPurple)
                    .padding(.top, 40)
                    .padding(.bottom, 20)
                
                // Title
                Text("Forgot Password?")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .padding(.bottom, 10)
                
                // Description
                Text("Enter your email address and we'll send you instructions to reset your password")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.bottom, 30)
                
                // Email Field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Email")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    TextField("Enter your email", text: $email)
                        .autocapitalization(.none)
                        .keyboardType(.emailAddress)
                        .padding()
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(textFieldBorder, lineWidth: 1)
                        )
                }
                .padding(.horizontal, 30)
                
                // Success Message
                if let success = successMessage {
                    Text(success)
                        .foregroundColor(.green)
                        .font(.caption)
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                }
                
                // Error Message
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal, 30)
                        .padding(.top, 10)
                }
                
                // Reset Button
                Button(action: resetPassword) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("SEND RESET LINK")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(primaryPurple)
                .cornerRadius(8)
                .padding(.horizontal, 30)
                .padding(.top, 20)
                .disabled(isLoading)
                
                // Back to Login
                Button(action: { dismiss() }) {
                    Text("Back to ")
                        .foregroundColor(.gray)
                    + Text("Login")
                        .foregroundColor(.black)
                        .fontWeight(.semibold)
                }
                .padding(.top, 20)
                
                Spacer()
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
    
    private func resetPassword() {
        guard !email.isEmpty else {
            errorMessage = "Please enter your email"
            return
        }
        
        // Validate email format
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        guard emailPredicate.evaluate(with: email) else {
            errorMessage = "Please enter a valid email"
            return
        }
        
        isLoading = true
        errorMessage = nil
        successMessage = nil
        
        Task {
            do {
                // Call password reset API
                let baseURL = ServerConfig.hosts.first ?? "https://audio-rough-water-3069.fly.dev"
                guard let url = URL(string: "\(baseURL)/api/auth/forgot-password") else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                let body = ["email": email]
                request.httpBody = try JSONEncoder().encode(body)
                
                let (data, response) = try await URLSession.shared.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
                }
                
                if httpResponse.statusCode == 200 {
                    await MainActor.run {
                        isLoading = false
                        successMessage = "Reset instructions sent! Check your email."
                    }
                } else {
                    let errorResponse = try? JSONDecoder().decode([String: String].self, from: data)
                    throw NSError(domain: "", code: httpResponse.statusCode, 
                                userInfo: [NSLocalizedDescriptionKey: errorResponse?["error"] ?? "Failed to send reset email"])
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
