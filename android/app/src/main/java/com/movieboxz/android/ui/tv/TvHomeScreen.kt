package com.movieboxz.android.ui.tv

import androidx.compose.foundation.layout.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.TVSeries
import com.movieboxz.android.ui.library.LibraryScreen
import com.movieboxz.android.ui.search.SearchScreen
import com.movieboxz.android.ui.series.SeriesScreen
import com.movieboxz.android.ui.settings.SettingsScreen

/**
 * The Android TV home: a persistent left nav rail + a content area that swaps
 * between Browse / Search / TV Series / Library / Settings. Movie and series
 * taps bubble up so the host NavHost can push the detail screens.
 */
@Composable
fun TvHomeScreen(
    onMovieClick: (Movie) -> Unit,
    onSeriesClick: (TVSeries) -> Unit,
) {
    var selected by rememberSaveable { mutableStateOf(0) }

    Row(Modifier.fillMaxSize()) {
        TvNavRail(selected = selected, onSelect = { selected = it })
        Box(Modifier.weight(1f).fillMaxHeight()) {
            when (selected) {
                0 -> TvBrowseScreen(onMovieClick = onMovieClick)
                1 -> SearchScreen(onMovieClick = onMovieClick)
                2 -> SeriesScreen(onSeriesClick = onSeriesClick)
                3 -> LibraryScreen(onMovieClick = onMovieClick)
                4 -> SettingsScreen()
            }
        }
    }
}
