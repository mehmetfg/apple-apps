// Müzik modu (port of Model/MusicMode.swift): the book in silence while music plays. Wise Path does not speak; the
// sentences of the part already read come and go on the screen with the music's beat: the reader's own marks first,
// then Teoria's key sentences and the book's main idea (when an insight file is known). The beat is heard through the
// microphone (music from the speaker) or given by tapping (music in the headphones, which the microphone cannot
// hear); without either it keeps a steady 96 a minute.
package com.fatihgocgun.wisepath.music

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioDeviceInfo
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.fatihgocgun.wisepath.TextFold
import com.fatihgocgun.wisepath.model.DocumentRecord
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.serialization.Serializable
import kotlin.math.sqrt

data class MusicLine(val id: Int, val text: String, val kind: Kind, val why: String? = null, val chapter: String? = null) {
    enum class Kind { mark, key, idea }
    val label: String get() = when (kind) { Kind.mark -> "işaretin"; Kind.key -> "can alıcı"; Kind.idea -> "ana fikir" }
}

/** Teoria's insight file, only the parts the music mode shows. */
@Serializable
data class TeoriaInsight(val core: Core? = null, val keys: List<Key>? = null) {
    @Serializable data class Core(val theme: String? = null, val claim: String? = null, val idea: String? = null)
    @Serializable data class Key(val quote: String, val why: String? = null, val weight: Int? = null)
}

object MusicPool {
    /** A sync module may hand the insight of a book by its title (the vault's Teoria files); none by default. */
    var insightFor: ((String) -> TeoriaInsight?)? = null

    /**
     * The lines for a book: every mark (in book order), the key sentences found in the part already read (heaviest
     * first), and the main idea. Marks come every other line so the reader's own choices lead.
     */
    fun build(doc: DocumentRecord, text: String, insight: TeoriaInsight?, chapterAt: (Int) -> String?): List<MusicLine> {
        var n = 0
        val marks = doc.highlights.sortedBy { it.location }
            .map { MusicLine(n++, it.text.trim(), MusicLine.Kind.mark, chapter = chapterAt(it.location)) }
            .filter { it.text.length >= 12 }
        val readUpTo = if (doc.isFinished) text.length else doc.position
        val keys = ArrayList<MusicLine>()
        val folded by lazy { TextFold.fold(text) }
        for (k in (insight?.keys ?: emptyList()).sortedByDescending { it.weight ?: 0 }) {
            // only sentences already heard: the quote is looked up in the text by its first words
            val at = folded.indexOf(TextFold.fold(k.quote.take(40)))
            if (at < 0 || at > readUpTo) continue
            keys.add(MusicLine(n++, k.quote, MusicLine.Kind.key, k.why, chapterAt(at)))
        }
        val ideas = ArrayList<MusicLine>()
        val c = insight?.core
        if ((doc.progress > 0.15 || doc.isFinished) && c != null) {
            listOfNotNull(c.claim, c.idea).filter { it.length > 20 }.forEach { ideas.add(MusicLine(n++, it, MusicLine.Kind.idea)) }
        }
        val out = ArrayList<MusicLine>()
        val m = ArrayDeque(marks); val k = ArrayDeque(keys + ideas)
        while (m.isNotEmpty() || k.isNotEmpty()) {
            m.removeFirstOrNull()?.let { out.add(it) }
            k.removeFirstOrNull()?.let { out.add(it) }
        }
        return out
    }
}

/** The beat: from the microphone when it hears a steady pulse, else from the tapped (or default) tempo. */
class BeatTracker(private val context: Context, private val scope: CoroutineScope) {
    enum class Source { clock, microphone }
    var beat by mutableIntStateOf(0); private set           // goes up by one on every beat
    var lastBeatAt by mutableLongStateOf(0L); private set
    var bpm by mutableDoubleStateOf(96.0); private set
    var level by mutableDoubleStateOf(0.0); private set     // loudness heard, 0…1 (for the glow)
    var source by mutableStateOf(Source.clock); private set
    var listening by mutableStateOf(false); private set     // the microphone is on
    var paused = false

    private var clock: Job? = null
    private val onsets = ArrayList<Long>()
    private val taps = ArrayList<Long>()
    private var lastMicBeat = 0L
    @Volatile private var record: AudioRecord? = null
    private var thread: Thread? = null
    private val main = Handler(Looper.getMainLooper())

