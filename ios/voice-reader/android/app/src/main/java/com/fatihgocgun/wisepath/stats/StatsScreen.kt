// İstatistik (port of StatsViews.swift): the dashboard (StatsDash.kt) and, under it, a period — Gün / Hafta / Ay,
// stepped back with ‹ › — as cards on a grouped ground: four numbers with small charts, what was listened to as a
// pie, the run of periods, efficiency as three rings, production, averages, the books, and the library's shelves.
// Yol (the GPS record) is its own screen, reached from the tab at the top.
package com.fatihgocgun.wisepath.stats

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.automirrored.filled.ShortText
import androidx.compose.material.icons.filled.AccountBalance
import androidx.compose.material.icons.filled.BarChart
import androidx.compose.material.icons.filled.BorderColor
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EditNote
import androidx.compose.material.icons.filled.Functions
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Headphones
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.MusicNote
import androidx.compose.material.icons.filled.Pause
import androidx.compose.material.icons.filled.PieChart
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.fatihgocgun.wisepath.AppModel
import com.fatihgocgun.wisepath.Format
import com.fatihgocgun.wisepath.ui.Page
import com.fatihgocgun.wisepath.ui.Palette
import java.time.format.DateTimeFormatter
import kotlin.math.max

/** İstatistik: the dashboard (today against the goal, this week against last, records, finished books) and Gün/Hafta/Ay. */
@Composable
fun StatsScreen(onBack: () -> Unit, onOpenBook: (String) -> Unit, onOpenRoads: () -> Unit) {
    val app = AppModel.get(LocalContext.current)
    val s = rememberStats(app)
    var span by remember { mutableStateOf(StatSpan.week) }
    var offset by remember { mutableIntStateOf(0) }
    var pieByBook by remember { mutableStateOf(false) }
    val names = PeriodNames(span, offset, s)
    Page("İstatistik", onBack) { pad ->
        Column(
            Modifier.fillMaxSize().background(StatGround.page).padding(pad).verticalScroll(rememberScrollState())
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            Segmented(listOf(false to "Okuma", true to "Yol"), false) { if (it) onOpenRoads() }
            StatsDashboard(s, onOpenBook)

            Row(Modifier.padding(top = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Dönem", fontSize = 20.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                Segmented(StatSpan.entries.map { it to it.label }, span, Modifier.widthIn(max = 220.dp)) { span = it; offset = 0 }
            }
            PeriodStepper(names.title, offset, onPrev = { offset -= 1 }, onNext = { offset += 1 })

            val t = s.total(span, offset)
            val b = s.buckets(span, offset)
            Highlights(b, names)
            PieSection(s, t, names, pieByBook) { pieByBook = it }
            Trend(b, span)
            Rings(s, t, span, offset, names)
            Production(s, t, span, offset, names)
            Averages(s)
            Books(s.books(t), t.seconds / 60, onOpenBook)
            Library(app, s, onBack)

            Text(
                "Dinleme süresi 22 Ekim 2026'dan beri tutuluyor; işaretler ve notlar eski tarihleriyle sayılır. 225 kelime = 1 sayfa. Seri: en az 5 dakika dinlenen günler.",
                fontSize = 12.sp, color = secondaryText, modifier = Modifier.padding(horizontal = 4.dp),
            )
        }
    }
}

/** How the chosen period and the one before it are called ("Bu hafta" / "geçen hafta", "3 Kas – 9 Kas"…). */
private class PeriodNames(span: StatSpan, offset: Int, s: StatsModel) {
    val title: String
    val previous: String
    init {
        val (a, z) = s.range(span, offset)
        title = when (offset) {
            0 -> when (span) { StatSpan.day -> "Bugün"; StatSpan.week -> "Bu hafta"; StatSpan.month -> "Bu ay" }
            -1 -> when (span) { StatSpan.day -> "Dün"; StatSpan.week -> "Geçen hafta"; StatSpan.month -> "Geçen ay" }
            else -> when (span) {
                StatSpan.day -> Format.day(a, "d MMMM EEEE")
                StatSpan.week -> "${StatFormat.dayMonth(a)} – ${StatFormat.dayMonth(z)}"
                StatSpan.month -> DateTimeFormatter.ofPattern("LLLL yyyy", Format.tr).format(a).replaceFirstChar { it.titlecase(Format.tr) }
            }
        }
        previous = if (offset == 0) when (span) { StatSpan.day -> "dün"; StatSpan.week -> "geçen hafta"; StatSpan.month -> "geçen ay" }
        else when (span) { StatSpan.day -> "önceki gün"; StatSpan.week -> "önceki hafta"; StatSpan.month -> "önceki ay" }
    }
    val lower: String get() = title.lowercase(Format.tr)
}

@Composable
private fun PeriodStepper(title: String, offset: Int, onPrev: () -> Unit, onNext: () -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(36.dp).clip(CircleShape).clickable(onClick = onPrev).semantics { contentDescription = "Önceki dönem" },
            contentAlignment = Alignment.Center) { Icon(Icons.Filled.ChevronLeft, null) }
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f),
            textAlign = androidx.compose.ui.text.style.TextAlign.Center)
        val can = offset < 0
        Box(Modifier.size(36.dp).clip(CircleShape).alpha(if (can) 1f else 0.25f).clickable(enabled = can, onClick = onNext)
            .semantics { contentDescription = "Sonraki dönem" }, contentAlignment = Alignment.Center) { Icon(Icons.Filled.ChevronRight, null) }
    }
}

