// A copy of where you are and what you marked, written into the PDM vault (Obsidian's folder), so the Mac, the PDM
// hub and Claude see it (port of Model/VaultMirror.swift). Written, never read: the shared sync folder stays the source.
//
//   <vault>/_araçlar/voice-reader/durum/
//     State/<device>.json        where each document was left (same shape as the sync State file)
//     Events/<device>.jsonl      highlights, notes, bookmarks… (same lines as the sync Events file)
//     Library/<id>.json          title, author, folder, length of each document
//     Texts/<id>.json            the readable text (content.json); written once per document
//     Notes/<device>.jsonl       written and voice notes (NoteStore's log, copied whole)
//     NoteAudio/<id>.m4a         the voice notes' recordings
//     Listening/<device>.json    the listening log
//
// The vault folder is picked once with the system folder picker; Android keeps the permission.
package com.fatihgocgun.wisepath.sync

import android.content.Context
import android.content.SharedPreferences
import android.net.Uri
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.DocumentRecord
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import java.io.File
import java.security.MessageDigest

class VaultMirror(private val context: Context, private val prefs: SharedPreferences) {
    @Serializable
    data class Meta(val author: String? = null, val folder: String? = null, val id: String, val language: String? = null,
                    val length: Int, val title: String)

    private var tree: Tree? = null
    private var base: Node? = null

    var uri: String
        get() = prefs.getString("vault.folder", "") ?: ""
        private set(v) { prefs.edit().putString("vault.folder", v).apply() }

    var status: String
        get() = prefs.getString("vault.status", "seçilmedi") ?: "seçilmedi"
        private set(v) { prefs.edit().putString("vault.status", v).apply() }

    /** The picked folder: the vault root, or a folder that holds it ("Personel Data Management"). Returns an error text. */
    fun choose(picked: Uri): String? {
        val t = Tree(context, picked)
        val names = t.list(t.root).map { it.name }.toSet()
        fun isRoot(n: Set<String>) = n.any { it in setOf("_bus", "_araçlar", "CLAUDE.md", "00 - Philosophy") }
        val ok = isRoot(names) || t.child(t.root, "Personel Data Management")?.let { isRoot(t.list(it).map { c -> c.name }.toSet()) } == true
        if (!ok) {
            val seen = names.sorted().take(6).joinToString(", ")
            val msg = "“${t.displayName}” vault'un kökü değil (içinde: ${seen.ifEmpty { "boş ya da okunamadı" }}). Obsidian › Personel Data Management klasörünü seç."
            status = msg
            return msg
        }
        uri = picked.toString()
        prefs.edit().remove("vault.seeded").remove("vault.written").apply()
        status = "bağlı: ${t.displayName}"
        tree = null; base = null
        return null
    }

    fun forget() {
        uri = ""
        tree = null; base = null
        status = "seçilmedi"
    }

    val connected get() = uri.isNotEmpty()

    /** durum/ inside the vault, created when missing. */
    private fun connect(): Pair<Tree, Node>? {
        val t0 = tree; val b0 = base
        if (t0 != null && b0 != null) return t0 to b0
        if (uri.isEmpty()) return null
        val t = Tree(context, Uri.parse(uri))
        val root = t.child(t.root, "Personel Data Management")?.takeIf { it.isDir && t.child(t.root, "_araçlar") == null } ?: t.root
        var n = root
        for (p in RELATIVE.split('/')) n = t.dir(n, p) ?: run { status = "yazılamadı: $RELATIVE"; return null }
        tree = t; base = n
        return t to n
    }

    private fun dir(sub: String): Pair<Tree, Node>? = connect()?.let { (t, b) -> t.dir(b, sub)?.let { t to it } }

    private fun write(t: Tree, d: Node, name: String, data: ByteArray, existing: Node? = t.child(d, name)) {
        status = if (t.write(d, name, data, existing)) "yazıldı ${Format.date(System.currentTimeMillis(), "HH:mm")}" else "yazılamadı $name"
    }

    // MARK: writing (all called on the sync engine's background thread)

    fun writeState(json: String, device: String) { dir("State")?.let { (t, d) -> write(t, d, "$device.json", json.toByteArray()) } }

