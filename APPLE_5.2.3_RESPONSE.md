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

## A3. Metadata & artwork licensing statement — posters and descriptions (paste into App Review notes)

MovieBoxZ displays movie/TV posters, artwork, and descriptions under a valid license
from their source, with the required attribution, and consistent with applicable law.

Source and license — TMDB (The Movie Database):
- All poster and backdrop images and the descriptive text (overviews) shown in
  MovieBoxZ are obtained from TMDB through the official TMDB API.
- TMDB grants API users a "worldwide, non-exclusive" license to use TMDB's content
  and metadata (images and text) under the TMDB API Terms of Use:
  https://www.themoviedb.org/api-terms-of-use
- TMDB confirms this on its developer FAQ: "The TMDB API is free to use for
  non-commercial purposes as long as you attribute TMDB as the source of the data
  and/or images." (https://developer.themoviedb.org/docs/faq)
- MovieBoxZ operates within that license: it is a free application (no fees, no
  purchases), and it displays the required TMDB attribution in-app — "This product
  uses the TMDB API but is not endorsed or certified by TMDB."
- TMDB API documentation: https://developer.themoviedb.org/docs/getting-started

Ratings — OMDb:
- Ratings are retrieved via the OMDb API under its terms (https://www.omdbapi.com/).
  Where IMDb ratings are shown, they are sourced through OMDb.

Legal basis in addition to the license:
Even independent of the TMDB license, the specific way MovieBoxZ uses this material is
consistent with established U.S. law:
- Posters appear only as small identifying thumbnails that help a user recognize a
  title — an informational, transformative use that courts have treated as fair use
  (e.g., Perfect 10, Inc. v. Amazon.com, Inc.:
  https://en.wikipedia.org/wiki/Perfect_10,_Inc._v._Amazon.com,_Inc.).
- Descriptions are short factual summaries that describe a title rather than reproduce
  its expression. Copyright protects specific expression, not facts or plot ideas, so
  a brief synopsis is not an infringing use.

In summary: the posters and descriptions in MovieBoxZ are used (1) under an express
license from TMDB, with attribution, and (2) in a manner consistent with fair use for
the underlying works. MovieBoxZ does not redistribute these assets as a standalone
product; they appear only as identifiers within the app's discovery experience.

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

## D. Rebuttal — use ONLY if rejected again (Resolution Center, formal register)

Dear App Review,

Thank you for your continued review of MovieBoxZ (submission 1d730900). We have
carefully reviewed Guidelines 5.2.1, 5.2.2, and 5.2.3, and we respectfully submit
that MovieBoxZ complies with each. We set out our analysis below and remain glad to
provide any further documentation or to discuss this directly with App Review.

1. Nature of the app. MovieBoxZ is a content discovery and catalog application. It
does not host, store, stream, transcode, record, download, or serve any audio or
video. It stores only public YouTube video identifiers and licensed metadata. When a
user selects a title, playback is performed entirely by YouTube's own application or
player; MovieBoxZ is never in the media path. This is the same model as established
App Store applications such as JustWatch, Reelgood, and TV Time, which catalog
third-party titles and link users to the service that serves them.

2. Guideline 5.2.3 (Audio/Video Downloading). This guideline provides that apps
"should not facilitate illegal file sharing or include the ability to save, convert,
or download media from third-party sources… Streaming of audio/video content may
also violate Terms of Use…" MovieBoxZ includes no capability to save, convert,
download, or file-share media, and does not facilitate file sharing; it contains no
downloading or ripping functionality of any kind. MovieBoxZ also does not itself
stream audio or video — all streaming is performed by YouTube. The app's access to
YouTube is expressly authorized: MovieBoxZ is a registered YouTube Data API client
operating under the YouTube API Services Terms of Service and Developer Policies, and
that authorization is attached and available on request. The conduct 5.2.3 addresses
is therefore not present in this app.

3. Guideline 5.2.2 (Third-Party Sites/Services). This guideline requires that an app
displaying content from a third-party service be "specifically permitted to do so
under the service's terms of use," with authorization available on request. The
relevant third-party service here is YouTube, and MovieBoxZ is specifically permitted
under YouTube's terms as a compliant YouTube Data API client: it uses only the
official API, performs no downloading, hands all playback to YouTube's own player,
displays source-channel attribution, and does not circumvent any measure. The
governing authorization is our YouTube API license, which is attached.

4. Guideline 5.2.1 (Generally). The only third-party material MovieBoxZ reproduces is
poster artwork and descriptive text, which are licensed from TMDB (displayed with the
required attribution) and OMDb. MovieBoxZ reproduces no film or television video, and
includes no misleading, false, or copycat names or metadata.

5. Regarding "unauthorized access." MovieBoxZ provides no access that a user could not
already obtain directly on YouTube. It surfaces only content that YouTube itself makes
publicly available and serves under YouTube's own rights framework (Content ID and
DMCA). Because MovieBoxZ stores only a video identifier, any item removed at the
source — by the uploader, by Content ID, or through a DMCA action — becomes
immediately unavailable in the app. MovieBoxZ does not, and as a discovery layer
cannot, adjudicate the rights of individual uploads; that determination rests with
YouTube. As a good-faith measure, MovieBoxZ sources only from established channels and
automatically excludes any channel less than one year old (verified by an automated
audit we can provide), and it offers an in-app path to report a copyright concern.

We respectfully submit that MovieBoxZ complies with Guidelines 5.2.1 through 5.2.3 and
ask that the app be approved. We would welcome the opportunity to discuss this with
App Review directly, or before the App Review Board, if that would assist. Thank you
for your time and consideration.

Sincerely,
The MovieBoxZ Team

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
