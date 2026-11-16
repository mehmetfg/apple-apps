// Reading and listening preferences (port of Model/Settings.swift), kept in SharedPreferences with the iOS keys.
// Grouped like Voice Dream's two panels: Görsel Ayarlar (text, colours, highlighting, scrolling) and Ses Ayarları
// (speed, voice, advanced). Every property is Compose state, so a screen that reads one redraws when it changes.
package com.fatihgocgun.wisepath.settings

import android.content.Context
import android.content.SharedPreferences
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontFamily
import com.fatihgocgun.wisepath.model.AppJson
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

enum class NavigationUnit(val label: String) {
    sentence("Cümle"), paragraph("Paragraf"), page("Sayfa"), chapter("Bölüm"),
    bookmark("Yer imi"), highlight("İşaret"), seconds15("15 saniye"), seconds30("30 saniye");
}

/** How reading sits with music from another app: off stops the music; otherwise it plays under the voice. */
enum class MusicMix(val label: String) {
    off("Kapalı (müziği durdurur)"), duck("Müzik arka planda"), mix("Müzik arka planda");
    companion object { val shown = listOf(off, mix) }
}

enum class EndBehavior(val label: String) {
    stopAtEnd("Belgenin sonunda dur"), keepGoing("Sonraki bitmemiş belgeye geç");
}

enum class ReaderTheme(val label: String, val background: Color, val text: Color, val chrome: Color, val band: Color, val hairline: Color) {
    light("Açık", Color(0xFFF0F0F0), Color(0xFF0F0F0F), Color(0xFFF6F6F6), Color.White, Color(0xFFA0A0A0)),
    sepia("Sepya", Color(0xFFF3E9D2), Color(0xFF413022), Color(0xFFECE0C6), Color(0xFFFCF6E5), Color(0xFFC7B896)),
    dark("Koyu", Color(0xFF1C1C1E), Color(0xFFE0E0E0), Color(0xFF262628), Color(0xFF343437), Color(0x2EFFFFFF)),
    black("Siyah", Color.Black, Color(0xFFE0E0E0), Color(0xFF0E0E0E), Color(0xFF212121), Color(0x2EFFFFFF));
    val isDark get() = this == dark || this == black
}

/** The iOS fonts by their stored names, drawn with the closest family Android ships. */
enum class ReaderFont(val label: String, val family: FontFamily) {
    system("Sistem (Roboto)", FontFamily.SansSerif),
    newYork("Serif (Noto Serif)", FontFamily.Serif),
    georgia("Georgia benzeri", FontFamily.Serif),
    charter("Charter benzeri", FontFamily.Serif),
    palatino("Palatino benzeri", FontFamily.Serif),
    avenir("Avenir benzeri", FontFamily.SansSerif),
    helvetica("Helvetica benzeri", FontFamily.SansSerif),
    verdana("Eşaralıklı", FontFamily.Monospace);
}

/** The colours offered for the spoken word, the spoken line and selections. */
enum class MarkColor(val label: String, val color: Color) {
    paper("Beyaz", Color.White), yellow("Sarı", Color(0xFFFFFF00)), orange("Turuncu", Color(0xFFFF9E40)),
    green("Yeşil", Color(0xFF66D973)), blue("Mavi", Color(0xFF2961F2)), purple("Mor", Color(0xFFB380FF)),
    pink("Pembe", Color(0xFFFF80B3)), gray("Gri", Color(0xFF999999));
}

enum class CursorPosition(val label: String, val fraction: Float) { top("Üstte", 0.25f), middle("Ortada", 0.45f) }

enum class SortOrder(val label: String) {
    lastOpened("Son açılan"), addDate("Eklenme tarihi"), title("Başlık"), author("Yazar"), duration("Süre"), progress("İlerleme");
}

/** Sayfa karartma: what happens to the page around the line being read. */
enum class PageDim(val label: String, val note: String) {
    off("Yok", "Sayfa olduğu gibi kalır."),
    fade("Soluk", "Okunan satır dışındaki yazı kâğıdın rengine doğru solar."),
    dark("Karart", "Sayfanın geri kalanı düz bir gölgeyle kararır."),
    spotlight("Spot ışığı", "Satırın çevresi aydınlık kalır, uzaklaştıkça koyulaşır; sahne ışığı gibi."),
    window("Pencere", "Okunan satırla bir üst ve bir alt satır açık kalır; geri kalanı solar."),
    dusk("Alacakaranlık", "Sayfanın geri kalanı sıcak, kehribar bir gölgeye bürünür; gece okumasına göre.");
}

enum class LibraryStyle(val label: String) {
    spines("Kitaplık"), flow("Akış"), shelf("Vitrin"), grid("Izgara"), wall("Kapak duvarı"), cards("Kartlar"),
    folders("Klasör rafları"), remaining("Kalan süre"), list("Liste"), compact("Sıkı liste");
}

enum class LibraryFilter(val label: String) {
    all("Tümü"), unread("Okunmamış"), inProgress("Devam eden"), finished("Biten"), flagged("Etiketli");
}

/** The moving modes: on a bicycle or on foot (the same screens, its own record). */
enum class MoveKind(val label: String) { bike("Bisiklet"), walk("Yürüyüş") }

