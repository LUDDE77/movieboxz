package com.movieboxz.android.ui.series

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.movieboxz.android.data.MovieRepository
import com.movieboxz.android.data.model.Season
import com.movieboxz.android.data.model.TVSeries
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class SeriesDetailUiState(
    val loading: Boolean = true,
    val series: TVSeries? = null,
    val seasons: List<Season> = emptyList(),
    val error: String? = null,
)

class SeriesDetailViewModel(private val repo: MovieRepository = MovieRepository()) : ViewModel() {

    private val _state = MutableStateFlow(SeriesDetailUiState())
    val state: StateFlow<SeriesDetailUiState> = _state.asStateFlow()

    fun load(id: String) {
        _state.value = SeriesDetailUiState(loading = true)
        viewModelScope.launch {
            try {
                val d = repo.seriesEpisodes(id)
                _state.value = SeriesDetailUiState(loading = false, series = d.series, seasons = d.seasons)
            } catch (e: Exception) {
                _state.value = SeriesDetailUiState(loading = false, error = e.message ?: "Couldn't load this series")
            }
        }
    }
}
