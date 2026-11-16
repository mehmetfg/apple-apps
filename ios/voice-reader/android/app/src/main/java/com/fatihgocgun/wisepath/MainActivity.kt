package com.fatihgocgun.wisepath

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.snapshotFlow
import androidx.navigation.NavHostController
import androidx.navigation.compose.rememberNavController
import com.fatihgocgun.wisepath.ui.AppNav
import com.fatihgocgun.wisepath.ui.Routes
import com.fatihgocgun.wisepath.ui.WisePathTheme
import com.fatihgocgun.wisepath.ui.openReader
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {
    private lateinit var app: AppModel
    private var nav: NavHostController? = null
    private var pendingIntent: Intent? = null

    private val notificationPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) {}

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        app = AppModel.get(this)
        if (Build.VERSION.SDK_INT >= 33) notificationPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        pendingIntent = intent
        setContent {
            val controller = rememberNavController()
            nav = controller
            WisePathTheme(app) { AppNav(app, controller) }
            LaunchedEffect(controller) {
                pendingIntent?.let { handle(it) }
                pendingIntent = null
            }
            // the screen stays awake while the reader (or the ride screen) is open and reading
            LaunchedEffect(Unit) {
                snapshotFlow { app.readerOpen }.collect { open ->
                    if (open) window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    else window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handle(intent)
    }

    /** Files opened or shared from other apps, text shared, and wisepath:// links (widgets, shortcuts). */
    private fun handle(intent: Intent) {
        val nav = nav ?: run { pendingIntent = intent; return }
        when (intent.action) {
            Intent.ACTION_VIEW -> {
                val uri = intent.data ?: return
                if (uri.scheme == "wisepath") { DeepLinks.handle(app, nav, uri); return }
                app.scope.launch { importAndOpen(listOf(uri)) }
            }
            Intent.ACTION_SEND -> {
                @Suppress("DEPRECATION")
                val stream = intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM)
                if (stream != null) app.scope.launch { importAndOpen(listOf(stream)) }
                else intent.getStringExtra(Intent.EXTRA_TEXT)?.let { text ->
                    val rec = app.importText(text, intent.getStringExtra(Intent.EXTRA_SUBJECT))
                    if (rec != null) nav.openReader(app, rec.id)
                }
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                @Suppress("DEPRECATION")
                val list = intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM) ?: return
                app.scope.launch { app.importUris(list) }
            }
        }
    }

    private suspend fun importAndOpen(uris: List<Uri>) {
        val before = app.store.documents.value.map { it.id }.toSet()
        if (app.importUris(uris) == 1) {
            app.store.documents.value.firstOrNull { it.id !in before }?.let { nav?.openReader(app, it.id) }
        }
    }
}

/** wisepath://book/<id> · wisepath://play · wisepath://pause · wisepath://mark · wisepath://ride · wisepath://stats … */
object DeepLinks {
    fun handle(app: AppModel, nav: NavHostController, uri: Uri) {
        when (uri.host) {
            "book" -> uri.pathSegments.firstOrNull()?.let { nav.openReader(app, it) }
            "play" -> app.remotePlay()
            "pause" -> app.player.pause()
            "toggle" -> app.player.toggle()
            "mark" -> app.markSpokenSentence()
            "note" -> app.toggleVoiceNote()
            "continue" -> app.currentDocument?.let { nav.openReader(app, it.id); app.player.play() }
            "ride" -> { app.settings.bikeMode = true; app.currentDocument?.let { nav.openReader(app, it.id) } ?: nav.navigate(Routes.RIDE) }
            "stats" -> nav.navigate(Routes.STATS)
            "notes" -> nav.navigate(Routes.NOTES)
            "automation" -> nav.navigate(Routes.AUTOMATION)
            "music" -> nav.navigate(Routes.MUSIC)
        }
    }
}
