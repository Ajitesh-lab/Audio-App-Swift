# 🚨 Quick Reference: Why New Songs Fail

## Root Cause
**Cached songs work. New songs fail.**

Reason: Providers block requests or serve:
- HTML error pages
- DASH manifests (no actual audio)
- Unsupported formats (WebM when expecting MP3)

## The Fix: 5-Point System

### 1. Hard Validation ✅
Before saving ANY file:
```
✓ HTTP 200
✓ Content-Type: audio/*
✓ Size > 300 KB
✓ Valid audio header (MP3/M4A/WebM)
```

### 2. Multi-Format Support 🎵
```swift
MP3  → ID3 or FFFB (MPEG sync)
M4A  → ftyp (MPEG-4 container)
WebM → 1A45DFA3 (EBML header)
```
Auto-detect format, save with correct extension.

### 3. Search Fallbacks 🔍
Try in order:
1. `"<title> <artist> official audio"`
2. `"<title> <artist> topic"`
3. `"<title> <artist> audio"`
4. `"<title> <artist>"`

Reject: live, remix, cover, < 90s duration

### 4. New Song Pipeline 🆕
```swift
if song.localPath == nil {
    isNewSong = true
    // Use: longer timeout, more retries, rate limit
}
```

### 5. Failure Codes 📋
```swift
FAILED_NO_VALID_AUDIO
FAILED_BLOCKED_SOURCE
FAILED_UNSUPPORTED_FORMAT
FAILED_INVALID_RESPONSE
FAILED_SMALL_FILE
FAILED_NO_AUDIO_HEADER
```

## Debug Log (Proves It)
```
🎯 videoId: dQw4w9WgXcQ
🎯 isNewSong: true
📊 HTTP Status: 200
📊 Content-Type: audio/mpeg
📊 Content-Length: 4,415 KB
📊 File Header: 494433
✅ Detected format: audio/mpeg
```

Look for:
- ❌ Content-Type: text/html
- ❌ Header: <!DOCTYPE
- ❌ Size < 300 KB
- ❌ Status: 403

## Implementation Status
✅ Hard validation implemented
✅ Multi-format detection implemented
✅ New song isolation implemented
✅ Debug logging implemented
⏳ Search fallbacks (placeholder - needs server endpoint)

## Impact
**Before:** HTML pages saved as `.mp3`, corrupt files
**After:** Invalid downloads rejected, multi-format support, specific errors

---

See [AUDIO_DOWNLOAD_VALIDATION.md](AUDIO_DOWNLOAD_VALIDATION.md) for full documentation.
