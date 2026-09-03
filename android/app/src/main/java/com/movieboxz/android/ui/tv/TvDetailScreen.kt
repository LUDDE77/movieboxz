package com.movieboxz.android.ui.tv

import androidx.compose.foundation.background
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.paint
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import coil.compose.rememberAsyncImagePainter
import com.movieboxz.android.data.local.FavoritesStore
import com.movieboxz.android.ui.components.YouTubeLoadingOverlay
import com.movieboxz.android.ui.detail.DetailViewModel
import kotlinx.coroutines.delay
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MbzMuted
import com.movieboxz.android.util.ImageUrls
import com.movieboxz.android.util.YouTubeLauncher

/** Android TV detail — full-bleed backdrop, metadata, and an auto-focused Watch button. */
@Composable
fun TvDetailScreen(movieId: String, vm: DetailViewModel = viewModel()) {
    val context = LocalContext.current
    val state by vm.state.collectAsStateWithLifecycle()
    val watchFocus = remember { FocusRequester() }

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
            var launching by remember { mutableStateOf(false) }
            LaunchedEffect(m.id) { runCatching { watchFocus.requestFocus() } }
            LaunchedEffect(launching) {
                if (launching) { delay(500); YouTubeLauncher.watch(context, m.youtubeVideoId); launching = false }
            }

            Box(Modifier.fillMaxSize()) {
                // Full-bleed backdrop with a left-to-right + bottom scrim for legibility.
                Box(
                    Modifier
                        .fillMaxSize()
                        .paint(
                            painter = rememberAsyncImagePainter(ImageUrls.hero(m)),
                            contentScale = ContentScale.Crop,
                        )
                        .background(
                            Brush.horizontalGradient(
                                0f to MbzInk.copy(alpha = 0.95f),
                                0.6f to MbzInk.copy(alpha = 0.5f),
                                1f to Color.Transparent,
                            )
                        )
                )
                Column(
                    Modifier
                        .fillMaxWidth(0.6f)
                        .align(Alignment.CenterStart)
                        .padding(start = 48.dp, end = 24.dp)
                        .verticalScroll(rememberScrollState()),
                ) {
                    Text(
                        m.displayTitle,
                        style = MaterialTheme.typography.displaySmall,
                        fontWeight = FontWeight.ExtraBold,
                    )
                    Spacer(Modifier.height(8.dp))
                    val meta = listOfNotNull(
                        m.releaseYear, m.runtimeText, m.ratingText?.let { "★ $it" }, m.rated,
                    ).joinToString("   ·   ")
                    if (meta.isNotBlank()) Text(meta, color = MbzMuted, style = MaterialTheme.typography.titleMedium)

                    m.genres?.takeIf { it.isNotEmpty() }?.let {
                        Spacer(Modifier.height(4.dp))
                        Text(it.joinToString(", ") { g -> g.name }, color = MbzMuted)
                    }

                    m.description?.takeIf { it.isNotBlank() }?.let {
                        Spacer(Modifier.height(16.dp))
                        Text(it, style = MaterialTheme.typography.bodyLarge, maxLines = 5)
                    }

                    Spacer(Modifier.height(24.dp))
                    val favorites by FavoritesStore.favorites.collectAsStateWithLifecycle()
                    val isFav = favorites.any { it.id == m.id }
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Button(
                            onClick = { launching = true },
                            shape = RoundedCornerShape(12.dp),
                            modifier = Modifier.focusRequester(watchFocus),
                        ) {
                            Icon(Icons.Filled.PlayArrow, contentDescription = null)
                            Spacer(Modifier.width(8.dp))
                            Text("Watch on YouTube", fontWeight = FontWeight.Bold)
                        }
                        Spacer(Modifier.width(16.dp))
                        OutlinedButton(
                            onClick = { FavoritesStore.toggle(m) },
                            shape = RoundedCornerShape(12.dp),
                        ) {
                            Icon(
                                if (isFav) Icons.Filled.Favorite else Icons.Filled.FavoriteBorder,
                                contentDescription = if (isFav) "Remove from Library" else "Add to Library",
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(if (isFav) "In Library" else "Add to Library", fontWeight = FontWeight.Bold)
                        }
                    }
                    m.channelTitle?.let {
                        Spacer(Modifier.height(20.dp))
                        Text("From $it on YouTube", color = MbzMuted, style = MaterialTheme.typography.titleMedium)
                    }
                }
                if (launching) YouTubeLoadingOverlay()
            }
        }
    }
}
