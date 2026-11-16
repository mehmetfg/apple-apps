// The shared folder on disk (port of CloudFiles in Model/SyncEngine.swift). Android has no iCloud container, so the
// folder is one the user picked with the system folder picker (a Storage Access Framework tree): typically a folder a
// sync app mirrors from iCloud Drive › Voice Reader. Same layout and file formats as the iOS app:
//
//   Loader/                      drop files here (subfolder = library folder); the first device that sees a file
//                                imports it and moves it to Loader/Alındı/
//   Library/<id>/meta.json       the document (title, author, format, language, added)
//   Library/<id>/content.json    the readable text — written once, never changed
//   Library/<id>/cover.jpg
//   Library/<id>/parts/001.md…   pages appended later; every device appends them in order to the end of the text
//   State/<device>.json          where each document was left on that device, with the time; newest wins
//   Events/<device>.jsonl        highlights, notes, bookmarks, folders, labels, titles, deletions — append-only
//
// Every file has one writer (its device), so the sync app never has to resolve a conflict.
package com.fatihgocgun.wisepath.sync

import android.content.ContentResolver
import android.content.Context
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.DocumentContent
import com.fatihgocgun.wisepath.model.DocumentFormat
import com.fatihgocgun.wisepath.model.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction
import java.util.UUID

@Serializable
data class DocumentMeta(
    val id: String,
    val title: String,
    val author: String? = null,
    val format: DocumentFormat = DocumentFormat.TXT,
    val sourceName: String = "",
    val language: String? = null,
    val addedAt: Instant,
    val folder: String? = null,
)

/** `length` and `title` are for readers outside the app (the Mac hub, Claude): percent = position / length. */
@Serializable
data class StateEntry(
    val position: Int,
    val opened: Instant? = null,
    val at: Instant,
    val length: Int? = null,
    val title: String? = null,
)

/**
 * Swift encodes `[UUID: Entry]` as an array of alternating keys and values (only String and Int keys make a JSON
 * object), so State files read `{"docs": ["<UUID>", {…}, "<UUID>", {…}]}`. Read both shapes, write the Swift one.
 */
object DeviceStateCodec {
    fun encode(docs: Map<String, StateEntry>): String {
        val arr = ArrayList<JsonElement>()
        for ((id, e) in docs) {
            arr += JsonPrimitive(id)
            arr += AppJson.encodeToJsonElement(StateEntry.serializer(), e)
        }
        return JsonObject(mapOf("docs" to JsonArray(arr))).toString()
    }

    fun decode(text: String): Map<String, StateEntry> {
        val root = runCatching { AppJson.parseToJsonElement(text) as? JsonObject }.getOrNull() ?: return emptyMap()
        val out = HashMap<String, StateEntry>()
        when (val docs = root["docs"]) {
            is JsonArray -> {
                var i = 0
                while (i + 1 < docs.size) {
                    val id = runCatching { docs[i].jsonPrimitive.content }.getOrNull()
                    val e = runCatching { AppJson.decodeFromJsonElement(StateEntry.serializer(), docs[i + 1]) }.getOrNull()
                    if (id != null && e != null) out[id.uppercase()] = e
                    i += 2
                }
            }
            is JsonObject -> docs.forEach { (k, v) ->
                runCatching { AppJson.decodeFromJsonElement(StateEntry.serializer(), v) }.getOrNull()?.let { out[k.uppercase()] = it }
            }
            else -> {}
        }
        return out
    }
}

/** One entry of a picked folder tree (Storage Access Framework). */
data class Node(val docId: String, val name: String, val isDir: Boolean, val size: Long)

/**
 * A folder tree the user granted, read and written through DocumentsContract (one query per listing, which is far
 * faster than DocumentFile's per-name lookups on large folders).
 */
class Tree(private val context: Context, val treeUri: Uri) {
    private val cr: ContentResolver get() = context.contentResolver
    val root: Node = Node(DocumentsContract.getTreeDocumentId(treeUri), "", true, 0)

    val usable: Boolean get() = runCatching { DocumentFile.fromTreeUri(context, treeUri)?.let { it.exists() && it.canWrite() } }.getOrNull() == true
    val displayName: String get() = runCatching { DocumentFile.fromTreeUri(context, treeUri)?.name }.getOrNull() ?: treeUri.lastPathSegment ?: "?"

    fun uri(n: Node): Uri = DocumentsContract.buildDocumentUriUsingTree(treeUri, n.docId)

