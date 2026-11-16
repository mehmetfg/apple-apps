// Cloud voices (port of Speech/ElevenLabs.swift and Speech/CloudVoice.swift): ElevenLabs, Google Cloud
// Text-to-Speech, Azure AI Speech and OpenAI. The user's own keys (kept only in the app's settings on this device),
// a voice per service; each piece of text is synthesised once, stored on disk with its word timings, and played by
// CloudBackend. Speed is applied on the device (MediaPlayer's time stretch keeps the pitch), so a stored piece serves
// every speed and listening to it again costs no credits.
//
//   ElevenLabs  POST /v1/text-to-speech/{voice}/with-timestamps (audio + per-character times), GET /v1/voices,
//               GET /v1/user/subscription (credits used / limit)
//   Google      WaveNet / Standard 4 M characters a month free, Neural2 and Chirp 3: HD 1 M; word times by SSML marks
//   Azure       neural voices 0.5 M characters a month free on the F0 key
//   OpenAI      no free allowance (gpt-4o-mini-tts)
//
// Voice ids the reader stores: "eleven:<voiceId>" and "cloud:<provider>:<voice>".
package com.fatihgocgun.wisepath.cloud

import android.content.Context
import android.content.SharedPreferences
import android.media.MediaMetadataRetriever
import android.os.Handler
import android.os.Looper
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.model.AppJson
import com.fatihgocgun.wisepath.settings.Settings
import com.fatihgocgun.wisepath.speech.VoiceInfo
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonObject
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.security.MessageDigest
import java.text.NumberFormat
import java.time.YearMonth
import java.util.Base64
import java.util.Locale

// MARK: settings

enum class ElevenModel(val id: String, val label: String) {
    flash("eleven_flash_v2_5", "Flash v2.5 · hızlı, yarım kredi"),
    turbo("eleven_turbo_v2_5", "Turbo v2.5 · yarım kredi"),
    multilingual("eleven_multilingual_v2", "Multilingual v2 · en doğal, tam kredi");
    /** Only the v2.5 models accept `language_code`; the others answer with an error when it is sent. */
    val forcesLanguage get() = this != multilingual
    companion object { fun of(id: String) = entries.firstOrNull { it.id == id } ?: multilingual }
}

/** The stored format decides how much a gigabyte of cache holds. */
enum class ElevenQuality(val id: String, val kbps: Int) {
    low("mp3_22050_32", 32), medium("mp3_44100_64", 64), high("mp3_44100_128", 128);
    val megabytesPerHour get() = kbps * 1000.0 / 8 * 3600 / 1_000_000
    val label get() = "$kbps kbps · saatte ~${Math.round(megabytesPerHour)} MB"
    companion object { fun of(id: String?) = entries.firstOrNull { it.id == id } ?: medium }
}

enum class CloudProvider(val label: String, val keyHelp: String) {
    google("Google Cloud", "console.cloud.google.com › Text-to-Speech API'yi etkinleştir › Kimlik bilgileri › API anahtarı. Ücretsiz kota için bile faturalandırma hesabı ister."),
    azure("Microsoft Azure", "portal.azure.com › Speech kaynağı oluştur (ücretsiz F0) › Anahtarlar ve uç nokta: Anahtar 1 ve Bölge (örn. westeurope)."),
    openai("OpenAI", "platform.openai.com › API keys. Ücretsiz kota yok; dakikası yaklaşık 1,5 sent.");
    companion object { fun of(s: String) = entries.firstOrNull { it.name == s } ?: google }
}

@Serializable data class ElevenVoice(val id: String, val name: String, val category: String = "")
@Serializable data class CloudVoiceInfo(val id: String, val name: String, val detail: String)
data class ElevenSubscription(val tier: String, val used: Int, val limit: Int, val resets: Long?) {
    val left get() = maxOf(0, limit - used)
}

class CloudException(message: String) : Exception(message)

internal object CloudErrors {
    const val noKey = "API anahtarı kayıtlı değil."
    const val noVoice = "Ses seçilmedi. ElevenLabs ayarlarında Bağlantıyı dene'ye bas."
    const val undecodable = "Sunucunun gönderdiği ses okunamadı."
    fun server(code: Int, m: String): String {
        if (m.lowercase().contains("quota")) return "Kredi bitti ($code). $m"
        return when (code) {
            401 -> "Anahtar geçersiz ya da bu işlem için izni yok (401). $m"
            429 -> "Çok sık istek ya da eşzamanlı istek sınırı (429). $m"
            else -> "Sunucu hatası $code. $m"
        }
    }
}

class ServerException(val code: Int, val detail: String) : Exception(CloudErrors.server(code, detail))

// MARK: HTTP (HttpURLConnection; no extra libraries)

