# Kids Cartoon Channel Enrichment Plan

Reference channel: **Masters of the Universe: He-Man & She-Ra**

This type of channel is different from a movie channel. Instead of individual films, it contains episodes from one or more TV series. Each video is an episode and must be matched to its correct series, season, and episode number.

---

## What Makes This Different From Movie Channels

| Movie channel | Kids cartoon channel |
|--------------|---------------------|
| One video = one film | One video = one episode |
| IMDB match by film title | IMDB match by series + season + episode number |
| No series grouping needed | Must create tv_series records first |
| Enrich from OMDB/TMDB by title | Must match YouTube title to IMDB episode guide |
| Single enrichment pass | Two passes: series setup → episode matching |

---

## The Series in This Channel

The "Masters of the Universe: He-Man & She-Ra" channel contains at least these two series:

| Series | IMDB ID | Seasons | Episodes | Years |
|--------|---------|---------|---------|-------|
| He-Man and the Masters of the Universe | tt0126158 | 2 | 100 | 1983–1985 |
| She-Ra: Princess of Power | tt0126171 | 2 | 78 | 1985–1987 |

There may also be **The New Adventures of He-Man** — check channel content before assuming the list is complete.

Episode guides are scraped and stored at:
- `/tmp/episodes-tt0126158-clean.json` (100 episodes)
- `/tmp/episodes-tt0126171-clean.json` (78 episodes)

---

## How the Database Stores This

### tv_series table (one row per series)

```
id, title, description, poster_path, year_start, year_end
```

Each series (He-Man, She-Ra, New Adventures) gets one row.

### movies / staged_movies (one row per episode)

| Column | What to set |
|--------|------------|
| `tv_series_id` | UUID from the tv_series row |
| `series_type` | `'tv_series'` (cartoon series, not mini-series) |
| `is_tv_series` | `true` |
| `is_tv_show` | `true` |
| `season_number` | e.g. 1 or 2 |
| `episode_number` | e.g. 1–50 |
| `episode_name` | Episode title from IMDB |
| `imdb_id` | Episode-level IMDB ID (e.g. tt0781877) if available, else series ID |

---

## The Enrichment Plan — Step by Step

### Step 1 — Create tv_series records

For each series in the channel, create one row in `tv_series` via the API:

```
POST /api/admin/tv-series
{
  "title": "He-Man and the Masters of the Universe",
  "description": "...",
  "year_start": 1983,
  "year_end": 1985
}
```

Save the returned UUIDs — needed for episode assignment.

Do this for every distinct series in the channel before touching episodes.

---

### Step 2 — Identify which series each YouTube video belongs to

The YouTube title will tell us the series. Common patterns on this channel:

- `"He-Man... Episode Title"` → He-Man original series (tt0126158)
- `"She-Ra... Episode Title"` → She-Ra (tt0126171)
- `"New Adventures of He-Man..."` → New Adventures (separate series)

Use a **title prefix matching** strategy:
1. Fetch all staged movies for the channel
2. For each video, check the `youtube_video_title` against known series name patterns
3. Assign `tv_series_id` based on match

This can be done with a Node.js script (similar to `enrich-tv-series.js`).

---

### Step 3 — Match each video to its episode number

YouTube titles on cartoon channels rarely include season/episode numbers directly. Two strategies:

**Strategy A — Title matching against IMDB episode guide**
1. Load the scraped episode list from IMDB (JSON files above)
2. For each staged movie, compare `youtube_video_title` to IMDB episode titles using fuzzy matching (Levenshtein, same scorer used in the verify agent)
3. Best match gives us: `season_number`, `episode_number`, `episode_name`, and the episode IMDB ID

**Strategy B — oEmbed + manual ordering**
1. Use `https://www.youtube.com/oembed?url=...&format=json` to get the real YouTube title
2. If the title contains episode number clues (e.g. "Ep 5", "Episode 12"), extract them
3. Fall back to air-date ordering if episode numbers are absent

**Recommended:** Strategy A first, fall back to Strategy B. Flag any unmatched episodes for manual review in the browser review tool.

---

