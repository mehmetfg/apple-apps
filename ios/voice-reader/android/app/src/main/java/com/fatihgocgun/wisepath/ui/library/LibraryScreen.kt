// The library, the app's first page and its point (port of Views/LibraryScreen.swift + HomeShelf.swift): books first.
// On top the last three books, then every book as a bookcase of spines (Kitaplık), a grid, cards or a list, by shelf
// (Süren · Okunacak · Bitenler) or folder; today's listening and the automation; the folders. Statistics, the moving
// modes and the notes are keys at the top. Adding from files or the clipboard; a mini player while reading.
package com.fatihgocgun.wisepath.ui.library

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.Notes
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.ContentPaste
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.Map
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Route
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TextField
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.navigation.NavHostController
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.FolderScope
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.automation.AutomationCard
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.search.LibrarySentenceResults
import com.fatihgocgun.wisepath.settings.LibraryStyle
import com.fatihgocgun.wisepath.settings.MoveKind
import com.fatihgocgun.wisepath.stats.TodayCard
import com.fatihgocgun.wisepath.ui.Page
import com.fatihgocgun.wisepath.ui.Routes
import com.fatihgocgun.wisepath.ui.openReader
import kotlinx.coroutines.launch

data class BookshelfSection(val title: String, val docs: List<DocumentRecord>)

/** The MIME types the file picker offers (everything the importer reads). */
val importMimeTypes = arrayOf(
    "application/pdf", "application/epub+zip", "text/*", "application/rtf", "text/rtf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "application/msword",
    "application/vnd.oasis.opendocument.text", "application/x-mobipocket-ebook", "application/vnd.amazon.ebook",
    "application/x-fictionbook+xml", "application/xhtml+xml", "application/octet-stream",
)