internal object Http {
    fun send(url: String, method: String = "GET", headers: Map<String, String> = emptyMap(), body: ByteArray? = null,
             timeoutMs: Int = 40_000): ByteArray {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.requestMethod = method
            c.connectTimeout = 15_000
            c.readTimeout = timeoutMs
            headers.forEach { (k, v) -> c.setRequestProperty(k, v) }
            if (body != null) { c.doOutput = true; c.outputStream.use { it.write(body) } }
            val code = c.responseCode
            val data = (if (code in 200..299) c.inputStream else c.errorStream)?.use { it.readBytes() } ?: ByteArray(0)
            if (code !in 200..299) throw ServerException(code, message(data))
            return data
        } finally { c.disconnect() }
    }

    /** The provider's own words from an error answer (ElevenLabs: detail; the others: error.message). */
    private fun message(data: ByteArray): String {
        var m = String(data)
        runCatching {
            val j = AppJson.parseToJsonElement(m).jsonObject
            val d = j["detail"]
            when {
                d is JsonObject -> m = (d["message"] ?: d["status"])?.jsonPrimitive?.content ?: m
                d is JsonPrimitive -> m = d.content
                j["error"] is JsonObject -> m = j["error"]!!.jsonObject["message"]?.jsonPrimitive?.content ?: m
            }
        }
        return m.take(200)
    }

    fun enc(s: String): String = URLEncoder.encode(s, "UTF-8").replace("+", "%20")
}

// MARK: the disk cache

@Serializable data class CacheWord(val location: Int, val length: Int, val seconds: Double)

/** Same fields as the iOS ElevenRecord, plus the text and the voice tag (so a later piece can reuse its end). */
@Serializable
data class CacheRecord(
    val words: List<CacheWord>,
    val seconds: Double,
    val characters: Int,
    val text: String? = null,
    val tag: String? = null,
)

/** A stored piece: the MP3, its timings, and where in it the requested text begins. */
data class Clip(val file: File, val record: CacheRecord, val fromCache: Boolean, val startSeconds: Double = 0.0,
                val words: List<CacheWord> = record.words)

data class CacheStats(val paragraphs: Int, val bytes: Long, val seconds: Double)

/**
 * noBackupFilesDir/cloud-voices: <sha256>.mp3 + <sha256>.json per piece. Not in cacheDir, which Android empties when
 * space runs low, because the point is to listen again offline (iOS keeps it in Application Support for the same
 * reason); not part of backups. The least recently heard pieces go when the limit is passed.
 */
class VoiceCache(context: Context) {
    val folder = File(context.noBackupFilesDir, "cloud-voices").also { it.mkdirs() }
    private val index = HashMap<String, MutableList<Pair<String, String>>>()      // tag → (text, key)
    private var indexed = false

    fun key(voice: String, model: String, quality: String, text: String): String =
        MessageDigest.getInstance("SHA-256").digest("$voice|$model|$quality|$text".toByteArray())
            .joinToString("") { "%02x".format(it) }

    @Synchronized
    fun find(k: String): Clip? {
        val mp3 = File(folder, "$k.mp3")
        val js = File(folder, "$k.json")
        if (!mp3.exists()) return null
        val record = runCatching { AppJson.decodeFromString(CacheRecord.serializer(), js.readText()) }.getOrNull() ?: return null
        mp3.setLastModified(System.currentTimeMillis())         // recently heard
        return Clip(mp3, record, true)
    }

    /**
     * A stored piece of the same voice whose text ends with `text` at a word start: a reading resumed in the middle
     * of a paragraph plays the end of the stored piece instead of paying for it again.
     */
    @Synchronized
    fun findEnding(tag: String, text: String): Clip? {
        if (!indexed) buildIndex()
        for ((t, k) in index[tag].orEmpty()) {
            if (t.length <= text.length || !t.endsWith(text)) continue
            val clip = find(k) ?: continue
            val delta = t.length - text.length
            val first = clip.record.words.firstOrNull { it.location == delta } ?: continue
            val words = clip.record.words.filter { it.location >= delta }.map { it.copy(location = it.location - delta) }
            return clip.copy(startSeconds = maxOf(0.0, first.seconds - 0.01), words = words)
        }
        return null
    }

    private fun buildIndex() {
        indexed = true
        folder.listFiles { f -> f.extension == "json" }?.forEach { f ->
            val r = runCatching { AppJson.decodeFromString(CacheRecord.serializer(), f.readText()) }.getOrNull() ?: return@forEach
            if (r.text != null && r.tag != null) index.getOrPut(r.tag) { mutableListOf() }.add(r.text to f.nameWithoutExtension)
        }
    }

    /** `timing`: for providers without exact word timings, the words from the audio's measured length (seconds). */
    @Synchronized
    fun write(k: String, audio: ByteArray, record: CacheRecord, limit: Long, timing: ((Double) -> List<CacheWord>)? = null): Clip {
        val mp3 = File(folder, "$k.mp3")
        val js = File(folder, "$k.json")
        mp3.writeBytes(audio)
        var r = record
        val seconds = duration(mp3)
        if (timing != null) {
            if (seconds <= 0) { mp3.delete(); throw CloudException(CloudErrors.undecodable) }
            r = r.copy(seconds = seconds, words = timing(seconds))
        } else if (r.seconds <= 0 && seconds > 0) r = r.copy(seconds = seconds)
        js.writeText(AppJson.encodeToString(CacheRecord.serializer(), r))
        val t = r.text
        val g = r.tag
        if (indexed && t != null && g != null) index.getOrPut(g) { mutableListOf() }.add(t to k)
        prune(limit, keep = k)
        return Clip(mp3, r, false)
    }

