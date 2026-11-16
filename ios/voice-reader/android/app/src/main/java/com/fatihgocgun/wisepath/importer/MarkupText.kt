// HTML / XHTML → plain paragraphs (port of Import/MarkupText.swift). Tolerant of broken markup: it scans tags rather
// than parsing a tree, so a whole book's chapter of sloppy HTML still comes out as text.
package com.fatihgocgun.wisepath.importer

/** A heading found while reading: the paragraph it starts at, its text and level (1 = chapter). */
data class Heading(val paragraph: Int, val title: String, val level: Int)

object MarkupText {
    class Output {
        val paragraphs = mutableListOf<String>()
        val headings = mutableListOf<Heading>()
        var title: String? = null
    }

    private val blockTags = setOf(
        "p", "div", "br", "li", "ul", "ol", "tr", "td", "th", "table", "section", "article", "aside", "header", "footer",
        "blockquote", "pre", "hr", "dt", "dd", "dl", "figcaption", "figure", "h1", "h2", "h3", "h4", "h5", "h6", "nav", "main",
        "body", "caption",
    )
    private val skipTags = setOf("script", "style", "head", "svg", "math", "noscript", "template")

    fun convert(html: String): Output {
        val out = Output()
        val current = StringBuilder()
        var headingLevel = 0
        var headingStart = -1
        var skipDepth = 0
        var skipName = ""
        var inTitle = false
        val titleText = StringBuilder()

        fun flush() {
            val p = current.toString().trim()
            current.setLength(0)
            if (p.isNotEmpty()) out.paragraphs.add(p)
        }

        val s = html
        val n = s.length
        var i = 0
        val text = StringBuilder()
        fun takeText() {
            if (text.isEmpty()) return
            val chunk = decodeEntities(text.toString())
            text.setLength(0)
            if (inTitle) { titleText.append(chunk); return }
            if (skipDepth > 0) return
            appendCollapsed(chunk, current)
        }

        while (i < n) {
            if (s[i] == '<') {
                // comment
                if (i + 3 < n && s[i + 1] == '!' && s[i + 2] == '-' && s[i + 3] == '-') {
                    takeText()
                    var j = i + 4
                    while (j + 2 < n && !(s[j] == '-' && s[j + 1] == '-' && s[j + 2] == '>')) j++
                    i = j + 3
                    continue
                }
                var j = i + 1
                var quote = '\u0000'
                while (j < n) {
                    val c = s[j]
                    if (quote != '\u0000') { if (c == quote) quote = '\u0000' }
                    else if (c == '"' || c == '\'') quote = c
                    else if (c == '>') break
                    j++
                }
                if (j >= n) { text.append(s, i, n); break }
                takeText()
                val tag = s.substring(i + 1, j)
                i = j + 1
                val closing = tag.startsWith("/")
                val name = tag.trimStart('/').takeWhile { !it.isWhitespace() && it != '/' && it != '>' }.lowercase()
                val bare = name.substringAfterLast(':')        // xhtml:p
                // a self-closing <title/> opens nothing, and a title left open ends with the head: either one used to
                // send the whole rest of the file into the title, and the chapter came out empty
                if (inTitle && (bare == "head" || bare == "body")) inTitle = false
                if (bare == "title") {
                    inTitle = !closing && !tag.endsWith("/")
                    if (closing) out.title = titleText.toString().trim()
                    continue
                }
                if (bare in skipTags) {
                    if (closing) {
                        if (bare == skipName) { skipDepth = maxOf(0, skipDepth - 1); if (skipDepth == 0) skipName = "" }
                    } else if (!tag.endsWith("/") && (skipName.isEmpty() || skipName == bare)) {
                        skipName = bare; skipDepth++
                    }
                    continue
                }
                if (skipDepth > 0) continue
                if (bare == "img" && !closing) {
                    val alt = attribute("alt", tag)
                    if (alt != null && alt.length > 2) appendCollapsed(" $alt ", current)
                }
                if (bare in blockTags) {
                    val lv = if (bare.length == 2 && bare[0] == 'h') bare[1].digitToIntOrNull() else null
                    if (lv != null) {
                        if (!closing) { flush(); headingLevel = lv; headingStart = out.paragraphs.size }
                        else {
                            flush()
                            if (headingStart >= 0 && headingStart < out.paragraphs.size) {
                                val t = out.paragraphs.subList(headingStart, out.paragraphs.size).joinToString(" ")
                                out.headings.add(Heading(headingStart, t.take(140), headingLevel))
                            }
                            headingStart = -1
                        }
                    } else {
                        flush()
                    }
                }
            } else {
                text.append(s[i])
                i++
            }
        }
        takeText()
        flush()
        return out
    }

    private fun appendCollapsed(chunk: String, current: StringBuilder) {
        for (ch in chunk) {
            if (ch.isWhitespace() || ch == ' ') {
                if (current.isNotEmpty() && current[current.length - 1] != ' ') current.append(' ')
            } else {
                current.append(ch)
            }
        }
    }

    private fun attribute(name: String, tag: String): String? {
        val r = tag.indexOf("$name=", ignoreCase = true)
        if (r < 0) return null
        val rest = tag.substring(r + name.length + 1)
        val q = rest.firstOrNull() ?: return null
        if (q != '"' && q != '\'') return null
        val end = rest.indexOf(q, 1)
        if (end < 0) return null
        return decodeEntities(rest.substring(1, end))
    }

    private val named = mapOf(
        "amp" to "&", "lt" to "<", "gt" to ">", "quot" to "\"", "apos" to "'", "nbsp" to " ", "mdash" to "—", "ndash" to "–",
        "hellip" to "…", "rsquo" to "’", "lsquo" to "‘", "ldquo" to "“", "rdquo" to "”", "laquo" to "«", "raquo" to "»",
        "copy" to "©", "reg" to "®", "trade" to "™", "shy" to "", "middot" to "·", "bull" to "•", "deg" to "°", "times" to "×",
        "eacute" to "é", "egrave" to "è", "agrave" to "à", "acirc" to "â", "icirc" to "î", "ucirc" to "û", "ouml" to "ö", "uuml" to "ü",
        "ccedil" to "ç", "Ouml" to "Ö", "Uuml" to "Ü", "Ccedil" to "Ç", "szlig" to "ß", "auml" to "ä", "Auml" to "Ä", "zwj" to "", "zwnj" to "",
        "thinsp" to " ", "ensp" to " ", "emsp" to " ", "prime" to "′", "Prime" to "″", "euro" to "€", "pound" to "£", "sect" to "§", "para" to "¶",
    )

    fun decodeEntities(s: String): String {
        if (!s.contains('&')) return s
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val c = s[i]
            if (c == '&') {
                val semi = s.indexOf(';', i).takeIf { it in i until minOf(s.length, i + 12) }
                if (semi != null) {
                    val body = s.substring(i + 1, semi)
                    val rep: String? = when {
                        body.startsWith("#x") || body.startsWith("#X") -> body.drop(2).toIntOrNull(16)?.let(::codePoint)
                        body.startsWith("#") -> body.drop(1).toIntOrNull()?.let(::codePoint)
                        else -> named[body]
                    }
                    if (rep != null) { out.append(rep); i = semi + 1; continue }
                }
            }
            out.append(c)
            i++
        }
        return out.toString()
    }

    private fun codePoint(v: Int): String? =
        if (Character.isValidCodePoint(v) && v !in 0xD800..0xDFFF) String(Character.toChars(v)) else null
}
