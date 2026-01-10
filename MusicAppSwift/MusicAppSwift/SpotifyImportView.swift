//
//  SpotifyImportView.swift
//  MusicAppSwift
//
//  UI for Spotify playlist import
//

import SwiftUI
import UIKit

struct SpotifyImportView: View {
    @ObservedObject var importService: SpotifyImportService
    @ObservedObject var musicPlayer: MusicPlayer
    @Environment(\.dismiss) var dismiss
    
    @State private var showLoginSheet = false
    @State private var showCompletionAlert = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.86, green: 0.92, blue: 0.99),
                        Color(red: 0.93, green: 0.96, blue: 1.0)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                if importService.isFetchingPlaylists {
                    connectingView
                } else if !importService.isImporting && importService.importQueue.isEmpty {
                    // Initial state
                    initialView
                } else if importService.isImporting || !importService.importQueue.isEmpty {
                    // Import in progress or completed
                    importProgressView
                }
            }
            .navigationTitle("Import from Spotify")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                // Reset authentication state when view appears
                importService.isAuthenticated = false
                importService.hasStartedFetchingPlaylists = false
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showLoginSheet) {
                SpotifyOAuthView(importService: importService)
            }
            .sheet(isPresented: $importService.showPlaylistSelection) {
                PlaylistSelectionView(importService: importService, musicPlayer: musicPlayer)
            }
            .onChange(of: importService.showPlaylistSelection) { oldValue, newValue in
                print("🔄 showPlaylistSelection changed from \(oldValue) to \(newValue)")
            }
            .onChange(of: importService.isAuthenticated) { oldValue, newValue in
                print("🔄 isAuthenticated changed from \(oldValue) to \(newValue)")
                if newValue && !oldValue {
                    // Dismiss login sheet; playlist fetch is started inside handleAuthCallback
                    showLoginSheet = false
                }
            }
            .alert("Import Complete!", isPresented: $showCompletionAlert) {
                Button("View Playlists") {
                    dismiss()
                }
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text("Successfully imported \(importService.completedSongs) songs into \(importService.playlistsInfo.count) playlists!\n\(importService.failedSongs) songs failed.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred")
            }
        }
    }
    
    // MARK: - Initial View
    
    private var initialView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            Spacer()
            
            // Spotify Icon
            Image(systemName: "music.note.list")
                .font(.system(size: 80, weight: .regular))
                .foregroundColor(DesignSystem.Colors.accent)
                .padding(.bottom, DesignSystem.Spacing.md)
            
            Text("Import Your Spotify Playlists")
                .font(DesignSystem.Typography.largeTitle)
                .multilineTextAlignment(.center)
            
            Text("Download all your Spotify songs and playlists to your library")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.xl)
            
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.sm) {
                featureRow(icon: "checkmark.circle.fill", text: "All playlists imported")
                featureRow(icon: "arrow.down.circle.fill", text: "Songs downloaded for offline")
                featureRow(icon: "music.note", text: "Auto-matched from YouTube")
                featureRow(icon: "folder.fill", text: "Organized in one playlist")
            }
            .padding(DesignSystem.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(Color.white.opacity(0.7))
            )
            .padding(.horizontal, DesignSystem.Spacing.lg)
            
            Spacer()
            
            Button(action: {
                // Reset auth state before showing login
                importService.isAuthenticated = false
                importService.hasStartedFetchingPlaylists = false
                showLoginSheet = true
            }) {
                HStack(spacing: DesignSystem.Spacing.sm) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(size: 20))
                    Text("Connect Spotify")
                        .font(DesignSystem.Typography.title3)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DesignSystem.Spacing.md)
                .background(DesignSystem.Colors.accent)
                .cornerRadius(DesignSystem.CornerRadius.md)
            }
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .padding(.bottom, DesignSystem.Spacing.lg)
        }
    }
    
    // MARK: - Import Progress View
    
    private var connectingView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            ProgressView(importService.currentStep.isEmpty ? "Connecting to Spotify..." : importService.currentStep)
                .progressViewStyle(CircularProgressViewStyle(tint: DesignSystem.Colors.accent))
                .padding()
            
            Text("Returning from Spotify. Fetching your playlists...")
                .font(DesignSystem.Typography.body)
                .foregroundColor(DesignSystem.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignSystem.Spacing.xl)
        }
    }
    
    private var importProgressView: some View {
        VStack(spacing: DesignSystem.Spacing.lg) {
            // Status Header
            VStack(spacing: DesignSystem.Spacing.sm) {
                Text(importService.currentStep)
                    .font(DesignSystem.Typography.title3)
                
                Text("\(importService.completedSongs)/\(importService.totalSongs) completed")
                    .font(DesignSystem.Typography.subheadline)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                
                if importService.failedSongs > 0 {
                    Text("\(importService.failedSongs) failed")
                        .font(DesignSystem.Typography.caption)
                        .foregroundColor(.red)
                }
                
                // Overall Progress Bar
                ProgressView(value: Double(importService.completedSongs), total: Double(importService.totalSongs))
                    .tint(DesignSystem.Colors.accent)
                    .padding(.horizontal, DesignSystem.Spacing.xl)
            }
            .padding(DesignSystem.Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.lg)
                    .fill(Color.white.opacity(0.7))
            )
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.md)
            
            // Song List
            ScrollView {
                LazyVStack(spacing: DesignSystem.Spacing.xs) {
                    ForEach(importService.importQueue) { song in
                        ImportSongRow(song: song)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
            
            // Action Button
            if !importService.isImporting {
                Button(action: {
                    dismiss()
                }) {
                    Text("Done")
                        .font(DesignSystem.Typography.title3)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DesignSystem.Spacing.md)
                        .background(DesignSystem.Colors.accent)
                        .cornerRadius(DesignSystem.CornerRadius.md)
                }
                .padding(.horizontal, DesignSystem.Spacing.lg)
                .padding(.bottom, DesignSystem.Spacing.lg)
            }
        }
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            Image(systemName: icon)
                .foregroundColor(DesignSystem.Colors.accent)
            Text(text)
                .font(DesignSystem.Typography.body)
        }
    }
}

