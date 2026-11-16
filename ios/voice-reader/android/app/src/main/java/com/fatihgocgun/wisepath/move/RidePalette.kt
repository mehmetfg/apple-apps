// The road screen's colours (port of RideView.swift's Ride / RideLight / DayLight) and the concepts of each sentence
// (RideConcepts). Gece: OLED black, cream text, sunlight amber for what is heard, gold for marks. Gündüz: warm paper,
// ink text, a burnt orange and a deep gold that hold against daylight. Otomatik follows the screen's brightness.
package com.fatihgocgun.wisepath.move

import android.content.Context
import android.provider.Settings as SystemSettings
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import com.fatihgocgun.wisepath.AppModel
import kotlinx.coroutines.delay
import java.text.BreakIterator
import java.util.Locale
import kotlin.math.ln

class RideColors(val day: Boolean) {
    private fun pick(n: Triple<Double, Double, Double>, d: Triple<Double, Double, Double>): Color {
        val c = if (day) d else n
        return Color(c.first.toFloat(), c.second.toFloat(), c.third.toFloat())
    }
    private fun t(r: Double, g: Double, b: Double) = Triple(r, g, b)
    val oled = pick(t(0.0, 0.0, 0.0), t(0.965, 0.945, 0.905))
    val panel = pick(t(0.051, 0.047, 0.043), t(0.935, 0.912, 0.868))
    val raise = pick(t(0.090, 0.082, 0.075), t(0.905, 0.880, 0.832))
    val line = pick(t(0.165, 0.149, 0.133), t(0.800, 0.770, 0.710))
    val paper = pick(t(0.957, 0.925, 0.863), t(0.125, 0.105, 0.085))
    val muted = pick(t(0.553, 0.525, 0.482), t(0.400, 0.370, 0.330))
    val dim = pick(t(0.290, 0.271, 0.247), t(0.600, 0.570, 0.520))
    val amber = pick(t(0.941, 0.698, 0.290), t(0.780, 0.360, 0.030))
    val gold = pick(t(0.847, 0.698, 0.369), t(0.620, 0.430, 0.060))
    val alert = pick(t(0.886, 0.439, 0.353), t(0.760, 0.240, 0.160))
    val edge = pick(t(0.120, 0.110, 0.100), t(0.830, 0.800, 0.745))
    val well = pick(t(0.055, 0.051, 0.047), t(0.990, 0.978, 0.952))
    val track = pick(t(0.114, 0.106, 0.098), t(0.850, 0.820, 0.765))
    val onAmber = if (day) Color.White else Color.Black.copy(alpha = 0.85f)

    companion object {
        val serif = FontFamily.Serif
        val mono = FontFamily.Monospace
    }
}

val LocalRide = staticCompositionLocalOf { RideColors(false) }

/** The road screen's and the kinetic type's light: Gece, Gündüz, or by the screen's brightness. */
enum class RideLight(val label: String) {
    night("Gece"), day("Gündüz"), auto("Otomatik (ekran parlaklığına göre)");
    companion object { fun of(raw: String) = entries.firstOrNull { it.name == raw } ?: night }
}

/** The screen's brightness 0…1 (Android keeps 0…255; some phones more, then clipped). */
private fun brightness(context: Context): Float =
    runCatching { SystemSettings.System.getInt(context.contentResolver, SystemSettings.System.SCREEN_BRIGHTNESS) / 255f }
        .getOrDefault(0.5f).coerceIn(0f, 1f)

/** Day colours or night colours: as set, or (Otomatik) on above 75 % brightness and off under 55 %. */
@Composable
fun rememberRideDay(app: AppModel): Boolean {
    val light = RideLight.of(app.settings.rideLight)
    val context = LocalContext.current
    var bright by remember { mutableStateOf(brightness(context) >= 0.75f) }
    if (light == RideLight.auto) LaunchedEffect(Unit) {
        while (true) {
            val b = brightness(context)
            if (b >= 0.75f) bright = true else if (b <= 0.55f) bright = false
            delay(5000)
        }
    }
    return when (light) { RideLight.night -> false; RideLight.day -> true; RideLight.auto -> bright }
}

/**
 * The concept of each sentence: a content word that recurs in the book (grouped by its first five letters, so
 * "bilginin" and "bilgi" count together) or a proper noun. Worked out once per document, off the main thread.
 */
