package com.movieboxz.android.ui.search

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.movieboxz.android.data.MovieRepository
import com.movieboxz.android.data.model.Movie
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SearchUiState(
    val query: String = "",
    val loading: Boolean = false,
    val results: List<Movie> = emptyList(),
    val hasSearched: Boolean = false,
    val error: String? = null,
)

class SearchViewModel(private val repo: MovieRepository = MovieRepository()) : ViewModel() {

    private val _state = MutableStateFlow(SearchUiState())
    val state: StateFlow<SearchUiState> = _state.asStateFlow()

    private var searchJob: Job? = null

    fun onQueryChange(query: String) {
        _state.value = _state.value.copy(query = query)
        searchJob?.cancel()
        val trimmed = query.trim()
        if (trimmed.length < 2) {
            _state.value = _state.value.copy(loading = false, results = emptyList(), hasSearched = false, error = null)
            return
        }
        searchJob = viewModelScope.launch {
            delay(300)  // debounce as the user types
            _state.value = _state.value.copy(loading = true, error = null)
            try {
                val results = repo.search(trimmed)
                _state.value = _state.value.copy(loading = false, results = results, hasSearched = true)
            } catch (e: Exception) {
                _state.value = _state.value.copy(loading = false, error = e.message ?: "Search failed", hasSearched = true)
            }
        }
    }

    fun clear() {
        searchJob?.cancel()
        _state.value = SearchUiState()
    }
}
