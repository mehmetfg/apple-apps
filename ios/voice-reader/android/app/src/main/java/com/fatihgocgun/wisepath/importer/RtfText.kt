// RTF → plain text. iOS reads RTF through NSAttributedString; Android has no RTF reader, so this is a small one that
// keeps what is read aloud: the body text, paragraph and line breaks, Unicode (\uN) and code-page (\'hh) characters
// in the right code page (\ansicpg, and a font's \fcharset — older Turkish Word files write ı as \'fd in a
// charset-162 font), and leaves out font/colour/style tables, pictures, field instructions and the document info.
package com.fatihgocgun.wisepath.importer

import java.nio.charset.Charset

object RtfText {
    /** Groups whose text is never part of the body. */
    private val skipDestinations = setOf(
        "fonttbl", "colortbl", "stylesheet", "listtable", "listoverridetable", "info", "pict", "object", "objdata",
        "themedata", "colorschememapping", "datastore", "latentstyles", "rsidtbl", "generator", "xmlnstbl", "mmathPr",
        "header", "headerl", "headerr", "headerf", "footer", "footerl", "footerr", "footerf", "fldinst", "revtbl",
        "filetbl", "pgdsctbl", "bkmkstart", "bkmkend", "nonshppict", "shpinst", "expandedcolortbl", "listtext",
        "pntext", "pntxta", "pntxtb", "falt", "panose", "template", "userprops", "docvar", "wgrffmtfilter",
    )

    private class Group(var skip: Boolean, var uc: Int, var font: Int)

    fun text(bytes: ByteArray): String {
        // RTF is 7-bit; Latin-1 keeps every byte as one char so \'hh and stray 8-bit bytes can be re-decoded
        val s = String(bytes, Charsets.ISO_8859_1)
        val out = StringBuilder(s.length / 2)
        var docCodePage = 1252
        val fontCodePage = HashMap<Int, Int>()
        val stack = ArrayList<Group>()
        var g = Group(skip = false, uc = 1, font = -1)
        var inFontTable = 0                 // depth of the font table group while reading it
        var fontNumber = -1
        var pendingSkip = 0                 // characters still to skip after a \uN
        var destinationStart = false        // the next control word names this group's destination
        val bytesRun = java.io.ByteArrayOutputStream()

        fun codePage(): Int = fontCodePage[g.font] ?: docCodePage
        fun flushBytes() {
            if (bytesRun.size() == 0) return
            val cs = charset(codePage())
            out.append(String(bytesRun.toByteArray(), cs))
            bytesRun.reset()
        }
        fun emit(c: Char) { flushBytes(); if (!g.skip) out.append(c) }
        fun emit(t: String) { flushBytes(); if (!g.skip) out.append(t) }

        var i = 0
        val n = s.length
        while (i < n) {
            val c = s[i]
            when (c) {
                '{' -> {
                    flushBytes()
                    stack.add(g)
                    g = Group(g.skip, g.uc, g.font)
                    destinationStart = true
                    pendingSkip = 0
                    i++
                }
                '}' -> {
                    flushBytes()
                    if (inFontTable > 0 && stack.size <= inFontTable) inFontTable = 0   // the table itself closes
                    if (stack.isNotEmpty()) g = stack.removeAt(stack.size - 1)
                    destinationStart = false
                    pendingSkip = 0
                    i++
                }
                '\\' -> {
                    if (i + 1 >= n) { i++; continue }
                    val d = s[i + 1]
                    if (d.isLetter()) {
                        var j = i + 1
                        while (j < n && s[j].isLetter() && s[j].code < 128) j++
                        val word = s.substring(i + 1, j)
                        var param: Int? = null
                        if (j < n && (s[j] == '-' || s[j].isDigit())) {
                            val k0 = j
                            j++
                            while (j < n && s[j].isDigit()) j++
                            param = s.substring(k0, j).toIntOrNull()
                        }
                        if (j < n && s[j] == ' ') j++
                        i = j
                        val wasStart = destinationStart
                        destinationStart = false
                        if (word == "bin") {                       // raw binary data: skip it whole
                            i += maxOf(0, param ?: 0)
                            continue
                        }
                        if (pendingSkip > 0) { pendingSkip--; continue }
                        if (wasStart && word in skipDestinations) {
                            if (word == "fonttbl") inFontTable = stack.size
                            flushBytes(); g.skip = true
                            continue
                        }
                        when (word) {
                            "ansicpg" -> if (param != null) docCodePage = param
                            "f" -> {
                                if (param != null) {
                                    if (inFontTable > 0) fontNumber = param else { flushBytes(); g.font = param }
                                }
                            }
                            "fcharset" -> if (inFontTable > 0 && fontNumber >= 0 && param != null) {
                                charsetCodePage(param)?.let { fontCodePage[fontNumber] = it }
                            }
                            "cpg" -> if (inFontTable > 0 && fontNumber >= 0 && param != null) fontCodePage[fontNumber] = param
                            "uc" -> g.uc = maxOf(0, param ?: 1)
                            "u" -> if (param != null) {
                                val v = if (param < 0) param + 65536 else param
                                emit(v.toChar())
                                pendingSkip = g.uc
                            }
                            "par", "line", "sect", "page", "row" -> emit('\n')
                            "tab", "cell" -> emit(' ')
                            "emdash" -> emit('—')
                            "endash" -> emit('–')
                            "lquote" -> emit('‘')
                            "rquote" -> emit('’')
                            "ldblquote" -> emit('“')
                            "rdblquote" -> emit('”')
                            "bullet" -> emit('•')
                            "emspace", "enspace", "qmspace" -> emit(' ')
                        }
                    } else {
                        i += 2
                        val wasStart = destinationStart
                        destinationStart = false
                        when (d) {
                            '\'' -> {
                                if (i + 2 <= n) {
                                    val v = s.substring(i, i + 2).toIntOrNull(16)
                                    i += 2
                                    if (v != null) {
                                        if (pendingSkip > 0) { pendingSkip--; continue }
                                        if (!g.skip) bytesRun.write(v)
                                    }
                                }
                            }
                            '*' -> if (wasStart) { flushBytes(); g.skip = true }
                            '\\', '{', '}' -> if (pendingSkip > 0) pendingSkip-- else emit(d)
                            '~' -> emit(' ')
                            '_' -> emit('-')
                            '-' -> {}                                    // optional hyphen
                            '\n', '\r' -> emit('\n')
                            else -> {}
                        }
                    }
                }
                '\r', '\n' -> i++
                else -> {
                    destinationStart = false
                    if (pendingSkip > 0) { pendingSkip--; i++; continue }
                    if (c.code >= 128) { if (!g.skip) bytesRun.write(c.code) } else emit(c)
                    i++
                }
            }
        }
        flushBytes()
        return out.toString()
    }

    private fun charsetCodePage(charset: Int): Int? = when (charset) {
        0 -> null              // ANSI: the document's code page
        162 -> 1254
        161 -> 1253
        204 -> 1251
        238 -> 1250
        177 -> 1255
        178 -> 1256
        186 -> 1257
        163 -> 1258
        222 -> 874
        77 -> 10000
        else -> null
    }

    private val charsets = HashMap<Int, Charset>()
    private fun charset(cp: Int): Charset = synchronized(charsets) {
        charsets.getOrPut(cp) {
            val name = when (cp) { 10000 -> "x-MacRoman"; 65001 -> "UTF-8"; else -> "windows-$cp" }
            runCatching { Charset.forName(name) }.getOrNull()
                ?: runCatching { Charset.forName("Cp$cp") }.getOrNull()
                ?: Charset.forName("windows-1252")
        }
    }
}
