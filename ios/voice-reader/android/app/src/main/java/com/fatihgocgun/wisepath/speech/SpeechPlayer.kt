// Reads a document aloud (port of Speech/SpeechPlayer.swift). The text is cut into pieces — a few sentences of one
// language inside one paragraph — that are queued on the voice two ahead, so there is no gap between them. The
// highlighted word follows the voice's own range callbacks; a voice that gives none is followed by its measured pace.
//
// Positions are UTF-16 offsets in the document's plain text (one paragraph per line).
package com.fatihgocgun.wisepath.speech

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.fatihgocgun.wisepath.model.DocumentContent
import com.fatihgocgun.wisepath.settings.MusicMix
import com.fatihgocgun.wisepath.settings.NavigationUnit
import com.fatihgocgun.wisepath.settings.VoiceTune
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

sealed class SleepTimer {
    data object Off : SleepTimer()
    data class Minutes(val minutes: Int) : SleepTimer()
    data object EndOfChapter : SleepTimer()
}

enum class BreakKind { music, wait }

/** What the screens draw from (changes a few times a second at most). */
data class PlayerState(
    val documentID: String? = null,
    val title: String = "",
    val author: String? = null,
    val isSpeaking: Boolean = false,          // a reading session exists (playing or paused)
    val isPaused: Boolean = false,
    val cursor: Int = 0,
    val length: Int = 0,
    val sleepTimer: SleepTimer = SleepTimer.Off,
    val sleepEnds: Long? = null,
    val breakEnds: Long? = null,
    val breakKind: BreakKind = BreakKind.music,
    val problem: String? = null,
    val speed: Double = 1.0,
) {
    val isPlaying get() = isSpeaking && !isPaused
    val progress: Float get() = if (length > 0) cursor.toFloat() / length else 0f
}

/** The word and sentence being heard (changes with every word; only the page observes it). */
data class Spoken(val word: IntRange? = null, val sentence: IntRange? = null)

class SpeechPlayer(private val context: Context) : SpeechCallbacks {
    private val main = Handler(Looper.getMainLooper())
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val _state = MutableStateFlow(PlayerState())
    val state: StateFlow<PlayerState> = _state
    private val _spoken = MutableStateFlow(Spoken())
    val spoken: StateFlow<Spoken> = _spoken

    var nav: TextNav = TextNav("")
        private set
    val documentID get() = _state.value.documentID
    val cursor get() = _state.value.cursor
    val isPlaying get() = _state.value.isPlaying

    // MARK: settings the app pushes in

    var speed = 1.0
        set(v) { if (field != v) { field = v; _state.value = _state.value.copy(speed = v); restartSoon() } }
    var pitch = 1.0
        set(v) { if (field != v) { field = v; restartSoon() } }
    var voiceTune: Map<String, VoiceTune> = emptyMap()
        set(v) { if (field != v) { field = v; restartSoon() } }
    /** Language code → voice id. */
    var voices: Map<String, String> = emptyMap()
        set(v) { if (field != v) { field = v; restartSoon() } }
    /** The document's own voice (overrides the language default for its base language). */
    var documentVoice: String? = null
        set(v) { if (field != v) { field = v; restartSoon() } }
    var baseLanguage = "tr"
    var mixedLanguage = true
        set(v) { if (field != v) { field = v; restartSoon() } }
    var simplifyLinks = true
        set(v) { if (field != v) { field = v; restartSoon() } }
    var skipCitations = true
        set(v) { if (field != v) { field = v; restartSoon() } }
    var startAtSentence = true
    var musicMix = MusicMix.off
    var charsPerSecond = 14.0
    var breakEvery = 0.0                     // minutes of listening between music breaks (0 = off)
    var breakLength = 30.0
    var marks: (NavigationUnit) -> List<Int> = { emptyList() }

    // MARK: hooks the app sets

