// Yolda: the moving modes' road screen (port of RideView.swift). One OLED-black page: on top only a quiet line
// (clock · battery · speed; a tap shows the way's time · km · calories large), the book and the chapter at the bottom;
// in the middle the last sentences as they are heard (Yolda) or the heard words set as kinetic type (Kinetik). The
// GPS record runs as long as the moving mode is on (WorkoutService), also with the screen off. Marking (a tap
// anywhere, the big key, the headphone's ⏭), a voice note, the speed and the chapters are always at hand; a long
// press on the library key switches the book. Tam metin opens the reader (the record goes on); Klasik is the reader's
// light page with the three bicycle keys.
package com.fatihgocgun.wisepath.move

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Description
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Haptics
import com.fatihgocgun.wisepath.music.KineticListening
import com.fatihgocgun.wisepath.music.MusicModeScreen
import com.fatihgocgun.wisepath.settings.BikeLook
import com.fatihgocgun.wisepath.ui.LocalAccent
import com.fatihgocgun.wisepath.ui.LocalReaderTheme
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/** The moving modes' road screen (bicycle / walk): GPS record, last sentences or kinetic words, big keys. */
@Composable
fun RideScreen(onExit: () -> Unit, onOpenReader: () -> Unit) {
    val context = LocalContext.current
    val app = remember { AppModel.get(context) }
    val s = app.settings
    var music by remember { mutableStateOf(false) }

    // the record needs the location (and, for the steps, the activity) permission; asked here, once per visit
    val launcher = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { _ ->
        if (Workouts.hasLocationPermission(context)) WorkoutService.start(context)
        else Workouts.status = "Konum izni yok: Ayarlar › Uygulamalar › Wise Path › İzinler"
    }
    LaunchedEffect(Unit) {
        Workouts.attach(context)
        if (!s.bikeMode) s.bikeMode = true
        // back from the full text: the road screen again
        if (s.bikeLook == BikeLook.full) s.bikeLook = BikeLook.focus
        val need = buildList {
            add(Manifest.permission.ACCESS_FINE_LOCATION); add(Manifest.permission.ACCESS_COARSE_LOCATION)
            if (Build.VERSION.SDK_INT >= 29) add(Manifest.permission.ACTIVITY_RECOGNITION)
        }.filter { ContextCompat.checkSelfPermission(context, it) != PackageManager.PERMISSION_GRANTED }
        if (Workouts.hasLocationPermission(context)) WorkoutService.start(context)
        if (need.isNotEmpty()) launcher.launch(need.toTypedArray())
    }
    // the screen stays awake on the handlebar
    val view = LocalView.current
    DisposableEffect(Unit) { view.keepScreenOn = true; onDispose { view.keepScreenOn = false } }

    val exit = { WorkoutService.stop(context); onExit() }
    BackHandler(enabled = !music) { exit() }

    val day = rememberRideDay(app)
    CompositionLocalProvider(LocalRide provides RideColors(day)) {
        if (s.bikeLook == BikeLook.classic) ClassicRide(app, exit, onOpenReader) { music = true }
        else RoadScreen(app, exit, onOpenReader) { music = true }
    }
    if (music) {
        BackHandler { music = false }
        MusicModeScreen(onClose = { music = false })
    }
}

/** The jump the contents and the rest bar make: the reading place moves only by them. */
private fun jump(app: AppModel, offset: Int, play: Boolean) = app.player.moveCursor(offset, play = play)

