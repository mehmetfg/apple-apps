// Notes (port of Model/NoteStore.swift): written or spoken thoughts tied to a place in a document (a sentence, a
// highlight). One append-only log (a changed or deleted note is a new line; the newest line of an id wins) and one
// audio file per voice note.
//
//   files/WisePath/notes/<device>.jsonl     the log (same lines as the iOS file)
//   files/WisePath/notes/audio/<id>.m4a     the recordings
package com.fatihgocgun.wisepath.notes

import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.model.Instant
import com.fatihgocgun.wisepath.model.now
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.Serializable
import java.io.File
import java.util.UUID

@Serializable
data class ReaderNote(
    val id: String,
    val doc: String,
    val bookTitle: String,
    val text: String,
    val transcript: String? = null,         // where `text` came from: "device" (speech recognition), null = typed
    val audio: String? = null,              // file name in notes/audio
    val seconds: Double? = null,
    val location: Int,
    val length: Int,
    val quote: String,
    val chapterTitle: String? = null,
    val date: Instant,
    val edited: Instant? = null,
    val deleted: Boolean? = null,
) {
    val stamp: Long get() = edited ?: date
    val hasVoice: Boolean get() = audio != null
}

class NoteStore(root: File, device: String) {
    private val dir = File(root, "notes").also { it.mkdirs() }
    val audioDir = File(dir, "audio").also { it.mkdirs() }
    private val log = File(dir, "$device.jsonl")

    private val _notes = MutableStateFlow<List<ReaderNote>>(emptyList())
    /** Live notes, newest first. */
    val notes: StateFlow<List<ReaderNote>> = _notes

    /** Called after every write (the sync / vault copy registers here). */
    var onWrite: ((File, File) -> Unit)? = null

    init {
        val latest = HashMap<String, ReaderNote>()
        runCatching { log.readLines() }.getOrDefault(emptyList()).forEach { l ->
            val n = runCatching { AppJson.decodeFromString(ReaderNote.serializer(), l) }.getOrNull() ?: return@forEach
            val old = latest[n.id]
            if (old == null || old.stamp <= n.stamp) latest[n.id] = n
        }
        _notes.value = latest.values.filter { it.deleted != true }.sortedByDescending { it.stamp }
    }

    fun notes(of: String): List<ReaderNote> = _notes.value.filter { it.doc == of }.sortedBy { it.location }
    fun note(id: String): ReaderNote? = _notes.value.firstOrNull { it.id == id }
    fun audioFile(n: ReaderNote): File? = n.audio?.let { File(audioDir, it) }

    private fun write(n: ReaderNote) {
        runCatching { log.appendText(AppJson.encodeToString(ReaderNote.serializer(), n) + "\n") }
        val rest = _notes.value.filterNot { it.id == n.id }
        _notes.value = if (n.deleted == true) rest else listOf(n) + rest
        onWrite?.invoke(log, audioDir)
    }

    /** A new note. `recording` is the recorder's file; it moves into the notes' audio folder. */
    fun add(
        doc: String, title: String, location: Int, length: Int, quote: String, chapter: String?, text: String,
        transcript: String?, recording: File?, seconds: Double?,
    ): ReaderNote {
        val id = "vr-" + UUID.randomUUID().toString().take(12).lowercase()
        var audio: String? = null
        if (recording != null) {
            val name = "$id.${recording.extension.ifEmpty { "m4a" }}"
            val dst = File(audioDir, name)
            dst.delete()
            if (recording.renameTo(dst) || runCatching { recording.copyTo(dst); recording.delete() }.isSuccess) audio = name
        }
        val n = ReaderNote(
            id = id, doc = doc, bookTitle = title, text = text.trim(), transcript = transcript, audio = audio,
            seconds = seconds, location = location, length = length, quote = quote, chapterTitle = chapter, date = now(),
        )
        write(n)
        return n
    }

    fun setText(id: String, text: String, transcript: String?) {
        val n = note(id) ?: return
        write(n.copy(text = text.trim(), transcript = transcript, edited = now()))
    }

    fun delete(id: String) {
        val n = note(id) ?: return
        write(n.copy(deleted = true, edited = now()))
    }
}
