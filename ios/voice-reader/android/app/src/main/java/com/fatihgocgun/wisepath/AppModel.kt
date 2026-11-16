// The app's one model (port of AppModel.swift and its extensions): the library, the settings, the player, the
// listening log and the notes, and every action the screens and the media keys take. A process-wide singleton, so
// the media service, the widgets and the activity all see the same reading.
package com.fatihgocgun.wisepath

import android.content.ClipboardManager
import android.content.Context
import android.net.Uri
import android.provider.OpenableColumns
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fatihgocgun.wisepath.importer.DocumentImporter
import com.fatihgocgun.wisepath.model.Bookmark
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.model.Highlight
import com.fatihgocgun.wisepath.model.HighlightColor
import com.fatihgocgun.wisepath.model.now
import com.fatihgocgun.wisepath.notes.NoteRecorder
import com.fatihgocgun.wisepath.notes.NoteStore
import com.fatihgocgun.wisepath.settings.EndBehavior
import com.fatihgocgun.wisepath.settings.LibraryFilter
import com.fatihgocgun.wisepath.settings.NavigationUnit
import com.fatihgocgun.wisepath.settings.Settings
import com.fatihgocgun.wisepath.settings.SortOrder
import com.fatihgocgun.wisepath.speech.PlaybackService
import com.fatihgocgun.wisepath.speech.SpeechPlayer
import com.fatihgocgun.wisepath.stats.ListeningLog
import com.fatihgocgun.wisepath.store.LibraryStore
import com.fatihgocgun.wisepath.sync.SyncEvent
import com.fatihgocgun.wisepath.sync.SyncKind
import com.fatihgocgun.wisepath.sync.SyncSink
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File

/** Which documents a library page shows. */
sealed class FolderScope {
    data object All : FolderScope()
    data object Unfiled : FolderScope()
    data class Named(val name: String) : FolderScope()
}

/** Play or a jump was asked on a finished book: start a new reading? */
data class FinishedPrompt(val doc: String, val title: String, val offset: Int, val play: Boolean)

/** "Not kaydedildi" with its text once it is written. */
data class NoteToast(val id: String, val seconds: Double?, val text: String)

/** The mark just made, which holding (or ⏭ again) grows backwards. */
data class MarkChain(val doc: String, val range: IntRange, val count: Int, val at: Long) { companion object { const val MOST = 6 } }

