// The reading screen, laid out like Voice Dream (port of Views/ReaderScreen.swift): a top bar (back, title, the
// settings that own their icons: speaker → Ses Ayarları, Aa → Görsel Ayarlar, list → Konumlar), the page, and a
// bottom bar (contents · back · play · forward · search, the progress bar, % · chapter · skip unit · speed · sleep).
package com.fatihgocgun.wisepath.ui.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.FormatSize
import androidx.compose.material.icons.filled.List
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.SkipNext
import androidx.compose.material.icons.filled.SkipPrevious
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.navigation.NavHostController
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.settings.NavigationUnit
import com.fatihgocgun.wisepath.speech.SleepTimer
import com.fatihgocgun.wisepath.ui.LocalReaderTheme
import com.fatihgocgun.wisepath.ui.Palette
import com.fatihgocgun.wisepath.ui.Routes
import com.fatihgocgun.wisepath.ui.Slots

private enum class Sheet { audio, visual, places, search, selection, speed }

@Composable
fun ReaderScreen(app: AppModel, nav: NavHostController) {
    val state by app.player.state.collectAsState()
    val spoken = app.player.spoken.collectAsState()
    val docs by app.store.documents.collectAsState()
    val notes by app.notes.notes.collectAsState()
    val theme = LocalReaderTheme.current
    val doc = docs.firstOrNull { it.id == state.documentID }
    var sheet by remember { mutableStateOf<Sheet?>(null) }
    var selection by remember { mutableStateOf<IntRange?>(null) }
    val listState = rememberLazyListState()
    val follow = remember { PageFollow() }
    var revealAt by remember { mutableStateOf<Int?>(null) }

    DisposableEffect(Unit) {
        app.readerOpen = true
        onDispose { app.readerOpen = false }
    }
    // the moving modes have their own screen
    LaunchedEffect(app.settings.bikeMode) { if (app.settings.bikeMode) nav.navigate(Routes.RIDE) { launchSingleTop = true } }
    // a place asked from outside (search hit, note, mark): shown, the reading place stays
    LaunchedEffect(app.revealRequest) {
        val r = app.revealRequest ?: return@LaunchedEffect
        if (r.first == state.documentID) { revealAt = r.second; app.revealRequest = null }
    }
    // pressing play follows the voice again
    LaunchedEffect(state.isPlaying) { if (state.isPlaying) follow.following = true }

    if (doc == null) {
        Box(Modifier.fillMaxSize().background(theme.background), contentAlignment = Alignment.Center) { Text("Önce bir kitap aç") }
        return
    }
    val nav2 = app.player.nav
    val docNotes = remember(notes, doc.id) { notes.filter { it.doc == doc.id }.map { it.location }.toSet() }

    Box(Modifier.fillMaxSize().background(theme.background)) {
        Column(Modifier.fillMaxSize()) {
            TopBar(app, doc.title, onBack = { nav.popBackStack() }, onAudio = { sheet = Sheet.audio }, onVisual = { sheet = Sheet.visual },
                onPlaces = { sheet = Sheet.places }, onSearch = { sheet = Sheet.search }, onMusic = { nav.navigate(Routes.MUSIC) },
                onRide = { app.settings.bikeMode = true })
            Box(Modifier.weight(1f)) {
                ReaderText(
                    nav = nav2, spoken = spoken, highlights = doc.highlights, noteMarks = docNotes, settings = app.settings, theme = theme,
                    playing = state.isPlaying, listState = listState, follow = follow, reveal = revealAt, onRevealed = { revealAt = null },
                    onTap = { at ->
                        // a tap on a word reads from there (paused: the place moves there)
                        val w = nav2.wordRange(at)
                        app.player.moveCursor(w.first, play = state.isPlaying)
                    },
                    onLongPress = { at -> selection = nav2.sentenceRange(at); sheet = Sheet.selection },
                    contentPadding = PaddingValues(top = 12.dp, bottom = 120.dp),
                )
                if (!follow.following && state.isSpeaking) {
                    Surface(
                        onClick = { follow.following = true; revealAt = null },
                        shape = CircleShape, color = MaterialTheme.colorScheme.primary, shadowElevation = 6.dp,
                        modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = 16.dp),
                    ) {
                        Row(Modifier.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.MyLocation, null, tint = Color.White, modifier = Modifier.size(16.dp))
                            Spacer(Modifier.width(8.dp))
                            Text("Konuşma imlecine git", color = Color.White)
                        }
                    }
                }
                Box(Modifier.align(Alignment.BottomEnd).padding(16.dp)) { Slots.micButton() }
            }
            PlayerBar(app, onPlaces = { sheet = Sheet.places }, onSearch = { sheet = Sheet.search }, onSpeed = { sheet = Sheet.speed })
        }
        Slots.noteOverlays()
    }

    when (sheet) {
        Sheet.audio -> AudioSettingsSheet(app, nav) { sheet = null }
        Sheet.visual -> VisualSettingsSheet(app) { sheet = null }
        Sheet.places -> PlacesSheet(app, doc, onDismiss = { sheet = null }, onGo = { at, play ->
            sheet = null
            if (play) app.player.moveCursor(at, play = true) else { revealAt = at }
        }, onMove = { at -> sheet = null; app.player.moveCursor(at); follow.following = true })
        Sheet.search -> SearchSheet(app, onDismiss = { sheet = null }) { at -> sheet = null; revealAt = at }
        Sheet.speed -> SpeedSheet(app) { sheet = null }
        Sheet.selection -> selection?.let { r -> SelectionSheet(app, nav, doc, r, onChange = { selection = it }) { sheet = null; selection = null } }
        null -> {}
    }
}

