# MovieBoxZ - Claude Code Configuration

## 🎨 Custom Expert Agents

This project includes specialized expert agents for specific domains:

### Streaming UX Expert (`.claude/agents/streaming-ux-expert.md`)
Expert in iOS/tvOS streaming app UX design. Specializes in:
- Netflix-style content discovery patterns
- Platform-specific design (iOS touch vs tvOS focus)
- Apple Human Interface Guidelines compliance
- Accessibility best practices
- Video player UX patterns
- Content hierarchy and visual design
- Performance and loading states

**Usage**: Ask Claude to consult the streaming UX expert for design feedback, layout improvements, or user experience analysis.

**Example prompts**:
- "Use the streaming UX expert to review our browse screen"
- "Ask the UX expert how to improve our movie card layout"
- "Get UX recommendations for the detail screen from the streaming expert"

### iOS/tvOS Expert (`.claude/agents/ios-tvos-expert.md`)
Expert in iOS and tvOS development using command-line tools and Swift.

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

### Key Features
- 🎬 **Movie Discovery**: Browse movies organized by genre, popularity, and release date
- 📺 **Channel Integration**: Curate content from YouTube movie channels
- 🔍 **Smart Search**: Find movies across multiple YouTube channels
- 📱 **Multi-Platform**: Native support for iPhone, iPad, and Apple TV
- 🎨 **Netflix-Style UI**: Familiar and intuitive browsing interface
- ▶️ **YouTube Playback**: Opens videos in official YouTube app (TOS-compliant)

### Technical Stack
- **SwiftUI**: Modern declarative UI framework
- **iOS 17.0+**: iPhone and iPad support
- **tvOS 17.0+**: Apple TV support
- **YouTube Data API v3**: For fetching channel and video metadata ONLY
- **Deep Linking**: Opens videos in YouTube app (no custom player)
- **Backend**: Node.js/Express (in development)
- **Deployment**: Railway.app

### Architecture: Discovery + Deep Linking

```
┌─────────────────────────────────┐
│      MovieBoxZ App              │
│  (Netflix-style browsing UI)    │
│                                 │
│  YouTube Data API v3            │
│  └─> Fetch metadata only        │
│      (no video URLs)            │
│                                 │
│  User clicks "Watch"            │
│  └─> Deep link to YouTube app  │
└─────────────────────────────────┘
              │
              ▼
   ┌──────────────────────┐
   │   YouTube App        │
   │  (Handles playback)  │
   └──────────────────────┘
```

## Railway MCP Server Integration

This project uses the Railway MCP (Model Context Protocol) server to manage infrastructure and deployments directly from Claude Code.

### Configuration

The Railway MCP server is configured in `~/.claude.json` for this project:

```json
{
  "mcpServers": {
    "railway": {
      "type": "stdio",
      "command": "node",
      "args": [
        "/Users/mrahl/movieboxz/railway-mcp/build/index.js"
      ],
      "env": {
        "RAILWAY_API_TOKEN": "66d6110f-e127-4414-b1be-21437050ab5c"
      }
    }
  }
}
```

### Available Railway MCP Tools

Once configured, you can use these Railway commands through Claude Code:

#### Project Management
- `project-list` - List all Railway projects
- `project-info` - Get detailed project information
- `project-create` - Create a new project
- `project-delete` - Delete a project
- `project-environments` - List project environments

#### Service Management
- `service-list` - List all services in a project
- `service-info` - Get detailed service information
- `service-create-from-repo` - Create service from GitHub repository
- `service-create-from-image` - Create service from Docker image
- `service-delete` - Delete a service
- `service-restart` - Restart a service
- `service-update` - Update service configuration

#### Deployment Management
- `deployment-list` - List recent deployments
- `deployment-trigger` - Trigger a new deployment
- `deployment-logs` - Get deployment logs
- `deployment-health-check` - Check deployment health

#### Variable Management
- `variable-list` - List environment variables
- `variable-set` - Create or update a variable
- `variable-delete` - Delete a variable
- `variable-bulk-set` - Bulk update variables
- `variable-copy` - Copy variables between environments

