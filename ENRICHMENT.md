# MovieBoxZ Enrichment System

How enrichment actually works — the tools, the flow, the endpoints. Written so future Claude sessions can understand the system without guessing.

---

## What Enrichment Means

A movie enters the system as a YouTube video with almost no metadata — just a title, video ID, and channel. Enrichment fills in the rest: poster, description, runtime, director, actors, IMDB rating, genres, release date.

There are two enrichment paths:
1. **Automatic** — TMDB or OMDB API, based on title matching
2. **Manual (IMDB-verified)** — a human or the verify agent picks the exact IMDB ID

Manual enrichment always wins. It sets `manually_verified = true` and `enrichment_confidence = 1.0`, and batch enrichment will never overwrite it.

---

## The Two Tables

| Table | What it is |
|-------|-----------|
| `staged_movies` | Import queue — movies waiting to be reviewed and published |
| `movies` | Production — what users see in the app |

Enrichment can happen in either table. The endpoints and column names are the same but the routes differ (`/staging/` vs just `/admin/movies/`).

---

## The IMDB Verify Agent

**Location:** `/Users/mrahl/movieboxz/imdb-verify-agent/`

This is the main enrichment tool. A Node.js CLI that runs Playwright, searches IMDB, scores candidates, auto-fixes confident matches, and opens a browser review UI for uncertain ones.

### How to run it

```bash
cd /Users/mrahl/movieboxz/imdb-verify-agent

# Review staging movies from a specific channel
node verify.js --staging --channel "Artflix - Movie Classics"

# Production movies only
node verify.js

# Auto-fix only, no browser
node verify.js --auto-only

# Resume previous run (uses queue.json)
node verify.js --resume
```

The review UI opens at **http://localhost:7788** after all movies are processed.

### Internal flow

```
verify.js
  └── fetcher.js         → GET /api/admin/staging/movies (paginated)
  └── imdbSearcher.js    → IMDB suggestion API + Playwright page scrape
  └── scorer.js          → Confidence score 0–100
  └── autoFixer.js       → Calls backend to save the match
  └── reviewServer.js    → Express server on port 7788 for manual review
```

### Scoring thresholds

| Score | Action |
|-------|--------|
| ≥ 85 | Auto-fix — no human needed |
| 50–84 | Queued for manual review in browser |
| < 50 | Skipped |

Score is built from: title similarity (30pts) + year match (25pts) + director match (20pts) + actor overlap (15pts) + media type (10pts).

### Fallback mechanism (important)

The agent first tries the server-side enrichment endpoint. If the server returns **404 or 500** (usually because OMDB has no data for that IMDB ID), it falls back to scraping IMDB locally with Playwright and calling `enrich-from-data` instead.

**File:** `lib/autoFixer.js`

```
Primary:  POST /api/admin/staging/movies/:id/enrich-manual-imdb  (server uses OMDB)
Fallback: scrapeImdbWithPlaywright(imdbId) → POST .../enrich-from-data  (local Playwright)
```

---

## Backend Enrichment Endpoints

### Staging

| Endpoint | What it does |
|----------|-------------|
| `POST /api/admin/staging/movies/:id/enrich` | Auto-enrich from TMDB/OMDB by title |
| `POST /api/admin/staging/movies/:id/enrich-manual-imdb` | Enrich from specific IMDB ID (uses OMDB) |
| `POST /api/admin/staging/movies/:id/enrich-from-data` | Save pre-scraped Playwright data |
| `POST /api/admin/staging/movies/:id/preview-enrichment` | Preview enrichment without saving |
| `POST /api/admin/staging/movies/:id/clear-enrichment` | Reset all enrichment back to blank |
| `POST /api/admin/staging/batch-enrich` | Async batch enrich (skips manually_verified) |

### Production

| Endpoint | What it does |
|----------|-------------|
| `POST /api/admin/movies/:id/enrich-manual-imdb` | Enrich production movie from IMDB ID |
| `POST /api/admin/movies/:id/enrich-from-data` | Save pre-scraped Playwright data to production |

