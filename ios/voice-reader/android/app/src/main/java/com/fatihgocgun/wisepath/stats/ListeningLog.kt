// The listening log (port of Model/ListeningLog.swift): what was heard each day, per document. Once a second, while a
// reading session or a wait exists, it looks at the player: playing → that document's listening seconds; paused in a
// reading session → paused seconds; in a music break → break seconds. Words heard come from the cursor's advance.
//
//   files/WisePath/listening/<device>.json   the log (same shape as the iOS file)
package com.fatihgocgun.wisepath.stats

import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.speech.SpeechPlayer
import com.fatihgocgun.wisepath.store.LibraryStore
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.jsonObject
import java.io.File
import java.time.LocalDate
import java.util.concurrent.Executors

@Serializable
data class ListeningDoc(
    var seconds: Double = 0.0,
    var words: Int = 0,
    /** Heard spans [from, to] in characters. */
    var ranges: MutableList<List<Int>> = mutableListOf(),
) {
    /** Adds a heard span, joining it to the last one when they touch. */
    fun heard(from: Int, to: Int) {
        val last = ranges.lastOrNull()
        if (last != null && last.size == 2 && from >= last[0] && from - last[1] <= 50) {
            ranges[ranges.size - 1] = listOf(last[0], maxOf(last[1], to))
        } else ranges.add(listOf(from, to))
    }
}

@Serializable
data class ListeningDay(
    var docs: MutableMap<String, ListeningDoc> = mutableMapOf(),
    var paused: Double = 0.0,
    var breaks: Double = 0.0,
    var finished: MutableList<String> = mutableListOf(),
) {
    val seconds: Double get() = docs.values.sumOf { it.seconds }
    val words: Int get() = docs.values.sumOf { it.words }
}

class ListeningLog(root: File, device: String) {
    private val file = File(root, "listening/$device.json").also { it.parentFile?.mkdirs() }
    private val days = HashMap<String, ListeningDay>()
    private val finishedEver = HashSet<String>()
    private val writer = Executors.newSingleThreadExecutor()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var dirty = false
    private var lastSave = 0L
    private var lastTick = 0L
    private var lastPlace: Triple<String, Int, Long>? = null
    private var timer: Job? = null
    private var published = 0L

    /** Moves at most every 15 s while listening (and at once on start, pause, stop): screens observe this. */
    private val _revision = MutableStateFlow(0)
    val revision: StateFlow<Int> = _revision

    /** Called after each save with the whole log (widgets, the evening reminder). */
    var onSave: ((Map<String, ListeningDay>) -> Unit)? = null

    init {
        val raw = runCatching { file.readText() }.getOrNull()
        if (raw != null) {
            val parsed = runCatching {
                AppJson.parseToJsonElement(raw).jsonObject.mapNotNull { (k, v) ->
                    runCatching { k to AppJson.decodeFromJsonElement<ListeningDay>(v) }.getOrNull()
                }.toMap()
            }.getOrNull()
            if (parsed == null && raw.isNotBlank()) {
                runCatching { file.copyTo(File(file.parentFile, "${file.nameWithoutExtension}.unread-${System.currentTimeMillis()}.json")) }
            }
            parsed?.let { days.putAll(it) }
            days.values.forEach { finishedEver.addAll(it.finished) }
        }
    }

    // MARK: following the player

    fun attach(player: SpeechPlayer, store: LibraryStore) {
        scope.launch {
            player.state.collect { s ->
                val live = s.isSpeaking || s.breakEnds != null
                if (live && timer == null) {
                    lastTick = System.currentTimeMillis()
                    timer = scope.launch {
                        while (isActive) { delay(1000); tick(player) }
                    }
                    publish()
                } else if (!live && timer != null) {
                    timer?.cancel(); timer = null
                    save(force = true)
                    publish()
                }
                if (s.isPaused) save(force = true)
            }
        }
    }

    private fun tick(p: SpeechPlayer) {
        val now = System.currentTimeMillis()
        val dt = (now - lastTick) / 1000.0
        lastTick = now
        if (dt <= 0 || dt >= 5) return
        val s = p.state.value
        val day = days.getOrPut(key(LocalDate.now())) { ListeningDay() }
        when {
            s.breakEnds != null -> day.breaks += dt
            s.isPlaying && s.documentID != null -> day.docs.getOrPut(s.documentID) { ListeningDoc() }.seconds += dt
            s.isSpeaking -> day.paused += dt
            else -> return
        }
        dirty = true
        if (now - published >= 15_000) publish()
        save(force = false)
    }

    /** The player reported a new place (every couple of seconds while reading, and on every jump). */
    fun position(id: String, offset: Int, length: Int, text: (Int, Int) -> String) {
        val now = System.currentTimeMillis()
        val last = lastPlace
        lastPlace = Triple(id, offset, now)
        if (length > 0 && offset.toDouble() / length >= 0.99 && id !in finishedEver) {
            finishedEver.add(id)
            days.getOrPut(key(LocalDate.now())) { ListeningDay() }.finished.add(id)
            dirty = true
            publish()
        }
        if (last == null || last.first != id) return
        val delta = offset - last.second
        // a step forward longer than the voice can have read since the last report is a skip, not listening
        val reach = ((now - last.third) / 1000.0 * 90).toInt() + 150
        if (delta <= 0 || delta > minOf(3000, reach)) return
        val words = text(last.second, offset).split(Regex("\\s+")).count { it.isNotEmpty() }
        if (words <= 0) return
        val doc = days.getOrPut(key(LocalDate.now())) { ListeningDay() }.docs.getOrPut(id) { ListeningDoc() }
        doc.words += words
        doc.heard(last.second, offset)
        dirty = true
        if (now - published >= 15_000) publish()
    }

    private fun publish() {
        published = System.currentTimeMillis()
        _revision.value++
    }

    fun save(force: Boolean) {
        val now = System.currentTimeMillis()
        if (!dirty || (!force && now - lastSave < 30_000)) return
        dirty = false
        lastSave = now
        val snapshot = snapshot()
        onSave?.invoke(snapshot)
        val text = AppJson.encodeToString(MapSerializer(String.serializer(), ListeningDay.serializer()), snapshot)
        writer.execute { runCatching { LibraryStore.atomicWrite(file, text) } }
    }

    /** A deep copy of the log (safe to hand to another thread). */
    fun snapshot(): Map<String, ListeningDay> = days.mapValues { (_, d) ->
        d.copy(docs = d.docs.mapValues { it.value.copy(ranges = it.value.ranges.toMutableList()) }.toMutableMap(),
            finished = d.finished.toMutableList())
    }

    // MARK: reading the log

    fun day(d: LocalDate): ListeningDay = days[key(d)] ?: ListeningDay()

    /** The first day with anything in the log. */
    val firstDay: LocalDate? get() = days.keys.minOrNull()?.let { runCatching { LocalDate.parse(it) }.getOrNull() }

    /** All days from `from` to `to` (inclusive), summed. */
    fun total(from: LocalDate, to: LocalDate): ListeningDay {
        val out = ListeningDay()
        var d = from
        while (!d.isAfter(to)) {
            days[key(d)]?.let { x ->
                for ((id, v) in x.docs) {
                    val o = out.docs.getOrPut(id) { ListeningDoc() }
                    o.seconds += v.seconds
                    o.words += v.words
                }
                out.paused += x.paused
                out.breaks += x.breaks
                out.finished.addAll(x.finished)
            }
            d = d.plusDays(1)
        }
        return out
    }

    companion object {
        const val WORDS_PER_PAGE = 225.0
        fun key(d: LocalDate): String = d.toString()       // yyyy-MM-dd
    }
}