fun shelves(all: List<DocumentRecord>, shelf: String, grouped: Boolean): List<BookshelfSection> {
    val byOpened = compareByDescending<DocumentRecord> { it.lastOpenedAt ?: it.addedAt }
    val reading = all.filter { it.isInProgress }.sortedWith(byOpened)
    val unread = all.filter { it.isUnread }.sortedByDescending { it.addedAt }
    val finished = all.filter { it.isFinished }.sortedByDescending { it.finishedAt ?: 0 }
    return when (shelf) {
        "reading" -> listOf(BookshelfSection("Süren", reading))
        "unread" -> listOf(BookshelfSection("Okunacak", unread))
        "finished" -> listOf(BookshelfSection("Bitenler · arşiv", finished))
        "all" -> if (grouped) listOf(BookshelfSection("Süren", reading), BookshelfSection("Okunacak", unread), BookshelfSection("Bitenler · arşiv", finished))
        else listOf(BookshelfSection("Tümü", all.sortedWith(byOpened)))
        else -> listOf(BookshelfSection(shelf, all.filter { it.folder == shelf }.sortedWith(byOpened)))
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(app: AppModel, nav: NavHostController) {
    val docs by app.store.documents.collectAsState()
    val folders by app.store.folders.collectAsState()
    val noteCount = app.notes.notes.collectAsState().value.size
    val scope = rememberCoroutineScope()
    var addMenu by remember { mutableStateOf(false) }
    var roadMenu by remember { mutableStateOf(false) }
    var newFolder by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(false) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments()) { uris ->
        if (uris.isNotEmpty()) scope.launch { app.importUris(uris) }
    }
    val open: (String) -> Unit = { id -> nav.openReader(app, id) }
    val openPlace: (String, Int) -> Unit = { id, at -> nav.openReader(app, id, at) }

    Scaffold(
        containerColor = MaterialTheme.colorScheme.background,
        topBar = {
            TopAppBar(
                title = {
                    if (searching) {
                        TextField(
                            value = app.searchText, onValueChange = { app.searchText = it },
                            placeholder = { Text("Kitap, yazar ya da cümle ara") }, singleLine = true,
                            colors = TextFieldDefaults.colors(focusedContainerColor = Color.Transparent, unfocusedContainerColor = Color.Transparent),
                            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search), keyboardActions = KeyboardActions(),
                            modifier = Modifier.fillMaxWidth(),
                        )
                    } else Text("Kütüphane", fontWeight = FontWeight.Bold)
                },
                navigationIcon = {
                    IconButton(onClick = { nav.navigate(Routes.SETTINGS) }) { Icon(Icons.Default.Settings, "Ayarlar ve Otomasyon") }
                },
                actions = {
                    IconButton(onClick = { searching = !searching; if (!searching) app.searchText = "" }) {
                        Icon(if (searching) Icons.Default.Clear else Icons.Default.Search, "Ara")
                    }
                    IconButton(onClick = { nav.navigate(Routes.STATS) }) { Icon(Icons.Default.BarChart, "İstatistik: okuma ve yol") }
                    Box {
                        IconButton(onClick = { roadMenu = true }) { Icon(Icons.Default.Route, "Yolda: bisiklet, yürüyüş, müzik ve Yollarım") }
                        DropdownMenu(roadMenu, onDismissRequest = { roadMenu = false }) {
                            DropdownMenuItem(text = { Text("Bisiklet") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.DirectionsBike, null) }, onClick = {
                                roadMenu = false; startMove(app, nav, MoveKind.bike)
                            })
                            DropdownMenuItem(text = { Text("Yürüyüş") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.DirectionsWalk, null) }, onClick = {
                                roadMenu = false; startMove(app, nav, MoveKind.walk)
                            })
                            DropdownMenuItem(text = { Text("Müzik") }, leadingIcon = { Icon(Icons.Default.MusicNote, null) }, onClick = {
                                roadMenu = false; nav.navigate(Routes.MUSIC)
                            })
                            HorizontalDivider()
                            DropdownMenuItem(text = { Text("Yollarım: gün, hafta, ay") }, leadingIcon = { Icon(Icons.Default.Map, null) }, onClick = {
                                roadMenu = false; nav.navigate(Routes.ROADS)
                            })
                            DropdownMenuItem(text = { Text("Notlarım · $noteCount") }, leadingIcon = { Icon(Icons.AutoMirrored.Filled.Notes, null) }, onClick = {
                                roadMenu = false; nav.navigate(Routes.NOTES)
                            })
                        }
                    }
                    Box {
                        IconButton(onClick = { addMenu = true }) { Icon(Icons.Default.Add, "Ekle") }
                        DropdownMenu(addMenu, onDismissRequest = { addMenu = false }) {
                            DropdownMenuItem(text = { Text("Dosyalardan ekle") }, leadingIcon = { Icon(Icons.Default.FolderOpen, null) }, onClick = {
                                addMenu = false; picker.launch(importMimeTypes)
                            })
                            DropdownMenuItem(text = { Text("Panodan ekle") }, leadingIcon = { Icon(Icons.Default.ContentPaste, null) }, onClick = {
                                addMenu = false; app.importClipboard()
                            })
                            DropdownMenuItem(text = { Text("İstem oluşturucu") }, leadingIcon = { Icon(Icons.Default.AutoAwesome, null) }, onClick = {
                                addMenu = false; nav.navigate(Routes.PROMPT)
                            })
                            DropdownMenuItem(text = { Text("Yeni klasör") }, leadingIcon = { Icon(Icons.Default.CreateNewFolder, null) }, onClick = {
                                addMenu = false; newFolder = true
                            })
                        }
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.background),
            )
        },
        bottomBar = {
            val state by app.player.state.collectAsState()
            if (state.documentID != null) MiniPlayer(app) { state.documentID?.let(open) }
        },
    ) { pad ->
        val query = app.searchText.trim()
        LazyColumn(Modifier.fillMaxSize().padding(pad)) {
            if (query.isNotEmpty()) {
                val found = app.documents(FolderScope.All, applyFilter = false)
                items(found, key = { it.id }) { d -> LibraryRow(app, d, nav, onOpen = open) }
                item { LibrarySentenceResults(query, openPlace) }
                return@LazyColumn
            }
            item { RecentBooks(app, docs, open) }
            if (docs.isNotEmpty()) {
                item {
                    Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 12.dp, top = 18.dp), verticalAlignment = Alignment.CenterVertically) {
                        SectionTitle("Kitaplarım")
                        Spacer(Modifier.weight(1f))
                        StylePicker(app.settings.homeStyle) { app.settings.homeStyle = it }
                    }
                    ShelfChips(app, folders)
                }
                item { HomeBooks(app, docs, nav, open) }
                item { Box(Modifier.padding(horizontal = 16.dp, vertical = 8.dp)) { TodayCard(onOpenStats = { nav.navigate(Routes.STATS) }) } }
                item { Box(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) { com.fatihgocgun.wisepath.notes.NotesCard(onOpenNotes = { nav.navigate(Routes.NOTES) }) } }
            }
            item { Box(Modifier.padding(horizontal = 16.dp)) { AutomationCard(onOpen = { nav.navigate(Routes.AUTOMATION) }) } }
            item {
                Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 18.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    SectionTitle("Klasörler")
                    Spacer(Modifier.weight(1f))
                    IconButton(onClick = { newFolder = true }) { Icon(Icons.Default.CreateNewFolder, "Yeni klasör") }
                }
            }
            val scopes = listOf<FolderScope>(FolderScope.All) + folders.map { FolderScope.Named(it) } +
                (if (docs.any { it.folder == null }) listOf(FolderScope.Unfiled) else emptyList())
            items(scopes.chunked(2)) { row ->
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    row.forEach { s -> FolderTile(app, s, docs, Modifier.weight(1f)) { nav.navigate(Routes.folder(scopeKey(s))) } }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            if (docs.isEmpty()) {
                item {
                    Column(Modifier.fillMaxWidth().padding(32.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.LibraryBooks, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.4f))
                        Text("Kütüphane boş", style = MaterialTheme.typography.titleMedium)
                        Text("Sağ üstteki + ile dosyalardan ya da panodan belge ekle.", color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                        TextButton(onClick = { picker.launch(importMimeTypes) }) { Text("Dosyalardan ekle") }
                    }
                }
            }
            item { Spacer(Modifier.height(24.dp)) }
        }
        if (app.importing) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Surface(shape = RoundedCornerShape(16.dp), tonalElevation = 6.dp, shadowElevation = 6.dp) {
                    Text("Ekleniyor…", Modifier.padding(24.dp))
                }
            }
        }
    }
    if (newFolder) NameDialog("Yeni klasör", "Klasör adı", "", "Oluştur", onDismiss = { newFolder = false }) { app.addFolder(it); newFolder = false }
}

