package com.movieboxz.android.ui.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzInk

/**
 * A full-screen readable legal document (Terms / Privacy). Shown as an overlay
 * from Settings on both phone and TV. Close button is focusable for the remote.
 */
@Composable
fun LegalDocumentScreen(title: String, text: String, onClose: () -> Unit) {
    Column(Modifier.fillMaxSize().background(MbzInk)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 16.dp),
            verticalAlignment = androidx.compose.ui.Alignment.CenterVertically,
        ) {
            Text(title, style = MaterialTheme.typography.headlineSmall, fontWeight = FontWeight.ExtraBold, color = MbzGold, modifier = Modifier.weight(1f))
            OutlinedButton(onClick = onClose) {
                Icon(Icons.Filled.Close, contentDescription = "Close")
                Spacer(Modifier.width(8.dp))
                Text("Close")
            }
        }
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 24.dp)
                .padding(bottom = 32.dp),
        )
    }
}