/** The moving mode's screen. */
enum class BikeLook(val label: String) { focus("Yolda"), kinetic("Kinetik"), full("Tam metin"), classic("Klasik") }

/** The bicycle keys' colours. */
enum class BikeStyle(val label: String) { crystal("Kristal"), ocean("Okyanus"), ember("Kor"), forest("Orman"), mono("Siyah-beyaz") }

/** A voice's own pitch, volume and steadiness. */
@Serializable
data class VoiceTune(val pitch: Double = 1.0, val volume: Double = 1.0, val steady: Double = 0.0)

class Settings(context: Context) {
    private val p: SharedPreferences = context.getSharedPreferences("wisepath.settings", Context.MODE_PRIVATE)

    // MARK: delegates — Compose state that writes itself through

    private inner class Pref<T>(private val key: String, initial: T, private val write: SharedPreferences.Editor.(String, T) -> Unit) :
        ReadWriteProperty<Any?, T> {
        private var state by mutableStateOf(initial)
        override fun getValue(thisRef: Any?, property: KProperty<*>): T = state
        override fun setValue(thisRef: Any?, property: KProperty<*>, value: T) {
            state = value
            p.edit().apply { write(key, value) }.apply()
        }
    }

    private fun bool(key: String, def: Boolean) = Pref(key, p.getBoolean(key, def)) { k, v -> putBoolean(k, v) }
    private fun double(key: String, def: Double, range: ClosedFloatingPointRange<Double>? = null): Pref<Double> {
        var v = if (p.contains(key)) java.lang.Double.longBitsToDouble(p.getLong(key, 0)) else def
        if (range != null) v = v.coerceIn(range)
        return Pref(key, v) { k, x -> putLong(k, java.lang.Double.doubleToRawLongBits(x)) }
    }
    private fun int(key: String, def: Int) = Pref(key, p.getInt(key, def)) { k, v -> putInt(k, v) }
    private fun string(key: String, def: String) = Pref(key, p.getString(key, def) ?: def) { k, v -> putString(k, v) }
    private inline fun <reified E : Enum<E>> enum(key: String, def: E): Pref<E> {
        val stored = p.getString(key, null)
        val v = enumValues<E>().firstOrNull { it.name == stored } ?: def
        return Pref(key, v) { k, x -> putString(k, x.name) }
    }
    private fun stringMap(key: String) = Pref(key, readMap(key, String.serializer()) ?: emptyMap()) { k, v ->
        putString(k, AppJson.encodeToString(MapSerializer(String.serializer(), String.serializer()), v))
    }
    private fun doubleMap(key: String) = Pref(key, readMap(key, Double.serializer()) ?: emptyMap()) { k, v ->
        putString(k, AppJson.encodeToString(MapSerializer(String.serializer(), Double.serializer()), v))
    }
    private fun tuneMap(key: String) = Pref(key, readMap(key, VoiceTune.serializer()) ?: emptyMap()) { k, v ->
        putString(k, AppJson.encodeToString(MapSerializer(String.serializer(), VoiceTune.serializer()), v))
    }
    private fun <V> readMap(key: String, value: kotlinx.serialization.KSerializer<V>): Map<String, V>? =
        p.getString(key, null)?.let { runCatching { AppJson.decodeFromString(MapSerializer(String.serializer(), value), it) }.getOrNull() }

    // MARK: visual

    var font by enum("v.font", ReaderFont.georgia)
    var fontSize by double("v.size", 20.0)
    var lineSpacing by double("v.line", 6.0)
    var characterSpacing by double("v.kern", 0.0)
    var theme by enum("v.theme2", ReaderTheme.light)
    var followSystem by bool("v.followSystem", false)
    /** The accent colour (hex, no #): bars, icons, progress, switches. */
    var accentHex by string("v.accent", "003D61")
    var showSpokenWord by bool("v.word", true)
    var showSpokenLine by bool("v.lineHL", true)
    var wordColor by enum("v.wordColor", MarkColor.yellow)
    var lineColor by enum("v.lineColor", MarkColor.paper)
    var cursorPosition by enum("v.cursor", CursorPosition.top)
    var focusMode by bool("v.focus", false)
    /** Mercek: a band over the line being read, the line a touch larger on it. */
    var wordLens by bool("v.lens", true)
    var lensScale by double("v.lensScale3", 1.0, 1.0..1.3)
    var pageDim by enum("v.pageDim", PageDim.off)
    var pageDimStrength by double("v.pageDimStrength", 0.5, 0.15..0.85)
    /** Minutes of listening aimed at each day. */
    var dailyGoal by int("s.dailyGoal", 60)
    var bikeMode by bool("v.bike", false)
    var moveKind by enum("v.moveKind", MoveKind.bike)
    /** Body weight in kg for the calories; 0 = not given yet. */
    var bodyWeight by double("v.weight", 0.0)
    var musicMic by bool("v.musicMic", true)
    var rideLight by string("v.rideLight", "night")
    var musicKinetic by bool("v.musicKinetic", true)
    var kineticMask by bool("v.kineticMask", false)
    var musicBackdrop by string("v.musicBackdrop", "circle")
    var bikeStyle by enum("v.bikeStyle", BikeStyle.crystal)
    var bikeLook by enum("v.bikeLook", BikeLook.focus)
    var musicContent by string("v.musicContent", "lines")
    var musicOnPause by bool("v.musicOnPause", true)
    var bookLayout by bool("v.book", true)