fun scopeKey(s: FolderScope) = when (s) {
    FolderScope.All -> "\u0000all"
    FolderScope.Unfiled -> "\u0000unfiled"
    is FolderScope.Named -> s.name
}

fun scopeOf(key: String): FolderScope = when (key) {
    "\u0000all" -> FolderScope.All
    "\u0000unfiled" -> FolderScope.Unfiled
    else -> FolderScope.Named(key)
}

fun scopeTitle(s: FolderScope) = when (s) {
    FolderScope.All -> "Tüm belgeler"
    FolderScope.Unfiled -> "Klasörsüz"
    is FolderScope.Named -> s.name
}

private fun startMove(app: AppModel, nav: NavHostController, kind: MoveKind) {
    app.settings.moveKind = kind
    app.settings.bikeMode = true
    val book = app.currentDocument ?: app.recentDocuments(1).firstOrNull()
    if (book != null) nav.openReader(app, book.id) else nav.navigate(Routes.RIDE)
}

@Composable
fun SectionTitle(t: String) = Text(t, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold)

@Composable
private fun StylePicker(current: LibraryStyle, onPick: (LibraryStyle) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        Surface(onClick = { open = true }, shape = CircleShape, color = MaterialTheme.colorScheme.surfaceVariant) {
            Row(Modifier.padding(horizontal = 12.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Default.Tune, null, Modifier.size(16.dp))
                Spacer(Modifier.width(6.dp))
                Text(current.label, style = MaterialTheme.typography.labelLarge)
            }
        }
        DropdownMenu(open, onDismissRequest = { open = false }) {
            LibraryStyle.entries.forEach { s ->
                DropdownMenuItem(text = { Text(s.label + if (s == current) "  ✓" else "") }, onClick = { open = false; onPick(s) })
            }
        }
    }
}

@Composable
private fun ShelfChips(app: AppModel, folders: List<String>) {
    val shelves = listOf("all" to "Tümü", "reading" to "Süren", "unread" to "Okunacak", "finished" to "Bitenler") + folders.map { it to it }
    Row(Modifier.horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        shelves.forEach { (key, title) ->
            FilterChip(selected = app.settings.homeShelf == key, onClick = { app.settings.homeShelf = key }, label = { Text(title) })
        }
    }
}

