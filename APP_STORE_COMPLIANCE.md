# MovieBoxZ — App Store & YouTube Compliance

This document is the single source of truth for shipping the MovieBoxZ consumer
app (iOS + tvOS) to the App Store while complying with **Apple's App Review
Guidelines** and **YouTube's API Services Terms of Service**. It records what the
app already does to comply, the exact Info.plist / privacy configuration, and the
remaining human action items before submission.

Last updated: 2026-07-14 · App version 1.0 (build 1) · Bundle `com.movieboxz.app`

---

## 1. Compliance model in one paragraph

MovieBoxZ is a **discovery** app, not a video host. It shows curated metadata
(titles, posters, ratings, descriptions) and, when the user taps play, it
**deep-links to the official YouTube app** (`youtube:///watch?v=…`, with an
`https://www.youtube.com/watch?v=…` fallback). All video playback, advertising,
and data collection during playback happen **inside YouTube**, under YouTube's own
terms. MovieBoxZ never hosts, streams, embeds, downloads, caches, or strips ads
from any video. This is the pattern Apple and YouTube both sanction for
third-party content.

---

## 2. Apple App Review Guidelines — how we comply

| Guideline | Risk | How MovieBoxZ complies |
|---|---|---|
| **2.1 App Completeness** | Backend must be live | Backend on Railway is production; app degrades gracefully offline (Settings shows Connection status). |
| **2.3.1 Accurate metadata** | Hidden features | No hidden/undocumented features; app does exactly what the listing says. |
| **4.2 Minimum Functionality** | "Just a web wrapper" | App is a native SwiftUI experience: curated browse rows (Trending, Popular, High Score IMDB, genres), search, on-device Library/favorites, TV-series episode navigation — original curation, not a repackaged website. |
| **5.2.1 / 5.2.2 Intellectual Property** | Using others' content | We show only metadata + thumbnails we are licensed to use via the TMDB and YouTube APIs, with attribution (see §4). We do not reproduce full copyrighted works — playback is handed to YouTube. |
| **5.2.3 Third-party content (YouTube)** | Showing YT content without rights | Playback occurs in the official YouTube app under YouTube's ToS. In-app disclaimer (MovieDetailView): *"This content is hosted on YouTube and subject to YouTube's Terms of Service. MovieBoxZ does not host or stream any video content."* WelcomeView: *"By continuing, you agree to YouTube's Terms of Service."* |
| **1.1.6 / 1.2 Safety, objectionable content** | UGC moderation | Catalog is **admin-curated** (staging → review → publish pipeline); no end-user uploads. Kids content is separated into a dedicated Kids tab. |
| **3.1.1 Payments** | External purchase | App is free, no IAP, no external purchase links. |
| **5.1.1 Privacy — data collection & policy** | Missing policy / over-collection | No account, no sign-in, no personal data leaves the device. Favorites/watch history stored in `UserDefaults` on-device only. Privacy Policy + Terms linked in Settings. Privacy Manifest present (see §5). |
| **5.1.2 Data use & sharing** | Undisclosed tracking | `NSPrivacyTracking = false`; no analytics/ad SDKs; no `NSPrivacyTrackingDomains`. |

---

## 3. YouTube API Services — Terms of Service compliance

The MovieBoxZ **backend** uses the YouTube Data API v3 to import catalog metadata.
The **consumer app** does not call the YouTube API directly; it only deep-links to
the YouTube app. Both sides observe the YouTube API Services ToS and Developer
Policies:

- **No downloading / no local storage of video or streams.** We store only IDs and
  metadata; playback is streamed by YouTube itself.
- **No ad interference.** We never strip, block, or skip YouTube ads; playback is
  the unmodified YouTube app experience.
- **No background/PiP circumvention.** We do not embed the player to bypass
  YouTube's monetization or autoplay rules — we hand off to the app.
- **Attribution & links.** The app links users to **YouTube's Terms of Service**
  (`https://www.youtube.com/t/terms`) from Settings and surfaces YouTube
  attribution on content (see `YouTubeAttribution` component + "Watch on YouTube"
  affordances).
- **Google Privacy Policy.** Our Privacy Policy (linked in-app) must disclose the
  use of YouTube API Services and link to the **Google Privacy Policy**
  (`https://policies.google.com/privacy`). ← ensure the hosted policy text includes
  this (see §6 action items).
- **Quota discipline.** Import uses `playlistItems.list` (1 unit/page), never
  `search.list` (100 units); budget 10,000 units/day. Documented in `CLAUDE.md`.

---

## 4. Data-provider attribution (required by their terms)

- **TMDB** — Required text is shown in Settings → *Data Attribution*:
  *"This product uses the TMDB API but is not endorsed or certified by TMDB."*
  **Action:** TMDB also asks that the **TMDB logo** be displayed. Add the TMDB
  logo asset next to the attribution text (asset + short credit) to be fully in
  spec. Attribution text is already in the app.
