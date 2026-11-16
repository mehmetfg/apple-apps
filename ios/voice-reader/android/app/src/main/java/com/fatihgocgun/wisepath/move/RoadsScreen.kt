// İstatistik › Yol (Yollarım; port of RoadsScreen.swift): the GPS record on its own, apart from the books. A day, a
// week or a month, stepped back with ‹ › as far as the record goes: where you went (every way of the period drawn
// from its latitudes and longitudes, no map tiles), km, time in motion, calories, steps and climb, a bar for each
// day, and the ways grouped by day; a way opens with its own route, its numbers and the books heard on it.
package com.fatihgocgun.wisepath.move

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.DirectionsBike
import androidx.compose.material.icons.automirrored.filled.DirectionsWalk
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowLeft
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.FilterList
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Map
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.settings.MoveKind
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.temporal.TemporalAdjusters
import kotlin.math.cos

private enum class Span(val label: String) { day("Gün"), week("Hafta"), month("Ay") }

private val bikeColor = Color(0xFFFF9500)
private val walkColor = Color(0xFF34C759)
private fun kindColor(k: MoveKind) = if (k == MoveKind.bike) bikeColor else walkColor
private fun kindIcon(k: MoveKind) = if (k == MoveKind.bike) Icons.AutoMirrored.Filled.DirectionsBike else Icons.AutoMirrored.Filled.DirectionsWalk

private fun dayOf(ms: Long): LocalDate = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).toLocalDate()

/** The first and last day of the period `offset` steps back from now. */
private fun range(span: Span, offset: Int): Pair<LocalDate, LocalDate> {
    val today = LocalDate.now()
    return when (span) {
        Span.day -> today.plusDays(offset.toLong()).let { it to it }
        Span.week -> today.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)).plusWeeks(offset.toLong()).let { it to it.plusDays(6) }
        Span.month -> today.withDayOfMonth(1).plusMonths(offset.toLong()).let { it to it.with(TemporalAdjusters.lastDayOfMonth()) }
    }
}

private fun minutes(seconds: Double) = Format.duration(seconds)
private fun km1(m: Double) = String.format(RideTr, "%.1f", m / 1000)