// MARK: four numbers, each with its own small chart

@Composable
private fun Highlights(b: List<StatBucket>, names: PeriodNames) {
    val now = b.lastOrNull()
    val before = b.dropLast(1).lastOrNull()
    fun change(v: (StatBucket) -> Double): Double? {
        if (now == null || before == null || v(before) <= 0.01) return null
        return (v(now) - v(before)) / v(before)
    }
    val pace = now?.pace ?: 0.0
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MetricCard("Süre", Icons.Filled.Schedule, StatTint.orange, StatFormat.minutes(now?.minutes ?: 0.0), null,
                b.map { it.minutes }, change { it.minutes }, names, Modifier.weight(1f))
            MetricCard("Sayfa", Icons.Filled.Description, StatTint.sky, StatFormat.pages(now?.words ?: 0), "sayfa",
                b.map { it.pages }, change { it.pages }, names, Modifier.weight(1f))
        }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            MetricCard("Hız", Icons.Filled.Speed, StatTint.violet, if (pace > 0) "${Math.round(pace)}" else "—", "kelime/dk",
                b.map { it.pace }, change { it.pace }, names, Modifier.weight(1f))
            MetricCard("Biten kitap", Icons.Filled.Verified, StatTint.mint, "${now?.finished ?: 0}", "kitap",
                b.map { it.finished.toDouble() }, null, names, Modifier.weight(1f))
        }
    }
}

@Composable
private fun MetricCard(
    title: String, icon: ImageVector, tint: Color, value: String, unit: String?, series: List<Double>, change: Double?,
    names: PeriodNames, modifier: Modifier,
) {
    StatCard(title, icon, tint, modifier = modifier) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value, fontSize = 26.sp, fontWeight = FontWeight.Bold, maxLines = 1)
            if (unit != null) {
                Spacer(Modifier.width(4.dp))
                Text(unit, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = secondaryText, maxLines = 1,
                    modifier = Modifier.padding(bottom = 4.dp))
            }
        }
        MiniBars(series, tint, Modifier.fillMaxWidth().height(38.dp))
        Row(Modifier.height(20.dp), verticalAlignment = Alignment.CenterVertically) {
            DeltaChip(change)
            if (change != null) Spacer(Modifier.width(5.dp))
            Text(if (change == null) names.lower else "· " + names.previous, fontSize = 11.sp, color = secondaryText, maxLines = 1,
                overflow = TextOverflow.Ellipsis)
        }
    }
}

// MARK: what was listened to, as a pie

@Composable
private fun PieSection(s: StatsModel, t: ListeningDay, names: PeriodNames, byBook: Boolean, setByBook: (Boolean) -> Unit) {
    val slices = if (byBook) slices(s.books(t).map { it.title to it.minutes }) else slices(s.folders(t))
    StatCard("Neyi dinledin", Icons.Filled.PieChart, StatTint.violet, names.title) {
        if (slices.isEmpty()) {
            Box(Modifier.fillMaxWidth().height(80.dp), contentAlignment = Alignment.Center) {
                Text("${names.title} henüz dinleme yok.", fontSize = 15.sp, color = secondaryText)
            }
        } else {
            Segmented(listOf(false to "Klasör", true to "Kitap"), byBook, onSelect = setByBook)
            androidx.compose.runtime.key(byBook) { PieCard(slices, { StatFormat.minutes(it) }, "dinleme") }
        }
    }
}

