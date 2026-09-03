package com.movieboxz.android.ui.tv

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.selection.selectable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.movieboxz.android.data.LegalContent
import com.movieboxz.android.data.local.FavoritesStore
import com.movieboxz.android.data.local.SettingsStore
import com.movieboxz.android.ui.settings.LegalDocumentScreen
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.MovieRail
import com.movieboxz.android.data.model.TVSeries
import com.movieboxz.android.ui.kids.KidsViewModel
import com.movieboxz.android.ui.search.SearchViewModel
import com.movieboxz.android.ui.series.SeriesViewModel
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted

private val TV_PAD = 48.dp

@Composable
private fun TvHeader(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.displaySmall,
        fontWeight = FontWeight.ExtraBold,
        color = MbzGold,
        modifier = Modifier.padding(start = TV_PAD, top = 40.dp, bottom = 16.dp),
    )
}

// ---- TV Series (grid) --------------------------------------------------------

@Composable
fun TvSeriesScreen(onSeriesClick: (TVSeries) -> Unit, vm: SeriesViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize()) {
        TvHeader("TV Series")
        when {
            state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = MbzGold) }
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 170.dp),
                contentPadding = PaddingValues(horizontal = TV_PAD, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                items(state.series, key = { it.id }) { s -> TvSeriesCard(series = s, onClick = { onSeriesClick(s) }) }
            }
        }
    }
}

// ---- TV Library (favorites grid) ---------------------------------------------

@Composable
fun TvLibraryScreen(onMovieClick: (Movie) -> Unit) {
    val favorites by FavoritesStore.favorites.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize()) {
        TvHeader("My Library")
        if (favorites.isEmpty()) {
            Box(Modifier.fillMaxSize().padding(TV_PAD), Alignment.Center) {
                Text("No saved titles yet. Open a movie and choose “Add to Library”.", color = MbzMuted, style = MaterialTheme.typography.titleMedium)
            }
        } else {
            LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 170.dp),
                contentPadding = PaddingValues(horizontal = TV_PAD, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                items(favorites, key = { it.id }) { m -> TvMovieCard(movie = m, onClick = { onMovieClick(m) }) }
            }
        }
    }
}

// ---- TV Search ---------------------------------------------------------------

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TvSearchScreen(onMovieClick: (Movie) -> Unit, vm: SearchViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    Column(Modifier.fillMaxSize()) {
        TvHeader("Search")
        OutlinedTextField(
            value = state.query,
            onValueChange = vm::onQueryChange,
            modifier = Modifier.fillMaxWidth().padding(horizontal = TV_PAD).padding(bottom = 12.dp),
            placeholder = { Text("Search movies…") },
            leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null) },
            singleLine = true,
            textStyle = MaterialTheme.typography.titleMedium,
        )
        when {
            state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = MbzGold) }
            !state.hasSearched -> Box(Modifier.fillMaxSize().padding(TV_PAD), Alignment.Center) {
                Text("Search by title, actor, or genre.", color = MbzMuted, style = MaterialTheme.typography.titleMedium)
            }
            state.results.isEmpty() -> Box(Modifier.fillMaxSize().padding(TV_PAD), Alignment.Center) {
                Text("No results for “${state.query.trim()}”.", color = MbzMuted, style = MaterialTheme.typography.titleMedium)
            }
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 170.dp),
                contentPadding = PaddingValues(horizontal = TV_PAD, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                items(state.results, key = { it.id }) { m -> TvMovieCard(movie = m, onClick = { onMovieClick(m) }) }
            }
        }
    }
}

// ---- TV Kids (rows) ----------------------------------------------------------

