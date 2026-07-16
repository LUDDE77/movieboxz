# App Store screenshots — shot list (MovieBoxZ)

A single 6-shot story, captured on each required device. Shots 1–4 are the
must-haves; 5–6 are strong extras (up to 10 allowed per device). Keep the same
order and captions across devices so the listing feels cohesive.

## Required sizes (App Store Connect)
| Device | Pixel size | Notes |
|---|---|---|
| iPhone 6.7"/6.9" | 2796 × 1290 (landscape) | REQUIRED. Capture in landscape — that's how the app runs. iPhone 15/16 Pro Max. |
| iPad Pro 12.9" | 2732 × 2048 (landscape) | Required because the app supports iPad. |
| Apple TV | 3840 × 2160 (or 1920 × 1080) | Required for the tvOS app. 16:9. |

Min 1 per device; 3–5 recommended. Captions are optional overlays but strongly
lift conversion — keep them short, high-contrast, top or bottom third.

## Stage the data first (do this before capturing)
- In the **Hero Builder**, set a clean landscape backdrop for the first few
  featured movies so the hero looks premium (avoid poster-only heroes on shot 1).
- Favorite ~6–8 movies so the **Library / My List** shot isn't empty.
- Open one movie with a good backdrop + full metadata for the **detail** shot.
- Make sure rows are populated (fresh catalog load) so nothing is mid-loading.

---

## The 6 shots

### 1 — Hero / Browse  ⭐ (your lead image)
- **Screen:** Browse tab, hero carousel on a movie with a strong landscape
  backdrop, "Popular Movies" row visible beneath.
- **Caption:** “Thousands of free classic movies.”

### 2 — Browse by era / genres  ⭐
- **Screen:** Browse scrolled to the decade rows (Modern Cinema / 80s & 90s /
  60s & 70s / Classic Cinema) or the genre rails + High Score IMDb.
- **Caption:** “Browse by era, genre and IMDb score.”

### 3 — Movie detail  ⭐
- **Screen:** A movie detail page — backdrop, poster, synopsis, rating, the
  “Watch on YouTube” button.
- **Caption:** “One tap to watch — free, in the app that hosts it.”

### 4 — TV Series  ⭐
- **Screen:** The Series tab (or a series detail with seasons/episodes).
- **Caption:** “Full TV series, properly organized.”

### 5 — Kids
- **Screen:** The Kids tab with cartoons / family films.
- **Caption:** “A safe corner for the whole family.”

### 6 — Living room / Apple TV (tvOS set) or Search+Library (iPhone/iPad)
- **tvOS:** the big cinematic hero. **Caption:** “Made for the living room.”
- **iPhone/iPad:** Search results or Library. **Caption:** “Find anything, save
  your favorites.” · “Free & private — no account, ever.”

---

## Capture tips
- Turn on airplane-mode clocks? No — instead, on device use a clean status bar.
  On the **iOS Simulator** the status bar is already clean (9:41). Simulators are
  the easiest way to get exact pixel sizes.
- iPhone/iPad: **Simulator → File → Save Screen** (or `xcrun simctl io <udid>
  screenshot out.png`). Rotate to landscape first (Cmd+→) so it matches the app.
- Apple TV: `xcrun simctl io <tvOS-udid> screenshot out.png` gives 3840×2160.
- Do NOT include the device frame — upload raw screenshots. If you want framed/
  captioned marketing images, tools like Screenshots.pro / Fastlane frameit, or
  a Figma/Keynote template, add the caption bars.
- Keep captions in the app's palette: ink background bar, gold or screen-white
  text, the Futura-style display font.

## Fastest path
I can auto-capture the raw **iPhone** and **Apple TV** frames from the
simulators (I already have both booted) — shots 1–5. You'd then add caption
overlays (or ship them raw; raw is allowed). iPad I can capture too if an iPad
sim is installed. Say the word.