/** The last three books side by side, the one being read first. */
@Composable
private fun RecentBooks(app: AppModel, docs: List<DocumentRecord>, open: (String) -> Unit) {
    val state by app.player.state.collectAsState()
    val recent = remember(docs, state.documentID) {
        val cur = state.documentID?.let { id -> docs.firstOrNull { it.id == id } }
        (listOfNotNull(cur) + docs.filter { it.lastOpenedAt != null && it.id != cur?.id }.sortedByDescending { it.lastOpenedAt }).take(3)
    }
    if (recent.isEmpty()) return
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        recent.forEach { d ->
            Column(Modifier.weight(1f).clickable { open(d.id) }) {
                CoverView(d, Modifier.fillMaxWidth().aspectRatio(0.68f), playing = state.isPlaying && state.documentID == d.id)
                Spacer(Modifier.height(6.dp))
                Text(d.title, style = MaterialTheme.typography.labelLarge, maxLines = 2, overflow = TextOverflow.Ellipsis)
                StateLabel(d)
            }
        }
        repeat(3 - recent.size) { Spacer(Modifier.weight(1f)) }
    }
}

/** A book's state in one short word: "Yeni", "%42" or "✓ Bitti" (no bar). */
@Composable
fun StateLabel(d: DocumentRecord) {
    val (t, c) = when {
        d.isFinished -> (if (d.finishes.size > 1) "✓ Bitti · ${d.finishes.size}" else "✓ Bitti") to Color(0xFF2E7D32)
        d.isUnread -> "Yeni" to MaterialTheme.colorScheme.primary
        else -> Format.percent(d.progress) to MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f)
    }
    Text(t, style = MaterialTheme.typography.labelMedium, color = c, fontWeight = FontWeight.SemiBold)
}