/** At most seven slices; the rest are gathered into "Öteki". */
private fun slices(items: List<Pair<String, Double>>): List<PieSlice> {
    val sorted = items.filter { it.second >= 0.5 }.sortedByDescending { it.second }
    val out = sorted.take(7).mapIndexed { i, (n, v) -> PieSlice(n, v, StatTint.pie[i % StatTint.pie.size]) }.toMutableList()
    val rest = sorted.drop(7).sumOf { it.second }
    if (rest >= 0.5) out.add(PieSlice("Öteki", rest, Color.Gray))
    // two books of the same name would read alike
    val seen = HashMap<String, Int>()
    return out.map { sl ->
        val n = (seen[sl.name] ?: 0) + 1
        seen[sl.name] = n
        if (n > 1) sl.copy(name = "${sl.name} ($n)") else sl
    }
}

// MARK: the run of periods

@Composable
private fun Trend(b: List<StatBucket>, span: StatSpan) {
    val past = b.filter { !it.current }
    val mean = if (past.isEmpty()) 0.0 else past.sumOf { it.minutes } / past.size
    val title = when (span) { StatSpan.day -> "Son 14 gün"; StatSpan.week -> "Son 8 hafta"; StatSpan.month -> "Son 6 ay" }
    val measurer = rememberTextMeasurer()
    val label = secondaryText
    val grid = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
    val meanColor = secondaryText.copy(alpha = 0.7f)
    StatCard(title, Icons.Filled.BarChart, StatTint.orange, if (mean > 0.5) "ortalama ${StatFormat.minutes(mean)}" else null) {
        Text("dakika", fontSize = 10.sp, color = secondaryText)
        Canvas(Modifier.fillMaxWidth().height(180.dp)) {
            val ls = TextStyle(fontSize = 9.sp, color = label)
            val right = 26.dp.toPx()
            val bottom = size.height - 16.dp.toPx()
            val w = size.width - right
            val top = max(1.0, max(b.maxOfOrNull { it.minutes } ?: 0.0, mean)) * 1.1
            for (k in 0..2) {
                val v = top / 1.1 * k / 2
                val y = (bottom - v / top * bottom).toFloat()
                drawLine(grid, Offset(0f, y), Offset(w, y), 1f)
                drawText(measurer, Math.round(v).toString(), Offset(w + 4.dp.toPx(), y - 6.sp.toPx()), ls)
            }
            val slot = w / b.size
            b.forEachIndexed { i, x ->
                val h = (x.minutes / top * bottom).toFloat()
                val bw = slot * 0.62f
                if (h > 0) drawRoundRect(if (x.current) StatTint.hot else StatTint.cool, Offset(i * slot + (slot - bw) / 2, bottom - h),
                    Size(bw, h), CornerRadius(5.dp.toPx()))
                // the day's labels are long: every other one, like the chart's automatic axis
                if (span != StatSpan.day || i % 2 == (b.size - 1) % 2) {
                    val text = if (span == StatSpan.day) x.label.take(2) else x.label
                    val m = measurer.measure(text, ls)
                    drawText(m, topLeft = Offset(i * slot + (slot - m.size.width) / 2, bottom + 3.dp.toPx()))
                }
            }
            if (mean > 0.5) {
                val y = (bottom - mean / top * bottom).toFloat()
                drawLine(meanColor, Offset(0f, y), Offset(w, y), 1.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx())))
            }
        }
    }
}

// MARK: efficiency, as three rings

@Composable
private fun Rings(s: StatsModel, t: ListeningDay, span: StatSpan, offset: Int, names: PeriodNames) {
    val minutes = t.seconds / 60
    val days = s.daysSoFar(span, offset)
    val active = s.activeDays(span, offset)
    val goal = (s.app.settings.dailyGoal * days).toDouble()
    val goalShare = if (goal > 0) minutes / goal else 0.0
    val playShare = if (t.seconds + t.paused > 0) t.seconds / (t.seconds + t.paused) else 0.0
    val dayShare = active.toDouble() / days
    val wpm = if (minutes > 0.5) t.words / minutes else 0.0
    StatCard("Verim", Icons.Filled.Bolt, StatTint.rose, names.title) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            RingStack(listOf(goalShare to Palette.play, dayShare to StatTint.mint, playShare to StatTint.sky), Modifier.size(132.dp))
            Spacer(Modifier.width(18.dp))
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                RingRow(Palette.play, "Hedef", StatFormat.percent(goalShare), "${StatFormat.minutes(minutes)} / ${StatFormat.minutes(goal)}")
                RingRow(StatTint.mint, "Düzen", "$active/$days gün", "dinlenen gün")
                RingRow(StatTint.sky, "Çalma oranı", StatFormat.percent(playShare), "oturum açıkken sesin çaldığı pay")
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
        Row {
            Fact(Icons.Filled.Speed, StatTint.violet, if (wpm > 0) "${Math.round(wpm)} kelime/dk" else "—", "gerçek hız")
            Spacer(Modifier.weight(1f))
            Fact(Icons.Filled.MusicNote, StatTint.orange, StatFormat.minutes(t.breaks / 60), "müzik arası")
            Spacer(Modifier.weight(1f))
            Fact(Icons.Filled.Pause, Color.Gray, StatFormat.minutes(t.paused / 60), "duraklama")
        }
    }
}

