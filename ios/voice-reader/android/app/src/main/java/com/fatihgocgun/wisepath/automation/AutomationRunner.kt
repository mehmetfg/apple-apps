// Runs a listening automation (port of AppModel+Automation.swift): each reading step opens its folder's current book
// where it was left and reads for the step's minutes of listening, then stops at the end of a sentence; a pause step
// is a quiet break with a spoken announcement of what comes next. Between steps the reading session stays (paused),
// so the whole row plays through with the phone locked and nothing pressed.
package com.fatihgocgun.wisepath.automation

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.settings.MusicMix
import com.fatihgocgun.wisepath.store.LibraryStore
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import java.util.Locale

class AutomationRunner private constructor(private val app: AppModel) {
    val store = AutomationStore(app.context)

    /** The automation playing now (Otomasyon). */
    var run by mutableStateOf<AutomationRun?>(null)
        private set
    /** The step's book is finished: what now? */
    var choice by mutableStateOf<AutomationChoice?>(null)
        private set
    /** Seconds heard in the current reading segment (counted only while the voice is heard). */
    var segmentListened by mutableDoubleStateOf(0.0)
        private set

    private val player get() = app.player
    private val announcer = Announcer(app)
    private var job: Job? = null
    private var counter: Job? = null
    private var waiter: CompletableDeferred<SegmentOutcome>? = null
    private var choiceWaiter: CompletableDeferred<AutomationChoice.Answer>? = null
    private var expectedDoc: String? = null
    private var savedAt = 0L
    private var keptNext: (() -> Boolean)? = null
    private var keptPrevious: (() -> Boolean)? = null
    private var keysTaken = false

    init {
        // the book of a step was heard to its end: the automation decides what follows
        app.finishedOverride = { _ -> if (run != null) { segmentEnded(SegmentOutcome.finished); true } else false }
        // the step's time is up at the end of a sentence: the session stays, paused, for the announcements
        player.onSegmentEnd = {
            if (player.isPlaying) player.pause()
            segmentEnded(SegmentOutcome.timeUp)
        }
        // any other opening of a different document ends a running automation (the book the user chose plays on)
        app.scope.launch {
            player.state.map { it.documentID }.distinctUntilChanged().collect { id ->
                if (run != null && id != null && expectedDoc != null && id != expectedDoc) stopAutomation(touchPlayer = false)
            }
        }
        // leaving the screen: the place is written, so a killed process goes on from there
        Handler(Looper.getMainLooper()).post {
            ProcessLifecycleOwner.get().lifecycle.addObserver(object : DefaultLifecycleObserver {
                override fun onStop(owner: LifecycleOwner) { saveProgress() }
            })
        }
    }

    // MARK: choosing the book

    /**
     * A folder's current book: the one listened to last that is not finished; if none was opened yet, the first
     * unfinished one by title.
     */
    fun automationDocument(folder: String, excluding: Set<String> = emptySet()): DocumentRecord? {
        val docs = app.store.documents.value.filter { it.folder == folder && !it.isFinished && it.id !in excluding }
        docs.filter { it.lastOpenedAt != null }.maxByOrNull { it.lastOpenedAt!! }?.let { return it }
        return docs.minWithOrNull { a, b -> LibraryStore.collator.compare(a.title, b.title) }
    }

    /**
     * The book the folder is on: the one opened last in it, finished or not; if none was opened yet, its first
     * unfinished book. A finished one is not skipped in silence: the step asks what to do.
     */
    fun automationStepBook(folder: String): DocumentRecord? {
        val docs = app.store.documents.value.filter { it.folder == folder }
        docs.filter { it.lastOpenedAt != null }.maxByOrNull { it.lastOpenedAt!! }?.let { return it }
        return automationDocument(folder)
    }

    // MARK: a finished book in the way

