package com.movieboxz.android.ui

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.Tv
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.movieboxz.android.ui.browse.BrowseScreen
import com.movieboxz.android.ui.detail.MovieDetailScreen
import com.movieboxz.android.ui.kids.KidsScreen
import com.movieboxz.android.ui.library.LibraryScreen
import com.movieboxz.android.ui.search.SearchScreen
import com.movieboxz.android.ui.series.SeriesDetailScreen
import com.movieboxz.android.ui.series.SeriesScreen
import com.movieboxz.android.ui.settings.SettingsScreen

object Routes {
    const val BROWSE = "browse"
    const val SEARCH = "search"
    const val TV = "tv"
    const val KIDS = "kids"
    const val LIBRARY = "library"
    const val SETTINGS = "settings"
    const val DETAIL = "detail/{movieId}"
    const val SERIES_DETAIL = "series/{seriesId}"
    fun detail(id: String) = "detail/$id"
    fun seriesDetail(id: String) = "series/$id"
}

private data class Tab(val route: String, val label: String, val icon: ImageVector)

private val TABS = listOf(
    Tab(Routes.BROWSE, "Browse", Icons.Filled.Home),
    Tab(Routes.SEARCH, "Search", Icons.Filled.Search),
    Tab(Routes.TV, "TV", Icons.Filled.Tv),
    Tab(Routes.KIDS, "Kids", Icons.Filled.Star),
    Tab(Routes.LIBRARY, "Library", Icons.Filled.FavoriteBorder),
    Tab(Routes.SETTINGS, "Settings", Icons.Filled.Settings),
)

@Composable
fun MovieBoxZNav() {
    val nav = rememberNavController()
    val backStack by nav.currentBackStackEntryAsState()
    val currentRoute = backStack?.destination?.route
    val showBottomBar = TABS.any { it.route == currentRoute }

    Scaffold(
        bottomBar = {
            if (showBottomBar) {
                NavigationBar {
                    TABS.forEach { tab ->
                        NavigationBarItem(
                            selected = currentRoute == tab.route,
                            onClick = {
                                nav.navigate(tab.route) {
                                    popUpTo(nav.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            icon = { Icon(tab.icon, contentDescription = tab.label) },
                            label = { Text(tab.label) },
                        )
                    }
                }
            }
        },
    ) { padding ->
        NavHost(
            navController = nav,
            startDestination = Routes.BROWSE,
            modifier = Modifier.fillMaxSize().padding(padding),
        ) {
            composable(Routes.BROWSE) {
                BrowseScreen(onMovieClick = { nav.navigate(Routes.detail(it.id)) })
            }
            composable(Routes.SEARCH) {
                SearchScreen(onMovieClick = { nav.navigate(Routes.detail(it.id)) })
            }
            composable(Routes.TV) {
                SeriesScreen(onSeriesClick = { nav.navigate(Routes.seriesDetail(it.id)) })
            }
            composable(Routes.KIDS) {
                KidsScreen(
                    onMovieClick = { nav.navigate(Routes.detail(it.id)) },
                    onSeriesClick = { nav.navigate(Routes.seriesDetail(it.id)) },
                )
            }
            composable(Routes.LIBRARY) {
                LibraryScreen(onMovieClick = { nav.navigate(Routes.detail(it.id)) })
            }
            composable(Routes.SETTINGS) { SettingsScreen() }

            composable(
                Routes.DETAIL,
                arguments = listOf(navArgument("movieId") { type = NavType.StringType }),
            ) { backStackEntry ->
                MovieDetailScreen(movieId = backStackEntry.arguments?.getString("movieId").orEmpty())
            }
            composable(
                Routes.SERIES_DETAIL,
                arguments = listOf(navArgument("seriesId") { type = NavType.StringType }),
            ) { backStackEntry ->
                SeriesDetailScreen(seriesId = backStackEntry.arguments?.getString("seriesId").orEmpty())
            }
        }
    }
}
