package com.fatihgocgun.wisepath.importer

import com.fatihgocgun.wisepath.model.DocumentFormat
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.charset.Charset
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

class DocumentImporterTest {
    @get:Rule val tmp = TemporaryFolder()

    private fun file(name: String, bytes: ByteArray): File = tmp.newFile(name).also { it.writeBytes(bytes) }

    private fun zip(entries: List<Pair<String, String>>, stored: Set<String> = emptySet()): ByteArray {
        val bos = ByteArrayOutputStream()
        ZipOutputStream(bos).use { z ->
            for ((path, body) in entries) {
                val bytes = body.toByteArray()
                val e = ZipEntry(path)
                if (path in stored) {
                    e.method = ZipEntry.STORED
                    e.size = bytes.size.toLong(); e.compressedSize = bytes.size.toLong()
                    e.crc = java.util.zip.CRC32().also { it.update(bytes) }.value
                }
                z.putNextEntry(e); z.write(bytes); z.closeEntry()
            }
        }
        return bos.toByteArray()
    }

    /** Each chapter's offset points at its title's line in the text. */
    private fun assertChaptersAligned(text: String, chapters: List<com.fatihgocgun.wisepath.model.Chapter>) {
        for (c in chapters) {
            assertTrue("offset ${c.offset} at line start", c.offset == 0 || text[c.offset - 1] == '\n')
            val line = text.substring(c.offset).substringBefore('\n')
            assertEquals(c.title, line)
        }
    }

    @Test fun epub3WithNavAndCover() {
        val container = """<?xml version="1.0"?><container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
            <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles></container>"""
        val opf = """<?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" xmlns:dc="http://purl.org/dc/elements/1.1/">
            <metadata><dc:title>Küçük Kitap</dc:title><dc:creator>Ayşe Yazar</dc:creator><dc:language>tr</dc:language></metadata>
            <manifest>
              <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
              <item id="c1" href="Text/ch%201.xhtml" media-type="application/xhtml+xml"/>
              <item id="c2" href="Text/ch2.xhtml" media-type="application/xhtml+xml"/>
              <item id="img" href="Images/cover.jpg" media-type="image/jpeg" properties="cover-image"/>
            </manifest>
            <spine><itemref idref="c1"/><itemref idref="c2"/></spine></package>"""
        val nav = """<html xmlns:epub="http://www.idpf.org/2007/ops"><body><nav epub:type="toc"><ol>
            <li><a href="Text/ch%201.xhtml">Birinci Bölüm</a></li><li><a href="Text/ch2.xhtml#x">İkinci &amp; Son</a></li></ol></nav></body></html>"""
        val ch1 = """<?xml version="1.0"?><!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">
            <html><head><title>x</title><style>p{}</style></head><body><h1>Birinci Bölüm</h1>
            <p>Bu bir deneme metnidir ve okunacak.</p><h2>Alt başlık</h2><p>Sonra&nbsp;gelen paragraf da var.</p></body></html>"""
        val ch2 = "<html><body><h1>İkinci &amp; Son</h1><p>Kitabın son cümlesi burada.</p></body></html>"
        val bytes = zip(listOf(
            "mimetype" to "application/epub+zip", "META-INF/container.xml" to container, "OEBPS/content.opf" to opf,
            "OEBPS/nav.xhtml" to nav, "OEBPS/Text/ch 1.xhtml" to ch1, "OEBPS/Text/ch2.xhtml" to ch2,
            "OEBPS/Images/cover.jpg" to "notreallyajpeg",
        ), stored = setOf("mimetype"))
        val d = DocumentImporter.importFile(file("book.epub", bytes), "Kitap.epub")
        assertEquals(DocumentFormat.EPUB, d.format)
        assertEquals("Küçük Kitap", d.title)
        assertEquals("Ayşe Yazar", d.author)
        assertEquals("tr", d.language)
        assertEquals("Kitap.epub", d.sourceName)
        val text = d.content.text
        assertEquals(
            "Birinci Bölüm\nBu bir deneme metnidir ve okunacak.\nAlt başlık\nSonra gelen paragraf da var.\nİkinci & Son\nKitabın son cümlesi burada.\n",
            text,
        )
        assertEquals(listOf("Birinci Bölüm" to 1, "Alt başlık" to 2, "İkinci & Son" to 1), d.content.chapters.map { it.title to it.level })
        assertChaptersAligned(text, d.content.chapters)
        assertEquals(text.indexOf("İkinci"), d.content.chapters[2].offset)
        assertNull(d.cover)                    // no Android bitmap decoder in JVM tests
        assertEquals(com.fatihgocgun.wisepath.model.countWords(text), d.wordCount)
    }

