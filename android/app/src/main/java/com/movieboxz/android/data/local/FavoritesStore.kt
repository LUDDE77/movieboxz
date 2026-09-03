package com.movieboxz.android.data.local

import android.content.Context
import android.content.SharedPreferences
import com.movieboxz.android.data.model.Movie
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * The Android equivalent of the iOS `LibraryManager` — a local favorites list.
 * Persists the movies as JSON in SharedPreferences (via Moshi, already a
 * dependency) so the Library tab renders instantly and offline, no re-fetch.
 * Exposes a StateFlow so the UI reacts to add/remove immediately.
 *
 * Call [init] once from the Application before any UI reads it.
 */
object FavoritesStore {
    private lateinit var prefs: SharedPreferences
    private lateinit var adapter: com.squareup.moshi.JsonAdapter<List<Movie>>

    private val _favorites = MutableStateFlow<List<Movie>>(emptyList())
    val favorites: StateFlow<List<Movie>> = _favorites.asStateFlow()

    fun init(context: Context) {
        prefs = context.getSharedPreferences("mbz_favorites", Context.MODE_PRIVATE)
        val moshi = Moshi.Builder().add(KotlinJsonAdapterFactory()).build()
        val type = Types.newParameterizedType(List::class.java, Movie::class.java)
        adapter = moshi.adapter(type)
        _favorites.value = runCatching {
            prefs.getString("items", null)?.let { adapter.fromJson(it) }
        }.getOrNull() ?: emptyList()
    }

    fun isFavorite(id: String): Boolean = _favorites.value.any { it.id == id }

    /** Add if absent, remove if present. New favorites go to the top. */
    fun toggle(movie: Movie) {
        val current = _favorites.value
        _favorites.value = if (current.any { it.id == movie.id }) {
            current.filterNot { it.id == movie.id }
        } else {
            listOf(movie) + current
        }
        persist()
    }

    private fun persist() {
        prefs.edit().putString("items", adapter.toJson(_favorites.value)).apply()
    }
}
