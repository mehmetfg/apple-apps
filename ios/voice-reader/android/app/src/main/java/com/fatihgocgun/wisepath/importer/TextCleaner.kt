// The first pass on every imported document, for listening (port of Import/TextCleaner.swift): whatever the format
// gave (a hard-wrapped .txt, a PDF with running heads, a DOCX with empty paragraphs), the reader gets one
// sentence-ending paragraph per line.
//
//   1. characters: zero-width and soft hyphens out, odd spaces to one space, "....." → "…", "!!!" → "!",
//      superscript footnote marks glued to words out, "word - word" dashes kept as a pause
//   2. lines that say nothing aloud: lone page numbers, separators (***, ———, ____), lone bullets, "Page 12 of 300"
//   3. running heads and feet: a short line that comes back on many pages
//   4. hard-wrapped text: a paragraph that stops mid-sentence and the next starting in lower case are one paragraph;
//      "philo-" + "sophy" → "philosophy"
//   5. shouting: a paragraph in capitals (not a short heading) is read as a sentence, not letter by letter
//
// Headings are never joined or dropped; their indexes are mapped to the new paragraphs.
package com.fatihgocgun.wisepath.importer

import java.util.Locale

object TextCleaner {
    class Result(
        val paragraphs: List<String>,
        val headings: List<Heading>,
        /** Old paragraph index → new one (a dropped paragraph → the next one kept), for PDF page starts. */
        val index: List<Int>,
    )

    /** `paged`: the source has pages (PDF), so a short line coming back on many of them is a running head. */
    fun clean(paragraphs: List<String>, headings: List<Heading>, paged: Boolean = false): Result {
        val protected = headings.map { it.paragraph }.toHashSet()
        // 1-2: per paragraph
        val items = ArrayList<Pair<String, Int>>(paragraphs.size)
        for ((i, p) in paragraphs.withIndex()) {
            val t = normalize(p)
            if (i in protected) { items.add((if (t.isEmpty()) p else t) to i); continue }
            if (t.isEmpty() || silent(t)) continue
            items.add(t to i)
        }
        // 3: running heads (paged and long documents only: a novel's repeated "Evet." stays)
        if (paged && items.size > 60) {
            val seen = HashMap<String, Int>()
            for ((text, old) in items) if (text.length <= 70 && old !in protected) seen.merge(key(text), 1, Int::plus)
            val limit = maxOf(4, items.size / 80)
            val repeated = seen.filterValues { it >= limit }.keys
            if (repeated.isNotEmpty()) items.removeAll { (text, old) -> old !in protected && key(text) in repeated }
        }
        // 4: join broken paragraphs
        val out = ArrayList<Pair<String, List<Int>>>()
        for ((text, old) in items) {
            val last = out.lastOrNull()
            if (last != null && old !in protected && last.second.none { it in protected } && continues(last.first, text)) {
                val joined = if (last.first.endsWith("-") && text.first().isLowerCase()) last.first.dropLast(1) + text
                else last.first + " " + text
                out[out.size - 1] = joined to (last.second + old)
            } else {
                out.add(text to listOf(old))
            }
        }
        // 5: capitals
        val final = out.map { (text, old) -> if (old.any { it in protected }) text else uncapital(text) }
        // map headings
        val newIndex = HashMap<Int, Int>()
        for ((n, o) in out.withIndex()) for (k in o.second) newIndex[k] = n
        val mapped = headings.mapNotNull { h ->
            val n = newIndex[h.paragraph] ?: return@mapNotNull null
            val t = normalize(h.title)
            Heading(n, if (t.isEmpty()) h.title else t, h.level)
        }
        val index = IntArray(paragraphs.size + 1) { final.size }
        for (k in paragraphs.size - 1 downTo 0) index[k] = newIndex[k] ?: index[k + 1]
        return Result(final, mapped, index.dropLast(1))
    }

    // rules

    private const val ZERO_WIDTH = "\u200B\u200C\u200D\u2060\uFEFF\u00AD"
    private val oddSpaces = Regex("[\\u00A0\\u2000-\\u200A\\u202F\\u205F\\u3000\\t ]+")
    private val superscripts = Regex("(?<=\\p{L}[.,;:!?”\"»)]?)[¹²³⁰\\u2074-\\u2079]+")
    private val bracketNumber = Regex("(?<=\\p{L}[.,;:]?)\\[\\d{1,3}]")
    private val manyDots = Regex("\\.{4,}")
    private val repeatedMarks = Regex("([!?])\\1+")
    private val spaceBeforeMark = Regex("\\s+([,.;:!?…])")
    private val bullet = Regex("^[•·▪◦●○■□➢►\\-–—*]+\\s+")

    fun normalize(s: String): String {
        var t = s.filterNot { it in ZERO_WIDTH }
        t = oddSpaces.replace(t, " ")
        t = superscripts.replace(t, "")
        t = bracketNumber.replace(t, "")
        t = manyDots.replace(t, "…")
        t = t.replace("...", "…")
        t = repeatedMarks.replace(t, "$1")
        t = spaceBeforeMark.replace(t, "$1")
        t = bullet.replace(t, "")
        return t.trim()
    }

    private val lonePageNumber = Regex("^[\\-–—\\s]*\\d{1,4}[\\-–—\\s]*$")
    private val pageLabel = Regex("^(sayfa|page|s\\.|p\\.)\\s*\\d{1,4}(\\s*(/|of|'den|’den)\\s*\\d{1,4})?$", RegexOption.IGNORE_CASE)

    /** Nothing to say aloud: a page number, a separator, "Sayfa 3 / 120", "- 12 -". */
    fun silent(t: String): Boolean {
        if (t.none { it.isLetterOrDigit() }) return true
        if (t.length <= 12 && lonePageNumber.matches(t)) return true
        if (pageLabel.matches(t)) return true
        return false
    }

    /**
     * The next paragraph carries on the sentence: the first stops without a closing mark and the second begins in
     * lower case (or after a hyphenated break).
     */
    fun continues(a: String, b: String): Boolean {
        val last = a.lastOrNull() ?: return false
        val first = b.firstOrNull() ?: return false
        if (last in ".!?…:;”\"»)]") return false
        if (a.endsWith("-") && first.isLowerCase()) return true
        return first.isLowerCase() && a.length >= 25
    }

    private val turkish = Locale("tr", "TR")

    /** "BÖLÜM BİR: YOLUN BAŞI ve sonu" read as "Bölüm bir: yolun başı ve sonu" when it is a long all-capital line. */
    fun uncapital(t: String): String {
        val letters = t.filter { it.isLetter() }
        if (letters.length < 25 || letters.any { it.isLowerCase() }) return t
        val low = t.lowercase(turkish)
        if (low.isEmpty()) return t
        return low.substring(0, 1).uppercase(turkish) + low.substring(1)
    }

    private val digits = Regex("\\d+")
    private fun key(t: String): String = digits.replace(t.lowercase(), "#")
}
