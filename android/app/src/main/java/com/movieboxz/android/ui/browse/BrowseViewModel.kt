package com.movieboxz.android.ui.browse

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.movieboxz.android.data.MovieRepository
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.MovieRail
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class BrowseUiState(
    val loading: Boolean = true,
    val featured: List<Movie> = emptyList(),
    val rails: List<MovieRail> = emptyList(),
    val error: String? = null,
)

class BrowseViewModel(private val repo: MovieRepository = MovieRepository()) : ViewModel() {

    private val _state = MutableStateFlow(BrowseUiState())
    val state: StateFlow<BrowseUiState> = _state.asStateFlow()

    init { load() }

    fun load() {
        _state.value = _state.value.copy(loading = true, error = null)
        viewModelScope.launch {
            try {
                // One /browse/home call powers the whole screen (like iOS).
                val featured = repo.featured()
                val rails = repo.browseRails()
                _state.value = BrowseUiState(loading = false, featured = featured, rails = rails)
            } catch (e: Exception) {
                _state.value = BrowseUiState(loading = false, error = e.message ?: "Something went wrong")
            }
        }
    }
}
