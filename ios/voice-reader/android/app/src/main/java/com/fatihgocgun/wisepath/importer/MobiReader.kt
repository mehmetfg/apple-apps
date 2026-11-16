// Kindle books without DRM: MOBI, AZW, AZW3 (KF8) and PRC (port of Import/MobiReader.swift). A Palm database whose
// first record holds the PalmDOC and MOBI headers (and EXTH: author, title); the text records are PalmDOC-compressed
// HTML. Huffman-compressed (HUFF/CDIC) and encrypted books are refused with a message, not read wrongly.
package com.fatihgocgun.wisepath.importer

import java.nio.charset.Charset

object MobiReader {
    sealed class Failure : Exception() {
        object NotMobi : Failure()
        object Drm : Failure()
        object Huffman : Failure()
    }

    class Book(val html: String, val title: String?, val author: String?)

    fun read(b: ByteArray): Book {
        if (b.size <= 78) throw Failure.NotMobi
        val count = u16(b, 76)
        val offsets = mutableListOf<Int>()
        for (k in 0 until count) if (78 + k * 8 + 4 <= b.size) offsets.add(u32(b, 78 + k * 8).toInt())
        if (offsets.size < 2) throw Failure.NotMobi
        fun record(k: Int): ByteArray {
            val a = offsets[k]
            val z = if (k + 1 < offsets.size) offsets[k + 1] else b.size
            return if (a in 0 until z && z <= b.size) b.copyOfRange(a, z) else ByteArray(0)
        }
        val r0 = record(0)
        if (r0.size < 16) throw Failure.NotMobi
        val compression = u16(r0, 0)
        val textRecords = u16(r0, 8)
        if (u16(r0, 12) != 0) throw Failure.Drm
        if (compression == 17480) throw Failure.Huffman

        var utf8 = false
        var extraFlags = 0
        var title: String? = null
        var author: String? = null
        if (r0.size >= 24 && String(r0, 16, 4, Charsets.US_ASCII) == "MOBI") {
            val headerLength = u32(r0, 20).toInt()
            if (u32(r0, 28) == 65001L) utf8 = true
            fun str(from: Int, len: Int) = decode(r0.copyOfRange(from, from + len), utf8)
            if (headerLength >= 0xE4 && r0.size >= 16 + 0xF4) extraFlags = u16(r0, 16 + 0xE2)
            val nameAt = u32(r0, 84).toInt()
            val nameLength = u32(r0, 88).toInt()
            if (nameAt >= 0 && nameLength > 0 && nameAt + nameLength <= r0.size) title = str(nameAt, nameLength)
            // EXTH: 100 author, 503 updated title
            if (u32(r0, 128) and 0x40L != 0L) {
                var p = 16 + headerLength
                if (p >= 0 && p + 12 <= r0.size && String(r0, p, 4, Charsets.US_ASCII) == "EXTH") {
                    val n = u32(r0, p + 8).toInt()
                    p += 12
                    for (x in 0 until n) {
                        if (p + 8 > r0.size) break
                        val type = u32(r0, p)
                        val len = u32(r0, p + 4).toInt()
                        if (len < 8 || p + len > r0.size) break
                        val value = str(p + 8, len - 8)
                        if (type == 100L && author == null) author = value
                        if (type == 503L) title = value
                        p += len
                    }
                }
            }
        }

        val text = java.io.ByteArrayOutputStream()
        for (k in 1..maxOf(1, minOf(textRecords, offsets.size - 1))) {
            var r = record(k)
            val cut = minOf(r.size, trailing(r, extraFlags))
            if (cut > 0) r = r.copyOf(r.size - cut)
            text.write(if (compression == 2) palmDOC(r) else r)
        }
        val html = decode(text.toByteArray(), utf8)
        return Book(html, title?.trim(), author?.trim())
    }

    private val cp1252: Charset = Charset.forName("windows-1252")

    private fun decode(bytes: ByteArray, utf8: Boolean): String =
        if (utf8) String(bytes, Charsets.UTF_8) else String(bytes, cp1252)

    /** Bytes at the end of a text record that are not text (indexing data), as calibre measures them. */
    private fun trailing(r: ByteArray, flags: Int): Int {
        var num = 0
        var f = flags shr 1
        while (f != 0) {
            if (f and 1 != 0) {
                var size = r.size - num
                var bit = 0
                var value = 0
                while (size > 0) {
                    val v = r[size - 1].toInt() and 0xFF
                    value = value or ((v and 0x7F) shl bit)
                    bit += 7; size -= 1
                    if (v and 0x80 != 0 || bit >= 28) break
                }
                num += value
            }
            f = f shr 1
        }
        if (flags and 1 != 0 && r.size - num - 1 >= 0) num += (r[r.size - num - 1].toInt() and 0x3) + 1
        return num
    }

    /** PalmDOC LZ77. */
    private fun palmDOC(d: ByteArray): ByteArray {
        var out = ByteArray(maxOf(16, d.size * 2))
        var len = 0
        fun put(b: Int) {
            if (len == out.size) out = out.copyOf(out.size * 2)
            out[len++] = b.toByte()
        }
        var i = 0
        while (i < d.size) {
            val c = d[i].toInt() and 0xFF; i++
            when (c) {
                in 0x01..0x08 -> {
                    val end = minOf(d.size, i + c)
                    for (k in i until end) put(d[k].toInt())
                    i += c
                }
                0x00, in 0x09..0x7F -> put(c)
                in 0xC0..0xFF -> { put(0x20); put(c xor 0x80) }
                else -> {
                    if (i >= d.size) break
                    val v = ((c shl 8) or (d[i].toInt() and 0xFF)) and 0x3FFF; i++
                    val dist = v shr 3
                    val n = (v and 7) + 3
                    if (dist <= 0 || dist > len) continue
                    repeat(n) { put(out[len - dist].toInt()) }
                }
            }
        }
        return out.copyOf(len)
    }

    private fun u16(b: ByteArray, i: Int): Int =
        if (i >= 0 && i + 1 < b.size) ((b[i].toInt() and 0xFF) shl 8) or (b[i + 1].toInt() and 0xFF) else 0

    private fun u32(b: ByteArray, i: Int): Long =
        if (i >= 0 && i + 3 < b.size) (u16(b, i).toLong() shl 16) or u16(b, i + 2).toLong() else 0
}
