// Turns a file into readable text: one paragraph per line, headings at their offsets, PDF page starts
// (port of Import/DocumentImporter.swift). Pure functions; runs off the main thread (see AppModel.importUris).
// The camera scan (ScanImport.swift) is not part of this port.
package com.fatihgocgun.wisepath.importer

import android.content.Context
import com.fatihgocgun.wisepath.model.Chapter
import com.fatihgocgun.wisepath.model.DocumentContent
import com.fatihgocgun.wisepath.model.DocumentFormat
import com.fatihgocgun.wisepath.model.ImportedDocument
import com.fatihgocgun.wisepath.model.countWords
import com.fatihgocgun.wisepath.speech.LanguageGuess
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.charset.Charset
import java.nio.charset.CodingErrorAction

class ImportException(message: String) : Exception(message)

object DocumentImporter {
    /** The file name extensions the importer reads (for the file picker and the drop folder). */
    val extensions: Set<String> = setOf(
        "pdf", "epub", "docx", "html", "htm", "xhtml", "rtf", "rtfd", "md", "markdown", "mobi", "azw", "azw3", "prc",
        "odt", "fb2", "doc", "txt", "text",
    )

    /** Other plain-text extensions read as .txt (iOS: anything whose type conforms to public.text). */
    private val textLike = setOf(
        "text", "csv", "tsv", "log", "json", "xml", "yaml", "yml", "ini", "conf", "srt", "vtt", "tex", "org", "rst",
        "adoc", "asciidoc", "nfo", "me", "1st",
    )

    @Volatile private var appContext: Context? = null

    /** Gives the PDF reader its resources (fonts, glyph lists). AppModel calls it once; cheap to call again. */
    fun init(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        runCatching { com.tom_roush.pdfbox.android.PDFBoxResourceLoader.init(context.applicationContext) }
    }

    // errors (the iOS ImportError texts)
    private fun unsupported(n: String) = ImportException("“$n” biçimi desteklenmiyor.")
    private fun locked(n: String) = ImportException("“$n” kilitli (DRM). Kindle'ın koruduğu kitaplar okunamaz; korumasız bir kopya (EPUB, MOBI) dene.")
    private fun compressed(n: String) = ImportException("“$n” eski Kindle sıkıştırmasıyla (HUFF/CDIC) yazılmış. Calibre ile EPUB'a çevirip yeniden ekle.")
    private fun unreadable(n: String) = ImportException("“$n” okunamadı.")
    private fun empty(n: String) = ImportException("“$n” içinde okunacak metin bulunamadı. Taranmış bir PDF olabilir.")

    /** Reads `file`; `displayName` is the name the user saw (the file may be a temporary copy). */
    fun importFile(file: File, displayName: String = file.name): ImportedDocument {
        val name = displayName
        val ext = if (name.contains('.')) name.substringAfterLast('.').lowercase() else ""
        val base = if (name.contains('.')) name.substringBeforeLast('.') else name
        val result = try {
            when (ext) {
                "pdf" -> pdf(file, name, base)
                "epub" -> epub(file, name, base)
                "docx" -> docx(file, name, base)
                "html", "htm", "xhtml" -> html(file, name, base)
                "rtf", "rtfd" -> rtf(file, name, base)
                "md", "markdown" -> markdown(file, name, base)
                "mobi", "azw", "azw3", "prc" -> mobi(file, name, base)
                "odt" -> odt(file, name, base)
                "fb2" -> fb2(file, name, base)
                "doc" -> doc(file, name, base)
                else -> if (ext == "txt" || ext.isEmpty() || ext in textLike) plain(file, name, base) else throw unsupported(name)
            }
        } catch (e: ImportException) {
            throw e
        } catch (e: OutOfMemoryError) {
            throw unreadable(name)
        } catch (e: LinkageError) {          // a library class that failed to load (e.g. PDF resources missing)
            throw unreadable(name)
        } catch (e: Exception) {
            throw unreadable(name)
        }
        if (result.content.text.isBlank()) throw empty(name)
        return result
    }

