// The day measured against a goal (port of StatsDash.swift).
//
//   TodayCard        the library's home, on top: today's ring, the week's seven bars, the run of days, the week so far
//   StatsDashboard   the head of İstatistik: today, this week against last week, records, finished books, 17 weeks
package com.fatihgocgun.wisepath.stats

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.Bolt
import androidx.compose.material.icons.filled.ChevronLeft
import androidx.compose.material.icons.filled.ChevronRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.EmojiEvents
import androidx.compose.material.icons.filled.LocalFireDepartment
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.SportsScore
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.filled.TrackChanges
import androidx.compose.material.icons.filled.Verified
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
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
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.pointer.pointerInput
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
import com.fatihgocgun.wisepath.ui.Palette
import kotlin.math.max
import kotlin.math.min

// MARK: - the home card

/** The library's home card: today's ring against the daily goal, the week's seven bars, the run of days.
 *  A tap opens İstatistik. */
@Composable
fun TodayCard(onOpenStats: () -> Unit) {
    val app = AppModel.get(LocalContext.current)
    val s = rememberStats(app)
    val goal = app.settings.dailyGoal.toDouble()
    val today = s.todayStat
    val rec = s.records
    val delta = s.weekDelta
    val done = s.finished(StatSpan.week).size
    val left = goal - today.minutes
    Column(
        Modifier.padding(horizontal = 14.dp).fillMaxWidth().clip(RoundedCornerShape(20.dp))
            .background(StatGround.card).clickable(onClick = onOpenStats).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            GoalRing(today.minutes / goal, Modifier.size(88.dp)
                .semantics { contentDescription = "Günlük hedefin yüzde ${Math.round(min(today.minutes / goal, 9.99) * 100)}" }) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${Math.round(today.minutes)}", fontSize = 27.sp, fontWeight = FontWeight.Bold, lineHeight = 28.sp)
                    Text("dk", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = secondaryText, lineHeight = 12.sp)
                }
            }
            Spacer(Modifier.width(16.dp))
            Column(verticalArrangement = Arrangement.spacedBy(5.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("BUGÜN", fontSize = 12.sp, fontWeight = FontWeight.Bold, color = secondaryText)
                    Spacer(Modifier.weight(1f))
                    StreakChip(rec.streak)
                }
                Text(
                    if (left > 0.5) "Hedefe ${StatFormat.minutes(left)} kaldı"
                    else "Hedef tamam" + if (left < -0.5) " · +${StatFormat.minutes(-left)}" else "",
                    fontSize = 17.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis,
                    color = if (left > 0.5) MaterialTheme.colorScheme.onSurface else StatTint.green,
                )
                Text("${StatFormat.pages(today.words)} sayfa · hedef ${StatFormat.minutes(goal)}", fontSize = 12.sp, color = secondaryText, maxLines = 1)
                WeekBars(s.week(0), goal, s.today, Modifier.fillMaxWidth().height(40.dp))
            }
        }
        HorizontalDivider(color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f))
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(buildAnnotatedString {
                withStyle(SpanStyle(color = secondaryText)) { append("Bu hafta ") }
                withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(StatFormat.minutes(delta.now)) }
            }, fontSize = 13.sp, maxLines = 1)
            DeltaChip(delta.change)
            Spacer(Modifier.weight(1f))
            if (done > 0) {
                Icon(Icons.Filled.Verified, null, tint = StatTint.violet, modifier = Modifier.size(14.dp))
                Text("$done kitap bitti", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = StatTint.violet, maxLines = 1)
            }
            Icon(Icons.Filled.ChevronRight, null, tint = tertiaryText, modifier = Modifier.size(16.dp))
        }
    }
}

// MARK: - the head of İstatistik

@Composable
fun StatsDashboard(s: StatsModel, onOpenBook: (String) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Hero(s)
        WeekCard(s)
        RecordTiles(s)
        FinishedBooks(s, onOpenBook)
        Heat(s)
    }
}

private val goals = listOf(15, 20, 30, 45, 60, 75, 90, 120, 150, 180, 240)

