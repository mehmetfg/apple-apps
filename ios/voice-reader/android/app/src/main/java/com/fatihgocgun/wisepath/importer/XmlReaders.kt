// Small XML readers for the package formats (port of the XMLParser delegates in Import/DocumentImporter.swift).
// SAX from javax.xml, which Android and the JVM both have, without namespace processing so element names keep their
// prefix ("w:p", "dc:title") as they do in Foundation's XMLParser. A parse error stops the reading but keeps what was
// found up to it, as XMLParser does.
package com.fatihgocgun.wisepath.importer

import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.helpers.DefaultHandler
import java.io.ByteArrayInputStream
import java.io.StringReader
import javax.xml.parsers.SAXParserFactory

internal object Xml {
    private class Stop : RuntimeException()

    /** Runs `handler` over `data`; external DTDs (NCX, XHTML doctypes) are never fetched. */
    fun parse(data: ByteArray, handler: DefaultHandler) {
        try {
            val f = SAXParserFactory.newInstance()
            f.isNamespaceAware = false
            f.isValidating = false
            runCatching { f.setFeature("http://apache.org/xml/features/nonvalidating/load-external-dtd", false) }
            val reader = f.newSAXParser().xmlReader
            reader.contentHandler = handler
            reader.errorHandler = handler
            reader.setEntityResolver { _, _ -> InputSource(StringReader("")) }
            reader.parse(InputSource(ByteArrayInputStream(data)))
        } catch (_: Stop) {
        } catch (_: Exception) {
        }
    }

    fun stop(): Nothing = throw Stop()

    fun local(qName: String): String = qName.substringAfterLast(':')
}

/** Text of the first element with each given local name ("dc:title" → "title"). */
internal object SimpleXMLText {
    fun values(data: ByteArray, names: Set<String>): Map<String, String> {
        val found = HashMap<String, String>()
        var current: String? = null
        val buffer = StringBuilder()
        Xml.parse(data, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String, a: Attributes) {
                val local = Xml.local(qName)
                if (current == null && local in names && local !in found) { current = local; buffer.setLength(0) }
            }
            override fun characters(ch: CharArray, start: Int, length: Int) { if (current != null) buffer.append(ch, start, length) }
            override fun endElement(uri: String?, localName: String?, qName: String) {
                val local = Xml.local(qName)
                if (local == current) { found[local] = buffer.toString().trim(); current = null }
            }
        })
        return found
    }

    fun attribute(attr: String, element: String, data: ByteArray): String? {
        var value: String? = null
        Xml.parse(data, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String, a: Attributes) {
                if (Xml.local(qName) == element) {
                    a.getValue(attr)?.let { value = it; Xml.stop() }
                }
            }
        })
        return value
    }
}

/** EPUB package: title, creator, language, manifest, spine, navigation documents, cover. */
internal class OPFParser {
    var title: String? = null
    var creator: String? = null
    var language: String? = null
    var navHref: String? = null
    var ncxHref: String? = null
    var spineHrefs: List<String> = emptyList()
    var coverHref: String? = null
    private var coverID: String? = null
    private val manifest = LinkedHashMap<String, Pair<String, String>>()   // id → (href, media type)
    private val spineIDs = mutableListOf<String>()
    private var tocID: String? = null

    fun parse(data: ByteArray) {
        var current: String? = null
        val buffer = StringBuilder()
        Xml.parse(data, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String, a: Attributes) {
                when (val local = Xml.local(qName)) {
                    "item" -> {
                        val id = a.getValue("id")
                        val href = a.getValue("href")
                        if (id != null && href != null) {
                            manifest[id] = href to (a.getValue("media-type") ?: "")
                            val props = (a.getValue("properties") ?: "").split(' ')
                            if ("nav" in props) navHref = href
                            if ("cover-image" in props) coverHref = href
                        }
                    }
                    "itemref" -> {
                        val idref = a.getValue("idref")
                        if (idref != null && a.getValue("linear") != "no") spineIDs.add(idref)
                    }
                    "spine" -> tocID = a.getValue("toc")
                    "meta" -> if (a.getValue("name") == "cover") a.getValue("content")?.let { coverID = it }
                    "title", "creator", "language" -> { current = local; buffer.setLength(0) }
                }
            }
            override fun characters(ch: CharArray, start: Int, length: Int) { if (current != null) buffer.append(ch, start, length) }
            override fun endElement(uri: String?, localName: String?, qName: String) {
                val local = Xml.local(qName)
                if (local != current) return
                val v = buffer.toString().trim()
                if (local == "title" && title == null) title = v
                if (local == "creator" && creator == null) creator = v
                if (local == "language" && language == null) language = v
                current = null
            }
        })
        spineHrefs = spineIDs.mapNotNull { manifest[it]?.first }
        if (coverHref == null) coverID?.let { coverHref = manifest[it]?.first }
        if (coverHref == null) {
            coverHref = manifest.entries.firstOrNull { (id, v) ->
                (id.lowercase().contains("cover") || v.first.lowercase().contains("cover")) && v.second.startsWith("image/")
            }?.value?.first
        }
        tocID?.let { ncxHref = manifest[it]?.first }
        if (ncxHref == null) ncxHref = manifest.values.firstOrNull { it.second == "application/x-dtbncx+xml" }?.first
    }
}

