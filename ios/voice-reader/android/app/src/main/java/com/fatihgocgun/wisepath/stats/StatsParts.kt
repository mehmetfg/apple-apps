// The statistics' drawing parts (port of StatCard, PieCard, RingStack in StatsViews.swift and GoalRing, DeltaChip,
// StreakChip, WeekBars in StatsDash.swift), all drawn with Compose Canvas.
package com.fatihgocgun.wisepath.stats

import android.graphics.BitmapFactory
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.NorthEast
import androidx.compose.material.icons.filled.SouthEast
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.draw.scale
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.model.DocumentRecord
import com.fatihgocgun.wisepath.ui.Palette
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.PI
import kotlin.math.atan2
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** The statistics of the moment; recomputed when the log moves, the library or the notes change. */
@Composable
fun rememberStats(app: AppModel): StatsModel {
    val rev by app.log.revision.collectAsState()
    val docs by app.store.documents.collectAsState()
    val notes by app.notes.notes.collectAsState()
    return remember(rev, docs, notes, java.time.LocalDate.now()) { StatsModel(app, docs, notes) }
}

/** The grouped page's ground and its cards (iOS systemGroupedBackground / secondarySystemGroupedBackground). */
object StatGround {
    val page: Color @Composable get() = MaterialTheme.colorScheme.background
    val card: Color @Composable get() = MaterialTheme.colorScheme.surfaceContainerHigh
}

val secondaryText: Color @Composable get() = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
val tertiaryText: Color @Composable get() = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.35f)
val primaryFaint: Color @Composable get() = MaterialTheme.colorScheme.onSurface

/** A plain card of the page. */
@Composable
fun StatPanel(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier.fillMaxWidth().clip(RoundedCornerShape(22.dp)).background(StatGround.card).padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp), content = content,
    )
}

/** A card: a coloured title with its symbol, a quiet note on the right, the content under them. */
@Composable
fun StatCard(title: String, icon: ImageVector, tint: Color, note: String? = null, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    StatPanel(modifier) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = tint, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(6.dp))
            Text(title, color = tint, fontWeight = FontWeight.Bold, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false))
            Spacer(Modifier.weight(1f).widthIn(min = 4.dp))
            if (note != null) Text(note, fontSize = 12.sp, color = secondaryText, maxLines = 1)
        }
        content()
    }
}

/** A two- or three-way choice drawn as iOS's segmented control. */
@Composable
fun <T> Segmented(options: List<Pair<T, String>>, selected: T, modifier: Modifier = Modifier, onSelect: (T) -> Unit) {
    Row(
        modifier.fillMaxWidth().height(32.dp).clip(RoundedCornerShape(9.dp))
            .background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)).padding(2.dp),
    ) {
        options.forEach { (v, label) ->
            val on = v == selected
            Box(
                Modifier.weight(1f).fillMaxSize().clip(RoundedCornerShape(7.dp))
                    .background(if (on) MaterialTheme.colorScheme.surfaceContainerHigh else Color.Transparent)
                    .clickable { onSelect(v) },
                contentAlignment = Alignment.Center,
            ) {
                Text(label, fontSize = 13.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium, maxLines = 1)
            }
        }
    }
}

/** A thin progress line (LibraryScreen.swift's ProgressBar): green once finished. */
@Composable
fun ProgressLine(value: Double, modifier: Modifier = Modifier) {
    val accent = MaterialTheme.colorScheme.primary
    val ground = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.14f)
    Canvas(modifier.fillMaxWidth().height(4.dp)) {
        val r = CornerRadius(size.height / 2)
        drawRoundRect(ground, cornerRadius = r)
        val w = size.width * value.coerceIn(0.0, 1.0).toFloat()
        if (w > 0) drawRoundRect(if (value >= 0.99) StatTint.green else accent, size = Size(w, size.height), cornerRadius = r)
    }
}

