# ✅ Implementation Checklist: Audio Download Validation

## Status: Phase 1 Complete ✅

### Completed Items

#### 1️⃣ Hard Validation System ✅
- [x] HTTP status validation (must be 200)
- [x] Content-Type validation (must start with `audio/`)
- [x] Content-Length validation (must be > 300 KB)
- [x] Audio header validation (MP3/M4A/WebM signatures)
- [x] Reject and throw error if ANY validation fails
- [x] Comprehensive debug logging for each check

#### 2️⃣ Multi-Format Support ✅
- [x] Created `AudioContainer` enum (MP3, M4A, WebM, Opus)
- [x] Implemented `detect(from:)` method with header analysis
- [x] Auto-detect format from first 12 bytes
- [x] Save with correct file extension
- [x] Support MP3 (ID3/FFFB), M4A (ftyp), WebM (1A45DFA3)

#### 3️⃣ Failure Code System ✅
- [x] Created `DownloadFailureCode` enum
- [x] Defined 8 specific failure types
- [x] Log failure codes for debugging
- [x] Enables retry logic based on failure type

#### 4️⃣ New Song Pipeline ✅
- [x] Added `isNewSong` parameter to download functions
- [x] Longer timeouts for new songs (60s vs 30s)
- [x] Rate limiting (2s delay) for new songs
- [x] Separate validation path
- [x] Updated fallback path to mark as `isNewSong: true`

#### 5️⃣ Debug Logging ✅
- [x] Structured log output with borders
- [x] Log videoId, isNewSong status
- [x] Log HTTP status, Content-Type, Content-Length
- [x] Log file header in hex format
- [x] Log detected format
- [x] Clear pass/fail indicators (✅/❌)

#### 6️⃣ Documentation ✅
- [x] Created AUDIO_DOWNLOAD_VALIDATION.md (full guide)
- [x] Created DOWNLOAD_FIX_SUMMARY.md (quick reference)
- [x] Created this implementation checklist
- [x] Documented all validation steps
- [x] Included troubleshooting guide

---

## Phase 2: Server Enhancements (TODO)

### 3️⃣ Search Fallbacks (Placeholder)
- [ ] Implement `/api/youtube-search` server endpoint
- [ ] Accept search query, return filtered results
- [ ] Filter by duration (reject < 90s)
- [ ] Filter out: live, remix, cover, teaser
- [ ] Return best matching videoId
- [ ] Wire up `searchYouTubeWithFallbacks()` to endpoint
- [ ] Add retry logic with different queries

### Format Transcoding (Optional)
- [ ] Add `/api/transcode` endpoint
- [ ] Convert WebM → MP3 using FFmpeg
- [ ] Remux M4A → MP3 for consistency
- [ ] Cache transcoded files

### Source Rotation (Optional)
- [ ] Track failed video IDs in database
- [ ] Rotate to alternative sources
- [ ] Maintain blocklist of bad sources
- [ ] Auto-retry after 24 hours

---

## Phase 3: UX Enhancements (TODO)

### User Feedback
- [ ] Show specific error messages in UI
- [ ] "Blocked by provider" alert
- [ ] "Invalid format" with format name
- [ ] Suggest manual search if all fallbacks fail
- [ ] "Retrying with different search..." progress text

### Cache Management
- [ ] Store `DownloadFailureCode` with song metadata
- [ ] Retry failed downloads in background
- [ ] Auto-retry `failedBlockedSource` after 24 hours
- [ ] Show "Last failed: [reason]" in song info

### Analytics
- [ ] Track failure rates by code
- [ ] Identify problematic video IDs
- [ ] Monitor validation success rate
- [ ] Alert when success rate drops

---

## Testing Plan

### Test Cases

#### ✅ Valid Audio (Should Pass)
- [x] MP3 file with ID3 tags
- [x] M4A file with ftyp header
- [ ] WebM file with EBML header
- [ ] Large file (> 5 MB)

#### ❌ Invalid Audio (Should Fail)
- [ ] HTML error page (Content-Type: text/html)
- [ ] JSON response (Content-Type: application/json)
- [ ] Small file (< 100 KB)
- [ ] File with wrong header
- [ ] 403 Forbidden response
- [ ] DASH manifest (no actual audio)

