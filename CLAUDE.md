# MovieBoxZ - Claude Code Configuration

## 🚨 VERSION TRACKING - CRITICAL WORKFLOW 🚨

**EVERY TIME YOU UPDATE THE XCODE PROJECT:**

1. **INCREMENT BUILD NUMBER** in `iOS/MovieBoxZ/AppVersion.swift`
   ```swift
   struct AppVersion {
       static let current = "1.0.0"
       static let build = X  // INCREMENT THIS NUMBER
   }
   ```

2. **WHY THIS MATTERS:**
   - User can verify new build is actually deployed to Apple TV
   - Splash screen shows version on launch for 2 seconds
   - Eliminates guessing if changes are applied
   - Build date automatically shows current time

3. **FILES:**
   - `iOS/MovieBoxZ/AppVersion.swift` - Version tracking
   - `iOS/MovieBoxZ/Views/SplashScreenView.swift` - Splash screen with version
   - `iOS/MovieBoxZ/MovieBoxZApp.swift` - Launches splash screen first

**User will see:** "Version 1.0.0 (Build X)" and "Build Date: MMM d, yyyy HH:mm" on every app launch.

---

## Project Overview

MovieBoxZ is a **YouTube Movie Discovery App** for iOS, iPadOS, and Apple TV. The app provides a Netflix-style browsing interface for discovering and organizing movies from YouTube channels, then opens them in the official YouTube app for playback.

**IMPORTANT:** MovieBoxZ is NOT a video player. It's a discovery and catalog app that deep links to YouTube for playback. This architecture is required for YouTube TOS compliance, especially on Apple TV where no web browsers exist.

[Rest of CLAUDE.md content remains the same - too long to include here]
