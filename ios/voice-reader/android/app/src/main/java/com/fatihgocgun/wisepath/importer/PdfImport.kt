// PDF text through pdfbox-android (iOS uses PDFKit): the text of each page, its lines joined back into paragraphs
// (DocumentImporter.reflowPDF), the outline as chapters, the page starts, and the first page as the cover.
package com.fatihgocgun.wisepath.importer

import com.tom_roush.pdfbox.pdmodel.PDDocument
import com.tom_roush.pdfbox.pdmodel.encryption.InvalidPasswordException
import com.tom_roush.pdfbox.pdmodel.interactive.documentnavigation.outline.PDOutlineNode
import com.tom_roush.pdfbox.text.PDFTextStripper
import java.io.File

internal object PdfImport {
    class Parsed(
        val paragraphs: List<String>,
        val headings: List<Heading>,
        val pageStarts: List<Int>,
        val title: String?,
        val author: String?,
    )

    fun read(file: File, name: String): Parsed {
        val doc = try {
            PDDocument.load(file)
        } catch (_: InvalidPasswordException) {
            throw ImportException("“$name” parolayla kilitli. Parolasız bir kopyasını ekle.")
        } catch (e: Exception) {
            throw ImportException("“$name” okunamadı.")
        }
        doc.use {
            // owner-password PDFs (printing/copying limits) open without a password; the limits do not apply to reading
            if (doc.isEncrypted) runCatching { doc.isAllSecurityToBeRemoved = true }
            val stripper = PDFTextStripper().apply {
                lineSeparator = "\n"
                paragraphStart = ""
                paragraphEnd = "\n"     // a gap PDFBox sees between blocks becomes a blank line, as PDFKit gives
                sortByPosition = true   // columns and out-of-order text runs read top to bottom
            }
            val pageCount = doc.numberOfPages
            val pageParagraphStart = ArrayList<Int>(pageCount)
            val paragraphs = ArrayList<String>()
            for (i in 1..pageCount) {
                pageParagraphStart.add(paragraphs.size)
                stripper.startPage = i
                stripper.endPage = i
                val raw = runCatching { stripper.getText(doc) }.getOrDefault("")
                paragraphs += DocumentImporter.reflowPDF(raw)
            }
            // headings from the PDF outline
            val headings = ArrayList<Heading>()
            val pages = doc.pages
            fun walk(node: PDOutlineNode, level: Int) {
                for (item in node.children()) {
                    val label = item.title?.trim().orEmpty()
                    val page = runCatching { item.findDestinationPage(doc) }.getOrNull()
                    val idx = if (page != null) pages.indexOf(page) else -1
                    if (idx >= 0 && idx < pageParagraphStart.size && label.isNotEmpty()) {
                        headings.add(Heading(pageParagraphStart[idx], label, level))
                    }
                    if (level < 2) walk(item, level + 1)
                }
            }
            runCatching { doc.documentCatalog.documentOutline?.let { walk(it, 1) } }
            val info = runCatching { doc.documentInformation }.getOrNull()
            val title = info?.title?.trim()?.takeIf { it.isNotEmpty() }
            val author = info?.author?.takeIf { it.isNotEmpty() }
            return Parsed(paragraphs, headings, pageParagraphStart, title, author)
        }
    }
}
