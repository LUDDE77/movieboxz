# MovieBoxZ iOS App — Requirements

This document defines all screens, features, and data requirements for the MovieBoxZ iPhone app.
It is the single source of truth for the new build. No existing code is carried forward.

---

## Core Requirement: Full-Screen Landscape

- The app is **landscape-only** on iPhone and iPad
- The app content must fill **100% of the physical screen** edge-to-edge — no black bars on any side
- No status bar visible at any time
- No home indicator visible
- This must work from the very first frame, before any animation

---

## Navigation Structure

- Vertical **side rail** on the left edge (72pt wide)
- Four tabs in the rail: **Browse**, **Search**, **Library**, **Settings**
- Each tab button shows an icon + label below it
- Selected tab is red, unselected is gray
- Tapping a tab switches the content area and triggers haptic selection feedback
- Content area fills the rest of the screen to the right of the rail

### Tab Icons
- Browse: `tv.fill`
- Search: `magnifyingglass`
- Library: `heart.fill`
- Settings: `gearshape.fill`

---

## Screen 1: Welcome (First-Run Onboarding)

Shown only the very first time the app launches (`hasSeenWelcome` stored in UserDefaults).

### Visual Layout
- Dark gradient background (black → dark purple → black, diagonal)
- Circular badge with play icon (red-to-purple gradient)
- Title: "MovieBoxZ" (large, bold, rounded)
- Subtitle: "Discover Movies from YouTube"
- Three feature rows, each with icon + title + description:
  1. **Discover Movies** — "Browse thousands of movies from curated YouTube channels"
  2. **Watch on YouTube** — "All videos play in the official YouTube app"
  3. **Build Your Library** — "Save favourites and track what you've watched"
- Yellow info box: warning icon + text about YouTube requirement
- "Get Started" full-width button (red→purple gradient)
- Legal text: "By continuing, you agree to YouTube's Terms of Service"

### Behavior
- Tap "Get Started":
  - If YouTube app is installed → set `hasSeenWelcome = true`, proceed to main app
  - If YouTube not installed → show alert:
    - "Install YouTube" → open App Store YouTube page
    - "Continue Anyway" → set `hasSeenWelcome = true`, proceed anyway
    - "Cancel" → stay on welcome screen

---

## Screen 2: Splash Screen

Shown every launch after welcome is dismissed. Auto-advances to main app.

### Visual Layout
- Black background
- Centered play icon (100pt, red-to-purple gradient)
- App name: "MovieBoxZ" (52pt, bold, rounded)
- Version string below app name

### Behavior
- On appear: icon scales from 0.8 → 1.0 (0.5s easeIn), screen fades in (0.4s)
- After 2.0 seconds: fade out to main app content (0.5s easeOut)
- No user interaction

---

## Screen 3: Browse (Main Discovery)

Default tab. Shows curated movie content in horizontal carousels.

### Layout
- Full-width backdrop image (from featured movie) with black gradient overlay
- Below backdrop: scrollable list of carousels

### Sections (in order, only shown if populated)
1. **Featured Banner** — top hero section with one featured/recent movie
2. **Trending Now** — horizontal carousel, max 12 movies, "See All" button
3. **Popular** — horizontal carousel, max 12 movies, "See All" button
4. **Genre Sections** — one carousel per genre (sorted alphabetically), max 12 each, "See All" per genre
5. **Other** — uncategorized movies, horizontal carousel, "See All"
6. **Recently Added** — horizontal carousel, "See All"
7. **All Movies** — horizontal carousel, "See All"

### Featured Banner
- Backdrop image filling the hero area
- Bottom-left content: title, metadata pills (year, rating, runtime), 2-line description
- "Watch on YouTube" button (play icon + text, dark background)
- Tapping opens Movie Detail View

### Movie Card (used in all carousels and grids)
- 110×165pt poster image (corner radius 7pt)
- Fallback: YouTube thumbnail, then gray placeholder with film icon
- Title below (2 lines max, 11pt semibold white)
- Metadata row: star + rating + bullet + year (10pt, semi-transparent white)
- Tap → opens Movie Detail View
- Long-press context menu:
  - Add/Remove from Favourites
  - Watch on YouTube (opens deep link)