    private fun duration(f: File): Double = runCatching {
        val m = MediaMetadataRetriever()
        try { m.setDataSource(f.path); (m.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLong() ?: 0L) / 1000.0 }
        finally { m.release() }
    }.getOrDefault(0.0)

    /** Over the limit: delete the pieces heard longest ago (never the one just written). */
    @Synchronized
    fun prune(limit: Long, keep: String? = null) {
        val files = folder.listFiles() ?: return
        var total = files.sumOf { it.length() }
        if (total <= limit) return
        for (mp3 in files.filter { it.extension == "mp3" }.sortedBy { it.lastModified() }) {
            val name = mp3.nameWithoutExtension
            if (name == keep) continue
            val js = File(folder, "$name.json")
            total -= mp3.length() + js.length()
            mp3.delete(); js.delete()
            index.values.forEach { l -> l.removeAll { it.second == name } }
            if (total <= limit) break
        }
    }

    @Synchronized
    fun stats(): CacheStats {
        val files = folder.listFiles() ?: return CacheStats(0, 0, 0.0)
        var seconds = 0.0
        var n = 0
        for (f in files) if (f.extension == "json") {
            runCatching { AppJson.decodeFromString(CacheRecord.serializer(), f.readText()) }.getOrNull()?.let { seconds += it.seconds; n++ }
        }
        return CacheStats(n, files.sumOf { it.length() }, seconds)
    }

    @Synchronized
    fun clear() {
        folder.listFiles()?.forEach { it.delete() }
        index.clear()
    }
}

// MARK: the model: keys, voices, credits, synthesis

/**
 * Everything the cloud voices know. Keys, the chosen voices and the ElevenLabs model live in [Settings]; the rest
 * (quality, cache limit, counters, fetched voice lists, monthly usage) in its own preferences file with the iOS keys.
 */
class CloudVoices private constructor(context: Context, val settings: Settings) {
    private val main = Handler(Looper.getMainLooper())
    private val d: SharedPreferences = context.getSharedPreferences("wisepath.cloud", Context.MODE_PRIVATE)
    val cache = VoiceCache(context)

    // ElevenLabs
    var elevenVoiceName by mutableStateOf(d.getString("a.eleven.voiceName", "") ?: "")
        private set
    var quality by mutableStateOf(ElevenQuality.of(d.getString("a.eleven.quality", null)))
        private set
    var limitMB by mutableIntStateOf(d.getInt("a.eleven.limitMB", 500))
        private set
    var elevenVoices by mutableStateOf(readList("a.eleven.voices", ElevenVoice.serializer()))
        private set
    var subscription by mutableStateOf<ElevenSubscription?>(null)
        private set
    var elevenStatus by mutableStateOf<String?>(null)
    var cachedCharacters by mutableIntStateOf(d.getInt("a.eleven.cachedChars", 0))
        private set
    var networkCharacters by mutableIntStateOf(d.getInt("a.eleven.networkChars", 0))
        private set
    var stats by mutableStateOf<CacheStats?>(null)
        private set

    // Google, Azure, OpenAI
    var stayFree by mutableStateOf(d.getBoolean("a.cloud.stayFree", true))
        private set
    var cloudVoices by mutableStateOf(readList("a.cloud.voices.${provider.name}", CloudVoiceInfo.serializer()))
        private set
    var cloudStatus by mutableStateOf<String?>(null)
    var usedThisMonth by mutableIntStateOf(0)
        private set

    /** The last piece a cloud voice could not make (read by the phone's voice instead); null when all is well. */
    var problem by mutableStateOf<String?>(null)

    init { usedThisMonth = d.getInt(usageKey(provider, voiceOf(provider)), 0) }

    private fun <T> readList(key: String, s: kotlinx.serialization.KSerializer<T>): List<T> =
        d.getString(key, null)?.let { runCatching { AppJson.decodeFromString(ListSerializer(s), it) }.getOrNull() } ?: emptyList()
    private fun <T> writeList(key: String, s: kotlinx.serialization.KSerializer<T>, v: List<T>) =
        d.edit().putString(key, AppJson.encodeToString(ListSerializer(s), v)).apply()

    private fun ui(block: () -> Unit) { if (Looper.myLooper() == Looper.getMainLooper()) block() else main.post(block) }

    val cacheLimitBytes: Long get() = limitMB * 1_000_000L

    // MARK: ElevenLabs settings

    val elevenHasKey get() = settings.elevenKey.isNotBlank()
    val elevenReady get() = elevenHasKey && settings.elevenVoice.isNotEmpty()
    val elevenModel get() = ElevenModel.of(settings.elevenModel)
    val elevenDisplayName get() = if (elevenVoiceName.isEmpty()) "ElevenLabs" else "ElevenLabs · $elevenVoiceName"

