package com.movieboxz.android.ui.tv

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.MovieRail
import com.movieboxz.android.ui.browse.BrowseViewModel
import com.movieboxz.android.ui.theme.MbzGold

/** The 10-foot Browse screen for Android TV — big title + D-pad focusable rails. */
@Composable
fun TvBrowseScreen(onMovieClick: (Movie) -> Unit, vm: BrowseViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()

    when {
        state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = MbzGold)
        }
        state.error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            Text(state.error!!, style = MaterialTheme.typography.titleMedium)
        }
        else -> {
            // Build the full rail list (featured first) for the TV column.
            val rails = buildList {
                if (state.featured.isNotEmpty()) add(MovieRail("Featured", state.featured))
                addAll(state.rails)
            }
            LazyColumn(contentPadding = PaddingValues(top = 40.dp, bottom = 40.dp)) {
                item {
                    Text(
                        "MovieBoxZ",
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.ExtraBold,
                        color = MbzGold,
                        modifier = Modifier.padding(start = 48.dp, bottom = 8.dp),
                    )
                }
                items(rails, key = { it.title }) { rail ->
                    TvMovieRow(rail = rail, onMovieClick = onMovieClick)
                }
            }
        }
    }
}
