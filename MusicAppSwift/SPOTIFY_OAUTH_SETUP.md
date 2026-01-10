# Spotify OAuth Setup Guide

## 🎯 Overview

The app now uses **proper Spotify OAuth login** instead of manual token pasting. Users click "Connect Spotify" and log in with their Spotify account directly!

## 📋 Setup Steps

### 1. Create Spotify App

1. Go to https://developer.spotify.com/dashboard
2. Log in with your Spotify account
3. Click "Create App"
4. Fill in:
   - **App Name**: MusicApp Swift
   - **App Description**: iOS music player with Spotify import
   - **Redirect URI**: `musicappswift://spotify-callback`
   - **Which API/SDKs are you planning to use**: Web API
5. Accept terms and click "Save"
6. Copy your **Client ID** and **Client Secret**

### 2. Configure Environment Variables

Add to your `.env` file in the `server/` directory:

```bash
SPOTIFY_CLIENT_ID=your_client_id_here
SPOTIFY_CLIENT_SECRET=your_client_secret_here
```

### 3. Update iOS App

In `SpotifyImportService.swift` line 52, replace:

```swift
private let clientId = "YOUR_SPOTIFY_CLIENT_ID"
```

With your actual Client ID:

```swift
private let clientId = "abc123xyz456..."
```

### 4. Test the Flow

1. Start your server:
   ```bash
   cd server
   npm start
   ```

2. Run the iOS app in simulator or device

3. Go to Library → + menu → "Import from Spotify"

4. Click "Connect Spotify"

5. Safari will open → Log in with Spotify → Authorize

6. App automatically returns and starts importing!

## 🔐 How It Works

1. **User taps "Connect Spotify"** → Opens Safari with Spotify login
2. **User authorizes** → Spotify redirects to `musicappswift://spotify-callback?code=...`
3. **App receives callback** → Extracts authorization code
4. **App calls server** → `POST /api/spotify/token` with code
5. **Server exchanges code for token** → Uses client_secret (secure!)
6. **Token returned to app** → Starts importing playlists

## 🔒 Security

- ✅ **Client Secret stays on server** - Never exposed to app
- ✅ **Short-lived auth codes** - Codes expire after 10 minutes
- ✅ **Standard OAuth 2.0** - Industry best practice
- ✅ **URL scheme protection** - Only your app can receive callbacks

## 📱 URL Scheme Configuration

Already configured in `Info.plist`:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>musicappswift</string>
        </array>
    </dict>
</array>
```

App delegate handles incoming URLs in `MusicAppSwiftApp.swift`.

## 🎉 User Experience

**Before** (Manual token):
1. Open Spotify dev docs
2. Get token manually
3. Copy/paste into app
4. Token expires in 1 hour

**After** (OAuth):
1. Tap "Connect Spotify"
2. Log in once
3. ✅ Done!

Much cleaner! 🚀