    /** Text from the clipboard or a share. Markdown headings become the table of contents. */
    fun fromClipboard(text: String): ImportedDocument {
        // an AI's answer (İstem oluşturucu) or any Markdown: headings become the table of contents
        if (Regex("(?m)^#{1,3} \\S").containsMatchIn(text)) {
            val (paragraphs, headings) = parseMarkdown(text)
            if (paragraphs.isEmpty()) throw ImportException("Panoda okunacak metin yok.")
            val title = headings.firstOrNull { it.level == 1 }?.title ?: paragraphs[0].take(60)
            return assemble(title, null, DocumentFormat.CLIPBOARD, "Pano", paragraphs, headings)
        }
        val paragraphs = splitParagraphs(text)
        if (paragraphs.isEmpty()) throw ImportException("Panoda okunacak metin yok.")
        return assemble(paragraphs[0].take(60), null, DocumentFormat.CLIPBOARD, "Pano", paragraphs, emptyList())
    }

    // formats

    private fun plain(file: File, name: String, base: String): ImportedDocument =
        assemble(base, null, DocumentFormat.TXT, name, splitParagraphs(decode(file.readBytes())), emptyList())

    private fun mobi(file: File, name: String, base: String): ImportedDocument {
        val book = try {
            MobiReader.read(file.readBytes())
        } catch (_: MobiReader.Failure.Drm) {
            throw locked(name)
        } catch (_: MobiReader.Failure.Huffman) {
            throw compressed(name)
        } catch (_: Exception) {
            throw unreadable(name)
        }
        val html = Regex("<mbp:pagebreak[^>]*>").replace(book.html, "<p></p>")
        val out = MarkupText.convert(html)
        val headings = out.headings.filter { it.level <= 2 }
        return assemble(book.title?.takeIf { it.isNotEmpty() } ?: base, book.author, DocumentFormat.MOBI, name,
            out.paragraphs, headings)
    }

    /** OpenDocument text (LibreOffice, Pages export): content.xml's text:h / text:p as HTML headings and paragraphs. */
    private fun odt(file: File, name: String, base: String): ImportedDocument {
        val zip = runCatching { ZipArchive(file) }.getOrNull() ?: throw unreadable(name)
        val xml = zip.data("content.xml") ?: throw unreadable(name)
        var s = decode(xml)
        for ((a, b) in listOf(
            "<text:h\\b[^>]*>" to "<h2>", "</text:h>" to "</h2>", "<text:p\\b[^>]*>" to "<p>", "</text:p>" to "</p>",
            "<text:(line-break|tab|s)\\b[^>]*/>" to " ",
        )) s = Regex(a).replace(s, b)
        val out = MarkupText.convert(s)
        var title = base
        var author: String? = null
        var lang: String? = null
        zip.data("meta.xml")?.let { meta ->
            val m = SimpleXMLText.values(meta, setOf("title", "creator", "initial-creator", "language"))
            m["title"]?.takeIf { it.isNotEmpty() }?.let { title = it }
            author = (m["creator"] ?: m["initial-creator"])?.takeIf { it.isNotEmpty() }
            lang = m["language"]
        }
        return assemble(title, author, DocumentFormat.ODT, name, out.paragraphs, out.headings, metaLanguage = lang)
    }

    /** FictionBook (common for Russian and Turkish e-book archives): XML with <section><title><p>; images left out. */
    private fun fb2(file: File, name: String, base: String): ImportedDocument {
        val data = file.readBytes()
        val raw = decode(data)
        val meta = SimpleXMLText.values(data, setOf("book-title", "first-name", "last-name", "lang"))
        var s = Regex("(?s)<binary\\b.*?</binary>").replace(raw, "")
        s = Regex("(?s)<description\\b.*?</description>").replace(s, "")
        s = Regex("(?s)<title>(.*?)</title>").replace(s, "<h2>$1</h2>")
        val out = MarkupText.convert(s)
        val author = listOfNotNull(meta["first-name"], meta["last-name"]).joinToString(" ").trim()
        return assemble(meta["book-title"]?.takeIf { it.isNotEmpty() } ?: base, author.ifEmpty { null },
            DocumentFormat.FB2, name, out.paragraphs, out.headings, metaLanguage = meta["lang"])
    }

