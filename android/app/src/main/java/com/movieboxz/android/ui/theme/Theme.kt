package com.movieboxz.android.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// MovieBoxZ palette (matches the iOS mbz* colors).
val MbzInk = Color(0xFF141210)
val MbzPanel = Color(0xFF1D1A16)
val MbzGold = Color(0xFFE6B34D)
val MbzScreen = Color(0xFFEFE9DD)
val MbzMuted = Color(0xFFA49A89)

private val MbzColors = darkColorScheme(
    primary = MbzGold,
    onPrimary = MbzInk,
    background = MbzInk,
    onBackground = MbzScreen,
    surface = MbzPanel,
    onSurface = MbzScreen,
    secondary = MbzMuted,
)

@Composable
fun MovieBoxZTheme(content: @Composable () -> Unit) {
    // Dark-first, matching the app's cinema look (single-theme by design).
    MaterialTheme(colorScheme = MbzColors, content = content)
}