    fun list(dir: Node): List<Node> = runCatching {
        val out = ArrayList<Node>()
        cr.query(DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, dir.docId), arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID, DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE, DocumentsContract.Document.COLUMN_SIZE,
        ), null, null, null)?.use { c ->
            while (c.moveToNext()) {
                val name = c.getString(1) ?: continue
                if (name.startsWith(".") && !name.startsWith(".claimed-")) continue          // hidden, partial downloads
                out += Node(c.getString(0), name, c.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR, if (c.isNull(3)) 0 else c.getLong(3))
            }
        }
        out
    }.getOrDefault(emptyList())

    fun child(dir: Node, name: String): Node? = list(dir).firstOrNull { it.name == name }

    fun dir(parent: Node, name: String, create: Boolean = true): Node? {
        child(parent, name)?.let { return if (it.isDir) it else null }
        if (!create) return null
        val u = runCatching { DocumentsContract.createDocument(cr, uri(parent), DocumentsContract.Document.MIME_TYPE_DIR, name) }.getOrNull() ?: return null
        return Node(DocumentsContract.getDocumentId(u), name, true, 0)
    }

    /** A path of folders under the root ("Library/<id>/parts"). */
    fun path(path: String, create: Boolean = true): Node? {
        var n = root
        for (p in path.split('/').filter { it.isNotEmpty() }) n = dir(n, p, create) ?: return null
        return n
    }

    fun read(n: Node): ByteArray? = runCatching { cr.openInputStream(uri(n))?.use { it.readBytes() } }.getOrNull()
    fun read(dir: Node, name: String): ByteArray? = child(dir, name)?.takeIf { !it.isDir }?.let { read(it) }

    /** Writes a whole file, replacing what was there. False when the provider refused. */
    fun write(dir: Node, name: String, data: ByteArray, existing: Node? = child(dir, name)): Boolean = runCatching {
        val target = existing?.let { uri(it) }
            ?: DocumentsContract.createDocument(cr, uri(dir), "application/octet-stream", name) ?: return false
        val out = runCatching { cr.openOutputStream(target, "wt") }.getOrNull() ?: cr.openOutputStream(target, "w")
        out?.use { it.write(data) } ?: return false
        true
    }.getOrDefault(false)

    fun delete(n: Node): Boolean = runCatching { DocumentsContract.deleteDocument(cr, uri(n)) }.getOrDefault(false)

    fun rename(n: Node, name: String): Node? = runCatching {
        val u = DocumentsContract.renameDocument(cr, uri(n), name) ?: return null
        Node(DocumentsContract.getDocumentId(u), name, n.isDir, n.size)
    }.getOrNull()

    /** Moves a file to another folder: the provider's own move, else a copy and a delete. */
    fun move(n: Node, from: Node, to: Node): Node? {
        runCatching { DocumentsContract.moveDocument(cr, uri(n), uri(from), uri(to)) }.getOrNull()?.let {
            return Node(DocumentsContract.getDocumentId(it), n.name, n.isDir, n.size)
        }
        val data = read(n) ?: return null
        if (child(to, n.name) != null) return null
        if (!write(to, n.name, data, null)) return null
        delete(n)
        return child(to, n.name)
    }

    fun deleteRecursively(n: Node) {
        if (!delete(n) && n.isDir) { list(n).forEach { deleteRecursively(it) }; delete(n) }
    }
}

/** Everything sync reads and writes in the shared folder; called from one background thread. */
class SyncFiles(val tree: Tree, val device: String) {
    init { for (d in listOf("Loader", "Loader/Alındı", "Library", "State", "Events")) tree.path(d) }

    // MARK: library

    private fun library() = tree.path("Library")

    fun libraryIDs(): List<String> = library()?.let { tree.list(it) }.orEmpty()
        .filter { it.isDir && runCatching { UUID.fromString(it.name) }.isSuccess }.map { it.name.uppercase() }

    private fun docDir(id: String, create: Boolean = false): Node? = library()?.let { tree.dir(it, id, create) }

    fun meta(id: String): DocumentMeta? = docDir(id)?.let { tree.read(it, "meta.json") }
        ?.let { runCatching { AppJson.decodeFromString(DocumentMeta.serializer(), String(it)) }.getOrNull() }

    fun content(id: String): DocumentContent? = docDir(id)?.let { tree.read(it, "content.json") }
        ?.let { runCatching { AppJson.decodeFromString(DocumentContent.serializer(), String(it)) }.getOrNull() }

    fun cover(id: String): ByteArray? = docDir(id)?.let { tree.read(it, "cover.jpg") }

    fun publish(meta: DocumentMeta, content: ByteArray, cover: ByteArray?): Boolean {
        val dir = docDir(meta.id, create = true) ?: return false
        val ok = tree.write(dir, "content.json", content) && cover.let { it == null || tree.write(dir, "cover.jpg", it) }
        // meta.json last: a device that sees it finds the text already there
        return ok && tree.write(dir, "meta.json", AppJson.encodeToString(DocumentMeta.serializer(), meta).toByteArray())
    }

    fun removeDocument(id: String) { docDir(id)?.let { tree.deleteRecursively(it) } }

    /** Appended pages after the first `known`, in name order, as text. */
    fun parts(id: String, known: Int): List<String> {
        val dir = docDir(id)?.let { tree.dir(it, "parts", create = false) } ?: return emptyList()
        val all = tree.list(dir).filter { !it.isDir && (it.name.endsWith(".md") || it.name.endsWith(".txt")) }.sortedBy { it.name }
        if (all.size <= known) return emptyList()
        val out = ArrayList<String>()
        for (n in all.drop(known)) out += decode(tree.read(n) ?: break)
        return out
    }

    // MARK: state

