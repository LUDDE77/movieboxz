# MovieBoxZ — App Store Resubmission Checklist

Everything needed to resubmit build **1.0 (3)** and clear all five rejections. Work
top to bottom. Files referenced live in this repo unless noted.

---

## Rejection → fix map (what this submission covers)

| # | Guideline | Issue | Fixed by | Steps |
|---|-----------|-------|----------|-------|
| 1 | **2.3.7** | "free"/price words in name/subtitle | Metadata rewrite | 4 |
| 2 | **1.1.6** | Marketed as a free movie *service* | Description reframe | 4 |
| 3 | **4.1(a)** | Copyrighted posters in screenshots | Public-domain screenshots | 5 |
| 4 | **4.2.3(i)** | App required installing YouTube | Gate removed + tvOS QR fallback (**new binary**) | 3 |
| 5 | **5.2.3** | Rights to third-party content | Rights package + policy + enforcement + reply | 1, 2, 6, 7 |

Steps 1–3 need doing first (they produce things later steps attach/submit).

---

## Step 1 — Deploy the website  _(fixes 5.2.3 evidence)_

- [ ] Deploy the `website/` folder to movieboxz.com (same host as privacy.html).
- [ ] Confirm **https://movieboxz.com/content-policy** loads and looks right.
- [ ] Spot-check the nav "Content" link on privacy.html / terms.html.

_Why: gives Apple a public, clickable rights/policy page to cite in the reply._

---

## Step 2 — Gather evidence  _(fixes 5.2.3)_

- [ ] **Google Cloud Console screenshot** — Console → APIs & Services → *Enabled
      APIs* showing **YouTube Data API v3 enabled** on your project. Save as PNG/PDF.
      _(This is the single most important document — it is your authorization.)_
- [ ] Confirm **support@movieboxz.com** is monitored (Apple may test the report path).
- [ ] Export `CONTENT_SOURCING_POLICY.md` to PDF (or just link the live web page).
- [ ] (Optional but strong) Re-run the compliance audit and screenshot the result:
      `GET /api/admin/maintenance/channel-sourcing-audit` → shows 42/42 live sources
      compliant, 0 violations.

---

## Step 3 — Build & upload 1.0 (3)  _(fixes 4.2.3(i))_

This rejection required code changes, so a **new binary** is mandatory (the metadata/
screenshot fixes do not need one, but this does).

- [ ] In Xcode, confirm the build/version is **1.0 (3)** (bump the build number).
- [ ] Archive **iOS** → Distribute → Upload.
- [ ] Archive **tvOS** → Distribute → Upload.
- [ ] Wait for both builds to finish processing in App Store Connect.
- [ ] Attach build **1.0 (3)** to the version.

_What's in this build: welcome gate removed (app usable on launch, no YouTube
required); iOS falls back to Safari; Apple TV shows a QR to watch on phone when the
YouTube app is absent; Copyright section added to Settings; build number removed from
the splash screen._

---

## Step 4 — Update metadata  _(fixes 2.3.7 + 1.1.6)_

From `APP_STORE_LISTING.md`. In App Store Connect → the 1.0 version:

- [ ] **App Name:** `MovieBoxZ: Classic Film & TV`
- [ ] **Subtitle:** `Discover classic movies & TV`
- [ ] **Keywords:** `film noir,westerns,cult,sci-fi,retro,cinema,oldies,Hollywood,thriller,horror,drama,comedy,classictv`
- [ ] **Promotional Text:** (from listing file)
- [ ] **Description:** (full rewrite from listing file — the discovery-tool framing)
- [ ] **What's New:** the "build 1.0 (3)" notes from the listing file
- [ ] Double-check **no "free" / price words** remain in Name, Subtitle, or Keywords.

---

## Step 5 — Replace screenshots  _(fixes 4.1(a))_

From `~/Desktop/MovieBoxZ-Screenshots-v2/`. Delete the old sets, upload the new
public-domain ones into the matching slots:

- [ ] **iPhone 6.9"** → `iphone_6.9/` (2868×1320)
- [ ] **iPhone 6.7"** → `iphone_6.7/` (2796×1290) _(if the slot is shown)_
- [ ] **iPhone 6.5"** → `iphone_6.5/` (2778×1284) _(if the slot is shown)_
- [ ] **iPad 13"** → `ipad_13/` (2752×2064)
- [ ] **Apple TV** → `appletv/` (3840×2160)
- [ ] Confirm none of the uploaded images contain the word "free" or a copyrighted
      poster (they don't — public-domain only — but verify the slots after upload).

---

## Step 6 — App Review Information (notes + evidence)  _(fixes 5.2.3)_

In App Store Connect → the version → **App Review Information → Notes**:

- [ ] Paste the **"Notes for Reviewer"** block from `APP_STORE_LISTING.md`.
- [ ] Attach / link the evidence from Step 2:
  - Google Cloud screenshot (YouTube Data API v3 enabled)
  - YouTube API Services ToS URL
  - TMDB API terms URL + the in-app attribution line
  - OMDb terms URL
  - Content Sourcing Policy (PDF or https://movieboxz.com/content-policy link)
- [ ] Provide a demo note: browsing/search/library/detail all work with **no** other
      app installed; playback opens on YouTube (app, or Safari on iOS, or phone QR on
      Apple TV).

_(The exact attachment list is in `APPLE_5.2.3_RESPONSE.md` → section A.)_

---

## Step 7 — Resolution Center reply  _(fixes 5.2.3)_

- [ ] In the Resolution Center for submission **1d730900**, paste the **5.2.3 reply**
      from `APPLE_5.2.3_RESPONSE.md` → section B (the 6-point rights statement, with
      the JustWatch model and "our permission comes from YouTube").
- [ ] If it helps, also paste the earlier prepared replies for the prior guidelines
      (in `APP_STORE_LISTING.md`) so the reviewer sees every point addressed.

---

## Step 8 — Submit

- [ ] Version has: build 1.0 (3) attached, new metadata, new screenshots, review notes
      + evidence, Resolution Center reply posted.
- [ ] **Submit for Review.**

---

## After you submit — if 5.2.3 comes back again

5.2.3 on YouTube-catalog apps is Apple's most stubborn category; this is a strong,
document-backed swing but not a certainty. If it's rejected again, the likely next
ask is to **narrow sources to named legitimate distributors** or further prove
provenance. We deliberately do NOT claim per-channel permission (that would make us
the guarantor of each channel's rights — YouTube's responsibility, not ours). If it
gets there, re-open this and we'll iterate on the next move.

## Reference files
- `APP_STORE_LISTING.md` — name/subtitle/keywords/description/What's New + reviewer notes + prior replies
- `CONTENT_SOURCING_POLICY.md` / `website/content-policy.html` — the rights policy
- `APPLE_5.2.3_RESPONSE.md` — 5.2.3 reply + evidence checklist
- `~/Desktop/MovieBoxZ-Screenshots-v2/` — the public-domain screenshot sets