### enrich-manual-imdb request body

```json
{
  "imdbId": "tt0034303",
  "verifiedBy": "imdb-verify-agent"
}
```

This calls OMDB's `getByImdbId()`, sets `manually_verified = true`, `enrichment_source = 'manual_imdb'`, `enrichment_confidence = 1.0`.

### enrich-from-data request body (Playwright fallback)

```json
{
  "imdbId": "tt0034303",
  "title": "Topper Returns",
  "year": "1941",
  "directors": ["Roy Del Ruth"],
  "actors": ["Joan Blondell", "Roland Young"],
  "description": "...",
  "posterUrl": "https://...",
  "genres": ["Comedy", "Mystery"],
  "imdbRating": "7.1",
  "type": "Movie"
}
```

Sets `enrichment_source = 'playwright_local'`.

---

## Data Sources

| Source | When used |
|--------|----------|
| **OMDB** | Primary for `enrich-manual-imdb` — gets data by IMDB ID |
| **TMDB** | Used by auto-enrich (`/enrich`) via `selectiveEnrichment` service |
| **Playwright / IMDB** | Used by verify agent to search candidates + fallback scraping |

OMDB key is in Railway env var `OMDB_API_KEY`. TMDB key is `TMDB_API_KEY`.

---

## Key Database Columns

### Both tables

| Column | Meaning |
|--------|---------|
| `enrichment_source` | Where data came from: `'manual_imdb'`, `'omdb'`, `'tmdb'`, `'playwright_local'` |
| `enrichment_confidence` | 0–1 (1.0 = manually verified) |
| `enriched_at` | When enrichment happened |
| `imdb_id` | The IMDB title ID (e.g. tt0034303) |
| `poster_path` | TMDB-style path or full URL |

### Staging only

| Column | Meaning |
|--------|---------|
| `manually_verified` | `true` = human picked this IMDB ID, don't overwrite |
| `verified_by` | Who verified — e.g. `'imdb-verify-agent'`, `'admin'` |
| `verified_at` | Timestamp |
| `manual_imdb_id` | The IMDB ID specifically chosen by human |
| `enrichment_preview` | Preview data before committing (used by preview endpoint) |

---

## Batch Enrichment Scripts

These are one-off Node.js scripts in `backend/scripts/` with hardcoded movie lists:

| Script | Purpose |
|--------|---------|
| `enrich-tv-series.js` | Enrich TV series and mini-series in production |
| `restore-blacktree-posters.js` | Restore missing posters for BlackTree TV movies |
| `cleanup-artflix-duplicates.js` | Remove duplicate staged movies, publish approved |

Run from `backend/` directory:
```bash
cd /Users/mrahl/movieboxz/backend
node scripts/enrich-tv-series.js
```

---

## Staging → Production Flow

```
YouTube channel
  ↓
import (staged_movies, status: pending)
  ↓
enrich (auto or manual IMDB)
  ↓
approve → POST /api/admin/staging/movies/:id/approve
  ↓
publish → POST /api/admin/staging/publish  { ids: [...] }
  ↓
movies table (production)
```

Batch publish via the cleanup script or directly:
```bash
POST /api/admin/staging/publish
{ "ids": ["uuid1", "uuid2", ...] }
```

---

## What to Watch Out For

- **Batch enrich skips `manually_verified = true`** — safe to run without overwriting human picks
- **OMDB returns null for obscure films** → server returns 404 → verify agent fallback kicks in with Playwright
- **`enrich-manual-imdb` only updates `description`/`release_date`/`runtime` if they're currently empty** on production movies (to avoid overwriting good data)
- **Genres are deleted and re-inserted atomically** via the `update_movie_genres()` RPC or direct delete/insert in the admin route
- **The verify agent must be restarted to pick up new pending movies** — it fetches the list at startup, not live