#### Database Management
- `database-list-types` - List available database types
- `database-deploy` - Deploy a new database service

### Usage Examples

Ask Claude Code to help with Railway operations:

- "Show me my Railway projects"
- "List services in my MovieBoxZ project"
- "Deploy the backend service"
- "Show me the logs for my latest deployment"
- "What's the status of my deployments?"
- "Set environment variable YOUTUBE_API_KEY for production"
- "Create a new Postgres database"

### Railway MCP Server Location

The Railway MCP server is installed locally at:
```
/Users/mrahl/movieboxz/railway-mcp/
```

## Supabase MCP Server Integration

This project also uses the Supabase MCP (Model Context Protocol) server to manage Supabase databases and services directly from Claude Code.

### Configuration

The Supabase MCP server is configured in `~/.claude.json` for this project:

```json
{
  "mcpServers": {
    "supabase": {
      "type": "stdio",
      "command": "node",
      "args": [
        "/Users/mrahl/movieboxz/supabase-mcp/packages/mcp-server-supabase/dist/transports/stdio.js"
      ],
      "env": {}
    }
  }
}
```

### Available Supabase MCP Tools

Once configured, you can use these Supabase commands through Claude Code:

#### Account Management
- `list_projects` - List all Supabase projects
- `get_project` - Get project details
- `create_project` - Create new Supabase project
- `list_organizations` - List organizations

#### Database Operations
- `list_tables` - List database tables
- `list_extensions` - List database extensions
- `execute_sql` - Execute SQL queries
- `apply_migration` - Apply database migrations

#### Development Tools
- `get_project_url` - Get API URLs
- `get_publishable_keys` - Get API keys
- `generate_typescript_types` - Generate TypeScript types from schema

#### Edge Functions
- `list_edge_functions` - List Edge Functions
- `get_edge_function` - Get function code
- `deploy_edge_function` - Deploy Edge Functions

#### Debugging & Monitoring
- `get_logs` - Get service logs (api, postgres, functions, auth, storage)
- `get_advisors` - Get security and performance advisories

#### Storage
- `list_storage_buckets` - List storage buckets
- `get_storage_config` - Get storage configuration
- `update_storage_config` - Update storage settings

#### Knowledge Base
- `search_docs` - Search Supabase documentation

### Usage Examples

Ask Claude Code to help with Supabase operations:

- "Show me my Supabase projects"
- "List tables in my Supabase database"
- "Execute this SQL query on Supabase"
- "Generate TypeScript types from my Supabase schema"
- "Deploy this Edge Function to Supabase"
- "Show me the Postgres logs"
- "Search Supabase docs for authentication"

### Supabase MCP Server Location

The Supabase MCP server is installed locally at:
```
/Users/mrahl/movieboxz/supabase-mcp/
```

**Note**: For full setup details and advanced configuration options, see `SUPABASE_MCP_SETUP.md`.

## YouTube API Compliance

**CRITICAL**: This application must maintain strict compliance with YouTube's Terms of Service.

### Why YouTube Protects Video URLs

YouTube actively protects video streams through:
- **Dynamic URLs**: Generated per-request, expire in 5-6 hours
- **Signed Tokens**: Cryptographically validate request origin
- **Frequent Changes**: URL structure changes to prevent scraping
- **Movie Protection**: Enhanced DRM for full-length content

**Result**: You CANNOT extract video URLs for custom players. It's technically impossible and legally prohibited.

### TOS-Compliant Architecture

#### ✅ ALLOWED
1. **YouTube Data API v3**: Fetch video metadata (title, thumbnail, description, channel)
2. **Deep Linking**: Open videos in YouTube app via `youtube://` URL scheme
3. **IFrame Embed** (iOS only): Use YouTube's official IFrame player with full branding
4. **YouTube Attribution**: Display channel name and "Watch on YouTube" messaging