/** EPUB 3 navigation document: the <a href> links inside the toc <nav>, with their text. */
internal object NavParser {
    private val navStart = Regex("<nav[^>]*epub:type\\s*=\\s*[\"']toc[\"'][^>]*>")
    private val link = Regex("<a[^>]*href\\s*=\\s*[\"']([^\"']+)[\"'][^>]*>(.*?)</a>", setOf(RegexOption.DOT_MATCHES_ALL, RegexOption.IGNORE_CASE))
    private val tag = Regex("<[^>]+>")

    fun links(data: ByteArray): List<Pair<String, String>> {
        val html = DocumentImporter.decode(data)
        var scope = html
        navStart.find(html)?.let { r ->
            val end = html.indexOf("</nav>", r.range.last + 1)
            if (end >= 0) scope = html.substring(r.range.last + 1, end)
        }
        return link.findAll(scope).mapNotNull { m ->
            val title = MarkupText.decodeEntities(tag.replace(m.groupValues[2], "")).trim()
            if (title.isEmpty()) null else m.groupValues[1] to title
        }.toList()
    }
}

/** EPUB 2 NCX: navPoint label + content src, in document order. */
internal object NCXParser {
    fun points(data: ByteArray): List<Pair<String, String>> {
        val out = mutableListOf<Pair<String, String>>()
        val label = StringBuilder()
        var inText = false
        Xml.parse(data, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String, a: Attributes) {
                when (Xml.local(qName)) {
                    "navPoint" -> label.setLength(0)
                    "text" -> inText = true
                    "content" -> a.getValue("src")?.let { src ->
                        val t = label.toString().trim()
                        if (t.isNotEmpty()) out.add(src to t)
                    }
                }
            }
            override fun characters(ch: CharArray, start: Int, length: Int) { if (inText) label.append(ch, start, length) }
            override fun endElement(uri: String?, localName: String?, qName: String) { if (Xml.local(qName) == "text") inText = false }
        })
        return out
    }
}

/** DOCX body: w:p paragraphs of w:t runs; heading styles become chapters. */
internal class DocxParser {
    val paragraphs = mutableListOf<String>()
    val headings = mutableListOf<Heading>()

    fun parse(data: ByteArray) {
        val current = StringBuilder()
        var inText = false
        var headingLevel: Int? = null
        Xml.parse(data, object : DefaultHandler() {
            override fun startElement(uri: String?, localName: String?, qName: String, a: Attributes) {
                when (qName) {
                    "w:p" -> { current.setLength(0); headingLevel = null }
                    "w:t" -> inText = true
                    "w:tab", "w:br", "w:cr" -> current.append(' ')
                    "w:pStyle" -> {
                        val v = (a.getValue("w:val") ?: "").lowercase()
                        if (v == "title") headingLevel = 1
                        else if (v.startsWith("heading") || v.startsWith("balk") || v.startsWith("başlık")) {
                            headingLevel = v.filter { it.isDigit() }.toIntOrNull() ?: 1
                        }
                    }
                }
            }
            override fun characters(ch: CharArray, start: Int, length: Int) { if (inText) current.append(ch, start, length) }
            override fun endElement(uri: String?, localName: String?, qName: String) {
                if (qName == "w:t") inText = false
                if (qName == "w:p") {
                    val p = current.toString().trim()
                    if (p.isEmpty()) return
                    val lv = headingLevel
                    if (lv != null && lv <= 3) headings.add(Heading(paragraphs.size, p.take(140), lv))
                    paragraphs.add(p)
                }
            }
        })
    }
}
