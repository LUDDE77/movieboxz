package com.movieboxz.android.ui.settings

import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.movieboxz.android.data.LegalContent
import com.movieboxz.android.data.local.SettingsStore
import com.movieboxz.android.ui.theme.MbzGold
import com.movieboxz.android.ui.theme.MbzMuted

private data class RegionOption(val code: String?, val label: String)

private val REGIONS = listOf(
    RegionOption(null, "Automatic (device region)"),
    RegionOption("US", "United States"), RegionOption("GB", "United Kingdom"),
    RegionOption("SE", "Sweden"), RegionOption("PH", "Philippines"),
    RegionOption("MY", "Malaysia"), RegionOption("IN", "India"),
    RegionOption("CA", "Canada"), RegionOption("AU", "Australia"),
    RegionOption("ZA", "South Africa"), RegionOption("DE", "Germany"), RegionOption("FR", "France"),
)

/** Settings — mirrors the iOS SettingsView sections. */
@Composable
fun SettingsScreen() {
    val context = LocalContext.current
    var selected by remember { mutableStateOf(SettingsStore.regionOverride) }
    var legal by remember { mutableStateOf<Pair<String, String>?>(null) }

    fun open(url: String) = runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }

    if (legal != null) {
        LegalDocumentScreen(title = legal!!.first, text = legal!!.second, onClose = { legal = null })
        return
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
        Text(
            "Settings",
            style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.ExtraBold, color = MbzGold,
            modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 4.dp),
        )

        SectionHeader("About")
        LinkRow("Privacy Policy") { legal = "Privacy Policy" to LegalContent.privacyPolicy }
        LinkRow("Terms of Service") { legal = "Terms of Service" to LegalContent.termsOfService }

        SectionHeader("Region")
        Text(
            "Choose which country's catalog to browse. Some movies are only available in certain regions.",
            style = MaterialTheme.typography.bodySmall, color = MbzMuted,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp),
        )
        REGIONS.forEach { option ->
            Row(
                Modifier.fillMaxWidth()
                    .selectable(selected = option.code == selected, onClick = {
                        selected = option.code; SettingsStore.regionOverride = option.code
                    })
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                RadioButton(selected = option.code == selected, onClick = null)
                Spacer(Modifier.width(12.dp))
                Text(option.label, style = MaterialTheme.typography.bodyLarge)
            }
        }

        SectionHeader("Data Attribution")
        InfoText("Movie & TV metadata and artwork provided by TMDB. This product uses the TMDB API but is not endorsed or certified by TMDB.")
        InfoText("Ratings provided by OMDb API and IMDb.")
        InfoText("Video is hosted on and streamed from YouTube. MovieBoxZ links to the official YouTube app and does not host, stream, download, or store any video.")

        SectionHeader("Copyright")
        LinkRow("Report a Copyright Concern") { open("https://www.youtube.com/copyright_complaint_form") }
        InfoText("MovieBoxZ hosts no video. Because all content is hosted by YouTube, a copyright concern is resolved most completely by reporting the video to YouTube. You may also contact ${LegalContent.supportEmail} and we'll promptly remove the listing.")

        SectionHeader("Support")
        LinkRow("Help") { open("https://movieboxz.com") }
        LinkRow("Contact Support") { open("mailto:${LegalContent.supportEmail}") }

        SectionHeader("Data & Privacy")
        InfoText("No account required. Your favorites are stored only on this device. MovieBoxZ collects no personal data and requires no sign-in.")

        SectionHeader("About the app")
        InfoText("MovieBoxZ • Version 1.0")
        Spacer(Modifier.height(24.dp))
    }
}

@Composable
private fun SectionHeader(text: String) {
    Text(
        text.uppercase(),
        style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.Bold, color = MbzGold,
        modifier = Modifier.padding(start = 16.dp, top = 22.dp, bottom = 4.dp),
    )
}

@Composable
private fun LinkRow(title: String, onClick: () -> Unit) {
    Text(
        title,
        style = MaterialTheme.typography.bodyLarge,
        modifier = Modifier.fillMaxWidth().clickable { onClick() }.padding(horizontal = 16.dp, vertical = 14.dp),
    )
}

@Composable
private fun InfoText(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.bodySmall, color = MbzMuted,
        modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
    )
}