    // MARK: audio

    var speed by double("a.speed", 1.0)
    /** Language code → voice name (Android TextToSpeech Voice.name, or a cloud voice id). */
    var voiceByLanguage by stringMap("a.voices")
    var startAtSentence by bool("a.sentence", true)
    var simplifyLinks by bool("a.links", true)
    var skipCitations by bool("a.citations", true)
    var endBehavior by enum("a.end", EndBehavior.stopAtEnd)
    var navigationUnit by enum("a.unit", NavigationUnit.sentence)
    var pitch by double("a.pitch", 1.0)
    var mixedLanguage by bool("a.mixed", true)
    var musicMix by enum("a.music", MusicMix.off)
    var musicLevel by double("a.musicLevel", 40.0)
    var steadyCloud by bool("a.steadyCloud", true)
    var musicBreak by bool("a.break", false)
    var breakMinutes by double("a.breakMin", 5.0)
    var breakSeconds by double("a.breakSec", 30.0)
    /** Aktif bekleme: the headphone's ⏯ while reading waits and then goes on by itself. */
    var remotePauseWaits by bool("a.waitRemote", true)
    var waitSeconds by double("a.waitSec", 120.0)
    var voiceDepth by doubleMap("a.depth")
    var voiceTune by tuneMap("a.tune")
    /** Characters a second at 1× measured from the voice (for the time estimates). */
    var charsPerSecond by double("a.cps", 14.0)
    /** Android TTS engine package chosen for reading ("" = the system default). */
    var ttsEngine by string("a.engine", "")

    // MARK: library

    var sortOrder by enum("l.sort", SortOrder.lastOpened)
    var filter by enum("l.filter", LibraryFilter.all)
    var style by enum("l.style", LibraryStyle.shelf)
    var homeStyle by enum("l.homeStyle", LibraryStyle.spines)
    /** The home page's shelf: süren · okunacak · bitenler · all, or a folder's name. */
    var homeShelf by string("l.homeShelf", "all")
    var lastDocument by string("l.lastDocument", "")

    // MARK: sync (an Android folder that mirrors iCloud Drive › Voice Reader, chosen with the system picker)

    var syncFolderUri by string("sync.folder", "")
    var deviceName by string("sync.device", "android-" + android.os.Build.MODEL.replace(" ", "-").lowercase())

    // MARK: cloud voices (keys stay on the device)

    var elevenKey by string("cloud.elevenKey", "")
    var elevenVoice by string("cloud.elevenVoice", "")
    var elevenModel by string("cloud.elevenModel", "eleven_multilingual_v2")
    var cloudProvider by string("cloud.provider", "")          // "", "openai", "google", "azure"
    var openAIKey by string("cloud.openaiKey", "")
    var openAIVoice by string("cloud.openaiVoice", "alloy")
    var googleKey by string("cloud.googleKey", "")
    var googleVoice by string("cloud.googleVoice", "tr-TR-Wavenet-E")
    var azureKey by string("cloud.azureKey", "")
    var azureRegion by string("cloud.azureRegion", "westeurope")
    var azureVoice by string("cloud.azureVoice", "tr-TR-EmelNeural")

    fun tune(voice: String): VoiceTune = voiceTune[voice] ?: VoiceTune(pitch = pitch)
    fun setTune(voice: String, t: VoiceTune) { voiceTune = voiceTune + (voice to t) }

    /** The theme in effect: the phone's light/dark when following the system, else the chosen one. */
    fun effectiveTheme(systemDark: Boolean): ReaderTheme =
        if (followSystem) (if (systemDark) ReaderTheme.dark else ReaderTheme.light) else theme

    val accent: Color get() = parseHex(accentHex) ?: Color(0xFF003D61)

    fun restoreVisualDefaults() {
        font = ReaderFont.georgia; fontSize = 20.0; lineSpacing = 6.0; characterSpacing = 0.0
        theme = ReaderTheme.light; followSystem = false; accentHex = "003D61"
        showSpokenWord = true; showSpokenLine = true; wordColor = MarkColor.yellow; lineColor = MarkColor.paper
        cursorPosition = CursorPosition.top; focusMode = false; bookLayout = true; bikeStyle = BikeStyle.crystal
    }

    companion object {
        fun parseHex(hex: String): Color? = runCatching {
            Color(("FF" + hex.removePrefix("#").takeLast(6)).toLong(16))
        }.getOrNull()

        /** Named accents offered in Renk Ayarları. */
        val accents = listOf(
            "Lacivert" to "003D61", "Mavi" to "006FB4", "Petrol" to "00695C", "Orman" to "2E7D32",
            "Bordo" to "8E1B3A", "Mor" to "5B3FA0", "Turuncu" to "D9480F", "Grafit" to "37474F",
        )
    }
}
