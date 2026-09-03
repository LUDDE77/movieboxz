package com.movieboxz.android.data.local

import android.content.Context
import android.content.SharedPreferences

/**
 * Tracks whether the user has seen the welcome / accepted the terms (first run),
 * mirroring the iOS WelcomeView gate. Persisted so it only shows once.
 */
object WelcomeStore {
    private lateinit var prefs: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences("mbz_welcome", Context.MODE_PRIVATE)
    }

    var accepted: Boolean
        get() = prefs.getBoolean(KEY_ACCEPTED, false)
        set(value) { prefs.edit().putBoolean(KEY_ACCEPTED, value).apply() }

    private const val KEY_ACCEPTED = "terms_accepted"
}
