package com.movieboxz.android.ui.detail

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.movieboxz.android.data.MovieRepository
import com.movieboxz.android.data.model.Movie
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class DetailUiState(
    val loading: Boolean = true,
    val movie: Movie? = null,
    val error: String? = null,
)

class DetailViewModel(private val repo: MovieRepository = MovieRepository()) : ViewModel() {

    private val _state = MutableStateFlow(DetailUiState())
    val state: StateFlow<DetailUiState> = _state.asStateFlow()

    fun load(id: String) {
        _state.value = DetailUiState(loading = true)
        viewModelScope.launch {
            try {
                _state.value = DetailUiState(loading = false, movie = repo.movie(id))
            } catch (e: Exception) {
                _state.value = DetailUiState(loading = false, error = e.message ?: "Couldn't load this title")
            }
        }
    }
}
