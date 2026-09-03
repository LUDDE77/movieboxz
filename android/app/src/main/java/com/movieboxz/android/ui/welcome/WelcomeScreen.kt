package com.movieboxz.android.ui.welcome

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import com.movieboxz.android.data.LegalContent
import com.movieboxz.android.ui.settings.LegalDocumentScreen
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MbzMuted

/**
 * One-time first-run welcome + terms gate (mirrors the iOS WelcomeView).
 * Explains that MovieBoxZ is a discovery guide that hands playback to YouTube,
 * and that using it means accepting the terms. "Get Started" persists acceptance.
 */
@Composable
fun WelcomeScreen(onAccept: () -> Unit) {
    val getStarted = remember { FocusRequester() }
    LaunchedEffect(Unit) { runCatching { getStarted.requestFocus() } }  // TV: focus the CTA

    var legal by remember { mutableStateOf<Pair<String, String>?>(null) }
    if (legal != null) {
        LegalDocumentScreen(title = legal!!.first, text = legal!!.second, onClose = { legal = null })
        return
    }

    Box(Modifier.fillMaxSize().background(MbzInk), contentAlignment = Alignment.Center) {
        Column(
            Modifier
                .widthIn(max = 520.dp)
                .padding(32.dp)
                .verticalScroll(rememberScrollState()),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Box(
                Modifier.size(72.dp).clip(RoundedCornerShape(18.dp)).background(MbzGold),
                contentAlignment = Alignment.Center,
            ) {
                Icon(Icons.Filled.PlayArrow, contentDescription = null, tint = MbzInk, modifier = Modifier.size(42.dp))
            }
            Spacer(Modifier.height(16.dp))
            Text("Welcome to MovieBoxZ", style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.ExtraBold, color = MbzGold)
            Spacer(Modifier.height(6.dp))
            Text(
                "Your guide to thousands of classic films & TV.",
                style = MaterialTheme.typography.bodyLarge,
                color = MbzMuted,
            )

            Spacer(Modifier.height(24.dp))
            Point("Discover, don't host", "MovieBoxZ is a discovery guide. It doesn't host or stream any video.")
            Point("Plays on YouTube", "Every title opens and plays in the official YouTube app.")
            Point("Free & curated", "A hand-picked catalog of public and classic titles.")

            Spacer(Modifier.height(24.dp))
            Text(
                "By continuing, you agree to our Terms of Service and Privacy Policy. Content is provided by YouTube and its creators.",
                style = MaterialTheme.typography.bodySmall,
                color = MbzMuted,
            )
            Spacer(Modifier.height(8.dp))
            Row {
                Text(
                    "Terms of Service",
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = MbzGold,
                    modifier = Modifier.clickable { legal = "Terms of Service" to LegalContent.termsOfService },
                )
                Spacer(Modifier.width(24.dp))
                Text(
                    "Privacy Policy",
                    style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Bold, color = MbzGold,
                    modifier = Modifier.clickable { legal = "Privacy Policy" to LegalContent.privacyPolicy },
                )
            }

            Spacer(Modifier.height(20.dp))
            Button(
                onClick = onAccept,
                modifier = Modifier.fillMaxWidth().focusRequester(getStarted),
                shape = RoundedCornerShape(12.dp),
            ) {
                Text("Get Started", fontWeight = FontWeight.Bold)
            }
        }
    }
}

@Composable
private fun Point(title: String, body: String) {
    Column(Modifier.fillMaxWidth().padding(vertical = 6.dp)) {
        Text(title, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
        Text(body, style = MaterialTheme.typography.bodyMedium, color = MbzMuted)
    }
}
