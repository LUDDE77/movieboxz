package com.movieboxz.android.ui.category

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.movieboxz.android.data.MovieRepository
import com.movieboxz.android.data.model.Movie
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class CategoryUiState(
    val loading: Boolean = true,
    val movies: List<Movie> = emptyList(),
    val error: String? = null,
)

class CategoryViewModel(private val repo: MovieRepository = MovieRepository()) : ViewModel() {
    private val _state = MutableStateFlow(CategoryUiState())
    val state: StateFlow<CategoryUiState> = _state.asStateFlow()

    fun load(categoryId: String) {
        _state.value = CategoryUiState(loading = true)
        viewModelScope.launch {
            try {
                _state.value = CategoryUiState(loading = false, movies = repo.category(categoryId))
            } catch (e: Exception) {
                _state.value = CategoryUiState(loading = false, error = e.message ?: "Couldn't load this category")
            }
        }
    }
}