@Composable
private fun TopBar(
    app: AppModel, title: String, onBack: () -> Unit, onAudio: () -> Unit, onVisual: () -> Unit, onPlaces: () -> Unit,
    onSearch: () -> Unit, onMusic: () -> Unit, onRide: () -> Unit,
) {
    val theme = LocalReaderTheme.current
    val accent = MaterialTheme.colorScheme.primary
    val s by app.player.state.collectAsState()
    val doc = app.currentDocument
    val marked = doc?.bookmarks?.any { kotlin.math.abs(it.offset - s.cursor) < 40 } == true
    var more by remember { mutableStateOf(false) }
    Surface(color = theme.chrome, shadowElevation = 1.dp) {
        Row(Modifier.fillMaxWidth().statusBarsPadding().height(52.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Kütüphane", tint = accent) }
            Text(title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis, fontWeight = FontWeight.SemiBold,
                color = theme.text, textAlign = TextAlign.Center)
            IconButton(onClick = onAudio) { Icon(Icons.AutoMirrored.Filled.VolumeUp, "Ses Ayarları", tint = accent) }
            IconButton(onClick = onVisual) { Icon(Icons.Default.FormatSize, "Görsel Ayarlar", tint = accent) }
            IconButton(onClick = {
                val d = app.currentDocument ?: return@IconButton
                val b = d.bookmarks.firstOrNull { kotlin.math.abs(it.offset - s.cursor) < 40 }
                if (b != null) app.removeBookmark(b.id) else app.addBookmark()
            }) { Icon(if (marked) Icons.Default.Bookmark else Icons.Default.BookmarkBorder, "Yer imi", tint = accent) }
            Box {
                IconButton(onClick = { more = true }) { Icon(Icons.Default.MusicNote, "Diğer", tint = accent) }
                DropdownMenu(more, onDismissRequest = { more = false }) {
                    DropdownMenuItem(text = { Text("Müzik modu") }, leadingIcon = { Icon(Icons.Default.MusicNote, null) }, onClick = { more = false; onMusic() })
                    DropdownMenuItem(text = { Text("Yolda (bisiklet / yürüyüş)") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.DirectionsBike, null) }, onClick = { more = false; onRide() })
                    DropdownMenuItem(text = { Text("Konumlar") }, leadingIcon = { Icon(Icons.Default.List, null) }, onClick = { more = false; onPlaces() })
                    DropdownMenuItem(text = { Text("Belgede ara") }, leadingIcon = { Icon(Icons.Default.Search, null) }, onClick = { more = false; onSearch() })
                }
            }
        }
    }
}

@Composable
fun PlayKey(playing: Boolean, size: Int = 64, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = CircleShape, color = Palette.play, shadowElevation = 3.dp, modifier = Modifier.size(size.dp)) {
        Box(contentAlignment = Alignment.Center) {
            Icon(if (playing) Icons.Default.Pause else Icons.Default.PlayArrow, if (playing) "Duraklat" else "Oynat",
                tint = Color.White, modifier = Modifier.size((size * 0.55).dp))
        }
    }
}

