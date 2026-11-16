// The library on disk (port of Model/LibraryStore.swift):
//   files/WisePath/library.json            every DocumentRecord + the folder names
//   files/WisePath/library.backup.json     the copy from the last launch that read cleanly
//   files/WisePath/docs/<id>/content.json  the readable text, headings, pages
//   files/WisePath/docs/<id>/source.<ext>  the original file, kept for later re-import
//   files/WisePath/docs/<id>/cover.jpg
//   files/WisePath/places.json             the reading place of every document, written within a second of each move;
//                                          it wins over library.json when newer, so no kill, crash or update loses it
package com.fatihgocgun.wisepath.store

import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.DocumentContent
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.model.ImportedDocument
import com.fatihgocgun.wisepath.model.Instant
import com.fatihgocgun.wisepath.model.now
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.text.Collator
import java.util.Locale
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

@Serializable
data class Place(val position: Int, val at: Instant)

@Serializable
private data class LibraryFile(val documents: List<DocumentRecord>, val folders: List<String> = emptyList())

class LibraryStore(val root: File) {
    private val _documents = MutableStateFlow<List<DocumentRecord>>(emptyList())
    val documents: StateFlow<List<DocumentRecord>> = _documents
    private val _folders = MutableStateFlow<List<String>>(emptyList())
    val folders: StateFlow<List<String>> = _folders
    /** Bumped when a cover appears, so cover views reload. */
    val coverVersion = MutableStateFlow(0)

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val writer = Executors.newSingleThreadExecutor()
    private val contentCache = ConcurrentHashMap<String, DocumentContent>()
    private val places = ConcurrentHashMap<String, Place>()
    private var placeWritePending = false
    private var saveJob: Job? = null

    private val libraryFile get() = File(root, "library.json")
    private val backupFile get() = File(root, "library.backup.json")
    private val placesFile get() = File(root, "places.json")
    fun folderOf(id: String) = File(root, "docs/$id")
    fun coverFile(id: String) = File(folderOf(id), "cover.jpg")
    fun contentFile(id: String) = File(folderOf(id), "content.json")

    init {
        File(root, "docs").mkdirs()
        load()
        restorePlaces()
    }

    val isEmpty: Boolean get() = _documents.value.isEmpty()

    // MARK: reading the file — one bad record never takes the others with it

    private fun decodeLossy(text: String): Pair<LibraryFile, Int>? = try {
        val obj = AppJson.parseToJsonElement(text).jsonObject
        val arr = obj["documents"]?.jsonArray ?: JsonArray(emptyList())
        val docs = arr.mapNotNull { runCatching { AppJson.decodeFromJsonElement<DocumentRecord>(it) }.getOrNull() }
        val folders = (obj["folders"] as? JsonArray)?.mapNotNull { runCatching { it.jsonPrimitive.content }.getOrNull() } ?: emptyList()
        LibraryFile(docs, folders) to (arr.size - docs.size)
    } catch (e: Exception) { null }

    private fun load() {
        val raw = runCatching { libraryFile.readText() }.getOrNull()
        if (raw != null) {
            val parsed = decodeLossy(raw)
            if (parsed != null && parsed.second == 0) {
                _documents.value = parsed.first.documents
                _folders.value = parsed.first.folders
                runCatching { backupFile.writeText(raw) }
            } else {
                // a file this version cannot fully read is kept aside, never written over
                runCatching { libraryFile.copyTo(File(root, "library-unread-${System.currentTimeMillis()}.json"), overwrite = true) }
                val backup = runCatching { backupFile.readText() }.getOrNull()?.let { decodeLossy(it)?.first }
                val docs = (parsed?.first?.documents ?: emptyList()).toMutableList()
                backup?.documents?.forEach { d -> if (docs.none { it.id == d.id }) docs.add(d) }
                _documents.value = docs
                _folders.value = ((parsed?.first?.folders ?: emptyList()) + (backup?.folders ?: emptyList())).distinct().sortedWith(collator)
            }
        } else {
            val backup = runCatching { backupFile.readText() }.getOrNull()?.let { decodeLossy(it)?.first }
            if (backup != null) { _documents.value = backup.documents; _folders.value = backup.folders }
        }
    }

    // MARK: reading places

    private val placesSerializer = MapSerializer(String.serializer(), Place.serializer())

    private fun restorePlaces() {
        val stored = runCatching { AppJson.decodeFromString(placesSerializer, placesFile.readText()) }.getOrNull() ?: emptyMap()
        places.putAll(stored)
        var changed = false
        _documents.value = _documents.value.map { d ->
            val p = places[d.id]
            if (p != null && p.at > (d.positionAt ?: 0)) {
                changed = true
                d.copy(position = p.position.coerceIn(0, d.length), positionAt = p.at)
            } else d
        }
        if (changed) saveSoon()
    }

    /**
     * The speech cursor moved. The journal is written within a second; the library list (which every screen
     * observes) changes only when the whole per cent changes, on a jump, or at the start or the end.
     */
    fun setPosition(id: String, offset: Int, at: Long = now()) {
        places[id] = Place(offset, at)
        val d = _documents.value.firstOrNull { it.id == id }
        if (d != null) {
            val step = maxOf(1, d.length / 100)
            if (d.position == 0 || offset == 0 || offset >= d.length || offset / step != d.position / step || kotlin.math.abs(offset - d.position) > step) {
                update(id) { it.copy(position = offset, positionAt = at) }
            }
        }
        if (placeWritePending) return
        placeWritePending = true
        scope.launch { delay(1000); writePlaces() }
    }