@Composable
private fun HomeBooks(app: AppModel, docs: List<DocumentRecord>, nav: NavHostController, open: (String) -> Unit) {
    val style = app.settings.homeStyle
    val sections = shelves(docs, app.settings.homeShelf, grouped = style == LibraryStyle.spines)
    if (sections.all { it.docs.isEmpty() }) {
        Text("Bu rafta kitap yok.", Modifier.padding(horizontal = 20.dp, vertical = 8.dp), color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
        return
    }
    when (style) {
        LibraryStyle.spines -> BookshelfView(app, sections, nav, open)
        else -> DocumentCollection(app, sections.flatMap { it.docs }, style, nav, open)
    }
}

@Composable
private fun FolderTile(app: AppModel, s: FolderScope, docs: List<DocumentRecord>, modifier: Modifier, onClick: () -> Unit) {
    val list = when (s) {
        FolderScope.All -> docs
        FolderScope.Unfiled -> docs.filter { it.folder == null }
        is FolderScope.Named -> docs.filter { it.folder == s.name }
    }
    var menu by remember { mutableStateOf(false) }
    var rename by remember { mutableStateOf(false) }
    Box(modifier) {
        @OptIn(ExperimentalFoundationApi::class)
        Surface(
            shape = RoundedCornerShape(14.dp), color = MaterialTheme.colorScheme.surface, tonalElevation = 1.dp, shadowElevation = 1.dp,
            modifier = Modifier.fillMaxWidth().clip(RoundedCornerShape(14.dp)).combinedClickable(onClick = onClick, onLongClick = { if (s is FolderScope.Named) menu = true }),
        ) {
            Column(Modifier.padding(14.dp)) {
                Icon(if (s == FolderScope.All) Icons.Default.LibraryBooks else Icons.Default.Folder, null, tint = MaterialTheme.colorScheme.primary)
                Spacer(Modifier.height(8.dp))
                Text(scopeTitle(s), fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                val left = list.filter { !it.isFinished }.sumOf { app.duration(maxOf(0, it.length - it.position), it.speed) }
                Text("${list.size} belge" + if (left > 0) " · ${Format.duration(left)}" else "", style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
            }
        }
        DropdownMenu(menu, onDismissRequest = { menu = false }) {
            DropdownMenuItem(text = { Text("Klasörü yeniden adlandır") }, onClick = { menu = false; rename = true })
            DropdownMenuItem(text = { Text("Klasörü kaldır (belgeler kalır)") }, onClick = { menu = false; (s as? FolderScope.Named)?.let { app.removeFolder(it.name) } })
        }
    }
    if (rename && s is FolderScope.Named) NameDialog("Klasörü yeniden adlandır", "Ad", s.name, "Kaydet", onDismiss = { rename = false }) {
        app.renameFolder(s.name, it); rename = false
    }
}

/** A folder's (or all) documents with sort and filter, as the library styles show them. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FolderScreen(app: AppModel, nav: NavHostController, name: String) {
    val scope = scopeOf(name)
    val docs by app.store.documents.collectAsState()
    var menu by remember { mutableStateOf(false) }
    val list = remember(docs, app.settings.sortOrder, app.settings.filter, scope) { app.documents(scope) }
    Page(scopeTitle(scope), onBack = { nav.popBackStack() }, actions = {
        Box {
            IconButton(onClick = { menu = true }) { Icon(Icons.Default.Tune, "Sırala ve süz") }
            DropdownMenu(menu, onDismissRequest = { menu = false }) {
                Text("Sırala", Modifier.padding(horizontal = 16.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium)
                com.fatihgocgun.wisepath.settings.SortOrder.entries.forEach { o ->
                    DropdownMenuItem(text = { Text(o.label + if (o == app.settings.sortOrder) "  ✓" else "") }, onClick = { app.settings.sortOrder = o })
                }
                HorizontalDivider()
                Text("Süz", Modifier.padding(horizontal = 16.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium)
                com.fatihgocgun.wisepath.settings.LibraryFilter.entries.forEach { f ->
                    DropdownMenuItem(text = { Text(f.label + if (f == app.settings.filter) "  ✓" else "") }, onClick = { app.settings.filter = f })
                }
                HorizontalDivider()
                Text("Görünüm", Modifier.padding(horizontal = 16.dp, vertical = 4.dp), style = MaterialTheme.typography.labelMedium)
                LibraryStyle.entries.forEach { s ->
                    DropdownMenuItem(text = { Text(s.label + if (s == app.settings.style) "  ✓" else "") }, onClick = { app.settings.style = s; menu = false })
                }
            }
        }
    }) { pad ->
        val open: (String) -> Unit = { nav.openReader(app, it) }
        LazyColumn(Modifier.fillMaxSize().padding(pad)) {
            if (list.isEmpty()) item {
                Text("Bu klasörde belge yok. Bir belgeye basılı tutup “Klasöre taşı”yı seç.", Modifier.padding(24.dp),
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
            }
            item {
                if (app.settings.style == LibraryStyle.spines) BookshelfView(app, listOf(BookshelfSection(scopeTitle(scope), list)), nav, open)
                else DocumentCollection(app, list, app.settings.style, nav, open)
            }
        }
    }
}

/** The mini player shown under the library. */
@Composable
fun MiniPlayer(app: AppModel, onOpen: () -> Unit) {
    val s by app.player.state.collectAsState()
    val doc = s.documentID?.let { app.store.document(it) } ?: return
    Surface(color = MaterialTheme.colorScheme.surface, tonalElevation = 3.dp, shadowElevation = 8.dp, modifier = Modifier.fillMaxWidth()) {
        Column(Modifier.navigationBarsPadding()) {
            LinearProgressIndicator(progress = { s.progress }, modifier = Modifier.fillMaxWidth().height(2.dp))
            Row(Modifier.fillMaxWidth().clickable(onClick = onOpen).padding(horizontal = 12.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                CoverView(doc, Modifier.size(36.dp, 52.dp), corner = 4.dp)
                Spacer(Modifier.width(12.dp))
                Column(Modifier.weight(1f)) {
                    Text(doc.title, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    val chapter = app.player.nav.chapterTitle(s.cursor)
                    val sub = if (s.breakEnds != null) "Müzik arası" else listOfNotNull(chapter, Format.duration(app.player.remainingSeconds) + " kaldı").joinToString(" · ")
                    Text(sub, style = MaterialTheme.typography.bodySmall, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
                    com.fatihgocgun.wisepath.ui.Slots.automationStatus()
                }
                com.fatihgocgun.wisepath.ui.reader.PlayKey(s.isPlaying, size = 44) { app.player.toggle() }
            }
        }
    }
}

@Composable
fun NameDialog(title: String, label: String, initial: String, confirm: String, onDismiss: () -> Unit, onDone: (String) -> Unit) {
    var text by remember { mutableStateOf(initial) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(title) },
        text = { OutlinedTextField(text, { text = it }, label = { Text(label) }, singleLine = true) },
        confirmButton = { TextButton(onClick = { if (text.isNotBlank()) onDone(text.trim()) }) { Text(confirm) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Vazgeç") } },
    )
}

@Suppress("unused") private val unusedSerif = FontFamily.Serif
@Suppress("unused") private val unusedSp = 1.sp
@Suppress("unused") private fun unusedBg(m: Modifier) = m.background(Color.Unspecified)