    /** Says what happened and waits for the reader: on screen (the dialog) or with the headphone keys. */
    private suspend fun ask(c: AutomationChoice): AutomationChoice.Answer {
        choice = c
        run = run?.copy(phase = Phase.announcing, documentTitle = c.finishedTitle)
        var text = c.finishedTitle?.let { "Sıradaki kitap bitmiş: $it." } ?: "${c.folder} klasöründe bitmemiş kitap yok."
        c.nextTitle?.let { text += " İleri tuşu: $it." }
        c.currentTitle?.let { text += " Geri tuşu: $it kitabından sür." }
        text += " Oynat tuşu: durdur."
        val w = CompletableDeferred<AutomationChoice.Answer>()
        choiceWaiter = w
        takeKeys()
        app.scope.launch { announcer.say(text, mix()) }
        val answer = try { w.await() } finally {
            announcer.stop()
            choice = null
            releaseKeys()
        }
        return answer
    }

    /**
     * The reader answered (`key`: −1 ⏮ current · 0 stop · 1 ⏭ next, or the dialog's buttons). False when no choice
     * is waiting, so the key does its usual job.
     */
    fun answerChoice(key: Int): Boolean {
        val c = choice ?: return false
        val w = choiceWaiter ?: return false
        val answer = when (key) {
            1 -> { if (c.nextID == null) return true; AutomationChoice.Answer.next }
            -1 -> { if (c.currentID == null) return true; AutomationChoice.Answer.current }
            else -> AutomationChoice.Answer.stop
        }
        choiceWaiter = null
        w.complete(answer)
        return true
    }

    /** While a choice waits, ⏭ and ⏮ answer it; the keys go back to their owner afterwards. */
    private fun takeKeys() {
        if (keysTaken) return
        keysTaken = true
        keptNext = app.remoteNextOverride
        keptPrevious = app.remotePreviousOverride
        app.remoteNextOverride = { answerChoice(1) || keptNext?.invoke() == true }
        app.remotePreviousOverride = { answerChoice(-1) || keptPrevious?.invoke() == true }
    }

    private fun releaseKeys() {
        if (!keysTaken) return
        keysTaken = false
        app.remoteNextOverride = keptNext
        app.remotePreviousOverride = keptPrevious
        keptNext = null; keptPrevious = null
    }

    // MARK: running

    /**
     * `resume`: go on from the step where the automation was left (Kaldığı yerden), with the time already heard in
     * it; otherwise from its first step with full times. Either way each book reads on from its own place.
     */
    fun start(a: Automation, resume: Boolean = false) {
        stopAutomation()
        if (a.steps.isEmpty()) return
        if (app.recorder.isRecording) app.cancelVoiceNote()
        val from = if (resume) store.resumePoint(a) else null
        store.select(a.id)
        run = AutomationRun(a, step = from?.step ?: 0)
        expectedDoc = player.documentID
        job = app.scope.launch { runAutomation(a, from) }
    }

    /**
     * Writes where the running automation is, so it can go on from there later (after Durdur, after another book
     * was opened, after the app was closed).
     */
    fun saveProgress() {
        val r = run ?: return
        if (r.ending) return
        val heard = if (r.phase == Phase.reading) segmentListened else 0.0
        store.noteProgress(r.automation, r.step, r.listenedBefore + heard)
    }

    /** Ends the automation where it is; the book stays at its place, paused, and the automation remembers its step. */
    fun stopAutomation(touchPlayer: Boolean = true) {
        if (run == null) return
        saveProgress()
        job?.cancel(); job = null
        counter?.cancel(); counter = null
        waiter?.complete(SegmentOutcome.cancelled); waiter = null
        choiceWaiter?.complete(AutomationChoice.Answer.stop); choiceWaiter = null
        choice = null
        releaseKeys()
        announcer.stop()
        run = null
        expectedDoc = null
        player.endSegments()
        if (touchPlayer) {
            if (player.isPlaying) player.pause() else if (player.state.value.isSpeaking) player.stop()
        }
    }

    /** The player's step time is up or the book ended. */
    private fun segmentEnded(outcome: SegmentOutcome) {
        waiter?.complete(outcome)
        waiter = null
    }

    private fun mix() = app.settings.musicMix != MusicMix.off