### Carousel Row
- Section title (18pt bold white) + "See All" button (right side)
- Horizontal ScrollView, no scroll indicators
- Max 12 movie cards per carousel

### Loading State
- Show skeleton placeholders: hero placeholder + 3 carousel skeletons
- Each skeleton uses gray rectangles with shimmer animation

### Data Loaded on Appear (concurrent)
- Recent movies (50) — first becomes featured
- Trending (20)
- Popular (20)
- All genres list
- All movies (50)
- Uncategorized (10)
- Per-genre movies (10 each, in parallel)

---

## Screen 4: Category Grid View (modal, launched from "See All")

Full grid of movies for a specific category.

### Header
- Back/close button (chevron + "Back") — top left, dismisses modal
- Category title — center
- Movie count below header ("X movies")

### Content
- Adaptive grid (min 110pt, max 140pt per column, 14pt spacing)
- LazyVGrid of MovieCard components
- Loads up to 200 movies for the category

### Category Types
- Genre (by genre ID)
- Trending
- Popular
- Recently Added
- All Movies
- Uncategorized

### States
- Loading: centered spinner
- Error: error icon + message + "Try Again" button
- Content: movie grid

---

## Screen 5: Movie Detail View (modal sheet)

Full movie info sheet, opened when tapping any movie card.

### Layout
- Backdrop image at top with gradient (clear → black)
- Poster (90×135pt) bottom-left over gradient, with shadow
- Movie title (22pt bold, max 3 lines) next to poster
- Close button (X) top-left
- Favorite button (heart) top-right

### Content (scrollable below header)
1. **Watch on YouTube** button — full width, white bg, black text, play icon
2. **Secondary actions** row:
   - Save (bookmark icon) — adds to favorites
   - Share (share icon) — opens system share sheet with YouTube URL
3. **Metadata badges** — runtime, rating (star), release year, quality (green if present)
4. **Description** text (if available, 15pt)
5. **Genre tags** — horizontal scroll, pill-shaped, red/purple gradient bg
6. **YouTube Attribution** (full style — see below)
7. **Legal disclaimer** — "This content is hosted on YouTube. MovieBoxZ does not host or stream any video content."

### Behavior
- Tap Watch → record watch in history, open Video Player
- Tap Save → toggle favorite
- Tap Share → UIActivityViewController with YouTube URL
- Tap Close → dismiss modal
- Tap Favorite heart → toggle favorite with heart animation

---

## Screen 6: Video Player (sheet from Movie Detail)

Plays the movie via YouTube.

### Visual
- Full-screen SFSafariViewController
- Black bar color, red tint color for controls
- Close button overlay (top-left, X icon, white)

### Behavior
- Opens `youtube:///watch?v={youtubeVideoId}` (deep link — triple slash)
- Fallback if deep link fails: `https://www.youtube.com/watch?v={youtubeVideoId}`
- Close button dismisses player, returns to Movie Detail

---

## Screen 7: Search

Search movies by title.

### Layout
- Fixed search bar at top:
  - Magnifying glass icon (leading)
  - "Search movies..." placeholder
  - Clear (X) button when text is present
  - Submit label: "Search"
  - White 0.1 opacity background, 10pt corner radius
- Content area below

### States
- **Initial** (no search yet): icon + "Search Movies" + "Type a title to find movies"
- **Searching**: centered spinner
- **No results**: icon + "No Results" + "Try a different search term"
- **Results**: count text + adaptive grid of MovieCard components

### Behavior
- Tap submit on keyboard → call `searchMovies(query)` API
- Tap X → clear query, results, reset to initial state
- Tap movie card → open Movie Detail View

### API
- Endpoint: `GET /browse/search?q={query}&page=1&limit=50`

---

## Screen 8: Library

User's saved favorites and watch history.

### Layout
- Two-tab picker at top: "My List" (favorites) / "Watched" (history)
- Selected tab: semibold, white, light gray background pill
- Unselected: gray, transparent