    fun append(events: List<SyncEvent>, device: String) {
        if (events.isEmpty()) return
        val (t, d) = dir("Events") ?: return
        val existing = t.child(d, "$device.jsonl")
        val old = existing?.let { t.read(it) }
        if (existing != null && existing.size > 0 && (old == null || old.isEmpty())) return     // never replace the log
        val sb = StringBuilder(old?.let { String(it) } ?: "")
        if (sb.isNotEmpty() && sb.last() != '\n') sb.append('\n')
        for (e in events) sb.append(AppJson.encodeToString(SyncEvent.serializer(), e)).append('\n')
        write(t, d, "$device.jsonl", sb.toString().toByteArray(), existing)
    }

    private val pretty = Json(AppJson) { prettyPrint = true }

    /** Library/<id>.json for every document; a file is written only when its text changed since the last write. */
    fun writeMeta(docs: List<Meta>) {
        val (t, d) = dir("Library") ?: return
        val written = HashMap(readHashes())
        var changed = false
        val existing by lazy { t.list(d).associateBy { it.name } }
        for (m in docs) {
            val text = pretty.encodeToString(Meta.serializer(), m)
            val h = hash(text)
            if (written[m.id] == h) continue
            write(t, d, "${m.id}.json", text.toByteArray(), existing["${m.id}.json"])
            written[m.id] = h; changed = true
        }
        if (changed) prefs.edit().putString("vault.written", AppJson.encodeToString(JsonObject.serializer(),
            JsonObject(written.mapValues { kotlinx.serialization.json.JsonPrimitive(it.value) }))).apply()
    }

    private fun readHashes(): Map<String, String> = runCatching {
        AppJson.parseToJsonElement(prefs.getString("vault.written", "{}")!!).let { it as JsonObject }
            .mapValues { (it.value as kotlinx.serialization.json.JsonPrimitive).content }
    }.getOrDefault(emptyMap())

    private fun hash(s: String) = MessageDigest.getInstance("SHA-1").digest(s.toByteArray()).joinToString("") { "%02x".format(it) }

    /** Documents whose text is not in the vault copy yet. */
    fun missingTexts(ids: List<String>): List<String> {
        val (t, d) = dir("Texts") ?: return emptyList()
        val have = t.list(d).map { it.name }.toSet()
        return ids.filter { "$it.json" !in have }
    }

    fun writeText(data: ByteArray, id: String) { dir("Texts")?.let { (t, d) -> write(t, d, "$id.json", data, null) } }

    fun writeListening(data: ByteArray, device: String) { dir("Listening")?.let { (t, d) -> write(t, d, "$device.json", data) } }

    fun mirrorNotes(log: File, audioDir: File, device: String) {
        val (t, d) = dir("Notes") ?: return
        val data = runCatching { log.readBytes() }.getOrNull()
        if (data != null) {
            val existing = t.child(d, "$device.jsonl")
            if (existing == null || existing.size != data.size.toLong() || !t.read(existing).contentEquals(data)) write(t, d, "$device.jsonl", data, existing)
        }
        val (_, a) = dir("NoteAudio") ?: return
        val have = t.list(a).map { it.name }.toSet()
        audioDir.listFiles { f -> f.extension == "m4a" }?.forEach { f ->
            if (f.name !in have) runCatching { f.readBytes() }.getOrNull()?.let { write(t, a, f.name, it, null) }
        }
    }

    /** First time with this vault: every highlight and bookmark already in the library goes in as events. */
    fun seedIfNeeded(docs: List<DocumentRecord>, device: String) {
        if (connect() == null || prefs.getBoolean("vault.seeded", false)) return
        val events = ArrayList<SyncEvent>()
        for (d in docs) {
            d.highlights.forEach { events += SyncEvent(at = it.createdAt, kind = SyncKind.highlightAdd, doc = d.id, highlight = it) }
            d.bookmarks.forEach { events += SyncEvent(at = it.createdAt, kind = SyncKind.bookmarkAdd, doc = d.id, bookmark = it) }
        }
        append(events, device)
        prefs.edit().putBoolean("vault.seeded", true).apply()
    }

    companion object { const val RELATIVE = "_araçlar/voice-reader/durum" }
}