    /**
     * Word 97–2003 (.doc): no reader for it here either. The text sits in the file as UTF-16 (or one byte a character
     * in older files); runs of readable text are taken, the binary around them is left. Headings are not known.
     */
    private fun doc(file: File, name: String, base: String): ImportedDocument {
        val data = file.readBytes()
        val wide = textRuns(String(data, 0, data.size - data.size % 2, Charsets.UTF_16LE))
        val narrow = textRuns(String(data, windows1254))
        val best = if (wide.sumOf { it.length } >= narrow.sumOf { it.length }) wide else narrow
        return assemble(base, null, DocumentFormat.DOC, name, best, emptyList())
    }

    private const val EXTRA_TEXT_CHARS = "’‘“”«»–—…"

    private fun isPunctuation(c: Char): Boolean = when (Character.getType(c).toByte()) {
        Character.CONNECTOR_PUNCTUATION, Character.DASH_PUNCTUATION, Character.START_PUNCTUATION,
        Character.END_PUNCTUATION, Character.INITIAL_QUOTE_PUNCTUATION, Character.FINAL_QUOTE_PUNCTUATION,
        Character.OTHER_PUNCTUATION -> true
        else -> false
    }

    /**
     * Readable stretches of a binary file: letters, digits, punctuation and spaces, at least 40 characters with
     * mostly letters; carriage returns end paragraphs (Word's paragraph mark).
     */
    private fun textRuns(s: String): List<String> {
        val runs = mutableListOf<String>()
        val cur = StringBuilder()
        fun end() {
            val t = cur.toString().trim(' ')
            cur.setLength(0)
            if (t.isEmpty()) return
            val letters = t.count { it.isLetter() }.toDouble()
            if (t.length >= 40 && letters / t.length > 0.6) runs.add(t)
            else if (runs.isNotEmpty() && t.length >= 3 && letters > 0 && letters / t.length > 0.7) runs.add(t)
        }
        for (ch in s) {
            if (ch == '\r' || ch == '\n') { end(); continue }
            if (ch.isLetterOrDigit() || isPunctuation(ch) || ch == ' ' || ch in EXTRA_TEXT_CHARS) cur.append(ch) else end()
        }
        end()
        return runs
    }

    private fun markdown(file: File, name: String, base: String): ImportedDocument {
        val (paragraphs, headings) = parseMarkdown(decode(file.readBytes()))
        val title = headings.firstOrNull { it.level == 1 }?.title ?: base
        return assemble(title, null, DocumentFormat.MARKDOWN, name, paragraphs, headings)
    }

    private val newlines = Regex("\r\n|[\n\r\u000B\u000C\u0085  ]")

    /** Markdown → readable paragraphs and headings (front matter, fences, tables, links and emphasis handled). */
    fun parseMarkdown(text: String): Pair<List<String>, List<Heading>> {
        val paragraphs = mutableListOf<String>()
        val headings = mutableListOf<Heading>()
        var inFence = false
        var inFront = false
        for ((n, raw) in text.split(newlines).withIndex()) {
            var line = raw.trim(' ', '\t')
            if (n == 0 && line == "---") { inFront = true; continue }
            if (inFront) { if (line == "---") inFront = false; continue }
            if (line.startsWith("```")) { inFence = !inFence; continue }
            if (line.isEmpty() || line.all { it in "-*_=|: " }) continue
            var level = 0
            while (line.startsWith("#")) { line = line.substring(1); level++ }
            line = line.trim(' ', '\t')
            if (line.startsWith(">")) line = line.dropWhile { it == '>' || it == ' ' }
            if (line.startsWith("|")) {                    // table row → cells separated by a pause
                line = line.split('|').map { it.trim() }.filter { it.isNotEmpty() }.joinToString(" · ")
            }
            if (!inFence && (line.startsWith("- ") || line.startsWith("* ") || line.startsWith("+ "))) line = line.substring(2)
            line = stripMarkdown(line)
            if (line.isEmpty()) continue
            if (level > 0) headings.add(Heading(paragraphs.size, line, level))
            paragraphs.add(line)
        }
        return paragraphs to headings
    }

