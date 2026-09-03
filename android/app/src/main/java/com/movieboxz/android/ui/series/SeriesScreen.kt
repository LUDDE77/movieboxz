package com.movieboxz.android.ui.series

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.item
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.movieboxz.android.data.model.TVSeries
import com.movieboxz.android.ui.components.SeriesCard
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted

/** TV Series tab — a grid of series posters. Mirrors the iOS TVSeriesView. */
@Composable
fun SeriesScreen(onSeriesClick: (TVSeries) -> Unit, vm: SeriesViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()

    when {
        state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = MbzGold)
        }
        state.error != null -> Box(Modifier.fillMaxSize().padding(24.dp), Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("Couldn't load TV series", style = MaterialTheme.typography.titleMedium)
                Text(state.error!!, style = MaterialTheme.typography.bodySmall, color = MbzMuted)
                Spacer(Modifier.height(12.dp))
                Button(onClick = { vm.load() }) { Text("Retry") }
            }
        }
        else -> LazyVerticalGrid(
            columns = GridCells.Adaptive(minSize = 112.dp),
            contentPadding = PaddingValues(16.dp),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item(span = { GridItemSpan(maxLineSpan) }) {
                Text(
                    "TV Series",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.ExtraBold,
                    color = MbzGold,
                    modifier = Modifier.padding(top = 4.dp, bottom = 4.dp),
                )
            }
            items(state.series, key = { it.id }) { series ->
                SeriesCard(series = series, onClick = { onSeriesClick(series) })
            }
        }
    }
}
