# MovieBoxZ — Android (standalone)

A **standalone** native Android client for MovieBoxZ. It is completely independent
of the iOS/tvOS app (which is never touched) and talks to the **same backend**:
`https://movieboxz-backend-production.up.railway.app/api`.

Stack: **Kotlin + Jetpack Compose**, Retrofit + Moshi, Coil, Navigation-Compose.
MVVM — mirrors the iOS structure (Models / Services → data + repository, Views → Compose).

## Run it
1. Open the `android/` folder in **Android Studio** (Ladybug or newer).
2. Let it sync Gradle (it will create the Gradle wrapper automatically). JDK 17.
3. Run the `app` config on an emulator or device (min SDK 24 / Android 7).

That's it — no keys to set. The region is sent automatically from the device
locale via the `X-Country` header, exactly like the iOS app.

## What's here (Phase 1 MVP)
- **Browse** (`/browse/home` in one call) → featured strip + genre/era/trending rails
- **Movie detail** → backdrop, metadata, description
- **Watch** → deep-links to the YouTube app (`vnd.youtube:ID`) with a web fallback
- **Region-aware** via `X-Country` (device locale, overridable through `ApiClient.regionOverride`)
- Cinema **gold/ink theme** matching the iOS look

## Map to the iOS app
| iOS | Android |
|---|---|
| `MovieService` | `data/remote/MovieApi` + `data/MovieRepository` |
| `Movie` / `TVSeries` models | `data/model/Models.kt` (snake_case via `@Json`) |
| `X-Country` header | `data/remote/RegionInterceptor` |
| `WatchCoordinator` / `YouTubePlayerService` | `util/YouTubeLauncher` |
| poster/backdrop URL logic | `util/ImageUrls` |
| `MainBrowseView` | `ui/browse/BrowseScreen` |
| `MovieDetailView` | `ui/detail/MovieDetailScreen` |

## Next (from the plan)
- **Phase 2:** Search (`/movies/search`), Library/Favorites (Room), TV Series, Settings, region picker.
- **Phase 3:** **Android TV** target (Compose for TV — D-pad focus) from this same codebase.
- **Phase 4:** Google Play listing (reuse `CONTENT_SOURCING_POLICY.md`), phased rollout.

## Notes
- Analytics needs nothing new: the same endpoints feed the backend `usageTracker`.
  Add `platform=android` to requests when you want to split platforms in reports.
- JSON parsing is reflection-based (Moshi `KotlinJsonAdapterFactory`) so there's no
  KSP/codegen step to configure. If you later want faster startup, switch to
  `moshi-kotlin-codegen` + `@JsonClass(generateAdapter = true)`.