    fun setElevenModel(m: ElevenModel) { settings.elevenModel = m.id }
    fun chooseQuality(q: ElevenQuality) { quality = q; d.edit().putString("a.eleven.quality", q.id).apply() }
    fun setLimit(mb: Int) {
        limitMB = mb; d.edit().putInt("a.eleven.limitMB", mb).apply()
        Thread { cache.prune(cacheLimitBytes); refreshStatsBlocking() }.start()
    }

    fun saveElevenKey(raw: String) {
        val k = raw.trim()
        if (k.isEmpty()) return
        settings.elevenKey = k
        elevenStatus = "Anahtar bu cihazda kaydedildi."
    }

    fun deleteElevenKey() {
        settings.elevenKey = ""
        elevenVoices = emptyList(); subscription = null
        writeList("a.eleven.voices", ElevenVoice.serializer(), emptyList())
        elevenStatus = "Anahtar silindi."
    }

    /** Called from the screens' coroutines on an IO dispatcher. Checks the key, the voices and the credits. */
    fun testEleven() {
        val k = settings.elevenKey.trim()
        if (k.isEmpty()) { ui { elevenStatus = CloudErrors.noKey }; return }
        ui { elevenStatus = "Bağlanıyor…" }
        val voices = try { fetchElevenVoices(k) } catch (e: Exception) { ui { elevenStatus = e.message }; return }
        ui {
            elevenVoices = voices
            writeList("a.eleven.voices", ElevenVoice.serializer(), voices)
            if (settings.elevenVoice.isEmpty()) voices.firstOrNull()?.let { chooseEleven(it.id) }
            else voices.firstOrNull { it.id == settings.elevenVoice }?.let { setElevenName(it.name) }
            elevenStatus = "Bağlantı tamam · ${voices.size} ses"
        }
        try {
            val s = fetchSubscription(k)
            ui { subscription = s }
        } catch (e: Exception) {
            ui { subscription = null; elevenStatus = (elevenStatus ?: "") + " · kota okunamadı (anahtarın User okuma izni kapalı olabilir)" }
        }
    }

    private fun setElevenName(n: String) { elevenVoiceName = n; d.edit().putString("a.eleven.voiceName", n).apply() }

    /** A new ElevenLabs voice: the reader's choices that used the old one follow it. */
    var onVoiceReplaced: ((String, String) -> Unit)? = null

    fun chooseEleven(id: String) {
        val old = settings.elevenVoice
        elevenVoices.firstOrNull { it.id == id }?.let { setElevenName(it.name) }
        settings.elevenVoice = id
        if (old.isNotEmpty() && old != id) onVoiceReplaced?.invoke("eleven:$old", "eleven:$id")
    }

    private fun fetchElevenVoices(k: String): List<ElevenVoice> {
        val j = AppJson.parseToJsonElement(String(Http.send("$ELEVEN/v1/voices", headers = mapOf("xi-api-key" to k)))).jsonObject
        return j["voices"]?.jsonArray.orEmpty().mapNotNull { v ->
            val o = v.jsonObject
            val id = o["voice_id"]?.jsonPrimitive?.content ?: return@mapNotNull null
            ElevenVoice(id, o["name"]?.jsonPrimitive?.content ?: id, (o["category"] as? JsonPrimitive)?.content ?: "")
        }.sortedWith { a, b -> collator.compare(a.name, b.name) }
    }

    private fun fetchSubscription(k: String): ElevenSubscription {
        val o = AppJson.parseToJsonElement(String(Http.send("$ELEVEN/v1/user/subscription", headers = mapOf("xi-api-key" to k)))).jsonObject
        return ElevenSubscription(
            (o["tier"] as? JsonPrimitive)?.content ?: "?", o["character_count"]!!.jsonPrimitive.int, o["character_limit"]!!.jsonPrimitive.int,
            (o["next_character_count_reset_unix"] as? JsonPrimitive)?.doubleOrNull?.let { (it * 1000).toLong() },
        )
    }

    // MARK: ElevenLabs synthesis