@Composable
private fun RingRow(color: Color, title: String, value: String, hint: String) {
    Row {
        Box(Modifier.padding(top = 6.dp).size(10.dp).clip(CircleShape).background(color))
        Spacer(Modifier.width(8.dp))
        Column {
            Row(verticalAlignment = Alignment.Bottom) {
                Text(value, fontSize = 18.sp, fontWeight = FontWeight.Bold, color = color)
                Spacer(Modifier.width(6.dp))
                Text(title, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(bottom = 2.dp))
            }
            Text(hint, fontSize = 11.sp, color = secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun Fact(icon: ImageVector, color: Color, value: String, label: String) {
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, null, tint = color, modifier = Modifier.size(14.dp))
            Spacer(Modifier.width(4.dp))
            Text(value, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
        Text(label, fontSize = 11.sp, color = secondaryText)
    }
}

// MARK: production

@Composable
private fun Production(s: StatsModel, t: ListeningDay, span: StatSpan, offset: Int, names: PeriodNames) {
    val marks = s.marks(span, offset)
    val n = s.notes(span, offset)
    val hours = t.seconds / 3600
    val cells = listOf(
        Made(Icons.Filled.BorderColor, StatTint.amber, "$marks", "işaret"),
        Made(Icons.Filled.Mic, StatTint.rose, "${n.voice}", if (n.seconds > 0) "sesli not · ${StatFormat.minutes(n.seconds / 60)}" else "sesli not"),
        Made(Icons.Filled.EditNote, StatTint.sky, "${n.text}", "yazılı not"),
        Made(Icons.AutoMirrored.Filled.ShortText, StatTint.violet,
            if (t.words > 0) StatFormat.decimal(marks.toDouble() / t.words * 1000) else "—", "işaret / 1000 kelime"),
        Made(Icons.Filled.GraphicEq, StatTint.mint, if (hours > 0.05) StatFormat.decimal((n.voice + n.text) / hours) else "—", "not / saat"),
        Made(Icons.Filled.CreateNewFolder, StatTint.orange, "${s.added(span, offset)}", "eklenen kitap"),
    )
    StatCard("Üretim", Icons.Filled.BorderColor, StatTint.amber, names.title) {
        cells.chunked(3).forEach { row ->
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) { row.forEach { MadeCell(it, Modifier.weight(1f)) } }
        }
    }
}

private data class Made(val icon: ImageVector, val color: Color, val value: String, val label: String)

@Composable
private fun MadeCell(m: Made, modifier: Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(3.dp)) {
        Box(Modifier.size(28.dp).clip(RoundedCornerShape(8.dp)).background(m.color.copy(alpha = 0.16f)), contentAlignment = Alignment.Center) {
            Icon(m.icon, null, tint = m.color, modifier = Modifier.size(15.dp))
        }
        Text(m.value, fontSize = 20.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        Text(m.label, fontSize = 11.sp, color = secondaryText, maxLines = 2, lineHeight = 13.sp)
    }
}

// MARK: averages

@Composable
private fun Averages(s: StatsModel) {
    val (days, t) = s.averages ?: return
    val n = days.toDouble()
    val books = s.app.log.firstDay?.let { s.finished(it, s.today).size } ?: 0
    StatCard("Ortalama", Icons.Filled.Functions, StatTint.sky, "$days günde") {
        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            AvgRow("", "Günlük", "Haftalık", "Aylık", header = true)
            val rows = listOf<Triple<String, Double, (Double) -> String>>(
                Triple("Süre", t.seconds / 60 / n) { StatFormat.minutes(it) },
                Triple("Kelime", t.words / n) { StatFormat.number(Math.round(it).toInt()) },
                Triple("Sayfa", t.words / n / ListeningLog.WORDS_PER_PAGE) { StatFormat.decimal(it) },
                Triple("Kitap", books / n) { StatFormat.decimal(it) },
            )
            rows.forEachIndexed { i, (name, perDay, f) ->
                if (i > 0) HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
                AvgRow(name, f(perDay), f(perDay * 7), f(perDay * 30.4))
            }
        }
    }
}

@Composable
private fun AvgRow(name: String, a: String, b: String, c: String, header: Boolean = false) {
    val size = if (header) 12.sp else 15.sp
    val dim = secondaryText
    Row {
        Text(name, fontSize = size, color = dim, modifier = Modifier.weight(0.8f))
        Text(a, fontSize = size, fontWeight = FontWeight.SemiBold, color = if (header) dim else Color.Unspecified, modifier = Modifier.weight(1f))
        Text(b, fontSize = size, fontWeight = if (header) FontWeight.SemiBold else null, color = if (header) dim else Color.Unspecified, modifier = Modifier.weight(1f))
        Text(c, fontSize = size, fontWeight = if (header) FontWeight.SemiBold else null, color = if (header) dim else Color.Unspecified, modifier = Modifier.weight(1f))
    }
}

// MARK: the books of the period

@Composable
private fun Books(b: List<BookTime>, total: Double, onOpenBook: (String) -> Unit) {
    if (b.isEmpty()) return
    StatCard("Kitaplar", Icons.AutoMirrored.Filled.LibraryBooks, StatTint.mint, "${b.size} kitap") {
        Column {
            b.forEachIndexed { i, x ->
                Row(
                    Modifier.fillMaxWidth().let { m -> x.doc?.let { d -> m.clickable { onOpenBook(d.id) } } ?: m }.padding(vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    x.doc?.let { StatCover(it, 34.dp); Spacer(Modifier.width(12.dp)) }
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(5.dp)) {
                        Text(x.title, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        ProgressLine(x.doc?.progress ?: 0.0)
                        Text("${StatFormat.pages(x.words)} sayfa · %${((x.doc?.progress ?: 0.0) * 100).toInt()}" +
                            if (x.doc?.isFinished == true) " · bitti" else "", fontSize = 12.sp, color = secondaryText)
                    }
                    Spacer(Modifier.width(6.dp))
                    Column(horizontalAlignment = Alignment.End) {
                        Text(StatFormat.minutes(x.minutes), fontSize = 15.sp, fontWeight = FontWeight.Bold)
                        if (total > 0.5) Text("%${Math.round(x.minutes / total * 100)}", fontSize = 11.sp, color = secondaryText)
                    }
                }
                if (i < b.size - 1) HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.25f))
            }
        }
    }
}

