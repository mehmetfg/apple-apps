// Notlarım (port of NotesScreen.swift): every note in one place, apart from the books, each one showing the book and
// the sentence it belongs to. Listen in the row, read the text, open the note, or go to its place in the book. Going
// there only brings the sentence on screen; the reading place stays where it is.
package com.fatihgocgun.wisepath.notes

import android.media.AudioAttributes
import android.media.MediaPlayer
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.TextFold
import com.fatihgocgun.wisepath.stats.Segmented
import com.fatihgocgun.wisepath.stats.StatCover
import com.fatihgocgun.wisepath.ui.Page
import com.fatihgocgun.wisepath.ui.Palette
import java.io.File

/** One note plays at a time (the list's play keys, the note sheet). */
class NoteAudio {
    var playingID by mutableStateOf<String?>(null)
        private set
    private var player: MediaPlayer? = null

    fun toggle(id: String, file: File?) {
        if (playingID == id) { stop(); return }
        stop()
        if (file == null || !file.exists()) return
        val p = MediaPlayer()
        runCatching {
            p.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            p.setDataSource(file.path)
            p.setOnCompletionListener { if (player === it) stop() }
            p.prepare()
            p.start()
            player = p
            playingID = id
        }.onFailure { runCatching { p.release() } }
    }

    fun stop() {
        player?.let { runCatching { it.stop() }; runCatching { it.release() } }
        player = null
        playingID = null
    }
}

/** The library's link to Notlarım: how many voice and written notes, and the book of the latest. */
@Composable
fun NotesCard(onOpenNotes: () -> Unit) {
    val app = AppModel.get(LocalContext.current)
    val all by app.notes.notes.collectAsState()
    val voice = all.count { it.hasVoice }
    Row(
        Modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(RoundedCornerShape(22.dp))
            .background(MaterialTheme.colorScheme.surfaceContainerHigh).clickable(onClick = onOpenNotes).padding(16.dp)
            .semantics { contentDescription = "Notlarım: ${all.size} not, $voice sesli" },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(44.dp).clip(RoundedCornerShape(12.dp)).background(MaterialTheme.colorScheme.primary), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.GraphicEq, null, tint = Color.White, modifier = Modifier.size(22.dp))
        }
        Spacer(Modifier.width(14.dp))
        Column(Modifier.weight(1f)) {
            Text("Notlarım", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(
                if (all.isEmpty()) "Okurken 🎙 ile söylediklerin burada toplanır"
                else "$voice sesli · ${all.size - voice} yazılı" + (all.firstOrNull()?.let { " · son: " + it.bookTitle } ?: ""),
                fontSize = 13.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis,
            )
        }
        Icon(Icons.Filled.ChevronRight, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f))
    }
}

private enum class Kind(val label: String) { all("Hepsi"), voice("Sesli"), text("Yazılı") }
private enum class Order { date, book }

