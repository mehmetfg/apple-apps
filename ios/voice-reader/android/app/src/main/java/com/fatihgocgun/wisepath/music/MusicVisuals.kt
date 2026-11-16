// Müzik modu's moving backdrops (port of MusicVisuals.swift and the bars of MusicModeView.swift): Daire (bars round a
// breathing circle), the equalizer bars, Aurora (neon ribbons braiding, mirrored on the floor), Damla (a drop on dark
// water at every beat), Nabız (a wave packet running across), Lissajous, Tünel (flying through stars) and Nefes (a
// slowly breathing mandala, for thinking). All are drawn on a Canvas from the beat's time and the microphone's
// loudness; nothing is stored between frames. The glow of iOS's blur filter is a wide faint stroke under the line.
package com.fatihgocgun.wisepath.music

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.isActive
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** What every visual gets: when the last beat fell (ms), the tempo, the loudness and the beat count. */
data class BeatInput(val lastBeat: Long, val bpm: Double, val level: Double, val beat: Int, val paused: Boolean) {
    val period: Double get() = 60 / max(30.0, bpm)
    /** 1 on the beat, falling towards 0 before the next. */
    fun pulse(now: Long): Double = exp(-since(now) / period * 3)
    fun since(now: Long): Double = max(0.0, (now - lastBeat) / 1000.0)
}

/** The wall clock, ticking every frame while not paused. */
@Composable
fun rememberFrameTime(paused: Boolean): Long {
    var t by remember { mutableLongStateOf(System.currentTimeMillis()) }
    LaunchedEffect(paused) { if (!paused) while (isActive) withFrameMillis { t = System.currentTimeMillis() } }
    return t
}

private fun hsb(h: Double, s: Double, b: Double, a: Double = 1.0): Color {
    val hh = ((h % 1.0) + 1.0) % 1.0
    return Color.hsv((hh * 360).toFloat(), s.toFloat().coerceIn(0f, 1f), b.toFloat().coerceIn(0f, 1f), a.toFloat().coerceIn(0f, 1f))
}

