# Debugging Spotify OAuth "Invalid" Error

## 🔍 Check These First:

### 1. Server Running?
```bash
cd server
node server.js
```

Should see:
```
🚀 YouTube Audio Server running on http://0.0.0.0:3001
```

### 2. Spotify Credentials Configured?

Check `server/.env`:
```bash
cat server/.env | grep SPOTIFY
```

Should show:
```
SPOTIFY_CLIENT_ID=abc123...
SPOTIFY_CLIENT_SECRET=xyz789...
```

If missing, add them:
```bash
# Get from: https://developer.spotify.com/dashboard
SPOTIFY_CLIENT_ID=your_actual_client_id
SPOTIFY_CLIENT_SECRET=your_actual_client_secret
```

### 3. Client ID in App Matches?

Check `MusicAppSwift/MusicAppSwift/SpotifyImportService.swift` line 52:
```swift
private let clientId = "YOUR_SPOTIFY_CLIENT_ID"  // ❌ WRONG
```

Should be:
```swift
private let clientId = "abc123..."  // ✅ Same as server .env
```

### 4. Redirect URI Configured in Spotify Dashboard?

Go to https://developer.spotify.com/dashboard → Your App → Settings

**Redirect URIs** should include:
```
musicappswift://spotify-callback
```

## 🐛 Debug Steps:

1. **Start server with logging:**
```bash
cd server
node server.js
```

2. **Try login** - Watch server console for:
```
POST /api/spotify/token
```

3. **Check error message:**
   - If "Spotify credentials not configured" → Fix .env
   - If "invalid_client" → Client ID/Secret mismatch
   - If "invalid_grant" → Code expired or redirect_uri mismatch
   - If "redirect_uri_mismatch" → Add redirect URI to Spotify dashboard

## 📱 App Now Shows Actual Error!

The app will now display the actual error message in an alert, making debugging much easier!

Example errors you might see:
- "Spotify credentials not configured" → Add to .env
- "Token exchange failed: invalid_client" → Wrong client ID/secret
- "Token exchange failed: invalid_grant" → Redirect URI not matching

## ✅ Quick Fix Checklist:

- [ ] Server running on port 3001
- [ ] `SPOTIFY_CLIENT_ID` in server/.env
- [ ] `SPOTIFY_CLIENT_SECRET` in server/.env  
- [ ] Same Client ID in SpotifyImportService.swift line 52
- [ ] Redirect URI `musicappswift://spotify-callback` in Spotify dashboard
- [ ] Restart server after changing .env