/** Today: the ring, the numbers, the goal. */
@Composable
private fun Hero(s: StatsModel) {
    val settings = s.app.settings
    val goal = settings.dailyGoal.toDouble()
    val t = s.todayStat
    val left = goal - t.minutes
    val day = s.app.log.day(s.today)
    val wpm = if (t.minutes > 0.5) Math.round(t.words / t.minutes).toInt() else 0
    var menu by remember { mutableStateOf(false) }
    StatPanel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            GoalRing(t.minutes / goal, Modifier.size(132.dp), lineWidth = 13.dp) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("${Math.round(t.minutes)}", fontSize = 38.sp, fontWeight = FontWeight.Bold, lineHeight = 40.sp)
                    Text("/ ${settings.dailyGoal} dk", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = secondaryText)
                }
            }
            Spacer(Modifier.width(18.dp))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(if (left > 0.5) "Hedefe ${StatFormat.minutes(left)} kaldı" else "Bugünün hedefi tamam",
                    fontSize = 18.sp, fontWeight = FontWeight.Bold, maxLines = 2,
                    color = if (left > 0.5) MaterialTheme.colorScheme.onSurface else StatTint.green)
                HeroFact(Icons.Filled.Description, StatTint.sky, "${StatFormat.pages(t.words)} sayfa")
                HeroFact(Icons.Filled.TextFields, StatTint.violet, "${StatFormat.number(t.words)} kelime")
                if (wpm > 0) HeroFact(Icons.Filled.Speed, StatTint.orange, "$wpm kelime/dk")
                if (day.docs.isNotEmpty()) HeroFact(Icons.AutoMirrored.Filled.LibraryBooks, StatTint.mint, "${day.docs.size} kitaptan")
                Box {
                    Row(
                        Modifier.height(28.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f))
                            .clickable { menu = true }.padding(horizontal = 10.dp)
                            .semantics { contentDescription = "Günlük hedef: ${StatFormat.minutes(goal)}. Değiştir" },
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(Icons.Filled.TrackChanges, null, tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(5.dp))
                        Text("Hedef ${StatFormat.minutes(goal)}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = MaterialTheme.colorScheme.primary)
                    }
                    DropdownMenu(menu, onDismissRequest = { menu = false }) {
                        goals.forEach { g ->
                            DropdownMenuItem(
                                text = { Text(StatFormat.minutes(g.toDouble()), fontWeight = if (g == settings.dailyGoal) FontWeight.Bold else null) },
                                onClick = { settings.dailyGoal = g; menu = false },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun HeroFact(icon: ImageVector, color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, null, tint = color, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(7.dp))
        Text(text, fontSize = 15.sp, maxLines = 1)
    }
}

/** A week, day by day, over the week before it; ‹ › step through the weeks. */
@Composable
private fun WeekCard(s: StatsModel) {
    var weekOffset by remember { mutableIntStateOf(0) }
    var pages by remember { mutableStateOf(false) }
    var picked by remember { mutableStateOf<Int?>(null) }
    val goal = s.app.settings.dailyGoal.toDouble()
    val thisW = s.week(weekOffset)
    val last = s.week(weekOffset - 1)
    val total = thisW.sumOf { it.minutes }
    val before = last.sumOf { it.minutes }
    val delta = if (weekOffset == 0) s.weekDelta.change else if (before >= 1) (total - before) / before else null
    val reachedDays = thisW.count { it.minutes >= goal }
    val name = when (weekOffset) {
        0 -> "BU HAFTA"
        -1 -> "GEÇEN HAFTA"
        else -> "${StatFormat.dayMonth(thisW.first().date)} – ${StatFormat.dayMonth(thisW.last().date)}".uppercase(Format.tr)
    }
    StatPanel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Box(Modifier.size(32.dp).clip(CircleShape).clickable { weekOffset -= 1; picked = null }
                .semantics { contentDescription = "Önceki hafta" }, contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.ChevronLeft, null)
            }
            Spacer(Modifier.width(6.dp))
            Column(Modifier.weight(1f)) {
                Text(name, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = secondaryText)
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(if (pages) "${StatFormat.pages(thisW.sumOf { it.words })} sayfa" else StatFormat.minutes(total),
                        fontSize = 24.sp, fontWeight = FontWeight.Bold)
                    DeltaChip(delta)
                }
            }
            val canNext = weekOffset < 0
            Box(Modifier.size(32.dp).clip(CircleShape).alpha(if (canNext) 1f else 0.25f)
                .clickable(enabled = canNext) { weekOffset += 1; picked = null }
                .semantics { contentDescription = "Sonraki hafta" }, contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.ChevronRight, null)
            }
        }
        WeekCompareChart(thisW, last, pages, goal, s.today, picked) { picked = if (picked == it) null else it }
        val p = picked
        if (p != null) {
            val d = thisW[p]; val b = last[p]
            Text("${StatFormat.dayMonth(d.date)}: ${StatFormat.minutes(d.minutes)} · ${StatFormat.pages(d.words)} sayfa   ·   önceki ${StatTint.weekdays[p]}: ${StatFormat.minutes(b.minutes)}",
                fontSize = 12.sp, color = secondaryText, maxLines = 1, overflow = TextOverflow.Ellipsis)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Legend(StatTint.cool, if (weekOffset == 0) "bu hafta" else "seçili hafta")
                Legend(Brush.linearGradient(listOf(Color.Gray.copy(alpha = 0.4f), Color.Gray.copy(alpha = 0.4f))), "önceki: ${StatFormat.minutes(before)}")
                Spacer(Modifier.weight(1f))
                Text("$reachedDays/7 gün hedefte", fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                    color = if (reachedDays > 0) StatTint.green else secondaryText)
            }
        }
        Segmented(listOf(false to "Dakika", true to "Sayfa"), pages) { pages = it }
    }
}