/** Draws `path` twice: wide and faint (the glow), then thin and bright. */
private fun DrawScope.neon(path: Path, brush: Brush, width: Float, glow: Float, opacity: Double = 1.0) {
    val o = opacity.toFloat().coerceIn(0f, 1f)
    drawPath(path, brush, alpha = o * 0.18f, style = Stroke(width * 3 + glow * 1.2f, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, brush, alpha = o * 0.35f, style = Stroke(width * 3, cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, brush, alpha = o, style = Stroke(width, cap = StrokeCap.Round, join = StrokeJoin.Round))
}

/** A cheap repeatable random number for a seed. */
private fun noise(n: Int): Double { val x = sin(n * 12.9898 + 78.233) * 43758.5453; return x - floor(x) }

/**
 * How tall bar `i` of `count` is now: full on the beat, settling before the next, a new shape each beat, a slow idle
 * wave, and the microphone's loudness under it all.
 */
private fun barValue(i: Int, count: Int, t: Double, since: Double, bpm: Double, seed: Int, level: Double, hump: Boolean): Double {
    val decay = exp(-since / (60 / bpm) * 3)
    val x = i.toDouble() / max(1, count - 1)
    val h = if (hump) 0.35 + 0.65 * sin(x * PI) else 1.0
    val shape = 0.5 + 0.5 * sin(seed * 12.9898 + i * 78.233)
    val idle = 0.5 + 0.5 * sin(t * 2.3 + i * 0.7)
    return min(1.0, 0.06 + h * (0.7 * decay * (0.4 + 0.6 * shape) + 0.12 * idle + 0.35 * level))
}

/** Bars standing round a circle: the circle breathes with the beat, the bars reach out from it. */
@Composable
fun RadialBars(input: BeatInput, modifier: Modifier, day: Boolean = false) {
    val now = rememberFrameTime(input.paused)
    val amber = if (day) Color(0.78f, 0.36f, 0.03f) else Color(0.98f, 0.72f, 0.30f)
    Canvas(modifier) {
        val t = now / 1000.0
        val since = input.since(now)
        val decay = exp(-since / (60 / input.bpm) * 3)
        val c = center
        val r0 = size.width * (0.25f + 0.03f * decay.toFloat())
        val maxLen = size.width * 0.26f
        drawCircle(Brush.radialGradient(listOf(amber.copy(alpha = (0.05 + 0.22 * decay).toFloat()), Color.Transparent), c, r0), r0, c)
        drawCircle(amber.copy(alpha = (0.15 + 0.25 * decay).toFloat()), r0, c, style = Stroke(10f + 10f * decay.toFloat()))
        drawCircle(amber.copy(alpha = (0.45 + 0.45 * decay).toFloat()), r0, c, style = Stroke(1.5f * density))
        val count = 64; val half = count / 2
        val spin = t * 0.05
        for (i in 0 until count) {
            val k = if (i < half) i else count - 1 - i
            val v = barValue(k, half, t, since, input.bpm, input.beat, input.level, false)
            val a = i.toDouble() / count * 2 * PI - PI / 2 + spin
            val inner = r0 + 6 * density
            val outer = inner + maxLen * v.toFloat()
            val ca = cos(a).toFloat(); val sa = sin(a).toFloat()
            val color = hsb(0.08 - 0.2 * v + (if (v > 0.6) 1 else 0), if (day) 0.9 else 0.8, if (day) 0.72 else 1.0, 0.6 + 0.4 * v)
            val p0 = Offset(c.x + ca * inner, c.y + sa * inner); val p1 = Offset(c.x + ca * outer, c.y + sa * outer)
            drawLine(color.copy(alpha = color.alpha * 0.3f), p0, p1, 9 * density, StrokeCap.Round)
            drawLine(color, p0, p1, 4.5f * density, StrokeCap.Round)
            val tip = outer + 10 * density * decay.toFloat()
            drawCircle((if (day) Color.Black else Color.White).copy(alpha = (0.35 + 0.6 * v).toFloat()), 2 * density, Offset(c.x + ca * tip, c.y + sa * tip))
            val e0 = r0 - 6 * density
            val e1 = e0 - maxLen * 0.3f * v.toFloat()
            drawLine(color.copy(alpha = 0.35f), Offset(c.x + ca * e0, c.y + sa * e0), Offset(c.x + ca * e1, c.y + sa * e1), 2.5f * density, StrokeCap.Round)
        }
    }
}

/** Equalizer bars mirrored around the middle: they jump on each beat and settle before the next. */
@Composable
fun RhythmBars(input: BeatInput, modifier: Modifier) {
    val now = rememberFrameTime(input.paused)
    Canvas(modifier) {
        val t = now / 1000.0
        val since = input.since(now)
        val count = 30
        val gap = 5 * density
        val bw = (size.width - gap * (count + 1)) / count
        for (i in 0 until count) {
            val v = barValue(i, count, t, since, input.bpm, input.beat, input.level, true)
            val h = v.toFloat() * size.height
            val top = (size.height - h) / 2
            drawRoundRect(Brush.verticalGradient(listOf(Color(1f, 0.42f, 0.25f), Color(0.98f, 0.72f, 0.30f), Color(1f, 0.42f, 0.25f)), top, top + h),
                Offset(gap + i * (bw + gap), top), Size(bw, h), androidx.compose.ui.geometry.CornerRadius(bw / 2))
        }
    }
}

/** Four neon ribbons across the middle that swell on the beat and braid round each other, with a faint reflection. */
@Composable
fun AuroraVisual(input: BeatInput, modifier: Modifier) {
    val now = rememberFrameTime(input.paused)
    Canvas(modifier) {
        val t = now / 1000.0
        val p = input.pulse(now)
        val cy = size.height * 0.46f
        val amp = size.height * (0.035 + 0.09 * p + 0.06 * input.level)
        val hue = (t / 40) % 1
        for (k in 0 until 4) {
            val path = Path()
            val phase = k * 1.7
            for (i in 0..90) {
                val x = i / 90.0
                val taper = sin(PI * x).pow(1.4)
                val y = sin(x * 9 + t * 1.3 + phase) * 0.55 + sin(x * 17 - t * 2.1 + phase * 2) * 0.3 + sin(x * 4 + t * 0.6) * 0.35
                val pt = Offset((x * size.width).toFloat(), (cy + y * amp * (1 - k * 0.16) * taper).toFloat())
                if (i == 0) path.moveTo(pt.x, pt.y) else path.lineTo(pt.x, pt.y)
            }
            val a = hsb(hue + k * 0.07, 0.85, 1.0); val b = hsb(hue + 0.22 + k * 0.05, 0.8, 1.0)
            val brush = Brush.horizontalGradient(listOf(b.copy(alpha = 0.2f), a, b, a.copy(alpha = 0.2f)), 0f, size.width)
            neon(path, brush, (if (k == 0) 2.4f else 1.4f) * density, (10 + 10 * p).toFloat() * density, if (k == 0) 1.0 else 0.6)
            // the reflection: the same ribbon upside down, flattened and faint
            withTransform({
                translate(0f, cy * 2 + size.height * 0.16f)
                scale(1f, -0.45f, Offset.Zero)
                translate(0f, cy * 0.55f)
            }) { neon(path, brush, 1.2f * density, 14 * density, 0.16) }
        }
    }
}

/** Dark water at a slant: every beat a drop falls in the middle, and its rings spread out, thinning and fading. */
@Composable
fun DropVisual(input: BeatInput, modifier: Modifier) {
    val now = rememberFrameTime(input.paused)
    Canvas(modifier) {
        val since = input.since(now)
        val cx = size.width / 2; val cy = size.height * 0.62f
        val maxR = size.width * 0.75f
        val tilt = 0.3f
        drawOval(Brush.radialGradient(listOf(Color(0.55f, 0.2f, 0.9f, 0.25f), Color.Transparent), Offset(cx, cy), maxR * 0.6f),
            Offset(cx - maxR * 0.6f, cy - maxR * 0.6f * tilt), Size(maxR * 1.2f, maxR * 1.2f * tilt))
        for (back in 0 until 8) {
            val age = since + back * input.period
            val life = age / (input.period * 8)
            if (life >= 1) continue
            for (wave in 0 until 3) {
                val r = maxR * min(1.0, life * 1.15).toFloat() * (1 - wave * 0.12f)
                if (r <= 4) continue
                val path = Path().apply { addOval(Rect(cx - r, cy - r * tilt, cx + r, cy + r * tilt)) }
                neon(path, Brush.linearGradient(listOf(hsb(0.72 + 0.18 * life - wave * 0.04, 0.8, 1.0), hsb(0.72 + 0.18 * life - wave * 0.04, 0.8, 1.0))),
                    ((2.6 * (1 - life)) + 0.4).toFloat() * density, 8 * density, (1 - life) * (if (wave == 0) 0.95 else 0.45))
            }
            if (back < 2) {
                val r = maxR * min(1.0, life * 1.15).toFloat()
                for (n in 0 until 70) {
                    val a = noise(n + back * 97) * 2 * PI
                    val j = 1 + (noise(n * 7 + back) - 0.5) * 0.12
                    drawCircle(Color.White.copy(alpha = (0.5 * (1 - life)).toFloat()), 1.2f * density,
                        Offset((cx + cos(a) * r * j).toFloat(), (cy + sin(a) * r * tilt * j).toFloat()))
                }
            }
        }
        val s = min(1.0, since / (input.period * 1.5))
        if (s < 1) for (n in 0 until 14) {
            val dx = (noise(n + input.beat * 31) - 0.5) * size.width * 0.3
            val up = (0.2 + noise(n * 3 + input.beat) * 0.8) * size.height * 0.22 * s
            drawCircle(Color(1f, 0.8f, 0.95f, (1 - s).toFloat()), 2 * density, Offset((cx + dx * s).toFloat(), (cy - up).toFloat()))
        }
    }
}

/** A wave packet runs from left to right once every beat; the trace stays as a fading afterglow of the last beats. */
@Composable
fun PulseVisual(input: BeatInput, modifier: Modifier) {
    val now = rememberFrameTime(input.paused)
    Canvas(modifier) {
        val since = input.since(now)
        val cy = size.height * 0.46f
        val green = Color(0.2f, 0.95f, 0.45f)
        val brush = Brush.horizontalGradient(listOf(green, Color(1f, 0.88f, 0.25f), green), 0f, size.width)
        drawLine(green.copy(alpha = 0.18f), Offset(0f, cy), Offset(size.width, cy), 1f)
        for (back in 0 until 4) {
            val travel = (since + back * input.period) / input.period
            val fade = if (back == 0) 1.0 else 0.4 / (back * back)
            val center = size.width * (-0.15 + 1.3 * min(1.2, travel))
            val amp = size.height * (0.07 + 0.05 * input.level) * (if (back == 0) 1.0 else 0.8)
            val path = Path()
            for (i in 0..160) {
                val x = size.width * i / 160.0
                val d = (x - center) / (size.width * 0.11)
                val y = cy - sin(d * 9) * amp * exp(-d * d)
                if (i == 0) path.moveTo(x.toFloat(), y.toFloat()) else path.lineTo(x.toFloat(), y.toFloat())
            }
            neon(path, brush, (if (back == 0) 2.2f else 1.4f) * density, 9 * density, fade)
        }
    }
}

/** A neon Lissajous figure, slowly turning: its frequencies follow the tempo, it opens on the beat, a light runs along it. */
@Composable
fun LissajousVisual(input: BeatInput, modifier: Modifier) {
    val now = rememberFrameTime(input.paused)
    Canvas(modifier) {
        val t = now / 1000.0
        val p = input.pulse(now)
        val cx = size.width / 2; val cy = size.height * 0.46f
        val r = min(size.width, size.height) * (0.3 + 0.05 * p + 0.04 * input.level)
        val (fa, fb) = if (input.bpm < 90) 3.0 to 2.0 else if (input.bpm < 120) 5.0 to 4.0 else 7.0 to 6.0
        val spin = t * 0.15
        fun at(s: Double): Offset {
            val x = sin(fa * s + t * 0.25); val y = sin(fb * s)
            val rx = x * cos(spin) - y * sin(spin); val ry = x * sin(spin) + y * cos(spin)
            return Offset((cx + rx * r).toFloat(), (cy + ry * r).toFloat())
        }
        val path = Path()
        for (i in 0..600) { val o = at(i / 600.0 * 2 * PI); if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y) }
        val hue = (t / 30) % 1
        val brush = Brush.linearGradient(listOf(hsb(hue, 0.75, 1.0), hsb(hue + 0.35, 0.75, 1.0)),
            Offset((cx - r).toFloat(), (cy - r).toFloat()), Offset((cx + r).toFloat(), (cy + r).toFloat()))
        neon(path, brush, 1.3f * density, (8 + 8 * p).toFloat() * density, 0.55 + 0.45 * p)
        val head = (t * 0.12) % 1
        val tail = Path()
        for (i in 0..30) { val o = at((max(0.0, head - 0.04) + 0.04 * i / 30) * 2 * PI); if (i == 0) tail.moveTo(o.x, o.y) else tail.lineTo(o.x, o.y) }
        neon(tail, Brush.linearGradient(listOf(Color.White, Color.White)), 3 * density, 12 * density)
    }
}

/** Flying through stars: specks come from the middle towards the viewer; on the beat the flight speeds up a moment. */
@Composable
fun TunnelVisual(input: BeatInput, modifier: Modifier) {
    val now = rememberFrameTime(input.paused)
    Canvas(modifier) {
        val t = now / 1000.0
        val p = input.pulse(now)
        val cx = size.width / 2; val cy = size.height * 0.46f
        val reach = max(size.width, size.height) * 0.75
        val r = (30 + 50 * p).toFloat() * density
        drawCircle(Brush.radialGradient(listOf(Color(0.75f, 0.6f, 1f, (0.25 + 0.4 * p).toFloat()), Color.Transparent), Offset(cx, cy), r * 2), r * 2, Offset(cx, cy))
        val travel = t * 0.18 + input.beat * 0.06 + (1 - p) * 0.06
        for (n in 0 until 220) {
            val angle = noise(n) * 2 * PI
            val z = (noise(n * 13) + travel) % 1
            val d = z.pow(2.2) * reach
            val len = (6 + 40 * z) * (1 + 1.5 * p) * density
            val a = Offset((cx + cos(angle) * d).toFloat(), (cy + sin(angle) * d).toFloat())
            val b = Offset((cx + cos(angle) * (d + len)).toFloat(), (cy + sin(angle) * (d + len)).toFloat())
            drawLine(hsb(0.6 + 0.25 * noise(n * 5), 0.35 + 0.4 * z, 1.0, min(1.0, z * 1.6)), a, b, ((0.6 + 2.2 * z) * density).toFloat(), StrokeCap.Round)
        }
    }
}

/** For thinking rather than moving: a mandala that opens over four beats and closes over the next four, like a breath. */
@Composable
fun BreathVisual(input: BeatInput, modifier: Modifier) {
    val now = rememberFrameTime(input.paused)
    val measurer = rememberTextMeasurer()
    Canvas(modifier) {
        val t = now / 1000.0
        val p = input.pulse(now)
        val cycle = input.period * 8
        val breath = 0.5 - 0.5 * cos(t / cycle * 2 * PI)
        val cx = size.width / 2; val cy = size.height * 0.46f
        val unit = (min(size.width, size.height) * (0.1 + 0.06 * breath)).toFloat()
        val spin = t * 0.02
        val color = hsb(0.55 + 0.12 * sin(t / 50), 0.45, 1.0)
        val petals = Path()
        petals.addOval(Rect(Offset(cx, cy), unit))
        for (ring in 1..2) {
            val n = ring * 6
            val dir = if (ring == 1) 1.0 else -0.6
            for (k in 0 until n) {
                val a = k.toDouble() / n * 2 * PI + spin * dir
                val d = unit * ring * (0.85 + 0.15 * breath).toFloat()
                petals.addOval(Rect(Offset((cx + cos(a) * d).toFloat(), (cy + sin(a) * d).toFloat()), unit))
            }
        }
        drawPath(petals, color, alpha = (0.15 + 0.1 * breath).toFloat(), style = Stroke(6 * density))
        drawPath(petals, color.copy(alpha = (0.35 + 0.25 * breath + 0.15 * p).toFloat().coerceAtMost(1f)), style = Stroke(0.8f * density))
        val rOut = unit * 3.2f
        drawCircle(color.copy(alpha = (0.18 + 0.12 * breath).toFloat()), rOut, Offset(cx, cy), style = Stroke(1 * density))
        val a = t / (cycle * 2) * 2 * PI
        val dot = Offset((cx + cos(a) * rOut).toFloat(), (cy + sin(a) * rOut).toFloat())
        drawCircle(Brush.radialGradient(listOf(Color.White.copy(alpha = 0.8f), Color.Transparent), dot, 9 * density), 9 * density, dot)
        val inhale = sin(t / cycle * 2 * PI) > 0
        val layout = measurer.measure(if (inhale) "nefes al" else "nefes ver",
            TextStyle(color = color.copy(alpha = 0.35f), fontSize = 13.sp, fontFamily = FontFamily.Serif))
        drawText(layout, topLeft = Offset(cx - layout.size.width / 2, cy + rOut + 30 * density - layout.size.height / 2))
    }
}

