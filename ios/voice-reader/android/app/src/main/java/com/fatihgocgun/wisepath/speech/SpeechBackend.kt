// A voice the player can read with. The player cuts the text into pieces (a few sentences of one language, inside
// one paragraph) and hands each to the backend with an utterance id; the backend reports when a piece starts, which
// span of the spoken string is being said (when it knows), and when it is done.
//
//   TtsBackend     Android's TextToSpeech (any installed engine: Google, Samsung, RHVoice…), live word callbacks
//   cloud voices   ElevenLabs / OpenAI / Google / Azure render audio files (see cloud/CloudBackend.kt)
package com.fatihgocgun.wisepath.speech

import android.content.Context
import android.media.AudioAttributes
import android.os.Bundle
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import android.speech.tts.Voice
import java.util.Locale

interface SpeechCallbacks {
    fun onStart(utteranceId: String)
    /** `start` and `end` are positions in the spoken string handed to `enqueue`. */
    fun onRange(utteranceId: String, start: Int, end: Int)
    fun onDone(utteranceId: String)
    fun onError(utteranceId: String, message: String?)
}

data class SpeakRequest(
    val utteranceId: String,
    val text: String,
    val language: String,
    val voice: String?,              // backend-specific voice name; null = the language's default
    val rate: Float,                 // 1 = the voice's normal pace
    val pitch: Float,
    val volume: Float,
)

interface SpeechBackend {
    /** Whether the backend can speak now. */
    val ready: Boolean
    /** Whether it reports word ranges (else the player estimates the word from the time). */
    val reportsRanges: Boolean
    fun enqueue(request: SpeakRequest)
    fun stop()
    fun shutdown() {}
}

/** One installed voice, as the voice page lists it. */
data class VoiceInfo(
    val id: String,               // TextToSpeech Voice.name, or "eleven:…" / "cloud:…"
    val name: String,
    val language: String,         // "tr", "en"…
    val locale: String,           // "tr-TR"
    val quality: Int,
    val network: Boolean,
    val installed: Boolean,
)

class TtsBackend(context: Context, enginePackage: String?, private val callbacks: SpeechCallbacks, onReady: (Boolean) -> Unit) : SpeechBackend {
    private var isReady = false
    private val tts: TextToSpeech

    init {
        val listener = TextToSpeech.OnInitListener { status ->
            isReady = status == TextToSpeech.SUCCESS
            onReady(isReady)
        }
        tts = if (enginePackage.isNullOrEmpty()) TextToSpeech(context.applicationContext, listener)
        else TextToSpeech(context.applicationContext, listener, enginePackage)
        tts.setAudioAttributes(
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_MEDIA).setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build()
        )
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String) = callbacks.onStart(utteranceId)
            override fun onDone(utteranceId: String) = callbacks.onDone(utteranceId)
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String) = callbacks.onError(utteranceId, null)
            override fun onError(utteranceId: String, errorCode: Int) = callbacks.onError(utteranceId, "TTS hata kodu $errorCode")
            override fun onStop(utteranceId: String, interrupted: Boolean) {}
            override fun onRangeStart(utteranceId: String, start: Int, end: Int, frame: Int) {
                rangesSeen = true
                callbacks.onRange(utteranceId, start, end)
            }
        })
    }

    @Volatile private var rangesSeen = false
    override val ready get() = isReady
    override val reportsRanges get() = rangesSeen

    private var currentVoice: String? = null
    private var currentLocale: String? = null

    override fun enqueue(request: SpeakRequest) {
        if (!isReady) { callbacks.onError(request.utteranceId, "Ses motoru hazır değil"); return }
        val voice = request.voice?.let { v -> runCatching { tts.voices?.firstOrNull { it.name == v } }.getOrNull() }
        if (voice != null) {
            if (currentVoice != voice.name) { tts.voice = voice; currentVoice = voice.name; currentLocale = null }
        } else if (currentLocale != request.language || currentVoice != null) {
            tts.language = Locale.forLanguageTag(request.language)
            currentLocale = request.language
            currentVoice = null
        }
        tts.setSpeechRate(request.rate)
        tts.setPitch(request.pitch)
        val params = Bundle().apply { putFloat(TextToSpeech.Engine.KEY_PARAM_VOLUME, request.volume.coerceIn(0f, 1f)) }
        tts.speak(request.text, TextToSpeech.QUEUE_ADD, params, request.utteranceId)
    }

    override fun stop() { tts.stop() }
    override fun shutdown() { tts.shutdown() }

    fun voices(): List<VoiceInfo> = runCatching {
        tts.voices.orEmpty().map { v: Voice ->
            VoiceInfo(
                id = v.name, name = prettyName(v), language = v.locale.language, locale = v.locale.toLanguageTag(),
                quality = v.quality, network = v.isNetworkConnectionRequired,
                installed = !v.features.orEmpty().contains(TextToSpeech.Engine.KEY_FEATURE_NOT_INSTALLED),
            )
        }.sortedWith(compareBy<VoiceInfo> { it.locale }.thenByDescending { it.quality }.thenBy { it.name })
    }.getOrDefault(emptyList())

    fun engines(): List<Pair<String, String>> = runCatching { tts.engines.map { it.name to it.label } }.getOrDefault(emptyList())
    val defaultEngine: String? get() = runCatching { tts.defaultEngine }.getOrNull()

    /** Speak a sample once, outside the reading queue (the voice page's preview). */
    fun preview(voice: VoiceInfo, rate: Float, pitch: Float) {
        val v = runCatching { tts.voices?.firstOrNull { it.name == voice.id } }.getOrNull() ?: return
        tts.stop()
        tts.voice = v
        currentVoice = v.name
        tts.setSpeechRate(rate)
        tts.setPitch(pitch)
        val sample = if (voice.language == "tr") "Merhaba, ben ${voice.name}. Bu sesle okuyabilirim."
        else "Hello, I am ${voice.name}. I can read your documents."
        tts.speak(sample, TextToSpeech.QUEUE_FLUSH, null, "preview")
    }

    companion object {
        /** "tr-tr-x-cfs-local" → "Türkçe · cfs (cihazda)". */
        fun prettyName(v: Voice): String {
            val lang = v.locale.getDisplayLanguage(Locale("tr"))
                .replaceFirstChar { it.titlecase(Locale("tr")) }
            val country = v.locale.getDisplayCountry(Locale("tr"))
            val tag = v.name.substringAfter("-x-", "").substringBefore("-")
            val where = if (v.isNetworkConnectionRequired) "ağ" else "cihazda"
            val base = if (country.isNotEmpty()) "$lang ($country)" else lang
            return if (tag.isNotEmpty()) "$base · $tag · $where" else "$base · ${v.name} · $where"
        }
    }
}

/** Voices from other backends (cloud), listed beside the device's own on the voice page. Set by the cloud module. */
object VoiceCatalog {
    var extra: () -> List<VoiceInfo> = { emptyList() }
}