    private suspend fun runAutomation(a: Automation, from: ResumePoint?) {
        val start = from?.step ?: 0
        var intro: String? = if (from == null) "Otomasyon başlıyor." else "Otomasyon kaldığı yerden sürüyor."
        for (i in start until a.steps.size) {
            if (run == null) return
            val step = a.steps[i]
            val heard = if (i == start) from?.listened ?: 0.0 else 0.0
            run = run?.copy(step = i, phase = Phase.announcing, stepSeconds = step.seconds.toDouble(), listenedBefore = heard)
            store.noteProgress(a, i, heard)
            when (step.kind) {
                StepKind.read -> { runReading(step, heard, intro); intro = null }
                StepKind.pause -> runPause(step, a.steps.drop(i + 1).firstOrNull { it.kind == StepKind.read })
            }
        }
        if (run == null) return
        run = run?.copy(ending = true, phase = Phase.announcing)
        store.clearProgress(a.id)
        announcer.say("Otomasyon bitti.", mix())
        if (run == null) return
        run = null
        expectedDoc = null
        player.endSegments()
        player.stop()
    }

    /**
     * Reads the folder's current book for the rest of the step's time (`listened`: seconds heard in it before a
     * stop). When that book is finished (before the step or during it) the reader chooses: the folder's next
     * unfinished book, the book already loaded, or stop. A finished book is never read again by the automation.
     */
    private suspend fun runReading(step: AutomationStep, listened: Double, intro: String?) {
        val folder = step.folder ?: return
        var remaining = step.seconds - listened
        val done = mutableSetOf<String>()
        val said = mutableListOf<String>().apply { intro?.let { add(it) } }
        var stepBook = automationStepBook(folder)
        while (remaining > 5 && run != null) {
            val doc: DocumentRecord
            val b = stepBook?.let { app.store.document(it.id) }
            if (b != null && !b.isFinished) {
                doc = b
            } else {
                val next = automationDocument(folder, done)
                val current = player.documentID?.let { app.store.document(it) }?.takeIf { !it.isFinished && it.id != next?.id }
                if (said.isNotEmpty()) { announcer.say(said.joinToString(" "), mix()); said.clear() }
                if (next == null && current == null) {
                    run = run?.copy(phase = Phase.announcing)
                    announcer.say("$folder klasöründe okunacak kitap yok, geçiyorum.", mix())
                    return
                }
                val answer = ask(AutomationChoice(stepBook?.title, folder, next?.id, next?.title, current?.id, current?.title))
                if (run == null) return
                doc = when (answer) {
                    AutomationChoice.Answer.next -> next!!
                    AutomationChoice.Answer.current -> current!!
                    AutomationChoice.Answer.stop -> { stopAutomation(); return }
                }
                stepBook = doc
            }
            run = run?.copy(phase = Phase.announcing, documentTitle = doc.title)
            expectedDoc = doc.id
            app.open(doc.id)
            if (run == null) return
            said.add(if (done.isEmpty()) "$folder. ${doc.title}." else "Sıradaki kitap: ${doc.title}.")
            announcer.say(said.joinToString(" "), mix())
            said.clear()
            if (run == null) return
            run = run?.copy(phase = Phase.reading)
            val w = CompletableDeferred<SegmentOutcome>()
            waiter = w
            startCounting()
            player.startSegment(remaining)
            delay(400)                      // a short hold after the announcement, as on the phone
            if (run == null) return
            player.play()
            val outcome = try { w.await() } finally { counter?.cancel(); counter = null }
            when (outcome) {
                SegmentOutcome.timeUp, SegmentOutcome.cancelled -> return
                SegmentOutcome.finished -> {
                    remaining -= segmentListened
                    run = run?.copy(listenedBefore = step.seconds - remaining, phase = Phase.announcing)
                    segmentListened = 0.0
                    saveProgress()
                    done.add(doc.id)
                    stepBook = app.store.document(doc.id)
                }
            }
        }
    }

    /** Counts the seconds the voice is heard in this segment, and writes the place every ten seconds or so. */
    private fun startCounting() {
        counter?.cancel()
        segmentListened = 0.0
        counter = app.scope.launch {
            var last = SystemClock.elapsedRealtime()
            while (isActive) {
                delay(250)
                val now = SystemClock.elapsedRealtime()
                val dt = (now - last) / 1000.0
                last = now
                val s = player.state.value
                if (s.isPlaying && s.breakEnds == null && dt < 2) segmentListened += dt
                if (now - savedAt >= 10_000) { savedAt = now; saveProgress() }
            }
        }
    }