#### ❌ PROHIBITED
1. **URL Extraction**: Using youtube-dl, yt-dlp, or similar tools
2. **Custom Players**: Playing YouTube content in AVPlayer or custom video players
3. **Content Caching**: Downloading or saving video streams locally
4. **Ad Blocking**: Circumventing or removing advertisements
5. **Misrepresentation**: Hiding that content comes from YouTube

### Platform-Specific Implementation

#### iOS (iPhone & iPad)
```swift
// Option 1: Deep linking (recommended)
YouTubePlayerService.shared.playVideo(videoID: movie.youtubeVideoId)

// Option 2: IFrame embed (acceptable with attribution)
YouTubeWebView(videoID: movie.youtubeVideoId)
```

#### tvOS (Apple TV)
```swift
// ONLY option: Deep linking (WKWebView not available on tvOS)
YouTubePlayerService.shared.playVideo(videoID: movie.youtubeVideoId)
```

**tvOS Reality**: Apple TV has NO web browser and NO WKWebView. Deep linking to the YouTube tvOS app is the ONLY legal way to play videos.

### Required Implementations
- **Info.plist**: Add `youtube` to `LSApplicationQueriesSchemes`
- **YouTube Attribution**: Display channel name on every movie card
- **Deep Linking**: Use `YouTubePlayerService` for all playback
- **First-Launch Check**: Verify YouTube app is installed
- **Clear Messaging**: App Store description states YouTube dependency

### Prohibited Actions
- ❌ No video URL extraction or parsing
- ❌ No custom AVPlayer implementation for YouTube
- ❌ No web scraping or reverse engineering
- ❌ No third-party YouTube player libraries
- ❌ No local video caching or downloading
- ❌ No ad circumvention or blocking
- ❌ No background audio (YouTube Premium feature)

**See `YOUTUBE_COMPLIANCE.md` for complete technical details.**

## Project Structure

```
movieboxz/
├── iOS/MovieBoxZ/
│   ├── Models/
│   │   └── Movie.swift                    # Movie data model (includes youtubeVideoId)
│   ├── Services/
│   │   ├── MovieService.swift             # Backend API client
│   │   └── YouTubePlayerService.swift     # Deep linking service (NEW)
│   ├── Views/
│   │   ├── VideoPlayerComponents.swift    # TOS-compliant player (UPDATED)
│   │   ├── MainBrowseView.swift           # Netflix-style browsing
│   │   ├── SearchView.swift               # Search interface
│   │   └── LibraryView.swift              # User's watchlist
│   └── MovieBoxZApp.swift                 # App entry point
├── backend/                               # Node.js/Express backend
│   ├── src/
│   │   ├── routes/movies.js               # Movie API endpoints
│   │   └── services/youtube.js            # YouTube Data API proxy
│   └── server.js
├── railway-mcp/                           # Railway MCP server
├── supabase-mcp/                          # Supabase MCP server
├── MovieBoxZ.xcodeproj/                   # Xcode project
├── YOUTUBE_COMPLIANCE.md                  # YouTube TOS compliance guide (NEW)
├── API_SETUP_GUIDE.md                     # API configuration guide
├── DEPLOYMENT_CHECKLIST.md                # Deployment steps
├── PROJECT_STATUS.md                      # Current project status
├── SETUP_INSTRUCTIONS.md                  # Setup guide
└── SUPABASE_MCP_SETUP.md                  # Supabase MCP configuration
```

### Key Files

#### YouTubePlayerService.swift
TOS-compliant service for opening videos in YouTube app. Handles:
- Deep linking to YouTube app (`youtube://` URL scheme)
- Fallback to web URL if app not installed
- YouTube app detection
- Channel navigation

#### VideoPlayerComponents.swift
Platform-specific video player implementation:
- **iOS**: Option to use IFrame embed OR deep linking
- **tvOS**: Deep linking only (no WKWebView available)
- Includes required YouTube attribution
- TOS-compliant implementation

#### Movie.swift
Data model with YouTube integration:
- `youtubeVideoId`: Video identifier
- `channelId`, `channelTitle`: YouTube channel info
- `youtubeURL`, `youtubeAppURL`: Computed properties for deep linking
- No video stream URLs (TOS-compliant)

## YouTube Integration Implementation

