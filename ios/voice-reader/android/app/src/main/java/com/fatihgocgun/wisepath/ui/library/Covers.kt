// Book covers (port of Views/Covers.swift): the real one when the document has it, a designed one when it does not
// (coloured by its series or folder, the title set large), and the moving sound-wave mark of the book being read.
package com.fatihgocgun.wisepath.ui.library

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.model.DocumentRecord
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.util.concurrent.ConcurrentHashMap

object CoverCache {
    private val cache = ConcurrentHashMap<String, Bitmap>()
    private val missing = ConcurrentHashMap.newKeySet<String>()

    fun cached(file: File): Bitmap? = cache[file.path]

    fun load(file: File, version: Int): Bitmap? {
        val key = file.path
        cache[key]?.let { return it }
        if (key + version in missing) return null
        if (!file.exists()) { missing.add(key + version); return null }
        val opts = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, opts)
        var sample = 1
        while (opts.outWidth / sample > 600) sample *= 2
        val b = BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })
        if (b != null) cache[key] = b else missing.add(key + version)
        return b
    }
}

/** A colour of its own for every series, folder or title: the generated covers and the spines. */
fun bookColor(d: DocumentRecord): Color {
    val key = AppModel.seriesFolder(d.title) ?: d.folder ?: d.title
    val palette = listOf(
        0xFF1F3A5F, 0xFF6B2E3B, 0xFF2F5D50, 0xFF5B4A8A, 0xFF8A5A2B, 0xFF33465C, 0xFF7A3B2E, 0xFF3C5A2E,
        0xFF2B4C7E, 0xFF6E4B6B, 0xFF4F6D7A, 0xFF8C6B3E,
    )
    return Color(palette[Math.floorMod(key.hashCode(), palette.size)])
}

@Composable
fun CoverView(doc: DocumentRecord, modifier: Modifier = Modifier, corner: Dp = 6.dp, playing: Boolean = false) {
    val app = AppModel.get(androidx.compose.ui.platform.LocalContext.current)
    val version by app.store.coverVersion.collectAsState()
    val file = remember(doc.id) { app.store.coverFile(doc.id) }
    var image by remember(doc.id, version) { mutableStateOf<ImageBitmap?>(CoverCache.cached(file)?.asImageBitmap()) }
    LaunchedEffect(doc.id, version) {
        if (image == null) image = withContext(Dispatchers.IO) { CoverCache.load(file, version)?.asImageBitmap() }
    }
    Box(modifier.shadow(3.dp, RoundedCornerShape(corner)).clip(RoundedCornerShape(corner))) {
        val img = image
        if (img != null) Image(img, doc.title, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        else GeneratedCover(doc)
        if (playing) Box(Modifier.align(Alignment.BottomEnd).padding(6.dp).background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(6.dp)).padding(4.dp)) {
            PlayingBars(Modifier.size(16.dp, 12.dp), Color.White)
        }
    }
}

/** A designed cover: the book's colour, a thin frame, the title large and the author small. */
@Composable
fun GeneratedCover(doc: DocumentRecord) {
    val base = bookColor(doc)
    Box(
        Modifier.fillMaxSize().background(Brush.linearGradient(listOf(base, lerpColor(base, Color.Black, 0.35f))))
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val inset = size.minDimension * 0.06f
            drawRoundRect(
                Color.White.copy(alpha = 0.35f), topLeft = Offset(inset, inset),
                size = Size(size.width - 2 * inset, size.height - 2 * inset), cornerRadius = CornerRadius(4f),
                style = androidx.compose.ui.graphics.drawscope.Stroke(width = 1.5f),
            )
        }
        Column(Modifier.fillMaxSize().padding(12.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(0.25f))
            Text(
                doc.title, color = Color.White, fontFamily = FontFamily.Serif, fontWeight = FontWeight.SemiBold,
                fontSize = 14.sp, lineHeight = 17.sp, textAlign = TextAlign.Center, maxLines = 5, overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(6.dp))
            Box(Modifier.size(24.dp, 1.dp).background(Color.White.copy(alpha = 0.6f)))
            Spacer(Modifier.height(6.dp))
            doc.author?.let {
                Text(it, color = Color.White.copy(alpha = 0.8f), fontSize = 10.sp, textAlign = TextAlign.Center, maxLines = 2,
                    overflow = TextOverflow.Ellipsis, modifier = Modifier.fillMaxWidth())
            }
            Spacer(Modifier.weight(0.75f))
            Text(doc.format.badge, color = Color.White.copy(alpha = 0.55f), fontSize = 8.sp, letterSpacing = 1.5.sp)
        }
    }
}

/** The moving sound-wave mark of the document being read. */
@Composable
fun PlayingBars(modifier: Modifier = Modifier, color: Color) {
    val t = rememberInfiniteTransition(label = "bars")
    val phase by t.animateFloat(0f, 1f, infiniteRepeatable(tween(900), RepeatMode.Restart), label = "phase")
    Canvas(modifier) {
        val n = 4
        val w = size.width / (n * 2 - 1)
        for (i in 0 until n) {
            val h = size.height * (0.35f + 0.65f * kotlin.math.abs(kotlin.math.sin((phase + i * 0.27f) * Math.PI)).toFloat())
            drawRoundRect(color, Offset(i * 2 * w, size.height - h), Size(w, h), CornerRadius(w / 2))
        }
    }
}

fun lerpColor(a: Color, b: Color, t: Float) = androidx.compose.ui.graphics.lerp(a, b, t)
