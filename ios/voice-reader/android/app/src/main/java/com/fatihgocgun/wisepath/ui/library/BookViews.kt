@file:OptIn(androidx.compose.foundation.ExperimentalFoundationApi::class)
// The books in every library style (port of Bookshelf.swift, the DocumentCollection of LibraryScreen.swift,
// HomeShelf.swift's Akış, MarksSheet.swift): Kitaplık (spines on wooden shelves), Akış (covers flowing sideways),
// Vitrin / Izgara / Kapak duvarı / Kartlar / Kalan süre / Liste / Sıkı liste; and the menu every book carries.
package com.fatihgocgun.wisepath.ui.library

import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.model.HighlightColor
import com.fatihgocgun.wisepath.search.BookSearchSheet
import com.fatihgocgun.wisepath.settings.LibraryStyle
import com.fatihgocgun.wisepath.ui.Palette
import com.fatihgocgun.wisepath.ui.Routes
import com.fatihgocgun.wisepath.ui.openReader
import kotlin.math.abs
import kotlin.math.min

// MARK: - the collections

@Composable
fun DocumentCollection(app: AppModel, docs: List<DocumentRecord>, style: LibraryStyle, nav: NavHostController, onOpen: (String) -> Unit) {
    when (style) {
        LibraryStyle.flow -> CoverFlow(app, docs, nav, onOpen)
        LibraryStyle.shelf, LibraryStyle.grid, LibraryStyle.wall -> {
            val cols = when (style) { LibraryStyle.wall -> 4; LibraryStyle.grid -> 3; else -> 3 }
            Column(Modifier.padding(horizontal = 16.dp)) {
                docs.chunked(cols).forEach { row ->
                    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        row.forEach { d -> BookTile(app, d, nav, onOpen, Modifier.weight(1f), showText = style != LibraryStyle.wall) }
                        repeat(cols - row.size) { Spacer(Modifier.weight(1f)) }
                    }
                }
            }
        }
        LibraryStyle.cards, LibraryStyle.folders, LibraryStyle.remaining -> Column(Modifier.padding(horizontal = 16.dp)) {
            val list = if (style == LibraryStyle.remaining) docs.sortedBy { if (it.isFinished) Double.MAX_VALUE else app.duration(it.length - it.position, it.speed) } else docs
            list.forEach { d -> BookCard(app, d, nav, onOpen, remainingFirst = style == LibraryStyle.remaining) }
        }
        LibraryStyle.compact -> Column { docs.forEach { d -> CompactRow(app, d, nav, onOpen) } }
        else -> Column { docs.forEach { d -> LibraryRow(app, d, nav, onOpen) } }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BookTile(app: AppModel, d: DocumentRecord, nav: NavHostController, onOpen: (String) -> Unit, modifier: Modifier, showText: Boolean) {
    val s by app.player.state.collectAsState()
    var menu by remember { mutableStateOf(false) }
    Box(modifier) {
        Column(Modifier.combinedClickable(onClick = { onOpen(d.id) }, onLongClick = { menu = true })) {
            CoverView(d, Modifier.fillMaxWidth().aspectRatio(0.68f), playing = s.isPlaying && s.documentID == d.id)
            if (showText) {
                Spacer(Modifier.height(4.dp))
                Text(d.title, style = MaterialTheme.typography.labelMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                StateLabel(d)
            }
        }
        BookMenu(app, d, nav, menu) { menu = false }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun LibraryRow(app: AppModel, d: DocumentRecord, nav: NavHostController, onOpen: (String) -> Unit) {
    val s by app.player.state.collectAsState()
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().combinedClickable(onClick = { onOpen(d.id) }, onLongClick = { menu = true }).padding(horizontal = 16.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            CoverView(d, Modifier.size(44.dp, 64.dp), corner = 4.dp, playing = s.isPlaying && s.documentID == d.id)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    d.flag?.let { Box(Modifier.size(8.dp).clip(RoundedCornerShape(4.dp)).background(Color(it.argb))); Spacer(Modifier.width(6.dp)) }
                    Text(d.title, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                }
                Text(listOfNotNull(d.author, d.format.badge).joinToString(" · "), style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f), maxLines = 1)
                Spacer(Modifier.height(4.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    LinearProgressIndicator(progress = { d.progress.toFloat() }, modifier = Modifier.weight(1f).height(3.dp))
                    Spacer(Modifier.width(8.dp))
                    Text(app.statusText(d), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                }
            }
            if (d.highlights.isNotEmpty()) MarksChip(app, d)
        }
        BookMenu(app, d, nav, menu) { menu = false }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CompactRow(app: AppModel, d: DocumentRecord, nav: NavHostController, onOpen: (String) -> Unit) {
    var menu by remember { mutableStateOf(false) }
    Box {
        Row(
            Modifier.fillMaxWidth().combinedClickable(onClick = { onOpen(d.id) }, onLongClick = { menu = true }).padding(horizontal = 20.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(d.title, Modifier.weight(1f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            StateLabel(d)
        }
        HorizontalDivider(Modifier.padding(start = 20.dp).align(Alignment.BottomStart), color = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
        BookMenu(app, d, nav, menu) { menu = false }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun BookCard(app: AppModel, d: DocumentRecord, nav: NavHostController, onOpen: (String) -> Unit, remainingFirst: Boolean) {
    var menu by remember { mutableStateOf(false) }
    Box(Modifier.padding(vertical = 6.dp)) {
        Surface(shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surface, shadowElevation = 2.dp,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).combinedClickable(onClick = { onOpen(d.id) }, onLongClick = { menu = true })) {
            Row(Modifier.padding(12.dp)) {
                CoverView(d, Modifier.size(64.dp, 94.dp), corner = 4.dp)
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    if (remainingFirst && !d.isFinished) Text(Format.duration(app.duration(d.length - d.position, d.speed)) + " kaldı",
                        style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary, fontWeight = FontWeight.Bold)
                    Text(d.title, fontWeight = FontWeight.SemiBold, fontFamily = FontFamily.Serif, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    d.author?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) }
                    Spacer(Modifier.height(6.dp))
                    Text(listOfNotNull(d.folder, "${(d.wordCount / 225.0).toInt()} sayfa", app.statusText(d)).joinToString(" · "),
                        style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    Spacer(Modifier.height(6.dp))
                    LinearProgressIndicator(progress = { d.progress.toFloat() }, modifier = Modifier.fillMaxWidth().height(3.dp))
                }
            }
        }
        BookMenu(app, d, nav, menu) { menu = false }
    }
}

/** Akış: the covers flowing left and right, tilted, the one in the middle named below. */
@Composable
private fun CoverFlow(app: AppModel, docs: List<DocumentRecord>, nav: NavHostController, onOpen: (String) -> Unit) {
    val state = rememberLazyListState()
    val density = LocalDensity.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val itemW = 150.dp
        val side = (maxWidth - itemW) / 2
        val center by remember { derivedStateOf {
            val info = state.layoutInfo
            val mid = (info.viewportStartOffset + info.viewportEndOffset) / 2
            info.visibleItemsInfo.minByOrNull { abs(it.offset + it.size / 2 - mid) }?.index ?: 0
        } }
        Column {
            LazyRow(state = state, contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = side), horizontalArrangement = Arrangement.spacedBy((-24).dp),
                flingBehavior = androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior(state)) {
                items(docs.size, key = { docs[it].id }) { i ->
                    val d = docs[i]
                    val info = state.layoutInfo.visibleItemsInfo.firstOrNull { it.index == i }
                    val mid = (state.layoutInfo.viewportStartOffset + state.layoutInfo.viewportEndOffset) / 2f
                    val delta = info?.let { (it.offset + it.size / 2f - mid) / with(density) { itemW.toPx() } } ?: 0f
                    val t = delta.coerceIn(-1.5f, 1.5f)
                    Box(Modifier.width(itemW).graphicsLayer {
                        rotationY = -t * 40f
                        scaleX = 1f - min(0.25f, abs(t) * 0.2f); scaleY = scaleX
                        cameraDistance = 12f * density.density
                    }.clickable { onOpen(d.id) }) {
                        Column {
                            CoverView(d, Modifier.fillMaxWidth().aspectRatio(0.68f))
                            // the reflection
                            Box(Modifier.fillMaxWidth().height(40.dp).graphicsLayer { scaleY = -1f; alpha = 0.18f }) {
                                CoverView(d, Modifier.fillMaxWidth().aspectRatio(0.68f))
                            }
                        }
                    }
                }
            }
            docs.getOrNull(center)?.let { d ->
                Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(d.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(app.statusText(d), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                }
            }
        }
    }
}

// MARK: - Kitaplık: spines on shelves

/** The spine is as thick as the book is long. */
private fun spineWidth(d: DocumentRecord): Float = (14f + 26f * min(1f, d.wordCount / 160_000f)).coerceIn(16f, 40f)

@Composable
fun BookshelfView(app: AppModel, sections: List<BookshelfSection>, nav: NavHostController, onOpen: (String) -> Unit) {
    var picked by remember { mutableStateOf<DocumentRecord?>(null) }
    val s by app.player.state.collectAsState()
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val inner = maxWidth.value - 40f
        Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            sections.filter { it.docs.isNotEmpty() }.forEach { sec ->
                Column {
                    if (sections.size > 1) Row(Modifier.padding(horizontal = 20.dp, vertical = 4.dp), verticalAlignment = Alignment.Bottom) {
                        Text(sec.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
                        Spacer(Modifier.width(6.dp))
                        Text("${sec.docs.size}", style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f))
                    }
                    val rows = mutableListOf(mutableListOf<DocumentRecord>())
                    var used = 0f
                    for (d in sec.docs) {
                        val w = spineWidth(d) + 3
                        if (used + w > inner && rows.last().isNotEmpty()) { rows.add(mutableListOf()); used = 0f }
                        rows.last().add(d); used += w
                    }
                    rows.forEach { row ->
                        Column(Modifier.padding(horizontal = 14.dp)) {
                            Row(
                                Modifier.fillMaxWidth().background(Brush.verticalGradient(listOf(Color(0xFF2A1E14), Color(0xFF3B2A1C))), RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
                                    .padding(start = 6.dp, end = 6.dp, top = 10.dp),
                                horizontalArrangement = Arrangement.spacedBy(3.dp), verticalAlignment = Alignment.Bottom,
                            ) {
                                row.forEach { d -> Spine(d, playing = s.isPlaying && s.documentID == d.id) { picked = d } }
                            }
                            // the plank
                            Box(Modifier.fillMaxWidth().height(9.dp).background(Brush.verticalGradient(listOf(Color(0xFF8B5E3C), Color(0xFF5E3D24))), RoundedCornerShape(bottomStart = 3.dp, bottomEnd = 3.dp)))
                        }
                        Spacer(Modifier.height(6.dp))
                    }
                }
            }
        }
    }
    picked?.let { d -> PulledBook(app, d, nav, onOpen = { picked = null; onOpen(d.id) }, onDismiss = { picked = null }) }
}

@Composable
private fun Spine(d: DocumentRecord, playing: Boolean, onTap: () -> Unit) {
    val base = bookColor(d)
    val h = (118 + Math.floorMod(d.id.hashCode(), 26)).dp
    Box(
        Modifier.width(spineWidth(d).dp).height(h).clip(RoundedCornerShape(2.dp))
            .background(Brush.horizontalGradient(listOf(lerpColor(base, Color.Black, 0.25f), base, lerpColor(base, Color.White, 0.08f), base, lerpColor(base, Color.Black, 0.3f))))
            .clickable(onClick = onTap),
    ) {
        // title and author run down the spine
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(
                d.title, color = Color.White.copy(alpha = 0.92f), fontSize = 10.sp, fontFamily = FontFamily.Serif, maxLines = 1,
                overflow = TextOverflow.Ellipsis, softWrap = false,
                modifier = Modifier.width(h - 16.dp).rotate(90f),
            )
        }
        if (d.isFinished) Box(Modifier.align(Alignment.BottomCenter).padding(bottom = 10.dp).fillMaxWidth().height(4.dp).background(Palette.gold))
        else if (d.isInProgress) {
            // the progress strip along the spine and the ribbon from its top
            Box(Modifier.align(Alignment.BottomStart).width(2.dp).fillMaxHeight(d.progress.toFloat()).background(Color.White.copy(alpha = 0.7f)))
            Box(Modifier.align(Alignment.TopCenter).width(4.dp).height(18.dp).background(Palette.play))
        }
        if (playing) Box(Modifier.align(Alignment.TopCenter).padding(top = 22.dp)) { PlayingBars(Modifier.size(10.dp, 8.dp), Color.White) }
    }
}

/** A tap takes the book off the shelf: its cover, with Aç and the marks. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PulledBook(app: AppModel, d: DocumentRecord, nav: NavHostController, onOpen: () -> Unit, onDismiss: () -> Unit) {
    var menu by remember { mutableStateOf(false) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp).padding(bottom = 24.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            CoverView(d, Modifier.size(150.dp, 220.dp))
            Spacer(Modifier.height(12.dp))
            Text(d.title, style = MaterialTheme.typography.titleMedium, fontFamily = FontFamily.Serif)
            d.author?.let { Text(it, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) }
            Text(app.statusText(d), style = MaterialTheme.typography.labelMedium)
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                androidx.compose.material3.Button(onClick = onOpen) { Text(if (d.isUnread) "Oku" else "Aç") }
                Box {
                    androidx.compose.material3.OutlinedButton(onClick = { menu = true }) { Text("Diğer") }
                    BookMenu(app, d, nav, menu) { menu = false }
                }
            }
        }
    }
}

// MARK: - a book's marks without opening it

@Composable
fun MarksChip(app: AppModel, d: DocumentRecord) {
    var shown by remember { mutableStateOf(false) }
    Surface(onClick = { shown = true }, shape = RoundedCornerShape(10.dp), color = Color(HighlightColor.YELLOW.argb).copy(alpha = 0.3f)) {
        Row(Modifier.padding(horizontal = 8.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.Edit, null, Modifier.size(12.dp))
            Spacer(Modifier.width(3.dp))
            Text("${d.highlights.size}", style = MaterialTheme.typography.labelSmall)
        }
    }
    if (shown) MarksSheet(app, d.id, onDismiss = { shown = false })
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MarksSheet(app: AppModel, docId: String, onDismiss: () -> Unit, onShow: ((String, Int) -> Unit)? = null) {
    val docs by app.store.documents.collectAsState()
    val d = docs.firstOrNull { it.id == docId } ?: return
    var chapters by remember { mutableStateOf<List<com.fatihgocgun.wisepath.model.Chapter>>(emptyList()) }
    LaunchedEffect(docId) { chapters = app.store.content(docId)?.chapters ?: emptyList() }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        Column(Modifier.fillMaxWidth().heightIn(max = 600.dp).verticalScroll(rememberScrollState()).padding(horizontal = 20.dp).padding(bottom = 24.dp)) {
            Text("İşaretler · ${d.title}", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(8.dp))
            if (d.highlights.isEmpty() && d.bookmarks.isEmpty()) Text("Bu kitapta işaret yok.")
            var last: String? = null
            d.highlights.sortedBy { it.location }.forEach { h ->
                val ch = chapters.lastOrNull { it.offset <= h.location }?.title
                if (ch != null && ch != last) { Text(ch, Modifier.padding(top = 12.dp), style = MaterialTheme.typography.labelLarge, color = MaterialTheme.colorScheme.primary); last = ch }
                Row(Modifier.fillMaxWidth().clickable(enabled = onShow != null) { onShow?.invoke(d.id, h.location) }.padding(vertical = 6.dp)) {
                    Box(Modifier.width(3.dp).height(40.dp).background(Color(h.color.argb)))
                    Spacer(Modifier.width(10.dp))
                    Column {
                        Text(h.text, maxLines = 4, overflow = TextOverflow.Ellipsis, fontFamily = FontFamily.Serif)
                        h.note?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.primary) }
                        Text(Format.date(h.createdAt, "d MMM yyyy"), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.5f))
                    }
                }
            }
            if (d.bookmarks.isNotEmpty()) {
                Text("Yer imleri", Modifier.padding(top = 16.dp), style = MaterialTheme.typography.labelLarge)
                d.bookmarks.forEach { b ->
                    Row(Modifier.fillMaxWidth().clickable(enabled = onShow != null) { onShow?.invoke(d.id, b.offset) }.padding(vertical = 6.dp)) {
                        Icon(Icons.Default.Bookmark, null, Modifier.size(16.dp), tint = MaterialTheme.colorScheme.primary)
                        Spacer(Modifier.width(8.dp))
                        Text(b.excerpt, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        }
    }
}

// MARK: - the menu every book carries

@Composable
fun BookMenu(app: AppModel, d: DocumentRecord, nav: NavHostController, expanded: Boolean, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var rename by remember { mutableStateOf(false) }
    var move by remember { mutableStateOf(false) }
    var flag by remember { mutableStateOf(false) }
    var delete by remember { mutableStateOf(false) }
    var rewind by remember { mutableStateOf(false) }
    var marks by remember { mutableStateOf(false) }
    var search by remember { mutableStateOf(false) }
    DropdownMenu(expanded, onDismissRequest = onDismiss) {
        DropdownMenuItem(text = { Text(if (d.isUnread) "Oku" else "Aç") }, onClick = { onDismiss(); nav.openReader(app, d.id) })
        DropdownMenuItem(text = { Text("Kitapta ara") }, onClick = { onDismiss(); search = true })
        if (d.highlights.isNotEmpty() || d.bookmarks.isNotEmpty())
            DropdownMenuItem(text = { Text("İşaretlere bak (${d.highlights.size})") }, onClick = { onDismiss(); marks = true })
        if (d.highlights.isNotEmpty()) {
            DropdownMenuItem(text = { Text("İşaretleri paylaş") }, onClick = {
                onDismiss()
                val text = app.highlightsExport(d)
                context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/markdown").putExtra(Intent.EXTRA_TEXT, text)
                    .putExtra(Intent.EXTRA_SUBJECT, d.title), "İşaretler"))
            })
            DropdownMenuItem(text = { Text("Genişlet (işaretlerden istem)") }, onClick = { onDismiss(); nav.navigate(Routes.expand(d.id)) })
        }
        HorizontalDivider()
        DropdownMenuItem(text = { Text("Yeniden adlandır") }, onClick = { onDismiss(); rename = true })
        DropdownMenuItem(text = { Text("Klasöre taşı") }, onClick = { onDismiss(); move = true })
        DropdownMenuItem(text = { Text("Etiket") }, onClick = { onDismiss(); flag = true })
        DropdownMenuItem(text = { Text(if (d.isFinished) "Yeniden oku" else "Başa sar") }, onClick = { onDismiss(); rewind = true })
        DropdownMenuItem(text = { Text("Sil", color = MaterialTheme.colorScheme.error) }, onClick = { onDismiss(); delete = true })
    }
    if (rename) NameDialog("Yeniden adlandır", "Başlık", d.title, "Kaydet", onDismiss = { rename = false }) { app.rename(d.id, it); rename = false }
    if (move) {
        val folders by app.store.folders.collectAsState()
        var newName by remember { mutableStateOf(false) }
        AlertDialog(
            onDismissRequest = { move = false },
            title = { Text("Klasöre taşı") },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState())) {
                    (listOf<String?>(null) + folders).forEach { f ->
                        Text((if (d.folder == f) "✓ " else "") + (f ?: "Klasörsüz"), Modifier.fillMaxWidth().clickable { app.setFolder(d.id, f); move = false }.padding(vertical = 10.dp))
                    }
                    Text("+ Yeni klasör", Modifier.fillMaxWidth().clickable { newName = true }.padding(vertical = 10.dp), color = MaterialTheme.colorScheme.primary)
                }
            },
            confirmButton = { TextButton(onClick = { move = false }) { Text("Vazgeç") } },
        )
        if (newName) NameDialog("Yeni klasör", "Klasör adı", "", "Oluştur", onDismiss = { newName = false }) {
            app.addFolder(it); app.setFolder(d.id, it); newName = false; move = false
        }
    }
    if (flag) AlertDialog(
        onDismissRequest = { flag = false },
        title = { Text("Etiket") },
        text = {
            Column {
                HighlightColor.entries.forEach { c ->
                    Row(Modifier.fillMaxWidth().clickable { app.setFlag(d.id, c); flag = false }.padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(16.dp).clip(RoundedCornerShape(8.dp)).background(Color(c.argb)))
                        Spacer(Modifier.width(10.dp))
                        Text(c.label + if (d.flag == c) "  ✓" else "")
                    }
                }
                if (d.flag != null) Text("Etiketi kaldır", Modifier.fillMaxWidth().clickable { app.setFlag(d.id, null); flag = false }.padding(vertical = 10.dp),
                    color = MaterialTheme.colorScheme.error)
            }
        },
        confirmButton = { TextButton(onClick = { flag = false }) { Text("Vazgeç") } },
    )
    if (rewind) AlertDialog(
        onDismissRequest = { rewind = false },
        title = { Text(if (d.isFinished) "“${d.title}” yeniden okunsun mu?" else "“${d.title}” başa sarılsın mı?") },
        text = { Text(if (d.isFinished) "Bitirdiğin okuma kayıtlı kalır." else "Kaldığın yer başa döner.") },
        confirmButton = { TextButton(onClick = { rewind = false; app.rewindToBeginning(d.id) }) { Text(if (d.isFinished) "Baştan başla · ${d.finishes.size + 1}. okuma" else "Başa sar") } },
        dismissButton = { TextButton(onClick = { rewind = false }) { Text("Vazgeç") } },
    )
    if (delete) AlertDialog(
        onDismissRequest = { delete = false },
        title = { Text("“${d.title}” silinsin mi?") },
        text = { Text("İşaretler, notlar ve yer imleri de silinir.") },
        confirmButton = { TextButton(onClick = { delete = false; app.delete(listOf(d.id)) }) { Text("Sil", color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { delete = false }) { Text("Vazgeç") } },
    )
    if (marks) MarksSheet(app, d.id, onDismiss = { marks = false }, onShow = { id, at -> marks = false; nav.openReader(app, id, at) })
    if (search) BookSearchSheet(d.id, onDismiss = { search = false }, onOpenPlace = { id, at -> search = false; nav.openReader(app, id, at) })
}
