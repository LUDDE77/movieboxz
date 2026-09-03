package com.movieboxz.android.ui.detail

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
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
import com.movieboxz.android.data.local.FavoritesStore
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted
import com.movieboxz.android.util.ImageUrls
import com.movieboxz.android.util.YouTubeLauncher

/** Movie detail — backdrop, metadata, description, and the Watch (deep-link) CTA. */
@Composable
fun MovieDetailScreen(movieId: String, vm: DetailViewModel = viewModel()) {
    val context = LocalContext.current
    val state by vm.state.collectAsStateWithLifecycle()

    LaunchedEffect(movieId) { vm.load(movieId) }

    when {
        state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            CircularProgressIndicator(color = MbzGold)
        }
        state.error != null || state.movie == null -> Box(Modifier.fillMaxSize(), Alignment.Center) {
            Text(state.error ?: "Not found")
        }
        else -> {
            val m = state.movie!!
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                AsyncImage(
                    model = ImageUrls.hero(m),
                    contentDescription = m.displayTitle,
                    contentScale = ContentScale.Crop,
                    modifier = Modifier.fillMaxWidth().aspectRatio(16f / 9f),
                )
                Column(Modifier.padding(16.dp)) {
                    Text(m.displayTitle, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.Bold)
                    Spacer(Modifier.height(6.dp))

                    val meta = listOfNotNull(
                        m.releaseYear,
                        m.runtimeText,
                        m.ratingText?.let { "★ $it" },
                        m.rated,
                    ).joinToString("  ·  ")
                    if (meta.isNotBlank()) Text(meta, color = MbzMuted, style = MaterialTheme.typography.bodyMedium)

                    m.genres?.takeIf { it.isNotEmpty() }?.let {
                        Spacer(Modifier.height(4.dp))
                        Text(it.joinToString(", ") { g -> g.name }, color = MbzMuted, style = MaterialTheme.typography.bodySmall)
                    }

                    Spacer(Modifier.height(16.dp))
                    val favorites by FavoritesStore.favorites.collectAsStateWithLifecycle()
                    val isFav = favorites.any { it.id == m.id }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Button(
                            onClick = { YouTubeLauncher.watch(context, m.youtubeVideoId) },
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Icon(Icons.Filled.PlayArrow, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Watch on YouTube", fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.width(12.dp))
                        FilledTonalIconButton(onClick = { FavoritesStore.toggle(m) }) {
                            Icon(
                                if (isFav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                                contentDescription = if (isFav) "Remove from Library" else "Save to Library",
                                tint = MbzGold,
                            )
                        }
                    }

                    m.description?.takeIf { it.isNotBlank() }?.let {
                        Spacer(Modifier.height(20.dp))
                        Text(it, style = MaterialTheme.typography.bodyMedium)
                    }

                    m.channelTitle?.let {
                        Spacer(Modifier.height(20.dp))
                        Text("From $it on YouTube", color = MbzMuted, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }
}
