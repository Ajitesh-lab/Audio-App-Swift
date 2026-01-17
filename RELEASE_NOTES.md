# Release Notes

## Latest Update - Login System & UI Polish

### New Features:
- **Complete Authentication System**
  - User registration with license key validation
  - Email/password login with JWT tokens
  - Device tracking (2 devices per account)
  - Forgot password functionality
  - Single-use license keys (4-digit format)

- **"Sotre" Branding**
  - Complete UI redesign with DocuFlex-inspired design
  - Purple color scheme throughout app
  - Clean, modern login and registration screens
  - Show/hide password toggles

- **Backend Infrastructure**
  - Node.js authentication server on Fly.io
  - SQLite database with persistent storage
  - Admin API for license key generation
  - Automatic deployment via GitHub Actions

- **UI Improvements**
  - Black text in all input fields
  - Improved error messages with specific feedback
  - Profile view redesign with black fonts
  - Clear cache now completely removes all data
  - Fixed slider glitch when switching songs

### Download System Enhancements:
- Smart alternative song selection with progressive tolerance (15s → 120s)
- Live concert filtering (only filters actual concerts, not songs with "live" in name)
- Better duration matching for failed downloads
- No unnecessary delays between retry attempts

### Developer Tools:
- `generate-key.js` - Simple script to create production license keys
- License system documentation
- Customer setup instructions

---

## Previous Update - Song Download Fixes

Summary:
- Cleaned up server and client code related to YouTube audio downloads.
- Fixed failed downloads and restricted songs with multi-method fallbacks (yt-dlp/youtube-dl + RapidAPI re-fetch).
- Implemented re-fetch retry logic: fresh RapidAPI URL fetched up to 3 times when a CDN URL 404s.
- Stream-based URL validation added to avoid false HEAD checks.
- CDN authentication headers (User-Agent with username and X-RUN MD5) applied.
- Album cover downloads and association now work for downloaded tracks.
- Improved logging and header redaction to avoid leaking API keys.

Notes:
- Server entrypoint: server.js (runs on port 3001).

If anything still fails to download, test via the server logs on the machine running the server.