/** Last week's wide grey bars behind this week's narrow coloured ones, the goal as a dashed line. */
@Composable
private fun WeekCompareChart(
    thisW: List<DayStat>, last: List<DayStat>, pages: Boolean, goal: Double, today: java.time.LocalDate,
    picked: Int?, onPick: (Int) -> Unit,
) {
    val value: (DayStat) -> Double = { if (pages) it.pages else it.minutes }
    val grown by animateFloatAsState(1f, tween(700), label = "grow")
    var start by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { start = true }
    val g = if (start) grown else 0f
    val top = max(1.0, maxOf(thisW.maxOf(value), last.maxOf(value), if (pages) 0.0 else goal)) * 1.1
    val measurer = rememberTextMeasurer()
    val faint = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.11f)
    val grid = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.08f)
    val label = secondaryText
    val axis = 28.dp
    Canvas(
        Modifier.fillMaxWidth().height(170.dp).pointerInput(thisW, pages) {
            detectTapGestures { p ->
                val left = axis.toPx()
                val slot = (size.width - left) / 7f
                val i = ((p.x - left) / slot).toInt()
                if (i in 0..6 && p.x >= left) onPick(i)
            }
        },
    ) {
        val left = axis.toPx()
        val bottom = size.height - 16.dp.toPx()
        val h = bottom
        val slot = (size.width - left) / 7f
        val ls = TextStyle(fontSize = 9.sp, color = label)
        // three grid lines with their values
        for (k in 0..2) {
            val v = top / 1.1 * k / 2
            val y = (bottom - v / top * h).toFloat()
            drawLine(grid, Offset(left, y), Offset(size.width, y), 1f)
            val txt = if (pages) StatFormat.decimal(v) else Math.round(v).toString()
            drawText(measurer, txt, Offset(0f, y - 6.sp.toPx()), ls)
        }
        val r = CornerRadius(6.dp.toPx())
        for (i in 0 until 7) {
            val x0 = left + i * slot
            val lb = (value(last[i]) / top * h * g).toFloat()
            val lw = slot * 0.82f
            if (lb > 0) drawRoundRect(faint, Offset(x0 + (slot - lw) / 2, bottom - lb), Size(lw, lb), r)
            val d = thisW[i]
            val tb = (value(d) / top * h * g).toFloat()
            val tw = slot * 0.46f
            if (tb > 0) drawRoundRect(StatTint.bar(d.date == today, d.minutes >= goal), Offset(x0 + (slot - tw) / 2, bottom - tb), Size(tw, tb), r,
                alpha = if (picked == null || picked == i) 1f else 0.4f)
            val m = measurer.measure(StatTint.weekdays[i], ls)
            drawText(m, topLeft = Offset(x0 + (slot - m.size.width) / 2, bottom + 3.dp.toPx()))
        }
        if (!pages) {
            val y = (bottom - goal / top * h).toFloat()
            drawLine(StatTint.green.copy(alpha = 0.75f), Offset(left, y), Offset(size.width, y), 1.dp.toPx(),
                pathEffect = PathEffect.dashPathEffect(floatArrayOf(4.dp.toPx(), 4.dp.toPx())))
            val m = measurer.measure("hedef", TextStyle(fontSize = 9.sp, fontWeight = FontWeight.SemiBold, color = StatTint.green))
            drawText(m, topLeft = Offset(size.width - m.size.width, y - m.size.height - 2.dp.toPx()))
        }
    }
}

/** The run of days, the longest run, the best day. */
@Composable
private fun RecordTiles(s: StatsModel) {
    val r = s.records
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        RecordTile(Icons.Filled.LocalFireDepartment, "${r.streak}", "gün seri", listOf(StatTint.orange, Palette.play), Modifier.weight(1f))
        RecordTile(Icons.Filled.EmojiEvents, "${r.best}", "en uzun seri", listOf(StatTint.violet, StatTint.rose), Modifier.weight(1f))
        RecordTile(Icons.Filled.Bolt, r.top?.let { StatFormat.minutes(it.minutes) } ?: "—",
            r.top?.let { "en iyi gün · " + StatFormat.dayMonth(it.date) } ?: "en iyi gün", listOf(StatTint.sky, StatTint.mint), Modifier.weight(1f))
    }
}