### Step 4 — Enrich with IMDB episode data

For cartoon episodes, OMDB works poorly (it often returns the series record, not the episode).

**Better approach:**

- If we have an episode-level IMDB ID (e.g. tt0781877 for "Diamond Ray of Disappearance"):
  - Call `POST /api/admin/staging/movies/:id/enrich-manual-imdb` with the episode IMDB ID
  - This gets episode-specific rating, air date, description

- If we only have the series IMDB ID (no episode-level ID):
  - Use `enrich-from-data` with series poster + episode metadata we already know
  - Set: `imdb_id` = series ID, `episode_name`, `season_number`, `episode_number`, `release_date` from air date

The series poster (from the series-level IMDB page) should be used as the poster for all episodes unless episode-specific posters are available.

---

### Step 5 — Set all TV metadata flags

After matching, update each staged movie:

```
PATCH /api/admin/staging/movies/:id
{
  "tv_series_id": "<uuid>",
  "series_type": "tv_series",
  "is_tv_series": true,
  "is_tv_show": true,
  "season_number": 1,
  "episode_number": 5,
  "episode_name": "Diamond Ray of Disappearance"
}
```

---

### Step 6 — Approve and publish

Once enriched and metadata is correct, approve and publish the same way as movie channels:

```
POST /api/admin/staging/movies/:id/approve
POST /api/admin/staging/publish  { "ids": [...] }
```

---

## Node.js Script Needed

We need a new script — `backend/scripts/enrich-cartoon-channel.js` — that does:

1. Fetch all staged movies for the channel
2. Load IMDB episode JSON files
3. For each staged movie:
   - Identify which series it belongs to (title prefix match)
   - Fuzzy-match title to IMDB episode list → get season, episode, episode IMDB ID
   - PATCH the staged movie with tv_series_id + episode metadata
   - Call enrich-manual-imdb with episode IMDB ID (or enrich-from-data if no episode ID)
4. Log unmatched episodes for manual review
5. Report how many matched vs unmatched

---

## What to Do Manually vs Automated

| Task | How |
|------|-----|
| Create tv_series records | Script or macOS Admin → TV Series tab |
| Match series by title prefix | Automated script |
| Match episode number by title | Automated (fuzzy match) |
| Flag ambiguous matches | Output to log, review manually |
| Enrich with IMDB data | Automated (enrich-manual-imdb per episode) |
| Approve + publish | Script or macOS Admin |

---

## Known Gotchas

- **Multiple series, same channel**: Don't assume all videos are from the same series. He-Man and She-Ra are two distinct series with separate IMDB IDs. The script must detect which series each video belongs to before assigning episode numbers.

- **Season numbering**: He-Man has 2 seasons of 50 episodes each. YouTube may not distinguish Season 1 from Season 2. Use air date from IMDB episode guide to determine the correct season if the title doesn't make it clear.

- **No episode-level IMDB IDs for some episodes**: Some IMDB episodes don't have their own tt ID (especially Season 2 of She-Ra). In that case use the series IMDB ID and rely on `enrich-from-data` with the episode metadata we have from the guide.

- **Duplicate episodes**: Same episode may appear twice on the channel (different upload). Use the same duplicate detection as for movie channels — match by `imdb_id` + `episode_number` + `season_number`.

- **The verify agent is not designed for episodes**: The existing imdb-verify-agent searches IMDB by film title and scores by year/director/actors. This doesn't work for cartoon episodes. We need a separate episode-matching script, not the verify agent.

---

## Summary

```
Channel imported to staged_movies
  ↓
Script identifies series per video (title prefix)
  ↓
Script fuzzy-matches video title to IMDB episode guide
  ↓
PATCH: tv_series_id, season_number, episode_number, episode_name
  ↓
enrich-manual-imdb (episode IMDB ID) or enrich-from-data (series ID + episode metadata)
  ↓
Approve → Publish
```

Two things to build:
1. `backend/scripts/enrich-cartoon-channel.js` — the matching + enrichment script
2. IMDB episode scraper — already partially done via Playwright agent, JSON files in /tmp
