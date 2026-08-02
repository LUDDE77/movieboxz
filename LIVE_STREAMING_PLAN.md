# MovieBoxZ — Live Streaming Plan ("Live Now")

A plan to add a live-stream discovery feature built **only on official / verified
channels streaming their own content** (Marvel HQ, Warner Bros. Entertainment,
MST3K, etc.), designed to pass App Review and deliver strong functionality.

_Draft — August 2026._

---

## 1. The concept

A **"Live Now"** section that surfaces streams currently live on YouTube **from a
curated whitelist of official, verified, first-party channels**, and hands playback
to YouTube — exactly like our VOD flow. We host nothing; we point users at what an
official rights-holder is already broadcasting publicly on YouTube.

**Naming:** "Live Now" or "Live on YouTube" — **never "Live TV"** (that phrase draws
extra IPTV/broadcast-rights scrutiny from Apple).

**Why this version is defensible:** the whole 5.2.3 risk collapses when the content
is a **rights-holder streaming its own catalog** (Marvel HQ = Disney's own Marvel
animation, 472 live viewers; WB = its own films; MST3K = its own show). That's the
strongest possible provenance — first-party content on an official channel.

---

## 2. Rules review — and how this plan satisfies each

### Apple

- **5.2.3 (rights to third-party content) — the decisive one.**
  Mitigation: **official/verified channels only, streaming their own content.** Every
  channel is manually vetted and recorded as official (studio/network/verified). We
  document provenance per channel. Same architecture as VOD: we host/stream nothing,
  deep-link to YouTube's own player, rely on YouTube's Content ID/DMCA, and any stream
  removed at the source vanishes from us automatically.
- **5.2.2 (third-party service terms).** We access via the official YouTube Data API
  (our licensed API client) and play in YouTube's own player. Authorization on request.