/** Every note in one place; a row plays the voice note, opens the note, or shows its place in the book. */
@Composable
fun NotesScreen(onBack: () -> Unit, onOpenPlace: (doc: String, offset: Int) -> Unit) {
    val app = AppModel.get(LocalContext.current)
    val all by app.notes.notes.collectAsState()
    val docs by app.store.documents.collectAsState()
    var kind by remember { mutableStateOf(Kind.all) }
    var order by remember { mutableStateOf(Order.date) }
    var query by remember { mutableStateOf("") }
    var sheet by remember { mutableStateOf<String?>(null) }
    var orderMenu by remember { mutableStateOf(false) }
    val audio = remember { NoteAudio() }
    DisposableEffect(Unit) { onDispose { audio.stop() } }

    val q = TextFold.fold(query.trim())
    val shown = all.filter {
        when (kind) { Kind.all -> true; Kind.voice -> it.hasVoice; Kind.text -> !it.hasVoice }
    }.filter { n -> q.isEmpty() || listOf(n.text, n.quote, n.bookTitle, n.chapterTitle ?: "").any { TextFold.fold(it).contains(q) } }

    val open: (ReaderNote) -> Unit = { n -> if (docs.any { it.id == n.doc }) { audio.stop(); onOpenPlace(n.doc, n.location) } }

    Page("Notlarım", onBack, actions = {
        Box {
            IconButton(onClick = { orderMenu = true }) {
                Icon(if (order == Order.date) Icons.Filled.CalendarMonth else Icons.AutoMirrored.Filled.LibraryBooks, "Sırala")
            }
            DropdownMenu(orderMenu, onDismissRequest = { orderMenu = false }) {
                DropdownMenuItem(text = { Text("Tarihe göre") }, leadingIcon = { Icon(Icons.Filled.CalendarMonth, null) },
                    onClick = { order = Order.date; orderMenu = false })
                DropdownMenuItem(text = { Text("Kitaba göre") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.LibraryBooks, null) },
                    onClick = { order = Order.book; orderMenu = false })
            }
        }
    }) { pad ->
        LazyColumn(
            Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background).padding(pad),
            contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
            verticalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            item {
                OutlinedTextField(
                    query, { query = it }, Modifier.fillMaxWidth(), singleLine = true,
                    placeholder = { Text("Notta, cümlede ya da kitapta ara") },
                    leadingIcon = { Icon(Icons.Filled.Search, null) }, shape = RoundedCornerShape(12.dp),
                )
            }
            item { Segmented(Kind.entries.map { it to it.label }, kind) { kind = it } }
            if (shown.isEmpty()) {
                item {
                    Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Icon(Icons.Filled.Mic, null, tint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.4f), modifier = Modifier.size(40.dp))
                        Text(if (query.isEmpty()) "Not yok" else "Bulunamadı", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                        if (query.isEmpty()) Text(
                            "Okurken 🎙 düğmesini basılı tut ya da bisiklette ⏮'e bas: not, okunan cümleye bağlanır.",
                            fontSize = 14.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f),
                            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                        )
                    }
                }
            } else if (order == Order.book) {
                val groups = shown.groupBy { it.doc }.entries.sortedByDescending { e -> e.value.maxOf { it.stamp } }
                groups.forEach { (doc, ns) ->
                    item(key = "h-$doc") { BookHeader(app, doc, ns.first().bookTitle, ns.size) }
                    item(key = "g-$doc") {
                        Group { ns.sortedBy { it.location }.forEachIndexed { i, n ->
                            if (i > 0) RowDivider()
                            NoteRow(app, n, showsBook = false, bookExists = docs.any { it.id == n.doc }, audio, open, { sheet = n.id })
                        } }
                    }
                }
            } else {
                val days = shown.groupBy { Format.localDate(it.date) }.entries.sortedByDescending { it.key }
                days.forEach { (day, ns) ->
                    item(key = "d-$day") {
                        Text(Format.day(day, "EEEE, d MMMM"), fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f), modifier = Modifier.padding(start = 6.dp, top = 8.dp))
                    }
                    item(key = "n-$day") {
                        Group { ns.sortedByDescending { it.date }.forEachIndexed { i, n ->
                            if (i > 0) RowDivider()
                            NoteRow(app, n, showsBook = true, bookExists = docs.any { it.id == n.doc }, audio, open, { sheet = n.id })
                        } }
                    }
                }
            }
        }
    }
    sheet?.let { id -> NoteSheet(id, onDismiss = { sheet = null }) }
}

@Composable
private fun Group(content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.surfaceContainerHigh)) { content() }
}

@Composable
private fun RowDivider() = HorizontalDivider(Modifier.padding(start = 68.dp), color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))

