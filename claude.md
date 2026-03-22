# MovieBoxZ — Project Guide for Claude

## What this project is

MovieBoxZ is a free movie streaming **discovery** platform. It does not host video — all movies play in the official YouTube app via deep link (`youtube:///watch?v=VIDEO_ID`). The platform:

1. Imports movies from curated YouTube channels via the YouTube Data API
2. Enriches them with metadata from TMDB and OMDB
3. Exposes them through a REST API (Node.js on Railway)
4. Displays them in consumer apps (iOS + tvOS)
5. Lets admins manage everything from a macOS Admin tool

---

## Repository layout

```
movieboxz/
├── backend/              Node.js API server (deployed on Railway)
│   ├── src/
│   │   ├── routes/       All API routes (browse, admin, staging, channels, etc.)
│   │   ├── services/     youtubeService, tmdbService
│   │   ├── middleware/   adminAuth, auth, errorHandler
│   │   └── config/       database (Supabase client)
│   └── database/
│       └── migrations/   SQL migrations (apply via Supabase dashboard or CLI)
├── iOS/                  iOS + tvOS consumer app (SwiftUI)
│   └── MovieBoxZ.xcodeproj
├── macOS/                macOS Admin tool (SwiftUI)
│   └── MovieBoxZAdmin.xcodeproj
└── Shared/               SwiftUI views shared between iOS and tvOS targets
    └── Views/
```

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Backend | Node.js (ESM), Express, Railway (hosting) |
| Database | Supabase (PostgreSQL) |
| iOS/tvOS app | SwiftUI, supports iOS 17+ and tvOS 17+ |
| macOS Admin | SwiftUI, macOS 14+ |
| Movie metadata | TMDB, OMDB |
| Video source | YouTube Data API v3 |

---

## Backend — key rules

### YouTube API quota
- **Budget: 10,000 units/day**
- `search.list` = 100 units per call — **almost never use this**
- `playlistItems.list` = 1 unit per page — use this to fetch channel videos
- `channels.list` (contentDetails) = 1 unit — to get the uploads playlist ID
- `videos.list` = 1 unit per page — to get video details
- The health check endpoint uses key-presence check only (0 units)

### Admin authentication
- All `/api/admin/*` routes require `x-admin-api-key` header
- Key is stored in Railway environment variable `ADMIN_API_KEY`
- Auth middleware is in `backend/src/middleware/adminAuth.js`
- **Never hardcode the key in source code**

### Staging workflow
```
YouTube channel → import (staged_movies) → enrich → approve → publish (movies table)
```
- `staged_movies` table: status flow is `pending` → `enriched` → `approved` → `publishing` → `published`
- `movies` table: production movies visible in the consumer apps
- Genre update uses the `update_movie_genres()` Postgres RPC (atomic)

### Field allowlist
The staging PATCH endpoint has an explicit `STAGING_PATCH_ALLOWED_FIELDS` allowlist. Do not add `approval_status`, `published_movie_id`, or `manually_verified` to it — those have dedicated endpoints.

---

## iOS/tvOS app — key rules

### Platform conditionals
Use `#if os(tvOS)` / `#if os(iOS)` throughout. Both platforms are built from the same source files. The tvOS target uses the same `.xcodeproj` — check `SUPPORTED_PLATFORMS` in build settings.

### tvOS specifics
- Icons live in `Assets.xcassets/AppIcon.brandassets` (`.imagestack` format, 2 layers required)
- Deep link format: `youtube:///watch?v=VIDEO_ID` (triple slash)
- No `.sheet` on tvOS — use `.fullScreenCover`
- No `.navigationBarLeading` toolbar placement on tvOS
- Use `.searchable(text:placement:.automatic)` + `.onSubmit(of:.search)` for search on tvOS
- Back buttons need `.buttonStyle(.card)` for focus ring on tvOS

### UI tests
- Test target: `MovieBoxZUITests`
- Base class: `MovieBoxZUITestCase` (sets `UI_TESTING_SKIP_WELCOME` launch arg)
- Page objects in `MovieBoxZUITests/Pages/`
- Tests in `MovieBoxZUITests/Tests/`
- SwiftUI `TabView` on iOS 18 does not expose as `UITabBar` — query `app.buttons["Browse"]` directly

---

## macOS Admin app — key rules

### API key setup
New contributors: open the app → Preferences (Cmd+,) → enter the `ADMIN_API_KEY` and backend URL. The key is **never** stored in source code.

### Architecture
- Each view has its own `@StateObject private var apiService = AdminAPIService()`
- `AdminAPIService` reads `apiBaseURL` and `adminAPIKey` from `UserDefaults` at init
- If you change the key in Preferences, restart the app for all views to pick it up

### Multi-user safety
- Delete staged movie: requires confirmation dialog
- Reject movie: requires typing a reason in a sheet
- Publish All: movies transition to `publishing` status atomically before processing (prevents double-publish)
- No optimistic locking yet — last write wins on concurrent edits (known limitation)

---

## Database

- Provider: Supabase (PostgreSQL)
- Project ref: `oltlikatlvbwavfxqazn`
- Migrations: `backend/database/migrations/` — numbered sequentially, apply in order
- Key tables: `movies`, `staged_movies`, `channels`, `channel_patterns`, `genres`, `movie_genres`
- Key RPC functions: `update_movie_genres(p_movie_id, p_genre_ids)`

---

## Running locally

### Backend
```bash
cd backend
cp .env.example .env        # fill in your own keys
npm install
npm run dev                 # starts on http://localhost:3000
```

### iOS app
Open `iOS/MovieBoxZ.xcodeproj` in Xcode. Select the `MovieBoxZ` scheme and run on simulator or device.

### macOS Admin
Open `macOS/MovieBoxZAdmin.xcodeproj` in Xcode. Run the `MovieBoxZAdmin` scheme. On first launch, go to Preferences (Cmd+,) and set:
- **Backend URL**: your Railway URL or `http://localhost:3000`
- **Admin API Key**: your `ADMIN_API_KEY` value

---

## Deployment

- Backend deploys automatically when `main` is pushed to GitHub (Railway CI)
- Migrations must be applied manually via the Supabase dashboard SQL editor or CLI
- iOS/tvOS: archive and submit via Xcode Organizer
- macOS Admin: distribute directly (not on App Store) — share the built `.app`

---

## Common pitfalls

| Pitfall | Fix |
|---------|-----|
| YouTube quota exhausted | Check Railway logs for unexpected `search.list` calls |
| Staging PATCH silently ignores fields | Only `STAGING_PATCH_ALLOWED_FIELDS` are applied — check the allowlist |
| tvOS icon build error | Icons need 2 layers and must be fully opaque (no alpha channel) |
| Admin returns 401 | Check `x-admin-api-key` header matches `ADMIN_API_KEY` env var |
| Genre update partially applied | Use the `update_movie_genres` RPC, not separate DELETE + INSERT |
