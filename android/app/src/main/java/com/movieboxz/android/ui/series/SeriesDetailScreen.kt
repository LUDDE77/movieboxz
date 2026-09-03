package com.movieboxz.android.ui.series

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.AsyncImage
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted
import com.movieboxz.android.util.ImageUrls
import com.movieboxz.android.util.YouTubeLauncher

/** Series detail — header + seasons, each listing tappable episodes that open on YouTube. */
@Composable
fun SeriesDetailScreen(seriesId: String, vm: SeriesDetailViewModel = viewModel()) {
    val context = LocalContext.current
    val state by vm.state.collectAsStateWithLifecycle()

    LaunchedEffect(seriesId) { vm.load(seriesId) }

    when {
        state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = MbzGold)
        }
        state.error != null -> Box(Modifier.fillMaxSize(), Alignment.Center) { Text(state.error!!) }
        else -> {
            val series = state.series
            LazyColumn(contentPadding = PaddingValues(bottom = 24.dp)) {
                item {
                    Column(Modifier.padding(16.dp)) {
                        Text(
                            series?.title ?: "TV Series",
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                        )
                        val meta = listOfNotNull(
                            series?.yearRange,
                            series?.seasonCount?.let { "$it season${if (it == 1) "" else "s"}" },
                            series?.episodeCount?.let { "$it episodes" },
                        ).joinToString("  ·  ")
                        if (meta.isNotBlank()) {
                            Spacer(Modifier.height(4.dp))
                            Text(meta, color = MbzMuted, style = MaterialTheme.typography.bodyMedium)
                        }
                        series?.description?.takeIf { it.isNotBlank() }?.let {
                            Spacer(Modifier.height(12.dp))
                            Text(it, style = MaterialTheme.typography.bodyMedium)
                        }
                    }
                }
                state.seasons.forEach { season ->
                    item {
                        Text(
                            "Season ${season.seasonNumber}",
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.Bold,
                            color = MbzGold,
                            modifier = Modifier.padding(start = 16.dp, top = 16.dp, bottom = 4.dp),
                        )
                    }
                    items(season.episodes) { episode ->
                        EpisodeRow(episode = episode, onClick = {
                            YouTubeLauncher.watch(context, episode.youtubeVideoId)
                        })
                    }
                }
            }
        }
    }
}

@Composable
private fun EpisodeRow(episode: Movie, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable { onClick() }
            .padding(horizontal = 16.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        AsyncImage(
            model = ImageUrls.backdrop(episode),
            contentDescription = episode.displayTitle,
            contentScale = ContentScale.Crop,
            modifier = Modifier
                .width(120.dp)
                .aspectRatio(16f / 9f)
                .clip(RoundedCornerShape(8.dp)),
        )
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            val label = episode.episodeNumber?.let { "E$it  " }.orEmpty() + episode.displayTitle
            Text(label, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold, maxLines = 2)
            episode.runtimeText?.let {
                Text(it, style = MaterialTheme.typography.bodySmall, color = MbzMuted)
            }
        }
        Icon(Icons.Filled.PlayArrow, contentDescription = "Play", tint = MbzGold)
    }
}
