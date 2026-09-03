package com.movieboxz.android.ui.tv

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.data.model.MovieRail
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted
import com.movieboxz.android.ui.theme.MbzScreen
import com.movieboxz.android.util.ImageUrls

/** A D-pad focusable poster card that scales up + shows a gold ring when focused. */
@Composable
fun TvMovieCard(movie: Movie, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(if (focused) 1.1f else 1f, label = "cardScale")

    Column(Modifier.width(150.dp)) {
        Box(
            Modifier
                .fillMaxWidth()
                .aspectRatio(2f / 3f)
                .scale(scale)
                .clip(RoundedCornerShape(10.dp))
                .then(
                    if (focused) Modifier.border(BorderStroke(3.dp, MbzGold), RoundedCornerShape(10.dp))
                    else Modifier
                )
                .onFocusChanged { focused = it.isFocused }
                .clickable { onClick() },
        ) {
            AsyncImage(
                model = ImageUrls.poster(movie),
                contentDescription = movie.displayTitle,
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize(),
            )
        }
        Spacer(Modifier.height(6.dp))
        Text(
            movie.displayTitle,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.SemiBold,
            color = if (focused) MbzScreen else MbzMuted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/** A titled row of TV cards (D-pad left/right within, up/down between rows). */
@Composable
fun TvMovieRow(rail: MovieRail, onMovieClick: (Movie) -> Unit) {
    Column(Modifier.padding(vertical = 12.dp)) {
        Text(
            rail.title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.Bold,
            color = MbzGold,
            modifier = Modifier.padding(start = 48.dp, bottom = 10.dp),
        )
        LazyRow(
            contentPadding = PaddingValues(horizontal = 48.dp),
            horizontalArrangement = Arrangement.spacedBy(20.dp),
        ) {
            items(rail.movies, key = { it.id }) { movie ->
                TvMovieCard(movie = movie, onClick = { onMovieClick(movie) })
            }
        }
    }
}
