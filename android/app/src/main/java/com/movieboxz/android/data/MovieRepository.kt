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
        fun add(title: String, movies: List<Movie>) {
            val avail = movies.filter { it.isAvailable }
            if (avail.isNotEmpty()) rails += MovieRail(title, avail)
        }
        add("Trending", h.trending)
        add("Popular", h.popular)
        add("Recently Added", h.recent)
        add("Top IMDb", h.topImdb)
        h.eras?.let {
            add("Modern", it.modern)
            add("80s & 90s", it.eighties90s)
            add("60s & 70s", it.sixties70s)
            add("Classics", it.classic)
        }
        h.genres.forEach { add(it.genre.name, it.movies) }
        return rails
    }

    suspend fun search(query: String): List<Movie> =
        api.search(query).data.movies.filter { it.isAvailable }

    suspend fun movie(id: String): Movie = api.movie(id).data

    /** All TV series for the TV tab. */
    suspend fun series(): List<TVSeries> = api.series().data.series

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