    @Test fun epub2WithNcx() {
        val container = """<container><rootfiles><rootfile full-path="content.opf"/></rootfiles></container>"""
        val opf = """<package xmlns:dc="http://purl.org/dc/elements/1.1/"><metadata><dc:title>The Book</dc:title></metadata>
            <manifest><item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
            <item id="a" href="a.html" media-type="application/xhtml+xml"/><item id="b" href="b.html" media-type="application/xhtml+xml"/></manifest>
            <spine toc="ncx"><itemref idref="a"/><itemref idref="b"/></spine></package>"""
        val ncx = """<?xml version="1.0"?><!DOCTYPE ncx PUBLIC "-//NISO//DTD ncx 2005-1//EN" "http://www.daisy.org/z3986/2005/ncx-2005-1.dtd">
            <ncx><navMap><navPoint id="p1"><navLabel><text>Chapter One</text></navLabel><content src="a.html"/></navPoint>
            <navPoint id="p2"><navLabel><text>Chapter Two</text></navLabel><content src="b.html#top"/></navPoint></navMap></ncx>"""
        val a = "<html><body><p>Chapter One</p><p>It was the best of times, and it was the worst of times for them.</p></body></html>"
        val b = "<html><body><p>Chapter Two</p><p>This is the end of the story that we have to tell you.</p></body></html>"
        val bytes = zip(listOf("META-INF/container.xml" to container, "content.opf" to opf, "toc.ncx" to ncx, "a.html" to a, "b.html" to b))
        val d = DocumentImporter.importFile(file("b.epub", bytes))
        assertEquals("The Book", d.title)
        assertEquals("en", d.language)
        assertEquals(listOf("Chapter One", "Chapter Two"), d.content.chapters.map { it.title })
        assertChaptersAligned(d.content.text, d.content.chapters)
    }

    @Test fun docxHeadingsAndMeta() {
        val w = """xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main""""
        val body = """<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document $w><w:body>
            <w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t>Rapor</w:t></w:r></w:p>
            <w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Giriş</w:t></w:r></w:p>
            <w:p><w:r><w:t xml:space="preserve">Bu raporun </w:t></w:r><w:r><w:t>ilk paragrafı.</w:t></w:r></w:p>
            <w:p></w:p>
            <w:p><w:pPr><w:pStyle w:val="Balk2"/></w:pPr><w:r><w:t>Ayrıntı</w:t></w:r></w:p>
            <w:p><w:r><w:t>Bir</w:t></w:r><w:r><w:tab/><w:t>iki.</w:t></w:r></w:p>
            </w:body></w:document>"""
        val core = """<cp:coreProperties xmlns:cp="x" xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>Yıllık Rapor</dc:title><dc:creator>Mehmet</dc:creator></cp:coreProperties>"""
        val d = DocumentImporter.importFile(file("r.docx", zip(listOf("word/document.xml" to body, "docProps/core.xml" to core))))
        assertEquals("Yıllık Rapor", d.title)
        assertEquals("Mehmet", d.author)
        assertEquals("Rapor\nGiriş\nBu raporun ilk paragrafı.\nAyrıntı\nBir iki.\n", d.content.text)
        assertEquals(listOf(Triple("Rapor", 0, 1), Triple("Giriş", 6, 1), Triple("Ayrıntı", 38, 2)),
            d.content.chapters.map { Triple(it.title, it.offset, it.level) })
        assertChaptersAligned(d.content.text, d.content.chapters)
    }

    @Test fun odt() {
        val content = """<office:document-content xmlns:office="o" xmlns:text="t"><office:body><office:text>
            <text:h text:outline-level="1">Başlık</text:h><text:p text:style-name="P1">Birinci<text:s/>satır<text:line-break/>devam.</text:p>
            </office:text></office:body></office:document-content>"""
        val meta = """<office:document-meta xmlns:office="o" xmlns:dc="d"><office:meta><dc:title>Belge</dc:title><meta:initial-creator xmlns:meta="m">Ali</meta:initial-creator></office:meta></office:document-meta>"""
        val d = DocumentImporter.importFile(file("a.odt", zip(listOf("content.xml" to content, "meta.xml" to meta))))
        assertEquals("Belge", d.title)
        assertEquals("Ali", d.author)
        assertEquals("Başlık\nBirinci satır devam.\n", d.content.text)
        assertEquals("Başlık", d.content.chapters.single().title)
    }

