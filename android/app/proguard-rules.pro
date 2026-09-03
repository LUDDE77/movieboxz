# Keep Moshi reflective adapters + our data models (reflection-based parsing).
-keep class com.movieboxz.android.data.model.** { *; }
-keepclassmembers class com.movieboxz.android.data.model.** { *; }

# Moshi / Kotlin reflection
-keep class kotlin.Metadata { *; }
-keepclassmembers class ** {
    @com.squareup.moshi.Json <fields>;
}
