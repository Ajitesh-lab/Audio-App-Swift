# 🎯 Audio Download Validation System

## Overview
Comprehensive audio download validation system that prevents corrupted downloads, supports multiple audio formats, and isolates new song downloads with stricter validation.

## 🚨 Problem Statement
**Old songs work because they're cached. New songs fail because:**
- Providers block or serve unsupported audio formats
- HTML responses are saved as audio files
- DASH-only streams without actual audio data
- No validation of download responses

## ✅ Solution: 5-Point Validation System

### 1️⃣ HARD VALIDATE DOWNLOAD RESPONSE (MANDATORY)

Before saving ANY audio file, the system validates:

#### HTTP Status Check
```swift
✅ Must be 200
❌ Reject: 403, 404, 500, etc.
```

#### Content-Type Validation
```swift
✅ Must start with "audio/"
✅ Accept: audio/mpeg, audio/mp4, audio/webm
❌ Reject: text/html, application/json
```

#### Content Length Check
```swift
✅ Must be > 300 KB (300,000 bytes)
❌ Reject: Small files are likely error pages
```

#### Audio Header Validation
```swift
✅ MP3: ID3 (49 44 33) or MPEG sync (FF FB/FF F3)
✅ M4A: ftyp (66 74 79 70)
✅ WebM: EBML header (1A 45 DF A3)
❌ Reject: Unknown/invalid file signatures
```

**If ANY validation fails:**
- ❌ DO NOT SAVE the file
- 🔄 Retry with different source
- 📝 Log specific failure reason

---

### 2️⃣ SUPPORT MULTIPLE AUDIO CONTAINERS

The system automatically detects and handles:

#### Supported Formats
| Format | MIME Type | File Header | Extension |
|--------|-----------|-------------|-----------|
| MP3 | audio/mpeg | `ID3` or `FFFB` | .mp3 |
| M4A/MP4 | audio/mp4 | `ftyp` | .m4a |
| WebM | audio/webm | `1A45DFA3` | .webm |
| Opus | audio/opus | `1A45DFA3` | .opus |

#### Container Detection
```swift
enum AudioContainer {
    case mp3    // ID3 or MPEG frame sync
    case m4a    // MPEG-4 container (ftyp)
    case webm   // WebM/Matroska (EBML)
    case opus   // Opus codec
    
    static func detect(from data: Data) -> AudioContainer?
}
```

#### Automatic Extension Correction
- Downloaded file analyzed for actual format
- Saved with correct extension (`.mp3`, `.m4a`, `.webm`)
- **Never blindly rename** without format detection

---

### 3️⃣ SEARCH FALLBACKS FOR NEW SONGS

When downloading new songs, the system tries multiple search strategies:

#### Search Query Priority
```swift
1. "<title> <artist> official audio"    // Prefer official releases
2. "<title> <artist> topic"             // Topic channels (high quality)
3. "<title> <artist> audio"             // Generic audio results
4. "<title> <artist>"                   // Fallback search
```

#### Result Filtering
**❌ Reject results with:**
- Duration < 90 seconds (likely incomplete/preview)
- "live" in title (concert recordings)
- "remix" in title (modified versions)
- "cover" in title (non-original versions)
- "teaser" in title (short previews)

**✅ Accept results with:**
- Duration within ±3 seconds of Spotify duration
- Clean artist/title match
- "Official Audio" or "Topic" in source

---

### 4️⃣ ISOLATED "NEW SONG" PIPELINE

New songs (without cached audio) use a separate, stricter download path:

#### New Song Detection
```swift
if song.localPath == nil {
    // This is a NEW song - use stricter validation
    isNewSong = true
}
```

#### Stricter Rules for New Songs
| Parameter | Cached Songs | New Songs |
|-----------|--------------|-----------|
| Timeout | 30s | 60s |
| Retry Count | 2 | 3 |
| Rate Limit | None | 2s delay |
| Validation | Basic | Full 4-point |
| Fallback Search | No | Yes |

#### Benefits
- **Cached songs**: Fast playback, minimal checks
- **New songs**: Thorough validation, multiple retries
- **No cross-contamination**: Issues with new downloads don't affect existing library

---

### 5️⃣ SPECIFIC FAILURE CODES

Instead of generic "download failed", the system logs precise failure reasons:

#### Failure Code Enum
```swift
enum DownloadFailureCode: String {
    case failedNoValidAudio          // No audio data received
    case failedBlockedSource         // Provider blocked request
    case failedUnsupportedFormat     // Format not recognized
    case failedInvalidResponse       // Non-200 HTTP status
    case failedSmallFile             // Content-Length < 300 KB
    case failedNoAudioHeader         // Invalid file header
    case failedShortDuration         // Duration < 90s
    case failedLiveContent           // Live/remix/cover detected
    case success                     // Download successful
}
```

