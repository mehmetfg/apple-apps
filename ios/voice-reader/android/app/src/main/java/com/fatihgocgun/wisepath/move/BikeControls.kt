// The bicycle keys (port of BikeControls.swift): three equal glass keys a gloved thumb can hit (voice note · play ·
// mark), a thin progress line, and the colour sets they wear (Görsel Ayarlar › Bisiklet Düğmeleri). Used by the
// Klasik look; the reader can use BikeBar too.
package com.fatihgocgun.wisepath.move

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.FormatClear
import androidx.compose.material.icons.filled.LinearScale
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Stop
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.RoundRect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.settings.BikeStyle
import com.fatihgocgun.wisepath.ui.Palette

enum class BikeKey { mic, play, mark }

/** The key's glass colour. Kristal is clear glass with coloured symbols; the others are tinted glass. */
fun BikeStyle.tint(k: BikeKey): Color = when (this) {
    BikeStyle.crystal -> when (k) { BikeKey.mic -> Color(0xFF0A84FF); BikeKey.play -> Palette.play; BikeKey.mark -> Color(0xFFE8B400) }
    BikeStyle.ocean -> when (k) { BikeKey.mic -> Color(0xFF12355B); BikeKey.play -> Color(0xFF1B998B); BikeKey.mark -> Color(0xFF8EDCE6) }
    BikeStyle.ember -> when (k) { BikeKey.mic -> Color(0xFF6A2C70); BikeKey.play -> Color(0xFFE84545); BikeKey.mark -> Color(0xFFF9D56E) }
    BikeStyle.forest -> when (k) { BikeKey.mic -> Color(0xFF2D4A35); BikeKey.play -> Color(0xFF4F7942); BikeKey.mark -> Color(0xFFC5D86D) }
    BikeStyle.mono -> when (k) { BikeKey.mic -> Color(0xFF3A3A3C); BikeKey.play -> Color(0xFF636366); BikeKey.mark -> Color(0xFFD1D1D6) }
}

val BikeStyle.solid get() = this != BikeStyle.crystal

/** Symbol and label colour on the key. */
fun BikeStyle.ink(k: BikeKey): Color = if (!solid) tint(k) else if (k == BikeKey.mark) Color.Black.copy(alpha = 0.85f) else Color.White

private val keyShape = RoundedCornerShape(26.dp)

private fun Modifier.bikeGlass(tint: Color, solid: Boolean, dimmed: Boolean = false): Modifier {
    val amount = if (solid) (if (dimmed) 0.42f else 0.86f) else (if (dimmed) 0.06f else 0.13f)
    return this.clip(keyShape)
        .background(Color.White.copy(alpha = 0.10f))
        .background(tint.copy(alpha = amount))
        .border(1.dp, Brush.verticalGradient(listOf(Color.White.copy(alpha = 0.55f), Color.White.copy(alpha = 0.08f))), keyShape)
}

@Composable
private fun RowScope.KeyFace(icon: ImageVector, label: String, ink: Color, modifier: Modifier) {
    Column(modifier.weight(1f).heightIn(min = 88.dp), horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(6.dp, Alignment.CenterVertically)) {
        Icon(icon, label, tint = ink, modifier = Modifier.size(32.dp))
        Text(label, color = ink, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
    }
}

/** A ring that runs round a rounded key as it is held (`progress` 0…1). */
fun DrawScope.holdRing(progress: Float, color: Color, corner: Dp, width: Dp) {
    if (progress <= 0f) return
    val inset = width.toPx() / 2 + 3.dp.toPx()
    val path = Path().apply {
        addRoundRect(RoundRect(inset, inset, size.width - inset, size.height - inset, CornerRadius(corner.toPx() - inset)))
    }
    val pm = PathMeasure().apply { setPath(path, false) }
    val seg = Path()
    pm.getSegment(0f, pm.length * progress.coerceIn(0f, 1f), seg, true)
    drawPath(seg, color, style = Stroke(width.toPx(), cap = StrokeCap.Round))
}

/** Bicycle mode's bar: voice note · play · mark, equal in size, and a thin progress line. */
@Composable
fun BikeBar(app: AppModel, hairline: Color, accent: Color, onMarked: (Boolean?) -> Unit = {}) {
    val st by app.player.state.collectAsState()
    app.player.spoken.collectAsState().value
    app.store.documents.collectAsState().value
    val style = app.settings.bikeStyle
    val heldState = remember { mutableStateOf(0) }
    val ringState = remember { mutableStateOf(0f) }
    Column(Modifier.fillMaxWidth()) {
        Box(Modifier.fillMaxWidth().padding(horizontal = 18.dp).padding(top = 8.dp).height(4.dp)) {
            Canvas(Modifier.fillMaxSize()) {
                drawRoundRect(hairline.copy(alpha = 0.35f), cornerRadius = CornerRadius(size.height / 2))
                drawRoundRect(accent, size = Size(maxOf(4.dp.toPx(), size.width * st.progress), size.height), cornerRadius = CornerRadius(size.height / 2))
            }
        }
        Row(Modifier.fillMaxWidth().padding(horizontal = 12.dp).padding(top = 10.dp, bottom = 8.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            // microphone: hold half a second to start (a ring runs round the key), tap to stop
            val on = app.recording
            val micInk = if (on) Color.White else style.ink(BikeKey.mic)
            KeyFace(if (on) Icons.Filled.Stop else Icons.Filled.Mic, if (on) "Bitir" else "Basılı tut", micInk,
                Modifier.bikeGlass(if (on) Color.Red else style.tint(BikeKey.mic), on || style.solid)
                    .drawRingBehind(ringState.value, micInk)
                    .micHold(app, ringState, onStart = {}, onStop = {}))
            KeyFace(if (st.isPlaying) Icons.Filled.Pause else Icons.Filled.PlayArrow, if (st.isPlaying) "Duraklat" else "Oynat",
                style.ink(BikeKey.play), Modifier.bikeGlass(style.tint(BikeKey.play), style.solid).clickable { app.player.toggle() })
            val marked = app.spokenSentenceMarked()
            val n = heldState.value
            KeyFace(if (n > 1) Icons.Filled.LinearScale else if (marked) Icons.Filled.FormatClear else Icons.Filled.BorderColor,
                if (n > 1) "$n cümle" else if (marked) "Kaldır" else "İşaretle", style.ink(BikeKey.mark),
                Modifier.bikeGlass(style.tint(BikeKey.mark), style.solid, dimmed = marked)
                    .dashedIf(marked, style.ink(BikeKey.mark).copy(alpha = 0.45f))
                    .markHold(app, { onMarked(app.markSpokenSentence()) }, heldState))
        }
    }
}

fun Modifier.drawRingBehind(progress: Float, color: Color, corner: Dp = 26.dp, width: Dp = 4.dp): Modifier =
    this.drawWithContent { drawContent(); holdRing(progress, color, corner, width) }

private fun Modifier.dashedIf(on: Boolean, color: Color): Modifier = if (!on) this else
    this.drawWithContent {
        drawContent()
        val i = 4.dp.toPx()
        drawRoundRect(color, Offset(i, i), Size(size.width - 2 * i, size.height - 2 * i), CornerRadius(22.dp.toPx()),
            style = Stroke(2.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx()))))
    }