/** İstatistik › Yol: the recorded ways by day, week, month. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RoadsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    val app = remember { AppModel.get(context) }
    LaunchedEffect(Unit) { Workouts.attach(context) }
    var span by remember { mutableStateOf(Span.week) }
    var offset by remember { mutableIntStateOf(0) }
    var kind by remember { mutableStateOf<MoveKind?>(null) }
    var open by remember { mutableStateOf<Workout?>(null) }
    var kindMenu by remember { mutableStateOf(false) }

    val all = run {
        var l = Workouts.history
        Workouts.current?.let { c -> if (l.none { it.id == c.id }) l = listOf(c) + l }
        l.filter { kind == null || it.kind == kind }.sortedByDescending { it.start }
    }
    fun ways(a: LocalDate, z: LocalDate) = all.filter { val d = dayOf(it.start); !d.isBefore(a) && !d.isAfter(z) }
    // how far back ‹ can go: to the period of the first recorded way
    val earliest = run {
        val first = all.lastOrNull()?.let { dayOf(it.start) } ?: return@run 0
        var n = 0
        while (n > -400 && range(span, n).first.isAfter(first)) n--
        n
    }
    val (a, z) = range(span, offset)
    val now = ways(a, z)

    Scaffold(topBar = {
        TopAppBar(title = { Text("Yollarım") }, navigationIcon = {
            IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Filled.ArrowBack, "Geri") }
        })
    }) { pad ->
        Column(Modifier.fillMaxSize().padding(pad).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Span.entries.forEach { sp -> FilterChip(span == sp, { span = sp; offset = 0 }, label = { Text(sp.label) }) }
            }
            // ‹ 28 Ekim Salı ›
            Row(Modifier.fillMaxWidth().pointerInput(span, earliest) {
                var dx = 0f
                detectHorizontalDragGestures(onDragStart = { dx = 0f }, onDragEnd = {
                    if (dx > 60 && offset > earliest) offset-- else if (dx < -60 && offset < 0) offset++
                }) { _, d -> dx += d }
            }, verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = { offset-- }, enabled = offset > earliest) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowLeft, "Önceki") }
                Column(Modifier.weight(1f), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(title(span, a, z), fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                    if (offset == 0) Text(when (span) { Span.day -> "bugün"; Span.week -> "bu hafta"; Span.month -> "bu ay" },
                        fontSize = 12.sp, color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                }
                IconButton(onClick = { offset++ }, enabled = offset < 0) { Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, "Sonraki") }
                Box {
                    IconButton(onClick = { kindMenu = true }) { Icon(kind?.let { kindIcon(it) } ?: Icons.Filled.FilterList, "Tür: ${kind?.label ?: "hepsi"}") }
                    DropdownMenu(kindMenu, { kindMenu = false }) {
                        DropdownMenuItem(text = { Text("Hepsi") }, onClick = { kind = null; kindMenu = false })
                        MoveKind.entries.forEach { k ->
                            DropdownMenuItem(text = { Text(k.label) }, leadingIcon = { Icon(kindIcon(k), null) }, onClick = { kind = k; kindMenu = false })
                        }
                    }
                }
            }
            when {
                all.isEmpty() -> Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Icon(Icons.Filled.Map, null, Modifier.size(40.dp), tint = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.4f))
                    Text("Henüz yol yok", fontWeight = FontWeight.SemiBold, fontSize = 18.sp)
                    Text("Bisiklet ya da yürüyüş modunda dinlediğinde yolun burada görünür: harita, km, süre, kalori.",
                        color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f), fontSize = 14.sp)
                }
                now.isEmpty() -> Box(Modifier.fillMaxWidth().heightIn(min = 80.dp), contentAlignment = Alignment.Center) {
                    Text("Bu dönemde yol yok.", color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.6f))
                }
                else -> {
                    RoutesMap(now, Modifier.fillMaxWidth().height(280.dp))
                    Totals(now)
                    if (span != Span.day) Chart(a, z, now)
                    Days(app, now) { open = it }
                }
            }
        }
    }
    open?.let { w -> WayDetail(app, w) { open = null } }
}

private fun title(span: Span, a: LocalDate, z: LocalDate): String = when (span) {
    Span.day -> Format.day(a, "d MMMM EEEE")
    Span.week -> "${Format.day(a, "d MMM")} – ${Format.day(z, "d MMM")}"
    Span.month -> Format.day(a, "LLLL yyyy").replaceFirstChar { it.titlecase(RideTr) }
}

@Composable
private fun Totals(w: List<Workout>) {
    val tiles = listOf(
        Triple("km", km1(w.sumOf { it.distance }), Color(0xFFFF9500)),
        Triple("hareket", minutes(w.sumOf { it.moving }), Color(0xFF30B0C7)),
        Triple("kcal", "${Math.round(w.sumOf { it.calories })}", Color(0xFFFF3B30)),
        Triple("adım", String.format(RideTr, "%,d", w.sumOf { it.steps }), Color(0xFF34C759)),
        Triple("tırmanış", "${Math.round(w.sumOf { it.climb })} m", Color(0xFFA2845E)),
        Triple("yol", "${w.size}", Color(0xFF5856D6)),
    )
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        tiles.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                row.forEach { (t, v, c) ->
                    Column(Modifier.weight(1f).clip(RoundedCornerShape(14.dp)).background(MaterialTheme.colorScheme.onBackground.copy(alpha = 0.05f)).padding(11.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(t, color = c, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                        Text(v, fontSize = 19.sp, fontWeight = FontWeight.Bold, maxLines = 1)
                    }
                }
            }
        }
    }
}

/** km on each day of the week or month, bicycle and walking stacked. */
@Composable
private fun Chart(a: LocalDate, z: LocalDate, w: List<Workout>) {
    val days = generateSequence(a) { it.plusDays(1) }.takeWhile { !it.isAfter(z) }.toList()
    val bars = days.map { d ->
        val list = w.filter { dayOf(it.start) == d }
        list.filter { it.kind == MoveKind.bike }.sumOf { it.distance } / 1000 to list.filter { it.kind == MoveKind.walk }.sumOf { it.distance } / 1000
    }
    val max = maxOf(0.1, bars.maxOf { it.first + it.second })
    val ink = MaterialTheme.colorScheme.onBackground
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Legend("Bisiklet", bikeColor); Legend("Yürüyüş", walkColor)
            Spacer(Modifier.weight(1f))
            Text("en çok ${String.format(RideTr, "%.1f", max)} km", fontSize = 11.sp, color = ink.copy(alpha = 0.6f))
        }
        Canvas(Modifier.fillMaxWidth().height(130.dp)) {
            val n = bars.size
            val slot = size.width / n
            val bw = slot * 0.62f
            drawLine(ink.copy(alpha = 0.15f), Offset(0f, size.height), Offset(size.width, size.height), 1f)
            bars.forEachIndexed { i, (b, wk) ->
                val x = i * slot + (slot - bw) / 2
                val hb = (b / max * size.height).toFloat()
                val hw = (wk / max * size.height).toFloat()
                if (hb > 0) drawRoundRect(bikeColor, Offset(x, size.height - hb), Size(bw, hb), CornerRadius(3.dp.toPx()))
                if (hw > 0) drawRoundRect(walkColor, Offset(x, size.height - hb - hw), Size(bw, hw), CornerRadius(3.dp.toPx()))
            }
        }
        Row(Modifier.fillMaxWidth()) {
            days.forEachIndexed { i, d ->
                val label = if (days.size <= 7) Format.day(d, "EEEEE") else if (i % 5 == 0) "${d.dayOfMonth}" else ""
                Text(label, Modifier.weight(1f), fontSize = 10.sp, color = ink.copy(alpha = 0.6f), maxLines = 1,
                    textAlign = androidx.compose.ui.text.style.TextAlign.Center)
            }
        }
    }
}

