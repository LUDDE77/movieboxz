package com.movieboxz.android

import android.app.Application
import com.movieboxz.android.data.local.FavoritesStore
import com.movieboxz.android.data.local.SettingsStore

/**
 * Application entry point. Initializes the local stores (favorites + settings)
 * so the saved region override is applied to [com.movieboxz.android.data.remote.ApiClient]
 * before the first network call, and favorites are ready for the Library tab.
 */
class MovieBoxZApp : Application() {
    override fun onCreate() {
        super.onCreate()
        SettingsStore.init(this)
        FavoritesStore.init(this)
    }
}
