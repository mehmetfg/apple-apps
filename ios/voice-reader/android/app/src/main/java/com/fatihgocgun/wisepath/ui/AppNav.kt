// Every screen and how they are reached. The library is home; the reader opens over it; the moving modes, the
// statistics, the notes, the automations, the prompts and the settings are pages of their own.
package com.fatihgocgun.wisepath.ui

import android.net.Uri
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.automation.AutomationScreen
import com.fatihgocgun.wisepath.cloud.CloudVoiceSettings
import com.fatihgocgun.wisepath.move.RideScreen
import com.fatihgocgun.wisepath.move.RoadsScreen
import com.fatihgocgun.wisepath.music.MusicModeScreen
import com.fatihgocgun.wisepath.notes.NotesScreen
import com.fatihgocgun.wisepath.prompt.ExpandPromptScreen
import com.fatihgocgun.wisepath.prompt.PromptBuilderScreen
import com.fatihgocgun.wisepath.stats.StatsScreen
import com.fatihgocgun.wisepath.sync.SyncSettings
import com.fatihgocgun.wisepath.ui.library.FolderScreen
import com.fatihgocgun.wisepath.ui.library.LibraryScreen
import com.fatihgocgun.wisepath.ui.reader.ReaderScreen
import com.fatihgocgun.wisepath.ui.settings.GeneralSettingsScreen
import kotlinx.coroutines.launch

object Routes {
    const val LIBRARY = "library"
    const val READER = "reader"
    const val FOLDER = "folder/{name}"
    const val SETTINGS = "settings"
    const val STATS = "stats"
    const val ROADS = "roads"
    const val NOTES = "notes"
    const val RIDE = "ride"
    const val MUSIC = "music"
    const val AUTOMATION = "automation"
    const val PROMPT = "prompt"
    const val EXPAND = "expand/{doc}?start={start}&end={end}"
    const val CLOUD = "cloud"
    const val SYNC = "sync"

    fun folder(name: String) = "folder/" + Uri.encode(name)
    fun expand(doc: String, start: Int = -1, end: Int = -1) = "expand/$doc?start=$start&end=$end"
}

/** Opens a book in the reader (and the ride screen when a moving mode is on). */
fun NavHostController.openReader(app: AppModel, id: String, offset: Int? = null) {
    app.scope.launch {
        app.open(id)
        if (offset != null) app.revealRequest = id to offset
        val route = if (app.settings.bikeMode) Routes.RIDE else Routes.READER
        if (currentDestination?.route != route) navigate(route) { launchSingleTop = true }
    }
}

