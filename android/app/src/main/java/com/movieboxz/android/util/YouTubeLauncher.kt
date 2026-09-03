package com.movieboxz.android.util

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.Toast

/**
 * The Android equivalent of the iOS `WatchCoordinator` / `YouTubePlayerService`.
 * Opens the film in the YouTube app; falls back to the browser (which itself
 * offers the YouTube app). MovieBoxZ hosts nothing — it just hands off, exactly
 * like the iOS deep-link `youtube:///watch?v=ID`.
 */
object YouTubeLauncher {

    fun watch(context: Context, youtubeVideoId: String) {
        if (youtubeVideoId.isBlank()) {
            Toast.makeText(context, "This title can't be opened right now.", Toast.LENGTH_SHORT).show()
            return
        }
        val webUrl = "https://www.youtube.com/watch?v=$youtubeVideoId"

        // 1) Try the YouTube app explicitly (vnd.youtube scheme).
        val appIntent = Intent(Intent.ACTION_VIEW, Uri.parse("vnd.youtube:$youtubeVideoId")).apply {
            setPackage("com.google.android.youtube")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        // 2) Fallback: a normal VIEW intent (YouTube app if installed, else browser).
        val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse(webUrl)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        try {
            context.startActivity(appIntent)
        } catch (e: ActivityNotFoundException) {
            try {
                context.startActivity(webIntent)
            } catch (e2: ActivityNotFoundException) {
                Toast.makeText(context, "Couldn't open YouTube.", Toast.LENGTH_SHORT).show()
            }
        }
    }
}