@OptIn(ExperimentalFoundationApi::class, ExperimentalLayoutApi::class)
@Composable
private fun RoadScreen(app: AppModel, onExit: () -> Unit, onOpenReader: () -> Unit, onMusic: () -> Unit) {
    val r = LocalRide.current
    val scope = rememberCoroutineScope()
    val state = remember { RideState(scope) }
    val board = remember { mutableStateOf(false) }
    var switching by remember { mutableStateOf(false) }
    var contents by remember { mutableStateOf(false) }
    val kinetic = app.settings.bikeLook == BikeLook.kinetic
    val st by app.player.state.collectAsState()
    val context = LocalContext.current

    // the heard word's concept joins the sediment
    LaunchedEffect(Unit) { app.player.spoken.collect { state.heard(it.word) } }
    // the concepts are worked out once the text is there
    val textKey = "${st.documentID}·${app.player.nav.length}"
    LaunchedEffect(textKey) {
        state.reset()
        val text = app.player.nav.text
        if (text.isEmpty()) return@LaunchedEffect
        state.concepts = withContext(Dispatchers.Default) { RideConcepts.build(text) }
    }

    fun mark() {
        if (app.player.documentID == null) return
        val res = app.markSpokenSentence() ?: return
        state.marked(res)
    }

    BoxWithConstraints(Modifier.fillMaxSize().background(r.oled)) {
        val full = maxWidth
        val height = maxHeight
        val w = minOf(maxWidth, 520.dp)
        val density = LocalDensity.current
        RideTint(app)
        Box(Modifier.align(Alignment.TopCenter).width(w).fillMaxSize().padding(top = 96.dp, bottom = 244.dp)) {
            if (kinetic) {
                KineticListening(DpSize(w * 0.88f, maxOf(200.dp, height - 430.dp)), r.amber, r.paper, glow = !r.day,
                    mask = app.settings.kineticMask, page = r.oled, modifier = Modifier.align(Alignment.Center))
            } else {
                RestLayer(app, w, state.concepts, state.falling, Modifier.fillMaxSize().padding(horizontal = w * 0.07f))
            }
        }
        MarkBurst(state.falling, state.markPoint,
            with(density) { Offset(full.toPx() * 0.86f, height.toPx() - 150.dp.toPx()) })
        // anywhere on the page: a tap marks the sentence being heard
        Box(Modifier.fillMaxSize().padding(top = 70.dp, bottom = 96.dp).pointerInput(Unit) {
            detectTapGestures { p -> state.markPoint = Offset(p.x, p.y + 70.dp.toPx()); mark() }
        })
        // the chrome
        Column(Modifier.align(Alignment.TopCenter).width(w).fillMaxSize().systemBarsPadding()) {
            Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp).padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                // tap: leave (the library); hold: the books to switch to
                Box(Modifier.size(44.dp, 40.dp).border(1.dp, r.edge, CircleShape)
                    .combinedClickable(onClick = onExit, onLongClick = { Haptics.tick(context, true); switching = true }),
                    contentAlignment = Alignment.Center) {
                    Icon(Icons.AutoMirrored.Filled.LibraryBooks, "Kütüphane", tint = r.muted, modifier = Modifier.size(20.dp))
                }
                Ghost(Icons.AutoMirrored.Filled.List, "İçindekiler") { contents = true }
                Spacer(Modifier.weight(1f))
                RoadStatus(app, Modifier.widthIn(max = 220.dp).clickable { board.value = !board.value }.padding(vertical = 6.dp),
                    ink = r.muted, dim = r.dim)
                Spacer(Modifier.weight(1f))
                Ghost(Icons.Filled.Description, "Tam metne geç (yol kaydı sürer)") { app.settings.bikeLook = BikeLook.full; onOpenReader() }
                MoveModeMenu(app, r.amber, 24.dp, onOpenReader, onMusic, onExit)
            }
            Spacer(Modifier.weight(1f))
            if (!kinetic) Sediment(state, w)
            Box(Modifier.fillMaxWidth().padding(bottom = 10.dp), contentAlignment = Alignment.Center) {
                RestBar(app) { o, play -> jump(app, o, play) }
            }
            RideBookLine(app, { contents = true }, Modifier.padding(horizontal = w * 0.06f).padding(bottom = 6.dp))
            RideProgress(app, Modifier.padding(horizontal = w * 0.06f).padding(bottom = 10.dp))
            Box(Modifier.padding(horizontal = 10.dp).padding(bottom = 8.dp)) { RideDock(app, state, ::mark) }
        }
        AnimatedVisibility(state.toast != null, Modifier.align(Alignment.TopCenter).padding(top = w * 0.2f), enter = fadeIn(), exit = fadeOut()) {
            Text(state.toast ?: "", Modifier.background(r.well, RoundedCornerShape(50)).border(1.dp, r.gold.copy(alpha = 0.35f), RoundedCornerShape(50))
                .padding(horizontal = 14.dp, vertical = 7.dp), color = r.gold, fontFamily = RideColors.mono, fontSize = 13.sp)
        }
        MoveBoard(app, board)
    }
    if (switching) BookSwitchSheet(app) { switching = false }
    if (contents) RideContents(app, { o, play -> jump(app, o, play) }) { contents = false }
}

