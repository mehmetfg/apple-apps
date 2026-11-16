// The document's text and how the voice moves through it: paragraphs (one per line), sentences, words, pages,
// chapters and the skip targets of every navigation unit. Port of SpeechPlayer.swift's "text helpers" and
// "navigation targets". Positions are UTF-16 offsets (Kotlin String indices).
package com.fatihgocgun.wisepath.speech

import com.fatihgocgun.wisepath.model.Chapter
import com.fatihgocgun.wisepath.settings.NavigationUnit

class TextNav(val text: String, val chapters: List<Chapter> = emptyList(), val pages: List<Int> = emptyList()) {
    val length: Int get() = text.length

    /** Paragraph ranges (start, length), one per non-empty line. */
    val blocks: List<IntRange> = buildList {
        var start = 0
        while (start <= text.length) {
            var end = text.indexOf('\n', start)
            if (end < 0) end = text.length
            if (end > start) add(start until end)
            start = end + 1
        }
    }

    fun blockIndex(at: Int): Int {
        if (blocks.isEmpty()) return 0
        var lo = 0
        var hi = blocks.size - 1
        while (lo < hi) {
            val mid = (lo + hi + 1) / 2
            if (blocks[mid].first <= at) lo = mid else hi = mid - 1
        }
        return lo
    }

    private fun isEnder(c: Char) = c == '.' || c == '!' || c == '?' || c == '…' || c == '\n'

    /**
     * Whether the character at `k` closes a sentence. A full stop does not when a letter or digit follows directly
     * ("3.5", "vb.ler") or when it closes a bare number ("1. Bölüm", "12. yüzyıl").
     */
    fun endsSentence(k: Int): Boolean {
        if (k < 0 || k >= text.length) return false
        val c = text[k]
        if (!isEnder(c)) return false
        if (c != '.') return true
        if (k + 1 < text.length && text[k + 1].isLetterOrDigit()) return false
        var b = k - 1
        var digits = 0
        while (b >= 0 && text[b].isDigit()) { digits++; b-- }
        if (digits in 1..3 && (b < 0 || text[b] == ' ' || text[b] == '\n')) return false
        return true
    }

    fun sentenceStart(before: Int): Int {
        var j = before.coerceIn(0, text.length)
        val floor = if (blocks.isEmpty()) 0 else blocks[blockIndex(maxOf(0, j - 1))].first
        while (j > floor) {
            if (endsSentence(j - 1)) break
            j--
        }
        while (j < text.length && text[j] == ' ') j++
        return j
    }

    fun sentenceEnd(after: Int): Int? {
        var j = after.coerceIn(0, text.length)
        while (j < text.length) {
            val k = j; j++
            if (endsSentence(k)) {
                while (j < text.length && (text[j] == ' ' || text[j] == '\n')) j++
                return if (j < text.length) j else null
            }
        }
        return null
    }

    /** The sentence around `i`, as a range (start until end). */
    fun sentenceRange(i: Int): IntRange? {
        if (text.isEmpty()) return null
        val a = sentenceStart(minOf(i + 1, text.length))
        var z = a
        while (z < text.length) {
            val k = z; z++
            if (endsSentence(k)) break
        }
        while (z > a && (text[z - 1] == '\n' || text[z - 1] == ' ')) z--
        return if (z > a) a until z else null
    }

    /** The sentence that ends before offset `i`. */
    fun sentenceBefore(i: Int): IntRange? {
        var k = minOf(i, text.length) - 1
        while (k > 0 && (text[k] == ' ' || text[k] == '\n' || text[k] == '\u00A0')) k--
        if (k <= 0) return null
        val r = sentenceRange(k - 1) ?: return null
        return if (r.first < i) r else null
    }

