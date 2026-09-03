package com.movieboxz.android.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.movieboxz.android.data.local.WelcomeStore
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MbzMuted
import com.movieboxz.android.ui.welcome.WelcomeScreen
import kotlinx.coroutines.delay

private enum class Stage { Splash, Welcome, Ready }

/**
 * Wraps the app: shows a brief branded splash, then the one-time welcome/terms
 * gate (if not yet accepted), then the real [content]. Used by both the phone
 * (MainActivity) and TV (TvActivity) so the first-run experience matches iOS.
 */
@Composable
fun AppRoot(content: @Composable () -> Unit) {
    var stage by remember { mutableStateOf(Stage.Splash) }

    when (stage) {
        Stage.Splash -> {
            SplashContent()
            LaunchedEffect(Unit) {
                delay(1400)
                stage = if (WelcomeStore.accepted) Stage.Ready else Stage.Welcome
            }
        }
        Stage.Welcome -> WelcomeScreen(onAccept = {
            WelcomeStore.accepted = true
            stage = Stage.Ready
        })
        Stage.Ready -> content()
    }
}

@Composable
private fun SplashContent() {
    Box(Modifier.fillMaxSize().background(MbzInk), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier
                    .size(84.dp)
                    .clip(RoundedCornerShape(20.dp))
                    .background(MbzGold),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = MbzInk, modifier = Modifier.size(48.dp))
            }
            Spacer(Modifier.height(16.dp))
            Text("MovieBoxZ", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold, color = MbzGold)
            Spacer(Modifier.height(4.dp))
            Text("Classic Film & TV", style = MaterialTheme.typography.bodyMedium, color = MbzMuted)
        }
    }
}