    fun writePlaces() {
        placeWritePending = false
        val snapshot = HashMap(places)
        writer.execute { runCatching { atomicWrite(placesFile, AppJson.encodeToString(placesSerializer, snapshot)) } }
    }

    /** The record, with the exact place from the journal when that is newer than the list's. */
    fun document(id: String): DocumentRecord? {
        val d = _documents.value.firstOrNull { it.id == id } ?: return null
        val p = places[id]
        return if (p != null && p.at > (d.positionAt ?: 0)) d.copy(position = p.position.coerceIn(0, d.length), positionAt = p.at) else d
    }

    // MARK: adding and removing

    fun add(imported: ImportedDocument, original: File?, originalExt: String? = null): DocumentRecord {
        val record = DocumentRecord(
            title = imported.title, author = imported.author, format = imported.format,
            sourceName = imported.sourceName, length = imported.content.text.length,
            wordCount = imported.wordCount, language = imported.language,
        )
        val dir = folderOf(record.id)
        dir.mkdirs()
        atomicWrite(File(dir, "content.json"), AppJson.encodeToString(DocumentContent.serializer(), imported.content))
        imported.cover?.let { runCatching { File(dir, "cover.jpg").writeBytes(it) } }
        if (original != null) {
            val ext = (originalExt ?: original.extension).ifEmpty { "dat" }
            runCatching { original.copyTo(File(dir, "source.$ext"), overwrite = true) }
        }
        contentCache[record.id] = imported.content
        _documents.value = listOf(record) + _documents.value
        saveSoon()
        return record
    }

    /** A document that arrived from another device or from sync: same id, its content and cover as given. */
    fun insert(record: DocumentRecord, content: DocumentContent, cover: ByteArray?) {
        if (document(record.id) != null) return
        val dir = folderOf(record.id)
        dir.mkdirs()
        atomicWrite(File(dir, "content.json"), AppJson.encodeToString(DocumentContent.serializer(), content))
        if (cover != null) { runCatching { File(dir, "cover.jpg").writeBytes(cover) }; coverVersion.value++ }
        contentCache[record.id] = content
        _documents.value = listOf(record) + _documents.value
        saveSoon()
    }

    /** Replace a document's text (pages appended by sync); the record's length follows. */
    fun replaceContent(id: String, content: DocumentContent, wordCount: Int) {
        atomicWrite(contentFile(id), AppJson.encodeToString(DocumentContent.serializer(), content))
        contentCache[id] = content
        update(id) { it.copy(length = content.text.length, wordCount = wordCount) }
    }

    fun setCover(id: String, bytes: ByteArray) {
        runCatching { coverFile(id).writeBytes(bytes) }
        coverVersion.value++
    }

    fun delete(ids: Collection<String>) {
        val set = ids.toSet()
        for (id in set) {
            folderOf(id).deleteRecursively()
            contentCache.remove(id)
            places.remove(id)
        }
        _documents.value = _documents.value.filterNot { it.id in set }
        saveSoon()
    }

    // MARK: reading

    /** The document's text; read from disk off the main thread the first time. */
    suspend fun content(id: String): DocumentContent? {
        contentCache[id]?.let { return it }
        val loaded = withContext(Dispatchers.IO) {
            runCatching { AppJson.decodeFromString(DocumentContent.serializer(), contentFile(id).readText()) }.getOrNull()
        }
        if (loaded != null) contentCache[id] = loaded
        return loaded
    }

    fun cachedContent(id: String): DocumentContent? = contentCache[id]

    // MARK: editing

    fun update(id: String, save: Boolean = true, change: (DocumentRecord) -> DocumentRecord) {
        val list = _documents.value
        val i = list.indexOfFirst { it.id == id }
        if (i < 0) return
        _documents.value = list.toMutableList().also { it[i] = change(it[i]) }
        if (save) saveSoon()
    }

    fun addFolder(name: String) {
        val n = name.trim()
        if (n.isEmpty() || n in _folders.value) return
        _folders.value = (_folders.value + n).sortedWith(collator)
        saveSoon()
    }

    fun removeFolder(name: String) {
        _folders.value = _folders.value - name
        _documents.value = _documents.value.map { if (it.folder == name) it.copy(folder = null) else it }
        saveSoon()
    }

    fun renameFolder(old: String, new: String) {
        val n = new.trim()
        if (n.isEmpty() || old !in _folders.value || n in _folders.value) return
        _folders.value = _folders.value.map { if (it == old) n else it }.sortedWith(collator)
        _documents.value = _documents.value.map { if (it.folder == old) it.copy(folder = n) else it }
        saveSoon()
    }

    // MARK: saving — coalesced; a save already waiting is kept, not restarted

    fun saveSoon() {
        if (saveJob != null) return
        saveJob = scope.launch {
            delay(2000)
            saveJob = null
            val file = LibraryFile(_documents.value, _folders.value)
            writer.execute { runCatching { atomicWrite(libraryFile, AppJson.encodeToString(LibraryFile.serializer(), file)) } }
        }
    }

    fun saveNow() {
        saveJob?.cancel(); saveJob = null
        writePlaces()
        val file = LibraryFile(_documents.value, _folders.value)
        val text = AppJson.encodeToString(LibraryFile.serializer(), file)
        writer.submit { runCatching { atomicWrite(libraryFile, text) } }.get()
    }

    companion object {
        val collator: Collator = Collator.getInstance(Locale("tr", "TR")).apply { strength = Collator.SECONDARY }

        fun atomicWrite(target: File, text: String) {
            target.parentFile?.mkdirs()
            val tmp = File(target.parentFile, ".${target.name}.tmp")
            tmp.writeText(text)
            if (!tmp.renameTo(target)) { target.delete(); tmp.renameTo(target) }
        }
    }
}