    fun wordRange(i: Int): IntRange {
        if (text.isEmpty()) return IntRange.EMPTY
        fun space(j: Int) = text[j] == ' ' || text[j] == '\n' || text[j] == '\u00A0'
        var a = i.coerceIn(0, text.length - 1)
        var z = a
        while (a > 0 && !space(a - 1)) a--
        while (z < text.length && !space(z)) z++
        return a until z
    }

    fun excerpt(i: Int, max: Int = 80): String {
        val s = sentenceRange(i) ?: return ""
        val t = text.substring(s.first, s.last + 1)
        return if (t.length > max) t.take(max) + "…" else t
    }

    fun substring(r: IntRange): String =
        if (r.isEmpty()) "" else text.substring(r.first.coerceIn(0, text.length), (r.last + 1).coerceIn(0, text.length))

    fun chapterTitle(i: Int): String? = chapters.lastOrNull { it.offset <= i }?.title
    fun chapterIndex(i: Int): Int = chapters.indexOfLast { it.offset <= i }
    fun pageIndex(i: Int): Int = pages.indexOfLast { it <= i }

    /** Where a skip of `unit` goes from `at`; null when there is nowhere to go. */
    fun target(at: Int, forward: Boolean, unit: NavigationUnit, marks: List<Int>, charsPerSecondAtSpeed: Double): Int? {
        when (unit) {
            NavigationUnit.sentence -> {
                if (forward) return sentenceEnd(at)
                val here = sentenceStart(at + 1)
                return if (at - here > 3) here else sentenceStart(maxOf(0, here - 1))
            }
            NavigationUnit.paragraph -> {
                if (blocks.isEmpty()) return null
                val bi = blockIndex(at)
                if (forward) return if (bi + 1 < blocks.size) blocks[bi + 1].first else null
                return if (at - blocks[bi].first > 3) blocks[bi].first else blocks[maxOf(0, bi - 1)].first
            }
            NavigationUnit.page -> return step(if (pages.isEmpty()) blocks.map { it.first } else pages, at, forward)
            NavigationUnit.chapter -> return step(chapters.map { it.offset }, at, forward) ?: if (forward) null else 0
            NavigationUnit.bookmark, NavigationUnit.highlight -> return step(marks.sorted(), at, forward)
            NavigationUnit.seconds15, NavigationUnit.seconds30 -> {
                val secs = if (unit == NavigationUnit.seconds15) 15.0 else 30.0
                val d = (charsPerSecondAtSpeed * secs).toInt()
                val t = if (forward) minOf(text.length - 1, at + d) else maxOf(0, at - d)
                return wordRange(t).first
            }
        }
    }

    private fun step(list: List<Int>, at: Int, forward: Boolean): Int? =
        if (forward) list.firstOrNull { it > at + 1 } else list.lastOrNull { it < at - 3 }
}

/**
 * What the voice actually says can differ from what is on the page: a URL is read as its site name, an e-mail address
 * as "name at site", an in-text citation such as "[12]" or "(Kant, 1781)" is skipped. `original` turns every position
 * in the spoken string back into a position in the original, so the highlighted word still lands on the right place.
 */
class SpokenText(text: String, simplifyLinks: Boolean, skipCitations: Boolean) {
    val string: String
    private val map: IntArray

    fun original(spoken: Int): Int = map[spoken.coerceIn(0, map.size - 1)]

