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
import com.movieboxz.android.ui.browse.BrowseViewModel
import com.movieboxz.android.ui.theme.MbzGold

/** The 10-foot Browse screen for Android TV — big title + D-pad focusable rails. */
@Composable
fun TvBrowseScreen(
    onMovieClick: (Movie) -> Unit,
    onSeeAll: (categoryId: String, title: String) -> Unit = { _, _ -> },
    vm: BrowseViewModel = viewModel(),
) {
    val state by vm.state.collectAsStateWithLifecycle()

    when {
        state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = MbzGold)
        }
        state.error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            Text(state.error!!, style = MaterialTheme.typography.titleMedium)
        }
        else -> {
            // TV shows the content rails. (Featured items carry a backdrop but no
            // poster, so they'd render blank as poster cards; they still appear in
            // Trending/Popular. A dedicated TV hero banner can come later.)
            val rails = state.rails
            LazyColumn(contentPadding = PaddingValues(top = 32.dp, bottom = 40.dp)) {
                item {
                    Text(
                        "MovieBoxZ",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.ExtraBold,
                        color = MbzGold,
                        modifier = Modifier.padding(start = 48.dp, bottom = 12.dp),
                    )
                }
                // Featured hero (first featured item, if any).
                state.featured.firstOrNull()?.let { hero ->
                    item {
                        Column {
                            TvHero(movie = hero, onClick = { onMovieClick(hero) })
                            Spacer(Modifier.height(16.dp))
                        }
                    }
                }
                items(rails, key = { it.title }) { rail ->
                    TvMovieRow(
                        rail = rail,
                        onMovieClick = onMovieClick,
                        onSeeAll = rail.categoryId?.let { cid -> { onSeeAll(cid, rail.title) } },
                    )
                }
            }
        }
    }
}
