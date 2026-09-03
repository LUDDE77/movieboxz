package com.movieboxz.android.ui.kids

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Star
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
import com.movieboxz.android.data.model.MovieRail
import com.movieboxz.android.data.model.TVSeries
import com.movieboxz.android.ui.components.MovieRow
import com.movieboxz.android.ui.components.SeriesCard
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted

/** Kids tab — kids TV shows + Family + Animation rows (mirrors iOS KidsView). */
@Composable
fun KidsScreen(
    onMovieClick: (Movie) -> Unit,
    onSeriesClick: (TVSeries) -> Unit,
    vm: KidsViewModel = viewModel(),
) {
    val state by vm.state.collectAsStateWithLifecycle()

    when {
        state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = MbzGold)
        }
        else -> LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
            item {
                Row(
                    Modifier.padding(start = 16.dp, top = 20.dp, bottom = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(Icons.Filled.Star, contentDescription = null, tint = MbzGold)
                    Spacer(Modifier.width(8.dp))
                    Text("Kids", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold, color = MbzGold)
                }
            }

            val empty = state.series.isEmpty() && state.family.isEmpty() && state.animation.isEmpty()
            if (empty) {
                item {
                    Box(Modifier.fillMaxWidth().padding(40.dp), Alignment.Center) {
                        Text("No kids content yet", color = MbzMuted, style = MaterialTheme.typography.bodyLarge)
                    }
                }
            } else {
                if (state.series.isNotEmpty()) {
                    item {
                        Column(Modifier.padding(vertical = 10.dp)) {
                            Text(
                                "TV Shows",
                                style = MaterialTheme.typography.titleMedium,
                                fontWeight = FontWeight.Bold,
                                color = MbzGold,
                                modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                            )
                            LazyRow(
                                contentPadding = PaddingValues(horizontal = 16.dp),
                                horizontalArrangement = Arrangement.spacedBy(12.dp),
                            ) {
                                items(state.series, key = { it.id }) { series ->
                                    SeriesCard(series = series, onClick = { onSeriesClick(series) }, modifier = Modifier.width(126.dp))
                                }
                            }
                        }
                    }
                }
                if (state.family.isNotEmpty()) {
                    item { MovieRow(rail = MovieRail("Family", state.family), onMovieClick = onMovieClick) }
                }
                if (state.animation.isNotEmpty()) {
                    item { MovieRow(rail = MovieRail("Animation", state.animation), onMovieClick = onMovieClick) }
                }
            }
        }
    }
}