    @Test fun htmlTitleHeadingsEntities() {
        val html = """<html><head><title>Sayfa &amp; Başlık</title><script>var x = "<p>no</p>";</script></head>
            <body><!-- yorum <p>gizli</p> --><h1>Bir <em>başlık</em></h1><div>İlk&#x20;paragraf &#8220;tırnak&#8221;.</div>
            <p>Resim: <img alt="bir kedi" src="k.png"> burada.</p><h2>İkinci</h2><ul><li>madde bir.</li><li>madde iki.</li></ul></body></html>"""
        val d = DocumentImporter.importFile(file("s.html", html.toByteArray()))
        assertEquals("Sayfa & Başlık", d.title)
        assertEquals("Bir başlık\nİlk paragraf “tırnak”.\nResim: bir kedi burada.\nİkinci\nmadde bir.\nmadde iki.\n", d.content.text)
        assertEquals(listOf("Bir başlık" to 1, "İkinci" to 2), d.content.chapters.map { it.title to it.level })
        assertChaptersAligned(d.content.text, d.content.chapters)
    }

    @Test fun rtf() {
        val rtf = """{\rtf1\ansi\ansicpg1252\deff0{\fonttbl{\f0\fswiss Helvetica;}{\f1\fcharset162 Arial TUR;}}
{\colortbl;\red0\green0\blue0;}{\info{\title Gizli}{\author X}}
\f0\fs24 Merhaba d\u252\'fcnya\par
{\f1 Ayd\'fdnl\'fdk \'fe\'f0}\par
{\*\generator Riched20;}Son \ldblquote s\'f6z\rdblquote\line ikinci sat\u305?r.\par}"""
        val d = DocumentImporter.importFile(file("m.rtf", rtf.toByteArray(Charsets.US_ASCII)))
        assertEquals(DocumentFormat.RTF, d.format)
        assertEquals("m", d.title)
        assertEquals("Merhaba dünya\nAydınlık şğ\nSon “söz”\nikinci satır.\n", d.content.text)
    }

    @Test fun markdown() {
        val md = "---\ntitle: x\n---\n# Ana Başlık\n\nBir **kalın** ve [bağlantı](http://a.b) metin.\n\n## Alt\n- madde\n```\nkod\n```\n| a | b |\n|---|---|\n> alıntı\n"
        val d = DocumentImporter.importFile(file("n.md", md.toByteArray()))
        assertEquals(DocumentFormat.MARKDOWN, d.format)
        assertEquals("Ana Başlık", d.title)
        assertEquals("Ana Başlık\nBir kalın ve bağlantı metin.\nAlt\nmadde\nkod\na · b\nalıntı\n", d.content.text)
        assertEquals(listOf("Ana Başlık" to 1, "Alt" to 2), d.content.chapters.map { it.title to it.level })
        assertChaptersAligned(d.content.text, d.content.chapters)
    }