#### 🔄 Retry Logic
- [ ] First attempt fails → second succeeds
- [ ] All attempts fail → show error
- [ ] Different failure codes → different retry behavior

### Test Environment
```bash
# Test server endpoint
curl -X POST http://192.168.1.133:3001/api/download-audio \
  -H "Content-Type: application/json" \
  -d '{"videoId": "dQw4w9WgXcQ"}'

# Expected response:
{
  "success": true,
  "audioUrl": "http://192.168.1.133:3001/downloads/dQw4w9WgXcQ.mp3"
}

# Download and inspect
curl -I "http://192.168.1.133:3001/downloads/dQw4w9WgXcQ.mp3"
# Should show:
# Content-Type: audio/mpeg
# Content-Length: > 300000

# Check file header
curl "http://192.168.1.133:3001/downloads/dQw4w9WgXcQ.mp3" | xxd | head -n 1
# Should show: 49 44 33 (ID3) or FF FB (MPEG sync)
```

---

## Rollout Plan

### Phase 1: Internal Testing ✅ (Current)
- [x] Implement validation system
- [x] Test with known-good audio files
- [x] Verify build succeeds
- [x] Check debug logs

### Phase 2: Limited Rollout
- [ ] Enable for 10% of downloads
- [ ] Monitor failure rates
- [ ] Collect logs from real usage
- [ ] Identify edge cases

### Phase 3: Full Rollout
- [ ] Enable for all downloads
- [ ] Monitor success/failure metrics
- [ ] Add server-side search fallbacks
- [ ] Implement transcoding if needed

---

## Success Metrics

### Before (Baseline)
- ❌ Unknown failure rate
- ❌ Generic "download failed" errors
- ❌ Corrupt files saved
- ❌ No format validation

### After (Target)
- ✅ < 5% download failure rate
- ✅ Specific error codes logged
- ✅ 0% corrupt files saved
- ✅ Multi-format support (MP3, M4A, WebM)
- ✅ 95%+ validation accuracy

### Key Performance Indicators
1. **Download Success Rate**: % of downloads that pass validation
2. **Format Distribution**: % MP3 vs M4A vs WebM
3. **Failure Code Distribution**: Which failures are most common
4. **Retry Success Rate**: % of retries that succeed
5. **Average Download Time**: New songs vs cached songs

---

## Known Limitations

### Current Implementation
- ⚠️ Search fallbacks are placeholder (needs server endpoint)
- ⚠️ No transcoding (WebM stays WebM)
- ⚠️ No source rotation
- ⚠️ Single retry attempt per download

### Future Improvements
- Add YouTube search API integration
- Implement FFmpeg transcoding pipeline
- Build source quality database
- Add multiple retry strategies

---

## Maintenance Notes

### Regular Checks
- Monitor failure code distribution weekly
- Update audio header signatures if new formats emerge
- Adjust validation thresholds based on real data
- Review timeout values (30s/60s) if needed

### Known Issues
- Some providers may rotate IPs → need retry logic
- Regional blocks → need VPN/proxy rotation
- Format changes → update header detection

### Emergency Rollback
If validation causes too many false negatives:
```swift
// Temporarily disable strict validation
let isAudioType = true // Skip content-type check
let minSize = 0        // Skip size check
// Keep logging to identify issue
```

---

## Contact & Support

### Documentation
- Full guide: [AUDIO_DOWNLOAD_VALIDATION.md](AUDIO_DOWNLOAD_VALIDATION.md)
- Quick reference: [DOWNLOAD_FIX_SUMMARY.md](DOWNLOAD_FIX_SUMMARY.md)
- This checklist: IMPLEMENTATION_CHECKLIST.md

### Key Files
- Implementation: `MusicAppSwift/Services/MusicDownloadManager.swift`
- Server endpoint: `server/server.js` (download-audio route)

### Debug Commands
```bash
# Build and check for errors
xcodebuild -scheme MusicAppSwift -sdk iphonesimulator build

# Watch server logs
docker logs music-server --follow

# Test download endpoint
curl -X POST http://192.168.1.133:3001/api/download-audio \
  -H "Content-Type: application/json" \
  -d '{"videoId": "TEST_ID"}'
```

---

**Status: Phase 1 Complete ✅**
**Next: Test with real downloads, implement search fallbacks**