    /** The reader moved or the voice moved on (every ~2 s while reading and on every jump). */
    var onPosition: ((String, Int) -> Unit)? = null
    /** The end of the document was heard. */
    var onFinished: ((String) -> Unit)? = null
    /** Asked before a move: false keeps the place (a finished book asks first). */
    var mayMove: ((String, Int) -> Boolean)? = null
    /** An automation segment's time is up (at the end of a sentence). */
    var onSegmentEnd: (() -> Unit)? = null
    /** The pace was measured anew (characters a second at 1×). */
    var onPace: ((Double) -> Unit)? = null
    /** A new session began (the app starts the media service). */
    var onSessionStart: (() -> Unit)? = null

    // MARK: backends

    private var tts: TtsBackend? = null
    private var ttsEngine: String? = null
    private val extraBackends = mutableListOf<Pair<(String) -> Boolean, SpeechBackend>>()

    fun ttsBackend(): TtsBackend {
        tts?.let { return it }
        val b = TtsBackend(context, ttsEngine, this) { ok ->
            main.post { if (!ok) setProblem("Metin okuma motoru başlatılamadı. Ayarlar › Erişilebilirlik › Metin okuma çıktısından bir motor kurun.") }
        }
        tts = b
        return b
    }

    fun setEngine(pkg: String?) {
        val p = pkg?.ifEmpty { null }
        if (p == ttsEngine && tts != null) return
        ttsEngine = p
        val wasPlaying = isPlaying
        if (wasPlaying) stopAudio()
        tts?.shutdown()
        tts = null
        ttsBackend()
        if (wasPlaying) main.postDelayed({ play(cursor, snap = false) }, 600)
    }

    /** A cloud or other backend serves the voices whose id it accepts. */
    fun registerBackend(accepts: (String) -> Boolean, backend: SpeechBackend) { extraBackends.add(accepts to backend) }

    private fun backendFor(voice: String?): SpeechBackend =
        voice?.let { v -> extraBackends.firstOrNull { it.first(v) }?.second } ?: ttsBackend()

    // MARK: the queue

    private data class Piece(val start: Int, val end: Int, val language: String, val voice: String?, val spoken: SpokenText)

    private var generation = 0
    private var seq = 0
    private val queued = LinkedHashMap<Int, Piece>()        // seq → piece, in order
    private var nextFrom = 0                                // where the next piece starts
    private var current: Piece? = null
    private var currentSeq = -1
    private var currentStartedAt = 0L
    private var activeBackends = mutableSetOf<SpeechBackend>()
    private var audioHeard = false
    private var startedAt = 0
    private var stopAfterPiece = false
    private var segmentEndsAt: Long? = null                 // elapsed listening (ms) at which a segment ends
    private var listenedMs = 0L
    private var lastTick = 0L
    private var lastBreakAt = 0L
    private var paceMark: Pair<Long, Int>? = null
    private var lastReported = 0L
    private var ticker: Job? = null
    private var restartJob: Job? = null
    private var breakJob: Job? = null
    private var sleepChapterEnd: Int? = null
    private var heldBySystem = false

    // MARK: loading

    fun load(id: String, title: String, author: String?, content: DocumentContent, at: Int, language: String?) {
        stop(release = false)
        nav = TextNav(content.text, content.chapters, content.pages)
        baseLanguage = language?.take(2) ?: LanguageGuess.detect(content.text)
        val c = at.coerceIn(0, nav.length)
        _state.value = PlayerState(documentID = id, title = title, author = author, cursor = c, length = nav.length, speed = speed)
        setSpokenAround(c)
    }

    /** The text grew (sync appended pages): keep the place. */
    fun extend(content: DocumentContent) {
        nav = TextNav(content.text, content.chapters, content.pages)
        _state.value = _state.value.copy(length = nav.length)
    }

    fun unload() {
        stop()
        nav = TextNav("")
        _state.value = PlayerState(speed = speed)
        _spoken.value = Spoken()
    }

    // MARK: control

    fun play() = play(cursor)