/** A book's cover (docs/<id>/cover.jpg) or, without one, a coloured tile with its initial. */
@Composable
fun StatCover(doc: DocumentRecord, width: Dp, modifier: Modifier = Modifier) {
    val app = AppModel.get(LocalContext.current)
    val version by app.store.coverVersion.collectAsState()
    var bmp by remember(doc.id) { mutableStateOf<ImageBitmap?>(null) }
    LaunchedEffect(doc.id, version) {
        bmp = withContext(Dispatchers.IO) {
            val f = app.store.coverFile(doc.id)
            if (!f.exists()) null else runCatching {
                val o = BitmapFactory.Options().apply { inSampleSize = 4 }
                BitmapFactory.decodeFile(f.path, o)?.asImageBitmap()
            }.getOrNull()
        }
    }
    val shape = RoundedCornerShape(4.dp)
    val m = modifier.width(width).aspectRatio(2f / 3f).clip(shape)
    val b = bmp
    if (b != null) Image(b, doc.title, m, contentScale = ContentScale.Crop)
    else {
        val tint = StatTint.pie[(doc.id.hashCode() and 0x7fffffff) % 5]
        Box(m.background(Brush.verticalGradient(listOf(tint, tint.copy(alpha = 0.7f)))), contentAlignment = Alignment.Center) {
            Text(doc.title.take(1).uppercase(), color = Color.White, fontWeight = FontWeight.Bold, fontSize = (width.value * 0.42f).sp)
        }
    }
}

// MARK: rings

/** The day's ring: how much of the goal is heard. It fills from empty when it appears; at the goal it turns green. */
@Composable
fun GoalRing(progress: Double, modifier: Modifier = Modifier, lineWidth: Dp = 9.dp, center: @Composable BoxScope.() -> Unit) {
    val shown = remember { Animatable(0f) }
    LaunchedEffect(progress) {
        shown.animateTo(progress.toFloat().coerceIn(0f, 1f), spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessVeryLow))
    }
    val reached = progress >= 1
    val ground = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.09f)
    Box(modifier, contentAlignment = Alignment.Center) {
        Canvas(Modifier.fillMaxSize()) {
            val w = lineWidth.toPx()
            val d = min(size.width, size.height) - w
            val tl = Offset((size.width - d) / 2, (size.height - d) / 2)
            drawArc(ground, 0f, 360f, false, tl, Size(d, d), style = Stroke(w))
            val colors = if (reached) listOf(StatTint.mint, StatTint.green, StatTint.mint)
            else listOf(StatTint.orange, Palette.play, StatTint.rose, StatTint.orange)
            rotate(-90f) {
                drawArc(brush = Brush.sweepGradient(colors, Offset(size.width / 2, size.height / 2)), startAngle = 0f, sweepAngle = 360f * max(0.002f, shown.value),
                    useCenter = false, topLeft = tl, size = Size(d, d), style = Stroke(w, cap = StrokeCap.Round))
            }
        }
        center()
    }
}

/** Rings one inside the other, each a share of its own whole (the outermost first). */
@Composable
fun RingStack(rings: List<Pair<Double, Color>>, modifier: Modifier = Modifier, lineWidth: Dp = 13.dp) {
    val shown = remember { Animatable(0f) }
    LaunchedEffect(Unit) { shown.animateTo(1f, spring(dampingRatio = 0.8f, stiffness = Spring.StiffnessVeryLow)) }
    Canvas(modifier) {
        val w = lineWidth.toPx()
        rings.forEachIndexed { i, (v, c) ->
            val inset = i * (w + 4.dp.toPx()) + w / 2
            val d = min(size.width, size.height) - inset * 2
            if (d <= 0) return@forEachIndexed
            val tl = Offset((size.width - d) / 2, (size.height - d) / 2)
            drawArc(c.copy(alpha = 0.18f), 0f, 360f, false, tl, Size(d, d), style = Stroke(w))
            rotate(-90f) {
                drawArc(c, 0f, 360f * max(0.003f, (v.coerceIn(0.0, 1.0) * shown.value).toFloat()), false, tl, Size(d, d),
                    style = Stroke(w, cap = StrokeCap.Round))
            }
        }
    }
}

// MARK: chips

