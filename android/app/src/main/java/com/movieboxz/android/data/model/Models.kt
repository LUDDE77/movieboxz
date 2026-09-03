package com.movieboxz.android.data.model

import com.squareup.moshi.Json

/**
 * Movie — mirrors the iOS `Movie` model / the backend movies row.
 * All JSON keys are snake_case (matching the iOS CodingKeys). Nullable fields
 * stay nullable so one dirty row can never blank a whole list.
 */
data class Movie(
    val id: String = "",
    @Json(name = "youtube_video_id") val youtubeVideoId: String = "",
    val title: String = "",
    @Json(name = "youtube_video_title") val youtubeVideoTitle: String? = null,
    val description: String? = null,
    @Json(name = "release_date") val releaseDate: String? = null,   // ISO string
    @Json(name = "runtime_minutes") val runtimeMinutes: Int? = null,
    @Json(name = "channel_id") val channelId: String? = null,
    @Json(name = "channel_title") val channelTitle: String? = null,
    @Json(name = "poster_path") val posterPath: String? = null,
    @Json(name = "backdrop_path") val backdropPath: String? = null,
    @Json(name = "hero_image_url") val heroImageUrl: String? = null,
    @Json(name = "vote_average") val voteAverage: Double? = null,
    @Json(name = "imdb_rating") val imdbRating: Double? = null,
    @Json(name = "imdb_id") val imdbId: String? = null,
    @Json(name = "view_count") val viewCount: Int? = null,
    val rated: String? = null,
    val genres: List<Genre>? = null,
    @Json(name = "is_available") val isAvailable: Boolean = true,
    @Json(name = "is_tv_series") val isTvSeries: Boolean? = null,
    @Json(name = "tv_series_id") val tvSeriesId: String? = null,
    @Json(name = "original_title") val originalTitle: String? = null,
    @Json(name = "season_number") val seasonNumber: Int? = null,
    @Json(name = "episode_number") val episodeNumber: Int? = null,
) {
    /** TMDB title, falling back to the raw YouTube title if empty. */
    val displayTitle: String
        get() = title.trim().ifEmpty { youtubeVideoTitle ?: "" }

    val releaseYear: String?
        get() = releaseDate?.takeIf { it.length >= 4 }?.substring(0, 4)

    val ratingText: String?
        get() = (voteAverage ?: imdbRating)?.let { "%.1f".format(it) }

    val runtimeText: String?
        get() = runtimeMinutes?.let { m ->
            val h = m / 60; val min = m % 60
            if (h > 0) "${h}h ${min}m" else "${min}m"
        }
}

data class Genre(
    val id: Int,
    val name: String,
    @Json(name = "movie_count") val movieCount: Int? = null,
)

data class TVSeries(
    val id: String,
    val title: String,
    val description: String? = null,
    @Json(name = "poster_path") val posterPath: String? = null,
    @Json(name = "year_start") val yearStart: Int? = null,
    @Json(name = "year_end") val yearEnd: Int? = null,
    @Json(name = "episode_count") val episodeCount: Int? = null,
    @Json(name = "season_count") val seasonCount: Int? = null,
) {
    /** "1992–1998", "1992–", or "1992". */
    val yearRange: String?
        get() = yearStart?.let { s ->
            if (yearEnd != null && yearEnd != s) "$s–$yearEnd" else if (yearEnd == null) "$s–" else "$s"
        }
}

// ---- TV series envelopes -----------------------------------------------------

/** GET /series — the TV Series tab list. */
data class SeriesListResponse(val data: SeriesListData)
data class SeriesListData(val series: List<TVSeries> = emptyList(), val pagination: Pagination? = null)

/** GET /series/{id}/episodes — the series' seasons, each with its episodes. */
data class SeriesEpisodesResponse(val data: SeriesEpisodesData)
data class SeriesEpisodesData(val series: TVSeries? = null, val seasons: List<Season> = emptyList())
data class Season(
    @Json(name = "seasonNumber") val seasonNumber: Int = 0,
    val episodes: List<Movie> = emptyList(),
)

// ---- API envelopes -----------------------------------------------------------

data class MoviesResponse(val success: Boolean = true, val data: MoviesData)

data class MoviesData(
    val movies: List<Movie> = emptyList(),
    val pagination: Pagination? = null,
    val total: Int? = null,
)

data class Pagination(val page: Int = 1, val limit: Int = 20, val total: Int? = null, val pages: Int? = null)

/** GET /movies/{id} — `data` is the movie itself (matches the iOS decode). */
data class MovieDetailResponse(val success: Boolean = true, val data: Movie)

/** GET /browse/home — the whole Browse tab in one response. */
data class BrowseHomeResponse(val data: BrowseHomeData)

data class BrowseHomeData(
    val featured: List<Movie> = emptyList(),
    val popular: List<Movie> = emptyList(),
    val trending: List<Movie> = emptyList(),
    val recent: List<Movie> = emptyList(),
    @Json(name = "topImdb") val topImdb: List<Movie> = emptyList(),
    val genres: List<GenreCarousel> = emptyList(),
    val eras: Eras? = null,
)

data class GenreCarousel(val genre: Genre, val movies: List<Movie> = emptyList())

data class Eras(
    val modern: List<Movie> = emptyList(),
    @Json(name = "eighties90s") val eighties90s: List<Movie> = emptyList(),
    @Json(name = "sixties70s") val sixties70s: List<Movie> = emptyList(),
    val classic: List<Movie> = emptyList(),
)

/** A titled horizontal rail for the browse UI. */
data class MovieRail(val title: String, val movies: List<Movie>)