@Composable
fun TvKidsScreen(
    onMovieClick: (Movie) -> Unit,
    onSeriesClick: (TVSeries) -> Unit,
    onSeeAll: (categoryId: String, title: String) -> Unit = { _, _ -> },
    vm: KidsViewModel = viewModel(),
) {
    val state by vm.state.collectAsStateWithLifecycle()
    when {
        state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = MbzGold) }
        else -> LazyColumn(contentPadding = PaddingValues(bottom = 40.dp)) {
            item {
                Row(Modifier.padding(start = TV_PAD, top = 40.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(Icons.Filled.Star, contentDescription = null, tint = MbzGold)
                    Spacer(Modifier.width(12.dp))
                    Text("Kids", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.ExtraBold, color = MbzGold)
                }
            }
            if (state.series.isNotEmpty()) {
                item {
                    Column(Modifier.padding(vertical = 12.dp)) {
                        Text("TV Shows", style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = MbzGold, modifier = Modifier.padding(start = TV_PAD, bottom = 10.dp))
                        LazyRow(contentPadding = PaddingValues(horizontal = TV_PAD), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                            items(state.series, key = { it.id }) { s -> TvSeriesCard(series = s, onClick = { onSeriesClick(s) }) }
                        }
                    }
                }
            }
            if (state.family.isNotEmpty()) {
                item { TvMovieRow(rail = MovieRail("Family", state.family, "g10751"), onMovieClick = onMovieClick, onSeeAll = { onSeeAll("g10751", "Family") }) }
            }
            if (state.animation.isNotEmpty()) {
                item { TvMovieRow(rail = MovieRail("Animation", state.animation, "g16"), onMovieClick = onMovieClick, onSeeAll = { onSeeAll("g16", "Animation") }) }
            }
        }
    }
}

// ---- TV Settings (region) ----------------------------------------------------

private data class TvRegion(val code: String?, val label: String)
private val TV_REGIONS = listOf(
    TvRegion(null, "Automatic (device region)"),
    TvRegion("US", "United States"), TvRegion("GB", "United Kingdom"), TvRegion("SE", "Sweden"),
    TvRegion("PH", "Philippines"), TvRegion("MY", "Malaysia"), TvRegion("IN", "India"),
    TvRegion("CA", "Canada"), TvRegion("AU", "Australia"), TvRegion("ZA", "South Africa"),
)

@Composable
fun TvSettingsScreen() {
    val context = LocalContext.current
    var selected by remember { mutableStateOf(SettingsStore.regionOverride) }
    var legal by remember { mutableStateOf<Pair<String, String>?>(null) }

    if (legal != null) {
        LegalDocumentScreen(title = legal!!.first, text = legal!!.second, onClose = { legal = null })
        return
    }

    LazyColumn(contentPadding = PaddingValues(bottom = 40.dp)) {
        item { TvHeader("Settings") }

        item { TvSectionHeader("About") }
        item { TvLinkRow("Privacy Policy") { legal = "Privacy Policy" to LegalContent.privacyPolicy } }
        item { TvLinkRow("Terms of Service") { legal = "Terms of Service" to LegalContent.termsOfService } }

        item { TvSectionHeader("Region") }
        items(TV_REGIONS) { r ->
            Row(
                Modifier.fillMaxWidth()
                    .selectable(selected = r.code == selected, onClick = { selected = r.code; SettingsStore.regionOverride = r.code })
                    .padding(horizontal = TV_PAD, vertical = 14.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = r.code == selected, onClick = null)
                Spacer(Modifier.width(16.dp))
                Text(r.label, style = MaterialTheme.typography.titleLarge)
            }
        }

        item { TvSectionHeader("Copyright") }
        item { TvLinkRow("Report a Copyright Concern") { runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://www.youtube.com/copyright_complaint_form"))) } } }

        item { TvSectionHeader("About the app") }
        item {
            Text(
                "MovieBoxZ is a discovery guide — it hosts no video; every title plays in the YouTube app. No account, no personal data. Version 1.0.",
                style = MaterialTheme.typography.titleMedium, color = MbzMuted,
                modifier = Modifier.padding(horizontal = TV_PAD, vertical = 8.dp),
            )
        }
    }
}

@Composable
private fun TvSectionHeader(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold, color = MbzGold,
        modifier = Modifier.padding(start = TV_PAD, top = 24.dp, bottom = 4.dp),
    )
}

@Composable
private fun TvLinkRow(title: String, onClick: () -> Unit) {
    Text(
        title,
        style = MaterialTheme.typography.titleLarge,
        modifier = Modifier.fillMaxWidth().clickable { onClick() }.padding(horizontal = TV_PAD, vertical = 16.dp),
    )
}