object RideConcepts {
    private val stop: Set<String> = """
        ve veya ile ama fakat ancak lakin çünkü için gibi kadar daha çok pek en bu şu o bir iki her hiç hiçbir ne neden nasıl niçin
        ki de da mi mı mu mü ise ya yani bile sadece yalnız artık hep hepsi olan olarak olur olup olduğu olduğunu oldu olmak olmuş olsa
        etmek eder ediyor etti değil değildir var yok ben sen biz siz onlar onun bunun şunun bunu şunu onu ona buna bana sana bize size
        kendi kendini kendine göre doğru sonra önce üzere iken diye beri karşı rağmen ayrıca hem hemen zaten belki tüm bütün bazı birçok
        birkaç böyle şöyle öyle burada orada şimdi bunlar şunlar onları bunları bunlara içinde üzerine üstünde altında arasında yine
        gene başka diğer aynı şekilde biraz bazen kimi kimse herkes herşey birşey nedir değildi gerek gerekir olabilir olmalı yapmak
        yapar yaptı demek dedi diyor sanki bütünüyle oysa halde şeyi şeyler şeylerin tarafından ilgili yalnızca aslında bunun şeyin
        olduğunu olduğu olarak olan olduğunda bizim sizin onların kendisi kendileri dolayı itibaren böylece ardından birlikte
        büyük küçük önemli yeni eski ilk uzun kısa bugün yalnızca neredeyse sonunda başında yerine tarafı zaman zamanda
        şöyle böylece çünkü hiçbir birinin birini birine ikinci üçüncü kelime kelimeyi kelimeler cümle soruyu sorusu
        the and of to in is that for with this from are was were have has but not
    """.split(Regex("\\s+")).filter { it.isNotEmpty() }.toSet()

    private val tr = Locale("tr", "TR")

    private fun head(w: String) = w.split('\'', '’').first()
    private fun norm(w: String) = head(w).lowercase(tr).filter { it.isLetter() }
    private fun key(n: String) = if (n.length >= 6) n.take(5) else n

    private class Word(val loc: Int, val norm: String, val proper: Boolean)

    /** Word offset → the label shown for it. */
    fun build(text: String): Map<Int, String> {
        val sentences = ArrayList<List<Word>>()
        val freq = HashMap<String, Int>()
        val label = HashMap<String, String>()
        val properLabel = HashMap<String, String>()     // a name seen capitalised mid-sentence keeps its capital
        // every word of the text with its place, then cut into the sentences
        val sb = BreakIterator.getSentenceInstance(tr).apply { setText(text) }
        val ends = ArrayList<Int>()
        run { sb.first(); var e = sb.next(); while (e != BreakIterator.DONE) { ends.add(e); e = sb.next() } }
        val wb = BreakIterator.getWordInstance(tr).apply { setText(text) }
        val bySentence = ArrayList<ArrayList<Pair<String, Int>>>()
        var si = 0
        var cur = ArrayList<Pair<String, Int>>()
        var a = wb.first()
        var b = wb.next()
        while (b != BreakIterator.DONE) {
            while (si < ends.size && a >= ends[si]) { bySentence.add(cur); cur = ArrayList(); si++ }
            val w = text.substring(a, b)
            if (w.firstOrNull()?.isLetterOrDigit() == true) cur.add(w to a)
            a = b; b = wb.next()
        }
        bySentence.add(cur)
        for (raw in bySentence) {
            if (raw.isEmpty()) continue
            // a heading capitalises every word: there a capital says nothing about a name
            val caps = raw.count { it.first.first().isUpperCase() }
            val heading = raw.size > 1 && caps * 2 > raw.size
            val words = ArrayList<Word>()
            raw.forEachIndexed { i, (w, loc) ->
                val n = norm(w)
                val surface = head(w).filter { it.isLetter() }
                val proper = i > 0 && !heading && surface.firstOrNull()?.isUpperCase() == true
                if (n.length < 4 || n in stop) return@forEachIndexed
                val k = key(n)
                freq[k] = (freq[k] ?: 0) + 1
                val l = if (proper) surface else n
                val old = label[k]
                if (old == null || l.length < old.length) label[k] = l
                if (proper && surface.length < (properLabel[k]?.length ?: Int.MAX_VALUE)) properLabel[k] = surface
                words.add(Word(loc, n, proper))
            }
            sentences.add(words)
        }
        val out = HashMap<Int, String>()
        for (words in sentences) {
            val want = if (words.size >= 12) 2 else 1
            val cands = words.mapNotNull { w ->
                if (w.norm.length !in 5..18) return@mapNotNull null
                val k = key(w.norm); val f = freq[k] ?: 1
                if (f < 2 && !w.proper) return@mapNotNull null
                Triple(w, k, ln(1.0 + f) / ln(2.0) + (if (w.proper) 1.5 else 0.0) + w.norm.length * 0.08)
            }.sortedByDescending { it.third }
            val used = HashSet<String>()
            for ((w, k, _) in cands) {
                if (used.size >= want) break
                if (k in used) continue
                used.add(k)
                out[w.loc] = properLabel[k] ?: label[k] ?: w.norm
            }
        }
        return out
    }
}