    /**
     * One piece: from the cache when it was heard before with the same voice, model and quality; otherwise from the
     * server, stored for next time. Blocking; call off the main thread.
     */
    fun synthesizeEleven(voice: String, text: String, language: String): Clip {
        val k = settings.elevenKey.trim().ifEmpty { throw CloudException(CloudErrors.noKey) }
        if (voice.isEmpty()) throw CloudException(CloudErrors.noVoice)
        val mdl = elevenModel
        val q = quality
        // Kararlı ölçü asks the model itself for a steady reading (high stability, no style); such a piece is stored
        // under its own key. A piece already stored the plain way is used as it is (no credits again).
        val steady = settings.steadyCloud
        val plainKey = cache.key(voice, mdl.id, q.id, text)
        val ck = if (steady) cache.key(voice, mdl.id + "|steady", q.id, text) else plainKey
        val tag = "eleven|$voice|${mdl.id}${if (steady) "|steady" else ""}|${q.id}"
        (cache.find(ck) ?: cache.find(plainKey) ?: cache.findEnding(tag, text))?.let { count(cached = text.length); return it }

        val lang = language.substringBefore('-').lowercase().ifEmpty { "tr" }
        fun body(withSettings: Boolean) = buildJsonObject {
            put("text", text)
            put("model_id", mdl.id)
            if (mdl.forcesLanguage) put("language_code", lang)
            if (withSettings) putJsonObject("voice_settings") {
                put("stability", 0.9); put("similarity_boost", 0.8); put("style", 0.0); put("use_speaker_boost", true)
            }
        }.toString().toByteArray()
        val url = "$ELEVEN/v1/text-to-speech/${Http.enc(voice)}/with-timestamps?output_format=${q.id}"
        val headers = mapOf("xi-api-key" to k, "Content-Type" to "application/json")
        val data = if (steady) {
            try { Http.send(url, "POST", headers, body(true)) }
            catch (e: ServerException) {
                // the server would not take these settings for this voice or model: the plain request
                if (e.code in 400..499 && e.code != 401 && e.code != 429) Http.send(url, "POST", headers, body(false)) else throw e
            }
        } else Http.send(url, "POST", headers, body(false))
        val a = AppJson.parseToJsonElement(String(data)).jsonObject
        val mp3 = runCatching { Base64.getDecoder().decode(a["audio_base64"]!!.jsonPrimitive.content) }.getOrNull()
        if (mp3 == null || mp3.isEmpty()) throw CloudException(CloudErrors.undecodable)
        val clip = cache.write(ck, mp3, record(text, a["alignment"] as? JsonObject).copy(text = text, tag = tag), cacheLimitBytes)
        count(network = text.length)
        return clip
    }

    private fun count(cached: Int = 0, network: Int = 0) = ui {
        cachedCharacters += cached; networkCharacters += network
        d.edit().putInt("a.eleven.cachedChars", cachedCharacters).putInt("a.eleven.networkChars", networkCharacters).apply()
    }

    fun refreshStatsBlocking() { val s = cache.stats(); ui { stats = s } }

    fun clearCacheBlocking() {
        cache.clear()
        ui {
            cachedCharacters = 0; networkCharacters = 0
            d.edit().putInt("a.eleven.cachedChars", 0).putInt("a.eleven.networkChars", 0).apply()
        }
        refreshStatsBlocking()
    }

    // MARK: Google, Azure, OpenAI settings

    val provider: CloudProvider get() = CloudProvider.of(settings.cloudProvider)

    fun keyOf(p: CloudProvider) = when (p) {
        CloudProvider.google -> settings.googleKey
        CloudProvider.azure -> settings.azureKey
        CloudProvider.openai -> settings.openAIKey
    }.trim()

    fun voiceOf(p: CloudProvider) = when (p) {
        CloudProvider.google -> settings.googleVoice
        CloudProvider.azure -> settings.azureVoice
        CloudProvider.openai -> settings.openAIVoice
    }

    fun voiceNameOf(p: CloudProvider): String = d.getString("a.cloud.voiceName.${p.name}", null) ?: voiceOf(p).replace("tr-TR-", "")

    val cloudHasKey get() = keyOf(provider).isNotEmpty()
    fun cloudReady(p: CloudProvider = provider) = keyOf(p).isNotEmpty() && voiceOf(p).isNotEmpty() &&
        (p != CloudProvider.azure || settings.azureRegion.isNotBlank())
    fun cloudDisplayName(p: CloudProvider = provider) = voiceNameOf(p).let { if (it.isEmpty()) p.label else "${p.label} · $it" }

    fun setProvider(p: CloudProvider) {
        settings.cloudProvider = p.name
        cloudVoices = readList("a.cloud.voices.${p.name}", CloudVoiceInfo.serializer())
        usedThisMonth = d.getInt(usageKey(p, voiceOf(p)), 0)
        cloudStatus = null
    }

    fun changeStayFree(v: Boolean) { stayFree = v; d.edit().putBoolean("a.cloud.stayFree", v).apply() }

    fun saveCloudKey(raw: String) {
        val k = raw.trim()
        if (k.isEmpty()) return
        when (provider) {
            CloudProvider.google -> settings.googleKey = k
            CloudProvider.azure -> settings.azureKey = k
            CloudProvider.openai -> settings.openAIKey = k
        }
        cloudStatus = "Anahtar bu cihazda kaydedildi."
    }

    fun deleteCloudKey() {
        when (provider) {
            CloudProvider.google -> settings.googleKey = ""
            CloudProvider.azure -> settings.azureKey = ""
            CloudProvider.openai -> settings.openAIKey = ""
        }
        cloudVoices = emptyList()
        writeList("a.cloud.voices.${provider.name}", CloudVoiceInfo.serializer(), emptyList())
        cloudStatus = "Anahtar silindi."
    }

    fun chooseCloud(id: String) {
        val p = provider
        val old = voiceOf(p)
        val name = cloudVoices.firstOrNull { it.id == id }?.name ?: id
        d.edit().putString("a.cloud.voiceName.${p.name}", name).apply()
        when (p) {
            CloudProvider.google -> settings.googleVoice = id
            CloudProvider.azure -> settings.azureVoice = id
            CloudProvider.openai -> settings.openAIVoice = id
        }
        usedThisMonth = d.getInt(usageKey(p, id), 0)
        if (old.isNotEmpty() && old != id) onVoiceReplaced?.invoke("cloud:${p.name}:$old", "cloud:${p.name}:$id")
    }

