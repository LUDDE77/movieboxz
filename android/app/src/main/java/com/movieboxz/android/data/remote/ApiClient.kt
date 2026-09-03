package com.movieboxz.android.data.remote

import android.content.Context
import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import okhttp3.Interceptor
import okhttp3.OkHttpClient
import okhttp3.Response
import okhttp3.logging.HttpLoggingInterceptor
import retrofit2.Retrofit
import retrofit2.converter.moshi.MoshiConverterFactory
import java.util.Locale

/** Builds the Retrofit [MovieApi]. Mirrors the iOS base URL + X-Country header. */
object ApiClient {

    private const val BASE_URL = "https://movieboxz-backend-production.up.railway.app/api/"

    /** Optional 2-letter override; null = use the device locale region. */
    @Volatile var regionOverride: String? = null

    fun create(): MovieApi {
        val logging = HttpLoggingInterceptor().apply {
            level = HttpLoggingInterceptor.Level.BASIC
        }
        val client = OkHttpClient.Builder()
            .addInterceptor(RegionInterceptor { regionOverride })
            .addInterceptor(PlatformInterceptor)
            .addInterceptor(logging)
            .build()

        val moshi = Moshi.Builder()
            .add(KotlinJsonAdapterFactory())
            .build()

        return Retrofit.Builder()
            .baseUrl(BASE_URL)
            .client(client)
            .addConverterFactory(MoshiConverterFactory.create(moshi))
            .build()
            .create(MovieApi::class.java)
    }
}

/**
 * Adds `X-Country` (uppercase ISO-3166 alpha-2) to every request so the backend
 * can region-filter the catalog — exactly like the iOS app. Uses the override if
 * set, else the device's locale country.
 */
class RegionInterceptor(private val override: () -> String?) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val region = (override() ?: Locale.getDefault().country)
            ?.takeIf { it.length == 2 }
            ?.uppercase()
        val req = chain.request().newBuilder().apply {
            if (region != null) header("X-Country", region)
        }.build()
        return chain.proceed(req)
    }
}

/**
 * Tags every request as coming from Android so the backend usage analytics can
 * split platforms (the daily/hourly usage tables already have a platform column).
 * Without this, Android traffic is indistinguishable from iOS in reports.
 */
object PlatformInterceptor : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response =
        chain.proceed(chain.request().newBuilder().header("X-Platform", "android").build())
}
