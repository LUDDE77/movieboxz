# MovieBoxZ

A free movie discovery platform that surfaces YouTube-hosted movies in a curated, Netflix-style browsing experience across iOS, Apple TV, and a macOS admin tool.

> **Note:** MovieBoxZ does not host or stream video. All movies play in the official YouTube app via deep link.

---

## Apps

| App | Platform | Purpose |
|-----|----------|---------|
| **MovieBoxZ** | iOS 17+ / tvOS 17+ | Browse and watch movies |
| **MovieBoxZ Admin** | macOS 14+ | Import, enrich, approve, and publish movies |

---

## Prerequisites

- **Xcode 16+** (for iOS/tvOS/macOS apps)
- **Node.js 20+** (for the backend)
- A **Supabase** project (free tier works)
- A **YouTube Data API v3** key (Google Cloud Console)
- A **TMDB** API key (themoviedb.org)
- An **OMDB** API key (omdbapi.com)

---

## Quick start

### 1. Clone

```bash
git clone https://github.com/LUDDE77/movieboxz.git
cd movieboxz
```

### 2. Backend

```bash
cd backend
cp .env.example .env
# Open .env and fill in your Supabase, YouTube, TMDB, OMDB keys
# Generate an admin key: openssl rand -hex 32
npm install
npm run dev
# → http://localhost:3000/api/health
```

### 3. Database migrations

Apply migrations in order using the Supabase SQL editor or CLI:

```bash
# Via Supabase CLI
supabase db push

# Or manually: paste each file from backend/database/migrations/ into
# the Supabase dashboard → SQL Editor, in numerical order
```

### 4. iOS / tvOS app

```
Open iOS/MovieBoxZ.xcodeproj in Xcode
Select scheme: MovieBoxZ
Destination: iPhone simulator or Apple TV simulator
Run (Cmd+R)
```

The app talks to the backend at the URL configured in `MovieService.swift`. For local development, change `baseURL` to `http://localhost:3000`.

### 5. macOS Admin app

```
Open macOS/MovieBoxZAdmin.xcodeproj in Xcode
Run the MovieBoxZAdmin scheme
```

On first launch, open **Preferences (Cmd+,)** and set:
- **Backend URL** — your Railway URL or `http://localhost:3000`
- **Admin API Key** — the value you set as `ADMIN_API_KEY` in your `.env`

---

## Project structure

```
movieboxz/
├── backend/              Node.js/Express API (Railway)
│   ├── src/routes/       REST endpoints
│   ├── src/services/     YouTube, TMDB integrations
│   ├── src/middleware/   Auth, error handling
│   └── database/migrations/  SQL schema migrations
├── iOS/                  iOS + tvOS app (SwiftUI)
├── macOS/                Admin tool (SwiftUI, macOS-only)
└── Shared/               Views shared between iOS and tvOS
```

---

## How the staging workflow works

```
1. Import    Channel videos are fetched from YouTube and saved as staged_movies
2. Enrich    TMDB/OMDB metadata is fetched and applied to staged movies
3. Approve   An admin reviews and approves the staged movie
4. Publish   Approved movies are moved to the production movies table
             and become visible in the iOS/tvOS app
```

---

## Contributing

1. **Never commit secrets.** The `.gitignore` excludes `.env` files. Use `.env.example` as the template.
2. **Admin API key.** Set it in the macOS Admin app Preferences — never hardcode it in source.
3. **YouTube quota.** The daily budget is 10,000 units. `search.list` costs 100 units; `playlistItems.list` costs 1. Always use the cheaper API.
4. **Database migrations.** Add new migrations as `NNN_description.sql` in `backend/database/migrations/`. Apply them to Supabase manually before deploying backend code that depends on them.
5. **Both platforms.** If you change a shared view, test on both iOS simulator and Apple TV simulator.

---

## Deployment

The backend auto-deploys to Railway when `main` is pushed. iOS/tvOS and macOS Admin are distributed manually — archive in Xcode Organizer.

---

## Environment variables

See `backend/.env.example` for the full list with descriptions.