/** "↗ %18" against the period before: green up, orange down. */
@Composable
fun DeltaChip(change: Double?) {
    val c = change ?: return
    val up = c >= 0
    val color = if (up) StatTint.green else StatTint.orange
    Row(
        Modifier.clip(CircleShape).background(color.copy(alpha = 0.15f)).padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(if (up) Icons.Filled.NorthEast else Icons.Filled.SouthEast, null, tint = color, modifier = Modifier.size(11.dp))
        Spacer(Modifier.width(3.dp))
        Text("%" + Math.round(kotlin.math.abs(c) * 100), color = color, fontSize = 11.sp, fontWeight = FontWeight.Bold)
    }
}

/** "5 gün": the run of days, a small flame. */
@Composable
fun StreakChip(days: Int) {
    if (days < 2) return
    Row(
        Modifier.clip(CircleShape).background(StatTint.orange.copy(alpha = 0.15f)).padding(horizontal = 7.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(Icons.Filled.LocalFireDepartment, null, tint = StatTint.orange, modifier = Modifier.size(11.dp))
        Spacer(Modifier.width(3.dp))
        Text("$days gün", color = StatTint.orange, fontSize = 11.sp, fontWeight = FontWeight.Bold)
    }
}

// MARK: bars

/** Seven small bars, Monday to Sunday, measured against the goal; they grow when they appear. */
@Composable
fun WeekBars(days: List<DayStat>, goal: Double, today: java.time.LocalDate, modifier: Modifier = Modifier) {
    var grown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { grown = true }
    val top = maxOf(goal, days.maxOfOrNull { it.minutes } ?: 0.0, 1.0)
    val empty = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.10f)
    Row(modifier, horizontalArrangement = Arrangement.spacedBy(5.dp), verticalAlignment = Alignment.Bottom) {
        days.forEachIndexed { i, d ->
            val isToday = d.date == today
            val future = d.date.isAfter(today)
            val h by animateFloatAsState(if (grown) (d.minutes / top).toFloat() else 0f, tween(600, delayMillis = i * 40), label = "bar")
            Column(Modifier.weight(1f).fillMaxSize(), horizontalAlignment = Alignment.CenterHorizontally) {
                Canvas(Modifier.weight(1f).fillMaxWidth()) {
                    val bw = min(size.width, 18.dp.toPx())
                    val bh = max(4.dp.toPx(), size.height * h)
                    val tl = Offset((size.width - bw) / 2, size.height - bh)
                    val r = CornerRadius(3.5.dp.toPx())
                    if (future || d.minutes < 0.5) drawRoundRect(empty, tl, Size(bw, bh), r)
                    else drawRoundRect(StatTint.bar(isToday, d.minutes >= goal), tl, Size(bw, bh), r)
                }
                Spacer(Modifier.height(3.dp))
                Text(StatTint.weekdays[i % 7].take(1), fontSize = 9.sp,
                    fontWeight = if (isToday) FontWeight.ExtraBold else FontWeight.Medium,
                    color = if (isToday) MaterialTheme.colorScheme.onSurface else secondaryText)
            }
        }
    }
}

/** A small bar series: the last bar tinted, the earlier ones faint (the metric cards). */
@Composable
fun MiniBars(series: List<Double>, tint: Color, modifier: Modifier = Modifier) {
    val faint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.13f)
    val top = max(series.maxOrNull() ?: 0.0, 0.0001)
    Canvas(modifier) {
        if (series.isEmpty()) return@Canvas
        val slot = size.width / series.size
        val bw = slot * 0.7f
        series.forEachIndexed { i, v ->
            val bh = max(1.dp.toPx(), (v / top).toFloat() * size.height)
            val c = if (i == series.size - 1) tint else faint
            drawRoundRect(c, Offset(i * slot + (slot - bw) / 2, size.height - bh), Size(bw, bh), CornerRadius(2.5.dp.toPx()))
        }
    }
}

// MARK: pie

/** A slice of a pie. */
data class PieSlice(val name: String, val value: Double, val color: Color, val key: String? = null)

/** A large pie with its total in the middle. A touch on a slice puts that slice in the middle; the list under it
 *  gives every slice its share. */