    init {
        data class Edit(val start: Int, val end: Int, val replacement: String)
        val edits = mutableListOf<Edit>()
        fun overlaps(s: Int, e: Int) = edits.any { s < it.end && it.start < e }
        if (simplifyLinks) {
            URL.findAll(text).forEach { m ->
                var s = m.value.replace(Regex("^(https?://)?(www\\.)?", RegexOption.IGNORE_CASE), "")
                s = s.split('/').firstOrNull() ?: s
                edits.add(Edit(m.range.first, m.range.last + 1, s.trim('.', ',', ';', ':', ')')))
            }
            EMAIL.findAll(text).forEach { m ->
                if (!overlaps(m.range.first, m.range.last + 1))
                    edits.add(Edit(m.range.first, m.range.last + 1, m.groupValues[1] + " at " + m.groupValues[2]))
            }
        }
        if (skipCitations) {
            for (re in listOf(BRACKET, AUTHOR_YEAR)) re.findAll(text).forEach { m ->
                if (!overlaps(m.range.first, m.range.last + 1)) edits.add(Edit(m.range.first, m.range.last + 1, ""))
            }
        }
        if (edits.isEmpty()) {
            string = text
            map = IntArray(text.length + 1) { it }
        } else {
            edits.sortBy { it.start }
            val out = StringBuilder()
            val m = ArrayList<Int>(text.length + 1)
            var i = 0
            for (e in edits) {
                if (e.start < i) continue
                if (e.start > i) { out.append(text, i, e.start); for (k in i until e.start) m.add(k) }
                out.append(e.replacement)
                val span = e.end - e.start
                for (k in e.replacement.indices) m.add(e.start + k * span / maxOf(e.replacement.length, 1))
                i = e.end
            }
            if (i < text.length) { out.append(text, i, text.length); for (k in i until text.length) m.add(k) }
            m.add(text.length)
            string = out.toString()
            map = m.toIntArray()
        }
    }

    companion object {
        private val URL = Regex("\\b(?:https?://|www\\.)[^\\s<>\"]+", RegexOption.IGNORE_CASE)
        private val EMAIL = Regex("\\b([A-Za-z0-9._%+-]+)@([A-Za-z0-9.-]+\\.[A-Za-z]{2,})\\b")
        private val BRACKET = Regex("\\s?\\[(?:\\d+(?:[-–,]\\s?\\d+)*|[a-z])\\]")
        private val AUTHOR_YEAR = Regex(
            "\\s?\\((?:[A-ZÇĞİÖŞÜ][\\p{L}'’.-]+(?:\\s(?:ve|and|&|et al\\.?)\\s[A-ZÇĞİÖŞÜ][\\p{L}'’.-]+)?,?\\s(?:\\d{4}[a-z]?|t\\.y\\.|n\\.d\\.)(?:[,:]\\s?(?:s\\.\\s?|p\\.\\s?)?\\d+(?:[-–]\\d+)?)?(?:;\\s?)?)+\\)"
        )
    }
}

/** Turkish or English for a sentence of at least four words, when the guess is clear; null otherwise. */
object LanguageGuess {
    private val trWords = setOf("ve", "bir", "bu", "da", "de", "için", "ile", "olan", "gibi", "daha", "çok", "ne", "ama",
        "o", "şu", "her", "kadar", "sonra", "değil", "olarak", "mi", "mı", "ki", "en", "ise", "veya", "hem", "bile")
    private val enWords = setOf("the", "and", "of", "to", "is", "in", "that", "it", "for", "with", "as", "was", "on",
        "are", "be", "this", "by", "not", "or", "from", "at", "which", "but", "have", "an", "they", "you", "we")
    private const val TR_LETTERS = "çğışöüÇĞİŞÖÜ"

    fun guess(sentence: String): String? {
        val words = sentence.lowercase().split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        if (words.size < 4) return null
        val trChars = sentence.count { it in TR_LETTERS }
        val tr = words.count { it in trWords } * 2 + trChars
        val en = words.count { it in enWords } * 2
        return when {
            en >= 4 && en > tr * 3 && trChars == 0 -> "en"
            tr >= 3 && tr > en * 2 -> "tr"
            else -> null
        }
    }

    /** The main language of a whole text ("tr" or "en"), from a sample of it. */
    fun detect(text: String): String {
        val sample = text.take(20_000).lowercase()
        val words = sample.split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        val tr = words.count { it in trWords } * 2 + sample.count { it in TR_LETTERS }
        val en = words.count { it in enWords } * 2
        return if (en > tr * 1.5) "en" else "tr"
    }
}
