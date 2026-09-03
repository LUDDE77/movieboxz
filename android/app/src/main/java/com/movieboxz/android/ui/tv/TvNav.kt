package com.movieboxz.android.ui.tv

import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.movieboxz.android.ui.Routes

/** Android TV navigation: Browse → Detail (no bottom bar; D-pad only). */
@Composable
fun TvNav() {
    val nav = rememberNavController()
    NavHost(navController = nav, startDestination = Routes.BROWSE) {
        composable(Routes.BROWSE) {
            TvBrowseScreen(onMovieClick = { nav.navigate(Routes.detail(it.id)) })
        }
        composable(
            Routes.DETAIL,
            arguments = listOf(navArgument("movieId") { type = NavType.StringType }),
        ) { backStackEntry ->
            TvDetailScreen(movieId = backStackEntry.arguments?.getString("movieId").orEmpty())
        }
    }
}