    @Test fun windows1254AndBoms() {
        val s = "Işık ve gölge, şimdi çağ.\nİkinci satır ğüş."
        val d = DocumentImporter.importFile(file("t.txt", s.toByteArray(Charset.forName("windows-1254"))))
        assertEquals("$s\n", d.content.text)
        assertEquals("tr", d.language)
        val u16 = byteArrayOf(0xFF.toByte(), 0xFE.toByte()) + "Çok güzel.".toByteArray(Charsets.UTF_16LE)
        assertEquals("Çok güzel.\n", DocumentImporter.importFile(file("u.txt", u16)).content.text)
        val u8 = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte()) + "Öykü.".toByteArray()
        assertEquals("Öykü.\n", DocumentImporter.importFile(file("v.txt", u8)).content.text)
    }

    @Test fun fb2() {
        val fb2 = """<?xml version="1.0" encoding="utf-8"?><FictionBook xmlns="http://www.gribuser.ru/xml/fictionbook/2.0">
            <description><title-info><author><first-name>Lev</first-name><last-name>Tolstoy</last-name></author>
            <book-title>Savaş ve Barış</book-title><lang>tr</lang></title-info></description>
            <body><section><title><p>Birinci Kısım</p></title><p>Eh bien, mon prince, ve böyle başladı.</p></section>
            <section><title><p>İkinci Kısım</p></title><p>Sonra her şey değişti.</p></section></body>
            <binary id="c.jpg" content-type="image/jpeg">AAAA</binary></FictionBook>"""
        val d = DocumentImporter.importFile(file("w.fb2", fb2.toByteArray()))
        assertEquals("Savaş ve Barış", d.title)
        assertEquals("Lev Tolstoy", d.author)
        assertEquals("Birinci Kısım\nEh bien, mon prince, ve böyle başladı.\nİkinci Kısım\nSonra her şey değişti.\n", d.content.text)
        assertEquals(listOf("Birinci Kısım", "İkinci Kısım"), d.content.chapters.map { it.title })
        assertChaptersAligned(d.content.text, d.content.chapters)
    }

    @Test fun mobiPalmDoc() {
        // a minimal PalmDB: record 0 = PalmDOC header (no compression), record 1 = HTML text
        val html = "<html><body><h1>Bölüm</h1><p>Mobi metni burada.</p><mbp:pagebreak/><p>Son.</p></body></html>".toByteArray(Charset.forName("windows-1252"))
        val r0 = ByteArray(16).also { it[1] = 1; it[9] = 1 }   // compression 1, 1 text record
        val header = ByteArray(78 + 2 * 8)
        header[77] = 2
        val off0 = header.size
        val off1 = off0 + r0.size
        fun put32(at: Int, v: Int) { header[at] = (v ushr 24).toByte(); header[at + 1] = (v ushr 16).toByte(); header[at + 2] = (v ushr 8).toByte(); header[at + 3] = v.toByte() }
        put32(78, off0); put32(86, off1)
        val d = DocumentImporter.importFile(file("k.mobi", header + r0 + html))
        assertEquals("Bölüm\nMobi metni burada.\nSon.\n", d.content.text)
        assertEquals("Bölüm", d.content.chapters.single().title)
    }

    @Test fun mobiDrmRefused() {
        val header = ByteArray(78 + 16)
        header[77] = 2
        header[81] = (78 + 16).toByte()
        header[89] = (78 + 32).toByte()
        val r0 = ByteArray(16).also { it[13] = 1 }
        try { DocumentImporter.importFile(file("l.azw", header + r0 + ByteArray(4))); fail() }
        catch (e: ImportException) { assertTrue(e.message!!.contains("DRM")) }
    }

    @Test fun legacyDoc() {
        val text = "Bu eski bir Word belgesinin metnidir ve okunabilir olmalı.\rİkinci paragraf da burada duruyor efendim."
        val bytes = ByteArray(300) { if (it % 7 == 0) 0x13 else 0 } + text.toByteArray(Charsets.UTF_16LE) + ByteArray(200)
        val d = DocumentImporter.importFile(file("e.doc", bytes))
        assertEquals("Bu eski bir Word belgesinin metnidir ve okunabilir olmalı.\nİkinci paragraf da burada duruyor efendim.\n", d.content.text)
    }

    @Test fun unsupportedAndEmpty() {
        try { DocumentImporter.importFile(file("x.xyz", byteArrayOf(1))); fail() }
        catch (e: ImportException) { assertEquals("“x.xyz” biçimi desteklenmiyor.", e.message) }
        try { DocumentImporter.importFile(file("y.txt", "  \n\n".toByteArray())); fail() }
        catch (e: ImportException) { assertTrue(e.message!!.startsWith("“y.txt” içinde okunacak metin")) }
        try { DocumentImporter.importFile(file("z.epub", "not a zip".toByteArray())); fail() }
        catch (e: ImportException) { assertEquals("“z.epub” okunamadı.", e.message) }
    }

    @Test fun clipboard() {
        val d = DocumentImporter.fromClipboard("Kısa bir not.\n\nİkinci satır burada.")
        assertEquals(DocumentFormat.CLIPBOARD, d.format)
        assertEquals("Kısa bir not.", d.title)
        assertEquals("Pano", d.sourceName)
        val m = DocumentImporter.fromClipboard("# Cevap\nMetin.\n## Ayrıntı\nDaha fazla.")
        assertEquals("Cevap", m.title)
        assertEquals(2, m.content.chapters.size)
    }

    @Test fun cleanerAndReflow() {
        val raw = "Bu satır bir cümlenin ortasında kesildi ve\ndevam ediyor burada.\n12\n* * *\nYeni para-\ngraf."
        val d = DocumentImporter.fromClipboard(raw)
        assertEquals("Bu satır bir cümlenin ortasında kesildi ve devam ediyor burada.\nYeni paragraf.\n", d.content.text)
        val lines = DocumentImporter.reflowPDF("Uzun bir satır burada gelir ve devam eder\nsonraki satırda bitti.\n\n3\nYeni.")
        assertEquals(listOf("Uzun bir satır burada gelir ve devam eder sonraki satırda bitti.", "Yeni."), lines)
        assertEquals("Bölüm bir: yolun başı ve sonu geldi", TextCleaner.uncapital("BÖLÜM BİR: YOLUN BAŞI VE SONU GELDİ"))
    }

    @Test fun pageStartsMapThroughCleaner() {
        val paragraphs = listOf("Sayfa bir metni.", "1", "Sayfa iki metni.", "2", "Üçüncü sayfa.")
        val d = DocumentImporter.assemble("t", null, DocumentFormat.PDF, "t.pdf", paragraphs, listOf(Heading(2, "İki", 1)), pageStarts = listOf(0, 1, 3))
        assertEquals("Sayfa bir metni.\nSayfa iki metni.\nÜçüncü sayfa.\n", d.content.text)
        // page 2 starts at the dropped "1" → the next kept paragraph; page 3 at the dropped "2" → "Üçüncü"
        assertEquals(listOf(0, 17, 34), d.content.pages)
        assertEquals(17, d.content.chapters.single().offset)
    }
}
