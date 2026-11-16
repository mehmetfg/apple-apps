// The cloud voices as a SpeechBackend. Each piece the player hands over is fetched (or found in the disk cache) on one
// worker thread, in order, while the pieces before it play; the audio files are played by MediaPlayer, the next one
// prepared while the current one plays and chained to it, so the reading has no gap. Speed and pitch are applied on
// the device (PlaybackParams keeps the voice's pitch at any speed). Word ranges come from the stored word timings
// (ElevenLabs' character times, Google's SSML marks, or words spread over the audio by their length).
//
// A piece that cannot be made (no network, no credits, the free quota reached) is read by the phone's own voice, as
// on iOS; the reason is kept in CloudVoices.problem.
package com.fatihgocgun.wisepath.cloud

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.PlaybackParams
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.speech.SpeakRequest
import com.fatihgocgun.wisepath.speech.SpeechBackend
import com.fatihgocgun.wisepath.speech.SpeechCallbacks
import com.fatihgocgun.wisepath.speech.TtsBackend
import com.fatihgocgun.wisepath.speech.VoiceCatalog
import java.util.concurrent.Executors

class CloudBackend(
    private val context: Context,
    private val voices: CloudVoices,
    private val callbacks: SpeechCallbacks,
    private val ttsEngine: () -> String?,
) : SpeechBackend {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()

    private class Item(val req: SpeakRequest, val gen: Int) {
        @Volatile var clip: Clip? = null
        @Volatile var failure: String? = null
        val fetched get() = clip != null || failure != null
    }

    // main thread only
    @Volatile private var generation = 0
    private val queue = ArrayDeque<Item>()
    private var current: Item? = null
    private var currentPlayer: MediaPlayer? = null
    private var currentByTts = false
    private var prepared: Pair<Item, MediaPlayer>? = null
    private var chained = false
    private var lastWord = -1

    override val ready get() = true
    override val reportsRanges get() = true

    override fun enqueue(request: SpeakRequest) {
        val item = Item(request, generation)
        onMain {
            queue.addLast(item)
            worker.execute { fetch(item) }
        }
    }

    private fun onMain(block: () -> Unit) { if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block) }

    private fun fetch(item: Item) {
        if (item.gen != generation) return                // stopped meanwhile: no credits for a piece nobody hears
        val v = item.req.voice ?: ""
        try {
            item.clip = when {
                v.startsWith("eleven:") -> voices.synthesizeEleven(v.removePrefix("eleven:"), item.req.text, item.req.language)
                v.startsWith("cloud:") -> {
                    val parts = v.split(":", limit = 3)
                    voices.synthesizeCloud(CloudProvider.of(parts.getOrElse(1) { "" }), parts.getOrElse(2) { "" }, item.req.text, item.req.language)
                }
                else -> throw CloudException("Bilinmeyen ses: $v")
            }
        } catch (e: Exception) {
            item.failure = e.message ?: e.javaClass.simpleName
        }
        main.post { if (item.gen == generation) pump() }
    }

    /** Starts the head of the queue when nothing plays; prepares the next file while one plays. */
    private fun pump() {
        if (current == null) {
            val head = queue.firstOrNull() ?: return
            if (!head.fetched) return
            queue.removeFirst()
            if (head.clip != null) play(head) else speakWithPhone(head)
        }
        prepareNext()
    }

    private fun newPlayer(item: Item): MediaPlayer? {
        val clip = item.clip ?: return null
        return runCatching {
            MediaPlayer().apply {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                setWakeMode(context, PowerManager.PARTIAL_WAKE_LOCK)
                setDataSource(clip.file.path)
                prepare()
                if (clip.startSeconds > 0) seekTo((clip.startSeconds * 1000).toInt())
                val v = item.req.volume.coerceIn(0f, 1f)
                setVolume(v, v)
            }
        }.getOrNull()
    }

    private fun plain(req: SpeakRequest) = req.rate in 0.99f..1.01f && req.pitch in 0.99f..1.01f

    private fun prepareNext() {
        val cur = currentPlayer ?: return
        if (prepared != null || currentByTts) return
        val next = queue.firstOrNull() ?: return
        if (next.clip == null) return
        val mp = newPlayer(next) ?: run { next.clip = null; next.failure = CloudErrors.undecodable; return }
        prepared = next to mp
        // the same speed and pitch: MediaPlayer chains them itself, without a gap
        val c = current
        if (c != null && plain(c.req) && plain(next.req)) {
            runCatching { cur.setNextMediaPlayer(mp); chained = true }
        }
    }

    private fun play(item: Item) {
        val p = prepared
        val mp = if (p != null && p.first === item) { prepared = null; p.second } else {
            p?.second?.release(); prepared = null
            newPlayer(item)
        }
        if (mp == null) { item.clip = null; item.failure = CloudErrors.undecodable; speakWithPhone(item); return }
        val wasChained = chained
        chained = false
        begin(item, mp)
        if (!wasChained) {
            runCatching {
                if (plain(item.req)) mp.start()
                else mp.playbackParams = PlaybackParams().setSpeed(item.req.rate.coerceIn(0.25f, 4f)).setPitch(item.req.pitch.coerceIn(0.5f, 2f))
                if (!mp.isPlaying) mp.start()
            }.onFailure { finish(item, it.message); return }
        }
    }

    private fun begin(item: Item, mp: MediaPlayer) {
        current = item
        currentPlayer = mp
        currentByTts = false
        lastWord = -1
        mp.setOnCompletionListener { onMain { if (current === item) finish(item, null) } }
        mp.setOnErrorListener { _, what, _ -> onMain { if (current === item) finish(item, "MediaPlayer $what") }; true }
        callbacks.onStart(item.req.utteranceId)
        voices.problem = null
        main.removeCallbacks(ticker)
        main.post(ticker)
    }

    /** A piece is over: the next one starts (already playing when chained). */
    private fun finish(item: Item, error: String?) {
        main.removeCallbacks(ticker)
        val old = currentPlayer
        current = null
        currentPlayer = null
        if (error != null) {
            prepared?.second?.release(); prepared = null; chained = false
            old?.release()
            callbacks.onError(item.req.utteranceId, error)
            pump()
            return
        }
        callbacks.onDone(item.req.utteranceId)
        val p = prepared
        if (chained && p != null && queue.firstOrNull() === p.first) {
            queue.removeFirst()
            prepared = null
            chained = false
            begin(p.first, p.second)
            old?.release()
            prepareNext()
            return
        }
        old?.release()
        pump()
    }

    /** The word being heard, from the playing position and the stored word times. */
    private val ticker = object : Runnable {
        override fun run() {
            val item = current ?: return
            val mp = currentPlayer ?: return
            val clip = item.clip ?: return
            val pos = runCatching { mp.currentPosition }.getOrDefault(0) / 1000.0
            val words = clip.words
            var i = lastWord.coerceAtLeast(0)
            if (i < words.size && words[i].seconds > pos) i = 0
            while (i + 1 < words.size && words[i + 1].seconds <= pos) i++
            if (words.isNotEmpty() && words[i].seconds <= pos + 0.05 && i != lastWord) {
                lastWord = i
                val w = words[i]
                val len = item.req.text.length
                callbacks.onRange(item.req.utteranceId, w.location.coerceIn(0, len), (w.location + w.length).coerceIn(0, len))
            }
            main.postDelayed(this, 40)
        }
    }

    // MARK: the phone's voice for a piece the cloud could not make

    private var tts: TtsBackend? = null
    private var ttsReady = false

    private val ttsCallbacks = object : SpeechCallbacks {
        override fun onStart(utteranceId: String) = callbacks.onStart(utteranceId)
        override fun onRange(utteranceId: String, start: Int, end: Int) = callbacks.onRange(utteranceId, start, end)
        override fun onDone(utteranceId: String) {
            callbacks.onDone(utteranceId)
            main.post { val c = current; if (c != null && currentByTts && c.req.utteranceId == utteranceId) { current = null; currentByTts = false; pump() } }
        }
        override fun onError(utteranceId: String, message: String?) {
            callbacks.onError(utteranceId, message)
            main.post { val c = current; if (c != null && currentByTts && c.req.utteranceId == utteranceId) { current = null; currentByTts = false; pump() } }
        }
    }

    private fun phoneVoice(): TtsBackend = tts ?: TtsBackend(context, ttsEngine(), ttsCallbacks) { ok ->
        main.post { ttsReady = ok; val c = current; if (c != null && currentByTts) { if (ok) speakNow(c) else ttsCallbacks.onError(c.req.utteranceId, c.failure) } }
    }.also { tts = it }

    private fun speakWithPhone(item: Item) {
        voices.problem = item.failure
        current = item
        currentByTts = true
        val t = phoneVoice()
        if (ttsReady || t.ready) { ttsReady = true; speakNow(item) }       // else the onReady above speaks it
    }

    private fun speakNow(item: Item) {
        tts?.enqueue(item.req.copy(voice = null))
    }

    // MARK: control

    override fun stop() {
        generation++
        onMain {
            main.removeCallbacks(ticker)
            currentPlayer?.let { runCatching { it.stop() }; it.release() }
            prepared?.second?.release()
            currentPlayer = null
            prepared = null
            chained = false
            current = null
            currentByTts = false
            queue.clear()
            tts?.stop()
        }
    }

    override fun shutdown() {
        stop()
        tts?.shutdown()
        tts = null
    }

    // MARK: the settings page's sample

    private var sample: MediaPlayer? = null

    fun playSample(clip: Clip) = onMain {
        sample?.release()
        sample = MediaPlayer().apply {
            runCatching {
                setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
                setDataSource(clip.file.path); prepare(); start()
                setOnCompletionListener { it.release(); if (sample === it) sample = null }
            }
        }
    }

    companion object {
        @Volatile var installed: CloudBackend? = null
    }
}

/** Hooks the cloud voices into the player and the voice page (called once from Modules.install). */
fun installCloud(app: AppModel) {
    val voices = CloudVoices.get(app)
    val backend = CloudBackend(app.context, voices, app.player) { app.settings.ttsEngine.ifEmpty { null } }
    CloudBackend.installed = backend
    app.player.registerBackend(accepts = { it.startsWith("eleven:") || it.startsWith("cloud:") }, backend = backend)
    VoiceCatalog.extra = { voices.voiceInfos() }
    // a new voice chosen in the cloud settings: the reader's choices that used the old one follow it
    voices.onVoiceReplaced = { old, new ->
        val s = app.settings
        if (s.voiceByLanguage.values.any { it == old }) s.voiceByLanguage = s.voiceByLanguage.mapValues { if (it.value == old) new else it.value }
        app.store.documents.value.filter { it.voiceID == old }.forEach { d -> app.store.update(d.id) { it.copy(voiceID = new) } }
        app.applyAudioSettings()
    }
}

/** The cloud voices for the reader's voice page (the chosen ElevenLabs voice and each service's chosen voice). */
fun cloudVoiceInfos(app: AppModel) = CloudVoices.get(app).voiceInfos()
