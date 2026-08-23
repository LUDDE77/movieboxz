# MovieBoxZ — Content Sourcing & Copyright Policy

_Last updated: July 2026_

MovieBoxZ is a content **discovery and catalog** application. This policy explains
what MovieBoxZ is, how it sources what it displays, the authorization under which
it operates, and how rights holders can raise a concern.

---

## 1. What MovieBoxZ is (and is not)

MovieBoxZ **does not host, store, upload, stream, transcode, record, or serve any
video or audio.** It holds no media files.

MovieBoxZ stores only:
- **Public YouTube video identifiers** (the video ID) and public listing metadata.
- **Third-party catalog metadata** (titles, synopses, artwork, ratings) obtained
  from TMDB and OMDb/IMDb under their terms.

All playback is performed by **YouTube's own official application and player.** When
a user chooses to watch a title, MovieBoxZ hands off to the YouTube app (or, where
that app is unavailable, to youtube.com in the device browser, or — on Apple TV —
to the user's phone via a QR code). MovieBoxZ is never in the media path.

MovieBoxZ is, in structure, an **index and discovery layer** — comparable to a
search engine or a streaming guide — that helps users find and open publicly
available content on YouTube.

---

## 2. Our authorization to surface YouTube content

MovieBoxZ accesses YouTube content **exclusively through the official YouTube Data
API**, under the **YouTube API Services Terms of Service**
(https://developers.google.com/youtube/terms/api-services-terms-of-service),
which MovieBoxZ has accepted and operates under via a registered Google Cloud
project with the YouTube Data API enabled.

Under those terms, YouTube grants API clients a license to access and display
YouTube content within compliant applications. MovieBoxZ:
- uses only the official, documented API to retrieve public listing data;
- performs all playback through YouTube's own player/app;
- does not download, copy, cache, or re-host any video stream.

In short: **our permission to surface this content comes from YouTube itself**, the
platform that hosts it and that maintains the rights and licensing relationships
for it.

---

## 3. Reliance on YouTube's rights infrastructure

YouTube — not MovieBoxZ — is responsible for the rights and legality of the content
it hosts and serves. YouTube operates:
- **Content ID**, its automated rights-management and matching system, and
- a **DMCA / copyright takedown** process for rights holders.

Because MovieBoxZ stores only a YouTube video ID and never a copy of any media, if
a video is removed at the source — by the uploader, by Content ID, or by a DMCA
action — it **immediately and automatically becomes unavailable in MovieBoxZ.**
There is nothing for MovieBoxZ to separately serve, cache, or take down.

MovieBoxZ does not circumvent, disable, or interfere with any technical protection,
access control, or rights-management measure on YouTube or any other service.

---

## 4. Good-faith curation criteria

To avoid surfacing obviously infringing uploads, MovieBoxZ indexes videos only from
channels that operate **legitimately within YouTube's own system.** We favor
signals that reflect **YouTube's** determinations rather than our own judgment of
any party's rights:

- **The video is live and, where applicable, monetized on YouTube.** YouTube
  monetization requires a channel to pass YouTube's own policy and Content ID
  review, so an ad-supported, still-live video reflects YouTube's clearance.
- **Established channels.** We favor channels that are generally **at least one year
  old**, with a substantial, consistent catalog and clear branding — i.e., genuine
  distributor or creator operations.
- **Verified affiliates of an established channel family.** We also accept a **newer
  channel (under one year old) when it is owned by, or affiliated with, an established
  operator** — that is, the operator runs one or more **other channels older than two
  years** that share the same ownership, branding, and catalog, and that operate
  legitimately within YouTube's system. In that case we rely on the **family's
  established, compliant track record** rather than the individual channel's age. We
  record the affiliated older channel(s) as the basis for including the newer one.
- **Exclusion of bad-faith accounts.** We exclude channels that show signs of
  evading YouTube's systems — unaffiliated brand-new reupload accounts, mislabeled or
  manipulated uploads, and similar red flags.

This is a good-faith effort. It **relies on YouTube's determinations** and does not
constitute a warranty by MovieBoxZ of any channel's or work's rights.

---

## 5. Metadata and catalog sources

Movie and television information and artwork are provided by:
- **TMDB (The Movie Database)** via the TMDB API, used under the TMDB API Terms of
  Use with the required attribution: _"This product uses the TMDB API but is not
  endorsed or certified by TMDB."_
- **OMDb / IMDb** rating and metadata, used under their respective terms.

MovieBoxZ displays this attribution in-app.

---

## 6. Comparable services

MovieBoxZ operates on the same model as established, widely-distributed discovery
applications such as **JustWatch** and **Reelgood**: it catalogs third-party
content and links users to the platform that actually serves that content, without
hosting content itself and without holding studio licenses of its own. Those apps
rely on the underlying, licensed destination platform. MovieBoxZ does the same by
linking to YouTube — and, additionally, operates under an **explicit YouTube API
Services license.**

---

## 7. Reporting a copyright concern

MovieBoxZ provides an in-app link to report a copyright concern.

Because **MovieBoxZ hosts no content**, the most effective and complete remedy is to
report the underlying video to **YouTube**, which will remove it at the source —
after which it automatically disappears from MovieBoxZ:
- YouTube copyright complaint: https://www.youtube.com/copyright_complaint_form
- YouTube copyright help: https://support.google.com/youtube/answer/2807622

Rights holders may also contact MovieBoxZ directly and we will promptly remove the
corresponding **listing** from the app:
- **support@movieboxz.com**

We respond to good-faith reports promptly and act to remove any listing a rights
holder identifies.