    fun play(from: Int, snap: Boolean = true) {
        heldBySystem = false
        val id = documentID ?: return
        if (nav.blocks.isEmpty()) return
        if (mayMove?.invoke(id, from) == false) return
        var at = from.coerceIn(0, maxOf(0, nav.length - 1))
        if (snap && startAtSentence) at = nav.sentenceStart(at + 1)
        breakJob?.cancel(); breakJob = null
        stopAudio()
        if (!requestFocus()) { setProblem("Ses odağı alınamadı (bir arama sürüyor olabilir)."); return }
        _state.value = _state.value.copy(isSpeaking = true, isPaused = false, cursor = at, breakEnds = null, problem = null)
        onSessionStart?.invoke()
        nextFrom = at
        startedAt = at
        audioHeard = false
        paceMark = null
        stopAfterPiece = false
        fill()
        startTicker()
        report(force = true)
    }

    fun toggle() {
        val s = _state.value
        if (!s.isSpeaking) play() else if (s.isPaused) resume() else pause()
    }

    fun pause() {
        heldBySystem = false
        val s = _state.value
        if (!s.isSpeaking || s.isPaused) return
        stopAudio()
        _state.value = s.copy(isPaused = true)
        ticker?.cancel(); ticker = null
        paceMark = null
        report(force = true)
        if (musicMix != MusicMix.off) abandonFocus()
    }

    fun resume() {
        heldBySystem = false
        val s = _state.value
        if (!s.isSpeaking || !s.isPaused) return
        if (s.breakEnds != null) { endBreak(); return }
        play(cursor, snap = false)
    }

    fun stop(release: Boolean = true) {
        restartJob?.cancel()
        breakJob?.cancel(); breakJob = null
        ticker?.cancel(); ticker = null
        stopAudio()
        val s = _state.value
        if (s.isSpeaking) report(force = true)
        _state.value = s.copy(isSpeaking = false, isPaused = false, breakEnds = null, sleepTimer = SleepTimer.Off, sleepEnds = null)
        sleepChapterEnd = null
        segmentEndsAt = null
        if (release) abandonFocus()
    }

    /** Move the cursor without speaking (a tap on the page while paused, a jump from the contents). */
    fun moveCursor(to: Int, play: Boolean? = null) {
        val at = to.coerceIn(0, nav.length)
        val id = documentID ?: return
        if ((at != cursor || play == true) && mayMove?.invoke(id, at) == false) return
        if (play ?: isPlaying) {
            play(at, snap = false)
        } else {
            if (_state.value.isSpeaking) stopAudio()
            _state.value = _state.value.copy(cursor = at)
            setSpokenAround(at)
            report(force = true)
        }
    }

    fun skip(forward: Boolean, unit: NavigationUnit) {
        if (documentID == null) return
        val t = nav.target(cursor, forward, unit, marks(unit), charsPerSecond * speed) ?: return
        moveCursor(t)
    }

    fun setSleepTimer(t: SleepTimer) {
        when (t) {
            SleepTimer.Off -> { sleepChapterEnd = null; _state.value = _state.value.copy(sleepTimer = t, sleepEnds = null) }
            is SleepTimer.Minutes -> {
                sleepChapterEnd = null
                _state.value = _state.value.copy(sleepTimer = t, sleepEnds = System.currentTimeMillis() + t.minutes * 60_000L)
            }
            SleepTimer.EndOfChapter -> {
                sleepChapterEnd = nav.chapters.map { it.offset }.filter { it > cursor }.minOrNull() ?: nav.length
                _state.value = _state.value.copy(sleepTimer = t, sleepEnds = null)
            }
        }
    }

    fun clearProblem() { _state.value = _state.value.copy(problem = null) }
    private fun setProblem(p: String) { _state.value = _state.value.copy(problem = p) }

    // MARK: automation segments: read for so many seconds of listening, then stop at the end of a sentence

    fun startSegment(seconds: Double) { segmentEndsAt = listenedMs + (seconds * 1000).toLong() }
    fun endSegments() { segmentEndsAt = null }

    // MARK: breaks and active waits

