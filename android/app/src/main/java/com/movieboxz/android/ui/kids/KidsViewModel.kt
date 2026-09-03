package com.movieboxz.android.ui.kids

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.movieboxz.android.data.MovieRepository
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.TVSeries
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// TMDB genre ids used for the Kids rows (match iOS KidsView).
private const val GENRE_FAMILY = 10751
private const val GENRE_ANIMATION = 16

data class KidsUiState(
    val loading: Boolean = true,
    val series: List<TVSeries> = emptyList(),
    val family: List<Movie> = emptyList(),
    val animation: List<Movie> = emptyList(),
    val error: String? = null,
)

class KidsViewModel(private val repo: MovieRepository = MovieRepository()) : ViewModel() {

    private val _state = MutableStateFlow(KidsUiState())
    val state: StateFlow<KidsUiState> = _state.asStateFlow()

    init { load() }

    fun load() {
        _state.value = _state.value.copy(loading = true, error = null)
        viewModelScope.launch {
            try {
                // Fetch the three sources in parallel (like iOS).
                val seriesD = async { runCatching { repo.kidsSeries() }.getOrDefault(emptyList()) }
                val familyD = async { runCatching { repo.moviesByGenre(GENRE_FAMILY) }.getOrDefault(emptyList()) }
                val animationD = async { runCatching { repo.moviesByGenre(GENRE_ANIMATION) }.getOrDefault(emptyList()) }
                _state.value = KidsUiState(
                    loading = false,
                    series = seriesD.await(),
                    family = familyD.await(),
                    animation = animationD.await(),
                )
            } catch (e: Exception) {
                _state.value = KidsUiState(loading = false, error = e.message ?: "Couldn't load Kids content")
            }
        }
    }
}
