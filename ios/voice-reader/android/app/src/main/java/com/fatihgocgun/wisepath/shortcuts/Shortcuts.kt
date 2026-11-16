// The icon's quick actions (port of QuickActions in WidgetFeed.swift and WisePathShortcuts.swift): long-press the app
// icon for "Kaldığın yerden dinle" (with the book), the moving mode, music and "Cümleyi işaretle". Each one is a
// wisepath:// link that MainActivity's DeepLinks performs. Siri phrases have no Android counterpart; a launcher
// shortcut can be pinned to the home screen instead.
package com.fatihgocgun.wisepath.shortcuts

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.net.Uri
import androidx.core.content.pm.ShortcutInfoCompat
import androidx.core.content.pm.ShortcutManagerCompat
import androidx.core.graphics.drawable.IconCompat
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.MainActivity

/** Sets the dynamic shortcuts; call again when the book to go on with changes (WidgetFeed does). */
fun installShortcuts(context: Context) {
    val app = AppModel.get(context)
    val current = app.currentDocument ?: app.store.documents.value
        .filter { it.lastOpenedAt != null && !it.isFinished }.maxByOrNull { it.lastOpenedAt!! }
    installShortcuts(context, current?.title)
}

/** The same, with the title already known (off the main thread too). */
fun installShortcuts(context: Context, currentTitle: String?) {
    val list = mutableListOf<ShortcutInfoCompat>()
    if (currentTitle != null) {
        list.add(shortcut(context, "resume", "Kaldığın yerden dinle", currentTitle, "wisepath://continue", "▶", 0xFFFF3601.toInt()))
    }
    list.add(shortcut(context, "bike", "Bisiklet modu", "Yolda · GPS", "wisepath://ride", "🚲", 0xFF2E9E6A.toInt()))
    list.add(shortcut(context, "music", "Müzik modu", null, "wisepath://music", "♪", 0xFF8E5CC4.toInt()))
    list.add(shortcut(context, "mark", "Cümleyi işaretle", null, "wisepath://mark", "✎", 0xFFD9A02B.toInt()))
    val max = runCatching { ShortcutManagerCompat.getMaxShortcutCountPerActivity(context) }.getOrDefault(4).coerceAtLeast(1)
    runCatching { ShortcutManagerCompat.setDynamicShortcuts(context, list.take(max)) }
}

private fun shortcut(context: Context, id: String, title: String, subtitle: String?, link: String, glyph: String, color: Int): ShortcutInfoCompat {
    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(link), context, MainActivity::class.java)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
    val long = if (subtitle != null) "$title · $subtitle" else title
    return ShortcutInfoCompat.Builder(context, id)
        .setShortLabel(title.take(25))
        .setLongLabel(long.take(45))
        .setIcon(IconCompat.createWithAdaptiveBitmap(glyphIcon(glyph, color)))
        .setIntent(intent)
        .build()
}

/** A coloured disc with a glyph: the app ships no drawables for its shortcuts. */
private fun glyphIcon(glyph: String, color: Int): Bitmap {
    val size = 216                          // adaptive icon: 108 dp at 2×, the glyph inside the 72 dp safe zone
    val bmp = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
    val c = Canvas(bmp)
    c.drawColor(color)
    val p = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        this.color = 0xFFFFFFFF.toInt()
        textSize = size * 0.34f
        textAlign = Paint.Align.CENTER
    }
    val y = size / 2f - (p.descent() + p.ascent()) / 2
    c.drawText(glyph, size / 2f, y, p)
    return bmp
}