### States (per tab)
- **Loading**: centered spinner
- **Empty My List**: heart.slash icon + "No Favourites Yet" + "Tap ♡ on any movie to save it here"
- **Empty Watched**: clock.badge.xmark icon + "No Watch History" + "Movies you watch will appear here"
- **Content**: adaptive grid (min 110pt, max 140pt, 14pt spacing) of MovieCard components

### Behavior
- Data: fetches all movies (limit 200), filters locally by favorites/history IDs
- Tap movie card → open Movie Detail View
- Long-press on card → Add/Remove Favorites, Watch on YouTube
- Observes LibraryManager for live updates

---

## Screen 9: Settings

App info, connection status, and legal information.

### Layout
- Header: app icon + "MovieBoxZ" title + version string
- **Connection section**:
  - Status icon (green = connected, red = not connected)
  - Status text
  - "Test" button — calls health check, shows spinner while testing
- **YouTube section** (informational rows):
  - Deep link format
  - SFSafariViewController fallback
  - TOS compliance note
- **About section** (informational):
  - Privacy Policy
  - Terms of Service
- **Support section** (informational):
  - Help & FAQ
  - Contact Support
- Footer legal disclaimer text

### API
- Health check: `GET /health`

---

## Shared Components

### Favorite Button
- Circular (pill shape), black 0.5 opacity background
- Heart icon: filled red (favorited) or outlined white (not)
- Tap: toggle favorite via LibraryManager, light haptic, 0.2s easeInOut animation
- Initializes state from LibraryManager on appear

### YouTube Attribution
- **Compact** (on cards): small red play icon + "YouTube" text, dark bg
- **Full** (in Movie Detail): red play icon + "Powered by YouTube" + "Video content hosted on YouTube"

### Loading Skeleton
- Used in Browse while data is loading
- Hero placeholder + 3 carousel placeholders
- Gray rectangles with shimmer animation loop

### Haptic Feedback
- `light()` — on favorite toggle
- `selection()` — on tab switch
- `success/warning/error/medium/heavy` available for future use

---

## Data Model: Movie

All fields from the backend API:

| Field | Type | Notes |
|-------|------|-------|
| `id` | String | Unique ID |
| `youtubeVideoId` | String | YouTube video ID |
| `title` | String? | TMDB/enriched title |
| `originalTitle` | String? | Original film title |
| `description` | String? | Plot description |
| `releaseDate` | Date? | Release date |
| `runtimeMinutes` | Int? | Duration in minutes |
| `youtubeVideoTitle` | String? | YouTube video title (TOS required) |
| `channelId` | String | YouTube channel ID |
| `channelTitle` | String | YouTube channel name |
| `channelThumbnail` | String? | Channel avatar URL |
| `viewCount` | Int? | YouTube views |
| `likeCount` | Int? | YouTube likes |
| `publishedAt` | Date? | YouTube publish date |
| `tmdbId` | Int? | TMDB ID |
| `imdbId` | String? | IMDB ID |
| `posterPath` | String? | TMDB poster path |
| `backdropPath` | String? | TMDB backdrop path |
| `voteAverage` | Double? | TMDB rating (0–10) |
| `imdbRating` | Double? | IMDB rating |
| `rated` | String? | Content rating (PG, R, etc.) |
| `quality` | String? | Video quality |
| `featured` | Bool? | Featured flag |
| `trending` | Bool? | Trending flag |
| `genres` | [Genre]? | Genre objects |
| `addedAt` | Date? | When added to DB |

**Computed:**
- `displayTitle` — `title ?? youtubeVideoTitle ?? "Unknown Title"`
- `posterURL` — TMDB CDN `https://image.tmdb.org/t/p/w342{posterPath}` or YouTube thumbnail
- `backdropURL` — TMDB CDN `https://image.tmdb.org/t/p/w1280{backdropPath}` or YouTube maxres
- `youtubeAppURL` — `youtube:///watch?v={youtubeVideoId}` (triple slash)
- `youtubeURL` — `https://www.youtube.com/watch?v={youtubeVideoId}`
- `formattedRuntime` — "Xh Ym"
- `formattedReleaseYear` — 4-digit year
- `formattedRating` — TMDB or IMDB rating to 1 decimal