    /** Aktif bekleme: pause now and go on by itself after `seconds` (null = when the other app's music stops). */
    fun activePause(seconds: Double?) {
        val s = _state.value
        if (!s.isSpeaking) return
        stopAudio()
        ticker?.cancel(); ticker = null
        abandonFocus()
        val ends = System.currentTimeMillis() + ((seconds ?: 3600.0) * 1000).toLong()
        _state.value = s.copy(isPaused = true, breakEnds = ends, breakKind = BreakKind.wait)
        report(force = true)
        breakJob?.cancel()
        breakJob = scope.launch {
            if (seconds != null) delay((seconds * 1000).toLong())
            else {
                val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
                delay(4000)
                while (isActive && am.isMusicActive && System.currentTimeMillis() < ends) delay(2000)
            }
            endBreak()
        }
    }

    fun cancelWait() {
        breakJob?.cancel(); breakJob = null
        if (_state.value.breakEnds != null) _state.value = _state.value.copy(breakEnds = null)
    }

    private fun startBreak(seconds: Double) {
        val s = _state.value
        stopAudio()
        ticker?.cancel(); ticker = null
        abandonFocus()
        _state.value = s.copy(isPaused = true, breakEnds = System.currentTimeMillis() + (seconds * 1000).toLong(), breakKind = BreakKind.music)
        lastBreakAt = listenedMs
        breakJob?.cancel()
        breakJob = scope.launch { delay((seconds * 1000).toLong()); endBreak() }
    }

    private fun endBreak() {
        breakJob = null
        val s = _state.value
        if (!s.isSpeaking) return
        _state.value = s.copy(breakEnds = null)
        play(cursor, snap = false)
    }

    // MARK: building pieces

    private fun voiceFor(language: String): String? =
        if (language == baseLanguage && documentVoice != null) documentVoice else voices[language]

    private fun nextPiece(): Piece? {
        while (nextFrom < nav.length) {
            val bi = nav.blockIndex(nextFrom)
            val block = nav.blocks.getOrNull(bi) ?: return null
            if (nextFrom > block.last) {
                val nb = nav.blocks.getOrNull(bi + 1) ?: run { nextFrom = nav.length; return null }
                nextFrom = nb.first
                continue
            }
            if (nextFrom < block.first) nextFrom = block.first
            val start = nextFrom
            val blockEnd = block.last + 1
            var end = start
            var lang: String? = null
            while (end < blockEnd) {
                val sEnd = minOf(blockEnd, nav.sentenceEnd(end) ?: blockEnd)
                val sLen = maxOf(1, sEnd - end)
                val l = (if (mixedLanguage) LanguageGuess.guess(nav.text.substring(end, minOf(nav.length, end + sLen))) else null) ?: baseLanguage
                if (lang == null) lang = l
                else if (l != lang || (end - start) + sLen > 320) break
                end = maxOf(sEnd, end + 1)
                if (end - start >= 320) break
            }
            end = minOf(end, blockEnd)
            nextFrom = if (end >= blockEnd) (nav.blocks.getOrNull(bi + 1)?.first ?: nav.length) else end
            val raw = nav.text.substring(start, end)
            if (raw.isBlank()) continue
            val language = lang ?: baseLanguage
            return Piece(start, end, language, voiceFor(language), SpokenText(raw, simplifyLinks, skipCitations))
        }
        return null
    }

    private fun fill() {
        while (queued.size < 3) {
            val piece = nextPiece() ?: break
            if (piece.spoken.string.isBlank()) continue
            val id = ++seq
            queued[id] = piece
            val tune = voiceTune[piece.voice ?: ""] ?: VoiceTune(pitch = pitch)
            val backend = backendFor(piece.voice)
            activeBackends.add(backend)
            backend.enqueue(
                SpeakRequest("$generation:$id", piece.spoken.string, piece.language, piece.voice,
                    speed.toFloat(), tune.pitch.toFloat(), tune.volume.toFloat())
            )
        }
        if (queued.isEmpty() && nextFrom >= nav.length && _state.value.isPlaying) finished()
    }

    private fun stopAudio() {
        generation++
        activeBackends.forEach { it.stop() }
        activeBackends.clear()
        queued.clear()
        current = null
        currentSeq = -1
    }