    private val mdLink = Regex("!?\\[([^\\]]*)]\\([^)]*\\)")
    private val mdWiki = Regex("\\[\\[(?:[^\\]|]*\\|)?([^\\]]*)]]")
    private val mdEmphasis = Regex("(\\*\\*|__|\\*|_|`|~~)")

    private fun stripMarkdown(s: String): String {
        // [text](link) and ![alt](src) → text; [[wiki|alias]] → alias
        var t = mdLink.replace(s, "$1")
        t = mdWiki.replace(t, "$1")
        t = mdEmphasis.replace(t, "")
        return t.trim(' ', '\t')
    }

    private fun html(file: File, name: String, base: String): ImportedDocument {
        val out = MarkupText.convert(decode(file.readBytes()))
        val title = out.title?.takeIf { it.isNotEmpty() } ?: base
        return assemble(title, null, DocumentFormat.HTML, name, out.paragraphs, out.headings)
    }

    /** RTF; an .rtfd package arrives as a folder or a zip holding TXT.rtf. */
    private fun rtf(file: File, name: String, base: String): ImportedDocument {
        val bytes: ByteArray = when {
            file.isDirectory -> File(file, "TXT.rtf").takeIf { it.exists() }?.readBytes() ?: throw unreadable(name)
            else -> {
                val raw = file.readBytes()
                if (raw.size > 4 && raw[0] == 'P'.code.toByte() && raw[1] == 'K'.code.toByte()) {
                    val zip = runCatching { ZipArchive(raw) }.getOrNull()
                    val entry = zip?.paths?.firstOrNull { it.substringAfterLast('/').equals("TXT.rtf", true) }
                    entry?.let { zip.data(it) } ?: throw unreadable(name)
                } else raw
            }
        }
        if (!String(bytes, 0, minOf(bytes.size, 16), Charsets.ISO_8859_1).trimStart().startsWith("{\\rtf")) throw unreadable(name)
        return assemble(base, null, DocumentFormat.RTF, name, splitParagraphs(RtfText.text(bytes)), emptyList())
    }

    private fun docx(file: File, name: String, base: String): ImportedDocument {
        val zip = runCatching { ZipArchive(file) }.getOrNull() ?: throw unreadable(name)
        val xml = zip.data("word/document.xml") ?: throw unreadable(name)
        val parser = DocxParser()
        parser.parse(xml)
        var title = base
        var author: String? = null
        var lang: String? = null
        zip.data("docProps/core.xml")?.let { core ->
            val meta = SimpleXMLText.values(core, setOf("title", "creator", "language"))
            meta["title"]?.takeIf { it.isNotEmpty() }?.let { title = it }
            author = meta["creator"]?.takeIf { it.isNotEmpty() }
            lang = meta["language"]
        }
        return assemble(title, author, DocumentFormat.DOCX, name, parser.paragraphs, parser.headings, metaLanguage = lang)
    }

