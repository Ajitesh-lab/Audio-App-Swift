import SwiftUI

struct LoginView: View {
    @EnvironmentObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var showingRegistration = false
    @State private var showingForgotPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    
    // Custom colors matching the screenshot
    private let primaryPurple = Color(red: 88/255, green: 86/255, blue: 214/255)
    private let textFieldBorder = Color.gray.opacity(0.3)
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // App Title
                Text("Sotre")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.top, 40)
                    .padding(.bottom, 30)
                
                VStack(spacing: 16) {
                    // Sign In Title
                    Text("Sign In")
                        .font(.title2)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 30)
                    
                    // Email Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        TextField("Enter your email", text: $email)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .foregroundColor(.black)
                            .padding()
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(textFieldBorder, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 30)
                    
                    // Password Field
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Password")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        HStack {
                            if showPassword {
                                TextField("********", text: $password)
                                    .foregroundColor(.black)
                            } else {
                                SecureField("********", text: $password)
                                    .foregroundColor(.black)
                            }
                            
                            Button(action: { showPassword.toggle() }) {
                                Image(systemName: showPassword ? "eye" : "eye.slash")
                                    .foregroundColor(.gray)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(textFieldBorder, lineWidth: 1)
                        )
                    }
                    .padding(.horizontal, 30)
                    
                    // Forgot Password
                    Button(action: { showingForgotPassword = true }) {
                        Text("Forgot Password ?")
                            .font(.subheadline)
                            .foregroundColor(primaryPurple)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 30)
                    .padding(.top, -8)
                    
                    // Error Message
                    if let error = errorMessage {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                            .padding(.horizontal, 30)
                    }
                    
                    // Login Button
                    Button(action: login) {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("NEXT")
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(primaryPurple)
                    .cornerRadius(8)
                    .padding(.horizontal, 30)
                    .padding(.top, 5)
                    .disabled(isLoading)
                    
                    // Create Account Link
                    Button(action: { showingRegistration = true }) {
                        Text("Create a Account")
                            .foregroundColor(.black)
                            .fontWeight(.medium)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 20)
                }
                
                Spacer()
            }
            .background(Color.white)
            .navigationBarHidden(true)
            .sheet(isPresented: $showingRegistration) {
                RegisterView()
            }
            .sheet(isPresented: $showingForgotPassword) {
                ForgotPasswordView()
            }
        }
    }
    
    private func login() {
        guard !email.isEmpty, !password.isEmpty else {
            errorMessage = "Please enter email and password"
            return
        }
        
        // Validate email format
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        guard emailPredicate.evaluate(with: email) else {
            errorMessage = "Please enter a valid email address"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await authService.login(email: email, password: password)
                await MainActor.run {
                    isLoading = false
                    // Login successful - AuthService will update isAuthenticated
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Parse error message
                    let errorString = error.localizedDescription
                    if errorString.contains("401") || errorString.contains("Invalid credentials") {
                        errorMessage = "Invalid email or password"
                    } else if errorString.contains("403") || errorString.contains("Device limit") {
                        errorMessage = "Device limit reached. Please contact support."
                    } else if errorString.contains("network") || errorString.contains("Internet") {
                        errorMessage = "No internet connection"
                    } else {
                        errorMessage = "Login failed. Please try again."
                    }
                }
            }
        }
    }
    
    private func googleSignIn() {
        // Open Google OAuth URL in Safari
        let urlString = "https://audio-rough-water-3069.fly.dev/api/auth/google"
        
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid Google login URL"
            return
        }
        
        // Try to open the URL
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:]) { success in
                if !success {
                    DispatchQueue.main.async {
                        self.errorMessage = "Failed to open Google login"
                    }
                }
            }
        } else {
            errorMessage = "Cannot open Google login URL"
        }
    }
}

#Preview {
    LoginView()
        .environmentObject(AuthService())
}