@Composable
private fun Ghost(icon: ImageVector, label: String, action: () -> Unit) {
    val r = LocalRide.current
    Box(Modifier.size(44.dp, 40.dp).border(1.dp, r.edge, CircleShape).clickable(onClick = action), contentAlignment = Alignment.Center) {
        Icon(icon, label, tint = r.muted, modifier = Modifier.size(20.dp))
    }
}

/** The concepts heard this ride, quietly settled at the bottom; at most two lines, older ones paler; the marks' leaves. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Sediment(state: RideState, w: Dp) {
    val r = LocalRide.current
    val recent = state.sediment.takeLast(10)
    val size = with(LocalDensity.current) { (w * 0.039f).toSp() }
    Row(Modifier.fillMaxWidth().padding(horizontal = w * 0.06f).padding(bottom = 8.dp), verticalAlignment = Alignment.Bottom) {
        FlowRow(Modifier.weight(1f).heightIn(max = w * 0.17f), horizontalArrangement = Arrangement.spacedBy(w * 0.03f)) {
            recent.forEachIndexed { i, c ->
                Text(c, color = r.muted.copy(alpha = if (i < recent.size - 4) 0.45f else 1f), fontFamily = RideColors.serif, fontSize = size)
            }
        }
        Row(horizontalArrangement = Arrangement.spacedBy(w * 0.012f)) {
            repeat(minOf(state.leaves, 6)) { LeafDot(r.gold, w * 0.024f, w * 0.034f) }
        }
    }
}

/**
 * Klasik: the reader's own light page with the way's strip (on a tap), the sentences heard so far and the three
 * bicycle keys. A tap on the text marks the sentence being heard.
 */
@Composable
private fun ClassicRide(app: AppModel, onExit: () -> Unit, onOpenReader: () -> Unit, onMusic: () -> Unit) {
    val theme = LocalReaderTheme.current
    val accent = LocalAccent.current
    val st by app.player.state.collectAsState()
    val spoken by app.player.spoken.collectAsState()
    app.store.documents.collectAsState().value
    var details by remember { mutableStateOf(false) }
    val nav = app.player.nav
    Column(Modifier.fillMaxSize().background(theme.background).systemBarsPadding()) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(44.dp, 40.dp).clickable(onClick = onExit), contentAlignment = Alignment.Center) {
                Icon(Icons.AutoMirrored.Filled.LibraryBooks, "Kütüphane", tint = theme.text.copy(alpha = 0.7f))
            }
            Text(st.title, Modifier.weight(1f).clickable { details = !details }, color = theme.text, fontWeight = FontWeight.SemiBold,
                fontSize = 15.sp, maxLines = 1)
            MoveModeMenu(app, accent, 22.dp, onOpenReader, onMusic, onExit)
        }
        AnimatedVisibility(details, enter = slideInVertically() + fadeIn(), exit = slideOutVertically() + fadeOut()) {
            LaunchedEffect(Unit) { kotlinx.coroutines.delay(6000); details = false }
            Box(Modifier.padding(horizontal = 8.dp).background(theme.chrome.copy(alpha = 0.94f), RoundedCornerShape(16.dp)).clickable { details = false }) {
                MoveStripRow(app, theme.text, theme.text.copy(alpha = 0.6f))
            }
        }
        // the sentence being heard and the two before it, on the reader's page
        val cur = spoken.sentence ?: nav.sentenceRange(st.cursor)
        val list = buildList {
            if (cur != null) {
                var at = cur.first
                repeat(2) { val p = nav.sentenceBefore(at) ?: return@repeat; if (p.first < at) { add(0, p); at = p.first } }
                add(cur)
            }
        }
        Column(Modifier.weight(1f).fillMaxWidth().padding(24.dp).pointerInput(Unit) { detectTapGestures { app.markSpokenSentence() } },
            verticalArrangement = Arrangement.spacedBy(14.dp, Alignment.Bottom)) {
            list.forEach { rg ->
                val now = rg == cur
                Text(nav.substring(rg).trim(), Modifier.fillMaxWidth().background(
                    if (app.isMarked(rg)) Color(0x66FFE066) else Color.Transparent, RoundedCornerShape(6.dp)),
                    color = theme.text.copy(alpha = if (now) 1f else 0.5f), fontFamily = app.settings.font.family,
                    fontSize = app.settings.fontSize.sp, lineHeight = (app.settings.fontSize * 1.35).sp)
            }
        }
        BikeBar(app, theme.hairline, accent)
    }
}