    private fun epub(file: File, name: String, base: String): ImportedDocument {
        val zip = runCatching { ZipArchive(file) }.getOrNull() ?: throw unreadable(name)
        val container = zip.data("META-INF/container.xml") ?: throw unreadable(name)
        val opfPath = SimpleXMLText.attribute("full-path", "rootfile", container) ?: throw unreadable(name)
        val opfData = zip.data(opfPath) ?: throw unreadable(name)
        val opf = OPFParser()
        opf.parse(opfData)
        val dir = parentOf(opfPath)

        // table of contents: file → title (EPUB 3 nav, else EPUB 2 NCX)
        val tocTitles = HashMap<String, String>()
        val navHref = opf.navHref
        val ncxHref = opf.ncxHref
        val nav = navHref?.let { zip.data(resolve(it, dir)) }
        if (navHref != null && nav != null) {
            val navDir = parentOf(resolve(navHref, dir))
            for ((href, title) in NavParser.links(nav)) {
                val f = resolve(href.substringBefore('#'), navDir)
                tocTitles.putIfAbsent(f, title)
            }
        } else if (ncxHref != null) {
            zip.data(resolve(ncxHref, dir))?.let { ncx ->
                val ncxDir = parentOf(resolve(ncxHref, dir))
                for ((src, title) in NCXParser.points(ncx)) {
                    val f = resolve(src.substringBefore('#'), ncxDir)
                    tocTitles.putIfAbsent(f, title)
                }
            }
        }

        val paragraphs = mutableListOf<String>()
        val headings = mutableListOf<Heading>()
        for (href in opf.spineHrefs) {
            val path = resolve(href, dir)
            val d = zip.data(path) ?: continue
            val out = MarkupText.convert(decode(d))
            if (out.paragraphs.isEmpty()) continue
            val start = paragraphs.size
            val t = tocTitles[path] ?: tocTitles.entries.firstOrNull { it.key.equals(path, true) }?.value
            if (t != null) {
                headings.add(Heading(start, t, 1))
                for (h in out.headings) if (h.level >= 2 && h.paragraph > 0) headings.add(Heading(start + h.paragraph, h.title, 2))
            } else if (tocTitles.isEmpty()) {
                for (h in out.headings) if (h.level <= 2) headings.add(Heading(start + h.paragraph, h.title, h.level))
            }
            paragraphs += out.paragraphs
        }
        val title = opf.title?.takeIf { it.isNotEmpty() } ?: base
        val imported = assemble(title, opf.creator?.takeIf { it.isNotEmpty() }, DocumentFormat.EPUB, name, paragraphs, headings,
            metaLanguage = opf.language)
        val cover = opf.coverHref?.let { zip.data(resolve(it, dir)) }?.let { CoverMaker.jpeg(it) }
        return if (cover != null) imported.copy(cover = cover) else imported
    }

    private fun pdf(file: File, name: String, base: String): ImportedDocument {
        appContext?.let { if (!com.tom_roush.pdfbox.android.PDFBoxResourceLoader.isReady()) init(it) }
        val p = PdfImport.read(file, name)
        val imported = assemble(p.title ?: base, p.author, DocumentFormat.PDF, name, p.paragraphs, p.headings, pageStarts = p.pageStarts)
        val cover = CoverMaker.jpegFromPdf(file)
        return if (cover != null) imported.copy(cover = cover) else imported
    }

    /**
     * PDF text breaks every line. Join lines back into paragraphs: a line continues the previous one unless the
     * previous line closes a sentence and is clearly shorter than a full line. Lone page numbers are dropped.
     */
    fun reflowPDF(raw: String): List<String> {
        val lines = raw.split(newlines).map { it.trim(' ', '\t', ' ') }
        val full = lines.map { it.length }.sorted().dropLast(lines.size / 10).lastOrNull() ?: 60
        val out = mutableListOf<String>()
        var cur = StringBuilder()
        var lastLine = 0                                 // length of the last physical line joined into `cur`
        for (line in lines) {
            if (line.isEmpty()) { if (cur.isNotEmpty()) { out.add(cur.toString()); cur = StringBuilder() }; continue }
            if (line.length <= 4 && line.all { it.isDigit() || it == '-' || it == '–' }) continue
            if (cur.isEmpty()) { cur.append(line); lastLine = line.length; continue }
            val last = cur[cur.length - 1]
            val ends = last in ".!?:”\"»)"
            val short = lastLine < full * 0.7
            val veryShort = lastLine < full * 0.55
            val f = line[0]
            val nextUpper = f.isUpperCase() || f.isDigit() || f in "“\"«"
            if (short && (ends || (veryShort && nextUpper))) {
                // a sentence that ends a short line, or a short title-like line followed by a capital: new paragraph
                out.add(cur.toString()); cur = StringBuilder(line)
            } else if (last == '-' && f.isLowerCase()) {
                cur.setLength(cur.length - 1); cur.append(line)
            } else {
                cur.append(' ').append(line)
            }
            lastLine = line.length
        }
        if (cur.isNotEmpty()) out.add(cur.toString())
        return out
    }

    // helpers

    private val windows1254: Charset = runCatching { Charset.forName("windows-1254") }.getOrElse { Charsets.ISO_8859_1 }