// MARK: the library, as a pie of its shelves

@Composable
private fun Library(app: AppModel, s: StatsModel, onBack: () -> Unit) {
    val all = s.docs
    val reading = all.count { !it.isUnread && !it.isFinished }
    val unread = all.count { it.isUnread }
    val finished = all.count { it.isFinished }
    val open = all.filter { !it.isFinished }
    val left = open.sumOf { app.duration(it.length - it.position, it.speed) }
    val words = open.sumOf { (it.wordCount * (1 - it.progress)).toInt() }
    val slices = listOf(
        PieSlice("Süren", reading.toDouble(), StatTint.orange, "reading"),
        PieSlice("Okunacak", unread.toDouble(), StatTint.sky, "unread"),
        PieSlice("Bitti", finished.toDouble(), StatTint.mint, "finished"),
    ).filter { it.value > 0 }
    StatCard("Kütüphane", Icons.Filled.AccountBalance, StatTint.sky, "${all.size} kitap") {
        if (slices.isEmpty()) Text("Kütüphane boş.", fontSize = 15.sp, color = secondaryText)
        else {
            PieCard(slices, { "${it.toInt()} kitap" }, "kütüphanede") { sl ->
                sl.key?.let { app.settings.homeShelf = it }
                onBack()
            }
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(StatTint.violet.copy(alpha = 0.10f)).padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.Headphones, null, tint = StatTint.violet, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(10.dp))
                Text(buildAnnotatedString {
                    withStyle(SpanStyle(color = secondaryText)) { append("Dinlenecek ") }
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(StatFormat.hours(left)) }
                    withStyle(SpanStyle(color = secondaryText)) { append(" · ≈ ${StatFormat.pages(words)} sayfa") }
                }, fontSize = 13.sp)
            }
        }
    }
}
