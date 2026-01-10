# Testing Minimal Lock Screen Player

## What I Created

I've added a **minimal, isolated player** to test lock screen functionality independently from your main `MusicPlayer` class:

### New Files:
1. **`PlayerManager.swift`** - Minimal player with ONLY lock screen essentials
2. **`TestPlayerView.swift`** - Simple UI to test the player

## How to Test

### Option 1: Add to existing ContentView (Quickest)

Open `ContentView.swift` and add this at the top of the view hierarchy:

```swift
struct ContentView: View {
    @StateObject var musicPlayer = MusicPlayer.shared
    
    var body: some View {
        NavigationStack {
            // Add this button at the top
            NavigationLink("🧪 Test Lock Screen") {
                TestPlayerView()
            }
            .buttonStyle(.borderedProminent)
            .padding()
            
            // ... your existing content
        }
    }
}
```

### Option 2: Temporarily replace ContentView

Comment out your existing ContentView body and replace with:

```swift
var body: some View {
    TestPlayerView()
}
```

## Testing Steps

1. **Build & Run** on your real device
2. Tap **"Play Test Track"**
3. Console should show:
   ```
   🎧 Audio session configured
   🎮 Remote commands set up
   🎵 Found downloaded song: [name]
   📱 Now Playing info: [data]
   ```
4. **Lock your device**
5. **Check lock screen:**
   - Should show album artwork (gradient with music note)
   - Should show: "Test Song" by "Test Artist"
   - Should have play/pause controls
   - Should update progress bar every second

## What This Tests

✅ **Audio Session** - Simplified `.playback` setup  
✅ **Remote Commands** - Only play/pause (minimal)  
✅ **Now Playing Info** - All required fields  
✅ **Elapsed Time Updates** - Every 1 second  
✅ **Artwork** - Generated gradient (always valid size)

## Why This Works

This `PlayerManager` is **exactly** what Apple's documentation shows:
- Audio session BEFORE player creation ✅
- Remote command handlers (not just enabled) ✅
- Now Playing info with all fields ✅
- Periodic time updates ✅
- Non-zero artwork ✅

## Expected Behavior

If lock screen **still doesn't work** with this minimal player, then:
1. Your device has iOS restrictions enabled
2. Your provisioning profile is missing entitlements
3. iOS bug (restart device)

If lock screen **DOES work** with this but not your main player, then:
1. Compare `PlayerManager.swift` vs `MusicPlayer.swift`
2. Look for timing differences
3. Check if main player has conflicting setup

## Reverting

To go back to your normal app:
1. Remove the test button from ContentView
2. Or just ignore the new files (they don't interfere)

---

**Note:** The TestPlayerView will try to find your downloaded songs first, otherwise it uses a remote URL for testing. Both should work for lock screen display.
