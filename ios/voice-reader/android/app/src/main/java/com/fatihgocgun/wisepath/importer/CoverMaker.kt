// Cover images (port of Import/CoverMaker.swift): decoded and scaled down once at import, stored as JPEG next to the
// document. Android classes only — every call is guarded, so in JVM unit tests (where android.* is a stub) a cover
// simply comes out null.
package com.fatihgocgun.wisepath.importer

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.ParcelFileDescriptor
import java.io.ByteArrayOutputStream
import java.io.File

object CoverMaker {
    const val MAX_PIXEL = 600
    private const val QUALITY = 82

    /** Any image format Android decodes (JPEG, PNG, GIF, WebP…) → JPEG at most 600 px on the long side. */
    fun jpeg(imageData: ByteArray): ByteArray? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(imageData, 0, imageData.size, bounds)
        val w = bounds.outWidth
        val h = bounds.outHeight
        if (w <= 0 || h <= 0) return null
        // decode at the smallest power-of-two reduction that still covers 600 px, then scale exactly
        var sample = 1
        while (maxOf(w, h) / (sample * 2) >= MAX_PIXEL) sample *= 2
        val bmp = BitmapFactory.decodeByteArray(imageData, 0, imageData.size, BitmapFactory.Options().apply { inSampleSize = sample })
            ?: return null
        val scale = minOf(1f, MAX_PIXEL.toFloat() / maxOf(bmp.width, bmp.height))
        val scaled = if (scale < 1f) Bitmap.createScaledBitmap(bmp, maxOf(1, (bmp.width * scale).toInt()), maxOf(1, (bmp.height * scale).toInt()), true) else bmp
        encode(scaled)
    }.getOrNull()

    /** The first page of a PDF, 600 px tall, on white (PDF pages are often transparent). */
    fun jpegFromPdf(file: File): ByteArray? = runCatching {
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { fd ->
            PdfRenderer(fd).use { renderer ->
                if (renderer.pageCount == 0) return null
                renderer.openPage(0).use { page ->
                    if (page.height <= 0) return null
                    val scale = MAX_PIXEL.toFloat() / page.height
                    val w = maxOf(1, (page.width * scale).toInt())
                    val bmp = Bitmap.createBitmap(w, MAX_PIXEL, Bitmap.Config.ARGB_8888)
                    bmp.eraseColor(Color.WHITE)
                    page.render(bmp, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                    encode(bmp)
                }
            }
        }
    }.getOrNull()

    private fun encode(bmp: Bitmap): ByteArray? {
        val out = ByteArrayOutputStream()
        val opaque = if (bmp.hasAlpha()) {
            // JPEG has no alpha: a transparent PNG cover would turn black, so it is laid on white first
            Bitmap.createBitmap(bmp.width, bmp.height, Bitmap.Config.ARGB_8888).also {
                it.eraseColor(Color.WHITE)
                android.graphics.Canvas(it).drawBitmap(bmp, 0f, 0f, null)
            }
        } else bmp
        if (!opaque.compress(Bitmap.CompressFormat.JPEG, QUALITY, out)) return null
        return out.toByteArray().takeIf { it.isNotEmpty() }
    }
}
