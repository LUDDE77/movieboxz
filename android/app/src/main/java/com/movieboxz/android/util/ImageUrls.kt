package com.movieboxz.android.util

import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.TVSeries

/**
 * Image URL logic, ported 1:1 from the iOS `Movie` computed properties:
 * a full http(s) path is used as-is (OMDb), a relative path is a TMDB path,
 * and the last-resort fallback is the YouTube thumbnail.
 */
object ImageUrls {
    private const val TMDB = "https://image.tmdb.org/t/p"

    fun poster(m: Movie): String? {
        m.posterPath?.let { return if (it.startsWith("http")) it else "$TMDB/w342$it" }
        return youtubeThumb(m.youtubeVideoId)
    }

    fun backdrop(m: Movie): String? {
        m.backdropPath?.let { return if (it.startsWith("http")) it else "$TMDB/w1280$it" }
        return youtubeThumb(m.youtubeVideoId)
    }

    /** Featured hero: admin-picked image, else real backdrop, else poster. */
    fun hero(m: Movie): String? = m.heroImageUrl ?: backdrop(m)

    fun seriesPoster(s: TVSeries): String? =
        s.posterPath?.let { if (it.startsWith("http")) it else "$TMDB/w342$it" }

    private fun youtubeThumb(videoId: String): String? =
        videoId.takeIf { it.isNotBlank() }?.let { "https://img.youtube.com/vi/$it/hqdefault.jpg" }
}
