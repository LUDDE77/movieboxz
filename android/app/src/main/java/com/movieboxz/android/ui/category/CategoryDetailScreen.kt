package com.movieboxz.android.ui.category

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.ui.components.MovieGridCard
import com.movieboxz.android.ui.theme.MbzGold

/** Phone "See all" — every movie in a genre/category as a poster grid. */
@Composable
fun CategoryDetailScreen(categoryId: String, title: String, onMovieClick: (Movie) -> Unit, onBack: () -> Unit = {}, vm: CategoryViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(categoryId) { vm.load(categoryId) }

    Column(Modifier.fillMaxSize()) {
        Row(Modifier.padding(start = 8.dp, top = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                Spacer(Modifier.width(6.dp))
                Text("Back")
            }
        }
        Text(
            title,
            style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold, color = MbzGold,
            modifier = Modifier.padding(start = 16.dp, bottom = 8.dp),
        )
        when {
            state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = MbzGold) }
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 112.dp),
                contentPadding = PaddingValues(16.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                items(state.movies, key = { it.id }) { m -> MovieGridCard(movie = m, onClick = { onMovieClick(m) }) }
            }
        }
    }
}

/** TV "See all" — same, with 10-foot cards. */
@Composable
fun TvCategoryDetailScreen(categoryId: String, title: String, onMovieClick: (Movie) -> Unit, vm: CategoryViewModel = viewModel()) {
    val state by vm.state.collectAsStateWithLifecycle()
    LaunchedEffect(categoryId) { vm.load(categoryId) }

    Column(Modifier.fillMaxSize()) {
        Text(
            title,
            style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.ExtraBold, color = MbzGold,
            modifier = Modifier.padding(start = 48.dp, top = 40.dp, bottom = 16.dp),
        )
        when {
            state.loading -> Box(Modifier.fillMaxSize(), Alignment.Center) { CircularProgressIndicator(color = MbzGold) }
            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 170.dp),
                contentPadding = PaddingValues(horizontal = 48.dp, vertical = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                items(state.movies, key = { it.id }) { m ->
                    com.movieboxz.android.ui.tv.TvMovieCard(movie = m, onClick = { onMovieClick(m) })
                }
            }
        }
    }
}
