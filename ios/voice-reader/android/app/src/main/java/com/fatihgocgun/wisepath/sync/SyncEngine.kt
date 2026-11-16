// Connects the library to the shared folder (port of SyncEngine in Model/SyncEngine.swift, plus AppModel.apply and
// AppModel.appendParts): pushes local changes, pulls the other devices'. Runs when the app starts, when it goes to the
// background, every three minutes while it is on screen, and every fifteen minutes from WorkManager.
package com.fatihgocgun.wisepath.sync

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.Chapter
import com.fatihgocgun.wisepath.model.DocumentContent
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.model.HighlightColor
import com.fatihgocgun.wisepath.model.countWords
import com.fatihgocgun.wisepath.stats.ListeningDay
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.withContext
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class SyncEngine(private val app: AppModel) : SyncSink {
    private val context: Context = app.context
    private val prefs: SharedPreferences = context.getSharedPreferences("wisepath.sync", Context.MODE_PRIVATE)
    /** One background thread for every file operation, so writes never cross. */
    private val io = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    private val main = Handler(Looper.getMainLooper())
    val vault = VaultMirror(context, prefs)

    // MARK: what the settings page shows

    var status by mutableStateOf(if (app.settings.syncFolderUri.isEmpty()) "Klasör seçilmedi" else "Bekliyor")
        private set
    var error by mutableStateOf<String?>(prefs.getString("sync.error", null))
        private set
    var lastSync by mutableLongStateOf(prefs.getLong("sync.last", 0L))
        private set
    var busy by mutableStateOf(false)
        private set
    var vaultStatus by mutableStateOf(vault.status)
        private set

    private var files: SyncFiles? = null
    private var filesKey = ""
    private val pendingEvents = ArrayList<SyncEvent>()       // main thread
    private var cloudBacklog = ArrayList<SyncEvent>()        // io thread: held until the folder is there
    private var stateJob: Job? = null
    private var stateFirstPending = 0L
    private val running = Mutex()
    private var loop: Job? = null

    private val device get() = app.settings.deviceName.trim().ifEmpty { "android" }

    /** The shared folder, opened again when the picked folder or the device name changed. Io thread. */
    private fun files(): SyncFiles? {
        val uri = app.settings.syncFolderUri
        if (uri.isEmpty()) { files = null; return null }
        val key = "$uri|$device"
        files?.let { if (filesKey == key) return it }
        val tree = Tree(context, Uri.parse(uri))
        if (!tree.usable) { files = null; throw IllegalStateException("Klasöre erişilemiyor; yeniden seç.") }
        return SyncFiles(tree, device).also { files = it; filesKey = key }
    }

    // MARK: lifecycle

    fun start() {
        ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
            override fun onStart(owner: LifecycleOwner) {
                loop?.cancel()
                loop = app.scope.launch {
                    while (true) { syncNow(); delay(FOREGROUND_EVERY_MS) }
                }
            }
            override fun onStop(owner: LifecycleOwner) {
                loop?.cancel(); loop = null
                app.scope.launch { writeStateNow(); syncNow() }
            }
        })
        // the vault copy follows the notes and the listening log (other hooks set before this one keep running)
        val previousNotes = app.notes.onWrite
        app.notes.onWrite = { log, audio -> previousNotes?.invoke(log, audio); mirrorNotes(log, audio) }
        val previousLog = app.log.onSave
        app.log.onSave = { days -> previousLog?.invoke(days); mirrorListening(days) }
        schedule(context)
    }

    // MARK: push

    override fun record(event: SyncEvent) = onMain {
        if (event.kind == SyncKind.docDelete) event.doc?.let { id ->
            // a document deleted here never comes back from the folder, and its folder there goes
            markDeleted(listOf(id))
            app.scope.launch(io) { runCatching { files()?.removeDocument(id) } }
        }
        pendingEvents += event
        app.scope.launch { flushEvents() }
    }

    private fun onMain(block: () -> Unit) { if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block) }

    private suspend fun flushEvents() {
        if (pendingEvents.isEmpty()) return
        val batch = ArrayList(pendingEvents)
        pendingEvents.clear()
        withContext(io) {
            runCatching { vault.append(batch, device) }                   // the vault copy, even without a sync folder
            cloudBacklog.addAll(batch)
            val f = runCatching { files() }.getOrNull() ?: return@withContext
            if (f.append(cloudBacklog)) cloudBacklog = ArrayList()
        }
        refreshVaultStatus()
    }

    /**
     * Positions are written a few seconds after they settle, not on every word. The player reports every two seconds
     * while it reads, so a change that has waited 30 seconds is written even if more keep coming.
     */
    override fun positionsChanged() = onMain {
        val now = System.currentTimeMillis()
        if (stateFirstPending == 0L) stateFirstPending = now
        val wait = minOf(STATE_SETTLE_MS, maxOf(0L, STATE_MAX_WAIT_MS - (now - stateFirstPending)))
        stateJob?.cancel()
        stateJob = app.scope.launch { delay(wait); writeStateNow() }
    }

    private suspend fun writeStateNow() {
        stateJob = null
        stateFirstPending = 0L
        val docs = LinkedHashMap<String, StateEntry>()
        for (listed in app.store.documents.value) {
            if (listed.positionAt == null && listed.lastOpenedAt == null) continue
            val d = app.store.document(listed.id) ?: listed           // the exact place from the journal
            docs[d.id] = StateEntry(d.position, d.lastOpenedAt, d.positionAt ?: d.lastOpenedAt ?: d.addedAt, d.length, d.title)
        }
        val json = DeviceStateCodec.encode(docs)
        withContext(io) {
            runCatching { vault.writeState(json, device) }
            runCatching { files()?.tree?.let { t -> t.path("State")?.let { t.write(it, "$device.json", json.toByteArray()) } } }
        }
    }

    // MARK: the vault copy

    private fun mirrorNotes(log: File, audio: File) {
        if (!vault.connected) return
        app.scope.launch(io) { runCatching { vault.mirrorNotes(log, audio, device) } }
    }

    private fun mirrorListening(days: Map<String, ListeningDay>) {
        if (!vault.connected) return
        val text = AppJson.encodeToString(MapSerializer(String.serializer(), ListeningDay.serializer()), days)
        app.scope.launch(io) { runCatching { vault.writeListening(text.toByteArray(), device) } }
    }

    /** The vault copy: document list and (first time) every existing highlight and bookmark. */
    private suspend fun mirrorLibrary() {
        if (!vault.connected) return
        val docs = app.store.documents.value
        withContext(io) {
            runCatching {
                vault.seedIfNeeded(docs, device)
                vault.writeMeta(docs.map { VaultMirror.Meta(it.author, it.folder, it.id, it.language, it.length, it.title) })
                for (id in vault.missingTexts(docs.map { it.id })) {
                    runCatching { app.store.contentFile(id).readBytes() }.getOrNull()?.let { vault.writeText(it, id) }
                }
            }
        }
        refreshVaultStatus()
    }

    private fun refreshVaultStatus() = onMain { vaultStatus = vault.status }

    fun chooseVault(uri: Uri): String? = vault.choose(uri).also { refreshVaultStatus(); if (it == null) app.scope.launch { syncNow() } }
    fun forgetVault() { vault.forget(); refreshVaultStatus() }

    // MARK: the folder

    fun folderChanged() {
        files = null
        prefs.edit().remove("sync.published").apply()
        status = if (app.settings.syncFolderUri.isEmpty()) "Klasör seçilmedi" else "Bekliyor"
        error = null
        app.scope.launch { syncNow() }
    }

    private val deleted: Set<String> get() = prefs.getStringSet("sync.deleted", emptySet()) ?: emptySet()
    private fun markDeleted(ids: List<String>) = prefs.edit().putStringSet("sync.deleted", deleted + ids).apply()
    private val published: Set<String> get() = prefs.getStringSet("sync.published", emptySet()) ?: emptySet()

    private val seen: Map<String, Int>
        get() = runCatching { AppJson.decodeFromString(MapSerializer(String.serializer(), Int.serializer()), prefs.getString("sync.seen", "{}")!!) }
            .getOrDefault(emptyMap())

    // MARK: pull

    /** One whole pass. Returns false when it could not run (no folder, already running, an error). */
    suspend fun syncNow(): Boolean = withContext(Dispatchers.Main) {
        if (!running.tryLock()) return@withContext false
        busy = true
        try {
            mirrorLibrary()
            if (app.settings.syncFolderUri.isEmpty()) { status = "Klasör seçilmedi"; return@withContext false }
            status = "Eşitleniyor…"
            pass()
            lastSync = System.currentTimeMillis()
            prefs.edit().putLong("sync.last", lastSync).remove("sync.error").apply()
            error = null
            status = "Eşitlendi · ${Format.date(lastSync, "HH:mm")}"
            true
        } catch (e: Exception) {
            error = e.message ?: e.javaClass.simpleName
            prefs.edit().putString("sync.error", error).apply()
            status = "Eşitlenemedi"
            false
        } finally {
            busy = false
            running.unlock()
        }
    }

    private suspend fun pass() {
        val f = withContext(io) { files() } ?: return
        flushEvents()
        val store = app.store

        // 1. new documents from other devices
        val remote = withContext(io) { f.libraryIDs() }
        val known = store.documents.value.map { it.id.uppercase() }.toSet()
        val gone = deleted.map { it.uppercase() }.toSet()
        for (id in remote) {
            if (id in known || id in gone) continue
            val got = withContext(io) {
                val meta = f.meta(id) ?: return@withContext null
                val content = f.content(id) ?: return@withContext null
                Triple(meta, content, f.cover(id))
            } ?: continue
            val (meta, content, cover) = got
            val r = DocumentRecord(
                id = meta.id.uppercase(), title = meta.title, author = meta.author, format = meta.format, sourceName = meta.sourceName,
                folder = meta.folder, addedAt = meta.addedAt, length = content.text.length, wordCount = countWords(content.text),
                language = meta.language,
            )
            meta.folder?.let { store.addFolder(it) }
            store.insert(r, content, cover)
        }
        // what came from the folder needs no publishing
        prefs.edit().putStringSet("sync.published", published + remote).apply()

        // 2. events (highlights, bookmarks, folders…) from the others
        val (events, counts) = withContext(io) { f.otherEvents(seen) }
        for (e in events.sortedBy { it.at }) apply(e)
        prefs.edit().putString("sync.seen", AppJson.encodeToString(MapSerializer(String.serializer(), Int.serializer()), counts)).apply()

        // 3. positions: another device that read further carries this one forward. Sync never takes a place back;
        //    going back is only ever done by hand (an old state file, a clock off by minutes must not undo listening).
        for (state in withContext(io) { f.otherStates() }) {
            for ((id, entry) in state) {
                val d = store.documents.value.firstOrNull { it.id.equals(id, ignoreCase = true) }?.let { store.document(it.id) } ?: continue
                if (entry.at <= (d.positionAt ?: 0L) || entry.position <= d.position) continue
                if (app.player.documentID == d.id && app.player.state.value.isSpeaking) continue
                val pos = minOf(entry.position, d.length)
                store.setPosition(d.id, pos, entry.at)
                entry.opened?.let { o -> if (o > (d.lastOpenedAt ?: 0L)) store.update(d.id) { it.copy(lastOpenedAt = o) } }
                if (app.player.documentID == d.id && !d.isFinished) app.player.moveCursor(pos, play = false)
            }
        }

        // 4. pages appended to documents
        val remoteSet = remote.toSet()
        for (d in store.documents.value) {
            if (d.id.uppercase() !in remoteSet) continue
            val added = withContext(io) { f.parts(d.id, d.partsApplied ?: 0) }
            if (added.isNotEmpty()) appendParts(added, d.id)
        }

        // 5. the Loader inbox
        val claimed = withContext(io) { f.claimLoader() }
        for (c in claimed) {
            val tmp = withContext(io) {
                val data = f.tree.read(c.node) ?: return@withContext null
                File(context.cacheDir, "sync-" + System.nanoTime() + "-" + c.name.replace('/', '_')).also { it.writeBytes(data) }
            } ?: continue
            try {
                c.folder?.let { store.addFolder(it) }
                // the folder goes along as a parameter, never through the library's chosen folder
                app.importFile(tmp, c.name, c.folder)
            } finally { tmp.delete() }
            withContext(io) { f.finishLoader(c) }
        }

        // 6. documents of this device the folder does not have yet go up (imports, and those from before sync)
        val done = published
        val up = store.documents.value.filter { it.id.uppercase() !in remoteSet && it.id !in done && it.id.uppercase() !in gone }
        val sent = ArrayList<String>()
        for (d in up) {
            val meta = DocumentMeta(d.id, d.title, d.author, d.format, d.sourceName, d.language, d.addedAt, d.folder)
            val ok = withContext(io) {
                val content = runCatching { store.contentFile(d.id).readBytes() }.getOrNull() ?: return@withContext false
                val cover = store.coverFile(d.id).takeIf { it.exists() }?.let { runCatching { it.readBytes() }.getOrNull() }
                f.publish(meta, content, cover)
            }
            if (ok) sent += d.id
        }
        if (sent.isNotEmpty()) prefs.edit().putStringSet("sync.published", published + sent).apply()
        writeStateNow()
    }

    // MARK: applying the others' changes (AppModel.apply in iOS): recorded nowhere again

    private fun apply(e: SyncEvent) {
        val store = app.store
        val id = e.doc?.let { d -> store.documents.value.firstOrNull { it.id.equals(d, ignoreCase = true) }?.id }
        when (e.kind) {
            SyncKind.highlightAdd -> { val h = e.highlight ?: return; id ?: return
                store.update(id) { d -> if (d.highlights.any { it.id == h.id }) d else d.copy(highlights = (d.highlights + h).sortedBy { it.location }) } }
            SyncKind.highlightRemove -> { val r = e.ref ?: return; id ?: return
                store.update(id) { d -> d.copy(highlights = d.highlights.filterNot { it.id.equals(r, true) }) } }
            SyncKind.highlightNote -> { val r = e.ref ?: return; id ?: return
                store.update(id) { d -> d.copy(highlights = d.highlights.map { if (it.id.equals(r, true)) it.copy(note = e.text) else it }) } }
            SyncKind.bookmarkAdd -> { val b = e.bookmark ?: return; id ?: return
                store.update(id) { d -> if (d.bookmarks.any { it.id == b.id }) d else d.copy(bookmarks = (d.bookmarks + b).sortedBy { it.offset }) } }
            SyncKind.bookmarkRemove -> { val r = e.ref ?: return; id ?: return
                store.update(id) { d -> d.copy(bookmarks = d.bookmarks.filterNot { it.id.equals(r, true) }) } }
            SyncKind.docFolder -> { id ?: return
                e.text?.let { store.addFolder(it) }
                store.update(id) { it.copy(folder = e.text) } }
            SyncKind.docFlag -> { id ?: return
                val flag = e.text?.let { t -> HighlightColor.entries.firstOrNull { it.name.equals(t, ignoreCase = true) } }
                store.update(id) { it.copy(flag = flag) } }
            SyncKind.docTitle -> { val t = e.text ?: return; id ?: return; store.update(id) { it.copy(title = t) } }
            SyncKind.docDelete -> {
                markDeleted(listOfNotNull(e.doc?.uppercase(), id))
                id ?: return
                if (app.player.documentID == id) { app.player.unload(); app.settings.lastDocument = "" }
                if (app.openDocumentID == id) app.openDocumentID = null
                store.delete(listOf(id))
            }
            SyncKind.folderAdd -> e.text?.let { store.addFolder(it) }
            SyncKind.folderRemove -> e.text?.let { store.removeFolder(it) }
            SyncKind.folderRename -> { val a = e.text ?: return; val b = e.text2 ?: return; store.renameFolder(a, b) }
        }
    }

    /**
     * Pages appended to a document (Library/<id>/parts): added to the end of the text, so every earlier position,
     * highlight and bookmark keeps its place.
     */
    private suspend fun appendParts(pages: List<String>, id: String) {
        val store = app.store
        val content = store.content(id) ?: return
        val text = StringBuilder(content.text)
        val chapters = content.chapters.toMutableList()
        // the stored text may lack its last line break (the Android importer trims it): a part starts on its own line
        if (text.isNotEmpty() && text.last() != '\n') text.append('\n')
        for (page in pages) {
            val (paragraphs, headings) = MarkdownParts.parse(page)
            val offsets = ArrayList<Int>()
            for (p in paragraphs) { offsets += text.length; text.append(p).append('\n') }
            for (h in headings) if (h.paragraph < offsets.size) chapters += Chapter(h.title, offsets[h.paragraph], h.level)
        }
        val newContent = DocumentContent(text.toString(), chapters, content.pages)
        store.replaceContent(id, newContent, countWords(newContent.text))
        // new pages on a finished book: it is being read again from where it stood (the finish stays in its history)
        store.update(id) { it.copy(partsApplied = (it.partsApplied ?: 0) + pages.size, finishedAt = null) }
        if (app.player.documentID == id) app.player.extend(newContent)
    }

    companion object {
        private const val STATE_SETTLE_MS = 4_000L
        private const val STATE_MAX_WAIT_MS = 30_000L
        private const val FOREGROUND_EVERY_MS = 3 * 60_000L

        @Volatile var instance: SyncEngine? = null

        fun schedule(context: Context) {
            val req = PeriodicWorkRequestBuilder<SyncWorker>(15, TimeUnit.MINUTES).build()
            WorkManager.getInstance(context).enqueueUniquePeriodicWork("wisepath.sync", ExistingPeriodicWorkPolicy.KEEP, req)
        }
    }
}