// MARK: - Import Song Row

struct ImportSongRow: View {
    let song: ImportSong
    
    var body: some View {
        HStack(spacing: DesignSystem.Spacing.sm) {
            // Status Icon
            statusIcon
                .frame(width: 28, height: 28)
            
            // Song Info
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.xs) {
                Text(song.title)
                    .font(DesignSystem.Typography.bodyMedium)
                    .lineLimit(1)
                Text(song.artist)
                    .font(DesignSystem.Typography.caption)
                    .foregroundColor(DesignSystem.Colors.secondaryText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // Status/Progress
            statusView
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
        .frame(height: DesignSystem.Heights.songRow)
        .background(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.sm)
                .fill(backgroundColor)
        )
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch song.status {
        case .pending:
            Image(systemName: "circle")
                .foregroundColor(DesignSystem.Colors.secondaryText)
        case .matching:
            ProgressView()
                .scaleEffect(0.8)
        case .downloading, .converting:
            ProgressView(value: song.progress)
                .scaleEffect(0.8)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        }
    }
    
    @ViewBuilder
    private var statusView: some View {
        switch song.status {
        case .pending:
            Text("Pending")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.secondaryText)
        case .matching:
            Text("Matching...")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.accent)
        case .downloading:
            Text("\(Int(song.progress * 100))%")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.accent)
        case .converting:
            Text("Converting...")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(DesignSystem.Colors.accent)
        case .done:
            Text("Done")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(.green)
        case .failed:
            Text("Failed")
                .font(DesignSystem.Typography.caption)
                .foregroundColor(.red)
        }
    }
    
    private var backgroundColor: Color {
        switch song.status {
        case .done:
            return Color.green.opacity(0.1)
        case .failed:
            return Color.red.opacity(0.1)
        default:
            return Color.white.opacity(0.6)
        }
    }
}

// MARK: - Spotify OAuth Manager

import AuthenticationServices

final class SpotifyAuthManager: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?  // ✅ Strong reference
    
    func startLogin(
        authURL: URL,
        callbackScheme: String,
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        session = ASWebAuthenticationSession(
            url: authURL,
            callbackURLScheme: callbackScheme
        ) { [weak self] callbackURL, error in
            self?.session = nil  // Clear after completion
            
            if let error = error {
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin {
                    print("⚠️ User cancelled Spotify login")
                    completion(.failure(NSError(domain: "SpotifyAuth", code: -1, userInfo: [NSLocalizedDescriptionKey: "User cancelled"])))
                } else {
                    print("❌ Auth error: \(error.localizedDescription)")
                    completion(.failure(error))
                }
                return
            }
            
            guard let callbackURL = callbackURL else {
                print("❌ No callback URL received")
                completion(.failure(NSError(domain: "SpotifyAuth", code: -2, userInfo: [NSLocalizedDescriptionKey: "No callback URL"])))
                return
            }
            
            print("✅ Got callback URL: \(callbackURL.absoluteString)")
            completion(.success(callbackURL))
        }
        
        session?.presentationContextProvider = self
        session?.prefersEphemeralWebBrowserSession = false
        
        let started = session?.start() ?? false
        if !started {
            print("❌ ASWebAuthenticationSession failed to start")
            completion(.failure(NSError(domain: "SpotifyAuth", code: -3, userInfo: [NSLocalizedDescriptionKey: "Failed to start auth session"])))
        }
    }
    
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

// MARK: - Spotify OAuth View

struct SpotifyOAuthView: View {
    @ObservedObject var importService: SpotifyImportService
    @Environment(\.dismiss) var dismiss
    @State private var authManager = SpotifyAuthManager()  // ✅ Retained by @State
    @State private var showAuthError = false
    @State private var authErrorMessage = ""
    
    var body: some View {
        Color.clear
            .onAppear {
                startAuthentication()
            }
            .alert("Spotify Login Failed", isPresented: $showAuthError) {
                Button("OK", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(authErrorMessage)
            }
    }
    
    private func startAuthentication() {
        guard let authURL = importService.getSpotifyAuthURL() else {
            print("❌ Invalid Spotify auth URL")
            dismiss()
            return
        }
        
        authManager.startLogin(
            authURL: authURL,
            callbackScheme: "musicappswift"
        ) { result in
            switch result {
            case .success(let callbackURL):
                Task {
                    do {
                        try await importService.handleAuthCallback(url: callbackURL)
                        print("✅ Spotify OAuth successful")
                        await MainActor.run {
                            dismiss()
                        }
                    } catch {
                        print("❌ Failed to handle auth callback: \(error)")
                        await MainActor.run {
                            authErrorMessage = error.localizedDescription
                            showAuthError = true
                        }
                    }
                }
                
            case .failure(let error):
                authErrorMessage = error.localizedDescription
                showAuthError = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    dismiss()
                }
            }
        }
    }
}
