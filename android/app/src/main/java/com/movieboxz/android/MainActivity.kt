package com.movieboxz.android

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import androidx.compose.ui.Modifier
import com.movieboxz.android.ui.AppRoot
import com.movieboxz.android.ui.MovieBoxZNav
import com.movieboxz.android.ui.theme.MbzInk
import com.movieboxz.android.ui.theme.MovieBoxZTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        setContent {
            MovieBoxZTheme {
                Surface(Modifier.fillMaxSize().background(MbzInk)) {
                    AppRoot { MovieBoxZNav() }
                }
            }
        }
    }
}