@Composable
private fun BookHeader(app: AppModel, doc: String, title: String, count: Int) {
    val record = app.store.document(doc)
    Row(Modifier.padding(start = 6.dp, top = 8.dp, bottom = 2.dp), verticalAlignment = Alignment.CenterVertically) {
        if (record != null) { StatCover(record, 28.dp); Spacer(Modifier.width(10.dp)) }
        Column {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
            Text("$count not" + if (record == null) " · kitap kütüphanede yok" else "", fontSize = 12.sp,
                color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun NoteRow(
    app: AppModel, n: ReaderNote, showsBook: Boolean, bookExists: Boolean, audio: NoteAudio,
    onOpenPlace: (ReaderNote) -> Unit, onOpenNote: () -> Unit,
) {
    val playing = audio.playingID == n.id
    var menu by remember { mutableStateOf(false) }
    val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
    val accent = MaterialTheme.colorScheme.primary
    Box {
        Row(
            Modifier.fillMaxWidth().combinedClickable(onClick = onOpenNote, onLongClick = { menu = true })
                .padding(horizontal = 14.dp, vertical = 12.dp),
        ) {
            if (n.hasVoice) {
                Box(
                    Modifier.size(40.dp).clip(CircleShape).background(Palette.play).clickable {
                        if (app.player.isPlaying) app.player.pause()
                        audio.toggle(n.id, app.notes.audioFile(n))
                    }.semantics { contentDescription = if (playing) "Duraklat" else "Sesli notu dinle" },
                    contentAlignment = Alignment.Center,
                ) { Icon(if (playing) Icons.Filled.Pause else Icons.Filled.PlayArrow, null, tint = Color.White, modifier = Modifier.size(20.dp)) }
            } else {
                Box(Modifier.size(40.dp), contentAlignment = Alignment.Center) { Icon(Icons.Filled.Description, null, tint = accent) }
            }
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Text(n.text.ifEmpty { "Yazıya dökülmedi" }, fontSize = 15.sp, maxLines = 4, overflow = TextOverflow.Ellipsis,
                    color = if (n.text.isEmpty()) dim else MaterialTheme.colorScheme.onSurface)
                Text("“${n.quote}”", fontSize = 13.sp, fontFamily = FontFamily.Serif, fontStyle = FontStyle.Italic, color = dim,
                    maxLines = 2, overflow = TextOverflow.Ellipsis)
                Row(
                    Modifier.clip(RoundedCornerShape(6.dp)).clickable(enabled = bookExists) { onOpenPlace(n) }
                        .semantics { contentDescription = if (bookExists) "Kitapta, bu cümlede aç: ${n.bookTitle}" else n.bookTitle },
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val c = if (bookExists) accent else dim
                    Icon(Icons.AutoMirrored.Filled.MenuBook, null, tint = c, modifier = Modifier.size(12.dp))
                    Spacer(Modifier.width(5.dp))
                    Text(if (showsBook) n.bookTitle else n.chapterTitle ?: "Kitaptaki yeri", fontSize = 12.sp, fontWeight = FontWeight.Medium,
                        color = c, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (bookExists) { Spacer(Modifier.width(4.dp)); Icon(Icons.Filled.NorthEast, null, tint = c, modifier = Modifier.size(11.dp)) }
                }
                Text((if (n.hasVoice) Format.clock(n.seconds ?: 0.0) + " · " else "") + Format.date(n.date, "HH:mm"),
                    fontSize = 12.sp, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f))
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            if (bookExists) DropdownMenuItem(text = { Text("Kitapta, bu cümlede aç") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.MenuBook, null) },
                onClick = { menu = false; onOpenPlace(n) })
            DropdownMenuItem(text = { Text("Notu aç") }, leadingIcon = { Icon(Icons.Filled.EditNote, null) }, onClick = { menu = false; onOpenNote() })
            DropdownMenuItem(text = { Text("Sil", color = Color(0xFFE53935)) }, leadingIcon = { Icon(Icons.Filled.Delete, null, tint = Color(0xFFE53935)) },
                onClick = { menu = false; if (playing) audio.stop(); app.notes.delete(n.id) })
        }
    }
}