@Composable
private fun PlayerBar(app: AppModel, onPlaces: () -> Unit, onSearch: () -> Unit, onSpeed: () -> Unit) {
    val theme = LocalReaderTheme.current
    val accent = MaterialTheme.colorScheme.primary
    val s by app.player.state.collectAsState()
    var unitMenu by remember { mutableStateOf(false) }
    var sleepMenu by remember { mutableStateOf(false) }
    var dragging by remember { mutableStateOf(false) }
    var drag by remember { mutableFloatStateOf(0f) }
    val nav = app.player.nav
    val unit = app.settings.navigationUnit
    Surface(color = theme.chrome, shadowElevation = 4.dp) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding().padding(horizontal = 12.dp, vertical = 4.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onPlaces) { Icon(Icons.Default.List, "İçindekiler", tint = accent) }
                IconButton(onClick = { app.player.skip(false, unit) }, modifier = Modifier.size(52.dp)) {
                    Icon(Icons.Default.SkipPrevious, "Geri: ${unit.label}", tint = accent, modifier = Modifier.size(34.dp))
                }
                PlayKey(s.isPlaying) { app.player.toggle() }
                IconButton(onClick = { app.player.skip(true, unit) }, modifier = Modifier.size(52.dp)) {
                    Icon(Icons.Default.SkipNext, "İleri: ${unit.label}", tint = accent, modifier = Modifier.size(34.dp))
                }
                IconButton(onClick = onSearch) { Icon(Icons.Default.Search, "Ara", tint = accent) }
            }
            // the progress bar moves the place only when let go
            Slider(
                value = if (dragging) drag else s.progress,
                onValueChange = { dragging = true; drag = it },
                onValueChangeFinished = {
                    dragging = false
                    val at = (drag * nav.length).toInt().coerceIn(0, maxOf(0, nav.length - 1))
                    app.player.moveCursor(nav.sentenceStart(at + 1))
                },
                colors = SliderDefaults.colors(thumbColor = accent, activeTrackColor = accent),
                modifier = Modifier.fillMaxWidth().height(28.dp),
            )
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                val shownAt = if (dragging) (drag * nav.length).toInt() else s.cursor
                val pct = if (nav.length > 0) shownAt * 100 / nav.length else 0
                Text("%$pct", style = MaterialTheme.typography.labelMedium, color = theme.text.copy(alpha = 0.7f))
                Spacer(Modifier.width(8.dp))
                Text(nav.chapterTitle(shownAt) ?: Format.duration(app.player.remainingSeconds) + " kaldı", Modifier.weight(1f),
                    style = MaterialTheme.typography.labelMedium, maxLines = 1, overflow = TextOverflow.Ellipsis, color = theme.text.copy(alpha = 0.7f))
                Chip("${"%.2f".format(s.speed).trimEnd('0').trimEnd(',', '.')}×", accent, onSpeed)
                Spacer(Modifier.width(6.dp))
                Box {
                    Chip(unit.label, accent) { unitMenu = true }
                    DropdownMenu(unitMenu, onDismissRequest = { unitMenu = false }) {
                        NavigationUnit.entries.forEach { u ->
                            DropdownMenuItem(text = { Text(u.label + if (u == unit) "  ✓" else "") }, onClick = { app.settings.navigationUnit = u; unitMenu = false })
                        }
                    }
                }
                Spacer(Modifier.width(2.dp))
                Box {
                    IconButton(onClick = { sleepMenu = true }, modifier = Modifier.size(36.dp)) {
                        Icon(Icons.Default.Bedtime, "Uyku zamanlayıcısı", tint = if (s.sleepTimer != SleepTimer.Off) Palette.play else accent, modifier = Modifier.size(20.dp))
                    }
                    DropdownMenu(sleepMenu, onDismissRequest = { sleepMenu = false }) {
                        s.sleepEnds?.let { e ->
                            Text("Kalan: " + Format.clock((e - System.currentTimeMillis()) / 1000.0), Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
                                style = MaterialTheme.typography.labelMedium)
                        }
                        listOf(5, 10, 15, 30, 45, 60, 90).forEach { m ->
                            DropdownMenuItem(text = { Text("$m dakika") }, onClick = { app.player.setSleepTimer(SleepTimer.Minutes(m)); sleepMenu = false })
                        }
                        DropdownMenuItem(text = { Text("Bölümün sonunda") }, onClick = { app.player.setSleepTimer(SleepTimer.EndOfChapter); sleepMenu = false })
                        HorizontalDivider()
                        DropdownMenuItem(text = { Text("Kapalı") }, onClick = { app.player.setSleepTimer(SleepTimer.Off); sleepMenu = false })
                    }
                }
            }
            if (s.breakEnds != null) {
                Row(Modifier.fillMaxWidth().padding(bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (s.breakKind == com.fatihgocgun.wisepath.speech.BreakKind.music) "Müzik arası" else "Aktif bekleme", Modifier.weight(1f),
                        style = MaterialTheme.typography.labelMedium, color = Palette.play)
                    Chip("Şimdi devam et", accent) { app.player.cancelWait(); app.player.play(app.player.cursor, snap = false) }
                }
            }
        }
    }
}

@Composable
fun Chip(text: String, color: Color, onClick: () -> Unit) {
    Surface(onClick = onClick, shape = RoundedCornerShape(12.dp), color = color.copy(alpha = 0.12f)) {
        Text(text, Modifier.padding(horizontal = 10.dp, vertical = 5.dp), style = MaterialTheme.typography.labelMedium, color = color, fontWeight = FontWeight.SemiBold)
    }
}