    fun writeState(docs: Map<String, StateEntry>): Boolean =
        tree.path("State")?.let { tree.write(it, "$device.json", DeviceStateCodec.encode(docs).toByteArray()) } ?: false

    fun otherStates(): List<Map<String, StateEntry>> {
        val dir = tree.path("State") ?: return emptyList()
        return tree.list(dir).filter { !it.isDir && it.name.endsWith(".json") && it.name != "$device.json" }
            .mapNotNull { n -> tree.read(n)?.let { DeviceStateCodec.decode(String(it)) } }
    }

    // MARK: events

    fun append(events: List<SyncEvent>): Boolean {
        if (events.isEmpty()) return true
        val dir = tree.path("Events") ?: return false
        val existing = tree.child(dir, "$device.jsonl")
        val old = existing?.let { tree.read(it) }
        // the log exists but cannot be read now: writing would replace the whole history with this batch, and the other
        // devices, which count its lines, would then ignore every later event. Kept for the next pass instead.
        if (existing != null && existing.size > 0 && (old == null || old.isEmpty())) return false
        val sb = StringBuilder(old?.let { String(it) } ?: "")
        if (sb.isNotEmpty() && sb.last() != '\n') sb.append('\n')
        for (e in events) sb.append(AppJson.encodeToString(SyncEvent.serializer(), e)).append('\n')
        return tree.write(dir, "$device.jsonl", sb.toString().toByteArray(), existing)
    }

    /** New events from other devices since the line counts in `seen`; returns them and the new counts. */
    fun otherEvents(seen: Map<String, Int>): Pair<List<SyncEvent>, Map<String, Int>> {
        val counts = HashMap(seen)
        val out = ArrayList<SyncEvent>()
        val dir = tree.path("Events") ?: return out to counts
        for (n in tree.list(dir)) {
            if (n.isDir || !n.name.endsWith(".jsonl") || n.name == "$device.jsonl") continue
            val data = tree.read(n) ?: continue
            val lines = String(data).split('\n').filter { it.isNotEmpty() }
            val from = counts[n.name] ?: 0
            if (lines.size <= from) continue
            for (l in lines.drop(from)) runCatching { AppJson.decodeFromString(SyncEvent.serializer(), l) }.getOrNull()?.let { out += it }
            counts[n.name] = lines.size
        }
        return out to counts
    }

    // MARK: loader

    data class Claimed(val node: Node, val name: String, val folder: String?)

    private val claimName get() = ".claimed-$device"

    /** Files waiting in Loader/ (and Loader/<folder>/), claimed for this device by moving them aside. */
    fun claimLoader(): List<Claimed> {
        val loader = tree.path("Loader") ?: return emptyList()
        val claim = tree.dir(loader, claimName) ?: return emptyList()
        val found = ArrayList<Claimed>()
        fun take(n: Node, from: Node, folder: String?) {
            val target = (folder?.let { "${it}__" } ?: "") + n.name
            val moved = tree.move(n, from, claim) ?: return              // another device may win
            val renamed = if (moved.name != target) tree.rename(moved, target) ?: moved else moved
            found += Claimed(renamed, n.name, folder)
        }
        for (n in tree.list(loader)) {
            if (n.name == "Alındı" || n.name.startsWith(".")) continue
            if (n.isDir) tree.list(n).filter { !it.isDir }.forEach { take(it, n, n.name) }
            else take(n, loader, null)
        }
        // files claimed earlier but not finished (app closed mid-import)
        for (n in tree.list(claim)) if (!n.isDir && found.none { it.node.docId == n.docId }) {
            val parts = n.name.split("__", limit = 2)
            found += if (parts.size > 1) Claimed(n, parts[1], parts[0]) else Claimed(n, n.name, null)
        }
        return found
    }

    fun finishLoader(c: Claimed) {
        val loader = tree.path("Loader") ?: return
        val claim = tree.dir(loader, claimName) ?: return
        val done = tree.dir(loader, "Alındı") ?: return
        var name = c.name
        if (tree.child(done, name) != null) name = UUID.randomUUID().toString().take(6).uppercase() + "-" + name
        val n = if (c.node.name != name) tree.rename(c.node, name) ?: c.node else c.node
        tree.move(n, claim, done)
    }

    companion object {
        /** Bytes → text: UTF-8 (with or without BOM), UTF-16 with BOM, else Turkish Windows (1254). */
        fun decode(data: ByteArray): String {
            if (data.size >= 3 && data[0] == 0xEF.toByte() && data[1] == 0xBB.toByte() && data[2] == 0xBF.toByte()) return String(data, 3, data.size - 3)
            if (data.size >= 2 && ((data[0] == 0xFF.toByte() && data[1] == 0xFE.toByte()) || (data[0] == 0xFE.toByte() && data[1] == 0xFF.toByte()))) return String(data, Charsets.UTF_16)
            return runCatching {
                Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(data)).toString()
            }.getOrElse { runCatching { String(data, Charset.forName("windows-1254")) }.getOrDefault(String(data, Charsets.ISO_8859_1)) }
        }
    }
}
