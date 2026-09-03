package com.movieboxz.android.data.local

import android.content.Context
import android.content.SharedPreferences
import com.movieboxz.android.data.remote.ApiClient

/**
 * Persists user settings. Currently just the optional region override that
 * drives [ApiClient.regionOverride] (the X-Country header). null = use the
 * device locale. Call [init] once from the Application so the saved region is
 * applied before the first network call.
 */
object SettingsStore {
    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences("mbz_settings", Context.MODE_PRIVATE)
        ApiClient.regionOverride = prefs.getString(KEY_REGION, null)
    }

    var regionOverride: String?
        get() = prefs.getString(KEY_REGION, null)
        set(value) {
            prefs.edit().putString(KEY_REGION, value).apply()
            ApiClient.regionOverride = value
        }

    private const val KEY_REGION = "region_override"
}