    private fun parse(utteranceId: String): Int? {
        val g = utteranceId.substringBefore(':').toIntOrNull() ?: return null
        if (g != generation) return null
        return utteranceId.substringAfter(':').toIntOrNull()
    }

    // MARK: callbacks (from the voice's thread → main)

    override fun onStart(utteranceId: String) = main.post {
        val id = parse(utteranceId) ?: return@post
        val piece = queued[id] ?: return@post
        // a piece starting means every earlier one is over
        queued.keys.filter { it < id }.forEach { queued.remove(it) }
        current = piece
        currentSeq = id
        currentStartedAt = SystemClock.elapsedRealtime()
        audioHeard = true
        val sleepEnd = sleepChapterEnd
        if (sleepEnd != null && piece.start >= sleepEnd) { pause(); setSleepTimer(SleepTimer.Off); return@post }
        setCursor(piece.start)
    }.let { }

    override fun onRange(utteranceId: String, start: Int, end: Int) = main.post {
        val id = parse(utteranceId) ?: return@post
        val piece = queued[id] ?: return@post
        if (current !== piece) { current = piece; currentSeq = id; currentStartedAt = SystemClock.elapsedRealtime() }
        val at = piece.start + piece.spoken.original(start)
        setCursor(at.coerceIn(piece.start, piece.end))
    }.let { }

    override fun onDone(utteranceId: String) = main.post {
        val id = parse(utteranceId) ?: return@post
        val piece = queued.remove(id) ?: return@post
        if (!_state.value.isPlaying) return@post
        setCursor(minOf(piece.end, nav.length), word = false)
        // the end of a piece is the end of a sentence: the place for a sleep, a segment's end or a music break
        if (stopAfterPiece) { stopAfterPiece = false; pause(); setSleepTimer(SleepTimer.Off); return@post }
        val seg = segmentEndsAt
        if (seg != null && listenedMs >= seg) {
            segmentEndsAt = null
            stopAudio()
            report(force = true)
            onSegmentEnd?.invoke()
            return@post
        }
        if (breakEvery > 0 && listenedMs - lastBreakAt >= breakEvery * 60_000) {
            startBreak(breakLength)
            return@post
        }
        fill()
    }.let { }

    override fun onError(utteranceId: String, message: String?) = main.post {
        val id = parse(utteranceId) ?: return@post
        queued.remove(id)
        if (!audioHeard) {
            stop()
            setProblem("Ses üretilemedi: seçili ses bu cihazda kurulu olmayabilir. Ses Ayarları'ndan başka bir ses seçin ya da Android ayarlarından ses verisini indirin." +
                (message?.let { " ($it)" } ?: ""))
            return@post
        }
        if (_state.value.isPlaying) fill()
    }.let { }

    // MARK: cursor and spoken marks

    private fun setCursor(at: Int, word: Boolean = true) {
        val c = at.coerceIn(0, nav.length)
        if (c != _state.value.cursor) _state.value = _state.value.copy(cursor = c)
        if (word) setSpokenAround(c) else _spoken.value = _spoken.value.copy(word = null)
        report(force = false)
    }

    private fun setSpokenAround(at: Int) {
        if (nav.length == 0) { _spoken.value = Spoken(); return }
        val w = nav.wordRange(minOf(at, nav.length - 1))
        val s = nav.sentenceRange(at)
        val next = Spoken(if (w.isEmpty()) null else w, s)
        if (next != _spoken.value) _spoken.value = next
    }

    private fun startTicker() {
        if (ticker != null) return
        lastTick = SystemClock.elapsedRealtime()
        ticker = scope.launch {
            while (isActive) {
                delay(120)
                tick()
            }
        }
    }

