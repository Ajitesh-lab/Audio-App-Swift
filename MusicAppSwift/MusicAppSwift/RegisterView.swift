import SwiftUI

struct RegisterView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var authService: AuthService
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var name = ""
    @State private var licenseKey = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showPassword = false
    @State private var showConfirmPassword = false
    
    // Custom colors matching the screenshot
    private let primaryPurple = Color(red: 88/255, green: 86/255, blue: 214/255)
    private let textFieldBorder = Color.gray.opacity(0.3)
    
    var body: some View {
        NavigationView {
            ScrollView {
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
                        .padding(.top, 20)
                        .padding(.bottom, 30)
                    
                    VStack(spacing: 20) {
                        // Create Account Title
                        Text("Create Account")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 30)
                        
                        // Name Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Name (optional)")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            TextField("Enter your name", text: $name)
                                .foregroundColor(.black)
                                .padding()
                                .background(Color.white)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(textFieldBorder, lineWidth: 1)
                                )
                        }
                        .padding(.horizontal, 30)
                        
                        // Email Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            TextField("Enter your email", text: $email)
                                .foregroundColor(.black)
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
                        
                        // License Key Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("License Key")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            TextField("XXXX-XXXX-XXXX-XXXX", text: $licenseKey)
                                .foregroundColor(.black)
                                .autocapitalization(.allCharacters)
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
                        
                        // Confirm Password Field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Confirm Password")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            
                            HStack {
                                if showConfirmPassword {
                                    TextField("********", text: $confirmPassword)
                                        .foregroundColor(.black)
                                } else {
                                    SecureField("********", text: $confirmPassword)
                                        .foregroundColor(.black)
                                }
                                
                                Button(action: { showConfirmPassword.toggle() }) {
                                    Image(systemName: showConfirmPassword ? "eye" : "eye.slash")
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
                        
                        // Error Message
                        if let error = errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                                .padding(.horizontal, 30)
                        }
                        
                        // Register Button
                        Button(action: register) {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("CREATE ACCOUNT")
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
                        
                        // Login Link
                        Button(action: { dismiss() }) {
                            Text("Already have an account? ")
                                .foregroundColor(.gray)
                            + Text("Login")
                                .foregroundColor(.black)
                                .fontWeight(.semibold)
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 40)
                    }
                }
            }
            .background(Color.white)
            .navigationBarHidden(true)
        }
    }
    
    private func register() {
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
        
        guard !licenseKey.isEmpty else {
            errorMessage = "Please enter your license key"
            return
        }
        
        guard password == confirmPassword else {
            errorMessage = "Passwords don't match"
            return
        }
        
        guard password.count >= 6 else {
            errorMessage = "Password must be at least 6 characters"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                _ = try await authService.register(
                    email: email,
                    password: password,
                    name: name.isEmpty ? nil : name,
                    licenseKey: licenseKey.trimmingCharacters(in: .whitespaces)
                )
                await MainActor.run {
                    isLoading = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Parse error message
                    let errorString = error.localizedDescription
                    print("Registration error: \(errorString)")
                    
                    if errorString.contains("409") || errorString.contains("already exists") {
                        errorMessage = "An account with this email already exists"
                    } else if errorString.contains("400") && errorString.contains("license") {
                        errorMessage = "Invalid or already used license key"
                    } else if errorString.contains("Invalid license key") {
                        errorMessage = "Invalid license key"
                    } else if errorString.contains("already been used") {
                        errorMessage = "This license key has already been used"
                    } else if errorString.contains("network") || errorString.contains("Internet") {
                        errorMessage = "No internet connection"
                    } else {
                        errorMessage = "Registration failed: \(errorString)"
                    }
                }
            }
        }
    }
}

#Preview {
    RegisterView()
        .environmentObject(AuthService())
}