    fun testCloud() {
        val p = provider
        val k = keyOf(p)
        if (k.isEmpty()) { ui { cloudStatus = CloudErrors.noKey }; return }
        ui { cloudStatus = "Bağlanıyor…" }
        try {
            val voices = fetchCloudVoices(p, k)
            ui {
                if (provider != p) return@ui
                cloudVoices = voices
                writeList("a.cloud.voices.${p.name}", CloudVoiceInfo.serializer(), voices)
                if (voiceOf(p).isEmpty() || voices.none { it.id == voiceOf(p) }) voices.firstOrNull()?.let { chooseCloud(it.id) }
                cloudStatus = "Bağlantı tamam · ${voices.size} ses"
            }
        } catch (e: Exception) { ui { cloudStatus = e.message } }
    }

    private fun fetchCloudVoices(p: CloudProvider, k: String): List<CloudVoiceInfo> = when (p) {
        CloudProvider.google -> {
            val o = AppJson.parseToJsonElement(String(Http.send("https://texttospeech.googleapis.com/v1/voices?languageCode=tr-TR&key=${Http.enc(k)}"))).jsonObject
            val rank = listOf("chirp3-hd" to 0, "wavenet" to 1, "neural2" to 2, "standard" to 3)
            fun r(id: String) = rank.firstOrNull { id.lowercase().contains(it.first) }?.second ?: 9
            o["voices"]?.jsonArray.orEmpty().map { v ->
                val name = v.jsonObject["name"]!!.jsonPrimitive.content
                val g = (v.jsonObject["ssmlGender"] as? JsonPrimitive)?.content
                val family = name.split("-").drop(2).dropLast(1).joinToString("-").lowercase()
                val price = if (family.contains("chirp")) "en doğal · ayda 1 M ücretsiz"
                    else if (family.contains("wavenet") || family.contains("standard")) "ayda 4 M ücretsiz" else "ayda 1 M ücretsiz"
                val gender = if (g == "FEMALE") "Kadın" else if (g == "MALE") "Erkek" else ""
                CloudVoiceInfo(name, name.replace("tr-TR-", ""), listOf(gender, price).filter { it.isNotEmpty() }.joinToString(" · "))
            }.sortedWith(compareBy<CloudVoiceInfo> { r(it.id) }.thenBy { it.id })
        }
        CloudProvider.azure -> {
            val all = AppJson.parseToJsonElement(String(Http.send(azureURL(settings.azureRegion, "cognitiveservices/voices/list"),
                headers = mapOf("Ocp-Apim-Subscription-Key" to k)))).jsonArray
            all.map { it.jsonObject }.filter {
                val loc = it["Locale"]?.jsonPrimitive?.content
                loc == "tr-TR" || it["ShortName"]?.jsonPrimitive?.content?.contains("Multilingual") == true
            }.map { o ->
                val short = o["ShortName"]!!.jsonPrimitive.content
                val g = (o["Gender"] as? JsonPrimitive)?.content
                val tr = o["Locale"]?.jsonPrimitive?.content == "tr-TR"
                CloudVoiceInfo(short, (o["LocalName"] as? JsonPrimitive)?.content ?: short,
                    listOfNotNull(if (g == "Female") "Kadın" else if (g == "Male") "Erkek" else null, if (tr) "Türkçe" else "çok dilli").joinToString(" · "))
            }.sortedWith(compareBy<CloudVoiceInfo> { if (it.detail.contains("Türkçe")) 0 else 1 }.thenBy { it.name })
        }
        // OpenAI has no voice list endpoint; its voices speak every language
        CloudProvider.openai -> listOf("alloy", "ash", "ballad", "coral", "echo", "fable", "nova", "onyx", "sage", "shimmer", "verse")
            .map { CloudVoiceInfo(it, it.replaceFirstChar { c -> c.uppercase() }, "çok dilli") }
    }

    // MARK: free allowance

    /** Free characters a month for a voice; 0 when there is none. */
    fun freeAllowance(p: CloudProvider = provider, voice: String = voiceOf(p)): Int = when (p) {
        CloudProvider.google -> voice.lowercase().let { v -> if (v.contains("chirp") || v.contains("neural2") || v.contains("studio")) 1_000_000 else 4_000_000 }
        CloudProvider.azure -> 500_000
        CloudProvider.openai -> 0
    }

    /** Google counts each voice family on its own; the others count everything together. */
    private fun usageKey(p: CloudProvider, voice: String): String {
        val month = YearMonth.now().toString()                        // yyyy-MM
        val tier = if (p == CloudProvider.google) {
            val v = voice.lowercase()
            "." + (listOf("chirp", "neural2", "studio", "wavenet", "standard").firstOrNull { v.contains(it) } ?: "other")
        } else ""
        return "a.cloud.usage.${p.name}$tier.$month"
    }