    private suspend fun runPause(step: AutomationStep, next: AutomationStep?) {
        val ends = System.currentTimeMillis() + step.seconds * 1000L
        run = run?.copy(phase = Phase.thinking, documentTitle = null, phaseEnds = ends)
        var text = "Düşünme arası, ${spokenLength(step.seconds)}."
        next?.folder?.let { text += " Sonra $it." }
        announcer.say(text, mix())
        val left = ends - System.currentTimeMillis()
        if (left > 0) delay(left)
        run = run?.copy(phaseEnds = null)
    }

    private fun spokenLength(s: Int): String {
        val words = listOf("", "bir", "iki", "üç", "dört", "beş", "altı", "yedi", "sekiz", "dokuz", "on")
        val m = s / 60
        val r = s % 60
        if (r == 0 && m in 1..10) return "${words[m]} dakika"
        if (m == 0) return "$r saniye"
        return "$m dakika $r saniye"
    }

    companion object {
        @Volatile private var instance: AutomationRunner? = null

        /** Called once from Modules.install: the runner takes the player's segment and finish hooks. */
        fun install(app: AppModel): AutomationRunner = get(app)

        fun get(app: AppModel): AutomationRunner = instance ?: synchronized(this) {
            instance ?: AutomationRunner(app).also { instance = it }
        }
    }
}

/**
 * Speaks the automation's short announcements with a TextToSpeech of its own, so the reading engine's queue is not
 * touched. The Turkish voice chosen in the settings, else the engine's Turkish voice.
 */
private class Announcer(private val app: AppModel) {
    private var tts: TextToSpeech? = null
    private var ready = CompletableDeferred<Boolean>()
    private var waiter: CompletableDeferred<Unit>? = null
    private var speaking: String? = null
    private var serial = 0

    private fun engine(context: Context): TextToSpeech {
        tts?.let { return it }
        val r = CompletableDeferred<Boolean>()
        ready = r
        val listener = TextToSpeech.OnInitListener { status -> r.complete(status == TextToSpeech.SUCCESS) }
        val pkg = app.settings.ttsEngine.ifEmpty { null }
        val t = if (pkg != null) TextToSpeech(context, listener, pkg) else TextToSpeech(context, listener)
        t.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) {}
            override fun onDone(utteranceId: String) = ended(utteranceId)
            @Deprecated("Deprecated in Java") override fun onError(utteranceId: String) = ended(utteranceId)
            override fun onError(utteranceId: String, errorCode: Int) = ended(utteranceId)
            override fun onStop(utteranceId: String, interrupted: Boolean) = ended(utteranceId)
        })
        tts = t
        return t
    }

    /** From the engine's thread: only the utterance being waited for ends the wait. */
    private fun ended(id: String) {
        app.scope.launch { if (speaking == id) finish() }
    }

    suspend fun say(text: String, @Suppress("UNUSED_PARAMETER") mix: Boolean) {
        stop()
        val t = engine(app.context)
        val ok = withTimeoutOrNull(5000) { ready.await() } ?: false
        if (!ok) return
        val s = app.settings
        val chosen = s.voiceByLanguage["tr"]?.let { id -> runCatching { t.voices?.firstOrNull { it.name == id } }.getOrNull() }
        if (chosen != null) t.voice = chosen else t.language = Locale("tr", "TR")
        val tune = s.voiceTune[chosen?.name ?: ""]
        t.setPitch((tune?.pitch ?: s.pitch).toFloat())
        t.setSpeechRate(1.1f)
        t.setAudioAttributes(AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
        serial += 1
        val id = "announce-$serial"
        val w = CompletableDeferred<Unit>()
        waiter = w
        speaking = id
        val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, maxOf(0.6, tune?.volume ?: 1.0).toFloat()) }
        t.speak(text, TextToSpeech.QUEUE_FLUSH, params, id)
        // a safety net: a voice that never reports its end does not hold the automation
        withTimeoutOrNull(((text.length / 8.0 + 6) * 1000).toLong()) { w.await() }
        if (speaking == id) finish()
        delay(400)                          // the pause after an announcement
    }

    fun stop() {
        runCatching { if (tts?.isSpeaking == true) tts?.stop() }
        finish()
    }

    private fun finish() {
        waiter?.complete(Unit)
        waiter = null
        speaking = null
    }
}
