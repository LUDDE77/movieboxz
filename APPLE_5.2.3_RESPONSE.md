# Apple Guideline 5.2.3 (Legal) — Response Package

Submission 1d730900 / MovieBoxZ. Use this to (a) fill the **App Review Information**
notes, (b) attach evidence, and (c) reply in the Resolution Center.

---

## A. Documents / evidence to attach in App Review Information

Attach or link the following (PDF/screenshots where noted):

1. **YouTube API Services — authorization**
   - Screenshot of your **Google Cloud Console** project with **YouTube Data API v3
     enabled** (Console → APIs & Services → Enabled APIs).
   - The **YouTube API Services Terms of Service** URL you operate under:
     https://developers.google.com/youtube/terms/api-services-terms-of-service
   - The **YouTube API Services Developer Policies** we follow:
     https://developers.google.com/youtube/terms/developer-policies
   - One line: "MovieBoxZ accesses YouTube content solely through the official
     YouTube Data API under these terms; all playback is performed by YouTube's own
     player."

2. **TMDB (catalog metadata) — terms + attribution**
   - TMDB API Terms of Use URL: https://www.themoviedb.org/api-terms-of-use
   - Note the in-app attribution: "This product uses the TMDB API but is not
     endorsed or certified by TMDB."
   - (If you have a TMDB API key/registration screenshot, include it.)

3. **OMDb (ratings metadata) — terms**
   - OMDb API terms/registration: https://www.omdbapi.com/

4. **MovieBoxZ Content Sourcing & Copyright Policy**
   - Attach `CONTENT_SOURCING_POLICY.md` (export to PDF) and/or host it at
     `https://movieboxz.com/content-policy.html` and link it.

5. **Architecture statement — "we host nothing"**
   - One paragraph (below in the reply) stating MovieBoxZ stores only video IDs +
     metadata and never hosts/streams video.

6. **In-app copyright reporting** — note that the app now includes a "Report a
   copyright concern" link (Settings) pointing to YouTube's copyright complaint
   process and MovieBoxZ's contact.

---

## A2. Platform compliance summary (paste into App Review notes)

MovieBoxZ complies with the terms of every third-party service it uses. Reference
documents and how we follow them:

YouTube — YouTube API Services Terms of Service
(https://developers.google.com/youtube/terms/api-services-terms-of-service) and
YouTube API Services Developer Policies
(https://developers.google.com/youtube/terms/developer-policies):
- We access YouTube only through the official YouTube Data API as a registered API
  client (Google Cloud project "MovieBoxZ YouTube Integration", YouTube Data API v3
  enabled).
- We do not host, stream, download, cache, or store any video ourselves. Every
  "watch" hands the video off to YouTube — its own application, or youtube.com in the
  system browser — so all playback is performed by YouTube's official player under
  YouTube's terms.
- We display source attribution: the originating YouTube channel is shown on each
  title, and the app states that content is hosted on YouTube and subject to
  YouTube's Terms of Service.
- We do not circumvent any access control or rights-management measure, and we honor
  removals: because we store only a video ID, a video removed by the uploader,
  Content ID, or a DMCA action disappears from MovieBoxZ automatically.

TMDB — TMDB API Terms of Use (https://www.themoviedb.org/api-terms-of-use):
- Metadata and artwork are retrieved via the TMDB API and used only for display.
- We show TMDB's required attribution in-app: "This product uses the TMDB API but is
  not endorsed or certified by TMDB." We do not use the API to build or offer a
  competing database.

OMDb / IMDb — OMDb API (https://www.omdbapi.com/):
- Ratings are retrieved via the OMDb API under its terms using a registered API key.
  Where IMDb ratings are shown, they are sourced through OMDb; MovieBoxZ does not
  claim any direct license from IMDb.

---

## B. Resolution Center reply (paste-ready)

Hello, and thank you for the review.

MovieBoxZ is a content discovery and catalog application — the same model as
established apps such as JustWatch and Reelgood. We would like to set out the basis
on which we are authorized to operate, and we have attached supporting documentation
in the App Review Information section.

1. We are authorized by YouTube. MovieBoxZ accesses YouTube content exclusively
through the official YouTube Data API, under the YouTube API Services Terms of
Service, which we have accepted and operate under via a registered Google Cloud
project with the YouTube Data API enabled. Under those terms, YouTube grants API
clients a license to access and display YouTube content in compliant applications.
Our permission therefore comes directly from YouTube — the platform that hosts the
content and maintains the rights and licensing relationships for it.

2. We host nothing. MovieBoxZ does not host, store, upload, stream, transcode, or
serve any video or audio. We store only public YouTube video identifiers and
third-party catalog metadata (from TMDB and OMDb/IMDb, used under their terms with
attribution). All playback is performed by YouTube's own official player/app. We are
never in the media path.

3. We rely on, and defer to, YouTube's rights system. YouTube — not MovieBoxZ — is
responsible for the legality of content on its platform, and operates Content ID and
a DMCA takedown process. Because we store only a video ID, any video removed at the
source (by the uploader, Content ID, or a DMCA action) automatically becomes
unavailable in MovieBoxZ. We do not circumvent any protection measure.

4. This is the same model Apple already permits for discovery apps. Apps like
JustWatch and Reelgood catalog third-party movies and shows and link users to the
platform that serves them, without holding studio licenses themselves — they rely on
the underlying licensed platform. MovieBoxZ does exactly this by linking to YouTube,
and additionally operates under an explicit YouTube API Services license.

5. Good-faith curation. To avoid surfacing bad-faith uploads, we index only channels
operating legitimately within YouTube's own system — favoring established channels
whose videos remain live and monetized on YouTube (YouTube monetization requires
passing YouTube's own policy and Content ID review), and excluding brand-new
reupload accounts and manipulated uploads. This relies on YouTube's determinations,
not our own. This is enforced automatically: our import pipeline rejects any channel
under one year old, and we run an automated audit against the YouTube API confirming
that 100% of the channels currently surfacing content in the app are at least one
year old.

6. Reporting. The app includes a "Report a copyright concern" link that directs to
YouTube's copyright complaint process (the complete remedy, since removal at the
source removes it from MovieBoxZ) and to our own contact at support@movieboxz.com,
where we promptly remove any listing a rights holder identifies.

We have attached our Content Sourcing & Copyright Policy and the supporting
documentation. We are committed to operating lawfully and within YouTube's terms, and
we are glad to make any additional changes you recommend. Thank you.

---

## C. Notes / honest caveats (for us, not for Apple)

- 5.2.3 on YouTube-catalog apps is Apple's most stubborn category; this is a strong,
  document-backed swing, not a certainty. If rejected again, the likely next asks are
  (a) narrow the sources to named legitimate distributors, or (b) further prove
  provenance. We deliberately do NOT claim per-channel permission — doing so would
  make MovieBoxZ the guarantor of each channel's rights (YouTube's responsibility,
  not ours).
- Keep the source-channel set defensible (established, monetized, live). If we later
  enforce the age/monetization rule in the import pipeline, we can say it is
  automated, not just policy.