@Composable
fun PieCard(slices: List<PieSlice>, unit: (Double) -> String, centerTitle: String = "toplam", onPick: ((PieSlice) -> Unit)? = null) {
    val total = slices.sumOf { it.value }
    val sum = max(total, 0.0001)
    var picked by remember(slices) { mutableStateOf<Int?>(null) }
    val grow = remember { Animatable(0.86f) }
    LaunchedEffect(Unit) { grow.animateTo(1f, spring(dampingRatio = 0.6f, stiffness = Spring.StiffnessLow)) }
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Box(Modifier.fillMaxWidth().height(216.dp), contentAlignment = Alignment.Center) {
            Canvas(
                Modifier.fillMaxSize().scale(grow.value).graphicsLayer { alpha = ((grow.value - 0.86f) / 0.14f).coerceIn(0f, 1f) }
                    .pointerInput(slices) {
                        detectTapGestures { p ->
                            val cx = size.width / 2f; val cy = size.height / 2f
                            val r = min(size.width, size.height) / 2f
                            val dist = hypot(p.x - cx, p.y - cy)
                            if (dist < r * 0.55f || dist > r) { picked = null; return@detectTapGestures }
                            // angle from 12 o'clock, clockwise
                            var a = Math.toDegrees(atan2((p.y - cy).toDouble(), (p.x - cx).toDouble())) + 90
                            if (a < 0) a += 360
                            var run = 0.0
                            var hit = slices.size - 1
                            for ((i, s) in slices.withIndex()) { run += s.value / sum * 360; if (a <= run) { hit = i; break } }
                            picked = if (picked == hit) null else hit
                        }
                    },
            ) {
                val outer = min(size.width, size.height) / 2f
                val c = Offset(size.width / 2, size.height / 2)
                var start = -90f
                val gap = if (slices.size > 1) 1.2f else 0f
                slices.forEachIndexed { i, s ->
                    val sweep = (s.value / sum * 360).toFloat()
                    val on = picked == null || picked == i
                    val ro = outer * if (picked == i) 1f else 0.94f
                    val ri = outer * 0.62f
                    val w = ro - ri
                    val d = ro + ri
                    drawArc(
                        s.color.copy(alpha = if (on) 1f else 0.35f), start + gap, max(0.1f, sweep - 2 * gap), false,
                        Offset(c.x - d / 2, c.y - d / 2), Size(d, d), style = Stroke(w),
                    )
                    start += sweep
                }
            }
            val p = picked?.let { slices.getOrNull(it) }
            Column(Modifier.widthIn(max = 120.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(unit(p?.value ?: total), fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                Text(p?.let { "${it.name} · %${Math.round(it.value / sum * 100)}" } ?: centerTitle,
                    fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = secondaryText, maxLines = 2, textAlign = TextAlign.Center)
            }
        }
        Column {
            slices.forEachIndexed { i, s ->
                Row(
                    Modifier.fillMaxWidth().let { if (onPick != null) it.clickable { onPick(s) } else it }.padding(vertical = 9.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Box(Modifier.size(14.dp).clip(RoundedCornerShape(4.dp)).background(s.color))
                    Spacer(Modifier.width(10.dp))
                    Text(s.name, fontSize = 15.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
                    Spacer(Modifier.width(6.dp))
                    Text(unit(s.value), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("%${Math.round(s.value / sum * 100)}", fontSize = 12.sp, color = secondaryText, textAlign = TextAlign.End,
                        modifier = Modifier.width(38.dp))
                    if (onPick != null) Icon(Icons.Filled.ChevronRight, null, tint = tertiaryText, modifier = Modifier.size(16.dp))
                }
                if (i < slices.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
            }
        }
    }
}

/** A legend swatch with its text. */
@Composable
fun Legend(brush: Brush, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.dp)).background(brush))
        Spacer(Modifier.width(5.dp))
        Text(text, fontSize = 11.sp, color = secondaryText, maxLines = 1)
    }
}

/** A small outlined square (today in the heat map). */
fun Modifier.todayBorder(on: Boolean, color: Color): Modifier = if (on) border(1.dp, color, RoundedCornerShape(3.dp)) else this

@Suppress("unused") private val unusedPi = PI