#### Why This Matters
- **Retry logic**: Different failures need different solutions
- **Debugging**: Pinpoint exact issue in logs
- **User feedback**: Show meaningful error messages
- **Source rotation**: Mark bad sources, try alternatives

---

## 🧪 Debug Log Output

For every download attempt, the system logs:

```
🎯 ============================================
🎯 DOWNLOAD DEBUG LOG (videoId: dQw4w9WgXcQ)
🎯 isNewSong: true
🎯 ============================================

📤 Requesting download from server...
📦 Server response status: 200
✅ Got audio URL: http://192.168.1.133:3001/downloads/audio.mp3
⬇️ Downloading audio file...

📊 HTTP Status: 200
📊 Content-Type: audio/mpeg
📊 Content-Length: 4,521,342 bytes (4,415 KB)
📊 File Header (hex): 494433040000000023C4

✅ VALIDATION PASSED: Detected format: audio/mpeg
✅ Audio saved to: /path/to/dQw4w9WgXcQ.mp3

🎯 ============================================
```

### What To Look For
- ❌ **HTML received**: Content-Type is `text/html`, header shows `<!DOCTYPE`
- ❌ **Blocked source**: HTTP status 403, Content-Length is small
- ❌ **DASH stream**: No audio header, unsupported format
- ❌ **Wrong container**: Expected MP3, got WebM

---

## 🔧 Implementation Details

### Key Files Modified
- **MusicDownloadManager.swift**
  - Added `DownloadFailureCode` enum
  - Added `AudioContainer` detection
  - Enhanced `downloadYouTubeAudio()` with 4-point validation
  - Added `searchYouTubeWithFallbacks()` (placeholder)
  - Modified `downloadAudio()` with `isNewSong` flag
  - Updated fallback path to mark as new song

### Integration Points
```swift
// When downloading new song
let audioPath = try await downloadAudio(
    videoId: youtubeVideoId,
    quality: "medium",
    isNewSong: true  // ← Triggers stricter validation
)

// Validation happens automatically in downloadYouTubeAudio()
// - Checks HTTP status
// - Validates content-type
// - Verifies file size
// - Detects audio format
// - Saves with correct extension
```

---

## 📊 Expected Impact

### Before (Old System)
- ❌ Downloads succeed but files are corrupt
- ❌ HTML pages saved as `.mp3` files
- ❌ No distinction between new vs. cached songs
- ❌ Generic "download failed" errors

### After (New System)
- ✅ Invalid downloads rejected immediately
- ✅ Multiple audio formats supported
- ✅ New songs use stricter validation
- ✅ Specific failure codes for debugging
- ✅ Automatic format detection and extension correction

---

## 🚀 Next Steps

### Server-Side Enhancements (TODO)
1. **YouTube Search API**
   - Implement `/api/youtube-search` endpoint
   - Accept search query, return filtered results
   - Apply duration/content filtering

2. **Format Transcoding**
   - Add `/api/transcode` endpoint
   - Convert WebM → MP3 if needed
   - Remux M4A → MP3 for consistency

3. **Source Rotation**
   - Track failed video IDs
   - Rotate to alternative sources
   - Maintain blocklist of bad sources

### Client-Side Enhancements
1. **Search Fallbacks** (currently placeholder)
   - Wire up `searchYouTubeWithFallbacks()` to server
   - Implement result filtering
   - Add retry logic with different queries

2. **User Feedback**
   - Show specific error messages
   - "Blocked by provider" vs. "Invalid format"
   - Suggest manual search if all fallbacks fail

3. **Cache Management**
   - Store `DownloadFailureCode` with song metadata
   - Retry failed downloads after provider updates
   - Auto-retry `failedBlockedSource` after 24 hours

---

## 🎓 Technical Reference

### Audio File Signatures
```
MP3 (ID3v2): 49 44 33 [version] [flags] [size]
MP3 (MPEG):  FF FB 90 [bitrate info]
M4A (MP4):   [size] 66 74 79 70 [brand]
WebM:        1A 45 DF A3 [header size]
```

### Content-Type Headers
```
audio/mpeg           → MP3
audio/mp4            → M4A/AAC
audio/webm           → WebM/Opus/Vorbis
audio/ogg            → Ogg Vorbis
text/html            → ERROR: HTML page
application/json     → ERROR: JSON response
```

### Common Failure Patterns
| Symptom | Cause | Solution |
|---------|-------|----------|
| File < 100 KB | HTML error page | Check content-type |
| Wrong header | Format mismatch | Use container detection |
| 403 status | Region/IP blocked | Rotate source |
| No audio data | DASH manifest only | Request audio stream |

---

## 📝 One-Line Summary

**New songs fail because providers block or serve unsupported audio formats. Old songs work because they're cached. Fix requires strict response validation, multi-format support, search fallbacks, and a slower "new song" download path.**