### Genre
| Field | Type |
|-------|------|
| `id` | Int |
| `name` | String |
| `tmdbId` | Int? |
| `movieCount` | Int? |

---

## Data Storage (Local, UserDefaults)

### Favorites
- Key: `"movieboxz.favorites"`
- Type: JSON-encoded `[String]` (array of movie IDs)
- Operations: add, remove, toggle, check (isFavorite), list all

### Watch History
- Key: `"movieboxz.watchHistory"`
- Type: JSON-encoded `[WatchHistoryItem]`
- Max 100 items, newest first
- Duplicate entry is removed then re-added at top
- WatchHistoryItem: `{ id: UUID, movieId: String, movieTitle: String, posterURL: URL?, watchedAt: Date }`
- Operations: track (add), remove, clear all, check (isWatched)

---

## Backend API

**Base URL:** `https://movieboxz-backend-production.up.railway.app/api`

| Endpoint | Method | Params | Returns |
|----------|--------|--------|---------|
| `/health` | GET | — | Connection status |
| `/movies/featured` | GET | — | [Movie] |
| `/movies/trending` | GET | page, limit | [Movie] |
| `/movies/popular` | GET | page, limit | [Movie] |
| `/movies/recent` | GET | page, limit | [Movie] |
| `/movies` | GET | sort, page, limit | [Movie] |
| `/browse/search` | GET | q, page, limit | [Movie] |
| `/browse/genres` | GET | — | [Genre] |
| `/browse/genres/{id}` | GET | page, limit | [Movie] |

- JSON keys are snake_case from backend, decoded to camelCase in Swift
- Dates: ISO8601 primary, `yyyy-MM-dd` fallback
- No authentication required for browse/search endpoints

---

## YouTube Integration

- Deep link to play: `youtube:///watch?v={id}` (triple slash is required)
- YouTube app install check: `UIApplication.canOpenURL("youtube://")`
- Web fallback: `SFSafariViewController` with `https://www.youtube.com/watch?v={id}`
- Channel open: `youtube://channel/{channelId}` or web fallback
- App Store link (for install prompt): `https://apps.apple.com/app/youtube-watch-listen-stream/id544007664`

---

## Design Language

- **Background:** Pure black `#000000`
- **Primary accent:** Red
- **Secondary accent:** Purple (used in gradients with red)
- **Text primary:** White
- **Text secondary:** White at 50–70% opacity
- **Material:** `.ultraThinMaterial` for side rail background
- **Corner radius:** 7pt (cards), 8–10pt (buttons/containers), 16pt (genre pills)
- **Font:** System (San Francisco), rounded design for large display text
- **Poster aspect ratio:** 2:3 (110×165pt)
- **Card spacing in carousels:** 12pt
- **Horizontal padding:** 16pt
- **Section spacing:** 32pt

---

## Navigation Flow

```
App Launch
├── First run → Welcome Screen → (accepted) → Splash → Main App
└── Return user → Splash → Main App

Main App (side rail tabs)
├── Browse
│   ├── Featured Banner tap → Movie Detail (sheet)
│   ├── Movie Card tap → Movie Detail (sheet)
│   └── "See All" tap → Category Grid (sheet)
│       └── Movie Card tap → Movie Detail (sheet)
│
├── Search
│   └── Movie Card tap → Movie Detail (sheet)
│
├── Library
│   └── Movie Card tap → Movie Detail (sheet)
│
└── Settings
    └── Test Connection button

Movie Detail (sheet)
├── Watch → Video Player (sheet) → Close → back to Detail
├── Save → toggle favorite
├── Share → system share sheet
├── Favorite heart → toggle favorite
└── Close (X) → dismiss
```

---

## Technical Constraints

- **iOS 17+** minimum deployment target
- **iPhone and iPad** supported (`TARGETED_DEVICE_FAMILY = "1,2"`)
- **Landscape only** — both left and right landscape orientations
- **No status bar** at any time
- **No portrait support**
- Network timeout: 30s request, 60s resource
- All API calls: `async/await`
- LibraryManager: `@MainActor` singleton, `ObservableObject`
- YouTubeService: `@MainActor` singleton
- No server-side user accounts — all user data is local only
