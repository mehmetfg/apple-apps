// Search inside the books (port of Views/BookSearch.swift):
//   Kütüphane  under the search field, "Kitapların içinde": every book where the phrase occurs, the most recently
//              opened first, each with its first places
//   a book     "Kitapta ara" on its card searches it without opening it
//   a place    opens the book showing that place; the reading place stays where it was (revealRequest)
// Matching ignores case, accents and the dotted/dotless i (TextFold): "gazali" finds "Gazâlî", "ISIK" finds "ışık".
package com.fatihgocgun.wisepath.search

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
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
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.TextFold
import com.fatihgocgun.wisepath.model.Chapter
import com.fatihgocgun.wisepath.model.DocumentRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

private val Orange = Color(0xFFFF9500)

data class TextHit(val doc: String, val offset: Int, val chapter: String, val before: String, val match: String, val after: String) {
    val id get() = "$doc.$offset"
}

object TextSearch {
    data class Found(val hits: List<TextHit> = emptyList(), val total: Int = 0)

    /** The folded needle, or null when the phrase is shorter than `minimum`. */
    fun needle(q: String, minimum: Int = 2): String? {
        val t = q.trim()
        if (t.length < minimum) return null
        return TextFold.fold(t)
    }

    /** Every place in a document's text, in order; `total` counts past the limit too. */
    fun hits(doc: String, text: String, chapters: List<Chapter>, needle: String, limit: Int): Found {
        if (needle.isEmpty() || text.length < needle.length) return Found()
        // TextFold keeps one char per char, so an offset in the folded text is the offset in the original
        val folded = TextFold.fold(text)
        val heads = chapters.sortedBy { it.offset }
        val out = mutableListOf<TextHit>()
        var total = 0
        var i = folded.indexOf(needle)
        while (i >= 0) {
            total++
            if (out.size < limit) {
                val ch = heads.lastOrNull { it.offset <= i }?.title ?: ""
                out.add(snippet(doc, text, i, needle.length, ch))
            }
            i = folded.indexOf(needle, i + needle.length)
        }
        return Found(out, total)
    }

    /** The paragraph around a place, cut at word boundaries, never across a paragraph. */
    fun snippet(doc: String, text: String, at: Int, length: Int, chapter: String): TextHit {
        val pStart = text.lastIndexOf('\n', at - 1).let { if (it < 0) 0 else it + 1 }
        val pEnd = text.indexOf('\n', at + length).let { if (it < 0) text.length else it }
        var a = maxOf(pStart, at - 60)
        var z = minOf(pEnd, at + length + 90)
        if (a > pStart) text.indexOf(' ', a).takeIf { it in a until at }?.let { a = it + 1 }
        if (z < pEnd) text.lastIndexOf(' ', z).takeIf { it >= at + length }?.let { z = it }
        // never cut a surrogate pair
        if (a > 0 && a < text.length && Character.isLowSurrogate(text[a])) a++
        if (z > 0 && z < text.length && Character.isLowSurrogate(text[z])) z++
        z = z.coerceIn(at + length, text.length)
        fun clean(s: String) = s.replace('\n', ' ')
        return TextHit(doc, at, chapter,
            before = (if (a > pStart) "…" else "") + clean(text.substring(a, at)),
            match = text.substring(at, at + length),
            after = clean(text.substring(at + length, z)) + (if (z < pEnd - 1) "…" else ""))
    }
}

@Composable
private fun TextHitRow(hit: TextHit, showChapter: Boolean = true, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (showChapter && hit.chapter.isNotEmpty()) {
            Text(hit.chapter, style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, maxLines = 1,
                overflow = TextOverflow.Ellipsis, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f))
        }
        Text(buildAnnotatedString {
            append(hit.before)
            withStyle(SpanStyle(fontWeight = FontWeight.Bold, color = Orange)) { append(hit.match) }
            append(hit.after)
        }, fontFamily = FontFamily.Serif, style = MaterialTheme.typography.bodyMedium, maxLines = 4, overflow = TextOverflow.Ellipsis)
    }
}

private data class BookResult(val doc: DocumentRecord, val hits: List<TextHit>, val total: Int)

private const val MINIMUM = 3
private const val PER_BOOK = 12
private const val CAP = 300

