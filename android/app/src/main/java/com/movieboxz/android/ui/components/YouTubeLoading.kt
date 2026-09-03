package com.movieboxz.android.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MbzMuted

/**
 * Full-screen "handing off to YouTube" overlay. Shown briefly while the app opens
 * the YouTube deep link, so the transition isn't an abrupt blank — mirrors the
 * iOS loading state on watch hand-off.
 */
@Composable
fun YouTubeLoadingOverlay() {
    Box(
        Modifier.fillMaxSize().background(MbzInk.copy(alpha = 0.96f)),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            CircularProgressIndicator(color = MbzGold)
            Spacer(Modifier.height(20.dp))
            Text("Opening in YouTube…", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(6.dp))
            Text("Playback happens in the YouTube app.", style = MaterialTheme.typography.bodyMedium, color = MbzMuted)
        }
    }
}