class AppModel private constructor(val context: Context) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    val root = File(context.filesDir, "WisePath").also { it.mkdirs() }
    init { com.fatihgocgun.wisepath.importer.DocumentImporter.init(context) }     // PDF reader resources (pdfbox-android)
    val settings = Settings(context)
    val store = LibraryStore(root)
    val player = SpeechPlayer(context)
    val log = ListeningLog(root, settings.deviceName)
    val notes = NoteStore(root, settings.deviceName)
    val recorder = NoteRecorder(context)

    /** The sync engine registers itself here; every library edit is recorded for the other devices. */
    var sync: SyncSink? = null

    // MARK: screen state (Compose observes these)

    var openDocumentID by mutableStateOf<String?>(null)
    var readerOpen by mutableStateOf(false)
    var importing by mutableStateOf(false)
    var message by mutableStateOf<String?>(null)                   // shown as a dialog (import failures, problems)
    var finishedPrompt by mutableStateOf<FinishedPrompt?>(null)
    var noteToast by mutableStateOf<NoteToast?>(null)
    var markChain by mutableStateOf<MarkChain?>(null)
    var folder by mutableStateOf<FolderScope>(FolderScope.All)
    var searchText by mutableStateOf("")
    /** Show this place in the reader without moving the reading place (a search hit, a note, a mark). */
    var revealRequest by mutableStateOf<Pair<String, Int>?>(null)
    var recording by mutableStateOf(false)

    /** Media keys in the moving modes (bike): the module decides; true = handled. */
    var remoteNextOverride: (() -> Boolean)? = null
    var remotePreviousOverride: (() -> Boolean)? = null
    /** Asked when an automation step's book ends (the automation module sets it). */
    var finishedOverride: ((String) -> Boolean)? = null
    /** Things to do once the library is known (modules register here). */
    private val modules = mutableListOf<String>()

    private fun start() {
        player.onPosition = { id, offset ->
            store.setPosition(id, offset)
            val nav = player.nav
            log.position(id, offset, nav.length) { a, b -> nav.text.substring(a.coerceIn(0, nav.length), b.coerceIn(0, nav.length)) }
            sync?.positionsChanged()
        }
        player.onFinished = { id -> documentFinished(id) }
        player.mayMove = { id, _ -> mayMove(id) }
        player.onPace = { settings.charsPerSecond = it }
        player.onSessionStart = { PlaybackService.start(context) }
        player.marks = { unit ->
            val d = player.documentID?.let { store.document(it) }
            when (unit) {
                NavigationUnit.bookmark -> d?.bookmarks?.map { it.offset } ?: emptyList()
                NavigationUnit.highlight -> d?.highlights?.map { it.location } ?: emptyList()
                else -> emptyList()
            }
        }
        player.charsPerSecond = settings.charsPerSecond
        player.setEngine(settings.ttsEngine)
        log.attach(player, store)
        applyAudioSettings()
        setUpLibrary()
        Modules.install(this)
        scope.launch { restoreLastDocument() }
    }

    // MARK: series folders and the first document

    private fun setUpLibrary() {
        val prefs = context.getSharedPreferences("wisepath.once", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("seriesFolders.v1", false)) {
            prefs.edit().putBoolean("seriesFolders.v1", true).apply()
            SERIES_FOLDERS.forEach { store.addFolder(it) }
            store.documents.value.filter { it.folder == null }.forEach { d ->
                seriesFolder(d.title)?.let { f -> store.update(d.id) { it.copy(folder = f) } }
            }
        }
        if (store.isEmpty && !prefs.getBoolean("quickStartAdded", false)) {
            prefs.edit().putBoolean("quickStartAdded", true).apply()
            runCatching {
                val d = DocumentImporter.fromClipboard(QuickStart.text)
                store.add(d.copy(title = "Hızlı Başlangıç", sourceName = "Wise Path"), null)
            }
        }
    }

    // MARK: library views

    fun sorted(list: List<DocumentRecord>, order: SortOrder = settings.sortOrder): List<DocumentRecord> = when (order) {
        SortOrder.lastOpened -> list.sortedByDescending { it.lastOpenedAt ?: it.addedAt }
        SortOrder.addDate -> list.sortedByDescending { it.addedAt }
        SortOrder.title -> list.sortedWith { a, b -> LibraryStore.collator.compare(a.title, b.title) }
        SortOrder.author -> list.sortedWith { a, b -> LibraryStore.collator.compare(a.author ?: "~", b.author ?: "~") }
        SortOrder.duration -> list.sortedBy { it.length }
        SortOrder.progress -> list.sortedByDescending { it.progress }
    }

    fun filtered(list: List<DocumentRecord>, filter: LibraryFilter = settings.filter): List<DocumentRecord> = when (filter) {
        LibraryFilter.all -> list
        LibraryFilter.unread -> list.filter { it.isUnread }
        LibraryFilter.inProgress -> list.filter { it.isInProgress }
        LibraryFilter.finished -> list.filter { it.isFinished }
        LibraryFilter.flagged -> list.filter { it.flag != null }
    }

    fun documents(scope: FolderScope, applyFilter: Boolean = true): List<DocumentRecord> {
        val all = store.documents.value
        var list = when (scope) {
            FolderScope.All -> all
            FolderScope.Unfiled -> all.filter { it.folder == null }
            is FolderScope.Named -> all.filter { it.folder == scope.name }
        }
        if (applyFilter) list = filtered(list)
        val q = searchText.trim()
        if (q.isNotEmpty()) {
            val f = TextFold.fold(q)
            list = list.filter { TextFold.fold(it.title).contains(f) || TextFold.fold(it.author ?: "").contains(f) }
        }
        return sorted(list)
    }

    fun visibleDocuments() = documents(folder)

    fun recentDocuments(limit: Int): List<DocumentRecord> =
        store.documents.value.filter { it.lastOpenedAt != null }.sortedByDescending { it.lastOpenedAt }.take(limit)

    fun neighbor(id: String, forward: Boolean): DocumentRecord? {
        val list = visibleDocuments()
        val i = list.indexOfFirst { it.id == id }
        if (i < 0) return null
        return list.getOrNull(if (forward) i + 1 else i - 1)
    }

    /** Seconds of listening for `characters` at the reading speed. */
    fun duration(characters: Int, speed: Double? = null): Double =
        characters / (settings.charsPerSecond * (speed ?: settings.speed))

    fun statusText(d: DocumentRecord): String {
        if (d.isFinished) return if (d.finishes.size > 1) "✓ Bitti · ${d.finishes.size}. kez" else "✓ Bitti"
        if (d.isUnread) return "Yeni · " + Format.duration(duration(d.length, d.speed))
        val left = duration(maxOf(0, d.length - d.position), d.speed)
        return "%${(d.progress * 100).toInt()} · ${Format.duration(left)} kaldı"
    }

    // MARK: opening

    suspend fun open(id: String) {
        val doc = store.document(id) ?: return
        openDocumentID = id
        if (player.documentID != id) {
            val content = store.content(id) ?: run { message = "Belgenin metni okunamadı."; return }
            player.load(id, doc.title, doc.author, content, doc.position, doc.language)
        }
        store.update(id) { it.copy(lastOpenedAt = now()) }
        settings.lastDocument = id
        applyAudioSettings()
    }

    /** After a restart the last document is back in the mini player, at its place, not playing. */
    suspend fun restoreLastDocument() {
        if (player.documentID != null) return
        val id = settings.lastDocument.ifEmpty { return }
        val doc = store.document(id) ?: return
        val content = store.content(id) ?: return
        player.load(id, doc.title, doc.author, content, doc.position, doc.language)
        applyAudioSettings()
    }

    val currentDocument: DocumentRecord? get() = player.documentID?.let { store.document(it) }

    // MARK: audio settings → player

    fun applyAudioSettings() {
        val s = settings
        val doc = currentDocument
        player.speed = doc?.speed ?: s.speed
        player.pitch = s.pitch
        player.voiceTune = s.voiceTune
        player.voices = s.voiceByLanguage
        player.documentVoice = doc?.voiceID
        player.mixedLanguage = s.mixedLanguage
        player.simplifyLinks = s.simplifyLinks
        player.skipCitations = s.skipCitations
        player.startAtSentence = s.startAtSentence
        player.musicMix = s.musicMix
        player.breakEvery = if (s.musicBreak) s.breakMinutes else 0.0
        player.breakLength = s.breakSeconds
    }

    fun voiceID(language: String): String? = settings.voiceByLanguage[language]

    fun setVoice(id: String, language: String, documentOnly: Boolean) {
        val doc = currentDocument
        if (documentOnly && doc != null) store.update(doc.id) { it.copy(voiceID = id) }
        else {
            settings.voiceByLanguage = settings.voiceByLanguage + (language to id)
            doc?.let { d -> if (d.voiceID != null) store.update(d.id) { it.copy(voiceID = null) } }
        }
        applyAudioSettings()
    }

    fun setSpeed(s: Double, documentOnly: Boolean) {
        val v = (s * 20).let { Math.round(it) / 20.0 }.coerceIn(0.5, 3.5)
        val doc = currentDocument
        if (documentOnly && doc != null) store.update(doc.id) { it.copy(speed = v) }
        else {
            settings.speed = v
            doc?.let { d -> if (d.speed != null) store.update(d.id) { it.copy(speed = null) } }
        }
        applyAudioSettings()
    }

    // MARK: finished books stay finished

    private fun mayMove(id: String): Boolean {
        val d = store.document(id) ?: return true
        if (!d.isFinished) return true
        if (finishedPrompt == null) finishedPrompt = FinishedPrompt(id, d.title, 0, play = true)
        return false
    }

    private fun documentFinished(id: String) {
        store.document(id)?.let { d ->
            store.setPosition(id, d.length)
            if (!d.isFinished) {
                val t = now()
                store.update(id) { it.copy(finishedAt = t, finishes = it.finishes + t) }
                store.saveNow()
            }
        }
        if (finishedOverride?.invoke(id) == true) return
        when (settings.endBehavior) {
            EndBehavior.stopAtEnd -> {}
            EndBehavior.keepGoing -> {
                val list = visibleDocuments()
                val i = list.indexOfFirst { it.id == id }
                val next = if (i >= 0) list.drop(i + 1).firstOrNull { !it.isFinished } else null
                if (next != null) scope.launch { open(next.id); player.play() }
            }
        }
    }

    /** The reader started a finished book again: a new reading from the start or from the place chosen. */
    fun startReadingAgain(id: String, at: Int = 0, play: Boolean = false) {
        val d = store.document(id) ?: return
        val pos = at.coerceIn(0, maxOf(0, d.length - 1))
        store.update(id) { it.copy(finishedAt = null) }
        store.setPosition(id, pos)
        store.saveNow()
        sync?.positionsChanged()
        if (player.documentID == id) player.moveCursor(pos, play = play)
    }

    fun rewindToBeginning(id: String) {
        val d = store.document(id) ?: return
        if (d.isFinished) { startReadingAgain(id); return }
        store.setPosition(id, 0)
        store.update(id) { it.copy(position = 0, positionAt = now()) }
        sync?.positionsChanged()
        if (player.documentID == id) player.moveCursor(0, play = false)
    }

    // MARK: importing

    /** Files chosen in the picker or shared from another app. Returns how many became documents. */
    suspend fun importUris(uris: List<Uri>, folder: String? = null): Int {
        importing = true
        val failures = mutableListOf<String>()
        var added = 0
        val into = folder ?: (this.folder as? FolderScope.Named)?.name
        for (uri in uris) {
            val name = displayName(uri)
            val result = withContext(Dispatchers.IO) {
                runCatching {
                    val tmp = File(context.cacheDir, "import-" + System.nanoTime() + "-" + name.replace('/', '_'))
                    context.contentResolver.openInputStream(uri).use { input ->
                        requireNotNull(input) { "Dosya açılamadı" }
                        tmp.outputStream().use { input.copyTo(it) }
                    }
                    try {
                        val doc = DocumentImporter.importFile(tmp, name)
                        doc to tmp
                    } catch (e: Throwable) { tmp.delete(); throw e }
                }
            }
            result.onSuccess { (doc, tmp) ->
                val rec = store.add(doc, tmp, name.substringAfterLast('.', "dat"))
                tmp.delete()
                (into ?: seriesFolder(rec.title))?.let { setFolder(rec.id, it) }
                added++
            }.onFailure { failures.add("$name: ${it.message ?: it.javaClass.simpleName}") }
        }
        importing = false
        if (failures.isNotEmpty()) message = "Eklenemeyen dosyalar:\n" + failures.joinToString("\n")
        return added
    }

    /** Imports a file already on disk (the sync Loader, the drop folder). */
    suspend fun importFile(file: File, displayName: String = file.name, folder: String? = null): DocumentRecord? {
        val doc = withContext(Dispatchers.IO) { runCatching { DocumentImporter.importFile(file, displayName) } }
            .getOrElse { message = "$displayName eklenemedi: ${it.message}"; return null }
        val rec = store.add(doc, file, displayName.substringAfterLast('.', "dat"))
        if (folder != null) { store.addFolder(folder); setFolder(rec.id, folder) }
        return rec
    }

    fun importClipboard(): Boolean {
        val cm = context.getSystemService(ClipboardManager::class.java)
        val text = cm.primaryClip?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.coerceToText(context)?.toString()
        if (text.isNullOrBlank()) { message = "Panoda metin yok."; return false }
        importText(text)
        return true
    }

    fun importText(text: String, title: String? = null, folder: String? = null): DocumentRecord? {
        val doc = runCatching { DocumentImporter.fromClipboard(text) }.getOrElse { message = it.message; return null }
        val rec = store.add(if (title != null) doc.copy(title = title) else doc, null)
        val into = folder ?: (this.folder as? FolderScope.Named)?.name
        if (into != null) { store.addFolder(into); setFolder(rec.id, into) }
        return rec
    }

    private fun displayName(uri: Uri): String {
        runCatching {
            context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
                if (c.moveToFirst()) c.getString(0)?.let { return it }
            }
        }
        return uri.lastPathSegment?.substringAfterLast('/') ?: "belge"
    }

    fun delete(ids: List<String>) {
        if (player.documentID in ids) { player.unload(); settings.lastDocument = "" }
        store.delete(ids)
        ids.forEach { sync?.record(SyncEvent(kind = SyncKind.docDelete, doc = it)) }
    }

    // MARK: bookmarks, highlights

    fun addBookmark(at: Int = player.cursor) {
        val id = player.documentID ?: return
        if (store.document(id)?.bookmarks?.any { kotlin.math.abs(it.offset - at) < 5 } == true) return
        val b = Bookmark(offset = at, excerpt = player.nav.excerpt(at))
        store.update(id) { d -> d.copy(bookmarks = (d.bookmarks + b).sortedBy { it.offset }) }
        sync?.record(SyncEvent(kind = SyncKind.bookmarkAdd, doc = id, bookmark = b))
    }

    fun removeBookmark(bid: String, doc: String? = player.documentID) {
        val id = doc ?: return
        store.update(id) { d -> d.copy(bookmarks = d.bookmarks.filterNot { it.id == bid }) }
        sync?.record(SyncEvent(kind = SyncKind.bookmarkRemove, doc = id, ref = bid))
    }

    fun addHighlight(range: IntRange, color: HighlightColor, text: String, note: String? = null) {
        val id = player.documentID ?: return
        if (range.isEmpty()) return
        val loc = range.first
        val len = range.last + 1 - range.first
        val replaced = store.document(id)?.highlights?.filter { it.location >= loc && it.end <= loc + len } ?: emptyList()
        val kept = replaced.mapNotNull { it.note }.filter { it.isNotEmpty() }
        val h = Highlight(location = loc, length = len, color = color, text = text,
            note = note ?: kept.takeIf { it.isNotEmpty() }?.joinToString("\n"))
        store.update(id) { d ->
            d.copy(highlights = (d.highlights.filterNot { r -> replaced.any { it.id == r.id } } + h).sortedBy { it.location })
        }
        replaced.forEach { sync?.record(SyncEvent(kind = SyncKind.highlightRemove, doc = id, ref = it.id)) }
        sync?.record(SyncEvent(kind = SyncKind.highlightAdd, doc = id, highlight = h))
    }

    fun removeHighlight(hid: String, doc: String? = player.documentID) {
        val id = doc ?: return
        store.update(id) { d -> d.copy(highlights = d.highlights.filterNot { it.id == hid }) }
        sync?.record(SyncEvent(kind = SyncKind.highlightRemove, doc = id, ref = hid))
    }

    fun setHighlightNote(hid: String, note: String?, doc: String? = player.documentID) {
        val id = doc ?: return
        val n = note?.takeIf { it.isNotBlank() }
        store.update(id) { d -> d.copy(highlights = d.highlights.map { if (it.id == hid) it.copy(note = n) else it }) }
        sync?.record(SyncEvent(kind = SyncKind.highlightNote, doc = id, ref = hid, text = n))
    }

    private fun overlapsHalf(h: Highlight, r: IntRange): Boolean {
        val a = maxOf(h.location, r.first)
        val b = minOf(h.end, r.last + 1)
        val rl = r.last + 1 - r.first
        return (b - a) * 2 >= minOf(h.length, rl) && b > a
    }

    fun isMarked(r: IntRange): Boolean = currentDocument?.highlights?.any { overlapsHalf(it, r) } ?: false

    /** The place a note or a mark belongs to: the sentence being read (or where reading stopped). */
    fun sentenceNow(): IntRange? {
        if (player.documentID == null) return null
        return player.spoken.value.sentence ?: player.nav.sentenceRange(player.cursor)
    }

    /**
     * One press: the sentence being read turns yellow. A second press on the same sentence takes the mark away.
     * Pressed in the first two seconds of a new sentence, the one that just ended was meant.
     * Returns true when a mark was added, false when one was taken away, null when nothing happened.
     */
    fun markSpokenSentence(): Boolean? {
        val id = player.documentID ?: return null
        var r = sentenceNow() ?: return null
        if (r.isEmpty()) return null
        val since = sentenceSince
        if (player.isPlaying && since != null && since.first == r.first && System.currentTimeMillis() - since.second < 2000) {
            val prev = player.nav.sentenceBefore(r.first)
            if (prev != null && !isMarked(prev)) r = prev
        }
        val marked = store.document(id)?.highlights?.filter { overlapsHalf(it, r) } ?: emptyList()
        if (marked.isNotEmpty()) {
            marked.forEach { removeHighlight(it.id) }
            markChain = null
            Haptics.tick(context, strong = false)
            return false
        }
        val text = player.nav.substring(r).trim()
        if (text.isEmpty()) return null
        addHighlight(r, HighlightColor.YELLOW, text)
        markChain = MarkChain(id, r, 1, System.currentTimeMillis())
        Haptics.tick(context, strong = true)
        return true
    }

    /** The mark grows back by one sentence (held mark key, or ⏭ again). Null: nothing more to take. */
    fun extendMarkBack(): Int? {
        val id = player.documentID ?: return null
        var c = markChain
        if (c == null || c.doc != id) {
            val r = sentenceNow() ?: return null
            val h = store.document(id)?.highlights?.firstOrNull { it.location < r.last + 1 && r.first < it.end } ?: return null
            c = MarkChain(id, h.location until h.end, 1, System.currentTimeMillis())
        }
        if (c.count >= MarkChain.MOST) return null
        val prev = player.nav.sentenceBefore(c.range.first) ?: return null
        val r = prev.first..c.range.last
        store.document(id)?.highlights?.filter { it.location < r.last + 1 && r.first < it.end }?.forEach { removeHighlight(it.id) }
        addHighlight(r, HighlightColor.YELLOW, player.nav.substring(r).trim())
        markChain = c.copy(range = r, count = c.count + 1, at = System.currentTimeMillis())
        Haptics.tick(context, strong = true)
        return c.count + 1
    }

    /** When the sentence being read began (for the late press of the mark key). */
    private var sentenceSince: Pair<Int, Long>? = null
    init {
        scope.launch {
            player.spoken.collect { s -> s.sentence?.let { if (sentenceSince?.first != it.first) sentenceSince = it.first to System.currentTimeMillis() } }
        }
    }

    // MARK: notes

    private var pendingNote: PendingNote? = null
    private var resumeAfterNote = false
    private data class PendingNote(val doc: String, val title: String, val range: IntRange, val quote: String, val chapter: String?)

    fun toggleVoiceNote(anchor: IntRange? = null) { if (recorder.isRecording) finishVoiceNote() else startVoiceNote(anchor) }

    /** Reading pauses, recording starts; the note belongs to `anchor` (a highlight) or the sentence being read. */
    fun startVoiceNote(anchor: IntRange? = null) {
        if (recorder.isRecording) return
        val id = player.documentID ?: return
        val doc = store.document(id) ?: return
        val r = anchor ?: sentenceNow() ?: return
        pendingNote = PendingNote(id, doc.title, r, player.nav.substring(r).trim(), player.nav.chapterTitle(r.first))
        resumeAfterNote = player.isPlaying
        if (player.isPlaying) player.pause()
        Haptics.tick(context, strong = true)
        if (!recorder.start()) {
            pendingNote = null
            message = "Kayıt başlatılamadı. Mikrofon iznini verin."
            resumeReading()
        }
        recording = recorder.isRecording
    }

    fun finishVoiceNote() {
        val result = recorder.stop()
        recording = false
        val p = pendingNote
        pendingNote = null
        if (p != null && result != null) {
            val n = notes.add(p.doc, p.title, p.range.first, p.range.last + 1 - p.range.first, p.quote, p.chapter, "",
                null, result.first, result.second)
            noteToast = NoteToast(n.id, result.second, "")
            scope.launch {
                val f = notes.audioFile(n) ?: return@launch
                val text = recorder.transcribe(f)
                if (text.isNotBlank() && notes.note(n.id)?.text.isNullOrEmpty()) {
                    notes.setText(n.id, text, "device")
                    if (noteToast?.id == n.id) noteToast = noteToast?.copy(text = text)
                }
            }
        }
        resumeReading()
    }

    fun cancelVoiceNote() {
        recorder.cancel()
        recording = false
        pendingNote = null
        resumeReading()
    }

    private fun resumeReading() {
        if (!resumeAfterNote) return
        resumeAfterNote = false
        player.play(player.nav.sentenceStart(player.cursor + 1), snap = false)
    }

    /** A written note on a range (a highlight or a selection). */
    fun addTextNote(range: IntRange, quote: String, text: String) {
        val id = player.documentID ?: return
        val doc = store.document(id) ?: return
        if (text.isBlank()) return
        notes.add(id, doc.title, range.first, range.last + 1 - range.first, quote, player.nav.chapterTitle(range.first), text, null, null, null)
    }

    // MARK: library edits (recorded for the other devices)

    fun setFolder(id: String, folder: String?) {
        store.update(id) { it.copy(folder = folder) }
        sync?.record(SyncEvent(kind = SyncKind.docFolder, doc = id, text = folder))
    }

    fun setFlag(id: String, flag: HighlightColor?) {
        store.update(id) { it.copy(flag = flag) }
        sync?.record(SyncEvent(kind = SyncKind.docFlag, doc = id, text = flag?.name?.lowercase()))
    }

    fun rename(id: String, title: String) {
        if (title.isBlank()) return
        store.update(id) { it.copy(title = title.trim()) }
        sync?.record(SyncEvent(kind = SyncKind.docTitle, doc = id, text = title.trim()))
    }

    fun addFolder(name: String) { store.addFolder(name); sync?.record(SyncEvent(kind = SyncKind.folderAdd, text = name)) }
    fun removeFolder(name: String) { store.removeFolder(name); sync?.record(SyncEvent(kind = SyncKind.folderRemove, text = name)) }
    fun renameFolder(old: String, new: String) {
        store.renameFolder(old, new)
        sync?.record(SyncEvent(kind = SyncKind.folderRename, text = old, text2 = new))
    }

    /** The marks of a book as Markdown (share sheet). */
    fun highlightsExport(doc: DocumentRecord): String {
        val sb = StringBuilder("# ${doc.title}\n")
        doc.author?.let { sb.append("_${it}_\n") }
        sb.append('\n')
        val content = store.cachedContent(doc.id)
        var lastChapter: String? = null
        for (h in doc.highlights.sortedBy { it.location }) {
            val ch = content?.chapters?.lastOrNull { it.offset <= h.location }?.title
            if (ch != null && ch != lastChapter) { sb.append("## $ch\n\n"); lastChapter = ch }
            sb.append("> ${h.text}\n")
            h.note?.let { sb.append("\n$it\n") }
            sb.append('\n')
        }
        for (n in notes.notes(doc.id)) if (n.text.isNotBlank()) sb.append("- ${n.quote.take(60)}… — ${n.text}\n")
        return sb.toString()
    }

    // MARK: media keys

    fun remotePlay() { if (!player.state.value.isSpeaking && player.documentID == null) scope.launch { restoreLastDocument(); player.play() } else player.toggle() }
    fun remotePause() {
        if (settings.remotePauseWaits && player.isPlaying) player.activePause(if (settings.waitSeconds > 0) settings.waitSeconds else null)
        else player.pause()
    }
    fun remoteNext() { if (remoteNextOverride?.invoke() != true) player.skip(true, settings.navigationUnit) }
    fun remotePrevious() { if (remotePreviousOverride?.invoke() != true) player.skip(false, settings.navigationUnit) }
    fun seekToMillis(ms: Long) {
        val chars = (ms / 1000.0 * player.charsPerSecond * player.speed).toInt()
        player.moveCursor(player.nav.wordRange(chars.coerceIn(0, maxOf(0, player.nav.length - 1))).first)
    }

    init { start() }

    companion object {
        /** The listening series, plus literature; a document whose title starts with a series name is filed there. */
        val SERIES_FOLDERS = listOf("Felsefe", "Bilimler", "Mühendislik", "Edebiyat")

        fun seriesFolder(title: String): String? {
            val t = title.trim().lowercase(Format.tr)
            return listOf("Felsefe", "Bilimler", "Mühendislik").firstOrNull { t.startsWith(it.lowercase(Format.tr)) }
        }

        @Volatile private var instance: AppModel? = null
        fun get(context: Context): AppModel = instance ?: synchronized(this) {
            instance ?: AppModel(context.applicationContext).also { instance = it }
        }
    }
}
