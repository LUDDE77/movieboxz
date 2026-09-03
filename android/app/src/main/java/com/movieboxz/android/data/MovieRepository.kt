package com.movieboxz.android.data

import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.MovieRail
import com.movieboxz.android.data.model.SeriesEpisodesData
import com.movieboxz.android.data.model.TVSeries
import com.movieboxz.android.data.remote.ApiClient
import com.movieboxz.android.data.remote.MovieApi

/**
 * Single source of truth for movie data — mirrors the iOS `MovieService`.
 * Turns the one-shot /browse/home response into the ordered list of titled
 * rails the Browse screen renders.
 */
class MovieRepository(private val api: MovieApi = ApiClient.create()) {

    /** Featured carousel items (first non-empty of featured/trending). */
    suspend fun featured(): List<Movie> {
        val home = api.browseHome().data
        return home.featured.ifEmpty { home.trending }.filter { it.isAvailable }
    }

    /** The ordered browse rails, built from the single /browse/home call. */
    suspend fun browseRails(): List<MovieRail> {
        val h = api.browseHome().data
        val rails = mutableListOf<MovieRail>()
        fun add(title: String, movies: List<Movie>, categoryId: String? = null) {
            val avail = movies.filter { it.isAvailable }
            if (avail.isNotEmpty()) rails += MovieRail(title, avail, categoryId)
        }
        add("Trending", h.trending, "trending")
        add("Popular", h.popular, "popular")
        add("Recently Added", h.recent, "recent")
        add("Top IMDb", h.topImdb, "top-imdb")
        h.eras?.let {
            // Eras have no dedicated endpoint → no See-all.
            add("Modern", it.modern)
            add("80s & 90s", it.eighties90s)
            add("60s & 70s", it.sixties70s)
            add("Classics", it.classic)
        }
        h.genres.forEach { add(it.genre.name, it.movies, "g${it.genre.id}") }
        return rails
    }

    /** Load the full list for a "See all" — [categoryId] is "g{genreId}" or a
     *  category key ("trending"/"popular"/"recent"/"top-imdb"). */
    suspend fun category(categoryId: String): List<Movie> {
        val movies = when {
            categoryId.startsWith("g") -> return moviesByGenre(categoryId.removePrefix("g").toInt())
            categoryId == "trending" -> api.trending(limit = 60).data.movies
            categoryId == "popular" -> api.popular(limit = 60).data.movies
            categoryId == "recent" -> api.recent(limit = 60).data.movies
            categoryId == "top-imdb" -> api.topRated(limit = 60).data.movies
            else -> emptyList()
        }
        return movies.filter { it.isAvailable }
    }

    suspend fun search(query: String): List<Movie> =
        api.search(query).data.movies.filter { it.isAvailable }

    suspend fun movie(id: String): Movie = api.movie(id).data

    /** All TV series for the TV tab. */
    suspend fun series(): List<TVSeries> = api.series().data.series

    /** Kids-only TV series (episodes flagged kids content). */
    suspend fun kidsSeries(): List<TVSeries> = api.series(kids = "true").data.series

    /** Movies in one genre (e.g. Family=10751, Animation=16) for the Kids rows. */
    suspend fun moviesByGenre(genreId: Int): List<Movie> =
        api.moviesByGenre(genreId).data.movies.filter { it.isAvailable }

    /** A series' header + seasons (each with its available episodes). */
    suspend fun seriesEpisodes(id: String): SeriesEpisodesData {
        val d = api.seriesEpisodes(id).data
        val seasons = d.seasons
            .map { s -> s.copy(episodes = s.episodes.filter { it.isAvailable }) }
            .filter { it.episodes.isNotEmpty() }
            .sortedBy { it.seasonNumber }
        return d.copy(seasons = seasons)
    }
}
