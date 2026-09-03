package com.movieboxz.android.ui.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.movieboxz.android.data.local.SettingsStore
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted

private data class RegionOption(val code: String?, val label: String)

private val REGIONS = listOf(
    RegionOption(null, "Automatic (device region)"),
    RegionOption("US", "United States"),
    RegionOption("GB", "United Kingdom"),
    RegionOption("SE", "Sweden"),
    RegionOption("PH", "Philippines"),
    RegionOption("MY", "Malaysia"),
    RegionOption("IN", "India"),
    RegionOption("CA", "Canada"),
    RegionOption("AU", "Australia"),
    RegionOption("ZA", "South Africa"),
    RegionOption("DE", "Germany"),
    RegionOption("FR", "France"),
)

/** Settings tab — region override + about info. */
@Composable
fun SettingsScreen() {
    var selected by remember { mutableStateOf(SettingsStore.regionOverride) }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text(
            "Settings",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.ExtraBold,
            color = MbzGold,
            modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
        )

        SectionHeader("Region")
        Text(
            "Choose which country's catalog to browse. YouTube hides titles it won't play in your region.",
            style = MaterialTheme.typography.bodySmall,
            color = MbzMuted,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        REGIONS.forEach { option ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .selectable(
                        selected = option.code == selected,
                        onClick = {
                            selected = option.code
                            SettingsStore.regionOverride = option.code
                        },
                    )
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = option.code == selected, onClick = null)
                Spacer(Modifier.width(12.dp))
                Text(option.label, style = MaterialTheme.typography.bodyLarge)
            }
        }

        SectionHeader("About")
        InfoRow("How it works", "MovieBoxZ is a discovery guide. It hosts no video — every title opens in the YouTube app.")
        InfoRow("Version", "1.0")
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium,
        fontWeight = FontWeight.Bold,
        color = MbzGold,
        modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
    )
}

@Composable
private fun InfoRow(title: String, subtitle: String) {
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp)) {
        Text(title, style = MaterialTheme.typography.bodyLarge, fontWeight = FontWeight.SemiBold)
        Text(subtitle, style = MaterialTheme.typography.bodySmall, color = MbzMuted)
    }
}
