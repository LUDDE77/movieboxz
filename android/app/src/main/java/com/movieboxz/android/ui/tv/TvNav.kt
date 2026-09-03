package com.movieboxz.android.ui.tv

import android.net.Uri
import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.movieboxz.android.ui.Routes
import com.movieboxz.android.ui.category.TvCategoryDetailScreen
import com.movieboxz.android.ui.series.SeriesDetailScreen

/** Android TV navigation: Home (nav rail + content) → Movie/Series detail. */
@Composable
fun TvNav() {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = Routes.BROWSE) {
        composable(Routes.BROWSE) {
            TvHomeScreen(
                onMovieClick = { nav.navigate(Routes.detail(it.id)) },
                onSeriesClick = { nav.navigate(Routes.seriesDetail(it.id)) },
                onSeeAll = { cid, title -> nav.navigate(Routes.category(cid, title)) },
            )
        }
        composable(
            Routes.DETAIL,
            arguments = listOf(navArgument("movieId") { type = NavType.StringType }),
        ) { backStackEntry ->
            TvDetailScreen(movieId = backStackEntry.arguments?.getString("movieId").orEmpty())
        }
        composable(
            Routes.SERIES_DETAIL,
            arguments = listOf(navArgument("seriesId") { type = NavType.StringType }),
        ) { backStackEntry ->
            SeriesDetailScreen(seriesId = backStackEntry.arguments?.getString("seriesId").orEmpty())
        }
        composable(
            Routes.CATEGORY,
            arguments = listOf(
                navArgument("catId") { type = NavType.StringType },
                navArgument("catTitle") { type = NavType.StringType },
            ),
        ) { backStackEntry ->
            TvCategoryDetailScreen(
                categoryId = backStackEntry.arguments?.getString("catId").orEmpty(),
                title = Uri.decode(backStackEntry.arguments?.getString("catTitle").orEmpty()),
                onMovieClick = { nav.navigate(Routes.detail(it.id)) },
            )
        }
    }
}
