// What the library knows about a document (port of Model/Records.swift). The text itself lives in its own file
// (DocumentContent) and is loaded only when the document is opened, so the library stays small however many books
// it holds.
//
// The JSON shape is the iOS app's: dates are seconds since 2001-01-01 (Swift's JSONEncoder default) and ids are
// upper-case UUID strings, so content.json / library.json files can move between the two apps unchanged.
// Offsets are UTF-16 positions — the same unit as Kotlin's String indices.
package com.fatihgocgun.wisepath.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.util.UUID

/** Seconds between 1970-01-01 and 2001-01-01 (Apple's reference date). */
const val APPLE_EPOCH_OFFSET = 978_307_200.0

/** A moment, stored as Apple's reference-date seconds (Double) for compatibility with the iOS files. */
typealias Instant = @Serializable(with = AppleDateSerializer::class) Long

object AppleDateSerializer : KSerializer<Long> {
    override val descriptor = PrimitiveSerialDescriptor("AppleDate", PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Long) = encoder.encodeDouble(value / 1000.0 - APPLE_EPOCH_OFFSET)
    override fun deserialize(decoder: Decoder): Long = ((decoder.decodeDouble() + APPLE_EPOCH_OFFSET) * 1000).toLong()
}

fun now(): Long = System.currentTimeMillis()
fun newId(): String = UUID.randomUUID().toString().uppercase()

val AppJson = Json {
    ignoreUnknownKeys = true
    coerceInputValues = true          // an unknown colour or format falls back instead of failing
    explicitNulls = false
    encodeDefaults = true
    isLenient = true
}

@Serializable
enum class DocumentFormat(val badge: String) {
    @SerialName("pdf") PDF("PDF"),
    @SerialName("epub") EPUB("EPUB"),
    @SerialName("docx") DOCX("DOCX"),
    @SerialName("html") HTML("HTML"),
    @SerialName("rtf") RTF("RTF"),
    @SerialName("txt") TXT("TXT"),
    @SerialName("markdown") MARKDOWN("MD"),
    @SerialName("clipboard") CLIPBOARD("METİN"),
    @SerialName("mobi") MOBI("MOBI"),
    @SerialName("odt") ODT("ODT"),
    @SerialName("fb2") FB2("FB2"),
    @SerialName("doc") DOC("DOC"),
}

@Serializable
enum class HighlightColor(val label: String, val argb: Long) {
    @SerialName("yellow") YELLOW("Sarı", 0xFFFFDB40),
    @SerialName("blue") BLUE("Mavi", 0xFF73ADFF),
    @SerialName("red") RED("Kırmızı", 0xFFFF7373),
    @SerialName("green") GREEN("Yeşil", 0xFF73DB80),
}

@Serializable
data class Bookmark(
    val id: String = newId(),
    val offset: Int,
    val excerpt: String = "",
    val createdAt: Instant = now(),
)

@Serializable
data class Highlight(
    val id: String = newId(),
    val location: Int,
    val length: Int,
    val color: HighlightColor = HighlightColor.YELLOW,
    val text: String = "",
    val note: String? = null,
    val createdAt: Instant = now(),
) {
    val end: Int get() = location + length
}

/** A heading in the document, at its UTF-16 offset in the plain text. */
@Serializable
data class Chapter(val title: String, val offset: Int, val level: Int = 1)

/** The readable form of a document: plain text with one paragraph per line, its headings and (for PDF) page starts. */
@Serializable
data class DocumentContent(
    val text: String,
    val chapters: List<Chapter> = emptyList(),
    val pages: List<Int> = emptyList(),
)

@Serializable
data class DocumentRecord(
    val id: String = newId(),
    val title: String = "Adsız",
    val author: String? = null,
    val format: DocumentFormat = DocumentFormat.TXT,
    val sourceName: String = "",
    val folder: String? = null,
    val flag: HighlightColor? = null,
    val addedAt: Instant = now(),
    val lastOpenedAt: Instant? = null,
    val position: Int = 0,                      // UTF-16 offset of the speech cursor
    val length: Int = 0,
    val wordCount: Int = 0,
    val language: String? = null,               // BCP 47 code detected at import ("tr", "en"…)
    val voiceID: String? = null,                // document-specific voice, else the language default
    val speed: Double? = null,                  // document-specific speed, else the global speed
    val bookmarks: List<Bookmark> = emptyList(),
    val highlights: List<Highlight> = emptyList(),
    val positionAt: Instant? = null,            // when the position last changed (sync: newest wins)
    val partsApplied: Int? = null,
    val finishedAt: Instant? = null,            // the reading heard to the end; null while a reading goes on
    val finishes: List<Instant> = emptyList(),  // every reading heard to its end, oldest first
) {
    /** Finished is a fact written when the reading reached the end, never guessed from the place. */
    val isFinished: Boolean get() = finishedAt != null
    val isUnread: Boolean get() = position == 0 && lastOpenedAt == null && finishes.isEmpty()
    val isInProgress: Boolean get() = !isUnread && !isFinished
    val progress: Double get() = if (isFinished) 1.0 else if (length > 0) minOf(1.0, position.toDouble() / length) else 0.0
    /** 1 for the first reading, 2 once the book was started again after it was finished… */
    val readingNumber: Int get() = if (isFinished) maxOf(1, finishes.size) else finishes.size + 1
}

/** What an importer hands to the library. */
data class ImportedDocument(
    val title: String,
    val author: String?,
    val format: DocumentFormat,
    val sourceName: String,
    val content: DocumentContent,
    val wordCount: Int,
    val language: String?,
    val cover: ByteArray? = null,
)

fun countWords(text: String): Int {
    var n = 0
    var inWord = false
    for (c in text) {
        val space = c.isWhitespace()
        if (!space && !inWord) n++
        inWord = !space
    }
    return n
}