- **OMDb / IMDb** — Ratings credited in Settings → *Data Attribution*
  (*"Ratings provided by OMDb API and IMDb."*).
- **YouTube** — Credited in Settings + per-content attribution + playback
  disclaimer (see §3).

---

## 5. Info.plist & Privacy Manifest — exact configuration

**`iOS/MovieBoxZ/Info.plist`** (explicit plist; `GENERATE_INFOPLIST_FILE = NO`):

- `CFBundleDisplayName = MovieBoxZ` — home-screen name.
- `ITSAppUsesNonExemptEncryption = false` — app uses only standard HTTPS (exempt
  encryption); skips the export-compliance prompt each submission.
- `LSApplicationQueriesSchemes = [youtube, vnd.youtube]` — required so
  `canOpenURL` can detect and launch the YouTube app for deep-link playback.
- No `NSAppTransportSecurity` exceptions — **all** network + image traffic is HTTPS
  (Railway API, `image.tmdb.org`, `i.ytimg.com`, `m.media-amazon.com`). Do **not**
  add ATS exceptions; if any stored poster URL is `http://`, fix the data, not ATS.
- No camera/location/mic/contacts usage → no `NS*UsageDescription` keys needed.
- App is landscape-only (a TV-style layout) via `INFOPLIST_KEY_UISupportedInterfaceOrientations_*`.

**`iOS/MovieBoxZ/PrivacyInfo.xcprivacy`** (Apple Privacy Manifest, required):

- `NSPrivacyTracking = false`, `NSPrivacyTrackingDomains = []`.
- `NSPrivacyCollectedDataTypes = []` — nothing collected/linked to identity.
- `NSPrivacyAccessedAPITypes`: `NSPrivacyAccessedAPICategoryUserDefaults` with
  reason **`CA92.1`** (app-only storage for favorites/watch history). ← accurate;
  add more Required-Reason entries only if new APIs (e.g. file timestamp, disk
  space) get used.

---

## 6. Remaining action items before submission (human)

These are outside the codebase and must be done in App Store Connect / on the web:

1. **Host the legal pages** referenced in Settings (currently placeholder URLs):
   - `https://movieboxz.app/privacy` — Privacy Policy. Must state: no account, no
     personal data collected, on-device-only storage, **use of YouTube API
     Services**, and a link to the **Google Privacy Policy**. Also mention TMDB/OMDb.
   - `https://movieboxz.app/terms` — Terms of Service.
   - `https://movieboxz.app/help` — Help/FAQ.
   These must be live and reachable **before** review, and the Privacy Policy URL
   must also be entered in App Store Connect.
2. **App Privacy "nutrition label"** in App Store Connect → set **Data Not
   Collected** (matches the Privacy Manifest).
3. **Age rating** questionnaire — the catalog is general/classic film + curated
   kids content; answer honestly. Because content is third-party (YouTube), set the
   web-content/unrestricted-web answer appropriately (playback opens YouTube).
4. **Export compliance** — with `ITSAppUsesNonExemptEncryption=false` set, no
   annual documentation is required; confirm "uses standard encryption only".
5. **TMDB logo** — add the TMDB logo asset beside the attribution text (see §4).
6. **Screenshots & metadata** — provide required device screenshots; keep the App
   Store description aligned with `APP_STORE_DESCRIPTION.md` and avoid implying we
   host video.
7. **Demo/reviewer notes** — tell App Review that playback deep-links to the
   YouTube app; if a device lacks the YouTube app it falls back to
   `youtube.com` in Safari (so review works without the YouTube app installed).
8. **Content-rights note (5.2.3)** — be ready to state in Review Notes that all
   videos are publicly available on YouTube and play within YouTube under its ToS;
   MovieBoxZ is a discovery/index layer only.

---

## 7. Pre-flight checklist

- [x] Info.plist: display name, export-compliance flag, YouTube query schemes
- [x] Privacy Manifest present & accurate (no tracking, no collection, CA92.1)
- [x] In-app YouTube ToS link + playback disclaimer + "does not host video" copy
- [x] TMDB / OMDb attribution text in Settings
- [x] No ATS exceptions; all traffic HTTPS
- [x] No IAP / external payment; free app
- [ ] Privacy Policy / Terms / Help pages live at movieboxz.app (+ Google Privacy Policy link inside)
- [ ] Privacy Policy URL entered in App Store Connect; App Privacy = Data Not Collected
- [ ] Age rating questionnaire completed
- [ ] TMDB logo asset added beside attribution
- [ ] Screenshots + reviewer notes (deep-link + Safari fallback) prepared