### Step 1: Configure Info.plist

Add YouTube URL scheme to `Info.plist`:

```xml
<key>LSApplicationQueriesSchemes</key>
<array>
    <string>youtube</string>
</array>
```

### Step 2: Use YouTubePlayerService

```swift
import SwiftUI

struct MovieDetailView: View {
    let movie: Movie

    var body: some View {
        VStack {
            // Movie poster, title, description...

            // YouTube attribution (REQUIRED)
            HStack {
                Image(systemName: "play.rectangle.fill")
                    .foregroundColor(.red)
                Text("Hosted on \(movie.channelTitle)")
            }

            // Play button
            Button("Watch on YouTube") {
                YouTubePlayerService.shared.playMovie(movie) { success in
                    if !success {
                        // Handle error: YouTube app not installed
                        print("YouTube app required")
                    }
                }
            }
        }
    }
}
```

### Step 3: Check YouTube App on First Launch

```swift
.onAppear {
    if !YouTubePlayerService.shared.isYouTubeAppInstalled() {
        showYouTubeInstallPrompt = true
    }
}
.alert("YouTube App Required", isPresented: $showYouTubeInstallPrompt) {
    #if os(iOS)
    Button("Install") {
        YouTubePlayerService.shared.promptInstallYouTubeApp()
    }
    #else
    Button("OK", role: .cancel) { }
    #endif
} message: {
    Text("MovieBoxZ requires the YouTube app to play videos.")
}
```

### Step 4: Display Attribution Everywhere

Every movie card must show:
- Channel name
- YouTube icon/logo
- "Watch on YouTube" messaging

```swift
struct MovieCard: View {
    let movie: Movie

    var body: some View {
        VStack {
            AsyncImage(url: movie.posterURL)

            Text(movie.title)
                .font(.headline)

            // REQUIRED: YouTube attribution
            Text("on \(movie.channelTitle)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}
```

## Development Workflow

### Using Railway for Backend Deployment

1. **Check current deployments:**
   ```
   Ask: "Show me my Railway projects and their status"
   ```

2. **Deploy backend changes:**
   ```
   Ask: "Deploy the backend service to Railway"
   ```

3. **Monitor deployment:**
   ```
   Ask: "Show me the deployment logs"
   Ask: "What's the health status of my backend service?"
   ```

4. **Manage environment variables:**
   ```
   Ask: "List all environment variables for production"
   Ask: "Set YOUTUBE_API_KEY to [key] for production environment"
   ```

### Backend Development (Planned)

The backend will be deployed on Railway.app and will handle:
- YouTube API proxy to protect API keys
- Movie metadata caching
- User authentication and preferences
- Analytics and usage tracking

## Security Notes

- Railway API token is stored in `~/.claude.json` (never commit to git)
- Supabase credentials should be stored securely
- YouTube API keys should be stored in Railway environment variables
- Backend should proxy all YouTube API requests
- Never expose API keys in client code
- Follow Supabase MCP security best practices (see `SUPABASE_MCP_SETUP.md`)

## Resources

### Railway
- **Railway Dashboard**: https://railway.app/dashboard
- **Railway Docs**: https://docs.railway.app
- **Railway MCP GitHub**: https://github.com/jason-tan-swe/railway-mcp

### Supabase
- **Supabase Dashboard**: https://supabase.com/dashboard
- **Supabase Docs**: https://supabase.com/docs
- **Supabase MCP GitHub**: https://github.com/supabase-community/supabase-mcp

### YouTube
- **YouTube Data API**: https://developers.google.com/youtube/v3
- **YouTube Terms of Service**: https://www.youtube.com/t/terms

### MCP
- **MCP Documentation**: https://modelcontextprotocol.io

## Support

For Railway MCP issues:
- GitHub Issues: https://github.com/jason-tan-swe/railway-mcp/issues
- Railway Discord: https://discord.gg/railway

For Supabase MCP issues:
- GitHub Issues: https://github.com/supabase-community/supabase-mcp/issues

For MovieBoxZ development questions:
- Open an issue in this repository
