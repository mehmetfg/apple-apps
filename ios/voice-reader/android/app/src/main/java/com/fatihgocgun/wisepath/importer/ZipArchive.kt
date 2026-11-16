// Reads entries out of a ZIP file (EPUB, DOCX and ODT are ZIP files). Port of Import/ZipArchive.swift: stored and
// deflated entries; no ZIP64, no encryption. Hand-read rather than java.util.zip.ZipFile because ZipFile refuses
// archives with small defects (a bad local header, odd name bytes) that e-book tools write and the iOS app reads.
package com.fatihgocgun.wisepath.importer

import java.io.File
import java.util.zip.Inflater

class ZipArchive(private val data: ByteArray) {
    class Entry(val path: String, val method: Int, val compressedSize: Int, val size: Int, val localHeaderOffset: Int)

    class ZipError(message: String) : Exception(message)

    /** Path → entry, in central-directory order. */
    val entries = LinkedHashMap<String, Entry>()

    constructor(file: File) : this(file.readBytes())

    init { readDirectory() }

    val paths: List<String> get() = entries.keys.toList()

    private fun u16(at: Int): Int =
        if (at < 0 || at + 2 > data.size) 0 else (data[at].toInt() and 0xFF) or ((data[at + 1].toInt() and 0xFF) shl 8)

    private fun u32(at: Int): Long =
        if (at < 0 || at + 4 > data.size) 0 else
            (u16(at).toLong()) or (u16(at + 2).toLong() shl 16)

    private fun readDirectory() {
        // the end-of-central-directory record is in the last 64 KiB + 22 bytes
        val n = data.size
        if (n < 22) throw ZipError("notZip")
        var eocd = -1
        var i = n - 22
        val floor = maxOf(0, n - 65_557)
        while (i >= floor) {
            if (u32(i) == 0x0605_4B50L) { eocd = i; break }
            i--
        }
        if (eocd < 0) throw ZipError("notZip")
        val count = u16(eocd + 10)
        var p = u32(eocd + 16).toInt()
        repeat(count) {
            if (p < 0 || p + 46 > n || u32(p) != 0x0201_4B50L) throw ZipError("corrupt")
            val method = u16(p + 10)
            val csize = u32(p + 20).toInt()
            val size = u32(p + 24).toInt()
            val nameLen = u16(p + 28)
            val extraLen = u16(p + 30)
            val commentLen = u16(p + 32)
            val local = u32(p + 42).toInt()
            if (p + 46 + nameLen > n) throw ZipError("corrupt")
            val name = String(data, p + 46, nameLen, Charsets.UTF_8)
            entries[name] = Entry(name, method, csize, size, local)
            p += 46 + nameLen + extraLen + commentLen
        }
    }

    /**
     * The entry's bytes, or null if it is missing or cannot be read. Lookup ignores case as a fallback
     * (some EPUBs reference "Text/ch1.xhtml" while the archive holds "text/ch1.xhtml").
     */
    fun data(path: String): ByteArray? {
        val e = entries[path] ?: entries.entries.firstOrNull { it.key.equals(path, ignoreCase = true) }?.value ?: return null
        val h = e.localHeaderOffset
        if (u32(h) != 0x0403_4B50L) return null
        val start = h + 30 + u16(h + 26) + u16(h + 28)
        if (e.compressedSize < 0 || start + e.compressedSize > data.size) return null
        return when (e.method) {
            0 -> data.copyOfRange(start, start + e.compressedSize)
            8 -> inflate(start, e.compressedSize, e.size)
            else -> null
        }
    }

    private fun inflate(start: Int, length: Int, size: Int): ByteArray? {
        if (size == 0) return ByteArray(0)
        if (length == 0) return null
        val inf = Inflater(true)     // raw DEFLATE (RFC 1951), which is what ZIP stores
        return try {
            inf.setInput(data, start, length)
            val out = ByteArray(maxOf(size, 0))
            var written = 0
            while (written < out.size && !inf.finished()) {
                val k = inf.inflate(out, written, out.size - written)
                if (k == 0 && (inf.needsInput() || inf.needsDictionary())) break
                written += k
            }
            if (written <= 0) null else if (written == out.size) out else out.copyOf(written)
        } catch (_: Exception) {
            null
        } finally {
            inf.end()
        }
    }
}