@Composable
fun AppNav(app: AppModel, nav: NavHostController = rememberNavController()) {
    val openPlace: (String, Int) -> Unit = { doc, offset -> nav.openReader(app, doc, offset) }
    Box(Modifier.fillMaxSize()) {
        NavHost(nav, startDestination = Routes.LIBRARY) {
            composable(Routes.LIBRARY) { LibraryScreen(app, nav) }
            composable(Routes.READER) { ReaderScreen(app, nav) }
            composable(Routes.FOLDER, arguments = listOf(navArgument("name") { type = NavType.StringType })) {
                FolderScreen(app, nav, Uri.decode(it.arguments?.getString("name") ?: ""))
            }
            composable(Routes.SETTINGS) { GeneralSettingsScreen(app, nav) }
            composable(Routes.STATS) {
                StatsScreen(onBack = { nav.popBackStack() }, onOpenBook = { id -> nav.openReader(app, id) }, onOpenRoads = { nav.navigate(Routes.ROADS) })
            }
            composable(Routes.ROADS) { RoadsScreen(onBack = { nav.popBackStack() }) }
            composable(Routes.NOTES) { NotesScreen(onBack = { nav.popBackStack() }, onOpenPlace = openPlace) }
            composable(Routes.RIDE) {
                RideScreen(onExit = { app.settings.bikeMode = false; nav.popBackStack() }, onOpenReader = {
                    nav.navigate(Routes.READER) { launchSingleTop = true }
                })
            }
            composable(Routes.MUSIC) { MusicModeScreen(onClose = { nav.popBackStack() }) }
            composable(Routes.AUTOMATION) { AutomationScreen(onBack = { nav.popBackStack() }) }
            composable(Routes.PROMPT) {
                PromptBuilderScreen(onBack = { nav.popBackStack() }, onAdded = { id -> nav.popBackStack(); nav.openReader(app, id) })
            }
            composable(
                Routes.EXPAND,
                arguments = listOf(
                    navArgument("doc") { type = NavType.StringType },
                    navArgument("start") { type = NavType.IntType; defaultValue = -1 },
                    navArgument("end") { type = NavType.IntType; defaultValue = -1 },
                ),
            ) {
                ExpandPromptScreen(
                    docId = it.arguments?.getString("doc") ?: "", start = it.arguments?.getInt("start") ?: -1,
                    end = it.arguments?.getInt("end") ?: -1, onBack = { nav.popBackStack() },
                    onAdded = { id -> nav.popBackStack(); nav.openReader(app, id) },
                )
            }
            composable(Routes.CLOUD) { CloudVoiceSettings(onBack = { nav.popBackStack() }) }
            composable(Routes.SYNC) { SyncSettings(onBack = { nav.popBackStack() }) }
        }
        AppDialogs(app, nav)
    }
}

/** The app-wide questions: a message, a finished book asked to play again. */
@Composable
private fun AppDialogs(app: AppModel, nav: NavHostController) {
    com.fatihgocgun.wisepath.automation.AutomationChoiceDialog()
    app.message?.let { m ->
        AlertDialog(
            onDismissRequest = { app.message = null },
            confirmButton = { TextButton(onClick = { app.message = null }) { Text("Tamam") } },
            text = { Text(m) },
        )
    }
    val problem by app.player.state.collectAsState()
    problem.problem?.let { p ->
        AlertDialog(
            onDismissRequest = { app.player.clearProblem() },
            confirmButton = { TextButton(onClick = { app.player.clearProblem() }) { Text("Tamam") } },
            title = { Text("Okunamadı") },
            text = { Text(p) },
        )
    }
    app.finishedPrompt?.let { f ->
        AlertDialog(
            onDismissRequest = { app.finishedPrompt = null },
            title = { Text("\"${f.title}\" bitti") },
            text = { Text("Bu kitabı bitirdin. Yeni bir okuma başlatılsın mı? Önceki okumalar kayıtlı kalır.") },
            confirmButton = {
                TextButton(onClick = {
                    app.finishedPrompt = null
                    app.startReadingAgain(f.doc, 0, play = f.play)
                    if (f.play) app.player.play(0, snap = false)
                }) { Text("Baştan oku") }
            },
            dismissButton = { TextButton(onClick = { app.finishedPrompt = null }) { Text("Vazgeç") } },
        )
    }
}

/** A page with a back arrow and a title, for the screens still being written. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun StubScreen(title: String, onBack: () -> Unit) {
    Scaffold(topBar = {
        TopAppBar(title = { Text(title) }, navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") }
        })
    }) { pad ->
        Box(Modifier.fillMaxSize().padding(pad), contentAlignment = Alignment.Center) {
            Text("Hazırlanıyor", color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f))
        }
    }
}

/** A standard page: top bar with back and title, and actions. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Page(
    title: String,
    onBack: () -> Unit,
    actions: @Composable androidx.compose.foundation.layout.RowScope.() -> Unit = {},
    content: @Composable (androidx.compose.foundation.layout.PaddingValues) -> Unit,
) {
    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") } },
                actions = actions,
                colors = androidx.compose.material3.TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface),
            )
        },
        content = content,
    )
}

@Suppress("unused") private val unusedColor = Color.Unspecified
@Suppress("unused") @Composable private fun unused() { rememberCoroutineScope(); LaunchedEffect(Unit) {} }
