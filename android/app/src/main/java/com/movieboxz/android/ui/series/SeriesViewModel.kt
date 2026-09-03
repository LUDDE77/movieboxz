package com.movieboxz.android.ui.series

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.movieboxz.android.data.MovieRepository
import com.movieboxz.android.data.model.TVSeries
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SeriesUiState(
    val loading: Boolean = true,
    val series: List<TVSeries> = emptyList(),
    val error: String? = null,
)

class SeriesViewModel(private val repo: MovieRepository = MovieRepository()) : ViewModel() {

    private val _state = MutableStateFlow(SeriesUiState())
    val state: StateFlow<SeriesUiState> = _state.asStateFlow()

    init { load() }

    fun load() {
        _state.value = _state.value.copy(loading = true, error = null)
        viewModelScope.launch {
            try {
                _state.value = SeriesUiState(loading = false, series = repo.series())
            } catch (e: Exception) {
                _state.value = SeriesUiState(loading = false, error = e.message ?: "Couldn't load TV series")
            }
        }
    }
}
