// Small shared helpers: time and number formats in Turkish, accent-insensitive matching, haptics.
package com.fatihgocgun.wisepath

import android.content.Context
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import java.text.Normalizer
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

object Format {
    val tr: Locale = Locale("tr", "TR")

    /** 3725 s → "1 sa 2 dk", 300 → "5 dk", 40 → "1 dk". */
    fun duration(seconds: Double): String {
        val m = Math.round(seconds / 60.0).toInt()
        if (m < 1) return if (seconds > 0) "1 dk" else "0 dk"
        val h = m / 60
        return if (h > 0) (if (m % 60 > 0) "$h sa ${m % 60} dk" else "$h sa") else "$m dk"
    }

    /** "12:05" for a clock of minutes and seconds. */
    fun clock(seconds: Double): String {
        val s = maxOf(0, seconds.toInt())
        return if (s >= 3600) "%d:%02d:%02d".format(s / 3600, (s / 60) % 60, s % 60) else "%d:%02d".format(s / 60, s % 60)
    }

    fun percent(p: Double): String = "%" + (p * 100).toInt()

    fun date(millis: Long, pattern: String = "d MMMM yyyy"): String =
        DateTimeFormatter.ofPattern(pattern, tr).format(Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()))

    fun day(d: LocalDate, pattern: String = "d MMMM EEEE"): String = DateTimeFormatter.ofPattern(pattern, tr).format(d)

    fun localDate(millis: Long): LocalDate = Instant.ofEpochMilli(millis).atZone(ZoneId.systemDefault()).toLocalDate()

    fun wpm(charsPerSecond: Double, speed: Double): Int = Math.round(charsPerSecond * speed * 60 / 6.2).toInt()
}

/**
 * Matching that ignores case, accents and the dotted/dotless i: "gazali" finds "Gazâlî", "ISIK" finds "ışık".
 * `fold` keeps the string's length for the common letters, so a folded index is (almost always) the original index.
 */
object TextFold {
    fun fold(s: String): String {
        val sb = StringBuilder(s.length)
        for (c in s) sb.append(foldChar(c))
        return sb.toString()
    }

    fun foldChar(c: Char): Char = when (c) {
        'I', 'ı', 'İ', 'i', 'î', 'Î', 'ï', 'í', 'ì' -> 'i'
        'ş', 'Ş' -> 's'
        'ğ', 'Ğ' -> 'g'
        'ç', 'Ç' -> 'c'
        'ö', 'Ö', 'ô', 'ó', 'ò' -> 'o'
        'ü', 'Ü', 'û', 'Û', 'ú', 'ù' -> 'u'
        'â', 'Â', 'á', 'à', 'ä' -> 'a'
        'é', 'è', 'ê', 'ë' -> 'e'
        '’', '‘' -> '\''
        else -> {
            val l = c.lowercaseChar()
            if (l.code < 128) l else Normalizer.normalize(l.toString(), Normalizer.Form.NFD).firstOrNull() ?: l
        }
    }

    /** Every start of `query` in `text`, ignoring case and accents. */
    fun findAll(text: String, query: String, limit: Int = 500): List<IntRange> {
        val q = fold(query.trim())
        if (q.isEmpty()) return emptyList()
        val t = fold(text)
        val out = mutableListOf<IntRange>()
        var i = t.indexOf(q)
        while (i >= 0 && out.size < limit) {
            out.add(i until i + q.length)
            i = t.indexOf(q, i + q.length)
        }
        return out
    }
}

object Haptics {
    fun tick(context: Context, strong: Boolean) {
        val v: Vibrator? = if (Build.VERSION.SDK_INT >= 31) context.getSystemService(VibratorManager::class.java)?.defaultVibrator
        else @Suppress("DEPRECATION") context.getSystemService(Vibrator::class.java)
        runCatching {
            if (Build.VERSION.SDK_INT >= 29) v?.vibrate(VibrationEffect.createPredefined(if (strong) VibrationEffect.EFFECT_CLICK else VibrationEffect.EFFECT_TICK))
            else v?.vibrate(VibrationEffect.createOneShot(if (strong) 30 else 12, VibrationEffect.DEFAULT_AMPLITUDE))
        }
    }
}