    /** UTF-8 (with or without BOM), UTF-16 by BOM, else Turkish Windows-1254, else Latin-1. */
    fun decode(data: ByteArray): String {
        if (data.size >= 3 && data[0] == 0xEF.toByte() && data[1] == 0xBB.toByte() && data[2] == 0xBF.toByte()) {
            return String(data, 3, data.size - 3, Charsets.UTF_8)
        }
        if (data.size >= 2 && data[0] == 0xFF.toByte() && data[1] == 0xFE.toByte()) return String(data, 2, data.size - 2, Charsets.UTF_16LE)
        if (data.size >= 2 && data[0] == 0xFE.toByte() && data[1] == 0xFF.toByte()) return String(data, 2, data.size - 2, Charsets.UTF_16BE)
        val strict = Charsets.UTF_8.newDecoder()
            .onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
        return try {
            strict.decode(ByteBuffer.wrap(data)).toString()
        } catch (_: Exception) {
            String(data, windows1254)
        }
    }

    fun splitParagraphs(text: String): List<String> =
        text.replace("\r\n", "\n").replace('\r', '\n').split('\n')
            .map { it.replace('\t', ' ').trim() }
            .filter { it.isNotEmpty() }

    private fun parentOf(path: String): String = if (path.contains('/')) path.substringBeforeLast('/') else ""

    /** "OEBPS" + "../Text/ch%201.xhtml" → "OEBPS/../Text/ch 1.xhtml" → "Text/ch 1.xhtml" */
    fun resolve(href: String, dir: String): String {
        val decoded = percentDecode(href)
        val parts = if (dir.isEmpty()) mutableListOf() else dir.split('/').filter { it.isNotEmpty() }.toMutableList()
        for (p in decoded.split('/').filter { it.isNotEmpty() }) {
            if (p == "..") { if (parts.isNotEmpty()) parts.removeAt(parts.size - 1) }
            else if (p != ".") parts.add(p)
        }
        return parts.joinToString("/")
    }

    /** %XX escapes as UTF-8 (not URLDecoder: a "+" in a file name stays a plus). */
    private fun percentDecode(s: String): String {
        if (!s.contains('%')) return s
        val out = ByteArrayOutputStream()
        var i = 0
        val bytes = s.toByteArray(Charsets.UTF_8)
        while (i < bytes.size) {
            val b = bytes[i]
            if (b == '%'.code.toByte() && i + 2 < bytes.size) {
                val v = String(bytes, i + 1, 2, Charsets.US_ASCII).toIntOrNull(16)
                if (v != null) { out.write(v); i += 3; continue }
            }
            out.write(b.toInt())
            i++
        }
        return runCatching { Charsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(out.toByteArray())).toString() }.getOrDefault(s)
    }

    /** The language from the text; a metadata language other than Turkish or English (which the guess cannot tell) wins. */
    private fun language(text: String, meta: String?): String {
        val m = meta?.trim()?.lowercase()?.substringBefore('-')?.substringBefore('_')?.takeIf { it.length in 2..3 && it.all(Char::isLetter) }
        if (m != null && m != "tr" && m != "en" && m != "und") return m
        return LanguageGuess.detect(text)
    }

    fun assemble(
        title: String, author: String?, format: DocumentFormat, sourceName: String,
        paragraphs: List<String>, headings: List<Heading>,
        pageStarts: List<Int>? = null, metaLanguage: String? = null,
    ): ImportedDocument {
        // every format goes through the same first pass for listening (TextCleaner)
        val clean = TextCleaner.clean(paragraphs, headings, paged = pageStarts != null)
        val paras = clean.paragraphs
        val offsets = IntArray(paras.size)
        val text = StringBuilder()
        for ((k, p) in paras.withIndex()) {
            offsets[k] = text.length
            text.append(p).append('\n')
        }
        val chapters = clean.headings.mapNotNull { h ->
            if (h.paragraph < offsets.size) Chapter(h.title, offsets[h.paragraph], h.level) else null
        }
        val s = text.toString()
        val pages = (pageStarts ?: emptyList()).map { k ->
            val n = if (k < clean.index.size) clean.index[k] else paras.size
            if (n < offsets.size) offsets[n] else s.length
        }
        return ImportedDocument(
            title = title.trim().ifEmpty { "Adsız" }, author = author, format = format, sourceName = sourceName,
            content = DocumentContent(s, chapters, pages),
            wordCount = countWords(s), language = language(s, metaLanguage),
        )
    }
}
