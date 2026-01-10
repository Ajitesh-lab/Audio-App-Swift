Full Working Update - Song download fixes and cleanup

Summary:
- Cleaned up server and client code related to YouTube audio downloads.
- Fixed failed downloads and restricted songs with multi-method fallbacks (yt-dlp/youtube-dl + RapidAPI re-fetch).
- Implemented re-fetch retry logic: fresh RapidAPI URL fetched up to 3 times when a CDN URL 404s.
- Stream-based URL validation added to avoid false HEAD checks.
- CDN authentication headers (User-Agent with username and X-RUN MD5) applied.
- Album cover downloads and association now work for downloaded tracks.
- Improved logging and header redaction to avoid leaking API keys.

Notes:
- Username used for CDN auth: (kept out of release notes for security). Rotate your RapidAPI key if it was exposed.
- Server entrypoint: server/server.js (runs on port 3001).

If anything still fails to download, test via the server logs on the machine running the server.