/** The background pass (WorkManager, at most every 15 minutes, also when the app is not open). */
class SyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        withContext(Dispatchers.Main) { AppModel.get(applicationContext) }      // installs the engine through Modules
        val engine = SyncEngine.instance ?: return Result.success()
        engine.syncNow()
        return Result.success()
    }
}

/** Markdown → readable paragraphs and headings (port of DocumentImporter.parseMarkdown). */
object MarkdownParts {
    data class Heading(val paragraph: Int, val title: String, val level: Int)

    fun parse(text: String): Pair<List<String>, List<Heading>> {
        val paragraphs = ArrayList<String>()
        val headings = ArrayList<Heading>()
        var inFence = false
        var inFront = false
        for ((n, raw) in text.split("\r\n", "\n", "\r").withIndex()) {
            var line = raw.trim()
            if (n == 0 && line == "---") { inFront = true; continue }
            if (inFront) { if (line == "---") inFront = false; continue }
            if (line.startsWith("```")) { inFence = !inFence; continue }
            if (line.isEmpty() || line.all { it in "-*_=|: " }) continue
            var level = 0
            while (line.startsWith("#")) { line = line.drop(1); level++ }
            line = line.trim()
            if (line.startsWith(">")) line = line.dropWhile { it == '>' || it == ' ' }
            if (line.startsWith("|")) line = line.split("|").map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" · ")
            if (!inFence && (line.startsWith("- ") || line.startsWith("* ") || line.startsWith("+ "))) line = line.drop(2)
            line = strip(line)
            if (line.isEmpty()) continue
            if (level > 0) headings += Heading(paragraphs.size, line, level)
            paragraphs += line
        }
        return paragraphs to headings
    }

    private fun strip(s: String): String {
        var t = s
        t = t.replace(Regex("""!?\[([^\]]*)\]\([^)]*\)"""), "$1")
        t = t.replace(Regex("""\[\[(?:[^\]|]*\|)?([^\]]*)\]\]"""), "$1")
        t = t.replace(Regex("""(\*\*|__|\*|_|`|~~)"""), "")
        return t.trim()
    }
}

/** Hooks sync into the app (called once from Modules.install). */
fun installSync(app: AppModel) {
    val engine = SyncEngine(app)
    SyncEngine.instance = engine
    app.sync = engine
    // AppModel may be created on a worker thread (WorkManager); the lifecycle wants the main thread
    Handler(Looper.getMainLooper()).post { engine.start() }
}