@Composable
private fun Legend(name: String, c: Color) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(8.dp).background(c, RoundedCornerShape(2.dp)))
        Text(name, fontSize = 11.sp)
    }
}

/**
 * Every way of the period drawn from its points, each in its kind's colour, with its start (green) and end (red).
 * The points are projected flat (longitude scaled by the cosine of the latitude); pinch and drag to look closer.
 */
@Composable
fun RoutesMap(ways: List<Workout>, modifier: Modifier = Modifier) {
    val list = ways.filter { it.route.size >= 2 }
    var scale by remember(ways) { mutableFloatStateOf(1f) }
    var pan by remember(ways) { mutableStateOf(Offset.Zero) }
    val bg = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.05f)
    val grid = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.06f)
    Box(modifier.clip(RoundedCornerShape(18.dp)).background(bg).pointerInput(ways) {
        detectTransformGestures { _, p, z, _ -> scale = (scale * z).coerceIn(1f, 20f); pan += p }
    }) {
        if (list.isEmpty()) {
            Text("Rota yok (konum alınamamış).", Modifier.align(Alignment.Center), color = MaterialTheme.colorScheme.onBackground.copy(alpha = 0.5f))
            return@Box
        }
        Canvas(Modifier.fillMaxSize()) {
            val step = 32.dp.toPx()
            var gx = 0f; while (gx < size.width) { drawLine(grid, Offset(gx, 0f), Offset(gx, size.height)); gx += step }
            var gy = 0f; while (gy < size.height) { drawLine(grid, Offset(0f, gy), Offset(size.width, gy)); gy += step }
            val pts = list.flatMap { it.route }
            val minLat = pts.minOf { it[0] }; val maxLat = pts.maxOf { it[0] }
            val minLon = pts.minOf { it[1] }; val maxLon = pts.maxOf { it[1] }
            val k = cos(Math.toRadians((minLat + maxLat) / 2))
            val spanX = maxOf(1e-5, (maxLon - minLon) * k)
            val spanY = maxOf(1e-5, maxLat - minLat)
            val padPx = 20.dp.toPx()
            val fit = minOf((size.width - 2 * padPx) / spanX, (size.height - 2 * padPx) / spanY) * scale
            val cx = size.width / 2 + pan.x; val cy = size.height / 2 + pan.y
            val midLon = (minLon + maxLon) / 2; val midLat = (minLat + maxLat) / 2
            fun at(p: List<Double>) = Offset((cx + (p[1] - midLon) * k * fit).toFloat(), (cy - (p[0] - midLat) * fit).toFloat())
            for (w in list) {
                val path = Path()
                w.route.forEachIndexed { i, p -> val o = at(p); if (i == 0) path.moveTo(o.x, o.y) else path.lineTo(o.x, o.y) }
                drawPath(path, kindColor(w.kind), style = Stroke(4.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            for (w in list) {
                for ((p, c) in listOf(w.route.first() to Color(0xFF34C759), w.route.last() to Color(0xFFFF3B30))) {
                    val o = at(p)
                    drawCircle(Color.White, 6.dp.toPx(), o)
                    drawCircle(c, 4.dp.toPx(), o)
                }
            }
        }
    }
}

/** The ways of the period, under a heading for each day. */
@Composable
private fun Days(app: AppModel, w: List<Workout>, onOpen: (Workout) -> Unit) {
    val groups = w.groupBy { dayOf(it.start) }.toSortedMap(compareByDescending { it })
    val ink = MaterialTheme.colorScheme.onBackground
    Column(verticalArrangement = Arrangement.spacedBy(14.dp)) {
        groups.forEach { (day, list) ->
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row {
                    Text(Format.day(day, "EEEE d MMMM"), Modifier.weight(1f), fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    Text("${km1(list.sumOf { it.distance })} km", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = ink.copy(alpha = 0.6f))
                }
                list.forEach { x -> WayRow(app, x) { onOpen(x) } }
            }
        }
    }
}

private val hm = DateTimeFormatter.ofPattern("HH:mm")
private fun clock(ms: Long) = Instant.ofEpochMilli(ms).atZone(ZoneId.systemDefault()).format(hm)

@Composable
private fun WayRow(app: AppModel, way: Workout, onClick: () -> Unit) {
    val ink = MaterialTheme.colorScheme.onBackground
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(ink.copy(alpha = 0.04f)).clickable(onClick = onClick).padding(10.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(kindIcon(way.kind), null, Modifier.size(22.dp), tint = kindColor(way.kind))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text("${clock(way.start)} · ${way.kind.label}", fontSize = 14.sp, fontWeight = FontWeight.Medium)
            Text(summary(way), fontSize = 12.sp, color = ink.copy(alpha = 0.6f))
            val titles = way.documents.mapNotNull { app.store.document(it)?.title }
            if (titles.isNotEmpty()) Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                Icon(Icons.Filled.Headphones, null, Modifier.size(12.dp), tint = ink.copy(alpha = 0.6f))
                Text(titles.joinToString(" · "), fontSize = 12.sp, color = ink.copy(alpha = 0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        if (way.end == null) Text("sürüyor", fontSize = 11.sp, fontWeight = FontWeight.Bold, color = bikeColor)
        Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, null, tint = ink.copy(alpha = 0.3f))
    }
}

private fun summary(x: Workout): String {
    val p = mutableListOf("${MoveStrip.km(x.distance)} km", minutes(x.moving), "${Math.round(x.calories)} kcal")
    if (x.kind == MoveKind.walk && x.steps > 0) p.add("${x.steps} adım")
    if (x.kind == MoveKind.bike && x.averageSpeed > 0) p.add("ort. ${Math.round(x.averageSpeed)} km/sa")
    if (x.climb >= 1) p.add("↑${Math.round(x.climb)} m")
    return p.joinToString(" · ")
}

/** A way on its own: its route, its numbers and the books heard on it. */
@Composable
private fun WayDetail(app: AppModel, way: Workout, onClose: () -> Unit) {
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        val ink = MaterialTheme.colorScheme.onBackground
        Column(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.background)) {
            Row(Modifier.fillMaxWidth().padding(8.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("${way.kind.label} · ${Format.date(way.start, "d MMM")}", Modifier.weight(1f).padding(start = 8.dp),
                    fontWeight = FontWeight.SemiBold, fontSize = 17.sp)
                IconButton(onClick = onClose) { Icon(Icons.Filled.Close, "Kapat") }
            }
            Column(Modifier.verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
                if (way.route.size >= 2) RoutesMap(listOf(way), Modifier.fillMaxWidth().height(320.dp))
                else Text("Bu yolun rotası yok (konum alınamamış).", color = ink.copy(alpha = 0.6f))
                val rows = buildList {
                    add("Başlangıç" to Format.date(way.start, "d MMM yyyy HH:mm"))
                    add("Süre" to "${MoveStrip.clock(way.duration)} · hareket ${minutes(way.moving)}")
                    add("Mesafe" to "${MoveStrip.km(way.distance)} km")
                    add("Kalori" to "${Math.round(way.calories)} kcal")
                    if (way.kind == MoveKind.bike) add("Hız" to "ort. ${Math.round(way.averageSpeed)} · en çok ${Math.round(way.maxSpeed)} km/sa")
                    else add("Adım" to "${way.steps}")
                    add("Tırmanış" to "↑${Math.round(way.climb)} m · ↓${Math.round(way.descent)} m")
                }
                rows.forEach { (k, v) ->
                    Row { Text(k, Modifier.width(96.dp), color = ink.copy(alpha = 0.6f), fontSize = 14.sp); Text(v, fontSize = 14.sp) }
                }
                val titles = way.documents.mapNotNull { app.store.document(it)?.title }
                if (titles.isNotEmpty()) {
                    Text("Yolda dinlenenler", fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    titles.forEach { t ->
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Filled.Headphones, null, Modifier.size(16.dp)); Text(t, fontSize = 14.sp)
                        }
                    }
                }
            }
        }
    }
}
