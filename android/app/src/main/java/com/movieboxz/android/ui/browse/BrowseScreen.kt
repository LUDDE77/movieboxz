package com.movieboxz.android.ui.browse

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.ui.components.HeroCarousel
import com.movieboxz.android.ui.components.MovieRow
import com.movieboxz.android.ui.theme.MbzGold

/**
 * The Browse tab — a featured header + a vertical list of horizontal rails.
 * Mirrors the iOS MainBrowseView.
 */
@Composable
fun BrowseScreen(
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
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Couldn't load movies", style = MaterialTheme.typography.titleMedium)
                Text(state.error!!, style = MaterialTheme.typography.bodySmall)
                Spacer(Modifier.height(12.dp))
                Button(onClick = { vm.load() }) { Text("Retry") }
            }
        }
        else -> LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                Text(
                    "MovieBoxZ",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.ExtraBold,
                    color = MbzGold,
                    modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
                )
            }
            // Featured hero carousel (first few featured items).
            if (state.featured.isNotEmpty()) {
                item {
                    HeroCarousel(items = state.featured.take(6), onMovieClick = onMovieClick)
                }
            }
            items(state.rails, key = { it.title }) { rail ->
                MovieRow(
                    rail = rail,
                    onMovieClick = onMovieClick,
                    onSeeAll = rail.categoryId?.let { cid -> { onSeeAll(cid, rail.title) } },
                )
            }
        }
    }
}