    /** The microphone only when the music comes out of the phone's speaker: with headphones it hears nothing. */
    fun start(microphone: Boolean) {
        startClock()
        if (microphone && speakerOut() && micAllowed(context)) startMicrophone()
    }

    fun stop() {
        clock?.cancel(); clock = null
        stopMicrophone()
    }

    private fun speakerOut(): Boolean {
        val am = context.getSystemService(AudioManager::class.java) ?: return true
        val heads = mutableSetOf(AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET,
            AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLUETOOTH_SCO, AudioDeviceInfo.TYPE_USB_HEADSET)
        if (Build.VERSION.SDK_INT >= 31) heads.add(AudioDeviceInfo.TYPE_BLE_HEADSET)
        return am.getDevices(AudioManager.GET_DEVICES_OUTPUTS).none { it.type in heads }
    }

    /** Four taps or more in time set the tempo (the average of the last intervals). */
    fun tap() {
        val now = System.currentTimeMillis()
        taps.add(now)
        taps.removeAll { now - it > 3000 }
        if (taps.size < 3) return
        val gaps = taps.zipWithNext { a, b -> (b - a) / 1000.0 }
        val mean = gaps.average()
        if (mean <= 0.25 || mean >= 1.6) return
        bpm = Math.round(60 / mean).toDouble()
        source = Source.clock
        startClock()
    }

    private fun startClock() {
        clock?.cancel()
        clock = scope.launch {
            while (isActive) {
                delay((60_000 / bpm).toLong())
                // the microphone leads while it hears a pulse; the clock fills in when it has been quiet for 3 s
                if (source == Source.microphone && System.currentTimeMillis() - lastMicBeat < 3000) continue
                source = Source.clock
                tick()
            }
        }
    }

    private fun tick() {
        if (paused) return
        beat++
        lastBeatAt = System.currentTimeMillis()
    }

    // MARK: microphone

    @SuppressLint("MissingPermission")
    private fun startMicrophone() {
        if (record != null) return
        val rate = 44_100
        val min = AudioRecord.getMinBufferSize(rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
        if (min <= 0) return
        val r = runCatching {
            AudioRecord(MediaRecorder.AudioSource.MIC, rate, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT, maxOf(min, 4096))
        }.getOrNull() ?: return
        if (r.state != AudioRecord.STATE_INITIALIZED) { r.release(); return }
        runCatching { r.startRecording() }.onFailure { r.release(); return }
        record = r
        listening = true
        val detector = OnsetDetector()
        thread = Thread {
            val buf = ShortArray(1024)
            while (record === r) {
                val n = r.read(buf, 0, buf.size)
                if (n <= 0) continue
                var sum = 0.0
                for (i in 0 until n) { val v = buf[i] / 32768.0; sum += v * v }
                val rms = sqrt(sum / n).toFloat()
                val hit = detector.feed(rms)
                main.post { heard(rms, hit) }
            }
        }.apply { name = "beat-mic"; isDaemon = true; start() }
    }

    private fun stopMicrophone() {
        val r = record ?: return
        record = null
        listening = false
        runCatching { r.stop() }
        r.release()
        thread = null
    }

    private fun heard(rms: Float, onset: Boolean) {
        level = level * 0.7 + minOf(1.0, rms * 8.0) * 0.3
        if (!onset) return
        val now = System.currentTimeMillis()
        onsets.add(now)
        onsets.removeAll { now - it > 5000 }
        // a pulse is steady when the last gaps are close to one another
        val gaps = onsets.zipWithNext { a, b -> (b - a) / 1000.0 }.takeLast(6)
        if (gaps.size < 4) return
        val mean = gaps.average()
        val spread = sqrt(gaps.sumOf { (it - mean) * (it - mean) } / gaps.size) / mean
        if (spread >= 0.3 || mean <= 0.25 || mean >= 1.6) return
        bpm = Math.round(60 / mean).toDouble()
        source = Source.microphone
        lastMicBeat = now
        tick()
    }

    companion object {
        fun micAllowed(context: Context) =
            ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
    }
}

/** Energy onsets: a block clearly louder than the last second's average, at most one every 0.25 s. */
private class OnsetDetector {
    private val history = ArrayDeque<Float>()
    private var since = 99
    fun feed(rms: Float): Boolean {
        history.addLast(rms)
        if (history.size > 43) history.removeFirst()          // ≈ 1 s of 1024-frame blocks at 44.1 kHz
        since++
        val avg = history.sum() / history.size
        if (rms <= 0.01f || rms <= avg * 1.45f || since <= 10) return false
        since = 0
        return true
    }
}
