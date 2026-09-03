package com.movieboxz.android.ui.tv

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.movieboxz.android.data.model.Movie
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MbzMuted
import com.movieboxz.android.util.ImageUrls

/**
 * A big featured hero banner for the TV home — full-width backdrop with a
 * left+bottom scrim, FEATURED label, title, and year. Focusable (gold ring on
 * focus); Select opens the detail.
 */
@Composable
fun TvHero(movie: Movie, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    Box(
        Modifier
            .fillMaxWidth()
            .height(320.dp)
            .padding(horizontal = 48.dp)
            .clip(RoundedCornerShape(16.dp))
            .then(
                if (focused) Modifier.border(BorderStroke(3.dp, MbzGold), RoundedCornerShape(16.dp))
                else Modifier
            )
            .onFocusChanged { focused = it.isFocused }
            .clickable { onClick() },
    ) {
        AsyncImage(
            model = ImageUrls.hero(movie),
            contentDescription = movie.displayTitle,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize(),
        )
        Box(
            Modifier.fillMaxSize().background(
                Brush.horizontalGradient(
                    0f to MbzInk.copy(alpha = 0.9f),
                    0.5f to MbzInk.copy(alpha = 0.35f),
                    1f to Color.Transparent,
                )
            )
        )
        Column(Modifier.align(Alignment.BottomStart).padding(32.dp)) {
            Text("FEATURED", style = MaterialTheme.typography.labelLarge, fontWeight = FontWeight.Bold, color = MbzGold)
            Text(
                movie.displayTitle,
                style = MaterialTheme.typography.displaySmall,
                fontWeight = FontWeight.ExtraBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            movie.releaseYear?.let {
                Text(it, style = MaterialTheme.typography.titleMedium, color = MbzMuted)
            }
        }
    }
}