@Composable
private fun RecordTile(icon: ImageVector, value: String, label: String, colors: List<Color>, modifier: Modifier) {
    Column(
        modifier.heightIn(min = 92.dp).clip(RoundedCornerShape(18.dp)).background(Brush.linearGradient(colors)).padding(12.dp),
        verticalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        Icon(icon, null, tint = Color.White, modifier = Modifier.size(18.dp))
        Text(value, color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold, maxLines = 1)
        Text(label, color = Color.White.copy(alpha = 0.9f), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, lineHeight = 13.sp)
    }
}

/** Finished books, week by week, by name. */
@Composable
private fun FinishedBooks(s: StatsModel, onOpenBook: (String) -> Unit) {
    val thisW = s.finished(StatSpan.week)
    val last = s.finished(StatSpan.week, -1)
    val month = s.finished(StatSpan.month)
    val earlier = month.filter { m -> thisW.none { it.id == m.id } && last.none { it.id == m.id } }
    StatPanel {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.Verified, null, tint = StatTint.violet, modifier = Modifier.size(18.dp))
            Spacer(Modifier.width(6.dp))
            Text("Biten kitaplar", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = StatTint.violet)
            Spacer(Modifier.weight(1f))
            Text("bu ay ${month.size}", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = secondaryText)
        }
        if (thisW.isEmpty() && last.isEmpty() && earlier.isEmpty()) Text("Bu ay henüz biten kitap yok.", fontSize = 15.sp, color = secondaryText)
        FinishedRow("Bu hafta", thisW, onOpenBook)
        FinishedRow("Geçen hafta", last, onOpenBook)
        FinishedRow("Bu ay, daha önce", earlier, onOpenBook)
        s.nearest?.let { (doc, left) ->
            Row(
                Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(StatTint.orange.copy(alpha = 0.10f))
                    .clickable { onOpenBook(doc.id) }.padding(10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Filled.SportsScore, null, tint = StatTint.orange, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(10.dp))
                Text(buildAnnotatedString {
                    withStyle(SpanStyle(color = secondaryText)) { append("Bitişe en yakın: ") }
                    withStyle(SpanStyle(fontWeight = FontWeight.SemiBold)) { append(doc.title) }
                    withStyle(SpanStyle(color = secondaryText)) { append(" · %${(doc.progress * 100).toInt()} · ${Format.duration(left)} kaldı") }
                }, fontSize = 13.sp, maxLines = 2, overflow = TextOverflow.Ellipsis)
            }
        }
    }
}

@Composable
private fun FinishedRow(title: String, books: List<FinishedBook>, onOpenBook: (String) -> Unit) {
    if (books.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text("$title · ${books.size} kitap bitirdin", fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Row(Modifier.horizontalScroll(rememberScrollState()), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            books.forEach { b ->
                Column(Modifier.width(62.dp).clickable { onOpenBook(b.doc.id) }, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                    StatCover(b.doc, 62.dp)
                    Text(b.doc.title, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, maxLines = 2, lineHeight = 13.sp, overflow = TextOverflow.Ellipsis)
                    Text(StatFormat.dayMonth(b.at), fontSize = 9.sp, color = secondaryText)
                }
            }
        }
    }
}

/** Seventeen weeks, a square a day. */
@Composable
private fun Heat(s: StatsModel) {
    val goal = s.app.settings.dailyGoal.toDouble()
    val weeks = (16 downTo 0).map { s.week(-it) }
    val active = weeks.flatten().count { it.minutes >= StatsModel.STREAK_FLOOR }
    val empty = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)
    val todayLine = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.6f)
    StatPanel(Modifier.semantics { contentDescription = "Son 17 haftada $active gün dinledin" }) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text("Son 17 hafta", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Text("$active gün dinledin", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = secondaryText)
        }
        Row(horizontalArrangement = Arrangement.spacedBy(3.dp)) {
            weeks.forEach { w ->
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    w.forEach { d ->
                        val future = d.date.isAfter(s.today)
                        val c = when {
                            future -> Color.Transparent
                            d.minutes < 0.5 -> empty
                            else -> {
                                val r = d.minutes / goal
                                StatTint.mint.copy(alpha = if (r >= 1) 1f else if (r >= 0.6) 0.7f else if (r >= 0.3) 0.4f else 0.2f)
                            }
                        }
                        Box(Modifier.fillMaxWidth().aspectRatio(1f).clip(RoundedCornerShape(3.dp)).background(c)
                            .todayBorder(d.date == s.today, todayLine))
                    }
                }
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("az", fontSize = 9.sp, color = secondaryText)
            listOf(0.2f, 0.4f, 0.7f, 1f).forEach { o ->
                Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.dp)).background(StatTint.mint.copy(alpha = o)))
            }
            Text("hedef", fontSize = 9.sp, color = secondaryText)
        }
    }
}
