package com.movieboxz.android.tv

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.movieboxz.android.ui.AppRoot
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MovieBoxZTheme
import com.movieboxz.android.ui.tv.TvNav

/**
 * Android TV entry point (LEANBACK_LAUNCHER). Hosts the 10-foot, D-pad-driven
 * Compose UI. Separate from [com.movieboxz.android.MainActivity] (phone/tablet)
 * so each surface can be tuned independently — the tvOS-equivalent split.
 */
class TvActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MovieBoxZTheme {
                Surface(Modifier.fillMaxSize().background(MbzInk)) {
                    AppRoot { TvNav() }
                }
            }
        }
    }
}