    @Synchronized
    private fun countCloud(p: CloudProvider, voice: String, n: Int) {
        val key = usageKey(p, voice)
        val v = d.getInt(key, 0) + n
        d.edit().putInt(key, v).apply()
        ui { if (provider == p && voiceOf(p) == voice) usedThisMonth = v }
    }

    // MARK: Google, Azure, OpenAI synthesis

    /** One piece, from the cache or the provider. Blocking; call off the main thread. */
    fun synthesizeCloud(p: CloudProvider, voice: String, text: String, language: String): Clip {
        val k = keyOf(p).ifEmpty { throw CloudException(CloudErrors.noKey) }
        if (voice.isEmpty()) throw CloudException(CloudErrors.noVoice)
        val ck = cache.key("${p.name}:$voice", "", "", text)
        val tag = "cloud|${p.name}|$voice"
        (cache.find(ck) ?: cache.findEnding(tag, text))?.let { return it }
        val n = text.length
        val free = freeAllowance(p, voice)
        if (stayFree && d.getInt(usageKey(p, voice), 0) + n > free) {
            throw CloudException(if (p == CloudProvider.openai) "OpenAI'nin ücretsiz kotası yok; \"Ücretsiz kotada kal\" kapalı olmalı."
                else "Bu ayın ücretsiz kotası doldu (${NumberFormat.getIntegerInstance(Locale("tr")).format(free)} karakter).")
        }
        val (audio, marks) = fetch(text, p, voice, k, settings.azureRegion, language)
        countCloud(p, voice, n)
        return cache.write(ck, audio, CacheRecord(emptyList(), 0.0, text.length, text, tag), cacheLimitBytes) { seconds -> words(text, marks, seconds) }
    }

    /** "tr" → "tr-TR"; a full tag stays. */
    private fun locale(language: String): String = when {
        language.contains('-') -> language
        language == "en" -> "en-US"
        language.isEmpty() -> "tr-TR"
        else -> "$language-${language.uppercase()}"
    }

    /** Audio (MP3) and, when the provider gives them, the start of every word in seconds. */
    private fun fetch(text: String, p: CloudProvider, voice: String, key: String, region: String, language: String): Pair<ByteArray, List<Double>?> =
        when (p) {
            CloudProvider.google -> {
                val chirp = voice.lowercase().contains("chirp")
                val (ssml, count) = if (chirp) "" to 0 else marked(text)
                val useMarks = !chirp && ssml.toByteArray().size < 4800
                val langCode = voice.split("-").take(2).joinToString("-").ifEmpty { "tr-TR" }
                val body = buildJsonObject {
                    putJsonObject("voice") { put("languageCode", langCode); put("name", voice) }
                    putJsonObject("audioConfig") { put("audioEncoding", "MP3"); put("sampleRateHertz", 24000) }
                    putJsonObject("input") { if (useMarks) put("ssml", ssml) else put("text", text) }
                    if (useMarks) put("enableTimePointing", JsonArray(listOf(JsonPrimitive("SSML_MARK"))))
                }
                val a = AppJson.parseToJsonElement(String(Http.send("https://texttospeech.googleapis.com/v1beta1/text:synthesize?key=${Http.enc(key)}",
                    "POST", mapOf("Content-Type" to "application/json"), body.toString().toByteArray()))).jsonObject
                val mp3 = runCatching { Base64.getDecoder().decode(a["audioContent"]!!.jsonPrimitive.content) }.getOrNull()
                    ?: throw CloudException(CloudErrors.undecodable)
                var starts: List<Double>? = null
                val t = (a["timepoints"] as? JsonArray)?.map { it.jsonObject }
                if (useMarks && t != null && t.size == count) {
                    starts = t.sortedBy { it["markName"]!!.jsonPrimitive.content.drop(1).toIntOrNull() ?: 0 }
                        .map { it["timeSeconds"]!!.jsonPrimitive.double }
                }
                mp3 to starts
            }
            CloudProvider.azure -> {
                val lang = locale(language)
                val ssml = "<speak version='1.0' xml:lang='$lang'><voice name='$voice'><lang xml:lang='$lang'>${escape(text)}</lang></voice></speak>"
                Http.send(azureURL(region, "cognitiveservices/v1"), "POST", mapOf(
                    "Ocp-Apim-Subscription-Key" to key, "Content-Type" to "application/ssml+xml",
                    "X-Microsoft-OutputFormat" to "audio-24khz-48kbitrate-mono-mp3", "User-Agent" to "WisePath",
                ), ssml.toByteArray()) to null
            }
            CloudProvider.openai -> {
                val body = buildJsonObject {
                    put("model", "gpt-4o-mini-tts"); put("voice", voice); put("input", text); put("response_format", "mp3")
                    put("instructions", "Metni Türkçe, sakin ve kararlı bir anlatıcı gibi oku: ses yüksekliği ve hız baştan sona aynı kalsın, tonlama dar olsun, duygu ve abartılı vurgu katma, her cümlenin sonunda sesi belirgin biçimde indir, nefes ve uzun duraklama ekleme.")
                }
                Http.send("https://api.openai.com/v1/audio/speech", "POST",
                    mapOf("Authorization" to "Bearer $key", "Content-Type" to "application/json"), body.toString().toByteArray(), 60_000) to null
            }
        }