    private fun tick() {
        val now = SystemClock.elapsedRealtime()
        val dt = now - lastTick
        lastTick = now
        val s = _state.value
        if (!s.isPlaying) return
        if (dt in 1..2000) listenedMs += dt
        // a voice without range callbacks: the word is estimated from the time since the piece began
        val piece = current
        val backend = backendFor(piece?.voice)
        if (piece != null && !backend.reportsRanges) {
            val elapsed = (now - currentStartedAt) / 1000.0
            val est = piece.start + (elapsed * charsPerSecond * speed).toInt()
            if (est in piece.start until piece.end && est > cursor) setCursor(est)
        }
        val ends = s.sleepEnds
        if (ends != null && System.currentTimeMillis() >= ends) {
            // the sentence being read is finished first
            stopAfterPiece = true
            _state.value = s.copy(sleepEnds = null)
        }
        measurePace()
    }

    private fun measurePace() {
        if (!(current != null && backendFor(current?.voice).reportsRanges)) return
        val now = SystemClock.elapsedRealtime()
        val m = paceMark ?: run { paceMark = now to cursor; return }
        val dt = (now - m.first) / 1000.0
        if (dt < 20) return
        val dc = cursor - m.second
        if (dc > 0 && dt < 120) {
            val cps = dc / dt / speed
            if (cps > 4 && cps < 40) {
                charsPerSecond = charsPerSecond * 0.7 + cps * 0.3
                onPace?.invoke(charsPerSecond)
            }
        }
        paceMark = now to cursor
    }

    private fun report(force: Boolean) {
        val id = documentID ?: return
        val now = SystemClock.elapsedRealtime()
        if (!force && now - lastReported < 2000) return
        lastReported = now
        onPosition?.invoke(id, cursor)
    }

    private fun finished() {
        val id = documentID ?: return
        // the end was reached without a single sound: not a book heard to its end
        if (!audioHeard && nav.length - startedAt > 200) {
            val at = startedAt
            stop()
            _state.value = _state.value.copy(cursor = at)
            setProblem("Ses üretilemedi: seçili ses bu cihazda kurulu olmayabilir. Ses Ayarları'ndan başka bir ses seçin.")
            report(force = true)
            return
        }
        _state.value = _state.value.copy(cursor = nav.length)
        stop()
        onFinished?.invoke(id)
    }

    private fun restartSoon() {
        if (!isPlaying) return
        restartJob?.cancel()
        restartJob = scope.launch {
            delay(350)
            if (isPlaying) play(nav.sentenceStart(cursor + 1), snap = false)
        }
    }

    /** Seconds of listening left from the cursor at the current speed. */
    val remainingSeconds: Double get() = maxOf(0, nav.length - cursor) / (charsPerSecond * speed)
    val totalSeconds: Double get() = nav.length / (charsPerSecond * speed)

    // MARK: audio focus — calls, other apps, headphones

    private val audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private var focusRequest: AudioFocusRequest? = null
    private val focusListener = AudioManager.OnAudioFocusChangeListener { change ->
        main.post {
            when (change) {
                AudioManager.AUDIOFOCUS_LOSS -> { if (isPlaying) { pause() } }
                AudioManager.AUDIOFOCUS_LOSS_TRANSIENT, AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> {
                    if (isPlaying) { pause(); heldBySystem = true }
                }
                AudioManager.AUDIOFOCUS_GAIN -> {
                    if (heldBySystem && _state.value.isSpeaking && _state.value.isPaused) { heldBySystem = false; resume() }
                }
            }
        }
    }

    private fun requestFocus(): Boolean {
        val gain = if (musicMix == MusicMix.off) AudioManager.AUDIOFOCUS_GAIN else AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK
        val req = AudioFocusRequest.Builder(gain)
            .setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setOnAudioFocusChangeListener(focusListener, main)
            .setWillPauseWhenDucked(true)
            .build()
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = req
        val r = audioManager.requestAudioFocus(req)
        return r == AudioManager.AUDIOFOCUS_REQUEST_GRANTED || r == AudioManager.AUDIOFOCUS_REQUEST_DELAYED
    }

    private fun abandonFocus() {
        focusRequest?.let { audioManager.abandonAudioFocusRequest(it) }
        focusRequest = null
    }

    /** Headphones pulled out: pause. */
    fun becameNoisy() { if (isPlaying) pause() }
}
