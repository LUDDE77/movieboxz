package com.movieboxz.android.data.remote

import com.movieboxz.android.data.model.BrowseHomeResponse
import com.movieboxz.android.data.model.MovieDetailResponse
import com.movieboxz.android.data.model.MoviesResponse
import com.movieboxz.android.data.model.SeriesEpisodesResponse
import com.movieboxz.android.data.model.SeriesListResponse
import retrofit2.http.GET
import retrofit2.http.Path
import retrofit2.http.Query

/**
 * MovieBoxZ backend — the same endpoints the iOS `MovieService` calls.
 * The viewer's country is added automatically by [RegionInterceptor]
 * (X-Country header), so it's not a parameter here.
 */
interface MovieApi {

    @GET("browse/home")
    suspend fun browseHome(): BrowseHomeResponse

    @GET("movies/trending")
    suspend fun trending(@Query("page") page: Int = 1, @Query("limit") limit: Int = 20): MoviesResponse

    @GET("movies/popular")
    suspend fun popular(@Query("page") page: Int = 1, @Query("limit") limit: Int = 20): MoviesResponse

    @GET("movies/recent")
    suspend fun recent(@Query("page") page: Int = 1, @Query("limit") limit: Int = 20): MoviesResponse

    @GET("movies/top-rated")
    suspend fun topRated(
        @Query("source") source: String = "imdb",
        @Query("page") page: Int = 1,
        @Query("limit") limit: Int = 20,
    ): MoviesResponse

    @GET("movies/search")
    suspend fun search(
        @Query("q") query: String,
        @Query("page") page: Int = 1,
        @Query("limit") limit: Int = 40,
    ): MoviesResponse

    @GET("movies/category/{category}")
    suspend fun category(
        @Path("category") category: String,
        @Query("page") page: Int = 1,
        @Query("limit") limit: Int = 40,
    ): MoviesResponse

    @GET("movies/{id}")
    suspend fun movie(@Path("id") id: String): MovieDetailResponse

    @GET("series")
    suspend fun series(@Query("limit") limit: Int = 200): SeriesListResponse

    @GET("series/{id}/episodes")
    suspend fun seriesEpisodes(@Path("id") id: String): SeriesEpisodesResponse
}