    /** The Azure address for a region the user typed; a region that does not make a host name is an error to show. */
    private fun azureURL(region: String, path: String): String {
        val host = region.trim().lowercase()
        if (host.isEmpty() || !host.all { it in 'a'..'z' || it in '0'..'9' || it == '-' }) throw CloudException("Azure bölgesi geçersiz: “$region”. Örnek: westeurope.")
        return "https://$host.tts.speech.microsoft.com/$path"
    }

    // MARK: the reader's voice list

    /** The cloud voices as the voice page lists them: the chosen ElevenLabs voice and each service's chosen voice. */
    fun voiceInfos(): List<VoiceInfo> {
        val out = mutableListOf<VoiceInfo>()
        if (elevenHasKey && settings.elevenVoice.isNotEmpty()) {
            out += VoiceInfo("eleven:${settings.elevenVoice}", elevenDisplayName, "tr", "tr-TR", 500, network = true, installed = true)
        }
        for (p in CloudProvider.entries) if (cloudReady(p)) {
            val v = voiceOf(p)
            val loc = if (p == CloudProvider.openai) "tr-TR" else v.split("-").take(2).joinToString("-")
            out += VoiceInfo("cloud:${p.name}:$v", cloudDisplayName(p), loc.substringBefore('-'), loc, 400, network = true, installed = true)
        }
        return out
    }

    companion object {
        private const val ELEVEN = "https://api.elevenlabs.io"
        private val collator = java.text.Collator.getInstance(Locale("tr", "TR"))
        const val SAMPLE = "Merhaba. Kitaplarını bu sesle, istediğin hızda okuyabilirim."

        @Volatile private var instance: CloudVoices? = null
        fun get(app: AppModel): CloudVoices = instance ?: synchronized(this) {
            instance ?: CloudVoices(app.context, app.settings).also { instance = it }
        }

        /** The paragraph as SSML with a mark before every word (w0, w1…), and the number of words. */
        fun marked(text: String): Pair<String, Int> {
            val out = StringBuilder("<speak>")
            var n = 0
            val word = StringBuilder()
            var inWord = false
            for (ch in text) {
                if (ch.isWhitespace()) {
                    if (inWord) { out.append(escape(word.toString())); word.clear(); inWord = false }
                    out.append(ch)
                } else {
                    if (!inWord) { out.append("<mark name=\"w$n\"/>"); n++; inWord = true }
                    word.append(ch)
                }
            }
            if (inWord) out.append(escape(word.toString()))
            return out.append("</speak>").toString() to n
        }

        fun escape(s: String) = s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;").replace("'", "&apos;")

        /**
         * Word ranges with their start times: from the provider's marks, or spread over the audio by the length of each
         * word (a pause after , ; : . counts as a few letters more).
         */
        fun words(text: String, marks: List<Double>?, seconds: Double): List<CacheWord> {
            val ranges = mutableListOf<Triple<Int, Int, Int>>()
            var i = 0
            while (i < text.length) {
                while (i < text.length && text[i].isWhitespace()) i++
                val start = i
                while (i < text.length && !text[i].isWhitespace()) i++
                if (i > start) {
                    val last = text[i - 1]
                    val pause = if (last in ".!?…") 6 else if (last in ",;:") 3 else 0
                    ranges += Triple(start, i - start, i - start + 1 + pause)
                }
            }
            if (marks != null && marks.size == ranges.size) return ranges.zip(marks) { r, m -> CacheWord(r.first, r.second, m) }
            val total = maxOf(1, ranges.sumOf { it.third }).toDouble()
            val lead = minOf(0.15, seconds * 0.02)
            val span = maxOf(0.0, seconds - lead * 2)
            var at = 0
            return ranges.map { r -> CacheWord(r.first, r.second, lead + span * at / total).also { at += r.third } }
        }

        /** ElevenLabs' character timings → word timings. The characters must spell the text exactly, else no words. */
        fun record(text: String, a: JsonObject?): CacheRecord {
            val chars = a?.get("characters")?.jsonArray?.map { it.jsonPrimitive.content }
            val starts = a?.get("character_start_times_seconds")?.jsonArray?.map { it.jsonPrimitive.double }
            val ends = a?.get("character_end_times_seconds")?.jsonArray?.map { it.jsonPrimitive.double }
            val endSec = ends?.lastOrNull() ?: 0.0
            if (chars == null || starts == null || chars.size != starts.size || chars.joinToString("") != text) {
                return CacheRecord(emptyList(), endSec, text.length)
            }
            val words = mutableListOf<CacheWord>()
            var at = 0
            var start: Pair<Int, Double>? = null
            for ((i, c) in chars.withIndex()) {
                if (c.all { it.isWhitespace() }) {
                    start?.let { words += CacheWord(it.first, at - it.first, it.second) }
                    start = null
                } else if (start == null) start = at to starts[i]
                at += c.length
            }
            start?.let { words += CacheWord(it.first, at - it.first, it.second) }
            return CacheRecord(words, endSec, text.length)
        }
    }
}

