# Download Queue System

## Overview
The download queue system allows users to queue multiple songs for download and automatically retries failed downloads with alternative YouTube results that match the original song's duration.

## Features

### 1. Persistent Queue
- Downloads are queued and persist across app restarts
- Queue is automatically saved to `download_queue.json` in the documents directory
- Incomplete downloads resume automatically on app launch

### 2. Background Processing
- Queue processes downloads sequentially in the background
- Users can navigate away while downloads continue
- Search for more songs while downloads are in progress

### 3. Smart Retry with Alternatives
When a song fails to download:
- Automatically tries alternative songs from the same search results
- Matches alternatives by duration (within ±30 seconds)
- Tries up to 3 alternatives before marking as failed
- Prioritizes alternatives with closest duration match

### 4. Duration Matching Algorithm
```swift
// Example: Original song is 3:45 (225 seconds)
// System will try alternatives in order of closest duration:
// 1. 3:50 (230s) - 5 second difference ✓
// 2. 3:40 (220s) - 5 second difference ✓
// 3. 4:10 (250s) - 25 second difference ✓
// 4. 5:00 (300s) - 75 second difference ✗ (exceeds tolerance)
```

### 5. Visual Queue Management
- Queue icon with badge count in search toolbar
- Separate sections for:
  - Active downloads (queued/downloading/retrying)
  - Failed downloads (with retry option)
  - Completed downloads (with clear option)
- Real-time progress updates
- Retry attempt counter
- Individual item removal

## Usage

### Adding Songs to Queue
1. Search for a song on YouTube
2. Tap the download button (arrow icon)
3. Song is added to queue and downloads automatically
4. Button changes to "Queued" checkmark

### Viewing Queue
1. Tap the queue icon (tray) in the search toolbar
2. Badge shows count of pending/active downloads
3. View download progress and status

### Managing Failed Downloads
1. Failed downloads appear in "Failed Downloads" section
2. Shows failure reason
3. Tap "Retry All" to requeue all failed items
4. Or remove individual failed items with trash icon

## Implementation Details

### Key Components

#### DownloadQueueManager
- Singleton manager (`DownloadQueueManager.shared`)
- Manages queue state and persistence
- Processes downloads sequentially
- Handles retry logic and alternative selection

#### DownloadQueueItem
- Represents a queued download
- Stores:
  - YouTube video information
  - Download status and progress
  - Retry count
  - Alternative search results
  - Current alternative index

#### Download Status
- `queued` - Waiting to be processed
- `downloading` - Currently downloading
- `retrying` - Attempting alternative
- `completed` - Successfully downloaded
- `failed` - All attempts exhausted

### Configuration

```swift
// DownloadQueueManager settings
private let maxRetries = 3  // Max alternative attempts
private let durationMatchTolerance: Double = 30.0  // ±30 seconds
```

## User Flow

### Happy Path
```
User searches → Selects song → Downloads → Added to library
                    ↓
              Queued instantly
                    ↓
            Background processing
```

### Retry Path
```
Download fails → Find next best alternative (by duration)
      ↓                        ↓
   Retry 1              Duration: 3:45 → 3:50 (5s diff)
      ↓                        ↓
   Retry 2              Duration: 3:45 → 3:40 (5s diff)
      ↓                        ↓
   Retry 3              Duration: 3:45 → 4:10 (25s diff)
      ↓                        ↓
   Failed               No more suitable alternatives
```

## Technical Notes

### Queue Persistence
- Completed items are filtered out on load
- Failed items persist for manual retry
- Queue autosaves after every state change

### Concurrent Operations
- Only one download processes at a time
- New items trigger queue processing if idle
- Queue processor runs until all items complete

### Error Handling
- Network errors trigger retry
- Spotify match failures are terminal (no retry)
- Duration mismatch within tolerance still attempts download

## Benefits

1. **User Experience**
   - No need to wait for downloads
   - Browse while downloading
   - Automatic recovery from failures

2. **Reliability**
   - Intelligent retry with alternatives
   - Persistent queue survives app restarts
   - Duration matching ensures correct versions

3. **Efficiency**
   - Sequential processing prevents server overload
   - Automatic alternative selection
   - Smart duration-based matching

## Future Enhancements

Potential improvements:
- Parallel downloads (configurable max concurrent)
- Priority queue (reorder items)
- Download speed throttling
- Bandwidth usage statistics
- Manual alternative selection
- Batch operations (pause all, cancel all)