/** Under the library's search field: every book where the phrase occurs, with its first places. */
@Composable
fun LibrarySentenceResults(query: String, onOpenPlace: (doc: String, offset: Int) -> Unit) {
    val app = AppModel.get(LocalContext.current)
    val q = query.trim()
    var results by remember { mutableStateOf<List<BookResult>>(emptyList()) }
    var searched by remember { mutableStateOf("") }
    var scanned by remember { mutableStateOf(0) }
    var count by remember { mutableStateOf(0) }
    var running by remember { mutableStateOf(false) }
    var capped by remember { mutableStateOf(false) }
    var expanded by remember { mutableStateOf(setOf<String>()) }
    var allOf by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(q) {
        if (q.length < MINIMUM) { results = emptyList(); searched = ""; scanned = 0; count = 0; capped = false; running = false; return@LaunchedEffect }
        delay(320)
        val needle = TextSearch.needle(q, MINIMUM) ?: return@LaunchedEffect
        val docs = app.store.documents.value.sortedByDescending { it.lastOpenedAt ?: it.addedAt }
        searched = q; results = emptyList(); scanned = 0; count = docs.size; capped = false; running = true; expanded = emptySet()
        var shown = 0
        try {
            for ((n, d) in docs.withIndex()) {
                val limit = minOf(PER_BOOK, CAP - shown)
                val found = withContext(Dispatchers.Default) {
                    // read straight from the file: the whole library must not stay in the content cache
                    val c = app.store.cachedContent(d.id) ?: runCatching {
                        com.fatihgocgun.wisepath.model.AppJson.decodeFromString(com.fatihgocgun.wisepath.model.DocumentContent.serializer(),
                            app.store.contentFile(d.id).readText())
                    }.getOrNull() ?: return@withContext null
                    TextSearch.hits(d.id, c.text, c.chapters, needle, limit)
                }
                if (found != null && found.total > 0) {
                    results = results + BookResult(d, found.hits, found.total)
                    shown += found.hits.size
                }
                if (n % 4 == 3 || n == docs.size - 1) scanned = n + 1
                if (shown >= CAP) { capped = true; scanned = n + 1; break }
            }
        } finally { running = false }
    }

    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (q.length >= MINIMUM) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Kitapların içinde", Modifier.weight(1f), style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                if (results.isNotEmpty()) Text("${results.sumOf { it.total }} yer · ${results.size} kitap", style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
            }
            results.forEach { r ->
                val open = r.doc.id in expanded
                val list = if (open) r.hits else r.hits.take(3)
                Card(colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)) {
                    Column(Modifier.padding(14.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Row {
                            Column(Modifier.weight(1f)) {
                                Text(r.doc.title, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold, maxLines = 2, overflow = TextOverflow.Ellipsis)
                                r.doc.author?.let { Text(it, style = MaterialTheme.typography.bodySmall, maxLines = 1, color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)) }
                            }
                            Spacer(Modifier.width(8.dp))
                            Text("${r.total} yer", style = MaterialTheme.typography.labelMedium, fontWeight = FontWeight.SemiBold, color = Orange)
                        }
                        list.forEach { h -> TextHitRow(h) { onOpenPlace(h.doc, h.offset) } }
                        if (!open && r.hits.size > 3) {
                            TextButton(onClick = { expanded = expanded + r.doc.id }) { Text("${r.hits.size - 3} yer daha", color = Orange) }
                        } else if (r.total > r.hits.size) {
                            TextButton(onClick = { allOf = r.doc.id }) { Text("Bu kitaptaki ${r.total} yerin hepsi", color = Orange) }
                        }
                    }
                }
            }
            if (running) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp)
                    Spacer(Modifier.width(8.dp))
                    Text("$scanned/$count kitap tarandı", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                }
            } else if (searched.isNotEmpty() && results.isEmpty()) {
                Text("“$searched” hiçbir kitabın içinde geçmiyor.", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
            }
            if (capped) Text("İlk $CAP yer gösteriliyor; daha dar bir ifadeyle ara.", style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
        } else if (q.isNotEmpty()) {
            Text("Kitapların içinde aramak için en az üç harf.", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
        }
    }
    allOf?.let { id -> BookSearchSheet(id, onDismiss = { allOf = null }, onOpenPlace = onOpenPlace, initialQuery = q) }
}

/** "Kitapta ara" from a book's card, without opening it. */
@Composable
fun BookSearchSheet(docId: String, onDismiss: () -> Unit, onOpenPlace: (doc: String, offset: Int) -> Unit) =
    BookSearchSheet(docId, onDismiss, onOpenPlace, "")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun BookSearchSheet(docId: String, onDismiss: () -> Unit, onOpenPlace: (doc: String, offset: Int) -> Unit, initialQuery: String) {
    val app = AppModel.get(LocalContext.current)
    val doc = remember(docId) { app.store.document(docId) }
    var query by remember { mutableStateOf(initialQuery) }
    var content by remember { mutableStateOf<com.fatihgocgun.wisepath.model.DocumentContent?>(null) }
    var found by remember { mutableStateOf(TextSearch.Found()) }
    var searched by remember { mutableStateOf("") }
    LaunchedEffect(docId) { content = app.store.content(docId) }
    LaunchedEffect(query, content) {
        val c = content ?: return@LaunchedEffect
        delay(250)
        val needle = TextSearch.needle(query)
        if (needle == null) { found = TextSearch.Found(); searched = ""; return@LaunchedEffect }
        found = withContext(Dispatchers.Default) { TextSearch.hits(docId, c.text, c.chapters, needle, 300) }
        searched = query.trim()
    }
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
        Column(Modifier.fillMaxSize().padding(horizontal = 16.dp)) {
            Text(doc?.title ?: "", style = MaterialTheme.typography.titleMedium, maxLines = 1, overflow = TextOverflow.Ellipsis)
            OutlinedTextField(query, { query = it }, placeholder = { Text("Bu kitapta ara") }, singleLine = true,
                modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp))
            val dim = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
            when {
                content == null -> Row(verticalAlignment = Alignment.CenterVertically) {
                    CircularProgressIndicator(Modifier.size(16.dp), strokeWidth = 2.dp); Spacer(Modifier.width(8.dp)); Text("Metin yükleniyor…", color = dim)
                }
                searched.isEmpty() -> Text("Bu kitabın içinde bir ifade ara. Büyük/küçük harf, şapka ve ı/i fark etmez.", color = dim)
                found.hits.isEmpty() -> Text("“$searched” için sonuç yok.", color = dim)
                else -> LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    item {
                        Text("${found.total} yer · ${found.hits.map { it.chapter }.toSet().size} bölümde", style = MaterialTheme.typography.labelLarge, color = dim)
                    }
                    items(found.hits, key = { it.id }) { h -> TextHitRow(h) { onDismiss(); onOpenPlace(h.doc, h.offset) } }
                    if (found.total > found.hits.size) item {
                        Text("İlk ${found.hits.size} yer gösteriliyor; kitabı açıp ⌕ ile hepsini gezebilirsin.", style = MaterialTheme.typography.bodySmall, color = dim)
                    }
                }
            }
        }
    }
}
