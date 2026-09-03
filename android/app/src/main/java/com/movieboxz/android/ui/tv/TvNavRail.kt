package com.movieboxz.android.ui.tv

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.focus.onFocusEvent
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MbzMuted
import com.movieboxz.android.ui.theme.MbzScreen

data class TvDest(val label: String, val icon: ImageVector)

val TV_DESTS = listOf(
    TvDest("Browse", Icons.Filled.Home),
    TvDest("Search", Icons.Filled.Search),
    TvDest("TV Series", Icons.Filled.Tv),
    TvDest("Kids", Icons.Filled.Star),
    TvDest("Library", Icons.Filled.FavoriteBorder),
    TvDest("Settings", Icons.Filled.Settings),
)

/**
 * The Android-TV left nav rail. Collapses to an icon strip when focus is in the
 * content, and expands to icons+labels when the user D-pads into it (standard TV
 * drawer behavior). Selecting an item switches the content area.
 */
@Composable
fun TvNavRail(selected: Int, onSelect: (Int) -> Unit, modifier: Modifier = Modifier) {
    var expanded by remember { mutableStateOf(false) }
    val width by animateDpAsState(if (expanded) 220.dp else 92.dp, label = "railWidth")

    Column(
        modifier
            .fillMaxHeight()
            .width(width)
            .background(MbzInk)
            .onFocusEvent { expanded = it.hasFocus }   // expand while any item is focused
            .padding(vertical = 32.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        if (expanded) {
            Text(
                "MovieBoxZ",
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.ExtraBold,
                color = MbzGold,
                maxLines = 1,
                overflow = TextOverflow.Clip,
                modifier = Modifier.padding(start = 24.dp, bottom = 24.dp),
            )
        } else {
            Spacer(Modifier.height(48.dp))
        }
        TV_DESTS.forEachIndexed { i, dest ->
            TvNavItem(dest = dest, selected = selected == i, expanded = expanded, onClick = { onSelect(i) })
        }
    }
}

@Composable
private fun TvNavItem(dest: TvDest, selected: Boolean, expanded: Boolean, onClick: () -> Unit) {
    var focused by remember { mutableStateOf(false) }
    val highlight = focused || selected
    Row(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp, vertical = 2.dp)
            .clip(RoundedCornerShape(10.dp))
            .background(if (focused) MbzGold.copy(alpha = 0.18f) else Color.Transparent)
            .onFocusChanged { focused = it.isFocused }
            .clickable { onClick() }
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(dest.icon, contentDescription = dest.label, tint = if (highlight) MbzGold else MbzMuted)
        if (expanded) {
            Spacer(Modifier.width(14.dp))
            Text(
                dest.label,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = if (highlight) FontWeight.Bold else FontWeight.Normal,
                color = if (highlight) MbzScreen else MbzMuted,
                maxLines = 1,
                overflow = TextOverflow.Clip,
            )
        }
    }
}