- **4.2.3 (minimum functionality / requiring other apps).** Live plays via the same
  YouTube hand-off we already ship (app → web on iOS → phone QR on tvOS). The Live
  section itself is standalone discovery (browse what's live, viewer counts) that works
  with nothing else installed.
- **4.1(a) (metadata/screenshots).** Screenshots use the **official channels' own
  live thumbnails** (first-party art) — not copyrighted movie posters.
- **Live-TV/IPTV scrutiny.** Neutralized by naming ("Live Now"), by official-channel
  curation, and by framing as discovery, not broadcast.

### YouTube API Services Terms + Developer Policies

- Access only through the official **YouTube Data API** (we're a registered client).
- **Playback in YouTube's own player** (deep-link / hand-off) — no restreaming,
  downloading, or embedding of a custom player.
- **Attribution:** show the channel name and "Live on YouTube" on every stream.
- **No circumvention;** honor removals (we store only a video ID).
- **Quota-respectful** (see §4) — we do not hammer search.list.

---

## 3. Content strategy — official channels only

- **Whitelist model.** A curated, manually-vetted list of official channels. Nothing
  is surfaced live unless its channel is on the list and marked `official = true`.
- **Confirmed seed set (from our probe):**
  - **Marvel HQ** — 5 permanent 24/7 streams (Ultimate Spider-Man 472 viewers, Marvel's
    Spider-Man, Hulk SMASH, Avengers Assemble). Disney first-party. ⭐ strongest.
  - **Warner Bros. Entertainment** — LOTR / Harry Potter marathons (seasonal). WB
    first-party.
  - **MST3K** — 5 streams of their own show, 24/7.
- **Where the content clusters: kids/animation.** Sustained 24/7 legit streams live in
  the kids/animation space. Candidate expansion (verify official status first):
  Nickelodeon, Cartoon Network, PBS Kids, and similar. This suggests "Live Now" pairs
  naturally with the **Kids** experience, plus a general Live row.
- **Verification rule:** a channel qualifies only if it is the rights-holder's official
  channel (verified badge / studio / network) streaming its own content. No third-party
  re-streamers, ever. Each addition is logged with its justification.

---

## 4. Technical architecture

The core constraint is **quota**: discovering a channel's live streams costs
**100 units per `search.list?eventType=live`**, but *monitoring* a known-live video is
**1 unit** (`videos.list?part=liveStreamingDetails`). So: **discover rarely, monitor
cheaply, cache aggressively, serve users from cache.**

- **`live_channels` table** (curated whitelist): `channel_id`, `handle`, `name`,
  `official` (bool), `category` (kids | movies | classic), `notes`, `active`.
- **`live_streams` cache table**: `video_id`, `channel_id`, `title`, `thumbnail_url`,
  `state` (live | ended), `concurrent_viewers`, `actual_start`, `scheduled_start`,
  `last_checked_at`.
- **Discovery job** (scheduled, e.g. every 3–4h): for each active channel,
  `search.list?eventType=live` (100 u) → new/changed live video IDs → hydrate with one
  `videos.list?liveStreamingDetails` (1 u) → upsert into `live_streams`.
  Budget: ~10 channels × 100 × ~5/day ≈ **5,000 u/day** (within the 10k budget). Scale
  channels/frequency to fit.
- **Monitor job** (frequent, e.g. every 15–30 min): for currently-`live` rows only,
  `videos.list?liveStreamingDetails` (1 u each) → refresh viewers, flip to `ended`
  when the flag clears. Near-free.
- **Public endpoint** `GET /api/browse/live?country=XX`: returns current live streams
  **from the cache** (no per-user YouTube call → fast, zero per-request quota),
  region-filtered like everything else. Reuse the existing usage-tracking + region code.
- **App:** a "Live Now" row/section that fetches `/browse/live`; each card → the same
  playback hand-off (`youtube:///watch?v=…` → web on iOS → phone QR on tvOS). No new
  playback tech.

---

## 5. UX / functionality

- **"Live Now" section** — a horizontal row on Browse, a row in Kids, and/or a small
  dedicated Live entry. Not a full "TV guide."
- **Card:** live thumbnail · **🔴 LIVE** badge · **viewer count** (real-time popularity
  — a great "what's hot" signal) · channel name · title.
- **Tap → play** the live stream on YouTube (existing deep-link/QR flow).
- **"Coming up"** (optional, later): scheduled premieres via `scheduledStartTime`.
- **Graceful ended-state:** cache refresh removes dead streams; the UI never shows a
  stream that has stopped.
- **Attribution:** channel name + "Live on YouTube" on each card and detail.

---

## 6. Rollout & risk mitigation

- **Ship in a later update**, after the current approval (and the pending tvOS build)
  are stable — not on a fragile resubmit.
- **Start small:** a handful of confirmed official channels (Marvel HQ, WB, MST3K).
- **Reviewer notes** for the update: emphasize *official/verified channels only,
  first-party content, host-nothing, YouTube hand-off, Content-ID/DMCA reliance* — and
  reference our existing Content Sourcing Policy, extended to cover live.
- **Screenshots:** use the official channels' own live thumbnails.
- **Honest residual risk:** any live feature re-opens the 5.2.3 surface. This
  official-only version is the most defensible possible framing, but expect Apple to
  look twice — so keep it small, well-documented, and clearly first-party.

---

## 7. Phased build

| Phase | Work | App build? |
|-------|------|:----------:|
| **1** | `live_channels` + `live_streams` tables; discovery + monitor jobs; `/api/browse/live` | No |
| **2** | Inventory & vet the official channel whitelist (expand kids/animation) | No |
| **3** | "Live Now" UI (row + cards + play hand-off), iOS + tvOS | **Yes** |
| **4** | Compliance: reviewer notes, screenshots, policy update, naming | No |
| **5** | Submit in a later update; monitor review | — |

Phases 1–2 and 4 are backend/prep and can start now with zero App Store exposure. Only
Phase 3 needs a build, and Phase 5 is the actual submission.

---

## 8. Open decisions (for you)

1. **Placement:** a Live row on Browse, a section in Kids, a dedicated Live tab — or a
   combination? (Given the content skews kids/animation, Kids + a Browse row is natural.)
2. **Scope of channels at launch:** just the 3 confirmed, or spend Phase 2 verifying a
   broader official kids/animation set first?
3. **Timing:** build the backend (Phases 1–2) now while the tvOS review clears, and hold
   the app-facing Phase 3 for a later, deliberate update?
